-- Player script for Texas Hold'em
local drive = peripheral.wrap("left") or error("No disk drive found")
local modem = peripheral.find("modem") or error("No modem found")
print("Opening modem: " .. peripheral.getName(modem))
rednet.open("top")  -- Modem on top side
local serverID
local state = "searching"
local hand = {}
local chips = 0
local currentBet = 0
local name = "Unknown"
local diskID
local communityCards = {}
local pots = {}
local currentPlayer
local blinds = {}
local round = ""
local showdown = false

-- Disk functions
function readBalance()
    if not drive.isDiskPresent() then
        print("readBalance: No disk present")
        return nil, "No disk"
    end
    local path = drive.getMountPath()
    if not path then
        print("readBalance: No mount path")
        return nil, "No mount path"
    end
    local filePath = fs.combine(path, "balance.txt")
    if not fs.exists(filePath) then
        print("readBalance: balance.txt not found")
        return nil, "balance.txt not found"
    end
    local file = fs.open(filePath, "r")
    if file then
        local bal = tonumber(file.readLine())
        file.close()
        print("readBalance: Balance read = " .. (bal or "nil"))
        return bal or 0
    end
    print("readBalance: Failed to open file")
    return nil, "Failed to read file"
end

function writeBalance(balance)
    if not drive.isDiskPresent() then
        print("writeBalance: No disk present")
        return false
    end
    local path = drive.getMountPath()
    if not path then
        print("writeBalance: No mount path")
        return false
    end
    local file = fs.open(fs.combine(path, "balance.txt"), "w")
    if file then
        file.write(tostring(balance))
        file.close()
        print("writeBalance: Wrote balance = " .. balance)
        return true
    end
    print("writeBalance: Failed to write file")
    return false
end

function readUsername()
    if not drive.isDiskPresent() then
        print("readUsername: No disk present")
        return "Unknown"
    end
    local path = drive.getMountPath()
    if not path then
        print("readUsername: No mount path")
        return "Unknown"
    end
    local file = fs.open(fs.combine(path, "username.txt"), "r")
    if file then
        local name = file.readLine()
        file.close()
        print("readUsername: Name read = " .. (name or "Unknown"))
        return name or "Unknown"
    end
    print("readUsername: No username.txt, using default")
    return "Unknown"
end

-- Write output to monitor
function writeOutput(x, y, text)
    local monitor = peripheral.find("monitor")
    if monitor then
        monitor.setCursorPos(x, y)
        monitor.write(text)
    end
end

-- Clear output
function clearOutput(color)
    local monitor = peripheral.find("monitor")
    if monitor then
        monitor.clear()
        monitor.setTextScale(0.5)
        monitor.setBackgroundColor(color)
        monitor.setTextColor(colors.white)
    end
end

-- Draw button
function drawButton(x, y, width, height, text, color)
    local monitor = peripheral.find("monitor")
    if monitor then
        monitor.setBackgroundColor(color)
        for i = 0, height - 1 do
            monitor.setCursorPos(x, y + i)
            monitor.write(string.rep(" ", width))
        end
        monitor.setCursorPos(x + math.floor((width - #text) / 2), y + math.floor(height / 2))
        monitor.setTextColor(colors.white)
        monitor.write(text)
    end
end

-- Check button click
function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- Join server with retries
local function joinServer()
    serverID = rednet.lookup("poker", "server")
    if not serverID then
        print("joinServer: Server not found")
        return false
    end
    diskID = drive.getDiskID()
    if not diskID then
        print("joinServer: No diskID")
        return false
    end
    for i = 1, 3 do
        print("Attempt " .. i .. " to join server " .. serverID)
        rednet.send(serverID, {type = "join", diskID = diskID})
        local id, msg = rednet.receive(5)
        if id == serverID and msg and msg.type == "joined" then
            print("joinServer: Success, joined as " .. (msg.name or "Unknown"))
            return true
        elseif id == serverID and msg and msg.type == "error" then
            print("joinServer: Error - " .. (msg.message or "Unknown error"))
            writeOutput(1, 5, "Error: " .. (msg.message or "Unknown"))
            return false
        end
    end
    print("joinServer: Failed after 3 attempts")
    return false
end

-- Handle rednet messages
local function handleRednet()
    while true do
        local senderID, msg = rednet.receive()
        if msg and type(msg) == "table" and senderID == serverID then
            print("Received: " .. (msg.type or "nil"))
            if msg.type == "hand" then
                hand = msg.cards or {}
            elseif msg.type == "state" then
                communityCards = msg.communityCards or {}
                pots = msg.pots or {}
                currentBet = msg.currentBet or 0
                currentPlayer = msg.currentPlayer or 0
                blinds = msg.blinds or {}
                round = msg.round or ""
                showdown = msg.showdown or false
            elseif msg.type == "showdown" then
                showdown = true
            elseif msg.type == "eliminated" then
                state = "eliminated"
            elseif msg.type == "read_balance" then
                local bal, err = readBalance()
                print("Sending read_balance_response: balance=" .. (bal or "nil") .. ", error=" .. (err or "nil"))
                rednet.send(serverID, {type = "read_balance_response", balance = bal, error = err})
            elseif msg.type == "write_balance" then
                local success = writeBalance(msg.data.balance)
                print("Sending write_balance_response: success=" .. tostring(success))
                rednet.send(serverID, {type = "write_balance_response", success = success})
            elseif msg.type == "read_username" then
                local uname = readUsername()
                print("Sending read_username_response: name=" .. uname)
                rednet.send(serverID, {type = "read_username_response", name = uname})
            end
        else
            print("Invalid message from " .. (senderID or "unknown"))
        end
        sleep(0.1)
    end
end

-- Handle monitor updates and touches
local function handleMonitor()
    while true do
        clearOutput(colors.black)
        writeOutput(1, 1, "Texas Hold'em")

        if state == "searching" then
            writeOutput(1, 3, "Searching for server...")
            if not drive.isDiskPresent() then
                writeOutput(1, 5, "Insert a disk")
            else
                local balance, err = readBalance()
                if balance and balance >= 100 then
                    if joinServer() then
                        name = readUsername()
                        chips = 1000
                        local balance = readBalance() or 0
                        writeBalance(balance - 100)  -- Buy-in
                        state = "game"
                        print("Joined as " .. name)
                    end
                else
                    writeOutput(1, 5, "Insufficient chips: " .. (balance or 0) .. "/100")
                end
            end
        elseif state == "game" then
            writeOutput(1, 3, "Player: " .. name .. " | Chips: " .. chips)
            local handStr = "Hand: " .. (hand[1] and (hand[1].rank .. hand[1].suit) or "") .. " " .. (hand[2] and (hand[2].rank .. hand[2].suit) or "")
            writeOutput(1, 4, handStr)
            local commStr = "Community: "
            for _, card in ipairs(communityCards) do commStr = commStr .. (card.rank or "?") .. (card.suit or "?") .. " " end
            writeOutput(1, 6, commStr)
            local potStr = "Pots: "
            for i, pot in ipairs(pots) do potStr = potStr .. (i > 1 and "Side " or "Main ") .. pot.amount .. " " end
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

            local event, param1, param2, param3 = os.pullEvent()
            if event == "monitor_touch" and state == "game" then
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
                        writeOutput(1, 10, "Enter raise amount: ")
                        local amount = tonumber(read())
                        if amount and amount > currentBet then
                            rednet.send(serverID, {type = "action", action = "raise", amount = amount})
                        end
                    elseif isClickInButton(x, y, 14, 14, 10, 3) then
                        rednet.send(serverID, {type = "action", action = "fold"})
                    elseif isClickInButton(x, y, 2, 18, 10, 3) then
                        rednet.send(serverID, {type = "action", action = "allin"})
                    end
                end
            end
        elseif state == "eliminated" then
            writeOutput(1, 3, "Eliminated! Reinsert disk to rejoin.")
        end
        sleep(0.1)
    end
end

-- Main loop
parallel.waitForAny(handleRednet, handleMonitor)
