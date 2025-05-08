-- Poker Tournament Client for GearHallow Casino
-- Save as 'poker_client.lua' on player terminal computers (e.g., IDs 391, 393)
-- Requires a wired modem on back and an advanced monitor on right
-- Reads SERVER_ID from config.txt

local modem = peripheral.wrap("back") or error("No modem found on back side", 0)
local monitor = peripheral.wrap("right") or error("No monitor found on right side", 0)
local SERVER_ID = nil
local player_name = nil
local buttons = {} -- {x, y, width, height, label, action}
local raise_amount = 0
local entering_raise = false
local last_cards = {}
local registered = false

-- Load server ID from config.txt
local config_file = fs.open("config.txt", "r")
if config_file then
    SERVER_ID = tonumber(config_file.readLine())
    config_file.close()
else
    error("config.txt not found or invalid", 0)
end

-- Initialize rednet and monitor
modem.open(os.getComputerID())
rednet.open("back")
monitor.setTextScale(0.5)
monitor.clear()
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)

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

-- Display cards with suit colors on terminal
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
                    local color
                    if suit == "D" then
                        color = colors.cyan
                    elseif suit == "H" then
                        color = colors.red
                    elseif suit == "C" then
                        color = colors.green
                    else -- Spades (S)
                        color = colors.white
                    end
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

-- Display game state with colored cards on monitor
function displayState(state, cards)
    local success, err = pcall(function()
        monitor.clear()
        drawText(1, 1, "GearHallow Poker Tournament", colors.yellow, colors.black)
        drawText(1, 3, "Community: ", colors.white, colors.black)
        local x = 12
        for _, card in ipairs(state.community_cards) do
            local suit = card:sub(-1)
            local color
            if suit == "D" then
                color = colors.cyan
            elseif suit == "H" then
                color = colors.red
            elseif suit == "C" then
                color = colors.green
            else -- Spades (S)
                color = colors.white
            end
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
            table.insert(buttons, drawButton(1, y + 1, 10, 3, "Fold", colors.white, colors.red))
            table.insert(buttons, drawButton(12, y + 1, 10, 3, "Call", colors.white, colors.green))
            table.insert(buttons, drawButton(23, y + 1, 10, 3, "Raise", colors.white, colors.cyan))
            if entering_raise then
                drawText(1, y + 4, "Raise Amount: " .. raise_amount, colors.white, colors.black)
                local x = 1
                for i = 0, 9 do
                    table.insert(buttons, drawButton(x, y + 5, 5, 3, tostring(i), colors.white, colors.black))
                    x = x + 5
                end
                table.insert(buttons, drawButton(x, y + 5, 8, 3, "Enter", colors.white, colors.green))
                table.insert(buttons, drawButton(x + 8, y + 5, 8, 3, "Clear", colors.white, colors.red))
            end
        end
        if #cards > 0 then
            displayCards(cards)
        end
    end)
    if not success then
        print("Error in displayState: " .. err)
    end
end

-- Main loop with error handling
function main()
    local success, err = pcall(function()
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
        rednet.send(SERVER_ID, {type = "register", name = player_name})
        local _, message = rednet.receive(nil, 10)
        if message and message.type == "message" then
            monitor.clear()
            drawText(1, 1, message.text, colors.white, colors.black)
            if message.text:find("Registered") then
                term.clear()
                term.setCursorPos(1, 1)
                print("Registration successful. Waiting for game to start...")
            else
                term.clear()
                term.setCursorPos(1, 1)
                print(message.text)
                return
            end
        else
            monitor.clear()
            drawText(1, 1, "Failed to register. Try again.", colors.red, colors.black)
            term.clear()
            term.setCursorPos(1, 1)
            print("Failed to register. Try again.")
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
    end)
    if not success then
        print("Error in main loop: " .. err)
    end
end

main()
