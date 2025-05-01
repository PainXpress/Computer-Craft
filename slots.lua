-- Slot Machine for Casino Debit Cards
-- Save as 'slots.lua' on slot machine computer

local drive = peripheral.wrap("left")
if not drive then
    error("No disk drive found. Please connect a disk drive.")
end
local monitor = peripheral.find("monitor")
local symbols = {"7", "Cherry", "Bar", "Bell"}
local payouts = {
    {symbol = "7", count = 3, multiplier = 35},
    {symbol = "Cherry", count = 3, multiplier = 14},
    {symbol = "Bar", count = 3, multiplier = 7},
    {symbol = "Bell", count = 3, multiplier = 3}
}
local state = "main"
local bet = 0
local message = ""
local reels = nil
local win = 0

-- Read balance from disk
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

-- Write balance to disk
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

-- Write to monitor or terminal
function writeOutput(x, y, text)
    if monitor then
        monitor.setCursorPos(x, y)
        monitor.write(text)
    else
        term.setCursorPos(x, y)
        term.write(text)
    end
end

-- Clear monitor or terminal with specified color
function clearOutput(color)
    if monitor then
        monitor.clear()
        monitor.setTextScale(0.5)
        monitor.setBackgroundColor(color)
        monitor.setTextColor(colors.white)
    else
        term.clear()
        term.setBackgroundColor(color)
        term.setTextColor(colors.white)
    end
end

-- Draw button (monitor only)
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

-- Check if click is within button (monitor only)
function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- Spin reels
function spinReels()
    local reels = {}
    for i = 1, 3 do
        reels[i] = symbols[math.random(1, #symbols)]
    end
    return reels
end

-- Calculate win based on reels and bet
function calculateWin(reels, bet)
    for _, payout in ipairs(payouts) do
        if reels[1] == payout.symbol and reels[2] == payout.symbol and reels[3] == payout.symbol then
            return bet * payout.multiplier
        end
    end
    return 0
end

-- Play sound effect
function playSound(sound)
    local success, result = pcall(function()
        commands.exec("playsound " .. sound .. " block @a ~ ~ ~ 1 1")
    end)
    if not success then
        -- Silently fail if commands.exec is disabled or lacks permissions
    end
end

-- Main loop
function main()
    math.randomseed(os.time())
    while true do
        clearOutput(state == "main" and colors.yellow or colors.black)
        writeOutput(1, 1, "Slot Machine")
        local balance, err = readBalance()
        if balance then
            writeOutput(1, 2, "Chip Balance: " .. balance)
        else
            writeOutput(1, 2, err or "Error reading balance")
        end
        writeOutput(1, 4, message)

        if state == "main" then
            if monitor then
                drawButton(2, 6, 10, 3, "Bet 10", colors.green)
                drawButton(14, 6, 10, 3, "Bet 50", colors.blue)
            else
                writeOutput(1, 6, "[1] Bet 10")
                writeOutput(1, 7, "[2] Bet 50")
            end
        elseif state == "spin" then
            writeOutput(2, 6, "Reels: " .. table.concat(reels, " | "))
            writeOutput(2, 7, win > 0 and "Win: " .. win .. " chips!" or "No win")
            if monitor then
                drawButton(2, 9, 22, 3, "Continue", colors.green)
            else
                writeOutput(2, 9, "[1] Continue")
            end
        end

        local eventData = {os.pullEvent()}
        local event, param1, param2, param3 = eventData[1], eventData[2], eventData[3], eventData[4]
        message = ""

        if state == "main" and (event == "monitor_touch" or event == "char") then
            local selectedBet = 0
            if monitor and event == "monitor_touch" then
                if isClickInButton(param2, param3, 2, 6, 10, 3) then
                    selectedBet = 10
                elseif isClickInButton(param2, param3, 14, 6, 10, 3) then
                    selectedBet = 50
                else
                    message = "Click Bet 10 or Bet 50"
                end
            elseif event == "char" then
                if param1 == "1" then
                    selectedBet = 10
                elseif param1 == "2" then
                    selectedBet = 50
                else
                    message = "Press 1 or 2"
                end
            end
            if selectedBet > 0 then
                local balance, err = readBalance()
                if balance and balance >= selectedBet then
                    balance = balance - selectedBet
                    if writeBalance(balance) then
                        bet = selectedBet
                        reels = spinReels()
                        win = calculateWin(reels, bet)
                        if win > 0 then
                            playSound("entity.player.levelup")
                            balance = balance + win
                            writeBalance(balance)
                        else
                            playSound("block.note_block.bass")
                        end
                        state = "spin"
                    else
                        message = "Error writing to disk"
                    end
                else
                    message = err or "Insufficient chips"
                end
            end
        elseif state == "spin" and (event == "monitor_touch" or event == "char") then
            local continueClicked = false
            if monitor and event == "monitor_touch" then
                if isClickInButton(param2, param3, 2, 9, 22, 3) then
                    continueClicked = true
                end
            elseif event == "char" and param1 == "1" then
                continueClicked = true
            end
            if continueClicked then
                state = "main"
                bet = 0
                reels = nil
                win = 0
            else
                message = monitor and "Click Continue to play again" or "Press 1 to continue"
            end
        end
    end
end

main()
