-- custom_sign.lua
local monitor = peripheral.find("monitor") or error("No monitor attached.")
monitor.setTextScale(5) -- for BIG text
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()

-- Load config
local function loadConfig()
    local config = {
        text = "Welcome!",
        textColor = "white",
        backgroundColor = "black",
        blink = false,
        blinkInterval = 1,
    }

    if fs.exists("config.txt") then
        for line in io.lines("config.txt") do
            local key, value = line:match("^(%w+)%s*=%s*(.+)$")
            if key and value then
                if value == "true" then value = true
                elseif value == "false" then value = false
                elseif tonumber(value) then value = tonumber(value)
                end
                config[key] = value
            end
        end
    end

    return config
end

local function toColor(name)
    local map = {
        white=colors.white, orange=colors.orange, magenta=colors.magenta,
        lightBlue=colors.lightBlue, yellow=colors.yellow, lime=colors.lime,
        pink=colors.pink, gray=colors.gray, lightGray=colors.lightGray,
        cyan=colors.cyan, purple=colors.purple, blue=colors.blue,
        brown=colors.brown, green=colors.green, red=colors.red, black=colors.black
    }
    return map[name] or colors.white
end

-- Draw centered text
local function drawText(text, textColor, backgroundColor)
    monitor.setBackgroundColor(backgroundColor)
    monitor.clear()
    monitor.setTextColor(textColor)

    local w, h = monitor.getSize()
    local x = math.floor((w - #text) / 2) + 1
    local y = math.floor(h / 2)

    monitor.setCursorPos(x, y)
    monitor.write(text)
end

-- Main loop
local function runSign()
    local config = loadConfig()

    local show = true
    while true do
        if config.blink then
            if show then
                drawText(config.text, toColor(config.textColor), toColor(config.backgroundColor))
            else
                monitor.clear()
            end
            show = not show
            sleep(config.blinkInterval or 1)
        else
            drawText(config.text, toColor(config.textColor), toColor(config.backgroundColor))
            sleep(1)
        end
    end
end

runSign()
