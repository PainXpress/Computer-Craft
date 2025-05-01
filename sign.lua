-- GearHallow Casino Flashy Scrolling Sign with Border

local mon = peripheral.find("monitor")
mon.setTextScale(0.5)
mon.setBackgroundColor(colors.black)
local monW, monH = mon.getSize()

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

function drawLetter(char, x, y, scale, color)
    local lines = font[char] or font[" "]
    for row = 1, #lines do
        for col = 1, #lines[row] do
            local pixel = lines[row]:sub(col, col)
            if pixel == "#" then
                for dx = 0, scale - 1 do
                    for dy = 0, scale - 1 do
                        local px = x + (col - 1) * scale + dx
                        local py = y + (row - 1) * scale + dy
                        if px >= 1 and px <= monW and py >= 1 and py <= monH then
                            mon.setCursorPos(px, py)
                            mon.setTextColor(color)
                            mon.write("█")
                        end
                    end
                end
            end
        end
    end
end

function drawBorder()
    mon.setTextColor(colors.white)
    for x = 1, monW do
        mon.setCursorPos(x, 1)
        mon.write("═")
        mon.setCursorPos(x, monH)
        mon.write("═")
    end
    for y = 1, monH do
        mon.setCursorPos(1, y)
        mon.write("║")
        mon.setCursorPos(monW, y)
        mon.write("║")
    end
    mon.setCursorPos(1, 1) mon.write("╔")
    mon.setCursorPos(monW, 1) mon.write("╗")
    mon.setCursorPos(1, monH) mon.write("╚")
    mon.setCursorPos(monW, monH) mon.write("╝")
end

function displayTextScroll(fullText, color)
    local scale = 2
    local letterWidth = 5 * scale
    local spacing = 1 * scale
    local totalWidth = (#fullText * letterWidth) + ((#fullText - 1) * spacing)
    local visibleWidth = monW

    for offset = 0, totalWidth do
        mon.clear()
        drawBorder()
        local xStart = 2 - offset
        local yStart = math.floor((monH - 5 * scale) / 2)
        for i = 1, #fullText do
            local char = fullText:sub(i, i):upper()
            drawLetter(char, xStart + (i - 1) * (letterWidth + spacing), yStart, scale, color)
        end
        sleep(0.05)
    end
end

local messages = {"GEARHALLOW", "CASINO"}
local colorsList = { colors.red, colors.orange, colors.yellow, colors.green, colors.cyan, colors.blue, colors.purple, colors.pink }

while true do
    for _, message in ipairs(messages) do
        for _, color in ipairs(colorsList) do
            displayTextScroll(message, color)
            sleep(0.4)
        end
        sleep(1.5)
    end
end
