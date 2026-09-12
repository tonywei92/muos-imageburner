#!/bin/sh
DEST="/mnt/mmc/MUOS/application/Image Burner"
cp /tmp/ib/imageburner/main.lua /tmp/ib/imageburner/conf.lua "$DEST/imageburner/"
cd "$DEST" || exit 1

export LD_LIBRARY_PATH="$DEST/libs"
export IB_SELFTEST=1

./love imageburner
echo "exit=$?"
