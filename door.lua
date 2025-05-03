os.pullEvent = os.pullEventRaw -- Prevents Ctrl+T termination
local side = "right" -- Door is on the right side
local password = "waila" -- Password set to "waila"
local opentime = 5 -- Door stays open for 5 seconds

while true do
    term.clear() -- Clears the screen
    term.setCursorPos(1, 1) -- Sets cursor to top-left
    write("Password: ") -- Prompts for password
    local input = read("*") -- Reads input, displays asterisks for security
    if input == password then
        term.clear()
        term.setCursorPos(1, 1)
        print("Password correct!")
        rs.setOutput(side, true) -- Opens the door
        sleep(opentime) -- Waits 5 seconds
        rs.setOutput(side, false) -- Closes the door
    else
        term.clear()
        term.setCursorPos(1, 1)
        print("Password incorrect!")
        sleep(2) -- Waits 2 seconds before retry
    end
end
