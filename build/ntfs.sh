#!/bin/bash
set -e
export PATH="$HOME/muos-build/aarch64-linux-musl-cross/bin:$PATH"
BUILD="$HOME/muos-build"
mkdir -p "$BUILD"
cd "$BUILD"
VER=2022.10.3
if [ ! -d "ntfs-3g_ntfsprogs-$VER" ]; then
  curl -fL --retry 3 -o "ntfs-3g_ntfsprogs-$VER.tgz" \
    "https://tuxera.com/opensource/ntfs-3g_ntfsprogs-$VER.tgz"
  tar xzf "ntfs-3g_ntfsprogs-$VER.tgz"
fi
cd "ntfs-3g_ntfsprogs-$VER"
if [ ! -f config.h ]; then
  ./configure --host=aarch64-linux-musl \
    --enable-static --disable-shared \
    --disable-ntfs-3g --disable-uuid \
    CC=aarch64-linux-musl-gcc LDFLAGS="-static -s" >configure.log 2>&1 \
    || { tail -40 configure.log; exit 1; }
fi
make -j"$(nproc)" >make.log 2>&1 || { tail -50 make.log; exit 1; }
find . -name 'mkntfs*' -maxdepth 3 -type f
file ntfsprogs/mkntfs 2>/dev/null || true
