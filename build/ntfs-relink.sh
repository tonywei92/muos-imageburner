#!/bin/bash
set -e
export PATH="$HOME/muos-build/aarch64-linux-musl-cross/bin:$PATH"
cd "$HOME/muos-build/ntfs-3g_ntfsprogs-2022.10.3/ntfsprogs"
echo "--- static libs ---"
ls -la ../libntfs-3g/.libs/*.a 2>/dev/null || true
OBJS="$(ls mkntfs-*.o)"
echo "objs: $OBJS"
aarch64-linux-musl-gcc -static -s -o mkntfs.static $OBJS ../libntfs-3g/.libs/libntfs-3g.a -lpthread
file mkntfs.static
if readelf -l mkntfs.static | grep -q INTERP; then echo "STILL DYNAMIC"; else echo "STATIC OK"; fi
ls -la mkntfs.static
