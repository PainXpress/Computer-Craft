-- Poker (Texas Hold'em) for Casino Debit Cards
-- Save as 'poker.lua' on main computer

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
local state = "lobby"
local players = {} -- {id, name, chips, diskID, hand, active, betThisRound, showCards}
local deck = {}
local communityCards = {}
local pots = {{amount = 0, eligible = {}}} -- Main pot and side pots
local currentBet = 0
local blinds = {small = 10, big = 20}
local dealerPos = 1
local currentPlayer = 1
local round = "preflop"
local message = ""
local buyIn = 100
local startingChips = 1000
local suits = {"H", "D", "C", "S"}
local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
local showdown = false
local showdownResponses = {} -- {playerID, choice: "muck" or "show"}

-- Read balance from disk
function readBalance(diskID)
    if not drive.isDiskPresent() or drive.getDiskID() ~= diskID then
        print("readBalance failed: Invalid or no disk for diskID " .. (diskID or "nil"))
        return nil, "Invalid or no disk inserted"
    end
    local path = drive.getMountPath()
    if fs.exists(fs.combine(path, "balance.txt")) then
        local file = fs.open(fs.combine(path, "balance.txt"), "r")
        local balance = tonumber(file.readLine())
        file.close()
        print("readBalance: DiskID " .. diskID .. " has balance " .. balance)
        return balance
    else
        print("readBalance: No balance.txt for diskID " .. diskID)
        return 0
    end
end

-- Write balance to disk
function writeBalance(diskID, balance)
    if not drive.isDiskPresent() or drive.getDiskID() ~= diskID then
        print("writeBalance failed: Invalid or no disk for diskID " .. (diskID or "nil"))
        return false, "Invalid or no disk inserted"
    end
    local path = drive.getMountPath()
    local file = fs.open(fs.combine(path, "balance.txt"), "w")
    file.write(tostring(balance))
    file.close()
    print("writeBalance: Wrote " .. balance .. " to diskID " .. diskID)
    return true
end

-- Read username from disk
function readUsername(diskID)
    if not drive.isDiskPresent() or drive.getDiskID() ~= diskID then
        print("readUsername: No disk for diskID " .. (diskID or "nil"))
        return "Unknown"
    end
    local path = drive.getMountPath()
    if fs.exists(fs.combine(path, "username.txt")) then
        local file = fs.open(fs.combine(path, "username.txt"), "r")
        local name = file.readLine()
        file.close()
        print("readUsername: DiskID " .. diskID .. " has name " .. (name or "Unknown"))
        return name or "Unknown"
    else
        print("readUsername: No username.txt for diskID " .. diskID)
        return "Unknown"
    end
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

-- Play sound
function playSound(sound)
    local success, result = pcall(function()
        commands.exec("playsound " .. sound .. " block @a ~ ~ ~ 1 1")
    end)
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

-- Deal cards
function dealCards()
    for _, player in ipairs(players) do
        if player.active then
            player.hand = {table.remove(deck), table.remove(deck)}
            rednet.send(player.id, {type = "hand", cards = player.hand})
        end
    end
end

-- Evaluate hand (full Texas Hold'em ranking)
function evaluateHand(player)
    local cards = {}
    for _, card in ipairs(player.hand) do
        table.insert(cards, card)
    end
    for _, card in ipairs(communityCards) do
        table.insert(cards, card)
    end
    local function cardValue(card)
        return card.rank == "A" and 14 or card.rank == "K" and 13 or card.rank == "Q" and 12 or card.rank == "J" and 11 or tonumber(card.rank) or 10
    end
    table.sort(cards, function(a, b) return cardValue(a) > cardValue(b) end)
    local suits = {}
    local ranks = {}
    for _, card in ipairs(cards) do
        suits[card.suit] = (suits[card.suit] or 0) + 1
        ranks[cardValue(card)] = (ranks[cardValue(card)] or 0) + 1
    end
    local isFlush = false
    local flushSuit
    for suit, count in pairs(suits) do
        if count >= 5 then
            isFlush = true
            flushSuit = suit
        end
    end
    local isStraight = false
    local highCard = 0
    for i = 14, 5, -1 do
        if ranks[i] and ranks[i-1] and ranks[i-2] and ranks[i-3] and ranks[i-4] then
            isStraight = true
            highCard = i
            break
        end
    end
    if ranks[14] and ranks[2] and ranks[3] and ranks[4] and ranks[5] then
        isStraight = true
        highCard = 5
    end
    if isFlush and isStraight then
        local flushCards = {}
        for _, card in ipairs(cards) do
            if card.suit == flushSuit then
                table.insert(flushCards, cardValue(card))
            end
        end
        table.sort(flushCards, function(a, b) return a > b end)
        for i = 1, #flushCards - 4 do
            if flushCards[i] == flushCards[i+4] + 4 then
                return {rank = 9, value = flushCards[i]} -- Straight Flush
            end
        end
    end
    local quads = 0
    local quadValue = 0
    for rank, count in pairs(ranks) do
        if count == 4 then
            quads = rank
            quadValue = rank
        end
    end
    if quads > 0 then
        for rank, count in pairs(ranks) do
            if count >= 1 and rank ~= quads then
                return {rank = 8, value = quadValue} -- Four of a Kind
            end
        end
    end
    local trips = 0
    local pair = 0
    for rank, count in pairs(ranks) do
        if count == 3 then
            trips = rank
        elseif count == 2 then
            pair = rank
        end
    end
    if trips > 0 and pair > 0 then
        return {rank = 7, value = trips} -- Full House
    end
    if isFlush then
        local flushCards = {}
        for _, card in ipairs(cards) do
            if card.suit == flushSuit then
                table.insert(flushCards, cardValue(card))
            end
        end
        table.sort(flushCards, function(a, b) return a > b end)
        return {rank = 6, value = flushCards[1]} -- Flush
    end
    if isStraight then
        return {rank = 5, value = highCard} -- Straight
    end
    if trips > 0 then
        return {rank = 4, value = trips} -- Three of a Kind
    end
    local pairs = {}
    for rank, count in pairs(ranks) do
        if count == 2 then
            table.insert(pairs, rank)
        end
    end
    if #pairs >= 2 then
        table.sort(pairs, function(a, b) return a > b end)
        return {rank = 3, value = pairs[1]} -- Two Pair
    end
    if #pairs == 1 then
        return {rank = 2, value = pairs[1]} -- One Pair
    end
    local highCards = {}
    for _, card in ipairs(cards) do
        table.insert(highCards, cardValue(card))
    end
    table.sort(highCards, function(a, b) return a > b end)
    return {rank = 1, value = highCards[1]} -- High Card
end

-- Compare hands
function compareHands(hand1, hand2)
    if hand1.rank ~= hand2.rank then
        return hand1.rank > hand2.rank and 1 or -1
    end
    return hand1.value > hand2.value and 1 or hand1.value < hand2.value and -1 or 0
end

-- Create side pots
function createSidePots()
    pots = {{amount = 0, eligible = {}}}
    local bets = {}
    for _, player in ipairs(players) do
        if player.active then
            bets[player.id] = player.betThisRound or 0
        end
    end
    local sortedBets = {}
    for id, bet in pairs(bets) do
        table.insert(sortedBets, bet)
    end
    table.sort(sortedBets)
    sortedBets = {table.unpack(sortedBets, 1, #sortedBets)} -- Remove duplicates
    for i, bet in ipairs(sortedBets) do
        if bet > 0 then
            local pot = {amount = 0, eligible = {}}
            for _, player in ipairs(players) do
                if player.active and (player.betThisRound or 0) >= bet then
                    table.insert(pot.eligible, player.id)
                    pot.amount = pot.amount + (i == 1 and bet or bet - sortedBets[i-1])
                end
            end
            if pot.amount > 0 then
                table.insert(pots, pot)
            end
        end
    end
end

-- Broadcast game state
function broadcastState()
    local stateData = {
        type = "state",
        communityCards = communityCards,
        pots = pots,
        currentBet = currentBet,
        currentPlayer = players[currentPlayer].id,
        blinds = blinds,
        round = round,
        showdown = showdown
    }
    for _, player in ipairs(players) do
        if player.active then
            rednet.send(player.id, stateData)
        end
    end
end

-- Main loop
function main()
    math.randomseed(os.time())
    rednet.host("poker", "server")
    print("Hosting poker server on ID " .. os.getComputerID())
    while true do
        clearOutput(state == "lobby" and colors.yellow or colors.black)
        writeOutput(1, 1, "Texas Hold'em")
        writeOutput(1, 2, "Players: " .. #players .. " | Blinds: " .. blinds.small .. "/" .. blinds.big)
        writeOutput(1, 4, message)

        if state == "lobby" then
            writeOutput(1, 6, "Waiting for players (Buy-in: " .. buyIn .. " chips)")
            if #players >= 2 then
                drawButton(2, 8, 10, 3, "Start", colors.green)
            end
        elseif state == "game" then
            local playerStr = ""
            for i, player in ipairs(players) do
                playerStr = playerStr .. player.name .. ": " .. player.chips .. " chips\n"
            end
            writeOutput(2, 6, playerStr)
            local commStr = "Community: "
            for _, card in ipairs(communityCards) do
                commStr = commStr .. card.rank .. card.suit .. " "
            end
            writeOutput(2, 10, commStr)
            local potStr = "Pots: "
            for i, pot in ipairs(pots) do
                potStr = potStr .. (i > 1 and "Side " or "Main ") .. pot.amount .. " "
            end
            writeOutput(2, 11, potStr)
            writeOutput(2, 12, "Bet: " .. currentBet)
            if showdown then
                local showdownStr = "Showdown: "
                for id, choice in pairs(showdownResponses) do
                    for _, player in ipairs(players) do
                        if player.id == id then
                            showdownStr = showdownStr .. player.name .. ": "
                            if choice == "show" then
                                showdownStr = showdownStr .. player.hand[1].rank .. player.hand[1].suit .. " " .. player.hand[2].rank .. player.hand[2].suit
                            else
                                showdownStr = showdownStr .. "Mucked"
                            end
                            showdownStr = showdownStr .. " | "
                        end
                    end
                end
                writeOutput(2, 13, showdownStr)
            else
                writeOutput(2, 13, "Turn: " .. players[currentPlayer].name)
            end
        end

        local eventData = {os.pullEvent()}
        local event, param1, param2, param3 = eventData[1], eventData[2], eventData[3], eventData[4]
        message = ""

        if event REN "rednet_message" then
            local senderID, msg = param1, param2
            print("Received message: " .. msg.type .. " from " .. senderID)
            if msg.type == "join" and state == "lobby" then
                print("Processing join for player ID " .. senderID .. ", diskID " .. (msg.diskID or "nil"))
                local balance, err = readBalance(msg.diskID)
                if balance and balance >= buyIn then
                    balance = balance - buyIn
                    if writeBalance(msg.diskID, balance) then
                        table.insert(players, {
                            id = senderID,
                            name = readUsername(msg.diskID),
                            chips = startingChips,
                            diskID = msg.diskID,
                            hand = {},
                            active = true,
                            betThisRound = 0,
                            showCards = false
                        })
                        rednet.send(senderID, {type = "joined", name = readUsername(msg.diskID)})
                        message = "Player " .. readUsername(msg.diskID) .. " joined!"
                        print("Join successful for " .. readUsername(msg.diskID) .. ", sent joined message")
                        playSound("block.note_block.hat")
                    else
                        rednet.send(senderID, {type = "error", message = "Error writing to disk"})
                        print("Join failed: Error writing to disk for diskID " .. (msg.diskID or "nil"))
                    end
                else
                    rednet.send(senderID, {type = "error", message = err or "Insufficient chips"})
                    print("Join failed: " .. (err or "Insufficient chips") .. " for diskID " .. (msg.diskID or "nil"))
                end
            elseif msg.type == "action" and state == "game" and senderID == players[currentPlayer].id and not showdown then
                local player = players[currentPlayer]
                if msg.action == "fold" then
                    player.active = false
                    playSound("block.note_block.bass")
                elseif msg.action == "check" and player.betThisRound == currentBet then
                    playSound("block.note_block.hat")
                elseif msg.action == "call" and player.chips >= currentBet - (player.betThisRound or 0) then
                    local bet = currentBet - (player.betThisRound or 0)
                    player.chips = player.chips - bet
                    player.betThisRound = (player.betThisRound or 0) + bet
                    playSound("block.note_block.hat")
                elseif msg.action == "raise" and player.chips >= msg.amount - (player.betThisRound or 0) and msg.amount > currentBet then
                    local bet = msg.amount - (player.betThisRound or 0)
                    player.chips = player.chips - bet
                    player.betThisRound = (player.betThisRound or 0) + bet
                    currentBet = msg.amount
                    playSound("block.note_block.hat")
                elseif msg.action == "allin" and player.chips > 0 then
                    local bet = player.chips
                    player.chips = 0
                    player.betThisRound = (player.betThisRound or 0) + bet
                    if player.betThisRound > currentBet then
                        currentBet = player.betThisRound
                    end
                    playSound("block.note_block.hat")
                else
                    rednet.send(senderID, {type = "error", message = "Invalid action"})
                    message = "Invalid action by " .. player.name
                    print("Invalid action by player ID " .. senderID)
                end
                -- Move to next player
                currentPlayer = currentPlayer % #players + 1
                while not players[currentPlayer].active or players[currentPlayer].chips == 0 do
                    currentPlayer = currentPlayer % #players + 1
                end
                broadcastState()
                -- Check if betting round is over
                local activePlayers = 0
                local matchedBets = 0
                for _, p in ipairs(players) do
                    if p.active and p.chips > 0 then
                        activePlayers = activePlayers + 1
                        if p.betThisRound == currentBet or p.chips == 0 then
                            matchedBets = matchedBets + 1
                        end
                    end
                end
                if activePlayers <= 1 or (matchedBets == activePlayers and currentPlayer == dealerPos) then
                    createSidePots()
                    if activePlayers <= 1 then
                        -- End hand
                        local winner
                        for _, p in ipairs(players) do
                            if p.active then
                                winner = p
                                break
                            end
                        end
                        if winner then
                            for _, pot in ipairs(pots) do
                                local rake = math.floor(pot.amount * 0.01)
                                pot.amount = pot.amount - rake
                                winner.chips = winner.chips + pot.amount
                            end
                            message = winner.name .. " wins " .. pots[1].amount .. " chips!"
                            winner.showCards = true
                            showdownResponses[winner.id] = "show"
                            playSound("entity.player.levelup")
                        end
                        -- Reset for new hand
                        pots = {{amount = 0, eligible = {}}}
                        currentBet = 0
                        round = "preflop"
                        communityCards = {}
                        showdown = false
                        showdownResponses = {}
                        for _, p in ipairs(players) do
                            p.betThisRound = 0
                            p.active = p.chips > 0
                            p.showCards = false
                        end
                        -- Check for game end
                        local remainingPlayers = 0
                        for _, p in ipairs(players) do
                            if p.chips > 0 then
                                remainingPlayers = remainingPlayers + 1
                            else
                                rednet.send(p.id, {type = "eliminated"})
                                playSound("block.note_block.bass")
                            end
                        end
                        if remainingPlayers <= 1 then
                            state = "lobby"
                            for _, p in ipairs(players) do
                                if p.chips > 0 then
                                    writeBalance(p.diskID, (readBalance(p.diskID) or 0) + p.chips)
                                end
                            end
                            players = {}
                            message = "Game over! Insert disks to join again."
                        else
                            initDeck()
                            shuffleDeck()
                            dealCards()
                            dealerPos = dealerPos % #players + 1
                            currentPlayer = (dealerPos + 1) % #players + 1
                            while not players[currentPlayer].active or players[currentPlayer].chips == 0 do
                                currentPlayer = currentPlayer % #players + 1
                            end
                            -- Collect blinds
                            local sbPlayer = (dealerPos + 1) % #players + 1
                            local bbPlayer = (dealerPos + 2) % #players + 1
                            if players[sbPlayer].chips >= blinds.small then
                                players[sbPlayer].chips = players[sbPlayer].chips - blinds.small
                                players[sbPlayer].betThisRound = blinds.small
                                pots[1].amount = pots[1].amount + blinds.small
                            end
                            if players[bbPlayer].chips >= blinds.big then
                                players[bbPlayer].chips = players[bbPlayer].chips - blinds.big
                                players[bbPlayer].betThisRound = blinds.big
                                pots[1].amount = pots[1].amount + blinds.big
                                currentBet = blinds.big
                            end
                            for _, p in ipairs(players) do
                                table.insert(pots[1].eligible, p.id)
                            end
                            broadcastState()
                        end
                    elseif round == "preflop" then
                        round = "flop"
                        communityCards = {table.remove(deck), table.remove(deck), table.remove(deck)}
                        currentBet = 0
                        for _, p in ipairs(players) do
                            p.betThisRound = 0
                        end
                        currentPlayer = (dealerPos + 1) % #players + 1
                        while not players[currentPlayer].active or players[currentPlayer].chips == 0 do
                            currentPlayer = currentPlayer % #players + 1
                        end
                        broadcastState()
                    elseif round == "flop" then
                        round = "turn"
                        table.insert(communityCards, table.remove(deck))
                        currentBet = 0
                        for _, p in ipairs(players) do
                            p.betThisRound = 0
                        end
                        currentPlayer = (dealerPos + 1) % #players + 1
                        while not players[currentPlayer].active or players[currentPlayer].chips == 0 do
                            currentPlayer = currentPlayer % #players + 1
                        end
                        broadcastState()
                    elseif round == "turn" then
                        round = "river"
                        table.insert(communityCards, table.remove(deck))
                        currentBet = 0
                        for _, p in ipairs(players) do
                            p.betThisRound = 0
                        end
                        currentPlayer = (dealerPos + 1) % #players + 1
                        while not players[currentPlayer].active or players[currentPlayer].chips == 0 do
                            currentPlayer = currentPlayer % #players + 1
                        end
                        broadcastState()
                    elseif round == "river" then
                        -- Initiate showdown
                        showdown = true
                        for _, p in ipairs(players) do
                            if p.active then
                                rednet.send(p.id, {type = "showdown"})
                            end
                        end
                        broadcastState()
                    end
                end
            elseif msg.type == "showdown_choice" and state == "game" and showdown then
                local player
                for _, p in ipairs(players) do
                    if p.id == senderID and p.active then
                        player = p
                        break
                    end
                end
                if player then
                    showdownResponses[senderID] = msg.choice
                    player.showCards = msg.choice == "show"
                    print("Showdown choice: " .. msg.choice .. " from player ID " .. senderID)
                end
                -- Check if all responses are in
                local activePlayers = 0
                for _, p in ipairs(players) do
                    if p.active then
                        activePlayers = activePlayers + 1
                    end
                end
                if table.getn(showdownResponses) == activePlayers then
                    -- Evaluate hands
                    local handResults = {}
                    for _, p in ipairs(players) do
                        if p.active then
                            table.insert(handResults, {player = p, hand = evaluateHand(p)})
                        end
                    end
                    table.sort(handResults, function(a, b) return compareHands(a.hand, b.hand) > 0 end)
                    for _, pot in ipairs(pots) do
                        local eligiblePlayers = {}
                        for _, p in ipairs(handResults) do
                            for _, id in ipairs(pot.eligible) do
                                if p.player.id == id then
                                    table.insert(eligiblePlayers, p)
                                    break
                                end
                            end
                        end
                        if #eligiblePlayers > 0 then
                            local bestHand = eligiblePlayers[1].hand
                            local winners = {}
                            for _, p in ipairs(eligiblePlayers) do
                                if compareHands(p.hand, bestHand) == 0 then
                                    table.insert(winners, p.player)
                                end
                            end
                            local rake = math.floor(pot.amount * 0.01)
                            pot.amount = pot.amount - rake
                            local split = math.floor(pot.amount / #winners)
                            for _, winner in ipairs(winners) do
                                winner.chips = winner.chips + split
                                winner.showCards = true -- Winners show cards
                                showdownResponses[winner.id] = "show"
                            end
                            message = message .. winners[1].name .. (#winners > 1 and " and others" or "") .. " win " .. split .. " chips! "
                            playSound("entity.player.levelup")
                        end
                    end
                    -- Reset for new hand
                    pots = {{amount = 0, eligible = {}}}
                    currentBet = 0
                    round = "preflop"
                    communityCards = {}
                    showdown = false
                    showdownResponses = {}
                    for _, p in ipairs(players) do
                        p.betThisRound = 0
                        p.active = p.chips > 0
                        p.showCards = false
                    end
                    -- Check for game end
                    local remainingPlayers = 0
                    for _, p in ipairs(players) do
                        if p.chips > 0 then
                            remainingPlayers = remainingPlayers + 1
                        else
                            rednet.send(p.id, {type = "eliminated"})
                            playSound("block.note_block.bass")
                        end
                    end
                    if remainingPlayers <= 1 then
                        state = "lobby"
                        for _, p in ipairs(players) do
                            if p.chips > 0 then
                                writeBalance(p.diskID, (readBalance(p.diskID) or 0) + p.chips)
                            end
                        end
                        players = {}
                        message = "Game over! Insert disks to join again."
                    else
                        initDeck()
                        shuffleDeck()
                        dealCards()
                        dealerPos = dealerPos % #players + 1
                        currentPlayer = (dealerPos + 1) % #players + 1
                        while not players[currentPlayer].active or players[currentPlayer].chips == 0 do
                            currentPlayer = currentPlayer % #players + 1
                        end
                        -- Collect blinds
                        local sbPlayer = (dealerPos + 1) % #players + 1
                        local bbPlayer = (dealerPos + 2) % #players + 1
                        if players[sbPlayer].chips >= blinds.small then
                            players[sbPlayer].chips = players[sbPlayer].chips - blinds.small
                            players[sbPlayer].betThisRound = blinds.small
                            pots[1].amount = pots[1].amount + blinds.small
                        end
                        if players[bbPlayer].chips >= blinds.big then
                            players[bbPlayer].chips = players[bbPlayer].chips - blinds.big
                            players[bbPlayer].betThisRound = blinds.big
                            pots[1].amount = pots[1].amount + blinds.big
                            currentBet = blinds.big
                        end
                        for _, p in ipairs(players) do
                            table.insert(pots[1].eligible, p.id)
                        end
                        broadcastState()
                    end
                end
            end
        elseif state == "lobby" and #players >= 2 and event == "monitor_touch" and isClickInButton(param2, param3, 2, 8, 10, 3) then
            state = "game"
            initDeck()
            shuffleDeck()
            dealCards()
            currentPlayer = (dealerPos + 1) % #players + 1
            -- Collect blinds
            local sbPlayer = (dealerPos + 1) % #players + 1
            local bbPlayer = (dealerPos + 2) % #players + 1
            if players[sbPlayer].chips >= blinds.small then
                players[sbPlayer].chips = players[sbPlayer].chips - blinds.small
                players[sbPlayer].betThisRound = blinds.small
                pots[1].amount = pots[1].amount + blinds.small
            end
            if players[bbPlayer].chips >= blinds.big then
                players[bbPlayer].chips = players[bbPlayer].chips - blinds.big
                players[bbPlayer].betThisRound = blinds.big
                pots[1].amount = pots[1].amount + blinds.big
                currentBet = blinds.big
            end
            for _, p in ipairs(players) do
                table.insert(pots[1].eligible, p.id)
            end
            broadcastState()
            playSound("block.note_block.hat")
        end
    end
end

main()
