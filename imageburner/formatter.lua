-- formatter.lua
-- Filesystem/cluster options and a background format runner for Image Burner.

local burner = require("burner")
local formatter = {}

local sq = burner.sq

local STATUS = "/tmp/ibfmt.status"
local PIDFILE = "/tmp/ibfmt.pid"
local LOG = "/tmp/ibfmt.log"
local RUNSCRIPT = "/tmp/ibfmt-run.sh"

formatter.STATUS = STATUS

function formatter.toolsDir()
  return love.filesystem.getSource() .. "/tools"
end

-- Filesystems we support, in menu order.
-- mbrtype = MBR partition type byte, gpttype = GPT partition type GUID.
local MSDATA = "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" -- Microsoft basic data
local LINUXFS = "0FC63DAF-8483-4772-8E79-3D69D8477DE4" -- Linux filesystem
formatter.kinds = {
  { id = "fat32", name = "FAT32", kind = "fat", bits = 32, mbrtype = "c", gpttype = MSDATA },
  { id = "fat16", name = "FAT16", kind = "fat", bits = 16, mbrtype = "6", gpttype = MSDATA },
  { id = "fat12", name = "FAT12", kind = "fat", bits = 12, mbrtype = "1", gpttype = MSDATA },
  { id = "exfat", name = "exFAT", kind = "exfat", mbrtype = "7", gpttype = MSDATA },
  { id = "ext2", name = "EXT2", kind = "ext", journal = false, mbrtype = "83", gpttype = LINUXFS },
  { id = "ext3", name = "EXT3", kind = "ext", journal = true, mbrtype = "83", gpttype = LINUXFS },
  { id = "ntfs", name = "NTFS", kind = "ntfs", mbrtype = "7", gpttype = MSDATA },
}

-- Cluster / block size choices. v = sectors (FAT), b = bytes (others). nil label = Auto.
function formatter.clusterOptions(fs)
  if fs.kind == "fat" then
    -- Windows only accepts FAT12 up to 4K, FAT32 up to 32K clusters; FAT16 up to 64K.
    local opts = {
      { label = "Auto" }, { label = "512 B", v = 1 }, { label = "1 KB", v = 2 },
      { label = "2 KB", v = 4 }, { label = "4 KB", v = 8 },
    }
    if fs.bits == 16 then
      opts[#opts + 1] = { label = "8 KB", v = 16 }
      opts[#opts + 1] = { label = "16 KB", v = 32 }
      opts[#opts + 1] = { label = "32 KB", v = 64 }
      opts[#opts + 1] = { label = "64 KB", v = 128 }
    elseif fs.bits == 32 then
      opts[#opts + 1] = { label = "8 KB", v = 16 }
      opts[#opts + 1] = { label = "16 KB", v = 32 }
      opts[#opts + 1] = { label = "32 KB", v = 64 }
    end
    return opts
  elseif fs.kind == "exfat" then
    return {
      { label = "Auto" }, { label = "4 KB", b = 4096 }, { label = "8 KB", b = 8192 },
      { label = "16 KB", b = 16384 }, { label = "32 KB", b = 32768 }, { label = "64 KB", b = 65536 },
      { label = "128 KB", b = 131072 }, { label = "256 KB", b = 262144 }, { label = "512 KB", b = 524288 },
      { label = "1 MB", b = 1048576 }, { label = "2 MB", b = 2097152 }, { label = "4 MB", b = 4194304 },
      { label = "8 MB", b = 8388608 }, { label = "16 MB", b = 16777216 }, { label = "32 MB", b = 33554432 },
    }
  elseif fs.kind == "ntfs" then
    return {
      { label = "Auto" }, { label = "512 B", b = 512 }, { label = "1 KB", b = 1024 },
      { label = "2 KB", b = 2048 }, { label = "4 KB", b = 4096 }, { label = "8 KB", b = 8192 },
      { label = "16 KB", b = 16384 }, { label = "32 KB", b = 32768 }, { label = "64 KB", b = 65536 },
    }
  else -- ext
    return {
      { label = "Auto" }, { label = "1 KB", b = 1024 }, { label = "2 KB", b = 2048 }, { label = "4 KB", b = 4096 },
    }
  end
end

local function mkfsCommand(fs, target, cluster, full)
  local t = sq(target)
  local tools = sq(formatter.toolsDir())
  if fs.kind == "fat" then
    local a = "-F " .. fs.bits
    if cluster and cluster.v then a = a .. " -s " .. cluster.v end
    return "/sbin/mkfs.fat " .. a .. " -I " .. t
  elseif fs.kind == "exfat" then
    local a = ""
    if cluster and cluster.b then a = "--cluster-size=" .. cluster.b end
    return "/usr/sbin/mkfs.exfat " .. a .. " " .. t
  elseif fs.kind == "ext" then
    local ty = fs.journal and "ext3" or "ext2"
    local b = ""
    if cluster and cluster.b then b = "-b " .. cluster.b end
    return tools .. "/mke2fs -F -q -t " .. ty .. " " .. b .. " " .. t
  elseif fs.kind == "ntfs" then
    -- mkntfs: -f = quick (skip its own zeroing). If we already zeroed for a full
    -- format, use quick so we don't zero twice. Otherwise let it do a full init.
    local a = (full and "-f " or "") .. "-F -q"
    if cluster and cluster.b then a = a .. " -c " .. cluster.b end
    return tools .. "/mkntfs " .. a .. " " .. t
  end
  return nil
end

-- Build the generated shell script for a run.
local function buildScript(opts)
  local fs = opts.fs
  local dev = opts.dev
  local hasPT = (opts.layout == "mbr" or opts.layout == "gpt")
  local target = dev
  if hasPT then
    if dev:match("%d$") then target = dev .. "p1" else target = dev .. "1" end
  end
  local mkfs = mkfsCommand(fs, target, opts.cluster, opts.mode == "full")

  local label, ptype
  if opts.layout == "gpt" then
    label, ptype = "gpt", fs.gpttype or "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
  else
    label, ptype = "dos", fs.mbrtype or "83"
  end

  return ([[
#!/bin/sh
STATUS="%s"
PIDFILE="%s"
LOG="%s"
DEV="%s"
LAYOUT="%s"
LABEL="%s"
PTYPE="%s"
MODE="%s"
TARGET="%s"

set_status() { printf 'STAGE=%%s\nPROGRESS=%%s\nTOTAL=%%s\nMSG=%%s\n' "$1" "$2" "$3" "$4" >"$STATUS"; }

echo $$ >"$PIDFILE"
DD_PID=""

cleanup() { [ -n "$DD_PID" ] && kill "$DD_PID" 2>/dev/null; rm -f "$PIDFILE"; }
trap 'set_status canceled 0 0 "Canceled"; cleanup; exit 1' TERM INT

TOTAL=$(cat "/sys/class/block/$(basename "$DEV")/size" 2>/dev/null)
[ -z "$TOTAL" ] && TOTAL=0
TOTAL=$((TOTAL * 512))

if [ "$MODE" = full ]; then
  set_status zerofill 0 "$TOTAL" "Zeroing card (full format)..."
  dd if=/dev/zero of="$DEV" bs=4M conv=fsync 2>/dev/null &
  DD_PID=$!
  while kill -0 "$DD_PID" 2>/dev/null; do
    W=$(awk '/^write_bytes/{print $2}' "/proc/$DD_PID/io" 2>/dev/null)
    [ -z "$W" ] && W=0
    set_status zerofill "$W" "$TOTAL" "Zeroing card (full format)..."
    sleep 1
  done
  wait "$DD_PID"
fi

set_status mkfs 0 "$TOTAL" "Writing filesystem..."
dd if=/dev/zero of="$DEV" bs=1M count=1 conv=fsync 2>/dev/null

if [ "$LAYOUT" != "none" ]; then
  printf ',,'"$PTYPE"'\n' | sfdisk --wipe=always --label "$LABEL" "$DEV" >>"$LOG" 2>&1
  partprobe "$DEV" >/dev/null 2>&1
  blockdev --rereadpt "$DEV" >/dev/null 2>&1
  sleep 1
fi

%s >>"$LOG" 2>&1
RC=$?
sync
if [ $RC -eq 0 ]; then
  set_status done 0 "$TOTAL" "Format complete"
else
  set_status error 0 "$TOTAL" "mkfs failed (rc=$RC)"
fi
rm -f "$PIDFILE"
]]):format(STATUS, PIDFILE, LOG, dev, opts.layout, label, ptype, opts.mode, target, mkfs)
end

-- Launch a format run in the background.
function formatter.start(opts)
  local script = buildScript(opts)
  local f = io.open(RUNSCRIPT, "w")
  if not f then return false, "cannot write run script" end
  f:write(script)
  f:close()

  -- clear old status
  local s = io.open(STATUS, "w"); if s then s:write("STAGE=starting\nPROGRESS=0\nTOTAL=0\nMSG=Starting...\n"); s:close() end
  local lg = io.open(LOG, "w"); if lg then lg:write(""); lg:close() end

  os.execute("chmod 755 " .. sq(RUNSCRIPT) .. "; sh " .. sq(RUNSCRIPT) .. " >/dev/null 2>&1 &")
  opts.target = (opts.layout ~= "none")
    and ((opts.dev:match("%d$") and (opts.dev .. "p1")) or (opts.dev .. "1"))
    or opts.dev
  formatter._opts = opts
  return true
end

-- Read current run status.
function formatter.status()
  local f = io.open(STATUS, "r")
  if not f then return nil end
  local data = f:read("*a") or ""
  f:close()
  local st = {}
  for k, v in data:gmatch("(%w+)=(.-)\n") do st[k] = v end
  st.PROGRESS = tonumber(st.PROGRESS) or 0
  st.TOTAL = tonumber(st.TOTAL) or 0
  return st
end

function formatter.cancel()
  local f = io.open(PIDFILE, "r")
  if not f then return end
  local pid = (f:read("*a") or ""):gsub("%s", "")
  f:close()
  if pid ~= "" then burner.exec("kill " .. pid) end
end

function formatter.logTail(n)
  local out = burner.exec("tail -n " .. tostring(n or 4) .. " " .. sq(LOG))
  return (out:gsub("%s+$", ""))
end

return formatter
