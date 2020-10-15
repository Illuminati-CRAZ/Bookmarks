BOOKMARK_COLOR = 1459515016
MENU_BAR_HEIGHT = 35
BOTTOM_MENU_HEIGHT = 52
LINE_LENGTH = 0.05
LINE_THICKNESS = 2

LAST_BOOKMARK_OFFSET = 999999
MEMORY_OFFSET = 1000000

function draw()
    if not memory.read(LAST_BOOKMARK_OFFSET) then
        imgui.Begin("Bookmarks")
        if imgui.Button("Initialize") then
            initialize()
        end
        imgui.End()
        return
    end

    bookmarks = memory.read(MEMORY_OFFSET, memory.read(LAST_BOOKMARK_OFFSET))
    if type(bookmarks) == "number" then
        bookmarks = {bookmarks}
    elseif type(bookmarks) == "nil" then
        bookmarks = {}
    end

    if utils.IsKeyPressed(keys.OemComma) then
        actions.GoToObjects(findNearestBookmark(state.SongTime, false))
    end

    if utils.IsKeyPressed(keys.OemPeriod) then
        actions.GoToObjects(findNearestBookmark(state.SongTime, true))
    end

    window()

    for _, time in pairs(bookmarks) do
        drawLine(time, BOOKMARK_COLOR, 1)
    end
end

function window()
    imgui.Begin("Bookmarks")

    state.IsWindowHovered = imgui.IsWindowHovered()

    if imgui.Button("Add Bookmark At Current Time") then
        local time = math.floor(state.SongTime)
        table.insert(bookmarks, time)
        table.sort(bookmarks)
        memory.delete(MEMORY_OFFSET, memory.read(LAST_BOOKMARK_OFFSET))
        memory.write(MEMORY_OFFSET, bookmarks)
        memory.write(LAST_BOOKMARK_OFFSET, memory.delete(LAST_BOOKMARK_OFFSET) + 1)
    end

    if imgui.Button("Remove Bookmark At Current Time") then
        local songtime = math.floor(state.SongTime)
        for i, time in pairs(bookmarks) do
            if time == songtime then
                table.remove(bookmarks, i)
            end
        end
        memory.delete(MEMORY_OFFSET, memory.read(LAST_BOOKMARK_OFFSET))
        memory.write(MEMORY_OFFSET, bookmarks)
        memory.delete(LAST_BOOKMARK_OFFSET)
        memory.write(LAST_BOOKMARK_OFFSET, 1000000 + #bookmarks - 1)
    end

    if imgui.Button("Go to Previous Bookmark") then
        actions.GoToObjects(findNearestBookmark(state.SongTime, false))
    end

    if imgui.Button("Go to Next Bookmark") then
        actions.GoToObjects(findNearestBookmark(state.SongTime, true))
    end

    if imgui.Button("Deinitialize") then
        deinitialize()
    end

    imgui.TextWrapped(tableToString(bookmarks))
    --imgui.TextWrapped("SongTime: " .. state.SongTime)

    imgui.End()
end

function initialize()
    memory.write(LAST_BOOKMARK_OFFSET, MEMORY_OFFSET - 1)
end

function deinitialize()
    memory.delete(LAST_BOOKMARK_OFFSET, memory.read(LAST_BOOKMARK_OFFSET))
end

function findNearestBookmark(time, forwards)
    if #bookmarks == 1 then
        return (bookmarks[1])
    end
    if #bookmarks == 0 then
        return
    end

    local i = 1
    local songtime = state.SongTime
    local lenience = forwards and 1 or -1 --state.SongTime is dumb
    while bookmarks[i] < state.SongTime + lenience do
        if i < #bookmarks then
            i = i + 1
        else
            break
        end
    end
    return forwards and bookmarks[i] or bookmarks[i - 1]
end

function drawLine(time, color, lineScale)
    local progress = time / map.TrackLength

    local startPoint = relToAbsCoord(progress, 1 - LINE_LENGTH * lineScale)
    local endPoint = relToAbsCoord(progress, 1)
    imgui.GetOverlayDrawList().AddLine(startPoint, endPoint, color,
                                       LINE_THICKNESS)
end

function relToAbsCoord(x, y)
    return {
        x * state.WindowSize[1],
        y * (state.WindowSize[2] - MENU_BAR_HEIGHT - BOTTOM_MENU_HEIGHT) +
            MENU_BAR_HEIGHT
    }
end

function tableToString(thing)
    local results = {}
    for i,value in pairs(thing) do
        table.insert(results, value)
    end

    return (table.concat(results, ", "))
end

---------------------------------------------------------------------------------------------------------------------------

--this is probably all jank idk
memory = {}

MEMORY_INCREMENT = .25

--maybe i should change "offset" to "index"
function memory.write(offset, data, step, mirror)
    if type(data) != "number" and type(data) != "table" then
        return(offset) --return same offset to use since nothing is written
    end

    step = step or 1
    mirror = mirror or false --setting mirror to true causes effect of sv to be (mostly) negated by an equal and opposite sv and then a 1x sv is placed

    if type(data) == "number" then
        if mirror then
            local svs = {}
            table.insert(svs, utils.CreateScrollVelocity(offset, data))
            table.insert(svs, utils.CreateScrollVelocity(offset + MEMORY_INCREMENT, -data))
            table.insert(svs, utils.CreateScrollVelocity(offset + 2 * MEMORY_INCREMENT, 1))
            actions.PlaceScrollVelocityBatch(svs)
        else
            actions.PlaceScrollVelocity(utils.CreateScrollVelocity(offset, data))
        end
        return(offset + step) --one sv placed, so increment offset by 1 step
    else --data is a table
        local svs = {}
        for i, value in pairs(data) do
            table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1), value))
            if mirror then
                table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1) + MEMORY_INCREMENT, -value))
                table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1) + 2 * MEMORY_INCREMENT, 1))
            end
        end
        actions.PlaceScrollVelocityBatch(svs)
        return(offset + #data * step) --increment offset by number of elements in data times step
    end
end

function memory.search(start, stop)
    local svs = map.ScrollVelocities --I'm assuming this returns the svs in order so I'm not sorting them
    local selection = {}
    for _, sv in pairs(svs) do
        if (start <= sv.StartTime) and (sv.StartTime <= stop) then
            table.insert(selection, sv)
        elseif sv.StartTime > stop then --since they're in order, I should be able to return once StartTime exceeds stop
            break
        end
    end
    return(selection) --returns table of svs
end

function memory.read(start, stop, step)
    if not start then
        return(false)
    end

    step = step or 1 --step indicated which svs are for data and which are for mirroring
    stop = stop or start --stop defaults to start, so without a stop provided, function returns one item

    local selection = {}
    for _, sv in pairs(memory.search(start, stop)) do
        if sv.StartTime % step == 0 then --by default, anything without integer starttime is not included
            table.insert(selection, sv.Multiplier)
        end
    end
    if #selection == 1 then --if table of only one element
        return(selection[1]) --return element
    elseif #selection == 0 then
        return(nil)
    else --otherwise
        return(selection) --return table of elements
    end
end

function memory.delete(start, stop, step)
    if not start then
        return(false)
    end

    step = step or 1
    stop = stop or start

    local svs = memory.search(start, stop)
    local selection = {}

    for _, sv in pairs(svs) do
        if sv.StartTime % step == 0 then
            table.insert(selection, sv.Multiplier)
        end
    end

    actions.RemoveScrollVelocityBatch(svs)
    if #selection == 1 then --if table of only one element
        return(selection[1]) --return element
    elseif #selection == 0 then
        return(nil)
    else --otherwise
        return(selection) --return table of elements
    end
end

function memory.generateCorrectionSVs(limit, offset) --because there's going to be a 1293252348328x SV that fucks the game up
    local svs = map.ScrollVelocities --if these don't come in order i'm going to hurt someone

    local totaldisplacement = 0

    for i, sv in pairs(svs) do
        if (sv.StartTime < limit) and not (sv.StartTime == offset or sv.StartTime == offset + 1) then
            length = svs[i+1].StartTime - sv.StartTime
            displacement = length * (sv.Multiplier - 1) --displacement in ms as a distance
            totaldisplacement = totaldisplacement + displacement --total displacement in ms as a distance
        else
            break
        end
    end

    corrections = {}
    table.insert(corrections, utils.CreateScrollVelocity(offset, -totaldisplacement + 1)) --i think this is correct?
    table.insert(corrections, utils.CreateScrollVelocity(offset + 1, 1))

    return(corrections)
end

function memory.correctDisplacement(limit, offset) --will not work if there's an ultra large number at the end
    local limit = limit or 0 --where the memory ends
    local offset = offset or -10000002 --SVs will return with StartTime = offset and offset + 1

    local currentsvs = {}
    table.insert(currentsvs, getScrollVelocityAtExactly(offset))
    table.insert(currentsvs, getScrollVelocityAtExactly(offset + 1))
    actions.RemoveScrollVelocityBatch(currentsvs)

    actions.PlaceScrollVelocityBatch(memory.generateCorrectionSVs(limit, offset))
end

function getScrollVelocityAtExactly(time)
    local currentsv = map.GetScrollVelocityAt(time)
    if currentsv.StartTime == time then
        return(currentsv)
    end
end
