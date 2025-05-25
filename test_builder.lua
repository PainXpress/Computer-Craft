-- Load JSON parser (rxi/json.lua)
local json = require("json")

-- Load schematic from local turtle storage
local schematicFile = "schematic.json"

if not fs.exists(schematicFile) then
  print("schematic.json not found!")
  return
end

local file = fs.open(schematicFile, "r")
local content = file.readAll()
file.close()

local success, schematic = pcall(json.decode, content)
if not success or not schematic then
  print("Failed to parse schematic.json")
  return
end

print("Schematic loaded successfully!")

-- Dummy test print to verify format
-- You can replace this with actual material counting / building
for y, layer in ipairs(schematic.layers or {}) do
  for z, row in ipairs(layer) do
    for x, block in ipairs(row) do
      print(string.format("Block at %d,%d,%d is %s", x, y, z, block.name or "air"))
    end
  end
end
