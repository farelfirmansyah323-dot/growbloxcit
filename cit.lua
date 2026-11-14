local G = _G
if type(getgenv) == "function" then
    local ok, globals = pcall(getgenv)
    if ok and type(globals) == "table" then G = globals end
end
for _, key in ipairs({ "__n4thOpus", "__GTFarm" }) do -- __GTFarm = legacy version name
    if G[key] and G[key].Cleanup then pcall(G[key].Cleanup) end
    G[key] = nil
end
local Session = {}
Session.Build = "2026-11-14-native-menu-1"
G.__n4thOpus = Session
local function alive()
    return G.__n4thOpus == Session
end
-- Keep executor aliases local so the game environment is not modified.
local getgc = getgc or get_gc_objects
local getmodules = getmodules or get_modules
local gethui = gethui or get_hidden_gui
local getconnections = getconnections or get_connections
local getloadedmodules = getloadedmodules or get_loaded_modules
function Session.runtimeObjects()
    if type(getgc) ~= "function" then return nil, "Executor does not have getgc()" end
    local function read(includeTables)
        local ok, objects
        if includeTables then ok, objects = pcall(getgc, true) else ok, objects = pcall(getgc) end
        if not ok then return nil, tostring(objects) end
        if type(objects) ~= "table" then return nil, "result is not a table" end
        for _, value in pairs(objects) do
            if type(value) == "table" or type(value) == "function" then return objects, nil, true end
        end
        return objects
    end
    local objects, reason, readable = read(true)
    if readable then return objects, nil, true end
    local fallback, fallbackReason, fallbackReadable = read(false)
    return fallbackReadable and fallback or objects or fallback, fallbackReason or reason, fallbackReadable == true
end
function Session.connectionFunction(connection)
    if type(connection) == "function" then return connection end
    local ok, fn = pcall(function() return connection.Function end)
    if ok and type(fn) == "function" then return fn end
    ok, fn = pcall(function() return connection.Callback end)
    if ok and type(fn) == "function" then return fn end
    if type(getconnectionfunction) == "function" then
        ok, fn = pcall(getconnectionfunction, connection)
        if ok and type(fn) == "function" then return fn end
    end
end
function Session.scanStep(budget, visited)
    if visited % 64 ~= 0 or os.clock() < budget.next then return end
    task.wait()
    budget.next = os.clock() + 0.0015
end
Session.InitStep = "game services"
function Session.download(url)
    local lastError = "empty response"
    local function checked(source)
        if type(source) ~= "string" or source:match("^%s*$") then return nil, "empty response" end
        if source:match("^%s*<") then return nil, "server sent HTML instead of script/metadata" end
        if source:match("^%s*[45]%d%d[:%s]") then return nil, source:sub(1, 120) end
        return source
    end
    local ok, source = pcall(function() return game:HttpGet(url) end)
    if ok then
        local valid, reason = checked(source)
        if valid then return valid end
        lastError = reason
    else lastError = tostring(source) end
    local seen = {}
    for _, api in ipairs({ request or false, http_request or false, syn_request or false,
        (syn and syn.request) or false, (http and http.request) or false, (fluxus and fluxus.request) or false }) do
        if type(api) == "function" and not seen[api] then
            seen[api] = true
            local sent, response = pcall(api, { Url = url, Method = "GET" })
            if sent and type(response) == "table" then
                local status = tonumber(response.StatusCode or response.Status)
                if status and (status < 200 or status >= 300) then
                    lastError = "HTTP " .. tostring(status)
                else
                    local valid, reason = checked(response.Body or response.body)
                    if valid then return valid end
                    lastError = reason
                end
            elseif sent and type(response) == "string" then
                local valid, reason = checked(response)
                if valid then return valid end
                lastError = reason
            else lastError = tostring(response) end
        end
    end
    local fetched, fallback = pcall(function() return game:GetService("HttpService"):GetAsync(url) end)
    if fetched then
        local valid, reason = checked(fallback)
        if valid then return valid end
        lastError = reason
    end
    error("[n4th] Download failed: " .. tostring(lastError), 0)
end
print("[n4th] Loading build " .. Session.Build)
task.delay(45, function()
    if alive() and not Session.Ready then
        warn("[n4th] Still loading: " .. tostring(Session.InitStep)
            .. ". Send this line if the menu does not appear.")
    end
end)

do
    local getId = getthreadidentity or get_thread_identity or getidentity or (syn and syn.get_thread_identity)
    if type(getId) == "function" then pcall(function() Session.Ident = getId() end) end
    Session.Exec = coroutine.create(function(job)
        while true do
            local ok, err = pcall(job)
            job = coroutine.yield(ok, err)
        end
    end)
end

---------------------------------------------------------------------
-- SERVICES & GAME MODULES
---------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui
local Shared, WorldRemotes, SetTileRemote
local ItemDB, InventoryModule, NetOk, Net
local GameGui, ParticlesOk, ParticlesModule, MenuModOk, MenuModule
local RolesOk, RolesModule, SfxOk, SfxModule
do
    local deadline = os.clock() + 15
    while not LocalPlayer and os.clock() < deadline do
        task.wait(0.1)
        LocalPlayer = Players.LocalPlayer
    end
    assert(LocalPlayer, "[n4th] LocalPlayer not available yet. Enter the game and re-execute.")

    local function requiredChild(parent, name)
        Session.InitStep = parent:GetFullName() .. "/" .. name
        local child = parent:FindFirstChild(name) or parent:WaitForChild(name, 15)
        assert(child, "[n4th] Could not find " .. Session.InitStep .. " after 15 seconds.")
        return child
    end
    PlayerGui = requiredChild(LocalPlayer, "PlayerGui")
    Shared = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage
    GameGui = PlayerGui:FindFirstChild("GameGui")
    Session.Modules = {}
    local indexed, seen, loaded = {}, {}, {}
    local function isModule(object)
        local ok, yes = pcall(function() return object:IsA("ModuleScript") end)
        return ok and yes
    end
    local function add(object)
        if isModule(object) and not seen[object] then
            seen[object] = true
            indexed[#indexed + 1] = object
        end
    end
    local function refreshIndex()
        indexed, seen, loaded = {}, {}, {}
        for _, root in ipairs({ ReplicatedStorage, PlayerGui, LocalPlayer:FindFirstChild("PlayerScripts") or false }) do
            if root then
                local ok, descendants = pcall(root.GetDescendants, root)
                if ok and type(descendants) == "table" then for _, object in pairs(descendants) do add(object) end end
            end
        end
        local used = {}
        for _, api in ipairs({ getloadedmodules or false, getmodules or false }) do
            if type(api) == "function" and not used[api] then
                used[api] = true
                local ok, objects = pcall(api)
                if ok and type(objects) == "table" then
                    for key, value in pairs(objects) do
                        local object = isModule(value) and value or key
                        add(object)
                        if api == getloadedmodules and isModule(object) then loaded[object] = true end
                    end
                end
            end
        end
    end
    local function findModule(parent, name)
        if parent then
            local direct = parent:FindFirstChild(name)
            if isModule(direct) then return direct end
            local found
            for _, child in ipairs(parent:GetDescendants()) do
                if child.Name == name and isModule(child) then
                    if found then return nil, "multiple modules named " .. name .. " in " .. parent:GetFullName() end
                    found = child
                end
            end
            if found then return found end
        end
        local found
        for _, object in ipairs(indexed) do
            if object.Name == name then
                if found then return nil, "multiple modules named " .. name .. " in client list" end
                found = object
            end
        end
        return found
    end
    refreshIndex()
    local function report()
        local folders, names = {}, {}
        for _, child in ipairs(ReplicatedStorage:GetChildren()) do
            folders[#folders + 1] = child.Name .. ":" .. child.ClassName
        end
        for _, object in ipairs(indexed) do names[#names + 1] = object.Name end
        table.sort(folders)
        table.sort(names)
        return ("Place=%s | Version=%s | ReplicatedStorage=%s | Modules=%d [%s] | loadedmodules=%s | getmodules=%s"):format(
            tostring(game.PlaceId), tostring(game.PlaceVersion), table.concat(folders, ", "):sub(1, 900),
            #indexed, table.concat(names, ", "):sub(1, 1400), type(getloadedmodules), type(getmodules))
    end
    local moduleDeadline = os.clock() + 5
    local structuralNames = { "ItemDB", "Inventory", "Net", "WorldMenu", "Roles", "Sfx" }
    local runtimeMatches, exportMatches, triedModules = {}, {}, {}
    local lastGC, runtimeComplete, exportsComplete = -math.huge, false, false
    Session.ModuleScan = { Tables = 0, Loaded = 0, Errors = 0 }
    local function functions(value, names)
        for _, name in ipairs(names) do if type(rawget(value, name)) ~= "function" then return false end end
        return true
    end
    local function isItemDatabase(value)
        local checked, entries, named, metadata, seeds, solids = 0, 0, 0, 0, 0, 0
        for id, item in pairs(value) do
            checked += 1
            if type(id) == "number" and id >= 0 and id % 1 == 0 then
                entries += 1
                if type(item) == "table" and type(rawget(item, "name")) == "string" and rawget(item, "name") ~= "" then
                    named += 1
                    if type(rawget(item, "hits")) == "number" or type(rawget(item, "solid")) == "boolean" or rawget(item, "kind") == "seed" then metadata += 1 end
                    if rawget(item, "kind") == "seed" then seeds += 1 end
                    if rawget(item, "solid") == true then solids += 1 end
                end
            end
            if checked >= 160 or entries >= 64 then break end
        end
        return entries >= 12 and named / entries >= 0.85 and metadata >= 8 and (seeds > 0 or solids >= 4)
    end
    function Session.isMovementMenu(value)
        if type(value) ~= "table" or type(rawget(value, "isDown")) ~= "function" then return false end
        local keys = rawget(value, "KEYS") or rawget(value, "keys")
        if type(keys) == "table" and next(keys) ~= nil then return true end
        return (type(rawget(value, "mount")) == "function" and type(rawget(value, "SKINS")) == "table"
                and type(rawget(value, "DEFAULT_SKIN")) == "number")
            or (rawget(value, "KEYS") == keys and type(keys) == "table")
    end
    local function matches(name, value)
        if type(value) ~= "table" then return false end
        if name == "ItemDB" then return isItemDatabase(value) end
        if name == "Inventory" then
            return rawget(value, "capacity") == nil and functions(value, { "new", "add", "remove", "count", "used", "room", "select" })
        end
        if name == "Net" then
            return functions(value, { "call", "on", "worldTag" }) and type(rawget(value, "CALLS")) == "table"
                and type(rawget(value, "EVENTS")) == "table" and type(rawget(value, "punch")) == "table"
                and type(rawget(rawget(value, "punch"), "send")) == "function"
        end
        if name == "WorldMenu" then return Session.isMovementMenu(value) end
        if name == "Roles" then return functions(value, { "isDeveloper", "isModerator", "isUndercover" }) end
        if name == "Sfx" then return functions(value, { "play", "playAt", "loop" }) end
        return false
    end
    local function rememberMatch(target, name, value, object)
        local previous = target[name]
        if not previous then
            target[name] = { Value = value, Object = object, Candidates = { { Value = value, Object = object } } }
        elseif not rawequal(previous.Value, value) then
            previous.Ambiguous = true
            for _, candidate in ipairs(previous.Candidates) do if rawequal(candidate.Value, value) then return end end
            if #previous.Candidates < 16 then previous.Candidates[#previous.Candidates + 1] = { Value = value, Object = object }
            else previous.Truncated = true end
        end
    end
    local function definitionEquals(a, b, visited, work, depth)
        if rawequal(a, b) then return true end
        if type(a) ~= "table" or type(b) ~= "table" or depth > 12 then return false end
        local paired = visited[a]
        if paired and paired[b] then return true end
        if not paired then paired = {}; visited[a] = paired end
        paired[b] = true
        for key, value in pairs(a) do
            work[1] += 1
            if work[1] > 200000 or not definitionEquals(value, rawget(b, key), visited, work, depth + 1) then return false end
        end
        for key in pairs(b) do if rawget(a, key) == nil then return false end end
        return true
    end
    local function containsDatabase(a, b, deadline)
        local visited, work, checked = {}, { 0 }, 0
        for id, definition in pairs(b) do
            if type(id) == "number" and id >= 0 and id % 1 == 0 then
                if not definitionEquals(rawget(a, id), definition, visited, work, 0) then return false end
                checked += 1
                if checked % 512 == 0 then
                    if not alive() or os.clock() >= deadline then return false end
                    task.wait()
                end
            end
        end
        return true
    end
    local function resolveDatabase(match, deadline)
        if match.Truncated then return nil end
        -- Select only if all other candidate definitions are covered and identical.
        -- Table copies and coherent subset lists are not treated as ID conflicts.
        for _, candidate in ipairs(match.Candidates) do
            local coherent = true
            for _, other in ipairs(match.Candidates) do
                if not containsDatabase(candidate.Value, other.Value, deadline or moduleDeadline) then coherent = false break end
            end
            if coherent then return candidate end
        end
    end
    local function readUpvalues(fn)
        for _, api in ipairs({ (debug and debug.getupvalues) or false, getupvalues or false }) do
            if type(api) == "function" then
                local ok, values = pcall(api, fn)
                if ok and type(values) == "table" and next(values) then return values end
            end
        end
        for _, api in ipairs({ (debug and debug.getupvalue) or false, getupvalue or false }) do
            if type(api) == "function" then
                local values = {}
                for index = 1, 80 do
                    local ok, first, second = pcall(api, fn, index)
                    if not ok then break end
                    if second ~= nil then values[index] = second else values[index] = first end
                end
                if next(values) then return values end
            end
        end
        return {}
    end
    local function actionFunction(fn)
        if fn == actionFunction then return false end
        for _, api in ipairs({ (debug and debug.getconstants) or false, getconstants or false }) do
            if type(api) == "function" then
                local ok, values = pcall(api, fn)
                if ok and type(values) == "table" then
                    local tile, placed, flips, vending, crack = false, false, false, false, false
                    for _, value in pairs(values) do
                        if value == "tile" or value == "SetTile" then tile = true
                        elseif value == "placedAt" then placed = true
                        elseif value == "flips" then flips = true
                        elseif value == "newCrack" or value == "HarvestProvider" then crack = true
                        elseif type(value) == "string" and value:lower():find("empty", 1, true) and value:lower():find("vending", 1, true) then vending = true end
                    end
                    if (tile and placed and flips) or (vending and crack) then return true end
                end
            end
        end
        return false
    end
    local bindingAt, boundDatabase = -math.huge, nil
    local databaseFields = { "ItemDB", "itemDB", "Items", "items", "ItemsById", "ById", "byId" }
    local function recordItemDatabase(results, value, object)
        if isItemDatabase(value) then
            rememberMatch(results, "ItemDB", value, object)
            return
        end
        for _, key in ipairs(databaseFields) do
            local nested = rawget(value, key)
            if type(nested) == "table" and isItemDatabase(nested) then
                rememberMatch(results, "ItemDB", nested, object)
            end
        end
    end
    local actionFields = { "World", "world", "currentWorld", "controller", "data", "shared",
        "tileChanged", "atTile", "backpackNow", "getItem", "itemDef" }
    local function inspectAction(results, node, depth, visited)
        if depth > 5 or (visited[node] and visited[node] <= depth) then return end
        visited[node] = depth
        local members = type(node) == "function" and readUpvalues(node) or nil
        if members then
            for _, value in pairs(members) do
                if type(value) == "table" or type(value) == "function" then
                    inspectAction(results, value, depth + 1, visited)
                end
            end
        else
            pcall(recordItemDatabase, results, node)
            for _, key in ipairs(actionFields) do
                local value = rawget(node, key)
                if type(value) == "table" or type(value) == "function" then
                    inspectAction(results, value, depth + 1, visited)
                end
            end
        end
    end
    function Session.itemsFromReferences()
        if Session.ItemDBSource then return true end
        local refs = Session.References
        if not refs then return false end
        local results, visited = {}, {}
        for _, root in pairs({ refs.Punch, refs.SetTile, refs.World }) do
            inspectAction(results, root, 0, visited)
        end
        local found = results.ItemDB
        if not found then return false end
        if found.Ambiguous then
            found = resolveDatabase(found, os.clock() + 1)
            if not found then return false end
        end
        if not alive() then return false end
        Session.ItemDBSource = found.Value
        Session.Modules.ItemDB = "runtime:ItemDB"
        Session.ModuleScan.DatabaseResolution = "punch, place, and active world references"
        print("[n4th] ItemDB resolved from active game references.")
        return true
    end
    local function databaseFromActions()
        if boundDatabase or os.clock() - bindingAt < 2 then return boundDatabase end
        bindingAt = os.clock()
        if type(getconnections) ~= "function" then return nil end
        local queue, seen, results = {}, {}, {}
        local function push(value)
            if (type(value) == "function" or type(value) == "table") and not seen[value] then
                seen[value] = true
                queue[#queue + 1] = value
            end
        end
        for _, entry in ipairs({ { RunService, { "RenderStepped", "Heartbeat", "PreRender", "Stepped" } },
            { UserInputService, { "InputBegan", "InputEnded", "TouchTap" } } }) do
            for _, name in ipairs(entry[2]) do
                local ok, signal = pcall(function() return entry[1][name] end)
                if ok and signal then
                    local got, connections = pcall(getconnections, signal)
                    if got and type(connections) == "table" then
                        for _, connection in pairs(connections) do
                            local read, fn = pcall(Session.connectionFunction, connection)
                            if read then push(fn) end
                        end
                    end
                end
            end
        end
        local index = 1
        while index <= #queue and index <= 900 and alive() and os.clock() < moduleDeadline do
            local value = queue[index]
            index += 1
            if type(value) == "function" then
                if actionFunction(value) then inspectAction(results, value, 0, {}) end
                for _, upvalue in pairs(readUpvalues(value)) do push(upvalue) end
            elseif not isItemDatabase(value) then
                for _, member in pairs(value) do if type(member) == "function" then push(member) end end
            end
            if index % 100 == 0 then task.wait() end
        end
        local found = results.ItemDB
        if found then
            local resolved = not found.Ambiguous and found or resolveDatabase(found)
            if resolved then
                boundDatabase = resolved.Value
                Session.ModuleScan.DatabaseResolution = "punch/place function upvalues on active game connections"
            end
        end
        return boundDatabase
    end
    local function inspectValue(target, value, object)
        if type(value) ~= "table" then return end
        for _, name in ipairs(structuralNames) do
            if object and name == "ItemDB" then
                pcall(recordItemDatabase, target, value, object)
            else
                local ok, yes = pcall(matches, name, value)
                if ok and yes then rememberMatch(target, name, value, object) end
            end
        end
    end
    local filteredMatches, filteredTried = {}, false
    local function scanFiltered()
        if filteredTried then return end
        filteredTried = true
        local api = filtergc or filter_gc
        if type(api) ~= "function" then return end
        -- Native Arceus filter avoids copying the entire heap into a Lua table.
        -- Results are still validated and database conflicts are still checked.
        local filters = {
            ItemDB = { 2, 4 }, Inventory = { "new", "add", "remove", "count", "used", "room", "select" },
            Net = { "call", "on", "worldTag", "CALLS", "EVENTS", "punch" },
            WorldMenu = { "isDown", "KEYS" },
            Roles = { "isDeveloper", "isModerator", "isUndercover" }, Sfx = { "play", "playAt", "loop" },
        }
        for _, name in ipairs(structuralNames) do
            if not alive() or os.clock() >= moduleDeadline then break end
            local ok, values = pcall(api, "table", { Keys = filters[name] }, false)
            if ok and type(values) == "table" then
                for _, value in pairs(values) do
                    local valid, yes = pcall(matches, name, value)
                    if valid and yes then rememberMatch(filteredMatches, name, value) end
                end
            else Session.ModuleScan.FilterError = tostring(values):sub(1, 160) end
            task.wait()
        end
        Session.ModuleScan.NativeFiltered = true
    end
    local function scanRuntime(retry)
        if runtimeComplete and not retry then return end
        if os.clock() - lastGC < 3 or type(getgc) ~= "function" then return end
        lastGC = os.clock()
        local objects, _, readable = Session.runtimeObjects()
        if not objects then return end
        runtimeMatches = {}
        runtimeComplete = true
        if not readable then return end
        local visited, actionCandidates = 0, {}
        local budget = { next = os.clock() + 0.0015 }
        for _, value in pairs(objects) do
            if not alive() or os.clock() >= moduleDeadline then runtimeComplete = false break end
            if type(value) == "table" then
                Session.ModuleScan.Tables += 1
                inspectValue(runtimeMatches, value)
            elseif type(value) == "function" and #actionCandidates < 2000 then
                actionCandidates[#actionCandidates + 1] = value
            end
            visited += 1
            Session.scanStep(budget, visited)
        end
        -- Some executors only return functions even when getgc(true) is accepted.
        if not runtimeMatches.ItemDB and not boundDatabase then
            local results, seenActions = {}, {}
            for index, fn in ipairs(actionCandidates) do
                if not alive() or os.clock() >= moduleDeadline then break end
                if actionFunction(fn) then inspectAction(results, fn, 0, seenActions) end
                Session.scanStep(budget, index)
            end
            local match = results.ItemDB
            local validated = match and (not match.Ambiguous and match or resolveDatabase(match))
            if validated then
                boundDatabase = validated.Value
                Session.ModuleScan.DatabaseResolution = "punch/place function upvalues from getgc"
            end
        end
        lastGC = os.clock()
    end
    local function clientModule(object)
        -- Do not read CoreGui/engine module exports or run modules that have not loaded yet.
        local parent = object
        for _ = 1, 40 do
            if parent == ReplicatedStorage or parent == PlayerGui then return true end
            if not parent then break end
            parent = parent.Parent
        end
        return false
    end
    local function readExport(object, untilTime)
        local done, ok, value = false, false, nil
        local worker = task.spawn(function()
            ok, value = pcall(require, object)
            done = true
        end)
        while alive() and not done and os.clock() < untilTime do task.wait(0.05) end
        if done then
            if not ok then
                local message = tostring(value):lower()
                if message:find("not allowed", 1, true) or message:find("cannot require", 1, true) then
                    Session.ModuleScan.RequireDenied = true
                end
            end
            return ok, value
        end
        if task.cancel and worker then pcall(task.cancel, worker) end
        return false, "export read timed out"
    end
    local function scanLoaded()
        exportsComplete = true
        for object in pairs(loaded) do
            if not alive() or os.clock() >= moduleDeadline then exportsComplete = false break end
            if not triedModules[object] and clientModule(object) then
                triedModules[object] = true
                Session.InitStep = "reading client export " .. object:GetFullName()
                local ok, value = readExport(object, math.min(moduleDeadline, os.clock() + 1))
                if ok then
                    Session.ModuleScan.Loaded += 1
                    inspectValue(exportMatches, value, object)
                else
                    Session.ModuleScan.Errors += 1
                    Session.ModuleScan.LastError = object:GetFullName() .. ": " .. tostring(value):sub(1, 180)
                end
                task.wait()
            end
        end
    end
    local function structuralModule(name, retry)
        if not table.find(structuralNames, name) then return nil end
        scanFiltered()
        local filtered = filteredMatches[name]
        if filtered then
            if not filtered.Ambiguous then return filtered.Value end
            if name == "ItemDB" then
                local resolved = resolveDatabase(filtered)
                if resolved then return resolved.Value end
                local bound = databaseFromActions()
                if bound then return bound end
            end
        end
        if name == "ItemDB" then
            local active = databaseFromActions()
            if active then return active end
        end
        scanRuntime(retry)
        local found = runtimeMatches[name]
        if runtimeComplete and found and not found.Ambiguous then return found.Value, found.Object end
        if runtimeComplete and found and name == "ItemDB" then
            local resolved = resolveDatabase(found)
            if resolved then
                Session.ModuleScan.DatabaseResolution = "identical/covered definitions, candidates=" .. #found.Candidates
                return resolved.Value, resolved.Object
            end
        end
        if name == "ItemDB" then
            local value = databaseFromActions()
            if value then return value end
        end
        scanLoaded()
        found = exportMatches[name]
        if exportsComplete and found then
            if found.Ambiguous and name == "ItemDB" then
                local resolved = resolveDatabase(found)
                if resolved then return resolved.Value, resolved.Object end
            end
            if found.Ambiguous then return nil, nil, "multiple exports match shape " .. name end
            return found.Value, found.Object
        end
        if runtimeMatches[name] and runtimeMatches[name].Ambiguous then return nil, nil, "multiple runtime tables match shape " .. name end
    end
    local function loadModule(parent, name, required)
        Session.InitStep = "searching for module " .. name
        local object, reason = findModule(parent, name)
        local value, shapedObject
        if not object and not reason then value, shapedObject, reason = structuralModule(name) end
        while not object and not reason and required and alive() and os.clock() < moduleDeadline do
            if value then break end
            -- Single shared timeout; do not wait for Shared folder which may have been moved.
            if parent then parent:WaitForChild(name, math.min(1, moduleDeadline - os.clock()))
            else task.wait(0.25) end
            task.wait(0.1) -- a child with the same name may be a Folder; do not busy-loop
            refreshIndex()
            object, reason = findModule(parent, name)
            if not object and not reason then value, shapedObject, reason = structuralModule(name, true) end
        end
        if value then
            Session.Modules[name] = shapedObject and shapedObject:GetFullName() or "runtime:" .. name
            print("[n4th] " .. name .. " resolved from data: " .. Session.Modules[name])
            return true, value, shapedObject
        end
        if object then
            Session.InitStep = "loading " .. object:GetFullName()
            local ok, result = readExport(object, os.clock() + 4)
            if ok and type(result) == "table"
                and (name ~= "WorldMenu" or type(rawget(result, "isDown")) == "function") then
                Session.Modules[name] = object:GetFullName()
                return true, result, object
            end
            reason = ok and "module export did not match" or tostring(result)
            local recovered, recoveredObject = structuralModule(name, true)
            if recovered then
                Session.Modules[name] = recoveredObject and recoveredObject:GetFullName() or "runtime:" .. name
                return true, recovered, recoveredObject
            end
        end
        local message = "[n4th] Module " .. name .. ": " .. (reason or "not found")
        if required then
            Session.BootstrapReport = report()
            warn("[n4th] Client structure: " .. Session.BootstrapReport)
            warn(("[n4th] Data scan: tables=%d | exports=%d | failed=%d | last=%s"):format(
                Session.ModuleScan.Tables, Session.ModuleScan.Loaded, Session.ModuleScan.Errors, tostring(Session.ModuleScan.LastError)))
            error(message .. ". Run n4th-diagnose.lua to inspect the latest client structure.", 0)
        end
        warn(message .. " (optional, continuing to load menu)")
        return false, nil
    end
    function Session.findModule(name, parent)
        refreshIndex()
        return findModule(parent or Shared, name)
    end
    WorldRemotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
    SetTileRemote = WorldRemotes and WorldRemotes:FindFirstChild("SetTile")
    local _, itemDB, itemModule = loadModule(Shared, "ItemDB", false)
    ItemDB = itemDB
    if itemDB then moduleDeadline = os.clock() + 8 end
    -- Modules split across folders can still be located through the client index.
    Shared = (itemModule and itemModule.Parent) or Shared
    local _, inventory = loadModule(Shared, "Inventory", false)
    InventoryModule = inventory
    NetOk, Net = loadModule(Shared, "Net", false)
    ParticlesOk, ParticlesModule = loadModule(GameGui, "Particles", false)
    local menuObject
    MenuModOk, MenuModule, menuObject = loadModule(GameGui, "WorldMenu", false)
    if not GameGui and menuObject then GameGui = menuObject.Parent end
    RolesOk, RolesModule = loadModule(Shared, "Roles", false)
    SfxOk, SfxModule = loadModule(Shared, "Sfx", false)
    function Session.resolveMovement()
        if Session.MovementScan or Session.ItemScan or not alive() then return nil end
        if os.clock() - (Session.MovementScanAt or -math.huge) < 3 then return nil end
        Session.MovementScanAt, Session.MovementScan = os.clock(), true
        local ok, value = pcall(function()
            GameGui = PlayerGui:FindFirstChild("GameGui") or GameGui
            refreshIndex()
            moduleDeadline = os.clock() + 3
            triedModules, exportMatches = {}, {}
            local object = findModule(GameGui, "WorldMenu")
            if object then
                local read, result = readExport(object, math.min(moduleDeadline, os.clock() + 1))
                if read and type(result) == "table" and type(rawget(result, "isDown")) == "function" then return result end
                triedModules[object] = true
            end
            scanLoaded()
            local match = exportMatches.WorldMenu
            if match and exportsComplete and not match.Ambiguous then return match.Value end
        end)
        Session.MovementScan = false
        if ok then return value end
        warn("[n4th] Movement control scan: " .. tostring(value))
    end
    function Session.resolveItems(quick)
        if Session.ItemDBSource then return true end
        if Session.ItemScan or Session.MovementScan then return false end
        Session.ItemScan = true
        lastGC = -math.huge
        bindingAt, boundDatabase = -math.huge, nil
        runtimeComplete, exportsComplete, filteredTried = false, false, false
        runtimeMatches, exportMatches, triedModules, filteredMatches = {}, {}, {}, {}
        local ok, reason = pcall(function()
            local found = Session.itemsFromReferences()
            moduleDeadline = os.clock() + (quick and 4 or 12)
            GameGui = PlayerGui:FindFirstChild("GameGui") or GameGui
            refreshIndex()
            local value, object
            if not found then
                local _
                _, value, object = loadModule(Shared, "ItemDB", not quick)
            end
            Shared = (object and object.Parent) or Shared
            Session.ItemDBSource = value or Session.ItemDBSource
            if not InventoryModule then
                local _, inventory = loadModule(Shared, "Inventory", false)
                InventoryModule = inventory
            end
            if not NetOk then NetOk, Net = loadModule(Shared, "Net", false) end
            if not MenuModOk then MenuModOk, MenuModule = loadModule(GameGui, "WorldMenu", false) end
        end)
        Session.ItemScan = false
        if not ok then warn("[n4th] ItemDB scan: " .. tostring(reason)) end
        return Session.ItemDBSource ~= nil
    end
    Session.InitStep = "game modules ready"
end

-- Item metadata is constant for a session. Copy only used IDs;
-- cross-VM table reads per tile are far more expensive than a local cache.
do
    local source = ItemDB
    Session.ItemDBSource = source
    ItemDB = setmetatable({}, { __index = function(cache, id)
        local database = Session.ItemDBSource
        local item = database and database[id]
        if type(item) ~= "table" then return item end
        local copy = {}
        for key, value in pairs(item) do copy[key] = value end
        rawset(cache, id, copy)
        return copy
    end })
end

do
    -- PNGs from logo.png and icons/farm.png in n4th v3, embedded for single-file loader.
    local function loadBrandAssets()
        local register = getcustomasset or getsynasset
        if type(writefile) ~= "function" or type(register) ~= "function" then return end

        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local lookup = {}
        for i = 1, #alphabet do lookup[alphabet:byte(i)] = i - 1 end

        local function loadImage(name, encoded)
            local bytes, accumulator, bits = {}, 0, 0
            for i = 1, #encoded do
                local value = lookup[encoded:byte(i)]
                if value then
                    accumulator = accumulator * 64 + value
                    bits += 6
                    if bits >= 8 then
                        bits -= 8
                        local divisor = 2 ^ bits
                        bytes[#bytes + 1] = string.char(math.floor(accumulator / divisor))
                        accumulator %= divisor
                    end
                end
            end
            local ok, asset = pcall(function()
                local path = name .. ".png"
                writefile(path, table.concat(bytes))
                return register(path)
            end)
            if ok and type(asset) == "string" and asset ~= "" then return asset end
        end

        Session.BrandLogo = loadImage("n4th-v3-logo", "iVBORw0KGgoAAAANSUhEUgAABAAAAAQACAYAAAB/HSuDAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAGuoSURBVHhe7fx9sG35WR92Npgqgt33nHte7rnvt+9b9+1uSSCEXpAQamFJDWpJjSUkoe5GQAHOwMSkhngcirIdAnEcMAkODjaemBAcjF2mKpnglxgrGCdTYBhc9gCeKfBYODEVLE8yUDEDGATcO6fhXGutH9++WmftvfZ+1t6fb9XnH/u0kJ77e/bZz7er7kMiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIqfJ3Rdu73Td+5I713uef/wzel648+aeDz7x1q5feP+tr+j6oadv/GEA2Hbt78e7H3zima729+vdDz7++q7f9fv5uccOu05+rYuIiIi8dBQAADC99vejAkBERERWHgUAAEyv/f2oABAREZGVRwEAANNrfz8qAEREROR35d77bu52/W9f8Njnd/3Ntz7yp7q+47Mu/62ub3j1pQ93fdXLz/9q1zM3D+91vfrK3gNdO9ztOb+/AwAs6Oq53Z70O7ir/f39f3z5+V/v+g9fc/nnuv7zN179u11/8y3X/3TX//q+x97fdfeLH73cdfK1RERERKaMAgAANp8CQERERBQAALAFFAAiIiKiAACALaAAEBER2YDc/aJP/X1d/+Q9j/2Bru9845Xv6/o/v/LiP+/63BsH97ouHuz0pC8RAACncaHxtusHPf/uKy/8Qtd3vfHqf9f1T95964u77n7w8YOuk69FIiIimx0FAABQnQJARERkCVEAAADVKQBERESWEAUAAFCdAkBERCTk7nuvfErX3336+ld3/dFXXfx/d73j1uHdriuHu/e60i9hAIA5af8FxdM3Dnr+2Ksu/i9dH3r6kW/suvfcY4ddJ1+7RERE1hsFAABAnwJAREQ2MgoAAIA+BYCIiGxkFAAAAH0KABERmWX+H8/eeEfXN7/20g93vev24W92pV+CAAAM9/SNg7tdf+I1l/5R1489c+PLu+5+9e1P7jr5GiciInK6KAAAAFZLASAiImuJAgAAYLUUACIispYoAAAAVksBICIiS8m9p576pK7vf8sjX9f15U8e/e9d1w5373WlX1IAAKzO5YPdnufunPu1ru9507U/13X3y+6c6Tr5WigiIpseBQAAwLwpAEREZFAUAAAA86YAEBGRQVEAAADMmwJARER+O+1fAvNXf/+1P9n1/J3DX+66eLBzryv9kgEAYL7ecevwN7r+7Osvf2/X3fc+ud918rVSRESqRwEAAECXAkBEZEOjAAAAoEsBICKyoVEAAADQpQAQEZlp7j300Cd0/aU3P/KNXe999PDXutIvAQAAuO+pR/Z/q+tbX3/5+7ruvvfKp3SdfC0VEZGpowAAAGCZFAAiIkWjAAAAYJkUACIiRaMAAABgmRQAIiJF8n/7vNtPdX3VK87/i65LBzv3utKHOgAAjPWuWwe/2vWXn7r6lV0nX1tFRGTRKAAAAFgnBYCIyIqiAAAAYJ0UACIiK4oCAACAdVIAiIgsKffed3O36z96zaUPdT158ey9rvShDAAAq3LlcLfn33rFhQ93/fW33Xx518nXXhERUQAAADAnCgARkZFRAAAAMCcKABGRkVEAAAAwJwoAEZGB+b+++foXdr395uGvd6UPWQAAmItXXNy72/XNr730bV0nX4tFRDY/CgAAADaZAkBE5CQKAAAANpkCQETkJAoAAAA2mQJARLYm977+oU/s+rY3XP4rXY+dP3uvK31oAgDAprjQ+Ionj3666wc+88p+18nXahGR+lEAAADAxygARGRjowAAAICPUQCIyMZGAQAAAB+jABCRjck/+vxbV7v+0CvO/1xX+hBkda4c7vZ89rWDni954qjnG159qed7nrrW83c/70bPjzxzs+cfvLPv597zKADwcbS/P9vfr+3v37/01NWe9vf3lz5xvudNjxz0tN8P0ncIVudN1/Z/retbX3vx87tOvnaLiKw/CoDa2l/wCgAAqKf9/dn+fm1//yoANosCQERmEwVAbe0veAUAANTT/v5sf7+2v38VAJtFASAis4kCoLb2F7wCAADq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")
        Session.FarmLogo = loadImage("n4th-v3-farm", "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")
    end
    loadBrandAssets()
end
Session.InitStep = "config and game references"

---------------------------------------------------------------------
-- SETTINGS & DATA
---------------------------------------------------------------------
local State = {
    Running = false,
    Mode = "Place + Break",       -- "Place + Break" | "Break only" | "Place only"
    PlaceMs = 250,                -- delay after each place
    BreakMs = 220,                -- delay per punch (normal 220)
    AfterBreakMs = 250,           -- delay after block breaks
    HitsOverride = 0,             -- manual punch count (0 = auto)
    BreakBackground = true,       -- always break background as well (no toggle)
    MultiTarget = 1,              -- number of tiles punched alternately (1 = single)
    SelectedId = nil,
    WorldBreakId = nil,           -- single foreground block type from active world
    WorldBreakCollect = false,    -- separate from Auto Farm / Clear World collect options
    Offsets = {},                 -- tiles selected on the Grid
    CalibX = 0,
    CalibY = 0,
    AntiAfk = true,
    MutePunch = true,
    Visual = true,                -- hand animation on break / place / plant / harvest (visual only)
    LiteMode = false,
    AutoCollect = true,           -- pick up drops on selected tiles
    CollectAround = false,        -- pick up drops around character (radius) anytime
    CollectRadius = 3,            -- collect radius (tiles), used in Remote mode
    CollectMode = "Touch",     -- "Touch" (body touch, like manual play) / "Remote" (remote pickup, legacy)
    Override = nil,               -- Factory uses its own tiles & block
    Quiet = false,                -- without notifications (used by Factory)
    Cycles = 0,
    Placed = 0,
    Broken = 0,
    Collected = 0,                -- number of drops collected
    CollectFail = 0,              -- number of drops rejected by server
    LastAction = "-",
    SeedDrop = false,             -- broken seeds accumulated -> drop at drop point
    SeedDropAt = 190,             -- drop when seed count reaches this amount
    SeedKeep = 0,                 -- seeds to keep
    Dropped = 0,
    DropPause = false,            -- Auto Farm temporarily paused (going to drop)
    DropYield = false,            -- AutoDrop requested farm cycle to finish breaking placed blocks first
    DropYieldWait = false,        -- hold farmLoop cleanly until AutoDrop takes over
}

local Misc = {
    Speed = 100,      -- walkspeed % (100 = normal)
    InfJump = false,
    Ghost = false,    -- fly + noclip through blocks
    UpHeld = false,   -- on-screen UP button held
    DownHeld = false, -- on-screen DN button held
    CustomName = true,          -- name watermark (always on, removed only when script closes)
    NameText = "https://dsc.gg/nath",  -- watermark text
}

-- Auto Clear World
local Clear = {
    Running = false,
    IncludeBg = true,         -- also break background
    UseBlock = true,          -- place scaffold block if there is no footing
    ScaffoldId = nil,         -- block used for scaffolding
    Collect = true,           -- collect drops after each break
    Sweep = "Left -> Right",   -- "Left -> Right" or "Zig-zag"
    Skip = {},                -- temporarily skipped tiles
    TopRow = -1,              -- row currently being cleared
    DirRow = nil,             -- zig-zag direction for this row
    Dir = nil,
    Broken = 0,
    Remaining = -1,
    Status = "-",
}

-- Auto Splice: plant Seed A then splice Seed B
local Splice = {
    Running = false,
    Roam = true,        -- roam whole world using A* (false = Grid tiles only)
    Roaming = false,
    A = nil,
    B = nil,
    Ms = 300,
    Made = 0,
    Planted = 0,
    Fail = {},
    Skip = {},
    Status = "-",
    Row = {},           -- row currently being worked on (neat per row)
}

-- Land (farm world): block rows from top to bottom
local Land = {
    X0 = 0, X1 = 99,  -- start & end columns
    Y0 = 2,           -- topmost block row
    Gap = 2,          -- spacing between rows (2 = 1 empty tile for trees)
    Rows = 10,        -- number of rows
    Stairs = true,    -- row ends opened alternately left/right (walk up/down like stairs)
}

-- Build Land
local Build = {
    Running = false,
    BlockId = nil,
    Dirt = { X0 = 0, X1 = 99, Y0 = 2, Y1 = -1, Dig = false },
    UseBlock = true,     -- allow placing scaffold blocks if the first row is unreachable
    Produce = true,      -- short on blocks -> produce first (plant & harvest) until enough
    ThenFactory = false,  -- done -> automatically start Factory
    Placed = 0,
    Phase = "-",
    Status = "-",
    Skip = {},
    FieldSkip = {},      -- temporarily skipped harvest / plant tiles (block production)
    Row = {},            -- production planting row currently in progress
    Harvested = 0,
    Planted = 0,
    Dug = 0,             -- tiles being dug (block + background)
    Carved = {},         -- [idx] = true: block dug by Build Land (background also broken)
    Surface = nil,       -- natural ground surface y (background below it is also broken)
    Under = {},          -- [row] = time: temporarily place from below (cannot climb onto that row)
    BreakTimes = {},     -- tiles that keep reverting after being dug
    Reserve = 0,         -- blocks reserved from placing (kept to make seeds)
    RESERVE = 10,        -- keep this many blocks during production
    BreakX = -1, BreakY = -1, -- production break position (unset = automatic at right end of row)
    Tiles = {},          -- production break tiles, relative to break position ("dx,dy") (Grid Land mode)
}

-- Vending: stock from drops / empty until done
local Vend = {
    Running = false,
    Mode = "Stock from drops",  -- or "Empty until done"
    Point = "",                    -- vending drop point: "WORLD" / "WORLD:ID" (empty = current world)
    Status = "-",
    Stocked = 0, Taken = 0, Dropped = 0,
    Picked = {},                   -- [id] = collected count not yet stocked into vending
    Items = {},                    -- items allowed to be picked up / stocked / emptied (empty = all)
    Kind = "All",                -- "All" / "Blocks only" / "Seeds only"
    Seen = {},                     -- seen items (vending, bag, drops) for selection list
    DropX = -1, DropY = -1,        -- standing position at vending drop point (-1 = arrival point)
    Carry = {},                    -- [id] = count taken from vending (empty mode)
}

-- Factory: break blocks -> plant seeds -> harvest -> break again, excess seeds dropped
local Factory = {
    Running = false,
    SeedId = nil,
    BlockId = nil,
    WholeWorld = false,  -- plant & harvest across the whole world (not just land)
    SideTiles = 2,       -- harvest N tiles left + N right, including center tile
    CollectDist = 2,     -- collect by walking right N tiles then left N tiles
    BreakAt = 200,       -- start breaking when block count reaches this amount
    Harvesting = false,  -- suppress break auto-collect during harvest/plant phases
    Got = {},            -- harvested seed IDs whose blocks may be collected
    Tiles = {},          -- break tiles, relative to break position ("dx,dy")
    BreakX = -1, BreakY = -1,
    BreakSec = 60,       -- duration of 1 break session before checking trees again
    Drop = true,
    Keep = 50,           -- seeds to keep for replanting
    DropAt = 200,        -- drop when seed count reaches this amount
    DropWorld = "",      -- "" = current world | "WORLD" | "WORLD:ID"
    DropX = -1, DropY = -1,
    Harvested = 0,
    Planted = 0,
    Dropped = 0,
    Skip = {},
    Status = "-",
    Traveling = false,
    Home = "",
    Zone = nil,          -- drop location (excluded from auto-collect), shared across all drop features
    Row = {},            -- planting row currently in progress
}

local AutoDrop = {
    On = false,
    Items = {},
    World = "",
    X = -1, Y = -1,
    Facing = 1,
    Busy = false,
    Cancelled = false,
    Dropped = 0,
    Status = "Off",
    Zones = {},
}

local WorldFinder = {
    Running = false,
    Busy = false,
    Cancelled = false,
    Mode = "Mixed",
    Custom = "",
    Manual = "",
    Limit = 100,
    DelaySec = 8,
    WebhookEach = false,
    Checked = 0, Found = 0, Locked = 0, Unknown = 0, Failed = 0,
    Status = "Off",
    Results = {},
    FoundNames = {},
    Logs = {},
}

local Guard = {
    On = false,
    Who = "Staff (Mod/Dev)",   -- "Staff (Mod/Dev)" | "All players"
    StopAll = true,            -- pause all activities
    Leave = false,             -- leave world
    AutoBack = true,           -- resume after safe
    BackSec = 60,              -- (leave world) wait before re-entering
    CalmSec = 5,               -- (pause) wait until clear before resuming
    Mode = "idle",             -- idle | pause | away | out | back
    Allow = {},                -- regular players already present when Guard was enabled (ignored)
    Alerted = {},              -- already warned
    Saved = nil,               -- activity before being paused
    Token = 0,
    BackAt = 0,
    CalmAt = nil,
    LeftFg = nil,
    BackText = nil,
    Status = "Off",
    Detected = 0,
}

-- Farmer: automatic harvest & plant
local Farmer = {
    Running = false,
    Harvest = true,
    Plant = true,
    Collect = true,
    UseBlock = false,   -- place scaffold block if no path
    ScaffoldId = nil,
    HarvestMs = 250,    -- delay after each harvest
    PlantMs = 250,      -- delay after each plant
    SeedId = nil,
    Skip = {},
    Harvested = 0,
    Planted = 0,
    Status = "-",
    Drop = false,       -- inventory almost full -> drop harvest items at drop point
    DropAt = 190,       -- drop when harvested item reaches this count
    Keep = 50,          -- planting seeds to keep
    Dropped = 0,
    Got = {},           -- tree seeds previously harvested (to identify harvest items)
    Row = {},           -- planting row currently in progress (plant neatly per row)
}

-- Virtual movement keys (used by Clear & Farmer)
local AutoInput = { active = false, left = false, right = false, jump = false, down = false }

-- Auto Chat
local Spam = {
    On = false,
    Texts = {},         -- message list, sent in rotation
    IntervalSec = 6,
    Index = 1,
    Sent = 0,
    Last = "-",
}

local Refs = {
    World = nil,      -- world data (fg, bg, size)
    Inv = nil,        -- inventory
    SetTile = nil,    -- game place function
    State = nil,      -- character position
    Punch = nil,      -- game punch function
    Particles = {},   -- particles (for Lite mode)
    Menu = nil,       -- game menu (leave / enter world)
    Gems = nil,       -- gems display updater
    Hud = nil,        -- punch & place reach
    Trees = nil,      -- tree data (plant timestamp)
    Others = nil,     -- other players list in world (for Guard)
}
Session.References = Refs

-- World drop list (read from game)
local Drops = { list = nil, update = nil, brokeAt = {} }
-- Action animation: game hand draw function + "last action" upvalue index (filled on connect)
local Anim = { fn = nil, idx = nil, set = nil }
local DropFailUntil = {}   -- rejected drops, retried later

local UI = { Tabs = {}, DropdownTabs = {}, PendingDropdowns = {} }
UI.Palette = {
    Background = Color3.fromRGB(32, 34, 37),
    Panel = Color3.fromRGB(47, 49, 54),
    Surface = Color3.fromRGB(54, 57, 63),
    Border = Color3.fromRGB(37, 40, 43),
    WindowBorder = Color3.fromRGB(32, 34, 37),
    Text = Color3.fromRGB(255, 255, 255),
    Muted = Color3.fromRGB(142, 146, 151),
    Icon = Color3.fromRGB(220, 221, 222),
    Accent = Color3.fromRGB(114, 137, 228),
    Amber = Color3.fromRGB(250, 166, 26),
    Action = Color3.fromRGB(114, 137, 228),
    Stop = Color3.fromRGB(240, 71, 71),
}
function UI.tabVisible(title)
    if not UI.Window then return true end
    if UI.Window.Closed then return false end
    local tab = title and UI.Tabs[title]
    return not title or (tab and tab.Selected == true) or false
end

-- Run fn with elevated thread identity. Returns: ok, err (like pcall)
function UI.ident()
    local getId = getthreadidentity or get_thread_identity or getidentity or (syn and syn.get_thread_identity)
    if type(getId) ~= "function" then return nil end
    local ok, v = pcall(getId)
    return ok and v or nil
end
function UI.exec(fn)
    local setId = setthreadidentity or set_thread_identity or setidentity or (syn and syn.set_thread_identity)
    local function elevate()
        if Session.Ident and type(setId) == "function" then pcall(setId, Session.Ident) end
    end
    local err1 = nil
    local co = Session.Exec
    if co and coroutine.status(co) == "suspended" then
        local okR, ok, err = coroutine.resume(co, function()
            elevate()
            fn()
        end)
        if okR and ok ~= false then return true end
        err1 = okR and err or ok
    end
    -- fallback: run on this thread (after restoring its identity)
    elevate()
    local ok2, err2 = pcall(fn)
    if ok2 then return true end
    return false, tostring(err2 or err1)
end
UI.Jobs = {}
function UI.later(key, fn, delay)
    UI.Jobs[key] = { fn = fn, at = os.clock() + (delay or 0) }
end
-- Run due UI jobs (called by the INIT thread, see INIT section)
function UI.runJobs()
    if UI.flushInventory then UI.flushInventory() end
    local now = os.clock()
    local due = {}
    for key, job in pairs(UI.Jobs) do
        if now >= job.at then due[#due + 1] = key end
    end
    for _, key in ipairs(due) do
        local job = UI.Jobs[key]
        if job and now >= job.at then
            UI.Jobs[key] = nil
            local ok, err = pcall(job.fn)
            if not ok then warn("[n4th] UI job " .. tostring(key) .. ": " .. tostring(err)) end
        end
    end
end
local Connections = {}
local HitCount = {}   -- hit counter (fallback)
local PlacedAt = {}   -- when tile was placed

local function notify(title, content, dur)
    task.defer(function()
        pcall(function()
            if UI.notify then UI.notify(title, content, dur) end
        end)
    end)
end

---------------------------------------------------------------------
-- CONFIG: auto save & load settings
---------------------------------------------------------------------
-- How it works:
--   1. On execute, config file is read and values are applied to settings
--      BEFORE UI creation, so toggles & sliders immediately reflect saved config.
--   2. Every 3 seconds current settings are compared against the last saved snapshot.
--      Anything changed -> immediately saved (auto save).
--   3. Per-account file: workspace/n4thOpus/config_<UserId>.json
--   Not saved: run toggles (Auto Farm / Clear / Farmer / Chat), fly & inf jump.
local Config = {
    AutoSave = true,
    Paused = false,      -- true after reset (so the file is not recreated)
    Folder = "n4thOpus",
    Data = {},           -- file contents on execute
    List = {},           -- registered setting tables
    LastJson = nil,
    Status = "-",
}

do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local HttpService = game:GetService("HttpService")
    local canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    Config.CanFile = canFile
    Config.Path = Config.Folder .. "/config_" .. tostring(LocalPlayer.UserId) .. ".json"

    local function read()
        if not canFile then return nil end
        local okE, exists = pcall(isfile, Config.Path)
        if not okE or not exists then return nil end
        local okR, raw = pcall(readfile, Config.Path)
        if not okR or type(raw) ~= "string" then return nil end
        local okD, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if okD and type(data) == "table" then return data end
        return nil
    end

    local loaded = read()
    local migrated = false
    if type(loaded) == "table" then
        local function mvSection(oldK, newK)
            if loaded[oldK] ~= nil then
                if type(loaded[newK]) ~= "table" then
                    loaded[newK] = loaded[oldK]
                elseif type(loaded[oldK]) == "table" then
                    for k, v in pairs(loaded[oldK]) do
                        if loaded[newK][k] == nil then loaded[newK][k] = v end
                    end
                end
                loaded[oldK] = nil
                migrated = true
            end
        end
        local function mvKey(sec, oldK, newK)
            local t = loaded[sec]
            if type(t) == "table" and t[oldK] ~= nil then
                if t[newK] == nil then t[newK] = t[oldK] end
                t[oldK] = nil
                migrated = true
            end
        end
        local function mapVal(sec, key, map)
            local t = loaded[sec]
            if type(t) == "table" and type(t[key]) == "string" and map[t[key]] then
                t[key] = map[t[key]]
                migrated = true
            end
        end
        mvSection("Lahan", "Land")
        mvSection("Bangun", "Build")
        mvSection("Pabrik", "Factory")
        mvSection("Penjaga", "Guard")
        mvSection("Tas", "Bag")
        if loaded.Bahasa ~= nil then
            loaded.Bahasa = nil
            migrated = true
        end
        mvKey("Build", "ThenPabrik", "ThenFactory")
        mvKey("Discord", "Penjaga", "Guard")
        mvKey("Discord", "Pabrik", "Factory")
        mapVal("Farm", "Mode", { ["Break saja"] = "Break only", ["Place saja"] = "Place only" })
        mapVal("Farm", "CollectMode", { ["Sentuhan"] = "Touch" })
        mapVal("Clear", "Sweep", { ["Kiri \226\134\146 Kanan"] = "Left -> Right", ["Left \226\134\146 Right"] = "Left -> Right" })
        mapVal("Vending", "Mode", { ["Isi stock dari drop"] = "Stock from drops", ["Kosongkan sampai habis"] = "Empty until done" })
        mapVal("AutoDrop", "Facing", { ["Kanan"] = "Right", ["Kiri"] = "Left" })
        mapVal("WorldFinder", "Mode", { ["Campuran"] = "Mixed", ["3 Huruf"] = "3 letters", ["4 Huruf"] = "4 letters", ["Kata Indonesia"] = "Indonesian words", ["Daftar sendiri"] = "Custom list" })
        mapVal("Guard", "Who", { ["Semua pemain"] = "All players" })
        mapVal("Growscan", "Layer", { ["Semua"] = "All", ["Depan"] = "Front" })
    end
    Config.Found = loaded ~= nil
    Config.Migrated = migrated
    Config.Data = loaded or {}
    if Config.Data.AutoSave == false then Config.AutoSave = false end
    Config.Status = Config.Found and "Config loaded" or (canFile and "No config yet" or "Executor cannot save files")

    -- Register a settings table. Saved values from file are applied immediately
    -- (except keys in 'later', applied manually after connecting to the game).
    function Config.add(name, tbl, keys, later)
        table.insert(Config.List, { name = name, tbl = tbl, keys = keys })
        local saved = Config.Data[name]
        if type(saved) ~= "table" then return end
        for _, k in ipairs(keys) do
            local v, cur = saved[k], tbl[k]
            if v ~= nil and not (later and later[k]) and (cur == nil or type(v) == type(cur)) then
                tbl[k] = v
            end
        end
    end

    function Config.saved(name, key)
        local t = Config.Data[name]
        return type(t) == "table" and t[key] or nil
    end

    local function collect()
        local out = { AutoSave = Config.AutoSave, Version = 2 }
        for _, e in ipairs(Config.List) do
            local t = {}
            for _, k in ipairs(e.keys) do t[k] = e.tbl[k] end
            out[e.name] = t
        end
        return out
    end

    local function copy(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local result = {}
        seen[value] = result
        for key, entry in pairs(value) do result[key] = copy(entry, seen) end
        return result
    end
    local function equal(value, saved, seen)
        if rawequal(value, saved) then return true end
        if type(value) ~= "table" or type(saved) ~= "table" then return false end
        seen = seen or {}
        if seen[value] == saved then return true end
        seen[value] = saved
        for key, entry in pairs(value) do if not equal(entry, saved[key], seen) then return false end end
        for key in pairs(saved) do if value[key] == nil then return false end end
        return true
    end

    function Config.save(force)
        if not canFile then
            Config.Status = "Executor cannot save files"
            return false
        end
        if Config.Paused and not force then return false end
        local current = collect()
        -- Compare snapshot before encoding: idle config does not generate a new JSON
        -- every three seconds. Deep copy also detects in-place grid edits.
        if not force and equal(current, Config.LastSnapshot) then return true end
        local okJ, json = pcall(HttpService.JSONEncode, HttpService, current)
        if not okJ then
            Config.Status = "Failed to serialize settings"
            return false
        end
        if not force and json == Config.LastJson then
            Config.LastSnapshot = copy(current)
            return true
        end
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local okF, has = pcall(isfolder, Config.Folder)
            if okF and not has then pcall(makefolder, Config.Folder) end
        end
        local ok = pcall(writefile, Config.Path, json)
        if ok then
            Config.LastJson = json
            Config.LastSnapshot = copy(current)
            Config.Paused = false
            Config.Status = "Saved " .. os.date("%H:%M:%S")
        else
            Config.Status = "Failed to save file"
        end
        return ok
    end

    -- Delete config file (re-execute = reset to defaults)
    function Config.reset()
        Config.Paused = true
        Config.LastJson = nil
        Config.LastSnapshot = nil
        if canFile and type(delfile) == "function" then
            local ok = pcall(delfile, Config.Path)
            Config.Status = ok and "Config deleted. Re-execute for defaults" or "Failed to delete file"
            return ok
        end
        Config.Status = "Executor cannot delete files"
        return false
    end

    function Config.start()
        -- Use file contents as snapshot rather than treating new defaults as already saved.
        if Config.Found and not Config.Migrated then Config.LastSnapshot = copy(Config.Data) end
        task.spawn(function()
            while alive() do
                task.wait(3)
                if Config.AutoSave and alive() then Config.save(false) end
            end
        end)
    end
end)() end

Config.add("Farm", State, {
    "Mode", "PlaceMs", "BreakMs", "AfterBreakMs", "HitsOverride", "SelectedId", "Offsets",
    "CalibX", "CalibY", "AntiAfk", "MutePunch", "Visual", "LiteMode", "AutoCollect", "MultiTarget",
    "CollectAround", "CollectRadius", "CollectMode",
    "WorldBreakId", "WorldBreakCollect",
})
-- Migrate old default values. User choices in newer versions are preserved.
if (Config.Data.Version == nil or Config.Data.Version == 1) and State.AfterBreakMs == 300 then
    State.AfterBreakMs = 250
end
Config.add("Clear", Clear, { "UseBlock", "ScaffoldId", "Collect", "Sweep" })
Config.add("Farmer", Farmer, {
    "Harvest", "Plant", "Collect", "UseBlock", "ScaffoldId", "HarvestMs", "PlantMs", "SeedId",
})
-- update 1084: game enforces minimum action delays (place ~0.135s, punch ~0.19s)
State.PlaceMs = math.max(State.PlaceMs, 140)
State.BreakMs = math.max(State.BreakMs, 200)
Farmer.HarvestMs = math.max(Farmer.HarvestMs, 140)
Farmer.PlantMs = math.max(Farmer.PlantMs, 140)
Config.add("Misc", Misc, { "Speed" })
Config.add("Chat", Spam, { "Texts", "IntervalSec" })
Config.add("Land", Land, { "X0", "X1", "Y0" })
Config.add("DirtFarm", Build.Dirt, { "X0", "X1", "Y0", "Y1", "Dig" })
Config.add("Build", Build, { "BlockId", "ThenFactory", "BreakX", "BreakY", "Tiles" })
Config.add("Vending", Vend, { "Mode", "Point", "Items", "DropX", "DropY" })
Config.add("AutoDrop", AutoDrop, { "Items", "World", "X", "Y", "Facing" })
Config.add("WorldFinder", WorldFinder, { "Mode", "Custom", "Manual", "Limit", "DelaySec", "WebhookEach" })
Config.add("Factory", Factory, {
    "SeedId", "WholeWorld", "SideTiles", "CollectDist", "BreakAt", "Tiles", "BreakX", "BreakY",
    "Drop", "Keep", "DropAt", "DropWorld", "DropX", "DropY",
})
---------------------------------------------------------------------
-- SESSION STATS & DISCORD NOTIFICATIONS (shown in Info & Stats and Discord)
---------------------------------------------------------------------
local Stats = { T0 = os.clock(), Gems0 = nil, Items = {}, Base = {} }

-- How webhooks work:
--   Hook.send(kind, text) enqueues a message.
--   Queue is sent one by one every 2.5 seconds (to avoid Discord rate limits).
local Hook = {
    On = false,
    Url = "",
    Guard = true,   -- mod / dev / player enters world
    Stop = true,      -- activity stopped (out of blocks, error)
    Full = true,      -- inventory full
    Bonus = true,     -- quest claimed / code redeemed
    Rejoin = true,    -- kicked / rejoined
    Factory = true,    -- factory drop / land finished / stopped
    Finder = true,
    ReportMin = 0,    -- stats report every X minutes (0 = off)
    Queue = {},
    LastFull = {},
    Status = "-",
}

do (function()
    local HttpService = game:GetService("HttpService")

    local function requester()
        return (syn and syn.request) or (http and http.request) or http_request or request
            or (fluxus and fluxus.request)
    end

    function Hook.valid(url)
        url = tostring(url or "")
        for _, host in ipairs({ "discord.com", "discordapp.com", "ptb.discord.com", "canary.discord.com" }) do
            if string.sub(url, 1, #host + 22) == "https://" .. host .. "/api/webhooks/" then return true end
        end
        return false
    end

    -- kind: "guard" | "stop" | "full" | "bonus" | "rejoin" | "factory" | "finder" | "report" | "test"
    function Hook.send(kind, text)
        -- Local tests do not send Discord notifications; user config stays intact.
        if G.__n4thLiveTest and G.__n4thLiveTest.Running then return end
        if not Hook.On or not Hook.valid(Hook.Url) then return end
        local allow = kind == "test" or kind == "report"
            or (kind == "guard" and Hook.Guard) or (kind == "stop" and Hook.Stop)
            or (kind == "full" and Hook.Full) or (kind == "bonus" and Hook.Bonus)
            or (kind == "rejoin" and Hook.Rejoin) or (kind == "factory" and Hook.Factory)
            or (kind == "finder" and Hook.Finder)
        if not allow or #Hook.Queue >= 20 then return end
        table.insert(Hook.Queue, tostring(text))
    end

    task.spawn(function()
        while alive() do
            local text = table.remove(Hook.Queue, 1)
            if not text then
                task.wait(0.5)
            else
                local req = requester()
                if not req then
                    Hook.Status = "Executor has no request function"
                else
                    local body = HttpService:JSONEncode({
                        username = "n4th",
                        content = ("**[%s]** %s"):format(LocalPlayer.Name, text),
                    })
                    local ok, res = pcall(req, {
                        Url = Hook.Url, Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" }, Body = body,
                    })
                    local code = ok and type(res) == "table" and tonumber(res.StatusCode or res.Status) or nil
                    if ok and (code == nil or code < 300) then
                        Hook.Status = "Sent " .. os.date("%H:%M:%S")
                    else
                        Hook.Status = "Send failed (" .. tostring(code or res) .. ")"
                    end
                end
                task.wait(2.5)
            end
        end
    end)
end)() end

---------------------------------------------------------------------
-- FIND GAME DATA & FUNCTIONS (getgc)
---------------------------------------------------------------------
local function getconsts(fn)
    -- Some executors expose debug APIs that only return empty tables.
    local previous
    for _, api in ipairs({ (debug and debug.getconstants) or false, getconstants or false }) do
        if type(api) == "function" and api ~= previous then
            previous = api
            local ok, values = pcall(api, fn)
            if ok and type(values) == "table" and next(values) ~= nil then return values end
        end
    end
    return {}
end

local function getUpvalues(fn)
    for _, api in ipairs({ (debug and debug.getupvalues) or false, getupvalues or false }) do
        if type(api) == "function" then
            local ok, values = pcall(api, fn)
            if ok and type(values) == "table" and next(values) ~= nil then return values end
        end
    end
    for _, api in ipairs({ (debug and debug.getupvalue) or false, getupvalue or false }) do
        if type(api) == "function" then
            local out = {}
            for i = 1, 80 do
                local ok, first, second = pcall(api, fn, i)
                if not ok then break end
                -- Executors typically return value; standard Lua debug API may also return name, value.
                local value = first
                if second ~= nil then value = second end
                if value ~= nil then out[i] = value end
            end
            if next(out) ~= nil then return out end
        end
    end
    return {}
end

-- After an update, executor require may return a different class table
-- than the active inventory instance metatable. Validate its API and slot layout.
local function isInventory(value)
    if type(value) ~= "table" or type(rawget(value, "slots")) ~= "table"
        or type(rawget(value, "capacity")) ~= "number" then return false end
    if type(value.count) ~= "function" or type(value.remove) ~= "function"
        or type(value.add) ~= "function" or type(value.used) ~= "function"
        or type(value.select) ~= "function" or type(value.room) ~= "function" then return false end
    for _, slot in pairs(rawget(value, "slots")) do
        if type(slot) ~= "table" or type(slot.id) ~= "number" or type(slot.n) ~= "number" then return false end
    end
    return true
end

-- Game place function: the only one using both "placedAt" and "flips".
-- Sends "tile" (new game, ByteNet) or "SetTile" (legacy game).
local function isSetTileFn(fn)
    if not getconsts then return false end
    local ok, consts = pcall(getconsts, fn)
    if not ok or type(consts) ~= "table" then return false end
    local hasSend, hasPlaced, hasFlips = false, false, false
    for _, c in pairs(consts) do
        if c == "tile" or c == "SetTile" then hasSend = true
        elseif c == "placedAt" then hasPlaced = true
        elseif c == "flips" then hasFlips = true end
    end
    return hasSend and hasPlaced and hasFlips
end

-- Game punch function: strings "Empty the Vending Machine first!" + "newCrack"
-- (legacy game: "HarvestProvider")
local function isPunchFn(fn)
    if not getconsts then return false end
    local ok, consts = pcall(getconsts, fn)
    if not ok or type(consts) ~= "table" then return false end
    local hasVend, hasMark = false, false
    for _, c in pairs(consts) do
        if type(c) == "string" and c:lower():find("empty", 1, true) and c:lower():find("vending", 1, true) then hasVend = true
        elseif c == "newCrack" or c == "HarvestProvider" then hasMark = true end
    end
    return hasVend and hasMark
end

-- Game function that draws the character's hand when punching / placing
function Anim.isArmFn(fn)
    if not getconsts then return false end
    local ok, consts = pcall(getconsts, fn)
    if not ok or type(consts) ~= "table" then return false end
    local a, b, c = false, false, false
    for _, k in pairs(consts) do
        if k == "forearm" then a = true
        elseif k == "heldReach" then b = true
        elseif k == "punchReach" then c = true end
    end
    return a and b and c
end

-- Find the "last action" upvalue index (table {t, x, y, facing} or nil) in hand function.
-- This upvalue is shared by game input & character rendering code, so updating it once suffices.
function Anim.bind(fn)
    local gu = (debug and debug.getupvalue) or getupvalue
    local su = (debug and debug.setupvalue) or setupvalue
    if not (gu and su) then return false end
    local vals, last = {}, 0
    for i = 1, 16 do
        local ok, v = pcall(gu, fn, i)
        if not ok then break end
        vals[i] = v
        if v ~= nil then last = i end
    end
    for i = 1, last - 1 do
        local v = vals[i]
        if v == nil or (type(v) == "table" and rawget(v, "t") ~= nil and rawget(v, "facing") ~= nil) then
            Anim.fn, Anim.idx, Anim.set = fn, i, su
            return true
        end
    end
    return false
end

local function isStateHolder(v)
    local fn = rawget(v, "state")
    if type(fn) ~= "function" then return false end
    local ok, s = pcall(fn)
    return ok and type(s) == "table" and type(s.x) == "number" and type(s.y) == "number"
        and s.facing ~= nil and s.vx ~= nil
end

-- Ensure function belongs to the game, not this script
local function isGameFn(fn)
    if fn == isSetTileFn or fn == isPunchFn then return false end
    local sources = {}
    if debug and type(debug.info) == "function" then
        local ok, src = pcall(debug.info, fn, "s")
        if ok and type(src) == "string" then sources[#sources + 1] = src end
    end
    if debug and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, fn, "S")
        if ok and type(info) == "table" then
            if type(info.source) == "string" then sources[#sources + 1] = info.source end
            if type(info.short_src) == "string" then sources[#sources + 1] = info.short_src end
        end
    end
    for _, src in ipairs(sources) do
        if src:find("GameGui", 1, true) or src:find("PlayerScripts", 1, true)
            or src:find("ReplicatedStorage", 1, true) then return true end
    end
    if isexecutorclosure then
        local ok, res = pcall(isexecutorclosure, fn)
        if ok and res then return false end
    end
    for _, src in ipairs(sources) do
        if src:find("n4th-main", 1, true) or src == "executor" or src == "[C]" or src == "=[C]" then return false end
    end
    return true
end

function Anim.isWorld(v)
    local w, h = rawget(v, "w"), rawget(v, "h")
    if type(w) ~= "number" or w <= 0 or type(h) ~= "number" or h <= 0
        or type(rawget(v, "fg")) ~= "table" or type(rawget(v, "bg")) ~= "table" then return false end
    return rawget(v, "spawn") ~= nil or (
        type(rawget(v, "name")) == "string"
        and type(rawget(v, "atTile")) == "function"
        and (type(rawget(v, "dropList")) == "function" or type(rawget(v, "enter")) == "function")
    )
end

function Anim.consider(v)
    local tv = type(v)
    if tv == "table" then
        if not Refs.MovementMenu and rawget(v, "isDown") and Session.isMovementMenu(v) then Refs.MovementMenu = v end
        if not Refs.World then
            local ok, isWorld = pcall(Anim.isWorld, v)
            if ok and isWorld then Refs.World = v end
        end
        if not Refs.Inv then
            local ok, isInv = pcall(function()
                return isInventory(v)
            end)
            if ok and isInv then Refs.Inv = v end
        end
        if not Refs.State then
            local ok, isHolder = pcall(isStateHolder, v)
            if ok and isHolder then Refs.State = rawget(v, "state") end
        end
        if not Refs.Menu then
            local ok, isMenu = pcall(function()
                return type(rawget(v, "openBackpack")) == "function" and type(rawget(v, "ui")) == "table"
            end)
            if ok and isMenu then Refs.Menu = v end
        end
        if not Refs.Gems then
            local ok, isG = pcall(function() return type(rawget(v, "addGems")) == "function" end)
            if ok and isG then Refs.Gems = v end
        end
        if not Refs.Hud then
            local ok, isH = pcall(function()
                return type(rawget(v, "punchRange")) == "function" and type(rawget(v, "handPower")) == "function"
            end)
            if ok and isH then Refs.Hud = v end
        end
        if not Refs.Others then
            -- other player data: has list(), where(), playerAt()
            local ok, isO = pcall(function()
                return type(rawget(v, "list")) == "function" and type(rawget(v, "where")) == "function"
                    and type(rawget(v, "playerAt")) == "function"
            end)
            if ok and isO then Refs.Others = v end
        end
        if ParticlesOk then
            local ok, isP = pcall(function()
                return getmetatable(v) == ParticlesModule and type(rawget(v, "live")) == "table"
                    and type(rawget(v, "free")) == "table"
            end)
            if ok and isP and not table.find(Refs.Particles, v) then table.insert(Refs.Particles, v) end
        end
    elseif tv == "function" and (not Refs.SetTile or not Refs.Punch) and isGameFn(v) then
        if not Refs.SetTile and isSetTileFn(v) then
            Refs.SetTile = v
        elseif not Refs.Punch and isPunchFn(v) then
            Refs.Punch = v
        end
    end
end

-- World and inventory are sometimes only reachable from game closures, including
-- on executors that return functions only from getgc.
function Anim.walkRefs(roots, limit)
    local queue, seen = {}, {}
    local function push(value)
        local kind = type(value)
        if #queue < limit and (kind == "function" or kind == "table") and not seen[value] then
            seen[value] = true
            queue[#queue + 1] = value
        end
    end
    for _, root in ipairs(roots) do push(root) end
    local fields = { "World", "world", "currentWorld", "activeWorld", "inventory", "inv", "controller", "state",
        "WorldMenu", "worldMenu", "menu", "input" }
    local budget = { next = os.clock() + 0.0015 }
    local index = 1
    while index <= #queue and alive() do
        local value = queue[index]
        Anim.consider(value)
        if Refs.Inv and Refs.World and Refs.Punch and Refs.SetTile and Refs.State and Refs.Menu
            and (Refs.MovementMenu or Session.MovementMenu) then break end
        if type(value) == "function" then
            if isGameFn(value) then
                for _, upvalue in pairs(getUpvalues(value)) do push(upvalue) end
            end
        elseif value ~= ItemDB and value ~= Session.ItemDBSource and value ~= InventoryModule then
            for _, key in ipairs(fields) do push(rawget(value, key)) end
            local checked = 0
            for _, member in pairs(value) do
                if type(member) == "function" then push(member) end
                checked += 1
                if checked >= 256 or #queue >= limit then break end
            end
        end
        Session.scanStep(budget, index)
        index += 1
    end
    return math.min(index, #queue)
end

local function findRefs()
    -- Reconnect already cleared old references. Keep results from active input hooks.
    Refs.ScanCount, Refs.ScanError = 0, nil
    Refs.RuntimeReadable = nil
    local filter = filtergc or filter_gc
    if not Refs.World and type(filter) == "function" then
        local ok, worlds = pcall(filter, "table", { Keys = { "fg", "bg", "w", "h" } }, false)
        if ok and type(worlds) == "table" then
            for _, world in pairs(worlds) do
                if type(world) == "table" then Anim.consider(world) end
                if Refs.World then break end
            end
        end
    end
    if Refs.World and Refs.Inv and Refs.SetTile and Refs.State and Refs.Punch
        and Refs.Menu and Refs.Gems and Refs.Hud and Refs.Others
        and (Refs.MovementMenu or Session.MovementMenu) then return true end
    local objects, reason, readable = Session.runtimeObjects()
    Refs.RuntimeReadable = readable == true
    if not objects then
        Refs.ScanError = reason
        return Refs.World ~= nil, Refs.ScanError
    end
    if not readable then
        Refs.ScanError = "getgc did not return tables or functions"
        return Refs.World ~= nil, Refs.ScanError
    end
    -- Executor getgc results may contain holes or non-sequential keys.
    -- ipairs stops at the first hole and skips valid objects.
    local roots = {}
    local budget = { next = os.clock() + 0.0015 }
    for _, v in pairs(objects) do
        if not alive() then return false end
        Refs.ScanCount += 1
        Anim.consider(v)
        if Refs.World and Refs.Inv and Refs.SetTile and Refs.State and Refs.Punch
            and Refs.Menu and Refs.Gems and Refs.Hud and Refs.Others
            and (Refs.MovementMenu or Session.MovementMenu) then break end
        if (not Refs.World or not Refs.Inv or not (Refs.MovementMenu or Session.MovementMenu))
            and type(v) == "function" and #roots < 1100 and isGameFn(v) then
            roots[#roots + 1] = v
        end
        Session.scanStep(budget, Refs.ScanCount)
    end
    if not Refs.World or not Refs.Inv or not (Refs.MovementMenu or Session.MovementMenu) then
        local actions = {}
        if Refs.Punch then actions[#actions + 1] = Refs.Punch end
        if Refs.SetTile then actions[#actions + 1] = Refs.SetTile end
        Anim.walkRefs(actions, 300)
        if not Refs.World or not Refs.Inv or not (Refs.MovementMenu or Session.MovementMenu) then
            Anim.walkRefs(roots, 2400)
        end
    end
    return Refs.World ~= nil
end

local function refsText()
    local summary = "ItemDB: " .. (Session.ItemDBSource and "OK" or "NO")
        .. " | World: " .. (Refs.World and "OK" or "NO")
        .. " | " .. "Movement" .. ": " .. (Session.MovementReady and "OK" or "NO")
        .. " | Inventory: " .. (Refs.Inv and "OK" or "NO")
        .. " | setTile: " .. (Refs.SetTile and "OK" or "fallback")
        .. " | Position: " .. (Refs.State and "OK" or "fallback")
        .. " | Punch: " .. (Refs.Punch and "OK" or "NO")
        .. " | Drop: " .. (Drops.list and "OK" or "NO")
        .. " | Trees: " .. (Refs.Trees and "OK" or "NO")
        .. " | Players: " .. (Refs.Others and "OK" or "NO")
        .. " | Anim: " .. (Anim.fn and "OK" or "NO")
        .. " | Dropdown: " .. (UI.DropErr and ("ERROR " .. tostring(UI.DropErr)) or (UI.DropOk and "OK" or "-"))
    if Session.RuntimeAccessMessage then
        return Session.RuntimeAccessMessage .. "\n" .. summary
    end
    return summary
end

---------------------------------------------------------------------
-- ITEMS & INVENTORY
---------------------------------------------------------------------
local function itemName(id)
    local it = ItemDB[id]
    return (it and it.name) or ("Item #" .. tostring(id))
end

local function invCount(id)
    if not Refs.Inv then return 0 end
    local ok, n = pcall(function() return Refs.Inv:count(id) end)
    return ok and n or 0
end

local function isPlaceable(id)
    local it = ItemDB[id]
    if not it then return false end
    if it.kind == "tool" or it.kind == "cloth" or it.kind == "clothes" or it.kind == "consumable" then
        return false
    end
    if it.lock or it.area then return false end
    return true
end

local function placeableIds()
    local ids = {}
    if Refs.Inv then
        for _, slot in ipairs(Refs.Inv.slots) do
            if slot.id and (slot.n or 0) > 0 and isPlaceable(slot.id) then
                ids[#ids + 1] = slot.id
            end
        end
    end
    table.sort(ids)
    return ids
end

local function inventoryLabels(ids)
    local out = {}
    for _, id in ipairs(ids or placeableIds()) do
        out[#out + 1] = string.format("%s [%d]", itemName(id), id)
    end
    if #out == 0 then out = { "(inventory empty / not read yet)" } end
    return out
end

-- Only refresh dropdown if item set changed (to avoid lag)
local lastInvSig = nil
local invRefreshPending = false

local lastSeedSig = nil
local lastBlockSig = nil

-- Seeds in inventory (for Farmer)
local function seedIds()
    local ids = {}
    if Refs.Inv then
        for _, slot in ipairs(Refs.Inv.slots) do
            local it = slot.id and ItemDB[slot.id]
            if it and it.kind == "seed" and (slot.n or 0) > 0 then
                ids[#ids + 1] = slot.id
            end
        end
    end
    table.sort(ids)
    return ids
end

-- After refreshing the list, re-select the active item (from config / previous selection)
local function selectSaved(dd, labels, id)
    if not dd or not id then return end
    local pending = UI.PendingDropdowns[dd]
    if pending then pending.id = id return end
    local want = "[" .. tostring(id) .. "]"
    for _, label in ipairs(labels) do
        if string.sub(label, -#want) == want then
            UI.exec(function() dd:Select(label) end)
            return
        end
    end
end

-- Refresh 1 dropdown; errors are logged (shown in General)
function UI.ddRefresh(dd, labels)
    if not dd then return end
    if not UI.tabVisible(UI.DropdownTabs[dd]) then
        UI.PendingDropdowns[dd] = { labels = labels }
        return
    end
    UI.PendingDropdowns[dd] = nil
    local ok, err = UI.exec(function() dd:Refresh(labels) end)
    if ok then
        UI.DropOk = os.clock()
    else
        UI.DropErr = ("%s (id %s/%s)"):format(tostring(err), tostring(UI.ident()), tostring(Session.Ident))
        UI.DropErrAt = os.clock()
    end
end

local function doInvRefresh(force)
    if not force and UI.Window and UI.Window.Closed then UI.InvDirty = true return end
    UI.DropErr = nil
    if Vend.refreshItems and not Vend.Running and UI.VendVisible and UI.VendVisible() then pcall(Vend.refreshItems, false) end
    local ids = placeableIds()
    local sig = table.concat(ids, ",")
    if force or sig ~= lastInvSig then
        lastInvSig = sig
        local labels = inventoryLabels(ids)
        UI.ddRefresh(UI.InvDropdown, labels)
        selectSaved(UI.InvDropdown, labels, State.SelectedId)
    end
    local sids = seedIds()
    local ssig = table.concat(sids, ",")
    if force or ssig ~= lastSeedSig then
        lastSeedSig = ssig
        local labels = {}
        for _, id in ipairs(sids) do
            labels[#labels + 1] = string.format("%s [%d]", itemName(id), id)
        end
        if #labels == 0 then labels = { "(no seeds in inventory)" } end
        UI.ddRefresh(UI.SeedDropdown, labels)
        selectSaved(UI.SeedDropdown, labels, Farmer.SeedId)
        if UI.FactorySeedDropdown then
            UI.ddRefresh(UI.FactorySeedDropdown, labels)
            selectSaved(UI.FactorySeedDropdown, labels, Factory.SeedId)
        end
    end
    -- solid block for scaffolding
    local bids = {}
    for _, id in ipairs(ids) do
        local it = ItemDB[id]
        if it and it.solid and it.kind ~= "seed" then bids[#bids + 1] = id end
    end
    local bsig = table.concat(bids, ",")
    if force or bsig ~= lastBlockSig then
        lastBlockSig = bsig
        local labels = {}
        for _, id in ipairs(bids) do
            labels[#labels + 1] = string.format("%s [%d]", itemName(id), id)
        end
        if #labels == 0 then labels = { "(no solid blocks in inventory)" } end
        UI.ddRefresh(UI.ClearBlockDropdown, labels)
        UI.ddRefresh(UI.FarmerBlockDropdown, labels)
        selectSaved(UI.ClearBlockDropdown, labels, Clear.ScaffoldId)
        selectSaved(UI.FarmerBlockDropdown, labels, Farmer.ScaffoldId)
        if UI.BuildBlockDropdown then
            UI.ddRefresh(UI.BuildBlockDropdown, labels)
            selectSaved(UI.BuildBlockDropdown, labels, Build.BlockId)
        end
    end
    -- Splice & Bag lists (created further down in the script)
    if UI.SpliceRefresh then pcall(UI.SpliceRefresh, force) end
    if UI.TrashRefresh then pcall(UI.TrashRefresh, force) end
    if UI.AutoDropRefresh then pcall(UI.AutoDropRefresh, force) end
end

local function refreshInvDropdown(force)
    if force then UI.InvForce = true end
    if not force and invRefreshPending then return end
    invRefreshPending = true
    UI.later("inv", function()
        invRefreshPending = false
        local f = UI.InvForce == true
        UI.InvForce = false
        if alive() then doInvRefresh(f) end
    end, force and 0 or 0.3)
end

-- Hidden dropdowns do not need rebuilding on every inventory change.
-- When tab is opened, read fresh data and run at most one pending list.
function UI.flushInventory()
    if not UI.Window or UI.Window.Closed then return end
    local tab = UI.Window.CurrentTab
    if UI.InvDirty or UI.LastInventoryTab ~= tab then
        UI.InvDirty, UI.LastInventoryTab = false, tab
        refreshInvDropdown(false)
    end
    if invRefreshPending then return end
    for dd, pending in pairs(UI.PendingDropdowns) do
        if UI.tabVisible(UI.DropdownTabs[dd]) then
            UI.PendingDropdowns[dd] = nil
            UI.ddRefresh(dd, pending.labels)
            selectSaved(dd, pending.labels, pending.id)
            break
        end
    end
end

local invConn
local function watchInventory()
    if invConn then pcall(function() invConn:Disconnect() end) end
    if Refs.Inv and typeof(Refs.Inv.changed) == "Instance" then
        invConn = Refs.Inv.changed.Event:Connect(function()
            if alive() then refreshInvDropdown(false) end
        end)
        table.insert(Connections, invConn)
    end
end

---------------------------------------------------------------------
-- WORLD: tiles & character position
---------------------------------------------------------------------
local function tileAt(layer, x, y)
    local w = Refs.World
    if not w or x < 0 or y < 0 or x >= w.w or y >= w.h then return nil end
    local grid = w[layer]
    local row = grid and grid[y]
    return row and (row[x] or 0) or nil
end

local function getView()
    local gg = PlayerGui:FindFirstChild("GameGui")
    local cam = gg and gg:FindFirstChild("World") and gg.World:FindFirstChild("Camera")
    local tiles = cam and cam:FindFirstChild("Tiles")
    local pv = cam and cam:FindFirstChild("PlayerView")
    if not (tiles and pv) then return nil end
    local sample = tiles:FindFirstChildWhichIsA("ImageLabel")
    if not sample or sample.AbsoluteSize.X <= 0 then return nil end
    return { tiles = tiles, pv = pv, ts = sample.AbsoluteSize.X }
end

local function getPlayerTile()
    if Refs.State then
        local ok, s = pcall(Refs.State)
        if ok and type(s) == "table" and type(s.x) == "number" then
            if s.active == false then return nil end
            return math.floor(s.x) + State.CalibX, math.floor(s.y - 0.475) + State.CalibY
        end
    end
    local v = getView()
    if not v then return nil end
    local center = v.pv.AbsolutePosition + v.pv.AbsoluteSize / 2
    local rel = center - v.tiles.AbsolutePosition
    return math.floor(rel.X / v.ts) + State.CalibX, math.floor(rel.Y / v.ts) + State.CalibY
end

-- Active Auto Farm tiles, block & mode (Factory uses its own)
local function farmOffsets()
    local o = State.Override
    return (o and o.offsets) or State.Offsets
end
local function farmBlock()
    local o = State.Override
    if o then return o.block end
    return State.SelectedId
end
local function farmMode()
    local o = State.Override
    return (o and o.mode) or State.Mode
end

local function sortedOffsets()
    local list = {}
    for key in pairs(farmOffsets()) do
        local dx, dy = string.match(key, "^(-?%d+),(-?%d+)$")
        table.insert(list, { dx = tonumber(dx), dy = tonumber(dy) })
    end
    table.sort(list, function(a, b)
        if a.dy ~= b.dy then return a.dy < b.dy end
        return a.dx < b.dx
    end)
    return list
end

---------------------------------------------------------------------
-- BASIC ACTIONS: place & punch
---------------------------------------------------------------------
local function sendSetTile(layer, x, y, id, skipLocalPrediction)
    if id ~= 0 and State.Visual and Anim.place then Anim.place(x, y, id) end
    if Refs.SetTile then
        local ok, err = pcall(Refs.SetTile, layer, x, y, id, false, false)
        if ok then return true end
        warn("[n4th] Game setTile failed, using direct remote: " .. tostring(err))
    end
    if NetOk and type(Net) == "table" and type(Net.tile) == "table" then
        -- matches game: layer 1 = fg, 2 = bg
        local ok = pcall(Net.tile.send, {
            layer = (layer == "bg") and 2 or 1, x = x, y = y, id = id, flip = false,
        })
        if not ok then return false end
    elseif SetTileRemote then
        SetTileRemote:FireServer(layer, x, y, id, false)
    else
        return false
    end
    local grid = Refs.World and Refs.World[layer]
    if not skipLocalPrediction and grid and grid[y] then grid[y][x] = id end
    return true
end

local function sendHitFx(x, y)
    if NetOk and type(Net) == "table" and Net.act then
        pcall(Net.act.send, { x = x + 0.5, y = y + 0.5 })
    end
end

local function hitsNeeded(id)
    if State.HitsOverride > 0 then return State.HitsOverride end
    local it = ItemDB[id]
    if not it then return 4 end
    local h = (it.kind == "seed") and 20 or it.hits
    return tonumber(h) or 4
end

local function canBreak(id)
    if id == 0 then return false end
    local it = ItemDB[id]
    if not it then return true end
    if it.lock or it.area or it.vend or it.display then return false end
    local h = (it.kind == "seed") and 20 or it.hits
    return h == nil or h > 0
end

-- Game ignores punches on recently placed tiles (< 0.3 seconds)
local PLACE_GUARD = 0.32

-- Place 1 tile if empty. Returns: "place" / "empty" / nil
local function tryPlace(x, y)
    local sel = farmBlock()
    if not sel then return nil end
    local fg = tileAt("fg", x, y)
    if fg == nil then return nil end
    local bg = tileAt("bg", x, y)
    local it = ItemDB[sel]
    local layer = (it and it.background) and "bg" or "fg"
    local cur = (layer == "bg") and bg or fg
    if not (cur == 0 and (layer == "bg" or fg == 0)) then return nil end
    if invCount(sel) <= 0 then return "empty" end

    sendSetTile(layer, x, y, sel)
    if Refs.Inv then pcall(function() Refs.Inv:remove(sel, 1) end) end
    local key = x .. "," .. y
    HitCount[key] = nil
    PlacedAt[key] = os.clock()
    State.Placed += 1
    State.LastAction = "Place " .. itemName(sel) .. " (" .. x .. "," .. y .. ")"
    return "place"
end

-- Is there anything breakable left at this tile? (foreground / background)
local function breakableAt(x, y)
    local fg = tileAt("fg", x, y)
    if fg == nil then return false end
    if fg ~= 0 then return canBreak(fg) end
    local bg = tileAt("bg", x, y)
    return State.BreakBackground and bg ~= nil and bg ~= 0 and canBreak(bg)
end

-- Punch once. Returns: "hit" / "broke" / nil
-- includeBg = also break background
local function tryBreak(x, y, includeBg, onlyId, allowHit)
    if includeBg == nil then includeBg = State.BreakBackground end
    local key = x .. "," .. y
    local fg = tileAt("fg", x, y)
    if fg == nil then return nil end
    local bg = tileAt("bg", x, y)
    local layer, id
    if fg ~= 0 then
        layer, id = "fg", fg
    elseif includeBg and bg ~= 0 then
        layer, id = "bg", bg
    end
    if not layer or not canBreak(id) then return nil end
    if onlyId and (layer ~= "fg" or id ~= onlyId) then return nil end

    -- wait briefly if tile was just placed
    local t = PlacedAt[key]
    if t then
        local age = os.clock() - t
        if age < PLACE_GUARD then task.wait(PLACE_GUARD - age) end
        PlacedAt[key] = nil
    end

    if allowHit and not allowHit(x, y, id, layer) then return nil end
    if onlyId and (not Clear.Running or Clear.TargetId ~= onlyId or not Refs.Punch
        or not Refs.World or Refs.World.fg ~= Clear.TargetGrid or Refs.World.name ~= Clear.TargetWorld
        or tileAt("fg", x, y) ~= onlyId) then return nil end
    if onlyId then
        local ray = rawget(Refs.World, "raymanOn")
        if type(ray) == "function" then
            local ok, on = pcall(ray)
            if not ok or on then return nil end
        end
    end
    if Refs.Punch then
        local ok, err = pcall(Refs.Punch, x, y, State.MutePunch or nil, nil)
        if not ok then
            State.LastAction = "Punch error: " .. tostring(err)
            return nil
        end
        if State.Visual then Anim.swing(x, y, "punch") end
        if tileAt(layer, x, y) ~= id then
            Drops.brokeAt[key] = os.clock()
            State.Broken += 1
            State.LastAction = "Break " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            return "broke"
        end
        State.LastAction = "Punch " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
        return "hit"
    end

    -- Fallback: track hits manually
    local hc = HitCount[key]
    if not hc or hc.id ~= id or hc.layer ~= layer then
        hc = { id = id, layer = layer, n = 0 }
        HitCount[key] = hc
    end
    hc.n += 1
    sendHitFx(x, y)
    if State.Visual then Anim.swing(x, y, "punch") end
    local need = hitsNeeded(id)
    if hc.n >= need then
        sendSetTile(layer, x, y, 0)
        HitCount[key] = nil
        Drops.brokeAt[key] = os.clock()
        State.Broken += 1
        State.LastAction = "Break " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
        return "broke"
    end
    State.LastAction = "Punch " .. itemName(id) .. " " .. hc.n .. "/" .. need
    return "hit"
end

---------------------------------------------------------------------
-- AUTO COLLECT
---------------------------------------------------------------------
-- Game behavior: World.takeDrop(uid, amount) -> server confirms amount -> added to inventory.
-- Game normally only collects drops touched by the body; this picks them up directly.
local TakeDropRemote = WorldRemotes and WorldRemotes:FindFirstChild("TakeDrop") -- legacy game only

-- Game hand function is called from render functions connected to RenderStepped:
-- checking their upvalues is enough (much lighter than scanning getgc).
function Anim.findFast()
    if not getconnections or Anim.fn then return Anim.fn ~= nil end
    for _, name in ipairs({ "RenderStepped", "Heartbeat", "PreRender", "Stepped" }) do
        local okS, sig = pcall(function() return RunService[name] end)
        if okS and sig then
            local ok, conns = pcall(getconnections, sig)
            if ok and type(conns) == "table" then
                for _, c in pairs(conns) do
                    local okf, fn = pcall(Session.connectionFunction, c)
                    if okf and type(fn) == "function" then
                        for _, u in pairs(getUpvalues(fn)) do
                            if type(u) == "function" and Anim.isArmFn(u) then
                                Refs.Arm = u
                                return Anim.bind(u)
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- Prioritize closures from active connections so stale worlds in heap are not chosen.
function Anim.quickRefs()
    if type(getconnections) ~= "function" then return false end
    local roots = {}
    local function readSignal(signal)
        local ok, connections = pcall(getconnections, signal)
        if ok and type(connections) == "table" then
            for _, connection in pairs(connections) do
                local read, fn = pcall(Session.connectionFunction, connection)
                if read and type(fn) == "function" and isGameFn(fn) then roots[#roots + 1] = fn end
            end
        end
    end
    for _, entry in ipairs({
        { RunService, { "RenderStepped", "Heartbeat", "PreRender", "Stepped" } },
        { UserInputService, { "InputBegan", "InputEnded", "TouchTap" } },
    }) do
        for _, name in ipairs(entry[2]) do
            local okS, sig = pcall(function() return entry[1][name] end)
            if okS and sig then readSignal(sig) end
        end
    end
    Refs.ConnectionCount = Anim.walkRefs(roots, 900)
    if not Refs.World or not (Refs.MovementMenu or Session.MovementMenu) then
        table.clear(roots)
        local folders = { ReplicatedStorage:FindFirstChild("WorldRemotes") or false, ReplicatedStorage }
        for _, folder in ipairs(folders) do
            if folder then
                for _, remote in ipairs(folder:GetChildren()) do
                    if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
                        readSignal(remote.OnClientEvent)
                    end
                end
            end
        end
        Refs.ConnectionCount += Anim.walkRefs(roots, 900)
    end
    return Refs.Inv ~= nil
end

-- Check whether this table is the game's drop list
local function isDropList(t)
    if type(t) ~= "table" or t == Refs.World then return false end
    local first = rawget(t, 1)
    if first == nil then return next(t) == nil end
    return type(first) == "table" and rawget(first, "uid") ~= nil and rawget(first, "frame") ~= nil
end

-- deep = true: allow getgc (heavy, may lag / crash on mobile) -> only from "Connect to game" button
local function findDropRefs(deep)
    -- 0) game function World.dropList(): shared drop list for all worlds (lightest)
    local w0 = Refs.World
    local dl = w0 and rawget(w0, "dropList")
    if type(dl) == "function" then
        local okl, l = pcall(dl)
        if okl and isDropList(l) then
            if Drops.list ~= l then Drops.update = nil end
            Drops.list = l
            -- v5.9.0: update function (reduce / remove drop) must also be found. Previously returned
            -- early here, leaving Drops.update nil -> Remote mode drops weren't removed visually.
            if not Drops.update then Drops.findUpdate() end
            return true
        end
    end
    if Drops.list and not deep then return true end -- legacy path still active
    Drops.list, Drops.update = nil, nil
    -- 1) from World.dropTaken (contains: drop list + update function)
    local wd = Refs.World and rawget(Refs.World, "dropTaken")
    if type(wd) == "function" then
        for _, u in pairs(getUpvalues(wd)) do
            if not Drops.list and isDropList(u) then
                Drops.list = u
            elseif not Drops.update and type(u) == "function" then
                Drops.update = u
            end
        end
    end
    -- 2) from game's DropTaken handler
    local ev = WorldRemotes and WorldRemotes:FindFirstChild("DropTaken")
    if not Drops.list and ev and getconnections then
        local ok, conns = pcall(getconnections, ev.OnClientEvent)
        if ok and type(conns) == "table" then
            for _, c in pairs(conns) do
                local okf, fn = pcall(Session.connectionFunction, c)
                if okf and type(fn) == "function" then
                    for _, u in pairs(getUpvalues(fn)) do
                        if not Drops.list and isDropList(u) then
                            Drops.list = u
                        elseif not Drops.update and type(u) == "function" then
                            Drops.update = u
                        end
                    end
                end
                if Drops.list then break end
            end
        end
    end
    -- 3) fallback: search via getgc (only when requested: heavy)
    if not Drops.list and deep and type(getgc) == "function" then
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then ok, objects = pcall(getgc) end
        for _, v in pairs(ok and type(objects) == "table" and objects or {}) do
            if type(v) == "table" then
                local e = rawget(v, 1)
                if type(e) == "table" and rawget(e, "uid") ~= nil and rawget(e, "frame") ~= nil
                    and rawget(e, "born") ~= nil then
                    Drops.list = v
                    break
                end
            end
        end
    end
    return Drops.list ~= nil
end

-- Find the game function that subtracts / removes drops (used by World.dropTaken).
-- Signature: upvalue of World.dropTaken that itself holds the same drop list.
function Drops.findUpdate()
    local w, list = Refs.World, Drops.list
    local wd = w and rawget(w, "dropTaken")
    if type(wd) ~= "function" or not list then return false end
    for _, u in pairs(getUpvalues(wd)) do
        if type(u) == "function" then
            for _, uu in pairs(getUpvalues(u)) do
                if rawequal(uu, list) then
                    Drops.update = u
                    return true
                end
            end
        end
    end
    return false
end

-- Apply collected drop result visually, matching game behavior:
--   remaining > 0 -> decrement drop stack; remaining 0 -> remove from list + destroy frame.
-- Without this, the game's render loop shows the drop again (flown resets when body isn't touching).
function Drops.applyTaken(d, left)
    local list = Drops.list
    if not list or not table.find(list, d) then return end
    if not Drops.update then Drops.findUpdate() end
    if Drops.update then
        local ok = pcall(Drops.update, d, left)
        if ok then
            if left > 0 then
                d.flown = nil
                if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = not d.culled end) end
            end
            return
        end
    end
    -- manual fallback (game function not found)
    d.n = left
    if left > 0 then
        pcall(function()
            if d.setGem then d.setGem(left) elseif d.count then d.count:set(left > 1 and tostring(left) or "") end
        end)
        d.flown = nil
        if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = not d.culled end) end
    else
        local i = table.find(list, d)
        if i then table.remove(list, i) end
        if typeof(d.frame) == "Instance" then pcall(function() d.frame:Destroy() end) end
    end
end

function AutoDrop.isProtected(d)
    local world = Refs.World
    if not world then return false end
    local key = d.uid or d
    for _, zone in ipairs(AutoDrop.Zones) do
        if zone.world == world.name and zone.grid == world.fg and zone.id == d.id and zone.piles[key] then
            return true
        end
    end
    return false
end

function Drops.dirtRoom(id)
    local dirt = Build.DirtRun
    if dirt and (id == dirt.block or id == dirt.seed) then return math.max(0, 200 - invCount(id)) end
end

local function takeDrop(d, lastDirtBlock)
    if AutoDrop.Busy or AutoDrop.isProtected(d) then return false end
    local worldTake = Refs.World and rawget(Refs.World, "takeDrop")
    if type(worldTake) ~= "function" and not TakeDropRemote then return false end
    if d.taking or d.pending or d.display or (d.n or 0) <= 0 then return false end
    -- drops you threw yourself cannot be picked up again yet (game rule), except gems
    if d.armed == false and d.id ~= 112 then return false end
    local now = os.clock()
    if DropFailUntil[d.uid] and now < DropFailUntil[d.uid] then return false end

    local roomForDirt = Drops.dirtRoom(d.id)
    if roomForDirt == 0 or (lastDirtBlock and roomForDirt ~= 1) then return false end
    local amount = roomForDirt and math.min(d.n, roomForDirt) or d.n
    if d.id ~= 112 and Refs.Inv and not (lastDirtBlock and roomForDirt == 1) then -- 112 = gems
        local okr, room = pcall(function() return Refs.Inv:room(d.id) end)
        if okr and type(room) == "number" then amount = math.min(amount, room) end
    end
    if amount <= 0 then -- inventory full: retry in 1 second
        DropFailUntil[d.uid] = now + 1
        local last = Hook.LastFull[d.id]
        if not last or now - last > 120 then
            Hook.LastFull[d.id] = now
            Hook.send("full", "Inventory full: " .. itemName(d.id) .. " cannot hold any more")
        end
        return false
    end

    d.taking = true -- prevent double collection
    -- hide immediately on screen while awaiting server response.
    -- Avoid d.flown: render loop resets flown and redraws the drop
    -- every frame if body isn't touching it (Remote mode = remote pickup).
    if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = false end) end
    local ok, taken
    if type(worldTake) == "function" then
        ok, taken = pcall(worldTake, d.uid, amount) -- new game path
    else
        ok, taken = pcall(TakeDropRemote.InvokeServer, TakeDropRemote, d.uid, amount)
    end
    d.taking = false

    if not (ok and type(taken) == "number" and taken > 0) then
        State.CollectFail += 1
        d.refused = os.clock() -- mark as rejected, matching game
        d.failN = (d.failN or 0) + 1
        DropFailUntil[d.uid] = os.clock() + math.min(8, d.failN) -- 1, 2, 3.. seconds (repeatedly rejected drops back off)
        d.flown = nil
        if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = not d.culled end) end
        return false
    end
    DropFailUntil[d.uid] = nil

    if d.id == 112 then
        if Refs.Gems then pcall(Refs.Gems.addGems, taken) end
    elseif Refs.Inv then
        pcall(function() Refs.Inv:add(d.id, taken) end)
    end
    Drops.applyTaken(d, math.max(0, (d.n or 0) - taken)) -- subtract / remove drop matching game
    State.Collected += taken
    Stats.Items[d.id] = (Stats.Items[d.id] or 0) + taken
    State.LastAction = "Collect " .. itemName(d.id) .. " x" .. taken
    return true
end

local function inTile(t, x, y)
    return x >= t.x - 0.15 and x < t.x + 1.15 and y >= t.y - 0.15 and y < t.y + 1.15
end

-- ---------- Fast collector ----------
-- Check drops in a single worker with a small time budget. Pickups still run
-- in parallel, without spawning thousands of tasks in one frame on huge piles.
--   Auto Farm  : drops on tiles selected in Grid
--   Clear / Farmer : drops around character
local OffsetParse = {}
local nextDropScan = 0

local function canTry(d, now)
    if type(d) ~= "table" or d.taking or (d.n or 0) <= 0 or type(d.x) ~= "number" then return false end
    if d.armed == false and d.id ~= 112 then return false end
    if AutoDrop.isProtected(d) then return false end
    if Drops.dirtRoom(d.id) == 0 then return false end
    local fail = DropFailUntil[d.uid]
    return not (fail and now < fail)
end

-- Drops are NOT picked up remotely by script: game collects them automatically on body
-- touch (game physics, like manual play). This only tracks drop list & counts
-- drops picked up near the body (for status).
-- Remote mode (legacy): drops on grid tiles / around character are collected via game take-drop function
function Drops.remoteTick(list, s)
    if Clear.Running and Clear.TargetId and not State.WorldBreakCollect then return end
    local offs = farmOffsets()
    local farmArea = (State.AutoCollect or State.Override ~= nil) and next(offs) ~= nil and not Factory.Harvesting
    local nearArea = (Clear.Running and (Clear.TargetId and State.WorldBreakCollect or not Clear.TargetId and Clear.Collect)) or (Farmer.Running and Farmer.Collect)
        or Factory.Running or Build.Running or Splice.Roaming
    if not farmArea and not nearArea then return end
    local cx, cy = s.x, s.y - 0.475
    local ptx, pty = getPlayerTile()
    local now = os.clock()
    local R = (State.CollectRadius or 3) + 0.2
    local world, budget, targets, scheduled = Refs.World, { next = os.clock() + 0.0015 }, {}, 0
    if farmArea and ptx then
        for key in pairs(offs) do
            local o = OffsetParse[key]
            if not o then
                local dx, dy = string.match(key, "^(-?%d+),(-?%d+)$")
                o = { tonumber(dx), tonumber(dy) }
                OffsetParse[key] = o
            end
            if o[1] and o[2] then targets[#targets + 1] = { x = ptx + o[1], y = pty + o[2] } end
        end
    end
    local z = Factory.Zone -- ignore factory drop spot so dropped items aren't re-collected
    if z and z.world ~= (Refs.World and rawget(Refs.World, "name")) then z = nil end
    for i = #list, 1, -1 do
        local d = list[i]
        if canTry(d, now) and not (z and math.abs(d.x - z.x) <= 2.5 and math.abs(d.y - z.y) <= 2.5) then
            local hit = nearArea and math.abs(d.x - cx) <= R and math.abs(d.y - cy) <= R
            if not hit and farmArea and ptx then
                for _, tile in ipairs(targets) do
                    if inTile(tile, d.x, d.y) then
                        hit = true
                        break
                    end
                end
            end
            if hit then
                task.spawn(takeDrop, d)
                scheduled += 1
                if scheduled >= 8 then break end
            end
        end
        Session.scanStep(budget, #list - i + 1)
        if not alive() or Drops.list ~= list or Refs.World ~= world or AutoDrop.Busy or WorldFinder.Busy
            or (Clear.Running and Clear.TargetId and not State.WorldBreakCollect) then return end
    end
end

local function collectTick()
    if AutoDrop.Busy or WorldFinder.Busy then return end
    if Clear.Running and Clear.TargetId and not State.WorldBreakCollect then
        Drops.seen = nil
        return
    end
    local busy = State.AutoCollect or State.Override ~= nil or (Clear.Running and Clear.Collect)
        or (Clear.Running and Clear.TargetId and State.WorldBreakCollect)
        or (Farmer.Running and Farmer.Collect) or Factory.Running or Build.Running or Splice.Roaming or Vend.Running
    if not busy then return end
    local tnow = os.clock()
    if tnow < (Drops.nextTick or 0) then return end -- 5-10x per second is enough (saves FPS)
    Drops.nextTick = tnow + ((State.CollectMode == "Remote") and 0.1 or 0.2)
    local list = Drops.list
    if not list then
        local now = os.clock()
        if now >= nextDropScan then -- refresh drop list at most every 5 seconds
            nextDropScan = now + 5
            findDropRefs()
        end
        return
    end
    local ok, s = false, nil
    if Refs.State then ok, s = pcall(Refs.State) end
    if not (ok and type(s) == "table" and type(s.x) == "number") then return end
    if State.CollectMode == "Remote" then
        Drops.remoteTick(list, s) -- picked count is tracked by takeDrop
        return
    end
    local cx, cy = s.x, s.y - 0.475
    local seen = {}
    local previous = Drops.seen
    local membership = previous and next(previous) and {} or nil
    local world, budget = Refs.World, { next = os.clock() + 0.0015 }
    for index, d in ipairs(list) do
        if membership then membership[d] = true end
        if type(d) == "table" and type(d.x) == "number" and math.abs(d.x - cx) <= 1.5 and math.abs(d.y - cy) <= 1.5 then
            seen[d] = d.n or 0
        end
        Session.scanStep(budget, index)
        if not alive() or Drops.list ~= list or Refs.World ~= world then Drops.seen = nil return end
    end
    for d, n in pairs(previous or {}) do
        if seen[d] == nil and not membership[d] and d.id and n > 0 then -- disappeared near body = collected
            State.Collected += n
            Stats.Items[d.id] = (Stats.Items[d.id] or 0) + n
        end
    end
    Drops.seen = seen
end

task.spawn(function()
    while alive() do
        local ok, err = pcall(collectTick)
        if not ok and os.clock() - (Drops.LastErrorAt or -10) >= 10 then
            Drops.LastErrorAt = os.clock()
            warn("[n4th] Collect: " .. tostring(err))
        end
        task.wait(0.05)
    end
end)

-- Wait briefly for drops on this tile to be collected (avoid covering with new block)
local function waitTileDrops(t, maxSec)
    local list = Drops.list
    if not list then return end
    local t0 = os.clock()
    while os.clock() - t0 < maxSec and alive() do
        local now, busy = os.clock(), false
        for _, d in ipairs(list) do
            if type(d) == "table" and type(d.x) == "number" and (d.n or 0) > 0 and inTile(t, d.x, d.y)
                and (d.taking or canTry(d, now)) then
                busy = true
                break
            end
        end
        if not busy then return end
        task.wait()
    end
end

-- Wait until drops touching the body finish being picked up by game physics (touch, no remote)
local function waitNearDrops(maxSec)
    local list = Drops.list
    if not list then return end
    task.wait(0.15) -- new drops appear slightly delayed
    local t0 = os.clock()
    while os.clock() - t0 < maxSec and alive() do
        local ok, s = false, nil
        if Refs.State then ok, s = pcall(Refs.State) end
        if not (ok and type(s) == "table" and type(s.x) == "number") then return end
        local cx, cy = s.x, s.y - 0.475
        local busy = false
        for _, d in ipairs(list) do
            -- matches game rule: < 0.6 tile horizontally & body height (feet s.y, head s.y - 0.95)
            if type(d) == "table" and type(d.x) == "number" and (d.n or 0) > 0 and d.armed ~= false
                and math.abs(d.x - s.x) < 0.6 and d.y + 0.3 > s.y - 0.95 and d.y - 0.3 < s.y then
                local room = true
                if d.id ~= 112 and Refs.Inv then -- inventory full: won't be picked up
                    local okr, r = pcall(function() return Refs.Inv:room(d.id) end)
                    if okr and type(r) == "number" and r <= 0 then room = false end
                end
                if room then
                    busy = true
                    break
                end
            end
        end
        if not busy then return end
        task.wait()
    end
end

---------------------------------------------------------------------
-- STATUS
---------------------------------------------------------------------
local function offsetsText()
    local list = {}
    for _, o in ipairs(sortedOffsets()) do
        table.insert(list, "(" .. o.dx .. "," .. o.dy .. ")")
    end
    return #list > 0 and table.concat(list, " ") or "-"
end

local lastStatusText = nil

local function updateStatus()
    if not UI.Status then return end
    local px, py = getPlayerTile()
    local sel = State.SelectedId
    local txt = "Status   : " .. (State.Running and "RUNNING" or "STOPPED")
        .. "\nBlock    : " .. (sel and (itemName(sel) .. " x" .. invCount(sel)) or "-")
        .. "\nCharacter: " .. (px and ("(" .. px .. "," .. py .. ")") or "not in world")
        .. "\nTile     : " .. offsetsText()
        .. "\nPlace/Break/Collect : " .. State.Placed .. " / " .. State.Broken .. " / " .. State.Collected
        .. (State.CollectFail > 0 and (" (rejected " .. State.CollectFail .. ")") or "")
        .. (State.Dropped > 0 and ("\nSeed drop: dropped " .. State.Dropped) or "")
        .. "\nAction   : " .. State.LastAction
    if txt == lastStatusText then return end
    lastStatusText = txt
    task.defer(function()
        pcall(function() UI.Status:SetDesc(txt) end)
    end)
end

---------------------------------------------------------------------
-- LITE MODE (disable particles + sound)
---------------------------------------------------------------------
local DummyLabel = setmetatable({}, { __index = function() return 0 end, __newindex = function() end })
local DummyParticle = setmetatable({ l = DummyLabel, k = {} }, { __index = function() return 0 end, __newindex = function() end })
local NullSound
NullSound = setmetatable({}, {
    __index = function() return NullSound end,
    __newindex = function() end,
    __call = function() return NullSound end,
})
local LiteSaved = {}

local function liteOverride(tbl, key, repl)
    if type(tbl) == "table" and type(rawget(tbl, key)) == "function" then
        table.insert(LiteSaved, { tbl, key, rawget(tbl, key) })
        tbl[key] = repl
    end
end

local function setLite(on)
    State.LiteMode = on
    if on then
        if #LiteSaved == 0 then
            if ParticlesOk then liteOverride(ParticlesModule, "spawn", function() return DummyParticle end) end
            if SfxOk then
                liteOverride(SfxModule, "play", function() return NullSound end)
                liteOverride(SfxModule, "playAt", function() return NullSound end)
            end
        end
        for _, p in ipairs(Refs.Particles) do
            pcall(function()
                for _, e in ipairs(p.live) do
                    if typeof(e.l) == "Instance" then e.l.Visible = false end
                end
            end)
        end
    else
        for _, s in ipairs(LiteSaved) do
            pcall(function() s[1][s[2]] = s[3] end)
        end
        table.clear(LiteSaved)
    end
end

---------------------------------------------------------------------
-- MISC: walkspeed, infinite jump, fly + noclip
---------------------------------------------------------------------
-- Infinite jump: tricks game into thinking an Antigravity Generator is active, allowing mid-air jumps
local OrigJammerOn = nil
local function infJumpWrapper(id, ...)
    -- disabled while Clear / Farmer runs (jumping must behave normally)
    if Misc.InfJump and id == 4992 and not AutoInput.active then
        return true
    end
    if OrigJammerOn then return OrigJammerOn(id, ...) end
    return false
end

local function hookJammer()
    local w = Refs.World
    if not w then return end
    local cur = rawget(w, "jammerOn")
    if cur == infJumpWrapper or type(cur) ~= "function" then return end
    OrigJammerOn = cur
    w.jammerOn = infJumpWrapper
end

local function unhookJammer()
    local w = Refs.World
    if w and rawget(w, "jammerOn") == infJumpWrapper and OrigJammerOn then
        w.jammerOn = OrigJammerOn
    end
end

local function setInfJump(on)
    Misc.InfJump = on
    if on then hookJammer() else unhookJammer() end
end

local function setGhost(on, checkCollision)
    if on then pcall(Session.bindMovement, true) end
    if checkCollision and on ~= Misc.Ghost then
        local checked, clear, reason = pcall(Session.checkGhostPosition)
        if not checked or clear == nil then
            pcall(Anim.quickRefs)
            pcall(Session.bindMovement, true)
            checked, clear, reason = pcall(Session.checkGhostPosition)
        end
        local message
        if not checked or clear == nil then
            message = "Position or block data is unavailable. Connect to the game and try again."
        elseif not on and not clear then
            message = reason
        end
        if message then
            Misc.UpHeld, Misc.DownHeld = false, false
            if UI.GhostToggle then pcall(function() UI.GhostToggle:Set(Misc.Ghost, false) end) end
            notify("Fly + Noclip", message, 5)
            return
        end
    end
    Misc.Ghost = on
    if Session.GhostNoclip then
        Session.GhostNoclip.active = false
        Session.GhostNoclip.hover = false
        Session.GhostNoclip.x, Session.GhostNoclip.y = nil, nil
        Session.GhostNoclip.preX, Session.GhostNoclip.preY, Session.GhostNoclip.preT = nil, nil, nil
    end
    if not on then
        Misc.UpHeld, Misc.DownHeld = false, false
    end
    if Refs.World then Refs.World.ghost = on == true end
    if UI.FlyPad then UI.FlyPad.Enabled = on end
end

local function setSpeed(pct)
    Misc.Speed = math.clamp(math.floor(tonumber(pct) or 100), 50, 500)
    if Misc.Speed == 100 and Refs.World then Refs.World.speedScale = 1 end
end

Session.GhostNoclip = {
    active = false,
    hover = false,
    x = nil,
    y = nil,
    preX = nil,
    preY = nil,
    preT = nil,
    inputs = {},
    inputAt = {},
    lastRefresh = 0,
}

-- Game movement keys are read from WorldMenu.isDown. Hooked so
-- Fly UP/DN buttons work, and Clear / Farmer can press virtual keys.
local OrigIsDown = nil
local function isDownWrapper(saved, key, ...)
    if AutoInput.active then
        if key == "keyLeft" then return AutoInput.left end
        if key == "keyRight" then return AutoInput.right end
        if key == "keyJump" then return AutoInput.jump end
        if key == "keyDown" then return AutoInput.down end
    end
    if Misc.Ghost then
        if key == "keyDown" and Misc.DownHeld then return true end
        if key == "keyJump" and Misc.UpHeld then return true end
    end
    local down = OrigIsDown(saved, key, ...)
    if key == "keyLeft" or key == "keyRight" or key == "keyJump" or key == "keyDown" then
        local gn = Session.GhostNoclip
        gn.inputs[key] = down == true
        gn.inputAt[key] = os.clock()
    end
    return down
end

function Session.tryMovementMenu(menu)
    if type(menu) ~= "table" then return false end
    local original = rawget(menu, "isDown")
    if original == isDownWrapper then return Session.MovementMenu == menu and OrigIsDown ~= nil end
    if type(original) ~= "function" then return false end
    local ok, reason = pcall(rawset, menu, "isDown", isDownWrapper)
    if not ok then
        warn("[n4th] Could not hook movement controls: " .. tostring(reason))
        return false
    end
    local previous = Session.MovementMenu
    if previous and previous ~= menu and rawget(previous, "isDown") == isDownWrapper then
        pcall(rawset, previous, "isDown", OrigIsDown)
    end
    Session.MovementMenu, OrigIsDown = menu, original
    Session.MovementReady = true
    MenuModule, MenuModOk = menu, true
    return true
end

function Session.bindMovement(retry, deep)
    if Session.tryMovementMenu(Refs.MovementMenu) then return true end
    if Session.tryMovementMenu(Session.MovementMenu or MenuModule) then return true end
    if not retry then return false end
    pcall(Anim.quickRefs)
    if Session.tryMovementMenu(Refs.MovementMenu) then return true end
    if Session.tryMovementMenu(Session.resolveMovement()) then return true end
    if deep then
        pcall(findRefs)
        if Session.tryMovementMenu(Refs.MovementMenu) then return true end
    end
    return false
end
Session.bindMovement()

function Session.scheduleMovementRetry()
    if OrigIsDown or Session.MovementRetry then return end
    Session.MovementRetry = true
    task.spawn(function()
        for _, delay in ipairs({ 1, 2, 4 }) do
            task.wait(delay)
            if not alive() or OrigIsDown then break end
            if not Session.Connecting then Session.bindMovement(true) end
            if OrigIsDown then
                UI.later("movement-ready", function()
                    pcall(function() UI.RefInfo:SetDesc(refsText()) end)
                end)
                break
            end
        end
        Session.MovementRetry = false
    end)
end

-- Apply walkspeed & fly before/after game step + fallback noclip assist when solid collision blocks ghost
do (function()
    local gn = Session.GhostNoclip

    local function resetNoclip()
        gn.active = false
        gn.hover = false
        gn.x, gn.y = nil, nil
        gn.preX, gn.preY, gn.preT = nil, nil, nil
    end

    local function applyWorldProps(w)
        if Misc.Speed ~= 100 then w.speedScale = Misc.Speed / 100 end
        if Misc.Ghost and w.ghost ~= true then w.ghost = true end
    end

    local function readState()
        if not Refs.State then return nil end
        local ok, s = pcall(Refs.State)
        if ok and type(s) == "table" and type(s.x) == "number" and type(s.y) == "number"
            and s.active ~= false and not s.dead then
            return s
        end
        return nil
    end

    local function keyHeld(key, kc1, kc2, kc3)
        if key == "keyJump" and Misc.UpHeld then return true end
        if key == "keyDown" and Misc.DownHeld then return true end
        local now = os.clock()
        if gn.inputs[key] and (now - (gn.inputAt[key] or 0)) <= 0.15 then return true end
        if OrigIsDown and Session.MovementMenu then
            local ok, res = pcall(OrigIsDown, Session.MovementMenu, key)
            if ok and res == true then return true end
        end
        if not UserInputService:GetFocusedTextBox() then
            if kc1 and UserInputService:IsKeyDown(kc1) then return true end
            if kc2 and UserInputService:IsKeyDown(kc2) then return true end
            if kc3 and UserInputService:IsKeyDown(kc3) then return true end
        end
        return false
    end

    local function heldAxes()
        local left = keyHeld("keyLeft", Enum.KeyCode.A, Enum.KeyCode.Left)
        local right = keyHeld("keyRight", Enum.KeyCode.D, Enum.KeyCode.Right)
        local up = keyHeld("keyJump", Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.Space)
        local down = keyHeld("keyDown", Enum.KeyCode.S, Enum.KeyCode.Down)
        return (right and 1 or 0) - (left and 1 or 0), (down and 1 or 0) - (up and 1 or 0)
    end

    local function ensureLiveRefs()
        local now = os.clock()
        if now - gn.lastRefresh < 2 then return end
        local w = Refs.World
        local staleWorld = (not w) or type(rawget(w, "fg")) ~= "table" or type(rawget(w, "w")) ~= "number"
        if staleWorld or not Refs.State then
            gn.lastRefresh = now
            if staleWorld then Refs.World = nil end
            pcall(Anim.quickRefs)
            pcall(Session.bindMovement, true)
        end
    end

    pcall(function()
        RunService:BindToRenderStep("n4th_MiscPreRender", Enum.RenderPriority.First.Value - 10, function()
            if not alive() then return end
            local w = Refs.World
            if w then applyWorldProps(w) end
            if not Misc.Ghost or AutoInput.active then return end
            local s = readState()
            if not s then return end
            if (gn.active or gn.hover) and gn.x and gn.y then
                s.x = gn.x
                s.y = gn.y
                s.vx = 0
                s.vy = 0
                s.grounded = false
            end
            gn.preX, gn.preY, gn.preT = s.x, s.y, os.clock()
        end)
    end)

    table.insert(Connections, RunService.Stepped:Connect(function()
        if not alive() then return end
        local w = Refs.World
        if w then applyWorldProps(w) end
    end))

    table.insert(Connections, RunService.Heartbeat:Connect(function()
        if not alive() then return end
        if Misc.Ghost or Misc.Speed ~= 100 then ensureLiveRefs() end
        local w = Refs.World
        if not w then return end
        applyWorldProps(w)
        if not Misc.Ghost or AutoInput.active then
            resetNoclip()
            return
        end
        local s = readState()
        if not s or type(w.w) ~= "number" or type(w.h) ~= "number" then return end
        local hx, hy = heldAxes()
        local now = os.clock()
        local dt = math.clamp(now - (gn.preT or now), 1 / 240, 0.08)
        local preX = gn.preX or s.x
        local preY = gn.preY or s.y
        local speed = 7.0 * (Misc.Speed / 100)
        local minMove = speed * dt * 0.35
        local overlap = Session.boxOverlapsSolid

        local curX, curY = s.x, s.y
        local overlapsNow = overlap and overlap(curX, curY) == true

        if hx ~= 0 then
            local movedX = (curX - preX) * hx
            local aheadX = overlap and overlap(preX + hx * 0.2, preY) == true
            if movedX < minMove and (overlapsNow or aheadX or gn.active) then
                gn.active = true
                gn.x = math.clamp((gn.x or preX) + hx * speed * dt, 0.35, w.w - 0.35)
                s.x = gn.x
                s.vx = 0
            else
                gn.x = curX
            end
        elseif gn.active then
            s.x = gn.x or preX
            s.vx = 0
        else
            gn.x = curX
        end

        local evalX = gn.x or curX
        if hy ~= 0 then
            local movedY = (curY - preY) * hy
            local aheadY = overlap and overlap(evalX, preY + hy * 0.2) == true
            local stuckY = (hy > 0 and s.grounded) or (hy < 0 and math.abs(s.vy or 0) < 0.05)
            if movedY < minMove and (overlapsNow or aheadY or stuckY or gn.active) then
                gn.active = true
                gn.hover = true
                gn.y = math.clamp((gn.y or preY) + hy * speed * dt, 0.96, w.h - 0.05)
                s.y = gn.y
                s.vy = 0
                s.grounded = false
            else
                gn.y = curY
                gn.hover = false
            end
        elseif gn.active then
            s.y = gn.y or preY
            s.vy = 0
            s.grounded = false
        elseif gn.hover or ((curY - preY) > 0.015 and not s.grounded) then
            gn.hover = true
            gn.y = gn.y or preY
            s.y = gn.y
            s.vy = 0
            s.grounded = false
        else
            gn.y = curY
        end

        if gn.active and hx == 0 and hy == 0 then
            local inside = overlap and overlap(gn.x or s.x, gn.y or s.y) == true
            if not inside then
                gn.active = false
                if not gn.hover then resetNoclip() end
            end
        end
    end))
end)() end

---------------------------------------------------------------------
-- FARM LOOP: place all first, then break one by one
---------------------------------------------------------------------
local stopFarm

local function waitMs(ms)
    task.wait(math.max(ms or 0, 10) / 1000)
    return State.Running and alive()
end

local function validate()
    local doPlace = farmMode() ~= "Break only"
    if not Refs.World then return "World data not found. Press 'Connect to game'" end
    if not Session.bindMovement(true) then return "Game movement controls not found. Press 'Connect to game'" end
    if next(farmOffsets()) == nil then return "Select tiles in the Tile Grid first" end
    if not getPlayerTile() then return "You are not in a world yet" end
    if doPlace and not farmBlock() then return "Select a block from inventory" end
    return nil
end

-- Is Rayman's Fist equipped? (native game check)
local function raymanOn()
    local w = Refs.World
    local f = w and rawget(w, "raymanOn")
    if type(f) ~= "function" then return false end
    local ok, on = pcall(f)
    return ok and on == true
end

-- Find 2-3 aligned target tiles from character (8 directions, range 1-3),
-- matching Rayman punch in the game.
local RAY_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local function raymanLine(px, py, active)
    local byKey = {}
    for _, a in ipairs(active) do byKey[a.x .. "," .. a.y] = a end
    local best, bestDir = nil, nil
    for _, d in ipairs(RAY_DIRS) do
        local line = {}
        for i = 1, 3 do
            local a = byKey[(px + d[1] * i) .. "," .. (py + d[2] * i)]
            if a then line[#line + 1] = a end
        end
        if #line >= 2 and #line > (best and #best or 0) then best, bestDir = line, d end
    end
    return best, bestDir
end

-- Notify server of Rayman swing (same packet the game sends on Rayman punch)
local function raymanAct(dir)
    local ok, s = pcall(Refs.State)
    if not ok or type(s) ~= "table" or not s.x then return end
    if NetOk and type(Net) == "table" and Net.act then
        pcall(Net.act.send, { kind = 4, x = s.x + dir[1], y = s.y - 0.475 + dir[2] })
    end
end

local function farmLoop(runId)
    local lastStatus = 0
    local function currentRun()
        return State.Running and alive() and State.RunId == runId
    end
    while currentRun() do
        if State.DropPause then -- currently away dropping seeds
            task.wait(0.2)
            continue
        end
        if State.DropYield then
            State.DropYield = false
            while currentRun() and State.DropYieldWait do task.wait(0.05) end
            continue
        end
        local doPlace = farmMode() ~= "Break only"
        local doBreak = farmMode() ~= "Place only"

        local px, py = getPlayerTile()
        if not px then
            stopFarm("Character not found (left world?)")
            return
        end

        local tiles = {}
        for _, o in ipairs(sortedOffsets()) do
            tiles[#tiles + 1] = { x = px + o.dx, y = py + o.dy }
        end

        local acted, outOfBlock = false, false

        -- 0) Collect drops on all grid tiles via body touch (single pass), then return to position
        if (State.AutoCollect or State.Override) and not State.DropPause and not State.DropYield then
            Drops.waitSpawn(tiles) -- break drops just arrived from server: wait for them to spawn
            if not currentRun() then break end
            if State.CollectMode == "Remote" then
                for _, t in ipairs(tiles) do
                    if not currentRun() or State.DropYield then break end
                    waitTileDrops(t, 0.4)
                end
            elseif Drops.touchAll then
                Drops.touchAll(tiles, px, py, currentRun)
            end
        end
        if not currentRun() then break end

        -- 1) Place all empty tiles (stop placing new blocks if Auto Drop is waiting to depart)
        if doPlace and not State.DropYield then
            for _, t in ipairs(tiles) do
                if not currentRun() or State.DropPause or State.DropYield then break end
                local r = tryPlace(t.x, t.y)
                if r == "empty" then
                    outOfBlock = true
                    break
                elseif r == "place" then
                    acted = true
                    if not waitMs(State.PlaceMs) then break end
                end
            end
        end

        -- 2) Punch tiles until cleared (foreground block then background).
        --    Server accepts 1 punch every ~0.22s (normal hand), so multi-target punches
        --    tiles ALTERNATELY (like multi-finger). All tiles break completely.
        --    With Rayman's Fist: 2-3 aligned tiles are hit per punch (like real Rayman).
        if doBreak then
            local K = math.clamp(math.floor(State.MultiTarget or 1), 1, 5)
            local nextI, active = 1, {}
            while currentRun() and not State.DropPause do
                while #active < K and nextI <= #tiles do
                    local t = tiles[nextI]
                    nextI += 1
                    active[#active + 1] = { x = t.x, y = t.y, n = 0 }
                end
                if #active == 0 then break end

                -- choose tiles to punch next
                local hits, rayDir = nil, nil
                if K > 1 and raymanOn() then
                    hits, rayDir = raymanLine(px, py, active)
                end
                if not rayDir then hits = { active[1] } end -- front of queue turn

                local t0 = os.clock()
                if rayDir then raymanAct(rayDir) end
                local hit, broke = false, false
                for i, a in ipairs(hits) do
                    if i > 1 then task.wait(0.05) end -- tile delay matching Rayman animation
                    if not currentRun() or State.DropPause then break end
                    local r = tryBreak(a.x, a.y)
                    a.n += 1
                    if r then hit, acted = true, true end
                    if r == "broke" then broke = true end
                    -- done when empty / unbreakable / cleared down to background
                    if r == nil or a.n > 80 or (r == "broke" and not breakableAt(a.x, a.y)) then
                        a.done = true
                    end
                    a.used = true
                end

                -- just-punched tile moves to back of queue (alternating)
                local nextActive = {}
                for _, a in ipairs(active) do
                    if not a.done and not a.used then nextActive[#nextActive + 1] = a end
                end
                for _, a in ipairs(hits) do
                    a.used = nil
                    if not a.done then nextActive[#nextActive + 1] = a end
                end
                active = nextActive

                if hit then
                    local gap = State.BreakMs / 1000
                    if rayDir then gap = math.max(gap, 0.35) end -- real Rayman delay
                    local rest = gap - (os.clock() - t0)
                    if rest > 0.005 then task.wait(rest) end
                    if not currentRun() then break end
                end
                -- drops are collected automatically by fast collector
                if broke and State.AfterBreakMs > 0 then task.wait(State.AfterBreakMs / 1000) end
            end
        end

        if not currentRun() then break end
        if State.DropYield then
            State.DropYield = false
            while currentRun() and State.DropYieldWait do task.wait(0.05) end
            continue
        end
        if State.DropPause then continue end

        if not acted then
            local sel = farmBlock()
            if outOfBlock or (doPlace and sel and invCount(sel) <= 0) then
                stopFarm("Block " .. itemName(sel) .. " ran out in inventory")
                return
            end
            if not waitMs(State.BreakMs) then break end
        end

        State.Cycles += 1
        if os.clock() - lastStatus > 1 then
            lastStatus = os.clock()
            updateStatus()
        end
    end
    updateStatus()
end

local function setRunningVisual()
    if State.Override then return end -- run by Factory: Auto Farm toggle stays untouched
    if UI.FarmToggle then pcall(function() UI.FarmToggle:Set(State.Running) end) end
    if UI.GridStart and UI.GridMode == "farm" then
        UI.GridStart.Text = State.Running and "STOP" or "START"
        UI.GridStart.BackgroundColor3 = State.Running and UI.Palette.Stop or UI.Palette.Action
    end
end

stopFarm = function(reason)
    State.Running = false
    State.DropYield = false
    State.DropYieldWait = false
    setRunningVisual()
    if reason and not State.Quiet then
        notify("Auto Farm stopped", reason, 4)
        Hook.send("stop", "Auto Farm stopped: " .. reason)
    end
    updateStatus()
end

-- Auto Farm, Clear & Farmer must not run simultaneously
local stopClear, stopFarmer

local function startFarm()
    if State.Running then return end
    if WorldFinder.Busy then notify("World Finder", "Stop hunting before running farming", 3) return end
    if AutoDrop.Busy then notify("Auto Drop", "Wait for the drop trip to finish", 3) return end
    local err = validate()
    if err then
        stopFarm(err)
        return
    end
    if Splice.Running and Splice.stop then Splice.stop("Stopped because Auto Farm started") end
    if Factory.Running and Factory.stop then Factory.stop("Stopped because Auto Farm started") end
    if Build.Running and Build.stop then Build.stop("Stopped because Auto Farm started") end
    if Clear.Running and stopClear then stopClear("Stopped because Auto Farm started") end
    if Farmer.Running and stopFarmer then stopFarmer("Stopped because Auto Farm started") end
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.DropPause = false
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    setRunningVisual()
    updateStatus()
    task.spawn(farmLoop, State.RunId)
end


-- UI helpers grouped here (Luau limits 200 locals per scope)
local Auto = {}
do (function() -- isolated function: internal locals do not count toward the 200-local limit
---------------------------------------------------------------------
-- AUTO MOVEMENT (used by Clear World & Farmer)
---------------------------------------------------------------------
-- How it works:
--   - Paths found via A* matching game physics (walk, fall, jump up 1-3 tiles).
--   - Character moves by pressing virtual keys, just like normal play.
--   - No fly / noclip since the server rolls them back.
--   - Without footing, place a scaffold block from inventory (bridge / stairs).
local floor, abs = math.floor, math.abs

local Move = { Placed = 0 }  -- count of scaffold blocks placed
local BadEdge = {}           -- recently failed paths (avoid temporarily)
local ClearFail, FarmerFail = {}, {}
local BreakTimes = {}        -- tiles that keep reverting after breaking
local Reach = nil            -- cached reachable tiles list

local function autoOn()
    if Move.Homing and Move.HomingLive and not Move.HomingLive() then return false end
    if Build.DirtRun and not Build.dirtWorldMatches(Build.DirtRun) then return false end
    return (Clear.Running or Farmer.Running or Splice.Roaming or Factory.Running or Build.Running or Move.Homing
        or Vend.Running) and alive()
end

local function setMoveStatus(text)
    if AutoDrop.Busy then
        AutoDrop.Status = text
    elseif Clear.Running then
        Clear.Status = text
    elseif Farmer.Running then
        Farmer.Status = text
    elseif Splice.Roaming then
        Splice.Status = text
    elseif Build.Running then
        Build.Status = text
    elseif Factory.Running then
        Factory.Status = text
    elseif Vend.Running then
        Vend.Status = text
    end
end

local function skipTile(tbl, idx, sec)
    tbl[idx] = os.clock() + (sec or 30)
end

local function skipped(tbl, idx, now)
    local t = tbl[idx]
    if not t then return false end
    if (now or os.clock()) >= t then
        tbl[idx] = nil
        return false
    end
    return true
end

local function skippedCount(tbl)
    local n, now = 0, os.clock()
    for _, t in pairs(tbl) do
        if t > now then n += 1 end
    end
    return n
end

local function hudRange(name, def)
    local f = Refs.Hud and Refs.Hud[name]
    if type(f) == "function" then
        local ok, r = pcall(f)
        if ok and type(r) == "number" and r > 0 then return r end
    end
    return def
end

local function punchReach() return hudRange("punchRange", 2.5) end
local function buildReach() return hudRange("buildRange", 2.5) end

local function playerState()
    if not Refs.State then return nil end
    local ok, s = pcall(Refs.State)
    if ok and type(s) == "table" and type(s.x) == "number" and type(s.y) == "number" and s.active ~= false then
        return s
    end
    return nil
end

local function fgIdAt(x, y)
    local w = Refs.World
    local row = w and w.fg[y]
    return (row and row[x]) or 0
end

local function fgItemAt(x, y)
    local id = fgIdAt(x, y)
    if id ~= 0 then return ItemDB[id] end
    return nil
end

-- Is tile solid? (matches game collision check)
local function solidAt(x, y)
    local w = Refs.World
    if not w then return true end
    if x < 0 or x >= w.w or y >= w.h then return true end
    if y < 0 then return false end
    local it = fgItemAt(x, y)
    if not it then return false end
    if it.combiner then
        local ok, shut = pcall(w.combinerShut, x, y)
        return (not ok) or (shut and true or false)
    end
    if it.vip then -- VIP door: solid if you lack access
        local ok, may = pcall(w.vipMay, x, y)
        return not (ok and may)
    end
    if it.entrance then
        local sw = w.switches and w.switches[y * w.w + x]
        if it.gate then
            return not (sw and sw.off == true)
        end
        if sw and sw.public then return false end
        local ok, may = pcall(function() return w.areas.mayBuild(w.lock, x, y) end)
        return not (ok and may)
    end
    return it.solid and true or false
end

function Session.boxOverlapsSolid(px, py)
    local w = Refs.World
    if not w or type(w.fg) ~= "table" or not Session.ItemDBSource
        or not (math.abs(px) < math.huge and math.abs(py) < math.huge) then return nil end
    -- Use character hitbox dimensions from game client's boxHits.
    for y = floor(py - 0.95), floor(py - 0.0001) do
        for x = floor(px - 0.3), floor(px + 0.3 - 0.0001) do
            if x >= 0 and x < w.w and y >= 0 and y < w.h then
                if type(w.fg[y]) ~= "table" then return nil end
                local id = fgIdAt(x, y)
                if id ~= 0 and type(ItemDB[id]) ~= "table" then return nil end
            end
            if solidAt(x, y) then return true end
        end
    end
    return false
end

function Session.checkGhostPosition()
    local s = playerState()
    if not s then return nil end
    local hit = Session.boxOverlapsSolid(s.x, s.y)
    if hit == nil then return nil end
    if hit then
        return false, "Your character still overlaps a block. Move into open space and turn it off again."
    end
    if math.abs(s.vx or 0) > 0.1 or math.abs(s.vy or 0) > 0.1 then
        return false, "Release movement controls and wait for your character to stop before turning Fly off."
    end
    return true
end

-- Hazardous tile (lava, spikes, laser)
local function hazardAt(x, y)
    local it = fgItemAt(x, y)
    return it ~= nil and (it.deadly or it.hurts or it.laser) and true or false
end

local function platformAt(x, y)
    local it = fgItemAt(x, y)
    return it ~= nil and it.platform and true or false
end

local function openAt(x, y)
    return not solidAt(x, y) and not hazardAt(x, y)
end

-- Is there safe footing below this tile?
local function realSupport(x, y)
    return not hazardAt(x, y + 1) and (solidAt(x, y + 1) or platformAt(x, y + 1))
end

-- Is target in line of sight from body? (not blocked by solid floor / ceiling in between)
-- Harvesting through blocks works, but drops land behind them and stay uncollected.
function Move.los(nx, ny, tx, ty)
    if ty - ny >= 2 then
        for y = ny + 1, ty - 1 do
            if solidAt(tx, y) then return false end
        end
    elseif ny - ty >= 2 then
        for y = ty + 1, ny - 1 do
            if solidAt(tx, y) then return false end
        end
    end
    return true
end

-- Is tile within reach? (box area around body)
local function stateReaches(s, tx, ty, R)
    return abs(tx + 0.5 - s.x) <= R and abs(ty + 0.5 - (s.y - 0.475)) <= R
end

-- Allowed to break here? (check lock)
local function canWorkAt(x, y)
    local w = Refs.World
    local ok, res = pcall(function()
        if w.areas and type(w.areas.mayBuild) == "function" and not w.areas.mayBuild(w.lock, x, y) then
            return false
        end
        if type(w.builderOk) == "function" and not w.builderOk(x, y, false) then
            return false
        end
        return true
    end)
    return (not ok) or res
end

-- ---------- Scaffold blocks ----------
local function scaffoldId()
    local id, use
    if Clear.Running then
        id, use = Clear.ScaffoldId, Clear.UseBlock and not Clear.TargetId
    elseif Farmer.Running then
        id, use = Farmer.ScaffoldId, Farmer.UseBlock
    end -- Build Land uses no scaffolds (walks on the row being built)
    if use and id and invCount(id) > 0 then return id end
    return nil
end

-- Allowed to place block here? (empty + build permission)
local function placeOk(x, y)
    local w = Refs.World
    if not w or x < 0 or y < 0 or x >= w.w or y >= w.h then return false end
    if fgIdAt(x, y) ~= 0 then return false end
    local ok, res = pcall(function()
        if w.areas and type(w.areas.canEdit) == "function" and not w.areas.canEdit(x, y) then return false end
        if type(w.builderOk) == "function" and not w.builderOk(x, y, true) then return false end
        return true
    end)
    return (not ok) or res
end

local function placeScaffold(x, y)
    local id = scaffoldId()
    if not id or not placeOk(x, y) then return false end
    local s = playerState()
    if not s or not stateReaches(s, x, y, buildReach() - 0.05) then return false end
    sendSetTile("fg", x, y, id) -- place via game function
    if Refs.Inv then pcall(function() Refs.Inv:remove(id, 1) end) end
    Move.Placed += 1
    return true
end

local function worldVersion()
    -- increments whenever a block / tree changes so reach cache doesn't go stale
    return Clear.Broken + Farmer.Harvested + Farmer.Planted + Move.Placed + Splice.Planted
        + Factory.Harvested + Factory.Planted + Build.Placed + Build.Harvested + Build.Planted + Build.Dug
        + State.Placed + State.Broken
end

local function startNode(s)
    local ny = floor(s.y - 0.475)
    local nx = floor(s.x)
    if realSupport(nx, ny) then return nx, ny end
    local a, b = floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001)
    for _, c in ipairs({ a, b }) do
        if c ~= nx and realSupport(c, ny) then return c, ny end
    end
    return nx, ny
end

-- ---------- Priority queue for A* ----------
local function heapPush(hf, hi, n, f, i)
    n += 1
    local k = n
    while k > 1 do
        local p = k // 2
        if hf[p] <= f then break end
        hf[k], hi[k] = hf[p], hi[p]
        k = p
    end
    hf[k], hi[k] = f, i
    return n
end

local function heapPop(hf, hi, n)
    local top = hi[1]
    local lf, li = hf[n], hi[n]
    hf[n], hi[n] = nil, nil
    n -= 1
    if n > 0 then
        local k = 1
        while true do
            local c = k * 2
            if c > n then break end
            if c < n and hf[c + 1] < hf[c] then c += 1 end
            if lf <= hf[c] then break end
            hf[k], hi[k] = hf[c], hi[c]
            k = c
        end
        hf[k], hi[k] = lf, li
    end
    return top, n
end

-- ---------- A* ----------
-- Find lowest-cost path to a tile that can reach one of the targets.
-- Available move types:
--   walk   : move 1 tile sideways (+ place scaffold if needed)
--   fall   : walk off edge and fall
--   jump   : jump up 1-3 tiles
--   gap    : jump across 1-2 tile gap
--   stair  : land stair: jump up 2 through gap into 1-tile-high corridor
--   pillar : jump then place block underfoot (climb 1)
local MAX_EXPAND = 8000
local BLOCK_COST = 4

local function reachOffsets(R)
    return floor(R), math.ceil(-R + 0.025), floor(R + 0.025)
end

local function astar(sx, sy, goals, _gx, _gy, R, useBlock, route)
    local w = Refs.World
    if not w then return nil, false, {} end
    local W, H = w.w, w.h
    local edgeFailures = goals.badEdges or (route and route.badEdges) or BadEdge
    local canContinue = goals.live or (route and route.live) or autoOn
    local grid, worldName = w.fg, w.name
    local WH = W * H
    local dxm, dyLo, dyHi = reachOffsets(R)
    local oC, sC, bC = {}, {}, {}

    local function open(x, y)
        if x < 0 or x >= W or y >= H then return false end
        if y < 0 then return true end
        local i = y * W + x
        local v = oC[i]
        if v == nil then
            v = openAt(x, y)
            oC[i] = v
        end
        return v
    end

    local function sup(x, y)
        if x < 0 or x >= W or y < 0 or y >= H then return false end
        local i = y * W + x
        local v = sC[i]
        if v == nil then
            v = realSupport(x, y)
            sC[i] = v
        end
        return v
    end

    local function buildable(x, y)
        if not useBlock or x < 0 or x >= W or y < 0 or y >= H then return false end
        local i = y * W + x
        local v = bC[i]
        if v == nil then
            v = placeOk(x, y)
            bC[i] = v
        end
        return v
    end

    local minX, maxX, minY, maxY = W, -1, H, -1
    for index, wanted in pairs(goals) do
        if type(index) == "number" and wanted then
            local x, y = index % W, index // W
            minX, maxX = math.min(minX, x - dxm), math.max(maxX, x + dxm)
            minY, maxY = math.min(minY, y - dyHi), math.max(maxY, y - dyLo)
        end
    end
    if maxX < minX then return nil, false, {} end
    local function h(x, y)
        local dx = math.max(minX - x, x - maxX, 0)
        local dy = math.max(0.5 * (minY - y), 1.5 * (y - maxY), 0)
        -- A single jump / fall can traverse both axes at once.
        return math.max(dx, dy)
    end

    local function isGoal(nx, ny)
        if route and not route.point(nx, ny) then return 0 end
        -- goals.maxY: standing tile must not be lower than this (Build Land)
        if goals.maxY and ny > goals.maxY then return 0 end
        local count = 0
        for ty = ny + dyLo, ny + dyHi do
            if ty >= 0 and ty < H then
                local base = ty * W
                for tx = nx - dxm, nx + dxm do
                    -- do not stand directly on target (noSelf: also not inside target tile)
                    if tx >= 0 and tx < W and goals[base + tx] and not (tx == nx and ty == ny + 1)
                        and not (goals.noSelf and tx == nx and ty == ny)
                        and not (goals.startState and nx == sx and ny == sy and not stateReaches(goals.startState, tx, ty, R))
                        and not (goals.los and ty - ny >= 2 and not open(tx, ny + 1))
                        and not (goals.los and ny - ty >= 2 and not open(tx, ny - 1)) then
                        if not goals.preferBatch then return 1 end
                        count += 1
                    end
                end
            end
        end
        return count
    end

    local ex, ey, ek, ec, eb = {}, {}, {}, {}, {}
    local n, fromX, fromY = 0, sx, sy
    local function add(x, y, kind, cost, build)
        if route and not route.edge(fromX, fromY, x, y, kind) then return end
        n += 1
        ex[n], ey[n], ek[n], ec[n], eb[n] = x, y, kind, cost, build
    end

    local function expand(x, y)
        n = 0
        fromX, fromY = x, y
        -- Platforms can be passed through from below. Land-end stairs often
        -- require a straight jump on the same column before turning.
        for dy = 1, 3 do
            if not open(x, y - dy) then break end
            if sup(x, y - dy) and open(x, y - dy - 1) then
                add(x, y - dy, "jump", 2 + 1.5 * dy, false)
            end
        end
        for s = -1, 1, 2 do
            local ax = x + s
            if open(ax, y) then
                if sup(ax, y) then
                    add(ax, y, "walk", 1, false)
                else
                    if buildable(ax, y + 1) then
                        add(ax, y, "walk", 1 + BLOCK_COST, true)
                    end
                    -- fall until hitting ground
                    local fy = y + 1
                    while fy < H and fy - y <= 40 and open(ax, fy) and not sup(ax, fy) do
                        fy += 1
                    end
                    if fy < H and open(ax, fy) and sup(ax, fy) then
                        add(ax, fy, "fall", 1.5 + 0.5 * (fy - y), false)
                    end
                    -- jump across 1-2 tile gap
                    if open(x, y - 1) and open(x, y - 2) then
                        for dist = 2, 3 do
                            local mx = x + (dist - 1) * s
                            if not (open(mx, y) and open(mx, y - 1) and open(mx, y - 2)) then break end
                            if dist == 3 and sup(mx, y) then break end
                            local bx = x + dist * s
                            if open(bx, y - 1) and open(bx, y - 2) then
                                for k = 0, 2 do
                                    if not open(bx, y + k) then break end
                                    if sup(bx, y + k) then
                                        add(bx, y + k, "gap", dist + 1 + 0.5 * k, false)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- jump up (headspace must be clear)
            for dy = 1, 3 do
                if not open(x, y - dy) then break end
                if open(x, y - dy - 1) and open(ax, y - dy) and sup(ax, y - dy) and open(ax, y - dy - 1) then
                    add(ax, y - dy, "jump", 2 + 1.5 * dy, false)
                end
            end
            -- land stair: climb 1-2 tiles into 1-tile corridor (ceiling sits right overhead,
            -- so a normal jump hits the ceiling). Hug wall, jump, slide in at peak.
            for dy = 1, 2 do
                if open(x, y - 1) and (dy == 1 or open(x, y - 2)) and open(ax, y - dy) and sup(ax, y - dy)
                    and not (open(x, y - dy - 1) and open(ax, y - dy - 1)) then
                    add(ax, y - dy, "stair", 3 + 1.5 * dy, false)
                end
            end
        end
        -- pillar up 1 using block
        if useBlock and open(x, y - 1) and open(x, y - 2) and open(x, y - 3) and buildable(x, y) then
            add(x, y - 1, "pillar", 2 + BLOCK_COST, true)
        end
        return n
    end

    local startI = sy * W + sx
    local g, came, kind, buildOf, closed = { [startI] = 0 }, {}, {}, {}, {}
    local function makePath(cur)
        local path, i = {}, cur
        while i ~= startI do
            local p = came[i]
            path[#path + 1] = { fx = p % W, fy = p // W, x = i % W, y = i // W,
                kind = kind[i], build = buildOf[i], key = p * WH + i }
            i = p
        end
        for left = 1, #path // 2 do
            local right = #path - left + 1
            path[left], path[right] = path[right], path[left]
        end
        return path
    end
    local hf, hi, hn = {}, {}, 0
    hn = heapPush(hf, hi, hn, h(sx, sy), startI)
    local expanded = 0
    local now = os.clock()
    local nextSlice, popped = now + 0.0015, 0
    local bestGoal, bestCount, bestCost, costLimit = nil, 0, math.huge, nil

    while hn > 0 do
        if costLimit and hf[1] > costLimit then break end
        popped += 1
        -- Node costs vary (collision, lock, and jumps).
        -- Cap by CPU budget rather than waiting for 400 nodes all at once.
        if popped % 8 == 0 and os.clock() >= nextSlice then
            task.wait()
            if not canContinue() or Refs.World ~= w or w.fg ~= grid or w.name ~= worldName then return nil, false, closed end
            nextSlice = os.clock() + 0.0015
        end
        local cur
        cur, hn = heapPop(hf, hi, hn)
        if not closed[cur] and (not costLimit or g[cur] <= costLimit) then
            closed[cur] = true
            local cx, cy = cur % W, cur // W
            local count = isGoal(cx, cy)
            if count > 0 then
                if not goals.preferBatch or count >= (goals.targetCount or 1) then return makePath(cur), false, closed end
                if count > bestCount or (count == bestCount and g[cur] < bestCost) then
                    bestGoal, bestCount, bestCost = cur, count, g[cur]
                end
                costLimit = costLimit or (g[cur] + (goals.batchExtra or 2))
            end
            expanded += 1
            if expanded > MAX_EXPAND then return bestGoal and makePath(bestGoal) or nil, false, closed end
            local gc = g[cur]
            local cnt = expand(cx, cy)
            for k = 1, cnt do
                local ni = ey[k] * W + ex[k]
                if not closed[ni] then
                    local bad = edgeFailures[cur * WH + ni]
                    if not (bad and bad > now) then
                        local ng = gc + ec[k]
                        local old = g[ni]
                        if (not costLimit or ng <= costLimit) and (old == nil or ng < old) then
                            g[ni], came[ni], kind[ni], buildOf[ni] = ng, cur, ek[k], eb[k]
                            hn = heapPush(hf, hi, hn, ng + h(ex[k], ey[k]), ni)
                        end
                    end
                end
            end
        end
    end
    if bestGoal then return makePath(bestGoal), false, closed end
    return nil, true, closed -- no path at all
end

-- All tiles reachable from this area
local function reachableTileSet(closed, W, R)
    local set = {}
    local dxm, dyLo, dyHi = reachOffsets(R)
    local n = 0
    local w, grid = Refs.World, Refs.World and Refs.World.fg
    local budget = { next = os.clock() + 0.0015 }
    for i in pairs(closed) do
        local x, y = i % W, i // W
        for dy = dyLo, dyHi do
            local ty = y + dy
            if ty >= 0 then
                local base = ty * W
                for dx = -dxm, dxm do
                    local tx = x + dx
                    if tx >= 0 and tx < W then set[base + tx] = true end
                end
            end
        end
        n += 1
        Session.scanStep(budget, n * 8)
        if not autoOn() or Refs.World ~= w or (w and w.fg ~= grid) then return {} end
    end
    return set
end

-- Cache reachable tiles so tiles across chasms are skipped immediately
-- (avoids repeated failed pathfinding that freezes character).
local function reachFilter(startI, R, useBlock)
    local c = Reach
    if c and c.world == Refs.World and c.start == startI and c.R == R and c.block == useBlock
        and c.ver == worldVersion() and os.clock() - c.at < 30 then
        return c.set
    end
    return nil
end

local function storeReach(startI, R, useBlock, closed)
    Reach = {
        world = Refs.World, start = startI, R = R, block = useBlock, ver = worldVersion(), at = os.clock(),
        set = reachableTileSet(closed, Refs.World.w, R),
    }
end

-- ---------- Move character ----------
local function releaseInput()
    AutoInput.left, AutoInput.right, AutoInput.jump, AutoInput.down = false, false, false, false
    AutoInput.collectOwner = nil
end

local function frame()
    task.wait()
    local route = Move.HomingRoute
    if route and ((route.needsRefresh and route.needsRefresh()) or not route.safe(playerState())) then
        releaseInput()
        route.invalidated = true
        return false -- walkTo recalculates path from last position
    end
    return autoOn()
end

local function waitAuto(ms)
    task.wait(math.max(ms or 0, 30) / 1000)
    return autoOn()
end

-- ===== ACTION ANIMATION (local visual only, sends nothing to server) =====
-- Aim character's hand toward tile (just like when punching / placing manually).
function Anim.swing(x, y, kind)
    if not (Anim.fn and Anim.idx and Anim.set) then return end
    local s = playerState()
    local facing = (s and x + 0.5 < s.x) and -1 or 1
    pcall(Anim.set, Anim.fn, Anim.idx, { t = os.clock(), x = x + 0.5, y = y + 0.5, facing = facing, kind = kind })
end

-- Small puff effect when placing block (uses game "place" effect)
function Anim.puff(x, y)
    local list = Refs.Particles
    if not list or #list == 0 then return end
    local pick = Anim.Particles
    if not pick then
        local worldGui = PlayerGui:FindFirstChild("GameGui")
        worldGui = worldGui and worldGui:FindFirstChild("World")
        for _, p in ipairs(list) do
            local ok, inWorld = pcall(function()
                return worldGui ~= nil and typeof(p.parent) == "Instance" and p.parent:IsDescendantOf(worldGui)
            end)
            if ok and inWorld then
                pick = p
                break
            end
        end
        pick = pick or list[1]
        Anim.Particles = pick
    end
    pcall(function() pick:place(x + 0.5, y + 0.5) end)
end

function Anim.place(x, y, id)
    local it = ItemDB[id]
    local seed = it and it.kind == "seed"
    Anim.swing(x, y, "build")
    if not seed then Anim.puff(x, y) end
end

-- Walk to targetX, release key when close enough to stop cleanly
local function steerX(s, targetX, tol)
    local dx = targetX - s.x
    local vx = s.vx or 0
    local decel = s.grounded and 48 or 17
    local dir = 0
    if abs(dx) > tol then
        dir = dx > 0 and 1 or -1
        if vx * dir > 0 and (vx * vx) / (2 * decel) >= abs(dx) - tol * 0.5 then
            dir = 0
        end
    end
    AutoInput.left = dir < 0
    AutoInput.right = dir > 0
end

-- Walk until centered on destination tile
local function execWalk(tx, ty, tolerance)
    tolerance = tolerance or 0.2
    local cx = tx + 0.5
    local s0 = playerState()
    if not s0 then return false end
    local limit = 1.5 + abs(cx - s0.x) * 0.35
    local t0 = os.clock()
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        local nx, ny = floor(s.x), floor(s.y - 0.475)
        if s.grounded and ny ~= ty then return false end
        steerX(s, cx, math.min(0.1, tolerance * 0.5))
        if nx == tx and abs(s.x - cx) <= tolerance and s.grounded and abs(s.vx or 0) < 2 then
            AutoInput.left, AutoInput.right = false, false
            return true
        end
        if os.clock() - t0 > limit then return false end
    end
    return false
end

-- Walk off edge and fall onto destination tile
local function execFall(e)
    local cx = e.x + 0.5
    local limit = 1.5 + 0.3 * (e.y - e.fy)
    local t0 = os.clock()
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        steerX(s, cx, 0.1)
        if s.grounded then
            local nx, ny = floor(s.x), floor(s.y - 0.475)
            if ny == e.y then
                if nx == e.x and abs(s.x - cx) <= 0.25 then return true end
            elseif ny ~= e.fy then
                return false
            end
        end
        if os.clock() - t0 > limit then return false end
    end
    return false
end

-- Jump up to adjacent tile
local function execJump(e)
    if not execWalk(e.fx, e.fy) then return false end
    local dy = e.fy - e.y
    local top = e.y + 1                               -- target foot height
    local releaseY = top - ((dy == 1) and 0 or 0.4)   -- release jump here (head won't bonk)
    local cx = e.x + 0.5
    releaseInput()
    if not frame() then return false end              -- release for 1 frame so jump registers
    AutoInput.jump = true
    local t0 = os.clock()
    local airborne = false
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        if not s.grounded then airborne = true end
        if AutoInput.jump and (s.y <= releaseY or (airborne and (s.vy or 0) >= 0)) then
            AutoInput.jump = false
        end
        if s.y <= top + 0.25 then
            steerX(s, cx, 0.1)
        else
            steerX(s, e.fx + 0.5, 0.15)
        end
        if airborne and s.grounded then
            local nx, ny = floor(s.x), floor(s.y - 0.475)
            if ny == e.y then
                if nx == e.x and abs(s.x - cx) <= 0.25 then
                    AutoInput.jump = false
                    return true
                end
            else
                return false
            end
        end
        if not airborne and os.clock() - t0 > 0.35 then return false end
        if os.clock() - t0 > 1.8 then return false end
    end
    return false
end

-- Jump gap: run-up, jump at edge, brake mid-air
local function execGap(e)
    if not execWalk(e.fx, e.fy) then return false end
    local s0 = playerState()
    if not s0 then return false end
    local dir = (e.x > e.fx) and 1 or -1
    local takeoff = e.fx + 0.5 + dir * 0.6
    local startY = s0.y
    local cx = e.x + 0.5
    releaseInput()
    local t0 = os.clock()
    local jumped, airborne, jumpAt = false, false, 0
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        if not jumped then
            AutoInput.left, AutoInput.right = dir < 0, dir > 0
            if (s.x - takeoff) * dir >= 0 or not s.grounded then
                jumped, jumpAt = true, os.clock()
                AutoInput.jump = s.grounded
            end
        else
            if not s.grounded then airborne = true end
            if AutoInput.jump and (s.y <= startY - 1 or (airborne and (s.vy or 0) >= 0)) then
                AutoInput.jump = false
            end
            steerX(s, cx, 0.1)
            if airborne and s.grounded then
                local nx, ny = floor(s.x), floor(s.y - 0.475)
                if ny == e.y then
                    if nx == e.x and abs(s.x - cx) <= 0.25 then return true end
                else
                    return false
                end
            end
            if not airborne and os.clock() - jumpAt > 0.35 then return false end
        end
        if os.clock() - t0 > 2.2 then return false end
    end
    return false
end

-- Land stair: climb 1-2 tiles into 1-tile corridor (through stair gap / out of shaft).
-- Manual technique: stand flush against target side, jump, press direction AFTER rising
-- (pressing too soon pushes body under target block -> head bonk -> fall),
-- when head touches ceiling, feet clear target block -> slide in. 3 methods tried.
function Move.execStair(e)
    if not execWalk(e.fx, e.fy) then return false end
    local dir = (e.x > e.fx) and 1 or -1
    local top = e.y + 1 -- target foot height (top of footing block)
    local hug = e.fx + 0.5 + dir * 0.17
    for try = 1, 3 do
        -- hug wall on target side
        local t0 = os.clock()
        while frame() do
            local s = playerState()
            if not s or s.dead then return false end
            steerX(s, hug, 0.03)
            if abs(s.x - hug) <= 0.06 and abs(s.vx or 0) < 1 then break end
            if os.clock() - t0 > 0.8 then break end
        end
        releaseInput()
        if not frame() then return false end
        local s0 = playerState()
        if not s0 then return false end
        local y0 = s0.y
        AutoInput.jump = true
        t0 = os.clock()
        local airborne, landed = false, nil
        while frame() do
            local s = playerState()
            if not s or s.dead then return false end
            if not s.grounded then airborne = true end
            if AutoInput.jump and (s.y <= top - 0.1 or (airborne and (s.vy or 0) >= 0)) then
                AutoInput.jump = false -- reached target height / hit ceiling
            end
            -- When jumping under corridor ceiling, head presses ceiling ~0.18s while feet clear target
            -- block: press direction then -> body enters corridor smoothly (no game step-up needed).
            -- DO NOT press direction from floor: body slips under target block -> head bonk -> fall.
            -- try 1: once feet reach top of target block (touching ceiling)
            -- try 2: after rising 0.15 tile (pressing block side, game steps body up <= 0.3 tile)
            -- try 3: when feet are 0.25 tile below block top
            local press = (try == 1 and s.y <= top + 0.02) or (try == 2 and s.y <= y0 - 0.15) or (try == 3 and s.y <= top + 0.25)
            if airborne and press then
                AutoInput.right, AutoInput.left = dir > 0, dir < 0
            else
                steerX(s, hug, 0.03)
            end
            if airborne and s.grounded then
                landed = floor(s.y - 0.475)
                break
            end
            if not airborne and os.clock() - t0 > 0.35 then break end
            if os.clock() - t0 > 1.8 then break end
        end
        releaseInput()
        if landed == e.y then
            return execWalk(e.x, e.y) -- inside upper corridor: center on target tile
        end
        if landed ~= nil and landed ~= e.fy then return false end -- fell elsewhere
        if not execWalk(e.fx, e.fy) then return false end
    end
    return false
end

-- Climb 1 tile: jump, place block underfoot, then land on top.
-- Place block slightly delayed so server position has already risen.
local function execPillar(e)
    if not execWalk(e.fx, e.fy) then return false end
    if fgIdAt(e.fx, e.fy) ~= 0 then return false end
    releaseInput()
    if not frame() then return false end
    AutoInput.jump = true
    local t0 = os.clock()
    local placed, airborne = false, false
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        if not s.grounded then airborne = true end
        steerX(s, e.fx + 0.5, 0.12)
        if AutoInput.jump and (s.y < e.fy - 0.9 or (airborne and (s.vy or 0) >= 0)) then
            AutoInput.jump = false
        end
        if not placed and airborne and s.y < e.fy - 0.25 and ((s.vy or 0) > -6 or s.y < e.fy - 0.8) then
            placed = placeScaffold(e.fx, e.fy)
            if not placed then return false end
        end
        if s.grounded and airborne then
            local nx, ny = floor(s.x), floor(s.y - 0.475)
            return placed and nx == e.x and ny == e.y
        end
        if not airborne and os.clock() - t0 > 0.35 then return false end
        if os.clock() - t0 > 1.8 then return false end
    end
    return false
end

local function followPath(path, badEdges)
    local i = 1
    while i <= #path do
        if not autoOn() then return false end
        local e = path[i]
        local last, ok = i, false
        if e.kind == "walk" then
            -- consecutive same-direction steps merged into one move
            local dir = e.x - e.fx
            while path[last + 1] and path[last + 1].kind == "walk" and (path[last + 1].x - path[last + 1].fx) == dir do
                last += 1
            end
            local anyBuild = false
            for j = i, last do
                if path[j].build then
                    anyBuild = true
                    break
                end
            end
            if anyBuild then
                -- needs block: place ahead, then step onto it
                ok = true
                for j = i, last do
                    local st = path[j]
                    if st.build and not realSupport(st.x, st.y) then
                        setMoveStatus(("Place scaffold block (%d,%d)"):format(st.x, st.y + 1))
                        if not placeScaffold(st.x, st.y + 1) or not waitAuto(120) then
                            ok = false
                            break
                        end
                    end
                    if not execWalk(st.x, st.y) then
                        ok = false
                        break
                    end
                end
            else
                setMoveStatus(("Walk to (%d,%d)"):format(path[last].x, path[last].y))
                ok = execWalk(path[last].x, path[last].y)
            end
        elseif e.kind == "pillar" then
            setMoveStatus(("Pillar up to (%d,%d)"):format(e.x, e.y))
            ok = execPillar(e)
        elseif e.kind == "fall" then
            setMoveStatus(("Drop down to (%d,%d)"):format(e.x, e.y))
            ok = execFall(e)
        elseif e.kind == "jump" then
            setMoveStatus(("Jump to (%d,%d)"):format(e.x, e.y))
            ok = execJump(e)
        elseif e.kind == "gap" then
            setMoveStatus(("Jump gap to (%d,%d)"):format(e.x, e.y))
            ok = execGap(e)
        elseif e.kind == "stair" then
            setMoveStatus(("Climb stair to (%d,%d)"):format(e.x, e.y))
            ok = Move.execStair(e)
        end
        releaseInput()
        if not ok then
            if badEdges and Move.HomingRoute and Move.HomingRoute.invalidated then return false end
            -- avoid this edge temporarily (short cooldown on stairs so it doesn't detour to another stair)
            local failures = badEdges or BadEdge
            if last > i then
                local state = playerState()
                if state then
                    local x, y = startNode(state)
                    for j = i, last do
                        if path[j].fx == x and path[j].fy == y then e = path[j] break end
                    end
                end
            end
            failures[e.key] = os.clock() + (badEdges and 2 or ((e.kind == "stair") and 5 or 20))
            return false
        end
        i = last + 1
    end
    return true
end

-- Pathfind to target group, then walk there
local function travelGroup(sx, sy, group, R, useBlock, skipTbl, failTbl)
    local w = Refs.World
    local goals = {}
    goals.maxY = group.maxY
    goals.los = group.los
    if group.preferBatch then
        goals.preferBatch, goals.targetCount = true, #group
    end
    for _, t in ipairs(group) do goals[t.idx] = true end
    local first = group[1]
    setMoveStatus(("Pathfinding A* to (%d,%d)"):format(first.x, first.y))
    local path, exhausted, closed = astar(sx, sy, goals, first.x, first.y, R, useBlock)
    if path then
        if #path == 0 then
            for _, t in ipairs(group) do skipTile(skipTbl, t.idx, 20) end
        elseif not followPath(path) then
            failTbl[first.idx] = (failTbl[first.idx] or 0) + 1
            if failTbl[first.idx] >= 3 then
                for _, t in ipairs(group) do skipTile(skipTbl, t.idx, 40) end
            end
        end
        releaseInput()
        return true
    end
    -- no path to this group
    for _, t in ipairs(group) do skipTile(skipTbl, t.idx, exhausted and 60 or 30) end
    if exhausted and w then storeReach(sy * w.w + sx, R, useBlock, closed) end
    releaseInput()
    return false
end

-- ---------- Walk to uncollected drops ----------
-- Harvest drops sometimes land out of collect range. Drops are scanned from game drop list
-- (same as Growscan), then character walks over (A*, no scaffold) until the drop
-- is actually collected. Unreachable drops are skipped briefly.
-- Collect drops on work tiles via body touch (Auto Farm, Factory, Build Land seeds), no remote.
-- Game rule: drops collect when within < 0.6 tile of body center (horizontal) and body height.
--   - same-row tiles (left / right, up to 3 tiles): sweep to furthest tile each side
--   - upper-row tiles (left, middle, right): stand below and hop (tap); while airborne
--     shift toward next upper tile still holding drops (can hit 2 in one jump)
-- then return to work position (hx, hy). Returns: true = back at work position.
function Drops.touchAll(tiles, hx, hy, live)
    local list = Drops.list
    if not list or not OrigIsDown or AutoDrop.Busy then return false end
    local function dropsAt(t)
        for _, d in ipairs(list) do
            if type(d) == "table" and type(d.x) == "number" and (d.n or 0) > 0 and d.armed ~= false
                and not d.taking and canTry(d, os.clock()) and inTile(t, d.x, d.y) then
                return true
            end
        end
        return false
    end
    local has = {}
    for _, t in ipairs(tiles) do
        if not solidAt(t.x, t.y) and dropsAt(t) then has[#has + 1] = t end
    end
    if #has == 0 then return false end
    local s0 = playerState()
    if not s0 or s0.dead or not s0.grounded then return false end
    local route = #AutoDrop.Zones > 0 and AutoDrop.route and AutoDrop.route()
    local function ground(c) return openAt(c, hy) and realSupport(c, hy) end
    local function walkable(a, b)
        local st = (b >= a) and 1 or -1
        for c = a, b, st do
            if not ground(c) then return false end
        end
        return true
    end
    local was = AutoInput.active
    local owner = {}
    AutoInput.collectOwner = owner
    AutoInput.active = true
    local function canMove()
        return AutoInput.collectOwner == owner and alive() and not AutoDrop.Busy and (not live or live())
    end
    local function moveTo(cx, maxT)
        if not canMove() then return false end
        if route then
            local state = playerState()
            if not state or not route.edge(floor(state.x), floor(state.y - 0.475), floor(cx), hy, "walk") then return false end
        end
        local t0 = os.clock()
        while os.clock() - t0 < (maxT or 1.2) do
            task.wait()
            if not canMove() then return false end
            local c = playerState()
            if not c or c.dead then break end
            steerX(c, cx, 0.1)
            if c.grounded and abs(c.x - cx) <= 0.15 and abs(c.vx or 0) < 1.5 then
                AutoInput.left, AutoInput.right = false, false
                return true
            end
        end
        AutoInput.left, AutoInput.right = false, false
        return false
    end
    -- small hop (tap = ~1.4 tile high, won't climb onto block row above), drift toward toX mid-air
    local function hop(toX)
        if not canMove() then return end
        AutoInput.left, AutoInput.right = false, false
        local c0 = playerState()
        if not c0 then return end
        if route then
            local x, y = floor(c0.x), floor(c0.y - 0.475)
            if not route.edge(x, y, floor(toX or c0.x), y, "jump") then return end
        end
        local y0 = c0.y
        AutoInput.jump = true
        local t0, air = os.clock(), false
        while os.clock() - t0 < 1.4 do
            task.wait()
            if not canMove() then return end
            local c = playerState()
            if not c or c.dead then break end
            if not c.grounded then
                air = true
                AutoInput.jump = false -- tap: release jump as soon as airborne
            end
            if toX and air and c.y <= y0 - 0.25 then steerX(c, toX, 0.1) else AutoInput.left, AutoInput.right = false, false end
            if air and c.grounded then break end
            if not air and os.clock() - t0 > 0.35 then break end
        end
        AutoInput.jump, AutoInput.left, AutoInput.right = false, false, false
    end
    -- body row: sweep to furthest tile on each side
    local lo, hi = hx, hx
    for _, t in ipairs(has) do
        if t.y == hy and abs(t.x - hx) <= 3 then
            if t.x < lo then lo = t.x end
            if t.x > hi then hi = t.x end
        end
    end
    if lo < hx and walkable(hx - 1, lo) then moveTo(lo + 0.5) end
    if hi > hx and walkable(hx + 1, hi) then moveTo(hi + 0.5) end
    -- upper row: jump beneath tiles still holding drops (max 4 jumps)
    for _ = 1, 4 do
        local cs = playerState()
        if not cs or not canMove() then break end
        local cur = floor(cs.x)
        local cols = {}
        for _, t in ipairs(has) do
            if t.y == hy - 1 and abs(t.x - hx) <= 1 and ground(t.x) and walkable(cur, t.x)
                and not solidAt(t.x, t.y) and dropsAt(t) then
                cols[#cols + 1] = t.x
            end
        end
        if #cols == 0 then break end
        table.sort(cols, function(p, q) return abs(p - cur) < abs(q - cur) end)
        local a = cols[1]
        if a ~= cur then moveTo(a + 0.5) end
        hop(cols[2] and (cols[2] + 0.5) or nil) -- while drifting to next tile
    end
    -- return to work position
    local ok = moveTo(hx + 0.5, 2)
    if AutoInput.collectOwner == owner then
        releaseInput()
        AutoInput.active = was
        if ok then waitNearDrops(0.2) end
    end
    return ok
end

function Drops.touch(t, hx, hy)
    return Drops.touchAll({ t }, hx, hy)
end

-- Just-broken tile: drops arrive from server (latency-dependent). Wait until new drop
-- spawns on that tile (or timeout), before being covered by a new block / missed.
function Drops.waitSpawn(tiles)
    local ping = 0.1
    pcall(function() ping = LocalPlayer:GetNetworkPing() end)
    local limit = math.clamp(0.15 + 2.5 * ping, 0.25, 0.8)
    local newest = nil
    for _, t in ipairs(tiles) do
        local b = Drops.brokeAt[t.x .. "," .. t.y]
        if b and os.clock() - b < limit and (not newest or b > newest) then newest = b end
    end
    if not newest then return end
    local list = Drops.list
    while os.clock() - newest < limit and alive() do
        if list then
            for _, d in ipairs(list) do
                if type(d) == "table" and type(d.x) == "number" and (d.born or 0) >= newest then
                    for _, t in ipairs(tiles) do
                        if inTile(t, d.x, d.y) then
                            task.wait(0.05) -- another drop from the same break
                            return
                        end
                    end
                end
            end
        end
        task.wait()
    end
end

-- Walk to 1 drop until collected (stand on its tile; if unstandable,
-- e.g. stair shaft: stand right below and jump once). Returns: true = collected.
function Move.visitDrop(d)
    local w = Refs.World
    local s = playerState()
    if not w or not s then return false, "nopath" end
    local W = w.w
    local tx, ty = floor(d.x), floor(d.y)
    if solidAt(tx, ty) then return false, "nopath" end -- buried inside a block: cannot be touched
    local sx, sy = startNode(s)
    local goal = { [ty * W + tx] = true }
    local path = astar(sx, sy, goal, tx, ty, 0.5, false)
    if not path and ty + 1 < w.h then
        path = astar(sx, sy, { [(ty + 1) * W + tx] = true }, tx, ty + 1, 0.5, false)
    end
    if not path then path = astar(sx, sy, goal, tx, ty, 1.2, false) end
    if not path then return false, "nopath" end
    if #path > 0 then
        local ok = followPath(path)
        releaseInput()
        if not ok then return false, "nopath" end
    end
    local ping = 0.1
    pcall(function() ping = LocalPlayer:GetNetworkPing() end)
    waitNearDrops(math.clamp(0.6 + 3 * ping, 1, 2.5))
    local function left() return (d.n or 0) > 0 and table.find(Drops.list or {}, d) ~= nil end
    local cur = playerState()
    if left() and cur and cur.grounded and abs(d.x - cur.x) <= 0.9 and d.y < cur.y - 0.9 and d.y > cur.y - 2.6 then
        -- drop overhead: jump once to touch with body
        AutoInput.active = true
        AutoInput.jump = true
        task.wait(0.25)
        AutoInput.jump = false
        local t0 = os.clock()
        repeat
            task.wait(0.05)
            local c = playerState()
        until not c or c.grounded or os.clock() - t0 > 1.5
        waitNearDrops(0.5)
    end
    if left() then return false, "left" end
    return true
end

-- Sweep 1 row (body tile ry) from col xa to xb without stopping per drop:
-- drops along the way are picked up in passing, just like manual play.
function Move.walkRow(ry, xa, xb)
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then return false end
    local sx, sy = startNode(s)
    local base = ry * w.w
    local path = astar(sx, sy, { [base + xa] = true, [base + xb] = true }, xa, ry, 0.5, false)
    if not path then return false end
    local first = path[#path] and path[#path].x or sx
    local last = first == xa and xb or xa
    local ok = (#path == 0 or followPath(path)) and (last == first or execWalk(last, ry))
    releaseInput()
    return ok
end

-- Collect uncollected drops ROW BY ROW (like manual play):
--   pick closest drop (current row prioritized), sweep that row from nearest end
--   to other end nonstop. Stragglers (e.g. in stair shafts) are visited individually,
--   and stubborn drops are skipped briefly.
-- filter(d) = true: drop allowed (nil = all). maxSec = time limit (20s).
Move.FetchFail = {}
function Drops.topUpDirt(live)
    local dirt = Build.DirtRun
    if not dirt or Build.DirtRefill ~= dirt or Drops.dirtRoom(dirt.block) ~= 1 or not live() then return false end
    local now = os.clock()
    if now < (dirt.nextTopUp or 0) then return false end
    dirt.nextTopUp = now + 0.4
    local s = playerState()
    if not s or s.dead then return false end
    local cx, cy = s.x, s.y - 0.475
    local best, bestDistance
    for _, d in ipairs(Drops.list or {}) do
        if type(d) == "table" and d.id == dirt.block and type(d.y) == "number" and canTry(d, now)
            and not d.pending and not d.display then
            local dx, dy = abs(d.x - cx), abs(d.y - cy)
            local distance = dx + dy
            if dx < 0.6 and dy < 0.75 and (not bestDistance or distance < bestDistance)
                and not solidAt(floor(d.x), floor(d.y)) then
                best, bestDistance = d, distance
            end
        end
    end
    return best ~= nil and live() and takeDrop(best, true)
end

function Move.fetchDrops(live, maxDist, filter, maxSec)
    local list = Drops.list
    local w = Refs.World
    if not list or not w then return 0 end
    maxDist = maxDist or 8
    local got, t0 = 0, os.clock()
    local function want(d, now)
        if not (canTry(d, now) and d.id and type(d.y) == "number") then return false end
        if Move.FetchFail[d.uid] and now < Move.FetchFail[d.uid] then return false end
        if solidAt(floor(d.x), floor(d.y)) then -- buried inside a block: cannot be touched
            Move.FetchFail[d.uid] = now + 300
            return false
        end
        local z = Factory.Zone
        if z and not Move.NoZone and z.world == rawget(w, "name") and abs(d.x - z.x) <= 2.5 and abs(d.y - z.y) <= 2.5 then
            return false
        end
        if filter and not filter(d) then return false end
        if d.id ~= 112 and Refs.Inv then -- inventory full: skip pickup
            local okr, r = pcall(function() return Refs.Inv:room(d.id) end)
            local dirt = Build.DirtRun
            local lastDirt = dirt and Build.DirtRefill == dirt and d.id == dirt.block and Drops.dirtRoom(d.id) == 1
            if okr and type(r) == "number" and r <= 0 and not lastDirt then return false end
        end
        return true
    end
    while live() and alive() and os.clock() - t0 < (maxSec or 20) do
        local s = playerState()
        if not s or s.dead then break end
        if not s.grounded then
            task.wait(0.05)
            continue
        end
        local cx, cy = s.x, s.y - 0.475
        local now = os.clock()
        local best, bd = nil, nil
        for _, d in ipairs(list) do
            if want(d, now) then
                local dx, dy = d.x - cx, d.y - cy
                if abs(dx) <= maxDist and abs(dy) <= maxDist and (abs(dx) >= 0.6 or abs(dy) >= 0.75) then
                    local dd = dx * dx + 9 * dy * dy -- current row prioritized
                    if not bd or dd < bd then best, bd = d, dd end
                end
            end
        end
        if not best then break end
        local ry = floor(best.y)
        if best.x < 0 or ry < 0 or best.x >= w.w or ry >= w.h then
            Move.FetchFail[best.uid] = now + 30
        else
            -- Sweep one walkable span in stride. Gaps/stairs split spans.
            local left, right = floor(best.x), floor(best.x)
            local grounded = realSupport(left, ry) and openAt(left, ry)
            if grounded then
                while left > 0 and left >= cx - maxDist and openAt(left - 1, ry) and realSupport(left - 1, ry) do left -= 1 end
                while right < w.w - 1 and right <= cx + maxDist and openAt(right + 1, ry) and realSupport(right + 1, ry) do right += 1 end
            end
            local inRow, lo, hi = {}, best.x, best.x
            for _, d in ipairs(list) do
                if type(d) == "table" and type(d.x) == "number" and type(d.y) == "number"
                    and floor(d.y) == ry and d.x >= left and d.x < right + 1
                    and abs(d.x - cx) <= maxDist and want(d, now) then
                    inRow[#inRow + 1] = d
                    if d.x < lo then lo = d.x end
                    if d.x > hi then hi = d.x end
                end
            end
            local xa, xb = floor(lo), floor(hi)
            setMoveStatus(("Collect drops on row y %d (x %d-%d)"):format(ry, xa, xb))
            local ok = grounded and Move.walkRow(ry, xa, xb)
            -- pickup sent to server: wait for reply (ping) before checking leftovers
            local ping = 0.1
            pcall(function() ping = LocalPlayer:GetNetworkPing() end)
            local tw = os.clock()
            repeat
                task.wait(0.05)
                local busy = false
                for _, d in ipairs(inRow) do
                    if d.taking then
                        busy = true
                        break
                    end
                end
            until not busy or os.clock() - tw > math.clamp(0.3 + 3 * ping, 0.5, 2.5)
            got += 1
            Move.FetchTry = Move.FetchTry or {}
            for _, d in ipairs(inRow) do
                if (ok or d == best) and table.find(list, d) and want(d, os.clock()) then
                    local okv, why = Move.visitDrop(d)
                    if not okv then
                        local tries = (Move.FetchTry[d.uid] or 0) + 1
                        Move.FetchTry[d.uid] = tries
                        if why == "left" and tries < 4 then
                            Move.FetchFail[d.uid] = os.clock() + 1.5 -- already visited (late server reply / partial remainder): retry shortly
                        else
                            Move.FetchFail[d.uid] = os.clock() + 30 -- no path / still uncollected
                        end
                    else
                        Move.FetchTry[d.uid] = nil
                    end
                end
            end
        end
    end
    releaseInput()
    return got
end

local function autoBegin()
    AutoInput.active = true
    releaseInput()
    Reach = nil
    if Misc.Ghost then
        setGhost(false) -- fly disabled (triggers rollback)
        if UI.GhostToggle then pcall(function() UI.GhostToggle:Set(false) end) end
    end
end

local function autoEnd()
    if Clear.Running or Farmer.Running or Splice.Roaming or Factory.Running or Build.Running or Move.Homing
        or Vend.Running then
        return
    end
    AutoInput.active = false
    releaseInput()
end

local function blockText(useBlock, id)
    if not useBlock then return "off" end
    if not id then return "not selected" end
    local n = invCount(id)
    return itemName(id) .. " x" .. n .. (n <= 0 and " (out)" or "")
end

---------------------------------------------------------------------
-- CLEAR WORLD: clear from top row to bottom, 2 rows per pass
---------------------------------------------------------------------
-- Allowed to break? (locks, vending, displays untouched)
local function clearCanBreak(id)
    if not id or id == 0 then return false end
    local it = ItemDB[id]
    if not it then return false end
    if it.lock or it.area or it.guildLock or it.vend or it.display then return false end
    local h = (it.kind == "seed") and 20 or it.hits
    if type(h) == "number" and h > 0 then return true end
    local w = Refs.World
    return (it.staffHits and w and w.areas and w.areas.staff) and true or false
end

function Auto.worldBreakOptions(background)
    local w, counts, ids = Refs.World, {}, {}
    if not w or type(w.fg) ~= "table" then return ids, counts end
    local spawn, grid, eligible = w.spawn, w.fg, {}
    local budget = { next = os.clock() + 0.0015 }
    local sx, sy
    if spawn and (typeof(spawn) == "Vector2" or type(spawn) == "table") then sx, sy = spawn.X, spawn.Y end
    for y = 0, (w.h or 0) - 1 do
        local row = grid[y]
        for x = 0, (w.w or 0) - 1 do
            local id = row and row[x]
            if id and id ~= 0 then
                if eligible[id] == nil then
                    local item = ItemDB[id]
                    eligible[id] = item ~= nil and item.kind ~= "seed" and clearCanBreak(id) or false
                end
                if eligible[id] and not (sx == x and sy == y) then counts[id] = (counts[id] or 0) + 1 end
            end
            if background then
                Session.scanStep(budget, y * w.w + x + 1)
                if not alive() or Refs.World ~= w or w.fg ~= grid then return {}, {} end
            end
        end
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local an, bn = itemName(a):lower(), itemName(b):lower()
        return an == bn and a < b or an < bn
    end)
    return ids, counts
end

-- Break layer: fg first, then bg
local function clearLayerAt(x, y)
    local w = Refs.World
    if Clear.TargetId and (not w or w.fg ~= Clear.TargetGrid or w.name ~= Clear.TargetWorld) then return nil end
    local sp = w and w.spawn
    if sp ~= nil and (typeof(sp) == "Vector2" or type(sp) == "table") and x == sp.X and y == sp.Y then
        return nil
    end
    local fg = tileAt("fg", x, y)
    if fg == nil then return nil end
    if fg ~= 0 then
        if Clear.TargetId and fg ~= Clear.TargetId then return nil end
        if clearCanBreak(fg) then return "fg", fg end
        return nil -- neither fg nor bg can be broken
    end
    if Clear.IncludeBg and not Clear.TargetId then
        local bg = tileAt("bg", x, y)
        if bg and bg ~= 0 and clearCanBreak(bg) then return "bg", bg end
    end
    return nil
end

-- Find highest row still containing blocks
local function scanTopRow()
    local w = Refs.World
    local W, H = w.w, w.h
    local now = os.clock()
    local grid, budget = w.fg, { next = now + 0.0015 }
    for y = 0, H - 1 do
        local frow, brow = w.fg[y], w.bg[y]
        for x = 0, W - 1 do
            local fid = frow and frow[x] or 0
            local bid = brow and brow[x] or 0
            if (fid ~= 0 or (Clear.IncludeBg and bid ~= 0)) and clearLayerAt(x, y)
                and not skipped(Clear.Skip, y * W + x, now) then
                return y
            end
            Session.scanStep(budget, y * W + x + 1)
            if not Clear.Running or not alive() or Refs.World ~= w or w.fg ~= grid then return nil end
        end
    end
    return nil
end

local function countRemaining()
    local w = Refs.World
    if not w then return -1 end
    local W, H = w.w, w.h
    local n, scanned = 0, 0
    local grid, budget = w.fg, { next = os.clock() + 0.0015 }
    for y = 0, H - 1 do
        local frow, brow = w.fg[y], w.bg[y]
        for x = 0, W - 1 do
            local fid = frow and frow[x] or 0
            local bid = brow and brow[x] or 0
            if (fid ~= 0 or (Clear.IncludeBg and bid ~= 0)) and clearLayerAt(x, y) then n += 1 end
            scanned += 1
            Session.scanStep(budget, scanned)
            if not alive() or not Clear.Running or Refs.World ~= w or w.fg ~= grid then return -1 end
        end
    end
    return n
end

-- Sweep direction. Zig-zag: direction chosen once per row (from nearest end),
-- then kept until row finishes to avoid backtracking.
local function bandDir(topRow, s)
    if Clear.Sweep ~= "Zig-zag" then return 1 end
    if Clear.DirRow == topRow and Clear.Dir then return Clear.Dir end
    local w = Refs.World
    local now = os.clock()
    local minX, maxX
    for y = topRow, math.min(topRow + 1, w.h - 1) do
        for x = 0, w.w - 1 do
            if clearLayerAt(x, y) and not skipped(Clear.Skip, y * w.w + x, now) then
                if not minX or x < minX then minX = x end
                if not maxX or x > maxX then maxX = x end
            end
        end
    end
    local dir = 1
    if minX and maxX and abs(s.x - maxX) < abs(s.x - minX) then dir = -1 end
    Clear.DirRow, Clear.Dir = topRow, dir
    return dir
end

-- All targets in this row, ordered by sweep direction.
-- Unreachable tiles are skipped immediately.
local function bandTargets(top, bottom, dir, filter)
    local w = Refs.World
    local W = w.w
    local list = {}
    local now = os.clock()
    local grid, budget, visited = w.fg, { next = now + 0.0015 }, 0
    for y = top, math.min(bottom, w.h - 1) do
        for x = 0, W - 1 do
            local idx = y * W + x
            if clearLayerAt(x, y) and not skipped(Clear.Skip, idx, now) then
                if filter and not filter[idx] then
                    skipTile(Clear.Skip, idx, 60) -- across chasm / no path
                elseif canWorkAt(x, y) then
                    list[#list + 1] = { x = x, y = y, idx = idx }
                else
                    skipTile(Clear.Skip, idx, 300) -- no permission
                end
            end
            visited += 1
            Session.scanStep(budget, visited * 8)
            if not Clear.Running or not alive() or Refs.World ~= w or w.fg ~= grid then return {} end
        end
    end
    table.sort(list, function(a, b)
        if a.x ~= b.x then return a.x * dir < b.x * dir end
        return a.y < b.y
    end)
    return list
end

-- Tiles reachable from here. Current footing broken last.
local function clearInReach(s, bottom, dir)
    local w = Refs.World
    local W = w.w
    local R = punchReach() - 0.08
    local cx, cy = s.x, s.y - 0.475
    local footRow = floor(s.y + 0.01)
    local colA, colB = floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001)
    local now = os.clock()
    local list = {}
    for ty = math.max(0, floor(cy - R - 0.5)), math.min(floor(cy + R + 0.5), bottom, w.h - 1) do
        for tx = math.max(0, floor(cx - R - 0.5)), math.min(floor(cx + R + 0.5), W - 1) do
            if stateReaches(s, tx, ty, R) then
                local idx = ty * W + tx
                if not skipped(Clear.Skip, idx, now) and clearLayerAt(tx, ty) then
                    if canWorkAt(tx, ty) then
                        list[#list + 1] = {
                            x = tx, y = ty, idx = idx,
                            support = (ty == footRow and tx >= colA and tx <= colB),
                        }
                    else
                        skipTile(Clear.Skip, idx, 300)
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.support ~= b.support then return not a.support end
        if a.x ~= b.x then return a.x * dir < b.x * dir end
        return a.y < b.y
    end)
    return list
end

-- If footing is broken, how far is the fall? (nil = falls onto lava/spikes)
local function fallAfterBreak(s, x, footRow)
    local colA, colB = floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001)
    for c = colA, colB do
        if c ~= x and (solidAt(c, footRow) or platformAt(c, footRow)) then return 0 end -- still supported by another column
    end
    local w = Refs.World
    for y = footRow + 1, math.min(w.h - 1, footRow + 60) do
        if hazardAt(x, y) then return nil end
        if solidAt(x, y) or platformAt(x, y) then return y - footRow end
    end
    return 60
end

-- Punch one tile until clear (fg then bg)
local function clearBreakTile(t)
    local x, y, idx = t.x, t.y, t.idx
    local layer, id = clearLayerAt(x, y)
    if not layer then return end
    local hits, maxHits = 0, hitsNeeded(id) * 3 + 6
    while Clear.Running and alive() do
        if Clear.TargetId and raymanOn() then
            stopClear("Unequip Rayman's Fist first so other blocks aren't hit.")
            return
        end
        layer, id = clearLayerAt(x, y)
        if not layer then return end
        local r = tryBreak(x, y, not Clear.TargetId and Clear.IncludeBg, Clear.TargetId)
        if r == nil then
            skipTile(Clear.Skip, idx, 60)
            return
        end
        if r == "broke" then
            Clear.Broken += 1
            Clear.Status = "Break " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            BreakTimes[idx] = (BreakTimes[idx] or 0) + 1
            if BreakTimes[idx] > 6 then -- server keeps reverting this tile
                skipTile(Clear.Skip, idx, 120)
                return
            end
            hits = 0
            local _, nid = clearLayerAt(x, y)
            if nid then maxHits = hitsNeeded(nid) * 3 + 6 end
        else
            hits += 1
            Clear.Status = "Punch " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            if hits > maxHits then
                skipTile(Clear.Skip, idx, 45)
                return
            end
        end
        if not waitAuto(State.BreakMs) then return end
        if r == "broke" then
            local s = playerState()
            if not s or not s.grounded then return end -- fell, recheck position
        end
    end
end

local function clearBreakList(list, s0)
    local footY = floor(s0.y - 0.475)
    local R = punchReach() - 0.08
    local done = 0
    for _, t in ipairs(list) do
        if not Clear.Running or not alive() then break end
        local s = playerState()
        if not s or s.dead or not stateReaches(s, t.x, t.y, R) then break end
        if not s.grounded or floor(s.y - 0.475) ~= footY then break end
        local skipIt = false
        if t.support then
            local d = fallAfterBreak(s, t.x, floor(s.y + 0.01))
            if d == nil then
                skipIt = true
                Clear.Status = ("Skip (%d,%d): hazard underneath"):format(t.x, t.y)
            elseif d > 3 then
                -- void underneath: break from the side later
                skipIt = true
                Clear.Status = ("Skip scaffold (%d,%d): void underneath"):format(t.x, t.y)
            end
        end
        if skipIt then
            skipTile(Clear.Skip, t.idx, 20)
        else
            clearBreakTile(t)
            done += 1
        end
    end
    return done
end

local lastClearText = nil
local function updateClearStatus()
    if not UI.ClearStatus and not UI.WorldBreakStatus then return end
    local txt = "Status   : " .. (Clear.Running and "RUNNING" or "STOPPED")
        .. "\nRow      : " .. (Clear.TopRow >= 0 and (Clear.TopRow .. "-" .. (Clear.TopRow + 1)) or "-")
        .. "  | dir: " .. ((Clear.Dir == -1 and Clear.Sweep == "Zig-zag") and "right->left" or "left->right")
        .. "\nBroken   : " .. Clear.Broken .. "  | collect: " .. State.Collected
        .. "\nLeft     : " .. (Clear.Remaining >= 0 and tostring(Clear.Remaining) or "-")
        .. "  | skipped: " .. skippedCount(Clear.Skip)
        .. (Clear.TargetId and ("\nTarget   : " .. itemName(Clear.TargetId)) or "")
        .. "\nScaffold : " .. blockText(Clear.UseBlock and not Clear.TargetId, Clear.ScaffoldId) .. "  | placed: " .. Move.Placed
        .. "\nAction   : " .. Clear.Status
    if txt == lastClearText then return end
    lastClearText = txt
    task.defer(function()
        if UI.ClearStatus then pcall(function() UI.ClearStatus:SetDesc(txt) end) end
        if UI.WorldBreakStatus and Clear.TargetId then pcall(function() UI.WorldBreakStatus:SetDesc(txt) end) end
    end)
end

local function clearLoop()
    local idle, lastUi, lastCount = 0, 0, -10
    while Clear.Running and alive() do
        task.wait()
        if Clear.TargetId and (not Refs.World or Refs.World.fg ~= Clear.TargetGrid or Refs.World.name ~= Clear.TargetWorld) then
            stopClear("World changed. Auto Break Block stopped.")
            return
        end
        local now = os.clock()
        if now - lastCount > 3 then
            lastCount = now
            Clear.Remaining = countRemaining()
            if not Clear.Running or not alive() then break end
        end
        if now - lastUi > 0.5 then
            lastUi = now
            updateClearStatus()
        end
        local w = Refs.World
        local s = playerState()
        if not w or not s or s.dead then
            releaseInput()
            Clear.Status = "Waiting for character / world..."
            task.wait(0.5)
            continue
        end
        if not s.grounded then
            releaseInput() -- still airborne, wait to land
            continue
        end
        releaseInput()

        local topRow = scanTopRow()
        if not Clear.Running or not alive() then break end
        if Refs.World ~= w then continue end
        if not topRow then
            local remaining = countRemaining()
            Clear.Remaining = remaining
            if remaining == 0 then
                stopClear(Clear.TargetId and ("Done. All " .. itemName(Clear.TargetId) .. " breakable blocks are cleared.") or "World is clear!")
                return
            end
            idle += 1
            if idle >= 3 then
                stopClear(("Done. %d remaining tiles are unreachable / unbreakable"):format(remaining))
                return
            end
            Clear.Status = ("%d skipped tiles remaining, retrying (%d/3)..."):format(remaining, idle)
            updateClearStatus()
            table.clear(Clear.Skip)
            table.clear(ClearFail)
            table.clear(BadEdge)
            Reach = nil
            if not waitAuto(2000) then break end
            continue
        end

        Clear.TopRow = topRow
        local bottom = topRow + 1 -- clear 2 rows before moving down
        local dir = bandDir(topRow, s)

        -- 1) Break everything within reach
        local list = clearInReach(s, bottom, dir)
        if #list > 0 then
            if clearBreakList(list, s) > 0 then idle = 0 end
            continue
        end

        -- 2) Sweep nearby drops (body touch), then move to next section
        if (Clear.TargetId and State.WorldBreakCollect) or (not Clear.TargetId and Clear.Collect) then
            local band0 = topRow - 1
            if Move.fetchDrops(function() return Clear.Running end, 5, function(d)
                return d.y >= band0 and d.y < bottom + 2
            end, 8) > 0 then
                continue
            end
        end
        local R = punchReach() - 0.35
        local useBlock = scaffoldId() ~= nil
        local sx, sy = startNode(s)
        local band = bandTargets(topRow, bottom, dir, reachFilter(sy * w.w + sx, R, useBlock))
        if #band > 0 then
            -- Pick a spot covering punch reach width, then clear
            -- all nearby targets before choosing next spot.
            local group = { preferBatch = true }
            for _, t in ipairs(band) do
                if (t.x - band[1].x) * dir <= 2 * floor(R) then group[#group + 1] = t end
            end
            travelGroup(sx, sy, group, R, useBlock, Clear.Skip, ClearFail)
        end
    end
    releaseInput()
end

local function setClearVisual()
    if UI.ClearVisualSync then return end
    UI.ClearVisualSync = true
    if UI.ClearToggle then pcall(function() UI.ClearToggle:Set(Clear.Running and not Clear.TargetId) end) end
    if UI.WorldBreakToggle then pcall(function() UI.WorldBreakToggle:Set(Clear.Running and Clear.TargetId ~= nil) end) end
    UI.ClearVisualSync = false
end

stopClear = function(reason)
    Clear.Running = false
    autoEnd()
    setClearVisual()
    Clear.Status = reason or "Stopped"
    if reason then
        notify("Auto Clear", reason, 5)
        if not string.find(reason, "^Stopped") then Hook.send("stop", "Auto Clear stopped: " .. reason) end
    end
    updateClearStatus()
end

local function checkAutoStart()
    if not Refs.World then return "World data not found. Press 'Connect to game'" end
    if not Refs.Punch then return "Game punch function not found. Press 'Connect to game'" end
    if not Session.bindMovement(true) then return "Game movement controls (WorldMenu.isDown) not found" end
    if not playerState() then return "You are not in a world yet" end
    return nil
end

local function startClear(targetId)
    if Clear.Running then setClearVisual() return end
    if WorldFinder.Busy then notify("World Finder", "Stop hunting before running farming", 3) return end
    if AutoDrop.Busy then notify("Auto Drop", "Wait for the drop trip to finish", 3) return end
    local err = checkAutoStart()
    if err then
        notify("Auto Clear", err, 4)
        setClearVisual()
        return
    end
    if targetId ~= nil then
        if type(targetId) ~= "number" or not clearCanBreak(targetId) or (ItemDB[targetId] and ItemDB[targetId].kind == "seed") then
            notify("Auto Break Block", "Select a block type from the world first", 4)
            setClearVisual()
            return
        end
        local _, counts = Auto.worldBreakOptions()
        if not counts[targetId] then
            notify("Auto Break Block", "Selected block is not in this world. Refresh the block list.", 4)
            setClearVisual()
            return
        end
        if raymanOn() then
            notify("Auto Break Block", "Unequip Rayman's Fist first so other blocks aren't hit.", 5)
            setClearVisual()
            return
        end
    end
    if not targetId and Clear.UseBlock and (not Clear.ScaffoldId or invCount(Clear.ScaffoldId) <= 0) then
        notify("Auto Clear", "Scaffold block not selected / out: running without scaffold blocks", 5)
    end
    if Splice.Running and Splice.stop then Splice.stop("Stopped because Auto Clear started") end
    if Factory.Running and Factory.stop then Factory.stop("Stopped because Auto Clear started") end
    if Build.Running and Build.stop then Build.stop("Stopped because Auto Clear started") end
    if State.Running then stopFarm("Stopped because Auto Clear started") end
    if Farmer.Running then stopFarmer("Stopped because Auto Clear started") end
    table.clear(Clear.Skip)
    table.clear(ClearFail)
    table.clear(BadEdge)
    table.clear(BreakTimes)
    Clear.Broken = 0
    Clear.Remaining = -1
    Clear.TopRow = -1
    Clear.DirRow, Clear.Dir = nil, nil
    Clear.Status = "Starting..."
    Clear.TargetId = targetId
    Clear.TargetGrid = targetId and Refs.World.fg or nil
    Clear.TargetWorld = targetId and Refs.World.name or nil
    Clear.Running = true
    autoBegin()
    setClearVisual()
    updateClearStatus()
    task.spawn(function()
        local ok, e = pcall(clearLoop)
        if not ok then
            warn("[n4th] Auto Clear error: " .. tostring(e))
            if Clear.Running then stopClear("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- Auto Break uses Clear's traversal with a single locked foreground target.
function Auto.startWorldBreak()
    if type(State.WorldBreakId) ~= "number" then
        notify("Auto Break Block", "Select a block from the world list first", 4)
        setClearVisual()
        return
    end
    startClear(State.WorldBreakId)
    setClearVisual()
end

-- FARMER: harvest ready trees + plant seeds
---------------------------------------------------------------------
-- Tree is ready when: server time >= plant time + grow duration (matches game).
-- Seeds are planted on empty tiles above a solid block.
local function findTreeRefs()
    Refs.Trees, Refs.TreeMode, Refs.TreeP = nil, nil, nil
    -- 1) primary method (game v1159+): follow World.tileChanged -> tree store setter.
    --    Works even if world currently has no trees (empty table).
    local okS, foundS = pcall(function() return Auto.findTreesStruct and Auto.findTreesStruct() end)
    if okS and foundS == true then return true end
    Refs.Trees, Refs.TreeMode, Refs.TreeP = nil, nil, nil
    -- 2) legacy game: WorldRemotes.TreeChanged remote handler
    local ev = WorldRemotes and WorldRemotes:FindFirstChild("TreeChanged")
    if ev and ev:IsA("RemoteEvent") and getconnections then
        local ok, conns = pcall(getconnections, ev.OnClientEvent)
        if ok and type(conns) == "table" then
            for _, c in pairs(conns) do
                local okf, fn = pcall(Session.connectionFunction, c)
                if okf and type(fn) == "function" then
                    for _, u in pairs(getUpvalues(fn)) do
                        if type(u) == "table" and u ~= Refs.World and rawget(u, "fg") == nil then
                            local _, v = next(u)
                            if type(v) == "table" and type(rawget(v, "p")) == "number" then
                                Refs.Trees, Refs.TreeMode, Refs.TreeP = u, "idx", "p"
                                break
                            end
                        end
                    end
                end
                if Refs.Trees then return true end
            end
        end
    end
    -- 3) fallback: deep upvalue search (requires a world that already has trees)
    if Auto.findTreesDeep then pcall(Auto.findTreesDeep) end
    return Refs.Trees ~= nil
end

-- Does this table match tree data? Empty = allowed (world with no trees).
-- Shape = [y*W+x] -> { p = plant time (server time), f = fruit, s = spliced }
function Auto.treeTableOk(t)
    local w = Refs.World
    if type(t) ~= "table" or t == w or getmetatable(t) ~= nil or rawget(t, "fg") ~= nil then return false end
    local n = 0
    for k, v in pairs(t) do
        n += 1
        if n > 6 then break end
        if type(k) ~= "number" or type(v) ~= "table" or type(rawget(v, "p")) ~= "number" then return false end
        if w and type(w.w) == "number" and type(w.h) == "number" and (k < 0 or k >= w.w * w.h) then return false end
    end
    return true
end

-- Locate tree data via game code structure (no getgc, no remote):
--   World.tileChanged holds tree table + tree setter in upvalues.
--   Tree setter holds World + tree table + tree render table.
--   Table held by BOTH = tree table.
function Auto.findTreesStruct()
    local w = Refs.World
    if not w or not getUpvalues then return false end
    local roots = {}
    for _, name in ipairs({ "tileChanged", "treeChanged", "setTree" }) do
        local f = rawget(w, name)
        if type(f) == "function" then roots[#roots + 1] = f end
    end
    for _, root in ipairs(roots) do
        local ups = getUpvalues(root)
        local tset = {}
        for _, u in pairs(ups) do
            if type(u) == "table" and u ~= w then tset[u] = true end
        end
        for _, g in pairs(ups) do
            if type(g) == "function" then
                local gu = getUpvalues(g)
                local hasW, nT, shared = false, 0, {}
                for _, v in pairs(gu) do
                    if rawequal(v, w) then
                        hasW = true
                    elseif type(v) == "table" then
                        nT += 1
                        if tset[v] then shared[#shared + 1] = v end
                    end
                end
                -- tree setter: few upvalues (World + 2 tables), one shared with tileChanged
                if hasW and nT <= 3 and #shared == 1 and Auto.treeTableOk(shared[1]) then
                    Refs.Trees, Refs.TreeMode, Refs.TreeP = shared[1], "idx", "p"
                    return true
                end
            end
        end
        -- fallback: tileChanged table clearly holding tree data
        for t in pairs(tset) do
            if next(t) ~= nil and Auto.treeTableOk(t) and Auto.treeShape(t) == "idx" then
                Refs.Trees, Refs.TreeMode, Refs.TreeP = t, "idx", "p"
                return true
            end
        end
    end
    return false
end

-- Tree data at tile (x,y): { p = plant time (server time), s = spliced }.
-- Table layout varies by game version (see Auto.findTreesDeep).
function Auto.treeEntry(x, y)
    local t, w = Refs.Trees, Refs.World
    if not t or not w then return nil end
    local mode = Refs.TreeMode or "idx"
    local e
    if mode == "xy" then
        e = t[x .. "," .. y]
    elseif mode == "rows" then
        local r = t[y]
        e = type(r) == "table" and r[x] or nil
    else
        e = t[y * w.w + x]
    end
    if type(e) == "number" then return { p = e } end
    if type(e) ~= "table" then return nil end
    local pk = Refs.TreeP or "p"
    if pk ~= "p" then return { p = rawget(e, pk), s = rawget(e, "s") } end
    return e
end

-- Is this table tree data? Returns: mode ("idx" / "xy" / "rows"), plant time field name
function Auto.treeShape(t)
    local w = Refs.World
    if type(t) ~= "table" or not w or t == w or rawget(t, "fg") ~= nil then return nil end
    local W, H = w.w, w.h
    local okT, st = pcall(function() return workspace:GetServerTimeNow() end)
    if not okT then st = os.time() end
    local function timeKey(e)
        if type(e) == "number" then
            return (math.abs(e - st) < 86400 * 90) and "#" or nil
        end
        if type(e) ~= "table" then return nil end
        local pv = rawget(e, "p")
        if type(pv) == "number" and math.abs(pv - st) < 86400 * 90 then return "p" end
        for fk, fv in pairs(e) do
            if type(fv) == "number" and math.abs(fv - st) < 86400 * 90 then return fk end
        end
        return nil
    end
    local function seedAt(x, y)
        local row = w.fg[y]
        local id = row and row[x]
        local it = id and ItemDB[id]
        return it ~= nil and it.kind == "seed"
    end
    local checked, good, bad, mode, pk = 0, 0, 0, nil, nil
    for k, v in pairs(t) do
        checked += 1
        if checked > 10 then break end
        local x, y, e, m = nil, nil, nil, nil
        if type(k) == "number" and k % 1 == 0 and k >= 0 then
            if type(v) == "table" and k < H and timeKey(v) == nil then
                -- rows: t[y][x]
                local kx, ve = next(v)
                if type(kx) == "number" and kx >= 0 and kx < W then x, y, e, m = kx, k, ve, "rows" end
            elseif k < W * H then
                x, y, e, m = k % W, k // W, v, "idx"
            end
        elseif type(k) == "string" then
            local a, b = string.match(k, "^(%d+),(%d+)$")
            if a then x, y, e, m = tonumber(a), tonumber(b), v, "xy" end
        end
        if not x then return nil end
        if mode and mode ~= m then return nil end
        mode = m
        local tk = timeKey(e)
        if tk and seedAt(x, y) then
            good += 1
            pk = (tk == "#") and "p" or tk
        else
            bad += 1 -- stale entries (already harvested trees) may remain: small tolerance
        end
    end
    if good == 0 or bad > good then return nil end
    return mode, pk
end

-- Find tree data through game function upvalues (world remotes, World, RunService, Net). No getgc.
function Auto.findTreesDeep()
    local w = Refs.World
    if not w or not getUpvalues then return false end
    local queue, seenF, seenT, nF = {}, {}, {}, 0
    local function addFn(fn)
        if type(fn) == "function" and not seenF[fn] then queue[#queue + 1] = fn end
    end
    local function tryTable(t)
        if seenT[t] then return false end
        seenT[t] = true
        local mode, pk = Auto.treeShape(t)
        if mode then
            Refs.Trees, Refs.TreeMode, Refs.TreeP = t, mode, pk
            return true
        end
        return false
    end
    -- 1) direct World fields (tables & functions)
    for _, v in pairs(w) do
        if type(v) == "table" then
            if tryTable(v) then return true end
        elseif type(v) == "function" then
            addFn(v)
        end
    end
    -- 2) world remote handlers
    if getconnections then
        for _, ev in ipairs(WorldRemotes and WorldRemotes:GetChildren() or {}) do
            if ev:IsA("RemoteEvent") then
                local ok, conns = pcall(getconnections, ev.OnClientEvent)
                if ok and type(conns) == "table" then
                    for _, c in pairs(conns) do
                        local okf, fn = pcall(Session.connectionFunction, c)
                        if okf then addFn(fn) end
                    end
                end
            end
        end
        for _, name in ipairs({ "RenderStepped", "Heartbeat", "Stepped" }) do
            local okS, sig = pcall(function() return RunService[name] end)
            local ok, conns = pcall(getconnections, sig)
            if okS and ok and type(conns) == "table" then
                for _, c in pairs(conns) do
                    local okf, fn = pcall(Session.connectionFunction, c)
                    if okf then addFn(fn) end
                end
            end
        end
    end
    -- 3) walk upvalues (max 1500 functions)
    local i = 1
    while i <= #queue and nF < 1500 do
        local fn = queue[i]
        i += 1
        if not seenF[fn] then
            seenF[fn] = true
            nF += 1
            for _, u in pairs(getUpvalues(fn)) do
                if type(u) == "table" then
                    if tryTable(u) then return true end
                elseif type(u) == "function" then
                    addFn(u)
                end
            end
        end
    end
    return false
end

local function farmReach()
    return math.min(punchReach(), buildReach())
end

local function seedCount()
    return Farmer.SeedId and invCount(Farmer.SeedId) or 0
end

-- When this tree is ready to harvest (nil = not a tree)
local function treeReadyAt(x, y, id)
    if not Refs.Trees or not Refs.World then return nil end
    local it = ItemDB[id]
    if not (it and it.kind == "seed") then return nil end
    local t = Auto.treeEntry(x, y)
    if type(t) ~= "table" or type(t.p) ~= "number" then return nil end
    return t.p + (it.grow or 0)
end

-- Can plant seed here? (nil seedId = Farmer seed)
local function plantSpotOk(x, y, seedId)
    local w = Refs.World
    if not w or x < 0 or y < 0 or x >= w.w or y + 1 >= w.h then return false end
    if fgIdAt(x, y) ~= 0 then return false end
    local below = fgIdAt(x, y + 1)
    if below == 0 then return false end
    local it = ItemDB[below]
    if not it or it.kind == "seed" then return false end
    if not (solidAt(x, y + 1) or it.platform) then return false end
    local ok, res = pcall(function()
        if w.areas and type(w.areas.canEdit) == "function" and not w.areas.canEdit(x, y) then return false end
        if type(w.builderOk) == "function" and not w.builderOk(x, y, true) then return false end
        local sid = seedId or Farmer.SeedId
        local seed = sid and ItemDB[sid]
        if seed and type(w.needsWay) == "function" and w.needsWay(seed)
            and type(w.wayBlocked) == "function" and w.wayBlocked(x, y) then
            return false
        end
        return true
    end)
    return (not ok) or res
end

-- Harvest & plant engine shared by Farmer and Factory.
-- FC = active configuration (seed, area, speed, etc.).
local FC = nil
local function farmerCfg()
    return {
        run = function() return Farmer.Running end,
        harvest = Farmer.Harvest,
        plant = Farmer.Plant,
        seed = Farmer.SeedId,
        skip = Farmer.Skip,
        hms = Farmer.HarvestMs,
        pms = Farmer.PlantMs,
        area = nil,      -- function(x, y): allowed to harvest here?
        plantSet = nil,  -- [idx] = true: plant only on these tiles
        exclude = nil,   -- [idx] = true: do not plant on these tiles
        row = Farmer.Row,        -- plant neatly row by row
        collect = Farmer.Collect, -- collect harvest drops before continuing
        status = function(t) Farmer.Status = t end,
        onHarvest = function(id)
            Farmer.Harvested += 1
            if id then Farmer.Got[id] = true end
        end,
        onPlant = function() Farmer.Planted += 1 end,
    }
end

local function fcSeeds()
    return FC.seed and invCount(FC.seed) or 0
end

local function fcHarvestOk(x, y)
    return FC.harvest and (not FC.area or FC.area(x, y))
end

local function fcPlantOk(idx)
    if FC.plantArea then
        local w = Refs.World
        if not w or not FC.plantArea(idx % w.w, idx // w.w) then return false end
    end
    return (not FC.plantSet or FC.plantSet[idx]) and not (FC.exclude and FC.exclude[idx])
end

local function plantSeed(x, y)
    local id = FC.seed
    if not id or invCount(id) <= 0 then return false end
    if not sendSetTile("fg", x, y, id) then return false end
    if Refs.Inv then pcall(function() Refs.Inv:remove(id, 1) end) end
    FC.onPlant()
    FC.status("Plant " .. itemName(id) .. " (" .. x .. "," .. y .. ")")
    return true
end

-- Harvest & plant everything within reach from here
local function spanCollect(cx, row, span)
    if span <= 0 then return FC.run() and alive() end
    for _, tx in ipairs({ cx + span, cx - span }) do
        if not FC.run() or not alive() then return false end
        Auto.walkTo(tx, row, 10, FC.run)
    end
    return FC.run() and alive()
end

-- Panen & tanam semua yang terjangkau dari sini
local function farmerWorkInReach(s)
    local w = Refs.World
    local W = w.w
    local R = FC.plant and FC.placeReach or farmReach() - 0.08
    local cx, cy = s.x, s.y - 0.475
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local doPlant = FC.plant and fcSeeds() > 0
    local harvest, plant = {}, {}
    local bx, by = floor(s.x), floor(cy)
    for ty = math.max(0, floor(cy - R - 0.5)), math.min(floor(cy + R + 0.5), w.h - 1) do
        for tx = math.max(0, floor(cx - R - 0.5)), math.min(floor(cx + R + 0.5), W - 1) do
            if stateReaches(s, tx, ty, R) then
                local idx = ty * W + tx
                if not skipped(FC.skip, idx, now) then
                    local id = fgIdAt(tx, ty)
                    if id ~= 0 and fcHarvestOk(tx, ty) and (not FC.only or id == FC.only)
                        and (not FC.spanSet or FC.spanSet[idx]) then
                        local ra = treeReadyAt(tx, ty, id)
                        if ra and st >= ra and Move.los(bx, by, tx, ty) then
                            if canWorkAt(tx, ty) then
                                harvest[#harvest + 1] = { x = tx, y = ty, idx = idx }
                            else
                                skipTile(FC.skip, idx, 120)
                            end
                        end
                    elseif doPlant and not FC.spanX and id == 0 and fcPlantOk(idx) and (not FC.row or FC.row.y == ty)
                        and plantSpotOk(tx, ty, FC.seed) then
                        plant[#plant + 1] = { x = tx, y = ty, idx = idx }
                    end
                end
            end
        end
    end
    local function byX(a, b)
        -- Auto Rotasi selalu menyelesaikan baris paling atas dahulu.
        if FC.topDown and a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end
    table.sort(harvest, byX)
    table.sort(plant, byX)

    local done, got = 0, 0
    for _, t in ipairs(harvest) do
        if not FC.run() or not alive() then return done end
        local cur = playerState()
        if not cur or not stateReaches(cur, t.x, t.y, R) then break end
        local id = fgIdAt(t.x, t.y)
        local r = tryBreak(t.x, t.y, false, nil, FC.allowHarvest) -- pohon siap: 1 pukulan = panen
        if r == "broke" then
            FC.onHarvest(id)
            got += 1
            FC.status("Panen " .. itemName(id) .. " (" .. t.x .. "," .. t.y .. ")")
            -- Auto Rotasi: tile yang baru dipanen langsung ditanam lagi tanpa jalan
            if FC.spanX and FC.plant and fcPlantOk(t.idx) then
                plant[#plant + 1] = { x = t.x, y = t.y, idx = t.idx }
            end
        else
            skipTile(FC.skip, t.idx, 30)
        end
        done += 1
        if not waitAuto(FC.hms) then return done end
    end
    -- Auto Rotasi: panen -> tanam langsung (tanpa jalan / collect) -> baru collect
    local rotasi = FC.spanX ~= nil
    -- Mode lain: ambil hasil panen dulu sebelum pindah / tanam
    if got > 0 and FC.collect and not rotasi then
        FC.status("Ambil hasil panen...")
        task.wait(0.25) -- drop panen muncul sedikit terlambat
        if not FC.run() or not alive() then return done end
        -- susuri baris ini sampai drop terjauh (terambil sambil lewat, tanpa berhenti)
        if Move.fetchDrops(FC.run, 8, function(d) return abs(d.y - cy) <= 1.6 end, 10) > 0 then
            return done
        end
    end
    for _, t in ipairs(plant) do
        if not FC.run() or not alive() then return done end
        if fcSeeds() <= 0 then break end
        local cur = playerState()
        if not cur or not stateReaches(cur, t.x, t.y, R) then
            if rotasi then break end
            return done
        end
        if fgIdAt(t.x, t.y) == 0 and (not rotasi or plantSpotOk(t.x, t.y, FC.seed)) then
            if not plantSeed(t.x, t.y) then break end
            done += 1
            if not waitAuto(FC.pms) then return done end
        end
    end
    -- Collect: hanya sejauh area pukul panen (kanan N tile, lalu kiri N tile)
    if rotasi and got > 0 and FC.collect then
        FC.status("Collect kanan " .. FC.collectSpan .. " & kiri " .. FC.collectSpan .. " tile...")
        task.wait(0.25) -- drop panen muncul sedikit terlambat
        if not FC.run() or not alive() then return done end
        spanCollect(FC.spanX, FC.spanRow or floor(cy), FC.collectSpan)
    end
    return done
end

-- Cari target + kapan pohon berikutnya siap.
--   Panen : pohon siap terdekat (didahulukan).
--   Tanam : rapi per baris. Selesaikan 1 baris dulu (baris yang sedang dikerjakan,
--           atau baris terdekat dengan karakter), dari tile paling kiri ke kanan.
local function farmerScan(px, py, maxN, filter)
    local w = Refs.World
    local W, H = w.w, w.h
    local best = {}
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local nextReady = nil
    local doPlant = FC.plant and fcSeeds() > 0
    local rows = {} -- [y] = list of plant spots on that row
    local scanned = 0
    for y = 0, H - 1 do
        local frow, below = w.fg[y], w.fg[y + 1]
        for x = 0, W - 1 do
            local id = frow and frow[x] or 0
            if id ~= 0 then
                if fcHarvestOk(x, y) and (not FC.only or id == FC.only) then
                    local ra = treeReadyAt(x, y, id)
                    if ra and st >= ra then
                        local idx = y * W + x
                        if not skipped(FC.skip, idx, now) then
                            if filter and not filter[idx] then
                                skipTile(FC.skip, idx, 60)
                            else
                                local dx, dy = x - px, (y - py) * 1.3
                                local d = dx * dx + dy * dy
                                if #best < maxN or d < best[#best].d then
                                    if canWorkAt(x, y) then
                                        local pos = #best + 1
                                        while pos > 1 and best[pos - 1].d > d do pos -= 1 end
                                        table.insert(best, pos, { x = x, y = y, idx = idx, d = d, kind = "harvest" })
                                        if #best > maxN then best[#best] = nil end
                                    else
                                        skipTile(FC.skip, idx, 120)
                                    end
                                end
                            end
                        end
                    elseif ra and (not nextReady or ra - st < nextReady) then
                        nextReady = ra - st
                    end
                end
            elseif doPlant then
                local b = below and below[x] or 0
                local idx = y * W + x
                if b ~= 0 and fcPlantOk(idx) and not skipped(FC.skip, idx, now) then
                    if filter and not filter[idx] then
                        skipTile(FC.skip, idx, 60)
                    else
                        local r = rows[y]
                        if not r then
                            r = {}
                            rows[y] = r
                        end
                        r[#r + 1] = { x = x, y = y, idx = idx, kind = "plant" }
                    end
                end
            end
        end
        scanned += W
        if scanned >= 6000 then
            scanned = 0
            task.wait()
            if not FC.run() or not alive() then break end
        end
    end
    if #best > 0 or not doPlant then return best, nextReady end

    -- neat planting: active row first, then nearest row
    local lock = FC.row and FC.row.y
    local order = {}
    for y in pairs(rows) do order[#order + 1] = y end
    local function rowKey(y) return (y == lock) and -1 or math.abs(y - py) end
    table.sort(order, function(a, b)
        local ka, kb = rowKey(a), rowKey(b)
        if ka ~= kb then return ka < kb end
        return a < b
    end)
    for _, y in ipairs(order) do
        local list = rows[y]
        table.sort(list, function(a, b)
            if FC.bulkPlant then
                local da, db = abs(a.x - px), abs(b.x - px)
                if da ~= db then return da < db end
            end
            return a.x < b.x
        end)
        for _, t in ipairs(list) do
            if plantSpotOk(t.x, t.y, FC.seed) then
                if FC.row then FC.row.y = y end
                if not FC.bulkPlant then return { t }, nextReady end
                best[#best + 1] = t
                if #best >= maxN then break end
            else
                skipTile(FC.skip, t.idx, 120)
            end
        end
        if #best > 0 then return best, nextReady end
    end
    if FC.row then FC.row.y = nil end
    return best, nextReady
end

local lastFarmerText = nil
local function updateFarmerStatus()
    if Refs.World and not Refs.Trees and os.clock() >= (Auto.nextTreeScan or 0) then
        Auto.nextTreeScan = os.clock() + 15
        pcall(findTreeRefs)
    end
    if not UI.FarmerStatus then return end
    local seed = Farmer.SeedId
    local txt = "Status  : " .. (Farmer.Running and "RUNNING" or "STOPPED")
        .. "\nHarvest : " .. Farmer.Harvested .. "  | plant: " .. Farmer.Planted .. "  | collect: " .. State.Collected
        .. "\nSeed    : " .. (seed and (itemName(seed) .. " x" .. invCount(seed)) or "-")
        .. "\nTrees   : " .. (Refs.Trees and "readable" or "NOT readable (harvest off)")
        .. "\nScaffold: " .. blockText(Farmer.UseBlock, Farmer.ScaffoldId)
        .. "\nDrop    : " .. ((Factory.pointSet and Factory.pointSet()) and ("auto when >= " .. Farmer.DropAt
            .. " | dropped " .. Farmer.Dropped) or "drop point not set")
        .. "\nAction  : " .. Farmer.Status
    if txt == lastFarmerText then return end
    lastFarmerText = txt
    task.defer(function()
        pcall(function() UI.FarmerStatus:SetDesc(txt) end)
    end)
end

-- 1 harvest/plant engine step (using FC):
--   work what is within reach, or walk to nearest target.
-- Returns: "work" | "move" | "wait" | "idle" (+ seconds to next ready tree)
-- Stuck in mid-air / block edge (character idle): nudge sideways slightly
function Move.airCheck(s)
    if s.grounded then
        Move.AirAt = nil
        return
    end
    if not Move.AirAt then
        Move.AirAt = os.clock()
    elseif os.clock() - Move.AirAt > 3 then
        Move.AirAt = nil
        local right = (s.facing or 1) < 0 -- in the opposite direction
        AutoInput.active = true
        AutoInput.right, AutoInput.left = right, not right
        task.wait(0.2)
        AutoInput.right, AutoInput.left = false, false
    end
end

local function spanCenter(span)
    local w = Refs.World
    if not w then return nil end
    local st, now = workspace:GetServerTimeNow(), os.clock()
    for y = 0, w.h - 1 do
        local frow = w.fg[y]
        if frow then
            local ready, minX, maxX = {}, nil, nil
            for x = 0, w.w - 1 do
                local id = frow[x] or 0
                if id ~= 0 and fcHarvestOk(x, y) and (not FC.only or id == FC.only) then
                    local ra = treeReadyAt(x, y, id)
                    local idx = y * w.w + x
                    if ra and st >= ra and not skipped(FC.skip, idx, now) and canWorkAt(x, y) then
                        ready[x] = true
                        minX = minX or x
                        maxX = x
                    end
                end
            end
            if minX then
                local bestX, bestN = nil, 0
                for sx = math.max(0, minX - span), math.min(w.w - 1, maxX + span) do
                    if not solidAt(sx, y) then
                        local n = ready[sx] and 1 or 0 -- tile tengah ikut dipukul
                        for d = 1, span do
                            if ready[sx - d] then n += 1 end
                            if ready[sx + d] then n += 1 end
                        end
                        if n > bestN then bestX, bestN = sx, n end
                    end
                end
                if bestX then
                    local set, tiles = {}, {}
                    for d = -span, span do
                        local x = bestX + d
                        if ready[x] then
                            local idx = y * w.w + x
                            set[idx] = true
                            tiles[#tiles + 1] = { x = x, y = y, idx = idx, kind = "harvest" }
                        end
                    end
                    return bestX, y, set, tiles
                end
            end
        end
    end
    return nil
end

-- Langkah panen rotasi: berdiri di tengah, pukul panen 2 kiri + tengah + 2 kanan, lalu langsung tanam & collect
-- Drop floating yang diambil: hanya block yang kita panen (block dari seed pohon yang
-- dipanen) atau block yang kita break (block Auto Rotasi). Seed & item lain dibiarkan.
local function ownBlockDrop(d)
    if type(d) ~= "table" then return false end
    local it = ItemDB[d.id]
    if not it or it.kind == "seed" then return false end
    if d.id == Factory.BlockId then return true end
    for sid in pairs(Factory.Got) do
        if d.id == sid - 1 then return true end
    end
    return false
end

local function spanFieldStep(s)
    -- Ada block floating hasil panen / break kita di sekitar: ambil dulu (seed & item lain dibiarkan)
    if Move.fetchDrops(FC.run, 15, ownBlockDrop, 12) > 0 then return "work" end
    local cx, row, set, tiles = spanCenter(FC.span)
    if not cx then return "idle" end
    FC.spanSet, FC.spanX, FC.spanRow = set, cx, row
    local hx, hy = startNode(s)
    if hx == cx and hy == row then
        if farmerWorkInReach(s) > 0 then return "work" end
        -- tidak ada yang bisa dipukul dari sini: lewati sebentar agar tidak berputar
        for _, t in ipairs(tiles) do skipTile(FC.skip, t.idx, 30) end
        return "idle"
    end
    -- belum di posisi tengah: jalan ke sana dulu (setelah collect selalu cari tengah lagi)
    FC.status(("Jalan ke posisi tengah (%d,%d)"):format(cx, row))
    if not Auto.walkTo(cx, row, 20, FC.run) then
        for _, t in ipairs(tiles) do skipTile(FC.skip, t.idx, 30) end
        return "idle"
    end
    return "move"
end

local function fieldStep()
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then
        releaseInput()
        task.wait(0.5)
        return "wait"
    end
    if not s.grounded then
        releaseInput()
        Move.airCheck(s)
        task.wait()
        return "wait"
    end
    Move.AirAt = nil
    releaseInput()
    if FC.span then return spanFieldStep(s) end
    if farmerWorkInReach(s) > 0 then return "work" end
    local R = FC.plant and FC.placeReach or farmReach() - 0.35
    local useBlock = scaffoldId() ~= nil
    local sx, sy = startNode(s)
    local px, py = floor(s.x), floor(s.y - 0.475)
    local targets, nextReady = farmerScan(px, py, 8, reachFilter(sy * w.w + sx, R, useBlock))
    if not FC.run() or not alive() then return "wait" end
    if #targets == 0 then return "idle", nextReady end
    targets.los = targets[1].kind == "harvest" -- panen: berdiri di baris pohon (drop terambil)
    travelGroup(sx, sy, targets, R, useBlock, FC.skip, FarmerFail)
    return "move"
end

-- Item hasil panen yang sudah hampir penuh: seed pohon & block-nya
function Farmer.dropList()
    local out = {}
    for sid in pairs(Farmer.Got) do
        for _, id in ipairs({ sid, sid - 1 }) do
            local it = ItemDB[id]
            if it and (id == sid or it.kind ~= "seed") and not (AutoDrop.On and table.find(AutoDrop.Items, id)) then
                local n = invCount(id)
                local keep = (id == Farmer.SeedId) and Farmer.Keep or 0
                if n >= Farmer.DropAt and n > keep then
                    out[#out + 1] = { id = id, n = n - keep }
                end
            end
        end
    end
    return out
end

local function farmerLoop()
    local lastUi = 0
    while Farmer.Running and alive() do
        task.wait()
        if os.clock() - lastUi > 0.5 then
            lastUi = os.clock()
            updateFarmerStatus()
        end
        FC = farmerCfg()
        if not Refs.World then
            Farmer.Status = "Waiting for character / world..."
            task.wait(0.5)
            continue
        end
        -- inventory almost full -> drop harvest items at drop point
        if Factory.pointSet and Factory.pointSet() and Auto.dropTrip and os.clock() >= (Farmer.DropOffUntil or 0)
            and os.clock() - (Farmer.DropCheck or 0) > 2 then
            Farmer.DropCheck = os.clock()
            local items = Farmer.dropList()
            if #items > 0 then
                releaseInput()
                local ok, why = Auto.dropTrip(items, function() return Farmer.Running and alive() end,
                    function(t) Farmer.Status = t end)
                for _, it in ipairs(items) do Farmer.Dropped += it.got or 0 end
                if why == "home" then
                    stopFarmer("Failed to return to farmer world")
                    break
                end
                if not ok then Farmer.DropOffUntil = os.clock() + ((why == "nopoint") and 60 or 120) end
                continue
            end
        end
        local r, nextReady = fieldStep()
        if r == "wait" and not playerState() then
            Farmer.Status = "Waiting for character / world..."
        end
        if r == "idle" then
            local parts = {}
            if Farmer.Harvest then
                parts[#parts + 1] = nextReady and ("tree ready ~" .. math.ceil(nextReady) .. " s") or "no trees"
            end
            if Farmer.Plant then
                parts[#parts + 1] = (seedCount() <= 0) and "out of seeds / none selected" or "nowhere to plant"
            end
            Farmer.Status = "Waiting: " .. table.concat(parts, ", ")
            if not waitAuto(1000) then break end
        end
    end
    releaseInput()
end

local function setFarmerVisual()
    if UI.FarmerToggle then pcall(function() UI.FarmerToggle:Set(Farmer.Running) end) end
end

stopFarmer = function(reason)
    Farmer.Running = false
    autoEnd()
    setFarmerVisual()
    Farmer.Status = reason or "Stopped"
    if reason then
        notify("Farmer", reason, 5)
        if not string.find(reason, "^Stopped") then Hook.send("stop", "Farmer stopped: " .. reason) end
    end
    updateFarmerStatus()
end

local function startFarmer()
    if Farmer.Running then return end
    if WorldFinder.Busy then notify("World Finder", "Stop hunting before running farming", 3) return end
    if AutoDrop.Busy then notify("Auto Drop", "Wait for the drop trip to finish", 3) return end
    local err = checkAutoStart()
    if not err and not Farmer.Harvest and not Farmer.Plant then
        err = "Enable Auto Harvest or Auto Plant"
    end
    if not err and not Farmer.Harvest and not Farmer.SeedId then
        err = "Select a seed first for Auto Plant"
    end
    if err then
        notify("Farmer", err, 4)
        setFarmerVisual()
        return
    end
    if Farmer.Harvest and not Refs.Trees and not findTreeRefs() then
        notify("Farmer", "Tree data not found: Auto Harvest cannot check ready trees", 5)
    end
    if Splice.Running and Splice.stop then Splice.stop("Stopped because Farmer started") end
    if Factory.Running and Factory.stop then Factory.stop("Stopped because Farmer started") end
    if Build.Running and Build.stop then Build.stop("Stopped because Farmer started") end
    if State.Running then stopFarm("Stopped because Farmer started") end
    if Clear.Running then stopClear("Stopped because Farmer started") end
    table.clear(Farmer.Skip)
    table.clear(FarmerFail)
    table.clear(BadEdge)
    table.clear(Farmer.Row)
    Farmer.DropOffUntil = 0
    Farmer.Status = "Starting..."
    Farmer.Running = true
    autoBegin()
    setFarmerVisual()
    updateFarmerStatus()
    task.spawn(function()
        local ok, e = pcall(farmerLoop)
        if not ok then
            warn("[n4th] Farmer error: " .. tostring(e))
            if Farmer.Running then stopFarmer("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- ROAM SPLICE: plant Seed A + splice Seed B across the whole world
---------------------------------------------------------------------
-- How it works (same as Farmer, but action is splice):
--   1. Process all tiles within reach from current position:
--        empty tile (above solid block) -> plant A, then splice B onto that A tree
--        unspliced A tree                 -> splice B
--   2. When nothing else is in reach: find closest tile and walk there using A*.
--   Fully grown trees cannot be spliced (game rule), so skip them.
local SpliceFail = {}

local function spliceInv()
    return invCount(Splice.A or 0), invCount(Splice.B or 0)
end

-- Work type at this tile: "plant" | "splice" | nil
local function spliceKind(x, y, st)
    local A = Splice.A
    local id = fgIdAt(x, y)
    if id == 0 then
        local a, b = spliceInv()
        if a > 0 and b > 0 and plantSpotOk(x, y, A) then return "plant" end
        return nil
    end
    if id ~= A then return nil end
    local t = Auto.treeEntry(x, y)
    if type(t) == "table" and t.s == true then return nil end -- already spliced
    local ra = treeReadyAt(x, y, id)
    if ra and st >= ra then return nil end -- already ready to harvest
    local _, b = spliceInv()
    if b > 0 and canWorkAt(x, y) then return "splice" end
    return nil
end

local function spliceOnce(x, y)
    local w = Refs.World
    local f = w and rawget(w, "spliceSeed")
    if type(f) ~= "function" then return false, "game splice function not found" end
    local ok, made = pcall(f, x, y, Splice.B)
    if ok and made and ItemDB[made] then
        pcall(function() Refs.Inv:remove(Splice.B, 1) end)
        if Refs.SetTile then pcall(Refs.SetTile, "fg", x, y, made, true) end -- update display immediately
        Splice.Made += 1
        Splice.Status = ("Spliced into %s (%d,%d)"):format(itemName(made), x, y)
        return true
    end
    return false, "rejected by server"
end

-- Process 1 tile: plant A (if empty) then splice B
local function spliceTile(t)
    local A = Splice.A
    if fgIdAt(t.x, t.y) == 0 then
        if invCount(A) <= 0 then return false end
        sendSetTile("fg", t.x, t.y, A)
        pcall(function() Refs.Inv:remove(A, 1) end)
        Splice.Planted += 1
        Splice.Status = ("Plant %s (%d,%d)"):format(itemName(A), t.x, t.y)
        if not waitAuto(Splice.Ms) then return false end
    end
    if fgIdAt(t.x, t.y) ~= A then
        skipTile(Splice.Skip, t.idx, 30)
        return true
    end
    local ok, why = spliceOnce(t.x, t.y)
    if not ok then
        SpliceFail[t.idx] = (SpliceFail[t.idx] or 0) + 1
        skipTile(Splice.Skip, t.idx, 60)
        Splice.Status = ("Failed to splice (%d,%d): %s"):format(t.x, t.y, tostring(why))
    end
    waitAuto(Splice.Ms)
    return true
end

local function spliceWorkInReach(s)
    local w = Refs.World
    local W = w.w
    local R = farmReach() - 0.08
    local cx, cy = s.x, s.y - 0.475
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local list = {}
    for ty = math.max(0, floor(cy - R - 0.5)), math.min(floor(cy + R + 0.5), w.h - 1) do
        for tx = math.max(0, floor(cx - R - 0.5)), math.min(floor(cx + R + 0.5), W - 1) do
            if stateReaches(s, tx, ty, R) then
                local idx = ty * W + tx
                if Splice.Row.y == ty and not skipped(Splice.Skip, idx, now) and spliceKind(tx, ty, st) then
                    list[#list + 1] = { x = tx, y = ty, idx = idx }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local done = 0
    for _, t in ipairs(list) do
        if not Splice.Roaming or not alive() then return done end
        local cur = playerState()
        if not cur or not stateReaches(cur, t.x, t.y, R) then return done end
        if not spliceTile(t) then return done end
        done += 1
    end
    return done
end

-- Next work tile: neatly per row (current / nearest row),
-- from left to right
local function spliceScan(px, py, maxN, filter)
    local w = Refs.World
    local W, H = w.w, w.h
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local rows = {} -- [y] = leftmost work tile in that row
    local scanned = 0
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            local idx = y * W + x
            if not rows[y] and not skipped(Splice.Skip, idx, now) and spliceKind(x, y, st) then
                if filter and not filter[idx] then
                    skipTile(Splice.Skip, idx, 60)
                else
                    rows[y] = { x = x, y = y, idx = idx }
                end
            end
        end
        scanned += W
        if scanned > 6000 then
            scanned = 0
            task.wait()
            if not Splice.Roaming then return {} end
        end
    end
    local lock, pick, pk = Splice.Row.y, nil, nil
    for y, t in pairs(rows) do
        local k = (y == lock) and -1 or math.abs(y - py)
        if not pick or k < pk or (k == pk and y < pick.y) then pick, pk = t, k end
    end
    Splice.Row.y = pick and pick.y or nil
    return pick and { pick } or {}
end

local function spliceRoamLoop(runId)
    while Splice.Roaming and Splice.Running and alive() and Splice.RunId == runId do
        task.wait()
        local w = Refs.World
        local s = playerState()
        if not w or not s or s.dead then
            releaseInput()
            Splice.Status = "Waiting for character / world..."
            task.wait(0.5)
            continue
        end
        if not s.grounded then
            releaseInput()
            continue
        end
        releaseInput()
        local a, b = spliceInv()
        if b <= 0 then
            if Splice.stop then Splice.stop("Out of seeds") end
            break
        end
        -- 1) process everything in reach
        if spliceWorkInReach(s) > 0 then continue end
        -- 2) walk to closest tile
        local R = farmReach() - 0.35
        local sx, sy = startNode(s)
        local px, py = floor(s.x), floor(s.y - 0.475)
        local targets = spliceScan(px, py, 8, reachFilter(sy * w.w + sx, R, false))
        if not Splice.Roaming or not alive() then break end
        if #targets == 0 then
            Splice.Status = (a <= 0) and "Out of Seed A, no Seed A trees left to splice"
                or "Waiting: no empty spot / tree to splice"
            if not waitAuto(1000) then break end
            continue
        end
        travelGroup(sx, sy, targets, R, false, Splice.Skip, SpliceFail)
    end
    releaseInput()
end

local function startSpliceRoam()
    if not Session.bindMovement(true) then return "Game movement controls (WorldMenu.isDown) not found" end
    table.clear(Splice.Row)
    if not playerState() then return "You are not in a world yet" end
    if not Refs.Trees then findTreeRefs() end
    table.clear(Splice.Skip)
    table.clear(SpliceFail)
    table.clear(BadEdge)
    Splice.Roaming = true
    autoBegin()
    local id = Splice.RunId
    task.spawn(function()
        local ok, e = pcall(spliceRoamLoop, id)
        if not ok then
            warn("[n4th] Splice error: " .. tostring(e))
            if Splice.Running and Splice.stop then Splice.stop("Error: " .. tostring(e)) end
        end
    end)
    return nil
end

local function stopSpliceRoam()
    Splice.Roaming = false
    autoEnd()
    releaseInput()
end

-- Walk to 1 specific tile (used by Guard: return to Auto Farm position).
-- Uses the same A*, without placing scaffolds.
local function walkTo(tx, ty, maxSec, live, makeRoute)
    local w = Refs.World
    if not w or not OrigIsDown then return false end
    if tx < 0 or ty < 0 or tx >= w.w or ty >= w.h then return false end
    local grid = w.fg
    Move.Homing = true
    Move.HomingLive = live
    autoBegin()
    local badEdges = {}
    local goal = { [ty * w.w + tx] = true, badEdges = badEdges, live = live }
    local t0, ok = os.clock(), false
    local misses = 0
    while alive() and Move.Homing and (not live or live()) and Refs.World == w and w.fg == grid
        and os.clock() - t0 < (maxSec or 30) do
        local s = playerState()
        if not s or s.dead or not s.grounded then
            task.wait(0.15)
            continue
        end
        local sx, sy = startNode(s)
        local route = makeRoute and makeRoute()
        if route then
            route.badEdges, route.live = badEdges, live
            Move.HomingRoute = route
        end
        if sx == tx and sy == ty and s.grounded then
            if not route then
                ok = true
                break
            end
            if floor(s.x) == tx and route.safe(s, true) then
                if abs(s.vx or 0) < 2 then ok = true break end
                releaseInput()
                task.wait(0.12)
                continue
            end
            -- startNode may choose footing next to character position.
            if route.point(tx, ty) and execWalk(tx, ty) then ok = true break end
        end
        local path
        if not route or route.point(tx, ty) then path = astar(sx, sy, goal, tx, ty, 0.5, false, route) end
        if not path then
            if not route and not next(badEdges) then break end
            misses += 1
            if misses >= 3 then break end
            -- Retry once position / drops change, ignoring prior farming failure history.
            table.clear(badEdges)
        elseif #path == 0 then
            if not route or (floor(s.x) == tx and route.safe(s, true)) then
                ok = true
                break
            elseif route.point(tx, ty) and execWalk(tx, ty) then
                ok = true
                break
            end
            misses += 1
            if misses >= 3 then break end
            table.clear(badEdges)
        elseif #path > 0 then
            misses = 0
            followPath(path, badEdges)
        end
        releaseInput()
        task.wait(misses > 0 and 0.25 or 0.12)
    end
    Move.Homing, Move.HomingLive, Move.HomingRoute = false, nil, nil
    autoEnd()
    return ok
end

---------------------------------------------------------------------
-- LAND: farm world layout
---------------------------------------------------------------------
-- Block rows from top Y downward, always leaving 1 empty tile between (trees & walkway).
-- Automatic row count: descends through soil down to bedrock. If bedrock lands on a land
-- row, bedrock serves as the last row floor (soil directly above bedrock is still dug).
-- (soil in row gaps is dug by Build Land; soil on land rows is kept as the land floor).
-- Both row ends form alternating stairs (see landCols).
-- Result is briefly cached (called very frequently by Factory / status).
local function landRows(bounds)
    local w = Refs.World
    if not w then return {} end
    bounds = bounds or Land
    local x0 = math.clamp(math.floor(math.min(bounds.X0, bounds.X1)), 0, w.w - 1)
    local x1 = math.clamp(math.floor(math.max(bounds.X0, bounds.X1)), 0, w.w - 1)
    local y0 = math.max(1, math.floor(bounds.Y0))
    local y1 = (bounds.Y1 and bounds.Y1 >= 1) and math.min(bounds.Y1, w.h - 2) or w.h - 2
    local c = Land.Cache
    local now = os.clock()
    if c and c.w == w and c.x0 == x0 and c.x1 == x1 and c.y0 == y0 and c.y1 == y1 and now - c.at < 2 then
        return c.rows
    end
    local rows = {}
    local span = x1 - x0 + 1
    -- unbreakable blocks (bedrock etc.)
    local function hard(x, y)
        local id = fgIdAt(x, y)
        if id == 0 then return false end
        local it = ItemDB[id]
        return it ~= nil and it.solid == true and not canBreak(id)
    end
    local y = y0
    while y <= y1 and #rows < 40 do
        local hg, hr = 0, 0
        for x = x0, x1 do
            if hard(x, y - 1) then hg += 1 end
            if hard(x, y) then hr += 1 end
        end
        if hg * 2 > span then break end -- gap hits bedrock: stop
        rows[#rows + 1] = y
        if hr * 2 > span then break end -- this row is bedrock: use as bottommost floor
        y += 2
    end
    Land.Cache = { w = w, x0 = x0, x1 = x1, y0 = y0, y1 = y1, at = now, rows = rows }
    return rows
end

-- Is land tile already built? (any solid block, not tree / lava / spikes)
function Build.done(x, y)
    local id = fgIdAt(x, y)
    if id == 0 then return false end
    local it = ItemDB[id]
    if not it or it.kind == "seed" or not it.solid then return false end
    return not (it.deadly or it.hurts or it.laser)
end

-- Block columns for row k (0 = topmost). 2-column stairs on LEFT and RIGHT:
--   rows 1, 3, 5.. : x0+1 .. x1-1              (cols x0 & x1 open)
--   rows 2, 4, 6.. : x0, x0+2 .. x1-2, x1      (cols x0+1 & x1-1 open)
-- From either end you can descend (drop 2 tiles onto the step below)
-- and ascend (jump 2 tiles), alternating like stairs.
local function landCols(k, x0, x1)
    local w = Refs.World
    x0 = x0 or math.clamp(math.floor(math.min(Land.X0, Land.X1)), 0, w.w - 1)
    x1 = x1 or math.clamp(math.floor(math.max(Land.X0, Land.X1)), 0, w.w - 1)
    local cols = {}
    if x1 - x0 < 4 then -- too narrow for stairs
        for x = x0, x1 do cols[#cols + 1] = x end
    elseif k % 2 == 0 then
        for x = x0 + 1, x1 - 1 do cols[#cols + 1] = x end
    else
        cols[#cols + 1] = x0
        for x = x0 + 2, x1 - 2 do cols[#cols + 1] = x end
        cols[#cols + 1] = x1
    end
    return cols
end

local function inLandRect(x, y)
    local rows = landRows()
    if #rows == 0 then return false end
    local x0 = math.min(Land.X0, Land.X1)
    local x1 = math.max(Land.X0, Land.X1)
    return x >= x0 and x <= x1 and y >= rows[1] - 1 and y <= rows[#rows]
end

-- Land block tiles: [idx] = true
local function landBlockSet(P)
    local set = {}
    for k, y in ipairs(P.rows) do
        for _, x in ipairs(P.cols[k]) do set[y * P.W + x] = true end
    end
    return set
end

-- Land plant tiles (above already-placed blocks): [idx] = true
local function landPlantSet()
    local set = {}
    local w = Refs.World
    if not w then return set end
    for k, y in ipairs(landRows()) do
        for _, x in ipairs(landCols(k - 1)) do
            if fgIdAt(x, y) ~= 0 and y - 1 >= 0 then set[(y - 1) * w.w + x] = true end
        end
    end
    return set
end

-- Calculate required land blocks (+ remaining tiles to dig)
local function landInfo(P, carve)
    local info = { rows = 0, total = 0, need = 0, done = 0, blocked = 0, carve = 0 }
    local w = Refs.World
    if not w then return info end
    P = P or Build.plan()
    if not P then return info end
    local rows = P.rows
    info.rows = #rows
    if P.dirt and P.placeK and P.placeK > 0 then
        info.placeTop, info.placeBottom = rows[1], rows[P.placeK]
    end
    for k = 1, P.placeK or #rows do
        local y = rows[k]
        for _, x in ipairs(P.cols[k]) do
            info.total += 1
            if Build.done(x, y) then
                info.done += 1
            else
                info.need += 1
                if fgIdAt(x, y) ~= 0 then info.blocked += 1 end -- tree / lava etc.: break first then place
            end
        end
    end
    info.carve = #(carve or Build.carveList(P))
    return info
end

-- Seed <-> block (seed is usually block id + 1, except special items with seedId)
local function seedOfBlock(block)
    local it = block and ItemDB[block]
    if not it then return nil end
    local sid = it.seedId or (block + 1)
    local sd = ItemDB[sid]
    if sd and sd.kind == "seed" then return sid end
    return nil
end

local function blockOfSeed(seed)
    if not seed then return nil end
    local b = seed - 1
    local it = ItemDB[b]
    if it and it.kind ~= "seed" and (it.seedId == nil or it.seedId == seed) then return b end
    return nil
end

local function readyTreeCount(whole, only, plan)
    local w = Refs.World
    if not w then return 0 end
    local st = workspace:GetServerTimeNow()
    local x0, x1, y0, y1 = 0, w.w - 1, 0, w.h - 1
    if plan then
        x0, x1, y0, y1 = plan.x0, plan.x1, plan.rows[1] - 1, plan.rows[plan.K]
    elseif not whole then
        local rows = landRows()
        if #rows == 0 then return 0 end
        x0 = math.max(0, math.min(Land.X0, Land.X1))
        x1 = math.min(w.w - 1, math.max(Land.X0, Land.X1))
        y0, y1 = math.max(0, rows[1] - 1), rows[#rows]
    end
    local n, nxt = 0, nil
    for y = y0, y1 do
        for x = x0, x1 do
            local id = fgIdAt(x, y)
            if id ~= 0 and (not only or id == only) then
                local ra = treeReadyAt(x, y, id)
                if ra then
                    if st >= ra then
                        n += 1
                    elseif not nxt or ra - st < nxt then
                        nxt = ra - st
                    end
                end
            end
        end
    end
    return n, nxt
end

---------------------------------------------------------------------
-- FACTORY
---------------------------------------------------------------------
-- Phases (looping continuously):
--   HARVEST : harvest all ready trees on land (stop if block / seed nears 200)
--   PLANT   : plant seeds on all empty land tiles
--   BREAK   : walk to break spot, Auto Farm (place + break) on factory tiles until blocks RUN OUT
--             (no mid-break tree checks; stops only to drop seeds / full bag / stuck)
--   WAIT    : wait for trees to grow, then return to HARVEST
--   Whenever seed >= drop threshold -> go drop (seed - keep), then return.
-- Max inventory is 200 per item, so every phase guards against overflow.
-- Drops landed at the drop spot are excluded from collection.
local BOOT_SEEDS = 10 -- (produce mode) this many seeds suffice to start planting
local CAP = 190       -- safe item count limit (max 200 per item)

local function factoryCfg(o, harvest, plant)
    local plantSet, area = nil, nil
    if not o.whole then
        plantSet = landPlantSet()
        area = inLandRect
    end
    return {
        run = o.live,
        harvest = harvest,
        span = harvest and Factory.SideTiles or nil,      -- panen: N tile kiri + N tile kanan dari posisi berdiri
        collectSpan = harvest and Factory.CollectDist or nil, -- collect: kanan N & kiri N tile
        plant = plant and invCount(o.seed) > 0,
        seed = o.seed,
        skip = Factory.Skip,
        hms = Farmer.HarvestMs,
        pms = Farmer.PlantMs,
        area = area,
        plantSet = plantSet,
        exclude = o.exclude,
        row = Factory.Row,
        topDown = true,
        collect = true,
        status = function(t) Factory.Status = t end,
        onHarvest = function(id)
            Factory.Harvested += 1
            if id then Factory.Got[id] = true end
        end,
        onPlant = function() Factory.Planted += 1 end,
    }
end

-- Break block di posisi Auto Rotasi (pakai Auto Farm dengan tile & block Auto Rotasi)
local function factoryBreak(o)
    if os.clock() < (Factory.BreakFailUntil or 0) then return false end
    local s = playerState()
    if not s then return false end
    local hx, hy = startNode(s)
    if hx ~= Factory.BreakX or hy ~= Factory.BreakY then
        Factory.Status = ("Walking to break position (%d,%d)"):format(Factory.BreakX, Factory.BreakY)
        if not walkTo(Factory.BreakX, Factory.BreakY, 45) then
            Factory.Status = "Failed to walk to break position, retrying later"
            Factory.BreakFailUntil = os.clock() + 30
            return false
        end
    end
    if not o.live() then return false end
    State.Override = { offsets = Factory.Tiles, block = o.block, mode = "Place + Break" }
    State.Quiet = true
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    local id = State.RunId
    local acts0 = State.Placed + State.Broken
    local lastActs, lastActAt = acts0, os.clock()
    task.spawn(function() -- break session watchdog
        while State.Running and State.RunId == id do
            task.wait(1)
            local sd = invCount(o.seed)
            local acts = State.Placed + State.Broken
            if acts ~= lastActs then lastActs, lastActAt = acts, os.clock() end
            -- keep breaking until blocks run out (no session timer)
            if not o.live() or sd >= CAP
                or (o.drop and Factory.Drop and sd >= Factory.DropAt)
                or (o.breakMode ~= "always" and sd >= BOOT_SEEDS)
                or os.clock() - lastActAt > 8 then -- 8 seconds without place / punch: don't stall here
                State.Running = false
            end
        end
    end)
    Factory.Status = "Break " .. itemName(o.block) .. " at factory position"
    local ok, e = pcall(farmLoop, id)
    if not ok then warn("[n4th] Factory break error: " .. tostring(e)) end
    State.Running = false
    State.Override = nil
    State.Quiet = false
    if State.Placed + State.Broken == acts0 and invCount(o.block) > 0 then
        Factory.BreakFailUntil = os.clock() + 60
        Factory.Status = "Break session had no actions: check break position & tiles (retrying in 1m)"
    end
    return true
end

-- "WORLD" / "WORLD:ID" / ":ID" -> world name, door id
local function parseDropTarget()
    local raw = tostring(Factory.DropWorld or ""):gsub("%s", "")
    local name, door = string.match(raw, "^([^:]*):(.+)$")
    if not name then name = raw end
    name = string.upper(name):gsub("[^A-Z0-9]", "")
    if door == "" then door = nil end
    return name, door
end

-- Switch world (via game menu), optionally targeting a specific door
local function goWorld(name, door)
    if Guard.worldName() ~= "" then
        Guard.leaveWorld()
        task.wait(2)
    end
    if door and Refs.World then rawset(Refs.World, "arriveDoor", door) end
    local ok, err = Guard.enterWorld(name)
    if ok then
        task.wait(1.5)
        Guard.afterEnter()
    end
    return ok, err
end

-- Drop via game drop function (item falls in front of character)
local function dropItems(id, n, live, allowFlip)
    local hud = Refs.Hud
    local f = hud and rawget(hud, "onDrop")
    if type(f) ~= "function" then return 0, "game drop function not found" end
    local left, flipped = n, false
    local ping = 0.1
    pcall(function() ping = LocalPlayer:GetNetworkPing() end)
    local waitLimit = math.clamp(0.85 + 2.5 * ping, 0.9, 2.5)
    while left > 0 and live() do
        local before = invCount(id)
        local amount = math.min(left, 200, before)
        if amount <= 0 then return n - left, "item ran out" end
        local ok, err = pcall(f, id, amount)
        if not ok then return n - left, tostring(err) end
        task.wait(0.35) -- game rejects drops sent too fast (0.3s)
        local got = before - invCount(id)
        local deadline = os.clock() + waitLimit
        while got <= 0 and live() and os.clock() < deadline do
            task.wait(0.1)
            got = before - invCount(id)
        end
        if got > 0 then
            left -= got
        elseif not flipped and allowFlip ~= false then
            -- facing wall / cannot drop here: face another direction and retry
            flipped = true
            local st = playerState()
            local right = st and (st.facing or 1) < 0
            AutoInput.active = true
            AutoInput.right, AutoInput.left = right, not right
            task.wait(0.06)
            AutoInput.right, AutoInput.left = false, false
            task.wait(0.3)
        else
            return n - left, "cannot drop at this position"
        end
    end
    return n - left, nil
end

-- Shared drop point (used by Factory, Farmer, Auto Farm):
-- travel to drop point (may be another world / WORLD:ID), drop items, return to origin world.
-- items = { { id =, n = }, ... }  -> it.got filled with count actually dropped
-- Returns: ok, reason ("nopoint" | "home" | error text)
local function dropTrip(items, live, say)
    say = say or function() end
    local name, door = parseDropTarget()
    local home = Guard.worldName()
    if name == "" then name = home end
    if Factory.DropX < 0 and not door and name == home then
        say("Drop point not set (Auto Drop -> Shared drop point), drop skipped")
        return false, "nopoint"
    end
    Factory.Traveling = true
    local away = name ~= home
    local ok, why = true, nil
    if away or door then
        say("Going to " .. name .. (door and (":" .. door) or "") .. " to drop")
        local okw, err = goWorld(name, door)
        if not okw then ok, why = false, "failed to enter " .. name .. " (" .. tostring(err) .. ")" end
    end
    if ok and live() and Factory.DropX >= 0 then
        say(("Walking to drop position (%d,%d)"):format(Factory.DropX, Factory.DropY))
        if not walkTo(Factory.DropX, Factory.DropY, 60) then ok, why = false, "cannot walk to drop position" end
    end
    if ok and live() then
        local s = playerState()
        if s then Factory.Zone = { world = Guard.worldName(), x = s.x, y = s.y - 0.475 } end
        for _, it in ipairs(items) do
            if not live() then break end
            local got, err = dropItems(it.id, it.n, live)
            it.got = got
            if got > 0 then
                local msg = ("Dropped %s x%d at %s"):format(itemName(it.id), got, Guard.worldName())
                say(msg)
                notify("Drop", msg, 4)
                Hook.send("factory", msg)
            end
            if err then
                ok, why = false, err
                break
            end
        end
    end
    if not ok then
        say("Drop failed: " .. tostring(why))
        notify("Drop", "Drop failed: " .. tostring(why), 5)
        Hook.send("factory", "Drop failed: " .. tostring(why))
    end
    -- return to origin world
    if away and home ~= "" and live() then
        say("Returning to " .. home)
        local okh = goWorld(home, nil)
        if not okh and live() then
            task.wait(5)
            okh = goWorld(home, nil)
        end
        if not okh then
            Factory.Traveling = false
            autoEnd()
            return false, "home"
        end
    end
    Factory.Traveling = false
    autoEnd()
    return ok, why
end
Auto.dropTrip = dropTrip

-- Auto Drop chooses full stacks and saves one standing position in this world.
do
    local function hasDropSpace(x, y, facing)
        local frontX = x + facing
        return frontX >= 0 and frontX < Refs.World.w and openAt(frontX, y)
    end

    function AutoDrop.targetError()
        local w = Refs.World
        if not w or not Refs.Inv or not playerState() then return "Enter a world and connect game references first" end
        if AutoDrop.World == "" or AutoDrop.X < 0 or AutoDrop.Y < 0 then return "Select a drop tile first" end
        if Guard.worldName() ~= AutoDrop.World then return "Waiting for world " .. AutoDrop.World end
        if AutoDrop.X >= w.w or AutoDrop.Y >= w.h or not openAt(AutoDrop.X, AutoDrop.Y)
            or not realSupport(AutoDrop.X, AutoDrop.Y) then return "Drop tile must be safe to stand on" end
        if not hasDropSpace(AutoDrop.X, AutoDrop.Y, 1) and not hasDropSpace(AutoDrop.X, AutoDrop.Y, -1) then
            return "Both sides of the drop tile are blocked"
        end
        if not Session.bindMovement(true) then return "Game movement controls not found" end
        if not Refs.Hud or type(rawget(Refs.Hud, "onDrop")) ~= "function" then return "Game drop function not found" end
        return nil
    end

    function AutoDrop.setPoint(x, y, world)
        if AutoDrop.Busy then return false, "Wait for the drop trip to finish" end
        if world ~= Guard.worldName() then return false, "World changed, open the grid again" end
        if not Refs.World or x < 0 or y < 0 or x >= Refs.World.w or y >= Refs.World.h
            or not openAt(x, y) or not realSupport(x, y) then
            return false, "Choose an empty tile with a safe surface underneath"
        end
        AutoDrop.X, AutoDrop.Y, AutoDrop.World = x, y, world
        AutoDrop.Status = "Drop tile saved"
        Config.save(true)
        return true
    end

    function AutoDrop.beginGrid()
        if AutoDrop.Busy then return false, "Wait for the drop trip to finish" end
        local s = playerState()
        if not s or Guard.worldName() == "" then return false, "You are not in a world yet" end
        local x, y = startNode(s)
        AutoDrop.Grid = { x = x, y = y, world = Guard.worldName(), fg = Refs.World.fg }
        AutoDrop.GridSelection = {}
        if AutoDrop.World == AutoDrop.Grid.world then
            local dx, dy = AutoDrop.X - x, AutoDrop.Y - y
            AutoDrop.GridSelection[dx .. "," .. dy] = true
        end
        return true
    end

    function AutoDrop.selectTile(dx, dy)
        local grid = AutoDrop.Grid
        if not grid or not Refs.World or grid.fg ~= Refs.World.fg then
            notify("Auto Drop", "World changed, open the grid again", 4)
            return
        end
        local ok, message = AutoDrop.setPoint(grid.x + dx, grid.y + dy, grid.world)
        if ok then
            table.clear(AutoDrop.GridSelection)
            AutoDrop.GridSelection[dx .. "," .. dy] = true
            notify("Auto Drop", ("Standing position for drop (%d,%d) saved"):format(AutoDrop.X, AutoDrop.Y), 3)
        else
            notify("Auto Drop", message, 4)
        end
        if UI.applyGrid then UI.applyGrid() end
    end

    function AutoDrop.fullItems()
        local items, seen = {}, {}
        local building = Build.DirtRun
        for _, id in ipairs(AutoDrop.Items) do
            if type(id) == "number" and not seen[id] and (not building or id ~= building.block) then
                seen[id] = true
                if invCount(id) >= 200 then items[#items + 1] = id end
            end
        end
        return items
    end

    function AutoDrop.labels()
        local ids = {}
        if Refs.Inv then
            for _, slot in pairs(Refs.Inv.slots) do
                if type(slot) == "table" and type(slot.id) == "number" and (slot.n or 0) > 0 then ids[slot.id] = true end
            end
        end
        for _, id in ipairs(AutoDrop.Items) do if type(id) == "number" then ids[id] = true end end
        local sorted, labels, picked = {}, {}, {}
        for id in pairs(ids) do sorted[#sorted + 1] = id end
        table.sort(sorted)
        for _, id in ipairs(sorted) do
            local label = ("%s [%d]"):format(itemName(id), id)
            labels[#labels + 1] = label
            if table.find(AutoDrop.Items, id) then picked[#picked + 1] = label end
        end
        return labels, picked
    end

    local function dropAmounts(id)
        local amounts = {}
        for _, drop in pairs(Drops.list or {}) do
            if type(drop) == "table" and drop.id == id and type(drop.n) == "number" then
                amounts[drop.uid or drop] = drop.n
            end
        end
        return amounts
    end

    -- Record newly created or incremented stack IDs during the drop.
    -- Farm stays paused until recording finishes.
    local function trackDrop(zone, final)
        local changes, observed = {}, 0
        for _, drop in pairs(Drops.list or {}) do
            if type(drop) == "table" and drop.id == zone.id and type(drop.n) == "number"
                and type(drop.x) == "number" and type(drop.y) == "number"
                and abs(drop.x - zone.x) <= 2.5 and abs(drop.y - zone.y) <= 2.5 then
                local key = drop.uid or drop
                local added = drop.n - (zone.before[key] or 0)
                if added > 0 then
                    if added >= zone.amount then
                        zone.piles[key] = true
                        zone.before = nil
                        return
                    end
                    changes[#changes + 1] = { key = key, amount = added }
                    observed += added
                end
            end
        end
        if observed >= zone.amount or final then
            table.sort(changes, function(a, b) return a.amount > b.amount end)
            local remaining = zone.amount
            for _, change in ipairs(changes) do
                zone.piles[change.key] = true
                remaining -= change.amount
                if remaining <= 0 then break end
            end
            zone.before = nil
        else
            local pending = {}
            for _, change in ipairs(changes) do pending[change.key] = true end
            return pending
        end
    end

    local function protectDrop(id, x, y, world, grid, dropX, dropY, before, amount)
        for _, zone in ipairs(AutoDrop.Zones) do
            if zone.id == id and zone.world == world and zone.grid == grid and zone.x == x and zone.y == y then
                zone.dropX, zone.dropY, zone.at = dropX, dropY, os.clock()
                zone.before, zone.amount = before, amount
                trackDrop(zone)
                return zone
            end
        end
        local zone = { id = id, x = x, y = y, world = world, grid = grid, dropX = dropX, dropY = dropY,
            at = os.clock(), piles = {}, before = before, amount = amount }
        AutoDrop.Zones[#AutoDrop.Zones + 1] = zone
        trackDrop(zone)
        return zone
    end

    local function pileKey(drop, zone, pending)
        if type(drop) ~= "table" or drop.id ~= zone.id or (drop.n or 0) <= 0
            or type(drop.x) ~= "number" or type(drop.y) ~= "number" then return nil end
        local key = drop.uid or drop
        if zone.piles[key] or (pending and pending[key]) then return key end
        return nil
    end

    -- Avoid native item drop coordinates, with facing fallback during replication.
    function AutoDrop.route(predicted)
        local obstacles, watch, current = {}, {}, playerState()
        local watchUntil = 0
        if predicted then obstacles[1] = predicted end
        for _, zone in ipairs(AutoDrop.Zones) do
            if zone.world == Guard.worldName() and Refs.World and zone.grid == Refs.World.fg then
                local pending = zone.before and trackDrop(zone)
                local expires = (zone.at or 0) + 3
                local known = os.clock() < expires and {} or nil
                if known then
                    watch[zone] = known
                    watchUntil = math.max(watchUntil, expires)
                end
                local found = false
                for _, drop in pairs(Drops.list or {}) do
                    local key = pileKey(drop, zone, pending)
                    if key then
                        local point = { x = drop.x, y = drop.y }
                        obstacles[#obstacles + 1] = point
                        if known then known[key] = point end
                        found = true
                    end
                end
                if not found and (zone.before or os.clock() - (zone.at or 0) < 5) then
                    obstacles[#obstacles + 1] = { x = zone.dropX or zone.x, y = zone.dropY or zone.y }
                end
            end
        end
        local radius = 0.68 -- game touch pickup radius is ~0.6 tile, keep safe margin without blocking adjacent tiles
        local function inside(x, y, item) return abs(x - item.x) < radius and abs(y - item.y) < radius end
        for _, item in ipairs(obstacles) do
            item.escaping = current and inside(current.x, current.y - 0.475, item) or false
            item.startDistance = current and abs(current.x - item.x) or 0
        end
        local route = {}
        local startX, startY, startBodyX, startBodyY
        if current then
            startX, startY = startNode(current)
            startBodyX, startBodyY = current.x, current.y - 0.475
        end
        if next(watch) then
            local checkAt = os.clock() + 0.15
            function route.needsRefresh()
                local now = os.clock()
                if now < checkAt or now >= watchUntil then return false end
                checkAt = now + 0.15
                for zone, known in pairs(watch) do
                    local pending = zone.before and trackDrop(zone)
                    for _, drop in pairs(Drops.list or {}) do
                        local key = pileKey(drop, zone, pending)
                        if key then
                            local old = known[key]
                            if not old or abs(old.x - drop.x) > 0.12 or abs(old.y - drop.y) > 0.12 then
                                return true
                            end
                        end
                    end
                end
                return false
            end
        end
        function route.point(x, y)
            for _, item in ipairs(obstacles) do if inside(x + 0.5, y + 0.5, item) then return false end end
            return true
        end
        function route.edge(fx, fy, tx, ty, kind)
            local x0, y0, x1, y1 = fx + 0.5, fy + 0.5, tx + 0.5, ty + 0.5
            if fx == startX and fy == startY then x0, y0 = startBodyX, startBodyY end
            for _, item in ipairs(obstacles) do
                if inside(x0, y0, item) then
                    -- Exit drop radius solely by walking away.
                    if kind ~= "walk" or fy ~= ty or (x0 - item.x) * (x1 - item.x) < 0
                        or abs(x1 - item.x) <= abs(x0 - item.x) then return false end
                else
                    local top = math.min(y0, y1)
                    if kind == "jump" or kind == "gap" or kind == "stair" then top -= 3 end
                    if math.max(x0, x1) > item.x - radius and math.min(x0, x1) < item.x + radius
                        and math.max(y0, y1) > item.y - radius and top < item.y + radius then return false end
                end
            end
            return true
        end
        function route.safe(s, arriving)
            if not s then return false end
            for _, item in ipairs(obstacles) do
                if inside(s.x, s.y - 0.475, item) then
                    if arriving or not item.escaping or abs(s.x - item.x) < item.startDistance - 0.02 then return false end
                else item.escaping = false end
            end
            return true
        end
        return route
    end

    local function atPoint(x, y, facing)
        local s = playerState()
        return s and not s.dead and s.grounded and floor(s.x) == x and floor(s.y - 0.475) == y
            and (not facing or ((s.facing or 1) < 0 and -1 or 1) == facing)
    end

    function AutoDrop.trip(items)
        local state = playerState()
        if not state or state.dead or not state.grounded or AutoInput.collectOwner then
            AutoDrop.Status = "Waiting for the character to return to a stable farm tile"
            return
        end
        if not Session.bindMovement(true) then
            AutoDrop.Status = "Game movement controls not found"
            return
        end
        local hx, hy = startNode(state)
        if not openAt(hx, hy) or not realSupport(hx, hy) then
            AutoDrop.Status = "Waiting for the character to return to a stable farm tile"
            return
        end
        local world, fg = Refs.World, Refs.World.fg
        for index = #AutoDrop.Zones, 1, -1 do
            local zone = AutoDrop.Zones[index]
            if zone.grid ~= fg or zone.world ~= world.name then table.remove(AutoDrop.Zones, index) end
        end
        local token = Guard.Token
        local x, y, facing = AutoDrop.X, AutoDrop.Y, AutoDrop.Facing
        local saved = Guard.snapshot()
        AutoDrop.Busy, AutoDrop.Cancelled, AutoDrop.Saved = true, false, saved
        local function sameWorld()
            return alive() and not AutoDrop.Cancelled and Guard.Token == token and Guard.Mode == "idle"
                and Refs.World == world and world.fg == fg and Guard.worldName() == saved.world
        end
        local function live() return sameWorld() and AutoDrop.On end
        local returned, failure, departed = false, nil, false
        local droppedZones, freedItems = {}, {}
        local ok, err = pcall(function()
            if State.Running and not State.Override and farmMode() ~= "Place only" then
                AutoDrop.Status = "Finishing current farm cycle before drop"
                State.DropYield, State.DropYieldWait = true, true
                local yieldUntil = os.clock() + 4
                while live() and State.Running and State.DropYield and os.clock() < yieldUntil do
                    task.wait(0.05)
                end
            end
            Guard.stopAll(true)
            State.DropYield, State.DropYieldWait = false, false
            local freshState = playerState()
            if freshState and freshState.grounded and not freshState.dead then
                local fx, fy = startNode(freshState)
                if openAt(fx, fy) and realSupport(fx, fy) then hx, hy = fx, fy end
            end
            AutoDrop.Status = "Pausing farming to drop"
            task.wait(0.6)
            if not live() then return end
            AutoDrop.Status = "Walking to the drop point"
            local walkOk = walkTo(x, y, 60, live, AutoDrop.route)
            local afterWalk = playerState()
            if walkOk or (afterWalk and (floor(afterWalk.x) ~= hx or floor(afterWalk.y - 0.475) ~= hy)) then
                departed = true
            end
            if not walkOk or not live() then
                if live() then failure = "The drop tile is unreachable" end
                return
            end
            local cur = playerState()
            if cur and math.abs(cur.x - (x + 0.5)) > 0.22 then
                AutoInput.active = true
                execWalk(x, y, 0.15)
            end
            local function returnPath(direction)
                local s = playerState()
                if not live() or not s or not atPoint(x, y) or not hasDropSpace(x, y, direction) then return false end
                local route = AutoDrop.route({ x = s.x + direction, y = s.y - 0.475 })
                if hx == x and hy == y then return route.safe(s, true) end
                route.badEdges, route.live = {}, live
                local goal = { [hy * world.w + hx] = true }
                return route.point(hx, hy) and astar(x, y, goal, hx, hy, 0.5, false, route) ~= nil
            end
            if not returnPath(facing) then
                if not returnPath(-facing) then
                    failure = "Drop deferred because the stack would block the way back"
                    return
                end
                facing = -facing
            end
            -- Face direction cleanly at target tile, releasing immediately when facing flips.
            AutoInput.active = true
            for _ = 1, 4 do
                if not live() or atPoint(x, y, facing) then break end
                local sNow = playerState()
                if not sNow or floor(sNow.x) ~= x or floor(sNow.y - 0.475) ~= y then
                    execWalk(x, y, 0.15)
                    if atPoint(x, y, facing) then break end
                end
                AutoInput.left, AutoInput.right = facing < 0, facing > 0
                local turnUntil = os.clock() + 0.35
                while live() and os.clock() < turnUntil do
                    task.wait()
                    local st = playerState()
                    if not st or ((st.facing or 1) < 0 and -1 or 1) == facing then break end
                    if floor(st.x) ~= x then break end
                end
                AutoInput.left, AutoInput.right = false, false
                task.wait(0.08)
            end
            local sFinal = playerState()
            if live() and sFinal and (floor(sFinal.x) ~= x or floor(sFinal.y - 0.475) ~= y) then
                execWalk(x, y, 0.15)
            end
            local function canDrop() return live() and atPoint(x, y, facing) end
            if not canDrop() then failure = "The character has not reached the drop tile or is facing the wrong way" return end
            if not returnPath(facing) then failure = "Drop deferred because the stack would block the way back" return end
            for _, id in ipairs(items) do
                if not canDrop() then break end
                if table.find(AutoDrop.Items, id) and invCount(id) >= 200 then
                    AutoDrop.Status = "Drop " .. itemName(id) .. " x200"
                    pcall(findDropRefs)
                    if #droppedZones > 0 and not returnPath(facing) then
                        failure = "Drop deferred because the stack would block the way back"
                        break
                    end
                    local before = dropAmounts(id)
                    local origin = playerState()
                    if not origin or not canDrop() then break end
                    local dropX, dropY = origin.x + facing, origin.y - 0.475
                    local got, reason = dropItems(id, 200, canDrop, false)
                    AutoDrop.Dropped += got
                    if got > 0 then
                        pcall(findDropRefs)
                        local zone = protectDrop(id, x + 0.5, y + 0.5, saved.world, fg, dropX, dropY, before, got)
                        droppedZones[#droppedZones + 1] = zone
                        freedItems[id] = true
                    end
                    if reason then failure = reason break end
                end
            end
        end)
        State.DropYield, State.DropYieldWait = false, false
        if not ok then failure = tostring(err) end
        -- Return trip still finishes if toggle is switched off mid-way.
        if sameWorld() then
            AutoDrop.Status = "Finding a safe path back"
            local backOk, result = pcall(function()
                if not departed and atPoint(hx, hy) then return true end
                if not departed then
                    local stNow = playerState()
                    if stNow and floor(stNow.x) == hx and floor(stNow.y - 0.475) == hy then return true end
                end
                return walkTo(hx, hy, 60, sameWorld, AutoDrop.route)
            end)
            returned = backOk and result == true
            if not backOk then failure = tostring(result) end
        end
        Move.Homing, Move.HomingLive, Move.HomingRoute = false, nil, nil
        releaseInput()
        autoEnd()
        if sameWorld() then
            pcall(function()
                findDropRefs()
                for _, zone in ipairs(droppedZones) do if zone.before then trackDrop(zone, true) end end
                for _, drop in pairs(Drops.list or {}) do
                    if type(drop) == "table" and drop.uid and freedItems[drop.id] and not AutoDrop.isProtected(drop) then
                        DropFailUntil[drop.uid] = nil
                    end
                end
            end)
            Drops.seen, Drops.nextTick = nil, 0
        end
        for _, zone in ipairs(droppedZones) do zone.before = nil end
        AutoDrop.Busy, AutoDrop.Saved = false, nil
        if returned and sameWorld() then
            local curX, curY = Auto.here()
            if curX then saved.tx, saved.ty = curX, curY end
            local resumed, resumeError = pcall(Guard.resumeActivities, saved, sameWorld)
            if not resumed then failure = tostring(resumeError) end
        elseif sameWorld() then
            AutoDrop.On = false
            failure = "No safe way back. Auto Drop stopped. Change the drop tile or direction."
            if UI.AutoDropToggle then
                UI.later("autoDropOff", function()
                    UI.AutoDropToggle:Set(false)
                    AutoDrop.Status = failure
                end)
            end
        end
        AutoDrop.NextTry = os.clock() + (failure and 10 or 1)
        AutoDrop.Status = failure or (AutoDrop.On and "Waiting for an item to reach 200" or "Off")
        if failure then notify("Auto Drop", failure, 5) end
    end

    task.spawn(function()
        while alive() do
            task.wait(0.5)
            if Session.Ready and AutoDrop.On and not AutoDrop.Busy and not WorldFinder.Busy and Guard.Mode == "idle"
                and not State.DropPause and not Factory.Traveling and not Move.Homing
                and os.clock() >= (AutoDrop.NextTry or 0) then
                local ok, err = pcall(function()
                    local reason = AutoDrop.targetError()
                    if reason then AutoDrop.Status = reason return end
                    local items = AutoDrop.fullItems()
                    if #items > 0 then AutoDrop.trip(items) else AutoDrop.Status = "Waiting for an item to reach 200" end
                end)
                if not ok then
                    AutoDrop.Status = tostring(err)
                    AutoDrop.NextTry = os.clock() + 10
                    warn("[n4th] Auto Drop: " .. tostring(err))
                end
            end
        end
    end)
end

-- Is drop point configured? (position, WORLD:ID, or another world)
function Factory.pointSet()
    if Factory.DropX >= 0 then return true end
    local name, door = parseDropTarget()
    if door then return true end
    return name ~= "" and name ~= Guard.worldName()
end

local function factoryDrop(seed, n, live)
    local items = { { id = seed, n = n } }
    local ok, why = dropTrip(items, live, function(t) Factory.Status = t end)
    Factory.Dropped += items[1].got or 0
    if why == "home" then
        if Factory.stop then Factory.stop("Failed to return to factory world " .. tostring(Factory.Home)) end
    elseif not ok then
        Factory.DropOffUntil = os.clock() + ((why == "nopoint") and 60 or 120)
    end
end

-- Auto Farm: broken seeds full -> pause, drop seeds at drop point,
-- return to farm position, then resume (checked every 2 seconds)
task.spawn(function()
    while alive() do
        task.wait(2)
        local seed = State.SelectedId and seedOfBlock(State.SelectedId)
        if State.Running and not State.Override and Factory.pointSet() and not State.DropPause and seed
            and not AutoDrop.Busy and not (AutoDrop.On and table.find(AutoDrop.Items, seed))
            and os.clock() >= (State.DropOffUntil or 0) then
            local n = invCount(seed)
            local s = playerState()
            if s and n >= State.SeedDropAt and n > State.SeedKeep then
                local hx, hy = startNode(s)
                local runId = State.RunId
                local function live() return State.Running and alive() and State.RunId == runId end
                State.DropPause = true
                task.wait(0.8) -- wait for last punch to finish
                local items = { { id = seed, n = n - State.SeedKeep } }
                local ok, why = dropTrip(items, live, function(t) State.LastAction = t end)
                State.Dropped += items[1].got or 0
                if not ok then State.DropOffUntil = os.clock() + ((why == "nopoint") and 60 or 120) end
                if why == "home" then
                    stopFarm("Failed to return to farm world")
                elseif live() then
                    State.LastAction = ("Walking back to farm position (%d,%d)"):format(hx, hy)
                    if not walkTo(hx, hy, 60) then
                        stopFarm("Failed to return to farm position, Auto Farm stopped")
                    else
                        State.LastAction = "Resuming Auto Farm"
                    end
                end
                State.DropPause = false
            end
        end
    end
end)

local PHASE_NAME = { harvest = "HARVEST", plant = "PLANT", ["break"] = "BREAK", wait = "WAIT" }

local function breakReady()
    return Factory.BreakX >= 0 and next(Factory.Tiles) ~= nil and os.clock() >= (Factory.BreakFailUntil or 0)
end

-- 1 factory step. o = { seed, block, drop, breakMode, whole, exclude, live, phase }
-- Returns: "drop" | "work" | "move" | "wait" | "break" | "next" | "idle" (+ seconds to ready tree)
local FACTORY_ROTASI_PHASE_NAME = { panen = "HARVEST", tanam = "PLANT", ["break"] = "BREAK", tunggu = "WAIT" }

local function factoryStep(o)
    local seeds, blocks = invCount(o.seed), invCount(o.block)
    o.phase = o.phase or "panen"
    Factory.Phase = FACTORY_ROTASI_PHASE_NAME[o.phase]
    Factory.Harvesting = (o.phase == "panen" or o.phase == "tanam") -- mau panen: collect break off
    -- Break hanya dimulai kalau block sudah BreakAt (200); sekali mulai lanjut sampai block habis
    local T = math.clamp(Factory.BreakAt or 200, 1, 200)
    if blocks >= T then o.breaking = true elseif blocks <= 0 then o.breaking = false end
    -- drop seed lebihan (kapan saja)
    if o.drop and Factory.Drop and seeds >= Factory.DropAt and seeds > Factory.Keep
        and os.clock() >= (Factory.DropOffUntil or 0) then
        factoryDrop(o.seed, seeds - Factory.Keep, o.live)
        return "drop"
    end

    if o.phase == "panen" then
        -- terus panen sampai block cukup untuk break (BreakAt); seed disisakan ruang ~20 item
        if blocks >= T or seeds >= CAP - 20 then
            o.phase = "tanam"
            return "next"
        end
        -- Selesaikan panen baris atas dahulu. Penanaman dilakukan pada fase TANAM,
        -- supaya tidak selang-seling panen/tanam antar tile atau antar baris.
        FC = factoryCfg(o, true, true) -- panen lalu tanam langsung di tempat (lihat farmerWorkInReach)
        local r = fieldStep()
        if r == "idle" then
            o.idleAt = os.clock()
            o.phase = "tanam"
            return "next"
        end
        return r
    end

    if o.phase == "tanam" then
        if seeds > 0 then
            FC = factoryCfg(o, false, true)
            local r = fieldStep()
            if r ~= "idle" then return r end
        end
        o.phase = "break"
        return "next"
    end

    if o.phase == "break" then
        local want
        if o.breakMode == "always" then
            -- tidak ada seed & tidak ada pohon: break dulu supaya dapat seed (kalau tidak, macet)
            local nb, nxtb = readyTreeCount(o.whole)
            local bootstrap = seeds == 0 and nb == 0 and nxtb == nil
            want = blocks > 0 and (o.breaking or bootstrap)
        else -- mode produksi: break hanya untuk dapat seed awal
            local _, nxt = readyTreeCount(o.whole)
            want = blocks > 0 and seeds < BOOT_SEEDS and nxt == nil
        end
        if want and breakReady() and factoryBreak(o) then
            -- block masih ada: lanjut break (habiskan dulu), block habis: tanam
            o.phase = (o.breakMode == "always" and invCount(o.block) > 0) and "break" or "tanam"
            return "break"
        end
        o.phase = "tunggu"
        return "next"
    end

    -- tunggu
    local n, nxt = readyTreeCount(o.whole)
    if n > 0 and os.clock() - (o.idleAt or 0) > 5 then
        o.phase = "panen"
        return "next"
    end
    if o.breakMode == "always" and blocks > 0 and (o.breaking or (seeds == 0 and n == 0 and nxt == nil))
        and breakReady() then
        o.phase = "break"
        return "next"
    end
    if seeds > 0 and os.clock() - (o.plantAt or 0) > 10 then
        o.plantAt = os.clock() -- sesekali cek tile kosong (misal pohon dipanen orang lain)
        o.phase = "tanam"
        return "next"
    end
    return "idle", nxt, n
end

local function waitText(sec)
    sec = math.max(0, math.ceil(sec or 0))
    if sec >= 60 then return ("%dm %ds"):format(sec // 60, sec % 60) end
    return sec .. " s"
end

local function factoryLoop(runId)
    local function live() return Factory.Running and alive() and Factory.RunId == runId end
    local o = { seed = Factory.SeedId, block = Factory.BlockId, drop = true, breakMode = "always", live = live }
    while live() do
        task.wait()
        o.whole = Factory.WholeWorld
        local here = Guard.worldName()
        if not Factory.Traveling and Factory.Home ~= "" and here ~= Factory.Home then
            Factory.Status = "Bukan di world pabrik (" .. Factory.Home .. "), menunggu..."
            task.wait(2)
            continue
        end
        local r, nextReady, nReady = factoryStep(o)
        if r ~= "idle" then o.stuckAt = nil end
        if r == "idle" then
            local seeds, blocks = invCount(o.seed), invCount(o.block)
            if not nextReady and (nReady or 0) == 0 and seeds <= 0 and blocks <= 0 then
                if Factory.stop then Factory.stop("Seed & block habis, tidak ada pohon tumbuh") end
                break
            end
            if (nReady or 0) > 0 then
                -- ada pohon siap tapi tidak terjangkau: lama-lama reset daftar lewati & jalur
                o.stuckAt = o.stuckAt or os.clock()
                if os.clock() - o.stuckAt > 30 then
                    o.stuckAt = nil
                    table.clear(Factory.Skip)
                    table.clear(BadEdge)
                    Reach = nil
                end
            end
            if seeds >= CAP - 20 and not (Factory.Drop and Factory.pointSet()) then
                Factory.Status = ("Seed hampir penuh (%d): atur titik drop & nyalakan Auto drop seed"):format(seeds)
            elseif (nReady or 0) > 0 then
                Factory.Status = nReady .. " pohon siap belum terjangkau, dicoba lagi"
            elseif nextReady then
                Factory.Status = "Menunggu pohon siap ±" .. waitText(nextReady)
            elseif blocks > 0 and (Factory.BreakX < 0 or next(Factory.Tiles) == nil) then
                Factory.Status = "Ada block tapi posisi / tile break belum diatur"
            elseif seeds > 0 then
                Factory.Status = "Lahan penuh, menunggu"
            else
                Factory.Status = "Menunggu..."
            end
            if not waitAuto(1000) then break end
        end
    end
    releaseInput()
end

function Factory.stop(reason)
    Factory.Running = false
    Factory.Harvesting = false
    Factory.Traveling = false
    if State.Override then State.Running = false end
    autoEnd()
    releaseInput()
    Factory.Status = reason or "Dihentikan"
    if UI.FactoryToggle then pcall(function() UI.FactoryToggle:Set(false) end) end
    if reason then
        notify("Auto Rotasi", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("factory", "Auto Rotasi berhenti: " .. reason) end
    end
end

function Factory.start()
    if Factory.Running then return end
    if WorldFinder.Busy then notify("World Finder", "Hentikan hunting sebelum menjalankan farming", 3) return end
    if AutoDrop.Busy then notify("Auto Drop", "Tunggu perjalanan drop selesai", 3) return end
    local err
    local block = blockOfSeed(Factory.SeedId)
    if not Refs.World then
        err = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
    elseif not Session.bindMovement(true, true) then
        err = "Kontrol gerak game (WorldMenu.isDown) tidak ketemu"
    elseif not playerState() then
        err = "Kamu belum masuk world"
    elseif not Factory.SeedId then
        err = "Pilih seed Auto Rotasi dulu"
    elseif not block then
        err = "Block dari seed ini tidak ketemu"
    elseif not Factory.WholeWorld and #landRows() == 0 then
        err = "Atur lahan dulu (tab Lahan)"
    end
    if err then
        notify("Auto Rotasi", err, 4)
        if UI.FactoryToggle then pcall(function() UI.FactoryToggle:Set(false) end) end
        return
    end
    if State.Running and not State.Override then stopFarm("Dihentikan karena Auto Rotasi dimulai") end
    if Clear.Running then stopClear("Dihentikan karena Auto Rotasi dimulai") end
    if Farmer.Running then stopFarmer("Dihentikan karena Auto Rotasi dimulai") end
    if Splice.Running and Splice.stop then Splice.stop("Dihentikan karena Auto Rotasi dimulai") end
    if not Refs.Trees then findTreeRefs() end
    Factory.BlockId = block
    Factory.Home = Guard.worldName()
    table.clear(Factory.Skip)
    table.clear(Factory.Row)
    table.clear(BadEdge)
    Factory.DropOffUntil, Factory.BreakFailUntil = 0, 0
    Factory.Harvesting = false
    Factory.Running = true
    Factory.RunId = (Factory.RunId or 0) + 1
    Factory.Status = "Mulai..."
    autoBegin()
    if UI.FactoryToggle then pcall(function() UI.FactoryToggle:Set(true) end) end
    local id = Factory.RunId
    task.spawn(function()
        local ok, e = pcall(factoryLoop, id)
        if not ok then
            warn("[n4th] Auto Rotasi error: " .. tostring(e))
            if Factory.Running then Factory.stop("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- VENDING
---------------------------------------------------------------------
-- Mode "Stock from drops":
--   1. Go to vending drop point (WORLD / WORLD:ID, empty = this world), wait for drops matching
--      items sold by your vendings (or anything if empty vending exists), pick up (body touch).
--   2. Return to vending world, restock matching vendings / fill empty vendings.
--   3. Repeat. Switch worlds only when carrying items (avoids unnecessary hops).
-- Mode "Empty until done":
--   Withdraw from all owned vendings. Bag full / all taken -> go to vending drop point,
--   drop everything, return, continue until all vendings are empty.
-- Vending calls via game function (World.vendCall), character must stand in front of machine.
local VEND_STOCK, VEND_EMPTY = "Stock from drops", "Empty until done"
Vend.Fail = {} -- vendings that failed withdrawal: [x,y] = failure count

function Vend.point()
    local raw = tostring(Vend.Point or ""):gsub("%s", "")
    local name, door = string.match(raw, "^([^:|]*)[:|](.+)$")
    if not name then name = raw end
    name = string.upper(name):gsub("[^A-Z0-9]", "")
    if door == "" then door = nil end
    return name, door
end

-- Your vendings in this world: { x, y, fg, id, stock, cap }
function Vend.machines(background)
    local w = Refs.World
    local out = {}
    if not w or type(w.fg) ~= "table" then return out end
    local grid, vending = w.fg, {}
    local budget = { next = os.clock() + 0.0015 }
    local vends = rawget(w, "vends")
    local owner = rawget(w, "vendOwner")
    for y = 0, w.h - 1 do
        local row = w.fg[y]
        if row then
            for x = 0, w.w - 1 do
                local id = row[x] or 0
                if vending[id] == nil then
                    local it = id ~= 0 and ItemDB[id]
                    vending[id] = it and not not it.vend or false
                end
                if vending[id] then
                    local okO, mine = true, true
                    if type(owner) == "function" then okO, mine = pcall(owner, x, y) end
                    if okO and mine then
                        local d = nil
                        if type(vends) == "table" and type(vends.get) == "function" then
                            local okD, v = pcall(vends.get, x, y)
                            if okD and type(v) == "table" then d = v end
                        end
                        d = d or {}
                        if not d.shop then
                            out[#out + 1] = {
                                x = x, y = y, fg = id, id = d.id, stock = tonumber(d.stock) or 0,
                                cap = (id == 9268) and 10398 or 5199,
                            }
                        end
                    end
                end
                if background then
                    Session.scanStep(budget, y * w.w + x + 1)
                    if not alive() or Refs.World ~= w or w.fg ~= grid then return {} end
                end
            end
        end
    end
    return out
end

-- Can this item be processed? (kind filter + item list; tools & locks never allowed)
-- Allowed in vending? (gems, tools, locks, untradables, vending machines: no)
function Vend.sellable(id)
    if type(id) ~= "number" or id == 112 then return false end
    local it = ItemDB[id]
    if not it or it.kind == "tool" then return false end
    if it.lock or it.area or it.guildLock or it.untradeable or it.vend or it.hub then return false end
    local nm = tostring(it.name or ""):lower()
    if nm == "gems" or nm == "gem" then return false end
    return true
end

function Vend.allow(id)
    if not Vend.sellable(id) then return false end
    if #Vend.Items > 0 and not table.find(Vend.Items, id) then return false end
    return true
end

function Vend.filtered()
    return #Vend.Items > 0
end

-- Dropdown choices: items in vending, bag, seen drops, and currently selected
function Vend.labels(machines)
    local seen = Vend.Seen
    local st = { inv = 0, drop = 0, vend = 0 }
    for _, m in ipairs(machines or {}) do
        if m.id then
            seen[m.id] = true
            st.vend += 1
        end
    end
    -- bag contents: read inventory slots (same as block / seed dropdowns)
    if Refs.Inv then
        local okS, slots = pcall(function() return Refs.Inv.slots end)
        if okS and type(slots) == "table" then
            for _, slot in pairs(slots) do
                local id = type(slot) == "table" and tonumber(slot.id) or nil
                if id and (tonumber(slot.n) or 1) > 0 then
                    seen[id] = true
                    st.inv += 1
                end
            end
        end
    end
    -- drops in this world
    local list = Drops.list
    if type(list) == "table" then
        local n, ids = 0, {}
        for _, d in pairs(list) do
            n += 1
            if n > 600 then break end
            local id = type(d) == "table" and tonumber(d.id) or nil
            if id and not ids[id] then
                ids[id] = true
                seen[id] = true
                st.drop += 1
            end
        end
    end
    for _, id in ipairs(Vend.Items) do seen[id] = true end
    local ids = {}
    for id in pairs(seen) do
        if Vend.sellable(id) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local labels, picked = {}, {}
    for _, id in ipairs(ids) do
        local label = ("%s [%d]"):format(tostring(itemName(id)), id)
        labels[#labels + 1] = label
        if table.find(Vend.Items, id) then picked[#picked + 1] = label end
    end
    return labels, picked, st
end

function Vend.call(...)
    local w = Refs.World
    local f = w and rawget(w, "vendCall")
    if type(f) ~= "function" then return false end
    local ok, res = pcall(f, ...)
    return ok and res == true
end

-- Stand in front of vending (game rule: <= 0.85 tile horizontally, same row)
function Vend.goTo(m)
    local function near(c)
        return c ~= nil and math.abs(c.x - (m.x + 0.5)) <= 0.84 and math.abs((c.y - 0.5) - (m.y + 0.5)) <= 0.58
    end
    if near(playerState()) then return true end
    if walkTo(m.x, m.y, 40) and near(playerState()) then return true end
    for _, dx in ipairs({ -1, 1 }) do
        if walkTo(m.x + dx, m.y, 30) then
            local t0 = os.clock()
            AutoInput.active = true
            while alive() and os.clock() - t0 < 1 do
                task.wait()
                local c = playerState()
                if not c then break end
                steerX(c, m.x + 0.5 + dx * 0.55, 0.06)
                if near(c) and c.grounded then break end
            end
            releaseInput()
            if near(playerState()) then return true end
        end
    end
    return false
end

function Vend.sortNear(list)
    local s = playerState()
    if not s then return list end
    table.sort(list, function(a, b)
        local da = math.abs(a.x + 0.5 - s.x) + 2 * math.abs(a.y + 1 - s.y)
        local db = math.abs(b.x + 0.5 - s.x) + 2 * math.abs(b.y + 1 - s.y)
        return da < db
    end)
    return list
end

-- Restock ONLY from picked-up items (Vend.Picked = counts), never unrelated bag items.
-- Picked-up item without an existing vending -> empty vending.
function Vend.stockAll(live)
    local list = Vend.sortNear(Vend.machines())
    local selling = {}
    for _, m in ipairs(list) do
        if m.id and m.stock > 0 then selling[m.id] = true end
    end
    local done, tried = 0, 0
    for _, m in ipairs(list) do
        if not live() then break end
        local id = (m.id and m.stock > 0) and m.id or nil
        if id and not Vend.allow(id) then id = nil end
        local n = 0
        if id then
            -- vending already selling this item: stock full bag stack too
            n = math.min(invCount(id), m.cap - m.stock)
        elseif not (m.id and m.stock > 0) then
            -- empty vending: chosen items in bag, or (unfiltered) picked-up items
            local cands = {}
            if #Vend.Items > 0 then
                for _, pid in ipairs(Vend.Items) do cands[#cands + 1] = pid end
            else
                for pid, cnt in pairs(Vend.Picked) do
                    if cnt > 0 then cands[#cands + 1] = pid end
                end
                table.sort(cands)
            end
            for _, pid in ipairs(cands) do
                if not selling[pid] and Vend.allow(pid) and invCount(pid) > 0 then
                    id = pid
                    break
                end
            end
            if id then
                n = math.min(invCount(id), m.cap)
                if #Vend.Items == 0 then n = math.min(n, Vend.Picked[id] or 0) end
            end
        end
        if id and n > 0 then
            tried += 1
            Vend.Status = ("To vending (%d,%d): add %s x%d"):format(m.x, m.y, itemName(id), n)
            if Vend.goTo(m) then
                if Vend.call("stock", m.x, m.y, id, n) then
                    selling[id] = true
                    if Vend.Picked[id] then
                        Vend.Picked[id] -= n
                        if Vend.Picked[id] <= 0 then Vend.Picked[id] = nil end
                    end
                    Vend.Stocked += n
                    done += n
                    Vend.Status = ("Stocked %s +%d at (%d,%d)"):format(itemName(id), n, m.x, m.y)
                    task.wait(0.3)
                else
                    Vend.Status = ("Failed to add stock at (%d,%d)"):format(m.x, m.y)
                    task.wait(0.5)
                end
            else
                Vend.Status = ("Cannot reach vending (%d,%d)"):format(m.x, m.y)
            end
        end
    end
    return done, tried
end

-- Items to look for when restocking: sold by non-full vendings.
-- Empty vendings: may take new items (up to empty vending count; skip items whose vendings are full).
function Vend.wanted()
    local want, sold, empty = {}, {}, 0
    for _, m in ipairs(Vend.machines()) do
        if m.id and m.stock > 0 then
            sold[m.id] = true
            if m.stock < m.cap and Vend.allow(m.id) then want[m.id] = true end
        else
            empty += 1
        end
    end
    return want, empty, sold
end

-- Switch world (via game menu); same world without door = no move
function Vend.travel(name, door)
    if name == Guard.worldName() and not door then return true end
    local ok, err = goWorld(name, door)
    if ok then
        -- wait until character spawns in destination world (dynamic, not fixed delay)
        local t0 = os.clock()
        while os.clock() - t0 < 4 and not (playerState() and Guard.worldName() == name) do task.wait(0.1) end
        task.wait(0.2)
    end
    return ok, err
end

-- Pick up target drops in this world (body touch, per row). Returns: total collected.
function Vend.pickHere(live, want, empty, sold)
    local before = {} -- bag count before item was picked up (recorded when drop first spotted)
    local newIds = 0
    for id, cnt in pairs(Vend.Picked) do
        if not sold[id] and cnt > 0 and invCount(id) > 0 then newIds += 1 end
    end
    local function wantId(d)
        if not Vend.allow(d.id) then return false end
        if not want[d.id] then
            if sold[d.id] or empty <= 0 then return false end -- vending for this item is full / no empty vending left
            if before[d.id] == nil and not (Vend.Picked[d.id] and invCount(d.id) > 0) then
                if newIds >= empty then return false end -- empty vending already reserved by another item
                newIds += 1
            end
        end
        if before[d.id] == nil then before[d.id] = invCount(d.id) end
        return true
    end
    Move.NoZone = true -- allow picking up drops placed by Factory at the drop point
    Move.fetchDrops(live, 999, wantId, 240)
    Move.NoZone = false
    local got = 0
    for id, n in pairs(before) do
        local diff = invCount(id) - n
        if diff > 0 then
            got += diff
            Vend.Picked[id] = (Vend.Picked[id] or 0) + diff
        end
    end
    return got
end

-- Drop all withdrawn vending items at vending drop point, then return
function Vend.dropTrip(live, home)
    local name, door = Vend.point()
    if name == "" then name = home end
    local items = {}
    for id, cnt in pairs(Vend.Carry) do -- only drop amounts withdrawn from vending (leave other bag items)
        local n = math.min(cnt, invCount(id))
        if n > 0 then items[#items + 1] = { id = id, n = n } end
    end
    if #items == 0 then return true end
    Vend.Status = "Going to drop point " .. name .. (door and (":" .. door) or "")
    local ok, err = Vend.travel(name, door)
    if not ok then
        Vend.Status = "Failed to reach drop point: " .. tostring(err)
        return false
    end
    if not Vend.goSpot(live) then return false end
    for _, it in ipairs(items) do
        if not live() then break end
        local got, derr = dropItems(it.id, it.n, live)
        Vend.Dropped += got
        if got > 0 then
            local msg = ("Dropped %s x%d at %s"):format(itemName(it.id), got, Guard.worldName())
            Vend.Status = msg
            Hook.send("factory", "Vending: " .. msg)
        end
        if derr then Vend.Status = "Drop: " .. tostring(derr) end
    end
    if Guard.worldName() ~= home and live() then
        Vend.Status = "Returning to " .. home
        local okh = Vend.travel(home, nil)
        if not okh and live() then
            task.wait(5)
            okh = Vend.travel(home, nil)
        end
        if not okh then return false, "home" end
    end
    return true
end

-- Walk to saved vending drop position (if configured)
function Vend.goSpot(live)
    if Vend.DropX < 0 or not live() then return true end
    local s = playerState()
    if s then
        local hx, hy = startNode(s)
        if hx == Vend.DropX and hy == Vend.DropY then return true end
    end
    Vend.Status = ("Walking to vending drop position (%d,%d)"):format(Vend.DropX, Vend.DropY)
    if walkTo(Vend.DropX, Vend.DropY, 60) then return true end
    Vend.Status = ("Cannot walk to vending drop position (%d,%d)"):format(Vend.DropX, Vend.DropY)
    return false
end

-- Self-dropped items can only be picked up after stepping away (game rule: armed).
-- If standing on / near your own drop of a wanted item: step 2-4 tiles aside, wait briefly.
function Vend.stepAway(live)
    local s = playerState()
    local list = Drops.list
    if not s or type(list) ~= "table" or not live() then return false end
    local near = false
    for _, d in pairs(list) do
        if type(d) == "table" and d.armed == false and type(d.x) == "number" and type(d.y) == "number"
            and Vend.allow(d.id) and math.abs(d.x - s.x) < 1.8 and math.abs(d.y - (s.y - 0.5)) < 1.8 then
            near = true
            break
        end
    end
    if not near then return false end
    local hx, hy = startNode(s)
    for _, dx in ipairs({ 3, -3, 2, -2, 4, -4 }) do
        if not live() then return false end
        Vend.Status = "Stepping away from own drop so it can be picked up"
        if walkTo(hx + dx, hy, 8) then
            Vend.sleep(0.6, live)
            return true
        end
    end
    return false
end

-- After world change: wait for world & vending data to load (max 12s). Returns: vending list
function Vend.waitWorld(home, live)
    local t0 = os.clock()
    local list = {}
    while live() and os.clock() - t0 < 25 do
        if Guard.worldName() == home and playerState() then
            list = Vend.machines()
            if #list > 0 then return list end
        end
        task.wait(0.5)
    end
    return list
end

-- Is drop point set? (another world / door / XY position)
function Vend.hasPoint()
    local name, door = Vend.point()
    return name ~= "" or door ~= nil or Vend.DropX >= 0
end

-- Temporary hiccup (high ping, slow server, world switch failure): retry with increasing
-- backoff. Stop only after 8 consecutive failures. Returns: true = continue.
function Vend.soft(reason, live)
    Vend.Soft = (Vend.Soft or 0) + 1
    if Vend.Soft > 8 then
        Vend.stop(reason)
        return false
    end
    Vend.Status = reason .. (" - retry %d/8"):format(Vend.Soft)
    Vend.sleep(math.min(2 + Vend.Soft * 2, 15), live)
    return live()
end

-- wait (cancellable)
function Vend.sleep(sec, live)
    local t0 = os.clock()
    while live() and os.clock() - t0 < sec do task.wait(0.25) end
end

local function vendLoop(runId)
    local function live() return Vend.Running and alive() and Vend.RunId == runId end
    local home = Guard.worldName()
    Vend.Home = home
    Vend.Soft = 0
    if #Vend.waitWorld(home, live) == 0 then
        if live() then Vend.stop("No owned vendings in this world (run inside vending world)") end
        return
    end
    while live() do
        task.wait()
        if Vend.Mode == VEND_EMPTY then
            -- ===== empty mode =====
            if Guard.worldName() ~= home then
                if not Vend.travel(home, nil) then
                    if not Vend.soft("Failed to return to vending world " .. home, live) then break end
                    continue
                end
            end
            local hasPoint = Vend.hasPoint()
            local list = {}
            local all = Vend.waitWorld(home, live)
            if #all == 0 and live() then
                if not Vend.soft("Your vendings in " .. home .. " could not be read", live) then break end
                pcall(goWorld, home, nil) -- re-enter so world data reloads
                continue
            end
            local skipped = {}
            for _, m in ipairs(all) do
                if m.id and m.stock > 0 then
                    if not Vend.allow(m.id) then
                        skipped[#skipped + 1] = itemName(m.id) .. " x" .. m.stock
                    elseif (Vend.Fail[m.x .. "," .. m.y] or 0) < 4 then
                        list[#list + 1] = m
                    end
                end
            end
            if #list == 0 and not Vend.Confirm then
                -- double-check shortly (server stock data may lag)
                Vend.Confirm = true
                Vend.Status = "Rechecking vending contents..."
                Vend.sleep(1.5, live)
                continue
            end
            Vend.Confirm = false
            if #list == 0 then
                -- finished: bring leftovers to drop point (if set)
                if hasPoint and next(Vend.Carry) then
                    local ok, why = Vend.dropTrip(live, home)
                    if why == "home" or not ok then
                        if not Vend.soft(why == "home" and ("Failed to return to vending world " .. home)
                            or ("Vendings empty, but drop failed: " .. Vend.Status), live) then break end
                        continue
                    end
                    Vend.Soft = 0
                end
                table.clear(Vend.Carry)
                if next(Vend.Fail) then
                    Vend.stop("Done, some vendings failed to withdraw")
                elseif #skipped > 0 then
                    Vend.stop("Selected items finished. Skipped (not selected): "
                        .. table.concat(skipped, ", ", 1, math.min(#skipped, 4))
                        .. ((#skipped > 4) and (" +" .. (#skipped - 4)) or "")
                        .. ". Clear item filter to take all")
                else
                    Vend.stop("All vendings are now empty")
                end
                break
            end
            local full = false
            for _, m in ipairs(Vend.sortNear(list)) do
                if not live() then break end
                local room = 200
                if Refs.Inv then
                    local okr, r = pcall(function() return Refs.Inv:room(m.id) end)
                    if okr and type(r) == "number" then room = r end
                end
                if room <= 0 then
                    full = true
                    break
                end
                Vend.Status = ("To vending (%d,%d): take %s"):format(m.x, m.y, itemName(m.id))
                local key = m.x .. "," .. m.y
                if Vend.goTo(m) then
                    local before = invCount(m.id)
                    local okc = Vend.call("empty", m.x, m.y)
                    task.wait(0.4)
                    local got = invCount(m.id) - before
                    if got > 0 then
                        Vend.Soft = 0
                        Vend.Taken += got
                        Vend.Carry[m.id] = (Vend.Carry[m.id] or 0) + got
                        Vend.Fail[key] = nil
                        Vend.Status = ("Took %s x%d from (%d,%d)"):format(itemName(m.id), got, m.x, m.y)
                        if got < m.stock then
                            -- bag cannot fit all: drop at drop point first, then take the rest
                            full = true
                            break
                        end
                    else
                        Vend.Fail[key] = (Vend.Fail[key] or 0) + 1
                        if not okc and next(Vend.Carry) then
                            full = true -- bag likely full: drop at drop point first
                            break
                        end
                        Vend.sleep(1, live) -- server lag (ping): pause before retry
                    end
                else
                    Vend.Fail[key] = (Vend.Fail[key] or 0) + 1
                    Vend.Status = ("Cannot reach vending (%d,%d)"):format(m.x, m.y)
                end
            end
            if not live() then break end
            if full then
                if not hasPoint then
                    Vend.stop("Bag full: set vending drop point (WORLD / WORLD:ID / save XY position)")
                    break
                end
                if not next(Vend.Carry) then
                    Vend.stop("Bag full with other items, clear bag first")
                    break
                end
                local ok, why = Vend.dropTrip(live, home)
                if why == "home" or not ok then
                    -- keep item tracked, retry dropping next cycle
                    if not Vend.soft(why == "home" and ("Failed to return to vending world " .. home)
                        or ("Drop failed: " .. Vend.Status), live) then break end
                    continue
                end
                Vend.Soft = 0
                table.clear(Vend.Carry)
                table.clear(Vend.Fail)
            end
        else
            -- ===== restock from drops =====
            if Guard.worldName() == home then
                Vend.waitWorld(home, live)
                local done, tried = Vend.stockAll(live)
                if not live() then break end
                if tried > 0 and done == 0 then
                    if not Vend.soft("Failed to add stock: " .. Vend.Status, live) then break end
                    continue
                else
                    if done > 0 then Vend.Soft = 0 end
                end
            end
            local want, empty, sold = Vend.wanted()
            if not next(want) and empty == 0 then
                Vend.Status = Vend.filtered() and "Vendings for selected items are full / none selling them yet"
                    or "All vendings full / none selling items yet"
                Vend.sleep(4, live)
                continue
            end
            local name, door = Vend.point()
            if name == "" then name = home end
            if Guard.worldName() ~= name or door then
                if not (Guard.worldName() == name and Vend.AtPoint) then
                    Vend.Status = "Going to " .. name .. (door and (":" .. door) or "") .. " collect drops"
                    local ok, err = Vend.travel(name, door)
                    if not ok then
                        Vend.Status = "Failed to reach drop point: " .. tostring(err)
                        Vend.sleep(10, live)
                        continue
                    end
                    Vend.AtPoint = true
                end
            end
            Vend.goSpot(live)
            -- wait at drop point until pickup arrives (avoids unnecessary world hops)
            local got = 0
            while live() do
                Vend.stepAway(live)
                got += Vend.pickHere(live, want, empty, sold)
                local carry = false
                for id in pairs(want) do
                    if invCount(id) > 0 then
                        carry = true
                        break
                    end
                end
                if not carry then
                    for id, cnt in pairs(Vend.Picked) do
                        if cnt > 0 and invCount(id) > 0 then
                            carry = true
                            break
                        end
                    end
                end
                if carry then break end
                Vend.Status = "Waiting for new drops at " .. Guard.worldName() .. "..."
                Vend.sleep(0.5, live)
            end
            if not live() then break end
            Vend.AtPoint = false
            if Guard.worldName() ~= home then
                Vend.Status = "Returning to " .. home .. " to restock"
                local okh = Vend.travel(home, nil)
                if not okh then
                    if not Vend.soft("Failed to return to vending world " .. home, live) then break end
                    continue
                end
            end
        end
    end
    releaseInput()
end

function Vend.stop(reason)
    Vend.Running = false
    Vend.AtPoint = false
    Move.NoZone = false
    autoEnd()
    releaseInput()
    Vend.Status = reason or "Stopped"
    Vend.Confirm = false
    if UI.VendToggle then UI.later("vendToggle", function() UI.VendToggle:Set(false) end) end
    if reason then
        notify("Vending", reason, 5)
        if not string.find(reason, "^Stopped") then Hook.send("factory", "Vending: " .. reason) end
    end
end

function Vend.start()
    if Vend.Running then return end
    if WorldFinder.Busy then notify("World Finder", "Stop hunting before running farming", 3) return end
    if AutoDrop.Busy then notify("Auto Drop", "Wait for the drop trip to finish", 3) return end
    local err
    if not Refs.World then
        err = "World data not found. Press 'Connect to game'"
    elseif not Session.bindMovement(true) then
        err = "Game movement controls (WorldMenu.isDown) not found"
    elseif not playerState() then
        err = "You are not in a world yet"
    elseif type(rawget(Refs.World, "vendCall")) ~= "function" then
        err = "Game vending function not found"
    end
    if err then
        notify("Vending", err, 4)
        if UI.VendToggle then pcall(function() UI.VendToggle:Set(false) end) end
        return
    end
    if State.Running and not State.Override then stopFarm("Stopped because Vending started") end
    if Clear.Running then stopClear("Stopped because Vending started") end
    if Farmer.Running then stopFarmer("Stopped because Vending started") end
    if Splice.Running and Splice.stop then Splice.stop("Stopped because Vending started") end
    if Factory.Running then Factory.stop("Stopped because Vending started") end
    if Build.Running and Build.stop then Build.stop("Stopped because Vending started") end
    table.clear(Vend.Carry)
    table.clear(Vend.Picked)
    table.clear(Vend.Fail)
    table.clear(BadEdge)
    Vend.FailRuns = 0
    Vend.AtPoint = false
    Vend.Running = true
    Vend.RunId = (Vend.RunId or 0) + 1
    Vend.Status = "Starting..."
    autoBegin()
    if UI.VendToggle then pcall(function() UI.VendToggle:Set(true) end) end
    local id = Vend.RunId
    task.spawn(function()
        local ok, e = pcall(vendLoop, id)
        if not ok then
            warn("[n4th] Vending error: " .. tostring(e))
            if Vend.Running then Vend.stop("Error: " .. tostring(e)) end
        end
    end)
end
Auto.VEND_MODES = { VEND_STOCK, VEND_EMPTY }

---------------------------------------------------------------------
-- BUILD LAND
---------------------------------------------------------------------
-- How it works (just like building a manual farm in a fresh dirt world):
--   1. DIG     : snake downward from surface to right above bedrock.
--                Dig 1-tile gaps above each row (trees & walkway), alternating left & right
--                stair openings, breaking dirt background as well.
--                Soil on land rows is left intact = free pre-built land.
--   2. PLACE   : empty rows (above ground) are placed from BOTTOM to top.
--                First block placed from stair edge, then row becomes a bridge:
--                stand at edge, place blocks ahead one by one, walk forward, repeat to end.
--   3. PRODUCE : out of blocks -> collect leftover dug drops on land, plant 1 row,
--                place-break blocks to RIGHT of character for seeds (like Factory),
--                collect, harvest. Reach 190 blocks -> resume placing, keep 10 blocks.
--   4. CLEAN   : scan any remaining drops on land and walk to pick them up with A*.
local BuildFail = {}

local function overlapsPlayer(x, y, s)
    return x + 1 > s.x - 0.3 and x < s.x + 0.3 and y + 1 > s.y - 0.95 and y < s.y
end

function Build.dirtBlock()
    if not Session.ItemDBSource then return nil end
    if Build.DirtId ~= nil then return Build.DirtId or nil end
    for id, item in pairs(Session.ItemDBSource) do
        if type(id) == "number" and type(item) == "table" and item.solid and item.kind ~= "seed"
            and type(item.name) == "string" and item.name:lower() == "dirt" then
            Build.DirtId = id
            return id
        end
    end
    Build.DirtId = false
end

function Build.canDigTerrain(id)
    local item = ItemDB[id]
    if not item or type(item.name) ~= "string" or not clearCanBreak(id) then return false end
    local name = item.name:lower()
    return name == "dirt" or name == "rock" or name == "lava"
end

function Build.dirtWorldMatches(run)
    local w = Refs.World
    return w == run.world and w.fg == run.grid and w.name == run.worldName
end

function Build.allowDirtHit(x, y, id, layer)
    local run = Build.DirtRun
    if not Build.Running or not run or not Build.dirtWorldMatches(run) or raymanOn()
        or tileAt(layer, x, y) ~= id or not canWorkAt(x, y) then return false end
    local s = playerState()
    if not s or not s.grounded or not stateReaches(s, x, y, punchReach() - 0.08) then return false end
    if layer == "bg" then return fgIdAt(x, y) == 0 and clearCanBreak(id) end
    return Build.canDigTerrain(id)
end

function Build.placeReach()
    local range = buildReach()
    if Build.DirtRun then return math.min(2, range) end
    return range - 0.08
end

function Build.activeBlock()
    return Build.DirtRun and Build.DirtRun.block or Build.BlockId
end

local function placeBuild(t, s)
    local id = Build.activeBlock()
    if Build.DirtRun and not Build.dirtWorldMatches(Build.DirtRun) then return false end
    if invCount(id) <= (Build.Reserve or 0) or overlapsPlayer(t.x, t.y, s)
        or not stateReaches(s, t.x, t.y, Build.placeReach()) then return false end
    if not placeOk(t.x, t.y) then
        skipTile(Build.Skip, t.idx, 120)
        return false
    end
    local dirt = Build.DirtRun
    if not sendSetTile("fg", t.x, t.y, id, dirt ~= nil) then return false end
    if dirt then
        local deadline = os.clock() + 0.75
        while fgIdAt(t.x, t.y) == 0 and os.clock() < deadline do
            task.wait(0.05)
            if not Build.Running or Build.DirtRun ~= dirt or not Build.dirtWorldMatches(dirt) then return false end
        end
        if fgIdAt(t.x, t.y) ~= id then
            skipTile(Build.Skip, t.idx, 5)
            return false
        end
    end
    pcall(function() Refs.Inv:remove(id, 1) end)
    Build.Placed += 1
    Build.Status = ("Place %s (%d,%d)"):format(itemName(id), t.x, t.y)
    return true
end

-- Land plan: rows, block columns & stair shafts per row
function Build.plan(dirt)
    local w = Refs.World
    if not w then return nil end
    local bounds = dirt or Land
    local rows = landRows(bounds)
    if #rows == 0 then return nil end
    local W = w.w
    local P = {
        rows = rows, K = #rows, W = W, dirt = dirt ~= nil,
        placeOnly = dirt ~= nil and dirt.Dig == false,
        x0 = math.clamp(math.floor(math.min(bounds.X0, bounds.X1)), 0, W - 1),
        x1 = math.clamp(math.floor(math.max(bounds.X0, bounds.X1)), 0, W - 1),
        cols = {}, isLand = {}, holes = {},
    }
    local stairOffset = 0
    if dirt then
        P.surface = Build.findSurface(P)
        if P.surface == math.huge then
            local s = playerState()
            if bounds.Y1 and bounds.Y1 >= 1 then
                P.surface = bounds.Y1 + 1
            elseif s and s.grounded then
                local _, y = startNode(s)
                P.surface = y + 1
            else
                P.surface = w.h - 1
            end
        end
        if P.placeOnly and bounds.Y0 == 2 then
            -- If top boundary is still default, match parity of existing Dirt rows.
            local even, odd = 0, 0
            local dirtId = Build.dirtBlock()
            local width = P.x1 - P.x0 + 1
            for y = 2, math.min(P.surface - 1, rows[#rows]) do
                local blocks, airAbove = 0, 0
                for x = P.x0, P.x1 do
                    if fgIdAt(x, y) == dirtId then blocks += 1 end
                    if fgIdAt(x, y - 1) == 0 then airAbove += 1 end
                end
                if blocks * 2 > width and airAbove * 2 > width then
                    if y % 2 == 0 then even += 1 else odd += 1 end
                end
            end
            if odd >= 2 and odd > even then
                local aligned = table.clone(bounds)
                aligned.Y0 = 3
                local adjusted = landRows(aligned)
                if #adjusted > 0 then
                    rows = adjusted
                    P.rows, P.K = rows, #rows
                end
            end
        end
        P.placeK = 0
        for _, y in ipairs(rows) do
            if y >= P.surface then break end
            P.placeK += 1
        end
        if P.placeOnly and P.x1 - P.x0 >= 4 then
            local score = 0
            local dirtId = Build.dirtBlock()
            for k = 1, P.placeK do
                local y = rows[k]
                local phase = k % 2 == 1 and 1 or -1
                for _, edge in ipairs({ P.x0, P.x1 }) do
                    local outer = fgIdAt(edge, y)
                    local inner = fgIdAt(edge + (edge == P.x0 and 1 or -1), y)
                    if outer == 0 and inner == dirtId then score += phase end
                    if outer == dirtId and inner == 0 then score -= phase end
                end
            end
            if score <= -2 then stairOffset = 1 end
        end
    end
    for k = 1, #rows do
        local cols = landCols(k - 1 + stairOffset, P.x0, P.x1)
        local set = {}
        for _, x in ipairs(cols) do set[x] = true end
        local holes = {}
        for x = P.x0, P.x1 do
            if not set[x] then holes[#holes + 1] = x end
        end
        P.cols[k], P.isLand[k], P.holes[k] = cols, set, holes
    end
    return P
end

-- Natural ground surface: first row where it and the row beneath are mostly solid
function Build.findSurface(P)
    local w = Refs.World
    local span = P.x1 - P.x0 + 1
    local function full(y)
        local n = 0
        for x = P.x0, P.x1 do
            local it = ItemDB[fgIdAt(x, y)]
            if it and it.solid and it.kind ~= "seed" then n += 1 end
        end
        return n * 2 > span
    end
    for y = math.max(0, P.rows[1] - 1), w.h - 2 do
        if full(y) and full(y + 1) then return y end
    end
    return math.huge
end

-- What still needs digging at this tile: "fg" (dirt / rock / lava), "bg" (dirt bg), nil = done.
-- Trees & non-solid objects left alone.
function Build.carveLayer(x, y, W, dirt)
    local fg = fgIdAt(x, y)
    if fg ~= 0 then
        if dirt then return Build.canDigTerrain(fg) and "fg" or nil end
        local it = ItemDB[fg]
        if it and it.kind ~= "seed" and (it.solid or it.deadly or it.hurts) and canBreak(fg) then return "fg" end
        return nil
    end
    -- Gaps already dug before re-executing may still contain background.
    if dirt then return clearCanBreak(tileAt("bg", x, y)) and "bg" or nil end
    if y >= (Build.Surface or math.huge) or Build.Carved[y * W + x] then
        local bg = tileAt("bg", x, y)
        if bg and bg ~= 0 and canBreak(bg) then return "bg" end
    end
    return nil
end

-- Snake dig order, top to bottom (only tiles still needing digging):
--   gap row 1 left -> right, drop through right shaft,
--   gap row 2 right -> left, drop through left shaft, etc.
--   Starting-end shaft is opened from the gap below (prevents falling early).
--   Holes (caves) / lava in underground land floors are patched while passing.
function Build.carveList(P, live)
    local W, list, kept = P.W, {}, 0
    if P.placeOnly then return list, kept end
    local budget, visited = { next = os.clock() + 0.0015 }, 0
    local function add(x, y, kind)
        if y < 0 then return end
        if Build.carveLayer(x, y, W, P.dirt) then
            list[#list + 1] = { x = x, y = y, idx = y * W + x, kind = kind }
        elseif P.dirt then
            local fg = fgIdAt(x, y)
            if fg ~= 0 then
                local item = ItemDB[fg]
                if not item or item.kind ~= "seed" then kept += 1 end
            elseif (tileAt("bg", x, y) or 0) ~= 0 then
                kept += 1
            end
        end
    end
    local surf = Build.Surface or math.huge
    local block = P.dirt and Build.activeBlock() or Build.BlockId
    local canFill = block ~= nil and invCount(block) > 0
    local function fill(x, y)
        if y < surf then return end
        local id = fgIdAt(x, y)
        local need = false
        if id == 0 then
            need = canFill
        elseif not Build.done(x, y) then
            local it = ItemDB[id]
            need = (not P.dirt or Build.canDigTerrain(id)) and it ~= nil and it.kind ~= "seed" and (it.deadly or it.hurts) and canBreak(id) and true or false
        end
        if need then list[#list + 1] = { x = x, y = y, idx = y * W + x, kind = "fill" } end
    end
    for k = 1, P.K do
        local y = P.rows[k]
        local d = ((k - 1) % 2 == 0) and 1 or -1
        local up = nil -- starting-end shaft for the row above, opened from this gap
        if k > 1 and #P.holes[k - 1] > 0 then
            local ph = P.holes[k - 1]
            up = (d == -1) and ph[1] or ph[#ph]
        end
        local a, b = P.x0, P.x1
        if d == -1 then a, b = P.x1, P.x0 end
        local L = P.isLand[k]
        for x = a, b, d do
            if P.dirt then
                visited += 1
                Session.scanStep(budget, visited)
                if live and not live() then return list, kept end
            end
            if not P.dirt and L[x] then fill(x, y) end -- patch floor while digging in Build Land
            add(x, y - 1, "gap")
            if x == up then add(x, P.rows[k - 1], "hole") end
        end
        -- exit shaft for this row = drop down to gap row below
        if k < P.K and #P.holes[k] > 0 then
            local h = P.holes[k]
            add((d == 1) and h[#h] or h[1], y, "hole")
        end
    end
    return list, kept
end

-- Walk (A*) to a position within reach of one of the targets.
-- maxY = standing Y cannot be below this, noSelf = never stand inside target tile.
-- Returns: "move" | "nopath" | "wait"
function Build.goNear(targets, R, maxY, noSelf, live)
    local w = Refs.World
    local s = playerState()
    if not w or not s then return "wait" end
    local sx, sy = startNode(s)
    local goals = { maxY = maxY, noSelf = noSelf, live = live }
    if Build.DirtRun then goals.startState = s end
    for _, t in ipairs(targets) do goals[t.idx] = true end
    local f = targets[1]
    setMoveStatus(("Pathfinding A* to (%d,%d)"):format(f.x, f.y))
    local path = astar(sx, sy, goals, f.x, f.y, R, false)
    if live and not live() then return "wait" end
    if not path then
        releaseInput()
        return "nopath"
    end
    local fails = BuildFail[f.idx] or 0
    if #path == 0 then
        execWalk(sx, sy) -- already on spot but out of reach: center on tile
        fails += 1
    elseif not followPath(path) then
        fails += 1
    else
        fails = 0
    end
    if live and not live() then return "wait" end
    releaseInput()
    if fails >= 4 then
        fails = 0
        for _, t in ipairs(targets) do skipTile(Build.Skip, t.idx, 30) end
    end
    BuildFail[f.idx] = (fails > 0) and fails or nil
    return "move"
end

-- Punch 1 tile until clear (foreground block first, then background).
-- Returns: "done" | "fall" (character fell) | "skip" | "stop"
function Build.carveTile(t, live)
    local hits, maxHits = 0, nil
    local dirt = Build.DirtRun ~= nil
    while live() and alive() do
        local layer = Build.carveLayer(t.x, t.y, Refs.World.w, dirt)
        if not layer then return "done" end
        local id = (layer == "fg") and fgIdAt(t.x, t.y) or (tileAt("bg", t.x, t.y) or 0)
        maxHits = maxHits or (hitsNeeded(id) * 3 + 6)
        local r = tryBreak(t.x, t.y, layer == "bg", nil, dirt and Build.allowDirtHit or nil)
        if r == nil then
            skipTile(Build.Skip, t.idx, 60)
            return "skip"
        end
        if r == "broke" then
            if layer == "fg" then Build.Carved[t.idx] = true end
            Build.Dug += 1
            Build.Status = ("Dig %s (%d,%d)"):format(itemName(id), t.x, t.y)
            local bt = (Build.BreakTimes[t.idx] or 0) + 1
            Build.BreakTimes[t.idx] = bt
            if bt > 8 then -- server keeps reverting this tile
                skipTile(Build.Skip, t.idx, 120)
                return "skip"
            end
            hits, maxHits = 0, nil
            local s = playerState()
            if not s or not s.grounded then
                waitAuto(State.BreakMs)
                return "fall"
            end
        else
            hits += 1
            Build.Status = ("Punch %s (%d,%d)"):format(itemName(id), t.x, t.y)
            if hits > maxHits then
                skipTile(Build.Skip, t.idx, 45)
                return "skip"
            end
        end
        if not waitAuto(State.BreakMs) then return "stop" end
    end
    return "stop"
end

-- Hollow / lava land floor: break if needed, then place block.
-- Returns: "done" | "fall" | "skip" | "stop"
function Build.fillTile(t, live, dirt)
    local id = fgIdAt(t.x, t.y)
    if id ~= 0 and not Build.done(t.x, t.y) then
        Build.Status = ("Break %s in floor (%d,%d)"):format(itemName(id), t.x, t.y)
        for _ = 1, 40 do
            if not live() then return "stop" end
            local r = tryBreak(t.x, t.y, false, nil, dirt and Build.allowDirtHit or nil)
            if r == nil then
                skipTile(Build.Skip, t.idx, 60)
                return "skip"
            end
            if r == "broke" then break end
            if not waitAuto(State.BreakMs) then return "stop" end
        end
        local cur = playerState()
        if not cur or not cur.grounded then return "fall" end
    end
    if not live() then return "stop" end
    if fgIdAt(t.x, t.y) == 0 then
        local cur = playerState()
        if not cur or not cur.grounded then return "fall" end
        if not stateReaches(cur, t.x, t.y, Build.placeReach()) or overlapsPlayer(t.x, t.y, cur) then
            return "move"
        end
        if invCount(Build.activeBlock()) <= 0 or not placeBuild(t, cur) then
            skipTile(Build.Skip, t.idx, 30)
            return "skip"
        end
        Build.Status = ("Patch land floor (%d,%d)"):format(t.x, t.y)
        if not waitAuto(State.PlaceMs) then return "stop" end
    end
    return "done"
end

-- 1 dig step. Returns: "work" | "move" | "wait" | "none"
function Build.carveStep(P, list, live)
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then
        releaseInput()
        task.wait(0.5)
        return "wait"
    end
    if not s.grounded then
        releaseInput()
        Move.airCheck(s)
        task.wait()
        return "wait"
    end
    Move.AirAt = nil
    releaseInput()
    local hitR, placeR = punchReach() - 0.08, Build.placeReach()
    local now = os.clock()
    local fi = nil
    for i, t in ipairs(list) do
        if not skipped(Build.Skip, t.idx, now) then
            fi = i
            break
        end
    end
    if not fi then return "none" end
    local work = list
    local first = list[fi]
    if P.dirt and first.kind == "gap" then
        work = {}
        for _, t in ipairs(list) do
            if t.kind == "gap" and t.y == first.y and not skipped(Build.Skip, t.idx, now) then
                work[#work + 1] = t
            end
        end
        table.sort(work, function(a, b) return abs(a.x + 0.5 - s.x) < abs(b.x + 0.5 - s.x) end)
        fi = 1
    end
    -- break reachable tiles in order (stop at first unreachable tile)
    local did = 0
    for j = fi, math.min(#work, fi + 5) do
        local t = work[j]
        if not skipped(Build.Skip, t.idx, now) then
            local cur = playerState()
            local R = (t.kind == "fill" and fgIdAt(t.x, t.y) == 0) and placeR or hitR
            if not cur or cur.dead or not cur.grounded or not stateReaches(cur, t.x, t.y, R) then break end
            if t.kind == "fill" and overlapsPlayer(t.x, t.y, cur) then break end -- standing on its shaft: step aside first
            if not canWorkAt(t.x, t.y) then
                skipTile(Build.Skip, t.idx, 300) -- locked by someone else
            elseif t.kind == "fill" then
                did += 1
                if Build.fillTile(t, live, P.dirt) ~= "done" then break end
            else
                -- own footing block: break only if resulting fall is short & safe
                local foot = floor(cur.y + 0.01)
                if t.y == foot and t.x >= floor(cur.x - 0.3) and t.x <= floor(cur.x + 0.3 - 0.0001) then
                    local d = fallAfterBreak(cur, t.x, foot)
                    if d == nil or d > 3 then
                        skipTile(Build.Skip, t.idx, 20)
                        break
                    end
                end
                did += 1
                if Build.carveTile(t, live) ~= "done" then break end
            end
        end
    end
    if did > 0 then return "work" end
    local F = work[fi]
    local filling = F.kind == "fill"
    local R = (filling and fgIdAt(F.x, F.y) == 0) and placeR or hitR
    local r = Build.goNear(work ~= list and work or { F }, R, nil, filling, live)
    if r == "nopath" then
        -- no path here yet: skip the rest of row briefly (avoid pathfinding every tile)
        if filling then
            skipTile(Build.Skip, F.idx, 5)
        else
            for _, t in ipairs(list) do
                if t.y == F.y then skipTile(Build.Skip, t.idx, 30) end
            end
        end
        return "move"
    end
    return r
end

-- Row entry tile: block beside stair shaft (first block of row is placed from here)
function Build.entries(P, k)
    local e = {}
    local holes, L = P.holes[k], P.isLand[k]
    if #holes == 0 then
        e[P.x0], e[P.x1] = true, true
    else
        for _, h in ipairs(holes) do
            if L[h - 1] and L[h - 2] then e[h - 1] = true end
            if L[h + 1] and L[h + 2] then e[h + 1] = true end
        end
    end
    return e
end

-- 1 place step: bottommost incomplete row first, working upward.
-- Active row doubles as bridge: stand on it and place forward.
-- Returns: "work" | "move" | "wait" | "none"
function Build.placeStep(P, live)
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then
        releaseInput()
        task.wait(0.5)
        return "wait"
    end
    if not s.grounded then
        releaseInput()
        Move.airCheck(s)
        task.wait()
        return "wait"
    end
    Move.AirAt = nil
    releaseInput()
    local W = P.W
    local id = Build.activeBlock()
    local placeR, hitR = Build.placeReach(), punchReach() - 0.08
    local now = os.clock()
    local k, T = nil, nil
    for kk = P.placeK or P.K, 1, -1 do
        local y = P.rows[kk]
        local list = {}
        local incomplete = false
        for _, x in ipairs(P.cols[kk]) do
            local idx = y * W + x
            if not Build.done(x, y) then
                incomplete = true
                if not skipped(Build.Skip, idx, now) then
                    list[#list + 1] = { x = x, y = y, idx = idx }
                end
            end
        end
        if #list > 0 then
            k, T = kk, list
            break
        end
        if P.dirt and incomplete then return "none" end
    end
    if not k then return "none" end
    local y = P.rows[k]
    if P.dirt then
        local count = P.placeK or P.K
        Build.Phase = ("Placing Dirt from below: row %d/%d (Y %d)"):format(count - k + 1, count, y)
    end
    local px = s.x
    table.sort(T, function(a, b) return abs(a.x + 0.5 - px) < abs(b.x + 0.5 - px) end)
    local _, sy = startNode(s)
    local onRow = sy <= y - 1 -- standing on this row (bridge)
    local under = Build.Under[k] ~= nil and now < Build.Under[k]
    local entry = Build.entries(P, k)
    local hasAny = false
    for _, x in ipairs(P.cols[k]) do
        if Build.done(x, y) then
            hasAny = true
            break
        end
    end

    -- place reachable tiles, nearest first (max 2 per step)
    local done = 0
    for _, t in ipairs(T) do
        if done >= 2 then break end
        if not live() then return "wait" end
        local cur = playerState()
        if not cur or not cur.grounded then break end
        local occupied = fgIdAt(t.x, t.y) ~= 0
        local R = occupied and hitR or placeR
        if stateReaches(cur, t.x, t.y, R) and (P.dirt or onRow or under or entry[t.x]) then
            if occupied then
                if P.placeOnly then
                    skipTile(Build.Skip, t.idx, 30)
                    continue
                end
                -- land tile occupied by tree / lava / decor: break first
                if not canWorkAt(t.x, t.y) or (P.dirt and not Build.canDigTerrain(fgIdAt(t.x, t.y))) then
                    skipTile(Build.Skip, t.idx, 300)
                else
                    Build.Status = ("Clear land tile (%d,%d)"):format(t.x, t.y)
                    local broke = false
                    for _ = 1, 40 do
                        if not live() then return "wait" end
                        local r = tryBreak(t.x, t.y, false, nil, P.dirt and Build.allowDirtHit or nil)
                        if r == nil then break end -- unbreakable (lock, door, etc.)
                        if r == "broke" then
                            broke = true
                            break
                        end
                        if not waitAuto(State.BreakMs) then return "wait" end
                    end
                    -- cannot clear: avoid revisiting repeatedly (prevents long back-and-forth trips)
                    if not broke then skipTile(Build.Skip, t.idx, 1800) end
                    waitNearDrops(0.5)
                end
                return "work"
            end
            if placeBuild(t, cur) then
                done += 1
                if entry[t.x] then Build.Under[k] = nil end
                if not waitAuto(State.PlaceMs) then return "wait" end
            elseif invCount(id) <= (Build.Reserve or 0) then
                break
            end
        end
    end
    if done > 0 then return "work" end
    if invCount(id) <= (Build.Reserve or 0) then return "none" end

    local RR = P.dirt and placeR or placeR - 0.27
    -- climb onto this row and place forward (row acts as bridge)
    if not P.dirt and hasAny and not under then
        local r = Build.goNear(T, RR, y - 1, true, live)
        if r ~= "nopath" then return r end
        Build.Under[k] = now + 60 -- cannot climb onto this row: temporarily place from below
        under = true
    end
    -- no footing yet: go to stair edge, place row's first block from there
    if not P.dirt and not under then
        local E = {}
        for _, t in ipairs(T) do
            if entry[t.x] then E[#E + 1] = t end
        end
        if #E > 0 then
            local r = Build.goNear(E, RR, nil, true, live)
            if r ~= "nopath" then return r end
        end
        Build.Under[k] = now + 60
    end
    local r = Build.goNear(T, RR, nil, true, live)
    if r == "nopath" then
        for _, t in ipairs(T) do skipTile(Build.Skip, t.idx, 30) end
        Build.Status = ("Row y %d unreachable, skipping briefly"):format(y)
        return "none"
    end
    return r
end

-- ---------- Produce blocks (1 row, like Factory) ----------
function Build.cfg(o, harvest, plant)
    return {
        run = o.target and function() return o.live() and invCount(o.block) < o.target end or o.live,
        harvest = harvest,
        plant = plant and invCount(o.seed) > 0,
        seed = o.seed,
        only = o.seed,           -- harvest only trees of this block's seed
        allowHarvest = o.allowHarvest,
        placeReach = o.plan and Build.placeReach() or nil,
        plantArea = o.plan and o.area or nil,
        bulkPlant = o.plan ~= nil,
        skip = Build.FieldSkip,
        hms = Farmer.HarvestMs,
        pms = Farmer.PlantMs,
        area = o.area or inLandRect, -- only trees inside land rows (row by row)
        plantSet = o.plantSet,   -- plant only on production row
        exclude = o.exclude,
        row = Build.Row,
        collect = true,
        status = function(t) Build.Status = t end,
        onHarvest = function() Build.Harvested += 1 end,
        onPlant = function() Build.Planted += 1 end,
    }
end

-- Production row: complete row directly below the row being placed
-- (fallback: nearest complete row to character)
function Build.prodRow(P)
    local function complete(k)
        local y = P.rows[k]
        for _, x in ipairs(P.cols[k]) do
            if not Build.done(x, y) then return false end
        end
        return true
    end
    for k = P.placeK or P.K, 1, -1 do
        if not complete(k) then
            if k < P.K then return k + 1 end
            break
        end
    end
    local s = playerState()
    local best, bd = nil, nil
    for k = 1, P.K do
        if complete(k) then
            local d = s and abs(P.rows[k] - s.y) or k
            if not bd or d < bd then best, bd = k, d end
        end
    end
    return best
end

-- Production row plant spots + place-break position.
-- If Land break spot & grid are set (Land tab / Grid Land mode): use them.
-- Unset: auto-stand near right end of row, block to RIGHT of character.
function Build.prodSpots(P, k)
    local W, y = P.W, P.rows[k]
    local gy = y - 1
    local o = { set = {} }
    local L = P.isLand[k]
    local skip = {}
    if not P.dirt and Build.BreakX >= 0 and next(Build.Tiles) ~= nil then
        skip[Build.BreakY * W + Build.BreakX] = true -- do not plant on standing spot & break tiles
        for key in pairs(Build.Tiles) do
            local dx, dy = string.match(key, "^(-?%d+),(-?%d+)$")
            if dx then skip[(Build.BreakY + tonumber(dy)) * W + Build.BreakX + tonumber(dx)] = true end
        end
    else
        local bx = P.x1 - 3
        if gy >= 0 and bx > P.x0 and L[bx] and L[bx + 1] and Build.done(bx, y) and Build.done(bx + 1, y) then
            o.stand = { x = bx, y = gy }
            o.tile = { x = bx + 1, y = gy }
            skip[gy * W + bx], skip[gy * W + bx + 1] = true, true
        end
    end
    if gy >= 0 then
        for _, x in ipairs(P.cols[k]) do
            local idx = gy * W + x
            if not skip[idx] then o.set[idx] = true end
        end
    end
    return o
end

-- Production break session at land spot & grid (Auto Farm engine: multi-tile, touch drops per cycle).
-- Stop when seeds suffice to fill the row, blocks run out, or 8s pass without action.
function Build.breakSession(o)
    local s = playerState()
    if not s then return false end
    local hx, hy = startNode(s)
    if hx ~= Build.BreakX or hy ~= Build.BreakY then
        Build.Status = ("Walking to land break position (%d,%d)"):format(Build.BreakX, Build.BreakY)
        if not walkTo(Build.BreakX, Build.BreakY, 45) then
            Build.Status = "Failed to walk to land break position, using auto spot"
            return nil
        end
    end
    if not o.live() then return false end
    local before = invCount(o.seed)
    local want = math.max(1, Build.freeSpots(o))
    State.Override = { offsets = Build.Tiles, block = o.block, mode = "Place + Break" }
    State.Quiet = true
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    local id = State.RunId
    local lastActs, lastActAt = State.Placed + State.Broken, os.clock()
    task.spawn(function() -- break session watchdog
        while State.Running and State.RunId == id do
            task.wait(0.5)
            local acts = State.Placed + State.Broken
            if acts ~= lastActs then lastActs, lastActAt = acts, os.clock() end
            if not o.live() or invCount(o.seed) >= before + want or invCount(o.block) <= 0
                or os.clock() - lastActAt > 8 then
                State.Running = false
            end
        end
    end)
    Build.Status = ("Break %s at land break spot (%d,%d)"):format(itemName(o.block), Build.BreakX, Build.BreakY)
    local ok, e = pcall(farmLoop, id)
    if not ok then warn("[n4th] Land break error: " .. tostring(e)) end
    State.Running = false
    State.Override = nil
    State.Quiet = false
    return invCount(o.seed) > before
end

-- Remaining empty plant spots on production row
function Build.freeSpots(o)
    local w = Refs.World
    if not w then return 0 end
    if not o.plantSet then
        local n, nxt = readyTreeCount(true, o.seed, o.plan)
        return (n == 0 and nxt == nil) and 1 or 0
    end
    local n = 0
    for idx in pairs(o.plantSet) do
        local x, y = idx % w.w, idx // w.w
        if fgIdAt(x, y) == 0 and plantSpotOk(x, y, o.seed) then n += 1 end
    end
    return n
end

-- Place then break block to RIGHT of character for seeds (like Factory)
function Build.bootstrap(o)
    local w = Refs.World
    if not w or invCount(o.block) <= 0 then return false end
    if not o.plan and Build.BreakX >= 0 and next(Build.Tiles) ~= nil then
        local r = Build.breakSession(o)
        if r ~= nil then return r end -- nil = cannot reach break position: use automatic fallback
    end
    local spot = nil
    if o.stand then
        local s0 = playerState()
        local hx, hy = nil, nil
        if s0 then hx, hy = startNode(s0) end
        if hx ~= o.stand.x or hy ~= o.stand.y then
            Build.Status = ("Walking to place-break spot (%d,%d)"):format(o.stand.x, o.stand.y)
            if not walkTo(o.stand.x, o.stand.y, 45, o.live) then o.stand = nil end
        end
        if o.stand and o.tile then
            local id = fgIdAt(o.tile.x, o.tile.y)
            if id == o.block or (id == 0 and placeOk(o.tile.x, o.tile.y)) then spot = o.tile end
        end
    end
    if not o.live() then return false end
    local s = playerState()
    if not s or not s.grounded then return false end
    if not spot then
        local R = o.plan and math.min(punchReach() - 0.08, Build.placeReach()) or farmReach() - 0.08
        local ty = floor(s.y - 0.475)
        for _, dx in ipairs({ 1, 2, -1, -2 }) do -- right first
            local tx = floor(s.x) + dx
            local idx = ty * w.w + tx
            if tx >= 0 and tx < w.w and ty >= 0 and fgIdAt(tx, ty) == 0
                and (not o.area or o.area(tx, ty))
                and not (o.plantSet and o.plantSet[idx]) and not (o.exclude and o.exclude[idx])
                and stateReaches(s, tx, ty, R) and not overlapsPlayer(tx, ty, s) and placeOk(tx, ty) then
                spot = { x = tx, y = ty }
                break
            end
        end
    end
    if not spot then return false end
    -- 1 long session (like Factory): keep placing-breaking until enough seeds to fill
    -- all empty spots on production row, or blocks run out. No mid-break harvest / plant.
    local before = invCount(o.seed)
    local want = math.max(1, Build.freeSpots(o))
    for _ = 1, 300 do
        if not o.live() or (invCount(o.block) <= 0 and fgIdAt(spot.x, spot.y) == 0) then break end
        if invCount(o.seed) >= before + want then break end
        local id = fgIdAt(spot.x, spot.y)
        if o.plan and id ~= 0 and id ~= o.block then break end
        if id == 0 then
            if o.plan then
                local cur = playerState()
                if not cur or not cur.grounded or not stateReaches(cur, spot.x, spot.y, Build.placeReach())
                    or overlapsPlayer(spot.x, spot.y, cur) or not placeOk(spot.x, spot.y) then break end
            end
            if not sendSetTile("fg", spot.x, spot.y, o.block) then break end
            pcall(function() Refs.Inv:remove(o.block, 1) end)
            PlacedAt[spot.x .. "," .. spot.y] = os.clock()
            Build.Status = ("Place & break %s for seeds (%d,%d)"):format(itemName(o.block), spot.x, spot.y)
            if not waitAuto(State.PlaceMs) then break end
        end
        for _ = 1, 40 do
            if not o.live() then break end
            local r = tryBreak(spot.x, spot.y, false, nil, o.plan and Build.allowDirtHit or nil)
            if r == nil or r == "broke" then break end
            if not waitAuto(State.BreakMs) then break end
        end
        -- wait for drops from server, then touch-collect: step in and step back
        Drops.waitSpawn({ spot })
        local s2 = playerState()
        if s2 and s2.grounded then
            local hx, hy = startNode(s2)
            if not Drops.touch(spot, hx, hy) then waitNearDrops(0.3) end
        end
    end
    return invCount(o.seed) > before
end

-- 1 produce step. Returns: "work" | "move" | "wait" | "next" | "idle" (+ seconds to ready tree, ready count)
-- Sequential cycle (like Factory), each phase finishes before next, no interruption:
--   HARVEST : harvest ALL ready trees on land (row by row), pick up drops         -> PLANT
--   PLANT   : fill all empty spots on production row                              -> BREAK / WAIT
--   BREAK   : out of seeds & row incomplete: place-break to right of character
--             until enough seeds for the row (or blocks run out)                -> PLANT
--   WAIT    : wait for trees TOGETHER (none ready within 20s)                     -> HARVEST
function Build.produceStep(o)
    o.phase = o.phase or "harvest"
    if o.phase == "harvest" then
        FC = Build.cfg(o, true, false)
        local r = fieldStep()
        if r == "idle" then
            if o.plan then o.harvestRetryAt = os.clock() + 3 end
            o.phase = "plant"
            return "next"
        end
        return r
    end
    if o.phase == "plant" then
        -- Dirt Farm keeps planting remaining gaps even while some trees are already growing.
        if invCount(o.seed) > 0 and (o.plan or Build.freeSpots(o) > 0) then
            FC = Build.cfg(o, false, true)
            local r = fieldStep()
            if r ~= "idle" then return r end
        end
        if not (o.plan and o.plan.placeOnly) and not o.broke and Build.freeSpots(o) > 0
            and invCount(o.seed) <= 0 and invCount(o.block) > 0 then
            o.phase = "break"
        else
            o.phase, o.broke = "wait", nil
        end
        return "next"
    end
    if o.phase == "break" then
        o.broke = true -- 1 break session per cycle
        o.bootAt = os.clock()
        Build.bootstrap(o)
        o.phase = "plant"
        return "work"
    end
    -- WAIT
    local n, nxt = readyTreeCount(false, o.seed, o.plan)
    if n > 0 and ((o.plan and os.clock() >= (o.harvestRetryAt or 0))
        or (not o.plan and (nxt == nil or nxt > 20))) then
        o.phase = "harvest" -- wait for batch of ready trees
        return "next"
    end
    if n == 0 and nxt == nil and Build.freeSpots(o) > 0 and os.clock() - (o.retryAt or 0) > 10 then
        -- no trees growing at all (break yielded no seeds): plant / break again
        if invCount(o.seed) > 0 or (invCount(o.block) > 0 and os.clock() - (o.bootAt or 0) > 5) then
            o.retryAt = os.clock()
            o.phase = "plant"
            return "next"
        end
    end
    return "idle", nxt, n
end

-- Collect drops across land ROW BY ROW (scan game drop list), like manual play:
--   nearest row first, sweep end to end nonstop (picked up while passing),
--   then move to next row. ids = nil (all) or { [id] = true }
function Build.sweep(P, live, ids, maxSec)
    if not Drops.list then return 0 end
    local x0, x1 = P.x0, P.x1 + 1
    local y0, y1 = math.max(0, P.rows[1] - 1), P.rows[P.K] + 1
    return Move.fetchDrops(live, 999, function(d)
        return d.x >= x0 and d.x < x1 and d.y >= y0 and d.y < y1 and (not ids or ids[d.id] == true)
    end, maxSec or 60)
end

function Build.stop(reason)
    local dirt = Build.DirtRun
    Build.Running, Build.DirtRun = false, nil
    if Factory.Running == false and State.Override then State.Running = false end
    autoEnd()
    releaseInput()
    Build.Phase = reason or "Stopped"
    local toggle = dirt and UI.DirtToggle or UI.BuildToggle
    if dirt then
        Build.DirtPhase = Build.Phase
        Build.Phase, Build.Status = dirt.previousPhase, dirt.previousStatus
    end
    if toggle then pcall(function() toggle:Set(false, false) end) end
    if reason then
        notify(dirt and "Auto Dirt Farm" or "Build Land", reason, 5)
        if not string.find(reason, "^Stopped") then Hook.send("factory", (dirt and "Auto Dirt Farm: " or "Build Land: ") .. reason) end
    end
end

local function buildLoop(runId, dirt)
    local function live()
        return Build.Running and alive() and Build.RunId == runId and (not dirt or Build.dirtWorldMatches(dirt))
    end
    local block = Build.activeBlock()
    local seed = seedOfBlock(block)
    local o = { seed = seed, block = block, live = live, plan = dirt and dirt.plan }
    local refillPending = dirt and Build.DirtRefill and Build.dirtWorldMatches(Build.DirtRefill)
    if o.plan then
        local P = o.plan
        o.dugSwept = P.placeOnly or refillPending
        o.area = function(x, y) return x >= P.x0 and x <= P.x1 and y >= P.rows[1] - 1 and y <= P.rows[P.K] end
    end
    local phase = nil
    local noneAt = nil
    while live() do
        task.wait()
        if not live() then break end
        if dirt and not o.plan.placeOnly and raymanOn() then Build.stop("Unequip Rayman before running Auto Dirt Farm") break end
        local P = o.plan or Build.plan()
        if not P then
            Build.stop("No land rows fit (check Start X / End X / Top row Y)")
            break
        end
        if Build.Surface == nil and not P.placeOnly then Build.Surface = P.surface or Build.findSurface(P) end
        local carve, kept = Build.carveList(P, live)
        if not live() then break end
        local info = landInfo(P, carve)
        if dirt then
            info.kept = kept
            Build.DirtInfo = info
        else
            Build.Info, Build.InfoAt = info, os.clock()
        end

        -- 1) DIG down first
        local r = "none"
        if #carve > 0 and not (dirt and o.dugSwept) then
            Build.Reserve = 0
            Build.Phase = ("Digging: %d tiles left"):format(#carve)
            r = Build.carveStep(P, carve, live)
            if not live() then break end
            if r ~= "none" then noneAt = nil end
        end
        if r == "none" and (#carve == 0 or dirt) and not o.dugSwept then
            -- dig done: collect all dug drops first, row by row
            o.dugSwept, o.sweptAt = true, os.clock()
            Build.Phase = "Collecting leftover dug drops (row by row)"
            Build.sweep(P, live, nil, 600)
            continue
        end
        if r == "none" then
            local have = invCount(block)
            if info.need == 0 then
                -- only skipped dig tiles remain: retry shortly
                if #carve > 0 and not (dirt and o.dugSwept) then
                    noneAt = noneAt or os.clock()
                    local waited = os.clock() - noneAt
                    if waited < 45 then
                        Build.Status = #carve .. " dig tiles unreachable, retrying"
                        if waited > 20 and not o.carveReset then
                            o.carveReset = true
                            table.clear(Build.Skip)
                            table.clear(BuildFail)
                            table.clear(BadEdge)
                            Reach = nil
                        end
                        if not waitAuto(1000) then break end
                        continue
                    end
                end
                -- 4) CLEAN: pick up all leftover drops on land
                Build.Phase = "Collecting drops across land (row by row)"
                Build.sweep(P, live, nil, 900)
                if not live() then break end
                if dirt then
                    -- Wait for latest tile updates and re-verify entire floor from bottom to top.
                    task.wait(0.65)
                    if not live() then break end
                    carve, kept = Build.carveList(P, live)
                    if not live() then break end
                    info = landInfo(P, carve)
                    info.kept = kept
                    Build.DirtInfo = info
                    if info.need > 0 then
                        phase, o.placeNeed = nil, nil
                        continue
                    end
                    Build.DirtRefill = nil
                end
                local note = (#carve > 0) and (", " .. #carve .. " dig tiles skipped") or ""
                if dirt then
                    local remaining = #carve + kept
                    if remaining > 0 then
                        Build.stop(("Dirt Farm: %d floor tiles ready, %d tiles still blocked"):format(info.done, remaining))
                    elseif P.placeK == 0 then
                        Build.stop("Dirt Farm excavation complete")
                    else
                        Build.stop(("Dirt Farm complete (%d floor tiles)"):format(info.done))
                    end
                else
                    Build.stop("Land complete (" .. info.done .. " blocks" .. note .. ")")
                end
                if not dirt and Build.ThenFactory then
                    if not Factory.SeedId then Factory.SeedId = seed end
                    Factory.start()
                end
                break
            end
            local reserve = (P.placeOnly or have >= info.need or not seed) and 0 or Build.RESERVE
            if phase ~= "produce" and not refillPending and have > reserve then
                -- 2) PLACE (keep spare blocks for production if still short)
                phase = "place"
                Build.Reserve = reserve
                Build.Phase = ("Placing land: %d tiles left"):format(info.need)
                    .. ((reserve > 0) and (" (keep " .. reserve .. " blocks)") or "")
                if dirt and (not o.placeNeed or info.need < o.placeNeed) then
                    o.placeNeed, o.placeProgressAt = info.need, os.clock()
                end
                local pr = Build.placeStep(P, live)
                if not live() then break end
                if dirt and os.clock() - o.placeProgressAt > 60 then
                    Build.stop(("Dirt Farm stopped: %d floor tiles unreachable or blocked"):format(info.need))
                    break
                end
                if pr == "none" and invCount(block) > reserve then
                    Build.Status = "Remaining tiles unreachable / blocked, retrying"
                    noneAt = noneAt or os.clock()
                    if os.clock() - noneAt > 20 then -- nothing placeable for a while: reset & retry
                        noneAt = nil
                        table.clear(Build.Skip)
                        table.clear(BuildFail)
                        table.clear(BadEdge)
                        table.clear(Build.Under)
                        Reach = nil
                    end
                    if not waitAuto(1500) then break end
                elseif pr ~= "none" then
                    noneAt = nil
                end
            elseif not seed and not P.placeOnly then
                Build.stop(("Out of blocks, %d short (matching seed not found)"):format(info.need))
                break
            else
                -- 3) PRODUCE
                local target = dirt and 200 or math.min(CAP, info.need + Build.RESERVE)
                if dirt then
                    Build.DirtRefill = dirt
                    refillPending = true
                    o.target = target
                end
                if phase ~= "produce" then
                    if P.placeOnly then
                        Build.Phase = "Collecting Dirt and Dirt Seeds in the farm"
                        local materials = { [block] = true }
                        if seed then materials[seed] = true end
                        Build.sweep(P, live, materials, 90)
                        if not live() then break end
                        have = invCount(block)
                        if have < target and not seed then
                            Build.stop(("Out of Dirt, %d floor tiles short"):format(info.need))
                            break
                        end
                        if have < target and not Refs.Trees then
                            Build.stop("Tree data is unavailable. Reconnect to the game to refill Dirt.")
                            break
                        end
                    elseif os.clock() - (o.sweptAt or -1e9) > 120 then
                        -- pick up leftover drops on land first (blocks, seeds & more), row by row
                        o.sweptAt = os.clock()
                        Build.Phase = "Collecting leftover drops on land (row by row)"
                        Build.sweep(P, live, nil, 300)
                        continue
                    end
                    phase = "produce"
                    o.placeNeed = nil
                    o.productionSince = os.clock()
                    o.productionHave = have
                    o.phase, o.rowK = nil, nil
                    notify(dirt and "Auto Dirt Farm" or "Build Land", "Out of blocks, producing 1 row first", 4)
                end
                if have >= target then
                    phase = "place"
                    if dirt then
                        Build.DirtRefill = nil
                        refillPending = false
                    end
                    notify(dirt and "Auto Dirt Farm" or "Build Land", "Enough blocks (" .. have .. "), resuming place", 4)
                else
                    if P.placeOnly and raymanOn() then
                        Build.stop("Unequip Rayman before running Auto Dirt Farm")
                        break
                    end
                    if o.rowK and not P.rows[o.rowK] then o.rowK = nil end
                    if o.rowK == nil then
                        o.rowK = not dirt and Build.prodRow(P) or false
                        table.clear(Build.Row)
                        if o.rowK then
                            local sp = Build.prodSpots(P, o.rowK)
                            o.plantSet, o.stand, o.tile, o.exclude = sp.set, sp.stand, sp.tile, nil
                        else -- no complete row yet: plant anywhere outside land tiles
                            o.plantSet, o.stand, o.tile, o.exclude = nil, nil, nil, landBlockSet(P)
                            if dirt then
                                -- Plant only on existing footing, outside planned land floors and stair shafts.
                                for k, y in ipairs(P.rows) do
                                    for _, x in ipairs(P.holes[k]) do
                                        o.exclude[y * P.W + x] = true
                                        o.exclude[(y - 1) * P.W + x] = true
                                    end
                                end
                                o.allowHarvest = function(x, y, id, layer)
                                    return live() and layer == "fg" and id == seed and fgIdAt(x, y) == seed
                                        and not raymanOn() and canWorkAt(x, y)
                                        and (treeReadyAt(x, y, seed) or math.huge) <= workspace:GetServerTimeNow()
                                end
                            end
                        end
                    end
                    Build.Phase = ("Producing %s: block %d / %d"):format(PHASE_NAME[o.phase or "harvest"] or "-", have, target)
                        .. (o.rowK and (" | row y " .. P.rows[o.rowK]) or "")
                    if dirt and have == target - 1 then
                        if Drops.topUpDirt(live) then continue end
                        if os.clock() >= (o.nextLastDirtSweep or 0) then
                            Build.sweep(P, live, { [block] = true }, 6)
                            if not live() then break end
                            o.nextLastDirtSweep = os.clock() + 4
                            if invCount(block) >= target or Drops.topUpDirt(live) then continue end
                        end
                    end
                    local pr, nextReady, nReady = Build.produceStep(o)
                    if not live() then break end
                    local noSeeds = not nextReady and (nReady or 0) == 0 and invCount(seed) <= 0
                    if dirt and pr == "idle" and noSeeds then
                        if os.clock() >= (o.nextRefillSweep or 0) then
                            Build.sweep(P, live, { [block] = true, [seed] = true }, 15)
                            if not live() then break end
                            o.nextRefillSweep = os.clock() + 15
                        end
                        Build.Phase = ("Waiting for Dirt or Dirt Seed (%d/200)"):format(invCount(block))
                        o.productionSince = os.clock()
                        if not waitAuto(1000) then break end
                        continue
                    end
                    if dirt then
                        local current = invCount(block)
                        local treeActions = Build.Planted + Build.Harvested
                        if current > (o.productionHave or 0) or treeActions ~= o.treeActions or nextReady then
                            o.productionSince = os.clock()
                        end
                        o.treeActions = treeActions
                        o.productionHave = current
                        if os.clock() - o.productionSince > 90 then
                            Build.stop("Dirt production has stalled. Add Dirt or check the planting area.")
                            break
                        end
                    end
                    if pr ~= "idle" then o.stuckAt = nil end
                    if pr == "idle" then
                        if noSeeds and have <= 0 then
                            Build.stop("Out of seeds & blocks. Need " .. info.need .. " blocks")
                            break
                        end
                        if (nReady or 0) > 0 then
                            Build.Status = nReady .. " ready trees unreachable, retrying"
                            o.stuckAt = o.stuckAt or os.clock()
                            if os.clock() - o.stuckAt > 30 then -- reset skip list & path history
                                o.stuckAt = nil
                                table.clear(Build.FieldSkip)
                                table.clear(BadEdge)
                                Reach = nil
                            end
                        elseif nextReady then
                            Build.Status = "Waiting for ready tree ~" .. waitText(nextReady)
                        elseif invCount(seed) <= 0 then
                            Build.Status = "Out of seeds & no room to place-break next to character"
                        else
                            Build.Status = "No empty plant spots, waiting"
                        end
                        if not waitAuto(1000) then break end
                    end
                end
            end
        end
    end
    if Build.RunId == runId then
        if dirt and alive() and Build.Running and not Build.dirtWorldMatches(dirt) then
            Build.stop("World changed. Auto Dirt Farm stopped")
        else
            releaseInput()
        end
    end
end

function Build.start(dirtMode)
    dirtMode = dirtMode == true
    local toggle = dirtMode and UI.DirtToggle or UI.BuildToggle
    local title = dirtMode and "Auto Dirt Farm" or "Build Land"
    local err, dirt, dirtId
    if Build.Running then
        if dirtMode == (Build.DirtRun ~= nil) then return end
        err = "Stop the current build first"
    elseif WorldFinder.Busy then
        err = "Stop hunting before running farming"
    elseif AutoDrop.Busy then
        err = "Wait for the drop trip to finish"
    elseif not Refs.World then
        err = "World data not found. Press 'Connect to game'"
    elseif not Session.bindMovement(true) then
        err = "Game movement controls (WorldMenu.isDown) not found"
    elseif not playerState() then
        err = "You are not in a world yet"
    elseif dirtMode then
        dirtId = Build.dirtBlock()
        local w = Refs.World
        local plan = Build.plan(Build.Dirt)
        if not Refs.Inv then
            err = "Inventory is unavailable. Press Connect to game"
        elseif not dirtId then
            err = "Dirt block was not found in the item data"
        elseif not plan then
            err = "The Dirt Farm area is empty. Check the X and Y bounds."
        elseif plan.placeOnly and plan.placeK == 0 then
            err = "No rows to place above the surface within the selected area"
        elseif not plan.placeOnly and raymanOn() then
            err = "Unequip Rayman before running Auto Dirt Farm"
        else
            dirt = {
                block = dirtId, seed = seedOfBlock(dirtId), world = w, grid = w.fg, worldName = w.name, plan = plan,
                previousPhase = Build.Phase, previousStatus = Build.Status,
            }
        end
    elseif not (Build.BlockId and ItemDB[Build.BlockId] and ItemDB[Build.BlockId].solid) then
        err = "Select a solid block for land"
    elseif #landRows() == 0 then
        err = "No rows fit (top Y is too low). Stand at TOP-left corner of land and press 'Use character position'"
    end
    if err then
        notify(title, err, 4)
        if toggle then pcall(function() toggle:Set(false, false) end) end
        return
    end
    if State.Running and not State.Override then stopFarm("Stopped because Build Land started") end
    if Clear.Running then stopClear("Stopped because Build Land started") end
    if Farmer.Running then stopFarmer("Stopped because Build Land started") end
    if Splice.Running and Splice.stop then Splice.stop("Stopped because Build Land started") end
    if Factory.Running then Factory.stop("Stopped because Build Land started") end
    if dirtMode and Vend.Running and Vend.stop then Vend.stop("Stopped because Auto Dirt Farm started") end
    if not Refs.Trees then findTreeRefs() end
    table.clear(Build.Skip)
    table.clear(BuildFail)
    table.clear(Build.FieldSkip)
    table.clear(Build.Row)
    table.clear(Build.Under)
    table.clear(Build.BreakTimes)
    table.clear(BadEdge)
    Build.Surface = nil -- recalculated (natural ground surface)
    Build.Reserve = 0
    Land.Cache = nil
    Factory.BreakFailUntil = 0
    Build.DirtRun = dirt
    if dirt then Build.DirtInfo = nil end
    Build.Running = true
    Build.RunId = (Build.RunId or 0) + 1
    Build.Phase = "Calculating..."
    autoBegin()
    if toggle then pcall(function() toggle:Set(true, false) end) end
    local id = Build.RunId
    task.spawn(function()
        local ok, e = pcall(buildLoop, id, dirt)
        if not ok then
            warn("[n4th] Build Land error: " .. tostring(e))
            if Build.Running and Build.RunId == id then Build.stop("Error: " .. tostring(e)) end
        end
    end)
end

Auto.landInfo = landInfo
Auto.landRows = landRows
Auto.seedOfBlock = seedOfBlock
Auto.blockOfSeed = blockOfSeed
Auto.parseDropTarget = parseDropTarget

Auto.walkTo = walkTo
Auto.startSpliceRoam = startSpliceRoam
Auto.stopSpliceRoam = stopSpliceRoam
Auto.treeReadyAt = treeReadyAt
Auto.plantSpotOk = plantSpotOk
Auto.stopWalk = function() Move.Homing = false end
Auto.here = function()
    local s = playerState()
    if s then return startNode(s) end
    return nil
end
Auto.startClear = startClear
Auto.startFarmer = startFarmer
Auto.updateClearStatus = updateClearStatus
Auto.updateFarmerStatus = updateFarmerStatus
Auto.findTreeRefs = findTreeRefs
Auto.releaseInput = releaseInput
Auto.BadEdge = BadEdge
Auto.ClearFail = ClearFail
Auto.resetReach = function() Reach = nil end
end)() end -- do (auto movement)

---------------------------------------------------------------------
-- AUTO CHAT
---------------------------------------------------------------------
-- Messages sent to world chat in rotating order
local TextChatService = game:GetService("TextChatService")

local function worldChannel()
    local folder = TextChatService:FindFirstChild("WorldChannels")
    if not folder then return nil end
    local name = Refs.World and Refs.World.name
    if type(name) == "string" and name ~= "" then
        local ch = folder:FindFirstChild(name)
        if ch then return ch end
    end
    -- fallback: find a channel we belong to
    for _, ch in ipairs(folder:GetChildren()) do
        if ch:IsA("TextChannel") then
            for _, src in ipairs(ch:GetChildren()) do
                if src:IsA("TextSource") and src.UserId == LocalPlayer.UserId then return ch end
            end
        end
    end
    return nil
end

local function parseSpamTexts(raw)
    local out = {}
    for part in string.gmatch(raw or "", "[^|\n]+") do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

local lastSpamText = nil
local function updateSpamStatus()
    if not UI.SpamStatus then return end
    local txt = "Status   : " .. (Spam.On and "RUNNING" or "STOPPED")
        .. "\nMessages : " .. #Spam.Texts .. " (rotating)"
        .. "\nSent     : " .. Spam.Sent
        .. "\nLast     : " .. Spam.Last
    if txt == lastSpamText then return end
    lastSpamText = txt
    task.defer(function()
        pcall(function() UI.SpamStatus:SetDesc(txt) end)
    end)
end

-- Send next message
local function sendNextChat()
    if #Spam.Texts == 0 then
        Spam.Last = "Message list is empty"
        return false
    end
    local ch = worldChannel()
    if not ch then
        Spam.Last = "World chat channel not found (enter a world first)"
        return false
    end
    if Spam.Index > #Spam.Texts then Spam.Index = 1 end
    local msg = Spam.Texts[Spam.Index]
    Spam.Index = Spam.Index % #Spam.Texts + 1
    local ok, err = pcall(ch.SendAsync, ch, msg)
    if ok then
        Spam.Sent += 1
        Spam.Last = msg
    else
        Spam.Last = "Failed: " .. tostring(err)
    end
    return ok
end

Spam.NextAt = 0
task.spawn(function()
    while alive() do
        if Spam.On and os.clock() >= Spam.NextAt then
            sendNextChat()
            Spam.NextAt = os.clock() + math.max(3, Spam.IntervalSec)
            updateSpamStatus()
        end
        task.wait(0.25)
    end
end)

---------------------------------------------------------------------
-- n4th NAME WATERMARK (local display only)
---------------------------------------------------------------------
-- Original name (image font "BitmapText") hidden and replaced with animated text:
-- flowing gradient colors + subtle pulse. Other players still see the real name.
-- Always active as script watermark (no on/off toggle).
local TextService = game:GetService("TextService")
local NameFx = { t0 = os.clock() }

local NAME_COLORS = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromHex("FA526A")),
    ColorSequenceKeypoint.new(0.50, Color3.fromHex("F9BCC9")),
    ColorSequenceKeypoint.new(1.00, Color3.fromHex("FA526A")),
})
local NAME_FONT = Enum.Font.FredokaOne

do
local function nameGlyphs(holder)
    local bitmap = holder and holder:FindFirstChild("BitmapText")
    if not bitmap then return nil end
    local glyphs = {}
    for _, child in ipairs(bitmap:GetChildren()) do
        if child:IsA("ImageLabel") then glyphs[#glyphs + 1] = child end
    end
    if #glyphs == 0 then return nil end
    table.sort(glyphs, function(a, b)
        if a.Position.X.Offset ~= b.Position.X.Offset then return a.Position.X.Offset < b.Position.X.Offset end
        return a.Position.Y.Offset < b.Position.Y.Offset
    end)
    local key = {}
    for _, glyph in ipairs(glyphs) do
        key[#key + 1] = ("%s:%d,%d,%d,%d"):format(glyph.Image, glyph.ImageRectOffset.X, glyph.ImageRectOffset.Y,
            glyph.ImageRectSize.X, glyph.ImageRectSize.Y)
    end
    return table.concat(key, "|")
end

local function nameVisible(object)
    local node = object
    while node and node ~= PlayerGui do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node = node.Parent
    end
    return node == PlayerGui
end

local function nameTagShape(holder)
    if not holder:IsA("Frame") or holder.AnchorPoint.X ~= 0.5 or holder.AnchorPoint.Y ~= 1 then return false end
    if not holder:FindFirstChild("BitmapText") then return false end
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("ImageLabel") and child.Size.X.Offset == 32 and child.Size.Y.Offset == 32 then return true end
    end
    return false
end

local function ownNameGlyphs()
    local chat = PlayerGui:FindFirstChild("ChatGui")
    local hud = chat and chat:FindFirstChild("HUD")
    local panel = hud and hud:FindFirstChild("PlayerPanel")
    return nameGlyphs(panel and panel:FindFirstChild("Name"))
end

local function findOwnNameTag(root, signature)
    if not root or not signature then return nil end
    local level, budget, visited = { root }, { next = os.clock() + 0.0015 }, 0
    for _ = 0, 6 do
        local found, matches = nil, 0
        for _, object in ipairs(level) do
            if nameTagShape(object) and nameVisible(object) and nameGlyphs(object) == signature then
                found, matches = object, matches + 1
            end
            visited += 1
            Session.scanStep(budget, visited * 8)
            if not alive() then return nil end
        end
        if matches > 0 then return matches == 1 and found or nil end
        local nextLevel = {}
        for _, object in ipairs(level) do
            for _, child in ipairs(object:GetChildren()) do
                if child:IsA("Frame") and child.Visible then nextLevel[#nextLevel + 1] = child end
            end
            visited += 1
            Session.scanStep(budget, visited * 8)
            if not alive() then return nil end
        end
        if #nextLevel == 0 then break end
        level = nextLevel
    end
end

task.spawn(function()
    while alive() do
        if Misc.CustomName then
            local holder, signature = NameFx.nativeHolder, ownNameGlyphs()
            if not holder or not holder.Parent or not nameVisible(holder) or nameGlyphs(holder) ~= signature then
                local gg = PlayerGui:FindFirstChild("GameGui")
                local world = gg and gg:FindFirstChild("World")
                local camera = world and world:FindFirstChild("Camera")
                local legacy = camera and camera:FindFirstChild("NameTag")
                local found = legacy or findOwnNameTag(gg, signature)
                if not alive() or not Misc.CustomName then break end
                NameFx.nativeHolder, Session.NameTagHolder = found, found
            end
        end
        task.wait(1)
    end
end)

end

-- Name locations: above character & top-left panel
local function nameHolders()
    local gg = PlayerGui:FindFirstChild("GameGui")
    local world = gg and gg:FindFirstChild("World")
    local cam = world and world:FindFirstChild("Camera")
    local chat = PlayerGui:FindFirstChild("ChatGui")
    local hud = chat and chat:FindFirstChild("HUD")
    local panel = hud and hud:FindFirstChild("PlayerPanel")
    local tag = NameFx.nativeHolder
    if not tag or not tag.Parent then tag = cam and cam:FindFirstChild("NameTag") end
    return tag, panel and panel:FindFirstChild("Name")
end

local function textWidth(text, size)
    local ok, v = pcall(TextService.GetTextSize, TextService, text, size, NAME_FONT, Vector2.new(2000, 200))
    return (ok and v.X or #text * size * 0.55) + 6 -- +6 for outline padding
end

local function makeLabel(holder, size, isTag)
    local lb = Instance.new("TextLabel")
    lb.Name = "n4thName"
    lb.BackgroundTransparency = 1
    lb.Font = NAME_FONT
    lb.TextSize = size
    lb.TextColor3 = Color3.new(1, 1, 1)
    lb.Text = Misc.NameText
    lb.ZIndex = isTag and 1017 or 10
    if isTag then
        lb.AnchorPoint = Vector2.new(0.5, 0.5) -- pulse from center
        lb.Position = UDim2.fromScale(0.5, 0.5)
    else
        lb.AnchorPoint = Vector2.new(0, 0.5)
        lb.Position = UDim2.new(0, 3, 0.5, 0)
        lb.TextXAlignment = Enum.TextXAlignment.Left
        lb.TextScaled = true
        local sizeLimit = Instance.new("UITextSizeConstraint")
        sizeLimit.MaxTextSize = size
        sizeLimit.Parent = lb
    end
    local st = Instance.new("UIStroke")
    st.Thickness = 2
    st.Color = Color3.fromHex("140B10")
    st.Transparency = 0.1
    st.Parent = lb
    local gr = Instance.new("UIGradient")
    gr.Color = NAME_COLORS
    gr.Rotation = 12
    gr.Parent = lb
    local sc = Instance.new("UIScale")
    sc.Parent = lb
    lb.Parent = holder
    local bitmap = holder:FindFirstChild("BitmapText")
    return { holder = holder, bitmap = bitmap, bitmapVisible = bitmap and bitmap.Visible, label = lb, gr = gr, sc = sc,
        size = size, isTag = isTag, text = nil, w = 0 }
end

local function dropEntry(e)
    if not e then return end
    pcall(function() e.label:Destroy() end)
    if e.bitmap then pcall(function() e.bitmap.Visible = e.bitmapVisible end) end
    if e.isTag and e.bitmap then
        -- restore tag size & wrench position to match original name
        pcall(function()
            local bw = e.bitmap.Size.X.Offset
            e.holder.Size = UDim2.fromOffset(bw, e.holder.Size.Y.Offset)
            local wr = e.holder:FindFirstChild("Wrench")
            if wr then wr.Position = UDim2.fromOffset(bw + 4, wr.Position.Y.Offset) end
        end)
    end
end

local function nameRestore()
    dropEntry(NameFx.tag)
    dropEntry(NameFx.panel)
    NameFx.tag, NameFx.panel = nil, nil
    NameFx.nativeHolder, Session.NameTagHolder = nil, nil
end

-- Ensure label exists, original name is hidden, tag size fits text
local function nameKeep(e, holder, size, isTag)
    if not holder then
        dropEntry(e)
        return nil
    end
    if not e or e.holder ~= holder or not e.label.Parent then
        dropEntry(e)
        e = makeLabel(holder, size, isTag)
    end
    if e.text ~= Misc.NameText then
        e.text = Misc.NameText
        e.label.Text = Misc.NameText
        e.w = textWidth(Misc.NameText, size)
    end
    local bitmap = holder:FindFirstChild("BitmapText")
    if bitmap ~= e.bitmap then
        e.bitmap, e.bitmapVisible = bitmap, bitmap and bitmap.Visible
    end
    if e.bitmap and e.bitmap.Visible then e.bitmap.Visible = false end
    if isTag then
        local h = math.max(holder.Size.Y.Offset, size + 6)
        if e.label.Size.X.Offset ~= e.w or e.label.Size.Y.Offset ~= h then
            e.label.Size = UDim2.fromOffset(e.w, h)
        end
        if holder.Size.X.Offset ~= e.w then
            holder.Size = UDim2.fromOffset(e.w, holder.Size.Y.Offset) -- keep flag to the left of name
        end
        local wr = holder:FindFirstChild("Wrench")
        if wr and wr.Position.X.Offset ~= e.w + 4 then
            wr.Position = UDim2.fromOffset(e.w + 4, wr.Position.Y.Offset)
        end
    else
        e.label.Size = UDim2.new(1, -6, 1, 0)
    end
    return e
end

-- Per-frame animation: flowing gradient + subtle pulse
table.insert(Connections, RunService.RenderStepped:Connect(function()
    if not alive() or not Misc.CustomName then return end
    local tag, panelName = nameHolders()
    NameFx.tag = nameKeep(NameFx.tag, tag, 22, true)
    NameFx.panel = nameKeep(NameFx.panel, panelName, 21, false)
    local t = os.clock() - NameFx.t0
    local offset = Vector2.new(((t * 0.45) % 2) - 1, 0)
    local pulse = 1 + 0.045 * math.sin(t * 3.2)
    local tg, pn = NameFx.tag, NameFx.panel
    if tg then
        tg.gr.Offset = offset
        tg.sc.Scale = pulse
    end
    if pn then
        pn.gr.Offset = offset
        pn.sc.Scale = pulse
    end
end))

---------------------------------------------------------------------
-- ANTI AFK
---------------------------------------------------------------------
table.insert(Connections, LocalPlayer.Idled:Connect(function()
    if State.AntiAfk and alive() then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end))

---------------------------------------------------------------------
-- EXTRA GUI: 5x5 Tile Grid + Fly UP/DN buttons
---------------------------------------------------------------------
do (function() -- Preserve main chunk registers for unoptimized bytecode compilation.
local guiParent
if type(gethui) == "function" then
    local ok, parent = pcall(gethui)
    if ok and typeof(parent) == "Instance" then guiParent = parent end
end
guiParent = guiParent or game:GetService("CoreGui")

local function newScreenGui(name)
    local sg = Instance.new("ScreenGui")
    sg.Name = name
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 999
    sg.Enabled = false
    if syn and syn.protect_gui then pcall(syn.protect_gui, sg) end
    local ok = pcall(function() sg.Parent = guiParent end)
    if not ok then sg.Parent = PlayerGui end
    return sg
end

local GRID_RADIUS = 2
local CELL = 38
local GAP = 4

local GridGui = newScreenGui("n4thGrid")
UI.GridGui = GridGui

local side = GRID_RADIUS * 2 + 1
local gridSize = side * CELL + (side - 1) * GAP

local Panel = Instance.new("Frame")
Panel.Size = UDim2.fromOffset(gridSize + 20, gridSize + 96)
Panel.Position = UDim2.fromOffset(20, 80)
Panel.BackgroundColor3 = UI.Palette.Panel
Panel.BorderSizePixel = 0
Panel.Parent = GridGui
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 10)
local pStroke = Instance.new("UIStroke", Panel)
pStroke.Color = UI.Palette.Border

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 0, 28)
Title.Position = UDim2.fromOffset(10, 4)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = UI.Palette.Text
Title.Text = "Tile Grid"
Title.Parent = Panel

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(24, 24)
CloseBtn.Position = UDim2.new(1, -30, 0, 6)
CloseBtn.BackgroundColor3 = UI.Palette.Surface
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.Parent = Panel
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
CloseBtn.MouseButton1Click:Connect(function()
    GridGui.Enabled = false
end)

local GridHolder = Instance.new("Frame")
GridHolder.Size = UDim2.fromOffset(gridSize, gridSize)
GridHolder.Position = UDim2.fromOffset(10, 36)
GridHolder.BackgroundTransparency = 1
GridHolder.Parent = Panel

local COLOR_OFF = UI.Palette.Surface
local COLOR_ON = UI.Palette.Action
local COLOR_ME = UI.Palette.Border
local CellButtons = {}

-- Grid shares Farm, Factory, Land modes, and a single Auto Drop position.
UI.GridMode = "farm"
UI.gridTarget = function()
    if UI.GridMode == "autodrop" then return AutoDrop.GridSelection or {} end
    if UI.GridMode == "factory" then return Factory.Tiles end
    if UI.GridMode == "land" then return Build.Tiles end
    return State.Offsets
end

local function paintCell(key)
    local b = CellButtons[key]
    if b then
        b.BackgroundColor3 = UI.gridTarget()[key] and COLOR_ON
            or (key == "0,0" and COLOR_ME or COLOR_OFF)
    end
end

for row = 0, side - 1 do
    for col = 0, side - 1 do
        local dx, dy = col - GRID_RADIUS, row - GRID_RADIUS
        local key = dx .. "," .. dy
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(CELL, CELL)
        btn.Position = UDim2.fromOffset(col * (CELL + GAP), row * (CELL + GAP))
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Parent = GridHolder
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

        if dx == 0 and dy == 0 then
            btn.Text = "ME"
            btn.BackgroundColor3 = COLOR_ME
            btn.AutoButtonColor = false
            CellButtons[key] = btn
            btn.MouseButton1Click:Connect(function()
                if UI.GridMode == "autodrop" then AutoDrop.selectTile(0, 0) end
            end)
        else
            btn.Text = ""
            btn.BackgroundColor3 = UI.gridTarget()[key] and COLOR_ON or COLOR_OFF
            CellButtons[key] = btn
            btn.MouseButton1Click:Connect(function()
                if UI.GridMode == "autodrop" then AutoDrop.selectTile(dx, dy) return end
                local tgt = UI.gridTarget()
                tgt[key] = (not tgt[key]) or nil
                paintCell(key)
                updateStatus()
            end)
        end
    end
end

local GridStart = Instance.new("TextButton")
GridStart.Size = UDim2.new(1, -20, 0, 30)
GridStart.Position = UDim2.new(0, 10, 1, -54)
GridStart.BackgroundColor3 = COLOR_ON
GridStart.Font = Enum.Font.GothamBold
GridStart.TextSize = 14
GridStart.TextColor3 = Color3.new(1, 1, 1)
GridStart.Text = "START"
GridStart.Parent = Panel
Instance.new("UICorner", GridStart).CornerRadius = UDim.new(0, 8)
UI.GridStart = GridStart
GridStart.MouseButton1Click:Connect(function()
    if UI.GridMode == "autodrop" then
        GridGui.Enabled = false
    elseif UI.GridMode == "land" then
        if Build.Running and not Build.DirtRun then Build.stop() elseif Build.start then Build.start() end
    elseif UI.GridMode == "factory" then
        if Factory.Running then Factory.stop() else Factory.start() end
    elseif State.Running and not State.Override then
        stopFarm()
    else
        startFarm()
    end
end)

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(1, -20, 0, 18)
ClearBtn.Position = UDim2.new(0, 10, 1, -22)
ClearBtn.BackgroundTransparency = 1
ClearBtn.Font = Enum.Font.Gotham
ClearBtn.TextSize = 12
ClearBtn.TextColor3 = UI.Palette.Muted
ClearBtn.Text = "Clear selection"
ClearBtn.Parent = Panel
ClearBtn.MouseButton1Click:Connect(function()
    if UI.GridMode == "autodrop" then
        if not AutoDrop.Busy then
            AutoDrop.X, AutoDrop.Y, AutoDrop.World = -1, -1, ""
            table.clear(AutoDrop.GridSelection)
            Config.save(true)
            if UI.applyGrid then UI.applyGrid() end
        end
        return
    end
    local tgt = UI.gridTarget()
    for key in pairs(tgt) do
        tgt[key] = nil
        paintCell(key)
    end
    updateStatus()
end)

-- Grid mode cycle button: Farm (Auto Farm tiles) / Factory (factory break tiles)
do (function()
    local ModeBtn = Instance.new("TextButton")
    ModeBtn.Size = UDim2.fromOffset(62, 22)
    ModeBtn.Position = UDim2.new(1, -98, 0, 7)
    ModeBtn.Font = Enum.Font.GothamBold
    ModeBtn.TextSize = 11
    ModeBtn.TextColor3 = Color3.new(1, 1, 1)
    ModeBtn.Parent = Panel
    Instance.new("UICorner", ModeBtn).CornerRadius = UDim.new(0, 6)
    Title.Size = UDim2.new(1, -106, 0, 28)

    local function apply()
        local fac = UI.GridMode == "factory"
        local lnd = UI.GridMode == "land"
        local drop = UI.GridMode == "autodrop"
        ModeBtn.Text = lnd and "Land" or (fac and "Auto Rotasi" or "Farm")
        ModeBtn.BackgroundColor3 = lnd and UI.Palette.Stop
            or (fac and UI.Palette.Action or UI.Palette.Surface)
        Title.Text = lnd and "Land Break Tiles" or (fac and "Auto Rotasi Break Tiles" or "Tile Grid")
        if drop then
            ModeBtn.Text = "Drop"
            Title.Text = "Choose drop standing tile"
        end
        for key in pairs(CellButtons) do paintCell(key) end
        if drop then
            GridStart.Text = "Done"
            GridStart.BackgroundColor3 = COLOR_ON
        elseif lnd then
            local run = Build.Running and not Build.DirtRun
            GridStart.Text = run and "STOP LAND" or "START LAND"
            GridStart.BackgroundColor3 = run and UI.Palette.Stop or COLOR_ON
        elseif fac then
            GridStart.Text = Factory.Running and "STOP AUTO ROTASI" or "START AUTO ROTASI"
            GridStart.BackgroundColor3 = Factory.Running and UI.Palette.Stop or COLOR_ON
        else
            local run = State.Running and not State.Override
            GridStart.Text = run and "STOP" or "START"
            GridStart.BackgroundColor3 = run and UI.Palette.Stop or COLOR_ON
        end
    end

    UI.setGridMode = function(m)
        if m == "autodrop" then
            local ok, message = AutoDrop.beginGrid()
            if not ok then notify("Auto Drop", message, 4) return false end
        end
        UI.GridMode = m
        apply()
        return true
    end
    UI.applyGrid = apply
    ModeBtn.MouseButton1Click:Connect(function() -- Farm -> Factory -> Land -> Farm
        local nxt = { farm = "factory", factory = "land", land = "autodrop", autodrop = "farm" }
        UI.setGridMode(nxt[UI.GridMode] or "farm")
    end)
    apply()
end)() end

-- Panel draggable by its title bar
do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local dragging, dragStart, startPos
    Title.Active = true
    Title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Panel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            Panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end)() end

task.spawn(function()
    while alive() do
        if GridGui.Enabled then
            local px, py = getPlayerTile()
            local t = px and ("ME (" .. px .. "," .. py .. ")") or "Tile Grid | not in world"
            if Title.Text ~= t then Title.Text = t end
        end
        task.wait(0.5)
    end
end)

-- Fly UP/DN buttons (shown when Fly is enabled)
local FlyPad = newScreenGui("n4thFlyPad")
UI.FlyPad = FlyPad

local function flyButton(text, yOffset, onHold)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(64, 64)
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Position = UDim2.new(1, -24, 0.5, yOffset)
    b.BackgroundColor3 = UI.Palette.Panel
    b.BackgroundTransparency = 0.2
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 18
    b.TextColor3 = Color3.new(1, 1, 1)
    b.AutoButtonColor = true
    b.Parent = FlyPad
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", b)
    st.Color = UI.Palette.Border
    st.Thickness = 2
    -- release when finger lifts (even after dragging outside) so it never gets stuck
    local heldInput = nil
    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            heldInput = input
            onHold(true)
        end
    end)
    table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
        if heldInput and (input == heldInput
            or (input.UserInputType == Enum.UserInputType.MouseButton1
                and heldInput.UserInputType == Enum.UserInputType.MouseButton1)) then
            heldInput = nil
            onHold(false)
        end
    end))
    return b
end

flyButton("UP", -40, function(v) Misc.UpHeld = v end)
flyButton("DN", 40, function(v) Misc.DownHeld = v end)
end)() end

---------------------------------------------------------------------
-- N4TH MENU (Discord UI Lib - koya-alt/Roblox-UI)
---------------------------------------------------------------------
Session.InitStep = "building n4th menu"
-- Discord UI Library (Server rail, Channel sidebar, and Channel controls)
do (function()
    local DiscordColors = {
        Main = Color3.fromRGB(32, 34, 37),
        Sidebar = Color3.fromRGB(47, 49, 54),
        ChannelBg = Color3.fromRGB(54, 57, 63),
        ChannelHover = Color3.fromRGB(52, 55, 60),
        ChannelActive = Color3.fromRGB(57, 60, 67),
        Userpad = Color3.fromRGB(41, 43, 47),
        InputBg = Color3.fromRGB(48, 51, 57),
        InputOutline = Color3.fromRGB(37, 40, 43),
        ItemHover = Color3.fromRGB(42, 44, 48),
        Divider = Color3.fromRGB(66, 69, 74),
        Blurple = Color3.fromRGB(114, 137, 228),
        BlurpleHover = Color3.fromRGB(103, 123, 196),
        Green = Color3.fromRGB(67, 181, 129),
        Red = Color3.fromRGB(240, 71, 71),
        SwitchOff = Color3.fromRGB(114, 118, 125),
        SliderTrack = Color3.fromRGB(79, 84, 92),
        Text = Color3.fromRGB(255, 255, 255),
        SubText = Color3.fromRGB(171, 172, 176),
        Muted = Color3.fromRGB(127, 131, 137),
        ChannelIdle = Color3.fromRGB(114, 118, 125),
        TopTitle = Color3.fromRGB(99, 102, 109),
    }

    local function create(class, properties, parent)
        local instance = Instance.new(class)
        for key, value in pairs(properties) do instance[key] = value end
        instance.Parent = parent
        return instance
    end

    local function corner(instance, radius)
        create("UICorner", { CornerRadius = type(radius) == "userdata" and radius or UDim.new(0, radius) }, instance)
        return instance
    end

    local function callback(fn, ...)
        if not fn or not alive() then return end
        local ok, err = pcall(fn, ...)
        if not ok then warn("[n4th] UI: " .. tostring(err)) end
    end

    local function makeDraggable(topbarobject, object)
        local dragging, dragInput, dragStart, startPos
        topbarobject.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = object.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        topbarobject.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)
        table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging and dragStart and startPos then
                local delta = input.Position - dragStart
                object.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end))
    end

    local TweenService = game:GetService("TweenService")
    local DiscordLib = {}
    local gui = create("ScreenGui", {
        Name = "N4TH_V2",
        ResetOnSpawn = false,
        DisplayOrder = 900,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, PlayerGui)

    local pfp = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(LocalPlayer.UserId) .. "&width=420&height=420&format=png"
    local user = LocalPlayer.Name
    local tag = tostring((LocalPlayer.UserId % 9000) + 1000)

    function DiscordLib:Window(text)
        local currentServerToggled = ""
        local minimized = false
        local firstServer = false
        local windowObj = { Closed = false, Tabs = {}, Servers = {}, DiscordLib = DiscordLib }

        local MainFrame = create("Frame", {
            Name = "MainFrame",
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = DiscordColors.Main,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 681, 0, 396),
        }, gui)
        corner(MainFrame, 8)

        local scale = create("UIScale", {}, MainFrame)
        local function resize()
            local camera = workspace.CurrentCamera
            if not camera then return end
            local view = camera.ViewportSize
            scale.Scale = math.clamp(math.min((view.X - 20) / 681, (view.Y - 20) / 396), 0.35, 1)
        end
        local cameraConnection
        local function bindCamera()
            if cameraConnection then cameraConnection:Disconnect() end
            local camera = workspace.CurrentCamera
            if camera then
                cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
                table.insert(Connections, cameraConnection)
            end
            resize()
        end
        table.insert(Connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera))
        bindCamera()

        local TopFrame = create("Frame", {
            Name = "TopFrame",
            BackgroundColor3 = DiscordColors.Main,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0, 681, 0, 22),
            Active = true,
        }, MainFrame)

        local TopFrameHolder = create("Frame", {
            Name = "TopFrameHolder",
            BackgroundColor3 = DiscordColors.Main,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0, 681, 0, 22),
        }, TopFrame)

        create("TextLabel", {
            Name = "Title",
            BackgroundTransparency = 1,
            Position = UDim2.new(0.012, 0, 0, 0),
            Size = UDim2.new(0, 260, 0, 22),
            Font = Enum.Font.GothamBold,
            Text = text,
            TextColor3 = DiscordColors.TopTitle,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, TopFrame)

        local CloseBtn = create("TextButton", {
            Name = "CloseBtn",
            BackgroundColor3 = DiscordColors.Main,
            BorderSizePixel = 0,
            Position = UDim2.new(0.959, 0, 0, 0),
            Size = UDim2.new(0, 28, 0, 22),
            Font = Enum.Font.Gotham,
            Text = "",
            AutoButtonColor = false,
        }, TopFrame)

        create("ImageLabel", {
            Name = "CloseIcon",
            BackgroundTransparency = 1,
            Position = UDim2.new(0.19, 0, 0.13, 0),
            Size = UDim2.new(0, 17, 0, 17),
            Image = "http://www.roblox.com/asset/?id=6035047409",
            ImageColor3 = Color3.fromRGB(220, 221, 222),
        }, CloseBtn)

        local MinimizeBtn = create("TextButton", {
            Name = "MinimizeButton",
            BackgroundColor3 = DiscordColors.Main,
            BorderSizePixel = 0,
            Position = UDim2.new(0.918, 0, 0, 0),
            Size = UDim2.new(0, 28, 0, 22),
            Font = Enum.Font.Gotham,
            Text = "",
            AutoButtonColor = false,
        }, TopFrame)

        create("ImageLabel", {
            Name = "MinimizeLabel",
            BackgroundTransparency = 1,
            Position = UDim2.new(0.19, 0, 0.13, 0),
            Size = UDim2.new(0, 17, 0, 17),
            Image = "http://www.roblox.com/asset/?id=6035067836",
            ImageColor3 = Color3.fromRGB(220, 221, 222),
        }, MinimizeBtn)

        local ServersHolder = create("Folder", { Name = "ServersHolder" }, TopFrameHolder)

        local Userpad = create("Frame", {
            Name = "Userpad",
            BackgroundColor3 = DiscordColors.Userpad,
            BorderSizePixel = 0,
            Position = UDim2.new(0.106243297, 0, 15.9807148, 0),
            Size = UDim2.new(0, 179, 0, 43),
            ZIndex = 3,
        }, TopFrameHolder)

        local UserIcon = corner(create("Frame", {
            Name = "UserIcon",
            BackgroundColor3 = Color3.fromRGB(31, 33, 36),
            BorderSizePixel = 0,
            Position = UDim2.new(0.034, 0, 0.124, 0),
            Size = UDim2.new(0, 32, 0, 32),
            ZIndex = 3,
        }, Userpad), UDim.new(1, 8))

        local UserImage = create("ImageLabel", {
            Name = "UserImage",
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 32, 0, 32),
            Image = Session.BrandLogo or pfp,
            ZIndex = 3,
        }, UserIcon)

        create("ImageLabel", {
            Name = "UserCircleImage",
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 32, 0, 32),
            Image = "rbxassetid://4031889928",
            ImageColor3 = DiscordColors.Userpad,
            ZIndex = 3,
        }, UserImage)

        create("TextLabel", {
            Name = "UserName",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0.23, 0, 0.116, 0),
            Size = UDim2.new(0, 98, 0, 17),
            Font = Enum.Font.GothamSemibold,
            Text = user,
            TextColor3 = DiscordColors.Text,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
            ZIndex = 3,
        }, Userpad)

        create("TextLabel", {
            Name = "UserTag",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0.23, 0, 0.455, 0),
            Size = UDim2.new(0, 95, 0, 17),
            Font = Enum.Font.Gotham,
            Text = "#" .. tag,
            TextColor3 = DiscordColors.Text,
            TextSize = 13,
            TextTransparency = 0.3,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 3,
        }, Userpad)

        local QuitBtn = corner(create("TextButton", {
            Name = "SettingsOpenBtn",
            BackgroundColor3 = DiscordColors.ChannelBg,
            Position = UDim2.new(0.81, 0, 0.21, 0),
            Size = UDim2.new(0, 26, 0, 24),
            Font = Enum.Font.GothamBold,
            Text = "X",
            TextColor3 = DiscordColors.SubText,
            TextSize = 15,
            AutoButtonColor = false,
            ZIndex = 4,
        }, Userpad), 4)
        QuitBtn.MouseEnter:Connect(function()
            QuitBtn.BackgroundColor3 = DiscordColors.Red
            QuitBtn.TextColor3 = DiscordColors.Text
        end)
        QuitBtn.MouseLeave:Connect(function()
            QuitBtn.BackgroundColor3 = DiscordColors.ChannelBg
            QuitBtn.TextColor3 = DiscordColors.SubText
        end)
        QuitBtn.MouseButton1Click:Connect(function()
            if Session.Cleanup then Session.Cleanup() end
            if G.__n4thOpus == Session then G.__n4thOpus = nil end
        end)

        local ServersHoldFrame = create("Frame", {
            Name = "ServersHoldFrame",
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 71, 0, 396),
        }, MainFrame)

        local ServersHold = create("ScrollingFrame", {
            Name = "ServersHold",
            Active = true,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 0.058, 0),
            Size = UDim2.new(0, 71, 0, 373),
            ScrollBarThickness = 1,
            ScrollBarImageTransparency = 1,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, ServersHoldFrame)

        local ServersHoldLayout = create("UIListLayout", {
            Name = "ServersHoldLayout",
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 7),
        }, ServersHold)

        create("UIPadding", {
            Name = "ServersHoldPadding",
            PaddingLeft = UDim.new(0, 12),
            PaddingTop = UDim.new(0, 4),
        }, ServersHold)

        local launcher = corner(create("TextButton", {
            Name = "N4THLauncher",
            Position = UDim2.new(0, 16, 0.5, -24),
            Size = UDim2.fromOffset(48, 48),
            BackgroundColor3 = DiscordColors.Blurple,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = DiscordColors.Text,
            Text = Session.BrandLogo and "" or "N4",
            AutoButtonColor = false,
            Visible = false,
        }, gui), UDim.new(0, 15))
        create("UIStroke", { Color = DiscordColors.Main, Thickness = 2 }, launcher)
        if Session.BrandLogo then
            create("ImageLabel", {
                BackgroundTransparency = 1,
                Image = Session.BrandLogo,
                ScaleType = Enum.ScaleType.Fit,
                Position = UDim2.fromOffset(7, 7),
                Size = UDim2.fromOffset(34, 34),
            }, launcher)
        end
        makeDraggable(launcher, launcher)

        local function showWindow(show)
            MainFrame.Visible = show
            launcher.Visible = not show
            windowObj.Closed = not show
        end

        CloseBtn.MouseButton1Click:Connect(function() showWindow(false) end)
        launcher.MouseButton1Click:Connect(function() showWindow(true) end)

        CloseBtn.MouseEnter:Connect(function() CloseBtn.BackgroundColor3 = DiscordColors.Red end)
        CloseBtn.MouseLeave:Connect(function() CloseBtn.BackgroundColor3 = DiscordColors.Main end)

        MinimizeBtn.MouseEnter:Connect(function() MinimizeBtn.BackgroundColor3 = Color3.fromRGB(40, 43, 46) end)
        MinimizeBtn.MouseLeave:Connect(function() MinimizeBtn.BackgroundColor3 = DiscordColors.Main end)

        MinimizeBtn.MouseButton1Click:Connect(function()
            if not minimized then
                MainFrame:TweenSize(UDim2.new(0, 681, 0, 22), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true)
            else
                MainFrame:TweenSize(UDim2.new(0, 681, 0, 396), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true)
            end
            minimized = not minimized
        end)

        makeDraggable(TopFrame, MainFrame)

        table.insert(Connections, UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == Enum.KeyCode.Insert or input.KeyCode == Enum.KeyCode.RightShift then
                showWindow(windowObj.Closed)
            end
        end))

        function DiscordLib:Notification(titletext, desctext, btntext)
            local NotificationHolderMain = create("TextButton", {
                Name = "NotificationHolderMain",
                BackgroundColor3 = Color3.fromRGB(22, 22, 22),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0.056, 0),
                Size = UDim2.new(0, 681, 0, 374),
                AutoButtonColor = false,
                Font = Enum.Font.SourceSans,
                Text = "",
                ZIndex = 20,
            }, MainFrame)

            TweenService:Create(
                NotificationHolderMain,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundTransparency = 0.2 }
            ):Play()

            local Notification = corner(create("Frame", {
                Name = "Notification",
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = DiscordColors.ChannelBg,
                ClipsDescendants = true,
                Position = UDim2.new(0.525, 0, 0.469, 0),
                Size = UDim2.new(0, 0, 0, 0),
                BackgroundTransparency = 1,
                ZIndex = 21,
            }, NotificationHolderMain), 5)

            Notification:TweenSize(UDim2.new(0, 346, 0, 176), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
            TweenService:Create(
                Notification,
                TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundTransparency = 0 }
            ):Play()

            local UnderBar = corner(create("Frame", {
                Name = "UnderBar",
                BackgroundColor3 = DiscordColors.Sidebar,
                Position = UDim2.new(0, 0, 0.945, 0),
                Size = UDim2.new(0, 346, 0, 10),
                ZIndex = 22,
            }, Notification), 5)

            create("Frame", {
                Name = "UnderBarFrame",
                BackgroundColor3 = DiscordColors.Sidebar,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, -3.76, 0),
                Size = UDim2.new(0, 346, 0, 40),
                ZIndex = 22,
            }, UnderBar)

            create("TextLabel", {
                Name = "Text1",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 0, 0.02, 0),
                Size = UDim2.new(0, 346, 0, 68),
                Font = Enum.Font.GothamSemibold,
                Text = tostring(titletext or "Notification"),
                TextColor3 = DiscordColors.Text,
                TextSize = 20,
                ZIndex = 23,
            }, Notification)

            create("TextLabel", {
                Name = "Text2",
                BackgroundTransparency = 1,
                Position = UDim2.new(0.106, 0, 0.318, 0),
                Size = UDim2.new(0, 272, 0, 63),
                Font = Enum.Font.Gotham,
                Text = tostring(desctext or ""),
                TextColor3 = DiscordColors.SubText,
                TextSize = 14,
                TextWrapped = true,
                ZIndex = 23,
            }, Notification)

            local AlrightBtn = corner(create("TextButton", {
                Name = "AlrightBtn",
                BackgroundColor3 = DiscordColors.Blurple,
                Position = UDim2.new(0.033, 0, 0.789, 0),
                Size = UDim2.new(0, 322, 0, 27),
                Font = Enum.Font.Gotham,
                Text = tostring(btntext or "Okay!"),
                TextColor3 = DiscordColors.Text,
                TextSize = 13,
                AutoButtonColor = false,
                ZIndex = 23,
            }, Notification), 4)

            AlrightBtn.MouseEnter:Connect(function()
                TweenService:Create(AlrightBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = DiscordColors.BlurpleHover }):Play()
            end)
            AlrightBtn.MouseLeave:Connect(function()
                TweenService:Create(AlrightBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = DiscordColors.Blurple }):Play()
            end)
            AlrightBtn.MouseButton1Click:Connect(function()
                TweenService:Create(NotificationHolderMain, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
                Notification:TweenSize(UDim2.new(0, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
                TweenService:Create(Notification, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
                task.delay(0.22, function()
                    if NotificationHolderMain.Parent then NotificationHolderMain:Destroy() end
                end)
            end)
        end

        local function buildChannelControls(ChannelHolder, ChannelHolderLayout)
            local function updateCanvas()
                ChannelHolder.CanvasSize = UDim2.new(0, 0, 0, ChannelHolderLayout.AbsoluteContentSize.Y + 12)
            end
            ChannelHolderLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

            local function attachMethods(targetContainer)
                local ChannelContent = { Body = targetContainer }

                function ChannelContent:Seperator()
                    local Seperator1 = create("Frame", {
                        Name = "Seperator1",
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, 8),
                    }, targetContainer)
                    create("Frame", {
                        Name = "Seperator2",
                        BackgroundColor3 = DiscordColors.Divider,
                        BorderSizePixel = 0,
                        Position = UDim2.new(0, 0, 0, 4),
                        Size = UDim2.new(1, 0, 0, 1),
                    }, Seperator1)
                    updateCanvas()
                    return Seperator1
                end

                function ChannelContent:Label(labelText)
                    local Label = create("TextButton", {
                        Name = "Label",
                        BackgroundColor3 = DiscordColors.ChannelBg,
                        BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 30),
                        AutoButtonColor = false,
                        Font = Enum.Font.Gotham,
                        Text = "",
                        TextColor3 = DiscordColors.Text,
                        TextSize = 14,
                    }, targetContainer)
                    local LabelTitle = create("TextLabel", {
                        Name = "LabelTitle",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 5, 0, 0),
                        Size = UDim2.new(1, -10, 0, 30),
                        Font = Enum.Font.Gotham,
                        Text = tostring(labelText or ""),
                        TextColor3 = DiscordColors.Muted,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextWrapped = true,
                    }, Label)
                    updateCanvas()
                    return {
                        SetTitle = function(_, nextText) LabelTitle.Text = tostring(nextText or "") end,
                        SetDesc = function(_, nextText) LabelTitle.Text = tostring(nextText or "") end,
                    }
                end

                function ChannelContent:Paragraph(options)
                    options = type(options) == "table" and options or { Title = tostring(options or ""), Desc = "" }
                    local card = corner(create("Frame", {
                        Name = "EmbedParagraph",
                        BackgroundColor3 = DiscordColors.Sidebar,
                        BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                    }, targetContainer), 4)
                    corner(create("Frame", {
                        Name = "EmbedBar",
                        BackgroundColor3 = DiscordColors.Blurple,
                        BorderSizePixel = 0,
                        Size = UDim2.new(0, 4, 1, 0),
                    }, card), 4)
                    local inner = create("Frame", {
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(12, 0),
                        Size = UDim2.new(1, -18, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                    }, card)
                    create("UIPadding", {
                        PaddingTop = UDim.new(0, 8),
                        PaddingBottom = UDim.new(0, 8),
                    }, inner)
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 4),
                    }, inner)
                    local heading = create("TextLabel", {
                        BackgroundTransparency = 1,
                        LayoutOrder = 1,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        Font = Enum.Font.GothamSemibold,
                        Text = tostring(options.Title or ""),
                        TextColor3 = DiscordColors.Text,
                        TextSize = 13,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, inner)
                    local desc = create("TextLabel", {
                        BackgroundTransparency = 1,
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        Font = Enum.Font.Gotham,
                        Text = tostring(options.Desc or ""),
                        TextColor3 = DiscordColors.SubText,
                        TextSize = 12,
                        TextWrapped = true,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        Visible = tostring(options.Desc or "") ~= "",
                    }, inner)
                    local control = {}
                    function control:SetDesc(nextText)
                        desc.Text = tostring(nextText or "")
                        desc.Visible = desc.Text ~= ""
                        updateCanvas()
                    end
                    function control:SetTitle(nextText)
                        heading.Text = tostring(nextText or "")
                        updateCanvas()
                    end
                    updateCanvas()
                    return control
                end

                function ChannelContent:Button(arg1, arg2)
                    local btnTitle, btnDesc, btnCallback
                    if type(arg1) == "table" then
                        btnTitle = tostring(arg1.Title or "")
                        btnDesc = arg1.Desc and tostring(arg1.Desc) or nil
                        btnCallback = arg1.Callback
                    else
                        btnTitle = tostring(arg1 or "")
                        btnCallback = arg2
                    end
                    local hasDesc = btnDesc and btnDesc ~= ""
                    local Button = corner(create("TextButton", {
                        Name = "Button",
                        BackgroundColor3 = DiscordColors.Blurple,
                        Size = UDim2.new(1, 0, 0, hasDesc and 44 or 30),
                        AutoButtonColor = false,
                        Font = Enum.Font.GothamSemibold,
                        TextColor3 = DiscordColors.Text,
                        TextSize = 14,
                        Text = hasDesc and "" or btnTitle,
                    }, targetContainer), 4)

                    if hasDesc then
                        create("TextLabel", {
                            BackgroundTransparency = 1,
                            Position = UDim2.fromOffset(10, 4),
                            Size = UDim2.new(1, -20, 0, 18),
                            Font = Enum.Font.GothamSemibold,
                            Text = btnTitle,
                            TextColor3 = DiscordColors.Text,
                            TextSize = 13,
                            TextXAlignment = Enum.TextXAlignment.Left,
                        }, Button)
                        create("TextLabel", {
                            BackgroundTransparency = 1,
                            Position = UDim2.fromOffset(10, 22),
                            Size = UDim2.new(1, -20, 0, 18),
                            Font = Enum.Font.Gotham,
                            Text = btnDesc,
                            TextColor3 = Color3.fromRGB(225, 230, 255),
                            TextSize = 11,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            TextTruncate = Enum.TextTruncate.AtEnd,
                        }, Button)
                    end

                    Button.MouseEnter:Connect(function()
                        TweenService:Create(Button, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = DiscordColors.BlurpleHover }):Play()
                    end)
                    Button.MouseLeave:Connect(function()
                        TweenService:Create(Button, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = DiscordColors.Blurple }):Play()
                    end)
                    Button.MouseButton1Click:Connect(function()
                        callback(btnCallback)
                        if not hasDesc then
                            Button.TextSize = 0
                            TweenService:Create(Button, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextSize = 14 }):Play()
                        end
                    end)
                    updateCanvas()
                    return Button
                end

                function ChannelContent:Toggle(arg1, arg2, arg3)
                    local titleText, descText, defaultVal, toggleCallback
                    if type(arg1) == "table" then
                        titleText = tostring(arg1.Title or "")
                        descText = arg1.Desc and tostring(arg1.Desc) or nil
                        defaultVal = arg1.Value == true
                        toggleCallback = arg1.Callback
                    else
                        titleText = tostring(arg1 or "")
                        defaultVal = arg2 == true
                        toggleCallback = arg3
                    end
                    local hasDesc = descText and descText ~= ""
                    local Toggle = create("TextButton", {
                        Name = "Toggle",
                        BackgroundColor3 = DiscordColors.ChannelBg,
                        BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, hasDesc and 44 or 30),
                        AutoButtonColor = false,
                        Font = Enum.Font.Gotham,
                        Text = "",
                    }, targetContainer)

                    local ToggleTitle = create("TextLabel", {
                        Name = "ToggleTitle",
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(5, hasDesc and 2 or 0),
                        Size = UDim2.new(1, -60, 0, hasDesc and 20 or 30),
                        Font = Enum.Font.Gotham,
                        Text = titleText,
                        TextColor3 = DiscordColors.Text,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                    }, Toggle)

                    if hasDesc then
                        create("TextLabel", {
                            Name = "ToggleDesc",
                            BackgroundTransparency = 1,
                            Position = UDim2.fromOffset(5, 21),
                            Size = UDim2.new(1, -60, 0, 20),
                            Font = Enum.Font.Gotham,
                            Text = descText,
                            TextColor3 = DiscordColors.Muted,
                            TextSize = 11,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            TextWrapped = true,
                        }, Toggle)
                    end

                    local ToggleFrame = corner(create("Frame", {
                        Name = "ToggleFrame",
                        AnchorPoint = Vector2.new(1, 0.5),
                        BackgroundColor3 = DiscordColors.SwitchOff,
                        Position = UDim2.new(1, -5, 0.5, 0),
                        Size = UDim2.new(0, 40, 0, 21),
                    }, Toggle), UDim.new(1, 8))

                    local ToggleFrameCircle = corner(create("Frame", {
                        Name = "ToggleFrameCircle",
                        BackgroundColor3 = DiscordColors.Text,
                        Position = UDim2.new(0.235, -5, 0.133, 0),
                        Size = UDim2.new(0, 15, 0, 15),
                    }, ToggleFrame), UDim.new(1, 0))

                    local Icon = create("ImageLabel", {
                        Name = "Icon",
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 8, 0, 8),
                        Size = UDim2.new(0, 13, 0, 13),
                        Image = "http://www.roblox.com/asset/?id=6035047409",
                        ImageColor3 = DiscordColors.SwitchOff,
                    }, ToggleFrameCircle)

                    create("Frame", {
                        BackgroundColor3 = DiscordColors.Divider,
                        BackgroundTransparency = 0.5,
                        BorderSizePixel = 0,
                        Position = UDim2.new(0, 5, 1, -1),
                        Size = UDim2.new(1, -10, 0, 1),
                    }, Toggle)

                    local control = { Value = false }
                    local function renderState(on)
                        ToggleTitle.TextColor3 = on and DiscordColors.Text or DiscordColors.SubText
                        local targetColor = on and DiscordColors.Green or DiscordColors.SwitchOff
                        TweenService:Create(Icon, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageColor3 = targetColor }):Play()
                        TweenService:Create(ToggleFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = targetColor }):Play()
                        ToggleFrameCircle:TweenPosition(
                            on and UDim2.new(0.655, -5, 0.133, 0) or UDim2.new(0.235, -5, 0.133, 0),
                            Enum.EasingDirection.Out,
                            Enum.EasingStyle.Quart,
                            0.25,
                            true
                        )
                        Icon.Image = on and "http://www.roblox.com/asset/?id=6023426926" or "http://www.roblox.com/asset/?id=6035047409"
                    end

                    function control:Set(value, fire)
                        value = value == true
                        if self.Value == value then return end
                        self.Value = value
                        renderState(value)
                        if fire ~= false then callback(toggleCallback, value) end
                    end

                    control.Value = defaultVal
                    renderState(defaultVal)

                    Toggle.MouseButton1Click:Connect(function()
                        control:Set(not control.Value)
                    end)

                    updateCanvas()
                    return control
                end

                function ChannelContent:Slider(arg1, minArg, maxArg, startArg, cbArg)
                    local titleText, descText, min, max, start, step, sliderCallback
                    if type(arg1) == "table" then
                        titleText = tostring(arg1.Title or "")
                        descText = arg1.Desc and tostring(arg1.Desc) or nil
                        local range = arg1.Value or {}
                        min = tonumber(range.Min) or 0
                        max = tonumber(range.Max) or 100
                        start = tonumber(range.Default) or min
                        step = tonumber(arg1.Step) or 1
                        sliderCallback = arg1.Callback
                    else
                        titleText = tostring(arg1 or "")
                        min = tonumber(minArg) or 0
                        max = tonumber(maxArg) or 100
                        start = tonumber(startArg) or min
                        step = 1
                        sliderCallback = cbArg
                    end
                    if max <= min then max = min + 1 end
                    local hasDesc = descText and descText ~= ""

                    local SliderFunc = {}
                    local dragging = false
                    local value = math.clamp(start, min, max)

                    local Slider = create("TextButton", {
                        Name = "Slider",
                        BackgroundColor3 = DiscordColors.ChannelBg,
                        BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, hasDesc and 52 or 38),
                        AutoButtonColor = false,
                        Font = Enum.Font.Gotham,
                        Text = "",
                    }, targetContainer)

                    create("TextLabel", {
                        Name = "SliderTitle",
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(5, 0),
                        Size = UDim2.new(1, -75, 0, 20),
                        Font = Enum.Font.Gotham,
                        Text = titleText,
                        TextColor3 = DiscordColors.SubText,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                    }, Slider)

                    local HeaderValue = create("TextLabel", {
                        Name = "HeaderValue",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(1, -68, 0, 0),
                        Size = UDim2.new(0, 63, 0, 20),
                        Font = Enum.Font.GothamSemibold,
                        Text = tostring(value),
                        TextColor3 = DiscordColors.Text,
                        TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Right,
                    }, Slider)

                    if hasDesc then
                        create("TextLabel", {
                            Name = "SliderDesc",
                            BackgroundTransparency = 1,
                            Position = UDim2.fromOffset(5, 18),
                            Size = UDim2.new(1, -10, 0, 15),
                            Font = Enum.Font.Gotham,
                            Text = descText,
                            TextColor3 = DiscordColors.Muted,
                            TextSize = 11,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            TextTruncate = Enum.TextTruncate.AtEnd,
                        }, Slider)
                    end

                    local SliderFrame = corner(create("Frame", {
                        Name = "SliderFrame",
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        BackgroundColor3 = DiscordColors.SliderTrack,
                        Position = UDim2.new(0.5, 0, 1, -10),
                        Size = UDim2.new(1, -16, 0, 8),
                    }, Slider), 4)

                    local initRatio = math.clamp((value - min) / (max - min), 0, 1)
                    local CurrentValueFrame = corner(create("Frame", {
                        Name = "CurrentValueFrame",
                        BackgroundColor3 = DiscordColors.Blurple,
                        Size = UDim2.new(initRatio, 0, 0, 8),
                    }, SliderFrame), 4)

                    local Zip = corner(create("Frame", {
                        Name = "Zip",
                        BackgroundColor3 = DiscordColors.Text,
                        Position = UDim2.new(initRatio, -5, -0.645, 0),
                        Size = UDim2.new(0, 10, 0, 18),
                    }, SliderFrame), 3)

                    local ValueBubble = corner(create("Frame", {
                        Name = "ValueBubble",
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        BackgroundColor3 = Color3.fromRGB(38, 38, 38),
                        Position = UDim2.new(0.5, 0, -1.008, 0),
                        Size = UDim2.new(0, 36, 0, 21),
                        Visible = false,
                        ZIndex = 8,
                    }, Zip), 3)

                    local ValueLabel = create("TextLabel", {
                        Name = "ValueLabel",
                        BackgroundTransparency = 1,
                        Size = UDim2.new(0, 36, 0, 21),
                        Font = Enum.Font.Gotham,
                        Text = tostring(value),
                        TextColor3 = DiscordColors.Text,
                        TextSize = 10,
                        ZIndex = 9,
                    }, ValueBubble)

                    Zip.MouseEnter:Connect(function()
                        if not dragging then ValueBubble.Visible = true end
                    end)
                    Zip.MouseLeave:Connect(function()
                        if not dragging then ValueBubble.Visible = false end
                    end)

                    local function snapValue(raw)
                        local clamped = math.clamp(raw, min, max)
                        if step and step > 0 then
                            local snapped = min + math.floor(((clamped - min) / step) + 0.5) * step
                            if step % 1 == 0 then
                                snapped = math.floor(snapped + 0.5)
                            else
                                snapped = tonumber(string.format("%.4f", snapped)) or snapped
                            end
                            return math.clamp(snapped, min, max)
                        end
                        return math.floor(clamped + 0.5)
                    end

                    local function applyValue(nextVal, fire)
                        local snapped = snapValue(tonumber(nextVal) or value)
                        local ratio = math.clamp((snapped - min) / (max - min), 0, 1)
                        CurrentValueFrame.Size = UDim2.new(ratio, 0, 0, 8)
                        Zip.Position = UDim2.new(ratio, -5, -0.645, 0)
                        ValueLabel.Text = tostring(snapped)
                        HeaderValue.Text = tostring(snapped)
                        local changed = snapped ~= value
                        value = snapped
                        if fire ~= false and changed then
                            callback(sliderCallback, value)
                        end
                    end

                    local function moveFromInput(input)
                        local width = math.max(1, SliderFrame.AbsoluteSize.X)
                        local ratio = math.clamp((input.Position.X - SliderFrame.AbsolutePosition.X) / width, 0, 1)
                        applyValue(min + ratio * (max - min), true)
                    end

                    local function beginSlide(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            dragging = true
                            ValueBubble.Visible = true
                            moveFromInput(input)
                        end
                    end
                    Zip.InputBegan:Connect(beginSlide)
                    SliderFrame.InputBegan:Connect(beginSlide)

                    table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                            dragging = false
                            ValueBubble.Visible = false
                        end
                    end))
                    table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
                        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                            moveFromInput(input)
                        end
                    end))

                    function SliderFunc:Change(tochange)
                        applyValue(tochange, true)
                    end
                    function SliderFunc:Set(tochange, fire)
                        applyValue(tochange, fire)
                    end

                    updateCanvas()
                    return SliderFunc
                end

                function ChannelContent:Textbox(arg1, arg2, arg3, arg4)
                    local titleText, descText, placeText, initValue, disappear, boxCallback
                    local isTableMode = type(arg1) == "table"
                    if isTableMode then
                        titleText = tostring(arg1.Title or "")
                        descText = arg1.Desc and tostring(arg1.Desc) or nil
                        initValue = tostring(arg1.Value or "")
                        placeText = tostring(arg1.Placeholder or "")
                        disappear = false
                        boxCallback = arg1.Callback
                    else
                        titleText = tostring(arg1 or "")
                        initValue = ""
                        placeText = tostring(arg2 or "")
                        disappear = arg3 == true
                        boxCallback = arg4
                    end
                    local hasDesc = descText and descText ~= ""
                    local headerH = hasDesc and 38 or 25

                    local Textbox = create("Frame", {
                        Name = "Textbox",
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, headerH + 38),
                    }, targetContainer)

                    create("TextLabel", {
                        Name = "TextboxTitle",
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(5, 0),
                        Size = UDim2.new(1, -10, 0, 22),
                        Font = Enum.Font.Gotham,
                        Text = titleText,
                        TextColor3 = DiscordColors.SubText,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, Textbox)

                    if hasDesc then
                        create("TextLabel", {
                            Name = "TextboxDesc",
                            BackgroundTransparency = 1,
                            Position = UDim2.fromOffset(5, 19),
                            Size = UDim2.new(1, -10, 0, 16),
                            Font = Enum.Font.Gotham,
                            Text = descText,
                            TextColor3 = DiscordColors.Muted,
                            TextSize = 11,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            TextTruncate = Enum.TextTruncate.AtEnd,
                        }, Textbox)
                    end

                    local TextboxFrameOutline = corner(create("Frame", {
                        Name = "TextboxFrameOutline",
                        BackgroundColor3 = DiscordColors.InputOutline,
                        Position = UDim2.fromOffset(2, headerH),
                        Size = UDim2.new(1, -4, 0, 36),
                    }, Textbox), 3)

                    local TextboxFrame = corner(create("Frame", {
                        Name = "TextboxFrame",
                        BackgroundColor3 = DiscordColors.InputBg,
                        ClipsDescendants = true,
                        Position = UDim2.fromOffset(2, 2),
                        Size = UDim2.new(1, -4, 1, -4),
                    }, TextboxFrameOutline), 3)

                    local TextBox = create("TextBox", {
                        Name = "TextBox",
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(8, 0),
                        Size = UDim2.new(1, -16, 1, 0),
                        ClearTextOnFocus = false,
                        Font = Enum.Font.Gotham,
                        PlaceholderColor3 = DiscordColors.ChannelIdle,
                        PlaceholderText = placeText,
                        Text = initValue,
                        TextColor3 = DiscordColors.Text,
                        TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, TextboxFrame)

                    local last = TextBox.Text
                    local control = {}
                    function control:Set(value)
                        TextBox.Text = tostring(value or "")
                        last = TextBox.Text
                    end

                    TextBox.Focused:Connect(function()
                        TweenService:Create(
                            TextboxFrameOutline,
                            TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                            { BackgroundColor3 = DiscordColors.Blurple }
                        ):Play()
                    end)

                    TextBox.FocusLost:Connect(function(enterPressed)
                        TweenService:Create(
                            TextboxFrameOutline,
                            TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                            { BackgroundColor3 = DiscordColors.InputOutline }
                        ):Play()
                        if isTableMode then
                            if TextBox.Text == last then return end
                            last = TextBox.Text
                            callback(boxCallback, last)
                        elseif enterPressed and #TextBox.Text > 0 then
                            callback(boxCallback, TextBox.Text)
                            if disappear then TextBox.Text = "" end
                        end
                    end)

                    updateCanvas()
                    return control
                end

                function ChannelContent:Input(options)
                    return self:Textbox(options)
                end

                function ChannelContent:Dropdown(arg1, listArg, cbArg)
                    local titleText, descText, values, initValue, isMulti, dropCallback
                    if type(arg1) == "table" then
                        titleText = tostring(arg1.Title or "")
                        descText = arg1.Desc and tostring(arg1.Desc) or nil
                        values = arg1.Values or {}
                        initValue = arg1.Value
                        isMulti = arg1.Multi == true
                        dropCallback = arg1.Callback
                    else
                        titleText = tostring(arg1 or "")
                        values = listArg or {}
                        initValue = nil
                        isMulti = false
                        dropCallback = cbArg
                    end

                    local hasDesc = descText and descText ~= ""
                    local headerH = hasDesc and 38 or 25
                    local closedH = headerH + 40
                    local DropTog = false
                    local DropFunc = {
                        Value = isMulti and table.clone(type(initValue) == "table" and initValue or {}) or initValue,
                    }

                    local Dropdown = create("Frame", {
                        Name = "Dropdown",
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, closedH),
                    }, targetContainer)

                    create("TextLabel", {
                        Name = "DropdownTitle",
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(5, 0),
                        Size = UDim2.new(1, -10, 0, 22),
                        Font = Enum.Font.Gotham,
                        Text = titleText,
                        TextColor3 = DiscordColors.SubText,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, Dropdown)

                    if hasDesc then
                        create("TextLabel", {
                            Name = "DropdownDesc",
                            BackgroundTransparency = 1,
                            Position = UDim2.fromOffset(5, 19),
                            Size = UDim2.new(1, -10, 0, 16),
                            Font = Enum.Font.Gotham,
                            Text = descText,
                            TextColor3 = DiscordColors.Muted,
                            TextSize = 11,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            TextTruncate = Enum.TextTruncate.AtEnd,
                        }, Dropdown)
                    end

                    local DropdownFrameOutline = corner(create("Frame", {
                        Name = "DropdownFrameOutline",
                        BackgroundColor3 = DiscordColors.InputOutline,
                        Position = UDim2.fromOffset(2, headerH),
                        Size = UDim2.new(1, -4, 0, 36),
                    }, Dropdown), 3)

                    local DropdownFrame = corner(create("Frame", {
                        Name = "DropdownFrame",
                        BackgroundColor3 = DiscordColors.InputBg,
                        ClipsDescendants = true,
                        Position = UDim2.fromOffset(2, 2),
                        Size = UDim2.new(1, -4, 1, -4),
                    }, DropdownFrameOutline), 3)

                    local CurrentSelectedText = create("TextLabel", {
                        Name = "CurrentSelectedText",
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(8, 0),
                        Size = UDim2.new(1, -36, 1, 0),
                        Font = Enum.Font.Gotham,
                        Text = "...",
                        TextColor3 = Color3.fromRGB(212, 212, 212),
                        TextSize = 13,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                    }, DropdownFrame)

                    local ArrowImg = create("ImageLabel", {
                        Name = "ArrowImg",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(1, -26, 0.5, -11),
                        Size = UDim2.new(0, 22, 0, 22),
                        Image = "http://www.roblox.com/asset/?id=6034818372",
                        ImageColor3 = Color3.fromRGB(212, 212, 212),
                    }, DropdownFrame)

                    local DropdownFrameBtn = create("TextButton", {
                        Name = "DropdownFrameBtn",
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 1, 0),
                        Text = "",
                    }, DropdownFrame)

                    local DropdownFrameMainOutline = corner(create("Frame", {
                        Name = "DropdownFrameMainOutline",
                        BackgroundColor3 = DiscordColors.InputOutline,
                        Position = UDim2.fromOffset(2, closedH + 2),
                        Size = UDim2.new(1, -4, 0, 140),
                        Visible = false,
                    }, Dropdown), 3)

                    local DropdownFrameMain = corner(create("Frame", {
                        Name = "DropdownFrameMain",
                        BackgroundColor3 = DiscordColors.Sidebar,
                        ClipsDescendants = true,
                        Position = UDim2.fromOffset(2, 2),
                        Size = UDim2.new(1, -4, 1, -4),
                        Visible = false,
                    }, DropdownFrameMainOutline), 3)

                    local SearchBox = corner(create("TextBox", {
                        Name = "SearchBox",
                        BackgroundColor3 = DiscordColors.Main,
                        Position = UDim2.fromOffset(4, 4),
                        Size = UDim2.new(1, -8, 0, 24),
                        ClearTextOnFocus = false,
                        Font = Enum.Font.Gotham,
                        PlaceholderColor3 = DiscordColors.ChannelIdle,
                        PlaceholderText = "Search...",
                        Text = "",
                        TextColor3 = DiscordColors.Text,
                        TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, DropdownFrameMain), 3)
                    create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, SearchBox)

                    local DropItemHolder = create("ScrollingFrame", {
                        Name = "ItemHolder",
                        Active = true,
                        BackgroundTransparency = 1,
                        BorderSizePixel = 0,
                        Position = UDim2.fromOffset(4, 32),
                        Size = UDim2.new(1, -8, 1, -36),
                        CanvasSize = UDim2.new(0, 0, 0, 0),
                        AutomaticCanvasSize = Enum.AutomaticSize.Y,
                        ScrollBarThickness = 5,
                        ScrollBarImageColor3 = Color3.fromRGB(28, 29, 32),
                    }, DropdownFrameMain)

                    local DropItemHolderLayout = create("UIListLayout", {
                        Name = "ItemHolderLayout",
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 2),
                    }, DropItemHolder)

                    local function isSelected(itemVal)
                        if isMulti then
                            return type(DropFunc.Value) == "table" and table.find(DropFunc.Value, itemVal) ~= nil
                        end
                        return DropFunc.Value == itemVal
                    end

                    local function repaintSummary()
                        if isMulti then
                            local list = type(DropFunc.Value) == "table" and DropFunc.Value or {}
                            CurrentSelectedText.Text = #list > 0 and table.concat(list, ", ") or "..."
                        else
                            CurrentSelectedText.Text = (DropFunc.Value ~= nil and DropFunc.Value ~= "") and tostring(DropFunc.Value) or "..."
                        end
                    end

                    local function updateDropdownSize()
                        if not DropTog then
                            Dropdown.Size = UDim2.new(1, 0, 0, closedH)
                            DropdownFrameMain.Visible = false
                            DropdownFrameMainOutline.Visible = false
                            ArrowImg.Rotation = 0
                        else
                            local visibleCount = 0
                            for _, child in ipairs(DropItemHolder:GetChildren()) do
                                if child:IsA("TextButton") and child.Visible then visibleCount = visibleCount + 1 end
                            end
                            local listH = math.clamp(math.max(1, visibleCount) * 30, 30, 120)
                            local panelH = listH + 40
                            DropdownFrameMainOutline.Size = UDim2.new(1, -4, 0, panelH)
                            DropdownFrameMain.Size = UDim2.new(1, -4, 1, -4)
                            DropdownFrameMain.Visible = true
                            DropdownFrameMainOutline.Visible = true
                            Dropdown.Size = UDim2.new(1, 0, 0, closedH + panelH + 4)
                            ArrowImg.Rotation = 180
                        end
                        updateCanvas()
                    end

                    local function renderItems()
                        for _, child in ipairs(DropItemHolder:GetChildren()) do
                            if child:IsA("TextButton") then child:Destroy() end
                        end
                        local query = SearchBox.Text:lower()
                        for _, itemVal in ipairs(values) do
                            local itemStr = tostring(itemVal)
                            if query == "" or itemStr:lower():find(query, 1, true) then
                                local picked = isSelected(itemVal)
                                local Item = corner(create("TextButton", {
                                    Name = "Item",
                                    BackgroundColor3 = picked and DiscordColors.Blurple or DiscordColors.ItemHover,
                                    BackgroundTransparency = picked and 0.15 or 1,
                                    Size = UDim2.new(1, -6, 0, 28),
                                    AutoButtonColor = false,
                                    Font = Enum.Font.SourceSans,
                                    Text = "",
                                }, DropItemHolder), 4)

                                if picked then
                                    create("ImageLabel", {
                                        Name = "CheckIcon",
                                        BackgroundTransparency = 1,
                                        Position = UDim2.new(0, 7, 0.5, -7),
                                        Size = UDim2.fromOffset(14, 14),
                                        Image = "http://www.roblox.com/asset/?id=6023426926",
                                        ImageColor3 = DiscordColors.Text,
                                    }, Item)
                                end

                                local ItemText = create("TextLabel", {
                                    Name = "ItemText",
                                    BackgroundTransparency = 1,
                                    Position = UDim2.fromOffset(picked and 26 or 8, 0),
                                    Size = UDim2.new(1, picked and -34 or -16, 1, 0),
                                    Font = Enum.Font.Gotham,
                                    TextColor3 = picked and DiscordColors.Text or Color3.fromRGB(212, 212, 212),
                                    TextSize = 13,
                                    TextXAlignment = Enum.TextXAlignment.Left,
                                    TextTruncate = Enum.TextTruncate.AtEnd,
                                    Text = itemStr,
                                }, Item)

                                Item.MouseEnter:Connect(function()
                                    ItemText.TextColor3 = DiscordColors.Text
                                    Item.BackgroundTransparency = 0
                                end)
                                Item.MouseLeave:Connect(function()
                                    local nowPicked = isSelected(itemVal)
                                    ItemText.TextColor3 = nowPicked and DiscordColors.Text or Color3.fromRGB(212, 212, 212)
                                    Item.BackgroundColor3 = nowPicked and DiscordColors.Blurple or DiscordColors.ItemHover
                                    Item.BackgroundTransparency = nowPicked and 0.15 or 1
                                end)
                                Item.MouseButton1Click:Connect(function()
                                    if isMulti then
                                        if type(DropFunc.Value) ~= "table" then DropFunc.Value = {} end
                                        local idx = table.find(DropFunc.Value, itemVal)
                                        if idx then
                                            table.remove(DropFunc.Value, idx)
                                        else
                                            table.insert(DropFunc.Value, itemVal)
                                        end
                                        repaintSummary()
                                        renderItems()
                                        callback(dropCallback, table.clone(DropFunc.Value))
                                    else
                                        DropFunc.Value = itemVal
                                        DropTog = false
                                        repaintSummary()
                                        renderItems()
                                        updateDropdownSize()
                                        callback(dropCallback, itemVal)
                                    end
                                end)
                            end
                        end
                        DropItemHolder.CanvasSize = UDim2.new(0, 0, 0, DropItemHolderLayout.AbsoluteContentSize.Y)
                        if DropTog then updateDropdownSize() end
                    end

                    DropdownFrameBtn.MouseButton1Click:Connect(function()
                        DropTog = not DropTog
                        if DropTog then renderItems() end
                        updateDropdownSize()
                    end)

                    SearchBox:GetPropertyChangedSignal("Text"):Connect(renderItems)

                    function DropFunc:Refresh(nextValues)
                        values = nextValues or {}
                        repaintSummary()
                        if DropTog then renderItems() end
                    end

                    function DropFunc:Select(value)
                        self.Value = isMulti and table.clone(type(value) == "table" and value or {}) or value
                        repaintSummary()
                        if DropTog then renderItems() end
                    end

                    function DropFunc:Clear()
                        values = {}
                        self.Value = isMulti and {} or nil
                        DropTog = false
                        repaintSummary()
                        renderItems()
                        updateDropdownSize()
                    end

                    function DropFunc:Add(textadd)
                        table.insert(values, textadd)
                        if DropTog then renderItems() end
                    end

                    repaintSummary()
                    updateCanvas()
                    return DropFunc
                end

                function ChannelContent:Bind(bindText, presetbind, bindCallback)
                    local Key = (presetbind and presetbind.Name) or "RightShift"
                    local Keybind = create("TextButton", {
                        Name = "Keybind",
                        BackgroundColor3 = DiscordColors.ChannelBg,
                        BorderSizePixel = 0,
                        Size = UDim2.new(1, 0, 0, 30),
                        AutoButtonColor = false,
                        Font = Enum.Font.Gotham,
                        Text = "",
                    }, targetContainer)
                    create("TextLabel", {
                        Name = "KeybindTitle",
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(5, 0),
                        Size = UDim2.new(1, -100, 0, 30),
                        Font = Enum.Font.Gotham,
                        Text = tostring(bindText or ""),
                        TextColor3 = DiscordColors.SubText,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, Keybind)
                    local KeybindText = create("TextLabel", {
                        Name = "KeybindText",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(1, -90, 0, 0),
                        Size = UDim2.new(0, 85, 0, 30),
                        Font = Enum.Font.Gotham,
                        Text = Key,
                        TextColor3 = DiscordColors.Muted,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Right,
                    }, Keybind)
                    Keybind.MouseButton1Click:Connect(function()
                        KeybindText.Text = "..."
                        local inputwait = UserInputService.InputBegan:Wait()
                        if inputwait.KeyCode.Name ~= "Unknown" then
                            KeybindText.Text = inputwait.KeyCode.Name
                            Key = inputwait.KeyCode.Name
                        end
                    end)
                    table.insert(Connections, UserInputService.InputBegan:Connect(function(current, pressed)
                        if not pressed and current.KeyCode.Name == Key then
                            callback(bindCallback)
                        end
                    end))
                    updateCanvas()
                    return Keybind
                end

                function ChannelContent:Section(options)
                    options = type(options) == "table" and options or { Title = tostring(options or ""), Opened = true }
                    local sectionFrame = create("Frame", {
                        Name = "DiscordSection",
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                    }, targetContainer)
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 6),
                    }, sectionFrame)

                    local headerBtn = corner(create("TextButton", {
                        Name = "SectionHeader",
                        LayoutOrder = 1,
                        BackgroundColor3 = DiscordColors.Sidebar,
                        Size = UDim2.new(1, 0, 0, 28),
                        AutoButtonColor = false,
                        Font = Enum.Font.GothamBold,
                        Text = "",
                    }, sectionFrame), 4)

                    local arrowIcon = create("ImageLabel", {
                        Name = "ArrowIcon",
                        BackgroundTransparency = 1,
                        Position = UDim2.new(0, 6, 0.5, -8),
                        Size = UDim2.fromOffset(16, 16),
                        Image = "http://www.roblox.com/asset/?id=6034818372",
                        ImageColor3 = DiscordColors.Muted,
                    }, headerBtn)

                    local headerTitle = create("TextLabel", {
                        BackgroundTransparency = 1,
                        Position = UDim2.fromOffset(25, 0),
                        Size = UDim2.new(1, -31, 1, 0),
                        Font = Enum.Font.GothamBold,
                        Text = string.upper(tostring(options.Title or "")),
                        TextColor3 = DiscordColors.Muted,
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                    }, headerBtn)

                    local body = create("Frame", {
                        Name = "SectionBody",
                        LayoutOrder = 2,
                        BackgroundTransparency = 1,
                        Size = UDim2.new(1, 0, 0, 0),
                        AutomaticSize = Enum.AutomaticSize.Y,
                        Visible = options.Opened == true,
                    }, sectionFrame)
                    create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 2) }, body)
                    create("UIListLayout", {
                        SortOrder = Enum.SortOrder.LayoutOrder,
                        Padding = UDim.new(0, 6),
                    }, body)

                    local function repaintHeader()
                        arrowIcon.Rotation = body.Visible and 0 or -90
                        headerTitle.TextColor3 = body.Visible and DiscordColors.Text or DiscordColors.Muted
                        arrowIcon.ImageColor3 = body.Visible and DiscordColors.Blurple or DiscordColors.Muted
                        updateCanvas()
                    end
                    headerBtn.MouseEnter:Connect(function()
                        headerBtn.BackgroundColor3 = DiscordColors.ChannelActive
                    end)
                    headerBtn.MouseLeave:Connect(function()
                        headerBtn.BackgroundColor3 = DiscordColors.Sidebar
                    end)
                    headerBtn.MouseButton1Click:Connect(function()
                        body.Visible = not body.Visible
                        repaintHeader()
                    end)
                    repaintHeader()
                    return attachMethods(body)
                end

                return ChannelContent
            end

            return attachMethods(ChannelHolder)
        end

        function windowObj:Server(serverText, img)
            local firstChannel = false
            local currentChannelToggled = ""
            local Server = create("TextButton", {
                Name = serverText .. "Server",
                BackgroundColor3 = DiscordColors.Sidebar,
                Position = UDim2.new(0.125, 0, 0, 0),
                Size = UDim2.new(0, 47, 0, 47),
                AutoButtonColor = false,
                Font = Enum.Font.GothamSemibold,
                Text = "",
                TextColor3 = DiscordColors.Text,
                TextSize = 18,
            }, ServersHold)

            local ServerBtnCorner = create("UICorner", {
                CornerRadius = UDim.new(1, 0),
                Name = "ServerCorner",
            }, Server)

            local ServerIco = create("ImageLabel", {
                Name = "ServerIco",
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                Position = UDim2.new(0.489, 0, 0.489, 0),
                Size = UDim2.new(0, 26, 0, 26),
                Image = "",
                ScaleType = Enum.ScaleType.Fit,
            }, Server)

            local ServerWhiteFrame = create("Frame", {
                Name = "ServerWhiteFrame",
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = DiscordColors.Text,
                Position = UDim2.new(-0.347, 0, 0.503, 0),
                Size = UDim2.new(0, 11, 0, 10),
            }, Server)

            create("UICorner", {
                CornerRadius = UDim.new(1, 0),
                Name = "ServerWhiteFrameCorner",
            }, ServerWhiteFrame)

            ServersHold.CanvasSize = UDim2.new(0, 0, 0, ServersHoldLayout.AbsoluteContentSize.Y)

            local ServerFrame = create("Frame", {
                Name = "ServerFrame",
                BackgroundColor3 = DiscordColors.Sidebar,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Position = UDim2.new(0.105726875, 0, 1.01262593, 0),
                Size = UDim2.new(0, 609, 0, 373),
                Visible = false,
            }, ServersHolder)
            corner(ServerFrame, 9)

            create("Frame", {
                Name = "ServerFrame1",
                BackgroundColor3 = DiscordColors.Sidebar,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0.972290039, 0),
                Size = UDim2.new(0, 12, 0, 10),
            }, ServerFrame)

            create("Frame", {
                Name = "ServerFrame2",
                BackgroundColor3 = DiscordColors.Sidebar,
                BorderSizePixel = 0,
                Position = UDim2.new(0.980295539, 0, 0.972290039, 0),
                Size = UDim2.new(0, 12, 0, 9),
            }, ServerFrame)

            local ServerTitleFrame = create("Frame", {
                Name = "ServerTitleFrame",
                BackgroundTransparency = 1,
                Position = UDim2.new(-0.001, 0, -0.0009, 0),
                Size = UDim2.new(0, 180, 0, 40),
            }, ServerFrame)

            create("TextLabel", {
                Name = "ServerTitle",
                BackgroundTransparency = 1,
                Position = UDim2.new(0.075, 0, 0, 0),
                Size = UDim2.new(0, 160, 0, 39),
                Font = Enum.Font.GothamSemibold,
                Text = serverText,
                TextColor3 = DiscordColors.Text,
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, ServerTitleFrame)

            local GlowFrame = create("Frame", {
                Name = "GlowFrame",
                BackgroundTransparency = 1,
                Position = UDim2.new(-0.001, 0, -0.0009, 0),
                Size = UDim2.new(0, 609, 0, 40),
            }, ServerFrame)

            create("ImageLabel", {
                Name = "Glow",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, -15, 0, -15),
                Size = UDim2.new(1, 30, 1, 30),
                ZIndex = 0,
                Image = "rbxassetid://4996891970",
                ImageColor3 = Color3.fromRGB(15, 15, 15),
                ScaleType = Enum.ScaleType.Slice,
                SliceCenter = Rect.new(20, 20, 280, 280),
            }, GlowFrame)

            local ServerContentFrame = create("Frame", {
                Name = "ServerContentFrame",
                BackgroundTransparency = 1,
                Position = UDim2.new(-0.001, 0, 0.106338218, 0),
                Size = UDim2.new(0, 180, 0, 333),
            }, ServerFrame)

            local ChannelTitleFrame = create("Frame", {
                Name = "ChannelTitleFrame",
                BackgroundColor3 = DiscordColors.ChannelBg,
                BorderSizePixel = 0,
                Position = UDim2.new(0.294561088, 0, -0.000900391256, 0),
                Size = UDim2.new(0, 429, 0, 40),
            }, ServerFrame)

            create("TextLabel", {
                Name = "Hashtag",
                BackgroundTransparency = 1,
                Position = UDim2.new(0.0279720277, 0, 0, 0),
                Size = UDim2.new(0, 19, 0, 39),
                Font = Enum.Font.Gotham,
                Text = "#",
                TextColor3 = DiscordColors.ChannelIdle,
                TextSize = 25,
            }, ChannelTitleFrame)

            local ChannelTitle = create("TextLabel", {
                Name = "ChannelTitle",
                BackgroundTransparency = 1,
                Position = UDim2.new(0.0862470865, 0, 0, 0),
                Size = UDim2.new(0, 360, 0, 39),
                Font = Enum.Font.GothamSemibold,
                Text = "",
                TextColor3 = DiscordColors.Text,
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, ChannelTitleFrame)

            local ChannelContentFrame = create("Frame", {
                Name = "ChannelContentFrame",
                BackgroundColor3 = DiscordColors.ChannelBg,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Position = UDim2.new(0.294561088, 0, 0.106338218, 0),
                Size = UDim2.new(0, 429, 0, 333),
            }, ServerFrame)

            create("ImageLabel", {
                Name = "GlowChannel",
                BackgroundTransparency = 1,
                Position = UDim2.new(0, -33, 0, -91),
                Size = UDim2.new(1.06396091, 30, 0.228228226, 30),
                ZIndex = 0,
                Image = "rbxassetid://4996891970",
                ImageColor3 = Color3.fromRGB(15, 15, 15),
                ScaleType = Enum.ScaleType.Slice,
                SliceCenter = Rect.new(20, 20, 280, 280),
            }, ChannelContentFrame)

            local ServerChannelHolder = create("ScrollingFrame", {
                Name = "ServerChannelHolder",
                Active = true,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Position = UDim2.new(0.00535549596, 0, 0.0241984241, 0),
                Selectable = false,
                Size = UDim2.new(0, 179, 0, 278),
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollBarThickness = 4,
                ScrollBarImageColor3 = Color3.fromRGB(18, 19, 21),
                ScrollBarImageTransparency = 1,
            }, ServerContentFrame)

            local ServerChannelHolderLayout = create("UIListLayout", {
                Name = "ServerChannelHolderLayout",
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4),
            }, ServerChannelHolder)

            create("UIPadding", {
                Name = "ServerChannelHolderPadding",
                PaddingLeft = UDim.new(0, 9),
            }, ServerChannelHolder)

            ServerChannelHolder.MouseEnter:Connect(function() ServerChannelHolder.ScrollBarImageTransparency = 0 end)
            ServerChannelHolder.MouseLeave:Connect(function() ServerChannelHolder.ScrollBarImageTransparency = 1 end)

            if not img or img == "" then
                Server.Text = string.sub(serverText, 1, 1)
            else
                ServerIco.Image = img
            end

            local ChannelHold = {
                Name = serverText,
                Button = Server,
                Corner = ServerBtnCorner,
                WhiteFrame = ServerWhiteFrame,
                Frame = ServerFrame,
                ChannelTitle = ChannelTitle,
                ChannelContentFrame = ChannelContentFrame,
                ServerChannelHolder = ServerChannelHolder,
                Tabs = {},
                Channels = {},
            }

            local function activateServerVisuals()
                currentServerToggled = Server.Name
                for _, v in next, ServersHolder:GetChildren() do
                    if v.Name == "ServerFrame" then v.Visible = false end
                end
                ServerFrame.Visible = true
                for _, v in next, ServersHold:GetChildren() do
                    if v.ClassName == "TextButton" then
                        local active = (v == Server)
                        TweenService:Create(v, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            BackgroundColor3 = active and DiscordColors.Blurple or DiscordColors.Sidebar,
                        }):Play()
                        TweenService:Create(v.ServerCorner, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                            CornerRadius = active and UDim.new(0, 15) or UDim.new(1, 0),
                        }):Play()
                        v.ServerWhiteFrame:TweenSize(
                            active and UDim2.new(0, 11, 0, 46) or UDim2.new(0, 11, 0, 10),
                            Enum.EasingDirection.Out,
                            Enum.EasingStyle.Quart,
                            0.3,
                            true
                        )
                    end
                end
            end
            ChannelHold.ActivateServer = activateServerVisuals

            Server.MouseEnter:Connect(function()
                if currentServerToggled ~= Server.Name then
                    TweenService:Create(Server, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = DiscordColors.Blurple }):Play()
                    TweenService:Create(ServerBtnCorner, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CornerRadius = UDim.new(0, 15) }):Play()
                    ServerWhiteFrame:TweenSize(UDim2.new(0, 11, 0, 27), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true)
                end
            end)

            Server.MouseLeave:Connect(function()
                if currentServerToggled ~= Server.Name then
                    TweenService:Create(Server, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = DiscordColors.Sidebar }):Play()
                    TweenService:Create(ServerBtnCorner, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CornerRadius = UDim.new(1, 0) }):Play()
                    ServerWhiteFrame:TweenSize(UDim2.new(0, 11, 0, 10), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true)
                end
            end)

            Server.MouseButton1Click:Connect(function()
                if #ChannelHold.Tabs > 0 then
                    windowObj:SelectTab((ChannelHold.Last or ChannelHold.Tabs[1]).Index)
                else
                    activateServerVisuals()
                end
            end)

            if not firstServer then
                firstServer = true
                activateServerVisuals()
            end

            function ChannelHold:Channel(channelText)
                local ChannelBtn = corner(create("TextButton", {
                    Name = channelText .. "ChannelBtn",
                    BackgroundColor3 = DiscordColors.Sidebar,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0.241, 0, 0.578, 0),
                    Size = UDim2.new(0, 160, 0, 30),
                    AutoButtonColor = false,
                    Font = Enum.Font.SourceSans,
                    Text = "",
                }, ServerChannelHolder), 6)

                local ChannelBtnHashtag = create("TextLabel", {
                    Name = "ChannelBtnHashtag",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.0279720314, 0, 0, 0),
                    Size = UDim2.new(0, 24, 0, 30),
                    Font = Enum.Font.Gotham,
                    Text = "#",
                    TextColor3 = DiscordColors.ChannelIdle,
                    TextSize = 21,
                }, ChannelBtn)

                local ChannelBtnTitle = create("TextLabel", {
                    Name = "ChannelBtnTitle",
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0.173747092, 0, -0.166666672, 0),
                    Size = UDim2.new(0, 128, 0, 39),
                    Font = Enum.Font.Gotham,
                    Text = channelText,
                    TextColor3 = DiscordColors.ChannelIdle,
                    TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                }, ChannelBtn)

                ServerChannelHolder.CanvasSize = UDim2.new(0, 0, 0, ServerChannelHolderLayout.AbsoluteContentSize.Y)

                local ChannelHolder = create("ScrollingFrame", {
                    Name = "ChannelHolder",
                    Active = true,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Position = UDim2.new(0.0360843192, 0, 0.0241984241, 0),
                    Size = UDim2.new(0, 412, 0, 314),
                    ScrollBarThickness = 6,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarImageTransparency = 0,
                    ScrollBarImageColor3 = Color3.fromRGB(18, 19, 21),
                    Visible = false,
                    ClipsDescendants = false,
                }, ChannelContentFrame)

                create("UIPadding", {
                    PaddingRight = UDim.new(0, 10),
                    PaddingBottom = UDim.new(0, 8),
                }, ChannelHolder)

                local ChannelHolderLayout = create("UIListLayout", {
                    Name = "ChannelHolderLayout",
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 6),
                }, ChannelHolder)

                local ChannelContent = buildChannelControls(ChannelHolder, ChannelHolderLayout)
                ChannelContent.Name = channelText
                ChannelContent.Chip = ChannelBtn
                ChannelContent.ChipTitle = ChannelBtnTitle
                ChannelContent.ChipHash = ChannelBtnHashtag
                ChannelContent.Holder = ChannelHolder
                ChannelContent.Category = ChannelHold
                ChannelContent.Index = #windowObj.Tabs + 1

                windowObj.Tabs[ChannelContent.Index] = ChannelContent
                table.insert(ChannelHold.Tabs, ChannelContent)

                local function activateChannelVisuals()
                    for _, v in next, ChannelContentFrame:GetChildren() do
                        if v.Name == "ChannelHolder" then v.Visible = false end
                    end
                    ChannelHolder.Visible = true
                    for _, v in next, ServerChannelHolder:GetChildren() do
                        if v.ClassName == "TextButton" then
                            v.BackgroundColor3 = DiscordColors.Sidebar
                            v.ChannelBtnTitle.TextColor3 = DiscordColors.ChannelIdle
                        end
                    end
                    ServerFrame.Visible = true
                    ChannelTitle.Text = channelText
                    ChannelBtn.BackgroundColor3 = DiscordColors.ChannelActive
                    ChannelBtnTitle.TextColor3 = DiscordColors.Text
                    currentChannelToggled = ChannelBtn.Name
                end
                ChannelContent.ActivateChannel = activateChannelVisuals

                ChannelBtn.MouseEnter:Connect(function()
                    if currentChannelToggled ~= ChannelBtn.Name then
                        ChannelBtn.BackgroundColor3 = DiscordColors.ChannelHover
                        ChannelBtnTitle.TextColor3 = Color3.fromRGB(220, 221, 222)
                    end
                end)

                ChannelBtn.MouseLeave:Connect(function()
                    if currentChannelToggled ~= ChannelBtn.Name then
                        ChannelBtn.BackgroundColor3 = DiscordColors.Sidebar
                        ChannelBtnTitle.TextColor3 = DiscordColors.ChannelIdle
                    end
                end)

                ChannelBtn.MouseButton1Click:Connect(function()
                    windowObj:SelectTab(ChannelContent.Index)
                end)

                if not firstChannel then
                    firstChannel = true
                    activateChannelVisuals()
                end

                return ChannelContent
            end

            table.insert(windowObj.Servers, ChannelHold)
            return ChannelHold
        end

        function windowObj:Category(name, icon)
            local iconAsset = ""
            if icon and Session.FarmLogo then
                iconAsset = Session.FarmLogo
            elseif name == "Home" and Session.BrandLogo then
                iconAsset = Session.BrandLogo
            elseif type(icon) == "string" then
                iconAsset = icon
            end
            return self:Server(name, iconAsset)
        end

        function windowObj:AddTab(category, name)
            return category:Channel(name)
        end

        function windowObj:SelectTab(index)
            local nextTab = self.Tabs[index]
            if not nextTab then return end
            for _, t in ipairs(self.Tabs) do
                t.Selected = false
            end
            nextTab.Selected = true
            self.CurrentTab = nextTab
            nextTab.Category.Last = nextTab
            if nextTab.Category.ActivateServer then nextTab.Category.ActivateServer() end
            if nextTab.ActivateChannel then nextTab.ActivateChannel() end
        end

        local notices = create("Frame", {
            Name = "DiscordNotices",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -14, 1, -14),
            Size = UDim2.new(0, 310, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            ZIndex = 50,
        }, gui)
        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
        }, notices)

        function UI.notify(titleText, message, duration)
            local toast = corner(create("Frame", {
                BackgroundColor3 = DiscordColors.Sidebar,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                ZIndex = 51,
            }, notices), 5)
            create("UIStroke", { Color = DiscordColors.Main, Thickness = 1 }, toast)
            corner(create("Frame", {
                BackgroundColor3 = DiscordColors.Blurple,
                BorderSizePixel = 0,
                Size = UDim2.new(0, 4, 1, 0),
                ZIndex = 52,
            }, toast), 5)
            local body = create("Frame", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 0),
                Size = UDim2.new(1, -20, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                ZIndex = 52,
            }, toast)
            create("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, body)
            create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, body)
            create("TextLabel", {
                BackgroundTransparency = 1,
                LayoutOrder = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                Font = Enum.Font.GothamSemibold,
                Text = tostring(titleText or "Notification"),
                TextColor3 = DiscordColors.Text,
                TextSize = 13,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 53,
            }, body)
            local msgText = tostring(message or "")
            if msgText ~= "" then
                create("TextLabel", {
                    BackgroundTransparency = 1,
                    LayoutOrder = 2,
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    Font = Enum.Font.Gotham,
                    Text = msgText,
                    TextColor3 = DiscordColors.SubText,
                    TextSize = 12,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 53,
                }, body)
            end
            local children = notices:GetChildren()
            if #children > 6 then
                for _, child in ipairs(children) do
                    if child:IsA("Frame") then child:Destroy() break end
                end
            end
            task.delay(duration or 3, function()
                if toast.Parent then toast:Destroy() end
            end)
        end

        function windowObj:Destroy()
            gui:Destroy()
        end

        return windowObj
    end

    UI.DiscordLib = DiscordLib
    UI.Window = DiscordLib:Window("N4TH v2.0 - Growtopia")
end)() end

local Window = UI.Window

-- If 1 element errors, other tabs still build
local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[n4th] UI error: " .. tostring(err)) end
end

-- Tab keys are used by inventory refresh and dropdown routing.
do
    local shortcuts = {}
    for _, group in ipairs({
        { Tabs = {
            { "Home", "Home" },
        } },
        { Title = "Farming", Tabs = {
            { "Farm", "Auto Farm", "Choose block and tiles to farm" },
            { "Farmer", "Plant & Harvest", "Choose seed to plant or harvest" },
            { "Clear World", "Break Blocks", "Break one block type or clear the world" },
            { "Auto Drop", "Auto Drop", "Drop full stacks to a chosen tile" },
            { "Dirt Farm", "Auto Dirt Farm" },
        } },
        { Title = "Production", Tabs = {
            { "Splice", "Splice" },
            { "Land", "Build Land" },
            { "Factory", "Auto Rotasi" },
            { "Vending", "Vending" },
        } },
        { Title = "Tools", Tabs = {
            { "World Finder", "World Finder" },
            { "Bag", "Inventory" },
            { "Growscan", "Info & Stats" },
            { "Bonus", "Bonus" },
            { "Auto Chat", "Auto Chat" },
        } },
        { Title = "Settings", Tabs = {
            { "Settings", "General", "Connect to the game and manage config" },
            { "Guard", "Guard" },
            { "Discord", "Discord" },
        } },
    }) do
        local category = Window:Category(group.Title or "Home", group.Title == "Farming")
        for _, spec in ipairs(group.Tabs) do
            local key, title, shortcut = table.unpack(spec)
            local tab = Window:AddTab(category, title)
            UI.Tabs[key] = tab
            if shortcut then shortcuts[#shortcuts + 1] = { tab, title, shortcut } end
        end
    end

    safe(function()
        local home = UI.Tabs.Home
        UI.HomeStatus = home:Paragraph({ Title = "Session status", Desc = "-" })
        for _, spec in ipairs(shortcuts) do
            local tab, title, desc = table.unpack(spec)
            home:Button({ Title = title, Desc = desc, Callback = function()
                Window:SelectTab(tab.Index)
            end })
        end
        Window:SelectTab(home.Index)
    end)
end
-- Collapsible sections inside tabs (keeps tabs uncluttered).
local function box(tab, title, opened)
    return tab:Section({ Title = title, Opened = opened == true })
end
local Box = {}

-- Numeric fields use Slider; fallback to input box if needed
local function addNumber(tab, o)
    local ok = pcall(function()
        tab:Slider({
            Title = o.Title,
            Desc = o.Desc,
            Step = o.Step or 1,
            Value = { Min = o.Min, Max = o.Max, Default = o.Default },
            Callback = function(v)
                v = tonumber(v)
                if v then o.Callback(v) end
            end,
        })
    end)
    if ok then return end
    safe(function()
        tab:Input({
            Title = o.Title,
            Desc = (o.Desc and (o.Desc .. " ") or "") .. "(" .. o.Min .. "-" .. o.Max .. ")",
            Value = tostring(o.Default),
            Placeholder = tostring(o.Default),
            Callback = function(text)
                local v = tonumber(text)
                if v then o.Callback(math.clamp(v, o.Min, o.Max)) end
            end,
        })
    end)
end

-- ===== TAB: FARM =====
local FarmTab = UI.Tabs["Farm"]

safe(function()
    UI.Status = FarmTab:Paragraph({ Title = "Status", Desc = "-" })
end)

do
    local controls = box(FarmTab, "Farm setup", true)
    local collect = box(FarmTab, "Collection method", false)
    local speed = box(FarmTab, "Speed & targets", false)

    safe(function()
        controls:Dropdown({
            Title = "Mode",
            Desc = "Choose the farming mode and mark tiles in the grid",
            Values = { "Place + Break", "Break only", "Place only" },
            Value = State.Mode,
            Callback = function(opt) State.Mode = opt end,
        })
    end)

    safe(function()
        UI.InvDropdown = controls:Dropdown({
            Title = "Select Block",
            Desc = "Only placeable items",
            Values = { "(loading...)" },
            Callback = function(opt)
                local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
                if id then
                    State.SelectedId = id
                    updateStatus()
                end
            end,
        })
    end)

    safe(function()
        controls:Button({
            Title = "Refresh list",
            Callback = function() UI.later("invForce", function() doInvRefresh(true) end) end,
        })
    end)

    safe(function()
        controls:Button({
            Title = "Open Tile Grid",
            Desc = "5x5 grid, center = character",
            Callback = function() UI.setGridMode("farm") UI.GridGui.Enabled = true end,
        })
    end)

    safe(function()
        controls:Toggle({
            Title = "Auto Collect",
            Desc = "Pick up drops on all grid tiles (method follows Collect mode)",
            Value = State.AutoCollect,
            Callback = function(on) State.AutoCollect = on end,
        })
    end)

    safe(function()
        UI.FarmToggle = controls:Toggle({
            Title = "Auto Farm",
            Desc = "Can also use the START button in the Grid",
            Value = false,
            Callback = function(on)
                if on then startFarm() elseif State.Running then stopFarm() end
            end,
        })
    end)

    safe(function()
        collect:Dropdown({
            Title = "Collect mode",
            Desc = "Applies to all features. Touch = like manual play. Remote = picks up from a distance (old method, fast)",
            Values = { "Touch", "Remote" },
            Value = State.CollectMode,
            Callback = function(v)
                if type(v) == "table" then v = v[1] end
                if v == "Touch" or v == "Remote" then State.CollectMode = v end
            end,
        })
    end)

    addNumber(collect, {
        Title = "Collect radius (Remote mode)",
        Desc = "Pickup distance around the character (tiles)",
        Min = 1, Max = 5, Step = 1, Default = State.CollectRadius,
        Callback = function(v) State.CollectRadius = math.floor(v) end,
    })

    addNumber(speed, {
        Title = "Speed Place (ms)",
        Desc = "Delay after each place",
        Min = 140, Max = 1000, Step = 10, Default = State.PlaceMs,
        Callback = function(v) State.PlaceMs = math.floor(v) end,
    })

    addNumber(speed, {
        Title = "Speed Break (ms)",
        Desc = "Delay per hit (normal 220). Also used by Clear",
        Min = 200, Max = 1000, Step = 10, Default = State.BreakMs,
        Callback = function(v) State.BreakMs = math.floor(v) end,
    })

    addNumber(speed, {
        Title = "Multi target break",
        Desc = "Auto Farm: tiles are hit in turns (like 2 fingers). With Rayman's Fist = 2-3 tiles in a line per punch",
        Min = 1, Max = 5, Step = 1, Default = State.MultiTarget,
        Callback = function(v) State.MultiTarget = math.clamp(math.floor(v), 1, 5) end,
    })

    addNumber(speed, {
        Title = "Delay after break (ms)",
        Desc = "Wait before moving to the next tile",
        Min = 0, Max = 1500, Step = 50, Default = State.AfterBreakMs,
        Callback = function(v) State.AfterBreakMs = math.floor(v) end,
    })
end

-- ===== AUTO BREAK BLOCK: block types from active world foreground =====
do (function()
    local controls = box(UI.Tabs["Clear World"], "Auto Break Block", true)
    local signature, lastWorld, lastGrid, lastName, lastWidth, lastHeight, refreshedAt
    safe(function() UI.WorldBreakStatus = controls:Paragraph({ Title = "Auto Break Status", Desc = "Select a block from the world, then enable Auto Break Block." }) end)
    safe(function()
        UI.WorldBreakItems = controls:Dropdown({
            Title = "Blocks in world",
            Desc = "Select one block type. x shows the count in the active world.",
            Values = { "(loading world blocks...)" },
            Callback = function(value)
                if UI.WorldBreakRefreshing then return end
                if type(value) == "table" then value = value[1] end
                local id = type(value) == "string" and tonumber(value:match("%[(%d+)%]$"))
                if not id then return end
                if Clear.Running and Clear.TargetId then
                    notify("Auto Break Block", "Stop Auto Break before switching targets", 3)
                    UI.later("worldBreakItems", function() UI.WorldBreakRefresh(true) end)
                    return
                end
                State.WorldBreakId = id
                if Session.Ready then Config.save(true) end
            end,
        })
    end)
    function UI.WorldBreakRefresh(force)
        local w = Refs.World
        local grid, name = w and w.fg, w and w.name
        local width, height = w and w.w, w and w.h
        local sameWorld = w == lastWorld and grid == lastGrid and name == lastName and width == lastWidth and height == lastHeight
        -- Do not scan world on hidden tabs or while break target is locked.
        if not force and signature and sameWorld then
            if Clear.Running or not UI.tabVisible("Clear World") or os.clock() - (refreshedAt or 0) < 8 then return end
        end
        local ids, counts = Auto.worldBreakOptions(true)
        if Refs.World ~= w or (w and w.fg ~= grid) then return end
        lastWorld, lastGrid, lastName, lastWidth, lastHeight, refreshedAt = w, grid, name, width, height, os.clock()
        local labels = {}
        for _, id in ipairs(ids) do labels[#labels + 1] = ("%s x%d [%d]"):format(itemName(id), counts[id], id) end
        if #labels == 0 then labels = { "(no breakable blocks found in this world yet)" } end
        local current = tostring(Refs.World) .. ":" .. tostring(Refs.World and Refs.World.name) .. ":" .. table.concat(labels, "|")
        if not force and current == signature then return end
        local ok, err = UI.exec(function()
            UI.WorldBreakRefreshing = true
            local refreshed, message = pcall(function()
                UI.WorldBreakItems:Refresh(labels)
                selectSaved(UI.WorldBreakItems, labels, State.WorldBreakId)
            end)
            UI.WorldBreakRefreshing = false
            if not refreshed then error(message, 0) end
        end)
        if ok then signature = current else warn("[n4th] World block list: " .. tostring(err)) end
    end
    safe(function()
        controls:Button({ Title = "Refresh world blocks", Desc = "Re-scan block types and counts from the active world.",
            Callback = function() UI.later("worldBreakItems", function() UI.WorldBreakRefresh(true) end) end })
    end)
    safe(function()
        UI.WorldBreakCollect = controls:Toggle({
            Title = "Auto collect drops",
            Desc = "Auto Break Block only. Off stops chasing drops; the game can still collect items you touch.",
            Value = State.WorldBreakCollect,
            Callback = function(on)
                State.WorldBreakCollect = on
                Drops.seen = nil
                if Session.Ready then Config.save(true) end
            end,
        })
    end)
    safe(function()
        UI.WorldBreakToggle = controls:Toggle({
            Title = "Auto Break Block",
            Desc = "Walks to the selected block and breaks only that type. Unreachable targets are skipped.",
            Value = false,
            Callback = function(on)
                if UI.ClearVisualSync then return end
                if on then Auto.startWorldBreak()
                elseif Clear.Running and Clear.TargetId then stopClear("Stopped: Auto Break Block") end
            end,
        })
    end)
    task.spawn(function()
        while alive() do
            UI.later("worldBreakItems", function() UI.WorldBreakRefresh(false) end)
            task.wait(3)
        end
    end)
end)() end

-- ===== TAB: AUTO DROP =====
do (function()
    local tab = UI.Tabs["Auto Drop"]
    safe(function() UI.AutoDropStatus = tab:Paragraph({ Title = "Status", Desc = "-" }) end)
    local itemBox = box(tab, "Pick items", true)
    local pointBox = box(tab, "Set drop point", true)
    local controls = box(tab, "Start Auto Drop", true)

    safe(function()
        UI.AutoDropToggle = controls:Toggle({
            Title = "Auto Drop",
            Desc = "At 200, selected items are taken to the drop tile. Then return and resume farming.",
            Value = false,
            Callback = function(on)
                if on then
                    local reason = #AutoDrop.Items == 0 and "Select an item first" or AutoDrop.targetError()
                    if reason then
                        AutoDrop.On = false
                        notify("Auto Drop", reason, 4)
                        UI.later("autoDropOff", function() UI.AutoDropToggle:Set(false) end)
                        return
                    end
                end
                AutoDrop.On = on
                AutoDrop.NextTry = 0
                AutoDrop.Status = on and "Waiting for an item to reach 200" or "Off"
            end,
        })
    end)

    safe(function()
        local labels, picked = AutoDrop.labels()
        UI.AutoDropItems = itemBox:Dropdown({
            Title = "Items to drop",
            Desc = "Select inventory items. Each selected item drops a full stack of 200 when full.",
            Values = #labels > 0 and labels or { "(inventory empty / not read yet)" },
            Value = picked,
            Multi = true,
            AllowNone = true,
            Callback = function(options)
                if UI.AutoDropRefreshing then return end
                if AutoDrop.Busy then
                    notify("Auto Drop", "Wait for the drop trip to finish", 3)
                    UI.later("autoDropItems", function() UI.AutoDropRefresh(true) end)
                    return
                end
                local items, seen = {}, {}
                for _, label in ipairs(type(options) == "table" and options or { options }) do
                    local id = tonumber(tostring(label):match("%[(%d+)%]$"))
                    if id and not seen[id] then items[#items + 1], seen[id] = id, true end
                end
                AutoDrop.Items = items
                if Session.Ready then Config.save(true) end
            end,
        })
    end)

    local lastSig
    UI.AutoDropRefresh = function(force)
        if not UI.AutoDropItems then return end
        if not force and not UI.tabVisible("Auto Drop") then return end
        local labels, picked = AutoDrop.labels()
        local signature = table.concat(labels, "|") .. "/" .. table.concat(picked, "|")
        if not force and signature == lastSig then return end
        local ok = UI.exec(function()
            UI.AutoDropRefreshing = true
            local refreshed, refreshError = pcall(function()
                UI.AutoDropItems:Refresh(#labels > 0 and labels or { "(inventory empty / not read yet)" })
                UI.AutoDropItems:Select(#picked > 0 and picked or nil)
            end)
            UI.AutoDropRefreshing = false
            if not refreshed then error(refreshError, 0) end
        end)
        if ok then lastSig = signature end
    end
    safe(function()
        itemBox:Button({
            Title = "Refresh item list",
            Callback = function() UI.later("autoDropItems", function() UI.AutoDropRefresh(true) end) end,
        })
    end)
    safe(function()
        pointBox:Button({
            Title = "Select drop tile",
            Desc = "Choose one tile on the 5x5 grid. It is saved as the standing position in this world.",
            Callback = function()
                if UI.setGridMode("autodrop") then UI.GridGui.Enabled = true end
            end,
        })
    end)
    safe(function()
        pointBox:Button({
            Title = "Use current standing tile",
            Callback = function()
                local x, y = Auto.here()
                if not x then notify("Auto Drop", "You are not in a world yet", 3) return end
                local ok, message = AutoDrop.setPoint(x, y, Guard.worldName())
                notify("Auto Drop", ok and ("Tile (%d,%d) saved"):format(x, y) or message, 4)
            end,
        })
    end)
    safe(function()
        UI.AutoDropFacing = pointBox:Dropdown({
            Title = "Drop direction",
            Desc = "The preferred direction is used when the way back is safe. The direction can reverse automatically.",
            Values = { "Right", "Left" },
            Value = AutoDrop.Facing < 0 and "Left" or "Right",
            Callback = function(option)
                if type(option) == "table" then option = option[1] end
                if AutoDrop.Busy then
                    UI.later("autoDropFacing", function()
                        UI.AutoDropFacing:Select(AutoDrop.Facing < 0 and "Left" or "Right")
                    end)
                    return
                end
                AutoDrop.Facing = option == "Left" and -1 or 1
                if Session.Ready then Config.save(true) end
            end,
        })
    end)

    task.spawn(function()
        while alive() do
            local point = AutoDrop.X >= 0 and ("%s (%d,%d)"):format(AutoDrop.World, AutoDrop.X, AutoDrop.Y) or "-"
            local counts = {}
            for _, id in ipairs(AutoDrop.Items) do counts[#counts + 1] = itemName(id) .. " " .. invCount(id) .. "/200" end
            local text = table.concat({
                AutoDrop.Status, point,
                table.concat(counts, " | "), ("Dropped: %d"):format(AutoDrop.Dropped),
            }, "\n")
            if UI.AutoDropStatus and text ~= AutoDrop.Shown then
                AutoDrop.Shown = text
                UI.later("autoDropStatus", function() UI.AutoDropStatus:SetDesc(text) end)
            end
            task.wait(0.5)
        end
    end)
end)() end

-- ===== TAB: CLEAR WORLD =====
local ClearTab = UI.Tabs["Clear World"]

Box.ClearCtl = box(ClearTab, "Clear the world", false)
Box.ClearSet = box(ClearTab, "World clear options", false)

safe(function()
    UI.ClearStatus = Box.ClearCtl:Paragraph({ Title = "Clear Status", Desc = "-" })
end)

safe(function()
    UI.ClearToggle = Box.ClearCtl:Toggle({
        Title = "Auto Clear World",
        Desc = "Clear from the top row down",
        Value = false,
        Callback = function(on)
            if UI.ClearVisualSync then return end
            if on then Auto.startClear() elseif Clear.Running and not Clear.TargetId then stopClear() end
        end,
    })
end)

safe(function()
    Box.ClearSet:Dropdown({
        Title = "Sweep direction",
        Desc = "Zig-zag is faster (no going back left)",
        Values = { "Left -> Right", "Zig-zag" },
        Value = Clear.Sweep,
        Callback = function(opt) Clear.Sweep = opt end,
    })
end)

safe(function()
    Box.ClearSet:Toggle({
        Title = "Use scaffold blocks",
        Desc = "Place blocks to cross gaps / reach floating blocks",
        Value = Clear.UseBlock,
        Callback = function(on)
            Clear.UseBlock = on
            Auto.resetReach()
        end,
    })
end)

safe(function()
    UI.ClearBlockDropdown = Box.ClearSet:Dropdown({
        Title = "Scaffold block",
        Desc = "Block used as scaffold",
        Values = { "(loading...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                Clear.ScaffoldId = id
                Auto.resetReach()
            end
        end,
    })
end)

safe(function()
    Box.ClearSet:Toggle({
        Title = "Auto collect after each break",
        Desc = "Nearby drops are walked over until the body touches them (no remote)",
        Value = Clear.Collect,
        Callback = function(on) Clear.Collect = on end,
    })
end)

safe(function()
    Box.ClearCtl:Button({
        Title = "Reset skipped tiles",
        Desc = "Retry tiles that failed",
        Callback = function()
            table.clear(Clear.Skip)
            table.clear(Auto.BadEdge)
            table.clear(Auto.ClearFail)
            Auto.updateClearStatus()
        end,
    })
end)

-- ===== TAB: FARMER =====
local FarmerTab = UI.Tabs["Farmer"]

safe(function()
    UI.FarmerStatus = FarmerTab:Paragraph({ Title = "Farmer Status", Desc = "-" })
end)

Box.FarmerSeed = box(FarmerTab, "Seed", true)
Box.FarmerCtl = box(FarmerTab, "Start planting & harvesting", true)
Box.FarmerSpeed = box(FarmerTab, "Speed", false)
Box.FarmerBlock = box(FarmerTab, "Scaffold block", false)

safe(function()
    UI.SeedDropdown = Box.FarmerSeed:Dropdown({
        Title = "Seed to plant",
        Desc = "Only seeds in your inventory",
        Values = { "(loading...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                Farmer.SeedId = id
                table.clear(Farmer.Skip)
                Auto.updateFarmerStatus()
            end
        end,
    })
end)

safe(function()
    Box.FarmerSeed:Button({
        Title = "Refresh seed list",
        Callback = function() UI.later("invForce", function() doInvRefresh(true) end) end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Harvest",
        Desc = "Only trees that are ready",
        Value = Farmer.Harvest,
        Callback = function(on) Farmer.Harvest = on end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Plant",
        Desc = "Plant on top of empty blocks",
        Value = Farmer.Plant,
        Callback = function(on) Farmer.Plant = on end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Collect",
        Desc = "Pick up harvest drops around the character",
        Value = Farmer.Collect,
        Callback = function(on) Farmer.Collect = on end,
    })
end)

safe(function()
    UI.FarmerToggle = Box.FarmerCtl:Toggle({
        Title = "Run Farmer",
        Desc = "Harvest ready trees & plant seeds automatically",
        Value = false,
        Callback = function(on)
            if on then Auto.startFarmer() elseif Farmer.Running then stopFarmer() end
        end,
    })
end)

addNumber(Box.FarmerSpeed, {
    Title = "Speed Harvest (ms)",
    Desc = "Delay after each harvest",
    Min = 140, Max = 2000, Step = 10, Default = Farmer.HarvestMs,
    Callback = function(v) Farmer.HarvestMs = math.floor(v) end,
})

addNumber(Box.FarmerSpeed, {
    Title = "Speed Plant (ms)",
    Desc = "Delay after each seed planted",
    Min = 140, Max = 2000, Step = 10, Default = Farmer.PlantMs,
    Callback = function(v) Farmer.PlantMs = math.floor(v) end,
})

safe(function()
    Box.FarmerBlock:Toggle({
        Title = "Use scaffold blocks",
        Desc = "Place blocks when there is no path (blocks stay behind)",
        Value = Farmer.UseBlock,
        Callback = function(on)
            Farmer.UseBlock = on
            Auto.resetReach()
        end,
    })
end)

safe(function()
    UI.FarmerBlockDropdown = Box.FarmerBlock:Dropdown({
        Title = "Scaffold block",
        Desc = "Block used as scaffold",
        Values = { "(loading...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                Farmer.ScaffoldId = id
                Auto.resetReach()
            end
        end,
    })
end)

-- ===== TAB: AUTO CHAT =====
local ChatTab = UI.Tabs["Auto Chat"]

safe(function()
    UI.SpamStatus = ChatTab:Paragraph({ Title = "Chat Status", Desc = "-" })
end)

Box.ChatCtl = box(ChatTab, "Controls", true)
Box.ChatMsg = box(ChatTab, "Messages", true)

safe(function()
    Box.ChatMsg:Input({
        Title = "Message list",
        Desc = "Separate with |   example: hi|selling dirt",
        Value = table.concat(Spam.Texts, "|"),
        Placeholder = "message 1|message 2|message 3",
        Callback = function(text)
            Spam.Texts = parseSpamTexts(text)
            Spam.Index = 1
            updateSpamStatus()
        end,
    })
end)

addNumber(Box.ChatMsg, {
    Title = "Interval (seconds)",
    Desc = "Delay between messages (min 3 seconds)",
    Min = 3, Max = 120, Step = 1, Default = Spam.IntervalSec,
    Callback = function(v) Spam.IntervalSec = math.max(3, math.floor(v)) end,
})

safe(function()
    UI.SpamToggle = Box.ChatCtl:Toggle({
        Title = "Auto Chat",
        Desc = "Send messages in order, one after another",
        Value = false,
        Callback = function(on)
            Spam.On = on
            if on then
                if #Spam.Texts == 0 then notify("Auto Chat", "Fill in the message list first (press Enter after typing)", 4) end
                Spam.NextAt = 0 -- immediately send first message
            end
            updateSpamStatus()
        end,
    })
end)

safe(function()
    Box.ChatCtl:Button({
        Title = "Send 1 message now",
        Desc = "Test sending the next message",
        Callback = function()
            task.spawn(function()
                sendNextChat()
                updateSpamStatus()
            end)
        end,
    })
end)

---------------------------------------------------------------------
-- GUARD: detect Mod / Dev / players entering world
---------------------------------------------------------------------
-- How it works:
--   1. Every 0.5s check world player list (game "Others" data).
--   2. Check roles via game Roles module (Developer / Moderator, undercover also detected).
--   3. Target found -> pause all activities, optionally leave world immediately.
--   4. Once safe -> resume prior activity.
--      Leave mode: wait X seconds, re-enter world, re-check.
--      Still present -> leave again. Clear -> resume (Auto Farm walks back to start tile).

do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local function strip(s) return (tostring(s or ""):gsub("`.", "")) end

    local function roleOf(uid)
        if not (RolesOk and type(RolesModule) == "table") then return nil end
        local okD, dev = pcall(RolesModule.isDeveloper, uid)
        if okD and dev then return "Developer" end
        local okM, mod = pcall(RolesModule.isModerator, uid)
        if okM and mod then return "Moderator" end
        return nil
    end

    local function worldName()
        local n = Refs.World and rawget(Refs.World, "name")
        return type(n) == "string" and n or ""
    end

    -- Other players in this world: { id, name, role }
    local function playersHere()
        local out = {}
        local o = Refs.Others
        if not o or type(rawget(o, "list")) ~= "function" then return out end
        local ok, list = pcall(o.list)
        if not ok or type(list) ~= "table" then return out end
        for _, e in ipairs(list) do
            local uid = type(e) == "table" and tonumber(e[1] or e.userId)
            if uid and uid ~= LocalPlayer.UserId then
                out[#out + 1] = { id = uid, name = strip(e[2] or e.name or uid), role = roleOf(uid) }
            end
        end
        return out
    end
    Guard.playersHere = playersHere

    local function threatsOf(list)
        local out = {}
        for _, p in ipairs(list) do
            if p.role or (Guard.Who == "All players" and not Guard.Allow[p.id]) then
                out[#out + 1] = p
            end
        end
        return out
    end

    local function label(p)
        local under = false
        if p.role and type(RolesModule.isUndercover) == "function" then
            local ok, u = pcall(RolesModule.isUndercover, p.id)
            under = ok and u == true
        end
        return p.name .. " (" .. (p.role or "Player") .. (under and ", undercover" or "") .. ")"
    end

    local function names(list, max)
        local t = {}
        for i, p in ipairs(list) do
            if i > (max or 4) then
                t[#t + 1] = "+" .. (#list - i + 1) .. " more"
                break
            end
            t[#t + 1] = label(p)
        end
        return table.concat(t, ", ")
    end

    local function anyRunning()
        return State.Running or Clear.Running or Farmer.Running or Splice.Running or Spam.On
            or Factory.Running or Build.Running or Vend.Running or AutoDrop.On or AutoDrop.Busy or WorldFinder.Busy
    end

    -- Snapshot running activities (to resume later)
    local function snapshot()
        if WorldFinder.Busy and WorldFinder.Saved then return WorldFinder.Saved end
        if AutoDrop.Busy and AutoDrop.Saved then return AutoDrop.Saved end
        local tx, ty = Auto.here()
        return {
            farm = State.Running and not State.Override, clear = Clear.Running, farmer = Farmer.Running,
            clearTarget = Clear.TargetId,
            spam = Spam.On, splice = Splice.Running, factory = Factory.Running, build = Build.Running and (Build.DirtRun and "dirt" or true) or false, vend = Vend.Running,
            world = worldName(), tx = tx, ty = ty,
        }
    end

    local function stopAll(forAutoDrop, forFinder)
        if WorldFinder.Busy and not forFinder then
            WorldFinder.Cancelled, WorldFinder.Running = true, false
            if WorldFinder.checkpoint then WorldFinder.checkpoint(false) end
        end
        if AutoDrop.Busy and not forAutoDrop then AutoDrop.Cancelled = true end
        Auto.stopWalk()
        if Factory.Running then Factory.stop() end
        if Build.Running then Build.stop() end
        if State.Running then stopFarm() end
        if Clear.Running then
            stopClear()
            Clear.Status = "Paused by Guard"
        end
        if Farmer.Running then
            stopFarmer()
            Farmer.Status = "Paused by Guard"
        end
        if Splice.Running and Splice.stop then Splice.stop() end
        if Vend.Running and Vend.stop then Vend.stop() end
        if Spam.On then
            Spam.On = false
            if UI.SpamToggle then pcall(function() UI.SpamToggle:Set(false) end) end
        end
        Auto.releaseInput()
    end

    -- Leave world = same as game "Exit World" button
    local function leaveWorld()
        local m = Refs.Menu
        if m and type(rawget(m, "openPicker")) == "function" and pcall(m.openPicker) then
            return true
        end
        local w = Refs.World
        if w and type(rawget(w, "call")) == "function" then
            return (pcall(w.call, "LeaveWorld"))
        end
        return false
    end

    -- Enter world via game menu (same as typing world name and pressing Enter)
    local function enterWorld(name)
        local w = Refs.World
        if not w or name == "" then return false, "unknown world name" end
        local oldFg = rawget(w, "fg")
        local oldName = worldName()
        local seenDifferent = oldName:upper() ~= name:upper()
        local m = Refs.Menu
        if m and type(rawget(m, "enter")) == "function" then
            local ok, res, msg, hopping = pcall(m.enter, name)
            if not ok then return false, strip(res) end
            if hopping == true then return false, strip(msg), true end
            if res == false then return false, strip(msg) end
        elseif type(rawget(w, "enter")) == "function" then
            local ok, res, msg, hopping = pcall(w.enter, name)
            if not ok then return false, strip(res) end
            -- Game v1225: false, msg, true means server is currently transferring the player.
            if hopping == true then return false, strip(msg), true end
            if not res then return false, strip(msg) end
        else
            return false, "enter world function not found"
        end
        -- succeeds once world data switches to the new world (table swap or in-place reload)
        local t0 = os.clock()
        while alive() and os.clock() - t0 < 10 do
            if WorldFinder.Busy and WorldFinder.Teleporting then return false, "Server transfer", true end
            local curW = Refs.World
            local curName = worldName()
            if curName == "" or curName:upper() ~= name:upper() then seenDifferent = true end
            if curW and (rawget(curW, "fg") ~= oldFg or (seenDifferent and curName:upper() == name:upper() and Auto.here() ~= nil)) then
                return true
            end
            task.wait(0.25)
        end
        return false, "world full / locked / failed"
    end

    local function stillBack(token)
        return alive() and Guard.Token == token and Guard.Mode == "back"
    end

    -- Resume previously paused activities
    local function resumeAll(saved, token, live)
        if not saved then return end
        local function active()
            if live then return live() end
            return stillBack(token)
        end
        if saved.world ~= "" and worldName() ~= saved.world then
            notify("Guard", "World changed, activity will not resume", 5)
            return
        end
        if saved.spam and not Spam.On and active() then
            if UI.SpamToggle then pcall(function() UI.SpamToggle:Set(true) end) end
            Spam.On = true
        end
        if saved.build then
            if active() then Build.start(saved.build == "dirt") end
        elseif saved.factory or saved.pabrik then
            if active() then Factory.start() end
        elseif saved.vend then
            if active() then Vend.start() end
        elseif saved.farm then
            -- Auto Farm uses tiles around character, so must walk back to starting position
            local hx, hy = Auto.here()
            if saved.tx and (hx ~= saved.tx or hy ~= saved.ty) then
                Guard.BackText = ("Walking back to farm position (%d,%d)"):format(saved.tx, saved.ty)
                local ok = Auto.walkTo(saved.tx, saved.ty, 45)
                if not ok and active() then ok = Auto.walkTo(saved.tx, saved.ty, 30) end
                if not ok then
                    if active() then
                        notify("Guard", "Failed to return to farm position. Auto Farm will not resume", 6)
                    end
                    return
                end
            end
            if active() then startFarm() end
        elseif saved.clear then
            if active() then Auto.startClear(saved.clearTarget) end
        elseif saved.farmer then
            if active() then Auto.startFarmer() end
        elseif saved.splice then
            if active() and Splice.start then Splice.start() end
        end
    end

    local function beginResume()
        local saved = Guard.Saved
        Guard.Token += 1
        local token = Guard.Token
        Guard.Mode = "back"
        Guard.BackText = nil
        task.spawn(function()
            local ok, err = pcall(resumeAll, saved, token)
            if not ok then warn("[n4th] Guard resume error: " .. tostring(err)) end
            if Guard.Token == token and Guard.Mode == "back" then
                Guard.Mode, Guard.Saved, Guard.BackText = "idle", nil, nil
            end
        end)
    end

    local function goAway()
        if not leaveWorld() then
            notify("Guard", "Failed to leave world, activity paused only", 5)
            Guard.Mode = "pause"
            return
        end
        task.wait(0.3)
        Guard.LeftFg = Refs.World and rawget(Refs.World, "fg")
        Guard.BackAt = os.clock() + Guard.BackSec
        Guard.Mode = Guard.AutoBack and "away" or "out"
        Guard.Status = "Leave world"
    end

    -- New watched player entered world
    local function trigger(fresh)
        Guard.Detected += #fresh
        notify("Guard", "Entered world: " .. names(fresh), 6)
        Hook.send("guard", "Entered world " .. worldName() .. ": " .. names(fresh))
        if not Guard.StopAll and not Guard.Leave then return end -- alert only
        -- save activity (if currently walking back, keep previous snapshot)
        if Guard.Mode ~= "back" and (anyRunning() or not Guard.Saved) then
            Guard.Saved = snapshot()
        end
        Guard.Token += 1
        stopAll()
        Guard.CalmAt = nil
        if Guard.Leave then
            goAway()
            if Guard.Mode == "away" then
                notify("Guard", "Left world. Re-entering in " .. Guard.BackSec .. " seconds", 5)
                Hook.send("guard", "Left world, re-entering in " .. Guard.BackSec .. " seconds")
            elseif Guard.Mode == "out" then
                notify("Guard", "Leave world", 4)
            end
        else
            Guard.Mode = "pause"
        end
    end

    -- After re-entering world: check first if target is still here
    local function checkAfterEnter()
        Auto.resetReach()
        pcall(findDropRefs)
        pcall(Auto.findTreeRefs)
        table.clear(DropFailUntil)
        task.wait(1.5) -- wait for player list to populate
        local th = threatsOf(playersHere())
        if #th > 0 then
            for _, p in ipairs(th) do Guard.Alerted[p.id] = true end
            notify("Guard", "Still here: " .. names(th) .. ". Leaving again", 5)
            goAway()
            return
        end
        notify("Guard", "World is safe, resuming activity", 4)
        Hook.send("guard", "World " .. worldName() .. " safe, resuming activity")
        beginResume()
    end

    -- Staff online across the server (not just this world)
    local lastScan, staffText = -10, "-"
    local function serverStaff()
        if os.clock() - lastScan < 3 then return staffText end
        lastScan = os.clock()
        local t = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local r = roleOf(plr.UserId)
                if r then t[#t + 1] = (plr.DisplayName or plr.Name) .. " (" .. r .. ")" end
            end
        end
        staffText = (#t > 0) and table.concat(t, ", ") or "none"
        return staffText
    end

    function Guard.tick(here)
        if not Guard.On then
            Guard.Status = "Off"
            return
        end
        local now = os.clock()
        local mode = Guard.Mode

        -- ===== currently outside world =====
        if mode == "away" or mode == "out" then
            local fgNow = Refs.World and rawget(Refs.World, "fg")
            if Guard.LeftFg and fgNow ~= Guard.LeftFg then
                -- already re-entered world manually
                if mode == "away" and Guard.Saved and worldName() == Guard.Saved.world then
                    checkAfterEnter()
                else
                    Guard.Mode, Guard.Saved = "idle", nil
                end
                return
            end
            local name = Guard.Saved and Guard.Saved.world or ""
            if mode == "out" or name == "" then
                Guard.Status = "Left world (auto resume is off)"
                return
            end
            local left = Guard.BackAt - now
            if left > 0 then
                Guard.Status = ("Outside world. Re-entering %s in %d seconds"):format(name, math.ceil(left))
                return
            end
            Guard.Status = "Re-entering " .. name .. "..."
            Guard.updateStatus({})
            local ok, err = enterWorld(name)
            if not ok then
                Guard.BackAt = os.clock() + math.max(15, Guard.BackSec)
                notify("Guard", "Failed to enter " .. name .. ": " .. tostring(err) .. ". Will retry later", 5)
                return
            end
            checkAfterEnter()
            return
        end

        -- ===== inside world =====
        local present = {}
        for _, p in ipairs(here) do present[p.id] = true end
        for id in pairs(Guard.Alerted) do
            if not present[id] then Guard.Alerted[id] = nil end -- left
        end
        local threats = threatsOf(here)
        local fresh = {}
        for _, p in ipairs(threats) do
            if not Guard.Alerted[p.id] then
                Guard.Alerted[p.id] = true
                fresh[#fresh + 1] = p
            end
        end
        if #fresh > 0 then
            trigger(fresh)
            if Guard.Mode == "away" or Guard.Mode == "out" then return end
        end

        if #threats > 0 then
            Guard.CalmAt = nil
            Guard.Status = (Guard.Mode == "pause" and "Paused. Detected: " or "Alert. Detected: ") .. names(threats)
            return
        end

        if Guard.Mode == "pause" then
            Guard.CalmAt = Guard.CalmAt or now
            local wait = Guard.CalmSec - (now - Guard.CalmAt)
            if wait > 0 then
                Guard.Status = ("They left. Resuming in %d seconds"):format(math.ceil(wait))
                return
            end
            Guard.CalmAt = nil
            if Guard.AutoBack and Guard.Saved then
                notify("Guard", "Safe now, resuming activity", 4)
                beginResume()
            else
                Guard.Mode, Guard.Saved = "idle", nil
            end
            return
        end

        if Guard.Mode == "back" then
            Guard.Status = Guard.BackText or "Resuming activity..."
            return
        end
        Guard.Status = "Safe"
    end

    function Guard.updateStatus(here)
        local txt = table.concat({
            "Status: " .. Guard.Status .. (Refs.Others and "" or " (player data not found: press 'Connect to game')"),
            "Players in world: " .. ((#here == 0) and "none" or names(here, 6)),
            "Staff online on server: " .. serverStaff(),
            "Detected: " .. Guard.Detected .. " times",
        }, "\n")
        if txt ~= Guard.LastTxt then
            Guard.LastTxt = txt
            if UI.GuardStatus then pcall(function() UI.GuardStatus:SetDesc(txt) end) end
        end
    end

    -- Enable / disable Guard
    function Guard.set(on)
        Guard.On = on
        Guard.Token += 1
        Auto.stopWalk()
        Guard.Mode, Guard.Saved, Guard.CalmAt, Guard.BackText = "idle", nil, nil, nil
        table.clear(Guard.Alerted)
        table.clear(Guard.Allow)
        if on then
            -- regular players already present are ignored (friends / alts)
            for _, p in ipairs(playersHere()) do
                if not p.role then Guard.Allow[p.id] = true end
            end
        end
    end

    -- used by other features (Auto Reconnect)
    Guard.snapshot = snapshot
    Guard.resumeActivities = function(saved, live) return resumeAll(saved, nil, live) end
    Guard.stopAll = stopAll
    Guard.enterWorld = enterWorld
    Guard.leaveWorld = leaveWorld
    Guard.worldName = worldName
    Guard.anyRunning = anyRunning
    function Guard.afterEnter()
        Auto.resetReach()
        pcall(Session.bindMovement, true)
        pcall(findDropRefs)
        pcall(Auto.findTreeRefs)
        table.clear(DropFailUntil)
    end
    function Guard.resumeSaved(saved)
        Guard.Saved = saved
        beginResume()
    end

    function Guard.allowNow()
        local n = 0
        for _, p in ipairs(playersHere()) do
            if not p.role then
                Guard.Allow[p.id] = true
                n += 1
            end
        end
        return n
    end

    task.spawn(function()
        while alive() do
            local here = (Guard.Mode ~= "away" and Guard.Mode ~= "out") and playersHere() or {}
            local ok, err = pcall(Guard.tick, here)
            if not ok then warn("[n4th] Guard error: " .. tostring(err)) end
            Guard.updateStatus(here)
            task.wait(0.5)
        end
    end)
end)() end

Config.add("Guard", Guard, { "On", "Who", "StopAll", "Leave", "AutoBack", "BackSec", "CalmSec" }, { On = true })

-- ===== TAB: GUARD =====
do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local GuardTab = UI.Tabs["Guard"]

    safe(function()
        UI.GuardStatus = GuardTab:Paragraph({ Title = "Guard Status", Desc = "Off" })
    end)

    local gCtl = box(GuardTab, "Controls", true)
    local gAct = box(GuardTab, "Action when detected", true)
    local gTime = box(GuardTab, "Timing", false)
    local gMore = box(GuardTab, "Other", false)

    safe(function()
        UI.GuardToggle = gCtl:Toggle({
            Title = "Enable Guard",
            Desc = "Watch for Mods / Devs / players entering the world",
            Value = false,
            Callback = function(on) Guard.set(on) end,
        })
    end)

    safe(function()
        gCtl:Dropdown({
            Title = "Detect",
            Desc = "All players: those already here when enabled are ignored",
            Values = { "Staff (Mod/Dev)", "All players" },
            Value = Guard.Who,
            Callback = function(opt) Guard.Who = opt end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Pause all activities",
            Desc = "Stop Auto Farm, Clear, Farmer & Auto Chat",
            Value = Guard.StopAll,
            Callback = function(on) Guard.StopAll = on end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Leave world",
            Desc = "Leave the world immediately when detected",
            Value = Guard.Leave,
            Callback = function(on) Guard.Leave = on end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Auto resume when safe",
            Desc = "Leave world: rejoin, check, then resume previous activity",
            Value = Guard.AutoBack,
            Callback = function(on) Guard.AutoBack = on end,
        })
    end)

    addNumber(gTime, {
        Title = "Rejoin world after (seconds)",
        Desc = "For leave-world mode",
        Min = 20, Max = 600, Step = 5, Default = Guard.BackSec,
        Callback = function(v) Guard.BackSec = math.floor(v) end,
    })

    addNumber(gTime, {
        Title = "Safe wait (seconds)",
        Desc = "For pause mode: delay after they leave",
        Min = 2, Max = 60, Step = 1, Default = Guard.CalmSec,
        Callback = function(v) Guard.CalmSec = math.floor(v) end,
    })

    safe(function()
        gMore:Button({
            Title = "Ignore players here now",
            Desc = "For friends / alt accounts (staff are still detected)",
            Callback = function()
                notify("Guard", Guard.allowNow() .. " players ignored", 3)
            end,
        })
    end)

    safe(function()
        gMore:Button({
            Title = "Cancel wait / resume",
            Desc = "Stop the leave-rejoin process & auto resume",
            Callback = function()
                Guard.set(Guard.On)
                notify("Guard", "Cancelled", 3)
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- BONUS: auto claim quests & auto redeem codes
---------------------------------------------------------------------
-- Uses the same calls as the in-game Quest & Redeem menus:
--   Net.call("Quests", "list")            -> today's quest list
--   Net.call("Quests", "claim", id)       -> claim reward (server verifies requirements)
--   Net.call("ActiveCodes")               -> active codes list
--   Net.call("ModCommand", "redeemcode", code) -> redeem code (used by in-game Redeem menu)
local Bonus = {
    Quest = false,
    Redeem = false,
    QuestEvery = 30,   -- check quests every 30 seconds
    CodeEvery = 300,   -- check codes every 5 minutes
    NextQuest = 0,
    NextCode = 0,
    Claimed = 0,
    Redeemed = 0,
    Tried = {},        -- codes already attempted
    QuestFail = {},    -- quests rejected by server (retried later)
    QuestText = "-",
    CodeText = "-",
    ResetAt = nil,
}

do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local function strip(s) return (tostring(s or ""):gsub("`.", "")) end

    local function netCall(...)
        if NetOk and type(Net) == "table" and type(Net.call) == "function" then
            return pcall(Net.call, ...)
        end
        return false, "Net.call unavailable"
    end

    local function timeText(sec)
        sec = math.max(0, math.floor(sec or 0))
        if sec >= 3600 then return ("%dh %dm"):format(sec // 3600, sec % 3600 // 60) end
        return ("%dm %ds"):format(sec // 60, sec % 60)
    end

    local function setGems(n)
        local g = Refs.Gems
        if type(n) == "number" and g and type(rawget(g, "setGems")) == "function" then
            pcall(g.setGems, n)
        end
    end

    function Bonus.checkQuests()
        if Bonus.BusyQ then return end
        Bonus.BusyQ = true
        local ok, good, data = netCall("Quests", "list")
        if not ok then
            Bonus.QuestText = "Failed to fetch quests: " .. strip(good)
        elseif not good or type(data) ~= "table" or type(data.quests) ~= "table" then
            Bonus.QuestText = "Quest not ready to claim" .. (type(data) == "string" and (": " .. strip(data)) or "")
        else
            local total, done, wait = 0, 0, 0
            local now = os.clock()
            for _, q in ipairs(data.quests) do
                total += 1
                local have, need = tonumber(q.have) or 0, tonumber(q.need) or math.huge
                if q.claimed then
                    done += 1
                elseif have >= need and not ((Bonus.QuestFail[q.id] or 0) > now) then
                    -- same check as in-game Claim button
                    local okc, success, msg, _, gems = netCall("Quests", "claim", q.id)
                    if okc and success then
                        done += 1
                        Bonus.Claimed += 1
                        local reward = q.xp and (tostring(q.reward) .. " XP") or (tostring(q.reward) .. " gems")
                        notify("Quest claimed", strip(q.text or q.id) .. "  +" .. reward, 4)
                        Hook.send("bonus", "Quest claimed: " .. strip(q.text or q.id) .. " +" .. reward)
                        setGems(gems)
                    else
                        wait += 1
                        Bonus.QuestFail[q.id] = now + 120
                        if okc and msg then Bonus.LastQuestMsg = strip(msg) end
                    end
                    task.wait(0.6)
                elseif have >= need then
                    wait += 1
                end
            end
            Bonus.ResetAt = os.clock() + (tonumber(data.resetIn) or 0)
            Bonus.QuestText = ("Completed %d/%d | claimed by script: %d"):format(done, total, Bonus.Claimed)
                .. ((wait > 0) and (" | rejected: " .. wait) or "")
        end
        Bonus.BusyQ = false
    end

    -- Redeem 1 code. Succeeds if server response begins with green color code (`2)
    function Bonus.redeem(code)
        local ok, res = netCall("ModCommand", "redeemcode", code)
        if not ok then return nil, "cannot reach server" end
        local lines = type(res) == "table" and type(res.lines) == "table" and res.lines or nil
        if not lines then return false, "empty reply" end
        local first = tostring(lines[1] or "")
        local parts = {}
        for _, l in ipairs(lines) do parts[#parts + 1] = strip(l) end
        return string.sub(first, 1, 2) == "`2", table.concat(parts, " ")
    end

    function Bonus.checkCodes()
        if Bonus.BusyR then return end
        Bonus.BusyR = true
        local ok, list = netCall("ActiveCodes")
        if not ok or type(list) ~= "table" then
            Bonus.CodeText = "Failed to fetch code list"
        elseif list.note ~= nil then
            Bonus.CodeText = "Redeem is currently closed: " .. strip(list.note)
        else
            local total, have, newOk = 0, 0, 0
            for _, c in ipairs(list) do
                total += 1
                local code = c.code and tostring(c.code)
                if c.done then
                    have += 1
                elseif code and not Bonus.Tried[code] and not (type(c.uses) == "number" and c.uses == 0) then
                    local success, msg = Bonus.redeem(code)
                    if success ~= nil then Bonus.Tried[code] = true end -- server responded
                    if success then
                        have += 1
                        newOk += 1
                        Bonus.Redeemed += 1
                        notify("Redeem succeeded", code .. ": " .. tostring(msg), 5)
                        Hook.send("bonus", "Redeem succeeded: " .. code .. ": " .. tostring(msg))
                    elseif success == false then
                        Bonus.LastCodeMsg = code .. ": " .. tostring(msg)
                    end
                    task.wait(1)
                end
            end
            Bonus.CodeText = ("Active codes: %d | already redeemed: %d | redeemed by script: %d"):format(total, have, Bonus.Redeemed)
        end
        Bonus.BusyR = false
    end

    function Bonus.updateStatus()
        local now = os.clock()
        local q = Bonus.QuestText
        if Bonus.ResetAt then q = q .. "\nNew quests in " .. timeText(Bonus.ResetAt - now) end
        if Bonus.LastQuestMsg then q = q .. "\nLast message: " .. Bonus.LastQuestMsg end
        q = q .. "\n" .. (Bonus.Quest and ("Next check in " .. math.max(0, math.ceil(Bonus.NextQuest - now)) .. " seconds") or "Auto claim off")
        local c = Bonus.CodeText
        if Bonus.LastCodeMsg then c = c .. "\nLast message: " .. Bonus.LastCodeMsg end
        c = c .. "\n" .. (Bonus.Redeem and ("Next check in " .. timeText(Bonus.NextCode - now)) or "Auto redeem off")
        if UI.QuestStatus then pcall(function() UI.QuestStatus:SetDesc(q) end) end
        if UI.CodeStatus then pcall(function() UI.CodeStatus:SetDesc(c) end) end
    end

    task.spawn(function()
        while alive() do
            local now = os.clock()
            if Bonus.Quest and now >= Bonus.NextQuest then
                Bonus.NextQuest = now + Bonus.QuestEvery
                pcall(Bonus.checkQuests)
            end
            if Bonus.Redeem and now >= Bonus.NextCode then
                Bonus.NextCode = now + Bonus.CodeEvery
                pcall(Bonus.checkCodes)
            end
            Bonus.updateStatus()
            task.wait(1)
        end
    end)
end)() end

Config.add("Bonus", Bonus, { "Quest", "Redeem" })

-- ===== TAB: BONUS =====
do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local BonusTab = UI.Tabs["Bonus"]
    local bQuest = box(BonusTab, "Daily Quests", true)
    local bCode = box(BonusTab, "Redeem Code", true)

    safe(function()
        UI.QuestStatus = bQuest:Paragraph({ Title = "Status", Desc = "-" })
    end)

    safe(function()
        bQuest:Toggle({
            Title = "Auto Claim Quest",
            Desc = "Claim rewards for finished quests",
            Value = Bonus.Quest,
            Callback = function(on)
                Bonus.Quest = on
                if on then Bonus.NextQuest = 0 end
            end,
        })
    end)

    safe(function()
        bQuest:Button({
            Title = "Check quests now",
            Callback = function() task.spawn(Bonus.checkQuests) end,
        })
    end)

    safe(function()
        UI.CodeStatus = bCode:Paragraph({ Title = "Status", Desc = "-" })
    end)

    safe(function()
        bCode:Toggle({
            Title = "Auto Redeem Code",
            Desc = "Redeem all active codes not used yet",
            Value = Bonus.Redeem,
            Callback = function(on)
                Bonus.Redeem = on
                if on then Bonus.NextCode = 0 end
            end,
        })
    end)

    safe(function()
        bCode:Button({
            Title = "Check codes now",
            Callback = function()
                table.clear(Bonus.Tried)
                task.spawn(Bonus.checkCodes)
            end,
        })
    end)

    safe(function()
        bCode:Input({
            Title = "Redeem code manually",
            Desc = "Type a code then press Enter",
            Value = "",
            Placeholder = "CODE",
            Callback = function(text)
                local code = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if code == "" then return end
                task.spawn(function()
                    local success, msg = Bonus.redeem(code)
                    if success then Bonus.Redeemed += 1 end
                    notify(success and "Redeem succeeded" or "Redeem failed", code .. ": " .. tostring(msg), 5)
                end)
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- GROWSCAN: Floating Items & World Blocks (like Growscan 9000 in Growtopia)
---------------------------------------------------------------------
-- How it works:
--   - Floating Items: world drops (from game drop list), summed per item.
--   - World Blocks: all world tiles counted per item (foreground + background).
--     Seed planted on foreground = tree.
--   - Auto Scan: repeats every 2s. Results sorted by highest count.
local Scan = {
    Auto = false,
    Layer = "All",      -- "All" | "Front" | "Background"
    Filter = "",          -- search item name
    Every = 2,
    Limit = 60,           -- max rows per list
    Last = nil,
}

do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local function fmtNum(n)
        local str = tostring(math.floor(n))
        local out = str:reverse():gsub("(%d%d%d)", "%1."):reverse()
        return (out:gsub("^%.", ""))
    end

    local function blockName(id)
        local it = ItemDB[id]
        local nm = itemName(id)
        if it and it.kind == "seed" then nm = nm .. " (tree)" end
        return nm
    end

    -- Convert {id = count} map to text, sorted descending
    local function listText(counts, nameFn)
        local list = {}
        for id, n in pairs(counts) do list[#list + 1] = { id = id, n = n } end
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.id < b.id
        end)
        local filter = string.lower(Scan.Filter or "")
        local lines, total = {}, 0
        for _, e in ipairs(list) do
            local name = nameFn(e.id)
            if filter == "" or string.find(string.lower(name), filter, 1, true) then
                total += 1
                if total <= Scan.Limit then
                    lines[#lines + 1] = name .. "  x" .. fmtNum(e.n)
                end
            end
        end
        if total > Scan.Limit then lines[#lines + 1] = ("... +%d more items (use Search item)"):format(total - Scan.Limit) end
        if #lines == 0 then lines[1] = (filter ~= "") and "No matches" or "Empty" end
        return table.concat(lines, "\n"), total
    end

    local function scanFloating()
        local counts, total, piles = {}, 0, 0
        local list = Drops.list
        if type(list) ~= "table" then return nil end
        for _, d in pairs(list) do
            if type(d) == "table" and type(d.id) == "number" then
                local n = tonumber(d.n) or 1
                if n > 0 then
                    counts[d.id] = (counts[d.id] or 0) + n
                    total += n
                    piles += 1
                end
            end
        end
        return counts, total, piles
    end

    local function scanBlocks()
        local w = Refs.World
        if not w or type(w.fg) ~= "table" or type(w.w) ~= "number" then return nil end
        local grid, budget = w.fg, { next = os.clock() + 0.0015 }
        local fgC, bgC, nf, nb = {}, {}, 0, 0
        local trees = {} -- [seed] = { r = ready, g = growing, nxt = seconds until next harvest }
        local st = workspace:GetServerTimeNow()
        local readyAt = Auto.treeReadyAt
        for y = 0, w.h - 1 do
            local rf = w.fg[y]
            local rb = w.bg and w.bg[y]
            for x = 0, w.w - 1 do
                local a = rf and rf[x] or 0
                if a ~= 0 then
                    fgC[a] = (fgC[a] or 0) + 1
                    nf += 1
                    local it = ItemDB[a]
                    if readyAt and it and it.kind == "seed" then
                        local ra = readyAt(x, y, a)
                        if ra then
                            local e = trees[a]
                            if not e then
                                e = { r = 0, g = 0 }
                                trees[a] = e
                            end
                            if st >= ra then
                                e.r += 1
                            else
                                e.g += 1
                                if not e.nxt or ra - st < e.nxt then e.nxt = ra - st end
                            end
                        end
                    end
                end
                local b = rb and rb[x] or 0
                if b ~= 0 then
                    bgC[b] = (bgC[b] or 0) + 1
                    nb += 1
                end
                Session.scanStep(budget, y * w.w + x + 1)
                if not alive() or Refs.World ~= w or w.fg ~= grid then return nil end
            end
        end
        return fgC, bgC, nf, nb, trees
    end

    local function waitText(sec)
        sec = math.max(0, math.floor(sec or 0))
        if sec >= 3600 then return ("%dh %dm"):format(sec // 3600, sec % 3600 // 60) end
        return ("%dm %ds"):format(sec // 60, sec % 60)
    end

    -- Tree list: ready to harvest first, then soonest ready
    local function treeText(trees)
        local list, totalR, totalG = {}, 0, 0
        local filter = string.lower(Scan.Filter or "")
        for id, e in pairs(trees) do
            totalR += e.r
            totalG += e.g
            local name = itemName(id)
            if filter == "" or string.find(string.lower(name), filter, 1, true) then
                list[#list + 1] = { name = name, e = e }
            end
        end
        table.sort(list, function(a, b)
            if a.e.r ~= b.e.r then return a.e.r > b.e.r end
            return (a.e.nxt or math.huge) < (b.e.nxt or math.huge)
        end)
        local lines = {}
        for i, v in ipairs(list) do
            if i > Scan.Limit then
                lines[#lines + 1] = ("... +%d more types"):format(#list - Scan.Limit)
                break
            end
            local line = ("%s: %d ready | %d growing"):format(v.name, v.e.r, v.e.g)
            if v.e.nxt then line = line .. " (next " .. waitText(v.e.nxt) .. ")" end
            lines[#lines + 1] = line
        end
        if #lines == 0 then lines[1] = (filter ~= "") and "No matches" or "No trees" end
        return table.concat(lines, "\n"), totalR, totalG
    end

    local function setDesc(el, txt, key)
        if Scan[key] == txt then return end
        Scan[key] = txt
        if el then pcall(function() el:SetDesc(txt) end) end
    end

    function Scan.run()
        if Scan.Busy then return end
        Scan.Busy = true
        local w = Refs.World
        local fl, flTotal, piles = scanFloating()
        local fgC, bgC, nf, nb, trees = scanBlocks()
        local treeTxt, treeR, treeG = "Tree data not found", nil, nil
        if trees then treeTxt, treeR, treeG = treeText(trees) end

        local floatText = fl and select(1, listText(fl, itemName)) or "Drop data not found. Press 'Connect to game'"
        local blockText = "World data not found. Press 'Connect to game'"
        if fgC then
            local pick
            if Scan.Layer == "Front" then
                pick = fgC
            elseif Scan.Layer == "Background" then
                pick = bgC
            else
                pick = {}
                for id, n in pairs(fgC) do pick[id] = (pick[id] or 0) + n end
                for id, n in pairs(bgC) do pick[id] = (pick[id] or 0) + n end
            end
            blockText = select(1, listText(pick, blockName))
        end

        local name = w and rawget(w, "name")
        local info = table.concat({
            "World: " .. ((type(name) == "string" and name ~= "") and name or "-")
                .. (w and type(w.w) == "number" and (" (" .. w.w .. "x" .. w.h .. ")") or ""),
            "Foreground: " .. (nf and fmtNum(nf) or "-") .. " | Background: " .. (nb and fmtNum(nb) or "-"),
            "Floating: " .. (flTotal and (fmtNum(flTotal) .. " items (" .. piles .. " stacks)") or "-"),
            "Trees: " .. (treeR and (fmtNum(treeR) .. " ready to harvest | " .. fmtNum(treeG) .. " growing") or "-"),
            "Last scan: " .. os.date("%H:%M:%S"),
        }, "\n")

        setDesc(UI.ScanInfo, info, "_info")
        setDesc(UI.ScanFloat, floatText, "_float")
        setDesc(UI.ScanBlocks, blockText, "_blocks")
        setDesc(UI.ScanTrees, treeTxt, "_trees")
        Scan.Busy = false
    end

    task.spawn(function()
        local last = 0
        while alive() do
            if Scan.Auto and os.clock() - last >= Scan.Every then
                last = os.clock()
                pcall(Scan.run)
            end
            task.wait(0.5)
        end
    end)
end)() end

Config.add("Growscan", Scan, { "Auto", "Layer" })

-- ===== TAB: GROWSCAN =====
do (function() -- isolated function: internal locals do not count toward the 200-local limit
    local ScanTab = UI.Tabs["Growscan"]
    Box.SessionStats = box(ScanTab, "Session stats", true)
    local sCtl = box(ScanTab, "Scan world", false)
    local sFloat = box(ScanTab, "Floating Items", false)
    local sBlock = box(ScanTab, "World Blocks", false)
    local sTree = box(ScanTab, "Trees (ready to harvest)", false)

    safe(function()
        UI.ScanInfo = sCtl:Paragraph({ Title = "World Info", Desc = "Press Scan now" })
    end)

    safe(function()
        sCtl:Toggle({
            Title = "Auto Scan",
            Desc = "Auto update every 2 seconds",
            Value = Scan.Auto,
            Callback = function(on)
                Scan.Auto = on
                if on then task.spawn(Scan.run) end
            end,
        })
    end)

    safe(function()
        sCtl:Button({
            Title = "Scan now",
            Callback = function() task.spawn(Scan.run) end,
        })
    end)

    safe(function()
        sCtl:Input({
            Title = "Search item",
            Desc = "Filter item name (empty = all)",
            Value = "",
            Placeholder = "example: seed",
            Callback = function(text)
                Scan.Filter = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                task.spawn(Scan.run)
            end,
        })
    end)

    safe(function()
        UI.ScanFloat = sFloat:Paragraph({ Title = "List", Desc = "-" })
    end)

    safe(function()
        sBlock:Dropdown({
            Title = "Layer",
            Values = { "All", "Front", "Background" },
            Value = Scan.Layer,
            Callback = function(opt)
                Scan.Layer = opt
                task.spawn(Scan.run)
            end,
        })
    end)

    safe(function()
        UI.ScanBlocks = sBlock:Paragraph({ Title = "List", Desc = "-" })
    end)

    safe(function()
        UI.ScanTrees = sTree:Paragraph({ Title = "List", Desc = "-" })
    end)
end)() end

---------------------------------------------------------------------
-- SESSION STATS
---------------------------------------------------------------------
-- How it works:
--   - On execute (or Reset button), baseline counters are recorded.
--   - Every second: current - baseline = session delta. Divided by session duration = per hour.
--   - Gems are read from the game HUD gems counter (inside addGems).
do (function()
    local function gemsNow()
        local g = Refs.Gems
        local f = g and rawget(g, "addGems")
        if type(f) ~= "function" then return nil end
        for _, v in pairs(getUpvalues(f)) do
            if type(v) == "number" then return v end
        end
        return nil
    end
    Stats.gemsNow = gemsNow

    local function fmt(n)
        local str = tostring(math.floor(n or 0))
        local neg = string.sub(str, 1, 1) == "-"
        if neg then str = string.sub(str, 2) end
        local out = str:reverse():gsub("(%d%d%d)", "%1."):reverse()
        out = out:gsub("^%.", "")
        return (neg and "-" or "") .. out
    end

    local function dur(sec)
        sec = math.max(0, math.floor(sec))
        return ("%dh %dm %ds"):format(sec // 3600, sec % 3600 // 60, sec % 60)
    end

    -- tracked counters (all increment continuously while script runs)
    local function counters()
        return {
            broken = State.Broken, placed = State.Placed, collected = State.Collected,
            harvested = Farmer.Harvested, planted = Farmer.Planted,
        }
    end

    function Stats.reset()
        Stats.T0 = os.clock()
        Stats.Gems0 = gemsNow()
        Stats.Items = {}
        Stats.Base = counters()
    end
    Stats.Base = counters()

    function Stats.text()
        local hours = math.max((os.clock() - Stats.T0) / 3600, 1 / 3600)
        local now, base = counters(), Stats.Base
        local function line(label, key)
            local v = now[key] - (base[key] or 0)
            return ("%s: %s  (%s/hour)"):format(label, fmt(v), fmt(v / hours))
        end
        local g = gemsNow()
        if g and not Stats.Gems0 then Stats.Gems0 = g end
        local gemLine = "Gems: -"
        if g and Stats.Gems0 then
            local d = g - Stats.Gems0
            gemLine = ("Gems: %s  (%s%s, %s/hour)"):format(fmt(g), d >= 0 and "+" or "", fmt(d), fmt(d / hours))
        end
        -- top 5 collected items
        local top = {}
        for id, n in pairs(Stats.Items) do top[#top + 1] = { id = id, n = n } end
        table.sort(top, function(a, b) return a.n > b.n end)
        local tops = {}
        for i = 1, math.min(5, #top) do tops[i] = itemName(top[i].id) .. " x" .. fmt(top[i].n) end
        return table.concat({
            "Session duration: " .. dur(os.clock() - Stats.T0),
            gemLine,
            line("Blocks broken", "broken"),
            line("Blocks placed", "placed"),
            line("Drops collected", "collected"),
            line("Harvested", "harvested"),
            line("Planted", "planted"),
            "Top items: " .. ((#tops > 0) and table.concat(tops, ", ") or "-"),
        }, "\n")
    end

    task.spawn(function()
        local lastReport = os.clock()
        while alive() do
            local ok, txt = pcall(Stats.text)
            if ok and UI.StatsText and txt ~= Stats.Shown then
                Stats.Shown = txt
                pcall(function() UI.StatsText:SetDesc(txt) end)
            end
            -- periodic Discord reports
            if Hook.ReportMin > 0 and os.clock() - lastReport >= Hook.ReportMin * 60 then
                lastReport = os.clock()
                if ok then Hook.send("report", "Stats report\n```\n" .. txt .. "\n```") end
            elseif Hook.ReportMin <= 0 then
                lastReport = os.clock()
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: STATS =====
do (function()
    local StatTab = Box.SessionStats

    safe(function()
        UI.StatsText = StatTab:Paragraph({ Title = "This session", Desc = "-" })
    end)

    safe(function()
        StatTab:Button({
            Title = "Reset stats",
            Desc = "Start counting from zero",
            Callback = function()
                Stats.reset()
                notify("Stats", "Reset", 2)
            end,
        })
    end)

    safe(function()
        StatTab:Button({
            Title = "Send to Discord now",
            Desc = "Needs a webhook in the Discord tab",
            Callback = function()
                local ok, txt = pcall(Stats.text)
                if not (Hook.On and Hook.valid(Hook.Url)) then
                    notify("Stats", "Enable the Discord webhook first", 3)
                elseif ok then
                    Hook.send("report", "Stats report\n```\n" .. txt .. "\n```")
                    notify("Stats", "Added to send queue", 2)
                end
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- BAG: auto recycle trash items & auto convert locks
---------------------------------------------------------------------
-- How it works (same as in-game inventory buttons):
--   Recycle : remove from inventory then World.call("Recycle", id, count)
--   Convert : 100 World Locks -> 1 Diamond Lock, 100 Diamond Locks -> 1 Blue Gem Lock
--             via World.call("ConvertLock", from, to)
-- Tools & locks cannot be selected for recycling (prevents accidental loss).
local Bag = {
    TrashOn = false,
    TrashList = {},    -- list of item IDs to recycle
    TrashAt = 150,     -- recycle once count reaches this threshold
    Keep = 0,          -- keep this many
    LockOn = false,
    Recycled = 0,
    Converted = 0,
    Status = "-",
}

do (function()
    local LOCK_IDS = { [242] = true, [1796] = true, [7188] = true }
    local LOCK_STEPS = {
        { from = 242, to = 1796, name = "Diamond Lock" },
        { from = 1796, to = 7188, name = "Blue Gem Lock" },
    }

    local function worldCall(...)
        local w = Refs.World
        local f = w and rawget(w, "call")
        if type(f) ~= "function" then return false end
        return pcall(f, ...)
    end

    local function trashable(id)
        local it = ItemDB[id]
        return it ~= nil and it.kind ~= "tool" and not LOCK_IDS[id]
    end

    function Bag.recycle(id, n)
        if not Refs.Inv or n <= 0 or not trashable(id) then return false end
        n = math.min(n, invCount(id))
        if n <= 0 then return false end
        pcall(function() Refs.Inv:remove(id, n) end)
        local ok = worldCall("Recycle", id, n)
        if ok then
            Bag.Recycled += n
            Bag.Status = ("Recycle %s x%d"):format(itemName(id), n)
        end
        return ok
    end

    -- matches in-game convert button check (whether bag has room)
    local function convertLock(step)
        local inv = Refs.Inv
        if not inv or invCount(step.from) < 100 then return false end
        local okU, used = pcall(function() return inv:used() end)
        local okC, cap = pcall(function() return inv.capacity end)
        if invCount(step.to) + 1 > 200 then return false end
        if invCount(step.to) == 0 and invCount(step.from) ~= 100 and okU and okC
            and type(used) == "number" and type(cap) == "number" and used >= cap then
            return false
        end
        pcall(function()
            inv:remove(step.from, 100)
            inv:add(step.to, 1)
        end)
        local ok = worldCall("ConvertLock", step.from, step.to)
        if ok then
            Bag.Converted += 1
            Bag.Status = "Convert to " .. step.name
        end
        return ok
    end

    function Bag.tick()
        if AutoDrop.Busy or WorldFinder.Busy then return end
        if Bag.TrashOn then
            for _, id in ipairs(Bag.TrashList) do
                local n = invCount(id)
                if n >= Bag.TrashAt and n > Bag.Keep then
                    Bag.recycle(id, n - Bag.Keep)
                    task.wait(0.5)
                end
            end
        end
        if Bag.LockOn then
            for _, step in ipairs(LOCK_STEPS) do
                if convertLock(step) then task.wait(0.5) end
            end
        end
    end

    -- dropdown labels: recyclable items in inventory
    function Bag.labels()
        local out, seen = {}, {}
        if Refs.Inv then
            for _, slot in ipairs(Refs.Inv.slots) do
                local id = slot.id
                if id and not seen[id] and (slot.n or 0) > 0 and trashable(id) then
                    seen[id] = true
                    out[#out + 1] = { id = id, label = ("%s [%d]"):format(itemName(id), id) }
                end
            end
        end
        -- already-selected items remain listed even at 0 count
        for _, id in ipairs(Bag.TrashList) do
            if not seen[id] then
                seen[id] = true
                out[#out + 1] = { id = id, label = ("%s [%d]"):format(itemName(id), id) }
            end
        end
        table.sort(out, function(a, b) return a.id < b.id end)
        local labels, picked = {}, {}
        for _, e in ipairs(out) do
            labels[#labels + 1] = e.label
            if table.find(Bag.TrashList, e.id) then picked[#picked + 1] = e.label end
        end
        return labels, picked
    end

    task.spawn(function()
        while alive() do
            pcall(Bag.tick)
            if UI.BagStatus then
                local txt = ("Status: %s\nRecycled: %d items | Lock converts: %d\nSelected items: %d"):format(
                    Bag.Status, Bag.Recycled, Bag.Converted, #Bag.TrashList)
                if txt ~= Bag.Shown then
                    Bag.Shown = txt
                    pcall(function() UI.BagStatus:SetDesc(txt) end)
                end
            end
            task.wait(3)
        end
    end)
end)() end

Config.add("Bag", Bag, { "TrashOn", "TrashList", "TrashAt", "Keep", "LockOn" })

-- ===== TAB: BAG =====
do (function()
    local BagTab = UI.Tabs["Bag"]

    safe(function()
        UI.BagStatus = BagTab:Paragraph({ Title = "Status", Desc = "-" })
    end)

    local bTrash = box(BagTab, "Auto Recycle (trash items)", true)
    local bLock = box(BagTab, "Auto Convert Lock", false)

    safe(function()
        bTrash:Toggle({
            Title = "Auto Recycle",
            Desc = "Selected items are recycled automatically",
            Value = Bag.TrashOn,
            Callback = function(on) Bag.TrashOn = on end,
        })
    end)

    safe(function()
        local labels, picked = Bag.labels()
        UI.TrashDropdown = bTrash:Dropdown({
            Title = "Items to recycle",
            Desc = "Multiple allowed. Tools & locks are not shown",
            Values = (#labels > 0) and labels or { "(inventory not read yet)" },
            Value = picked,
            Multi = true,
            AllowNone = true,
            Callback = function(opts)
                local list = {}
                for _, label in ipairs(type(opts) == "table" and opts or { opts }) do
                    local id = tonumber(string.match(tostring(label), "%[(%d+)%]$"))
                    if id then list[#list + 1] = id end
                end
                Bag.TrashList = list
            end,
        })
    end)

    -- called when inventory updates
    local lastSig = nil
    UI.TrashRefresh = function(force)
        if not force and not UI.tabVisible("Bag") then return end
        local labels, picked = Bag.labels()
        local sig = table.concat(labels, "|")
        if not force and sig == lastSig then return end
        lastSig = sig
        if not UI.TrashDropdown then return end
        UI.exec(function() UI.TrashDropdown:Refresh((#labels > 0) and labels or { "(inventory empty)" }) end)
        if #picked > 0 then UI.exec(function() UI.TrashDropdown:Select(picked) end) end
    end

    addNumber(bTrash, {
        Title = "Recycle when amount >=",
        Desc = "200 = only when a slot is full",
        Min = 1, Max = 200, Step = 1, Default = Bag.TrashAt,
        Callback = function(v) Bag.TrashAt = math.floor(v) end,
    })

    addNumber(bTrash, {
        Title = "Keep",
        Desc = "Amount not recycled",
        Min = 0, Max = 199, Step = 1, Default = Bag.Keep,
        Callback = function(v) Bag.Keep = math.floor(v) end,
    })

    safe(function()
        bTrash:Button({
            Title = "Refresh item list",
            Callback = function() UI.later("trash", function() UI.TrashRefresh(true) end) end,
        })
    end)

    safe(function()
        bLock:Toggle({
            Title = "Auto Convert Lock",
            Desc = "100 WL -> 1 DL, 100 DL -> 1 BGL (same as the game)",
            Value = Bag.LockOn,
            Callback = function(on) Bag.LockOn = on end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- AUTO SPLICE
---------------------------------------------------------------------
-- How it works (same as manual splicing in game):
--   1. Plant Seed A on an empty Grid tile (must have a block underneath).
--   2. Place Seed B on tree A -> World.spliceSeed(x, y, B).
--   3. Server responds with spliced tree ID, tile updates immediately on screen.
--   Splice outcome is checked via game Splice module first; invalid pairs are skipped.
do (function()
    local okMod, SpliceMod = pcall(function()
        local module = Session.findModule("Splice", Shared)
        if not module then return nil end
        return require(module)
    end)

    function Splice.result(a, b)
        if not (okMod and type(SpliceMod) == "table" and type(SpliceMod.result) == "function") then return nil end
        if not (a and b) then return nil end
        local ok, r = pcall(SpliceMod.result, a, b)
        return ok and r or nil
    end

    local function setVisual()
        if UI.SpliceToggle then pcall(function() UI.SpliceToggle:Set(Splice.Running) end) end
    end

    function Splice.stop(reason)
        Splice.Running = false
        if Splice.Roaming then Auto.stopSpliceRoam() end
        Splice.Status = reason or "Stopped"
        setVisual()
        if reason then notify("Auto Splice", reason, 4) end
    end

    local function treeSpliced(x, y)
        local t = Auto.treeEntry(x, y)
        return type(t) == "table" and t.s == true
    end

    local function spliceAt(x, y)
        local w = Refs.World
        local f = w and rawget(w, "spliceSeed")
        if type(f) ~= "function" then return false, "game splice function not found" end
        local ok, made = pcall(f, x, y, Splice.B)
        if ok and made and ItemDB[made] then
            pcall(function() Refs.Inv:remove(Splice.B, 1) end)
            if Refs.SetTile then pcall(Refs.SetTile, "fg", x, y, made, true) end -- update display immediately
            Splice.Made += 1
            Splice.Status = ("Spliced into %s (%d,%d)"):format(itemName(made), x, y)
            return true
        end
        return false, "rejected by server"
    end

    local function loop(runId)
        while Splice.Running and alive() and Splice.RunId == runId do
            local px, py = getPlayerTile()
            if not px then
                Splice.stop("Character not found (left world?)")
                return
            end
            local A, B = Splice.A, Splice.B
            local acted = false
            local now = os.clock()
            for _, o in ipairs(sortedOffsets()) do
                if not Splice.Running then break end
                local x, y = px + o.dx, py + o.dy
                local key = x .. "," .. y
                if not (Splice.Fail[key] and Splice.Fail[key] > now) then
                    local fg = tileAt("fg", x, y)
                    -- 1) plant Seed A
                    if fg == 0 and invCount(A) > 0 and invCount(B) > 0 and Auto.plantSpotOk(x, y, A) then
                        sendSetTile("fg", x, y, A)
                        pcall(function() Refs.Inv:remove(A, 1) end)
                        Splice.Planted += 1
                        Splice.Status = ("Plant %s (%d,%d)"):format(itemName(A), x, y)
                        acted = true
                        task.wait(Splice.Ms / 1000)
                        fg = tileAt("fg", x, y)
                    end
                    -- 2) splice Seed B onto tree A
                    if fg == A and invCount(B) > 0 and not treeSpliced(x, y) then
                        local ok, why = spliceAt(x, y)
                        if not ok then
                            Splice.Fail[key] = os.clock() + 30
                            Splice.Status = ("Failed to splice (%d,%d): %s"):format(x, y, why)
                        end
                        acted = true
                        task.wait(Splice.Ms / 1000)
                    end
                end
            end
            if not acted then
                if invCount(A) <= 0 or invCount(B) <= 0 then
                    Splice.stop("Out of seeds")
                    return
                end
                Splice.Status = "Waiting for empty Grid tile (harvest existing tree first)"
                task.wait(1)
            end
        end
    end

    function Splice.start()
        if Splice.Running then return end
        if WorldFinder.Busy then notify("World Finder", "Stop hunting before running farming", 3) return end
        if AutoDrop.Busy then notify("Auto Drop", "Wait for the drop trip to finish", 3) return end
        local err
        if not Refs.World then
            err = "World data not found. Press 'Connect to game'"
        elseif not (Splice.A and Splice.B) then
            err = "Select Seed A and Seed B first"
        elseif Splice.A == Splice.B then
            err = "Seed A and Seed B must differ"
        elseif not Splice.result(Splice.A, Splice.B) then
            err = "This combination cannot be spliced"
        elseif not Splice.Roam and next(State.Offsets) == nil then
            err = "Select tiles in Auto Farm's tile grid or turn on Walk around world"
        elseif State.Running or Clear.Running or Farmer.Running then
            err = "Stop Auto Farm / Clear / Farmer first"
        end
        if err then
            notify("Auto Splice", err, 4)
            setVisual()
            return
        end
        table.clear(Splice.Fail)
        Splice.Running = true
        Splice.RunId = (Splice.RunId or 0) + 1
        setVisual()
        if Splice.Roam then
            local e = Auto.startSpliceRoam()
            if e then Splice.stop(e) end
        else
            task.spawn(loop, Splice.RunId)
        end
    end

    function Splice.resultText()
        if not (Splice.A and Splice.B) then return "Select Seed A and Seed B" end
        local r = Splice.result(Splice.A, Splice.B)
        if not r then return "Result: cannot be spliced" end
        return "Result: " .. itemName(r)
    end

    task.spawn(function()
        while alive() do
            if UI.SpliceStatus then
                local txt = ("Status: %s\n%s\nSeed A: %s (x%d) | Seed B: %s (x%d)\nPlanted: %d | Spliced into: %d"):format(
                    Splice.Running and Splice.Status or ("STOPPED - " .. Splice.Status), Splice.resultText(),
                    Splice.A and itemName(Splice.A) or "-", Splice.A and invCount(Splice.A) or 0,
                    Splice.B and itemName(Splice.B) or "-", Splice.B and invCount(Splice.B) or 0,
                    Splice.Planted, Splice.Made)
                if txt ~= Splice.Shown then
                    Splice.Shown = txt
                    pcall(function() UI.SpliceStatus:SetDesc(txt) end)
                end
            end
            task.wait(1)
        end
    end)
end)() end

Config.add("Splice", Splice, { "A", "B", "Ms", "Roam" })
Splice.Ms = math.max(Splice.Ms, 140)

-- ===== TAB: SPLICE =====
do (function()
    local SpTab = UI.Tabs["Splice"]

    safe(function()
        UI.SpliceStatus = SpTab:Paragraph({ Title = "Splice Status", Desc = "-" })
    end)

    local sCtl = box(SpTab, "Controls", true)
    local sSeed = box(SpTab, "Seed", true)
    local sSpeed = box(SpTab, "Speed", false)

    safe(function()
        UI.SpliceToggle = sCtl:Toggle({
            Title = "Auto Splice",
            Desc = "Plant Seed A then splice Seed B",
            Value = false,
            Callback = function(on)
                if on then Splice.start() elseif Splice.Running then Splice.stop() end
            end,
        })
    end)

    local function seedLabels()
        local labels = {}
        for _, id in ipairs(seedIds()) do labels[#labels + 1] = ("%s [%d]"):format(itemName(id), id) end
        if #labels == 0 then labels = { "(no seeds in inventory)" } end
        return labels
    end
    local function idOf(opt) return tonumber(string.match(tostring(opt or ""), "%[(%d+)%]$")) end

    safe(function()
        UI.SpliceA = sSeed:Dropdown({
            Title = "Seed A (planted)",
            Values = { "(loading...)" },
            Callback = function(opt)
                local id = idOf(opt)
                if id then Splice.A = id end
            end,
        })
    end)

    safe(function()
        UI.SpliceB = sSeed:Dropdown({
            Title = "Seed B (spliced)",
            Values = { "(loading...)" },
            Callback = function(opt)
                local id = idOf(opt)
                if id then Splice.B = id end
            end,
        })
    end)

    -- called when inventory updates
    local lastSig = nil
    UI.SpliceRefresh = function(force)
        if not force and not UI.tabVisible("Splice") then return end
        local labels = seedLabels()
        local sig = table.concat(labels, "|")
        if not force and sig == lastSig then return end
        lastSig = sig
        for _, pair in ipairs({ { UI.SpliceA, Splice.A }, { UI.SpliceB, Splice.B } }) do
            local dd, id = pair[1], pair[2]
            if dd then
                UI.exec(function() dd:Refresh(labels) end)
                if id then
                    local want = "[" .. id .. "]"
                    for _, l in ipairs(labels) do
                        if string.sub(l, -#want) == want then
                            UI.exec(function() dd:Select(l) end)
                            break
                        end
                    end
                end
            end
        end
    end

    safe(function()
        sSeed:Button({
            Title = "Refresh seed list",
            Callback = function() UI.later("splice", function() UI.SpliceRefresh(true) end) end,
        })
    end)

    safe(function()
        sCtl:Toggle({
            Title = "Roam world (A*)",
            Desc = "On: walk the whole world. Off: only the 5x5 Grid tiles",
            Value = Splice.Roam,
            Callback = function(on)
                if Splice.Running then Splice.stop("Mode changed, re-enable") end
                Splice.Roam = on
            end,
        })
    end)

    addNumber(sSpeed, {
        Title = "Plant / splice delay (ms)",
        Min = 140, Max = 2000, Step = 10, Default = Splice.Ms,
        Callback = function(v) Splice.Ms = math.floor(v) end,
    })
end)() end

-- ===== TAB: AUTO DIRT FARM =====
do
    local tab = UI.Tabs["Dirt Farm"]
    local settings = Build.Dirt
    local inputs = {}
    local status
    safe(function()
        status = tab:Paragraph({ Title = "Status", Desc = "Ready to build" })
    end)
    safe(function()
        tab:Toggle({
            Title = "Dig first",
            Desc = "Turn on to excavate a new farm. Leave off to resume placing blocks in an excavated farm.",
            Value = settings.Dig,
            Callback = function(on) settings.Dig = on end,
        })
    end)
    safe(function()
        UI.DirtToggle = tab:Toggle({
            Title = "Run Auto Dirt Farm",
            Desc = "Refill Dirt from drops or Dirt Seeds, then resume building.",
            Value = false,
            Callback = function(on)
                if on then Build.start(true) elseif Build.DirtRun then Build.stop() end
            end,
        })
    end)
    local area = box(tab, "Area bounds", false)
    local function setBound(key, value)
        if Build.DirtRun then
            notify("Auto Dirt Farm", "Stop Auto Dirt Farm to edit the area", 3)
            return
        end
        settings[key] = value
    end
    for _, field in ipairs({
        { "X0", "Start X", 0 }, { "X1", "End X", 0 },
        { "Y0", "Top row Y", 1 }, { "Y1", "Bottom row Y", -1 },
    }) do
        local key, title, min = table.unpack(field)
        safe(function()
            inputs[key] = area:Input({
                Title = title,
                Desc = key == "Y1" and "Blank or -1 means down to bedrock" or nil,
                Value = tostring(settings[key]),
                Callback = function(text)
                    local n = tonumber(text)
                    if n and n == n and math.abs(n) < math.huge then
                        setBound(key, math.max(min, math.floor(n)))
                    elseif key == "Y1" and tostring(text):match("^%s*$") then
                        setBound(key, -1)
                    end
                end,
            })
        end)
    end
    for _, corner in ipairs({
        { "X0", "Y0", "Use current position as the top-left corner", "Stand on the block that will be the first row." },
        { "X1", "Y1", "Use current position as the bottom-right corner", "Stand on the block that will be the last row." },
    }) do
        local xKey, yKey, title, desc = table.unpack(corner)
        safe(function()
            area:Button({ Title = title, Desc = desc, Callback = function()
                if Build.DirtRun then notify("Auto Dirt Farm", "Stop Auto Dirt Farm to edit the area", 3) return end
                local x, y = Auto.here()
                if not x then notify("Auto Dirt Farm", "You are not in a world yet", 3) return end
                settings[xKey], settings[yKey] = x, math.max(1, y + 1)
                if inputs[xKey] then inputs[xKey]:Set(tostring(settings[xKey])) end
                if inputs[yKey] then inputs[yKey]:Set(tostring(settings[yKey])) end
                notify("Auto Dirt Farm", "Dirt Farm area saved", 3)
            end })
        end)
    end
    task.spawn(function()
        local shown
        while alive() do
            if status and UI.tabVisible("Dirt Farm") then
                local id, info = Build.dirtBlock(), Build.DirtInfo
                local phase = Build.DirtRun and Build.Phase or Build.DirtPhase or "Ready to build"
                local bottom = settings.Y1 >= 1 and tostring(settings.Y1) or "bedrock"
                local text = ("%s\nX %d-%d | Y %d-%s | Dirt x%d"):format(phase,
                    settings.X0, settings.X1, settings.Y0, bottom, id and invCount(id) or 0)
                if info then
                    text ..= ("\n%d/%d blocks | %d tiles"):format(info.done, info.total, info.carve + info.kept)
                    if info.placeTop then
                        text ..= ("\n%s: Y %d-%d"):format("Place rows", info.placeTop, info.placeBottom)
                    end
                end
                if shown ~= text then
                    shown = text
                    pcall(function() status:SetDesc(text) end)
                end
            end
            task.wait(1)
        end
    end)
end

-- ===== TAB: LAND (build farm world) =====
do (function()
    local LTab = UI.Tabs["Land"]

    safe(function()
        UI.LandStatus = LTab:Paragraph({ Title = "Land Status", Desc = "-" })
    end)

    local lCtl = box(LTab, "Build Land", true)
    local lShape = box(LTab, "Land shape", true)

    safe(function()
        UI.BuildToggle = lCtl:Toggle({
            Title = "Build Land",
            Desc = "Digs from the surface down to the bottom first, then places rows upward to the top (each row is its own bridge). Out of blocks: produces on 1 row",
            Value = false,
            Callback = function(on)
                if on then Build.start() elseif Build.Running and not Build.DirtRun then Build.stop() end
            end,
        })
    end)

    safe(function()
        UI.BuildBlockDropdown = lCtl:Dropdown({
            Title = "Land block",
            Desc = "Solid block from inventory",
            Values = { "(loading...)" },
            Callback = function(opt)
                local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
                if id then Build.BlockId = id end
            end,
        })
    end)

    local function num(text, def)
        local v = tonumber(tostring(text or ""):match("%-?%d+"))
        return v or def
    end

    safe(function()
        lShape:Input({
            Title = "Start X",
            Desc = "Leftmost column",
            Value = tostring(Land.X0),
            Placeholder = "0",
            Callback = function(t) Land.X0 = math.max(0, num(t, Land.X0)) end,
        })
    end)

    safe(function()
        lShape:Input({
            Title = "End X",
            Desc = "Rightmost column (beyond world width = to the edge)",
            Value = tostring(Land.X1),
            Placeholder = "99",
            Callback = function(t) Land.X1 = math.max(0, num(t, Land.X1)) end,
        })
    end)

    safe(function()
        lShape:Input({
            Title = "Top row Y",
            Desc = "Top block row. Rows below go automatically down to just above bedrock (dirt is dug out)",
            Value = tostring(Land.Y0),
            Placeholder = "2",
            Callback = function(t) Land.Y0 = math.max(1, num(t, Land.Y0)) end,
        })
    end)

    safe(function()
        lShape:Button({
            Title = "Use character position as top-left corner",
            Desc = "Stand on the first block of the top row, then press (left stairs go to its left)",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Land", "You are not in a world yet", 3)
                    return
                end
                -- stood-on block = first block of top row, left stair column is to its left
                Land.X0, Land.Y0 = math.max(0, x - 1), y + 1
                notify("Land", ("Start X %d, top row Y %d"):format(Land.X0, Land.Y0), 4)
            end,
        })
    end)

    safe(function()
        lCtl:Toggle({
            Title = "Start Factory when finished",
            Value = Build.ThenFactory,
            Callback = function(on) Build.ThenFactory = on end,
        })
    end)

    safe(function()
        lCtl:Button({
            Title = "Production break position = character position",
            Desc = "Stand at the break spot and press. Press again at the same spot = back to automatic",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Land", "You are not in a world yet", 3)
                    return
                end
                if Build.BreakX == x and Build.BreakY == y then
                    Build.BreakX, Build.BreakY = -1, -1
                    notify("Land", "Production break spot: automatic", 3)
                else
                    Build.BreakX, Build.BreakY = x, y
                    if next(Build.Tiles) == nil then Build.Tiles["1,0"] = true end
                    notify("Land", ("Production break spot (%d,%d)"):format(x, y), 3)
                end
            end,
        })
    end)

    safe(function()
        lCtl:Button({
            Title = "Pick production break tiles (Grid)",
            Desc = "Grid opens in Land mode (separate from Auto Farm & Factory)",
            Callback = function()
                if UI.setGridMode then UI.setGridMode("land") end
                if UI.GridGui then UI.GridGui.Enabled = true end
            end,
        })
    end)

    task.spawn(function()
        while alive() do
            if Build.DirtRun or (not Build.Running and not UI.tabVisible("Land")) then task.wait(1) continue end
            local txt
            if Refs.World then
                local info = Build.Info
                if not (Build.Running and info) then
                    local key = tostring(Build.BlockId) .. "|" .. Land.X0 .. "|" .. Land.X1 .. "|" .. Land.Y0
                    if not info or not Build.InfoAt or os.clock() - Build.InfoAt > 5 or Build.InfoKey ~= key then
                        info = Auto.landInfo()
                        Build.Info, Build.InfoAt, Build.InfoKey = info, os.clock(), key
                    end
                end
                local rows = Auto.landRows()
                local have = Build.BlockId and invCount(Build.BlockId) or 0
                local seed = Auto.seedOfBlock(Build.BlockId)
                txt = table.concat({
                    "Status   : " .. (Build.Running and "RUNNING" or "STOPPED") .. " - " .. Build.Phase,
                    (#rows > 0) and ("Layout   : %d rows (y %d-%d), x %d-%d, 1 gap per row, left & right stairs"):format(
                        #rows, rows[1], rows[#rows], math.min(Land.X0, Land.X1), math.max(Land.X0, Land.X1))
                        or "Layout   : no rows fit (top Y is too low)",
                    ("Block    : %s | have %d | need %d%s"):format(Build.BlockId and itemName(Build.BlockId) or "-",
                        have, info.need, (info.need > have) and (" (short " .. (info.need - have) .. ")") or " (enough)"),
                    ("Placed   : %d / %d%s"):format(info.done, info.total,
                        info.blocked > 0 and (" | blocked by other blocks: " .. info.blocked) or ""),
                    (info.carve > 0) and ("Dig      : left " .. info.carve .. " tiles (gaps, stairs, background)")
                        or "Dig      : done",
                    "Block seed: " .. (seed and (itemName(seed) .. " x" .. invCount(seed)) or "-"),
                    ("Produce  : harvest %d | plant %d"):format(Build.Harvested, Build.Planted),
                    "Break    : " .. ((Build.BreakX >= 0 and next(Build.Tiles) ~= nil)
                        and ("(" .. Build.BreakX .. "," .. Build.BreakY .. ") | land grid")
                        or "automatic (right of character, near row end)"),
                    "Action   : " .. Build.Status,
                }, "\n")
            else
                txt = "World data not found"
            end
            if UI.LandStatus and txt ~= Build.Shown then
                Build.Shown = txt
                pcall(function() UI.LandStatus:SetDesc(txt) end)
            end
            -- START button on Grid (land mode)
            if UI.GridMode == "land" and UI.GridStart then
                UI.GridStart.Text = Build.Running and "STOP LAND" or "START LAND"
                UI.GridStart.BackgroundColor3 = Build.Running and UI.Palette.Stop or UI.Palette.Action
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: VENDING =====
do (function()
    local VTab = UI.Tabs["Vending"]
    function UI.VendVisible() return not Window.Closed and VTab.Selected == true end

    safe(function()
        UI.VendStatus = VTab:Paragraph({ Title = "Vending Status", Desc = "-" })
    end)

    local vCtl = box(VTab, "Controls", true)
    local vItem = box(VTab, "Pick items", true)
    local vDrop = box(VTab, "Vending drop point", true)

    safe(function()
        UI.VendToggle = vCtl:Toggle({
            Title = "Run Vending",
            Desc = "Run it in your vending world",
            Value = false,
            Callback = function(on)
                if on then Vend.start() elseif Vend.Running then Vend.stop() end
            end,
        })
    end)

    safe(function()
        vCtl:Dropdown({
            Title = "Mode",
            Values = Auto.VEND_MODES,
            Value = Vend.Mode,
            Callback = function(v)
                if type(v) == "table" then v = v[1] end
                if type(v) == "string" then Vend.Mode = v end
            end,
        })
    end)

    safe(function()
        local labels, picked = Vend.labels(Refs.World and Vend.machines() or nil)
        UI.VendItems = vItem:Dropdown({
            Title = "Items to take",
            Desc = "Multi-select. Empty = all items. List: vending contents, backpack & seen drops",
            Values = (#labels > 0) and labels or { "(no items yet)" },
            Value = picked,
            Multi = true,
            AllowNone = true,
            Callback = function(opts)
                local list = {}
                for _, label in ipairs(type(opts) == "table" and opts or { opts }) do
                    local id = tonumber(string.match(tostring(label), "%[(%d+)%]$"))
                    if id then list[#list + 1] = id end
                end
                Vend.Items = list
            end,
        })
    end)

    -- refresh item list if new items appear (vending / bag / drops in world)
    -- Returns: item count, breakdown text (bag / drops / vending), or error message
    function Vend.refreshItems(force, machines)
        if not UI.VendItems then return 0, "dropdown not created yet" end
        local ok, labels, picked, st = pcall(function()
            local m = machines
            if not m and Refs.World then
                local okM, res = pcall(Vend.machines)
                m = okM and res or nil
            end
            return Vend.labels(m)
        end)
        if not ok then
            warn("[n4th] vending item list error: " .. tostring(labels))
            return 0, "error: " .. tostring(labels)
        end
        local info = ("bag %d | drops %d | vending %d"):format(st.inv, st.drop, st.vend)
        local sig = table.concat(labels, "|")
        if not force and sig == Vend.ItemSig then return #labels, info end
        Vend.ItemSig = sig
        UI.later("vendItems", function()
            local okR, errR = UI.exec(function()
                UI.VendItems:Refresh((#labels > 0) and labels or { "(no items yet)" })
            end)
            if not okR then
                Vend.ItemSig = nil
                warn("[n4th] vending item dropdown refresh failed: " .. tostring(errR))
                notify("Vending", "Failed to load item list: " .. tostring(errR), 6)
                return
            end
            if #picked > 0 then UI.exec(function() UI.VendItems:Select(picked) end) end
        end)
        return #labels, info
    end

    safe(function()
        vItem:Button({
            Title = "Reload item list",
            Desc = "Read items from vendings, backpack & drops in this world",
            Callback = function()
                local n, info = Vend.refreshItems(true)
                notify("Vending", ("Item list: %d items (%s)"):format(n, tostring(info)), 5)
            end,
        })
    end)

    safe(function()
        vItem:Button({
            Title = "Add the held item",
            Desc = "Select an item in the game backpack (held), then press. Adds it to the items to take",
            Callback = function()
                local id = nil
                if Refs.Inv then pcall(function() id = tonumber(Refs.Inv.selected) end) end
                local it = id and ItemDB[id]
                if not it or it.kind == "tool" or it.lock then
                    notify("Vending", "Select a block / seed in your in-game bag first (not a tool)", 4)
                    return
                end
                if not table.find(Vend.Items, id) then table.insert(Vend.Items, id) end
                Vend.Seen[id] = true
                Vend.refreshItems(true)
                notify("Vending", "Selected item: " .. itemName(id), 3)
            end,
        })
    end)

    safe(function()
        vItem:Button({
            Title = "Clear item selection",
            Desc = "Back to all items",
            Callback = function()
                table.clear(Vend.Items)
                Vend.ItemSig = nil
                UI.later("vendClear", function() UI.exec(function() UI.VendItems:Select(nil) end) end)
                Vend.refreshItems(true)
                notify("Vending", "Item filter cleared: all items", 3)
            end,
        })
    end)

    safe(function()
        UI.VendPointInput = vDrop:Input({
            Title = "Vending drop point",
            Desc = "WORLD or WORLD:ID (empty = this world). Stock: picks up drops here. Empty: drops here",
            Value = Vend.Point,
            Placeholder = "STORAGE:ID",
            Callback = function(t) Vend.Point = tostring(t or "") end,
        })
    end)

    safe(function()
        vDrop:Button({
            Title = "Save vending drop position (character position)",
            Desc = "Stand at the drop spot (can be in the drop-point world), then press. Used by stock & empty modes",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Vending", "You are not in a world yet", 3)
                    return
                end
                Vend.DropX, Vend.DropY = x, y
                -- auto-fill drop world unless a door ID is already used (WORLD:ID / WORLD|ID)
                local _, door = Vend.point()
                if not door then
                    Vend.Point = Guard.worldName()
                    if UI.VendPointInput then pcall(function() UI.VendPointInput:Set(Vend.Point) end) end
                end
                notify("Vending", ("Vending drop position (%d,%d) in %s"):format(x, y, Vend.Point), 4)
            end,
        })
    end)

    safe(function()
        vDrop:Button({
            Title = "Clear vending drop position",
            Desc = "Drop / wait at the arrival point (door) only",
            Callback = function()
                Vend.DropX, Vend.DropY = -1, -1
                notify("Vending", "Vending drop position cleared", 3)
            end,
        })
    end)

    task.spawn(function()
        while alive() do
            if not Vend.Running and not UI.VendVisible() then task.wait(1) continue end
            local txt
            if Refs.World then
                local list = Vend.machines(true)
                local total, empty = 0, 0
                for _, m in ipairs(list) do
                    if m.id and m.stock > 0 then total += m.stock else empty += 1 end
                end
                local name, door = Vend.point()
                local names = {}
                for i, id in ipairs(Vend.Items) do
                    if i > 4 then
                        names[#names + 1] = "+" .. (#Vend.Items - 4)
                        break
                    end
                    names[#names + 1] = itemName(id)
                end
                if not Vend.Running then Vend.refreshItems(false, list) end
                txt = table.concat({
                    "Status  : " .. (Vend.Running and "RUNNING" or "STOPPED") .. " - " .. Vend.Mode,
                    "Item    : " .. ((#names > 0) and table.concat(names, ", ") or "all sellable items"),
                    ("Vending : %d owned here | stocked %d | empty %d"):format(#list, total, empty),
                    "Point   : " .. ((name ~= "" or door) and (name .. (door and (":" .. door) or "")) or "this world")
                        .. (Vend.DropX >= 0 and (" (" .. Vend.DropX .. "," .. Vend.DropY .. ")") or " (arrival point)"),
                    ("Stats   : stocked +%d | taken %d | dropped %d"):format(Vend.Stocked, Vend.Taken, Vend.Dropped),
                    "Action  : " .. Vend.Status,
                }, "\n")
            else
                txt = "World data not found"
            end
            if UI.VendStatus and txt ~= Vend.Shown then
                Vend.Shown = txt
                pcall(function() UI.VendStatus:SetDesc(txt) end)
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: AUTO ROTASI =====
do (function()
    local PTab = UI.Tabs["Factory"]

    safe(function()
        UI.FactoryStatus = PTab:Paragraph({ Title = "Status Auto Rotasi", Desc = "-" })
    end)

    local pCtl = box(PTab, "Kontrol", true)
    local pBreak = box(PTab, "Posisi & tile break", true)
    local pDrop = box(PTab, "Drop seed", true)

    safe(function()
        UI.FactoryToggle = pCtl:Toggle({
            Title = "Jalankan Auto Rotasi",
            Desc = "Panen dan tanam berurutan dari baris atas; break untuk seed jika diperlukan",
            Value = false,
            Callback = function(on)
                if on then Factory.start() elseif Factory.Running then Factory.stop() end
            end,
        })
    end)

    safe(function()
        UI.FactorySeedDropdown = pCtl:Dropdown({
            Title = "Seed Auto Rotasi",
            Desc = "Block-nya otomatis (contoh: Dirt Seed -> Dirt)",
            Values = { "(memuat...)" },
            Callback = function(opt)
                local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
                if id then Factory.SeedId = id end
            end,
        })
    end)

    safe(function()
        pCtl:Toggle({
            Title = "Tanam di seluruh world",
            Desc = "Mati = hanya di lahan (tab Lahan)",
            Value = Factory.WholeWorld,
            Callback = function(on) Factory.WholeWorld = on end,
        })
    end)

    addNumber(pBreak, {
        Title = "Tile panen kiri & kanan",
        Desc = "2 = berdiri di tengah, pukul panen 2 tile kiri + tengah + 2 tile kanan (5 tile)",
        Min = 1, Max = 4, Step = 1, Default = Factory.SideTiles,
        Callback = function(v) Factory.SideTiles = math.floor(v) end,
    })

    addNumber(pBreak, {
        Title = "Break kalau block sudah",
        Desc = "Panen terus sampai block segini, baru break (sampai block habis)",
        Min = 1, Max = 200, Step = 1, Default = Factory.BreakAt,
        Callback = function(v) Factory.BreakAt = math.floor(v) end,
    })

    addNumber(pBreak, {
        Title = "Jarak collect (tile)",
        Desc = "Setelah panen & tanam: jalan kanan N tile, lalu kiri N tile",
        Min = 0, Max = 5, Step = 1, Default = Factory.CollectDist,
        Callback = function(v) Factory.CollectDist = math.floor(v) end,
    })

    safe(function()
        pBreak:Button({
            Title = "Pakai posisi sekarang untuk break",
            Desc = "Berdiri di tempat break, lalu tekan",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Auto Rotasi", "Kamu belum masuk world", 3)
                    return
                end
                Factory.BreakX, Factory.BreakY = x, y
                notify("Auto Rotasi", ("Posisi break (%d,%d)"):format(x, y), 3)
            end,
        })
    end)

    safe(function()
        pBreak:Button({
            Title = "Pilih tile break (Grid)",
            Desc = "Grid terbuka dalam mode Auto Rotasi (terpisah dari tile Auto Farm)",
            Callback = function()
                if UI.setGridMode then UI.setGridMode("factory") end
                if UI.GridGui then UI.GridGui.Enabled = true end
            end,
        })
    end)

    safe(function()
        pDrop:Toggle({
            Title = "Auto drop seed",
            Desc = "Ke titik drop (Auto Drop → Titik drop bersama)",
            Value = Factory.Drop,
            Callback = function(on) Factory.Drop = on end,
        })
    end)

    addNumber(pDrop, {
        Title = "Sisakan seed",
        Desc = "Untuk ditanam lagi",
        Min = 0, Max = 199, Step = 1, Default = Factory.Keep,
        Callback = function(v) Factory.Keep = math.floor(v) end,
    })

    addNumber(pDrop, {
        Title = "Drop kalau seed sudah",
        Desc = "Contoh 200 & sisakan 50 = drop 150",
        Min = 2, Max = 200, Step = 1, Default = Factory.DropAt,
        Callback = function(v) Factory.DropAt = math.floor(v) end,
    })

    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n += 1 end
        return n
    end

    task.spawn(function()
        while alive() do
            local seed, block = Factory.SeedId, Auto.blockOfSeed(Factory.SeedId)
            local name, door = Auto.parseDropTarget()
            local dropAt = (name ~= "" and name or "world ini") .. (door and (" pintu " .. door) or "")
                .. (Factory.DropX >= 0 and (" (" .. Factory.DropX .. "," .. Factory.DropY .. ")") or "")
            local txt = table.concat({
                "Status : " .. (Factory.Running and ("JALAN - fase " .. tostring(Factory.Phase or "-")) or "BERHENTI"),
                ("Seed   : %s x%d | block %s x%d"):format(seed and itemName(seed) or "-", seed and invCount(seed) or 0,
                    block and itemName(block) or "-", block and invCount(block) or 0),
                ("Break  : %s | tile %d"):format(Factory.BreakX >= 0 and ("(" .. Factory.BreakX .. "," .. Factory.BreakY .. ")")
                    or "belum diatur", countKeys(Factory.Tiles)),
                ("Drop   : %s | sisakan %d, drop saat >= %d"):format(Factory.Drop and dropAt or "mati", Factory.Keep, Factory.DropAt),
                ("Hasil  : panen %d | tanam %d | di-drop %d"):format(Factory.Harvested, Factory.Planted, Factory.Dropped),
                "Aksi   : " .. Factory.Status,
            }, "\n")
            if UI.FactoryStatus and txt ~= Factory.Shown then
                Factory.Shown = txt
                pcall(function() UI.FactoryStatus:SetDesc(txt) end)
            end
            -- tombol START di Grid (mode factory)
            if UI.GridMode == "factory" and UI.GridStart then
                UI.GridStart.Text = Factory.Running and "STOP AUTO ROTASI" or "START AUTO ROTASI"
                UI.GridStart.BackgroundColor3 = Factory.Running and UI.Palette.Stop or UI.Palette.Action
            end
            task.wait(1)
        end
    end)
end)() end

---------------------------------------------------------------------
-- AUTO RECONNECT
---------------------------------------------------------------------
-- How it works:
--   Kicked from world (WorldClosed event from server):
--     snapshot activity -> wait -> re-enter same world -> resume activity.
--   Disconnected from Roblox server (error prompt shown):
--     save activity to file -> rejoin game with target world data
--     (game auto-enters that world) -> script starts again -> resume activity.
--     To reload script after teleport: fill Script URL (queue_on_teleport)
--     or place script in your executor's autoexec folder.
local Rejoin = {
    On = false,
    World = true,       -- rejoin world if kicked from world
    Server = true,      -- rejoin game if disconnected from server
    DelaySec = 5,
    ScriptUrl = "https://raw.githubusercontent.com/ZennJxD/n4th/refs/heads/main/n4th",
    Keep = false,       -- always return to target world if outside a world
    Target = "",        -- target world (empty = last world)
    LastWorld = "",     -- last entered world
    Last = nil,         -- last activity snapshot
    LastAt = 0,
    Busy = false,
    Count = 0,
    Status = "-",
}

do (function()
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")
    local GuiService = game:GetService("GuiService")
    local CoreGui = game:GetService("CoreGui")
    local canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    local PENDING = "n4thOpus/rejoin_" .. tostring(LocalPlayer.UserId) .. ".json"
    local TELEPORT_KEY = "n4th.rejoin.v1"

    local function ensureOpusFolder()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local okF, has = pcall(isfolder, "n4thOpus")
            if okF and not has then pcall(makefolder, "n4thOpus") end
        end
    end

    local function queueScript()
        local q = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        local url = tostring(Rejoin.ScriptUrl or "")
        if type(q) == "function" and string.sub(url, 1, 8) == "https://" then
            return pcall(q, ("if not game:IsLoaded() then game.Loaded:Wait() end; loadstring(game:HttpGet(%q))()"):format(url))
        end
        return false
    end

    local function savePending(world, saved)
        local target = (saved and saved.world ~= "" and saved.world) or world or ""
        if target == "" then return false end
        local data = {
            world = target,
            farm = saved and saved.farm or false,
            clear = saved and saved.clear or false,
            farmer = saved and saved.farmer or false,
            clearTarget = saved and saved.clearTarget or nil,
            spam = saved and saved.spam or false,
            splice = saved and saved.splice or false,
            factory = saved and (saved.factory or saved.pabrik) or false,
            build = saved and saved.build or false,
            tx = saved and saved.tx or nil,
            ty = saved and saved.ty or nil,
            user = LocalPlayer.UserId,
            at = os.time(),
        }
        local wrote = false
        if canFile then
            ensureOpusFolder()
            wrote = pcall(function() writefile(PENDING, HttpService:JSONEncode(data)) end)
        end
        local tpOk = pcall(TeleportService.SetTeleportSetting, TeleportService, TELEPORT_KEY, data)
        return wrote or tpOk
    end

    -- snapshot activity while still running
    task.spawn(function()
        while alive() do
            local now = os.clock()
            if WorldFinder.Busy then task.wait(1) continue end
            local wn = Guard.worldName and Guard.worldName() or ""
            if wn ~= "" and not Factory.Traveling then Rejoin.LastWorld = wn end
            if Guard.anyRunning and Guard.anyRunning() and Guard.Mode == "idle" then
                Rejoin.Last = Guard.snapshot()
                Rejoin.LastAt = now
            elseif now - Rejoin.LastAt > 3 and Guard.Mode == "idle" and wn ~= "" then
                -- still in world when stopped manually: do not resume
                Rejoin.Last = nil
            end
            task.wait(1)
        end
    end)

    local function hasSavedActivity(saved)
        return saved and (saved.farm or saved.clear or saved.farmer or saved.spam
            or saved.splice or saved.factory or saved.pabrik or saved.build or saved.vend)
    end

    local function resume(saved, reason)
        Guard.afterEnter()
        Rejoin.Count += 1
        if hasSavedActivity(saved) then
            Rejoin.Status = "Re-entered successfully, resuming activity"
            notify("Auto Reconnect", reason .. ": resuming activity", 4)
            Hook.send("rejoin", reason .. " to " .. tostring(saved.world) .. ", activity resumed")
            Guard.resumeSaved(saved)
        else
            Rejoin.Status = "Re-entered " .. tostring(saved and saved.world or "") .. " successfully"
            notify("Auto Reconnect", reason .. ": returned to " .. tostring(saved and saved.world or ""), 4)
            Hook.send("rejoin", reason .. " to " .. tostring(saved and saved.world or ""))
        end
    end

    function Rejoin.targetWorld()
        local t = tostring(Rejoin.Target or ""):upper():gsub("[^A-Z0-9]", "")
        if t ~= "" then return t end
        return Rejoin.LastWorld or ""
    end

    local function enterAndResume(world, saved, reason)
        for try = 1, 3 do
            if not alive() then return false end
            local ok, err, hopping = Guard.enterWorld(world)
            if hopping == true then
                savePending(world, saved)
                local queued = queueScript()
                Rejoin.Status = "Server transfer to " .. world .. "..." .. (queued and "" or " (script not queued)")
                Hook.send("rejoin", reason .. " transfer to " .. world)
                return true
            end
            if ok then
                task.wait(1.5)
                if saved and saved.world == world and hasSavedActivity(saved) then
                    resume(saved, reason)
                else
                    Guard.afterEnter()
                    Rejoin.Count += 1
                    Rejoin.Status = reason .. " to " .. world .. " succeeded"
                    Hook.send("rejoin", reason .. " to " .. world)
                end
                return true
            end
            Rejoin.Status = ("Failed to enter %s (%d/3): %s"):format(world, try, tostring(err))
            task.wait(8)
        end
        notify("Auto Rejoin", "Failed to enter " .. world, 5)
        Hook.send("rejoin", "Failed to enter " .. world)
        return false
    end

    -- ===== kicked from world =====
    local function onWorldClosed(msg)
        if not (Rejoin.On and Rejoin.World) or Rejoin.Busy or Rejoin.Leaving or Factory.Traveling or WorldFinder.Busy then return end
        if Guard.Mode == "away" or Guard.Mode == "out" then return end -- Guard initiated the exit
        local saved = Rejoin.Last
        if saved and (saved.world == "" or os.clock() - Rejoin.LastAt > 60) then saved = nil end
        local target = (saved and saved.world ~= "" and saved.world) or Rejoin.targetWorld()
        if target == "" then target = Guard.worldName() end
        if target == "" then return end
        Rejoin.Busy = true
        task.spawn(function()
            local worldBefore = Guard.worldName()
            if Guard.anyRunning() then Guard.stopAll() end
            local text = tostring(msg or ""):gsub("`.", "")
            Rejoin.Status = "Kicked from " .. target .. ". Re-entering..."
            Hook.send("rejoin", "Kicked from world " .. target .. (text ~= "" and (" (" .. text .. ")") or ""))
            task.wait(Rejoin.DelaySec + 1.5) -- wait for door/kick transition to finish
            if alive() and Rejoin.On and Guard.worldName() ~= "" and Guard.worldName() == worldBefore then
                pcall(Guard.leaveWorld)
                task.wait(1.5)
            end
            if alive() and Rejoin.On then
                enterAndResume(target, saved, "Re-entering")
            end
            Rejoin.Busy = false
        end)
    end

    -- game v1159+: WorldClosed arrives via Net (ByteNet) packet, not named RemoteEvent.
    -- Net.on only LISTENS (sends nothing to server). Listeners cannot be detached,
    -- so alive() is checked so an unloaded older script instance stays inactive.
    local closedHooked = false
    if NetOk and type(Net) == "table" and type(Net.on) == "function"
        and type(Net.EVENTS) == "table" and Net.EVENTS.WorldClosed then
        closedHooked = pcall(Net.on, "WorldClosed", function(msg)
            if alive() then onWorldClosed(msg) end
        end, function()
            local w = Refs.World
            return w and rawget(w, "name") or ""
        end)
    end
    if not closedHooked then
        local closed = WorldRemotes and WorldRemotes:FindFirstChild("WorldClosed")
        if closed and closed:IsA("RemoteEvent") then
            table.insert(Connections, closed.OnClientEvent:Connect(function(msg)
                if alive() then onWorldClosed(msg) end
            end))
        end
    end

    function Rejoin.now()
        if Rejoin.Busy then
            notify("Auto Rejoin", "Already entering a world, please wait", 3)
            return
        end
        local world = Rejoin.targetWorld()
        if world == "" then
            notify("Auto Rejoin", "No target world yet. Fill in 'Target world' or enter a world first", 4)
            return
        end
        Rejoin.Busy = true
        task.spawn(function()
            local saved = nil
            if Guard.worldName() ~= "" then
                if Guard.anyRunning() then saved = Guard.snapshot() end
                Guard.stopAll()
                Rejoin.Status = "Leaving world..."
                if not Guard.leaveWorld() then
                    Rejoin.Status = "Failed to leave world"
                    notify("Auto Rejoin", Rejoin.Status, 4)
                    Rejoin.Busy = false
                    return
                end
                task.wait(math.max(2, Rejoin.DelaySec))
            end
            if saved and saved.world ~= world then saved = nil end -- different world: do not resume activity
            Rejoin.Status = "Entering " .. world .. "..."
            enterAndResume(world, saved, "Rejoin")
            Rejoin.Busy = false
        end)
    end

    task.spawn(function()
        local outSince = nil
        while alive() do
            task.wait(2)
            local out = Guard.worldName() == ""
            local free = Rejoin.On and Rejoin.Keep and not Rejoin.Busy and not Rejoin.Leaving and not Factory.Traveling
                and not WorldFinder.Busy and Guard.Mode == "idle"
            if not (out and free) then
                outSince = nil
            else
                outSince = outSince or os.clock()
                local world = Rejoin.targetWorld()
                if world ~= "" and os.clock() - outSince >= Rejoin.DelaySec then
                    outSince = nil
                    Rejoin.Busy = true
                    local saved = Rejoin.Last
                    if saved and (saved.world ~= world or os.clock() - Rejoin.LastAt > 600) then saved = nil end
                    Rejoin.Status = "Outside world, entering " .. world .. "..."
                    enterAndResume(world, saved, "Auto return")
                    Rejoin.Busy = false
                end
            end
        end
    end)

    -- ===== disconnected from server =====
    local function onDisconnect(msg)
        if not (Rejoin.On and Rejoin.Server) or Rejoin.Leaving then return end
        Rejoin.Leaving = true
        local finderActive = WorldFinder.Busy and WorldFinder.Running and not WorldFinder.Cancelled
        local saved = not finderActive and (Rejoin.Last or (Guard.anyRunning() and Guard.snapshot())) or nil
        local world = finderActive and WorldFinder.Queue and WorldFinder.Queue[WorldFinder.Index]
            or (saved and saved.world or Rejoin.targetWorld())
        if world == "" then world = Guard.worldName() end
        if not finderActive and (saved or world ~= "") then
            savePending(world, saved)
        end
        local queued
        if finderActive and WorldFinder.armTeleport then queued = WorldFinder.armTeleport()
        else queued = queueScript() end
        Rejoin.Status = "Disconnected: rejoining..." .. (queued and "" or " (script not queued)")
        Hook.send("rejoin", "Disconnected from server (" .. tostring(msg) .. "). Rejoining to " .. (world ~= "" and world or "game"))
        task.spawn(function()
            task.wait(Rejoin.DelaySec)
            while alive() do
                -- Roblox blocks client-supplied teleportData on Teleport(); rely on PENDING / SetTeleportSetting instead.
                local ok = pcall(function()
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                end)
                if not ok then
                    pcall(function() TeleportService:Teleport(game.PlaceId) end)
                end
                task.wait(15) -- still not teleported: retry
            end
        end)
    end

    pcall(function()
        table.insert(Connections, GuiService.ErrorMessageChanged:Connect(function(msg)
            if alive() and type(msg) == "string" and msg ~= "" then onDisconnect(msg) end
        end))
        local okE, existingErr = pcall(function() return GuiService:GetErrorMessage() end)
        if okE and type(existingErr) == "string" and existingErr ~= "" then
            task.defer(onDisconnect, existingErr)
        end
    end)

    pcall(function()
        local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
        local overlay = promptGui and promptGui:FindFirstChild("promptOverlay")
        if overlay then
            local function checkPrompt(child)
                if alive() and child and child.Name == "ErrorPrompt" then
                    local okMsg, errMsg = pcall(function() return GuiService:GetErrorMessage() end)
                    onDisconnect((okMsg and errMsg and errMsg ~= "") and errMsg or "Connection error prompt")
                end
            end
            table.insert(Connections, overlay.ChildAdded:Connect(checkPrompt))
            local existingPrompt = overlay:FindFirstChild("ErrorPrompt")
            if existingPrompt then task.defer(checkPrompt, existingPrompt) end
        end
    end)

    -- ===== post-execute: resume from rejoin snapshot =====
    function Rejoin.startup(reconnectFn)
        local saved = nil
        if canFile then
            local okE, has = pcall(isfile, PENDING)
            if okE and has then
                local okR, raw = pcall(readfile, PENDING)
                if type(delfile) == "function" then pcall(delfile, PENDING) end
                if okR and type(raw) == "string" then
                    local okD, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
                    if okD and type(decoded) == "table" then saved = decoded end
                end
            end
        end
        if not saved then
            local okT, tpData = pcall(TeleportService.GetTeleportSetting, TeleportService, TELEPORT_KEY)
            if okT and type(tpData) == "table" then saved = tpData end
        end
        pcall(TeleportService.SetTeleportSetting, TeleportService, TELEPORT_KEY, false)
        if type(saved) ~= "table" or type(saved.world) ~= "string" or saved.world == "" then return end
        if saved.user and saved.user ~= LocalPlayer.UserId then return end
        if os.time() - (tonumber(saved.at) or 0) > 15 * 60 then return end -- expired
        Rejoin.Busy = true
        Rejoin.Status = "Rejoin: waiting to enter " .. saved.world
        local t0 = os.clock()
        local lastTryAt, tries = -10, 0
        while alive() and os.clock() - t0 < 60 do
            if Refs.World and Guard.worldName():upper() == saved.world:upper() and Auto.here() then break end
            if not Refs.World then pcall(reconnectFn) end
            if Refs.World and tries < 3 and os.clock() - lastTryAt >= 10 then
                lastTryAt = os.clock()
                tries += 1
                Guard.enterWorld(saved.world)
            end
            task.wait(2)
        end
        if alive() and Guard.worldName():upper() == saved.world:upper() then
            pcall(reconnectFn)
            task.wait(1)
            resume(saved, "Rejoin server")
        else
            Rejoin.Status = "Rejoin: failed to enter " .. saved.world
            Hook.send("rejoin", Rejoin.Status)
        end
        Rejoin.Busy = false
    end
end)() end

Config.add("Reconnect", Rejoin, { "On", "World", "Server", "DelaySec", "ScriptUrl", "Keep", "Target" })
Config.add("Discord", Hook, { "On", "Url", "Guard", "Stop", "Full", "Bonus", "Rejoin", "Factory", "Finder", "ReportMin" })

-- WORLD FINDER: enter worlds and verify the entire foreground before marking unlocked.
do
    local modes = { "Mixed", "3 letters", "4 letters", "Indonesian words", "English Words", "BUY + Item", "Custom list" }
    WorldFinder.Modes = modes
    function WorldFinder.log(message)
        WorldFinder.Status = tostring(message)
        WorldFinder.Logs[#WorldFinder.Logs + 1] = os.date("%H:%M:%S") .. "  " .. tostring(message):gsub("\n", " | ")
        if #WorldFinder.Logs > 100 then table.remove(WorldFinder.Logs, 1) end
    end

    -- Only persists Finder's own queue. Does not probe worlds externally.
    local teleport = game:GetService("TeleportService")
    local pendingKey = "n4th.finder.teleport.v1"
    local bootSource = [=[
local globals = (getgenv and getgenv()) or _G
if not globals.__n4thFinderBooting then
    globals.__n4thFinderBooting = true
    task.spawn(function()
        if not game:IsLoaded() then game.Loaded:Wait() end
        local players = game:GetService("Players")
        local deadline = os.clock() + 30
        while not players.LocalPlayer and os.clock() < deadline do task.wait(0.1) end
        local player = players.LocalPlayer
        local ts = game:GetService("TeleportService")
        local ok, data = pcall(ts.GetTeleportSetting, ts, "n4th.finder.teleport.v1")
        local ran, err = true, nil
        if ok and type(data) == "table" and data.Active == true and data.Schema == 1
            and data.Universe == game.GameId and data.Job ~= game.JobId
            and player and data.User == player.UserId and type(data.At) == "number"
            and os.time() - data.At >= 0 and os.time() - data.At < 600 then
            ran, err = pcall(function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/ZennJxD/n4th/refs/heads/main/n4th"))()
            end)
        end
        globals.__n4thFinderBooting = nil
        if not ran then warn("[n4th] Failed to resume after teleport: " .. tostring(err)) end
    end)
end
]=]

    function WorldFinder.checkpoint(active)
        local data = false
        if active and WorldFinder.Queue then
            data = {
                Schema = 1, Active = true, At = os.time(), User = LocalPlayer.UserId,
                Universe = game.GameId, Job = game.JobId,
                Queue = table.clone(WorldFinder.Queue), Index = WorldFinder.Index,
                Checked = WorldFinder.Checked, Found = WorldFinder.Found, Locked = WorldFinder.Locked,
                Unknown = WorldFinder.Unknown, Failed = WorldFinder.Failed,
                Results = table.clone(WorldFinder.Results), FoundNames = table.clone(WorldFinder.FoundNames),
                Logs = table.clone(WorldFinder.Logs), DelaySec = WorldFinder.DelaySec,
                WebhookEach = WorldFinder.WebhookEach,
                Hook = { On = Hook.On, Url = Hook.Url, Finder = Hook.Finder },
            }
        end
        local ok, err = pcall(teleport.SetTeleportSetting, teleport, pendingKey, data)
        WorldFinder.CheckpointOK = ok
        return ok, err
    end

    function WorldFinder.armTeleport()
        local saved, reason = WorldFinder.checkpoint(true)
        if not saved then return false, "Failed to save teleport queue: " .. tostring(reason) end
        if WorldFinder.Queued then return true end
        local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        if type(queue) ~= "function" then return false, "Executor does not support auto-execute after teleport. Execute n4th again to continue." end
        local ok, err = pcall(queue, bootSource)
        WorldFinder.Queued = ok
        return ok, not ok and ("Failed to set up auto-execute: " .. tostring(err)) or nil
    end

    pcall(function()
        table.insert(Connections, LocalPlayer.OnTeleport:Connect(function(state)
            if not alive() then return end
            if state == Enum.TeleportState.Failed then
                WorldFinder.Teleporting, WorldFinder.Queued = false, false
                if WorldFinder.Running then WorldFinder.log("Teleport failed. Waiting for world entry result.") end
            elseif WorldFinder.Running and not WorldFinder.Cancelled and WorldFinder.Busy
                and (state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress
                    or state == Enum.TeleportState.WaitingForServer) then
                WorldFinder.Teleporting = true
                WorldFinder.log("Server teleport. Queue will resume once the game loads.")
                local ok, err = WorldFinder.armTeleport()
                if not ok then WorldFinder.log(err) end
            end
        end))
    end)

    function WorldFinder.startup(reconnectFn)
        local ok, data = pcall(teleport.GetTeleportSetting, teleport, pendingKey)
        if not ok or type(data) ~= "table" or data.Active ~= true or data.Job == game.JobId then return false end
        local valid = data.Schema == 1 and data.Universe == game.GameId and data.User == LocalPlayer.UserId
            and type(data.At) == "number" and os.time() - data.At >= 0 and os.time() - data.At < 600
            and type(data.Queue) == "table" and #data.Queue > 0 and #data.Queue <= 500
            and type(data.Index) == "number" and data.Index % 1 == 0 and data.Index >= 1 and data.Index <= #data.Queue
        if valid then
            for _, name in ipairs(data.Queue) do
                if type(name) ~= "string" or WorldFinder.name(name) ~= name then valid = false break end
            end
        end
        WorldFinder.checkpoint(false) -- one-shot; start() creates a new checkpoint
        if not valid then WorldFinder.log("Teleport queue expired or invalid. Starting a new search.") return false end
        local deadline = os.clock() + 45
        while alive() and os.clock() < deadline do
            if Session.Ready and Refs.World then return WorldFinder.start(nil, data) == true end
            if Session.Ready then pcall(reconnectFn) end
            task.wait(1)
        end
        WorldFinder.log("Cannot resume: game references unavailable. Connect to game and start again.")
        return false
    end
    local wordsID = "API AIR AKU AWAN AYAM BATU BINTANG BIRU BUKU BUMI BUNGA CAHAYA CINTA DAUN DEWA EMAS GARAM GULA GUNUNG HATI HUJAN IKAN INDAH JALAN KAYU KOPI KOTA KUCING LANGIT LAUT MADU MALAM MATA MIMPI NAGA NASI OMBAK PAGI PASIR PELANGI PINTU POHON PULAU RAJA RATU RUMAH SABUN SATU SAYUR SENJA SUSU TANAH TIGA TIMUR UANG UJIAN ULAR UTARA WARNA WAKTU"
    local wordsEN = "AIR APPLE ASH AURA BEACH BIRD BLUE BOOK BREAD BRICK CANDY CLOUD COIN CORAL CROWN DAWN DOOR DREAM DUSK EARTH EAST FIRE FISH FLAME FLOWER FOREST FROST GAME GARDEN GEM GLASS GOLD GREEN HOME HONEY ICE ISLAND JADE KING LAKE LEAF LIGHT LION LOVE LUCK MAGIC MAPLE MILK MINT MOON NIGHT NORTH OCEAN PEARL PINK PLANT RAIN RED RIVER ROSE SAND SEED SILK SKY SNOW SOUL STAR STONE SUN TREE WATER WEST WIND WOLF WOOD"
    local buyWords = "SEED SEEDS BLOCK BLOCKS FARM DIRT STONE WOOD LAVA DOOR LOCK WL DL BGL GEMS WATER SAND GLASS FLOWER TREE APPLE GRASS ROCK BRICK PLATFORM PICKAXE WINGS FIST RAYMAN CLOTHES HAT SHIRT PANTS SHOES HAND"

    function WorldFinder.name(raw)
        local name = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
        name = name:gsub("^/[Ww][Aa][Rr][Pp]%s+", ""):upper()
        if name == "" or not name:match("^[A-Z0-9]+$") then return nil end
        return name
    end

    local function words(text, prefix)
        local out = {}
        for name in text:upper():gmatch("[A-Z0-9]+") do out[#out + 1] = (prefix or "") .. name end
        return out
    end

    local function shortNames(length, count)
        local out, space = {}, 26 ^ length
        local start = math.random(0, space - 1)
        for index = 0, math.min(count, space) - 1 do
            local value, chars = (start + index * 137) % space, {}
            for pos = length, 1, -1 do
                chars[pos] = string.char(65 + value % 26)
                value = math.floor(value / 26)
            end
            out[#out + 1] = table.concat(chars)
        end
        return out
    end

    function WorldFinder.candidates(mode, limit, custom)
        limit = math.clamp(math.floor(tonumber(limit) or 100), 1, 500)
        local customNames = {}
        local cleaned = tostring(custom or ""):gsub("/[Ww][Aa][Rr][Pp]%s+", "")
        for entry in cleaned:gmatch("[^%s,;]+") do
            local name = WorldFinder.name(entry)
            if name then customNames[#customNames + 1] = name end
        end
        local pools = {
            ["3 letters"] = shortNames(3, limit), ["4 letters"] = shortNames(4, limit),
            ["Indonesian words"] = words(wordsID), ["English Words"] = words(wordsEN),
            ["BUY + Item"] = words(buyWords, "BUY"), ["Custom list"] = customNames,
        }
        local selected = mode == "Mixed"
            and { pools["3 letters"], pools["4 letters"], pools["Indonesian words"], pools["English Words"], pools["BUY + Item"], customNames }
            or { pools[mode] or {} }
        local out, seen, index = {}, {}, 1
        while #out < limit do
            local hasEntry = false
            for _, pool in ipairs(selected) do
                local name = pool[index]
                if name then
                    hasEntry = true
                    if not seen[name] then out[#out + 1], seen[name] = name, true end
                end
                if #out >= limit then break end
            end
            if not hasEntry then break end
            index += 1
        end
        return out
    end

    local function metadataLock(lock)
        if lock == nil or lock == false or lock == "" or lock == "0" or (type(lock) == "number" and lock <= 0) then return false, false end
        if type(lock) ~= "table" then return true, false end
        local owners = { owner = true, ownerId = true, ownerID = true, userId = true, uid = true }
        local flags = { locked = true, isLocked = true, claimed = true }
        local unknown = false
        for key, value in pairs(lock) do
            if owners[key] then
                if type(value) == "number" and value > 0 then return true, false end
                if type(value) == "string" and value ~= "" and value ~= "0" then return true, false end
                if type(value) ~= "number" and value ~= false and value ~= "" and value ~= "0" then unknown = true end
            elseif flags[key] and value == true then
                return true, false
            elseif value ~= false and value ~= 0 and value ~= "" and type(value) ~= "function"
                and not (type(value) == "table" and next(value) == nil) then
                unknown = true
            end
        end
        return false, unknown
    end

    function WorldFinder.inspect(w, expected)
        local result = { kind = "unknown", detail = "Incomplete world data" }
        if type(w) ~= "table" or rawget(w, "name") ~= expected then return result end
        local width, height, grid = rawget(w, "w"), rawget(w, "h"), rawget(w, "fg")
        if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0
            or width % 1 ~= 0 or height % 1 ~= 0 or type(grid) ~= "table" then return result end
        local lockCounts, missing, nonzero, checksum = {}, false, 0, 0
        local lockNames = { worldlock = true, smalllock = true, biglock = true, hugelock = true }
        for y = 0, height - 1 do
            local row = grid[y]
            if type(row) ~= "table" then
                missing = true
            else
                for x = 0, width - 1 do
                    local id = row[x] or 0
                    if type(id) ~= "number" then
                        missing = true
                    elseif id ~= 0 then
                        nonzero += 1
                        checksum = (checksum + id * (1 + y * width + x)) % 2147483647
                        local item = ItemDB[id]
                        if type(item) ~= "table" then
                            missing = true
                        else
                            local name = tostring(item.name or ("Item " .. id))
                            if item.lock or item.area or item.guildLock or lockNames[name:lower():gsub("[^a-z]", "")] then
                                lockCounts[name] = (lockCounts[name] or 0) + 1
                            end
                        end
                    end
                end
            end
        end
        local labels = {}
        for name, count in pairs(lockCounts) do labels[#labels + 1] = name .. " x" .. count end
        table.sort(labels)
        local hasOwner, unknownMetadata = metadataLock(rawget(w, "lock"))
        if #labels > 0 or hasOwner then
            result.kind, result.detail = "locked", #labels > 0 and table.concat(labels, ", ") or "World lock detected from owner metadata"
        elseif not missing and not unknownMetadata and nonzero > 0 then
            result.kind, result.detail = "unlocked", "No world lock or area lock in foreground or world metadata"
        elseif unknownMetadata then
            result.detail = "Unrecognized lock metadata format"
        end
        result.fingerprint = result.kind .. ":" .. result.detail .. ":" .. nonzero .. ":" .. checksum
        return result
    end

    local function waitFor(seconds, live)
        local untilTime = os.clock() + seconds
        while live() and os.clock() < untilTime do task.wait(math.min(0.1, untilTime - os.clock())) end
        return live()
    end

    function WorldFinder.warp(name, live)
        if not live() then return false, "Stopped" end
        if Guard.worldName() == name and Auto.here() then return true end
        local armed, armError = WorldFinder.armTeleport()
        if not armed then WorldFinder.log(armError) end
        local function waitTeleport()
            local deadline = os.clock() + 60
            while live() and WorldFinder.Teleporting and os.clock() < deadline do task.wait(0.25) end
            if live() and WorldFinder.Teleporting then
                WorldFinder.stop()
                WorldFinder.log("Teleport took too long. Search stopped to prevent queue desync.")
            end
            return live()
        end
        if Guard.worldName() ~= "" then
            WorldFinder.log("Leaving " .. Guard.worldName())
            if not Guard.leaveWorld() then return false, "Failed to leave current world" end
            if not waitFor(2, live) then return false, "Stopped" end
            if not waitTeleport() then return false, "Stopped" end
        end
        if not live() then return false, "Stopped" end
        WorldFinder.log("Entering " .. name .. " to inspect locks")
        local ok, reason, hopping = Guard.enterWorld(name)
        if hopping == true then
            WorldFinder.Teleporting = true
            WorldFinder.log("Game requested server transfer to " .. name .. ". Waiting for teleport.")
        end
        if not waitTeleport() then return false, "Stopped" end
        if not live() then return false, "Stopped" end
        if not ok then return false, tostring(reason or "World cannot be entered") end
        if not waitFor(1.5, live) then return false, "Stopped" end
        pcall(Guard.afterEnter)
        return Guard.worldName() == name, "Destination world not readable yet"
    end

    local function inspectLoaded(name, live)
        WorldFinder.log("Checking locks in " .. name .. ". Waiting for full data.")
        local deadline, previous, previousGrid = os.clock() + 6, nil, nil
        local result = { kind = "unknown", detail = "Incomplete world data" }
        while live() and os.clock() < deadline do
            local w = Refs.World
            result = WorldFinder.inspect(w, name)
            if Auto.here() and result.kind ~= "unknown" and previous == result.fingerprint and previousGrid == w.fg then return result end
            previous, previousGrid = result.fingerprint, w and w.fg
            if not waitFor(0.4, live) then break end
        end
        if result.kind ~= "unknown" then return { kind = "unknown", detail = "World data not stable yet" } end
        return result
    end

    function WorldFinder.record(name, result)
        WorldFinder.Checked += 1
        local labels = { unlocked = "UNLOCKED", locked = "LOCKED", unknown = "UNKNOWN", failed = "FAILED TO ENTER" }
        if result.kind == "unlocked" then
            WorldFinder.Found += 1
            WorldFinder.FoundNames[#WorldFinder.FoundNames + 1] = name
        elseif result.kind == "locked" then WorldFinder.Locked += 1
        elseif result.kind == "failed" then WorldFinder.Failed += 1
        else WorldFinder.Unknown += 1 end
        local message = name .. " | " .. (labels[result.kind] or labels.unknown) .. " | " .. result.detail
        WorldFinder.Results[#WorldFinder.Results + 1] = message
        WorldFinder.log(message)
        if result.kind == "unlocked" or WorldFinder.WebhookEach then Hook.send("finder", ("World Finder\n" .. message):sub(1, 1600)) end
        if result.kind == "unlocked" then notify("World Finder", message, 10) end
    end

    function WorldFinder.stop()
        WorldFinder.Running = false
        WorldFinder.checkpoint(false)
        if WorldFinder.Busy then WorldFinder.log("Stop requested. Waiting for active step to finish.") end
    end

    function WorldFinder.start(manual, pending)
        if WorldFinder.Busy then return end
        if not Session.Ready or not Refs.World or not Guard.enterWorld then notify("World Finder", "Connect to game first", 4) return end
        if AutoDrop.Busy or Factory.Traveling or Rejoin.Busy or Guard.Mode ~= "idle" then
            notify("World Finder", "Wait for automatic trip to finish", 4)
            return
        end
        local queue
        if pending then
            queue = pending.Queue
        elseif manual then
            local name = WorldFinder.name(manual)
            if not name then notify("World Finder", "World names use letters A-Z and digits 0-9", 4) return end
            queue = { name }
        else
            queue = WorldFinder.candidates(WorldFinder.Mode, WorldFinder.Limit, WorldFinder.Custom)
        end
        if #queue == 0 then notify("World Finder", "World name list is empty", 4) return end
        WorldFinder.Saved = Guard.snapshot()
        WorldFinder.Running, WorldFinder.Busy, WorldFinder.Cancelled = true, true, false
        WorldFinder.Queue, WorldFinder.Index, WorldFinder.Teleporting = queue, pending and pending.Index or 1, false
        WorldFinder.Checked, WorldFinder.Found, WorldFinder.Locked, WorldFinder.Unknown, WorldFinder.Failed = 0, 0, 0, 0, 0
        WorldFinder.Results, WorldFinder.FoundNames = {}, {}
        if pending then
            for _, key in ipairs({ "Checked", "Found", "Locked", "Unknown", "Failed" }) do
                WorldFinder[key] = math.max(0, math.floor(tonumber(pending[key]) or 0))
            end
            for _, key in ipairs({ "Results", "FoundNames", "Logs" }) do
                WorldFinder[key] = type(pending[key]) == "table" and pending[key] or {}
            end
            WorldFinder.DelaySec = math.clamp(tonumber(pending.DelaySec) or 8, 5, 60)
            WorldFinder.WebhookEach = pending.WebhookEach == true
            if type(pending.Hook) == "table" then
                Hook.On, Hook.Finder = pending.Hook.On == true, pending.Hook.Finder == true
                if type(pending.Hook.Url) == "string" then Hook.Url = pending.Hook.Url end
            end
        end
        WorldFinder.Total = #queue
        if pending then
            WorldFinder.log(("Resumed after teleport: %d/%d, target %s."):format(WorldFinder.Index, #queue, queue[WorldFinder.Index]))
        else
            WorldFinder.log(("Starting %s. %d names will be checked."):format(manual and "manual check" or "search", #queue))
        end
        WorldFinder.log("Lock data is read after entering each world.")
        local token = Guard.Token
        local function live()
            return alive() and WorldFinder.Running and not WorldFinder.Cancelled and Guard.Token == token and Guard.Mode == "idle"
        end
        local paused, pauseError = pcall(Guard.stopAll, nil, true)
        if not paused then
            WorldFinder.Running, WorldFinder.Busy, WorldFinder.Saved = false, false, nil
            WorldFinder.log("Failed to stop farming: " .. tostring(pauseError))
            notify("World Finder", WorldFinder.Status, 5)
            return
        end
        Rejoin.Last, Rejoin.LastAt = nil, 0
        pcall(Config.save, true)
        local armed, armError = WorldFinder.armTeleport()
        WorldFinder.log(armed and "Auto-resume after teleport is armed." or armError)
        task.spawn(function()
            local ok, reason = pcall(function()
                if not waitFor(1.2, live) then return end
                for index = WorldFinder.Index, #queue do
                    local name = queue[index]
                    if not live() then break end
                    WorldFinder.Index = index
                    WorldFinder.checkpoint(true)
                    WorldFinder.log(("Checking %d/%d: %s"):format(index, #queue, name))
                    local entered, message = WorldFinder.warp(name, live)
                    if not live() then break end
                    local result = entered and inspectLoaded(name, live) or { kind = "failed", detail = message }
                    if not live() then break end
                    WorldFinder.record(name, result)
                    if result.kind == "unlocked" then
                        WorldFinder.checkpoint(false)
                        WorldFinder.log("Found an unlocked world. Staying in " .. name .. ".")
                        break
                    end
                    if index < #queue then
                        WorldFinder.Index = index + 1
                        WorldFinder.checkpoint(true)
                        local delay = math.max(5, tonumber(WorldFinder.DelaySec) or 8)
                        WorldFinder.log(("Waiting %d seconds, then checking %s"):format(delay, queue[index + 1]))
                        if not waitFor(delay, live) then break end
                    end
                end
            end)
            local finished = live()
            WorldFinder.Running, WorldFinder.Busy, WorldFinder.Saved = false, false, nil
            WorldFinder.checkpoint(false)
            local foundPreview = {}
            for index = 1, math.min(10, #WorldFinder.FoundNames) do foundPreview[#foundPreview + 1] = WorldFinder.FoundNames[index] end
            if #WorldFinder.FoundNames > 10 then foundPreview[#foundPreview + 1] = "+" .. (#WorldFinder.FoundNames - 10) .. " more" end
            local outcome = WorldFinder.Found > 0 and ("Found: " .. table.concat(foundPreview, ", "))
                or "No verified unlocked worlds found"
            local summary = ("%s\nChecked %d | Unlocked %d | Locked %d | Unknown %d | Failed %d"):format(
                outcome, WorldFinder.Checked, WorldFinder.Found, WorldFinder.Locked, WorldFinder.Unknown, WorldFinder.Failed)
            if not ok then summary = "Hunting failed: " .. tostring(reason) .. "\n" .. summary
            elseif not finished then summary = "Hunting stopped\n" .. summary end
            WorldFinder.log(summary)
            if alive() then
                Hook.send("finder", ("World Finder\n" .. summary):sub(1, 1600))
                notify("World Finder", summary, 8)
            end
            if UI.FinderToggle then UI.later("finderOff", function() UI.FinderToggle:Set(false) end) end
        end)
        return true
    end
end

-- ===== TAB: WORLD FINDER =====
do (function()
    local tab = UI.Tabs["World Finder"]
    safe(function() UI.FinderStatus = tab:Paragraph({ Title = "Current task", Desc = WorldFinder.Status }) end)
    safe(function() UI.FinderLogs = tab:Paragraph({ Title = "Latest logs", Desc = "No activity yet" }) end)
    safe(function()
        tab:Button({
            Title = "Copy logs",
            Desc = "Copy the activity history to review or share",
            Callback = function()
                if type(setclipboard) ~= "function" then notify("World Finder", "Executor does not support clipboard", 3) return end
                local ok = pcall(setclipboard, table.concat(WorldFinder.Logs, "\n"))
                notify("World Finder", ok and "Logs copied" or "Failed to copy logs", 3)
            end,
        })
    end)
    local controls = box(tab, "Find unlocked worlds", true)
    local settings = box(tab, "Search settings", false)
    local manualBox = box(tab, "Manual travel", false)
    local webhookBox = box(tab, "Discord Notifications", false)

    safe(function()
        controls:Dropdown({
            Title = "Name type",
            Desc = "Choose short names, words, BUY names, or your own list",
            Values = WorldFinder.Modes,
            Value = WorldFinder.Mode,
            Callback = function(value)
                if type(value) == "table" then value = value[1] end
                if table.find(WorldFinder.Modes, value) then WorldFinder.Mode = value end
            end,
        })
    end)
    safe(function()
        controls:Input({
            Title = "World list",
            Desc = "For Custom list mode. Separate names with commas.",
            Value = WorldFinder.Custom,
            Placeholder = "BUYSEED, SKY, DREAM",
            Callback = function(value) WorldFinder.Custom = tostring(value or "") end,
        })
    end)
    safe(function()
        controls:Button({
            Title = "Start search",
            Desc = "Enter candidates to check locks. Stop when an unlocked world is found.",
            Callback = function() WorldFinder.start() end,
        })
    end)
    safe(function()
        controls:Button({
            Title = "Stop",
            Desc = "Finish the current operation and stop in the last world",
            Callback = WorldFinder.stop,
        })
    end)
    addNumber(settings, {
        Title = "World count",
        Desc = "Maximum names to check in one search",
        Min = 1, Max = 500, Step = 1, Default = WorldFinder.Limit,
        Callback = function(value) WorldFinder.Limit = math.floor(value) end,
    })
    addNumber(settings, {
        Title = "Search delay (seconds)",
        Desc = "Wait before checking the next candidate",
        Min = 5, Max = 60, Step = 1, Default = WorldFinder.DelaySec,
        Callback = function(value) WorldFinder.DelaySec = math.floor(value) end,
    })
    safe(function()
        manualBox:Input({
            Title = "World name",
            Desc = "Enter a world name. You can also use /warp BUYSEED.",
            Value = WorldFinder.Manual,
            Placeholder = "BUYSEED",
            Callback = function(value) WorldFinder.Manual = tostring(value or "") end,
        })
    end)
    safe(function()
        manualBox:Button({
            Title = "Travel & check",
            Desc = "Enter the specified world and show its lock status",
            Callback = function() WorldFinder.start(WorldFinder.Manual) end,
        })
    end)
    safe(function()
        manualBox:Button({
            Title = "Check this world",
            Desc = "Check locks in your current world",
            Callback = function()
                local name = Guard.worldName()
                if name == "" then notify("World Finder", "You are not in a world yet", 4) return end
                WorldFinder.start(name)
            end,
        })
    end)
    safe(function()
        webhookBox:Input({
            Title = "Webhook URL",
            Desc = "Paste the destination Discord channel webhook",
            Value = Hook.Url,
            Placeholder = "https://discord.com/api/webhooks/...",
            Callback = function(value)
                value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if value ~= "" and not Hook.valid(value) then notify("World Finder", "Invalid webhook URL", 4) return end
                Hook.Url = value
            end,
        })
    end)
    safe(function()
        UI.FinderWebhook = webhookBox:Toggle({
            Title = "Send results to Discord",
            Desc = "Send worlds found and the search summary",
            Value = Hook.On and Hook.Finder,
            Callback = function(on)
                if on and not Hook.valid(Hook.Url) then
                    notify("World Finder", "Fill in the webhook URL first", 4)
                    UI.later("finderWebhookOff", function() UI.FinderWebhook:Set(false) end)
                    return
                end
                Hook.Finder = on
                if on then Hook.On = true end
            end,
        })
    end)
    safe(function()
        webhookBox:Toggle({
            Title = "Send every result",
            Desc = "Include locked candidates and failed checks",
            Value = WorldFinder.WebhookEach,
            Callback = function(on) WorldFinder.WebhookEach = on end,
        })
    end)
    safe(function()
        webhookBox:Button({
            Title = "Test notification",
            Desc = "Send a test message to Discord",
            Callback = function()
                if not (Hook.On and Hook.Finder and Hook.valid(Hook.Url)) then
                    notify("World Finder", "Enable notifications and enter a webhook URL first", 4)
                    return
                end
                Hook.send("finder", "World Finder is ready to send search results from n4th")
                notify("World Finder", "Test message queued", 3)
            end,
        })
    end)
    task.spawn(function()
        local lastStatus, lastLogs
        while alive() do
            if UI.FinderStatus and WorldFinder.Status ~= lastStatus then
                local text = WorldFinder.Status
                lastStatus = text
                UI.later("finderStatus", function() UI.FinderStatus:SetDesc(text) end)
            end
            local recent = {}
            for index = #WorldFinder.Logs, math.max(1, #WorldFinder.Logs - 11), -1 do
                recent[#recent + 1] = WorldFinder.Logs[index]
            end
            local text = #recent > 0 and table.concat(recent, "\n") or "No activity yet"
            if UI.FinderLogs and text ~= lastLogs then
                lastLogs = text
                UI.later("finderLogs", function() UI.FinderLogs:SetDesc(text) end)
            end
            task.wait(0.5)
        end
    end)
end)() end

-- ===== TAB: DROP POINT (used by Factory, Farmer, Auto Farm) =====
do (function()
    local dBox = box(UI.Tabs["Auto Drop"], "Shared drop point", false)

    safe(function()
        UI.DropPointStatus = dBox:Paragraph({ Title = "Drop Point", Desc = "-" })
    end)

    safe(function()
        UI.DropWorldInput = dBox:Input({
            Title = "Drop world",
            Desc = "Empty = this world | WORLD | WORLD:ID (enter via door ID)",
            Value = Factory.DropWorld,
            Placeholder = "STORAGE:1",
            Callback = function(t) Factory.DropWorld = tostring(t or "") end,
        })
    end)

    safe(function()
        dBox:Button({
            Title = "Use current position for dropping",
            Desc = "Stand at the drop spot (can be another world), then press",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Drop Point", "You are not in a world yet", 3)
                    return
                end
                Factory.DropX, Factory.DropY = x, y
                -- auto-fill world unless already formatted as WORLD:ID
                if not string.find(Factory.DropWorld or "", ":", 1, true) then
                    Factory.DropWorld = Guard.worldName()
                    if UI.DropWorldInput then pcall(function() UI.DropWorldInput:Set(Factory.DropWorld) end) end
                end
                notify("Drop Point", ("Drop position (%d,%d) in %s"):format(x, y, Factory.DropWorld), 4)
            end,
        })
    end)

    safe(function()
        dBox:Button({
            Title = "Clear drop position",
            Desc = "Drop at the arrival point (door) instead",
            Callback = function()
                Factory.DropX, Factory.DropY = -1, -1
                notify("Drop Point", "Drop position cleared", 3)
            end,
        })
    end)

    task.spawn(function()
        while alive() do
            local name, door = Auto.parseDropTarget()
            local here = Guard.worldName()
            local point
            if Factory.DropX < 0 and not door and (name == "" or name == here) then
                point = "not set"
            else
                point = (name ~= "" and name or "this world") .. (door and (" door " .. door) or "")
                    .. (Factory.DropX >= 0 and (" (" .. Factory.DropX .. "," .. Factory.DropY .. ")") or " (arrival point)")
            end
            local txt = table.concat({
                "Point  : " .. point,
                "Used by: Factory (seeds), Farmer & Auto Farm (auto when stack ~190)",
                ("Dropped: Factory %d | Farmer %d | Auto Farm %d"):format(Factory.Dropped, Farmer.Dropped, State.Dropped),
                "Note: drops at this spot are excluded from collection",
            }, "\n")
            if UI.DropPointStatus and txt ~= UI.DropPointShown then
                UI.DropPointShown = txt
                pcall(function() UI.DropPointStatus:SetDesc(txt) end)
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: GENERAL =====
local ConnTab = UI.Tabs.Settings

Box.ConnMain = box(ConnTab, "Connection", true)
Box.ConnCfg = box(ConnTab, "Config", false)

safe(function()
    UI.RefInfo = Box.ConnMain:Paragraph({ Title = "Game references", Desc = refsText() })
end)
function Session.refreshGameRefs(show)
    -- stop Clear / Farmer first
    if Clear.Running then stopClear("Stopped: reconnecting to game") end
    if Farmer.Running then stopFarmer("Stopped: reconnecting to game") end
    if Build.DirtRun then Build.stop("Stopped: reconnecting to game") end
    Auto.resetReach()
    -- Do not use world objects or functions from a previous session.
    Refs.World, Refs.Inv, Refs.MovementMenu = nil, nil, nil
    Refs.SetTile, Refs.State, Refs.Punch, Refs.Menu = nil, nil, nil, nil
    Refs.Gems, Refs.Hud, Refs.Others, Refs.Arm = nil, nil, nil, nil
    Refs.Particles, Anim.Particles = {}, nil
    Refs.Trees, Refs.TreeMode, Refs.TreeP = nil, nil, nil
    Drops.list, Drops.update = nil, nil
    Refs.ConnectionCount = 0
    Session.RuntimeAccessMessage = nil
    -- 1) quickly scan bag and populate dropdowns (don't wait on slow getgc scan)
    pcall(Anim.quickRefs)
    if Refs.Inv and Session.ItemDBSource then
        pcall(doInvRefresh, true)
        task.wait() -- let dropdowns populate before full scan (full scan briefly stalls)
    end
    -- On world switch, wait for new connections before reading candidates from heap.
    if not Refs.World and type(getconnections) == "function" then
        for _ = 1, 4 do
            task.wait(0.5)
            if not alive() then return false end
            pcall(Anim.quickRefs)
            if Refs.World then break end
        end
    end
    if not alive() then return false end
    findRefs()
    if not alive() then return false end
    if Refs.ScanError then warn("[n4th] " .. Refs.ScanError) end
    local noRuntime = not Refs.World and not Refs.Inv and Refs.RuntimeReadable == false
        and Refs.ConnectionCount == 0
    local itemsReady = Session.resolveItems(noRuntime)
    if not alive() then return false end
    if noRuntime and not Refs.World then
        Session.RuntimeAccessMessage = Session.ModuleScan.RequireDenied
            and "The executor exposes no game tables or callbacks and denies module access."
            or "The executor exposes no game tables or callbacks."
        warn("[n4th] " .. Session.RuntimeAccessMessage)
    end
    Session.bindMovement(not noRuntime)
    watchInventory()
    pcall(doInvRefresh, true) -- run directly on this thread (INIT / UI queue thread), not button thread
    if Refs.World then
        findDropRefs(true)
        Auto.findTreeRefs()
    end
    table.clear(DropFailUntil)
    Anim.fn, Anim.idx = nil, nil
    pcall(Anim.findFast)
    if State.LiteMode then setLite(true) end
    if Misc.InfJump then hookJammer() end
    if Misc.Ghost and Refs.World then Refs.World.ghost = true end
    if Misc.Speed ~= 100 and Refs.World then Refs.World.speedScale = Misc.Speed / 100 end
    pcall(function() UI.RefInfo:SetDesc(refsText()) end)
    updateStatus()
    print("[n4th] " .. Session.Build .. " | scanned=" .. tostring(Refs.ScanCount)
        .. " | callbacks=" .. tostring(Refs.ConnectionCount or 0) .. " | " .. refsText())
    if show then
        local message = refsText()
        if not Refs.World and not Session.RuntimeAccessMessage then
            message = "World data not found. Press 'Connect to game'" .. "\n" .. message
        end
        notify(show, message, 5)
    end
    return Refs.World ~= nil and itemsReady
end

function Session.scheduleItemRetry()
    if Session.ItemDBSource or Session.ItemRetry or not Refs.World then return end
    Session.ItemRetry = true
    task.spawn(function()
        for _, delay in ipairs({ 1, 2, 4 }) do
            task.wait(delay)
            if not alive() or Session.ItemDBSource then break end
            if not Session.Connecting and not Session.ItemScan and Refs.World then
                local ok, found = pcall(Session.itemsFromReferences)
                if ok and found then
                    UI.later("itemdb-recovered", function()
                        pcall(doInvRefresh, true)
                        pcall(function() UI.RefInfo:SetDesc(refsText()) end)
                    end)
                    break
                end
            end
        end
        Session.ItemRetry = false
    end)
end

local function reconnect(show)
    if Session.Connecting then return false end
    Session.Connecting = true
    local ok, connected = pcall(Session.refreshGameRefs, show)
    Session.Connecting = false
    if ok then
        if not Session.RuntimeAccessMessage then Session.scheduleMovementRetry() end
        Session.scheduleItemRetry()
        return connected
    end
    warn("[n4th] Game connection: " .. tostring(connected))
    pcall(function() UI.RefInfo:SetDesc(refsText()) end)
    if show then notify(show, refsText(), 5) end
    return false
end

safe(function()
    Box.ConnMain:Button({
        Title = "Connect to game",
        Desc = "Use after changing worlds",
        Callback = function()
            UI.later("reconnect", function() reconnect("Connection") end)
        end,
    })
end)

safe(function()
    UI.ConfigStatus = Box.ConnCfg:Paragraph({ Title = "Status", Desc = Config.Status })
end)

safe(function()
    Box.ConnCfg:Toggle({
        Title = "Auto Save Config",
        Desc = "Save settings automatically, loaded again on execute",
        Value = Config.AutoSave,
        Callback = function(on)
            Config.AutoSave = on
            Config.save(true) -- save this setting too
        end,
    })
end)

safe(function()
    Box.ConnCfg:Button({
        Title = "Save config now",
        Callback = function()
            local ok = Config.save(true)
            notify("Config", ok and "Saved" or Config.Status, 3)
        end,
    })
end)

safe(function()
    Box.ConnCfg:Button({
        Title = "Reset config (default)",
        Desc = "Delete the config file, then re-execute",
        Callback = function()
            Config.reset()
            notify("Config", Config.Status, 4)
        end,
    })
end)

Box.ConnCalib = box(ConnTab, "Position correction", false)

safe(function()
    Box.ConnCalib:Input({
        Title = "Position correction X",
        Desc = "Enter 1 / -1 if tiles are off",
        Value = tostring(State.CalibX),
        Callback = function(text) State.CalibX = tonumber(text) or 0 end,
    })
end)

safe(function()
    Box.ConnCalib:Input({
        Title = "Position correction Y",
        Value = tostring(State.CalibY),
        Callback = function(text) State.CalibY = tonumber(text) or 0 end,
    })
end)

-- ===== CONNECTION: AUTO RECONNECT =====
do (function()
    local rBox = box(ConnTab, "Auto Reconnect", false)

    safe(function()
        UI.RejoinStatus = rBox:Paragraph({ Title = "Status", Desc = Rejoin.Status })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Auto Reconnect",
            Desc = "Rejoin & resume activity if kicked out",
            Value = Rejoin.On,
            Callback = function(on)
                Rejoin.On = on
                if Session.Ready and Config.AutoSave then Config.save(true) end
            end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Kicked from world",
            Desc = "World closed / kicked: rejoin the same world",
            Value = Rejoin.World,
            Callback = function(on)
                Rejoin.World = on
                if Session.Ready and Config.AutoSave then Config.save(true) end
            end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Always return to world",
            Desc = "If outside a world (world select screen), rejoin automatically",
            Value = Rejoin.Keep,
            Callback = function(on)
                Rejoin.Keep = on
                if Session.Ready and Config.AutoSave then Config.save(true) end
            end,
        })
    end)

    safe(function()
        rBox:Input({
            Title = "Target world",
            Desc = "Empty = the last world you entered",
            Value = Rejoin.Target,
            Placeholder = "WORLDNAME",
            Callback = function(text)
                Rejoin.Target = tostring(text or "")
                if Session.Ready and Config.AutoSave then Config.save(true) end
            end,
        })
    end)

    safe(function()
        rBox:Button({
            Title = "Rejoin world now",
            Desc = "Leave and rejoin, activity resumes",
            Callback = function() Rejoin.now() end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Disconnected from server",
            Desc = "Teleport back to the game and enter the last world",
            Value = Rejoin.Server,
            Callback = function(on)
                Rejoin.Server = on
                if Session.Ready and Config.AutoSave then Config.save(true) end
            end,
        })
    end)

    addNumber(rBox, {
        Title = "Delay before rejoining (seconds)",
        Min = 2, Max = 60, Step = 1, Default = Rejoin.DelaySec,
        Callback = function(v) Rejoin.DelaySec = math.floor(v) end,
    })

    safe(function()
        rBox:Input({
            Title = "Script URL (for server rejoin)",
            Desc = "Raw link of this script, so it runs again after teleport. Empty = use autoexec",
            Value = Rejoin.ScriptUrl,
            Placeholder = "https://...",
            Callback = function(text)
                Rejoin.ScriptUrl = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if Session.Ready and Config.AutoSave then Config.save(true) end
            end,
        })
    end)
end)() end

do
    local character = box(ConnTab, "Character", false)
    local effects = box(ConnTab, "Effects & performance", false)

    addNumber(character, {
        Title = "Walkspeed (%)",
        Desc = "100 = normal",
        Min = 50, Max = 500, Step = 10, Default = Misc.Speed,
        Callback = function(v) setSpeed(v) end,
    })

    safe(function()
        character:Toggle({
            Title = "Infinite Jump",
            Desc = "Jump mid-air (may get rolled back)",
            Value = false,
            Callback = function(on) setInfJump(on) end,
        })
    end)

    safe(function()
        UI.GhostToggle = character:Toggle({
            Title = "Fly + Noclip",
            Desc = "Use UP/DN to fly. Move into open space before turning it off. Passing through blocks can trigger a kick.",
            Value = false,
            Callback = function(on) setGhost(on, true) end,
        })
    end)

    safe(function()
        effects:Toggle({
            Title = "Lite Mode",
            Desc = "Turn off particles & sounds (low-end phones)",
            Value = State.LiteMode,
            Callback = function(on) setLite(on) end,
        })
    end)

    safe(function()
        effects:Toggle({
            Title = "Mute punch sounds",
            Value = State.MutePunch,
            Callback = function(on) State.MutePunch = on end,
        })
    end)

    safe(function()
        effects:Toggle({
            Title = "Action animation",
            Desc = "Arm moves on break / place / plant / harvest + place effect. Turn off to save FPS",
            Value = State.Visual,
            Callback = function(on)
                State.Visual = on
                if on and not Anim.fn and Refs.World then
                    notify("Animation", "Game animation function not found (press 'Connect to game')", 4)
                end
            end,
        })
    end)

    safe(function()
        effects:Toggle({
            Title = "Anti AFK",
            Value = State.AntiAfk,
            Callback = function(on) State.AntiAfk = on end,
        })
    end)

    addNumber(effects, {
        Title = "Hits per block (fallback)",
        Desc = "Used when 'Punch: NO'. 0 = automatic",
        Min = 0, Max = 20, Step = 1, Default = State.HitsOverride,
        Callback = function(v) State.HitsOverride = math.floor(v) end,
    })
end

-- ===== TAB: DISCORD =====
do (function()
    local DcTab = UI.Tabs["Discord"]

    safe(function()
        UI.HookStatus = DcTab:Paragraph({ Title = "Status", Desc = Hook.Status })
    end)

    local dMain = box(DcTab, "Webhook", true)
    local dWhat = box(DcTab, "What to send", false)

    safe(function()
        dMain:Toggle({
            Title = "Discord Notifications",
            Desc = "Send important updates to your Discord channel",
            Value = Hook.On,
            Callback = function(on) Hook.On = on end,
        })
    end)

    safe(function()
        dMain:Input({
            Title = "Webhook URL",
            Desc = "Discord channel > Edit > Integrations > Webhook > Copy URL",
            Value = Hook.Url,
            Placeholder = "https://discord.com/api/webhooks/...",
            Callback = function(text)
                text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                Hook.Url = text
                if text ~= "" and not Hook.valid(text) then
                    notify("Discord", "Invalid webhook URL", 4)
                end
            end,
        })
    end)

    safe(function()
        dMain:Button({
            Title = "Test send",
            Callback = function()
                if not Hook.valid(Hook.Url) then
                    notify("Discord", "Fill in the webhook URL first", 3)
                    return
                end
                local was = Hook.On
                Hook.On = true
                Hook.send("test", "Test notification from n4th")
                Hook.On = was
                notify("Discord", "Test message queued", 3)
            end,
        })
    end)

    addNumber(dMain, {
        Title = "Stats report (minutes)",
        Desc = "Send session stats every X minutes. 0 = off",
        Min = 0, Max = 180, Step = 5, Default = Hook.ReportMin,
        Callback = function(v) Hook.ReportMin = math.floor(v) end,
    })

    for _, item in ipairs({
        { "Guard", "Mod / Dev / player entered world" },
        { "Stop", "Activity stopped (out of blocks / error)" },
        { "Full", "Inventory full" },
        { "Bonus", "Quest claimed / redeem successful" },
        { "Rejoin", "Kicked / disconnected / rejoined" },
        { "Factory", "Auto Rotasi: seed di-drop / lahan selesai / berhenti" },
        { "Finder", "World Finder: world search results" },
    }) do
        safe(function()
            dWhat:Toggle({
                Title = item[2],
                Value = Hook[item[1]],
                Callback = function(on) Hook[item[1]] = on end,
            })
        end)
    end
end)() end


---------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------
for field, title in pairs({ InvDropdown = "Farm", SeedDropdown = "Farmer", FactorySeedDropdown = "Auto Rotasi",
    ClearBlockDropdown = "Clear World", FarmerBlockDropdown = "Farmer", BuildBlockDropdown = "Land" }) do
    if UI[field] then UI.DropdownTabs[UI[field]] = title end
end
-- UI worker thread: created here (same as status thread proven able to update UI).
-- Button callbacks / game events in some executors lack identity permission to edit dropdowns.
do
    task.spawn(function()
        while alive() do
            local ok, err = pcall(UI.runJobs)
            if not ok then warn("[n4th] UI runner: " .. tostring(err)) end
            task.wait(0.1)
        end
    end)
end

task.spawn(function()
    local readyDeadline = os.clock() + 12
    while alive() and LocalPlayer:GetAttribute("GameReady") ~= true and os.clock() < readyDeadline do task.wait(0.25) end
    if not alive() then return end
    local connected = reconnect("n4th v2.0")
    -- Input may bind late on executors injected before game client finishes loading.
    if connected and not Refs.Punch then
        task.spawn(function()
            for attempt = 1, 5 do
                task.wait(2)
                if not alive() or Refs.Punch then return end
                if Session.Connecting then continue end
                pcall(Anim.quickRefs)
                if attempt == 3 and not Refs.Punch then pcall(findRefs) end
                if Refs.Inv then pcall(watchInventory) end
                pcall(function() UI.RefInfo:SetDesc(refsText()) end)
                if Refs.Punch then
                    print("[n4th] Punch function found after game input became ready.")
                    return
                end
            end
            if alive() and not Refs.Punch then
                warn("[n4th] Punch still not found after trying GC and input connections. Run n4th-diagnose.lua for an executor API report.")
            end
        end)
    end
    -- Guard from config is enabled after player list is located
    -- (so existing players get recorded first)
    if connected and Config.saved("Guard", "On") == true and alive() then
        if UI.GuardToggle then pcall(function() UI.GuardToggle:Set(true) end) end
        if not Guard.On then Guard.set(true) end
    end
    Config.start()
    -- Finder gets priority so a farming rejoin snapshot does not switch worlds again.
    if connected and not WorldFinder.startup(reconnect) then Rejoin.startup(reconnect) end
end)

task.spawn(function()
    while alive() do
        if not State.Running then updateStatus() end
        Auto.updateClearStatus()
        Auto.updateFarmerStatus()
        updateSpamStatus()
        if UI.HomeStatus and UI.tabVisible("Home") then
            local world = Guard.worldName()
            local running = {}
            for _, activity in ipairs({
                { State.Running, "Auto Farm" },
                { Farmer.Running, "Plant & Harvest" },
                { Clear.Running, Clear.TargetId and "Auto Break Block" or "Auto Clear World" },
                { AutoDrop.On, "Auto Drop" },
                { Build.Running and Build.DirtRun, "Auto Dirt Farm" },
                { WorldFinder.Running, "World Finder" },
            }) do
                if activity[1] then running[#running + 1] = activity[2] end
            end
            local status = world ~= "" and world or "Outside a world"
            status ..= "\n" .. (#running > 0 and ("Active" .. "  " .. table.concat(running, " | "))
                or "No activities running")
            if status ~= UI.HomeShown then
                UI.HomeShown = status
                pcall(function() UI.HomeStatus:SetDesc(status) end)
            end
        end
        if UI.ConfigStatus and Config.Status ~= Config.Shown then
            Config.Shown = Config.Status
            pcall(function() UI.ConfigStatus:SetDesc(Config.Status) end)
        end
        local rj = ("%s\nTarget world: %s\nRe-entered: %d times"):format(
            Rejoin.Status, (Rejoin.targetWorld and Rejoin.targetWorld() ~= "") and Rejoin.targetWorld() or "-", Rejoin.Count)
        if UI.RejoinStatus and rj ~= Rejoin.Shown then
            Rejoin.Shown = rj
            pcall(function() UI.RejoinStatus:SetDesc(rj) end)
        end
        local hk = ("%s\nQueue: %d messages"):format(Hook.Status, #Hook.Queue)
        if UI.HookStatus and hk ~= Hook.Shown then
            Hook.Shown = hk
            pcall(function() UI.HookStatus:SetDesc(hk) end)
        end
        task.wait(1)
    end
end)

---------------------------------------------------------------------
-- CLEANUP (automatic on script re-execute)
---------------------------------------------------------------------
Session.Cleanup = function()
    WorldFinder.Running, WorldFinder.Cancelled = false, true
    if WorldFinder.checkpoint then WorldFinder.checkpoint(false) end
    AutoDrop.On, AutoDrop.Cancelled = false, true
    State.Running = false
    Clear.Running = false
    Farmer.Running = false
    Spam.On = false
    if Config.AutoSave then pcall(Config.save, false) end -- save before closing
    Guard.On = false
    Bonus.Quest, Bonus.Redeem = false, false
    Scan.Auto = false
    Splice.Running = false
    Rejoin.On = false
    Factory.Running = false
    Build.Running = false
    State.Override = nil
    pcall(Auto.stopWalk)
    AutoInput.active = false
    pcall(Auto.releaseInput)
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    pcall(function() RunService:UnbindFromRenderStep("n4th_MiscPreRender") end)
    -- restore original name (remove watermark)
    Misc.CustomName = false
    pcall(nameRestore)
    -- restore hooked game functions
    pcall(setLite, false)
    pcall(unhookJammer)
    local menu = Session.MovementMenu
    if menu and OrigIsDown and rawget(menu, "isDown") == isDownWrapper then
        pcall(rawset, menu, "isDown", OrigIsDown)
    end
    if Refs.World then
        if Misc.Ghost then pcall(function() Refs.World.ghost = false end) end
        if Misc.Speed ~= 100 then pcall(function() Refs.World.speedScale = 1 end) end
    end
    pcall(function() UI.GridGui:Destroy() end)
    pcall(function() UI.FlyPad:Destroy() end)
    pcall(function() Window:Destroy() end)
end

Session.InitStep = "ready"
Session.Ready = true
print("[n4th] Menu ready (build " .. Session.Build .. ")")
