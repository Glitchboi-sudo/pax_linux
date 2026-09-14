> **Idioma:** [English](README.md) · **Español** · [Português](README.pt.md)

# pax_adb para Linux

Versión nativa de Linux de **`pax_adb`**, la herramienta usada para hablar por
ADB con terminales POS **PAX PayDroid** (A910/A920/A930, serie D, etc.). Es el
`adb` de AOSP (**1.0.32**, `system/core/adb`) recompilado de forma nativa para
Linux con el único añadido propietario que los terminales PAX requieren: el
**handshake `A_HDSK`**. Equivale al `pax_adb.exe` de Windows.

## Qué tiene de especial "la parte de PAX"

`pax_adb.exe` **no** es un `adb` estándar renombrado: es un fork de AOSP `adb`
con tres cambios sobre el original, todos reimplementados aquí:

1. **Handshake `A_HDSK`** (comando `0x4b534448`, `"HDSK"`). Tras el `CNXN`, el
   `adbd` del terminal PAX envía `A_HDSK` con `arg0=1` (*PAX_HANDSHAKE_REQ*) y
   **no pone la conexión online hasta que el host responde** `A_HDSK` con
   `arg0=2` (*PAX_HANDSHAKE_RES*) y el payload fijo **`paxadb`** (6 bytes). No hay
   criptografía, ni claves, ni challenge-response: es un *magic string* constante.
   El `adb` estándar no conoce `A_HDSK`, por eso no conecta con terminales PAX.

2. **USB Vendor IDs de PAX** añadidos a la tabla de `adb` (no están en AOSP):
   `0x2FB8` (PAX Technology, actual) y `0x0327` (PAX legacy). `adb` solo reconoce
   la interfaz ADB (clase `0xFF` / subclase `0x42` / protocolo `0x01`) si el VID
   está en su lista. El VID `0x1F3A` (Allwinner, modo bootloader) ya venía en AOSP.

3. **Comandos extra** que no existen en el `adb` estándar (reimplementados aquí):
   - **`syslog`** → abre el servicio `paxlog:system` y vuelca el log de sistema del TPV.
   - **`systool <subcomando>`** → ejecuta `shell:systool …` en el terminal. Para los
     subcomandos con archivo (`update`/`write`/`install`/`apn`/`puk`) hace `push` del
     archivo local a `/data/local/tmp` antes y lo borra después. Además captura el
     **código de retorno** del terminal desde el marcador `[SYSTOOL:-N]` de la salida
     y lo devuelve como código de salida (comportamiento del `pax_adb.exe` de 2021).
   - **`puk <install|uninstall|list>`** → gestiona paquetes PUK vía `shell:puktools`
     (`install` sube el archivo local igual que `systool`).
   - **`sysver`** → muestra las versiones del firmware (`pax.ctrl.androidver`,
     `apbootver`, `spver`; o `systool sysver` según el firmware).
   - **`unlink <remoto>`** → borra un archivo en el terminal mediante la petición sync
     **`ULNK`**. *Version-aware*: si `pax.ctrl.systool.sysver ≥ 100` y la ruta está bajo
     `/data/resource/app/`, se redirige a `systool remove persist-app`.
   - **`getappinfo [<local>]`** → hace `pull` de `/data/resource/public/appinfo.bin`.
   - Además, un `push` a rutas bajo `/data/resource/app/` en firmware `sysver ≥ 100` se
     redirige a `systool install persist-app` (igual que el `.exe`).

El diff exacto sobre AOSP `android-5.1.1_r38` está en
[`patches/pax_adb.patch`](patches/pax_adb.patch).

> La parte de flasheo (`paydroidboot.exe`) es solo un fork de `fastboot` de AOSP
> con branding PAX. El `fastboot` estándar de Linux (`android-tools`) cubre
> `flash`/`erase`/`reboot bootloader`. No forma parte de este repositorio.

## Estructura

```
src/                 Fuentes del host adb (AOSP) con el parche PAX ya aplicado
include/             Cabeceras de AOSP necesarias para compilar sin el árbol completo
Makefile             Build autocontenido (no requiere el sistema de build de Android)
patches/             pax_adb.patch — el diff PAX sobre AOSP
packaging/
  arch/              PKGBUILD + scriptlet para paquete Arch (.pkg.tar.zst)
  udev/              Reglas udev (permisos USB sin root)
  portable/          install.sh (compila e instala en cualquier distro)
test/                Terminal PAX falso + runner para validar el handshake sin hardware
```

## Compilar

Dependencias: compilador C, y las cabeceras de **OpenSSL** y **zlib**.

```sh
# Arch
sudo pacman -S --needed base-devel openssl zlib
# Debian/Ubuntu
sudo apt install build-essential libssl-dev zlib1g-dev

make                 # produce ./pax_adb
sudo make install    # instala en /usr/bin y las reglas udev
```

## Instalar

### Paquete Arch
```sh
cd packaging/arch
makepkg -f
sudo pacman -U pax-adb-*.pkg.tar.zst
```

### Cualquier distro (script)
```sh
sudo ./packaging/portable/install.sh          # compila e instala en /usr/local/bin + udev
# o instalación de usuario (sin root, sin udev):
./packaging/portable/install.sh --user
```

Tras instalar, desconecta y reconecta el terminal para que se apliquen las reglas
udev. Si el acceso USB es denegado, añade tu usuario al grupo `plugdev` (o confía
en `uaccess` de systemd-logind al iniciar sesión localmente).

## Uso

Los comandos son idénticos a los del `adb` original:

| Windows (`.bat`)                            | Linux                                   |
|---------------------------------------------|-----------------------------------------|
| `pax_adb.exe reboot bootloader`             | `pax_adb reboot bootloader`             |
| `pax_adb.exe kill-server`                   | `pax_adb kill-server`                   |
| `pax_adb.exe shell pm uninstall --user 0 X` | `pax_adb shell pm uninstall --user 0 X` |
| `pax_adb.exe devices`                       | `pax_adb devices`                       |

Comandos específicos de PAX:

| Comando | Descripción |
|---|---|
| `pax_adb syslog` | Vuelca el log de sistema del TPV (`paxlog:system`) |
| `pax_adb systool <subcomando>` | Ejecuta un comando `systool` remoto (p. ej. `pax_adb systool puk write <archivo>`) |
| `pax_adb puk <install\|uninstall\|list>` | Gestiona paquetes PUK (`puktools`) |
| `pax_adb sysver` | Muestra las versiones del firmware del terminal |
| `pax_adb unlink <remoto>` | Borra un archivo en el terminal |
| `pax_adb getappinfo [<local>]` | Descarga el `appinfo.bin` del terminal |

## Probar con un terminal PAX real

1. En el terminal, activa **Depuración USB** (Ajustes → Opciones de
   desarrollador) y conéctalo por USB.
2. Comprueba que el sistema lo ve:
   ```sh
   lsusb | grep -iE "2fb8|0327|1f3a"
   ```
3. Lista los dispositivos:
   ```sh
   pax_adb kill-server && pax_adb devices     # debe aparecer con estado "device"
   ```
   Para ver el handshake en vivo:
   ```sh
   ADB_TRACE=all pax_adb nodaemon server      # busca "A_HDSK PAX_HANDSHAKE_REQ" y "paxadb"
   ```
4. Prueba un comando real:
   ```sh
   pax_adb shell getprop pax.ctrl.androidver
   ```
Si `devices` muestra `unauthorized`, acepta el diálogo RSA en la pantalla del POS.

## Validación sin hardware

El handshake se valida de punta a punta con un "terminal PAX falso" que habla el
protocolo ADB por TCP:

```sh
make
bash test/run_handshake_test.sh
```

Envía `A_HDSK(arg0=1)` y confirma que `pax_adb` responde `A_HDSK(arg0=2,"paxadb")`,
tras lo cual la conexión pasa a *online*. `handle_packet` es idéntico para USB y
TCP, así que esto ejercita exactamente el código del parche. El resultado válido
es la línea `RESULT: PASS` (el código de salida del shell puede ser ≠0 al cerrar
el daemon adb; es inofensivo).

## Licencia

Apache 2.0 (código base de AOSP). Ver [`LICENSE`](LICENSE) y [`NOTICE`](NOTICE).
