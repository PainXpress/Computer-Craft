-- Poker Tournament Server for GearHallow Casino
-- Save as 'poker_server.lua' on the server computer (ID 5680)
-- Requires a wired modem on back
-- Reads TERMINAL_IDS from config.txt
-- Players buy in via terminal disk drives

local modem = peripheral.wrap("back") or error("No modem found on back side", 0)
local VALID_TERMINAL_IDS = {5674, 5675} -- Updated to match client IDs
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
        players = state.players or {}
        deck = state.deck or {}
        community_cards = state.community_cards or {}
        main_pot = state.main_pot or 0
        side_pots = state.side_pots or {}
        current_bet = state.current_bet or 0
        dealer_pos = state.dealer_pos or 1
        small_blind = state.small_blind or 10
        big_blind = state.big_blind or 20
        game_state = state.game_state or "registration"
        current_player = state.current_player or 1
        casino_profits = state.casino_profits or 0
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
            local success, err = pcall(function() rednet.send(player.id, {type = "state", state = state, your_cards = player.cards}) end)
            if not success then
                print("Failed to send state to " .. player.name .. ": " .. err)
            end
        end
    end
    saveState()
end

-- Main game loop with error handling
function main()
    local success, err = pcall(function()
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
                        print("Received message from " .. sender .. " with type: " .. (message and message.type or "nil"))
                        if message.type == "register" and #players < MAX_PLAYERS then
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
                -- Game logic continues...
                -- (rest of the server code)
            end
        end
    end)
    if not success then
        print("Error in main loop: " .. err)
        os.sleep(2)
        os.reboot()
    end
end

main()
