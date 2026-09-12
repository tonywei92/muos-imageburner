#!/bin/sh
# HELP: Burn ISO/IMG images to a removable SD card
# ICON: burner
# GRID: Burner

. /opt/muos/script/var/func.sh

APP_BIN="love"
SETUP_APP "$APP_BIN" ""

# -----------------------------------------------------------------------------

LOVEDIR="${1:-$(dirname "$0")}"
cd "$LOVEDIR" || exit

export LD_LIBRARY_PATH="$LOVEDIR/libs:$LD_LIBRARY_PATH"

./love imageburner
