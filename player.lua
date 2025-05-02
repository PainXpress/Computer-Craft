-- Player script for Texas Hold'em poker game
local modem = peripheral.find("modem") or error("No modem found")
print("Opening modem: " .. peripheral.getName(modem))
rednet.open("top")  -- Modem on top side

local monitor = peripheral.find("monitor")
local disk = peripheral.find("disk")
local diskID = disk and peripheral.getID(disk) or "default"
local state = "searching"
local serverID = nil
local playerName = nil
local chips = 0
local hand = {}
local joining = false

-- Read balance from disk or use default
function readBalance(diskID)
    if disk and disk.isDiskPresent() then
        local balance = fs.open(fs.combine(disk.getMountPath(), "balance.txt"), "r")
        if balance then
            local bal = tonumber(balance.readLine())
            balance.close()
            print("readBalance: Balance read = " .. (bal or "nil"))
            return bal
        end
        return nil, "No balance file"
    end
    print("readBalance: No disk, using default balance = 100")
    return 100  -- Default balance if no disk
end

-- Write balance to disk or ignore if no disk
function writeBalance(diskID, balance)
    if disk and disk.isDiskPresent() then
        local file = fs.open(fs.combine(disk.getMountPath(), "balance.txt"), "w")
        if file then
            file.write(tostring(balance))
            file.close()
            print("writeBalance: Balance written = " .. balance)
            return true
        end
        return false
    end
    print("writeBalance: No disk, balance not saved")
    return false
end

-- Read username from disk or use default
function readUsername(diskID)
    if disk and disk.isDiskPresent() then
        local file = fs.open(fs.combine(disk.getMountPath(), "username.txt"), "r")
        if file then
            local name = file.readLine() or "Unknown"
            file.close()
            print("readUsername: Name read = " .. name)
            return name
        end
        return "Unknown"
    end
    print("readUsername: No disk, using default name = Player")
    return "Player"  -- Default name if no disk
end

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

-- Join server
function joinServer()
    if joining then
        print("Already attempting to join, skipping...")
        return false
    end
    joining = true
    local servers = {rednet.lookup("poker")}
    if #servers == 0 then
        print("No poker servers found")
        joining = false
        return false
    end
    serverID = servers[1]  -- Pick the first server (ID 5680 in this case)
    for attempt = 1, 3 do
        print("Attempt " .. attempt .. " to join server " .. serverID)
        rednet.send(serverID, {type = "join", diskID = diskID})
        local timerID = os.startTimer(5)
        while true do
            local event, param1, param2 = os.pullEvent()
            if event == "rednet_message" then
                local senderID, msg = param1, param2
                if senderID == serverID and msg and type(msg) == "table" then
                    if msg.type == "joined" then
                        playerName = msg.name
                        state = "lobby"
                        print("Joined server successfully as " .. playerName)
                        joining = false
                        return true
                    elseif msg.type == "error" then
                        print("Join error: " .. (msg.message or "Unknown error"))
                        joining = false
                        return false
                    end
                end
            elseif event == "timer" and param1 == timerID then
                break
            end
        end
    end
    print("JoinServer: Failed after 3 attempts")
    joining = false
    return false
end

-- Main loop
function main()
    math.randomseed(os.time())
    while true do
        -- Handle rednet messages
        local senderID, msg = rednet.receive(0.1)
        if msg and type(msg) == "table" then
            print("Received: " .. (msg.type or "nil") .. " from " .. senderID)
            if msg.type == "read_balance" then
                local balance, err = readBalance(msg.data.diskID)
                rednet.send(senderID, {type = "read_balance_response", balance = balance, error = err})
            elseif msg.type == "write_balance" then
                local success = writeBalance(msg.data.diskID, msg.data.balance)
                rednet.send(senderID, {type = "write_balance_response", success = success})
            elseif msg.type == "read_username" then
                local name = readUsername(msg.data.diskID)
                rednet.send(senderID, {type = "read_username_response", name = name})
            elseif msg.type == "joined" and state == "searching" then
                playerName = msg.name
                state = "lobby"
                print("Joined server successfully as " .. playerName)
            elseif msg.type == "error" then
                print("Server error: " .. (msg.message or "Unknown error"))
                state = "searching"
                serverID = nil
            elseif msg.type == "state" and state ~= "searching" then
                state = "game"
                chips = msg.chips or chips
                -- Update game state
                writeOutput(1, 1, "Game State: " .. msg.round)
            elseif msg.type == "hand" then
                hand = msg.cards
                writeOutput(1, 2, "Hand: " .. (hand[1].rank .. hand[1].suit .. " " .. hand[2].rank .. hand[2].suit))
            elseif msg.type == "eliminated" then
                state = "searching"
                serverID = nil
                chips = 0
                hand = {}
                writeOutput(1, 1, "Eliminated! Searching for new game...")
            end
        end

        -- State machine
        if state == "searching" then
            clearOutput(colors.red)
            writeOutput(1, 1, "Searching for poker server...")
            joinServer()
        elseif state == "lobby" then
            clearOutput(colors.yellow)
            writeOutput(1, 1, "In lobby as " .. (playerName or "Unknown"))
        elseif state == "game" then
            clearOutput(colors.black)
            writeOutput(1, 1, "Playing as " .. (playerName or "Unknown") .. " | Chips: " .. chips)
        end

        sleep(0.1)
    end
end

main()
