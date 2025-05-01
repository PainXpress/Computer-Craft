-- Player script for Texas Hold'em
-- Save as 'player.lua' on Advanced Pocket Computers

local drive = peripheral.wrap("left")
if not drive then
    error("No disk drive found. Please connect a disk drive.")
end
local modem = peripheral.find("modem")
if not modem then
    error("No wireless modem found. Please connect a modem.")
end
rednet.open(peripheral.getName(modem))
local state = "join"
local serverID = nil
local playerHand = {}
local communityCards = {}
local pots = {{amount = 0, eligible = {}}}
local currentBet = 0
local chips = 0
local blinds = {small = 0, big = 0}
local round = ""
local message = ""
local playerName = ""
local isTurn = false
local showdown = false

-- Write output to pocket computer
function writeOutput(x, y, text)
    term.setCursorPos(x, y)
    term.write(text)
end

-- Clear output with color
function clearOutput(color)
    term.clear()
    term.setBackgroundColor(color)
    term.setTextColor(colors.white)
end

-- Draw button
function drawButton(x, y, width, height, text, color)
    term.setBackgroundColor(color)
    for i = 0, height - 1 do
        term.setCursorPos(x, y + i)
        term.write(string.rep(" ", width))
    end
    term.setCursorPos(x + math.floor((width - #text) / 2), y + math.floor(height / 2))
    term.setTextColor(colors.white)
    term.write(text)
end

-- Check click in button
function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- Play sound
function playSound(sound)
    local success, result = pcall(function()
        commands.exec("playsound " .. sound .. " block @a ~ ~ ~ 1 1")
    end)
end

-- Main loop
function main()
    clearOutput(colors.yellow)
    writeOutput(1, 1, "Texas Hold'em")
    writeOutput(1, 2, "Searching for server...")
    for _, id in ipairs(rednet.lookup("poker")) do
        serverID = id
        break
    end
    if not serverID then
        error("No poker server found")
    end
    local diskID = drive.getDiskID()
    if not diskID then
        error("No disk inserted")
    end
    rednet.send(serverID, {type = "join", diskID = diskID})
    while true do
        clearOutput(state == "join" and colors.yellow or colors.black)
        writeOutput(1, 1, "Texas Hold'em")
        writeOutput(1, 2, "Player: " .. playerName .. " | Chips: " .. chips)
        writeOutput(1, 3, message)

        if state == "join" then
            writeOutput(1, 5, "Waiting to join...")
        elseif state == "game" then
            local handStr = "Your Hand: "
            for _, card in ipairs(playerHand) do
                handStr = handStr .. card.rank .. card.suit .. " "
            end
            writeOutput(2, 5, handStr)
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
            if showdown then
                writeOutput(2, 12, "Showdown!")
                drawButton(2, 14, 6, 2, "Muck", colors.red)
                drawButton(10, 14, 6, 2, "Show", colors.white)
            elseif isTurn then
                drawButton(2, 12, 6, 2, "Check", colors.green)
                drawButton(10, 12, 6, 2, "Call", colors.blue)
                drawButton(18, 12, 6, 2, "Raise", colors.yellow)
                drawButton(2, 14, 6, 2, "Fold", colors.red)
                drawButton(10, 14, 6, 2, "All-in", colors.orange)
            else
                writeOutput(2, 12, "Waiting for your turn...")
            end
        elseif state == "eliminated" then
            writeOutput(2, 5, "You have been eliminated!")
            writeOutput(2, 7, "Please return pocket computer.")
        end

        local eventData = {os.pullEvent()}
        local event, param1, param2, param3 = eventData[1], eventData[2], eventData[3], eventData[4]
        message = ""

        if event == "rednet_message" and param1 == serverID then
            local msg = param2
            if msg.type == "joined" then
                state = "game"
                playerName = msg.name
                chips = 1000 -- Starting chips
                message = "Joined game!"
                playSound("block.note_block.hat")
            elseif msg.type == "error" then
                message = msg.message
            elseif msg.type == "hand" then
                playerHand = msg.cards
            elseif msg.type == "state" then
                communityCards = msg.communityCards
                pots = msg.pots
                currentBet = msg.currentBet
                blinds = msg.blinds
                round = msg.round
                showdown = msg.showdown
                isTurn = msg.currentPlayer == os.computerID() and not msg.showdown
            elseif msg.type == "showdown" then
                showdown = true
            elseif msg.type == "eliminated" then
                state = "eliminated"
                message = "You are out of chips!"
                playSound("block.note_block.bass")
            end
        elseif state == "game" and isTurn and event == "mouse_click" and not showdown then
            if isClickInButton(param2, param3, 2, 12, 6, 2) and currentBet == 0 then
                rednet.send(serverID, {type = "action", action = "check"})
                isTurn = false
                playSound("block.note_block.hat")
            elseif isClickInButton(param2, param3, 10, 12, 6, 2) then
                rednet.send(serverID, {type = "action", action = "call"})
                isTurn = false
                playSound("block.note_block.hat")
            elseif isClickInButton(param2, param3, 18, 12, 6, 2) then
                -- Prompt for raise amount
                clearOutput(colors.black)
                writeOutput(1, 1, "Enter raise amount (min " .. (currentBet + 1) .. "):")
                local input = read()
                local amount = tonumber(input)
                if amount and amount > currentBet and amount <= chips then
                    rednet.send(serverID, {type = "action", action = "raise", amount = amount})
                    isTurn = false
                    playSound("block.note_block.hat")
                else
                    message = "Invalid raise amount"
                end
            elseif isClickInButton(param2, param3, 2, 14, 6, 2) then
                rednet.send(serverID, {type = "action", action = "fold"})
                isTurn = false
                playSound("block.note_block.bass")
            elseif isClickInButton(param2, param3, 10, 14, 6, 2) then
                rednet.send(serverID, {type = "action", action = "allin"})
                isTurn = false
                playSound("block.note_block.hat")
            end
        elseif state == "game" and showdown and event == "mouse_click" then
            if isClickInButton(param2, param3, 2, 14, 6, 2) then
                rednet.send(serverID, {type = "showdown_choice", choice = "muck"})
                showdown = false
                message = "Cards mucked"
                playSound("block.note_block.hat")
            elseif isClickInButton(param2, param3, 10, 14, 6, 2) then
                rednet.send(serverID, {type = "showdown_choice", choice = "show"})
                showdown = false
                message = "Cards shown"
                playSound("block.note_block.hat")
            end
        end
    end
end

main()
