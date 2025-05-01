-- GearHallow Casino sign for 4x8 (32x32) monitor
local mon = peripheral.find("monitor")
if not mon then error("No monitor connected!") end

-- Setup
mon.setTextScale(0.5)
term.redirect(mon)
term.setBackgroundColor(colors.black)
term.clear()

local w, h = term.getSize()
local colorsList = {
  colors.red, colors.orange, colors.yellow, colors.lime,
  colors.green, colors.cyan, colors.blue, colors.purple,
  colors.magenta
}

local function drawBorder(color)
  term.setBackgroundColor(color)
  for x = 1, w do
    term.setCursorPos(x, 1)
    term.write(" ")
    term.setCursorPos(x, h)
    term.write(" ")
  end
  for y = 2, h - 1 do
    term.setCursorPos(1, y)
    term.write(" ")
    term.setCursorPos(w, y)
    term.write(" ")
  end
end

local function drawCenteredRainbow(y, text, offset)
  for i = 1, #text do
    local letter = text:sub(i, i)
    local col = colorsList[((i + offset) % #colorsList) + 1]
    term.setCursorPos(math.floor((w - #text) / 2) + i, y)
    term.setTextColor(col)
    term.write(letter)
  end
end

-- Animation loop
local tick = 0
while true do
  term.setBackgroundColor(colors.black)
  term.clear()

  drawBorder(colorsList[(tick % #colorsList) + 1])

  drawCenteredRainbow(13, "GearHallow", tick)
  drawCenteredRainbow(15, "Casino", tick + 4)

  sleep(0.2)
  tick = tick + 1
end
