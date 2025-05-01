local mon = peripheral.find("monitor")
assert(mon, "Monitor not found")
term.redirect(mon)

mon.setTextScale(0.5)
term.setBackgroundColor(colors.black)

-- Rainbow colors to cycle through
local rainbow = {
  colors.red, colors.orange, colors.yellow, colors.lime,
  colors.cyan, colors.blue, colors.purple, colors.pink
}

-- 5x5 block font definition
local font = {
  A = {" ### ","#   #","#####","#   #","#   #"},
  C = {" ### ","#   #","#    ","#   #"," ### "},
  E = {"#####","#    ","#### ","#    ","#####"},
  G = {" ### ","#    ","# ## ","#  # "," ### "},
  H = {"#   #","#   #","#####","#   #","#   #"},
  I = {"#####","  #  ","  #  ","  #  ","#####"},
  L = {"#    ","#    ","#    ","#    ","#####"},
  N = {"#   #","##  #","# # #","#  ##","#   #"},
  O = {" ### ","#   #","#   #","#   #"," ### "},
  R = {"#### ","#   #","#### ","#  # ","#   #"},
  S = {" ####","#    "," ### ","    #","#### "},
  W = {"#   #","#   #","# # #","# # #"," # # "},
  " " = {"     ","     ","     ","     ","     "}
}

-- Draws a string in big letters at (x,y) with a given color
local function drawBigText(x, y, text, color)
  text = text:upper()
  for row = 1, 5 do
    term.setCursorPos(x, y + row - 1)
    for i = 1, #text do
      local char = text:sub(i, i)
      local glyph = font[char] or font[" "]
      term.setTextColor(color)
      term.write(glyph[row] .. " ")
    end
  end
end

-- Get screen size
local w, h = term.getSize()

-- Main animation loop
while true do
  for i = 1, #rainbow do
    term.setBackgroundColor(colors.black)
    term.clear()
    -- Center "GearHallow" and "Casino"
    drawBigText(math.floor((w - (#"GEARHALLOW" * 6 - 1)) / 2), 3, "GearHallow", rainbow[i])
    drawBigText(math.floor((w - (#"CASINO" * 6 - 1)) / 2), 11, "Casino", rainbow[#rainbow - i + 1])
    sleep(0.3)
  end
end
