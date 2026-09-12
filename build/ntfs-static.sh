#!/bin/bash
set -e
export PATH="$HOME/muos-build/aarch64-linux-musl-cross/bin:$PATH"
cd "$HOME/muos-build/ntfs-3g_ntfsprogs-2022.10.3"
make -C ntfsprogs clean >/dev/null 2>&1 || true
make -C ntfsprogs mkntfs CC=aarch64-linux-musl-gcc LDFLAGS="-static -s" >static.log 2>&1 \
  || { tail -30 static.log; exit 1; }
file ntfsprogs/mkntfs
if readelf -l ntfsprogs/mkntfs 2>/dev/null | grep -q INTERP; then
  echo "STILL DYNAMIC"
  readelf -l ntfsprogs/mkntfs | grep INTERP
else
  echo "STATIC OK"
fi
