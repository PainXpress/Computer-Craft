local font = require("font")

-- SETTINGS ------------------------
local text = "WELCOME!"
local alignment = "center"   -- "left", "center", "right"
local padding = 1            -- spaces between characters
local uppercase = true       -- convert to uppercase
local timeout = 10           -- seconds before clearing, or nil to not clear
local scroll = false         -- not implemented in this version
local blink = false          -- toggle visibility periodically
local rainbow = false        -- not implemented in this version
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
