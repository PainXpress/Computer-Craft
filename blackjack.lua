-- Blackjack for Casino Debit Cards
-- Save as 'blackjack.lua' on blackjack computer

local drive = peripheral.wrap("left")
if not drive then
    error("No disk drive found. Please connect a disk drive.")
end
local monitor = peripheral.find("monitor")
local state = "main"
local message = ""
local playerChips = 0
local bet = 0
local playerHands = {{cards = {}, active = true}} -- Support for splits
local dealerHand = {}
local deck = {}
local currentHand = 1

-- Card setup
local suits = {"H", "D", "C", "S"} -- Hearts, Diamonds, Clubs, Spades
local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}

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

-- Write to monitor or terminal
function writeOutput(x, y, text)
    if monitor then
        monitor.setCursorPos(x, y)
        monitor.write(text)
    else
        term.setCursorPos(x, y)
        term.write(text)
    end
end

-- Clear monitor or terminal with specified color
function clearOutput(color)
    if monitor then
        monitor.clear()
        monitor.setTextScale(0.5)
        monitor.setBackgroundColor(color)
        monitor.setTextColor(colors.white)
    else
        term.clear()
        term.setBackgroundColor(color)
        term.setTextColor(colors.white)
    end
end

-- Draw button (monitor only)
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

-- Check if click is within button (monitor only)
function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
end

-- Play sound effect
function playSound(sound)
    local success, result = pcall(function()
        commands.exec("playsound " .. sound .. " block @a ~ ~ ~ 1 1")
    end)
    if not success then
        -- Silently fail if commands.exec is disabled
    end
end

-- Initialize deck
function initDeck()
    deck = {}
    for _, suit in ipairs(suits) do
        for _, rank in ipairs(ranks) do
            table.insert(deck, {rank = rank, suit = suit})
        end
    end
end

-- Shuffle deck
function shuffleDeck()
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

-- Get card value
function cardValue(card)
    if card.rank == "A" then return 11 end
    if card.rank == "J" or card.rank == "Q" or card.rank == "K" then return 10 end
    return tonumber(card.rank) or 10
end

-- Calculate hand value
function handValue(hand)
    local value = 0
    local aces = 0
    for _, card in ipairs(hand) do
        if card.rank == "A" then
            aces = aces + 1
        else
            value = value + cardValue(card)
        end
    end
    for i = 1, aces do
        if value + 11 <= 21 then
            value = value + 11
        else
            value = value + 1
        end
    end
    return value
end

-- Check if hand is blackjack
function isBlackjack(hand)
    return #hand == 2 and handValue(hand) == 21
end

-- Dealer play (hit on 16 or less, stand on 17+)
function dealerPlay()
    while handValue(dealerHand) <= 16 do
        table.insert(dealerHand, table.remove(deck))
    end
end

-- Main loop
function main()
    math.randomseed(os.time())
    while true do
        local balance, err = readBalance()
        playerChips = balance or 0
        clearOutput(state == "main" and colors.yellow or colors.black)
        writeOutput(1, 1, "Blackjack")
        if balance then
            writeOutput(1, 2, "Your Chips: " .. playerChips)
        else
            writeOutput(1, 2, err or "Error reading balance")
            state = "main"
        end
        writeOutput(1, 4, message)

        if state == "main" then
            if playerChips < 10 then
                writeOutput(1, 6, "Need at least 10 chips")
            else
                if monitor then
                    drawButton(2, 6, 10, 3, "Bet 10", colors.green)
                    drawButton(14, 6, 10, 3, "Bet 50", colors.blue)
                else
                    writeOutput(1, 6, "[1] Bet 10")
                    writeOutput(1, 7, "[2] Bet 50")
                end
            end
        elseif state == "play" then
            local handStr = "Your Hand: "
            for _, card in ipairs(playerHands[currentHand].cards) do
                handStr = handStr .. card.rank .. card.suit .. " "
            end
            writeOutput(2, 6, handStr .. "(" .. handValue(playerHands[currentHand].cards) .. ")")
            writeOutput(2, 7, "Dealer: " .. dealerHand[1].rank .. dealerHand[1].suit .. " ?")
            writeOutput(2, 8, "Bet: " .. bet)
            if monitor then
                drawButton(2, 10, 6, 2, "Hit", colors.green)
                drawButton(10, 10, 6, 2, "Stand", colors.blue)
                if playerChips >= bet and #playerHands[currentHand].cards == 2 then
                    drawButton(18, 10, 6, 2, "Double", colors.yellow)
                end
                if #playerHands[currentHand].cards == 2 and playerChips >= bet and
                   cardValue(playerHands[currentHand].cards[1]) == cardValue(playerHands[currentHand].cards[2]) then
                    drawButton(26, 10, 6, 2, "Split", colors.red)
                end
            else
                local options = "[1] Hit  [2] Stand"
                if playerChips >= bet and #playerHands[currentHand].cards == 2 then
                    options = options .. "  [3] Double"
                end
                if #playerHands[currentHand].cards == 2 and playerChips >= bet and
                   cardValue(playerHands[currentHand].cards[1]) == cardValue(playerHands[currentHand].cards[2]) then
                    options = options .. "  [4] Split"
                end
                writeOutput(2, 10, options)
            end
        elseif state == "result" then
            local handStr = "Your Hand: "
            for _, card in ipairs(playerHands[currentHand].cards) do
                handStr = handStr .. card.rank .. card.suit .. " "
            end
            writeOutput(2, 6, handStr .. "(" .. handValue(playerHands[currentHand].cards) .. ")")
            local dealerStr = "Dealer: "
            for _, card in ipairs(dealerHand) do
                dealerStr = dealerStr .. card.rank .. card.suit .. " "
            end
            writeOutput(2, 7, dealerStr .. "(" .. handValue(dealerHand) .. ")")
            writeOutput(2, 8, "Result: " .. message)
            if monitor then
                drawButton(2, 10, 22, 3, "Next Hand", colors.green)
            else
                writeOutput(2, 10, "[1] Next Hand")
            end
        end

        local eventData = {os.pullEvent()}
        local event, param1, param2, param3 = eventData[1], eventData[2], eventData[3], eventData[4]
        message = ""

        if state == "main" and playerChips >= 10 then
            local selectedBet = 0
            if monitor and event == "monitor_touch" then
                if isClickInButton(param2, param3, 2, 6, 10, 3) then
                    selectedBet = 10
                elseif isClickInButton(param2, param3, 14, 6, 10, 3) then
                    selectedBet = 50
                else
                    message = "Click Bet 10 or Bet 50"
                end
            elseif event == "char" then
                if param1 == "1" then
                    selectedBet = 10
                elseif param1 == "2" then
                    selectedBet = 50
                else
                    message = "Press 1 or 2"
                end
            end
            if selectedBet > 0 then
                playerChips = playerChips - selectedBet
                if writeBalance(playerChips) then
                    bet = selectedBet
                    initDeck()
                    shuffleDeck()
                    playerHands = {{cards = {table.remove(deck), table.remove(deck)}, active = true}}
                    dealerHand = {table.remove(deck), table.remove(deck)}
                    currentHand = 1
                    playSound("block.note_block.hat")
                    if isBlackjack(playerHands[1].cards) then
                        state = "result"
                        local payout = math.floor(bet * 1.5)
                        playerChips = playerChips + bet + payout
                        writeBalance(playerChips)
                        message = "Blackjack! You win " .. payout .. " chips!"
                        playSound("entity.player.levelup")
                    elseif isBlackjack(dealerHand) then
                        state = "result"
                        message = "Dealer Blackjack! You lose."
                        playSound("block.note_block.bass")
                    else
                        state = "play"
                    end
                else
                    message = "Error writing to disk"
                end
            end
        elseif state == "play" and (event == "monitor_touch" or event == "char") then
            local action = nil
            if monitor then
                if isClickInButton(param2, param3, 2, 10, 6, 2) then
                    action = "hit"
                elseif isClickInButton(param2, param3, 10, 10, 6, 2) then
                    action = "stand"
                elseif isClickInButton(param2, param3, 18, 10, 6, 2) and playerChips >= bet and #playerHands[currentHand].cards == 2 then
                    action = "double"
                elseif isClickInButton(param2, param3, 26, 10, 6, 2) and #playerHands[currentHand].cards == 2 and playerChips >= bet and
                       cardValue(playerHands[currentHand].cards[1]) == cardValue(playerHands[currentHand].cards[2]) then
                    action = "split"
                else
                    message = "Click Hit, Stand, Double, or Split"
                end
            else
                if param1 == "1" then
                    action = "hit"
                elseif param1 == "2" then
                    action = "stand"
                elseif param1 == "3" and playerChips >= bet and #playerHands[currentHand].cards == 2 then
                    action = "double"
                elseif param1 == "4" and #playerHands[currentHand].cards == 2 and playerChips >= bet and
                       cardValue(playerHands[currentHand].cards[1]) == cardValue(playerHands[currentHand].cards[2]) then
                    action = "split"
                else
                    message = "Press 1, 2, 3, or 4"
                end
            end
            if action == "hit" then
                table.insert(playerHands[currentHand].cards, table.remove(deck))
                playSound("block.note_block.hat")
                if handValue(playerHands[currentHand].cards) > 21 then
                    playerHands[currentHand].active = false
                    if currentHand == #playerHands then
                        state = "result"
                        message = "Bust! You lose."
                        playSound("block.note_block.bass")
                    else
                        currentHand = currentHand + 1
                    end
                end
            elseif action == "stand" then
                playerHands[currentHand].active = false
                if currentHand == #playerHands then
                    dealerPlay()
                    state = "result"
                    local playerValue = handValue(playerHands[currentHand].cards)
                    local dealerValue = handValue(dealerHand)
                    if dealerValue > 21 or playerValue > dealerValue then
                        local payout = bet
                        playerChips = playerChips + bet + payout
                        writeBalance(playerChips)
                        message = "You win " .. payout .. " chips!"
                        playSound("entity.player.levelup")
                    elseif playerValue == dealerValue then
                        playerChips = playerChips + bet
                        writeBalance(playerChips)
                        message = "Push! Bet returned."
                        playSound("block.note_block.hat")
                    else
                        message = "Dealer wins!"
                        playSound("block.note_block.bass")
                    end
                else
                    currentHand = currentHand + 1
                end
                playSound("block.note_block.hat")
            elseif action == "double" then
                playerChips = playerChips - bet
                bet = bet * 2
                writeBalance(playerChips)
                table.insert(playerHands[currentHand].cards, table.remove(deck))
                playSound("block.note_block.hat")
                if handValue(playerHands[currentHand].cards) > 21 then
                    playerHands[currentHand].active = false
                    if currentHand == #playerHands then
                        state = "result"
                        message = "Bust! You lose."
                        playSound("block.note_block.bass")
                    else
                        currentHand = currentHand + 1
                    end
                else
                    playerHands[currentHand].active = false
                    if currentHand == #playerHands then
                        dealerPlay()
                        state = "result"
                        local playerValue = handValue(playerHands[currentHand].cards)
                        local dealerValue = handValue(dealerHand)
                        if dealerValue > 21 or playerValue > dealerValue then
                            local payout = bet
                            playerChips = playerChips + bet + payout
                            writeBalance(playerChips)
                            message = "You win " .. payout .. " chips!"
                            playSound("entity.player.levelup")
                        elseif playerValue == dealerValue then
                            playerChips = playerChips + bet
                            writeBalance(playerChips)
                            message = "Push! Bet returned."
                            playSound("block.note_block.hat")
                        else
                            message = "Dealer wins!"
                            playSound("block.note_block.bass")
                        end
                    else
                        currentHand = currentHand + 1
                    end
                end
            elseif action == "split" then
                playerChips = playerChips - bet
                writeBalance(playerChips)
                local newHand = {cards = {playerHands[currentHand].cards[2]}, active = true}
                playerHands[currentHand].cards[2] = table.remove(deck)
                table.insert(playerHands, newHand)
                table.insert(newHand.cards, table.remove(deck))
                playSound("block.note_block.hat")
                if handValue(playerHands[currentHand].cards) > 21 then
                    playerHands[currentHand].active = false
                    currentHand = currentHand + 1
                end
            end
        elseif state == "result" and (event == "monitor_touch" or event == "char") then
            local nextHand = false
            if monitor and event == "monitor_touch" and isClickInButton(param2, param3, 2, 10, 22, 3) then
                nextHand = true
            elseif event == "char" and param1 == "1" then
                nextHand = true
            end
            if nextHand then
                state = "main"
                bet = 0
                playerHands = {{cards = {}, active = true}}
                dealerHand = {}
                currentHand = 1
            else
                message = monitor and "Click Next Hand" or "Press 1 for next hand"
            end
        end
    end
end

main()
