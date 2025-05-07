-- Poker Tournament Server for GearHallow Casino
-- Save as 'poker_server.lua' on the server computer (ID 394)
-- Requires a wired modem on back
-- Reads TERMINAL_IDS from config.txt
-- Players buy in via terminal disk drives

-- Load configuration
local function loadConfig()
    local config = {TERMINAL_IDS = {391, 393}}
    if fs.exists("config.txt") then
        local file = fs.open("config.txt", "r")
        local content = file.readAll()
        file.close()
        for line in content:gmatch("[^\r\n]+") do
            local key, value = line:match("^(%S+)=(.+)$")
            if key == "TERMINAL_IDS" then
                config.TERMINAL_IDS = {}
                for id in value:gmatch("%d+") do
                    table.insert(config.TERMINAL_IDS, tonumber(id))
                end
            end
        end
    else
        local file = fs.open("config.txt", "w")
        file.writeLine("TERMINAL_IDS=391,393")
        file.close()
    end
    return config
end

local config = loadConfig()
local modem = peripheral.wrap("back") or error("No modem found on back side", 0)
local VALID_TERMINAL_IDS = config.TERMINAL_IDS
local TOURNAMENT_BUYIN = 300 -- Chips required for buy-in
local STARTING_CHIPS = 3000 -- Tournament starting stack
local MAX_PLAYERS = 9
local BLIND_INCREASE_TIME = 600 -- 10 minutes in seconds
local HOUSE_CUT = 0.1 -- 10% casino cut
local ACTION_TIMEOUT = 30 -- 30 seconds for player action
local players = {} -- {id, name, chips, cards, active, folded, current_bet}
local deck = {}
local community_cards = {}
local main_pot = 0
local side_pots = {} -- {amount, eligible_players}
local current_bet = 0
local dealer_pos = 1
local small_blind = 10
local big_blind = 20
local game_state = "registration" -- registration, preflop, flop, turn, river, showdown, ended
local current_player = 1
local casino_profits = 0

-- Initialize rednet
modem.open(os.getComputerID())
rednet.open("back")

-- Log casino profits
function logProfit(amount)
    casino_profits = casino_profits + amount
    local file = fs.open("casino_profits.txt", "a")
    file.writeLine(amount .. " chips withheld at " .. os.date("%Y-%m-%d %H:%M"))
    file.close()
end

-- Save game state
function saveState()
    local state = {
        players = players,
        deck = deck,
        community_cards = community_cards,
        main_pot = main_pot,
        side_pots = side_pots,
        current_bet = current_bet,
        dealer_pos = dealer_pos,
        small_blind = small_blind,
        big_blind = big_blind,
        game_state = game_state,
        current_player = current_player,
        casino_profits = casino_profits
    }
    local file = fs.open("game_state.txt", "w")
    file.write(textutils.serialize(state))
    file.close()
end

-- Load game state
function loadState()
    if fs.exists("game_state.txt") then
        local file = fs.open("game_state.txt", "r")
        local state = textutils.unserialize(file.readAll())
        file.close()
        players = state.players
        deck = state.deck
        community_cards = state.community_cards
        main_pot = state.main_pot
        side_pots = state.side_pots
        current_bet = state.current_bet
        dealer_pos = state.dealer_pos
        small_blind = state.small_blind
        big_blind = state.big_blind
        game_state = state.game_state
        current_player = state.current_player
        casino_profits = state.casino_profits
        return true
    end
    return false
end

-- Shuffle deck
function shuffleDeck()
    deck = {}
    local suits = {"H", "D", "C", "S"}
    local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"}
    for _, suit in ipairs(suits) do
        for _, rank in ipairs(ranks) do
            table.insert(deck, rank .. suit)
        end
    end
    for i = #deck, 2, -1 do
        local j = math.random(1, i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

-- Deal cards
function dealCards()
    shuffleDeck()
    for _, player in ipairs(players) do
        if player.active then
            player.cards = {table.remove(deck), table.remove(deck)}
            player.folded = false
            player.current_bet = 0
        end
    end
end

-- Deal community cards
function dealCommunity(num)
    for i = 1, num do
        table.insert(community_cards, table.remove(deck))
    end
end

-- Broadcast game state
function broadcastState()
    local state = {
        community_cards = community_cards,
        main_pot = main_pot,
        side_pots = side_pots,
        current_bet = current_bet,
        small_blind = small_blind,
        big_blind = big_blind,
        game_state = game_state,
        current_player = players[current_player] and players[current_player].name or "",
        players = {}
    }
    for _, player in ipairs(players) do
        table.insert(state.players, {
            name = player.name,
            chips = player.chips,
            active = player.active,
            folded = player.folded,
            bet = player.current_bet or 0
        })
    end
    for _, player in ipairs(players) do
        if player.active then
            rednet.send(player.id, {type = "state", state = state, your_cards = player.cards})
        end
    end
    saveState()
end

-- Convert card to numerical value
function cardValue(card)
    local rank = card:sub(1, -2)
    local values = {["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["T"]=10, ["J"]=11, ["Q"]=12, ["K"]=13, ["A"]=14}
    return values[rank]
end

-- Full hand evaluator
function evaluateHand(cards, community)
    local all_cards = {}
    for _, card in ipairs(cards) do table.insert(all_cards, card) end
    for _, card in ipairs(community) do table.insert(all_cards, card) end
    table.sort(all_cards, function(a, b) return cardValue(a) > cardValue(b) end)

    local values = {}
    local suits = {}
    for _, card in ipairs(all_cards) do
        local value = card:sub(1, -2)
        local suit = card:sub(-1)
        values[value] = (values[value] or 0) + 1
        suits[suit] = (suits[suit] or 0) + 1
    end

    local value_counts = {}
    for value, count in pairs(values) do
        value_counts[#value_counts + 1] = {value = value, count = count}
    end
    table.sort(value_counts, function(a, b) return a.count > b.count or (a.count == b.count and cardValue(a.value) > cardValue(b.value)) end)

    local is_flush = false
    local flush_suit = nil
    for suit, count in pairs(suits) do
        if count >= 5 then
            is_flush = true
            flush_suit = suit
            break
        end
    end

    local flush_cards = {}
    if is_flush then
        for _, card in ipairs(all_cards) do
            if card:sub(-1) == flush_suit then
                table.insert(flush_cards, card)
            end
        end
        table.sort(flush_cards, function(a, b) return cardValue(a) > cardValue(b) end)
    end

    local function isStraight(card_values)
        local nums = {}
        for _, val in ipairs(card_values) do
            nums[#nums + 1] = cardValue(val)
        end
        table.sort(nums, function(a, b) return a > b end)
        local unique = {}
        for _, num in ipairs(nums) do
            if not unique[num] then
                unique[num] = true
                unique[#unique + 1] = num
            end
        end
        nums = unique
        if #nums >= 5 then
            for i = 1, #nums - 4 do
                if nums[i] - nums[i + 4] == 4 then
                    return true, nums[i]
                end
            end
            if nums[1] == 14 and nums[#nums - 3] == 5 and nums[#nums - 2] == 4 and nums[#nums - 1] == 3 and nums[#nums] == 2 then
                return true, 5 -- Ace-low straight
            end
        end
        return false, 0
    end

    local is_straight, straight_high = isStraight(all_cards)
    local is_flush_straight, flush_straight_high = false, 0
    if is_flush and #flush_cards >= 5 then
        is_flush_straight, flush_straight_high = isStraight(flush_cards)
    end

    if is_flush_straight and flush_straight_high == 14 then
        return {rank = 9, high = flush_straight_high} -- Royal Flush
    elseif is_flush_straight then
        return {rank = 8, high = flush_straight_high} -- Straight Flush
    elseif value_counts[1].count == 4 then
        return {rank = 7, high = cardValue(value_counts[1].value)} -- Four of a Kind
    elseif value_counts[1].count == 3 and value_counts[2].count >= 2 then
        return {rank = 6, high = cardValue(value_counts[1].value)} -- Full House
    elseif is_flush then
        return {rank = 5, high = cardValue(flush_cards[1])} -- Flush
    elseif is_straight then
        return {rank = 4, high = straight_high} -- Straight
    elseif value_counts[1].count == 3 then
        return {rank = 3, high = cardValue(value_counts[1].value)} -- Three of a Kind
    elseif value_counts[1].count == 2 and value_counts[2].count == 2 then
        return {rank = 2, high = math.max(cardValue(value_counts[1].value), cardValue(value_counts[2].value))} -- Two Pair
    elseif value_counts[1].count == 2 then
        return {rank = 1, high = cardValue(value_counts[1].value)} -- Pair
    else
        return {rank = 0, high = cardValue(all_cards[1])} -- High Card
    end
end

-- Compare hands
function compareHands(hand1, hand2)
    if hand1.rank ~= hand2.rank then
        return hand1.rank > hand2.rank and 1 or -1
    end
    return hand1.high > hand2.high and 1 or hand1.high < hand2.high and -1 or 0
end

-- Create side pots
function createSidePots()
    side_pots = {}
    local sorted_players = {}
    for _, player in ipairs(players) do
        if player.active and not player.folded then
            table.insert(sorted_players, player)
        end
    end
    table.sort(sorted_players, function(a, b) return (a.current_bet or 0) < (b.current_bet or 0) end)

    local previous_bet = 0
    for _, player in ipairs(sorted_players) do
        local bet = player.current_bet or 0
        if bet > previous_bet then
            local pot_amount = 0
            local eligible = {}
            for _, p in ipairs(players) do
                if p.active and not p.folded and (p.current_bet or 0) >= bet then
                    pot_amount = pot_amount + (bet - previous_bet)
                    table.insert(eligible, p.id)
                end
            end
            if pot_amount > 0 then
                table.insert(side_pots, {amount = pot_amount, eligible_players = eligible})
            end
            previous_bet = bet
        end
    end
    main_pot = 0
    for _, player in ipairs(players) do
        if player.active and not player.folded then
            main_pot = main_pot + (player.current_bet or 0)
        end
    end
    for _, pot in ipairs(side_pots) do
        main_pot = main_pot - pot.amount
    end
end

-- Award pots
function awardPots()
    local pots = {{amount = main_pot, eligible_players = {}}}
    for _, player in ipairs(players) do
        if player.active and not player.folded then
            table.insert(pots[1].eligible_players, player.id)
        end
    end
    for _, pot in ipairs(side_pots) do
        table.insert(pots, pot)
    end

    for _, pot in ipairs(pots) do
        if pot.amount > 0 and #pot.eligible_players > 0 then
            local best_score = {rank = -1, high = 0}
            local winners = {}
            for _, id in ipairs(pot.eligible_players) do
                for _, player in ipairs(players) do
                    if player.id == id then
                        local score = evaluateHand(player.cards, community_cards)
                        local cmp = compareHands(score, best_score)
                        if cmp > 0 then
                            best_score = score
                            winners = {player}
                        elseif cmp == 0 then
                            table.insert(winners, player)
                        end
                    end
                end
            end
            local house_cut = math.floor(pot.amount * HOUSE_CUT)
            local player_pot = pot.amount - house_cut
            logProfit(house_cut)
            local split = math.floor(player_pot / #winners)
            for _, winner in ipairs(winners) do
                winner.chips = winner.chips + split
                rednet.send(winner.id, {type = "message", text = "You won " .. split .. " chips after 10% house cut from a pot!"})
            end
        end
    end
    main_pot = 0
    side_pots = {}
end

-- Check for tournament end
function checkTournamentEnd()
    local active_players = 0
    local winner = nil
    for _, player in ipairs(players) do
        if player.active then
            active_players = active_players + 1
            winner = player
        end
    end
    if active_players <= 1 then
        game_state = "ended"
        if winner then
            local house_cut = math.floor(winner.chips * HOUSE_CUT)
            local final_prize = winner.chips - house_cut
            logProfit(house_cut)
            winner.chips = final_prize
            rednet.send(winner.id, {type = "message", text = "You won the tournament with " .. final_prize .. " chips after 10% house cut!"})
        end
        saveState()
        return true
    end
    return false
end

-- Main game loop
function main()
    if loadState() then
        print("Resumed game from saved state")
    else
        print("Starting new game")
    end

    while true do
        if game_state == "registration" then
            print("Waiting for players to register...")
            local timer = os.startTimer(60) -- 1 minute to register
            while game_state == "registration" do
                local event, p1, p2, p3 = os.pullEvent()
                if event == "rednet_message" then
                    local sender, message = p1, p2
                    if message.type == "register" and #players < MAX_PLAYERS then
                        -- Validate terminal ID
                        local valid_terminal = false
                        for _, id in ipairs(VALID_TERMINAL_IDS) do
                            if sender == id then
                                valid_terminal = true
                                break
                            end
                        end
                        if not valid_terminal then
                            rednet.send(sender, {type = "message", text = "Invalid terminal ID. Contact casino staff."})
                        elseif message.name and message.name ~= "" then
                            if message.success then
                                table.insert(players, {
                                    id = sender,
                                    name = message.name,
                                    chips = STARTING_CHIPS,
                                    active = true,
                                    folded = false,
                                    cards = {},
                                    current_bet = 0
                                })
                                rednet.send(sender, {type = "message", text = "Registered! Note: 10% of winnings are withheld by the casino. Waiting for game to start."})
                                print(message.name .. " registered")
                                saveState()
                            else
                                rednet.send(sender, {type = "message", text = message.error or "Failed to deduct buy-in. Insert disk or check balance."})
                            end
                        else
                            rednet.send(sender, {type = "message", text = "Invalid name. Try again."})
                        end
                    end
                elseif event == "timer" and p1 == timer then
                    if #players >= 2 then
                        game_state = "preflop"
                        print("Starting tournament with " .. #players .. " players")
                        saveState()
                    else
                        print("Not enough players. Waiting...")
                        timer = os.startTimer(60)
                    end
                end
            end
        elseif game_state == "ended" then
            print("Tournament ended. Total casino profits: " .. casino_profits .. " chips")
            break
        else
            main_pot = 0
            side_pots = {}
            current_bet = 0
            community_cards = {}
            for _, player in ipairs(players) do
                player.folded = false
                player.current_bet = 0
            end
            dealCards()
            game_state = "preflop"
            current_player = (dealer_pos % #players) + 1
            local sb_player = players[(dealer_pos % #players) + 1]
            local bb_player = players[((dealer_pos + 1) % #players) + 1]
            sb_player.chips = sb_player.chips - small_blind
            sb_player.current_bet = small_blind
            main_pot = main_pot + small_blind
            bb_player.chips = bb_player.chips - big_blind
            bb_player.current_bet = big_blind
            main_pot = main_pot + big_blind
            current_bet = big_blind
            current_player = ((dealer_pos + 2) % #players) + 1
            local blind_timer = os.startTimer(BLIND_INCREASE_TIME)
            while game_state ~= "ended" do
                broadcastState()
                if players[current_player].active and not players[current_player].folded then
                    rednet.send(players[current_player].id, {type = "action", options = {"fold", "call", "raise"}})
                    local _, message = rednet.receive(nil, ACTION_TIMEOUT)
                    if message and message.type == "action" then
                        if message.action == "fold" then
                            players[current_player].folded = true
                        elseif message.action == "call" then
                            local to_call = current_bet - (players[current_player].current_bet or 0)
                            if to_call >= players[current_player].chips then
                                to_call = players[current_player].chips
                            end
                            players[current_player].chips = players[current_player].chips - to_call
                            players[current_player].current_bet = (players[current_player].current_bet or 0) + to_call
                            main_pot = main_pot + to_call
                        elseif message.action == "raise" and message.amount then
                            local raise = message.amount
                            if raise >= current_bet * 2 and raise <= players[current_player].chips then
                                local to_call = raise - (players[current_player].current_bet or 0)
                                players[current_player].chips = players[current_player].chips - to_call
                                players[current_player].current_bet = raise
                                main_pot = main_pot + to_call
                                current_bet = raise
                            end
                        end
                    else
                        players[current_player].folded = true -- Auto-fold on timeout
                        rednet.send(players[current_player].id, {type = "message", text = "You folded due to inactivity."})
                    end
                end
                current_player = (current_player % #players) + 1
                local active_players = 0
                local all_called = true
                for _, player in ipairs(players) do
                    if player.active and not player.folded then
                        active_players = active_players + 1
                        if player.current_bet ~= current_bet then
                            all_called = false
                        end
                    end
                end
                if active_players <= 1 then
                    createSidePots()
                    awardPots()
                    game_state = "preflop"
                    break
                elseif all_called then
                    createSidePots()
                    if game_state == "preflop" then
                        dealCommunity(3)
                        game_state = "flop"
                    elseif game_state == "flop" then
                        dealCommunity(1)
                        game_state = "turn"
                    elseif game_state == "turn" then
                        dealCommunity(1)
                        game_state = "river"
                    elseif game_state == "river" then
                        game_state = "showdown"
                        awardPots()
                        game_state = "preflop"
                        break
                    end
                    current_bet = 0
                    for _, player in ipairs(players) do
                        player.current_bet = 0
                    end
                end
                for _, player in ipairs(players) do
                    if player.chips <= 0 then
                        player.active = false
                    end
                end
                if checkTournamentEnd() then
                    break
                end
                local event, p1 = os.pullEvent()
                if event == "timer" and p1 == blind_timer then
                    small_blind = small_blind * 2
                    big_blind = big_blind * 2
                    blind_timer = os.startTimer(BLIND_INCREASE_TIME)
                    rednet.broadcast({type = "message", text = "Blinds increased to " .. small_blind .. "/" .. big_blind})
                end
            end
            dealer_pos = (dealer_pos % #players) + 1
        end
    end
end

pcall(main)
