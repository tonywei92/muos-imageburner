#!/bin/bash
set -e
export PATH="$HOME/muos-build/aarch64-linux-musl-cross/bin:$PATH"
BUILD="$HOME/muos-build"
mkdir -p "$BUILD"
cd "$BUILD"
VER=1.47.1
if [ ! -d "e2fsprogs-$VER" ]; then
  curl -fL --retry 3 -o "e2fsprogs-$VER.tar.gz" \
    "https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v$VER/e2fsprogs-$VER.tar.gz"
  tar xzf "e2fsprogs-$VER.tar.gz"
fi
cd "e2fsprogs-$VER"
if [ ! -f config.h ]; then
  ./configure --host=aarch64-linux-musl \
    --enable-static --disable-shared --disable-elf-shlibs \
    --disable-nls --disable-uuidd --disable-fsck --disable-e2initrd-helper \
    CC=aarch64-linux-musl-gcc LDFLAGS="-static -s" >configure.log 2>&1 || { tail -30 configure.log; exit 1; }
fi
make -j"$(nproc)" >make.log 2>&1 || { tail -40 make.log; exit 1; }
file misc/mke2fs
ls -la misc/mke2fs misc/tune2fs 2>/dev/null || true
