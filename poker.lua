-- Poker Host Server Code (poker.lua) - Rewritten
--[[
    ComputerCraft Poker Game - Host Server
    Handles game logic, player management, and communication.
    Rewritten to include basic turn management, action handling, and game flow.
]]

-- Configuration
local gameSettings = {
    minPlayers = 2,
    maxPlayers = 8,
    startingChips = 1000,
    smallBlind = 10,
    bigBlind = 20,
    debug = true -- Enable/disable debug messages
}

-- Global Game State Variables
local players = {} -- Table to store player info {id, name, chips, hand, currentBetInRound, totalBetInHand, status, isReady}
                  -- Status: connected, ready, playing, folded, allin, sitting_out
local deck = {}
local communityCards = {}
local pot = 0
local currentHighestBet = 0 -- Highest total bet placed *in the current betting round*
local minRaiseAmount = 0 -- Minimum amount needed to raise
local gameState = "lobby" -- lobby, dealing, preflop, flop, turn, river, showdown, hand_over
local dealerPosition = 0 -- Index in the players table
local actionPlayerIndex = 0 -- Index of the player whose turn it is
local lastRaiserIndex = 0 -- Index of the last player who bet or raised in the current round
local hostID = os.computerID()
local protocol = "poker_game" -- Rednet protocol identifier

-- Monitor Setup
local monitor = peripheral.find("monitor")
local function setupMonitor()
    if monitor then
        monitor.setTextScale(0.5)
        monitor.setCursorPos(1, 1)
        monitor.clear()
    end
end

-- Utility Functions
local function log(message)
    if gameSettings.debug then
        print("[DEBUG] " .. tostring(message))
    end
    if monitor then
        pcall(function() -- Wrap monitor operations in pcall for safety
            local w, h = monitor.getSize()
            local x, y = monitor.getCursorPos()
            monitor.setCursorPos(1, h) -- Log debug to the bottom line
            monitor.clearLine()
            monitor.write("[DBG] " .. string.sub(tostring(message), 1, w - 6)) -- Truncate if too long
            monitor.setCursorPos(x, y) -- Restore cursor
        end)
    end
end

local function deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepCopy(orig_key)] = deepCopy(orig_value)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- Creates a safe version of the players table to send (removes hands)
local function getPublicPlayersTable()
     local publicPlayers = deepCopy(players)
     for _, p in ipairs(publicPlayers) do
         p.hand = nil -- Don't broadcast hands
     end
     return publicPlayers
end


local function updateMonitor()
    if not monitor then return end
    pcall(function()
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write("--- Poker Server --- ID: " .. hostID .. " ---")
        monitor.setCursorPos(1, 2)
        monitor.write("Status: " .. gameState .. " | Pot: " .. pot .. " | High Bet: " .. currentHighestBet)
        monitor.setCursorPos(1, 3)
        monitor.write("Players (" .. #players .. "/" .. gameSettings.maxPlayers .. "):")

        local line = 4
        local w, h = monitor.getSize()
        for i, player in ipairs(players) do
            if line <= h -1 then -- Leave last line for debug
                monitor.setCursorPos(2, line)
                local statusText = player.status or "N/A"
                local turnIndicator = (i == actionPlayerIndex and gameState ~= "lobby" and gameState ~= "hand_over") and " (*)" or ""
                local dealerIndicator = (i == dealerPosition and gameState ~= "lobby") and " (D)" or ""
                local handStr = ""
                if gameState ~= "lobby" and player.hand and #player.hand > 0 then
                   -- Only show host the hands for debugging maybe? Or don't show at all.
                   -- handStr = " [" .. table.concat(player.hand, " ") .. "]" -- DEBUG ONLY
                end
                local betStr = (player.currentBetInRound > 0) and (" Bet:" .. player.currentBetInRound) or ""
                local readyStr = (player.isReady and gameState == "lobby") and " [R]" or ""

                local playerLine = string.format("%d. %s (ID:%d) C:%d S:%s%s%s%s%s",
                                     i, player.name or "??", player.id, player.chips, statusText,
                                     betStr, turnIndicator, dealerIndicator, readyStr --, handStr -- Add handStr back for debug
                                     )
                monitor.write(string.sub(playerLine, 1, w-2)) -- Truncate if needed
                line = line + 1
            end
        end

        if #communityCards > 0 then
             if line <= h - 1 then
                monitor.setCursorPos(1, line)
                monitor.write("Board: " .. table.concat(communityCards, " "))
                line = line + 1
            end
        end
    end)
end

local function broadcast(message, excludeID)
    log("Broadcasting: " .. textutils.serialize(message))
    for _, player in ipairs(players) do
        if player.id ~= excludeID then
            rednet.send(player.id, message, protocol)
        end
    end
    -- Also update host monitor after broadcast potentially
    updateMonitor()
end

local function sendToPlayer(playerID, message)
    log("Sending to " .. playerID .. ": " .. textutils.serialize(message))
    rednet.send(playerID, message, protocol)
end

-- Deck Functions
local function createDeck()
    deck = {}
    local suits = {"H", "D", "C", "S"} -- Hearts, Diamonds, Clubs, Spades
    local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"}
    for _, suit in ipairs(suits) do
        for _, rank in ipairs(ranks) do
            table.insert(deck, rank .. suit)
        end
    end
end

local function shuffleDeck()
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
    log("Deck shuffled.")
end

local function dealCard()
    if #deck == 0 then
        log("Error: Deck is empty!")
        -- Reshuffle or handle error? For now, return nil.
        return nil
    end
    return table.remove(deck)
end

-- Player Management
local function addPlayer(id, name)
    if gameState ~= "lobby" then
        sendToPlayer(id, { type = "error", message = "Game in progress. Please wait." })
        return false
    end
    if #players >= gameSettings.maxPlayers then
        sendToPlayer(id, { type = "error", message = "Game is full." })
        return false
    end
    -- Check if player ID already exists
    for _, p in ipairs(players) do
        if p.id == id then
            sendToPlayer(id, { type = "error", message = "You are already in the game." })
            -- Maybe just resend confirmation? For now, reject.
            return false
        end
    end

    local newPlayer = {
        id = id,
        name = name or "Player" .. id,
        chips = gameSettings.startingChips,
        hand = {},
        currentBetInRound = 0, -- Bet amount in the current street (preflop, flop, etc.)
        totalBetInHand = 0, -- Total bet amount in the entire hand
        status = "connected", -- connected, ready, playing, folded, allin, sitting_out
        isReady = false
    }
    table.insert(players, newPlayer)
    log("Player " .. newPlayer.name .. " (ID: " .. id .. ") joined.")

    -- Send confirmation and current game state
    sendToPlayer(id, { type = "join_confirm", hostID = hostID, settings = gameSettings, players = getPublicPlayersTable(), gameState = gameState })
    -- Notify other players
    broadcast({ type = "player_joined", player = {id=newPlayer.id, name=newPlayer.name, chips=newPlayer.chips, status=newPlayer.status, isReady=newPlayer.isReady} }, id) -- Send limited info
    updateMonitor()
    return true
end

local function removePlayer(id)
    local removedPlayer = nil
    local removedIndex = -1
    for i = #players, 1, -1 do
        if players[i].id == id then
            removedPlayer = table.remove(players, i)
            removedIndex = i
            log("Player " .. (removedPlayer.name or "Unknown") .. " (ID: " .. id .. ") left or disconnected.")
            broadcast({ type = "player_left", playerID = id })
            break
        end
    end

    if removedPlayer then
        -- Handle game state if player leaves mid-game
        if gameState ~= "lobby" and gameState ~= "hand_over" then
             log("Player left mid-game. Folding their hand.")
             -- If it was their turn, advance turn
             if removedIndex == actionPlayerIndex then
                 -- Need to be careful if removing the player shifts indices
                 -- It's generally safer to handle turn advancement *after* removal
                 -- Mark them as folded conceptually, let advanceTurn handle finding the *next* player
                 removedPlayer.status = "folded" -- Mark status for potential side pot calculations etc.
                 -- Potentially refund bets if round hasn't completed? Complex. Simplest is to forfeit bets.
                 advanceTurn()
             else
                 -- If the removed player was before the current action player, adjust actionPlayerIndex
                 if removedIndex < actionPlayerIndex then
                     actionPlayerIndex = actionPlayerIndex - 1
                 end
                 -- Adjust dealer position if needed
                 if removedIndex < dealerPosition then
                     dealerPosition = dealerPosition - 1
                 elseif removedIndex == dealerPosition then
                      -- If the dealer leaves, the button moves conceptually, but we'll recalculate next hand anyway
                      dealerPosition = (dealerPosition - 2 + #players) % #players + 1 -- Move back one relative to new table size
                 end
                 -- Adjust last raiser index
                 if removedIndex < lastRaiserIndex then
                      lastRaiserIndex = lastRaiserIndex - 1
                 elseif removedIndex == lastRaiserIndex then
                     -- Find the player before the removed player who last bet/raised or default to BB? Complex.
                     -- Simplest: Let the betting round continue, it will resolve naturally.
                 end
             end
        end
        updateMonitor()
    end
    return removedPlayer
end

-- Game Flow and Turn Management
local function getActivePlayersCount(includeAllIn)
    local count = 0
    for _, player in ipairs(players) do
        if player.status == "playing" or (includeAllIn and player.status == "allin") then
            count = count + 1
        end
    end
    return count
end

local function findNextPlayerIndex(startIndex, direction)
    direction = direction or 1 -- Default to clockwise
    local numPlayers = #players
    if numPlayers == 0 then return 0 end

    local currentIndex = startIndex
    repeat
        currentIndex = (currentIndex + direction - 1 + numPlayers) % numPlayers + 1
        local player = players[currentIndex]
        -- Eligible players are 'playing' and have chips left (or are 'allin' but haven't acted yet this round?)
        -- For now, only 'playing' status can act. 'allin' players are skipped.
        if player and player.status == "playing" then
            return currentIndex
        end
    until currentIndex == startIndex -- Full circle

    -- If no 'playing' players found (e.g., everyone else folded or is all-in)
    log("Could not find next active player from index " .. startIndex)
    return 0 -- Indicate no one else can act
end

local function advanceTurn()
    local numActivePlayers = getActivePlayersCount(false) -- Count players still able to bet/raise/fold
    local numTotalActive = getActivePlayersCount(true) -- Count players still in the hand (including all-in)

    log("Advancing turn. Active(betting): "..numActivePlayers..", Active(total): "..numTotalActive..", Current Action Player: "..actionPlayerIndex..", Last Raiser: "..lastRaiserIndex)

    if numActivePlayers <= 1 and currentHighestBet == 0 then
        -- If only one player can bet, and no bet has been made (e.g. pre-flop BB option), they get one more action.
        -- Or if betting round is complete. Check if action is back to last raiser.
    end

     -- Check if betting round is over
     -- Condition: Action returns to the last player who bet/raised *without* another raise occurring,
     -- OR only one player remains who hasn't folded.
     local nextPlayerIndex = findNextPlayerIndex(actionPlayerIndex)

     if numActivePlayers <= 1 then
          log("Betting round ends: Only one active player left.")
          endBettingRound()
          return
     end

     -- Check if the action has completed a full circle back to the last aggressor
     -- The player at 'nextPlayerIndex' is the one *potentially* closing the action.
     -- If the next player to act *is* the last raiser, the round ends, unless it's the BB pre-flop who hasn't acted yet.
     -- Exception: Big Blind pre-flop gets the option to raise even if others just called.
     local isPreflop = (gameState == "preflop")
     local isBigBlind = (actionPlayerIndex == ((dealerPosition + (isPreflop and 1 or 0)) % #players) + 1) -- Approximate BB position check
     local bigBlindCanCheckOrRaise = isPreflop and isBigBlind and currentHighestBet == gameSettings.bigBlind and actionPlayerIndex == lastRaiserIndex

     if nextPlayerIndex == lastRaiserIndex and not bigBlindCanCheckOrRaise then
         log("Betting round ends: Action returns to last raiser ("..lastRaiserIndex..").")
         endBettingRound()
         return
     end

     -- Otherwise, move to the next player
     actionPlayerIndex = nextPlayerIndex
     if actionPlayerIndex == 0 then
         -- This shouldn't happen if numActivePlayers > 1, but as a fallback:
         log("Error: Could not find next player, ending round.")
         endBettingRound()
     else
         log("Next action to player index: " .. actionPlayerIndex)
         requestAction(actionPlayerIndex)
     end
end


local function requestAction(playerIndex)
    local player = players[playerIndex]
    if not player or player.status ~= "playing" then
        log("Cannot request action from player " .. playerIndex .. " (status: " .. (player and player.status or "nil") .. "). Skipping.")
        advanceTurn() -- Skip to next player
        return
    end

    local callAmount = currentHighestBet - player.currentBetInRound
    local canCheck = (callAmount <= 0) -- Can check if no bet pending or already matched highest bet

    -- Calculate minimum raise amount
    -- Standard poker: Min raise must be at least the size of the previous bet/raise.
    -- minRaiseAmount was set when the last bet/raise occurred. If no raise yet, it's BB size.
    local effectiveMinRaise = math.max(gameSettings.bigBlind, minRaiseAmount)
    local minRaiseTotal = currentHighestBet + effectiveMinRaise -- The total bet needed for a minimum raise

    log("Requesting action from " .. player.name .. " (Index: " .. playerIndex .. ")")
    sendToPlayer(player.id, {
        type = "request_action",
        pot = pot,
        communityCards = communityCards,
        currentHighestBet = currentHighestBet,
        yourCurrentBet = player.currentBetInRound,
        callAmount = callAmount,
        minRaiseTo = minRaiseTotal, -- The total bet amount required for a min raise
        chips = player.chips,
        canCheck = canCheck,
        players = getPublicPlayersTable() -- Send current public state
    })
    updateMonitor() -- Show who's turn it is
end

local function collectBets()
    log("Collecting bets into pot.")
    for _, player in ipairs(players) do
        if player.currentBetInRound > 0 then
            pot = pot + player.currentBetInRound
            player.totalBetInHand = player.totalBetInHand + player.currentBetInRound -- Track total investment
            player.currentBetInRound = 0 -- Reset for next round
        end
    end
    currentHighestBet = 0 -- Reset for next betting round
    minRaiseAmount = gameSettings.bigBlind -- Reset min raise for next round
    log("Pot is now: " .. pot)
end

local function endBettingRound()
    log("Ending betting round for state: " .. gameState)
    collectBets()

    local activePlayersInHand = getActivePlayersCount(true) -- Include all-in players

    if activePlayersInHand <= 1 then
        log("Only one player left in hand.")
        -- Award pot to the remaining player
        awardPotToWinner() -- Simplified: assumes one winner
        transitionToState("hand_over")
        return
    end

    -- Transition to the next game state
    if gameState == "preflop" then
        transitionToState("flop")
    elseif gameState == "flop" then
        transitionToState("turn")
    elseif gameState == "turn" then
        transitionToState("river")
    elseif gameState == "river" then
        transitionToState("showdown")
    else
        log("Error: Unknown state to transition from: " .. gameState)
        -- Maybe default to hand_over or showdown?
        transitionToState("showdown")
    end
end

local function transitionToState(newState)
    log("Transitioning from " .. gameState .. " to " .. newState)
    gameState = newState
    updateMonitor() -- Update monitor immediately with new state

    if newState == "flop" then
        dealCommunityCards(3)
        broadcast({ type = "community_cards", cards = communityCards, pot = pot })
        -- Start betting round from player after dealer
        actionPlayerIndex = findNextPlayerIndex(dealerPosition)
        lastRaiserIndex = actionPlayerIndex -- Reset last raiser for the new round
        requestAction(actionPlayerIndex)
    elseif newState == "turn" then
        dealCommunityCards(1)
        broadcast({ type = "community_cards", cards = communityCards, pot = pot })
        actionPlayerIndex = findNextPlayerIndex(dealerPosition)
        lastRaiserIndex = actionPlayerIndex
        requestAction(actionPlayerIndex)
    elseif newState == "river" then
        dealCommunityCards(1)
        broadcast({ type = "community_cards", cards = communityCards, pot = pot })
        actionPlayerIndex = findNextPlayerIndex(dealerPosition)
        lastRaiserIndex = actionPlayerIndex
        requestAction(actionPlayerIndex)
    elseif newState == "showdown" then
        -- Reveal hands, determine winner(s)
        log("Entering Showdown...")
        -- TODO: Implement hand evaluation and winner determination
        local showdownInfo = { type = "showdown", players = {}, communityCards = communityCards, pot = pot }
        for _, p in ipairs(players) do
            if p.status == "playing" or p.status == "allin" then
                table.insert(showdownInfo.players, {id = p.id, name = p.name, hand = p.hand, status = p.status})
            end
        end
        broadcast(showdownInfo)
        awardPotToWinner() -- Placeholder for winner logic
        transitionToState("hand_over")
    elseif newState == "hand_over" then
        log("Hand over.")
        broadcast({ type = "hand_over", pot = pot, players = getPublicPlayersTable() }) -- Send final player states
        -- Wait a few seconds before starting next hand
        sleep(5)
        -- Check if enough players want to continue
        local canStart = false
        if getActivePlayersCount(true) >= gameSettings.minPlayers then -- Check if enough players have chips
             canStart = true
        end

        if canStart then
             startGame() -- Start the next hand
        else
             log("Not enough players with chips to continue. Returning to lobby.")
             gameState = "lobby"
             -- Reset player statuses etc for lobby
             for _, p in ipairs(players) do
                 p.status = "connected"
                 p.isReady = false
                 p.hand = {}
                 p.currentBetInRound = 0
                 p.totalBetInHand = 0
             end
             broadcast({type="state_update", gameState="lobby", players=getPublicPlayersTable()})
             updateMonitor()
        end
    end
end

local function dealCommunityCards(count)
    -- Burn one card (optional, standard practice)
    -- dealCard()
    log("Dealing " .. count .. " community cards.")
    for i = 1, count do
        local card = dealCard()
        if card then
            table.insert(communityCards, card)
        else
            log("Error: Ran out of cards while dealing community cards!")
            -- Handle error state?
            break
        end
    end
    log("Community cards: " .. table.concat(communityCards, " "))
end

-- TODO: Implement proper hand evaluation and pot awarding (complex)
local function awardPotToWinner()
    log("Awarding pot (placeholder logic)...")
    -- Find first player still in the hand (playing or allin)
    local winnerIndex = 0
    for i, p in ipairs(players) do
        if p.status == "playing" or p.status == "allin" then
            winnerIndex = i
            break
        end
    end

    if winnerIndex > 0 then
        local winner = players[winnerIndex]
        log("Awarding pot of " .. pot .. " to " .. winner.name)
        winner.chips = winner.chips + pot
        broadcast({ type = "winner_info", winnerID = winner.id, winnerName = winner.name, amountWon = pot })
    else
        log("Error: No winner found?") -- Should not happen if game logic is correct
    end
    pot = 0 -- Reset pot after awarding
end


-- Main Game Setup Function
local function startGame()
    local readyPlayerCount = 0
    for _, p in ipairs(players) do if p.isReady then readyPlayerCount = readyPlayerCount + 1 end end

    -- Allow starting manually via command later, for now auto-start if enough are ready
    -- Or, just proceed if called from hand_over state
    if gameState ~= "hand_over" and (readyPlayerCount < gameSettings.minPlayers or #players < gameSettings.minPlayers) then
        broadcast({ type = "error", message = "Not enough ready players to start ("..readyPlayerCount.."/"..gameSettings.minPlayers..")." })
        log("Start game failed: Not enough ready players.")
        gameState = "lobby" -- Ensure state is lobby
        return
    end

    log("Starting new hand...")
    gameState = "dealing"
    pot = 0
    communityCards = {}
    currentHighestBet = 0
    minRaiseAmount = gameSettings.bigBlind -- Initial min raise size

    createDeck()
    shuffleDeck()

    -- Reset player statuses and bets for the new hand
    for _, player in ipairs(players) do
        player.hand = {}
        player.currentBetInRound = 0
        player.totalBetInHand = 0
        -- Only set status to 'playing' if they have chips
        if player.chips > 0 then
             player.status = "playing"
        else
             player.status = "sitting_out" -- Or remove them? For now, sit out.
             log("Player "..player.name.." is sitting out (0 chips).")
        end
        -- isReady is reset implicitly by starting
    end

    -- Rotate dealer button
    dealerPosition = findNextPlayerIndex(dealerPosition) -- Find next *active* player for dealer
    if dealerPosition == 0 then dealerPosition = 1 end -- Fallback if only one player somehow

    log("Dealer position set to index: " .. dealerPosition .. " (Player: " .. players[dealerPosition].name .. ")")

    -- Determine blinds positions based on dealer
    local smallBlindIndex = findNextPlayerIndex(dealerPosition)
    local bigBlindIndex = findNextPlayerIndex(smallBlindIndex)

    -- Handle heads-up case (Dealer is SB)
    if #players == 2 then
        smallBlindIndex = dealerPosition
        bigBlindIndex = findNextPlayerIndex(dealerPosition)
    end

    log("Assigning blinds: SB Index " .. smallBlindIndex .. ", BB Index " .. bigBlindIndex)

    -- Post blinds automatically
    local function postBlind(playerIndex, blindAmount)
        local player = players[playerIndex]
        if not player then log("Error: Invalid player index for blind: "..playerIndex); return 0; end

        local amountToPost = math.min(player.chips, blindAmount) -- Cannot post more than available chips
        player.chips = player.chips - amountToPost
        player.currentBetInRound = amountToPost
        player.totalBetInHand = amountToPost -- Track total investment
        pot = pot + amountToPost
        log(player.name .. " posts blind of " .. amountToPost)
        if amountToPost == player.chips + amountToPost then -- Check if player went all-in posting blind
             player.status = "allin"
             log(player.name .. " is all-in posting blind.")
        end
        return amountToPost -- Return actual amount posted
    end

    local sbPosted = 0
    local bbPosted = 0
    if smallBlindIndex ~= 0 then sbPosted = postBlind(smallBlindIndex, gameSettings.smallBlind) end
    if bigBlindIndex ~= 0 then bbPosted = postBlind(bigBlindIndex, gameSettings.bigBlind) end

    currentHighestBet = math.max(sbPosted, bbPosted) -- Highest bet is now the BB (or SB if BB couldn't afford)
    minRaiseAmount = gameSettings.bigBlind -- Initial min raise is BB amount

    -- Deal hands (2 cards each)
    log("Dealing hands...")
    for i = 1, 2 do
        local currentDealIndex = dealerPosition -- Start dealing left of dealer
        for _ = 1, #players do
            currentDealIndex = findNextPlayerIndex(currentDealIndex)
            local player = players[currentDealIndex]
            if player and (player.status == "playing" or player.status == "allin") then -- Deal to active/all-in players
                local card = dealCard()
                if card then
                    table.insert(player.hand, card)
                else
                    log("Error: Ran out of cards during deal!") break
                end
            end
            if currentDealIndex == dealerPosition then break end -- Safety break for full circle
        end
    end

    -- Send hands privately AFTER dealing is complete
    for _, player in ipairs(players) do
         if player.status == "playing" or player.status == "allin" then
             sendToPlayer(player.id, { type = "deal_hand", hand = player.hand })
         end
    end

    log("Hands dealt. Starting preflop betting.")
    gameState = "preflop"

    -- Broadcast game start info (including blinds posted)
    broadcast({ type = "game_start",
                dealer = dealerPosition,
                smallBlind = smallBlindIndex,
                bigBlind = bigBlindIndex,
                pot = pot,
                currentHighestBet = currentHighestBet,
                players = getPublicPlayersTable() -- Send updated player list with statuses/chips
              })

    -- Determine first player to act (left of Big Blind)
    actionPlayerIndex = findNextPlayerIndex(bigBlindIndex)
    lastRaiserIndex = bigBlindIndex -- Initially, the BB is the 'last raiser'

    log("First action to player index: " .. actionPlayerIndex)
    requestAction(actionPlayerIndex)
    updateMonitor()
end


-- Action Handling
local function handlePlayerAction(senderID, actionData)
    local playerIndex = 0
    local player = nil
    for i, p in ipairs(players) do
        if p.id == senderID then
            player = p
            playerIndex = i
            break
        end
    end

    if not player then
        log("Error: Received action from unknown player ID " .. senderID)
        return
    end

    -- Validate if it's the player's turn
    if playerIndex ~= actionPlayerIndex then
       log("Warning: Action received from player " .. player.name .. " (ID: "..senderID..") out of turn. Expected index: "..actionPlayerIndex)
       sendToPlayer(player.id, { type = "error", message = "Not your turn."})
       return
    end

    -- Validate action based on game state
    if gameState ~= "preflop" and gameState ~= "flop" and gameState ~= "turn" and gameState ~= "river" then
        log("Warning: Action received from player " .. player.name .. " during invalid state: " .. gameState)
        sendToPlayer(player.id, { type = "error", message = "Cannot act now ("..gameState..")."})
        return
    end

    local action = actionData.action
    local amount = tonumber(actionData.amount) or 0 -- Ensure amount is a number
    local callAmount = currentHighestBet - player.currentBetInRound
    local canCheck = (callAmount <= 0)

    log("Processing action '" .. action .. "' from " .. player.name .. " (Index: " .. playerIndex .. ") Amount: " .. amount)

    local betPlaced = 0 -- Amount added to currentBetInRound this action

    -- Perform Action Logic
    if action == "fold" then
        player.status = "folded"
        log(player.name .. " folds.")
        broadcast({ type = "player_action", playerID = player.id, playerName = player.name, action = "fold", pot = pot, currentHighestBet = currentHighestBet, players = getPublicPlayersTable() })

    elseif action == "check" then
        if not canCheck then
            log("Invalid action: " .. player.name .. " tried to check when call is required.")
            sendToPlayer(player.id, { type = "error", message = "Cannot check, must call " .. callAmount .. " or raise."})
            requestAction(playerIndex) -- Re-request action from same player
            return
        end
        log(player.name .. " checks.")
        broadcast({ type = "player_action", playerID = player.id, playerName = player.name, action = "check", pot = pot, currentHighestBet = currentHighestBet, players = getPublicPlayersTable() })
        -- Note: Checking doesn't change lastRaiserIndex

    elseif action == "call" then
        if callAmount <= 0 then
            log("Invalid action: " .. player.name .. " tried to call when check is possible.")
            -- Treat as check? Or reject? Let's treat as check if callAmount is 0 or less.
             if callAmount == 0 then
                 log(player.name .. " calls (effectively checks).")
                 broadcast({ type = "player_action", playerID = player.id, playerName = player.name, action = "check", pot = pot, currentHighestBet = currentHighestBet, players = getPublicPlayersTable() })
                 -- No bet placed, proceed turn
             else -- callAmount < 0 shouldn't happen with correct logic
                 sendToPlayer(player.id, { type = "error", message = "Invalid call action."})
                 requestAction(playerIndex)
                 return
             end
        else
            local amountToCall = math.min(player.chips, callAmount) -- Can only call with available chips
            betPlaced = amountToCall
            player.chips = player.chips - amountToCall
            player.currentBetInRound = player.currentBetInRound + amountToCall
            log(player.name .. " calls " .. amountToCall .. ". Chips left: " .. player.chips .. ". Total bet in round: " .. player.currentBetInRound)

            if player.chips == 0 then
                player.status = "allin"
                log(player.name .. " is all-in by calling.")
            end
            broadcast({ type = "player_action", playerID = player.id, playerName = player.name, action = "call", amount = amountToCall, pot = pot, currentHighestBet = currentHighestBet, players = getPublicPlayersTable() })
            -- Note: Calling doesn't change lastRaiserIndex
        end

    elseif action == "bet" then
         if currentHighestBet > 0 then -- Cannot 'bet' if there's already a bet, must 'raise'
             log("Invalid action: " .. player.name .. " tried to bet when raise is required.")
             sendToPlayer(player.id, { type = "error", message = "Cannot bet, must call " .. callAmount .. " or raise."})
             requestAction(playerIndex)
             return
         end
         if amount <= 0 then
             log("Invalid action: " .. player.name .. " tried to bet zero/negative amount.")
             sendToPlayer(player.id, { type = "error", message = "Bet amount must be positive."})
             requestAction(playerIndex)
             return
         end
         -- Basic validation: Bet must be at least Big Blind unless going all-in for less
         if amount < gameSettings.bigBlind and amount < player.chips then
             log("Invalid action: " .. player.name .. " bet " .. amount .. " (less than BB).")
             sendToPlayer(player.id, { type = "error", message = "Bet must be at least " .. gameSettings.bigBlind .. " (or all-in)." })
             requestAction(playerIndex)
             return
         end

         local amountToBet = math.min(player.chips, amount)
         betPlaced = amountToBet
         player.chips = player.chips - amountToBet
         player.currentBetInRound = player.currentBetInRound + amountToBet
         currentHighestBet = player.currentBetInRound -- This bet sets the new highest bet
         minRaiseAmount = amountToBet -- The next raise must be at least this amount higher
         lastRaiserIndex = playerIndex -- This player is now the last aggressor

         log(player.name .. " bets " .. amountToBet .. ". Chips left: " .. player.chips .. ". New high bet: " .. currentHighestBet)
         if player.chips == 0 then
             player.status = "allin"
             log(player.name .. " is all-in betting.")
         end
         broadcast({ type = "player_action", playerID = player.id, playerName = player.name, action = "bet", amount = amountToBet, pot = pot, currentHighestBet = currentHighestBet, players = getPublicPlayersTable() })

    elseif action == "raise" then
        if callAmount < 0 then callAmount = 0 end -- Can always raise if action is on you, even if you could check
        local raiseAmount = amount - currentHighestBet -- The amount *added* on top of the current highest bet
        local minRaiseTotal = currentHighestBet + math.max(gameSettings.bigBlind, minRaiseAmount)

        if amount < minRaiseTotal and amount < player.currentBetInRound + player.chips then
            log("Invalid action: " .. player.name .. " raise to " .. amount .. " is less than minimum raise total of " .. minRaiseTotal)
            sendToPlayer(player.id, { type = "error", message = "Minimum raise is to " .. minRaiseTotal .. " (or all-in)." })
            requestAction(playerIndex)
            return
        end

        local totalAmountNeeded = amount - player.currentBetInRound -- Total chips needed for this action
        if totalAmountNeeded <= 0 then
             log("Invalid action: " .. player.name .. " raise to " .. amount .. " is not more than current bet.")
             sendToPlayer(player.id, { type = "error", message = "Raise amount must be higher than current bet." })
             requestAction(playerIndex)
             return
        end

        local amountToRaise = math.min(player.chips, totalAmountNeeded)
        betPlaced = amountToRaise -- Chips added this action
        player.chips = player.chips - amountToRaise
        player.currentBetInRound = player.currentBetInRound + amountToRaise -- This is the new total bet in round

        log(player.name .. " raises to " .. player.currentBetInRound .. " (added " .. amountToRaise .. "). Chips left: " .. player.chips)

        -- Update game state only if it was a valid raise (not just an all-in call for less than min raise)
        if player.currentBetInRound > currentHighestBet then
             minRaiseAmount = player.currentBetInRound - currentHighestBet -- The size of the raise itself becomes the new min raise amount
             currentHighestBet = player.currentBetInRound -- Set the new highest bet level
             lastRaiserIndex = playerIndex -- This player is the new aggressor
             log("New high bet: " .. currentHighestBet .. ". New min raise amount: " .. minRaiseAmount)
        else
             log("Raise was not higher than current bet (likely all-in call). High bet remains ".. currentHighestBet)
        end


        if player.chips == 0 then
            player.status = "allin"
            log(player.name .. " is all-in raising.")
        end
        broadcast({ type = "player_action", playerID = player.id, playerName = player.name, action = "raise", amount = player.currentBetInRound, pot = pot, currentHighestBet = currentHighestBet, players = getPublicPlayersTable() })

    elseif action == "allin" then
        local allInAmount = player.chips
        betPlaced = allInAmount
        local finalBetInRound = player.currentBetInRound + allInAmount
        player.chips = 0
        player.currentBetInRound = finalBetInRound
        player.status = "allin"
        log(player.name .. " goes all-in for " .. allInAmount .. "! Final bet in round: " .. finalBetInRound)

        -- Check if the all-in constitutes a valid raise
        if finalBetInRound > currentHighestBet then
            local raiseAmount = finalBetInRound - currentHighestBet
            -- Only update minRaiseAmount if the all-in raise was *at least* a min-raise itself
            if raiseAmount >= minRaiseAmount then
                 minRaiseAmount = raiseAmount
                 log("All-in constitutes a full raise. New min raise amount: " .. minRaiseAmount)
            else
                 log("All-in is less than a full raise ('under-raise'). Min raise amount ("..minRaiseAmount..") remains unchanged for subsequent players.")
            end
            currentHighestBet = finalBetInRound
            lastRaiserIndex = playerIndex
            log("New high bet: " .. currentHighestBet)
        else
             log("All-in is effectively a call. High bet remains ".. currentHighestBet)
        end
        broadcast({ type = "player_action", playerID = player.id, playerName = player.name, action = "allin", amount = finalBetInRound, pot = pot, currentHighestBet = currentHighestBet, players = getPublicPlayersTable() })

    else
        log("Error: Unknown action '" .. action .. "' received from " .. player.name)
        sendToPlayer(player.id, { type = "error", message = "Unknown action: " .. action })
        requestAction(playerIndex) -- Re-request action
        return
    end

    -- Action was valid and processed, advance to the next player/stage
    advanceTurn()
    updateMonitor() -- Update monitor after action and potential turn advance
end


-- Rednet Handling
local function openRednet()
    local sides = {"back", "top", "bottom", "left", "right", "front"}
    for _, side in ipairs(sides) do
        if rednet.open(side) then
            log("Rednet opened successfully on side: " .. side)
            return true
        end
    end
    log("Error: Failed to open rednet on any side. Is a modem attached?")
    print("Error: Failed to open rednet on any side.")
    return false
end

local function messageHandler()
    while true do
        local senderID, message, receivedProtocol = rednet.receive(protocol, 0.5) -- Check every 0.5 seconds

        if senderID then
            if receivedProtocol == protocol then
                -- log("Received message from " .. senderID .. " via protocol '" .. receivedProtocol .. "'") -- Can be noisy
                if type(message) == "table" and message.type then
                    -- log("Message content: " .. textutils.serialize(message)) -- Very noisy
                    if message.type == "join_request" then
                        addPlayer(senderID, message.name)
                    elseif message.type == "leave_request" then
                         removePlayer(senderID)
                    elseif message.type == "player_action" then
                        -- Ensure data sub-table exists
                        if type(message.data) == "table" and message.data.action then
                             handlePlayerAction(senderID, message.data)
                        else
                             log("Received invalid player_action format from "..senderID..": "..textutils.serialize(message))
                             sendToPlayer(senderID, {type="error", message="Invalid action format."})
                        end
                    elseif message.type == "ready_status" then
                         if gameState == "lobby" then
                             local player = nil
                             for _, p in ipairs(players) do if p.id == senderID then player = p break end end
                             if player then
                                 player.isReady = message.isReady
                                 log("Player " .. player.name .. " is now " .. (message.isReady and "ready" or "not ready"))
                                 broadcast({type="player_ready", playerID=senderID, isReady=message.isReady}, senderID) -- Inform others
                                 updateMonitor()
                                 -- Check if enough players are ready to auto-start
                                 local readyCount = 0
                                 for _, p in ipairs(players) do if p.isReady then readyCount = readyCount + 1 end end
                                 if readyCount >= gameSettings.minPlayers and #players >= gameSettings.minPlayers then
                                     log("Enough players ready, starting game...")
                                     startGame()
                                 end
                             end
                         else
                             log("Received ready_status outside of lobby from "..senderID)
                             sendToPlayer(senderID, {type="error", message="Can only set ready status in lobby."})
                         end
                    elseif message.type == "chat" then
                        local player = nil
                        for _, p in ipairs(players) do if p.id == senderID then player = p break end end
                        if player and type(message.text) == "string" and string.len(message.text) > 0 then
                            local chatText = string.sub(message.text, 1, 100) -- Limit chat message length
                            log("Chat from " .. player.name .. ": " .. chatText)
                            broadcast({type="chat_message", name=player.name, text=chatText}, nil) -- Send to everyone including sender
                        end
                    -- Add message type for manual start maybe?
                    -- elseif message.type == "admin_start_game" and senderID == hostID then
                    --     if gameState == "lobby" then startGame() end
                    else
                        log("Received unknown message type: " .. message.type .. " from ".. senderID)
                        -- Don't send error for unknown types, could be future features
                    end
                else
                    log("Received non-table or invalid message format from " .. senderID)
                    sendToPlayer(senderID, { type = "error", message = "Invalid message format." })
                end
            else
                 log("Received message from " .. senderID .. " with unexpected protocol: " .. (receivedProtocol or "nil"))
            end
        end

        -- Non-blocking tasks can go here (e.g., check timers, etc.)
        -- Example: Auto-start timer in lobby?

        -- Small sleep if receive timeout is very short or zero
        -- sleep(0.05) -- Already handled by receive timeout
    end
end

-- Main Execution
if not openRednet() then
    return -- Exit if rednet couldn't be opened
end

setupMonitor() -- Initial monitor setup
log("Poker server started. Host ID: " .. hostID)
log("Waiting for players to join...")
gameState = "lobby" -- Ensure starting state
updateMonitor() -- Initial monitor update

-- Start the main message handling loop
messageHandler()

-- Cleanup (never reached in normal operation)
log("Server shutting down.")
rednet.close()
if monitor then pcall(monitor.clear) end

