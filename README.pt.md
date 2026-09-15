> **Idioma:** [English](README.md) · [Español](README.es.md) · **Português**

# pax_adb para Linux

Versão nativa de Linux do **`pax_adb`**, a ferramenta usada para se comunicar por
ADB com terminais POS **PAX PayDroid** (A910/A920/A930, série D, etc.). É o `adb`
do AOSP (**1.0.32**, `system/core/adb`) recompilado de forma nativa para Linux,
com o único acréscimo proprietário que os terminais PAX exigem: o **handshake
`A_HDSK`**. Equivale ao `pax_adb.exe` do Windows.

## O que a "parte da PAX" tem de especial

`pax_adb.exe` **não** é um `adb` padrão renomeado: é um fork do `adb` do AOSP com
três mudanças em relação ao original, todas reimplementadas aqui:

1. **Handshake `A_HDSK`** (comando `0x4b534448`, `"HDSK"`). Após o `CNXN`, o `adbd`
   do terminal PAX envia `A_HDSK` com `arg0=1` (*PAX_HANDSHAKE_REQ*) e **não coloca
   a conexão online até que o host responda** com `A_HDSK`, `arg0=2`
   (*PAX_HANDSHAKE_RES*) e o payload fixo **`paxadb`** (6 bytes). Não há
   criptografia, nem chaves, nem challenge-response: é uma *magic string*
   constante. O `adb` padrão não conhece `A_HDSK`, por isso não conecta com
   terminais PAX.

2. **USB Vendor IDs da PAX** adicionados à tabela do `adb` (não estão no AOSP):
   `0x2FB8` (PAX Technology, atual) e `0x0327` (PAX legado). O `adb` só reconhece a
   interface ADB (classe `0xFF` / subclasse `0x42` / protocolo `0x01`) se o VID
   estiver na sua lista. O VID `0x1F3A` (Allwinner, modo bootloader) já vinha no AOSP.

3. **Comandos extras** que não existem no `adb` padrão (reimplementados aqui):
   - **`syslog`** → abre o serviço `paxlog:system` e despeja o log de sistema do terminal.
   - **`systool <subcomando>`** → executa `shell:systool …` no terminal. Para os
     subcomandos com arquivo (`update`/`write`/`install`/`apn`/`puk`) faz `push` do
     arquivo local para `/data/local/tmp` antes e o remove depois. Além disso captura o
     **código de retorno** do terminal a partir do marcador `[SYSTOOL:-N]` na saída e o
     retorna como código de saída do processo (comportamento do `pax_adb.exe` de 2021).
   - **`puk <install|uninstall|list>`** → gerencia pacotes PUK via `shell:puktools`
     (`install` envia o arquivo local, igual ao `systool`).
   - **`sysver`** → mostra as versões do firmware (`pax.ctrl.androidver`, `apbootver`,
     `spver`; ou `systool sysver` dependendo do firmware).
   - **`unlink <remoto>`** → apaga um arquivo no terminal por meio da requisição sync
     **`ULNK`**. *Version-aware*: se `pax.ctrl.systool.sysver ≥ 100` e o caminho estiver
     sob `/data/resource/app/`, é redirecionado para `systool remove persist-app`.
   - **`getappinfo [<local>]`** → faz `pull` de `/data/resource/public/appinfo.bin`.
   - Além disso, um `push` para caminhos sob `/data/resource/app/` em firmware
     `sysver ≥ 100` é redirecionado para `systool install persist-app` (igual ao `.exe`).

O diff exato em relação ao AOSP `android-5.1.1_r38` está em
[`patches/pax_adb.patch`](patches/pax_adb.patch).

> A parte de flashing (`paydroidboot.exe`) é apenas um fork do `fastboot` do AOSP
> com a marca PAX. O `fastboot` padrão do Linux (`android-tools`) cobre
> `flash`/`erase`/`reboot bootloader`. Não faz parte deste repositório.

## Estrutura

```
src/                 Fontes do host adb (AOSP) com o patch PAX já aplicado
include/             Cabeçalhos do AOSP necessários para compilar sem a árvore completa
Makefile             Build autocontido (não requer o sistema de build do Android)
patches/             pax_adb.patch — o diff PAX sobre o AOSP
packaging/
  arch/              PKGBUILD + scriptlet para o pacote Arch (.pkg.tar.zst)
  nfpm.yaml          fonte única para os pacotes .deb e .rpm
  scripts/           hooks post-install/remove compartilhados por .deb e .rpm
  build-packages.sh  gera .deb + .rpm + tarball portátil em ./dist
  udev/              Regras udev (acesso USB sem root)
  portable/          install.sh (compila e instala em qualquer distro)
test/                Terminal PAX falso + runner para validar o handshake sem hardware
```

## Compilar

Dependências: um compilador C, além dos cabeçalhos do **OpenSSL** e do **zlib**.

```sh
# Arch
sudo pacman -S --needed base-devel openssl zlib
# Debian/Ubuntu
sudo apt install build-essential libssl-dev zlib1g-dev

make                 # produz ./pax_adb
sudo make install    # instala em /usr/bin e as regras udev
```

## Instalar

### Pacotes pré-compilados (a partir de um [release](https://github.com/Glitchboi-sudo/pax_linux/releases))

Cada release traz pacotes nativos para as famílias de distros populares. Baixe o da
sua e instale:

```sh
# Debian / Ubuntu / Mint / Pop!_OS
sudo apt install ./pax-adb_*_amd64.deb

# Fedora / RHEL / Rocky / Alma / openSUSE
sudo dnf install ./pax-adb-*.x86_64.rpm      # ou: sudo zypper install ./pax-adb-*.x86_64.rpm

# Arch / Manjaro / EndeavourOS
sudo pacman -U pax-adb-*-x86_64.pkg.tar.zst

# Qualquer outra distro (tarball portátil, sem compilar)
tar xzf pax-adb-*-linux-x86_64.tar.gz && cd pax-adb-*-linux-x86_64
sudo ./install.sh
```

Os `.deb`/`.rpm` são compilados no Ubuntu 22.04 (glibc 2.35 + OpenSSL 3), então
rodam em Debian 12+, Ubuntu 22.04+, Fedora, RHEL/Rocky/Alma 9, openSUSE e derivados.
Em versões mais antigas (OpenSSL 1.1) compile a partir das fontes.

### Compilar o pacote Arch você mesmo
```sh
cd packaging/arch
makepkg -f
sudo pacman -U pax-adb-*.pkg.tar.zst
```

### Compilar a partir das fontes (qualquer distro)
```sh
sudo ./packaging/portable/install.sh          # compila e instala em /usr/local/bin + udev
# ou instalação de usuário (sem root, sem udev):
./packaging/portable/install.sh --user
```

> Mantenedores: `packaging/build-packages.sh` gera o `.deb`, `.rpm` e o tarball
> portátil de uma só vez; o workflow de GitHub Actions `release` faz isso
> automaticamente em cada tag `v*` e os envia ao release.

Após instalar, desconecte e reconecte o terminal para que as regras udev sejam
aplicadas. Se o acesso USB for negado, adicione seu usuário ao grupo `plugdev` (ou
confie no `uaccess` do systemd-logind ao fazer login localmente).

## Uso

Os comandos são idênticos aos do `adb` original:

| Windows (`.bat`)                            | Linux                                   |
|---------------------------------------------|-----------------------------------------|
| `pax_adb.exe reboot bootloader`             | `pax_adb reboot bootloader`             |
| `pax_adb.exe kill-server`                   | `pax_adb kill-server`                   |
| `pax_adb.exe shell pm uninstall --user 0 X` | `pax_adb shell pm uninstall --user 0 X` |
| `pax_adb.exe devices`                       | `pax_adb devices`                       |

Comandos específicos da PAX:

| Comando | Descrição |
|---|---|
| `pax_adb syslog` | Despeja o log de sistema do terminal (`paxlog:system`) |
| `pax_adb systool <subcomando>` | Executa um comando `systool` remoto (ex.: `pax_adb systool puk write <arquivo>`) |
| `pax_adb puk <install\|uninstall\|list>` | Gerencia pacotes PUK (`puktools`) |
| `pax_adb sysver` | Mostra as versões do firmware do terminal |
| `pax_adb unlink <remoto>` | Apaga um arquivo no terminal |
| `pax_adb getappinfo [<local>]` | Baixa o `appinfo.bin` do terminal |

## Testar com um terminal PAX real

1. No terminal, ative a **Depuração USB** (Configurações → Opções do
   desenvolvedor) e conecte-o via USB.
2. Verifique se o sistema o reconhece:
   ```sh
   lsusb | grep -iE "2fb8|0327|1f3a"
   ```
3. Liste os dispositivos:
   ```sh
   pax_adb kill-server && pax_adb devices     # deve aparecer com o estado "device"
   ```
   Para ver o handshake ao vivo:
   ```sh
   ADB_TRACE=all pax_adb nodaemon server      # procure por "A_HDSK PAX_HANDSHAKE_REQ" e "paxadb"
   ```
4. Teste um comando real:
   ```sh
   pax_adb shell getprop pax.ctrl.androidver
   ```
Se `devices` mostrar `unauthorized`, aceite a caixa de diálogo RSA na tela do POS.

## Validação sem hardware

O handshake é validado de ponta a ponta com um "terminal PAX falso" que fala o
protocolo ADB por TCP:

```sh
make
bash test/run_handshake_test.sh
```

Ele envia `A_HDSK(arg0=1)` e confirma que o `pax_adb` responde
`A_HDSK(arg0=2,"paxadb")`, após o que a conexão passa a *online*. `handle_packet`
é idêntico para USB e TCP, então isso exercita exatamente o código do patch. O
resultado válido é a linha `RESULT: PASS` (o código de saída do shell pode ser ≠0
ao encerrar o daemon adb; isso é inofensivo).

## Licença

Apache 2.0 (base de código do AOSP). Veja [`LICENSE`](LICENSE) e [`NOTICE`](NOTICE).
