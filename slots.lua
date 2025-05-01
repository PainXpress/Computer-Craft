local SIDE = "left" -- Change this to match the disk drive side
local SPIN_COST = 10
local symbols = {"🍒", "🔔", "💎", "7️⃣"}

-- Reads chip balance from disk
local function getBalance()
    if not disk.isPresent(SIDE) then return nil, "Insert your debit card." end
    local file = fs.open(SIDE.."/balance.txt", "r")
    if not file then return 0 end
    local balance = tonumber(file.readAll())
    file.close()
    return balance or 0
end

-- Writes chip balance to disk
local function setBalance(amount)
    local file = fs.open(SIDE.."/balance.txt", "w")
    file.write(tostring(amount))
    file.close()
end

-- Spin the reels (random symbols)
local function spinReels()
    local result = {}
    for i = 1, 3 do
        table.insert(result, symbols[math.random(1, #symbols)])
    end
    return result
end

-- Calculates winnings
local function calculateWinnings(reels)
    if reels[1] == reels[2] and reels[2] == reels[3] then
        if reels[1] == "7️⃣" then
            return 100
        elseif reels[1] == "💎" then
            return 50
        elseif reels[1] == "🔔" then
            return 30
        elseif reels[1] == "🍒" then
            return 20
        end
    elseif reels[1] == reels[2] or reels[2] == reels[3] or reels[1] == reels[3] then
        return 5 -- small match
    else
        return 0 -- no win
    end
end

-- Main game loop
while true do
    term.clear()
    term.setCursorPos(1,1)
    print("Welcome to the Slot Machine!")
    print("Insert your debit card and press Enter to play (10 chips/spin).")
    print("")

    io.read()

    local balance, err = getBalance()
    if not balance then
        print("Error: " .. err)
        sleep(2)
        goto continue
    end

    if balance < SPIN_COST then
        print("Not enough chips! You need at least 10.")
        sleep(2)
        goto continue
    end

    -- Deduct cost
    balance = balance - SPIN_COST
    setBalance(balance)

    -- Spin
    local reels = spinReels()
    local winnings = calculateWinnings(reels)
    balance = balance + winnings
    setBalance(balance)

    -- Show result
    term.clear()
    term.setCursorPos(1,1)
    print("🎰 Spinning...")
    sleep(1)
    print(table.concat(reels, " "))
    print("")

    if winnings > 0 then
        print("You won " .. winnings .. " chips!")
    else
        print("No win. Better luck next time!")
    end

    print("Current balance: " .. balance .. " chips")
    print("Play again? (y/n)")
    local answer = read()
    if answer:lower() ~= "y" then
        break
    end

    ::continue::
end

print("Thanks for playing!")
