-- File: displayMessage.lua

-- CONFIG
local filename = "message.txt"  -- Name of the text file to read

-- Find the monitor
local monitor = nil
for _, side in ipairs(rs.getSides()) do
  if peripheral.getType(side) == "monitor" then
    monitor = peripheral.wrap(side)
    break
  end
end

if not monitor then
  print("No monitor found. Please attach a monitor.")
  return
end

-- Clear monitor and set text scale
monitor.setTextScale(1)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

-- Read file content
if not fs.exists(filename) then
  print("File '" .. filename .. "' not found.")
  return
end

local file = fs.open(filename, "r")
local lines = {}
while true do
  local line = file.readLine()
  if not line then break end
  table.insert(lines, line)
end
file.close()

-- Get monitor size
local width, height = monitor.getSize()

-- Center each line
local function centerText(text)
  local x = math.floor((width - #text) / 2) + 1
  return x
end

-- Display each line, centered vertically if possible
local startY = math.floor((height - #lines) / 2) + 1
for i, line in ipairs(lines) do
  if startY + i - 1 > height then break end
  monitor.setCursorPos(centerText(line), startY + i - 1)
  monitor.write(line)
end
