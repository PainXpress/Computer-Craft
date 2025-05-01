-- Bank System for GearHallow Casino Debit Cards
-- Save as 'bank.lua' on the bank computer

local drive = peripheral.wrap("left") or error("No disk drive found on left side. Please attach a disk drive to the left.", 0)
local monitor = peripheral.wrap("right") -- Monitor on right side (optional)
local conversion_rate = 0.1 -- 1 currency = 0.1 chips (1,000 currency = 100 chips)
local state = "locked"
local message = ""
local password = "casino123" -- Change this to your desired password
local inactivity_timeout = 120 -- 2 minutes in seconds
local last_input_time = os.clock()

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

-- Write to monitor with color
function writeMonitor(x, y, text, fgColor, bgColor)
    if monitor then
        monitor.setTextColor(fgColor or colors.white)
        monitor.setBackgroundColor(bgColor or colors.black)
        monitor.setCursorPos(x, y)
        monitor.write(text)
    end
end

-- Clear monitor
function clearMonitor()
    if monitor then
        monitor.clear()
        monitor.setTextScale(0.5)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.yellow)
    end
end

-- Draw border
function drawBorder(x, y, width, height, fgColor, bgColor)
    if not monitor then return end
    local horizontal = string.rep("-", width - 2)
    writeMonitor(x, y, "+" .. horizontal .. "+", fgColor, bgColor)
    for i = 1, height - 2 do
        writeMonitor(x, y + i, "|", fgColor, bgColor)
        writeMonitor(x + width - 1, y + i, "|", fgColor, bgColor)
    end
    writeMonitor(x, y + height - 1, "+" .. horizontal .. "+", fgColor, bgColor)
end

-- Center text
function centerText(text, width)
    local padding = math.floor((width - #text) / 2)
    return string.rep(" ", padding) .. text .. string.rep(" ", width - #text - padding)
end

-- Display welcome screen on monitor
function displayWelcome()
    clearMonitor()
    local width = 28
    drawBorder(1, 1, width, 10, colors.yellow, colors.black)
    writeMonitor(2, 2, centerText("GearHallow Casino", width - 2), colors.yellow, colors.black)
    writeMonitor(2, 4, centerText("Conversion: 1,000 = 100 chips", width - 2), colors.lime, colors.black)
    writeMonitor(2, 6, "Insert floppy disk to view", colors.white, colors.black)
    writeMonitor(2, 7, "balance and transact.", colors.white, colors.black)
    local balance, err = readBalance()
    if balance then
        writeMonitor(2, 9, centerText("Balance: " .. balance .. " chips", width - 2), colors.green, colors.black)
    else
        writeMonitor(2, 9, centerText("No disk inserted", width - 2), colors.red, colors.black)
    end
end

-- Display transaction result on monitor
function displayResult(chips, isBuy)
    clearMonitor()
    local width = 28
    drawBorder(1, 1, width, 8, colors.yellow, colors.black)
    if isBuy then
        writeMonitor(2, 2, centerText("Purchased " .. chips .. " chips", width - 2), colors.green, colors.black)
    else
        local currency = math.floor(chips / conversion_rate)
        writeMonitor(2, 2, centerText("Cashed out " .. chips .. " chips", width - 2), colors.green, colors.black)
        writeMonitor(2, 3, centerText("for " .. currency .. " currency", width - 2), colors.green, colors.black)
    end
    writeMonitor(2, 5, centerText("Please remove your floppy disk", width - 2), colors.white, colors.black)
    writeMonitor(2, 6, centerText("and have fun at the casino!", width - 2), colors.white, colors.black)
    sleep(5) -- Show for 5 seconds
    displayWelcome()
end

-- Clear terminal
function clearTerminal()
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

-- Get hidden password input
function getPassword()
    clearTerminal()
    print("GearHallow Casino Bank")
    print("Enter password: ")
    local input = ""
    term.setCursorBlink(true)
    while true do
        local event, param1 = os.pullEvent()
        if event == "char" then
            input = input .. param1
            term.write("*")
            last_input_time = os.clock()
        elseif event == "key" and param1 == keys.enter then
            term.setCursorBlink(false)
            return input
        elseif event == "key" and param1 == keys.backspace and #input > 0 then
            input = input:sub(1, -2)
            local x, y = term.getCursorPos()
            term.setCursorPos(x - 1, y)
            term.write(" ")
            term.setCursorPos(x - 1, y)
            last_input_time = os.clock()
        end
    end
end

-- Check password
function checkPassword()
    local input = getPassword()
    if input == password then
        return true
    else
        clearTerminal()
        print("GearHallow Casino Bank")
        print("Incorrect password")
        print("Press any key to retry...")
        os.pullEvent("char")
        return false
    end
end

-- Main loop
function main()
    while true do
        if state == "locked" then
            displayWelcome()
            if checkPassword() then
                state = "main"
                last_input_time = os.clock()
            end
        else
            parallel.waitForAny(
                function() -- Monitor display loop
                    while state ~= "locked" do
                        if state == "main" then
                            displayWelcome()
                        end
                        os.sleep(0.1)
                    end
                end,
                function() -- Terminal interaction loop
                    local timer_id = os.startTimer(inactivity_timeout)
                    while state ~= "locked" do
                        clearTerminal()
                        print("GearHallow Casino Bank")
                        local balance, err = readBalance()
                        if balance then
                            print("Chip Balance: " .. balance)
                        else
                            print(err or "Error reading balance")
                        end
                        if message ~= "" then
                            print(message)
                        end
                        print("")
                        print("[1] Buy Chips")
                        print("[2] Cash Out")
                        print("[3] Check Balance")
                        print("[4] Exit")
                        print("[5] Lock")
                        print("Select option (1-5): ")

                        local event, param1, param2, param3 = os.pullEvent()
                        message = ""
                        last_input_time = os.clock()
                        os.cancelTimer(timer_id)
                        timer_id = os.startTimer(inactivity_timeout)

                        if event == "timer" and param1 == timer_id then
                            state = "locked"
                            break
                        elseif event == "char" and state == "main" then
                            if param1 == "1" then
                                state = "buy"
                            elseif param1 == "2" then
                                state = "cash"
                            elseif param1 == "3" then
                                state = "check"
                            elseif param1 == "4" then
                                clearMonitor()
                                error("Terminated", 0)
                            elseif param1 == "5" then
                                state = "locked"
                                break
                            else
                                message = "Press 1, 2, 3, 4, or 5"
                            end
                        end

                        if state == "buy" then
                            clearTerminal()
                            print("GearHallow Casino Bank")
                            print("Enter currency paid (or 'cancel'): ")
                            local line = io.read()
                            last_input_time = os.clock()
                            os.cancelTimer(timer_id)
                            timer_id = os.startTimer(inactivity_timeout)
                            if line == "cancel" then
                                state = "main"
                            else
                                local currency = tonumber(line)
                                if currency and currency > 0 then
                                    local chips = math.floor(currency * conversion_rate)
                                    local balance, err = readBalance()
                                    if balance then
                                        balance = balance + chips
                                        if writeBalance(balance) then
                                            message = "Added " .. chips .. " chips"
                                            if monitor then
                                                displayResult(chips, true)
                                            end
                                        else
                                            message = "Error writing to disk"
                                        end
                                    else
                                        message = err or "Error reading balance"
                                    end
                                    state = "main"
                                else
                                    message = "Invalid currency amount"
                                    state = "main"
                                end
                            end
                        elseif state == "cash" then
                            clearTerminal()
                            print("GearHallow Casino Bank")
                            local balance, err = readBalance()
                            if balance then
                                local currency = math.floor(balance / conversion_rate)
                                print("Chips: " .. balance)
                                print("Pay player: " .. currency .. " currency")
                                print("[1] Confirm, [2] Cancel")
                                local event, param1 = os.pullEvent("char")
                                last_input_time = os.clock()
                                os.cancelTimer(timer_id)
                                timer_id = os.startTimer(inactivity_timeout)
                                if param1 == "1" then
                                    if writeBalance(0) then
                                        message = "Cashed out " .. balance .. " chips for " .. currency .. " currency"
                                        if monitor then
                                            displayResult(balance, false)
                                        end
                                    else
                                        message = "Error writing to disk"
                                    end
                                    state = "main"
                                elseif param1 == "2" then
                                    state = "main"
                                else
                                    message = "Press 1 or 2"
                                end
                            else
                                message = err or "Error reading balance"
                                state = "main"
                            end
                        elseif state == "check" then
                            clearTerminal()
                            print("GearHallow Casino Bank")
                            local balance, err = readBalance()
                            if balance then
                                print("Balance: " .. balance .. " chips")
                            else
                                print(err or "Error reading balance")
                            end
                            print("Press any key to continue...")
                            os.pullEvent("char")
                            last_input_time = os.clock()
                            os.cancelTimer(timer_id)
                            timer_id = os.startTimer(inactivity_timeout)
                            state = "main"
                        end
                    end
                end
            )
        end
    end
end

-- Run with termination handling
local ok, err = pcall(main)
if not ok and err ~= "Terminated" then
    printError("Error: " .. err)
    if monitor then
        clearMonitor()
        writeMonitor(1, 1, "Bank System Error", colors.red, colors.black)
        writeMonitor(1, 2, "Please contact staff", colors.white, colors.black)
    end
end
