-- Load JSON parser
local json = require("json")

-- Helper to find inventory (chest)
-- CHANGED: Renamed function to detectChestAndSide and modified peripheral type check
local function detectChestAndSide()
  local sides = { "front", "back", "left", "right", "top", "bottom" }
  for _, side in ipairs(sides) do
    if peripheral.isPresent(side) then
      local pType = peripheral.getType(side)
      -- CHANGED: Now specifically checks for "projecte:alchemical_chest" OR "inventory"
      if pType == "projecte:alchemical_chest" or pType == "inventory" then
        print("Detected " .. pType .. " on side: " .. side)
        return peripheral.wrap(side), side -- Return both the wrapped peripheral and the side
      end
    end
  end
  return nil, nil -- Return nil for both if not found
end

-- Load schematic
local function loadSchematic(path)
  if not fs.exists(path) then
    error("Schematic file not found.")
  end
  local file = fs.open(path, "r")
  local data = file.readAll()
  file.close()
  local success, decoded = pcall(json.decode, data)
  if not success then
    error("Failed to parse schematic JSON. Error: " .. decoded)
  end
  return decoded
end

-- Count materials in schematic
local function countMaterials(schematic)
  local materialCounts = {}
  for y = 1, #schematic do
    for z = 1, #schematic[y] do
      for x = 1, #schematic[y][z] do
        local block = schematic[y][z][x]
        if block ~= "minecraft:air" and block ~= nil then
          materialCounts[block] = (materialCounts[block] or 0) + 1
        end
      end
    end
  end
  return materialCounts
end

-- Fetch required blocks from chest to inventory
-- CHANGED: Added chestSide parameter and used it in pullItems
local function loadInventory(materials, chest, chestSide)
  local slot = 1
  for block, count in pairs(materials) do
    for i = 1, chest.size() do
      local item = chest.getItemDetail(i)
      if item and item.name == block then
        turtle.select(slot)
        -- CHANGED: Used chestSide here for pullItems and added destination slot
        local actualPulled = chest.pullItems(chestSide, i, count, slot)
        if actualPulled > 0 then
            print("Loaded " .. actualPulled .. " of " .. block .. " into slot " .. slot)
            slot = slot + 1
        else
            print("WARNING: Could not pull " .. count .. " of " .. block .. " from chest.")
        end
        break -- Exit inner loop once item is found and pulled
      end
    end
  end
end

-- Find a block in turtle inventory
local function selectBlock(name)
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and item.name == name then
      turtle.select(i)
      return true
    end
  end
  return false
end

-- Main placement logic (starts at bottom layer, southeast corner)
local function placeSchematic(schematic)
  for y = 1, #schematic do
    for z = 1, #schematic[y] do
      for x = 1, #schematic[y][z] do
        local block = schematic[y][z][x]
        if block and block ~= "minecraft:air" then
          if selectBlock(block) then
            if not turtle.placeDown() then
                print("WARNING: Failed to place " .. block .. " at Y:" .. y .. " Z:" .. z .. " X:" .. x)
            end
          else
            print("ERROR: Missing block " .. block .. " in inventory at Y:" .. y .. " Z:" .. z .. " X:" .. x)
            error("Missing required block! Halting build.")
          end
        end
        if x < #schematic[y][z] then
          turtle.forward()
        end
      end
      if z < #schematic[y] then
        if z % 2 == 1 then
          turtle.turnRight()
          turtle.forward()
          turtle.turnRight()
        else
          turtle.turnLeft()
          turtle.forward()
          turtle.turnLeft()
        end
      end
    end
    -- move up to next layer
    if y < #schematic then
      if (#schematic[y] % 2 == 1) then
        turtle.turnRight()
        for i = 1, #schematic[y][1] - 1 do turtle.back() end
        turtle.turnRight()
      else
        turtle.turnLeft()
        for i = 1, #schematic[y][1] - 1 do turtle.back() end
        turtle.turnLeft()
      end
      turtle.up() -- Move up to the next layer
    end
  end
end

-- Program start
local schematic = loadSchematic("schematic.json")
local materials = countMaterials(schematic)

print("Required materials:")
for k, v in pairs(materials) do
  print(k .. ": " .. v)
end

print("Detecting chest...")
-- CHANGED: Call the new detectChestAndSide function and capture both values
local chest, chestSide = detectChestAndSide()
if not chest then
  print("No compatible inventory/chest found.")
  return
end
print("Chest found on side: " .. chestSide) -- Confirm detection

print("Loading materials...")
-- CHANGED: Pass chestSide to loadInventory
loadInventory(materials, chest, chestSide)

print("Building schematic...")
placeSchematic(schematic)

print("Finished!")
