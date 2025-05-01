-- Function to find the disk drive and mount path
function getDiskMount()
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "drive" and disk.isDiskPresent(side) then
            return disk.getMountPath(side), side
        end
    end
    return nil, nil
end

-- Function to get balance from the card
function getBalance()
    local mount, side = getDiskMount()
    if not mount then
        print("Insert your debit card (floppy disk) to begin.")
        return nil
    end

    local path = mount .. "/balance.txt"
    if not fs.exists(path) then
        print("No balance file found on the disk.")
        return nil
    end

    local file = fs.open(path, "r")
    local content = file.readAll()
    file.close()
    local balance = tonumber(content)

    if not balance then
        print("Invalid balance format on the disk.")
        return nil
    end

    return balance, mount
end

-- Function to update balance
function setBalance(mount, newBalance)
    local file = fs.open(mount .. "/balance.txt", "w")
    file.write(tostring(newBalance))
    file.close()
end

-- Function to simulate a slot spin
function spin()
    local symbols = {"🍒", "🔔", "🍋", "⭐", "💎"}
    return symbols[math.random(#symbols)], symbols[math.random(#symbols)], symbols[math.random(#symbols)]
end

-- MAIN PROGRAM
math.randomseed(os.time())
term.clear()
term.setCursorPos(1,1)
print("🎰 Welcome to the Slot Machine 🎰")

local balance, mount = getBalance()
if not balance then
    return
end

print("Your current chip balance: " .. balance)

local bet = 10
print("Spinning costs " .. bet .. " chips...")

if balance < bet then
    print("Insufficient chips to play.")
    return
end

-- Deduct bet
balance = balance - bet
setBalance(mount, balance)
print("You bet " .. bet .. " chips.")
sleep(1)

-- Spin the slots
local a, b, c = spin()
print("\n[ " .. a .. " ] [ " .. b .. " ] [ " .. c .. " ]")

-- Check results
local win = 0
if a == b and b == c then
    win = 50
    print("JACKPOT! You win 50 chips!")
elseif a == b or b == c or a == c then
    win = 20
    print("You matched two! You win 20 chips.")
else
    print("No match. Better luck next time!")
end

-- Update balance with winnings
balance = balance + win
setBalance(mount, balance)
print("New chip balance: " .. balance)
