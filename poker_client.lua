-- Poker Tournament Client for GearHallow Casino
-- Save as 'poker_client.lua' on player terminal computers (e.g., IDs 391, 393)
-- Requires a wired modem on back, advanced monitor on right, disk drive on left
-- Reads SERVER_ID from config.txt
-- Handles buy-in via local disk drive

-- Load configuration
local function loadConfig()
    local config = {SERVER_ID = 394}
    if fs.exists("config.txt") then
        local file = fs.open("config.txt", "r")
        local content = file.readAll()
        file.close()
        for line in content:gmatch("[^\r\n]+") do
            local key, value = line:match("^(%S+)=(.+)$")
            if key == "SERVER_ID" then
                config.SERVER_ID = tonumber(value) or config.SERVER_ID
            end
        end
    else
        local file = fs.open("config.txt", "w")
        file.writeLine("SERVER_ID=394")
        file.close()
    end
    return config
end

local config = loadConfig()
local modem = peripheral.wrap("back") or error("No modem found on back side", 0)
local monitor = peripheral.wrap("right") or error("No monitor found on right side", 0)
local drive = peripheral.wrap("left") or error("No disk drive found on left side", 0)
local SERVER_ID = config.SERVER_ID
local TOURNAMENT_BUYIN = 300 -- Chips required for buy-in
local player_name = nil
local buttons = {} -- {x, y, width, height, label, action}
local raise_amount = 0
local entering_raise = false
local last_cards = {}
local registered = false

-- Initialize rednet and monitor
modem.open(os.getComputerID())
rednet.open("back")
monitor.setTextScale(0.5)
monitor.clear()
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)

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

-- Draw text on monitor
function drawText(x, y, text, fg, bg)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

-- Draw button
function drawButton(x, y, width, height, label, fg, bg)
    drawText(x, y, "+" .. string.rep("-", width - 2) .. "+", fg, bg)
    for i = 1, height - 2 do
        drawText(x, y + i, "|", fg, bg)
        drawText(x + width - 1, y + i, "|", fg, bg)
    end
    drawText(x, y + height - 1, "+" .. string.rep("-", width - 2) .. "+", fg, bg)
    drawText(x + 1, y + math.floor(height / 2), label, fg, bg)
    return {x = x, y = y, width = width, height = height, label = label}
end

-- Check if a point is in a button
function inButton(x, y, button)
    return x >= button.x and x <= button.x + button.width - 1 and
           y >= button.y and y <= button.y + button.height - 1
end

-- Display cards with suit colors
function displayCards(cards)
    term.clear()
    term.setCursorPos(1, 1)
    term.write("Enter your name to view cards: ")
    local input = ""
    term.setCursorBlink(true)
    while true do
        local event, param1 = os.pullEvent()
        if event == "char" then
            input = input .. param1
            term.write(param1)
        elseif event == "key" and param1 == keys.enter then
            if input == player_name or not registered then
                term.clear()
                term.setCursorPos(1, 1)
                term.write("Your Cards: ")
                for i, card in ipairs(cards) do
                    local suit = card:sub(-1)
                    local color = suit == "S" and colors.white or
                                  suit == "D" and colors.cyan or
                                  suit == "C" and colors.green or
                                  suit == "H" and colors.red
                    term.setTextColor(color)
                    term.write(card)
                    if i < #cards then term.write(" ") end
                end
                term.setTextColor(colors.white)
                last_cards = cards
                break
            else
                term.clear()
                term.setCursorPos(1, 1)
                term.write("Incorrect name. Enter your name: ")
                input = ""
            end
        elseif event == "key" and param1 == keys.backspace and #input > 0 then
            input = input:sub(1, -2)
            local x, y = term.getCursorPos()
            term.setCursorPos(x - 1, y)
            term.write(" ")
            term.setCursorPos(x - 1, y)
        end
    end
    term.setCursorBlink(false)
end

-- Display game state
function displayState(state, cards)
    monitor.clear()
    drawText(1, 1, "GearHallow Poker Tournament", colors.yellow, colors.black)
    drawText(1, 3, "Community: ", colors.white, colors.black)
    local x = 12
    for _, card in ipairs(state.community_cards) do
        local suit = card:sub(-1)
        local color = suit == "S" and colors.white or
                      suit == "D" and colors.cyan or
                      suit == "C" and colors.green or
                      suit == "H" and colors.red
        drawText(x, 3, card, color, colors.black)
        x = x + 4
    end
    drawText(1, 5, "Main Pot: " .. state.main_pot, colors.green, colors.black)
    local y = 6
    for i, pot in ipairs(state.side_pots) do
        drawText(1, y, "Side Pot " .. i .. ": " .. pot.amount, colors.green, colors.black)
        y = y + 1
    end
    drawText(1, y, "Current Bet: " .. state.current_bet, colors.red, colors.black)
    y = y + 1
    drawText(1, y, "Blinds: " .. state.small_blind .. "/" .. state.big_blind, colors.white, colors.black)
    y = y + 1
    drawText(1, y, "Phase: " .. state.game_state, colors.white, colors.black)
    y = y + 1
    drawText(1, y, "Current Player: " .. state.current_player, colors.cyan, colors.black)
    y = y + 1
    for _, player in ipairs(state.players) do
        local status = player.active and (player.folded and "Folded" or "Active") or "Eliminated"
        drawText(1, y, player.name .. ": " .. player.chips .. " chips (" .. status .. ")", colors.white, colors.black)
        y = y + 1
    end
    buttons = {}
    if state.current_player == player_name and state.game_state ~= "showdown" then
        table.insert(buttons, drawButton(1, y + 1, 10, 3, "Fold", colors.white, colors.red)) -- Hearts
        table.insert(buttons, drawButton(12, y + 1, 10, 3, "Call", colors.white, colors.green)) -- Clubs
        table.insert(buttons, drawButton(23, y + 1, 10, 3, "Raise", colors.white, colors.cyan)) -- Diamonds
        if entering_raise then
            drawText(1, y + 4, "Raise Amount: " .. raise_amount, colors.white, colors.black) -- Spades
            local x = 1
            for i = 0, 9 do
                table.insert(buttons, drawButton(x, y + 5, 5, 3, tostring(i), colors.white, colors.black)) -- Spades
                x = x + 5
            end
            table.insert(buttons, drawButton(x, y + 5, 8, 3, "Enter", colors.white, colors.green)) -- Clubs
            table.insert(buttons, drawButton(x + 8, y + 5, 8, 3, "Clear", colors.white, colors.red)) -- Hearts
        end
    end
    if #cards > 0 then
        displayCards(cards)
    end
end

-- Main loop
function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("GearHallow Poker Tournament")
    print("Enter your player name: ")
    local input = ""
    term.setCursorBlink(true)
    while true do
        local event, param1 = os.pullEvent()
        if event == "char" then
            input = input .. param1
            term.write(param1)
        elseif event == "key" and param1 == keys.enter then
            player_name = input
            registered = true
            break
        elseif event == "key" and param1 == keys.backspace and #input > 0 then
            input = input:sub(1, -2)
            local x, y = term.getCursorPos()
            term.setCursorPos(x - 1, y)
            term.write(" ")
            term.setCursorPos(x - 1, y)
        end
    end
    term.setCursorBlink(false)
    term.clear()
    term.setCursorPos(1, 1)
    print("Insert floppy disk to register...")
    while not drive.isDiskPresent() do
        os.sleep(1)
    end
    local balance, err = readBalance()
    if balance and balance >= TOURNAMENT_BUYIN then
        balance = balance - TOURNAMENT_BUYIN
        if writeBalance(balance) then
            rednet.send(SERVER_ID, {type = "register", name = player_name, success = true})
        else
            rednet.send(SERVER_ID, {type = "register", name = player_name, success = false, error = "Error writing to disk"})
        end
    else
        rednet.send(SERVER_ID, {type = "register", name = player_name, success = false, error = err or "Insufficient balance"})
    end
    local _, message = rednet.receive(nil, 10)
    if message and message.type == "message" then
        monitor.clear()
        drawText(1, 1, message.text, colors.white, colors.black)
        if message.text:find("Registered") then
            term.clear()
            term.setCursorPos(1, 1)
            print("Registration successful. Waiting for game to start...")
            print("You may remove your floppy disk.")
        else
            term.clear()
            term.setCursorPos(1, 1)
            print(message.text)
            print("Remove disk and visit bank to add chips.")
            return
        end
    else
        monitor.clear()
        drawText(1, 1, "Failed to register. Try again.", colors.red, colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        print("Failed to register. Try again.")
        print("Remove disk and try again.")
        return
    end

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local message = p3
            if message.type == "state" then
                displayState(message.state, message.your_cards)
            elseif message.type == "action" then
                entering_raise = false
                raise_amount = 0
                displayState(message.state, message.your_cards)
            elseif message.type == "message" then
                drawText(1, 19, message.text, colors.green, colors.black)
            end
        elseif event == "monitor_touch" then
            local x, y = p2, p3
            for _, button in ipairs(buttons) do
                if inButton(x, y, button) then
                    if button.label == "Fold" then
                        rednet.send(SERVER_ID, {type = "action", action = "fold"})
                        entering_raise = false
                        raise_amount = 0
                    elseif button.label == "Call" then
                        rednet.send(SERVER_ID, {type = "action", action = "call"})
                        entering_raise = false
                        raise_amount = 0
                    elseif button.label == "Raise" then
                        entering_raise = true
                        raise_amount = 0
                        displayState(message.state, message.your_cards)
                    elseif button.label == "Enter" and entering_raise then
                        rednet.send(SERVER_ID, {type = "action", action = "raise", amount = raise_amount})
                        entering_raise = false
                        raise_amount = 0
                    elseif button.label == "Clear" and entering_raise then
                        raise_amount = 0
                        displayState(message.state, message.your_cards)
                    elseif entering_raise and button.label:match("%d") then
                        raise_amount = raise_amount * 10 + tonumber(button.label)
                        displayState(message.state, message.your_cards)
                    end
                    break
                end
            end
        end
    end
end

pcall(main)
