-- Bank System for GearHallow Casino Debit Cards
-- Save as 'bank.lua' on the bank computer

local drive = peripheral.wrap("left") or error("No disk drive found on left side. Please attach a disk drive to the left.", 0)
local monitor = peripheral.wrap("right") -- Monitor on right side (optional)
local conversion_rate = 0.1 -- 1 currency = 0.1 chips (1,000 currency = 100 chips)
local state = "main"
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

-- Write to monitor
function writeMonitor(x, y, text)
    if monitor then
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
        monitor.setTextColor(colors.white)
    end
end

-- Display welcome screen on monitor
function displayWelcome()
    clearMonitor()
    writeMonitor(1, 1, "Welcome to the GearHallow Casino")
    writeMonitor(1, 3, "Conversion Rate: 1,000 currency = 100 chips")
    writeMonitor(1, 5, "Please insert your floppy disk")
    writeMonitor(1, 6, "into the disk drive.")
end

-- Display transaction result on monitor
function displayResult(chips, isBuy)
    clearMonitor()
    if isBuy then
        writeMonitor(1, 1, "Purchased " .. chips .. " chips")
    else
        local currency = math.floor(chips / conversion_rate)
        writeMonitor(1, 1, "Cashed out " .. chips .. " chips")
        writeMonitor(1, 2, "for " .. currency .. " currency")
    end
    writeMonitor(1, 4, "Please remove your floppy disk")
    writeMonitor(1, 5, "and have fun at the casino!")
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

-- Main loop
function main()
    parallel.waitForAny(
        function() -- Monitor display loop
            while true do
                if state == "main" then
                    displayWelcome()
                end
                os.sleep(0.1)
            end
        end,
        function() -- Terminal interaction loop
            while true do
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
                print("[3] Exit")
                print("Select option (1-3): ")

                local event, param1 = os.pullEvent("char")
                message = ""

                if state == "main" then
                    if param1 == "1" then
                        state = "buy"
                    elseif param1 == "2" then
                        state = "cash"
                    elseif param1 == "3" then
                        clearMonitor()
                        break
                    else
                        message = "Press 1, 2, or 3"
                    end
                end

                if state == "buy" then
                    clearTerminal()
                    print("GearHallow Casino Bank")
                    print("Enter currency paid (or 'cancel'): ")
                    local line = io.read()
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
                end
            end
        end
    )
end

-- Run with termination handling
local ok, err = pcall(main)
if not ok and err ~= "Terminated" then
    printError("Error: " .. err)
    if monitor then
        clearMonitor()
        writeMonitor(1, 1, "Bank System Error")
        writeMonitor(1, 2, "Please contact staff")
    end
end
