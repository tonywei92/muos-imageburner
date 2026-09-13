-- burner.lua
-- Image/device discovery and the copy engine for Image Burner (muOS / LOVE 11.5)

local burner = {}

local CHUNK = 512 * 1024

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function burner.sq(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function burner.exec(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return "" end
  local out = p:read("*a") or ""
  p:close()
  return out
end

function burner.humanSize(n)
  n = tonumber(n) or 0
  if n >= 1024 ^ 4 then return string.format("%.2f TB", n / 1024 ^ 4) end
  if n >= 1024 ^ 3 then return string.format("%.2f GB", n / 1024 ^ 3) end
  if n >= 1024 ^ 2 then return string.format("%.1f MB", n / 1024 ^ 2) end
  if n >= 1024 then return string.format("%.1f KB", n / 1024) end
  return tostring(math.floor(n)) .. " B"
end

-- File size without reading the file. BusyBox `wc -c < file` reads the whole
-- file, so never use it for large images; seek("end") is O(1).
function burner.fileSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end")
  f:close()
  return n
end

local function joinPath(dir, name)
  if dir:sub(-1) == "/" then return dir .. name end
  return dir .. "/" .. name
end

-- "/dev/mmcblk0p5" -> "mmcblk0", "/dev/sda1" -> "sda", "/dev/nvme0n1p2" -> "nvme0n1"
local function baseDisk(src)
  local name = src and src:match("/dev/(.+)$")
  if not name then return nil end
  if name:match("^mmcblk%d+") or name:match("^nvme%d+n%d+") then
    name = name:gsub("p%d+$", "")
  else
    name = name:gsub("%d+$", "")
  end
  return name
end

function burner.rootDisk()
  local data = readFile("/proc/mounts") or ""
  for line in data:gmatch("[^\n]+") do
    local src, mnt = line:match("^(%S+)%s+(%S+)")
    if mnt == "/" then
      return baseDisk(src), src
    end
  end
  return nil
end

local function isPartOf(part, disk)
  if disk:match("^mmcblk") then
    return part:match("^" .. disk .. "p%d+$") ~= nil
  end
  return part:match("^" .. disk .. "%d+$") ~= nil
end

function burner.diskMounted(disk)
  local data = readFile("/proc/mounts") or ""
  for line in data:gmatch("[^\n]+") do
    local src = line:match("^(%S+)")
    if src and src:sub(1, 5) == "/dev/" then
      local dn = src:sub(6)
      if dn == disk or isPartOf(dn, disk) then return true end
    end
  end
  return false
end

-- Whole-disk block devices, with sizes and the root/booted disk flagged.
function burner.listDisks()
  local root = burner.rootDisk()
  local parts = readFile("/proc/partitions") or ""
  local disks = {}
  for line in parts:gmatch("[^\n]+") do
    local major, minor, blocks, name = line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%S+)")
    if name and (name:match("^mmcblk%d+$") or name:match("^sd[a-z]$") or name:match("^nvme%d+n%d+$")) then
      disks[#disks + 1] = {
        name = name,
        dev = "/dev/" .. name,
        size = tonumber(blocks) * 1024,
        root = (name == root),
        mounted = burner.diskMounted(name),
      }
    end
  end
  table.sort(disks, function(a, b) return a.dev < b.dev end)
  return disks
end

function burner.unmountDisk(disk)
  if disk:match("^mmcblk") then
    burner.exec("for p in /dev/" .. disk .. "p*; do umount \"$p\"; done")
  else
    burner.exec("for p in /dev/" .. disk .. "[0-9]*; do umount \"$p\"; done")
  end
  return true
end

local function isImage(name)
  local n = name:lower()
  return n:match("%.iso$") or n:match("%.img$") or n:match("%.dd$") or n:match("%.raw$")
      or n:match("%.iso%.gz$") or n:match("%.img%.gz$")
      or n:match("%.iso%.xz$") or n:match("%.img%.xz$")
end

-- Returns directories and image files in a path.
function burner.listDir(path)
  local cmd = "cd " .. burner.sq(path) .. " && for f in * .[!.]*; do " ..
    "[ -e \"$f\" ] || continue; " ..
    "if [ -d \"$f\" ]; then printf 'D\\t%s\\n' \"$f\"; " ..
    "else printf 'F\\t%s\\n' \"$f\"; fi; done"
  local out = burner.exec(cmd)
  local dirs, files = {}, {}
  for line in out:gmatch("[^\n]+") do
    local kind, name = line:match("^(%a)\t(.*)$")
    if kind == "D" then
      dirs[#dirs + 1] = { kind = "dir", name = name }
    elseif kind == "F" and isImage(name) then
      files[#files + 1] = { kind = "file", name = name, size = burner.fileSize(joinPath(path, name)) }
    end
  end
  table.sort(dirs, function(a, b) return a.name:lower() < b.name:lower() end)
  table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
  local items = {}
  for _, d in ipairs(dirs) do items[#items + 1] = d end
  for _, f in ipairs(files) do items[#items + 1] = f end
  return items
end

-- Uncompressed size of an image, or nil if unknown.
function burner.imageSize(path)
  local low = path:lower()
  if low:match("%.gz$") then
    -- Read the ISIZE field from the gzip trailer (last 4 bytes, little-endian).
    -- This is O(1). `gzip -l` is NOT usable here: for files whose uncompressed
    -- size exceeds 4 GiB it decompresses the whole file, which can take minutes.
    local c = burner.fileSize(path)
    if not c or c < 18 then return nil end
    local f = io.open(path, "rb")
    if not f then return nil end
    f:seek("set", c - 4)
    local b = f:read(4)
    f:close()
    if not b or #b < 4 then return nil end
    local r = b:byte(1) + b:byte(2) * 256 + b:byte(3) * 65536 + b:byte(4) * 16777216
    -- If the trailer value is at least the compressed size it is the real size;
    -- otherwise it wrapped past 4 GiB and we don't know the total -> unknown.
    if r >= c then return r end
    return nil
  elseif low:match("%.xz$") then
    local out = burner.exec("xz --robot --list " .. burner.sq(path))
    local u = out:match("\ntotals\t%d+\t%d+\t%d+\t(%d+)")
    return tonumber(u)
  else
    return burner.fileSize(path)
  end
end

-- ---------------------------------------------------------------------------
-- Burn engine: step()-driven so the UI stays responsive and cancellable.
-- ---------------------------------------------------------------------------

local Burn = {}
Burn.__index = Burn

function burner.newBurn(src, dst)
  local low = src:lower()
  local reader
  if low:match("%.gz$") then
    reader = io.popen("gzip -dc " .. burner.sq(src))
  elseif low:match("%.xz$") then
    reader = io.popen("xz -dc " .. burner.sq(src))
  else
    reader = io.open(src, "rb")
  end

  if not reader then
    return nil, "Cannot open source image"
  end

  local writer, err = io.open(dst, "wb")
  if not writer then
    if low:match("%.gz$") or low:match("%.xz$") then reader:close() else reader:close() end
    return nil, "Cannot open destination " .. dst .. ": " .. tostring(err)
  end
  writer:setvbuf("no")
  if reader.setvbuf then reader:setvbuf("full", 1024 * 1024) end

  local self = setmetatable({
    src = src,
    dst = dst,
    reader = reader,
    writer = writer,
    total = burner.imageSize(src) or 0,
    done = 0,
    finished = false,
    canceled = false,
    failed = nil,
  }, Burn)

  return self
end

function Burn:step()
  if self.finished or self.failed then return end
  local chunk = self.reader:read(CHUNK)
  if chunk == nil then
    self.finished = true
    return
  end
  if #chunk > 0 then
    local ok, err = self.writer:write(chunk)
    if not ok then
      self.failed = tostring(err)
      return
    end
    self.done = self.done + #chunk
  end
end

function Burn:finish()
  if self.writer then pcall(function() self.writer:flush() end) end
  if self.writer then pcall(function() self.writer:close() end) end
  if self.reader then pcall(function() self.reader:close() end) end
  self.writer, self.reader = nil, nil
  burner.exec("sync")
end

function Burn:cancel()
  self.canceled = true
  self:finish()
end

return burner
