-- speedometer.lua
local peripheralName = "neuralConnector_0" -- Adjust this to your neural connector name
local connector = peripheral.wrap(peripheralName)

if not connector then
    error("Neural Connector not found.")
end

local function getPosition()
    local pos = connector.getPlayer().getPosition()
    return vector.new(pos.x, pos.y, pos.z)
end

local function calculateSpeed(pos1, pos2, deltaTime)
    local distance = (pos2 - pos1):length()
    return distance / deltaTime
end

-- Display loop
while true do
    local pos1 = getPosition()
    sleep(0.1) -- 100ms between samples (adjust for precision vs performance)
    local pos2 = getPosition()

    local speed = calculateSpeed(pos1, pos2, 0.1) -- blocks per second
    term.clear()
    term.setCursorPos(1, 1)
    print("Speed: " .. string.format("%.2f", speed) .. " blocks/sec")
end
