-- Poker Tournament Client for GearHallow Casino
-- Save as 'poker_client.lua' on terminal computers (e.g., IDs 391, 393)
-- Requires a disk drive on top and a wired modem on back
-- Reads SERVER_ID and BUYIN from config.txt

-- Load configuration
local function loadConfig()
    local config = {SERVER_ID = 394, BUYIN = 300}
    if fs.exists("config.txt") then
        local file = fs.open("config.txt", "r")
        local content = file.readAll()
        file.close()
        for line in content:gmatch("[^\r\n]+") do
            local key, value = line:match("^(%S+)=(.+)$")
            if key == "SERVER_ID" then
                config.SERVER_ID = tonumber(value) or 394
            elseif key == "BUYIN" then
                config.BUYIN = tonumber(value) or 300
            end
        end
    else
        local file = fs.open("config.txt", "w")
        file.writeLine("SERVER_ID=394")
        file.writeLine("BUYIN=300")
        file.close()
    end
    return config
end

local config = loadConfig()
local SERVER_ID = config.SERVER_ID
local TOURNAMENT_BUYIN = config.BUYIN
local BANK_ID = 395 -- Bank computer ID
local modem = peripheral.wrap("back") or error("No modem found on back side", 0)
local diskDrive = peripheral.wrap("top") or error("No disk drive found on top side", 0)

-- Initialize rednet
modem.open(os.getComputerID())
rednet.open("back")

-- Get and write player name
local function getAndWritePlayerName()
    if not diskDrive.isDiskPresent() then
        return nil, "Please insert your player disk."
    end
    local diskPath = diskDrive.getMountPath()
    if not diskPath then
        return nil, "Failed to access disk."
    end
    local filePath = fs.combine(diskPath, "player.txt")

    term.clear()
    term.setCursorPos(1, 1)
    print("GearHallow Casino Poker Terminal")
    print("Buy-in: " .. TOURNAMENT_BUYIN .. " chips")
    print("Please enter your name (overwrites existing player.txt):")
    local name = io.read()
    if not name or name == "" then
        return nil, "Name cannot be empty."
    end
    local file = fs.open(filePath, "w")
    file.writeLine(name)
    file.close()
    print("Overwrote player.txt with name: " .. name)
    return name
end

-- Register with the server
local function register()
    local name, err = getAndWritePlayerName()
    if not name then
        return false, err
    end

    -- Request buy-in deduction from the bank
    rednet.send(BANK_ID, {type = "deduct", amount = TOURNAMENT_BUYIN, player = name})
    local _, response = rednet.receive(nil, 5) -- 5-second timeout
    if not response or response.type ~= "deduct_response" or not response.success then
        return false, response and response.error or "Failed to communicate with bank."
    end

    -- Register with the server
    rednet.send(SERVER_ID, {type = "register", name = name, success = true})
    return true, "Registration successful. Waiting for game to start..."
end

-- Main client loop
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("GearHallow Casino Poker Terminal")
    print("Buy-in: " .. TOURNAMENT_BUYIN .. " chips")
    print("Insert disk to register...")

    local registered = false
    while true do
        if not registered then
            local success, message = register()
            term.clear()
            term.setCursorPos(1, 1)
            print("GearHallow Casino Poker Terminal")
            print("Buy-in: " .. TOURNAMENT_BUYIN .. " chips")
            if success then
                print(message)
                registered = true
            else
                print("Registration failed: " .. message)
                print("Insert disk to try again, or remove disk to exit.")
                while true do
                    local event, side = os.pullEvent()
                    if event == "disk" and side == "top" then
                        break
                    elseif event == "disk_eject" and side == "top" then
                        term.clear()
                        term.setCursorPos(1, 1)
                        print("Disk removed. Terminal ready for next player.")
                        print("Insert disk to register...")
                        break
                    end
                end
            end
        else
            local _, message = rednet.receive()
            if message.type == "state" then
                term.clear()
                term.setCursorPos(1, 1)
                print("Game State: " .. message.state.game_state)
                print("Community Cards: " .. (#message.state.community_cards > 0 and table.concat(message.state.community_cards, ", ") or "None"))
                print("Your Cards: " .. table.concat(message.your_cards, ", "))
                print("Main Pot: " .. message.state.main_pot)
                for i, pot in ipairs(message.state.side_pots) do
                    print("Side Pot " .. i .. ": " .. pot.amount)
                end
                print("Current Bet: " .. message.state.current_bet)
                print("Blinds: " .. message.state.small_blind .. "/" .. message.state.big_blind)
                for _, player in ipairs(message.state.players) do
                    print(player.name .. ": " .. player.chips .. " chips" .. (player.folded and " (folded)" or "") .. (player.bet > 0 and " (bet " .. player.bet .. ")" or ""))
                end
            elseif message.type == "action" then
                print("Your turn! Options: " .. table.concat(message.options, ", "))
                print("Enter action (fold/call/raise amount):")
                local input = io.read()
                local action, amount = input:match("^(%S+)%s*(%d*)$")
                if action == "raise" then
                    amount = tonumber(amount)
                    if not amount then
                        print("Invalid raise amount.")
                        action = "fold"
                    end
                end
                rednet.send(SERVER_ID, {type = "action", action = action, amount = amount})
            elseif message.type == "message" then
                print(message.text)
            end
        end
    end
end

local success, err = pcall(main)
if not success then
    print("Error: " .. err)
    print("Terminal restarting in 5 seconds...")
    os.sleep(5)
    os.reboot()
end
