local function loadConfig(path)
  local config = {}
  local file = fs.open(path, "r")
  if not file then error("Missing config file: " .. path) end

  for line in file.readLine do
    local key, value = line:match("^(%w+)%s*=%s*(.+)$")
    if key and value then
      -- Attempt to auto-typecast
      if value == "true" then
        value = true
      elseif value == "false" then
        value = false
      elseif tonumber(value) then
        value = tonumber(value)
      end
      config[key] = value
    end
  end
  file.close()
  return config
end

local font = require("font")

-- SETTINGS ------------------------
local config = loadConfig("sign/config.txt")

local text      = config.text or "WELCOME!"
local alignment = config.alignment or "center"
local padding   = config.padding or 1
local uppercase = config.uppercase ~= false
local timeout   = config.timeout
local scroll    = config.scroll or false
local blink     = config.blink or false
local rainbow   = config.rainbow or false
-- ---------------------------------

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found!") end
monitor.setTextScale(0.5)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)

local function clearMonitor()
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
end

local function getCharLines(char)
  return font[char] or font["?"] or {
    "#####",
    "#####",
    "#####",
    "#####",
    "#####"
  }
end

local function renderText(input)
  if uppercase then input = input:upper() end

  -- Build each line of the big text
  local lines = {"", "", "", "", ""}
  for char in input:gmatch(".") do
    local charLines = getCharLines(char)
    for i = 1, 5 do
      lines[i] = lines[i] .. charLines[i] .. string.rep(" ", padding)
    end
  end

  -- Calculate horizontal position based on alignment
  local w, h = monitor.getSize()
  local yStart = math.floor((h - 5) / 2) + 1

  for i = 1, 5 do
    local line = lines[i]
    local x
    if alignment == "center" then
      x = math.floor((w - #line) / 2) + 1
    elseif alignment == "right" then
      x = w - #line + 1
    else -- left
      x = 1
    end
    monitor.setCursorPos(x, yStart + i - 1)
    monitor.write(line)
  end
end

local function blinkLoop()
  while true do
    clearMonitor()
    sleep(0.5)
    renderText(text)
    sleep(0.5)
  end
end

-- MAIN ----------------------------
clearMonitor()
if blink then
  blinkLoop()
else
  renderText(text)
  if timeout then
    sleep(timeout)
    clearMonitor()
  end
end
