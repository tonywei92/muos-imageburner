function love.conf(t)
  if os.getenv("IB_SELFTEST") == "1" then
    t.modules.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.joystick = false
    return
  end

  t.identity = "imageburner"
  t.window.title = "Image Burner"
  t.window.width = 720
  t.window.height = 480
  t.window.fullscreen = true
  t.window.resizable = false
  t.window.vsync = 1
end
