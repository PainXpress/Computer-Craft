-- Poker Player Client Code (player.lua) - Rewritten
--[[
    ComputerCraft Poker Game - Player Client
    Connects to the host, displays game state, and sends player actions.
    Rewritten with improved display, state handling, and action prompts.
]]

-- Configuration
local playerName = "Player" .. os.computerID() -- Default name
local hostID = nil -- Will be set after joining
local protocol = "poker_game" -- Must match the server's protocol
local connectionTimeout = 5 -- Seconds to wait for server responses
local debug = true -- Enable/disable debug messages

-- Game State Variables (Client Side)
local myID = os.computerID()
local chips = 0
local hand = {}
local communityCards = {}
local currentPot = 0
local currentHighestBet = 0 -- Highest bet player needs to match
local myCurrentBetInRound = 0 -- How much *this* player has bet in the current round
local myTurn = false
local canCheck = false
local callAmount = 0
local minRaiseTo = 0 -- The total bet amount for a minimum raise
local gameState = "disconnected" -- disconnected, connecting, lobby, playing, observing, showdown, hand_over
local players = {} -- Local cache of player list {id, name, chips, status, isReady, currentBetInRound}
local isReady = false -- For lobby
local lastMessage = "" -- For displaying status messages

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
    if debug then
        print("[DEBUG] " .. tostring(message))
    end
    -- Basic monitor logging
    if monitor then
        pcall(function()
            local w, h = monitor.getSize()
            local x, y = monitor.getCursorPos()
            monitor.setCursorPos(1, h)
            monitor.clearLine()
            monitor.write("[DBG] " .. string.sub(tostring(message), 1, w - 6))
            monitor.setCursorPos(x, y)
        end)
    end
end

local function updateDisplay()
    if not monitor then return end
    pcall(function()
        monitor.clear()
        local w, h = monitor.getSize()
        local line = 1

        -- Line 1: Title, Name
        monitor.setCursorPos(1, line)
        monitor.write(string.format("--- Poker Client --- Name: %s (ID:%d) ---", playerName, myID))
        line = line + 1

        -- Line 2: Status, Host, Chips
        monitor.setCursorPos(1, line)
        monitor.write(string.format("State: %s | Host: %s | Chips: %d", gameState, hostID or "N/A", chips))
        line = line + 1

        -- Line 3: Hand
        monitor.setCursorPos(1, line)
        monitor.write("Hand: " .. (#hand > 0 and table.concat(hand, " ") or "N/A"))
        line = line + 1

        -- Line 4: Community Cards
        monitor.setCursorPos(1, line)
        monitor.write("Board: " .. (#communityCards > 0 and table.concat(communityCards, " ") or "N/A"))
        line = line + 1

        -- Line 5: Pot, Current Bet Info
        monitor.setCursorPos(1, line)
        monitor.write(string.format("Pot: %d | High Bet: %d | My Bet: %d", currentPot, currentHighestBet, myCurrentBetInRound))
        line = line + 1

        -- Line 6: Separator
        monitor.setCursorPos(1, line)
        monitor.write(string.rep("-", w))
        line = line + 1

        -- Player List Area (Dynamic height)
        local playerAreaHeight = h - line - 3 -- Reserve 3 lines for prompt/status/debug
        monitor.setCursorPos(1, line)
        monitor.write("Players:")
        line = line + 1
        for i, player in ipairs(players) do
            if (line - 7) <= playerAreaHeight then -- Check if enough space in allocated area
                monitor.setCursorPos(2, line)
                local indicator = (player.id == myID) and " (*You*)" or ""
                local readyIndicator = (gameState == "lobby" and player.isReady) and " [R]" or ""
                local statusIndicator = string.format(" S:%s", player.status or "N/A")
                local betIndicator = (player.currentBetInRound and player.currentBetInRound > 0) and (" B:"..player.currentBetInRound) or ""
                -- TODO: Add dealer/turn indicators based on server info if available

                local playerLine = string.format("%d. %s%s C:%d%s%s%s",
                                     i, player.name or "??", indicator, player.chips or 0,
                                     statusIndicator, betIndicator, readyIndicator)
                monitor.write(string.sub(playerLine, 1, w-2))
                line = line + 1
            else
                -- Indicate more players exist if list truncated
                monitor.setCursorPos(2, line)
                monitor.write("...")
                line = line + 1
                break
            end
        end

        -- Action Prompt Area (if myTurn)
        monitor.setCursorPos(1, h - 2) -- Second to last line
        monitor.clearLine()
        if myTurn then
            monitor.setTextColor(colors.yellow)
            local prompt = "Your Turn! "
            if canCheck then prompt = prompt .. "check, " end
            if callAmount > 0 then prompt = prompt .. "call(" .. callAmount .. "), " end
            prompt = prompt .. "fold, raise <amt>, bet <amt>, allin"
            if minRaiseTo > 0 then prompt = prompt .. " (Min Raise To: " .. minRaiseTo .. ")" end
            monitor.write(prompt)
            monitor.setTextColor(colors.white)
        else
             -- Display last important message/status
             monitor.write("Status: " .. lastMessage)
        end

        -- Debug line is handled by log function
    end)
end

local function sendToServer(message)
    if not hostID then
        log("Error: Cannot send message, not connected to a host.")
        print("Error: Not connected to a host.")
        return false
    end
    -- log("Sending to host " .. hostID .. ": " .. textutils.serialize(message)) -- Noisy
    return rednet.send(hostID, message, protocol)
end

-- Action Functions
local function sendAction(action, amount)
    if not myTurn then
        print("Not your turn.")
        lastMessage = "Not your turn."
        updateDisplay()
        return
    end
    log("Sending action: " .. action .. (amount and (" " .. amount) or ""))
    if sendToServer({ type = "player_action", data = { action = action, amount = amount } }) then
        myTurn = false -- Assume turn ends after sending action, server will confirm/re-request if invalid
        lastMessage = "Action sent: " .. action .. (amount and (" "..amount) or "")
        updateDisplay() -- Update display immediately
    else
        lastMessage = "Failed to send action."
        updateDisplay()
    end
end

local function sendChatMessage(text)
    if not hostID then print("Not connected."); return end
    if type(text) ~= "string" or #text == 0 then print("Cannot send empty chat."); return end
    lastMessage = "Sending chat..."
    updateDisplay()
    sendToServer({type="chat", text=text})
end

local function toggleReady()
    if gameState == "lobby" then
        isReady = not isReady
        log("Toggling ready status to: " .. (isReady and "Ready" or "Not Ready"))
        lastMessage = "Set status to " .. (isReady and "Ready" or "Not Ready")
        sendToServer({type="ready_status", isReady=isReady})
        -- Update local player state immediately for better UX
        for _, p in ipairs(players) do
            if p.id == myID then
                p.isReady = isReady
                break
            end
        end
        updateDisplay()
    else
        print("Can only set ready status in the lobby.")
        lastMessage = "Can only set ready in lobby."
        updateDisplay()
    end
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

local function connectToHost(targetHostID)
    if hostID then print("Already connected/connecting."); return end
    if not targetHostID or tonumber(targetHostID) == nil then print("Invalid host ID."); return end

    gameState = "connecting"
    hostID = tonumber(targetHostID)
    lastMessage = "Connecting to host " .. hostID .. "..."
    log("Attempting to join host: " .. hostID)
    updateDisplay()

    if not sendToServer({ type = "join_request", name = playerName }) then
         log("Failed to send join request (rednet error?).")
         print("Failed to send join request.")
         lastMessage = "Failed to send join request."
         hostID = nil
         gameState = "disconnected"
         updateDisplay()
         return
    end

    -- Wait for confirmation
    log("Waiting for join confirmation from host...")
    term.write("Waiting for confirmation...")
    local senderID, message, receivedProtocol = rednet.receive(protocol, connectionTimeout)
    term.clearLine()
    term.setCursorPos(1, term.getCursorPos())

    if senderID == hostID and receivedProtocol == protocol and type(message) == "table" then
        if message.type == "join_confirm" then
            gameState = message.gameState or "lobby" -- Use state from server if provided
            players = message.players or {} -- Get initial player list
            -- Find my info in the player list
            local foundSelf = false
            for _, p in ipairs(players) do
                 if p.id == myID then
                     chips = p.chips
                     isReady = p.isReady
                     myCurrentBetInRound = p.currentBetInRound or 0
                     foundSelf = true
                     break
                 end
            end
            if not foundSelf then -- Should not happen if server includes us
                 log("Error: Did not find self in player list from server.")
                 -- Attempt to find chips from settings as fallback
                 chips = (message.settings and message.settings.startingChips) or 0
            end

            log("Successfully joined game. Host: " .. message.hostID .. " State: " .. gameState)
            print("Connected to game!")
            lastMessage = "Connected! State: " .. gameState
            updateDisplay()
        elseif message.type == "error" then
            log("Join failed: " .. message.message)
            print("Join failed: " .. message.message)
            lastMessage = "Join failed: " .. message.message
            hostID = nil
            gameState = "disconnected"
            updateDisplay()
        else
            log("Received unexpected message type during join: " .. message.type)
            print("Connection error: Unexpected response.")
            lastMessage = "Connection error: Unexpected response."
            hostID = nil
            gameState = "disconnected"
            updateDisplay()
        end
    else
        log("Join timed out or received invalid response.")
        print("Connection failed: No response from host " .. hostID)
        lastMessage = "Connection failed: No response from host."
        hostID = nil
        gameState = "disconnected"
        updateDisplay()
    end
end

-- Updates the local player list cache based on server data
local function updateLocalPlayers(serverPlayers)
    if type(serverPlayers) ~= "table" then return end
    players = serverPlayers -- Replace local cache with server's version
    -- Update my specific state from the list
    local foundSelf = false
    for _, p in ipairs(players) do
        if p.id == myID then
            chips = p.chips
            myCurrentBetInRound = p.currentBetInRound or 0
            -- Don't override isReady here, managed locally by toggleReady
            -- Status might be useful: if p.status == "folded" then myTurn = false end
            foundSelf = true
            break
        end
    end
    if not foundSelf then log("Warning: Self not found in updated player list.") end
end


local function messageHandler()
    while true do
        -- Non-blocking receive (timeout 0) or short timeout
        local senderID, message, receivedProtocol = rednet.receive(protocol, 0.2) -- Check frequently

        if senderID and receivedProtocol == protocol then
            if senderID == hostID then
                -- log("Received message from host: " .. textutils.serialize(message)) -- Noisy
                if type(message) == "table" and message.type then
                    -- Handle different message types from the server
                    if message.type == "error" then
                        print("Server Error: " .. message.message)
                        log("Server Error: " .. message.message)
                        lastMessage = "Server Error: " .. message.message
                        myTurn = false -- Assume error might stop turn

                    elseif message.type == "state_update" then -- Generic state update
                         log("Received state update: " .. message.gameState)
                         gameState = message.gameState
                         if message.players then updateLocalPlayers(message.players) end
                         if message.pot then currentPot = message.pot end
                         if message.currentHighestBet then currentHighestBet = message.currentHighestBet end
                         if message.communityCards then communityCards = message.communityCards end
                         lastMessage = "Game state is now " .. gameState
                         myTurn = false -- Reset turn on general state changes unless specifically requested

                    elseif message.type == "game_start" then
                        gameState = "preflop"
                        myTurn = false
                        hand = {} -- Clear hand before getting new one
                        communityCards = {}
                        currentPot = message.pot or 0
                        currentHighestBet = message.currentHighestBet or 0
                        if message.players then updateLocalPlayers(message.players) end
                        log("Game started.")
                        lastMessage = "New hand started!"

                    elseif message.type == "deal_hand" then
                        hand = message.hand or {}
                        log("Received hand: " .. table.concat(hand, " "))
                        lastMessage = "Received hand."

                    elseif message.type == "player_joined" then
                         if message.player then
                             -- Avoid duplicates if server sends full list later
                             local exists = false
                             for _, p in ipairs(players) do if p.id == message.player.id then exists = true break end end
                             if not exists then table.insert(players, message.player) end
                             log("Player joined: " .. message.player.name)
                             lastMessage = message.player.name .. " joined."
                         end
                         -- Request full list maybe? Or wait for next state update.

                    elseif message.type == "player_left" then
                         local leftName = "Player " .. message.playerID
                         for i = #players, 1, -1 do
                             if players[i].id == message.playerID then
                                 leftName = players[i].name
                                 log("Player left: " .. leftName)
                                 table.remove(players, i)
                                 break
                             end
                         end
                         lastMessage = leftName .. " left."

                    elseif message.type == "player_action" then
                         -- Update display based on other players' actions
                         log("Player " .. (message.playerName or message.playerID) .. " action: " .. message.action)
                         currentPot = message.pot or currentPot
                         currentHighestBet = message.currentHighestBet or currentHighestBet
                         if message.players then updateLocalPlayers(message.players) end -- Update all player states
                         lastMessage = (message.playerName or message.playerID) .. " " .. message.action .. (message.amount and (" "..message.amount) or "")

                    elseif message.type == "request_action" then
                         log("Received action request.")
                         myTurn = true
                         gameState = "playing" -- Ensure state is playing if action requested
                         currentPot = message.pot or currentPot
                         currentHighestBet = message.currentHighestBet or currentHighestBet
                         callAmount = message.callAmount or 0
                         canCheck = message.canCheck or false
                         minRaiseTo = message.minRaiseTo or 0
                         if message.players then updateLocalPlayers(message.players) end -- Get latest state
                         if message.communityCards then communityCards = message.communityCards end
                         print("--- YOUR TURN ---")
                         term.setTextColor(colors.yellow)
                         local prompt = ""
                         if canCheck then prompt = prompt .. "check, " end
                         if callAmount > 0 then prompt = prompt .. "call(" .. callAmount .. "), " end
                         prompt = prompt .. "fold, raise <amt>, bet <amt>, allin"
                         if minRaiseTo > 0 then prompt = prompt .. " (Min Raise To: " .. minRaiseTo .. ")" end
                         print(prompt)
                         term.setTextColor(colors.white)
                         lastMessage = "Received action request."

                    elseif message.type == "community_cards" then
                         communityCards = message.cards or communityCards
                         currentPot = message.pot or currentPot
                         log("Community cards updated: " .. table.concat(communityCards, " "))
                         lastMessage = "Community cards dealt."
                         myTurn = false -- Turn usually starts after cards are dealt

                    elseif message.type == "showdown" then
                         log("Showdown phase.")
                         gameState = "showdown"
                         communityCards = message.communityCards or communityCards
                         currentPot = message.pot or currentPot
                         lastMessage = "Showdown!"
                         myTurn = false
                         -- Display final hands from message.players
                         print("--- SHOWDOWN ---")
                         print("Board: " .. table.concat(communityCards, " "))
                         if type(message.players) == "table" then
                             for _, p_info in ipairs(message.players) do
                                 print(string.format("  %s (%s): %s", p_info.name, p_info.status, table.concat(p_info.hand or {}, " ")))
                             end
                         end

                    elseif message.type == "winner_info" then
                         log("Winner announced: " .. message.winnerName)
                         lastMessage = message.winnerName .. " wins " .. message.amountWon .. " chips!"
                         print(lastMessage)
                         myTurn = false

                    elseif message.type == "hand_over" then
                         log("Hand over.")
                         gameState = "hand_over"
                         currentPot = message.pot or currentPot
                         if message.players then updateLocalPlayers(message.players) end
                         lastMessage = "Hand over. Final Pot: " .. currentPot
                         myTurn = false
                         hand = {} -- Clear hand after it's over
                         communityCards = {}
                         isReady = false -- Require ready for next hand

                    elseif message.type == "player_ready" then
                        for _, p in ipairs(players) do
                            if p.id == message.playerID then
                                p.isReady = message.isReady
                                log("Player " .. p.name .. " ready status: " .. tostring(p.isReady))
                                lastMessage = p.name .. (p.isReady and " is ready." or " is not ready.")
                                break
                            end
                        end

                     elseif message.type == "chat_message" then
                        -- Avoid printing our own chat message if server relays it
                        if message.name ~= playerName then
                            print("[" .. message.name .. "]: " .. message.text)
                            -- Don't update lastMessage for chat
                        end

                    else
                        log("Received unhandled message type from host: " .. message.type)
                    end
                    -- Update display after processing any message
                    updateDisplay()
                else
                     log("Received invalid message format from host.")
                     lastMessage = "Received invalid message from host."
                     updateDisplay()
                end
            else
                 log("Received message from unexpected sender: " .. senderID .. " (Expected host: " .. (hostID or "None") .. ")")
                 -- Ignore messages not from host
            end
        end

        -- Allow other tasks or just sleep briefly
        sleep(0.05)
    end
end

-- Command Handling
local function commandHandler()
    while true do
        term.setCursorPos(1, term.getSize()) -- Ensure cursor is at the bottom line for input
        term.clearLine()
        write("> ")
        local input = read()
        local args = {}
        for word in string.gmatch(input, "[^%s]+") do
            table.insert(args, word)
        end
        local command = args[1] and string.lower(args[1]) or nil

        if command then
            -- Connection/Setup Commands
            if command == "connect" or command == "join" then
                connectToHost(args[2]) -- connectToHost handles validation
            elseif command == "name" then
                 if #args >= 2 then
                     playerName = table.concat(args, " ", 2)
                     print("Name set to: " .. playerName)
                     log("Name changed to: " .. playerName)
                     lastMessage = "Name set to " .. playerName
                     -- TODO: Optionally notify server of name change if already connected?
                     updateDisplay()
                 else
                     print("Usage: name <your_name>")
                 end
            elseif command == "leave" or command == "disconnect" then
                if hostID then
                    sendToServer({ type = "leave_request" })
                    print("Sent leave request to host.")
                    lastMessage = "Disconnecting..."
                    hostID = nil
                    gameState = "disconnected"
                    hand = {}
                    communityCards = {}
                    players = {}
                    chips = 0
                    isReady = false
                    myTurn = false
                    updateDisplay()
                else
                    print("Not connected to any host.")
                end
            elseif command == "ready" then
                 toggleReady()
            elseif command == "chat" or command == "say" then
                 if #args >= 2 then
                     local text = table.concat(args, " ", 2)
                     sendChatMessage(text)
                 else
                     print("Usage: chat <message>")
                 end
            -- In-game actions (check myTurn flag)
            elseif command == "fold" then
                sendAction("fold")
            elseif command == "check" then
                if myTurn and not canCheck then
                     print("Cannot check, must call "..callAmount.." or raise.")
                     lastMessage = "Cannot check."
                     updateDisplay()
                else
                     sendAction("check")
                end
            elseif command == "call" then
                 if myTurn and callAmount <= 0 and canCheck then
                     print("Cannot call, check instead.")
                     lastMessage = "Cannot call, check instead."
                     updateDisplay()
                 else
                     sendAction("call") -- Server validates if call is possible/needed
                 end
            elseif command == "bet" then
                if #args >= 2 then
                    local amount = tonumber(args[2])
                    if amount and amount > 0 then
                        sendAction("bet", amount)
                    else
                        print("Invalid bet amount.")
                        lastMessage = "Invalid bet amount."
                        updateDisplay()
                    end
                else
                    print("Usage: bet <amount>")
                end
            elseif command == "raise" then
                 if #args >= 2 then
                    local amount = tonumber(args[2])
                    if amount and amount > 0 then
                        -- Client-side check for minimum raise? Or let server handle it?
                        -- Let server handle validation for now.
                        sendAction("raise", amount)
                    else
                        print("Invalid raise amount.")
                        lastMessage = "Invalid raise amount."
                        updateDisplay()
                    end
                else
                    print("Usage: raise <amount>")
                end
            elseif command == "allin" then
                sendAction("allin")
            -- Other commands
            elseif command == "help" then
                print("Commands:")
                print("  connect <host_id> - Connect to a poker server")
                print("  name <your_name>  - Set your player name")
                print("  leave             - Disconnect from the server")
                print("  ready             - Toggle ready status in lobby")
                print("  chat <message>    - Send a chat message")
                print("  exit              - Quit the client")
                if myTurn then
                    print("Your Turn Actions: fold, check, call, bet <amt>, raise <amt>, allin")
                end
            elseif command == "redraw" then -- Manual redraw if display gets messed up
                 updateDisplay()
            elseif command == "exit" then
                 if hostID then
                    sendToServer({ type = "leave_request" }) -- Attempt graceful disconnect
                 end
                 print("Exiting.")
                 break -- Exit the command loop
            else
                 print("Unknown command: '" .. command .. "'. Type 'help' for options.")
                 if not myTurn and (command == "fold" or command == "check" or command == "call" or command == "bet" or command == "raise" or command == "allin") then
                     print("(It's not your turn to perform game actions.)")
                     lastMessage = "Not your turn."
                     updateDisplay()
                 end
            end
        end
    end
end

-- Main Execution
if not openRednet() then
    return -- Exit if rednet couldn't be opened
end

setupMonitor() -- Initial monitor setup
log("Poker client started. My ID: " .. myID)
print("Poker Client Initialized. My ID: " .. myID)
print("Use 'connect <host_id>' to join a game.")
print("Use 'name <your_name>' to set your name.")
lastMessage = "Initialized. Waiting for connection."
updateDisplay() -- Initial display update

-- Start background message listener and foreground command handler using parallel API
parallel.waitForAny(messageHandler, commandHandler)

-- Cleanup
log("Client shutting down.")
rednet.close()
if monitor then pcall(monitor.clear) end
term.setTextColor(colors.white) -- Reset terminal colors
term.setCursorPos(1, term.getSize())
term.clearLine()

