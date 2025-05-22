-- chunk_builder.lua
-- ComputerCraft Schematic Builder (Chunk-Based)
-- By Gemini (Google AI)
-- Rewritten runBuilder section on 2025-05-22

-- --- Configuration ---
local MANIFEST_FILE = "manifest.lua" -- Name of the manifest file on your turtle
local FUEL_THRESHOLD = 50           -- Refuel if fuel level drops below this
local SLOW_MODE = true              -- Set to true to slow down turtle actions for debugging
local LOG_FILE = "build_log.txt"    -- File to log building progress and errors

-- --- Global State Variables ---
local manifest = {}                 -- Will hold the loaded chunk manifest
local currentX, currentY, currentZ = 0, 0, 0 -- Turtle's current absolute position in world coords (relative to schematic origin)
local currentDir = "north"          -- Turtle's current facing direction ("north", "east", "south", "west")
local blockInventoryMap = {}        -- Maps block_id (e.g., "minecraft:stone") to inventory slot number

-- --- Helper Functions ---

-- Logs messages to both console and a log file
local function log(message)
    print(message)
    local file = fs.open(LOG_FILE, "a")
    if file then
        file.writeLine(os.date("[%Y-%m-%d %H:%M:%S] ") .. message)
        file.close()
    end
end

-- Pauses execution for debugging or user interaction
local function pause(reason)
    log("PAUSED: " .. reason .. ". Press any key to continue...")
    os.pullEvent("key")
    log("Resuming...")
end

-- Updates internal position based on turtle movement
local function updatePosition(action)
    if action == "forward" then
        if currentDir == "north" then currentZ = currentZ - 1
        elseif currentDir == "east" then currentX = currentX + 1
        elseif currentDir == "south" then currentZ = currentZ + 1
        elseif currentDir == "west" then currentX = currentX - 1 end
    elseif action == "back" then
        if currentDir == "north" then currentZ = currentZ + 1
        elseif currentDir == "east" then currentX = currentX - 1
        elseif currentDir == "south" then currentZ = currentZ - 1
        elseif currentDir == "west" then currentX = currentX + 1 end
    elseif action == "up" then currentY = currentY + 1
    elseif action == "down" then currentY = currentY - 1
    end
    if SLOW_MODE then sleep(0.1) end
end

-- Wrapper for turtle.forward()
local function goForward()
    checkFuel()
    if not turtle.forward() then
        log(string.format("ERROR: Turtle stuck going forward at (%d,%d,%d)! Current Dir: %s", currentX, currentY, currentZ, currentDir))
        pause("Stuck forward")
        return false
    end
    updatePosition("forward")
    return true
end

-- Wrapper for turtle.back()
local function goBack()
    checkFuel()
    if not turtle.back() then
        log(string.format("ERROR: Turtle stuck going back at (%d,%d,%d)! Current Dir: %s", currentX, currentY, currentZ, currentDir))
        pause("Stuck back")
        return false
    end
    updatePosition("back")
    return true
end

-- Wrapper for turtle.up()
local function goUp()
    checkFuel()
    if not turtle.up() then
        log(string.format("ERROR: Turtle stuck going up at (%d,%d,%d)! Current Dir: %s", currentX, currentY, currentZ, currentDir))
        pause("Stuck up")
        return false
    end
    updatePosition("up")
    return true
end

-- Wrapper for turtle.down()
local function goDown()
    checkFuel()
    if not turtle.down() then
        log(string.format("ERROR: Turtle stuck going down at (%d,%d,%d)! Current Dir: %s", currentX, currentY, currentZ, currentDir))
        pause("Stuck down")
        return false
    end
    updatePosition("down")
    return true
end

-- Wrapper for turtle.turnLeft()
local function turnLeft()
    checkFuel()
    turtle.turnLeft()
    if currentDir == "north" then currentDir = "west"
    elseif currentDir == "east" then currentDir = "north"
    elseif currentDir == "south" then currentDir = "east"
    elseif currentDir == "west" then currentDir = "south" end
    if SLOW_MODE then sleep(0.1) end
end

-- Wrapper for turtle.turnRight()
local function turnRight()
    checkFuel()
    turtle.turnRight()
    if currentDir == "north" then currentDir = "east"
    elseif currentDir == "east" then currentDir = "south"
    elseif currentDir == "south" then currentDir = "west"
    elseif currentDir == "west" then currentDir = "north" end
    if SLOW_MODE then sleep(0.1) end
end

-- Orients the turtle to face a specific direction
local function faceDirection(target_dir)
    if currentDir == target_dir then return end -- Already facing target

    local turns = 0
    while currentDir ~= target_dir and turns < 4 do
        turnRight()
        turns = turns + 1
    end
    if turns >= 4 then
        log("ERROR: Failed to face " .. target_dir ..". Stuck?")
        pause("Failed to orient")
        return false
    end
    return true
end

-- Ensures turtle has enough fuel, attempts to refuel if low
local function checkFuel()
    if turtle.getFuelLevel() < FUEL_THRESHOLD then
        log(string.format("Fuel low (%d), attempting to refuel...", turtle.getFuelLevel()))
        turtle.refuel() -- Assumes fuel is in turtle's inventory
        if turtle.getFuelLevel() == 0 then
            log("CRITICAL ERROR: Ran out of fuel and couldn't refuel! Stopping.")
            error("No fuel!")
        else
            log("Refueled to " .. turtle.getFuelLevel())
        end
    end
end

-- Populates blockInventoryMap by scanning turtle's inventory
local function scanInventory()
    blockInventoryMap = {} -- Clear previous map
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and item.name then
            -- Store block name -> slot mapping
            blockInventoryMap[item.name] = slot
            -- If you need to handle block states/metadata for different variants of the same block,
            -- you'd add a more complex key here, e.g., blockInventoryMap[item.name .. ":" .. item.metadata] = slot
            -- Or, if the schematic includes 'state_str', you might map that.
        end
    end
    log("Inventory scanned. Mapped blocks: " .. textutils.serialize(blockInventoryMap))
end

-- Attempts to select a block and place it
local function selectAndPlace(blockName)
    local slot = blockInventoryMap[blockName]
    if not slot then
        log("ERROR: Block '" .. blockName .. "' not found in inventory. Attempting re-scan.")
        scanInventory() -- Try scanning again
        slot = blockInventoryMap[blockName]
        if not slot then
            log("CRITICAL ERROR: Still no '" .. blockName .. "' in inventory. Cannot place.")
            -- TODO: Implement 'go to supply chest' logic here for real builds
            -- For now, this will pause and require manual intervention or abort.
            pause("Missing block: " .. blockName .. " (Check inventory or supply chest logic)")
            return false
        end
    end

    turtle.select(slot)
    if turtle.getItemCount(slot) == 0 then
        log("WARNING: Selected slot " .. slot .. " for " .. blockName .. " is empty! Attempting to get more.")
        -- TODO: Implement sophisticated 'go to supply chest' logic here
        -- For now, this simply fails to place.
        pause("Slot empty for: " .. blockName .. " (Need to fetch more)")
        return false
    end

    if not turtle.place() then
        log("WARNING: Failed to place " .. blockName .. " at (" .. currentX .. "," .. currentY .. "," .. currentZ .. "). Is space occupied?")
        -- Consider digging (turtle.dig()) if it's an unwanted block, or trying again.
        return false
    end
    return true
end

-- --- Absolute Movement Logic ---
local function goToAbsoluteCoords(targetX, targetY, targetZ)
    log(string.format("Moving to absolute coords: (%d,%d,%d)", targetX, targetY, targetZ))

    -- 1. Adjust Y level first
    while currentY < targetY do if not goUp() then return false end end
    while currentY > targetY do if not goDown() then return false end end

    -- 2. Adjust X then Z (or vice versa, but this is a common strategy)
    -- Move X
    if currentX < targetX then
        if not faceDirection("east") then return false end
        while currentX < targetX do if not goForward() then return false end end
    elseif currentX > targetX then
        if not faceDirection("west") then return false end
        while currentX > targetX do if not goForward() then return false end end
    end

    -- Move Z
    if currentZ < targetZ then
        if not faceDirection("north") then return false end
        while currentZ < targetZ do if not goForward() then return false end end
    elseif currentZ > targetZ then
        if not faceDirection("south") then return false end
        while currentZ > targetZ do if not goForward() then return false end end
    end

    log(string.format("Arrived at (%d,%d,%d)", currentX, currentY, currentZ))
    return true
end

-- --- Core Building Logic for a Single Chunk ---
local function buildSingleChunk(chunk_data, chunk_abs_startX, chunk_abs_startY, chunk_abs_startZ)
    log(string.format("Building chunk starting at absolute (%d,%d,%d)", chunk_abs_startX, chunk_abs_startY, chunk_abs_startZ))
    log(string.format("  Chunk dimensions: W=%d, H=%d, L=%d", chunk_data.width, chunk_data.height, chunk_data.length))

    -- Iterate through layers (Y) within the chunk from bottom to top (0-indexed for schematic data)
    for y_rel = 0, chunk_data.height - 1 do
        local abs_y_level = chunk_abs_startY + y_rel
        log(string.format("  Building Layer Y = %d (absolute Y = %d)", y_rel, abs_y_level))

        -- Move turtle to the correct Y level
        if currentY < abs_y_level then
            while currentY < abs_y_level do if not goUp() then return false end end
        elseif currentY > abs_y_level then
            while currentY > abs_y_level do if not goDown() then return false end end
        end
        
        -- Simple zig-zag pattern for X and Z within the chunk
        local z_direction = 1 -- 1 for forward (Z-), -1 for backward (Z+)
        for x_rel = 0, chunk_data.width - 1 do
            local abs_x_current_col = chunk_abs_startX + x_rel

            -- Adjust X position for the current column
            if currentX < abs_x_current_col then
                if not faceDirection("east") then return false end
                while currentX < abs_x_current_col do if not goForward() then return false end end
            elseif currentX > abs_x_current_col then
                if not faceDirection("west") then return false end
                while currentX > abs_x_current_col do if not goForward() then return false end end
            end

            -- Determine Z iteration direction (zig-zag for efficiency)
            if x_rel % 2 == 0 then
                z_direction = 1 -- Move from Z=0 to Z=length-1 (North)
            else
                z_direction = -1 -- Move from Z=length-1 to Z=0 (South)
            end
            
            -- Ensure turtle is at the start of the Z line for this zig-zag pass
            local target_z_start = (z_direction == 1) and (chunk_abs_startZ + 0) or (chunk_abs_startZ + chunk_data.length - 1)
            if currentZ < target_z_start then
                if not faceDirection("north") then return false end
                while currentZ < target_z_start do if not goForward() then return false end end
            elseif currentZ > target_z_start then
                if not faceDirection("south") then return false end
                while currentZ > target_z_start do if not goForward() then return false end end
            end
            
            -- Build the Z row
            if z_direction == 1 then
                if not faceDirection("north") then return false end
                for z_rel = 0, chunk_data.length - 1 do
                    local blockData = chunk_data.blocks[y_rel] and chunk_data.blocks[y_rel][x_rel] and chunk_data.blocks[y_rel][x_rel][z_rel]
                    if blockData and blockData.name ~= "minecraft:air" then
                        log(string.format("    Placing %s at relative (%d,%d,%d) / absolute (%d,%d,%d)",
                                          blockData.name, x_rel, y_rel, z_rel, currentX, currentY, currentZ))
                        if not selectAndPlace(blockData.name) then
                            log("Failed to place block in chunk. Aborting chunk build.")
                            return false
                        end
                    end
                    if z_rel < chunk_data.length - 1 then
                        if not goForward() then return false end
                    end
                end
            else -- z_direction == -1 (move backwards along Z)
                if not faceDirection("south") then return false end
                for z_rel = chunk_data.length - 1, 0, -1 do
                    local blockData = chunk_data.blocks[y_rel] and chunk_data.blocks[y_rel][x_rel] and chunk_data.blocks[y_rel][x_rel][z_rel]
                    if blockData and blockData.name ~= "minecraft:air" then
                        log(string.format("    Placing %s at relative (%d,%d,%d) / absolute (%d,%d,%d)",
                                          blockData.name, x_rel, y_rel, z_rel, currentX, currentY, currentZ))
                        if not selectAndPlace(blockData.name) then
                            log("Failed to place block in chunk. Aborting chunk build.")
                            return false
                        end
                    end
                    if z_rel > 0 then
                        if not goForward() then return false end
                    end
                end
            end
        end
    end
    log(string.format("Finished building chunk starting at absolute (%d,%d,%d)", chunk_abs_startX, chunk_abs_startY, chunk_abs_startZ))
    return true
end


-- --- Main Program Flow ---
local function init()
    -- Clear log file on start
    local file = fs.open(LOG_FILE, "w")
    if file then file.close() end

    log("Initializing ComputerCraft Chunk Builder...")

    -- Load the manifest file
    log("Attempting to load manifest from: " .. MANIFEST_FILE)
    manifest = dofile(MANIFEST_FILE)
    if not manifest or type(manifest) ~= "table" or #manifest == 0 then
        error("Failed to load manifest data or manifest format is incorrect from " .. MANIFEST_FILE)
    end
    log(string.format("Manifest '%s' loaded successfully with %d chunks.", MANIFEST_FILE, #manifest))

    -- Initial inventory scan
    scanInventory()
    checkFuel()

    log("Setup complete. Starting build in 5 seconds...")
    sleep(5)
end

local function runBuilder()
    init()

    local success_overall = true
    for i, chunk_info in ipairs(manifest) do
        log(string.format("\n--- Building Chunk %d/%d: %s ---", i, #manifest, chunk_info.file))

        -- Attempt to load chunk data
        local chunk_data_loaded_result, chunk_data_loaded_err = pcall(dofile, chunk_info.file)
        local chunk_data_loaded = nil

        if not chunk_data_loaded_result then
            log("CRITICAL ERROR: Failed to load chunk file: " .. chunk_info.file .. " Error: " .. tostring(chunk_data_loaded_err) .. ". Skipping this chunk.")
            success_overall = false
            -- No 'continue' here, as the loop structure will handle going to the next chunk.
            -- This also avoids potential misinterpretation if 'continue' was problematic.
        else
            chunk_data_loaded = chunk_data_loaded_err -- pcall returns the result as the second value on success
            if not chunk_data_loaded or type(chunk_data_loaded) ~= "table" then
                 log("CRITICAL ERROR: Chunk data from " .. chunk_info.file .. " is not a valid table. Skipping this chunk.")
                 success_overall = false
            else
                -- Go to the absolute start coordinates of this chunk
                if not goToAbsoluteCoords(chunk_info.startX, chunk_info.startY, chunk_info.startZ) then
                    log("CRITICAL ERROR: Failed to move to start of chunk " .. chunk_info.file .. ". Aborting build.")
                    success_overall = false
                    break
                end

                -- Build the current chunk
                if not buildSingleChunk(chunk_data_loaded, chunk_info.startX, chunk_info.startY, chunk_info.startZ) then
                    log("Chunk build failed for " .. chunk_info.file .. ". Aborting remaining build process.")
                    success_overall = false
                    break
                end
                -- Optional: Clear chunk_data_loaded from memory to free up resources if chunks are very large
                chunk_data_loaded = nil
                collectgarbage("collect") -- Force garbage collection
            end
        end
    end

    if success_overall then
        log("\n================================")
        log("BUILDING COMPLETED SUCCESSFULLY!")
        log("================================")
    else
        log("\n================================")
        log("BUILDING ABORTED OR FAILED!")
        log("Check build_log.txt for details.")
        log("================================")
    end
end

-- Execute the main builder function
runBuilder()
