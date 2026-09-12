#!/usr/bin/env python3
"""
Fake PAX terminal (adbd side) used to validate the A_HDSK handshake patch in
pax_adb WITHOUT real hardware.

It speaks the raw adb transport protocol over TCP (24-byte amessage header +
payload, magic = command ^ 0xffffffff, data_check = sum of payload bytes),
which is exactly what pax_adb's local (TCP) transport reads via remote_read().

Flow it drives:
  1. accept the connection from the adb server
  2. send  A_HDSK arg0=1            (PAX_HANDSHAKE_REQ, as a real terminal does)
  3. expect A_HDSK arg0=2 "paxadb"  (PAX_HANDSHAKE_RES, our patch must produce)
  4. also answers A_CNXN so the device would come "online"

Exit code 0 == handshake response correct.
"""
import socket, struct, sys, threading, time

A_SYNC = 0x434e5953
A_CNXN = 0x4e584e43
A_AUTH = 0x48545541
A_HDSK = 0x4b534448

NAMES = {A_SYNC:"SYNC", A_CNXN:"CNXN", A_AUTH:"AUTH", A_HDSK:"HDSK",
         0x4e45504f:"OPEN", 0x59414b4f:"OKAY", 0x45534c43:"CLSE", 0x45545257:"WRTE"}

def cmdname(c): return NAMES.get(c, "0x%08x" % c)

def pack(cmd, arg0, arg1, data=b""):
    check = sum(data) & 0xffffffff
    magic = cmd ^ 0xffffffff
    return struct.pack("<6I", cmd, arg0, arg1, len(data), check, magic) + data

def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf

def read_packet(sock):
    hdr = recv_exact(sock, 24)
    if hdr is None:
        return None
    cmd, arg0, arg1, dlen, dcheck, magic = struct.unpack("<6I", hdr)
    data = b""
    if dlen:
        data = recv_exact(sock, dlen)
        if data is None:
            return None
    return (cmd, arg0, arg1, dlen, dcheck, magic, data)

def handle(conn):
    ok = {"handshake": False}
    conn.settimeout(4.0)

    # Behave like a PAX terminal: as soon as we're connected, ask the host to
    # perform the proprietary handshake.
    time.sleep(0.2)
    print("[dev] -> A_HDSK arg0=1 (PAX_HANDSHAKE_REQ)")
    conn.sendall(pack(A_HDSK, 1, 0))

    try:
        while True:
            pkt = read_packet(conn)
            if pkt is None:
                print("[dev] connection closed by adb")
                break
            cmd, arg0, arg1, dlen, dcheck, magic, data = pkt
            print("[dev] <- %s arg0=%d arg1=%d len=%d data=%r"
                  % (cmdname(cmd), arg0, arg1, dlen, data[:32]))

            # verify wire integrity of whatever the host sent
            if magic != (cmd ^ 0xffffffff):
                print("[dev] !! bad magic from host")
            if (sum(data) & 0xffffffff) != dcheck:
                print("[dev] !! bad checksum from host")

            if cmd == A_HDSK and arg0 == 2:
                if data == b"paxadb":
                    print("[dev] ** A_HDSK PAX_HANDSHAKE_RES = 'paxadb'  --> HANDSHAKE OK")
                    ok["handshake"] = True
                    # A real terminal now announces itself.
                    conn.sendall(pack(A_CNXN, 0x01000000, 4096, b"device::pax\x00"))
                else:
                    print("[dev] !! wrong handshake payload: %r" % data)
            elif cmd == A_CNXN:
                # host greeted us; a real device would already have sent CNXN,
                # nothing else required for this test.
                pass
            elif cmd == A_AUTH:
                # not expected in the PAX flow, ignore
                pass
    except socket.timeout:
        print("[dev] read timeout")
    finally:
        conn.close()

    print("RESULT:", "PASS" if ok["handshake"] else "FAIL")
    sys.exit(0 if ok["handshake"] else 1)

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 15555
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(1)
    print("[dev] fake PAX terminal listening on 127.0.0.1:%d" % port)
    srv.settimeout(15.0)
    try:
        conn, addr = srv.accept()
    except socket.timeout:
        print("[dev] no connection within timeout"); sys.exit(2)
    print("[dev] adb connected from", addr)
    handle(conn)

if __name__ == "__main__":
    main()
