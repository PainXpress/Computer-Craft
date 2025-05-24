-- payouts_animated.lua

-- CONFIGURATION
local animateDelay = 0.3      -- Delay between lines
local loopDelay = 2           -- Delay before repeating animation

-- DATA
local payouts = {
    { combo = "7 7 7",              multiplier = 35, color = colors.red },
    { combo = "Cherry Cherry Cherry", multiplier = 14, color = colors.pink },
    { combo = "Bar Bar Bar",        multiplier = 7,  color = colors.blue },
    { combo = "Bell Bell Bell",     multiplier = 3,  color = colors.orange },
    { combo = "All other combos",   multiplier = 0,  color = colors.gray }
}

-- UTILITY
local function findMonitor()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            return peripheral.wrap(name)
        end
    end
    return nil
end

local function centerText(screen, y, text, textColor)
    local w, _ = screen.getSize()
    local x = math.floor((w - #text) / 2) + 1
    screen.setCursorPos(x, y)
    screen.setTextColor(textColor or colors.white)
    screen.write(text)
end

local function displayPayouts(screen)
    screen.setBackgroundColor(colors.black)
    screen.clear()

    screen.setTextColor(colors.yellow)
    centerText(screen, 1, "Slot Machine Payouts", colors.yellow)

    screen.setCursorPos(1, 3)
    screen.setTextColor(colors.lightGray)
    screen.write("Combo                    | Multiplier")
    screen.setCursorPos(1, 4)
    screen.write("-------------------------+-----------")

    for i, entry in ipairs(payouts) do
        sleep(animateDelay)
        local y = 4 + i
        screen.setCursorPos(1, y)
        screen.setTextColor(colors.white)
        screen.write(string.format("%-25s", entry.combo))
        screen.setTextColor(entry.color)
        screen.write("| ")
        screen.write(entry.multiplier .. "x")
    end
end

-- MAIN
local screen = findMonitor() or term
if peripheral.getType(screen) == "monitor" then
    screen.setTextScale(1)
end

while true do
    displayPayouts(screen)
    sleep(loopDelay)
end
