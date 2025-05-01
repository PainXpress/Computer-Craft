-- Player script for Texas Hold'em on Advanced Computer
-- Save as 'player.lua' on each player's computer

local drive = peripheral.wrap("left")
if not drive then
    error("No disk drive found. Please connect a disk drive.")
end
local monitor = peripheral.find("monitor")
local modem = peripheral.find("modem")
if not modem then
    error("No wireless modem found. Please connect a modem.")
end
print("Opening modem: " .. peripheral.getName(modem))
rednet.open(peripheral.getName(modem))
local serverID
local state = "searching"
local hand = {}
local chips = 0
local currentBet = 0
local name = "Unknown"
local diskID
local balance = 0
local buyIn = 100
local communityCards = {}
local pots = {}
local currentPlayer
local blinds = {}
local round = ""
local showdown = false

-- Write output to monitor
function writeOutput(x, y, text)
    if monitor then
        monitor.setCursorPos(x, y)
        monitor.write(text)
    end
end

-- Clear output with color
function clearOutput(color)
    if monitor then
        monitor.clear()
        monitor.setTextScale(0.5)
        monitor.setBackgroundColor(color)
        monitor.setTextColor(colors.white)
    end
end

-- Draw button
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

-- Check if click is in button
function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- Read balance from disk
function readBalance()
    if not drive.isDiskPresent() or drive.getDiskID() ~= diskID then
        return nil, "Invalid or no disk inserted"
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
function writeBalance(newBalance)
    if not drive.isDiskPresent() or drive.getDiskID() ~= diskID then
        return false, "Invalid or no disk inserted"
    end
    local path = drive.getMountPath()
    local file = fs.open(fs.combine(path, "balance.txt"), "w")
    file.write(tostring(newBalance))
    file.close()
    return true
end

-- Read username from disk
function readUsername()
    if not drive.isDiskPresent() or drive.getDiskID() ~= diskID then
        return "Unknown"
    end
    local path = drive.getMountPath()
    if fs.exists(fs.combine(path, "username.txt")) then
        local file = fs.open(fs.combine(path, "username.txt"), "r")
        local name = file.readLine()
        file.close()
        return name or "Unknown"
    else
        return "Unknown"
    end
end

-- Main loop
function main()
    while true do
        clearOutput(colors.black)
        writeOutput(1, 1, "Texas Hold'em")

        if state == "searching" then
            writeOutput(1, 3, "Searching for server...")
            if not drive.isDiskPresent() then
                writeOutput(1, 5, "Please insert a disk")
            else
                diskID = drive.getDiskID()
                balance = readBalance()
                if not balance or balance < buyIn then
                    writeOutput(1, 5, "Insufficient chips: " .. (balance or 0) .. "/" .. buyIn)
                else
                    print("Looking up server...")
                    serverID = rednet.lookup("poker", "server")
                    if serverID then
                        print("Server ID: " .. serverID)
                        print("Sending join to server " .. serverID)
                        rednet.send(serverID, {type = "join", diskID = diskID})
                    end
                end
            end
        elseif state == "game" then
            writeOutput(1, 3, "Player: " .. name .. " | Chips: " .. chips)
            writeOutput(1, 4, "Balance: " .. balance .. " chips")
            local commStr = "Community: "
            for _, card in ipairs(communityCards) do
                commStr = commStr .. card.rank .. card.suit .. " "
            end
            writeOutput(1, 6, commStr)
            local potStr = "Pots: "
            for i, pot in ipairs(pots) do
                potStr = potStr .. (i > 1 and "Side " or "Main ") .. pot.amount .. " "
            end
            writeOutput(1, 7, potStr)
            writeOutput(1, 8, "Current Bet: " .. currentBet)
            if showdown then
                drawButton(2, 10, 10, 3, "Muck", colors.red)
                drawButton(14, 10, 10, 3, "Show", colors.green)
            elseif currentPlayer == os.getComputerID() then
                drawButton(2, 10, 10, 3, "Check", currentBet == 0 and colors.green or colors.gray)
                drawButton(14, 10, 10, 3, "Call", currentBet > 0 and colors.green or colors.gray)
                drawButton(2, 14, 10, 3, "Raise", colors.green)
                drawButton(14, 14, 10, 3, "Fold", colors.red)
                drawButton(2, 18, 10, 3, "All-in", colors.orange)
            end
        elseif state == "eliminated" then
            writeOutput(1, 3, "Eliminated! Insert disk to rejoin.")
        end

        local eventData = {os.pullEvent()}
        local event, param1, param2, param3 = eventData[1], eventData[2], eventData[3], eventData[4]

        if event == "rednet_message" then
            local senderID, msg = param1, param2
            print("Received message: " .. (msg.type or "nil") .. " from " .. senderID)
            if msg.type == "joined" and state == "searching" then
                state = "game"
                name = msg.name
                chips = 1000
                balance = balance - buyIn
                writeBalance(balance)
                print("Joined game as " .. name)
            elseif msg.type == "error" and state == "searching" then
                writeOutput(1, 5, "Error: " .. msg.message)
            elseif msg.type == "hand" and state == "game" then
                hand = msg.cards
                term.clear()
                term.setCursorPos(1, 1)
                print("Your Hand: " .. hand[1].rank .. hand[1].suit .. " " .. hand[2].rank .. hand[2].suit)
            elseif msg.type == "state" and state == "game" then
                communityCards = msg.communityCards
                pots = msg.pots
                currentBet = msg.currentBet
                currentPlayer = msg.currentPlayer
                blinds = msg.blinds
                round = msg.round
                showdown = msg.showdown
            elseif msg.type == "showdown" and state == "game" then
                showdown = true
            elseif msg.type == "eliminated" and state == "game" then
                state = "eliminated"
                chips = 0
            elseif msg.type == "read_balance" then
                print("Received read_balance request for diskID " .. (msg.diskID or "nil"))
                if msg.diskID == diskID then
                    local bal, err = readBalance()
                    print("Sending balance_response: balance=" .. (bal or "nil") .. ", error=" .. (err or "nil"))
                    rednet.send(senderID, {type = "balance_response", balance = bal, error = err})
                else
                    print("DiskID mismatch: expected " .. diskID .. ", got " .. (msg.diskID or "nil"))
                end
            elseif msg.type == "write_balance" and msg.diskID == diskID then
                local success, err = writeBalance(msg.balance)
                rednet.send(senderID, {type = "write_response", success = success, error = err})
            elseif msg.type == "read_username" and msg.diskID == diskID then
                local username = readUsername()
                rednet.send(senderID, {type = "username_response", name = username})
            elseif msg.type == "pong" then
                print("Received pong from server")
            end
        elseif event == "monitor_touch" and state == "game" then
            local x, y = param2, param3
            if showdown then
                if isClickInButton(x, y, 2, 10, 10, 3) then
                    rednet.send(serverID, {type = "showdown_choice", choice = "muck"})
                elseif isClickInButton(x, y, 14, 10, 10, 3) then
                    rednet.send(serverID, {type = "showdown_choice", choice = "show"})
                end
            elseif currentPlayer == os.getComputerID() then
                if isClickInButton(x, y, 2, 10, 10, 3) and currentBet == 0 then
                    rednet.send(serverID, {type = "action", action = "check"})
                elseif isClickInButton(x, y, 14, 10, 10, 3) and currentBet > 0 then
                    rednet.send(serverID, {type = "action", action = "call"})
                elseif isClickInButton(x, y, 2, 14, 10, 3) then
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Enter raise amount: ")
                    local amount = tonumber(read())
                    if amount and amount > currentBet then
                        rednet.send(serverID, {type = "action", action = "raise", amount = amount})
                    end
                    term.clear()
                    term.setCursorPos(1, 1)
                    print("Your Hand: " .. hand[1].rank .. hand[1].suit .. " " .. hand[2].rank .. hand[2].suit)
                elseif isClickInButton(x, y, 14, 14, 10, 3) then
                    rednet.send(serverID, {type = "action", action = "fold"})
                elseif isClickInButton(x, y, 2, 18, 10, 3) then
                    rednet.send(serverID, {type = "action", action = "allin"})
                end
            end
        end
    end
end

main()
