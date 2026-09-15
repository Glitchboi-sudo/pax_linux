> **Language:** **English** · [Español](README.es.md) · [Português](README.pt.md)

# pax_adb for Linux

A native Linux build of **`pax_adb`**, the tool used to talk over ADB to **PAX
PayDroid** POS terminals (A910/A920/A930, D series, etc.). It is AOSP's `adb`
(**1.0.32**, `system/core/adb`) recompiled natively for Linux, with the only
proprietary addition that PAX terminals require: the **`A_HDSK` handshake**. It
is the equivalent of the Windows `pax_adb.exe`.

## What makes "the PAX part" special

`pax_adb.exe` is **not** a renamed stock `adb`: it is a fork of AOSP `adb` with
three changes over the original, all reimplemented here:

1. **`A_HDSK` handshake** (command `0x4b534448`, `"HDSK"`). After `CNXN`, the PAX
   terminal's `adbd` sends `A_HDSK` with `arg0=1` (*PAX_HANDSHAKE_REQ*) and **does
   not bring the connection online until the host replies** with `A_HDSK`,
   `arg0=2` (*PAX_HANDSHAKE_RES*) and the fixed payload **`paxadb`** (6 bytes).
   There is no cryptography, no keys, no challenge-response: it is a constant
   *magic string*. Stock `adb` does not know `A_HDSK`, which is why it never
   connects to PAX terminals.

2. **PAX USB Vendor IDs** added to `adb`'s table (they are not in AOSP): `0x2FB8`
   (PAX Technology, current) and `0x0327` (PAX legacy). `adb` only recognizes the
   ADB interface (class `0xFF` / subclass `0x42` / protocol `0x01`) if the VID is
   in its list. VID `0x1F3A` (Allwinner, bootloader mode) already shipped in AOSP.

3. **Extra commands** that do not exist in stock `adb` (reimplemented here):
   - **`syslog`** → opens the `paxlog:system` service and dumps the terminal's system log.
   - **`systool <subcommand>`** → runs `shell:systool …` on the terminal. For the
     file-based subcommands (`update`/`write`/`install`/`apn`/`puk`) it `push`es the
     local file to `/data/local/tmp` first and deletes it afterwards. It also captures
     the terminal's **return code** from the `[SYSTOOL:-N]` marker in the output and
     returns it as the process exit code (behavior of the 2021 `pax_adb.exe`).
   - **`puk <install|uninstall|list>`** → manages PUK packages via `shell:puktools`
     (`install` uploads the local file, just like `systool`).
   - **`sysver`** → shows the firmware versions (`pax.ctrl.androidver`, `apbootver`,
     `spver`; or `systool sysver` depending on the firmware).
   - **`unlink <remote>`** → deletes a file on the terminal via the **`ULNK`** sync
     request. *Version-aware*: if `pax.ctrl.systool.sysver ≥ 100` and the path is under
     `/data/resource/app/`, it is redirected to `systool remove persist-app`.
   - **`getappinfo [<local>]`** → `pull`s `/data/resource/public/appinfo.bin`.
   - In addition, a `push` to paths under `/data/resource/app/` on firmware `sysver ≥ 100`
     is redirected to `systool install persist-app` (same as the `.exe`).

The exact diff against AOSP `android-5.1.1_r38` is in
[`patches/pax_adb.patch`](patches/pax_adb.patch).

> The flashing part (`paydroidboot.exe`) is just a fork of AOSP `fastboot` with
> PAX branding. Linux's stock `fastboot` (`android-tools`) covers
> `flash`/`erase`/`reboot bootloader`. It is not part of this repository.

## Layout

```
src/                 adb host sources (AOSP) with the PAX patch already applied
include/             AOSP headers needed to build without the full tree
Makefile             Self-contained build (does not require the Android build system)
patches/             pax_adb.patch — the PAX diff over AOSP
packaging/
  arch/              PKGBUILD + scriptlet for the Arch package (.pkg.tar.zst)
  nfpm.yaml          single source for the .deb and .rpm packages
  scripts/           post-install/remove hooks shared by .deb and .rpm
  build-packages.sh  builds .deb + .rpm + portable tarball into ./dist
  udev/              udev rules (USB access without root)
  portable/          install.sh (builds and installs on any distro)
test/                Fake PAX terminal + runner to validate the handshake without hardware
```

## Build

Dependencies: a C compiler, plus the **OpenSSL** and **zlib** headers.

```sh
# Arch
sudo pacman -S --needed base-devel openssl zlib
# Debian/Ubuntu
sudo apt install build-essential libssl-dev zlib1g-dev

make                 # produces ./pax_adb
sudo make install    # installs into /usr/bin and the udev rules
```

## Install

### Prebuilt packages (from a [release](https://github.com/Glitchboi-sudo/pax_linux/releases))

Every release ships native packages for the popular distro families. Download the
one for yours and install it:

```sh
# Debian / Ubuntu / Mint / Pop!_OS
sudo apt install ./pax-adb_*_amd64.deb

# Fedora / RHEL / Rocky / Alma / openSUSE
sudo dnf install ./pax-adb-*.x86_64.rpm      # or: sudo zypper install ./pax-adb-*.x86_64.rpm

# Arch / Manjaro / EndeavourOS
sudo pacman -U pax-adb-*-x86_64.pkg.tar.zst

# Any other distro (portable tarball, no build)
tar xzf pax-adb-*-linux-x86_64.tar.gz && cd pax-adb-*-linux-x86_64
sudo ./install.sh
```

The `.deb`/`.rpm` are built on Ubuntu 22.04 (glibc 2.35 + OpenSSL 3), so they run on
Debian 12+, Ubuntu 22.04+, Fedora, RHEL/Rocky/Alma 9, openSUSE and derivatives. On
older releases (OpenSSL 1.1) build from source instead.

### Build the Arch package yourself
```sh
cd packaging/arch
makepkg -f
sudo pacman -U pax-adb-*.pkg.tar.zst
```

### Build from source (any distro)
```sh
sudo ./packaging/portable/install.sh          # builds and installs into /usr/local/bin + udev
# or a user install (no root, no udev):
./packaging/portable/install.sh --user
```

> Maintainers: `packaging/build-packages.sh` builds the `.deb`, `.rpm` and portable
> tarball in one shot; the `release` GitHub Actions workflow does it automatically for
> every `v*` tag and uploads them to the release.

After installing, unplug and replug the terminal so the udev rules take effect. If
USB access is denied, add your user to the `plugdev` group (or rely on
systemd-logind's `uaccess` when logged in locally).

## Usage

The commands are identical to those of the original `adb`:

| Windows (`.bat`)                            | Linux                                   |
|---------------------------------------------|-----------------------------------------|
| `pax_adb.exe reboot bootloader`             | `pax_adb reboot bootloader`             |
| `pax_adb.exe kill-server`                   | `pax_adb kill-server`                   |
| `pax_adb.exe shell pm uninstall --user 0 X` | `pax_adb shell pm uninstall --user 0 X` |
| `pax_adb.exe devices`                       | `pax_adb devices`                       |

PAX-specific commands:

| Command | Description |
|---|---|
| `pax_adb syslog` | Dumps the terminal's system log (`paxlog:system`) |
| `pax_adb systool <subcommand>` | Runs a remote `systool` command (e.g. `pax_adb systool puk write <file>`) |
| `pax_adb puk <install\|uninstall\|list>` | Manages PUK packages (`puktools`) |
| `pax_adb sysver` | Shows the terminal's firmware versions |
| `pax_adb unlink <remote>` | Deletes a file on the terminal |
| `pax_adb getappinfo [<local>]` | Downloads the terminal's `appinfo.bin` |

## Testing with a real PAX terminal

1. On the terminal, enable **USB debugging** (Settings → Developer options) and
   connect it over USB.
2. Check that the system sees it:
   ```sh
   lsusb | grep -iE "2fb8|0327|1f3a"
   ```
3. List devices:
   ```sh
   pax_adb kill-server && pax_adb devices     # it should appear with the "device" state
   ```
   To watch the handshake live:
   ```sh
   ADB_TRACE=all pax_adb nodaemon server      # look for "A_HDSK PAX_HANDSHAKE_REQ" and "paxadb"
   ```
4. Try a real command:
   ```sh
   pax_adb shell getprop pax.ctrl.androidver
   ```
If `devices` shows `unauthorized`, accept the RSA dialog on the POS screen.

## Validation without hardware

The handshake is validated end to end with a "fake PAX terminal" that speaks the
ADB protocol over TCP:

```sh
make
bash test/run_handshake_test.sh
```

It sends `A_HDSK(arg0=1)` and confirms that `pax_adb` replies
`A_HDSK(arg0=2,"paxadb")`, after which the connection goes *online*. `handle_packet`
is identical for USB and TCP, so this exercises exactly the patched code. A valid
result is the `RESULT: PASS` line (the shell's exit code may be ≠0 when the adb
daemon is shut down; that is harmless).

## License

Apache 2.0 (AOSP code base). See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).
