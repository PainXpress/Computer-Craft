-- Attempt to load JSON parser
local json = require("json")

-- Auto-detect disk drive and read JSON
local function findPeripheralByType(ptype)
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == ptype then
      return side
    end
  end
  return nil
end

local diskSide = findPeripheralByType("drive")
if not diskSide then
  print("No disk drive found!")
  return
end

local mountPath = disk.getMountPath(diskSide)
local filePath = mountPath .. "/schematic.json"

-- Read and decode JSON
local file = fs.open(filePath, "r")
if not file then
  print("Could not open schematic.json on disk.")
  return
end

local jsonText = file.readAll()
file.close()

local schematic = json.decode(jsonText)
if not schematic then
  print("Failed to parse schematic JSON.")
  return
end

print("Schematic loaded successfully!")
-- You can now start parsing and counting blocks.
