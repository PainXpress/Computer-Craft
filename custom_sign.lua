-- sign.lua - Fully featured customizable BIG text sign for ComputerCraft (Tekkit SMP)

-- Load font module
local font = require("sign/font")

-- Color name to ComputerCraft color API mapping
local colorNames = {
  white = colors.white,
  orange = colors.orange,
  magenta = colors.magenta,
  lightBlue = colors.lightBlue,
  yellow = colors.yellow,
  lime = colors.lime,
  pink = colors.pink,
  gray = colors.gray,
  lightGray = colors.lightGray,
  cyan = colors.cyan,
  purple = colors.purple,
  blue = colors.blue,
  brown = colors.brown,
  green = colors.green,
  red = colors.red,
  black = colors.black,
}

-- Load config from file
local function loadConfig(path)
  local config = {}
  local file = fs.open(path, "r")
  if not file then error("Missing config file: " .. path) end

  for line in file.readLine do
    local key, value = line:match("^(%w+)%s*=%s*(.+)$")
    if key and value then
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

-- Load config values
local config = loadConfig("sign/config.txt")
local text            = config.text or "WELCOME!"
local alignment       = config.alignment or "center"
local padding         = config.padding or 1
local uppercase       = config.uppercase ~= false
local timeout         = config.timeout or 0
local scrollDirection = config.scroll or "none"
local blink           = config.blink or false
local rainbow         = config.rainbow or false
local textColor       = colorNames[config.textColor or "white"] or colors.white
local backgroundColor = colorNames[config.backgroundColor or "black"] or colors.black

-- Wrap monitor (assumes 2x4 setup, adjust as needed)
local monitor = peripheral.find("monitor")
if not monitor then error("Monitor not found") end
monitor.setTextScale(0.5)
monitor.setBackgroundColor(backgroundColor)
monitor.setTextColor(textColor)

-- Clear monitor with current background
local function clearMonitor()
  monitor.setBackgroundColor(backgroundColor)
  monitor.clear()
end

-- Apply padding and alignment
local function getStartPos(lineLength, monitorWidth)
  if alignment == "left" then
    return padding + 1
  elseif alignment == "right" then
    return monitorWidth - lineLength - padding + 1
  else -- center
    return math.floor((monitorWidth - lineLength) / 2) + 1
  end
end

-- Rainbow color cycle
local rainbowColors = {
  colors.red, colors.orange, colors.yellow,
  colors.lime, colors.cyan, colors.blue,
  colors.purple
}

local function nextRainbowColor(index)
  return rainbowColors[(index - 1) % #rainbowColors + 1]
end

-- Draw BIG text to monitor
local function drawText(startY, offset)
  local lines = font.renderText(text, uppercase)
  local monW, monH = monitor.getSize()
  local colorIndex = 1
  for i = 1, #lines do
    local y = startY + i - 1
    if y >= 1 and y <= monH then
      local line = lines[i]
      local x = getStartPos(#line, monW)
      monitor.setCursorPos(x, y)
      if rainbow then
        for c = 1, #line do
          local ch = line:sub(c, c)
          monitor.setTextColor(nextRainbowColor(colorIndex))
          monitor.write(ch)
          colorIndex = colorIndex + 1
        end
      else
        monitor.setTextColor(textColor)
        monitor.write(line)
      end
    end
  end
end

-- Scroll text in various directions
local function scrollLoop()
  local monW, monH = monitor.getSize()
  local lines = font.renderText(text, uppercase)
  local textW = #lines[1]
  local textH = #lines
  local x = 1
  local y = 1
  local dx, dy = 0, 0

  if scrollDirection == "left" then dx = -1 end
  if scrollDirection == "right" then dx = 1; x = monW - textW + 1 end
  if scrollDirection == "up" then dy = -1 end
  if scrollDirection == "down" then dy = 1; y = monH - textH + 1 end

  while true do
    clearMonitor()
    drawText(y, x)
    sleep(0.2)
    x = x + dx
    y = y + dy

    -- Reset scrolling
    if x < -textW or x > monW or y < -textH or y > monH then
      if dx < 0 then x = monW end
      if dx > 0 then x = -textW end
      if dy < 0 then y = monH end
      if dy > 0 then y = -textH end
    end
  end
end

-- Blinking effect
local function blinkLoop()
  local visible = true
  while true do
    clearMonitor()
    if visible then drawText(1, 0) end
    visible = not visible
    sleep(0.5)
  end
end

-- Static display
local function staticDisplay()
  clearMonitor()
  drawText(1, 0)
  if timeout > 0 then sleep(timeout) end
end

-- Main controller
if scrollDirection ~= "none" then
  scrollLoop()
elseif blink then
  blinkLoop()
else
  staticDisplay()
end
