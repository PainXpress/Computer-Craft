-- Load JSON parser
local json = require("json")

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

-- Fetch required blocks from chest to turtle inventory
local function loadInventory(materials)
  local slot = 1
  for block, count in pairs(materials) do
    for i = 1, 16 do
      turtle.select(i)
      local item = turtle.getItemDetail()
      if item == nil then
        turtle.select(slot)
        -- Face the chest (assumes it's behind)
        turtle.turnLeft()
        turtle.turnLeft()
        print("Attempting to suck " .. count .. " of " .. block)
        local sucked = 0
        for attempt = 1, count do
          if turtle.suck(1) then
            local suckedItem = turtle.getItemDetail()
            if suckedItem and suckedItem.name == block then
              sucked = sucked + 1
            else
              break
            end
          end
        end
        turtle.turnRight()
        turtle.turnRight()
        if sucked > 0 then
          print("Loaded " .. sucked .. " of " .. block .. " into slot " .. slot)
          slot = slot + 1
        else
          print("WARNING: Could not pull " .. count .. " of " .. block)
        end
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

-- Main placement logic
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
    -- Move to next layer
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
      turtle.up()
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

print("Make sure the chest is directly behind the turtle.")
print("Loading materials...")
loadInventory(materials)

print("Building schematic...")
placeSchematic(schematic)

print("Finished!")
