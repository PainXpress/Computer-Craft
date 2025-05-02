-- Poker (Texas Hold'em) for Casino Debit Cards
-- Save as 'poker.lua' on main computer

local monitor = peripheral.find("monitor")
local modem = peripheral.find("modem") or error("No modem found")
print("Opening modem: " .. peripheral.getName(modem))
rednet.open("left")  -- Modem on left side

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

-- Helper: Retry rednet requests with timeout
local function retryRequest(playerID, requestType, data, retries, timeout)
    for i = 1, retries do
        print("Attempt " .. i .. " - " .. requestType .. " to ID " .. playerID)
        rednet.send(playerID, {type = requestType, data = data})
        local senderID, msg = rednet.receive(timeout)
        if senderID == playerID and msg and msg.type == requestType .. "_response" then
            return msg
        end
        sleep(1) -- Brief delay between retries
    end
    print(requestType .. " failed: No response from ID " .. playerID)
    return nil
end

-- Read balance with retries
function readBalance(playerID, diskID)
    local response = retryRequest(playerID, "read_balance", {diskID = diskID}, 3, 5)
    if response then
        return response.balance, response.error
    end
    return nil, "No response"
end

-- Write balance
function writeBalance(playerID, diskID, balance)
    local response = retryRequest(playerID, "write_balance", {diskID = diskID, balance = balance}, 3, 5)
    return response and response.success or false
end

-- Read username
function readUsername(playerID, diskID)
    local response = retryRequest(playerID, "read_username", {diskID = diskID}, 3, 5)
    return response and response.name or "Unknown"
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

-- Draw button
function drawButton(x, y, width, height, text, color)
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

-- Evaluate hand
function evaluateHand(player)
    local cards = {}
    for _, card in ipairs(player.hand) do
        table.insert(cards, card)
    end
    for _, card in ipairs(communityCards) do
        table.insert(cards, card)
    end
    local function cardValue(card)
        return card.rank == "A" and 14 or card.rank == "K" and 13 or card.rank == "Q" and 12 or card.rank == "J" and 11 or tonumber(card.rank) or 0
    end
    table.sort(cards, function(a, b) return cardValue(a) > cardValue(b) end)
    local suits = {}; local ranks = {}
    for _, card in ipairs(cards) do
        suits[card.suit] = (suits[card.suit] or 0) + 1
        ranks[cardValue(card)] = (ranks[cardValue(card)] or 0) + 1
    end
    local isFlush = false; local flushSuit
    for suit, count in pairs(suits) do if count >= 5 then isFlush = true; flushSuit = suit end end
    local isStraight = false; local highCard = 0
    for i = 14, 5, -1 do if ranks[i] and ranks[i-1] and ranks[i-2] and ranks[i-3] and ranks[i-4] then isStraight = true; highCard = i break end end
    if ranks[14] and ranks[2] and ranks[3] and ranks[4] and ranks[5] then isStraight = true; highCard = 5 end
    if isFlush and isStraight then
        local flushCards = {}
        for _, card in ipairs(cards) do if card.suit == flushSuit then table.insert(flushCards, cardValue(card)) end end
        table.sort(flushCards, function(a, b) return a > b end)
        for i = 1, #flushCards - 4 do if flushCards[i] == flushCards[i+4] + 4 then return {rank = 9, value = flushCards[i]} end end
    end
    local quads, quadValue = 0, 0
    for rank, count in pairs(ranks) do if count == 4 then quads = rank; quadValue = rank end end
    if quads > 0 then for rank, count in pairs(ranks) do if count >= 1 and rank ~= quads then return {rank = 8, value = quadValue} end end end
    local trips, pair = 0, 0
    for rank, count in pairs(ranks) do if count == 3 then trips = rank elseif count == 2 then pair = rank end end
    if trips > 0 and pair > 0 then return {rank = 7, value = trips} end
    if isFlush then
        local flushCards = {}
        for _, card in ipairs(cards) do if card.suit == flushSuit then table.insert(flushCards, cardValue(card)) end end
        table.sort(flushCards, function(a, b) return a > b end)
        return {rank = 6, value = flushCards[1]}
    end
    if isStraight then return {rank = 5, value = highCard} end
    if trips > 0 then return {rank = 4, value = trips} end
    local pairs = {}
    for rank, count in pairs(ranks) do if count == 2 then table.insert(pairs, rank) end end
    if #pairs >= 2 then table.sort(pairs, function(a, b) return a > b end); return {rank = 3, value = pairs[1]} end
    if #pairs == 1 then return {rank = 2, value = pairs[1]} end
    local highCards = {}
    for _, card in ipairs(cards) do table.insert(highCards, cardValue(card)) end
    table.sort(highCards, function(a, b) return a > b end)
    return {rank = 1, value = highCards[1]}
end

-- Compare hands
function compareHands(hand1, hand2)
    if hand1.rank ~= hand2.rank then return hand1.rank > hand2.rank and 1 or -1 end
    return hand1.value > hand2.value and 1 or hand1.value < hand2.value and -1 or 0
end

-- Create side pots
function createSidePots()
    pots = {{amount = 0, eligible = {}}}
    local bets = {}
    for _, player in ipairs(players) do if player.active then bets[player.id] = player.betThisRound or 0 end end
    local sortedBets = {}
    for id, bet in pairs(bets) do table.insert(sortedBets, bet) end
    table.sort(sortedBets)
    for i, bet in ipairs(sortedBets) do
        if bet > 0 then
            local pot = {amount = 0, eligible = {}}
            for _, player in ipairs(players) do
                if player.active and (player.betThisRound or 0) >= bet then
                    table.insert(pot.eligible, player.id)
                    pot.amount = pot.amount + (i == 1 and bet or bet - sortedBets[i-1])
                end
            end
            if pot.amount > 0 then table.insert(pots, pot) end
        end
    end
end

-- Broadcast state
function broadcastState()
    local stateData = {type = "state", communityCards = communityCards, pots = pots, currentBet = currentBet, currentPlayer = players[currentPlayer].id, blinds = blinds, round = round, showdown = showdown}
    for _, player in ipairs(players) do if player.active then rednet.send(player.id, stateData) end end
end

-- Check button click
function isClickInButton(x, y, bx, by, bw, bh)
    return x >= bx and x < bx + bw and y >= by and y < by + bh
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
            if #players >= 2 then drawButton(2, 8, 10, 3, "Start", colors.green) end
        elseif state == "game" then
            local playerStr = ""
            for i, player in ipairs(players) do playerStr = playerStr .. player.name .. ": " .. player.chips .. " chips\n" end
            writeOutput(2, 6, playerStr)
            local commStr = "Community: " .. table.concat(communityCards, function(c) return c.rank .. c.suit .. " " end)
            writeOutput(2, 10, commStr)
            local potStr = "Pots: " .. table.concat(pots, function(p, i) return (i > 1 and "Side " or "Main ") .. p.amount .. " " end)
            writeOutput(2, 11, potStr)
            writeOutput(2, 12, "Bet: " .. currentBet)
            if showdown then
                local showdownStr = "Showdown: "
                for id, choice in pairs(showdownResponses) do
                    for _, player in ipairs(players) do
                        if player.id == id then
                            showdownStr = showdownStr .. player.name .. ": " .. (choice == "show" and (player.hand[1].rank .. player.hand[1].suit .. " " .. player.hand[2].rank .. player.hand[2].suit) or "Mucked") .. " | "
                        end
                    end
                end
                writeOutput(2, 13, showdownStr)
            else
                writeOutput(2, 13, "Turn: " .. players[currentPlayer].name)
            end
        end

        local event, param1, param2, param3 = os.pullEvent()
        message = ""

        if event == "rednet_message" then
            local senderID, msg = param1, param2
            if msg and type(msg) == "table" then
                print("Received: " .. (msg.type or "nil") .. " from " .. senderID)
                if msg.type == "join" and state == "lobby" then
                    print("Processing join for ID " .. senderID .. ", diskID " .. (msg.diskID or "nil"))
                    if not msg.diskID then
                        rednet.send(senderID, {type = "error", message = "No diskID"})
                    else
                        local balance, err = readBalance(senderID, msg.diskID)
                        if balance and balance >= buyIn then
                            balance = balance - buyIn
                            if writeBalance(senderID, msg.diskID, balance) then
                                table.insert(players, {id = senderID, name = readUsername(senderID, msg.diskID), chips = startingChips, diskID = msg.diskID, hand = {}, active = true, betThisRound = 0, showCards = false})
                                rednet.send(senderID, {type = "joined", name = players[#players].name})
                                message = "Player " .. players[#players].name .. " joined!"
                                playSound("block.note_block.hat")
                            else
                                rednet.send(senderID, {type = "error", message = "Write failed"})
                            end
                        else
                            rednet.send(senderID, {type = "error", message = err or "Insufficient funds"})
                        end
                    end
                elseif msg.type == "action" and state == "game" and senderID == players[currentPlayer].id and not showdown then
                    local player = players[currentPlayer]
                    if msg.action == "fold" then player.active = false; playSound("block.note_block.bass")
                    elseif msg.action == "check" and player.betThisRound == currentBet then playSound("block.note_block.hat")
                    elseif msg.action == "call" and player.chips >= currentBet - (player.betThisRound or 0) then
                        local bet = currentBet - (player.betThisRound or 0); player.chips = player.chips - bet; player.betThisRound = (player.betThisRound or 0) + bet; playSound("block.note_block.hat")
                    elseif msg.action == "raise" and player.chips >= msg.amount - (player.betThisRound or 0) and msg.amount > currentBet then
                        local bet = msg.amount - (player.betThisRound or 0); player.chips = player.chips - bet; player.betThisRound = (player.betThisRound or 0) + bet; currentBet = msg.amount; playSound("block.note_block.hat")
                    elseif msg.action == "allin" and player.chips > 0 then
                        local bet = player.chips; player.chips = 0; player.betThisRound = (player.betThisRound or 0) + bet
                        if player.betThisRound > currentBet then currentBet = player.betThisRound end
                        playSound("block.note_block.hat")
                    else rednet.send(senderID, {type = "error", message = "Invalid action"}) end
                    currentPlayer = currentPlayer % #players + 1
                    while not players[currentPlayer].active or players[currentPlayer].chips == 0 do currentPlayer = currentPlayer % #players + 1 end
                    broadcastState()
                    local activePlayers, matchedBets = 0, 0
                    for _, p in ipairs(players) do if p.active and p.chips > 0 then activePlayers = activePlayers + 1; if p.betThisRound == currentBet or p.chips == 0 then matchedBets = matchedBets + 1 end end end
                    if activePlayers <= 1 or (matchedBets == activePlayers and currentPlayer == dealerPos) then
                        createSidePots()
                        if activePlayers <= 1 then
                            local winner = next((function() for _, p in ipairs(players) do if p.active then return p end end end)())
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
                            pots = {{amount = 0, eligible = {}}}
                            currentBet = 0
                            round = "preflop"
                            communityCards = {}
                            showdown = false
                            showdownResponses = {}
                            for _, p in ipairs(players) do p.betThisRound = 0; p.active = p.chips > 0; p.showCards = false end
                            local remainingPlayers = 0
                            for _, p in ipairs(players) do if p.chips > 0 then remainingPlayers = remainingPlayers + 1 else rednet.send(p.id, {type = "eliminated"}) end end
                            if remainingPlayers <= 1 then
                                state = "lobby"
                                for _, p in ipairs(players) do if p.chips > 0 then
                                    local currentBalance = readBalance(p.id, p.diskID)
                                    if currentBalance then writeBalance(p.id, p.diskID, currentBalance + p.chips) end
                                end end
                                players = {}
                                message = "Game over! Insert disks to join again."
                            else
                                initDeck()
                                shuffleDeck()
                                dealCards()
                                dealerPos = dealerPos % #players + 1
                                currentPlayer = (dealerPos + 1) % #players + 1
                                while not players[currentPlayer].active or players[currentPlayer].chips == 0 do currentPlayer = currentPlayer % #players + 1 end
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
                                for _, p in ipairs(players) do table.insert(pots[1].eligible, p.id) end
                                broadcastState()
                            end
                        elseif round == "preflop" then
                            round = "flop"
                            communityCards = {table.remove(deck), table.remove(deck), table.remove(deck)}
                            currentBet = 0
                            for _, p in ipairs(players) do p.betThisRound = 0 end
                            currentPlayer = (dealerPos + 1) % #players + 1
                            while not players[currentPlayer].active or players[currentPlayer].chips == 0 do currentPlayer = currentPlayer % #players + 1 end
                            broadcastState()
                        elseif round == "flop" then
                            round = "turn"
                            table.insert(communityCards, table.remove(deck))
                            currentBet = 0
                            for _, p in ipairs(players) do p.betThisRound = 0 end
                            currentPlayer = (dealerPos + 1) % #players + 1
                            while not players[currentPlayer].active or players[currentPlayer].chips == 0 do currentPlayer = currentPlayer % #players + 1 end
                            broadcastState()
                        elseif round == "turn" then
                            round = "river"
                            table.insert(communityCards, table.remove(deck))
                            currentBet = 0
                            for _, p in ipairs(players) do p.betThisRound = 0 end
                            currentPlayer = (dealerPos + 1) % #players + 1
                            while not players[currentPlayer].active or players[currentPlayer].chips == 0 do currentPlayer = currentPlayer % #players + 1 end
                            broadcastState()
                        elseif round == "river" then
                            showdown = true
                            for _, p in ipairs(players) do if p.active then rednet.send(p.id, {type = "showdown"}) end end
                            broadcastState()
                        end
                    end
                elseif msg.type == "showdown_choice" and state == "game" and showdown then
                    local player = next((function() for _, p in ipairs(players) do if p.id == senderID and p.active then return p end end end)())
                    if player then
                        showdownResponses[senderID] = msg.choice
                        player.showCards = msg.choice == "show"
                        print("Showdown choice: " .. msg.choice .. " from " .. senderID)
                    end
                    local activePlayers = 0
                    for _, p in ipairs(players) do if p.active then activePlayers = activePlayers + 1 end end
                    if #showdownResponses == activePlayers then
                        local handResults = {}
                        for _, p in ipairs(players) do if p.active then table.insert(handResults, {player = p, hand = evaluateHand(p)}) end end
                        table.sort(handResults, function(a, b) return compareHands(a.hand, b.hand) > 0 end)
                        for _, pot in ipairs(pots) do
                            local eligiblePlayers = {}
                            for _, p in ipairs(handResults) do for _, id in ipairs(pot.eligible) do if p.player.id == id then table.insert(eligiblePlayers, p) break end end end
                            if #eligiblePlayers > 0 then
                                local bestHand = eligiblePlayers[1].hand
                                local winners = {}
                                for _, p in ipairs(eligiblePlayers) do if compareHands(p.hand, bestHand) == 0 then table.insert(winners, p.player) end end
                                local rake = math.floor(pot.amount * 0.01)
                                pot.amount = pot.amount - rake
                                local split = math.floor(pot.amount / #winners)
                                for _, winner in ipairs(winners) do
                                    winner.chips = winner.chips + split
                                    winner.showCards = true
                                    showdownResponses[winner.id] = "show"
                                end
                                message = message .. winners[1].name .. (#winners > 1 and " and others" or "") .. " win " .. split .. " chips! "
                                playSound("entity.player.levelup")
                            end
                        end
                        pots = {{amount = 0, eligible = {}}}
                        currentBet = 0
                        round = "preflop"
                        communityCards = {}
                        showdown = false
                        showdownResponses = {}
                        for _, p in ipairs(players) do p.betThisRound = 0; p.active = p.chips > 0; p.showCards = false end
                        local remainingPlayers = 0
                        for _, p in ipairs(players) do if p.chips > 0 then remainingPlayers = remainingPlayers + 1 else rednet.send(p.id, {type = "eliminated"}) end end
                        if remainingPlayers <= 1 then
                            state = "lobby"
                            for _, p in ipairs(players) do if p.chips > 0 then
                                local currentBalance = readBalance(p.id, p.diskID)
                                if currentBalance then writeBalance(p.id, p.diskID, currentBalance + p.chips) end
                            end end
                            players = {}
                            message = "Game over! Insert disks to join again."
                        else
                            initDeck()
                            shuffleDeck()
                            dealCards()
                            dealerPos = dealerPos % #players + 1
                            currentPlayer = (dealerPos + 1) % #players + 1
                            while not players[currentPlayer].active or players[currentPlayer].chips == 0 do currentPlayer = currentPlayer % #players + 1 end
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
                            for _, p in ipairs(players) do table.insert(pots[1].eligible, p.id) end
                            broadcastState()
                        end
                    end
                end
            else
                print("Received invalid message from " .. (senderID or "unknown"))
            end
        elseif state == "lobby" and #players >= 2 and event == "monitor_touch" and isClickInButton(param2, param3, 2, 8, 10, 3) then
            state = "game"
            initDeck()
            shuffleDeck()
            dealCards()
            currentPlayer = (dealerPos + 1) % #players + 1
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
            for _, p in ipairs(players) do table.insert(pots[1].eligible, p.id) end
            broadcastState()
            playSound("block.note_block.hat")
        end
    end
end

main()
