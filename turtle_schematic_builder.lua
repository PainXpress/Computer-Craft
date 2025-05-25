-- turtle_schematic_builder.lua
-- Automatically detects chest and disk drive, loads schematic JSON, and prepares for building

local json = require("json") -- Assumes json.lua is installed on the turtle or on the disk

-- Auto-detect peripherals
local function detectPeripheral(typeName)
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == typeName then
      return side
    end
  end
  return nil
end

local function detectInventory()
  for _, side in ipairs(peripheral.getNames()) do
    local p = peripheral.wrap(side)
    if p and p.list then
      return side
    end
  end
  return nil
end

-- Step 1: Detect peripherals
local diskSide = detectPeripheral("drive")
if not diskSide then error("Disk drive not found!") end

local chestSide = detectInventory()
if not chestSide then error("Inventory (e.g., chest) not found!") end

-- Step 2: Read JSON file from disk
local path = "/disk/schematic.json"
local f = fs.open(path, "r")
if not f then error("Failed to open schematic.json from disk") end

local content = f.readAll()
f.close()

local schematic = json.decode(content)
if not schematic or not schematic.blocks then
  error("Invalid schematic format")
end

-- Step 3: Tally required blocks
local materialCounts = {}
for _, block in ipairs(schematic.blocks) do
  local name = block.name or "minecraft:air"
  if name ~= "minecraft:air" then
    materialCounts[name] = (materialCounts[name] or 0) + 1
  end
end

-- Step 4: Print required materials
print("Required Materials:")
for k, v in pairs(materialCounts) do
  print(k .. ": " .. v)
end

-- Step 5: Wait for confirmation to start
print("Press Enter to begin building...")
read()

-- Step 6: Begin building from turtle's position
-- You can define your own movement/build logic here
-- Example build loop stub:
for _, block in ipairs(schematic.blocks) do
  local x, y, z = block.x, block.y, block.z
  local name = block.name

  -- Movement and placement logic goes here...
  -- You would need a moveTo(x, y, z) and placeBlock(name)

  print("Placing " .. name .. " at (" .. x .. ", " .. y .. ", " .. z .. ")")
end

print("Build complete!")
