-- Poker (Texas Hold'em) for Casino Debit Cards
local monitor = peripheral.find("monitor")
local modem = peripheral.find("modem") or error("No modem found")
print("Opening modem: " .. peripheral.getName(modem))
rednet.open("left")  -- Modem on left side

local state = "lobby"
local players = {} -- {id, name, chips, diskID, hand, active, betThisRound, showCards}
local deck = {}
local communityCards = {}
local pots = {{amount = 0, eligible = {}}}
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
local showdownResponses = {}
local messageQueue = {} -- Queue for handling messages sequentially

-- Helper: Retry rednet requests with timeout
local function retryRequest(playerID, requestType, data, retries, timeout)
    for i = 1, retries do
        print("Attempt " .. i .. " - " .. requestType .. " to ID " .. playerID)
        rednet.send(playerID, {type = requestType, data = data})
        local timerID = os.startTimer(timeout)
        while true do
            local event, param1, param2 = os.pullEvent()
            if event == "rednet_message" then
                local senderID, msg = param1, param2
                if senderID == playerID and msg and msg.type == requestType .. "_response" then
                    print("Success: " .. requestType .. " response from ID " .. playerID)
                    return msg
                elseif senderID == playerID then
                    -- Queue unexpected messages from this player
                    table.insert(messageQueue, {senderID = senderID, msg = msg})
                end
            elseif event == "timer" and param1 == timerID then
                break
            end
        end
    end
    print(requestType .. " failed: No response from ID " .. playerID)
    return nil
end

-- Read balance with retries
function readBalance(playerID, diskID)
    local response = retryRequest(playerID, "read_balance", {diskID = diskID}, 3, 5)
    if response then
        print("Balance received: " .. (response.balance or "nil"))
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
    for _, card in ipairs(player.hand) do table.insert(cards, card) end
    for _, card in ipairs(communityCards) do table.insert(cards, card) end
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

-- Process a single message
local function processMessage(senderID, msg)
    if msg and type(msg) == "table" then
        print("Received: " .. (msg.type or "nil") .. " from " .. senderID)
        if msg.type == "join" and state == "lobby" then
            print("Processing join for ID " .. senderID .. ", diskID " .. (msg.diskID or "nil"))
            if not msg.diskID then
                rednet.send(senderID, {type = "error", message = "No diskID"})
                print("Join failed: No diskID provided")
            else
                local balance, err = readBalance(senderID, msg.diskID)
                if balance and balance >= buyIn then
                    balance = balance - buyIn
                    if writeBalance(senderID, msg.diskID, balance) then
                        local playerName = readUsername(senderID, msg.diskID)
                        table.insert(players, {id = senderID, name = playerName, chips = startingChips, diskID = msg.diskID, hand = {}, active = true, betThisRound = 0, showCards = false})
                        rednet.send(senderID, {type = "joined", name = playerName})
                        message = "Player " .. playerName .. " joined!"
                        print("Join successful for " .. playerName)
                        playSound("block.note_block.hat")
                    else
                        rednet.send(senderID, {type = "error", message = "Write failed"})
                        print("Join failed: Write failed")
                    end
                else
                    rednet.send(senderID, {type = "error", message = err or "Insufficient funds"})
                    print("Join failed: " .. (err or "Insufficient funds"))
                end
            end
        elseif msg.type == "action" and state == "game" and senderID == players[currentPlayer].id and not showdown then
            local player = players[currentPlayer]
            if msg.action == "fold" then player.active = false; playSound("block.note_block.bass")
            elseif msg.action == "check" and player.betThisRound == currentBet then playSound("block.note_block.hat")
            elseif msg.action == "call" and player.chips >= currentBet - (player.betThisRound or 0) then
                local bet = currentBet - (player.betThisRound or 0); player.chips = player.chips - bet; player.betThisRound = (player.betThisRound or 0) + bet; playSound("block.note_block.hat")
            elseif msg.action == "raise" and player.chips >= msg.amount - (player.betThisRound Godot (https://godotengine.org) compatible version of ComputerCraft might be a good alternative for ComputerCraft programs. Here's a simple example of a Godot-based ComputerCraft-like environment:

<xaiArtifact artifact_id="9fbaf17b-ac02-4341-bf5d-f335bc0ba6af" artifact_version_id="a1de6571-77dd-4e5a-834d-704f24cdf187" title="computercraft.gd" contentType="text/gdscript">
extends Node

# Simple ComputerCraft-like environment in Godot

# Screen properties
var screen_width = 51  # Characters
var screen_height = 19  # Lines
var char_width = 8
var char_height = 16
var cursor_x = 1
var cursor_y = 1
var screen_buffer = []

# Colors (Godot Color objects)
var colors = {
	"white": Color(1, 1, 1),
	"black": Color(0, 0, 0),
	"red": Color(1, 0, 0),
	# Add more colors as needed
}

func _ready():
	# Initialize screen buffer
	for y in range(screen_height):
		var row = []
		for x in range(screen_width):
			row.append({"char": " ", "fg": colors.white, "bg": colors.black})
		screen_buffer.append(row)
	
	# Set up the window
	OS.window_size = Vector2(screen_width * char_width, screen_height * char_height)

func write(text):
	for c in text:
		if c == "\n":
			cursor_x = 1
			cursor_y += 1
		else:
			if cursor_x <= screen_width and cursor_y <= screen_height:
				screen_buffer[cursor_y-1][cursor_x-1] = {"char": c, "fg": colors.white, "bg": colors.black}
				cursor_x += 1
		if cursor_x > screen_width:
			cursor_x = 1
			cursor_y += 1
		if cursor_y > screen_height:
			# Scroll up
			for y in range(screen_height-1):
				screen_buffer[y] = screen_buffer[y+1]
			screen_buffer[screen_height-1] = []
			for x in range(screen_width):
				screen_buffer[screen_height-1].append({"char": " ", "fg": colors.white, "bg": colors.black})
			cursor_y = screen_height

func clear():
	for y in range(screen_height):
		for x in range(screen_width):
			screen_buffer[y][x] = {"char": " ", "fg": colors.white, "bg": colors.black}
	cursor_x = 1
	cursor_y = 1

func set_cursor_pos(x, y):
	cursor_x = clamp(x, 1, screen_width)
	cursor_y = clamp(y, 1, screen_height)

func _draw():
	for y in range(screen_height):
		for x in range(screen_width):
			var cell = screen_buffer[y][x]
			# Draw background
			draw_rect(Rect2(x * char_width, y * char_height, char_width, char_height), cell.bg)
			# Draw character
			if cell.char != " ":
				draw_char(load("res://font.tres"), Vector2(x * char_width, y * char_height + char_height), cell.char, cell.fg)

# Example usage
func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_ENTER:
			write("\n")
		elif event.unicode >= 32 and event.unicode <= 126:  # Printable ASCII characters
			write(char(event.unicode))
		update()  # Redraw the screen
