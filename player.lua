-- Player script for Texas Hold'em on Advanced Computer
-- Save as 'player.lua' on each player's computer

local drive = peripheral.wrap("left")
if not drive then
    error("No disk drive found. Please connect a disk drive.")
end
local monitor = peripheral.find("monitor")
if not monitor then
    error("No monitor found. Please connect a 2x2 monitor.")
end
local modem = peripheral.find("modem")
if not modem then
    error("No wireless modem found. Please attach a modem.")
end
print("Opening modem: " .. peripheral.getName(modem))
rednet.open(peripheral.getName(modem))
local serverID = nil
local playerName = "Unknown"
local balance = 0
local hand = {}
local communityCards = {}
local pots = {{amount = 0, eligible = {}}}
local currentBet = 0
local blinds = {small = 10, big = 20}
local round = "preflop"
local message = ""
local state = "lobby"
local myID = os.getComputerID()
local currentPlayer = nil
local showdown = false

-- Read balance from disk
function readBalance(diskID)
    if not drive.isDiskPresent() or drive.getDiskID() ~= diskID then
        return nil necesitamos un disco válido insertado
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

-- Read username from disk
function readUsername(diskID)
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

-- Write output to monitor
function writeOutput(x, y, text)
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

-- Clear output with color
function clearOutput(color)
    monitor.clear()
    monitor.setTextScale(0.5)
    monitor.setBackgroundColor(color)
    monitor.setTextColor(colors.white)
end

-- Draw button
function drawButton(x, y, width, height, text, color)
    monitor.setBackgroundColor(color)
    for i = 0, height - 1 do
        monitor.setCursorPos(x, y + i)
        monitor.write(string.rep(" ", width))
    end
    monitor.setCursorPos(x + math.floor((width - #text) / 2), y + math.floor(height / 2))
    monitor.setTextColor(colors.white)
    monitor.write(text)
end

-- Check click in button
function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- Main loop
function main()
    rednet.host("poker", "player" .. myID)
    local diskID = drive.isDiskPresent() and drive.getDiskID() or nil
    if diskID then
        playerName = readUsername(diskID)
        balance = readBalance(diskID) or 0
    else
        print("No disk inserted")
    end
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    while true do
        clearOutput(state == "lobby" and colors.yellow or colors.black)
        writeOutput(1, 1, "Texas Hold'em - " .. playerName)
        writeOutput(1, 2, "Balance: " .. balance .. " chips")
        writeOutput(1, 4, message)

        if state == "lobby" then
            writeOutput(1, 6, "Searching for server...")
            if not serverID then
                print("Looking up server...")
                serverID = rednet.lookup("poker", "server")
                print("Server ID: " .. (serverID or "nil"))
                if serverID and diskID then
                    print("Sending join to server " .. serverID)
                    rednet.send(serverID, {type = "join", diskID = diskID})
                elseif not diskID then
                    message = "Please insert a disk"
                end
            end
        elseif state == "game" then
            -- Display hole cards on terminal
            term.clear()
            term.setCursorPos(1, 1)
            local handStr = "Your Hand: "
            for _, card in ipairs(hand) do
                handStr = handStr .. card.rank .. card.suit .. " "
            end
            term.write(handStr)
            -- Display public info on monitor
            local commStr = "Community: "
            for _, card in ipairs(communityCards) do
                commStr = commStr .. card.rank .. card.suit .. " "
            end
            writeOutput(2, 6, commStr)
            local potStr = "Pots: "
            for i, pot in ipairs(pots) do
                potStr = potStr .. (i > 1 and "Side " or "Main ") .. pot.amount .. " "
            end
            writeOutput(2, 7, potStr)
            writeOutput(2, 8, "Bet: " .. currentBet)
            writeOutput(2, 9, "Blinds: " .. blinds.small .. "/" .. blinds.big)
            writeOutput(2, 10, "Round: " .. round)

            if currentPlayer == myID then
                if showdown then
                    drawButton(2, 12, 10, 3, "Muck", colors.red)
                    drawButton(14, 12, 10, 3, "Show", colors.white)
                else
                    drawButton(2, 12, 6, 3, "Check", colors.green)
                    drawButton(9, 12, 6, 3, "Call", colors.blue)
                    drawButton(16, 12, 6, 3, "Raise", colors.yellow)
                    drawButton(2, 16, 6, 3, "Fold", colors.red)
                    drawButton(16, 16, 6, 3, "All-in", colors.orange)
                end
            else
                writeOutput(2, 12, "Waiting for other players...")
            end
        end

        local eventData = {os.pullEvent()}
        local event, param1, param2, param3 = eventData[1], eventData[2], eventData[3], eventData[4]
        message = ""

        if event == "rednet_message" then
            local senderID, msg = param1, param2
            print("Received message: " .. msg.type .. " from " .. senderID)
            if msg.type == "joined" then
                state = "game"
                playerName = msg.name
                message = "Joined game!"
            elseif msg.type == "error" then
                message = msg.message
                serverID = nil
                state = "lobby"
            elseif msg.type == "hand" then
                hand = msg.cards
            elseif msg.type == "state" then
                communityCards = msg.communityCards
                pots = msg.pots
                currentBet = msg.currentBet
                currentPlayer = msg.currentPlayer
                blinds = msg.blinds
                round = msg.round
                showdown = msg.showdown
            elseif msg.type == "showdown" then
                showdown = true
            elseif msg.type == "eliminated" then
                state = "lobby"
                serverID = nil
                message = "You were eliminated!"
            end
        elseif event == "monitor_touch" and currentPlayer == myID then
            local x, y = param2, param3
            if state == "game" then
                if showdown then
                    if isClickInButton(x, y, 2, 12, 10, 3) then
                        rednet.send(serverID, {type = "showdown_choice", choice = "muck"})
                        message = "Cards mucked"
                    elseif isClickInButton(x, y, 14, 12, 10, 3) then
                        rednet.send(serverID, {type = "showdown_choice", choice = "show"})
                        message = "Cards shown"
                    end
                else
                    if isClickInButton(x, y, 2, 12, 6, 3) and currentBet == 0 then
                        rednet.send(serverID, {type = "action", action = "check"})
                        message = "Checked"
                    elseif isClickInButton(x, y, 9, 12, 6, 3) then
                        rednet.send(serverID, {type = "action", action = "call"})
                        message = "Called"
                    elseif isClickInButton(x, y, 16, 12, 6, 3) then
                        writeOutput(2, 15, "Enter raise amount: ")
                        term.setBackgroundColor(colors.black)
                        term.setCursorPos(1, 3)
                        term.write("Raise amount: ")
                        local input = read()
                        local amount = tonumber(input)
                        if amount and amount > currentBet then
                            rednet.send(serverID, {type = "action", action = "raise", amount = amount})
                            message = "Raised to " .. amount
                        else
                            message = "Invalid raise amount"
                        end
                    elseif isClickInButton(x, y, 2, 16, 6, 3) then
                        rednet.send(serverID, {type = "action", action = "fold"})
                        message = "Folded"
                    elseif isClickInButton(x, y, 16, 16, 6, 3) then
                        rednet.send(serverID, {type = "action", action = "allin"})
                        message = "All-in!"
                    end
                end
            end
        end
    end
end

main()
