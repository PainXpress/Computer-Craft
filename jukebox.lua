-- Embedded DFPWM Decoder (sourced from gamax92/dfpwm.lua, MIT License, adapted for Lua 5.1 without bit API)
local function make_decoder()
    local previous_sample = 0
    local charge = 0
    local strength = 0
    local lastbit = false
    local filter_mult = 0.9

    local function reset()
        previous_sample = 0
        charge = 0
        strength = 0
        lastbit = false
    end

    local function decode_chunk(chunk)
        local samples = {}
        local byte = 0
        local bitpos = 0

        for i = 1, #chunk * 8 do
            if bitpos == 0 then
                byte = chunk:byte(math.floor((i - 1) / 8) + 1) or 0
                bitpos = 8
            end
            bitpos = bitpos - 1
            local mask = 2 ^ bitpos
            local bit = (math.floor(byte / mask) % 2) == 1

            local target = bit and 127 or -128
            local diff = target - charge
            local step = diff * strength

            charge = charge + step
            if charge > 127 then charge = 127 end
            if charge < -128 then charge = -128 end

            local sample = (charge + previous_sample) * filter_mult
            previous_sample = sample

            local adj = (bit ~= lastbit) and 0.015625 or -0.015625
            strength = strength + adj
            if strength < 0 then strength = 0 end
            if strength > 1 then strength = 1 end
            lastbit = bit

            samples[i] = math.floor(sample * 256)
        end

        return samples
    end

    return decode_chunk
end

-- Attempt to use built-in cc.audio.dfpwm module, fallback to embedded decoder
local dfpwm
if pcall(function() dfpwm = require("cc.audio.dfpwm") end) then
    -- Use built-in decoder
else
    dfpwm = { make_decoder = make_decoder }
end

-- Initialize peripherals
local speakers = {peripheral.find("minecraft:speaker")}
local monitors = {peripheral.find("monitor")}
local monitor = monitors[1]
if not monitor or #speakers == 0 then
    error("Monitor or speakers not found. Please connect them.")
end

-- Set up monitor
monitor.setTextScale(0.5)
monitor.clear()

-- State variables
local queue = {}
local current_song_url = nil
local current_response = nil
local playing = false
local paused = false
local speaker_ready = {}
local input_buffer = ""
local error_message = nil
local decoder = nil
for _, speaker in pairs(speakers) do
    speaker_ready[peripheral.getName(speaker)] = true
end

-- GUI functions
local function drawGUI()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    monitor.write("Jukebox - Play Any Song!")
    
    monitor.setCursorPos(1, 3)
    monitor.write("Now Playing: " .. (current_song_url and current_song_url:sub(1, 20) or "None"))
    
    monitor.setCursorPos(1, 5)
    monitor.write("Queue:")
    for i, url in ipairs(queue) do
        if i <= 5 then
            monitor.setCursorPos(1, 5 + i)
            monitor.write(i .. ". " .. url:sub(1, 20))
        end
    end
    
    monitor.setCursorPos(1, 12)
    monitor.write("Type 'add <url>' in terminal.")
    monitor.setCursorPos(1, 13)
    monitor.write("For YouTube: Convert to DFPWM at")
    monitor.setCursorPos(1, 14)
    monitor.write("music.madefor.cc, use that URL.")
    
    if error_message then
        monitor.setCursorPos(1, 16)
        monitor.write(error_message)
    end
    
    monitor.setCursorPos(1, 18)
    monitor.write("[" .. (paused and "Play" or "Pause") .. "]")
    monitor.setCursorPos(10, 18)
    monitor.write("[Skip]")
end

-- Playback functions
local function startSong(url)
    if current_response then
        current_response.close()
        for _, speaker in pairs(speakers) do
            speaker.stop()
        end
    end
    local response = http.get(url, nil, true)
    if not response then
        error_message = "Failed to stream: " .. url:sub(1, 20)
        drawGUI()
        return false
    end
    current_response = response
    current_song_url = url
    playing = true
    paused = false
    decoder = dfpwm.make_decoder()
    for _, speaker in pairs(speakers) do
        speaker_ready[peripheral.getName(speaker)] = true
    end
    error_message = nil
    drawGUI()
    return true
end

local function skipSong()
    if playing then
        playing = false
        if current_response then
            current_response.close()
            current_response = nil
        end
        for _, speaker in pairs(speakers) do
            speaker.stop()
            speaker_ready[peripheral.getName(speaker)] = true
        end
    end
    if #queue > 0 then
        local next_url = table.remove(queue, 1)
        startSong(next_url)
    else
        current_song_url = nil
        drawGUI()
    end
end

local function togglePause()
    if playing then
        paused = not paused
        if paused then
            for _, speaker in pairs(speakers) do
                speaker.stop()
            end
        end
        drawGUI()
    end
end

-- Queue management
local function addToQueue(url)
    -- Check if URL is a YouTube link
    if url:match("youtube%.com") or url:match("youtu%.be") then
        error_message = "Convert YouTube URL to DFPWM first."
        drawGUI()
        return
    end
    
    -- Check if URL ends with .dfpwm
    if not url:match("%.dfpwm$") then
        error_message = "URL must end with .dfpwm"
        drawGUI()
        return
    end
    
    table.insert(queue, url)
    if not playing then
        local next_url = table.remove(queue, 1)
        startSong(next_url)
    else
        drawGUI()
    end
end

-- Utility
local function allSpeakersReady()
    for _, ready in pairs(speaker_ready) do
        if not ready then return false end
    end
    return true
end

-- Main loop
drawGUI()
print("Type 'add <url>' to queue a song. Press Ctrl+T to exit.")
while true do
    if playing and not paused and allSpeakersReady() then
        local chunk = current_response.read(1024)
        if chunk then
            local pcm = decoder(chunk)
            for _, speaker in pairs(speakers) do
                speaker.playAudio(pcm)
                speaker_ready[peripheral.getName(speaker)] = false
            end
        else
            current_response.close()
            current_response = nil
            playing = false
            if #queue > 0 then
                local next_url = table.remove(queue, 1)
                startSong(next_url)
            else
                current_song_url = nil
                drawGUI()
            end
        end
    end
    local event, p1, p2, p3 = os.pullEvent()
    if event == "monitor_touch" then
        local x, y = p2, p3
        if y == 18 then
            if x >= 1 and x <= 6 then
                togglePause()
            elseif x >= 10 and x <= 15 then
                skipSong()
            end
        end
    elseif event == "speaker_audio_empty" then
        speaker_ready[p1] = true
    elseif event == "char" then
        input_buffer = input_buffer .. p1
        print("Typing: " .. input_buffer) -- Debug: Show input in terminal
    elseif event == "key" and p1 == keys.enter then
        if input_buffer:match("^add (.+)") then
            local url = input_buffer:match("^add (.+)")
            addToQueue(url)
        end
        input_buffer = ""
    end
end
