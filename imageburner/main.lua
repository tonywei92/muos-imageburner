local burner = require("burner")
local formatter = require("formatter")

-- ---------------------------------------------------------------------------
-- Palette / theme
-- ---------------------------------------------------------------------------
local COL = {
  bg1     = { 0.055, 0.055, 0.065 },
  bg2     = { 0.115, 0.115, 0.135 },
  bg      = { 0.055, 0.055, 0.065 },
  panel   = { 0.155, 0.155, 0.180 },
  panel2  = { 0.225, 0.225, 0.255 },
  fg      = { 0.95, 0.95, 0.96 },
  dim     = { 0.60, 0.60, 0.64 },
  muted   = { 0.60, 0.60, 0.64 },
  faint   = { 0.40, 0.40, 0.44 },
  accent  = { 1.00, 0.76, 0.22 },
  accent2 = { 1.00, 0.60, 0.10 },
  dark    = { 0.10, 0.09, 0.05 },
  danger  = { 0.95, 0.35, 0.32 },
  bar     = { 0.20, 0.20, 0.23 },
  track   = { 0.20, 0.20, 0.23 },
  ok      = { 0.40, 0.83, 0.45 },
}

local W, H
local FONT, FONT_S, FONT_L, FONT_XL
local BG

-- ---------------------------------------------------------------------------
-- App state
-- ---------------------------------------------------------------------------
local state = "home"
local homeIndex = 1
local menuIndex = 1
local source = nil      -- image path
local dest = nil        -- disk table
local browser = { path = "/mnt/mmc", items = {}, index = 1, top = 1 }
local disks, diskIndex, diskTop = {}, 1, 1
local diskReturn = "imgmenu"
local confirmIndex = 1
local burn, result
local heldDir, holdTimer = nil, 0
local prevA, prevB = false, false
local prevL, prevR = false, false

-- formatter option state (default filesystem: exFAT, the best choice for SD cards)
local defaultFs = 1
for i, f in ipairs(formatter.kinds) do
  if f.id == "exfat" then defaultFs = i end
end
local fmt = { fsIndex = defaultFs, clusterIndex = 1, layout = 1, mode = 1, row = 1 }
local formatStatus = nil

local function currentFs()
  return formatter.kinds[fmt.fsIndex]
end

local function clusterOpts()
  return formatter.clusterOptions(currentFs())
end

local function fmtLayoutName()
  if fmt.layout == 1 then return "MBR (1 partition)" end
  if fmt.layout == 2 then return "GPT (1 partition)" end
  return "None (superfloppy)"
end

local function fmtModeName()
  return fmt.mode == 2 and "Full (zero-fill)" or "Quick"
end

local function setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function makeVgrad(h, c1, c2)
  local id = love.image.newImageData(1, h)
  for y = 0, h - 1 do
    local t = y / (h - 1)
    local r = c1[1] + (c2[1] - c1[1]) * t
    local g = c1[2] + (c2[2] - c1[2]) * t
    local b = c1[3] + (c2[3] - c1[3]) * t
    id:setPixel(0, y, r, g, b, 1)
  end
  return love.graphics.newImage(id)
end

local function basename(p)
  return (p:gsub("/+$", ""):match("[^/]+$")) or p
end

local function joinPath(dir, name)
  if dir:sub(-1) == "/" then return dir .. name end
  return dir .. "/" .. name
end

local function parentPath(p)
  p = p:gsub("/+$", "")
  local parent = p:match("^(.*)/[^/]+$")
  if not parent or parent == "" then return "/" end
  return parent
end

-- ---------------------------------------------------------------------------
-- Browser / disk loading
-- ---------------------------------------------------------------------------
local function loadBrowser(path)
  browser.path = path
  local items = burner.listDir(path)
  if path ~= "/" then
    table.insert(items, 1, { kind = "up", name = ".." })
  end
  browser.items = items
  browser.index = 1
  browser.top = 1
end

local function refreshDisks()
  disks = burner.listDisks()
  diskIndex = 1
  diskTop = 1
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
local function startBurn()
  if not source or not dest then
    result = { ok = false, msg = "Select an image and a destination first." }
    state = "result"
    return
  end
  local ssz = burner.imageSize(source)
  if ssz and dest.size > 0 and ssz > dest.size then
    result = { ok = false, msg = "Image (" .. burner.humanSize(ssz) .. ") is larger than " ..
      dest.dev .. " (" .. burner.humanSize(dest.size) .. ")." }
    state = "result"
    return
  end
  state = "confirm"
end

local function beginBurn()
  burner.unmountDisk(dest.name)
  local b, err = burner.newBurn(source, dest.dev)
  if not b then
    result = { ok = false, msg = err or "Failed to start" }
    state = "result"
    return
  end
  burn = { b = b, speed = 0, lastT = love.timer.getTime(), lastDone = 0, started = love.timer.getTime() }
  state = "burning"
end

local function finishResult()
  if burn.b.failed then
    result = { ok = false, msg = "Write failed: " .. tostring(burn.b.failed) }
  elseif burn.b.canceled then
    result = { ok = false, msg = "Canceled. The card is incomplete." }
  else
    result = { ok = true, msg = "Image written successfully." }
  end
  burn = nil
  state = "result"
end

-- ---------------------------------------------------------------------------
-- Formatter actions
-- ---------------------------------------------------------------------------
local function wrapIndex(i, n)
  return ((i - 1) % n) + 1
end

local function cycleFormat(delta)
  if fmt.row == 2 then
    fmt.fsIndex = wrapIndex(fmt.fsIndex + delta, #formatter.kinds)
    fmt.clusterIndex = 1
  elseif fmt.row == 3 then
    fmt.clusterIndex = wrapIndex(fmt.clusterIndex + delta, #clusterOpts())
  elseif fmt.row == 4 then
    fmt.layout = (fmt.layout % 3) + 1
  elseif fmt.row == 5 then
    fmt.mode = (fmt.mode == 1) and 2 or 1
  end
end

local function startFormat()
  if not dest then
    result = { ok = false, msg = "Select a Card first (Formatter > Card)." }
    state = "result"
    return
  end
  if dest.root then
    result = { ok = false, msg = "That is the system card. Refusing to format." }
    state = "result"
    return
  end
  state = "formatconfirm"
end

local function beginFormat()
  local fs = currentFs()
  local cluster = clusterOpts()[fmt.clusterIndex]
  local layout = (fmt.layout == 1) and "mbr" or (fmt.layout == 2 and "gpt" or "none")
  burner.unmountDisk(dest.name)
  local ok, err = formatter.start({
    dev = dest.dev,
    name = dest.name,
    fs = fs,
    cluster = cluster,
    layout = layout,
    mode = (fmt.mode == 2) and "full" or "quick",
  })
  if not ok then
    result = { ok = false, msg = err or "Failed to start format" }
    state = "result"
    return
  end
  formatStatus = nil
  state = "formatting"
end

-- ---------------------------------------------------------------------------
-- Input plumbing
-- ---------------------------------------------------------------------------
local function heldDirection()
  local joy = love.joystick.getJoysticks()[1]
  if joy and joy:isGamepad() then
    if joy:isGamepadDown("dpup") then return "up" end
    if joy:isGamepadDown("dpdown") then return "down" end
  end
  if love.keyboard.isDown("up", "w") then return "up" end
  if love.keyboard.isDown("down", "s") then return "down" end
  return nil
end

local function buttonsDown()
  local a, b = false, false
  local joy = love.joystick.getJoysticks()[1]
  if joy and joy:isGamepad() then
    a = joy:isGamepadDown("a")
    b = joy:isGamepadDown("b")
  end
  a = a or love.keyboard.isDown("return", "space", "kpenter")
  b = b or love.keyboard.isDown("escape", "backspace")
  return a, b
end

local function leftRightDown()
  local l, r = false, false
  local joy = love.joystick.getJoysticks()[1]
  if joy and joy:isGamepad() then
    l = joy:isGamepadDown("dpleft")
    r = joy:isGamepadDown("dpright")
  end
  l = l or love.keyboard.isDown("left", "a")
  r = r or love.keyboard.isDown("right", "d")
  return l, r
end

local function doMove(dir)
  local n
  if state == "home" then
    homeIndex = ((homeIndex - 1 + (dir == "up" and -1 or 1)) % 2) + 1
  elseif state == "imgmenu" then
    menuIndex = ((menuIndex - 1 + (dir == "up" and -1 or 1)) % 3) + 1
  elseif state == "browser" then
    n = #browser.items
    if n > 0 then browser.index = ((browser.index - 1 + (dir == "up" and -1 or 1)) % n) + 1 end
  elseif state == "disks" then
    n = #disks
    if n > 0 then diskIndex = ((diskIndex - 1 + (dir == "up" and -1 or 1)) % n) + 1 end
  elseif state == "confirm" then
    confirmIndex = confirmIndex == 1 and 2 or 1
  elseif state == "formatopts" then
    fmt.row = ((fmt.row - 1 + (dir == "up" and -1 or 1)) % 6) + 1
  elseif state == "formatconfirm" then
    confirmIndex = confirmIndex == 1 and 2 or 1
  end
end

local function confirmAction()
  if state == "home" then
    if homeIndex == 1 then
      menuIndex = 1
      state = "imgmenu"
    else
      fmt.row = 1
      state = "formatopts"
    end
  elseif state == "imgmenu" then
    if menuIndex == 1 then
      state = "browser"
      loadBrowser(browser.path)
    elseif menuIndex == 2 then
      refreshDisks()
      diskReturn = "imgmenu"
      state = "disks"
    else
      startBurn()
    end
  elseif state == "browser" then
    local it = browser.items[browser.index]
    if not it then return end
    if it.kind == "up" then
      loadBrowser(parentPath(browser.path))
    elseif it.kind == "dir" then
      loadBrowser(joinPath(browser.path, it.name))
    else
      source = joinPath(browser.path, it.name)
      state = "imgmenu"
    end
  elseif state == "disks" then
    local d = disks[diskIndex]
    if not d then return end
    if d.root then
      result = { ok = false, msg = "That is the card muOS is running from.\nRefusing to overwrite the live system." }
      state = "result"
      return
    end
    dest = d
    state = diskReturn
  elseif state == "confirm" then
    if confirmIndex == 1 then
      beginBurn()
    else
      state = "imgmenu"
    end
  elseif state == "burning" then
    burn.b:cancel()
    finishResult()
  elseif state == "formatopts" then
    if fmt.row == 1 then
      refreshDisks()
      diskReturn = "formatopts"
      state = "disks"
    elseif fmt.row == 6 then
      startFormat()
    end
  elseif state == "formatconfirm" then
    if confirmIndex == 1 then
      beginFormat()
    else
      state = "formatopts"
    end
  elseif state == "formatting" then
    formatter.cancel()
    result = { ok = false, msg = "Format canceled." }
    state = "result"
  elseif state == "result" then
    state = "home"
  end
end

local function backAction()
  if state == "home" then
    love.event.quit()
  elseif state == "imgmenu" then
    state = "home"
  elseif state == "browser" then
    if browser.path ~= "/" then
      loadBrowser(parentPath(browser.path))
    else
      state = "imgmenu"
    end
  elseif state == "disks" then
    state = diskReturn
  elseif state == "confirm" then
    state = "imgmenu"
  elseif state == "burning" then
    burn.b:cancel()
    finishResult()
  elseif state == "formatopts" then
    state = "home"
  elseif state == "formatconfirm" then
    state = "formatopts"
  elseif state == "formatting" then
    formatter.cancel()
    result = { ok = false, msg = "Format canceled." }
    state = "result"
  elseif state == "result" then
    state = "home"
  end
end

-- ---------------------------------------------------------------------------
-- LOVE callbacks
-- ---------------------------------------------------------------------------
function love.load()
  if os.getenv("IB_FMTTEST") == "1" then
    local dev = os.getenv("IB_FMTDEV") or "/dev/loop0"
    local fs = formatter.kinds[1]
    local opts = {
      dev = dev, name = "loop", fs = fs,
      cluster = formatter.clusterOptions(fs)[1],
      layout = os.getenv("IB_FMTLAYOUT") or "mbr",
      mode = os.getenv("IB_FMTMODE") or "quick",
    }
    print("[fmttest] start " .. dev .. " " .. fs.id .. " layout=" .. opts.layout .. " mode=" .. opts.mode)
    local ok, err = formatter.start(opts)
    print("[fmttest] start ok=" .. tostring(ok) .. " target=" .. tostring(opts.target) .. " err=" .. tostring(err))
    for i = 1, 40 do
      os.execute("sleep 1")
      local st = formatter.status()
      if st then
        print(string.format("[fmttest] %2d stage=%s progress=%s total=%s msg=%s",
          i, tostring(st.STAGE), tostring(st.PROGRESS), tostring(st.TOTAL), tostring(st.MSG)))
        if st.STAGE == "done" or st.STAGE == "error" or st.STAGE == "canceled" then break end
      end
    end
    print("[fmttest] log tail: " .. formatter.logTail(5))
    love.event.quit()
    return
  end

  if os.getenv("IB_SELFTEST") == "1" then
    local rd, src = burner.rootDisk()
    print("[selftest] rootDisk=" .. tostring(rd) .. " rootSrc=" .. tostring(src))
    local ds = burner.listDisks()
    print("[selftest] disks=" .. #ds)
    for _, d in ipairs(ds) do
      print(string.format("  %s size=%s root=%s mounted=%s", d.dev, burner.humanSize(d.size),
        tostring(d.root), tostring(d.mounted)))
    end
    local items = burner.listDir("/mnt/mmc")
    print("[selftest] browse /mnt/mmc -> " .. #items .. " entries")
    for i = 1, math.min(#items, 12) do
      local it = items[i]
      print(string.format("  %s %s %s", it.kind, it.name, it.size and burner.humanSize(it.size) or ""))
    end

    local function exists(p)
      local f = io.open(p, "r")
      if f then f:close(); return true end
      return false
    end
    local toolsdir = formatter.toolsDir()
    print("[tools] dir=" .. toolsdir)
    print("[tools] mke2fs=" .. tostring(exists(toolsdir .. "/mke2fs")) ..
      " mkntfs=" .. tostring(exists(toolsdir .. "/mkntfs")) ..
      " mkfs.fat=" .. tostring(exists("/sbin/mkfs.fat")) ..
      " mkfs.exfat=" .. tostring(exists("/usr/sbin/mkfs.exfat")))
    for _, f in ipairs(formatter.kinds) do
      local c = formatter.clusterOptions(f)[1]
      print("[fmt] " .. f.id .. " cluster=" .. c.label)
    end

    -- copy-engine test against regular files (never real devices)
    local td = "/tmp/ibtest"
    os.execute("rm -rf " .. td .. "; mkdir -p " .. td)
    local b = {}
    for i = 1, 256 do b[i] = string.char(i - 1) end
    local data = string.rep(table.concat(b), 8000) -- 2,048,000 bytes
    local function wf(p, d) local f = io.open(p, "wb"); f:write(d); f:close() end
    wf(td .. "/raw.img", data)
    os.execute("gzip -c " .. td .. "/raw.img > " .. td .. "/raw.img.gz")
    os.execute("xz -c " .. td .. "/raw.img > " .. td .. "/raw.img.xz")
    for _, name in ipairs({ "raw.img", "raw.img.gz", "raw.img.xz" }) do
      local src = td .. "/" .. name
      local dst = td .. "/out_" .. name:gsub("%.", "_")
      local eng, err = burner.newBurn(src, dst)
      if not eng then
        print("[burn] " .. name .. " FAILED: " .. tostring(err))
      else
        while not eng.finished and not eng.failed do eng:step() end
        eng:finish()
        local got = tonumber(burner.exec("wc -c < " .. burner.sq(dst)))
        print(string.format("[burn] %-11s total=%s done=%d out=%d ok=%s",
          name, tostring(burner.imageSize(src)), eng.done, got,
          tostring(got == #data and eng.done == #data)))
      end
    end

    -- headless draw smoke test with mocked graphics
  local noop = function() end
  love.graphics = {
    setColor = noop, rectangle = noop, print = noop, printf = noop, setFont = noop,
    setDefaultFilter = noop, circle = noop, line = noop, setLineWidth = noop, draw = noop,
    getWidth = function() return 720 end,
    getHeight = function() return 480 end,
    newFont = function() return { setFilter = noop, getWidth = function(_, s) return #tostring(s) * 8 end } end,
  }
  W, H = 720, 480
  FONT, FONT_S, FONT_L, FONT_XL = love.graphics.newFont(), love.graphics.newFont(), love.graphics.newFont(), love.graphics.newFont()
  BG = nil
  source = "/mnt/mmc/ROMS/test.iso"
  dest = { dev = "/dev/mmcblk1", name = "mmcblk1", size = 8000000000 }
  result = { ok = true, msg = "ok" }
  burn = { b = { total = 1000000, done = 500000, failed = nil, canceled = false }, speed = 2000000, lastT = 0, lastDone = 0, started = 0 }
  refreshDisks()
  loadBrowser("/mnt/mmc")
  local okall = true
  for _, s in ipairs({ "home", "imgmenu", "browser", "disks", "confirm", "result", "burning",
                       "formatopts", "formatconfirm", "formatting" }) do
    state = s
    local ok, err = pcall(love.draw)
    if not ok then okall = false end
    print(string.format("[draw] %-9s %s", s, ok and "ok" or ("ERROR: " .. tostring(err))))
  end
  print("[draw] all=" .. tostring(okall))
  state = "home"
  love.event.quit()
  return
  end

  W, H = love.graphics.getWidth(), love.graphics.getHeight()
  FONT = love.graphics.newFont(20)
  FONT_S = love.graphics.newFont(15)
  FONT_L = love.graphics.newFont(26)
  FONT_XL = love.graphics.newFont(46)
  BG = makeVgrad(H, COL.bg2, COL.bg1)
  love.graphics.setFont(FONT)
  refreshDisks()
  loadBrowser(browser.path)
end

function love.update(dt)
  -- direction repeat
  local dir = heldDirection()
  if dir then
    if dir ~= heldDir then
      doMove(dir)
      heldDir = dir
      holdTimer = 0.30
    else
      holdTimer = holdTimer - dt
      if holdTimer <= 0 then
        doMove(dir)
        holdTimer = 0.09
      end
    end
  else
    heldDir = nil
  end

  local a, b = buttonsDown()
  if a and not prevA then confirmAction() end
  if b and not prevB then backAction() end
  prevA, prevB = a, b

  local l, r = leftRightDown()
  if state == "formatopts" then
    if l and not prevL then cycleFormat(-1) end
    if r and not prevR then cycleFormat(1) end
  end
  prevL, prevR = l, r

  if state == "formatting" then
    local st = formatter.status()
    if st then
      formatStatus = st
      if st.STAGE == "done" then
        result = { ok = true, msg = "Format complete on " .. ((dest and dest.dev) or "card") .. "." }
        state = "result"
      elseif st.STAGE == "error" then
        result = { ok = false, msg = "Format failed.\n" .. formatter.logTail(3) }
        state = "result"
      elseif st.STAGE == "canceled" then
        result = { ok = false, msg = "Format canceled." }
        state = "result"
      end
    end
  end

  if state == "burning" then
    local b = burn.b
    local budget = 0.06
    local t0 = love.timer.getTime()
    repeat
      b:step()
    until b.finished or b.failed or (love.timer.getTime() - t0) > budget

    local now = love.timer.getTime()
    if now - burn.lastT >= 0.25 then
      local inst = (b.done - burn.lastDone) / (now - burn.lastT)
      burn.speed = burn.speed == 0 and inst or (burn.speed * 0.6 + inst * 0.4)
      burn.lastDone = b.done
      burn.lastT = now
    end

    if b.finished or b.failed then
      b:finish()
      finishResult()
    end
  end
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------
local PAD = 22
local Y0 = 92
local ROWH = 46
local ROWGAP = 8

local function shadow(x, y, w, h, r)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x, y + 3, w, h, r, r)
end

local function header(title, subtitle)
  setColor(COL.bg2, 0.85)
  love.graphics.rectangle("fill", 0, 0, W, 62)
  setColor(COL.accent)
  love.graphics.rectangle("fill", 0, 62, W, 3)
  local cx, cy = PAD + 15, 31
  setColor(COL.accent)
  love.graphics.circle("fill", cx, cy, 15)
  setColor(COL.bg2)
  love.graphics.circle("fill", cx, cy, 6)
  love.graphics.setFont(FONT_L)
  setColor(COL.fg)
  love.graphics.print(title, PAD + 44, 15)
  if subtitle and subtitle ~= "" then
    love.graphics.setFont(FONT_S)
    setColor(COL.dim)
    love.graphics.printf(subtitle, PAD, 70, W - PAD * 2, "right")
  end
end

local function hint(x, y, key, label)
  love.graphics.setFont(FONT_S)
  local kw = FONT_S:getWidth(key) + 16
  local kh = 22
  setColor(COL.panel2)
  love.graphics.rectangle("fill", x, y, kw, kh, 6, 6)
  setColor(COL.fg)
  love.graphics.printf(key, x, y + 3, kw, "center")
  local lx = x + kw + 8
  setColor(COL.muted)
  love.graphics.print(label, lx, y + 3)
  return lx + FONT_S:getWidth(label) + 16
end

local function footer(hints)
  setColor(COL.bg2, 0.7)
  love.graphics.rectangle("fill", 0, H - 40, W, 40)
  setColor(COL.panel, 0.6)
  love.graphics.rectangle("fill", 0, H - 40, W, 1)
  -- measure then centre the group
  love.graphics.setFont(FONT_S)
  local total = 0
  for i, h in ipairs(hints) do
    total = total + FONT_S:getWidth(h[1]) + 16 + 8 + FONT_S:getWidth(h[2])
    if i < #hints then total = total + 16 end
  end
  local x = math.max(PAD, (W - total) / 2)
  local y = H - 34
  for _, h in ipairs(hints) do x = hint(x, y, h[1], h[2]) end
end

local function drawList(items, index, top, y0, renderer)
  love.graphics.setFont(FONT)
  local maxRows = math.floor((H - y0 - 52) / (ROWH + ROWGAP))
  if index < top then top = index end
  if index > top + maxRows - 1 then top = index - maxRows + 1 end
  for i = top, math.min(#items, top + maxRows - 1) do
    local y = y0 + (i - top) * (ROWH + ROWGAP)
    local selected = (i == index)
    local x, w = PAD, W - PAD * 2
    if selected then
      shadow(x, y, w, ROWH, 12)
      setColor(COL.accent)
      love.graphics.rectangle("fill", x, y, w, ROWH, 12, 12)
      setColor(COL.dark, 0.30)
      love.graphics.rectangle("fill", x, y, 6, ROWH, 12, 12)
    else
      setColor(COL.panel)
      love.graphics.rectangle("fill", x, y, w, ROWH, 12, 12)
    end
    renderer(items[i], x + 18, y + 13, selected)
  end
  return top
end

local SEL_TXT = COL.dark
local SEL_SUB = { 0.24, 0.20, 0.11 }

local function chevron(x, y, col, r)
  setColor(col)
  love.graphics.setLineWidth(4)
  love.graphics.line(x, y - 10, x + 10, y, x, y + 10)
  love.graphics.setLineWidth(1)
end

local function drawHome()
  header("Image Burner", "muOS")
  local items = {
    { label = "Image Tool", desc = "Write an ISO / IMG to a card", glyph = "disc" },
    { label = "Formatter",  desc = "Create a filesystem on a card", glyph = "wrench" },
  }
  local y, h = 118, 108
  for i, it in ipairs(items) do
    local sel = (i == homeIndex)
    local x, w = PAD, W - PAD * 2
    if sel then
      shadow(x, y, w, h, 16)
      setColor(COL.accent); love.graphics.rectangle("fill", x, y, w, h, 16, 16)
      setColor(COL.dark, 0.30); love.graphics.rectangle("fill", x, y, 6, h, 16, 16)
    else
      setColor(COL.panel); love.graphics.rectangle("fill", x, y, w, h, 16, 16)
    end
    local gx, gy = x + 54, y + h / 2
    setColor(sel and COL.dark or COL.panel2); love.graphics.circle("fill", gx, gy, 28)
    if it.glyph == "disc" then
      setColor(COL.accent); love.graphics.circle("fill", gx, gy, 15)
      setColor(sel and COL.dark or COL.panel2); love.graphics.circle("fill", gx, gy, 6)
    else
      setColor(COL.accent)
      love.graphics.setLineWidth(6)
      love.graphics.line(gx - 12, gy - 12, gx + 12, gy + 12)
      love.graphics.line(gx + 12, gy - 12, gx - 12, gy + 12)
      love.graphics.setLineWidth(1)
    end
    love.graphics.setFont(FONT_L)
    setColor(sel and SEL_TXT or COL.fg); love.graphics.print(it.label, x + 98, y + 24)
    love.graphics.setFont(FONT_S)
    setColor(sel and SEL_SUB or COL.muted); love.graphics.print(it.desc, x + 98, y + 62)
    chevron(x + w - 38, gy, sel and COL.dark or COL.faint)
    y = y + h + 24
  end
  footer({ { "A/Enter", "open" }, { "D-Pad", "move" }, { "B/Esc", "quit" } })
end

local function drawImgMenu()
  header("Image Tool", "write image to card")
  local items = {
    { label = "Image", value = source and basename(source) or nil, action = true },
    { label = "Destination", value = dest and (dest.dev .. "   " .. burner.humanSize(dest.size)) or nil, action = true },
    { label = "Start Burn", action = true },
  }
  drawList(items, menuIndex, 1, Y0 + 28, function(it, x, y, sel)
    love.graphics.setFont(FONT)
    setColor(sel and SEL_TXT or COL.fg)
    love.graphics.print(it.label, x, y)
    if it.value then
      love.graphics.setFont(FONT_S)
      setColor(sel and SEL_SUB or COL.muted)
      love.graphics.printf(it.value, x, y + 4, W - PAD * 2 - 70, "right")
    end
    chevron(x + W - PAD * 2 - 40, y + 10, sel and COL.dark or COL.faint)
  end)
  footer({ { "A/Enter", "select" }, { "D-Pad", "move" }, { "B/Esc", "back" } })
end

local function drawBrowser()
  header("Select Image", browser.path)
  if #browser.items == 0 then
    love.graphics.setFont(FONT)
    setColor(COL.muted)
    love.graphics.printf("No folders or .iso/.img files here.", 0, 200, W, "center")
  else
    browser.top = drawList(browser.items, browser.index, browser.top, Y0 + 4, function(it, x, y, sel)
      love.graphics.setFont(FONT)
      if it.kind == "up" then
        setColor(sel and SEL_TXT or COL.muted)
        love.graphics.print("..", x + 30, y)
        setColor(sel and COL.dark or COL.accent)
        love.graphics.circle("line", x + 12, y + 9, 8)
      elseif it.kind == "dir" then
        setColor(sel and COL.dark or COL.accent)
        love.graphics.rectangle("fill", x + 2, y + 2, 18, 14, 4, 4)
        setColor(sel and SEL_TXT or COL.fg)
        love.graphics.print(it.name, x + 30, y)
      else
        setColor(sel and COL.dark or COL.accent)
        love.graphics.circle("fill", x + 11, y + 9, 9)
        setColor(sel and COL.dark or COL.panel); love.graphics.circle("fill", x + 11, y + 9, 3)
        setColor(sel and SEL_TXT or COL.fg)
        love.graphics.print(it.name, x + 30, y)
        love.graphics.setFont(FONT_S)
        setColor(sel and SEL_SUB or COL.muted)
        love.graphics.printf(burner.humanSize(it.size), x, y + 4, W - PAD * 2 - 40, "right")
      end
    end)
  end
  footer({ { "A/Enter", "open" }, { "B/Esc", "up one level" } })
end

local function drawDisks()
  header("Select Card", "ALL DATA ON THE CHOSEN CARD WILL BE ERASED")
  if #disks == 0 then
    love.graphics.setFont(FONT)
    setColor(COL.muted)
    love.graphics.printf("No cards detected. Insert one and reopen.", 0, 200, W, "center")
  else
    diskTop = drawList(disks, diskIndex, diskTop, Y0 + 4, function(d, x, y, sel)
      love.graphics.setFont(FONT)
      setColor(sel and SEL_TXT or COL.fg)
      love.graphics.print(d.dev, x, y)
      love.graphics.setFont(FONT_S)
      setColor(sel and SEL_SUB or COL.muted)
      love.graphics.print(burner.humanSize(d.size), x + 240, y + 4)
      if d.root then
        setColor(sel and COL.dark or COL.danger)
        love.graphics.print("[SYSTEM - LOCKED]", x + 360, y + 4)
      elseif d.mounted then
        setColor(sel and COL.dark or COL.accent)
        love.graphics.print("[mounted]", x + 360, y + 4)
      end
    end)
  end
  footer({ { "A/Enter", "choose" }, { "B/Esc", "back" } })
end

local function infoCard(y, lines)
  setColor(COL.panel)
  love.graphics.rectangle("fill", PAD, y, W - PAD * 2, 20 + #lines * 26, 14, 14)
  local ty = y + 14
  for _, l in ipairs(lines) do
    setColor(COL.faint)
    love.graphics.setFont(FONT_S)
    love.graphics.print(l[1], PAD + 18, ty + 4)
    setColor(COL.fg)
    love.graphics.setFont(FONT)
    love.graphics.printf(l[2], PAD + 18, ty, W - PAD * 2 - 36, "right")
    ty = ty + 26
  end
end

local function warnBand(y, text)
  setColor(COL.danger, 0.16)
  love.graphics.rectangle("fill", PAD, y, W - PAD * 2, 42, 12, 12)
  setColor(COL.danger)
  love.graphics.setFont(FONT)
  love.graphics.printf(text, PAD + 12, y + 11, W - PAD * 2 - 24, "center")
end

local function confirmOptions(y)
  local items = { { label = "Yes, continue", danger = true }, { label = "No, go back" } }
  drawList(items, confirmIndex, 1, y, function(it, x, yy, sel)
    love.graphics.setFont(FONT)
    if it.danger then
      setColor(sel and COL.dark or COL.danger)
    else
      setColor(sel and SEL_TXT or COL.fg)
    end
    love.graphics.print(it.label, x, yy)
  end)
end

local function drawConfirm()
  header("Confirm Burn", "this cannot be undone")
  infoCard(Y0, {
    { "Image", basename(source) },
    { "Card", dest.dev .. "   (" .. burner.humanSize(dest.size) .. ")" },
  })
  warnBand(Y0 + 92, "ALL DATA ON " .. dest.dev .. " WILL BE ERASED")
  confirmOptions(Y0 + 156)
  footer({ { "A/Enter", "select" }, { "D-Pad", "move" }, { "B/Esc", "cancel" } })
end

local function drawProgressScreen(title, subtitle, frac, msg, sub)
  header(title, subtitle)
  local bw = W - PAD * 2
  local bx, by = PAD, 176
  love.graphics.setColor(0, 0, 0, 0.40); love.graphics.rectangle("fill", bx, by, bw, 38, 15, 15)
  setColor(COL.track); love.graphics.rectangle("fill", bx, by, bw, 38, 15, 15)
  if frac then
    local fw = math.max(18, bw * frac)
    setColor(COL.accent2); love.graphics.rectangle("fill", bx, by, fw, 38, 15, 15)
    setColor(COL.accent, 0.55); love.graphics.rectangle("fill", bx + 5, by + 5, math.max(6, fw - 10), 12, 6, 6)
  else
    local seg = bw * 0.28
    local pos = (love.timer.getTime() * 0.5 % 1.6) - 0.3
    local sx = bx + math.max(0, math.min(bw - seg, bw * pos))
    setColor(COL.accent2); love.graphics.rectangle("fill", sx, by, seg, 38, 15, 15)
    setColor(COL.accent, 0.5); love.graphics.rectangle("fill", sx + 5, by + 5, seg - 10, 12, 6, 6)
  end
  love.graphics.setFont(FONT_XL)
  setColor(COL.fg)
  love.graphics.printf(frac and string.format("%d%%", math.floor(frac * 100 + 0.5)) or "...", 0, by + 72, W, "center")
  love.graphics.setFont(FONT)
  setColor(COL.muted)
  love.graphics.printf(msg or "", PAD, by + 140, W - PAD * 2, "center")
  if sub then
    love.graphics.setFont(FONT_S)
    setColor(COL.faint)
    love.graphics.printf(sub, PAD, by + 172, W - PAD * 2, "center")
  end
  footer({ { "A/B/Esc", "cancel" } })
end

local function drawBurning()
  local b = burn.b
  local frac = b.total > 0 and math.min(1, b.done / b.total) or nil
  local sizeTxt = (b.total > 0)
    and (burner.humanSize(b.done) .. " / " .. burner.humanSize(b.total))
    or (burner.humanSize(b.done) .. " written")
  local eta = "--"
  if b.total > 0 and burn.speed > 1024 then
    local secs = (b.total - b.done) / burn.speed
    eta = string.format("%d:%02d", math.floor(secs / 60), math.floor(secs) % 60)
  end
  drawProgressScreen("Burning...", basename(source) .. "  ->  " .. dest.dev, frac, sizeTxt,
    string.format("Speed %s/s     ETA %s", burner.humanSize(burn.speed), eta))
end

local function drawResult()
  header("Image Burner", "")
  local cy = 196
  local col = result.ok and COL.ok or COL.danger
  setColor(col, 0.16); love.graphics.circle("fill", W / 2, cy, 74)
  setColor(col); love.graphics.circle("fill", W / 2, cy, 52)
  setColor(COL.bg1)
  love.graphics.setLineWidth(10)
  if result.ok then
    love.graphics.line(W / 2 - 22, cy + 2, W / 2 - 6, cy + 20)
    love.graphics.line(W / 2 - 6, cy + 20, W / 2 + 24, cy - 18)
  else
    love.graphics.line(W / 2 - 18, cy - 18, W / 2 + 18, cy + 18)
    love.graphics.line(W / 2 - 18, cy + 18, W / 2 + 18, cy - 18)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setFont(FONT_L)
  setColor(COL.fg)
  love.graphics.printf(result.ok and "Done" or "Stopped", 0, cy + 78, W, "center")
  love.graphics.setFont(FONT)
  setColor(COL.muted)
  love.graphics.printf(result.msg, PAD, cy + 122, W - PAD * 2, "center")
  footer({ { "A/B/Esc", "back" } })
end

local function drawFormatOpts()
  header("Formatter", dest and dest.dev or "no card selected")
  local fs = currentFs()
  local rows = {
    { label = "Card", value = dest and (dest.dev .. "   " .. burner.humanSize(dest.size)) or "select card", action = true },
    { label = "Filesystem", value = fs.name },
    { label = "Cluster / block", value = clusterOpts()[fmt.clusterIndex].label },
    { label = "Partition table", value = fmtLayoutName() },
    { label = "Mode", value = fmtModeName() },
    { label = "Start Format", action = true },
  }
  drawList(rows, fmt.row, 1, Y0, function(it, x, y, sel)
    love.graphics.setFont(FONT)
    if it.label == "Start Format" then
      setColor(sel and SEL_TXT or COL.accent)
      love.graphics.print(it.label, x, y)
      return
    end
    setColor(sel and SEL_TXT or COL.fg)
    love.graphics.print(it.label, x, y)
    love.graphics.setFont(FONT_S)
    setColor(sel and SEL_SUB or COL.muted)
    if it.action then
      love.graphics.printf("[ " .. it.value .. " ]", x, y + 4, W - PAD * 2 - 40, "right")
    else
      love.graphics.printf("< " .. it.value .. " >", x, y + 4, W - PAD * 2 - 40, "right")
    end
  end)
  footer({ { "L/R", "change" }, { "D-Pad", "row" }, { "A", "open" }, { "B/Esc", "back" } })
end

local function drawFormatConfirm()
  header("Confirm Format", "this cannot be undone")
  local fs = currentFs()
  infoCard(Y0, {
    { "Card", dest.dev .. "   (" .. burner.humanSize(dest.size) .. ")" },
    { "Filesystem", fs.name .. "   cluster " .. clusterOpts()[fmt.clusterIndex].label },
    { "Layout", fmtLayoutName() .. "   mode " .. fmtModeName() },
  })
  warnBand(Y0 + 118, "ALL DATA ON " .. dest.dev .. " WILL BE ERASED")
  confirmOptions(Y0 + 182)
  footer({ { "A/Enter", "select" }, { "D-Pad", "move" }, { "B/Esc", "cancel" } })
end

local function drawFormatting()
  local st = formatStatus or { STAGE = "starting", PROGRESS = 0, TOTAL = 0, MSG = "Starting..." }
  local frac, msg
  if st.STAGE == "zerofill" and st.TOTAL > 0 then
    frac = math.min(1, st.PROGRESS / st.TOTAL)
    msg = burner.humanSize(st.PROGRESS) .. " / " .. burner.humanSize(st.TOTAL)
  else
    msg = st.MSG or "Working..."
  end
  drawProgressScreen("Formatting...", dest and dest.dev or "card", frac, msg, "Do not remove the card")
end

function love.draw()
  if BG then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(BG, 0, 0, 0, W, 1)
  else
    setColor(COL.bg1)
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
  if state == "home" then drawHome()
  elseif state == "imgmenu" then drawImgMenu()
  elseif state == "browser" then drawBrowser()
  elseif state == "disks" then drawDisks()
  elseif state == "confirm" then drawConfirm()
  elseif state == "burning" then drawBurning()
  elseif state == "formatopts" then drawFormatOpts()
  elseif state == "formatconfirm" then drawFormatConfirm()
  elseif state == "formatting" then drawFormatting()
  elseif state == "result" then drawResult() end
end
