--[[
    Peex HUB | GrowBlox  (v13.1 - fix GUI tidak muncul)
    Prefix default "/" (bisa diganti / dikosongkan di /settingsgb)

      wld|wd <jumlah>        Drop World Lock
      tp|warp <world>        Pindah world
      pos1 | pos2            Simpan posisi sekarang
      win1|w1 [jumlah]       Teleport ke Pos 1 (opsional langsung drop WL)
      win2|w2 [jumlah]       Teleport ke Pos 2
      pos                    Lihat posisi sekarang & pos tersimpan
      rejoin|rj              Masuk ulang ke world ini
      noclip [on|off]        Tembus blok + terbang (mode ghost game)
      unlimitedjump|uj       Lompat di udara tanpa batas
      blink [on|off]         Warna skin berganti otomatis
      longhand|lh [n|off]    Jangkauan punch/build lebih jauh
      visualitem|vi          GUI item visual (lokal)
      settingsgb|sgb         GUI pengaturan
      afk                    Anti-AFK (tidak kena kick idle)
      autorejoin|arj         Rejoin otomatis kalau terputus
      session|sesi           GUI sesi (simpan & pulihkan otomatis)
      af|autofarm [on|off]   GUI Auto Farm
      ac|autoclear [on|off]  Auto Clear World
      acmode <walk|tp>       Mode Auto Clear
      acpunch <1-3>          Jumlah block yang dipukul sekaligus
      df|dirtfarm [on|off]   Auto Dirt Farm
      dirtid <id|nama>       Atur block dirt untuk Auto Dirt Farm
      ctp|clicktp [on|off]   Click TP
      move|mv <walk|tp|fly|mix> Mode gerak
      spam [on|off]          Kirim teks spam ke chat berulang
      setspam <teks>         Atur teks spam
      hiddenname|hn <off|self|all>  Sembunyikan nama (lokal saja)
      breakid <id,id,...>    Scan & pecahkan block ID tertentu
      aq|autoquest [on|off|scan]  Auto quest
      gs|growscan            Buka GrowScan
      god [on|off]           God mode
      blockid|bid <nama>     Cari ID block dari nama
      hpx                    Daftar fitur

    Tombol keyboard: P atau RightShift untuk buka/tutup menu.
    Simpan skrip ini di folder workspace executor dengan nama
    "PeexHub_GrowBlox.lua" (atau isi URL di tab Sesi) supaya auto-reload jalan.
]]

-- Cegah dobel-eksekusi (FIX: hanya memblokir kalau GUI-nya benar-benar masih ada)
local genv = (getgenv and getgenv()) or _G

local function PeexGuiExists()
    local found = false
    pcall(function()
        local lp = game:GetService("Players").LocalPlayer
        local places = { lp and lp:FindFirstChildOfClass("PlayerGui") }
        if gethui then
            table.insert(places, gethui())
        end
        table.insert(places, game:GetService("CoreGui"))
        for _, place in ipairs(places) do
            if place and place:FindFirstChild("PeexHubGB") then
                found = true
            end
        end
    end)
    return found
end

if genv.PeexHubGB_Loaded and PeexGuiExists() then
    if type(genv.PeexHubGB_Loaded) ~= "number" or os.clock() - genv.PeexHubGB_Loaded > 15 then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Peex HUB | GrowBlox",
                Text = "Sudah aktif. Ketik /hpx atau tekan tombol P.",
                Duration = 4,
            })
        end)
    end
    return
end
genv.PeexHubGB_Loaded = os.clock()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local DropEvent = ReplicatedStorage
    :WaitForChild("WorldRemotes")
    :WaitForChild("DropItem")

----------------------------------------------------------------------
-- CONFIG (disimpan ke file kalau executor mendukung writefile)
----------------------------------------------------------------------
local CONFIG_FILE = "PeexHub_GrowBlox.json"

local Config = {
    prefix = "/",
    dropId = 242,
    longhandRange = 3,
    blinkMin = 0.2,
    blinkMax = 0.5,
    winDrop = 0,
    pos1 = {},
    pos2 = {},
    -- Sesi
    autoRestore = true,
    autoReload = true,
    autoWarp = false,
    launcher = true,
    lastWorld = "",
    scriptUrl = "",
    session = {},
    -- Auto Farm
    farmDelay = 0.22,
    farmPlaceId = 0,
    farmGrid = { ["1,0"] = true },
    farmTake = true,
    -- Auto Clear World
    clearBreakDelay = 0.22,
    clearBatch = 2,
    clearTpDelay = 0.25,
    clearTake = true,
    walkBatch = 3,
    clearPunch = 3,
    -- Auto Dirt Farm
    dirtId = 0,
    dirtPlace = true,
    clearMode = "walk",
    -- Hidden Name
    hiddenNameMode = "off",
    -- Auto Break by Block ID
    breakIdText = "",
    -- Spam Chat
    spamText = "",
    spamDelay = 3,
    -- Pathfinding / Click TP
    navPath = true,
    moveMode = "mix",
    hopMin = 3,
    hopMax = 5,
    hopDelay = 0.12,
    navSpeed = 2,
    clickTpShift = false,
}

local SCRIPT_FILE = "PeexHub_GrowBlox.lua"
local QueueReload

local MAX_AMOUNT = 10000
local COOLDOWN = 0.3

local function LoadConfig()
    pcall(function()
        if isfile and readfile and isfile(CONFIG_FILE) then
            local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
            for key, value in pairs(data) do
                if Config[key] ~= nil and type(value) == type(Config[key]) then
                    Config[key] = value
                end
            end
        end
    end)
end

local function SaveConfig()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(Config))
        end
    end)
end

LoadConfig()
Config.launcher = true -- FIX: tombol P selalu muncul saat start

----------------------------------------------------------------------
-- UTIL
----------------------------------------------------------------------
local ToastHook = nil

local function Notify(message)
    if ToastHook then
        local ok = pcall(ToastHook, tostring(message))
        if ok then
            return
        end
    end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Peex HUB | GrowBlox",
            Text = message,
            Duration = 4,
        })
    end)
end

local function Trim(text)
    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local getgcFn = getgc or (debug and debug.getgc)
local getupvalueFn = (debug and debug.getupvalue) or getupvalue
local setupvalueFn = (debug and debug.setupvalue) or setupvalue

local function GetUpvalues(fn)
    local list = {}
    for i = 1, 255 do
        local ok, value = pcall(getupvalueFn, fn, i)
        if not ok then
            break
        end
        list[i] = value
    end
    return list
end

----------------------------------------------------------------------
-- AKSES KE INTERNAL GAME (lewat getgc)
----------------------------------------------------------------------
local cache = {}

local function ScanGc(name, check)
    local cached = cache[name]
    if cached and check(cached) then
        return cached
    end
    if not getgcFn then
        return nil
    end
    for _, obj in ipairs(getgcFn(true)) do
        if type(obj) == "table" then
            local ok, valid = pcall(check, obj)
            if ok and valid then
                cache[name] = obj
                return obj
            end
        end
    end
    return nil
end

local function FindInventory()
    return ScanGc("inventory", function(t)
        return type(rawget(t, "onDrop")) == "function"
            and type(rawget(t, "canDrop")) == "function"
            and type(rawget(t, "isWorn")) == "function"
    end)
end

local function FindWorld()
    return ScanGc("world", function(t)
        return type(rawget(t, "enter")) == "function"
            and type(rawget(t, "dropOk")) == "function"
    end)
end

local function FindRigs()
    return ScanGc("rigs", function(t)
        local a, b = rawget(t, 1), rawget(t, -1)
        return type(a) == "table" and type(b) == "table"
            and typeof(rawget(a, "body")) == "Instance"
            and typeof(rawget(b, "head")) == "Instance"
    end)
end

local function GetWorn()
    local inv = FindInventory()
    if not inv then
        return nil
    end
    local worn = GetUpvalues(inv.isWorn)[1]
    if type(worn) == "table" then
        return worn
    end
    return nil
end

local ItemDB = nil
local function GetItemDB()
    if ItemDB then
        return ItemDB
    end
    local ok, result = pcall(function()
        local shared = ReplicatedStorage:WaitForChild("Shared", 5)
        return require(shared:WaitForChild("ItemDB", 5))
    end)
    if ok and type(result) == "table" then
        ItemDB = result
    end
    return ItemDB
end

----------------------------------------------------------------------
-- POSISI GRID
----------------------------------------------------------------------
local function GetGridState()
    local inv = FindInventory()
    if not inv then
        return nil, "Inventory game tidak ditemukan (executor perlu getgc & debug.getupvalue)"
    end

    local canDropUp = GetUpvalues(inv.canDrop)
    local x = canDropUp[2]
    local facing = canDropUp[3]
    if type(x) ~= "number" or type(facing) ~= "number" then
        return nil, "Upvalue X/arah tidak cocok"
    end

    local nums = {}
    for _, value in ipairs(GetUpvalues(inv.onDrop)) do
        if type(value) == "number" then
            table.insert(nums, value)
        end
    end

    local y = nums[3]
    if type(y) ~= "number" then
        return nil, "Upvalue Y tidak ditemukan"
    end

    return x, y, (facing >= 0) and 1 or -1
end

local function GetTile()
    local x, y = GetGridState()
    if not x then
        return nil
    end
    return math.floor(x), math.floor(y - 0.475)
end

local Nav

local function CurrentWorldName()
    local world = FindWorld()
    local name = world and rawget(world, "name")
    return type(name) == "string" and name or ""
end

----------------------------------------------------------------------
-- DROP WORLD LOCK
----------------------------------------------------------------------
local busy = false

local function DropWorldLock(amount)
    if busy then
        Notify("Tunggu sebentar bre!")
        return
    end

    local x, y, facing = GetGridState()
    if not x then
        Notify("Posisi tidak terdeteksi: " .. tostring(y))
        return
    end

    local inv = FindInventory()
    local okCan, canDrop = pcall(inv.canDrop)
    if okCan and canDrop == false then
        Notify("Tidak bisa drop di posisi ini!")
        return
    end

    local dropX = x + facing * (0.7 + math.random() * 0.1)
    local dropY = y - 0.45

    busy = true

    local success, err = pcall(function()
        DropEvent:FireServer(Config.dropId, amount, dropX, dropY)
    end)

    if success then
        Notify("Sukses Drop " .. amount .. " World Lock")
    else
        Notify("Request gagal!")
        warn(err)
    end

    task.wait(COOLDOWN)
    busy = false
end

----------------------------------------------------------------------
-- WARP ANTAR WORLD
----------------------------------------------------------------------
local function WarpToWorld(name)
    name = Trim(name):upper()
    if name == "" then
        Notify("Contoh: " .. Config.prefix .. "tp START")
        return
    end

    local world = FindWorld()
    if not world then
        Notify("Fungsi world game tidak ditemukan!")
        return
    end

    Notify("Menuju world " .. name .. "...")
    local ok, success, message, teleporting = pcall(world.enter, name)

    if not ok then
        Notify("Warp gagal!")
        warn(success)
    elseif success then
        Notify("Berhasil masuk world " .. name)
    elseif teleporting then
        Notify(tostring(message or ("Memasuki " .. name .. "...")))
    else
        Notify(tostring(message or "Tidak bisa masuk world itu."))
    end
end

----------------------------------------------------------------------
-- POS1 / POS2 + WIN1 / WIN2
----------------------------------------------------------------------
local function SetPos(slot)
    local tx, ty = GetTile()
    if not tx then
        Notify("Posisi tidak terdeteksi!")
        return
    end
    Config["pos" .. slot] = { world = CurrentWorldName(), x = tx, y = ty }
    SaveConfig()
    Notify(string.format("Pos %d disimpan: %d, %d", slot, tx, ty))
end

local function GoToPos(slot, amount)
    local pos = Config["pos" .. slot]
    if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then
        Notify("Pos " .. slot .. " belum diset! Ketik " .. Config.prefix .. "pos" .. slot)
        return
    end

    local world = FindWorld()
    if not world or type(world.goTo) ~= "function" then
        Notify("Fungsi teleport game tidak ditemukan!")
        return
    end

    local current = CurrentWorldName()
    if type(pos.world) == "string" and pos.world ~= "" and current ~= pos.world then
        Notify(string.format("Pos %d disimpan di world %s (kamu di %s)", slot, pos.world, current))
        return
    end

    local ok, err
    if Nav and Nav.Tele then
        ok, err = Nav.Tele(pos.x, pos.y)
        if not ok and err ~= "cancel" then
            ok, err = pcall(world.goTo, pos.x, pos.y)
        end
    else
        ok, err = pcall(world.goTo, pos.x, pos.y)
    end
    if not ok then
        Notify("Teleport gagal!")
        warn(err)
        return
    end
    Notify(string.format("Pindah ke Pos %d (%d, %d)", slot, pos.x, pos.y))

    local dropAmount = amount
    if not dropAmount and Config.winDrop > 0 then
        dropAmount = Config.winDrop
    end
    if dropAmount then
        task.wait(0.4)
        DropWorldLock(dropAmount)
    end
end

local function ShowPos()
    local tx, ty = GetTile()
    local parts = {}
    table.insert(parts, tx and string.format("Sekarang: %d, %d (%s)", tx, ty, CurrentWorldName()) or "Posisi tidak terdeteksi")
    for slot = 1, 2 do
        local pos = Config["pos" .. slot]
        if type(pos) == "table" and type(pos.x) == "number" then
            table.insert(parts, string.format("Pos%d: %d, %d", slot, pos.x, pos.y))
        else
            table.insert(parts, "Pos" .. slot .. ": -")
        end
    end
    Notify(table.concat(parts, " | "))
end

----------------------------------------------------------------------
-- REJOIN
----------------------------------------------------------------------
local function Rejoin()
    local name = CurrentWorldName()
    if name == "" then
        name = Config.lastWorld
    end
    SaveConfig()
    if QueueReload then
        pcall(QueueReload)
    end
    local data = (name ~= "") and { world = name } or nil
    Notify(name ~= "" and ("Rejoin world " .. name .. "...") or "Rejoin...")
    local ok, err = pcall(function()
        TeleportService:Teleport(game.PlaceId, Player, data)
    end)
    if not ok then
        Notify("Rejoin gagal!")
        warn(err)
    end
end

----------------------------------------------------------------------
-- BLINK SKIN
----------------------------------------------------------------------
local blinkOn = false
local blinkOriginal = {}

local function CollectSkinParts()
    local list = {}
    local rigs = FindRigs()
    if not rigs then
        return list
    end

    for _, key in ipairs({ 1, -1, 0 }) do
        local rig = rawget(rigs, key)
        if type(rig) == "table" then
            for _, field in ipairs({ "body", "head", "eyelids", "blink", "forearm", "fist" }) do
                local part = rig[field]
                if typeof(part) == "Instance" then
                    table.insert(list, { part = part, face = false })
                end
            end
            for _, field in ipairs({ "armBack", "armFront" }) do
                local arm = rig[field]
                local sprite
                if typeof(arm) == "Instance" then
                    sprite = arm:FindFirstChild("Sprite")
                elseif type(arm) == "table" then
                    sprite = arm.Sprite
                end
                if typeof(sprite) == "Instance" then
                    table.insert(list, { part = sprite, face = false })
                end
            end
            if typeof(rig.face) == "Instance" then
                table.insert(list, { part = rig.face, face = true })
            end
        end
    end
    return list
end

local function StopBlink()
    if not blinkOn then
        return false
    end
    blinkOn = false
    for part, color in pairs(blinkOriginal) do
        pcall(function()
            part.ImageColor3 = color
        end)
    end
    table.clear(blinkOriginal)
    return true
end

local function StartBlink()
    if blinkOn then
        return true
    end
    if not FindRigs() then
        Notify("Rig karakter tidak ditemukan!")
        return false
    end

    blinkOn = true
    table.clear(blinkOriginal)
    for _, entry in ipairs(CollectSkinParts()) do
        blinkOriginal[entry.part] = entry.part.ImageColor3
    end

    task.spawn(function()
        while blinkOn do
            local color = Color3.fromHSV(math.random(), 0.55 + math.random() * 0.4, 1)
            local dark = Color3.new(color.R * 0.38, color.G * 0.35, color.B * 0.3)
            for _, entry in ipairs(CollectSkinParts()) do
                if blinkOriginal[entry.part] == nil then
                    blinkOriginal[entry.part] = entry.part.ImageColor3
                end
                pcall(function()
                    entry.part.ImageColor3 = entry.face and dark or color
                end)
            end
            local minT = math.min(Config.blinkMin, Config.blinkMax)
            local maxT = math.max(Config.blinkMin, Config.blinkMax)
            task.wait(minT + math.random() * (maxT - minT))
        end
    end)
    return true
end

----------------------------------------------------------------------
-- LONGHAND
----------------------------------------------------------------------
local longhandOn = false
local longhandOriginal = nil

local function ApplyLonghand()
    local inv = FindInventory()
    if not inv then
        Notify("Inventory game tidak ditemukan!")
        return false
    end

    if not longhandOriginal then
        longhandOriginal = { build = inv.buildRange, punch = inv.punchRange }
    end

    local target = 2.5 + Config.longhandRange
    inv.buildRange = function()
        return math.max(longhandOriginal.build(), target)
    end
    inv.punchRange = function()
        return math.max(longhandOriginal.punch(), target)
    end
    longhandOn = true
    return true
end

local function StopLonghand()
    if not longhandOn then
        return false
    end
    local inv = FindInventory()
    if inv and longhandOriginal then
        inv.buildRange = longhandOriginal.build
        inv.punchRange = longhandOriginal.punch
    end
    longhandOn = false
    return true
end

----------------------------------------------------------------------
-- NOCLIP
----------------------------------------------------------------------
local noclipOn = false
local noclipConn = nil

local function StopNoclip()
    if not noclipOn then
        return false
    end
    noclipOn = false
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end
    local world = FindWorld()
    if world then
        world.ghost = (Player:GetAttribute("Ghost") == true)
    end
    return true
end

local function StartNoclip()
    if noclipOn then
        return true
    end
    local world = FindWorld()
    if not world then
        Notify("World game tidak ditemukan!")
        return false
    end
    noclipOn = true
    world.ghost = true
    noclipConn = RunService.Heartbeat:Connect(function()
        local w = FindWorld()
        if w and w.ghost ~= true then
            w.ghost = true
        end
    end)
    return true
end

----------------------------------------------------------------------
-- UNLIMITED JUMP
----------------------------------------------------------------------
local ujumpOn = false
local ujumpConn = nil
local ujumpFn = nil
local ujumpWingsOriginal = nil
local JUMP_FLAG_INDEX = 27
local WINGS_INDEX = 29

local function FindRenderFn()
    if ujumpFn then
        return ujumpFn
    end
    if not getconnections then
        return nil
    end
    local world, inv = FindWorld(), FindInventory()
    if not world or not inv then
        return nil
    end
    local ok, conns = pcall(getconnections, RunService.RenderStepped)
    if not ok then
        return nil
    end
    for _, conn in ipairs(conns) do
        local okFn, fn = pcall(function()
            return conn.Function
        end)
        if okFn and type(fn) == "function" then
            local ups = GetUpvalues(fn)
            if ups[1] == world and ups[2] == inv then
                ujumpFn = fn
                return fn
            end
        end
    end
    return nil
end

local function FindFallbackWing()
    local db = GetItemDB()
    if not db then
        return nil
    end
    local best, bestPlain = nil, nil
    for id, item in pairs(db) do
        if type(id) == "number" and type(item) == "table" and item.doubleJump == true then
            if not item.wingSheet and (not bestPlain or id < bestPlain) then
                bestPlain = id
            end
            if not best or id < best then
                best = id
            end
        end
    end
    return bestPlain or best
end

local function StopUjump()
    if not ujumpOn then
        return false
    end
    ujumpOn = false
    if ujumpConn then
        ujumpConn:Disconnect()
        ujumpConn = nil
    end
    if ujumpFn and ujumpWingsOriginal and setupvalueFn then
        pcall(setupvalueFn, ujumpFn, WINGS_INDEX, ujumpWingsOriginal)
    end
    ujumpWingsOriginal = nil
    return true
end

local function StartUjump()
    if ujumpOn then
        return true
    end
    if not setupvalueFn then
        Notify("Executor perlu debug.setupvalue!")
        return false
    end
    local fn = FindRenderFn()
    if not fn then
        Notify("Fungsi gerak game tidak ditemukan (perlu getconnections)")
        return false
    end

    local ups = GetUpvalues(fn)
    if type(ups[JUMP_FLAG_INDEX]) ~= "boolean" or type(ups[WINGS_INDEX]) ~= "function" then
        Notify("Struktur game berubah, unlimited jump tidak bisa dipasang.")
        return false
    end

    local original = ups[WINGS_INDEX]
    local fallback = FindFallbackWing()
    if fallback then
        ujumpWingsOriginal = original
        pcall(setupvalueFn, fn, WINGS_INDEX, function()
            return original() or fallback
        end)
    end

    ujumpOn = true
    ujumpConn = RunService.Heartbeat:Connect(function()
        pcall(setupvalueFn, fn, JUMP_FLAG_INDEX, false)
    end)
    return true
end

----------------------------------------------------------------------
-- VISUAL ITEM
----------------------------------------------------------------------
local visualBackup = {}

local function IsVisualWorn(id)
    local worn = GetWorn()
    local db = GetItemDB()
    if not worn or not db or not db[id] then
        return false
    end
    return worn[db[id].slot] == id
end

local function ToggleVisual(id)
    local inv, worn, db = FindInventory(), GetWorn(), GetItemDB()
    if not inv or not worn or not db or not db[id] then
        Notify("Item/inventory game tidak ditemukan!")
        return false
    end

    local slot = db[id].slot
    if type(slot) ~= "string" then
        return false
    end

    if worn[slot] == id then
        worn[slot] = visualBackup[slot] or nil
    else
        if visualBackup[slot] == nil then
            visualBackup[slot] = worn[slot] or false
        end
        worn[slot] = id
    end

    pcall(inv.refresh)
    return true
end

local function ResetVisuals()
    local inv, worn = FindInventory(), GetWorn()
    if not inv or not worn then
        return
    end
    for slot, original in pairs(visualBackup) do
        worn[slot] = original or nil
    end
    table.clear(visualBackup)
    pcall(inv.refresh)
    Notify("Item visual dikembalikan.")
end

local wearableCache = nil
local function GetWearables()
    if wearableCache then
        return wearableCache
    end
    local db = GetItemDB()
    if not db then
        return nil
    end

    local list = {}
    for id, item in pairs(db) do
        if type(id) == "number" and type(item) == "table"
            and type(item.slot) == "string" and type(item.name) == "string" then
            local tags = {}
            local lower = item.name:lower()
            if item.kuyang then
                table.insert(tags, "Kuyang")
            end
            if item.bot then
                table.insert(tags, "LegendBot")
            end
            if id == 5480 or lower:find("rayman", 1, true) then
                table.insert(tags, "Rayman")
            end
            table.insert(list, { id = id, name = item.name, lower = lower, slot = item.slot, tags = tags })
        end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then
            return a.id < b.id
        end
        return a.name < b.name
    end)
    wearableCache = list
    return list
end

----------------------------------------------------------------------
-- FEATURE SETTERS
----------------------------------------------------------------------
local antiAfkOn = false
local antiAfkConn = nil

local function StopAntiAfk()
    if not antiAfkOn then
        return false
    end
    antiAfkOn = false
    if antiAfkConn then
        antiAfkConn:Disconnect()
        antiAfkConn = nil
    end
    return true
end

local function StartAntiAfk()
    if antiAfkOn then
        return true
    end
    local okVU, VirtualUser = pcall(function()
        return game:GetService("VirtualUser")
    end)
    if not okVU or not VirtualUser then
        Notify("VirtualUser tidak tersedia di executor ini.")
        return false
    end
    antiAfkOn = true
    antiAfkConn = Player.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
    return true
end

local arjOn = false
local arjConn = nil

local function StopAutoRejoin()
    if not arjOn then
        return false
    end
    arjOn = false
    if arjConn then
        arjConn:Disconnect()
        arjConn = nil
    end
    return true
end

local function StartAutoRejoin()
    if arjOn then
        return true
    end
    local ok, overlay = pcall(function()
        local gui = game:GetService("CoreGui"):WaitForChild("RobloxPromptGui", 5)
        return gui and gui:WaitForChild("promptOverlay", 5)
    end)
    if not ok or not overlay then
        Notify("Auto rejoin tidak didukung executor ini.")
        return false
    end
    arjOn = true
    arjConn = overlay.ChildAdded:Connect(function(child)
        if child.Name == "ErrorPrompt" and arjOn then
            Notify("Terputus! Rejoin dalam 3 detik...")
            task.wait(3)
            Rejoin()
        end
    end)
    return true
end

local RefreshHub

local SearchItems, ItemName, StartFarm, StopFarm, StartQuest, StopQuest, QuestReport, StartGod, StopGod, OpenNativeGrowScan, ScanWorld
local farmOn, questOn, godOn = false, false, false
Nav = { clickOn = false, token = 0, conn = nil, last = "-" }
local Clear = { on = false, token = 0, status = "Mati", stats = { scanned = 0, broken = 0, picked = 0, skipped = 0, left = 0, pass = 0 } }
local BreakId = { on = false, token = 0, status = "Mati", stats = { found = 0, broken = 0, picked = 0, skipped = 0, left = 0 } }
local DirtFarm = { on = false, token = 0, status = "Mati", stats = { rows = 0, broken = 0, picked = 0, placed = 0, skipped = 0 } }
local questStatus = "Mati"
local farmStats = { status = "Mati", placed = 0, broken = 0, picked = 0, cycles = 0 }
do
----------------------------------------------------------------------
-- DATABASE ITEM + PENCARIAN
----------------------------------------------------------------------
local blockListCache = nil

local function GetBlockList()
    if blockListCache then
        return blockListCache
    end
    local db = GetItemDB()
    if not db then
        return nil
    end
    local list = {}
    for id, item in pairs(db) do
        if type(id) == "number" and type(item) == "table" and type(item.name) == "string"
            and type(item.slot) ~= "string" then
            table.insert(list, {
                id = id,
                name = item.name,
                lower = item.name:lower(),
                kind = type(item.kind) == "string" and item.kind or "block",
            })
        end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then
            return a.id < b.id
        end
        return a.name < b.name
    end)
    blockListCache = list
    return list
end

function ItemName(id)
    local db = GetItemDB()
    local item = db and db[id]
    if type(item) == "table" and type(item.name) == "string" then
        return item.name
    end
    return "?"
end

function SearchItems(query, limit)
    local list = GetBlockList()
    local results = {}
    query = Trim(query):lower()
    if not list or query == "" then
        return {}
    end
    local wantId = tonumber(query)
    for _, entry in ipairs(list) do
        local rank = nil
        if wantId and entry.id == wantId then
            rank = 0
        elseif entry.lower == query then
            rank = 1
        elseif entry.lower:sub(1, #query) == query then
            rank = 2
        elseif entry.lower:find(query, 1, true) then
            rank = 3
        end
        if rank then
            table.insert(results, { entry = entry, rank = rank })
        end
    end
    table.sort(results, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        if a.entry.name ~= b.entry.name then
            return a.entry.name < b.entry.name
        end
        return a.entry.id < b.entry.id
    end)
    local out = {}
    for i = 1, math.min(limit or 25, #results) do
        out[i] = results[i].entry
    end
    return out
end

----------------------------------------------------------------------
-- AKSES FUNGSI GAME: hit, setTile, backpack
----------------------------------------------------------------------
local gameFns = {}

local function FindGameFn(name)
    local cached = gameFns[name]
    if cached then
        return cached
    end
    local world = FindWorld()
    if not world or not getgcFn or not (debug and debug.info) then
        return nil
    end
    for _, fn in ipairs(getgcFn(true)) do
        if type(fn) == "function" then
            local okName, fnName = pcall(debug.info, fn, "n")
            if okName and fnName == name then
                for _, value in pairs(GetUpvalues(fn)) do
                    if value == world then
                        gameFns[name] = fn
                        return fn
                    end
                end
            end
        end
    end
    return nil
end

local function GetBag()
    local world = FindWorld()
    if not world or type(rawget(world, "backpackNow")) ~= "function" then
        return nil
    end
    for _, value in pairs(GetUpvalues(world.backpackNow)) do
        if type(value) == "table" and type(value.slots) == "table" then
            return value
        end
    end
    return nil
end

local function CountItem(id)
    local bag = GetBag()
    if not bag then
        return nil
    end
    local total = 0
    for _, slot in pairs(bag.slots) do
        if type(slot) == "table" and slot.id == id then
            total += slot.n or 0
        end
    end
    return total
end

local function TileValue(world, layer, x, y)
    local grid = rawget(world, layer)
    local row = grid and grid[y]
    return row and row[x] or nil
end

local function InBounds(world, x, y)
    return type(world.w) == "number" and x >= 0 and y >= 0 and x < world.w and y < world.h
end

local function LayerOf(id)
    local db = GetItemDB()
    local item = db and db[id]
    if type(item) == "table" and item.background then
        return "bg"
    end
    return "fg"
end

----------------------------------------------------------------------
-- AUTO FARM
----------------------------------------------------------------------
local farmToken = 0
local farmAnchor = nil

local function FarmCells(world, anchor)
    local cells = {}
    for key, on in pairs(Config.farmGrid) do
        local dx, dy = tostring(key):match("^(-?%d+),(-?%d+)$")
        dx, dy = tonumber(dx), tonumber(dy)
        if on and dx and dy and math.abs(dx) <= 2 and math.abs(dy) <= 2 and not (dx == 0 and dy == 0) then
            local x, y = anchor.x + dx, anchor.y + dy
            if InBounds(world, x, y) then
                table.insert(cells, { x = x, y = y })
            end
        end
    end
    table.sort(cells, function(p, q)
        if p.y ~= q.y then
            return p.y < q.y
        end
        return p.x < q.x
    end)
    return cells
end

local function PlaceCell(id, cell, facing)
    local setTile = FindGameFn("setTile")
    if not setTile then
        return false
    end
    local ok = pcall(setTile, LayerOf(id), cell.x, cell.y, id, false, facing < 0)
    if not ok then
        return false
    end
    local bag = GetBag()
    if bag and type(bag.remove) == "function" then
        pcall(bag.remove, bag, id, 1)
    end
    return true
end

local function BreakCell(world, id, cell, token)
    local hit = FindGameFn("hit")
    if not hit then
        return false
    end
    local layer = LayerOf(id)
    if layer == "bg" and TileValue(world, "fg", cell.x, cell.y) ~= 0 then
        return false
    end
    local started = os.clock()
    while farmToken == token and TileValue(world, layer, cell.x, cell.y) == id do
        if os.clock() - started > 10 then
            return false
        end
        pcall(hit, cell.x, cell.y, true)
        task.wait(math.max(0.03, Config.farmDelay))
    end
    return TileValue(world, layer, cell.x, cell.y) ~= id
end

local function DropSet(world)
    local set = {}
    local ok, list = pcall(world.dropList)
    if ok and type(list) == "table" then
        for _, drop in ipairs(list) do
            set[drop] = true
        end
    end
    return set
end

local function CollectDrops(world, anchor, before, token)
    local ok, list = pcall(world.dropList)
    if not ok or type(list) ~= "table" then
        return 0
    end
    local targets = {}
    for _, drop in ipairs(list) do
        if not before[drop] and type(drop.x) == "number" and type(drop.y) == "number" and not drop.pending then
            table.insert(targets, drop)
        end
    end
    local picked = 0
    for _, drop in ipairs(targets) do
        if farmToken ~= token then
            break
        end
        if table.find(list, drop) then
            local reached = Nav.To(math.floor(drop.x), math.floor(drop.y), function() return farmToken ~= token end)
            local waited = os.clock()
            while reached and farmToken == token and table.find(list, drop) and os.clock() - waited < 0.9 do
                task.wait(0.05)
            end
            if not table.find(list, drop) then
                picked += 1
            end
        end
    end
    Nav.To(anchor.x, anchor.y, function() return farmToken ~= token end)
    return picked
end

local function FarmLoop(token)
    while farmToken == token do
        local world = FindWorld()
        if not world then
            farmStats.status = "World tidak ditemukan"
            break
        end
        if CurrentWorldName() ~= farmAnchor.world then
            farmStats.status = "World berubah, farm berhenti"
            Notify("Auto Farm berhenti: kamu pindah world.")
            break
        end

        local id = Config.farmPlaceId
        local layer = LayerOf(id)
        local cells = FarmCells(world, farmAnchor)
        if #cells == 0 then
            farmStats.status = "Tidak ada sel target"
            Notify("Auto Farm: pilih kotak hijau di grid GUI (" .. Config.prefix .. "af).")
            break
        end

        local tx, ty = GetTile()
        if tx ~= farmAnchor.x or ty ~= farmAnchor.y then
            Nav.To(farmAnchor.x, farmAnchor.y, function() return farmToken ~= token end)
            task.wait(0.15)
        end

        farmStats.status = "Place " .. ItemName(id)
        local outOfItem = false
        for _, cell in ipairs(cells) do
            if farmToken ~= token then
                break
            end
            if TileValue(world, layer, cell.x, cell.y) == 0 then
                local have = CountItem(id)
                if have ~= nil and have <= 0 then
                    outOfItem = true
                    break
                end
                if PlaceCell(id, cell, farmAnchor.facing) then
                    farmStats.placed += 1
                end
                task.wait(0.1)
            end
        end
        if farmToken ~= token then
            break
        end
        task.wait(0.35)

        farmStats.status = "Break " .. ItemName(id)
        local before = DropSet(world)
        for _, cell in ipairs(cells) do
            if farmToken ~= token then
                break
            end
            if TileValue(world, layer, cell.x, cell.y) == id then
                if BreakCell(world, id, cell, token) then
                    farmStats.broken += 1
                end
            end
        end
        if farmToken ~= token then
            break
        end

        if Config.farmTake then
            farmStats.status = "Ambil item"
            task.wait(0.3)
            farmStats.picked += CollectDrops(world, farmAnchor, before, token)
        end

        farmStats.cycles += 1

        if outOfItem then
            farmStats.status = "Item habis"
            Notify("Auto Farm berhenti: " .. ItemName(id) .. " habis di inventory.")
            break
        end
        task.wait(0.1)
    end
end

function StopFarm()
    if not farmOn then
        return false
    end
    farmToken += 1
    farmOn = false
    farmStats.status = "Mati"
    return true
end

function StartFarm()
    if farmOn then
        return true
    end
    local id = Config.farmPlaceId
    if type(id) ~= "number" or id <= 0 or ItemName(id) == "?" then
        Notify("Isi ID block dulu di GUI Auto Farm (" .. Config.prefix .. "af).")
        return false
    end
    local selected = 0
    local reach = 0
    for key, on in pairs(Config.farmGrid) do
        local dx, dy = tostring(key):match("^(-?%d+),(-?%d+)$")
        if on and dx and dy then
            selected += 1
            reach = math.max(reach, math.abs(tonumber(dx)), math.abs(tonumber(dy)))
        end
    end
    if selected < 1 then
        Notify("Pilih minimal 1 kotak di grid Auto Farm (" .. Config.prefix .. "af).")
        return false
    end
    if not (FindGameFn("hit") and FindGameFn("setTile")) then
        Notify("Fungsi hit/place game tidak ditemukan (executor perlu getgc + debug.info).")
        return false
    end
    local x, y, facing = GetGridState()
    if not x then
        Notify("Posisi tidak terdeteksi!")
        return false
    end

    local inv = FindInventory()
    local needed = reach + 0.05
    local okRange, range = pcall(function()
        return inv.buildRange()
    end)
    if okRange and type(range) == "number" and range < needed then
        if longhandOn then
            StopLonghand()
        end
        Config.longhandRange = math.max(Config.longhandRange, math.clamp(math.ceil(needed - 2.5), 1, 20))
        ApplyLonghand()
        Notify("Longhand otomatis aktif (" .. Config.longhandRange .. " tile) supaya target terjangkau.")
    end

    farmAnchor = {
        x = math.floor(x),
        y = math.floor(y - 0.475),
        facing = facing,
        world = CurrentWorldName(),
    }
    farmToken += 1
    local token = farmToken
    farmOn = true
    farmStats = { status = "Mulai", placed = 0, broken = 0, picked = 0, cycles = 0 }

    task.spawn(function()
        local ok, err = pcall(FarmLoop, token)
        if not ok then
            warn(err)
            Notify("Auto Farm error: " .. tostring(err))
        end
        if farmToken == token then
            farmOn = false
            if farmStats.status ~= "Item habis" then
                farmStats.status = "Mati"
            end
            if RefreshHub then
                RefreshHub()
            end
        end
    end)
    return true
end

----------------------------------------------------------------------
-- PATHFINDING + CLICK TP
----------------------------------------------------------------------
do
    local function Passable(db, world, x, y)
        if not InBounds(world, x, y) then
            return false
        end
        local id = TileValue(world, "fg", x, y)
        if id == nil then
            return false
        end
        if id == 0 then
            return true
        end
        local item = db and db[id]
        if type(item) ~= "table" then
            return false
        end
        if item.hurts or item.deadly then
            return false
        end
        if item.combiner then
            local okC, shut = pcall(function()
                return world.combinerShut(x, y)
            end)
            return okC and not shut
        end
        if item.entrance then
            local sw = nil
            local okS, sws = pcall(function()
                return world.switches
            end)
            if okS and type(sws) == "table" then
                sw = sws[y * world.w + x]
            end
            if item.gate then
                return sw ~= nil and sw.off == true
            end
            if sw and sw.public then
                return true
            end
            local okA, may = pcall(function()
                return world.areas.mayBuild(world.lock, x, y)
            end)
            return okA and may and true or false
        end
        return not item.solid
    end

    Nav.Passable = Passable

    function Nav.Find(sx, sy, tx, ty)
        local world = FindWorld()
        local db = GetItemDB()
        if not world or type(rawget(world, "w")) ~= "number" then
            return nil, "world"
        end
        local W = world.w

        if not Passable(db, world, tx, ty) then
            local best, bestD = nil, math.huge
            for r = 1, 3 do
                for dy = -r, r do
                    for dx = -r, r do
                        local nx, ny = tx + dx, ty + dy
                        if math.max(math.abs(dx), math.abs(dy)) == r and Passable(db, world, nx, ny) then
                            local d = math.abs(dx) + math.abs(dy)
                            if d < bestD then
                                best, bestD = { nx, ny }, d
                            end
                        end
                    end
                end
                if best then
                    break
                end
            end
            if not best then
                return nil, "target"
            end
            tx, ty = best[1], best[2]
        end

        if sx == tx and sy == ty then
            return {}, tx, ty
        end

        local startKey = sy * W + sx
        local goalKey = ty * W + tx
        local parent = { [startKey] = -1 }
        local queue, head = { startKey }, 1
        local found = false
        while head <= #queue do
            local key = queue[head]
            head += 1
            if key == goalKey then
                found = true
                break
            end
            local x, y = key % W, key // W
            local neighbors = { { x, y - 1 }, { x, y + 1 }, { x - 1, y }, { x + 1, y } }
            for _, n in ipairs(neighbors) do
                local nk = n[2] * W + n[1]
                if parent[nk] == nil and Passable(db, world, n[1], n[2]) then
                    parent[nk] = key
                    table.insert(queue, nk)
                end
            end
            if head % 800 == 0 then
                task.wait()
            end
        end
        if not found then
            return nil, "nopath"
        end

        local path, key = {}, goalKey
        while key ~= startKey do
            table.insert(path, 1, { x = key % W, y = key // W })
            key = parent[key]
        end
        return path, tx, ty
    end

    Nav.inDir = 0
    Nav.inJump = false
    Nav.hooked = false
    local VIM = nil
    pcall(function()
        VIM = game:GetService("VirtualInputManager")
    end)
    local keyState = {}
    local function PressKey(code, down)
        if not VIM or keyState[code] == down then
            return
        end
        keyState[code] = down
        pcall(function()
            VIM:SendKeyEvent(down, code, false, game)
        end)
    end

    local function FindControls()
        return ScanGc("controls", function(t)
            return type(rawget(t, "dir")) == "function"
                and type(rawget(t, "jumping")) == "function"
                and type(rawget(t, "punching")) == "function"
                and type(rawget(t, "busy")) == "function"
        end)
    end

    function Nav.InstallInput()
        if Nav.hooked then
            return true
        end
        local c = FindControls()
        if not c then
            return false
        end
        local origDir, origJump = c.dir, c.jumping
        c.dir = function(...)
            if Nav.inDir ~= 0 then
                return Nav.inDir
            end
            return origDir(...)
        end
        c.jumping = function(...)
            if Nav.inJump then
                return true
            end
            return origJump(...)
        end
        Nav.ctl, Nav.origDir, Nav.origJump = c, origDir, origJump
        Nav.hooked = true
        return true
    end

    function Nav.InputReady()
        return Nav.InstallInput() or VIM ~= nil
    end

    function Nav.SetInput(dir, jump)
        Nav.inDir = dir
        Nav.inJump = jump and true or false
        if not Nav.hooked then
            PressKey(Enum.KeyCode.Left, dir < 0)
            PressKey(Enum.KeyCode.Right, dir > 0)
            PressKey(Enum.KeyCode.Up, jump and true or false)
        end
    end

    local function Sign(n)
        return n > 0 and 1 or (n < 0 and -1 or 0)
    end

    function Nav.Walk(tx, ty, cancel)
        local started = os.clock()
        local world = FindWorld()
        if not world or type(rawget(world, "w")) ~= "number" then
            return false, "world"
        end
        if not Nav.InputReady() then
            return false, "input"
        end
        local sx, sy = GetTile()
        if not sx then
            return false, "pos"
        end
        local path, goalX, goalY = Nav.Find(sx, sy, tx, ty)
        if not path then
            return false, goalX
        end
        local W = world.w
        local timeout = math.clamp(8 + (math.abs(goalX - sx) + math.abs(goalY - sy)) * 0.6, 8, 90)
        local result, why = false, "stuck"

        local ok, err = pcall(function()
            local cur, pos = path, {}
            local function Rebuild(x, y)
                pos = { [y * W + x] = 0 }
                for i, n in ipairs(cur) do
                    pos[n.y * W + n.x] = i
                end
            end
            Rebuild(sx, sy)

            local prevPx, prevClock = nil, os.clock()
            local refX, refY, refT = nil, nil, os.clock()
            local lastReplan, replans, bestIdx = 0, 0, -1
            local pressSince = nil

            while true do
                if cancel and cancel() then
                    why = "cancel"
                    return
                end
                local now = os.clock()
                if now - started > timeout then
                    why = "timeout"
                    return
                end
                local px, py = GetGridState()
                if not px then
                    why = "pos"
                    return
                end
                local cx, cy = math.floor(px), math.floor(py - 0.475)
                local dt = math.max(now - prevClock, 1 / 240)
                local vx = prevPx and (px - prevPx) / dt or 0
                prevPx, prevClock = px, now

                if not refX or math.abs(px - refX) > 0.4 or math.abs(py - refY) > 0.4 then
                    refX, refY, refT = px, py, now
                elseif now - refT > 2.2 then
                    why = "stuck"
                    return
                end

                if cx == goalX and cy == goalY and math.abs(vx) < 1.5 then
                    result = true
                    return
                end

                local idx = pos[cy * W + cx]
                if idx == nil then
                    Nav.SetInput(0, false)
                    if now - lastReplan >= 0.12 then
                        lastReplan = now
                        replans += 1
                        if replans > 40 then
                            why = "stuck"
                            return
                        end
                        local p2 = Nav.Find(cx, cy, goalX, goalY)
                        if not p2 then
                            why = "nopath"
                            return
                        end
                        cur = p2
                        Rebuild(cx, cy)
                    end
                    RunService.Heartbeat:Wait()
                    continue
                end
                if idx > bestIdx then
                    bestIdx, replans = idx, 0
                end

                local node = cur[idx + 1]
                if not node then
                    Nav.SetInput(0, false)
                    RunService.Heartbeat:Wait()
                    continue
                end

                local dx, dy = node.x - cx, node.y - cy
                local inDir, jump = 0, false
                if dx ~= 0 then
                    inDir = dx
                else
                    local off = (cx + 0.5) - px
                    if math.abs(off) > 0.18 then
                        inDir = Sign(off)
                    end
                end
                if dy < 0 then
                    jump = true
                end
                if idx + 1 == #cur and dx ~= 0 then
                    local dist = (node.x + 0.5 - px) * dx
                    if dist < (vx * vx) / 80 + 0.1 then
                        inDir = 0
                    end
                end
                if inDir ~= 0 then
                    pressSince = pressSince or now
                    if dx ~= 0 and now - pressSince > 0.18 and math.abs(vx) < 0.6 then
                        jump = true
                    end
                else
                    pressSince = nil
                end
                Nav.SetInput(inDir, jump)
                RunService.Heartbeat:Wait()
            end
        end)
        Nav.SetInput(0, false)
        if not ok then
            warn(err)
            return false, "error"
        end
        if result then
            return true, os.clock() - started
        end
        return false, why
    end

    local function HopRange()
        local lo = math.clamp(math.floor(tonumber(Config.hopMin) or 3), 1, 8)
        local hi = math.clamp(math.floor(tonumber(Config.hopMax) or 5), lo, 10)
        return lo, hi
    end

    local function HopWait()
        task.wait(math.clamp(tonumber(Config.hopDelay) or 0.12, 0.03, 1))
    end

    function Nav.Fly(tx, ty, cancel)
        local started = os.clock()
        local world = FindWorld()
        if not world or type(world.goTo) ~= "function" then
            return false, "world"
        end
        local sx, sy = GetTile()
        if not sx then
            return false, "pos"
        end
        local db = GetItemDB()
        if not InBounds(world, tx, ty) then
            return false, "target"
        end
        if not Passable(db, world, tx, ty) then
            local best, bestD = nil, math.huge
            for r = 1, 3 do
                for dy = -r, r do
                    for dx = -r, r do
                        local nx, ny = tx + dx, ty + dy
                        if math.max(math.abs(dx), math.abs(dy)) == r and Passable(db, world, nx, ny) then
                            local d = math.abs(dx) + math.abs(dy)
                            if d < bestD then
                                best, bestD = { nx, ny }, d
                            end
                        end
                    end
                end
                if best then
                    break
                end
            end
            if not best then
                return false, "target"
            end
            tx, ty = best[1], best[2]
        end

        local dx, dy = tx - sx, ty - sy
        local len = math.sqrt(dx * dx + dy * dy)
        local lo, hi = HopRange()
        local cancelled = false
        local prevGhost = world.ghost
        world.ghost = true
        local okFly = pcall(function()
            local travelled = 0
            while travelled < len do
                if cancel and cancel() then
                    cancelled = true
                    return
                end
                travelled = math.min(len, travelled + math.random(lo, hi))
                local x = sx + math.floor(dx * travelled / len + 0.5)
                local y = sy + math.floor(dy * travelled / len + 0.5)
                pcall(world.goTo, x, y)
                HopWait()
            end
        end)
        world.ghost = (noclipOn == true) or (Player:GetAttribute("Ghost") == true)
        if cancelled then
            return false, "cancel"
        end
        if not okFly then
            world.ghost = prevGhost
            return false, "fly"
        end
        pcall(world.goTo, tx, ty)
        return true, os.clock() - started
    end

    function Nav.Hop(tx, ty, cancel)
        local started = os.clock()
        local world = FindWorld()
        if not world or type(world.goTo) ~= "function" then
            return false, "world"
        end
        local sx, sy = GetTile()
        if not sx then
            return false, "pos"
        end
        local path, a, b = Nav.Find(sx, sy, tx, ty)
        if not path then
            return false, a
        end
        local goalX, goalY = a, b
        local lo, hi = HopRange()
        local rejected = 0
        local i = 0
        while i < #path do
            if cancel and cancel() then
                return false, "cancel"
            end
            local j = math.min(#path, i + math.random(lo, hi))
            local node = path[j]
            pcall(world.goTo, node.x, node.y)
            HopWait()
            local cx, cy = GetTile()
            if cx and (cx ~= node.x or math.abs(cy - node.y) > 1) then
                rejected += 1
                if rejected > 8 then
                    return false, "rejected"
                end
                hi = math.max(1, hi - 1)
                lo = math.min(lo, hi)
                local p2 = Nav.Find(cx, cy, goalX, goalY)
                if not p2 then
                    return false, "nopath"
                end
                path, i = p2, 0
            else
                i = j
            end
        end
        return true, os.clock() - started
    end

    function Nav.Tele(tx, ty, cancel)
        local ok, info = Nav.Hop(tx, ty, cancel)
        if ok or info == "cancel" then
            return ok, info
        end
        return Nav.Fly(tx, ty, cancel)
    end

    function Nav.Go(tx, ty, cancel)
        local mode = Config.moveMode
        if mode == "fly" then
            return Nav.Fly(tx, ty, cancel)
        elseif mode == "tp" then
            return Nav.Tele(tx, ty, cancel)
        elseif mode == "walk" then
            return Nav.Walk(tx, ty, cancel)
        end
        local ok, info = Nav.Walk(tx, ty, cancel)
        if ok or info == "cancel" then
            return ok, info
        end
        return Nav.Fly(tx, ty, cancel)
    end

    function Nav.To(x, y, cancel)
        local world = FindWorld()
        if not world then
            return false
        end
        local ok = Nav.Go(x, y, cancel)
        return ok
    end

    local actFn = nil
    local function CamInfo()
        if not actFn then
            if not getgcFn or not (debug and debug.info) then
                return nil
            end
            for _, fn in ipairs(getgcFn(true)) do
                if type(fn) == "function" then
                    local okName, fnName = pcall(debug.info, fn, "n")
                    if okName and fnName == "act" then
                        local ups = GetUpvalues(fn)
                        if ups[1] == Players and type(ups[2]) == "number"
                            and type(ups[4]) == "number" and type(ups[5]) == "number" then
                            actFn = fn
                            break
                        end
                    end
                end
            end
        end
        if not actFn then
            return nil
        end
        local okX, camX = pcall(getupvalueFn, actFn, 2)
        local okT, tile = pcall(getupvalueFn, actFn, 4)
        local okY, camY = pcall(getupvalueFn, actFn, 5)
        if okX and okT and okY and type(camX) == "number" and type(tile) == "number"
            and type(camY) == "number" and tile > 0 then
            return camX, camY, tile
        end
        return nil
    end

    function Nav.ScreenToTile(pos)
        local camX, camY, tile = CamInfo()
        if not camX then
            return nil
        end
        local worldGui = PlayerGui:FindFirstChild("World", true)
        if not worldGui or not worldGui:IsA("GuiObject") then
            return nil
        end
        local scaleObj = worldGui:FindFirstChildWhichIsA("UIScale", true)
        local scale = scaleObj and scaleObj.Scale or 1
        local rel = (Vector2.new(pos.X, pos.Y) - worldGui.AbsolutePosition) / scale
        return math.floor(camX + rel.X / tile), math.floor(camY + rel.Y / tile)
    end

    local function OnClick(input, processed)
        if processed or not Nav.clickOn then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        if Config.clickTpShift and not (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
            return
        end
        local tx, ty = Nav.ScreenToTile(input.Position)
        if not tx then
            Notify("Click TP: posisi klik tidak terbaca.")
            return
        end
        Nav.token += 1
        local token = Nav.token
        task.spawn(function()
            local started = os.clock()
            local ok, info = Nav.Go(tx, ty, function()
                return Nav.token ~= token or not Nav.clickOn
            end)
            if ok then
                Nav.last = string.format("PATH FINDING in %.2fs", os.clock() - started)
                Notify(Nav.last)
            elseif info == "cancel" then
                return
            else
                Nav.last = "Gagal (" .. tostring(info) .. ")"
                if info == "nopath" then
                    Notify("PATH FINDING gagal: tidak ada jalan ke sana.")
                elseif info == "target" then
                    Notify("PATH FINDING gagal: tujuan tertutup block.")
                else
                    Notify("PATH FINDING gagal: " .. tostring(info))
                end
            end
        end)
    end

    function Nav.StartClick()
        if Nav.clickOn then
            return true
        end
        if not CamInfo() then
            Notify("Click TP: data kamera game tidak ditemukan (executor perlu getgc + debug.info).")
            return false
        end
        Nav.clickOn = true
        Nav.conn = UserInputService.InputBegan:Connect(OnClick)
        return true
    end

    function Nav.StopClick()
        if not Nav.clickOn then
            return false
        end
        Nav.clickOn = false
        Nav.token += 1
        if Nav.conn then
            Nav.conn:Disconnect()
            Nav.conn = nil
        end
        return true
    end
end
