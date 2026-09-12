#!/usr/bin/env python3
"""
Fuller fake PAX terminal: a minimal adbd that goes online (via the A_HDSK
handshake) and then services adb streams, so the PAX client commands can be
exercised end-to-end over TCP without hardware.

It records every A_OPEN destination it receives to a file (--log) so the test
runner can assert which services the client opened, and it implements just
enough of the shell / sync sub-protocols to let the commands complete:

  * shell:getprop pax.ctrl.systool.sysver  -> replies with $SYSVER (env, def "0")
  * shell:* / paxlog:system                -> replies with one canned line, closes
  * sync:                                   -> handles STAT (mode 0) and ULNK (OKAY)

Usage: fake_pax_full.py <port> [--sysver N] [--log FILE]
"""
import socket, struct, sys, os, time

def mkid(s): return struct.unpack("<I", s)[0]
A_SYNC=mkid(b"SYNC"); A_CNXN=mkid(b"CNXN"); A_OPEN=mkid(b"OPEN")
A_OKAY=mkid(b"OKAY"); A_CLSE=mkid(b"CLSE"); A_WRTE=mkid(b"WRTE")
A_HDSK=mkid(b"HDSK")
ID_STAT=mkid(b"STAT"); ID_ULNK=mkid(b"ULNK"); ID_QUIT=mkid(b"QUIT")
ID_RECV=mkid(b"RECV"); ID_DATA=mkid(b"DATA"); ID_DONE=mkid(b"DONE")

PORT=int(sys.argv[1]) if len(sys.argv)>1 else 15555
SYSVER="0"; LOGF=None
a=sys.argv[2:]
while a:
    if a[0]=="--sysver": SYSVER=a[1]; a=a[2:]
    elif a[0]=="--log": LOGF=a[1]; a=a[2:]
    else: a=a[1:]

opened=[]
def logopen(dest):
    opened.append(dest)
    if LOGF:
        with open(LOGF,"a") as f: f.write(dest+"\n")
    print("[dev] OPEN %r" % dest, flush=True)

def pack(cmd,a0,a1,data=b""):
    return struct.pack("<6I",cmd,a0,a1,len(data),sum(data)&0xffffffff,cmd^0xffffffff)+data

def recvn(s,n):
    b=b""
    while len(b)<n:
        c=s.recv(n-len(b))
        if not c: return None
        b+=c
    return b

def readpkt(s):
    h=recvn(s,24)
    if h is None: return None
    cmd,a0,a1,dl,dc,mg=struct.unpack("<6I",h)
    d=recvn(s,dl) if dl else b""
    if d is None: return None
    return [cmd,a0,a1,d]

class Stream:
    """One adb stream (our local id <-> host remote id)."""
    def __init__(s, conn, local_id, remote_id, dest):
        s.conn=conn; s.lid=local_id; s.rid=remote_id; s.dest=dest
        s.syncbuf=b""; s.is_sync=(dest=="sync:"); s.done=False
    def wrte(s, payload):
        s.conn.sendall(pack(A_WRTE, s.lid, s.rid, payload))
    def close(s):
        s.conn.sendall(pack(A_CLSE, s.lid, s.rid)); s.done=True

    def on_open(s):
        if s.is_sync:
            return  # wait for WRTE payloads
        if s.dest=="shell:getprop pax.ctrl.systool.sysver":
            s.wrte((SYSVER+"\n").encode())
        elif s.dest=="paxlog:system":
            s.wrte(b"[paxlog] fake system log line 1\n[paxlog] line 2\n")
        elif s.dest.startswith("shell:"):
            s.wrte(("[fake] ran: "+s.dest[len("shell:"):]+"\n").encode())
        else:
            s.wrte(b"[fake] "+s.dest.encode()+b"\n")
        s.close()

    def on_wrte(s, payload):
        # host -> device data. For sync streams, accumulate and parse.
        if not s.is_sync:
            return
        s.syncbuf+=payload
        s._parse_sync()

    def _parse_sync(s):
        while len(s.syncbuf)>=8:
            sid,nlen=struct.unpack("<II", s.syncbuf[:8])
            if sid==ID_QUIT:
                s.syncbuf=s.syncbuf[8:]; s.close(); return
            if len(s.syncbuf)<8+nlen: return
            path=s.syncbuf[8:8+nlen]; s.syncbuf=s.syncbuf[8+nlen:]
            if sid==ID_STAT:
                # stat resp: id, mode, size, time (16 bytes). For appinfo pretend
                # it's a regular file; otherwise mode 0 (= not found, unlink ok).
                print("[dev] sync STAT %r" % path, flush=True)
                if path.endswith(b"appinfo.bin"):
                    s.wrte(struct.pack("<4I", ID_STAT, 0x81a4, 12, 0))  # regular file
                else:
                    s.wrte(struct.pack("<4I", ID_STAT, 0, 0, 0))
            elif sid==ID_RECV:
                print("[dev] sync RECV %r" % path, flush=True)
                content=b"FAKEAPPINFO\n"
                s.wrte(struct.pack("<II", ID_DATA, len(content))+content)
                s.wrte(struct.pack("<II", ID_DONE, 0))
            elif sid==ID_ULNK:
                print("[dev] sync ULNK %r -> OKAY" % path, flush=True)
                if LOGF:
                    with open(LOGF,"a") as f: f.write("ULNK:"+path.decode(errors="replace")+"\n")
                s.wrte(struct.pack("<II", A_OKAY, 0))  # status header: id, msglen
            else:
                print("[dev] sync unknown id %08x" % sid, flush=True)
                s.wrte(struct.pack("<II", mkid(b'FAIL'), 0)); s.close(); return

def serve(conn):
    conn.settimeout(6.0)
    # PAX handshake first (like a real terminal)
    time.sleep(0.15)
    conn.sendall(pack(A_HDSK,1,0))
    streams={}; next_lid=[1000]; online=False
    try:
        while True:
            pkt=readpkt(conn)
            if pkt is None: break
            cmd,a0,a1,d=pkt
            if cmd==A_HDSK and a0==2:
                # host acknowledged handshake -> announce ourselves
                conn.sendall(pack(A_CNXN,0x01000000,4096,b"device::pax\x00"))
            elif cmd==A_CNXN:
                online=True
            elif cmd==A_OPEN:
                dest=d.split(b"\x00")[0].decode(errors="replace")
                logopen(dest)
                lid=next_lid[0]; next_lid[0]+=1
                st=Stream(conn,lid,a0,dest); streams[lid]=st
                conn.sendall(pack(A_OKAY, lid, a0))  # accept
                st.on_open()
                if st.done: streams.pop(lid,None)
            elif cmd==A_WRTE:
                st=streams.get(a1)
                # ack the write first (flow control)
                if st: conn.sendall(pack(A_OKAY, st.lid, st.rid))
                if st: st.on_wrte(d)
                if st and st.done: streams.pop(a1,None)
            elif cmd==A_OKAY:
                pass
            elif cmd==A_CLSE:
                streams.pop(a1,None)
    except socket.timeout:
        pass
    finally:
        conn.close()

def main():
    srv=socket.socket(); srv.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    srv.bind(("127.0.0.1",PORT)); srv.listen(4); srv.settimeout(20.0)
    print("[dev] fake PAX (full) on 127.0.0.1:%d sysver=%s"%(PORT,SYSVER), flush=True)
    # serve multiple sequential connections (the adb server may reconnect)
    end=time.time()+18
    while time.time()<end:
        try: conn,_=srv.accept()
        except socket.timeout: break
        serve(conn)

if __name__=="__main__":
    main()
