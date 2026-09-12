# Self-contained Makefile for pax_adb — a native Linux build of AOSP adb 1.0.32
# (system/core, android-5.1.1_r38) carrying the PAX A_HDSK handshake patch and
# the PAX USB vendor IDs.  No Android build system required.
#
#   make            build ./pax_adb
#   make install    install to $(DESTDIR)$(PREFIX)/bin  (PREFIX defaults to /usr)
#   make clean
#
# Dependencies: a C compiler, OpenSSL (libcrypto) and zlib development headers.
#   Arch:   pacman -S --needed base-devel openssl zlib
#   Debian: apt install build-essential libssl-dev zlib1g-dev

PREFIX  ?= /usr
DESTDIR ?=
CC      ?= cc

SRC := src
OUT := pax_adb

# HAVE_* macros normally injected by the AOSP build system (linux-x86 host)
HAVE_FLAGS := -DHAVE_FORKEXEC -DHAVE_SYMLINKS -DHAVE_TERMIO_H \
              -DHAVE_LINUX_LOCAL_SOCKET_NAMESPACE -DHAVE_EPOLL \
              -DHAVE_DIRENT_D_TYPE -DHAVE_OFF64_T

CFLAGS  ?= -O2 -g
CFLAGS  += -DADB_HOST=1 -D_XOPEN_SOURCE -D_GNU_SOURCE $(HAVE_FLAGS) \
           -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function \
           -Wno-deprecated-declarations -Wno-sign-compare \
           -I$(SRC) -Iinclude

LDLIBS  := -lcrypto -lz -lpthread -lrt -ldl

ADB_SRCS := \
	adb.c console.c transport.c transport_local.c transport_usb.c \
	commandline.c adb_client.c adb_auth_host.c sockets.c services.c \
	file_sync_client.c get_my_path_linux.c usb_linux.c usb_vendors.c fdevent.c

CUTILS_SRCS := \
	socket_loopback_client.c socket_loopback_server.c socket_network_client.c \
	socket_inaddr_any_server.c socket_local_client.c socket_local_server.c load_file.c

SRCS := $(ADB_SRCS) $(CUTILS_SRCS)
OBJS := $(addprefix obj/,$(SRCS:.c=.o))

all: $(OUT)

obj:
	mkdir -p obj

obj/%.o: $(SRC)/%.c | obj
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT): $(OBJS)
	$(CC) $(OBJS) $(LDLIBS) -o $@
	@echo "==> built $(OUT)"

install: $(OUT)
	install -Dm755 $(OUT) $(DESTDIR)$(PREFIX)/bin/pax_adb
	install -Dm644 packaging/udev/51-android-pax.rules \
		$(DESTDIR)$(PREFIX)/lib/udev/rules.d/51-android-pax.rules 2>/dev/null || true
	@echo "==> installed pax_adb to $(DESTDIR)$(PREFIX)/bin"

clean:
	rm -rf obj $(OUT)

.PHONY: all install clean
