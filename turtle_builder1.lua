
-- Load JSON parser
local json = require("json")

-- Helper to find inventory (chest)
local function detectChest()
  local sides = { "front", "back", "left", "right", "top", "bottom" }
  for _, side in ipairs(sides) do
    if peripheral.isPresent(side) and peripheral.getType(side) == "inventory" then
      return peripheral.wrap(side)
    end
  end
  return nil
end

local chest = detectChest()
if not chest then
  error("No chest detected nearby!")
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
    error("Failed to parse schematic JSON.")
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
local function loadInventory(materials, chest)
  local slot = 1
  for block, count in pairs(materials) do
    for i = 1, chest.size() do
      local item = chest.getItemDetail(i)
      if item and item.name == block then
        turtle.select(slot)
        chest.pullItems(peripheral.getName(chest), i, count)
        slot = slot + 1
        break
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
            turtle.placeDown()
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
      turtle.up()
      if (#schematic[y] % 2 == 1) then
        turtle.turnRight()
        for i = 1, #schematic[y][1] - 1 do turtle.back() end
        turtle.turnRight()
      else
        turtle.turnLeft()
        for i = 1, #schematic[y][1] - 1 do turtle.back() end
        turtle.turnLeft()
      end
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
local chest = findInventory()
if not chest then
  print("No chest found.")
  return
end

print("Loading materials...")
loadInventory(materials, chest)

print("Building schematic...")
placeSchematic(schematic)

print("Finished!")
