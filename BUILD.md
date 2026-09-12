# Building

The app itself is plain Lua and needs no build step. Two things must be available
on the device before it can run:

1. The **LÖVE 11.5 runtime** (binary + shared libraries).
2. The **static filesystem tools** (`mke2fs`, `mkntfs`) used by the Formatter for
   EXT2/EXT3 and NTFS.

Both are `aarch64` (Allwinner H700). `mkfs.fat` (FAT) and `mkfs.exfat` (exFAT) are
already present in muOS.

---

## 1. LÖVE 11.5 runtime

muOS ships LÖVE 11.5 as part of its bundled applications. The easiest way to get a
compatible runtime is to copy it from one of them on the device:

```sh
SRC="/opt/muos/share/application/RGB Controller"
cp "$SRC/love" ./love
mkdir -p libs
cp "$SRC/libs/liblove-11.5.so" "$SRC/libs/libluajit-5.1.so.2" ./libs/
chmod 755 ./love
```

`./love` links against the system SDL2 and friends, so only `liblove` and
`libluajit` need to be bundled.

---

## 2. Static filesystem tools

muOS does not ship `mkntfs` (NTFS) or a journalling `mke2fs` (EXT3 — the BusyBox
`mke2fs` can only create ext2). We build static `aarch64` binaries from source
using a rootless musl cross-toolchain. No root or system packages are required.

### Toolchain

```sh
mkdir -p ~/muos-build && cd ~/muos-build
curl -fLO https://musl.cc/aarch64-linux-musl-cross.tgz
tar xzf aarch64-linux-musl-cross.tgz
export PATH="$HOME/muos-build/aarch64-linux-musl-cross/bin:$PATH"
```

### e2fsprogs → `mke2fs` (EXT2/EXT3)

```sh
cd ~/muos-build
curl -fLO https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v1.47.1/e2fsprogs-1.47.1.tar.gz
tar xzf e2fsprogs-1.47.1.tar.gz && cd e2fsprogs-1.47.1
./configure --host=aarch64-linux-musl \
  --enable-static --disable-shared --disable-elf-shlibs \
  --disable-nls --disable-uuidd --disable-fsck --disable-e2initrd-helper \
  CC=aarch64-linux-musl-gcc LDFLAGS="-static -s"
make -j"$(nproc)"
# result: misc/mke2fs  (and misc/tune2fs)
```

### ntfs-3g → `mkntfs` (NTFS)

```sh
cd ~/muos-build
curl -fLO https://tuxera.com/opensource/ntfs-3g_ntfsprogs-2022.10.3.tgz
tar xzf ntfs-3g_ntfsprogs-2022.10.3.tgz && cd ntfs-3g_ntfsprogs-2022.10.3
./configure --host=aarch64-linux-musl \
  --enable-static --disable-shared --disable-ntfs-3g --disable-uuid \
  CC=aarch64-linux-musl-gcc LDFLAGS="-static -s"
make -j"$(nproc)"

# The build system links mkntfs dynamically against musl, so relink statically:
cd ntfsprogs
aarch64-linux-musl-gcc -static -s -o mkntfs.static mkntfs-*.o \
  ../libntfs-3g/.libs/libntfs-3g.a -lpthread
# result: ntfsprogs/mkntfs.static
```

Convenience scripts used to produce these are in [`build/`](build):

- `build/e2fs.sh`
- `build/ntfs-static.sh` + `build/ntfs-relink.sh`

Outputs are **not** committed (they are large GPL binaries); build them locally.

### Verify

```sh
file mke2fs mkntfs.static
# ELF 64-bit LSB pie executable, ARM aarch64 ... static-pie linked
```

---

## 3. Assemble the app folder

```sh
APP="/mnt/mmc/MUOS/application/Image Burner"
mkdir -p "$APP/imageburner/tools"
cp -r imageburner/*.lua "$APP/imageburner/"
cp mux_launch.sh mux_lang.ini "$APP/"
cp love "$APP/love"; mkdir -p "$APP/libs"
cp libs/*.so* "$APP/libs/"
cp mke2fs mkntfs.static "$APP/imageburner/tools/"
mv "$APP/imageburner/tools/mkntfs.static" "$APP/imageburner/tools/mkntfs"
chmod 755 "$APP/love" "$APP/mux_launch.sh" "$APP/imageburner/tools/"*
```

The app reads its tools from `<love source>/tools`, i.e.
`.../Image Burner/imageburner/tools/`.

An optional menu icon can be installed into the active theme:

```sh
cp glyph/burner.png "/opt/muos/share/theme/MustardOS/glyph/muxapp/burner.png"
```

Reload the muOS front end (or reboot) and launch **Image Burner** from
Applications.
