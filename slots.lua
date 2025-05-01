-- Slot Machine for Casino
-- Save as 'slots.lua' on slot machine computer

local drive = peripheral.wrap("right")
local monitor = peripheral.find("monitor")
local symbols = {"7", "Cherry", "Bar", "Bell"}
local payouts = { -- {symbol, count, multiplier}
    {"7", 3, 50}, {"Cherry", 3, 20}, {"Bar", 3, 10}, {"Bell", 3, 5}
}
local state = "main"
local bet = 0
local input = ""
local message = ""

function readBalance()
    if not drive.isDiskPresent() then
        return nil, "No disk inserted"
    end
    local path = drive.getMountPath()
    if fs.exists(fs.combine(path, "balance.txt")) then
        local file = fs.open(fs.combine(path, "balance.txt"), "r")
        local balance = tonumber(file.readLine())
        file.close()
        return balance
    else
        return 0
    end
end

function writeBalance(balance)
    if not drive.isDiskPresent() then
        return false, "No disk inserted"
    end
    local path = drive.getMountPath()
    local file = fs.open(fs.combine(path, "balance.txt"), "w")
    file.write(tostring(balance))
    file.close()
    return true
end

function writeOutput(x, y, text)
    if monitor then
        monitor.setCursorPos(x, y)
        monitor.write(text)
    else
        term.setCursorPos(x, y)
        term.write(text)
    end
end

function clearOutput()
    if monitor then
        monitor.clear()
        monitor.setTextScale(0.5)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
    else
        term.clear()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end
end

function drawButton(x, y, width, height, text, color)
    if not monitor then return end
    monitor.setBackgroundColor(color)
    for i = 0, height - 1 do
        monitor.setCursorPos(x, y + i)
        monitor.write(string.rep(" ", width))
    end
    monitor.setCursorPos(x + math.floor((width - #text) / 2), y + math.floor(height / 2))
    monitor.setTextColor(colors.white)
    monitor.write(text)
end

function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

function spinReels()
    local reels = {}
    for i = 1, 3 do
        reels[i] = symbols[math.random(1, #symbols)]
    end
    return reels
end

function calculateWin(reels, bet)
    for _, payout in ipairs(payouts) do
        local symbol, count, multiplier = payout[1], payout[2], payout[3]
        if reels[1] == symbol and reels[2] == symbol and reels[3] == symbol then
            return bet * multiplier
        end
    end
    return 0
end

function main()
    math.randomseed(os.time())
    while true do
        clearOutput()
        writeOutput(1, 1, "Slot Machine")
        local balance, err = readBalance()
        if balance then
            writeOutput(1, 2, "Chips: " .. balance)
        else
            writeOutput(1, 2, err or "Error reading balance")
        end
        writeOutput(1, 4, message)

        if state == "main" then
            if monitor then
                drawButton(2, 6, 10, 3, "Bet 10", colors.green)
                drawButton(14, 6, 10, 3, "Bet 50", colors.blue)
                drawButton(2, 10, 22, 3, "Exit", colors.red)
            else
                writeOutput(1, 6, "[1] Bet 10")
                writeOutput(1, 7, "[2] Bet 50")
                writeOutput(1, 8, "[3] Exit")
            end
        elseif state == "spin" then
            local reels = spinReels()
            writeOutput(2, 6, "Reels: " .. table.concat(reels, " | "))
            local win = calculateWin(reels, bet)
            if win > 0 then
                writeOutput(2, 7, "Win: " .. win .. " chips!")
                balance = balance + win
                if not writeBalance(balance) then
                    message = "Error writing to disk"
                end
            else
                writeOutput(2, 7, "No win")
            end
            if monitor then
                drawButton(2, 9, 22, 3, "Continue", colors.green)
            else
                writeOutput(2, 9, "[1] Continue")
            end
        end

        local event, param1, param2, param3
        if monitor then
            event, param1, param2, param3 = os.pullEvent("monitor_touch")
        else
            event, param1 = os.pullEvent("char")
        end
        message = ""

        if state == "main" then
            if monitor then
                if isClickInButton(param2, param3, 2, 6, 10, 3) then
                    bet = 10
                elseif isClickInButton(param2, param3, 14, 6, 10, 3) then
                    bet = 50
                elseif isClickInButton(param2, param3, 2, 10, 22, 3) then
                    break
                end
            else
                if param1 == "1" then
                    bet = 10
                elseif param1 == "2" then
                    bet = 50
                elseif param1 == "3" then
                    break
                else
                    message = "Press 1, 2, or 3"
                end
            end
            if bet > 0 then
                local balance, err = readBalance()
                if balance and balance >= bet then
                    balance = balance - bet
                    if writeBalance(balance) then
                        state = "spin"
                    else
                        message = "Error writing to disk"
                    end
                else
                    message = err or "Insufficient chips"
                    bet = 0
                end
            end
        elseif state == "spin" then
            if monitor then
                if isClickInButton(param2, param3, 2, 9, 22, 3) then
                    state = "main"
                    bet = 0
                end
            else
                if param1 == "1" then
                    state = "main"
                    bet = 0
                else
                    message = "Press 1 to continue"
                end
            end
        end
    end
end

main()
