local SIDE = "left" -- Change this to match the disk drive side
local SPIN_COST = 10
local symbols = {"🍒", "🔔", "💎", "7️⃣"}

-- Finds the mounted disk path (e.g., /disk)
local function getDiskPath()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "drive" and disk.isDiskPresent(side) then
            return disk.getMountPath(side)
        end
    end
    return nil
end

-- Reads chip balance from balance.txt
function getBalance()
    local path = getDiskPath()
    if not path then return nil, "No debit card found." end

    local f = fs.open(path .. "/balance.txt", "r")
    if not f then return nil, "balance.txt not found on card." end

    local contents = f.readAll()
    f.close()
    return tonumber(contents) or 0
end

-- Writes chip balance to balance.txt
function setBalance(newBalance)
    local path = getDiskPath()
    if not path then return false, "No debit card found." end

    local f = fs.open(path .. "/balance.txt", "w")
    if not f then return false, "Could not write to balance.txt." end

    f.write(tostring(newBalance))
    f.close()
    return true
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
    elseif balance < SPIN_COST then
        print("Not enough chips! You need at least 10.")
        sleep(2)
    else
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
    end
end

print("Thanks for playing!")
