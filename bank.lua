-- Bank System for Casino Debit Cards with Server Currency
-- Save as 'bank.lua' on the bank computer

local drive = peripheral.wrap("left") or error("No disk drive found on left side. Please attach a disk drive to the left.", 0)
local monitor = peripheral.wrap("right") -- Monitor on right side (optional)
local conversion_rate = 0.1 -- 1 currency = 0.1 chips (1,000 currency = 100 chips)
local state = "main"
local input = ""
local message = ""

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
        return 0 -- New debit card starts with 0 chips
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

-- Clear monitor or terminal
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

-- Main loop
function main()
    while true do
        clearOutput()
        writeOutput(1, 1, "Casino Bank")
        local balance, err = readBalance()
        if balance then
            writeOutput(1, 2, "Chip Balance: " .. balance)
        else
            writeOutput(1, 2, err or "Error reading balance")
        end
        writeOutput(1, 4, message)

        if state == "main" then
            if monitor then
                drawButton(2, 6, 10, 3, "Buy Chips", colors.green)
                drawButton(14, 6, 10, 3, "Cash Out", colors.blue)
                drawButton(2, 10, 22, 3, "Exit", colors.red)
            else
                writeOutput(1, 6, "[1] Buy Chips")
                writeOutput(1, 7, "[2] Cash Out")
                writeOutput(1, 8, "[3] Exit")
            end
        elseif state == "buy" then
            writeOutput(2, 6, "Currency paid: " .. input)
            if monitor then
                drawButton(2, 8, 5, 2, "100", colors.gray)
                drawButton(8, 8, 5, 2, "1000", colors.gray)
                drawButton(14, 8, 5, 2, "10000", colors.gray)
                drawButton(2, 11, 8, 2, "Confirm", colors.green)
                drawButton(12, 11, 8, 2, "Cancel", colors.red)
            else
                writeOutput(2, 8, "Enter currency paid (or 'cancel'):")
            end
        elseif state == "cash" then
            if balance then
                local currency = math.floor(balance / conversion_rate)
                writeOutput(2, 6, "Chips: " .. balance)
                writeOutput(2, 7, "Pay player: " .. currency .. " currency")
                if monitor then
                    drawButton(2, 9, 10, 3, "Confirm", colors.green)
                    drawButton(14, 9, 10, 3, "Cancel", colors.red)
                else
                    writeOutput(2, 9, "[1] Confirm, [2] Cancel")
                end
            else
                state = "main"
                message = "No disk inserted"
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
                    state = "buy"
                    input = ""
                elseif isClickInButton(param2, param3, 14, 6, 10, 3) then
                    state = "cash"
                elseif isClickInButton(param2, param3, 2, 10, 22, 3) then
                    break
                end
            else
                if param1 == "1" then
                    state = "buy"
                    input = ""
                elseif param1 == "2" then
                    state = "cash"
                elseif param1 == "3" then
                    break
                else
                    message = "Press 1, 2, or 3"
                end
            end
        elseif state == "buy" then
            if monitor then
                if isClickInButton(param2, param3, 2, 8, 5, 2) then
                    input = input .. "100"
                elseif isClickInButton(param2, param3, 8, 8, 5, 2) then
                    input = input .. "1000"
                elseif isClickInButton(param2, param3, 14, 8, 5, 2) then
                    input = input .. "10000"
                elseif isClickInButton(param2, param3, 2, 11, 8, 2) then
                    local currency = tonumber(input)
                    if currency and currency > 0 then
                        local chips = math.floor(currency * conversion_rate)
                        local balance, err = readBalance()
                        if balance then
                            balance = balance + chips
                            if writeBalance(balance) then
                                message = "Added " .. chips .. " chips"
                            else
                                message = "Error writing to disk"
                            end
                        else
                            message = err or "Error reading balance"
                        end
                    else
                        message = "Invalid currency amount"
                    end
                    state = "main"
                    input = ""
                elseif isClickInButton(param2, param3, 12, 11, 8, 2) then
                    state = "main"
                    input = ""
                end
            else
                local line = io.read()
                if line == "cancel" then
                    state = "main"
                    input = ""
                else
                    local currency = tonumber(line)
                    if currency and currency > 0 then
                        local chips = math.floor(currency * conversion_rate)
                        local balance, err = readBalance()
                        if balance then
                            balance = balance + chips
                            if writeBalance(balance) then
                                message = "Added " .. chips .. " chips"
                            else
                                message = "Error writing to disk"
                            end
                        else
                            message = err or "Error reading balance"
                        end
                        state = "main"
                        input = ""
                    else
                        message = "Invalid currency amount"
                    end
                end
            end
        elseif state == "cash" then
            if monitor then
                if isClickInButton(param2, param3, 2, 9, 10, 3) then
                    local balance, err = readBalance()
                    if balance then
                        if writeBalance(0) then
                            local currency = math.floor(balance / conversion_rate)
                            message = "Cashed out " .. balance .. " chips for " .. currency .. " currency"
                        else
                            message = "Error writing to disk"
                        end
                    else
                        message = err or "Error reading balance"
                    end
                    state = "main"
                elseif isClickInButton(param2, param3, 14, 9, 10, 3) then
                    state = "main"
                end
            else
                if param1 == "1" then
                    local balance, err = readBalance()
                    if balance then
                        if writeBalance(0) then
                            local currency = math.floor(balance / conversion_rate)
                            message = "Cashed out " .. balance .. " chips for " .. currency .. " currency"
                        else
                            message = "Error writing to disk"
                        end
                    else
                        message = err or "Error reading balance"
                    end
                    state = "main"
                elseif param1 == "2" then
                    state = "main"
                else
                    message = "Press 1 or 2"
                end
            end
        end
    end
end

main()
