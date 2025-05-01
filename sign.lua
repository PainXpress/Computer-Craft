-- GearHallow Casino Flashy Scrolling Sign with Border

local mon = peripheral.find("monitor")
assert(mon, "Monitor not found")
mon.setTextScale(0.5)
mon.setBackgroundColor(colors.black)
local monW, monH = mon.getSize()

-- Font definition (5×5)
local font = {
    ["A"] = {" ### ","#   #","#####","#   #","#   #"},
    ["C"] = {" ### ","#    ","#    ","#    "," ### "},
    ["E"] = {"#####","#    ","#### ","#    ","#####"},
    ["G"] = {" ### ","#    ","#  ##","#   #"," ### "},
    ["H"] = {"#   #","#   #","#####","#   #","#   #"},
    ["I"] = {" ### ","  #  ","  #  ","  #  "," ### "},
    ["L"] = {"#    ","#    ","#    ","#    ","#####"},
    ["N"] = {"#   #","##  #","# # #","#  ##","#   #"},
    ["O"] = {" ### ","#   #","#   #","#   #"," ### "},
    ["R"] = {"#### ","#   #","#### ","#  # ","#   #"},
    ["S"] = {" ####","#    "," ### ","    #","#### "},
    ["W"] = {"#   #","#   #","# # #","## ##","#   #"},
    [" "] = {"     ","     ","     ","     ","     "}
}

-- Draw a letter at (x,y) scaled
local function drawLetter(char, x, y, scale, color)
    local lines = font[char] or font[" "]
    for row = 1, #lines do
        for col = 1, #lines[row] do
            if lines[row]:sub(col,col) == "#" then
                for dx = 0, scale-1 do
                    for dy = 0, scale-1 do
                        local px = x + (col-1)*scale + dx
                        local py = y + (row-1)*scale + dy
                        if px>=1 and px<=monW and py>=1 and py<=monH then
                            mon.setCursorPos(px,py)
                            mon.setTextColor(color)
                            mon.write("█")
                        end
                    end
                end
            end
        end
    end
end

-- Draw border
local function drawBorder()
    mon.setTextColor(colors.white)
    for x=1,monW do
        mon.setCursorPos(x,1)   mon.write("═")
        mon.setCursorPos(x,monH) mon.write("═")
    end
    for y=1,monH do
        mon.setCursorPos(1,y)   mon.write("║")
        mon.setCursorPos(monW,y) mon.write("║")
    end
    mon.setCursorPos(1,1)       mon.write("╔")
    mon.setCursorPos(monW,1)    mon.write("╗")
    mon.setCursorPos(1,monH)     mon.write("╚")
    mon.setCursorPos(monW,monH)  mon.write("╝")
end

-- Scroll text: in from right -> center -> pause -> out to left
local function scrollWord(word, color)
    local scale = 2
    local letterW = 5 * scale
    local spacing = 1 * scale
    local totalW = #word * letterW + (#word - 1) * spacing
    local centerX = math.floor((monW - totalW) / 2) + 1
    local yStart = math.floor((monH - 5 * scale) / 2) + 1

    -- 1) Move in: from off-screen right to center
    for xStart = monW + 1, centerX, -1 do
        mon.clear()
        drawBorder()
        for i = 1, #word do
            drawLetter(word:sub(i,i), xStart + (i-1)*(letterW+spacing), yStart, scale, color)
        end
        sleep(0.05)
    end
    -- 2) Pause in center
    sleep(2)
    -- 3) Move out: from center to off-screen left
    for xStart = centerX, -totalW, -1 do
        mon.clear()
        drawBorder()
        for i = 1, #word do
            drawLetter(word:sub(i,i), xStart + (i-1)*(letterW+spacing), yStart, scale, color)
        end
        sleep(0.05)
    end
end

-- Main loop: scroll GEARHALLOW then CASINO
local colorsList = { colors.red, colors.orange, colors.yellow, colors.green, colors.cyan, colors.blue, colors.purple, colors.pink }
while true do
    for _, color in ipairs(colorsList) do
        scrollWord("GEARHALLOW", color)
    end
    for _, color in ipairs(colorsList) do
        scrollWord("CASINO", color)
    end
end
