-- payouts_animated.lua

-- CONFIGURATION
local useMonitor = false  -- Set to true if using a monitor peripheral
local monitorSide = "right"  -- Change this to match your setup
local animateDelay = 0.3

-- DATA
local payouts = {
    { combo = "7 7 7",              multiplier = 35, color = colors.red },
    { combo = "Cherry Cherry Cherry", multiplier = 14, color = colors.pink },
    { combo = "Bar Bar Bar",        multiplier = 7,  color = colors.blue },
    { combo = "Bell Bell Bell",     multiplier = 3,  color = colors.orange },
    { combo = "All other combos",   multiplier = 0,  color = colors.gray }
}

-- SETUP TERMINAL OR MONITOR
local screen = term
if useMonitor then
    local monitor = peripheral.wrap(monitorSide)
    monitor.setTextScale(1)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    screen = monitor
else
    term.setBackgroundColor(colors.black)
    term.clear()
end

-- UTILITY
local function centerText(y, text, textColor)
    local w, _ = screen.getSize()
    local x = math.floor((w - #text) / 2) + 1
    screen.setCursorPos(x, y)
    screen.setTextColor(textColor or colors.white)
    screen.write(text)
end

-- MAIN DISPLAY FUNCTION
local function displayPayouts()
    screen.setTextColor(colors.yellow)
    centerText(1, "Slot Machine Payouts", colors.yellow)

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

displayPayouts()
