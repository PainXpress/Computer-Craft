-- GearHallow Casino Flashy Sign

local mon = peripheral.find("monitor")
mon.setTextScale(0.5)
mon.setBackgroundColor(colors.black)
local monW, monH = mon.getSize()

-- Basic 5x5 font (use '#' for pixels)
font = {
    ["A"] = {
        " ### ",
        "#   #",
        "#####",
        "#   #",
        "#   #",
    },
    ["C"] = {
        " ### ",
        "#    ",
        "#    ",
        "#    ",
        " ### ",
    },
    ["E"] = {
        "#####",
        "#    ",
        "#### ",
        "#    ",
        "#####",
    },
    ["G"] = {
        " ### ",
        "#    ",
        "#  ##",
        "#   #",
        " ### ",
    },
    ["H"] = {
        "#   #",
        "#   #",
        "#####",
        "#   #",
        "#   #",
    },
    ["I"] = {
        " ### ",
        "  #  ",
        "  #  ",
        "  #  ",
        " ### ",
    },
    ["L"] = {
        "#    ",
        "#    ",
        "#    ",
        "#    ",
        "#####",
    },
    ["N"] = {
        "#   #",
        "##  #",
        "# # #",
        "#  ##",
        "#   #",
    },
    ["O"] = {
        " ### ",
        "#   #",
        "#   #",
        "#   #",
        " ### ",
    },
    ["R"] = {
        "#### ",
        "#   #",
        "#### ",
        "#  # ",
        "#   #",
    },
    ["S"] = {
        " ####",
        "#    ",
        " ### ",
        "    #",
        "#### ",
    },
    ["W"] = {
        "#   #",
        "#   #",
        "# # #",
        "## ##",
        "#   #",
    },
    [" "] = {
        "     ",
        "     ",
        "     ",
        "     ",
        "     ",
    }
}

-- Draw a letter at (x, y) with scale and color
function drawLetter(char, x, y, scale, color)
    local lines = font[char] or font[" "]
    for row = 1, #lines do
        for col = 1, #lines[row] do
            local pixel = lines[row]:sub(col, col)
            if pixel == "#" then
                for dx = 0, scale - 1 do
                    for dy = 0, scale - 1 do
                        mon.setCursorPos(x + (col - 1) * scale + dx, y + (row - 1) * scale + dy)
                        mon.setTextColor(color)
                        mon.write("█")
                    end
                end
            end
        end
    end
end

-- Draw scaled-up text centered
function displayText(text, color)
    mon.clear()
    local scale = 2
    local letterWidth = 5 * scale
    local spacing = 1 * scale
    local totalWidth = (#text * letterWidth) + ((#text - 1) * spacing)
    local startX = math.floor((monW - totalWidth) / 2)
    local startY = math.floor((monH - (5 * scale)) / 2)

    for i = 1, #text do
        local char = text:sub(i, i):upper()
        drawLetter(char, startX + (i - 1) * (letterWidth + spacing), startY, scale, color)
    end
end

-- Flashy color loop
local colorsList = { colors.red, colors.orange, colors.yellow, colors.green, colors.cyan, colors.blue, colors.purple, colors.pink }

while true do
    for i = 1, #colorsList do
        displayText("GEARHALLOW", colorsList[i])
        sleep(0.4)
    end
end
