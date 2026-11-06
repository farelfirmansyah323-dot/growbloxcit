--[[
    Peex HUB | GrowBlox  (v9.2 - Auto DF, Pathfinding, tanpa Key System)  +  GUI Redesign
    Perbaikan v9.1: GUI dipasang lewat gethui()/CoreGui (fallback PlayerGui),
    ScanGc dibatasi (anti-lag mobile), pengaman bangun-ulang GUI.
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
      af|autofarm [on|off]   GUI Auto Farm (kecepatan pukulan, ID block, grid 5x5)
      ac|autoclear [on|off]  Auto Clear World (GrowScan, grup 1-4 tile, mode jalan/teleport, ambil drop)
      df|autodf [on|off]     Auto DF: dig ke bawah (break block di bawah karakter)
      ctp|clicktp [on|off]   Click TP: klik mana saja, jalan lewat path (tampil seperti teleport)
      move|mv <walk|fly|mix> Mode gerak: jalan / terbang / campur
      spam [on|off]          Kirim teks spam ke chat berulang
      setspam <teks>         Atur teks spam
      aq|autoquest [on|off|scan]  Auto quest (claim + kerjakan quest break/place)
      gs|growscan            Buka GrowScan
      god [on|off]           God mode (kebal lava, spike, api)
      blockid|bid <nama>     Cari ID block dari nama
      hpx                    Daftar fitur

    SESI: fitur aktif, Pos 1/2 & world terakhir disimpan ke file dan dipulihkan
    otomatis setelah ganti world / rejoin / buka Roblox lagi.
    Simpan skrip ini di folder workspace executor dengan nama
    "PeexHub_GrowBlox.lua" (atau isi URL di tab Sesi) supaya auto-reload jalan.
]]

-- Cegah dobel-eksekusi (hanya blok kalau GUI-nya benar-benar masih ada)
local genv = (getgenv and getgenv()) or _G

local function FindExistingGui()
    local parents = {}
    pcall(function()
        if gethui then
            table.insert(parents, gethui())
        end
    end)
    pcall(function()
        table.insert(parents, game:GetService("CoreGui"))
    end)
    pcall(function()
        table.insert(parents, game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"))
    end)
    for _, parent in ipairs(parents) do
        local ok, found = pcall(function()
            return parent:FindFirstChild("PeexHubGB")
        end)
        if ok and found then
            return found
        end
    end
    return nil
end

do
    local alive = FindExistingGui()
    if genv.PeexHubGB_Loaded and alive then
        pcall(function()
            alive.Enabled = true
            local launcher = alive:FindFirstChild("Launcher")
            if launcher then
                launcher.Visible = true
            end
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "Peex HUB | GrowBlox",
                Text = "Sudah aktif. Tekan tombol P atau ketik /hpx.",
                Duration = 4,
            })
        end)
        return
    end
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

-- Jangan menahan seluruh skrip kalau remote game belum ada (tanpa yield)
local worldRemotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
local DropEvent = worldRemotes and worldRemotes:FindFirstChild("DropItem")

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
    winDrop = 0, -- jumlah WL otomatis di-drop setelah /win (0 = mati)
    pos1 = {},
    pos2 = {},
    -- Sesi
    autoRestore = true, -- pulihkan fitur yang aktif sebelumnya
    autoReload = true,  -- jalankan ulang skrip otomatis setelah teleport / rejoin
    autoWarp = false,   -- masuk lagi ke world terakhir setelah buka Roblox
    launcher = true,    -- tombol P melayang
    lastWorld = "",
    scriptUrl = "",     -- opsional: URL skrip untuk auto-reload
    session = {},       -- fitur yang sedang aktif (key -> true)
    -- Auto Farm
    farmDelay = 0.22,   -- jeda antar pukulan (detik)
    farmPlaceId = 0,    -- ID block yang di-place
    farmGrid = { ["1,0"] = true }, -- kotak 5x5 (dx,dy dari posisi player) yang di-place
    farmTake = true,    -- teleport ambil item setelah break
    -- Auto Clear World
   clearBreakDelay = 0.22, -- jeda antar putaran pukulan (detik); game sendiri memukul tiap 0.22 dtk
    clearBatch = 2,         -- jumlah block yang dipukul tiap putaran (1-4)
    clearTpDelay = 0.25,    -- jeda setelah teleport (detik)
    clearTake = true,       -- ambil item drop otomatis
    walkBatch = 3,          -- (lama, diganti clearPunch)
    clearPunch = 3,         -- Auto Clear & Dirt Farm: jumlah block yang dipukul SEKALIGUS (1-3)
    -- Spam Chat
    spamText = "",         -- teks yang dikirim berulang (isi lewat /setspam atau tab Spam)
    spamDelay = 3,          -- jeda antar pesan (detik, minimal 1.5)
    -- Pathfinding / Click TP
    navPath = true,         -- (lama, tidak dipakai lagi; diganti moveMode)
    moveMode = "mix",       -- "walk" = jalan lewat path | "fly" = terbang lurus tembus block | "mix" = jalan dulu, kalau buntu terbang
    navSpeed = 2,           -- jumlah tile per frame saat menyusuri path (1-12)
    clickTpShift = false,   -- Click TP hanya aktif kalau tahan Shift kiri atau kanan (PC)
    -- Auto DF (dig ke bawah)
    dfDelay = 0.22,         -- jeda antar pukulan (detik)
    dfFlip = false,         -- true kalau arah "bawah" ternyata terbalik di game
}

local SCRIPT_FILE = "PeexHub_GrowBlox.lua"
local QueueReload -- didefinisikan di bagian sesi

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
-- Migrasi nilai default lama (2 tile) ke default baru (3 tile).
if Config.clearBatch == 2 then
    Config.clearBatch = 3
    SaveConfig()
end
if Config.clearMoveMode ~= "walk" and Config.clearMoveMode ~= "teleport" then
    Config.clearMoveMode = "walk"
end

----------------------------------------------------------------------
-- UTIL
----------------------------------------------------------------------
local ToastHook = nil -- diisi oleh bagian GUI

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
local cache = { _scan = {} }

local function ScanGc(name, check)
    local cached = cache[name]
    if cached and check(cached) then
        return cached
    end
    if not getgcFn then
        return nil
    end
    -- jangan scan memori lebih sering dari tiap 3 detik (anti-lag di mobile)
    local now = os.clock()
    local last = cache._scan[name]
    if last and now - last < 3 then
        return nil
    end
    cache._scan[name] = now
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

-- Tabel inventory (onDrop, canDrop, isWorn, buildRange, refresh)
local function FindInventory()
    return ScanGc("inventory", function(t)
        return type(rawget(t, "onDrop")) == "function"
            and type(rawget(t, "canDrop")) == "function"
            and type(rawget(t, "isWorn")) == "function"
    end)
end

-- Tabel world (enter, dropOk, goTo, name, ghost)
local function FindWorld()
    return ScanGc("world", function(t)
        return type(rawget(t, "enter")) == "function"
            and type(rawget(t, "dropOk")) == "function"
    end)
end

-- Rig karakter lokal: [1] hadap kanan, [-1] hadap kiri, [0] portrait
local function FindRigs()
    return ScanGc("rigs", function(t)
        local a, b = rawget(t, 1), rawget(t, -1)
        return type(a) == "table" and type(b) == "table"
            and typeof(rawget(a, "body")) == "Instance"
            and typeof(rawget(b, "head")) == "Instance"
    end)
end

-- Tabel item yang sedang dipakai (slot -> id), upvalue dari isWorn
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
-- POSISI GRID (canDrop -> world, x, facing | onDrop -> x, facing, y)
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

-- Koordinat tile (sama dengan yang dipakai game: baris = floor(y - 0.475))
local function GetTile()
    local x, y = GetGridState()
    if not x then
        return nil
    end
    return math.floor(x), math.floor(y - 0.475)
end

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
        if not DropEvent then
            local remotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
            DropEvent = remotes and remotes:FindFirstChild("DropItem")
        end
        assert(DropEvent, "Remote WorldRemotes.DropItem belum ditemukan")
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
-- WARP ANTAR WORLD (/tp, /warp) -> world.enter milik game
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
-- POS1 / POS2 + WIN1 / WIN2  (teleport dalam world lewat world.goTo)
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

    local ok, err = pcall(world.goTo, pos.x, pos.y)
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
        task.wait(0.4) -- tunggu posisi game ter-update
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
-- REJOIN (masuk ulang ke world yang sama)
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
    -- Game membaca teleport data { world = "NAMA" } saat tiba di server baru
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
-- BLINK SKIN (warna skin ganti otomatis)
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
-- LONGHAND (jangkauan punch & build lebih jauh)
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

    -- Game: range = reach/build item terbaik + 2.5
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
-- NOCLIP (memakai mode "ghost" bawaan game: tembus blok + terbang)
-- Naik = tombol lompat, turun = panah bawah / S.
-- Selama aktif: tidak bisa ambil drop / sentuh blok (aturan mode ghost game).
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
            w.ghost = true -- game bisa mereset lewat atribut "Ghost"
        end
    end)
    return true
end

----------------------------------------------------------------------
-- UNLIMITED JUMP
-- Game: lompat udara hanya jika memakai item doubleJump dan flag "sudah
-- lompat udara" (upvalue di RenderStepped) belum terpakai. Flag itu di-reset
-- tiap frame. Kalau tidak memakai sayap, fungsi cek sayap dibungkus supaya
-- tetap dianggap punya item doubleJump (tanpa tampilan sayap).
----------------------------------------------------------------------
local ujumpOn = false
local ujumpConn = nil
local ujumpFn = nil
local ujumpWingsOriginal = nil
local JUMP_FLAG_INDEX = 27 -- upvalue "airJumpUsed" pada closure RenderStepped
local WINGS_INDEX = 29     -- upvalue fungsi wornWings

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
-- VISUAL ITEM (hanya tampilan lokal)
----------------------------------------------------------------------
local visualBackup = {} -- slot -> id asli (atau false kalau kosong)

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
-- FEATURE SETTERS (dipakai GUI & command)
----------------------------------------------------------------------
-- ANTI AFK
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

-- AUTO REJOIN (saat muncul layar error / disconnect)
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

local RefreshHub -- didefinisikan di bagian GUI

local SearchItems, ItemName, StartFarm, StopFarm, StartQuest, StopQuest, QuestReport, StartGod, StopGod, OpenNativeGrowScan, ScanWorld
local farmOn, questOn, godOn = false, false, false
local Nav = { clickOn = false, token = 0, conn = nil, last = "-" }
local Clear = { on = false, token = 0, status = "Mati", stats = { scanned = 0, broken = 0, picked = 0, skipped = 0, left = 0, pass = 0 } }
local Dig = { on = false, token = 0, status = "Mati", stats = { broken = 0, depth = 0 } }
local questStatus = "Mati"
local farmStats = { status = "Mati", placed = 0, broken = 0, picked = 0, cycles = 0 }
do
----------------------------------------------------------------------
-- DATABASE ITEM (diambil langsung dari ItemDB game) + PENCARIAN
-- Cari pakai nama (sebagian) atau ID. Hasil diurutkan dari yang paling cocok.
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
-- AKSES FUNGSI GAME: hit (pukulan), setTile (place), backpack
-- Dicari lewat getgc: fungsi bernama "hit"/"setTile" yang memegang tabel world.
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
-- Siklus: place block di semua sel target -> pukul sampai pecah ->
-- teleport ambil item yang jatuh -> kembali ke posisi awal.
-- Sel target: N tile ke depan (arah hadap) dan/atau N tile ke atas.
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
    -- urut dari atas ke bawah, kiri ke kanan
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

-- Ambil hanya drop yang muncul selama siklus ini (bukan drop lama / punya orang lain)
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

        -- pastikan di posisi awal
        local tx, ty = GetTile()
        if tx ~= farmAnchor.x or ty ~= farmAnchor.y then
            Nav.To(farmAnchor.x, farmAnchor.y, function() return farmToken ~= token end)
            task.wait(0.15)
        end

        -- 1) place
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
        task.wait(0.35) -- game menolak pukulan ke tile yang baru di-place < 0.3 detik

        -- 2) break
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

        -- 3) ambil item
        if Config.farmTake then
            farmStats.status = "Ambil item"
            task.wait(0.3) -- drop muncul sedikit setelah tile pecah
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

    -- Jangkauan: naikkan lewat Longhand kalau target lebih jauh dari range game
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
-- Teleport langsung (world.goTo ke tempat jauh) ditolak kalau jalannya
-- tertutup block. Jadi: cari rute lewat tile yang bisa dilewati (BFS), lalu
-- gerakkan karakter tile demi tile sangat cepat sampai tujuan. Dari sisi
-- pemain hasilnya terlihat seperti teleport singkat.
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
        if item.combiner then
            local okC, shut = pcall(function()
                return world.combinerShut(x, y)
            end)
            return okC and not shut
        end
        if item.entrance then
            -- Pintu/gerbang: sama seperti solidAt milik game. Bisa dilewati kalau
            -- punya akses build di area itu, pintunya publik, atau gate sedang terbuka.
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

    -- Cari rute terpendek (4 arah) dari (sx,sy) ke (tx,ty)
    function Nav.Find(sx, sy, tx, ty)
        local world = FindWorld()
        local db = GetItemDB()
        if not world or type(rawget(world, "w")) ~= "number" then
            return nil, "world"
        end
        local W = world.w

        -- tujuan tidak bisa dilewati (mis. diklik di atas block) -> tile kosong terdekat
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
                task.wait() -- world besar: jangan bikin freeze
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

    -- JALAN: cari rute lewat tile kosong lalu telusuri. Return: ok, detik (atau alasan gagal)
    function Nav.Walk(tx, ty, cancel)
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
        local perFrame = math.clamp(math.floor(tonumber(Config.navSpeed) or 2), 1, 12)
        local count = 0
        for _, node in ipairs(path) do
            if cancel and cancel() then
                return false, "cancel"
            end
            pcall(world.goTo, node.x, node.y)
            count += 1
            if count >= perFrame then
                count = 0
                RunService.Heartbeat:Wait()
            end
        end
        return true, os.clock() - started
    end

    -- TERBANG: garis lurus ke tujuan, tembus block (mode ghost dinyalakan hanya
    -- selama terbang, lalu dikembalikan supaya bisa ambil drop / pukul block).
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
        -- tujuan tertutup block -> tile kosong terdekat
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
        local steps = math.max(math.abs(dx), math.abs(dy))
        local perFrame = math.clamp(math.floor(tonumber(Config.navSpeed) or 2), 1, 12)
        local cancelled = false
        local prevGhost = world.ghost
        world.ghost = true
        local okFly = pcall(function()
            local count = 0
            for i = 1, steps do
                if cancel and cancel() then
                    cancelled = true
                    return
                end
                local x = sx + math.floor(dx * i / steps + 0.5)
                local y = sy + math.floor(dy * i / steps + 0.5)
                pcall(world.goTo, x, y)
                count += 1
                if count >= perFrame then
                    count = 0
                    RunService.Heartbeat:Wait()
                end
            end
        end)
        -- kembalikan mode ghost seperti semula (noclip / atribut Ghost tetap dihormati)
        world.ghost = (noclipOn == true) or (Player:GetAttribute("Ghost") == true)
        if cancelled then
            return false, "cancel"
        end
        if not okFly then
            world.ghost = prevGhost
            return false, "fly"
        end
        -- mendarat di tile tujuan dengan ghost sudah mati
        pcall(world.goTo, tx, ty)
        return true, os.clock() - started
    end

    -- Pindah sesuai mode (Config.moveMode): walk / fly / mix
    function Nav.Go(tx, ty, cancel)
        local mode = Config.moveMode
        if mode == "fly" then
            return Nav.Fly(tx, ty, cancel)
        elseif mode == "walk" then
            return Nav.Walk(tx, ty, cancel)
        end
        -- mix: jalan dulu; kalau tidak ada jalan, terbang
        local ok, info = Nav.Walk(tx, ty, cancel)
        if ok or info == "cancel" then
            return ok, info
        end
        return Nav.Fly(tx, ty, cancel)
    end

    -- Dipakai Auto Farm / Auto Clear
    function Nav.To(x, y, cancel)
        local world = FindWorld()
        if not world then
            return false
        end
        local ok = Nav.Go(x, y, cancel)
        return ok
    end

    -- Data kamera dari fungsi game "act" (upvalue: kamera X, ukuran tile, kamera Y)
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

    -- Posisi layar -> tile (rumus sama dengan klik bawaan game)
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
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
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

----------------------------------------------------------------------
-- AUTO CLEAR WORLD
-- Prioritas pukul: Dirt -> Cave -> block lainnya.
-- 1) GrowScan dulu (hitung isi world) -> 2) kumpulkan semua tile yang boleh
-- dipecah (lock, area & bedrock DILEWATI; bg di balik bedrock ikut dilewati) -> 3) bergerak ke dekat grup hingga 3 tile
-- -> 4) pukul tile dalam grup SEKALIGUS -> 5) ambil item drop.
-- Mode gerak (jalan/teleport) dan delay bisa diatur di tab Clear.
----------------------------------------------------------------------
do
    local function BatchSize()
        return math.clamp(math.floor(tonumber(Config.clearBatch) or 3), 1, 4)
    end

    -- Tile yang TIDAK boleh dipecah: lock, area, bedrock, hits <= 0, door utama
    local function IsBedrock(db, id)
        if tonumber(id) == 10 then
            return false
        end
        local item = db and db[id]
        if type(item) ~= "table" then
            return false
        end
        local name = type(item.name) == "string" and item.name:lower() or ""
        return name:find("bedrock", 1, true) ~= nil
    end

    local function Protected(db, id)
        -- Rock memakai ID 10 dan harus tetap bisa dipukul.
        if tonumber(id) == 10 then
            return false
        end
        local item = db and db[id]
        if type(item) ~= "table" then
            return true
        end
        if item.lock or item.area then
            return true
        end
        if type(item.hits) == "number" and item.hits <= 0 then
            return true
        end
        local name = type(item.name) == "string" and item.name:lower() or ""
        if name:find("bedrock", 1, true) or name:find("main door", 1, true)
            or name:find("white door", 1, true) or name:find("world lock", 1, true) then
            return true
        end
        return false
    end

    local function Alive(world, t)
        return TileValue(world, t.layer, t.x, t.y) == t.id
    end

    -- Foreground diproses lebih dulu. Background/cave hanya boleh diproses
    -- setelah foreground kosong. Jika foreground adalah bedrock, seluruh
    -- koordinat dikunci: background ID 14 atau background lain tidak disentuh.
    local function Collect(world, db, fails)
        local list = {}
        for y = 0, world.h - 1 do
            for x = 0, world.w - 1 do
                local f = TileValue(world, "fg", x, y)
                local skipCoordinate = false

                if f and f ~= 0 then
                    if tonumber(f) == 10 then
                        -- Rock ID 10 selalu masuk target foreground,
                        -- walaupun metadata ItemDB tidak lengkap/berbeda.
                        table.insert(list, { x = x, y = y, id = 10, layer = "fg" })
                        skipCoordinate = true
                    elseif IsBedrock(db, f) then
                        -- Jangan pernah mencoba cave/background di balik bedrock.
                        skipCoordinate = true
                    elseif not Protected(db, f) then
                        table.insert(list, { x = x, y = y, id = f, layer = "fg" })
                        -- Selama foreground masih ada, background menunggu.
                        skipCoordinate = true
                    else
                        -- Lock/area/door tetap dilindungi; background boleh
                        -- diproses seperti perilaku sebelumnya.
                        skipCoordinate = false
                    end
                end

                if not skipCoordinate then
                    local b = TileValue(world, "bg", x, y)
                    if tonumber(b) == 10 then
                        table.insert(list, { x = x, y = y, id = 10, layer = "bg" })
                    elseif b and b ~= 0 and not Protected(db, b) then
                        table.insert(list, { x = x, y = y, id = b, layer = "bg" })
                    end
                end
            end
        end
        -- Prioritas global: Dirt -> Cave -> block lainnya.
        -- Setelah prioritas sama, gunakan urutan ular agar perpindahan tetap pendek.
        local function ClearPriority(tile)
            local item = db and db[tile.id]
            local name = type(item) == "table" and type(item.name) == "string"
                and item.name:lower() or ""
            if name:find("dirt", 1, true) then
                return 1
            elseif name:find("cave", 1, true) then
                return 2
            elseif tonumber(tile.id) == 10 or name:find("rock", 1, true) then
                return 3
            end
            return 3
        end

        for _, tile in ipairs(list) do
            tile.priority = ClearPriority(tile)
        end
        table.sort(list, function(p, q)
            if p.priority ~= q.priority then
                return p.priority < q.priority
            end
            if p.y ~= q.y then
                return p.y < q.y
            end
            if p.y % 2 == 0 then
                return p.x < q.x
            end
            return p.x > q.x
        end)
        return list
    end

    -- Bentuk grup maksimal sesuai Tile per grup; jangan campur urutan prioritas.
    local function MakeGroups(list, reach)
        local groups, used = {}, {}
        for i, first in ipairs(list) do
            if not used[i] then
                used[i] = true
                local g = { first }
                for j = i + 1, math.min(#list, i + 60) do
                    if #g >= BatchSize() then
                        break
                    end
                    local t = list[j]
                    if not used[j] and t.priority == first.priority
                        and math.abs(t.x - first.x) <= reach and math.abs(t.y - first.y) <= reach then
                        used[j] = true
                        table.insert(g, t)
                    end
                end
                table.insert(groups, g)
            end
        end
        return groups
    end

    -- Cari tile kosong tempat berdiri yang menjangkau semua tile di grup
    local function StandingSpot(world, group, reach)
        local cx, cy = group[1].x, group[1].y
        local best, bestDist = nil, math.huge
        for dy = -reach, reach do
            for dx = -reach, reach do
                local x, y = cx + dx, cy + dy
                if InBounds(world, x, y) and TileValue(world, "fg", x, y) == 0 then
                    local ok = true
                    for _, t in ipairs(group) do
                        if math.abs(t.x - x) > reach or math.abs(t.y - y) > reach then
                            ok = false
                            break
                        end
                    end
                    if ok then
                        local d = math.abs(dx) + math.abs(dy)
                        if d < bestDist then
                            best, bestDist = { x = x, y = y }, d
                        end
                    end
                end
            end
        end
        return best
    end

    -- Pukul HANYA tile di grup (1-4 tile sesuai pengaturan), satu putaran = 1 pukulan
    -- per tile. Tile dianggap pecah kalau sudah hilang dari world (dibaca langsung).
    local function BreakGroup(world, hit, group, token)
        local started = os.clock()
        local failed = {}
        while Clear.token == token do
            local any = false
            for _, t in ipairs(group) do
                if Alive(world, t) then
                    any = true
                    pcall(hit, t.x, t.y, true)
                end
            end
            if not any then
                break
            end
            if os.clock() - started > 8 then
                for _, t in ipairs(group) do
                    if Alive(world, t) then
                        table.insert(failed, t)
                    end
                end
                break
            end
            task.wait(math.max(0.03, Config.clearBreakDelay))
        end
        return failed
    end

    local function BreakUntilClear(world, hit, group, token)
        -- Jangan pernah tandai target yang masih ada sebagai selesai/terlewati.
        -- Ulangi pukulan di grup yang sama sampai semua tile benar-benar hilang.
        while Clear.token == token do
            local failed = BreakGroup(world, hit, group, token)
            if #failed == 0 then
                return {}
            end
            task.wait(0.25)
        end
        return group
    end

    -- Gerakan khusus Auto Clear, tidak memakai Config.moveMode global.
    -- Mode jalan tidak pernah fallback ke teleport; mode teleport memakai goTo langsung.
    local function MoveClearTo(x, y, token)
        if Clear.token ~= token then
            return false, "cancel"
        end
        if Config.clearMoveMode == "walk" then
            return Nav.Walk(x, y, function()
                return Clear.token ~= token
            end)
        end
        local world = FindWorld()
        if not world or type(rawget(world, "goTo")) ~= "function" then
            return false, "world"
        end
        local ok, err = pcall(world.goTo, x, y)
        return ok, err
    end

    local function TakeDrops(world, before, token, home)
        local ok, list = pcall(world.dropList)
        if not ok or type(list) ~= "table" then
            return 0
        end
        local targets = {}
        for _, drop in ipairs(list) do
            if (before == nil or not before[drop]) and type(drop.x) == "number"
                and type(drop.y) == "number" and not drop.pending then
                table.insert(targets, drop)
            end
        end
        local picked = 0
        for _, drop in ipairs(targets) do
            if Clear.token ~= token then
                break
            end
            if table.find(list, drop) then
                local reached = MoveClearTo(math.floor(drop.x), math.floor(drop.y), token)
                task.wait(math.max(0.03, Config.clearTpDelay))
                local waited = os.clock()
                while reached and Clear.token == token and table.find(list, drop) and os.clock() - waited < 0.8 do
                    task.wait(0.05)
                end
                if not table.find(list, drop) then
                    picked += 1
                end
            end
        end
        if home then
            MoveClearTo(home.x, home.y, token)
            task.wait(math.max(0.03, Config.clearTpDelay))
        end
        return picked
    end

    local function ClearLoop(token, home)
        local db = GetItemDB()
        local hit = FindGameFn("hit")
        local inv = FindInventory()
        if not db or not hit then
            Clear.status = "Fungsi game tidak ditemukan"
            return
        end

        local fails = {}
        local function Fail(t, n)
            local key = t.x .. "," .. t.y .. "," .. t.layer
            fails[key] = (fails[key] or 0) + (n or 1)
        end
        local pass = 0
        while Clear.token == token do
            pass += 1
            if Clear.token ~= token then
                return
            end
            local world = FindWorld()
            if not world or CurrentWorldName() ~= home.world then
                Clear.status = "World berubah, berhenti"
                Notify("Auto Clear berhenti: kamu pindah world.")
                return
            end

            -- 1) GROWSCAN dulu
            Clear.status = "GrowScan world..."
            Clear.stats.pass = pass
            local scan = ScanWorld()
            local fgTotal, bgTotal = 0, 0
            if scan then
                for _, n in pairs(scan.fg) do fgTotal += n end
                for _, n in pairs(scan.bg) do bgTotal += n end
            end
            local targets = Collect(world, db, fails)
            Clear.stats.scanned = #targets
            Clear.stats.left = #targets
            if pass == 1 then
                Notify(string.format("GrowScan: %d fg, %d bg. Target pecah: %d tile (lock & bedrock dilewati).",
                    fgTotal, bgTotal, #targets))
            end
            if #targets == 0 then
                break
            end

            -- 2) jangkauan
            local okRange, range = pcall(function() return inv.buildRange() end)
            local reach = 2
            if okRange and type(range) == "number" then
                reach = math.max(1, math.floor(range - 0.05))
            end
            reach = math.min(reach, 6)

            local groups = MakeGroups(targets, math.max(1, math.floor(reach / 2)))
            for index, group in ipairs(groups) do
                if Clear.token ~= token then
                    return
                end
                local spot = StandingSpot(world, group, reach)
                while not spot and Clear.token == token do
                    Clear.status = string.format("Menunggu posisi untuk target (%d,%d)", group[1].x, group[1].y)
                    task.wait(0.5)
                    spot = StandingSpot(world, group, reach)
                end
                if Clear.token ~= token then
                    return
                end
                if spot then
                    Clear.status = string.format("Break grup %d/%d (pass %d)", index, #groups, pass)
                    local px, py = GetTile()
                    local reachable = true
                    if px ~= spot.x or py ~= spot.y then
                        reachable = MoveClearTo(spot.x, spot.y, token)
                        task.wait(math.max(0.03, Config.clearTpDelay))
                    end
                    -- pastikan posisi player benar-benar sudah dekat grup (kalau tidak, pukulan meleset)
                    local function InReach()
                        local cx, cy = GetTile()
                        if not cx then
                            return false
                        end
                        for _, t in ipairs(group) do
                            if math.abs(t.x - cx) > reach or math.abs(t.y - cy) > reach then
                                return false
                            end
                        end
                        return true
                    end
                    if not reachable or not InReach() then
                        reachable = MoveClearTo(spot.x, spot.y, token)
                        task.wait(math.max(0.05, Config.clearTpDelay))
                        reachable = reachable and InReach()
                    end
                    while not reachable and Clear.token == token do
                        Clear.status = string.format("Mencari posisi untuk target (%d,%d)", group[1].x, group[1].y)
                        task.wait(0.5)
                        local retrySpot = StandingSpot(world, group, reach)
                        if retrySpot then
                            reachable = MoveClearTo(retrySpot.x, retrySpot.y, token)
                            task.wait(math.max(0.05, Config.clearTpDelay))
                            reachable = reachable and InReach()
                        end
                    end
                    if Clear.token ~= token then
                        return
                    end
                    local before = DropSet(world)
                    local failed = BreakUntilClear(world, hit, group, token)
                    local dirtBroken = #group - #failed
                    Clear.stats.broken += dirtBroken
                    Clear.stats.left = math.max(0, Clear.stats.left - dirtBroken + #failed)
                    if Config.clearTake and dirtBroken > 0 then
                        task.wait(0.25) -- drop muncul sedikit setelah tile pecah
                        Clear.status = "Ambil drop Dirt"
                        Clear.stats.picked += TakeDrops(world, before, token, nil)
                    end

                    -- Setelah foreground di lokasi ini pecah, langsung cek Cave
                    -- di background koordinat yang sama sebelum teleport ke lokasi berikutnya.
                    local caveGroup = {}
                    for _, t in ipairs(group) do
                        if Clear.token ~= token then
                            return
                        end
                        local bg = TileValue(world, "bg", t.x, t.y)
                        local item = bg and db[bg]
                        local name = type(item) == "table" and type(item.name) == "string"
                            and item.name:lower() or ""
                        if TileValue(world, "fg", t.x, t.y) == 0
                            and bg and bg ~= 0 and name:find("cave", 1, true)
                            and not Protected(db, bg)
                            and (fails[t.x .. "," .. t.y .. ",bg"] or 0) < 3 then
                            table.insert(caveGroup, {
                                x = t.x, y = t.y, id = bg, layer = "bg"
                            })
                        end
                    end

                    if #caveGroup > 0 then
                        Clear.status = "Pukul Cave di lokasi yang sama"
                        local caveBefore = DropSet(world)
                        local caveFailed = BreakUntilClear(world, hit, caveGroup, token)
                        local caveBroken = #caveGroup - #caveFailed
                        Clear.stats.broken += caveBroken
                        Clear.stats.left = math.max(0, Clear.stats.left - caveBroken + #caveFailed)
                        if Config.clearTake and caveBroken > 0 then
                            task.wait(0.25)
                            Clear.status = "Ambil drop Cave"
                            Clear.stats.picked += TakeDrops(world, caveBefore, token, nil)
                        end
                    end
                end
            end
        end

        -- sapuan terakhir: ambil semua sisa drop
        if Config.clearTake and Clear.token == token then
            Clear.status = "Ambil sisa item"
            local world = FindWorld()
            if world then
                Clear.stats.picked += TakeDrops(world, nil, token, home)
            end
        end
        local world = FindWorld()
        if world and Clear.token == token then
            MoveClearTo(home.x, home.y, token)
        end
        Clear.status = "Selesai"
        Notify(string.format("Auto Clear selesai: %d pecah, %d diambil, %d dilewati.",
            Clear.stats.broken, Clear.stats.picked, Clear.stats.skipped))
    end

    function Clear.Stop()
        if not Clear.on then
            return false
        end
        Clear.token += 1
        Clear.on = false
        Clear.status = "Mati"
        return true
    end

    function Clear.Start()
        if Clear.on then
            return true
        end
        if farmOn then
            StopFarm()
        end
        if not (FindGameFn("hit") and GetItemDB()) then
            Notify("Fungsi hit game tidak ditemukan (executor perlu getgc + debug.info).")
            return false
        end
        local x, y = GetGridState()
        if not x then
            Notify("Posisi tidak terdeteksi!")
            return false
        end
        local world = FindWorld()
        if not world or type(rawget(world, "w")) ~= "number" then
            Notify("World tidak ditemukan.")
            return false
        end
        -- Longhand otomatis supaya grup 3 tile terjangkau
        local inv = FindInventory()
        local okRange, range = pcall(function() return inv.buildRange() end)
        if okRange and type(range) == "number" and range < 4.5 then
            if longhandOn then
                StopLonghand()
            end
            Config.longhandRange = math.max(Config.longhandRange, 3)
            ApplyLonghand()
        end

        local home = {
            x = math.floor(x),
            y = math.floor(y - 0.475),
            world = CurrentWorldName(),
        }
        Clear.token += 1
        local token = Clear.token
        Clear.on = true
        Clear.status = "Mulai"
        Clear.stats = { scanned = 0, broken = 0, picked = 0, skipped = 0, left = 0, pass = 0 }
        task.spawn(function()
            local ok, err = pcall(ClearLoop, token, home)
            if not ok then
                warn(err)
                Notify("Auto Clear error: " .. tostring(err))
            end
            if Clear.token == token then
                Clear.on = false
                if Clear.status ~= "Selesai" then
                    Clear.status = "Mati"
                end
                if RefreshHub then
                    RefreshHub()
                end
            end
        end)
        return true
    end
end
----------------------------------------------------------------------
-- AUTO QUEST
-- Modul quest game (QuestsUI) tidak ada di growblox.lua, jadi skrip ini
-- membaca jendela quest dari layar: cari baris progres "x/y", klik tombol
-- claim, lalu kerjakan quest break/place lewat Auto Farm.
-- Quest yang tidak bisa dikenali dilewati. Ketik /aq scan untuk lihat hasil baca.
----------------------------------------------------------------------
local questToken = 0

local function IsShown(obj)
    local current = obj
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("ScreenGui") and not current.Enabled then
            return false
        end
        current = current.Parent
    end
    return true
end

local function CleanText(text)
    return (tostring(text):gsub("<[^>]+>", ""))
end

local function ClickGui(button)
    local clicked = false
    if getconnections then
        for _, signalName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up" }) do
            local okSignal, conns = pcall(function()
                return getconnections(button[signalName])
            end)
            if okSignal and type(conns) == "table" then
                for _, conn in ipairs(conns) do
                    if pcall(function() conn:Fire() end) then
                        clicked = true
                    end
                end
            end
        end
    end
    if not clicked and firesignal then
        clicked = pcall(firesignal, button.MouseButton1Click)
    end
    return clicked
end

local function ButtonText(button)
    local texts = {}
    if button:IsA("TextButton") and button.Text ~= "" then
        table.insert(texts, button.Text)
    end
    for _, child in ipairs(button:GetDescendants()) do
        if (child:IsA("TextLabel") or child:IsA("TextButton")) and child.Text ~= "" then
            table.insert(texts, child.Text)
        end
    end
    return CleanText(table.concat(texts, " ")):lower()
end

-- Jendela quest = frame ukuran jendela yang memuat teks "quest"
local function FindQuestRoot()
    local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
    local best, bestCount = nil, 0
    for _, gui in ipairs(PlayerGui:GetChildren()) do
        if gui.Name ~= "PeexHubGB" and gui:IsA("ScreenGui") then
            for _, obj in ipairs(gui:GetDescendants()) do
                if obj:IsA("TextLabel") and obj.Text ~= "" and IsShown(obj)
                    and CleanText(obj.Text):lower():find("quest", 1, true) then
                    local root = obj
                    while root.Parent and root.Parent:IsA("GuiObject") do
                        local size = root.Parent.AbsoluteSize
                        if size.X >= viewport.X * 0.95 and size.Y >= viewport.Y * 0.95 then
                            break
                        end
                        root = root.Parent
                    end
                    local count = #root:GetDescendants()
                    if count > bestCount then
                        best, bestCount = root, count
                    end
                end
            end
        end
    end
    return best
end

local function ParseNumber(text)
    return tonumber((text:gsub(",", "")))
end

local function GatherTexts(container)
    local texts = {}
    for _, obj in ipairs(container:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Text ~= "" and IsShown(obj) then
            table.insert(texts, CleanText(obj.Text))
        end
    end
    return texts
end

local function ReadQuestRows(root)
    local rows, seen = {}, {}
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextLabel") and IsShown(obj) then
            local a, b = CleanText(obj.Text):match("(%d[%d,]*)%s*/%s*(%d[%d,]*)")
            if a and b then
                local container = obj.Parent
                local texts = GatherTexts(container)
                if #texts < 2 and container.Parent and container.Parent ~= root then
                    container = container.Parent
                    texts = GatherTexts(container)
                end
                if not seen[container] then
                    seen[container] = true
                    table.insert(rows, {
                        have = ParseNumber(a),
                        need = ParseNumber(b),
                        text = table.concat(texts, " "),
                    })
                end
            end
        end
    end
    return rows
end

local function ClassifyQuest(text)
    local lower = text:lower()
    local verb = nil
    if lower:find("break") or lower:find("punch") or lower:find("smash") or lower:find("harvest")
        or lower:find("chop") or lower:find("hancur") or lower:find("pecah") then
        verb = "break"
    elseif lower:find("place") or lower:find("build") or lower:find("plant")
        or lower:find("pasang") or lower:find("taruh") then
        verb = "place"
    elseif lower:find("collect") or lower:find("gather") or lower:find("pick up")
        or lower:find("kumpul") or lower:find("ambil") then
        verb = "collect"
    end

    local bestId, bestLen = nil, 0
    local list = GetBlockList()
    if list then
        for _, entry in ipairs(list) do
            if #entry.lower >= 3 and #entry.lower > bestLen and lower:find(entry.lower, 1, true) then
                bestId, bestLen = entry.id, #entry.lower
            end
        end
    end
    return verb, bestId
end

local function OpenQuestWindow()
    local world = FindWorld()
    local quests = world and rawget(world, "quests")
    if type(quests) ~= "table" or type(quests.open) ~= "function" then
        return nil
    end
    pcall(quests.open)
    task.wait(0.8)
    return FindQuestRoot()
end

local function CloseQuestWindow(root)
    if not root then
        return
    end
    for _, obj in ipairs(root:GetDescendants()) do
        if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and IsShown(obj) then
            local text = ButtonText(obj)
            if text == "x" or text:find("close", 1, true) or text:find("tutup", 1, true) then
                ClickGui(obj)
                return
            end
        end
    end
end

local function ClaimAll(root)
    local claimed = 0
    for _, obj in ipairs(root:GetDescendants()) do
        if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and IsShown(obj) then
            local text = ButtonText(obj)
            if text:find("claim", 1, true) or text:find("redeem", 1, true) or text:find("klaim", 1, true)
                or text:find("selesai", 1, true) then
                if ClickGui(obj) then
                    claimed += 1
                    task.wait(0.5)
                end
            end
        end
    end
    return claimed
end

function QuestReport()
    local root = OpenQuestWindow()
    if not root then
        Notify("Jendela quest tidak terbaca. Buka menu quest di game lalu ketik " .. Config.prefix .. "aq scan lagi.")
        return
    end
    local rows = ReadQuestRows(root)
    if #rows == 0 then
        Notify("Tidak ada baris progres (x/y) di jendela quest.")
    end
    for index, row in ipairs(rows) do
        local verb, itemId = ClassifyQuest(row.text)
        local line = string.format("Quest %d: %d/%d | aksi: %s | item: %s | %s", index, row.have, row.need,
            verb or "?", itemId and (ItemName(itemId) .. " #" .. itemId) or "?", row.text)
        print("[PeexHub] " .. line)
        Notify(string.format("Quest %d: %d/%d  %s  %s", index, row.have, row.need, verb or "?",
            itemId and ItemName(itemId) or "?"))
    end
end

local function QuestLoop(token)
    while questOn and questToken == token do
        questStatus = "Membaca quest"
        local root = OpenQuestWindow()
        if not root then
            questStatus = "Jendela quest tidak terbaca"
            Notify("Auto Quest berhenti: jendela quest tidak terbaca. Coba " .. Config.prefix .. "aq scan.")
            break
        end

        questStatus = "Claim reward"
        ClaimAll(root)
        task.wait(0.4)
        root = FindQuestRoot() or root

        local target = nil
        for _, row in ipairs(ReadQuestRows(root)) do
            if row.have < row.need then
                local verb, itemId = ClassifyQuest(row.text)
                if (verb == "break" or verb == "place") and itemId then
                    local have = CountItem(itemId)
                    if have == nil or have > 0 then
                        target = { itemId = itemId, text = row.text }
                        break
                    end
                end
            end
        end
        CloseQuestWindow(root)

        if not target then
            questStatus = "Tidak ada quest yang bisa dikerjakan otomatis"
            Notify("Auto Quest selesai: tidak ada quest break/place dengan item yang kamu punya.")
            break
        end

        -- kerjakan lewat Auto Farm
        local savedId = Config.farmPlaceId
        Config.farmPlaceId = target.itemId
        questStatus = "Farm " .. ItemName(target.itemId)
        if farmOn then
            StopFarm()
            task.wait(0.3)
        end
        if not StartFarm() then
            Config.farmPlaceId = savedId
            questStatus = "Auto Farm gagal mulai"
            break
        end
        local started = os.clock()
        local lastCheck = os.clock()
        local done = false
        while questOn and questToken == token and farmOn and os.clock() - started < 900 do
            task.wait(1)
            if os.clock() - lastCheck >= 25 then
                lastCheck = os.clock()
                local checkRoot = OpenQuestWindow()
                if checkRoot then
                    local finished = true
                    for _, row in ipairs(ReadQuestRows(checkRoot)) do
                        local verb, itemId = ClassifyQuest(row.text)
                        if itemId == target.itemId and (verb == "break" or verb == "place") and row.have < row.need then
                            finished = false
                        end
                    end
                    CloseQuestWindow(checkRoot)
                    if finished then
                        done = true
                        break
                    end
                end
            end
        end
        StopFarm()
        Config.farmPlaceId = savedId
        if not (questOn and questToken == token) then
            break
        end
        if not done then
            questStatus = "Farm berhenti sebelum quest selesai"
            Notify("Auto Quest berhenti: farm berhenti (item habis / world berubah / timeout).")
            break
        end
        task.wait(1)
    end
    if questToken == token then
        questOn = false
        if RefreshHub then
            RefreshHub()
        end
    end
end

function StopQuest()
    if not questOn then
        return false
    end
    questToken += 1
    questOn = false
    questStatus = "Mati"
    StopFarm()
    return true
end

function StartQuest()
    if questOn then
        return true
    end
    questToken += 1
    local token = questToken
    questOn = true
    questStatus = "Mulai"
    task.spawn(function()
        local ok, err = pcall(QuestLoop, token)
        if not ok then
            warn(err)
            Notify("Auto Quest error: " .. tostring(err))
            if questToken == token then
                questOn = false
                if RefreshHub then
                    RefreshHub()
                end
            end
        end
    end)
    return true
end

----------------------------------------------------------------------
-- GOD MODE
-- Hazard tile (lava, spike, api, dll) di game ditentukan dari flag
-- "hurts"/"deadly" di ItemDB. Flag itu dimatikan selama God Mode aktif,
-- dan event "Burned" dari server diabaikan.
-- Tidak mencakup kick / ban / warning dari staff.
----------------------------------------------------------------------
local godSaved = {}
local godConns = {}

function StopGod()
    if not godOn then
        return false
    end
    for _, saved in ipairs(godSaved) do
        pcall(function()
            rawset(saved.item, saved.key, saved.value)
        end)
    end
    godSaved = {}
    for _, conn in ipairs(godConns) do
        pcall(function()
            conn:Enable()
        end)
    end
    godConns = {}
    godOn = false
    return true
end

function StartGod()
    if godOn then
        return true
    end
    local db = GetItemDB()
    if not db then
        Notify("ItemDB game tidak ditemukan!")
        return false
    end
    godSaved = {}
    for _, item in pairs(db) do
        if type(item) == "table" then
            for _, key in ipairs({ "hurts", "deadly" }) do
                if item[key] then
                    table.insert(godSaved, { item = item, key = key, value = rawget(item, key) })
                    pcall(function()
                        if setreadonly then
                            setreadonly(item, false)
                        end
                        rawset(item, key, false)
                    end)
                end
            end
        end
    end

    local remotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
    local burned = remotes and remotes:FindFirstChild("Burned")
    if burned and getconnections then
        local okConn, conns = pcall(getconnections, burned.OnClientEvent)
        if okConn and type(conns) == "table" then
            for _, conn in ipairs(conns) do
                if pcall(function() conn:Disable() end) then
                    table.insert(godConns, conn)
                end
            end
        end
    end
    godOn = true
    return true
end

----------------------------------------------------------------------
-- GROWSCAN
-- Buka GrowScan bawaan game; kalau tidak tersedia, pakai scan dunia Peex.
----------------------------------------------------------------------
local function FindGrowScanItem()
    local db = GetItemDB()
    if db then
        for id, item in pairs(db) do
            if type(id) == "number" and type(item) == "table" and item.growscan then
                return id
            end
        end
    end
    return 0
end

function OpenNativeGrowScan()
    local world = FindWorld()
    local ui = world and rawget(world, "growScan")
    if type(ui) ~= "table" or type(ui.open) ~= "function" then
        return false
    end
    local ok, err = pcall(ui.open, {
        item = FindGrowScanItem(),
        owner = true,
        blocksPublic = false,
        floatingPublic = false,
    }, function() end)
    if not ok then
        warn(err)
    end
    return ok
end

-- Hitung isi world: foreground, background, dan item yang tergeletak
function ScanWorld()
    local world = FindWorld()
    if not world or type(rawget(world, "w")) ~= "number" then
        return nil
    end
    local result = { fg = {}, bg = {}, drops = {}, w = world.w, h = world.h }
    local gridFg, gridBg = rawget(world, "fg"), rawget(world, "bg")
    for y = 0, world.h - 1 do
        local rowFg = gridFg and gridFg[y]
        local rowBg = gridBg and gridBg[y]
        for x = 0, world.w - 1 do
            local f = rowFg and rowFg[x]
            if f and f ~= 0 then
                result.fg[f] = (result.fg[f] or 0) + 1
            end
            local b = rowBg and rowBg[x]
            if b and b ~= 0 then
                result.bg[b] = (result.bg[b] or 0) + 1
            end
        end
    end
    local okDrops, list = pcall(world.dropList)
    if okDrops and type(list) == "table" then
        for _, drop in ipairs(list) do
            if type(drop) == "table" and type(drop.id) == "number" then
                result.drops[drop.id] = (result.drops[drop.id] or 0) + (drop.n or 1)
            end
        end
    end
    return result
end

----------------------------------------------------------------------
-- AUTO DF (dig ke bawah)
-- Break block tepat di bawah karakter, tunggu jatuh, ulangi sampai mentok
-- (bedrock / lock / dasar world). Block yang dilindungi tidak disentuh.
----------------------------------------------------------------------
do
    local function DfProtected(db, id)
        local item = db and db[id]
        if type(item) ~= "table" then
            return true
        end
        if item.lock or item.area then
            return true
        end
        if type(item.hits) == "number" and item.hits <= 0 then
            return true
        end
        local name = type(item.name) == "string" and item.name:lower() or ""
        if name:find("bedrock", 1, true) or name:find("main door", 1, true)
            or name:find("white door", 1, true) or name:find("world lock", 1, true) then
            return true
        end
        return false
    end

    local function DfLoop(token, home)
        local db = GetItemDB()
        local hit = FindGameFn("hit")
        if not db or not hit then
            Dig.status = "Fungsi game tidak ditemukan"
            return
        end
        local dir = Config.dfFlip and -1 or 1
        local idle = 0
        while Dig.token == token do
            local world = FindWorld()
            if not world or CurrentWorldName() ~= home.world then
                Dig.status = "World berubah, berhenti"
                Notify("Auto DF berhenti: kamu pindah world.")
                return
            end
            local tx, ty = GetTile()
            if not tx then
                Dig.status = "Posisi tidak terdeteksi"
                task.wait(0.3)
                continue
            end
            local bx, by = tx, ty + dir
            if not InBounds(world, bx, by) then
                Dig.status = "Sampai dasar world"
                Notify("Auto DF selesai: sampai dasar world.")
                break
            end
            Dig.stats.depth = math.max(Dig.stats.depth, math.abs(ty - home.y))
            local id = TileValue(world, "fg", bx, by)
            if id and id ~= 0 then
                if DfProtected(db, id) then
                    Dig.status = "Mentok: " .. ItemName(id)
                    Notify("Auto DF berhenti: mentok " .. ItemName(id) .. ".")
                    break
                end
                Dig.status = "Break " .. ItemName(id)
                idle = 0
                local started = os.clock()
                while Dig.token == token and TileValue(world, "fg", bx, by) == id do
                    if os.clock() - started > 8 then
                        break
                    end
                    pcall(hit, bx, by, true)
                    task.wait(math.max(0.03, Config.dfDelay))
                end
                if TileValue(world, "fg", bx, by) ~= id then
                    Dig.stats.broken += 1
                end
                -- tunggu karakter jatuh ke bawah
                local waited = os.clock()
                while Dig.token == token and os.clock() - waited < 1.2 do
                    local _, cy = GetTile()
                    if cy and cy ~= ty then
                        break
                    end
                    task.wait(0.05)
                end
            else
                -- tile bawah kosong: sedang jatuh (atau tersangkut di udara)
                Dig.status = "Turun..."
                task.wait(0.15)
                idle += 0.15
                if idle >= 2 then
                    pcall(world.goTo, bx, by)
                    idle = 0
                end
            end
        end
    end

    function Dig.Stop()
        if not Dig.on then
            return false
        end
        Dig.token += 1
        Dig.on = false
        Dig.status = "Mati"
        return true
    end

    function Dig.Start()
        if Dig.on then
            return true
        end
        if farmOn then
            StopFarm()
        end
        if Clear.on then
            Clear.Stop()
        end
        if not (FindGameFn("hit") and GetItemDB()) then
            Notify("Fungsi hit game tidak ditemukan (executor perlu getgc + debug.info).")
            return false
        end
        local x, y = GetGridState()
        if not x then
            Notify("Posisi tidak terdeteksi!")
            return false
        end
        local home = {
            x = math.floor(x),
            y = math.floor(y - 0.475),
            world = CurrentWorldName(),
        }
        Dig.token += 1
        local token = Dig.token
        Dig.on = true
        Dig.status = "Mulai"
        Dig.stats = { broken = 0, depth = 0 }
        task.spawn(function()
            local ok, err = pcall(DfLoop, token, home)
            if not ok then
                warn(err)
                Notify("Auto DF error: " .. tostring(err))
            end
            if Dig.token == token then
                Dig.on = false
                if Dig.status == "Mulai" or Dig.status == "Turun..." or Dig.status:find("^Break") then
                    Dig.status = "Mati"
                end
                if RefreshHub then
                    RefreshHub()
                end
            end
        end)
        return true
    end
end

end

----------------------------------------------------------------------
-- SPAM CHAT
-- Game memakai TextChatService bawaan Roblox (tidak ada remote chat sendiri),
-- jadi pesan dikirim lewat channel RBXGeneral:SendAsync. Kalau chat lama
-- (legacy) yang dipakai, jatuh ke SayMessageRequest.
-- Teks yang diawali "/" ditolak: game menganggapnya command.
----------------------------------------------------------------------
local Spam = { on = false, token = 0, guardText = nil, guardT = 0 }
do
    local TextChatService = game:GetService("TextChatService")
    local MAX_CHAT = 200

    function Spam.Send(text)
        local sent = false
        pcall(function()
            if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
                local channels = TextChatService:FindFirstChild("TextChannels")
                local channel = channels and (channels:FindFirstChild("RBXGeneral")
                    or channels:FindFirstChildWhichIsA("TextChannel"))
                if channel then
                    channel:SendAsync(text)
                    sent = true
                end
            end
        end)
        if sent then
            return true
        end
        pcall(function()
            local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
            local say = events and events:FindFirstChild("SayMessageRequest")
            if say then
                say:FireServer(text, "All")
                sent = true
            end
        end)
        return sent
    end

    function Spam.SetText(text)
        text = Trim(tostring(text or ""))
        if text == "" then
            Config.spamText = ""
            SaveConfig()
            Notify("Teks spam dikosongkan.")
            return true
        end
        if text:sub(1, 1) == "/" then
            Notify("Teks spam tidak boleh diawali \"/\" (dianggap command oleh game).")
            return false
        end
        if #text > MAX_CHAT then
            text = text:sub(1, MAX_CHAT)
        end
        Config.spamText = text
        SaveConfig()
        Notify("Teks spam diset: " .. text)
        return true
    end

    function Spam.Stop()
        if not Spam.on then
            return false
        end
        Spam.on = false
        Spam.token += 1
        return true
    end

    function Spam.Start()
        if Spam.on then
            return true
        end
        if Trim(Config.spamText or "") == "" then
            Notify("Teks spam masih kosong. Isi dulu: " .. Config.prefix .. "setspam <teks> atau lewat tab Spam.")
            return false
        end
        Spam.on = true
        Spam.token += 1
        local token = Spam.token
        task.spawn(function()
            local fails = 0
            while Spam.on and Spam.token == token do
                local msg = Trim(Config.spamText or "")
                if msg ~= "" then
                    -- tandai supaya pesan ini tidak diproses sebagai command oleh hook chat
                    Spam.guardText = msg:lower()
                    Spam.guardT = os.clock()
                    if Spam.Send(msg) then
                        fails = 0
                    else
                        fails += 1
                    end
                    if fails >= 3 then
                        Spam.on = false
                        Config.session.spam = nil
                        SaveConfig()
                        Notify("Spam berhenti: pesan gagal terkirim 3 kali (chat tidak ditemukan / dibatasi).")
                        if RefreshHub then
                            RefreshHub()
                        end
                        return
                    end
                end
                local delay = math.max(1.5, tonumber(Config.spamDelay) or 3)
                local waited = 0
                while Spam.on and Spam.token == token and waited < delay do
                    task.wait(0.1)
                    waited += 0.1
                end
            end
        end)
        return true
    end
end

local Features = {
    blink = {
        label = "Blink",
        get = function() return blinkOn end,
        set = function(on)
            if on then return StartBlink() end
            return StopBlink()
        end,
    },
    longhand = {
        label = "Longhand",
        get = function() return longhandOn end,
        set = function(on)
            if on then return ApplyLonghand() end
            return StopLonghand()
        end,
    },
    noclip = {
        label = "Noclip",
        get = function() return noclipOn end,
        set = function(on)
            if on then return StartNoclip() end
            return StopNoclip()
        end,
    },
    ujump = {
        label = "Unlimited Jump",
        get = function() return ujumpOn end,
        set = function(on)
            if on then return StartUjump() end
            return StopUjump()
        end,
    },
    antiafk = {
        label = "Anti-AFK",
        get = function() return antiAfkOn end,
        set = function(on)
            if on then return StartAntiAfk() end
            return StopAntiAfk()
        end,
    },
    autorejoin = {
        label = "Auto Rejoin",
        get = function() return arjOn end,
        set = function(on)
            if on then return StartAutoRejoin() end
            return StopAutoRejoin()
        end,
    },
    god = {
        label = "God Mode",
        get = function() return godOn end,
        set = function(on)
            if on then return StartGod() end
            return StopGod()
        end,
    },
    clicktp = {
        label = "Click TP",
        get = function() return Nav.clickOn end,
        set = function(on)
            if on then return Nav.StartClick() end
            return Nav.StopClick()
        end,
    },
    spam = {
        label = "Spam Chat",
        get = function() return Spam.on end,
        set = function(on)
            if on then return Spam.Start() end
            return Spam.Stop()
        end,
    },
    autoclear = {
        label = "Auto Clear World",
        get = function() return Clear.on end,
        set = function(on)
            if on then return Clear.Start() end
            return Clear.Stop()
        end,
    },
    autodf = {
        label = "Auto DF",
        get = function() return Dig.on end,
        set = function(on)
            if on then return Dig.Start() end
            return Dig.Stop()
        end,
    },
    autofarm = {
        label = "Auto Farm",
        noSession = true,
        get = function() return farmOn end,
        set = function(on)
            if on then return StartFarm() end
            return StopFarm()
        end,
    },
    autoquest = {
        label = "Auto Quest",
        noSession = true,
        get = function() return questOn end,
        set = function(on)
            if on then return StartQuest() end
            return StopQuest()
        end,
    },
}

local function SetFeature(key, on)
    local feature = Features[key]
    feature.set(on)
    if feature.get() == on then
        Notify(feature.label .. (on and " aktif." or " dimatikan."))
        if not feature.noSession then
            Config.session[key] = on or nil
        end
        SaveConfig()
    end
    if RefreshHub then
        RefreshHub()
    end
end

----------------------------------------------------------------------
-- SESI: simpan, auto-reload setelah teleport, pulihkan fitur
----------------------------------------------------------------------
local function ReloadSource()
    local url = Config.scriptUrl
    if type(url) ~= "string" or url == "" then
        url = genv.PeexHubURL
    end
    if type(url) == "string" and url ~= "" then
        return string.format("loadstring(game:HttpGet(%q))()", url)
    end
    local okFile, exists = pcall(function()
        return isfile and readfile and isfile(SCRIPT_FILE)
    end)
    if okFile and exists then
        return string.format("loadstring(readfile(%q))()", SCRIPT_FILE)
    end
    return nil
end

local function GetQueueFn()
    return queue_on_teleport
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
end

local function ReloadReady()
    return GetQueueFn() ~= nil and ReloadSource() ~= nil
end

QueueReload = function()
    if not Config.autoReload then
        return false
    end
    local queueFn = GetQueueFn()
    local source = ReloadSource()
    if not queueFn or not source then
        return false
    end
    return pcall(queueFn, source)
end

local function InstallAutoexec()
    if not writefile then
        Notify("Executor tidak punya writefile.")
        return
    end
    local source = ReloadSource()
    if not source then
        Notify("Simpan skrip sebagai " .. SCRIPT_FILE .. " di folder workspace, atau isi URL dulu.")
        return
    end
    local loader = "-- Peex HUB | GrowBlox auto-loader\n" .. source .. "\n"
    pcall(writefile, "PeexHub_Loader.lua", loader) -- salinan manual di workspace

    for _, path in ipairs({ "../autoexec/PeexHub_Loader.lua", "../Autoexec/PeexHub_Loader.lua" }) do
        local okWrite = pcall(writefile, path, loader)
        local okCheck, exists = pcall(function()
            return isfile and isfile(path)
        end)
        if okWrite and okCheck and exists then
            Notify("Auto-execute terpasang. Skrip jalan otomatis tiap buka Roblox.")
            return
        end
    end
    Notify("Folder autoexec tidak terjangkau. Salin PeexHub_Loader.lua dari workspace ke folder autoexec executor.")
end

local function SaveSessionNow()
    Config.session = {}
    for key, feature in pairs(Features) do
        if feature.get() and not feature.noSession then
            Config.session[key] = true
        end
    end
    local world = CurrentWorldName()
    if world ~= "" then
        Config.lastWorld = world
    end
    SaveConfig()
end

local function RestoreSession()
    if not Config.autoRestore then
        return
    end

    local waited = 0
    while not (FindInventory() and FindWorld()) and waited < 60 do
        task.wait(1)
        waited += 1
    end
    waited = 0
    while CurrentWorldName() == "" and waited < 20 do
        task.wait(1)
        waited += 1
    end
    task.wait(1.5)

    if Config.autoWarp and Config.lastWorld ~= "" and CurrentWorldName() ~= Config.lastWorld then
        WarpToWorld(Config.lastWorld)
        task.wait(4)
    end

    local restored = {}
    for key, feature in pairs(Features) do
        if Config.session[key] and not feature.get() then
            local ok = pcall(feature.set, true)
            if ok and feature.get() then
                table.insert(restored, feature.label)
            end
        end
    end
    if RefreshHub then
        RefreshHub()
    end
    if #restored > 0 then
        table.sort(restored)
        Notify("Sesi dipulihkan: " .. table.concat(restored, ", "))
    end
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------
local C = {
    window = Color3.fromRGB(10, 14, 26),
    panel = Color3.fromRGB(16, 22, 38),
    card = Color3.fromRGB(23, 31, 52),
    cardHi = Color3.fromRGB(37, 49, 80),
    stroke = Color3.fromRGB(54, 68, 104),
    accent = Color3.fromRGB(56, 189, 248),   -- biru langit
    accent2 = Color3.fromRGB(167, 139, 250), -- ungu
    text = Color3.fromRGB(236, 242, 255),
    mute = Color3.fromRGB(143, 160, 192),
    ok = Color3.fromRGB(52, 211, 153),
    bad = Color3.fromRGB(244, 94, 112),
    warn = Color3.fromRGB(251, 191, 36),
}
local CARTOON_FONT = Enum.Font.GothamMedium

local function New(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function Corner(obj, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, obj)
end

local function Stroke(obj, color, thickness, transparency)
    return New("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function Tween(obj, duration, props, style, dir)
    TweenService:Create(obj, TweenInfo.new(duration, style or Enum.EasingStyle.Quad,
        dir or Enum.EasingDirection.Out), props):Play()
end

local function Label(parent, props)
    local p = {
        BackgroundTransparency = 1,
        TextColor3 = C.text,
        Font = CARTOON_FONT,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
    }
    for key, value in pairs(props) do
        p[key] = value
    end
    return New("TextLabel", p, parent)
end

-- helper tambahan (dikumpulkan dalam satu tabel supaya tidak menambah banyak local)
local UI = {}
function UI.Gradient(obj, c1, c2, rotation)
    return New("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rotation or 0 }, obj)
end

local rootGui = nil
local function GetGui()
    if rootGui and rootGui.Parent then
        return rootGui
    end
    local existing = FindExistingGui()
    if existing and existing:IsA("ScreenGui") then
        rootGui = existing
        return rootGui
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "PeexHubGB"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999
    gui.IgnoreGuiInset = true
    gui.Enabled = true

    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        end
    end)

    local parented = false
    if gethui then
        parented = pcall(function()
            gui.Parent = gethui()
        end) and gui.Parent ~= nil
    end
    if not parented then
        parented = pcall(function()
            gui.Parent = game:GetService("CoreGui")
        end) and gui.Parent ~= nil
    end
    if not parented then
        gui.Parent = PlayerGui
    end

    rootGui = gui
    return rootGui
end

-- Toast ---------------------------------------------------------------
local toastHolder = nil
local toastCounter = 0

ToastHook = function(message)
    local gui = GetGui()
    if not toastHolder or not toastHolder.Parent then
        toastHolder = New("Frame", {
            Name = "Toasts",
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 270, 1, -80),
            Position = UDim2.new(1, -284, 0, 16),
            ZIndex = 100,
        }, gui)
        New("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Top,
        }, toastHolder)
    end

    toastCounter += 1
    local existing = {}
    for _, child in ipairs(toastHolder:GetChildren()) do
        if child:IsA("Frame") then
            table.insert(existing, child)
        end
    end
    if #existing >= 4 then
        existing[1]:Destroy()
    end

    local toast = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = toastCounter,
        ZIndex = 100,
    }, toastHolder)
    Corner(toast, 12)
    local toastStroke = Stroke(toast, C.accent, 1, 1)

    local stripe = New("Frame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = C.accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 101,
    }, toast)
    UI.Gradient(stripe, C.accent, C.accent2, 90)

    local text = Label(toast, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = message,
        TextSize = 12,
        TextTransparency = 1,
        ZIndex = 101,
    })
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 13),
    }, text)

    local progress = New("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = C.accent2,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 102,
    }, toast)

    Tween(toast, 0.22, { BackgroundTransparency = 0.04 })
    Tween(toastStroke, 0.22, { Transparency = 0.45 })
    Tween(stripe, 0.22, { BackgroundTransparency = 0 })
    Tween(text, 0.22, { TextTransparency = 0 })
    Tween(progress, 0.22, { BackgroundTransparency = 0.2 })
    Tween(progress, 3.5, { Size = UDim2.new(0, 0, 0, 2) }, Enum.EasingStyle.Linear)

    task.delay(3.5, function()
        if not toast.Parent then
            return
        end
        Tween(toast, 0.25, { BackgroundTransparency = 1 })
        Tween(toastStroke, 0.25, { Transparency = 1 })
        Tween(stripe, 0.25, { BackgroundTransparency = 1 })
        Tween(text, 0.25, { TextTransparency = 1 })
        Tween(progress, 0.25, { BackgroundTransparency = 1 })
        task.wait(0.3)
        toast:Destroy()
    end)
end

local hub = {
    frame = nil,
    minimized = false,
    scale = nil,
    pages = {},
    builders = {},
    tabs = {},
    refreshers = {},
    active = nil,
    narrow = false,
}

local orders = setmetatable({}, { __mode = "k" })
local function NextOrder(parent)
    local n = (orders[parent] or 0) + 1
    orders[parent] = n
    return n
end

RefreshHub = function()
    for _, refresh in ipairs(hub.refreshers) do
        pcall(refresh)
    end
end

-- Komponen -----------------------------------------------------------
local function AddCard(page, height)
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        LayoutOrder = NextOrder(page),
    }, page)
    Corner(card, 12)
    Stroke(card, C.stroke, 1, 0.55)
    New("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 214, 240)),
        Rotation = 90,
    }, card)
    return card
end

local function AddSection(page, text)
    local row = New("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    local pill = New("Frame", {
        Position = UDim2.new(0, 2, 0.5, -7),
        Size = UDim2.fromOffset(3, 14),
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
    }, row)
    Corner(pill, 2)
    UI.Gradient(pill, C.accent, C.accent2, 90)
    Label(row, {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -12, 1, 0),
        Text = string.upper(text),
        TextColor3 = C.mute,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextWrapped = false,
    })
    return row
end

local function AddNote(page, text)
    local box = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        LayoutOrder = NextOrder(page),
    }, page)
    Corner(box, 10)
    Stroke(box, C.stroke, 1, 0.75)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 9),
        PaddingBottom = UDim.new(0, 9),
    }, box)
    Label(box, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = text,
        TextColor3 = C.mute,
        TextSize = 12,
    })
    return box
end

local function StyleButton(button, style)
    local base, hover
    if style == "primary" then
        base, hover = C.accent, Color3.fromRGB(125, 211, 252)
        UI.Gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(196, 176, 255), 0)
    elseif style == "danger" then
        base, hover = C.bad, Color3.fromRGB(252, 129, 143)
    else
        base, hover = C.cardHi, Color3.fromRGB(53, 68, 108)
    end
    button.BackgroundColor3 = base
    button.AutoButtonColor = false
    local scale = New("UIScale", { Scale = 1 }, button)
    button.MouseEnter:Connect(function()
        Tween(button, 0.12, { BackgroundColor3 = hover })
    end)
    button.MouseLeave:Connect(function()
        Tween(button, 0.12, { BackgroundColor3 = base })
        Tween(scale, 0.1, { Scale = 1 })
    end)
    button.MouseButton1Down:Connect(function()
        Tween(scale, 0.07, { Scale = 0.96 })
    end)
    button.MouseButton1Up:Connect(function()
        Tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
    end)
end

local function MakeButton(parent, text, style, props)
    local p = {
        Size = UDim2.new(1, 0, 0, 36),
        Text = text,
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        BorderSizePixel = 0,
    }
    for key, value in pairs(props or {}) do
        p[key] = value
    end
    local button = New("TextButton", p, parent)
    Corner(button, 9)
    Stroke(button, style == "ghost" and C.stroke or Color3.new(1, 1, 1), 1, style == "ghost" and 0.35 or 0.85)
    StyleButton(button, style)
    return button
end

local function AddButton(page, text, style, callback)
    local button = MakeButton(page, text, style, { LayoutOrder = NextOrder(page) })
    button.MouseButton1Click:Connect(callback)
    return button
end

local function AddSwitchCard(page, title, subtitle, getState, onToggle)
    local card = AddCard(page, 62)
    local cardStroke = card:FindFirstChildOfClass("UIStroke")

    Label(card, {
        Text = title,
        Font = Enum.Font.GothamSemibold,
        Position = UDim2.fromOffset(14, 9),
        Size = UDim2.new(1, -86, 0, 18),
        TextWrapped = false,
    })
    Label(card, {
        Text = subtitle,
        TextColor3 = C.mute,
        TextSize = 11,
        Position = UDim2.fromOffset(14, 28),
        Size = UDim2.new(1, -86, 0, 30),
        TextYAlignment = Enum.TextYAlignment.Top,
    })

    local track = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(46, 24),
        BackgroundColor3 = C.cardHi,
        BorderSizePixel = 0,
    }, card)
    Corner(track, 12)
    local trackGrad = UI.Gradient(track, Color3.new(1, 1, 1), Color3.fromRGB(196, 176, 255), 0)
    trackGrad.Enabled = false

    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    Corner(knob, 9)

    local hit = New("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
    }, card)

    local function Refresh()
        local on = getState()
        trackGrad.Enabled = on
        Tween(track, 0.18, { BackgroundColor3 = on and C.accent or C.cardHi })
        Tween(knob, 0.22, {
            Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        }, Enum.EasingStyle.Back)
        if cardStroke then
            Tween(cardStroke, 0.18, {
                Color = on and C.accent or C.stroke,
                Transparency = on and 0.3 or 0.55,
            })
        end
    end

    hit.MouseEnter:Connect(function()
        Tween(card, 0.12, { BackgroundColor3 = Color3.fromRGB(30, 41, 68) })
    end)
    hit.MouseLeave:Connect(function()
        Tween(card, 0.12, { BackgroundColor3 = C.card })
    end)
    hit.MouseButton1Click:Connect(function()
        onToggle(not getState())
        Refresh()
    end)

    table.insert(hub.refreshers, Refresh)
    Refresh()
end

local function AddInputCard(page, title, subtitle, value, placeholder, onCommit)
    local card = AddCard(page, 60)
    local boxWidth = hub.narrow and 88 or 120

    Label(card, {
        Text = title,
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.new(1, -(boxWidth + 34), 0, 16),
        TextWrapped = false,
    })
    Label(card, {
        Text = subtitle,
        TextColor3 = C.mute,
        TextSize = 10,
        Position = UDim2.fromOffset(14, 26),
        Size = UDim2.new(1, -(boxWidth + 34), 0, 30),
        TextYAlignment = Enum.TextYAlignment.Top,
    })

    local box = New("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(boxWidth, 34),
        BackgroundColor3 = C.window,
        BorderSizePixel = 0,
        Text = tostring(value),
        PlaceholderText = placeholder or "",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, card)
    Corner(box, 9)
    local boxStroke = Stroke(box, C.stroke, 1, 0.2)

    box.Focused:Connect(function()
        Tween(boxStroke, 0.12, { Color = C.accent, Thickness = 1.5 })
    end)
    box.FocusLost:Connect(function()
        Tween(boxStroke, 0.12, { Color = C.stroke, Thickness = 1 })
        onCommit(box.Text, box)
    end)
    return box
end

local function ClearPage(page)
    for _, child in ipairs(page:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
    orders[page] = 0
end


-- Halaman: Fitur -----------------------------------------------------
hub.builders.features = function(page)
    -- Kartu status live
    local status = AddCard(page, 48)
    local statusLabel = Label(status, {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = "...",
        Font = CARTOON_FONT,
        TextSize = 12,
        TextWrapped = false,
    })
    local dot = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = C.ok,
        BorderSizePixel = 0,
    }, status)
    Corner(dot, 4)

    local function UpdateStatus()
        local tx, ty = GetTile()
        local worldName = CurrentWorldName()
        if tx then
            statusLabel.Text = string.format("World: %s   |   Tile: %d, %d", worldName ~= "" and worldName or "-", tx, ty)
            dot.BackgroundColor3 = C.ok
        else
            statusLabel.Text = "Posisi tidak terdeteksi"
            dot.BackgroundColor3 = C.bad
        end
    end
    UpdateStatus()

    local owner = hub.frame
    task.spawn(function()
        while hub.frame == owner and owner and owner.Parent do
            task.wait(0.3)
            pcall(UpdateStatus)
        end
    end)

    AddSection(page, "Fitur")

    AddSwitchCard(page, "Blink Skin", "Warna skin berganti otomatis tiap 0.2-0.5 detik.",
        Features.blink.get, function(on) SetFeature("blink", on) end)
    AddSwitchCard(page, "Longhand", "Jangkauan punch & build lebih jauh (atur tile di Setelan).",
        Features.longhand.get, function(on) SetFeature("longhand", on) end)
    AddSwitchCard(page, "Noclip", "Tembus blok & terbang (mode ghost). Naik: lompat, turun: bawah/S.",
        Features.noclip.get, function(on) SetFeature("noclip", on) end)
    AddSwitchCard(page, "Unlimited Jump", "Lompat di udara tanpa batas, bahkan tanpa sayap.",
        Features.ujump.get, function(on) SetFeature("ujump", on) end)
    AddSwitchCard(page, "Anti-AFK", "Mencegah kick karena idle.",
        Features.antiafk.get, function(on) SetFeature("antiafk", on) end)
    AddSwitchCard(page, "Auto Rejoin", "Rejoin otomatis ke world ini kalau terputus.",
        Features.autorejoin.get, function(on) SetFeature("autorejoin", on) end)
    AddSwitchCard(page, "God Mode", "Kebal lava, spike, api (burn), dan hazard tile lain. Tidak mencakup kick/ban staff.",
        Features.god.get, function(on) SetFeature("god", on) end)
    AddSwitchCard(page, "Auto Farm", "Atur kecepatan, ID block, dan pola place di tab Farm.",
        Features.autofarm.get, function(on) SetFeature("autofarm", on) end)
    AddSwitchCard(page, "Auto Clear World", "GrowScan, break 1-4 block per pukulan (bisa diatur), ambil drop (tab Auto Clear).",
        Features.autoclear.get, function(on) SetFeature("autoclear", on) end)
    AddSwitchCard(page, "Auto DF", "Dig ke bawah: break block di bawah karakter terus sampai mentok (tab Auto DF).",
        Features.autodf.get, function(on) SetFeature("autodf", on) end)
    AddSwitchCard(page, "Click TP", "Klik tujuan, jalan lewat path tapi terlihat seperti teleport.",
        Features.clicktp.get, function(on) SetFeature("clicktp", on) end)
    AddSwitchCard(page, "Auto Quest", "Claim dan kerjakan quest otomatis (lihat tab Quest).",
        Features.autoquest.get, function(on) SetFeature("autoquest", on) end)

    AddSection(page, "Aksi cepat")

    local dropCard = AddCard(page, 96)
    Label(dropCard, {
        Text = "Drop World Lock",
        Font = CARTOON_FONT,
        TextSize = 12,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 16),
        TextWrapped = false,
    })
    local amountBox = New("TextBox", {
        Position = UDim2.fromOffset(12, 30),
        Size = UDim2.new(0.5, -17, 0, 28),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Text = "100",
        PlaceholderText = "Jumlah",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 12,
        ClearTextOnFocus = false,
    }, dropCard)
    Corner(amountBox, 8)
    Stroke(amountBox, C.stroke, 1, 0.2)
    local dropButton = MakeButton(dropCard, "Drop", "primary", {
        Position = UDim2.new(0.5, 5, 0, 30),
        Size = UDim2.new(0.5, -17, 0, 28),
    })
    dropButton.MouseButton1Click:Connect(function()
        local amount = tonumber(amountBox.Text)
        if amount and amount >= 1 and amount <= MAX_AMOUNT and amount == math.floor(amount) then
            task.spawn(DropWorldLock, amount)
        else
            Notify("Jumlah tidak valid (1-" .. MAX_AMOUNT .. ")")
        end
    end)
    local quickRow = New("Frame", {
        Position = UDim2.fromOffset(12, 64),
        Size = UDim2.new(1, -24, 0, 24),
        BackgroundTransparency = 1,
    }, dropCard)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
    }, quickRow)
    for _, value in ipairs({ 1, 10, 50, 100 }) do
        local chip = MakeButton(quickRow, tostring(value), "ghost", {
            Size = UDim2.new(0.25, -5, 1, 0),
            TextSize = 11,
        })
        chip.MouseButton1Click:Connect(function()
            amountBox.Text = tostring(value)
        end)
    end

    AddButton(page, "Rejoin World", "ghost", Rejoin)
end

-- Halaman: Posisi ----------------------------------------------------
local function AddPosCard(page, slot)
    local card = AddCard(page, 100)
    Label(card, {
        Text = "Pos " .. slot,
        Font = CARTOON_FONT,
        TextSize = 14,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(0.5, 0, 0, 18),
        TextWrapped = false,
    })
    local info = Label(card, {
        Text = "",
        TextColor3 = C.mute,
        TextSize = 11,
        Position = UDim2.fromOffset(12, 28),
        Size = UDim2.new(1, -24, 0, 16),
        TextWrapped = false,
    })

    local function Refresh()
        local pos = Config["pos" .. slot]
        if type(pos) == "table" and type(pos.x) == "number" then
            info.Text = string.format("Tile %d, %d  -  world %s", pos.x, pos.y, (pos.world and pos.world ~= "") and pos.world or "-")
            info.TextColor3 = C.ok
        else
            info.Text = "Belum diset"
            info.TextColor3 = C.mute
        end
    end
    table.insert(hub.refreshers, Refresh)
    Refresh()

    local setButton = MakeButton(card, "Set di sini", "primary", {
        Position = UDim2.new(0, 12, 1, -44),
        Size = UDim2.new(0.5, -17, 0, 32),
    })
    local goButton = MakeButton(card, "Teleport (win" .. slot .. ")", "ghost", {
        Position = UDim2.new(0.5, 5, 1, -44),
        Size = UDim2.new(0.5, -17, 0, 32),
    })
    setButton.MouseButton1Click:Connect(function()
        SetPos(slot)
        RefreshHub()
    end)
    goButton.MouseButton1Click:Connect(function()
        task.spawn(GoToPos, slot)
    end)
end

hub.builders.pos = function(page)
    AddNote(page, "Berdiri di posisi pemain lalu tekan Set. Saat ada pemenang, tekan Teleport atau ketik command win.")
    AddPosCard(page, 1)
    AddPosCard(page, 2)
    AddNote(page, string.format("Tips: %sw1 50 = teleport ke Pos 1 lalu langsung drop 50 World Lock.", Config.prefix))
end

-- Halaman: Visual Item ----------------------------------------------
hub.builders.visual = function(page)
    local list = GetWearables()
    if not list then
        AddNote(page, "ItemDB game tidak ditemukan.")
        return
    end

    AddNote(page, "Hanya tampilan lokal. Klik item untuk memakai/melepas. Perubahan inventory game bisa mereset tampilan.")

    local searchCard = AddCard(page, 42)
    local search = New("TextBox", {
        Position = UDim2.fromOffset(8, 6),
        Size = UDim2.new(1, -16, 1, -12),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Cari nama item...",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 13,
        ClearTextOnFocus = false,
    }, searchCard)
    Corner(search, 8)
    New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, search)

    local chipRow = New("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 5),
    }, chipRow)

    local resetButton = AddButton(page, "Kembalikan Semua Item", "danger", function() end)

    local results = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, results)

    local activeFilter = "Semua"
    local limit = 60
    local Rebuild

    local chips = {}
    for _, name in ipairs({ "Semua", "Kuyang", "LegendBot", "Rayman" }) do
        local chip = New("TextButton", {
            Size = UDim2.new(0.25, -4, 1, 0),
            BackgroundColor3 = C.cardHi,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = name,
            TextColor3 = C.text,
            Font = CARTOON_FONT,
            TextSize = 11,
        }, chipRow)
        Corner(chip, 8)
        chips[name] = chip
        chip.MouseButton1Click:Connect(function()
            activeFilter = name
            limit = 60
            Rebuild()
        end)
    end

    local function Matches(entry, query)
        if activeFilter ~= "Semua" and not table.find(entry.tags, activeFilter) then
            return false
        end
        return query == "" or entry.lower:find(query, 1, true) ~= nil
    end

    Rebuild = function()
        for _, child in ipairs(results:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end
        for name, chip in pairs(chips) do
            chip.BackgroundColor3 = (name == activeFilter) and C.accent or C.cardHi
        end

        local query = Trim(search.Text):lower()
        local shown, total = 0, 0
        for _, entry in ipairs(list) do
            if Matches(entry, query) then
                total += 1
                if shown < limit then
                    shown += 1
                    local worn = IsVisualWorn(entry.id)
                    local row = New("TextButton", {
                        Size = UDim2.new(1, 0, 0, 36),
                        BackgroundColor3 = worn and C.accent or C.card,
                        BackgroundTransparency = worn and 0.65 or 0,
                        BorderSizePixel = 0,
                        AutoButtonColor = false,
                        Text = "",
                        LayoutOrder = shown,
                    }, results)
                    Corner(row, 8)
                    Stroke(row, worn and C.accent or C.stroke, 1, worn and 0.2 or 0.6)

                    Label(row, {
                        Text = entry.name,
                        Font = CARTOON_FONT,
                        TextSize = 12,
                        Position = UDim2.fromOffset(10, 0),
                        Size = UDim2.new(1, -112, 1, 0),
                        TextWrapped = false,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                    })

                    local tagText = entry.slot
                    if #entry.tags > 0 then
                        tagText = tagText .. " - " .. table.concat(entry.tags, ",")
                    end
                    Label(row, {
                        Text = tagText,
                        TextColor3 = worn and C.text or C.mute,
                        TextSize = 10,
                        AnchorPoint = Vector2.new(1, 0.5),
                        Position = UDim2.new(1, -10, 0.5, 0),
                        Size = UDim2.fromOffset(100, 28),
                        TextXAlignment = Enum.TextXAlignment.Right,
                        TextTruncate = Enum.TextTruncate.AtEnd,
                    })

                    row.MouseEnter:Connect(function()
                        if not worn then
                            Tween(row, 0.1, { BackgroundColor3 = C.cardHi })
                        end
                    end)
                    row.MouseLeave:Connect(function()
                        if not worn then
                            Tween(row, 0.1, { BackgroundColor3 = C.card })
                        end
                    end)
                    row.MouseButton1Click:Connect(function()
                        if ToggleVisual(entry.id) then
                            Rebuild()
                        end
                    end)
                end
            end
        end

        local footer = Label(results, {
            Size = UDim2.new(1, 0, 0, 20),
            Text = string.format("Menampilkan %d dari %d item", shown, total),
            TextColor3 = C.mute,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Center,
            LayoutOrder = limit + 1,
        })

        if total > shown then
            local more = MakeButton(results, "Muat lebih banyak", "ghost", {
                Size = UDim2.new(1, 0, 0, 30),
                LayoutOrder = limit + 2,
            })
            more.MouseButton1Click:Connect(function()
                limit += 60
                Rebuild()
            end)
        end
        footer.Name = "Footer"
    end

    resetButton.MouseButton1Click:Connect(function()
        ResetVisuals()
        Rebuild()
    end)
    search:GetPropertyChangedSignal("Text"):Connect(function()
        limit = 60
        Rebuild()
    end)
    Rebuild()
end

-- Halaman: Sesi ------------------------------------------------------
hub.builders.session = function(page)
    AddNote(page, "Sesi menyimpan fitur aktif, Pos 1/2 dan world terakhir ke file. Setelah ganti world atau rejoin, skrip jalan lagi dan fitur dipulihkan otomatis.")

    local card = AddCard(page, 84)
    local info = Label(card, {
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 1, -16),
        TextSize = 11,
        TextColor3 = C.mute,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = "",
    })
    local function Refresh()
        local active = {}
        for key, feature in pairs(Features) do
            if Config.session[key] then
                table.insert(active, feature.label)
            end
        end
        table.sort(active)
        info.Text = table.concat({
            "World terakhir: " .. (Config.lastWorld ~= "" and Config.lastWorld or "-"),
            "Fitur tersimpan: " .. (#active > 0 and table.concat(active, ", ") or "-"),
            "Simpan file: " .. (writefile and "tersedia" or "TIDAK tersedia"),
            "Auto-reload: " .. (ReloadReady() and "siap" or "belum siap (simpan skrip di workspace / isi URL)"),
        }, "\n")
    end
    table.insert(hub.refreshers, Refresh)
    Refresh()

    AddSection(page, "Otomatis")
    AddSwitchCard(page, "Pulihkan fitur", "Nyalakan lagi fitur yang aktif sebelumnya saat skrip dimuat.",
        function() return Config.autoRestore end,
        function(on) Config.autoRestore = on SaveConfig() end)
    AddSwitchCard(page, "Auto-reload skrip", "Jalankan ulang skrip setelah pindah world / rejoin.",
        function() return Config.autoReload end,
        function(on)
            Config.autoReload = on
            SaveConfig()
            if on then QueueReload() end
            Refresh()
        end)
    AddSwitchCard(page, "Masuk world terakhir", "Setelah buka Roblox, warp otomatis ke world terakhir.",
        function() return Config.autoWarp end,
        function(on) Config.autoWarp = on SaveConfig() end)

    AddSection(page, "Sumber skrip")
    AddInputCard(page, "URL skrip (opsional)", "Dipakai auto-reload tanpa file", Config.scriptUrl, "https://...", function(text, box)
        Config.scriptUrl = Trim(text)
        box.Text = Config.scriptUrl
        SaveConfig()
        QueueReload()
        Refresh()
    end)

    AddSection(page, "Aksi")
    AddButton(page, "Simpan sesi sekarang", "primary", function()
        SaveSessionNow()
        Notify("Sesi disimpan.")
        Refresh()
    end)
    AddButton(page, "Pasang auto-execute (autoexec)", "ghost", function()
        InstallAutoexec()
    end)
    AddButton(page, "Reset sesi", "danger", function()
        Config.session = {}
        Config.lastWorld = ""
        SaveConfig()
        Notify("Sesi direset.")
        Refresh()
    end)
end

-- Halaman: Setelan ---------------------------------------------------
hub.builders.settings = function(page)
    AddNote(page, "Prefix boleh apa saja atau dikosongkan. " .. "/settingsgb dan /sgb selalu bisa dibuka dengan \"/\" walau prefix diganti.")

    AddSection(page, "Command")
    AddInputCard(page, "Prefix", "Kosong = tanpa prefix", Config.prefix, "(kosong)", function(text, box)
        Config.prefix = Trim(text)
        box.Text = Config.prefix
        SaveConfig()
        Notify(Config.prefix == "" and "Prefix dikosongkan." or ("Prefix: " .. Config.prefix))
        if hub.pages.help then
            ClearPage(hub.pages.help)
            hub.builders.help(hub.pages.help)
        end
    end)
    AddInputCard(page, "ID item drop", "Dipakai oleh wld / wd", Config.dropId, "242", function(text, box)
        local value = tonumber(text)
        if value and value >= 1 and value == math.floor(value) then
            Config.dropId = value
            SaveConfig()
            Notify("ID drop: " .. value)
        else
            Notify("ID tidak valid!")
        end
        box.Text = tostring(Config.dropId)
    end)
    AddInputCard(page, "Auto-drop saat win", "Jumlah WL otomatis (0 = mati)", Config.winDrop, "0", function(text, box)
        local value = tonumber(text)
        if value and value >= 0 and value <= MAX_AMOUNT and value == math.floor(value) then
            Config.winDrop = value
            SaveConfig()
            Notify(value == 0 and "Auto-drop dimatikan." or ("Auto-drop win: " .. value))
        else
            Notify("Isi angka 0-" .. MAX_AMOUNT .. "!")
        end
        box.Text = tostring(Config.winDrop)
    end)

    AddSection(page, "Fitur")
    AddInputCard(page, "Jangkauan longhand", "Tile tambahan (1-20)", Config.longhandRange, "3", function(text, box)
        local value = tonumber(text)
        if value and value >= 1 and value <= 20 then
            Config.longhandRange = value
            SaveConfig()
            if longhandOn then
                ApplyLonghand()
            end
            Notify("Longhand: +" .. value .. " tile")
        else
            Notify("Isi angka 1-20!")
        end
        box.Text = tostring(Config.longhandRange)
    end)
    AddInputCard(page, "Blink minimum", "Detik (0.05-10)", Config.blinkMin, "0.2", function(text, box)
        local value = tonumber(text)
        if value and value >= 0.05 and value <= 10 then
            Config.blinkMin = value
            SaveConfig()
        else
            Notify("Isi angka 0.05-10!")
        end
        box.Text = tostring(Config.blinkMin)
    end)
    AddInputCard(page, "Blink maksimum", "Detik (0.05-10)", Config.blinkMax, "0.5", function(text, box)
        local value = tonumber(text)
        if value and value >= 0.05 and value <= 10 then
            Config.blinkMax = value
            SaveConfig()
        else
            Notify("Isi angka 0.05-10!")
        end
        box.Text = tostring(Config.blinkMax)
    end)

    AddSection(page, "Lainnya")
    AddSwitchCard(page, "Tombol melayang", "Tombol P untuk buka/tutup menu (bisa digeser).",
        function() return Config.launcher end,
        function(on)
            Config.launcher = on
            SaveConfig()
            if hub.launcher then
                hub.launcher.Visible = on
            end
        end)
    AddButton(page, "Tutup Menu", "danger", function()
        if hub.close then
            hub.close()
        end
    end)
end

-- Halaman: Bantuan (/hpx) --------------------------------------------
local function HelpEntries()
    local p = Config.prefix
    return {
        { p .. "wld <jumlah>  |  " .. p .. "wd", "Drop World Lock (ID item di Setelan)" },
        { p .. "tp <world>  |  " .. p .. "warp", "Pindah ke world lain" },
        { p .. "pos1  |  " .. p .. "pos2", "Simpan posisi sekarang sebagai Pos 1 / Pos 2" },
        { p .. "win1  |  " .. p .. "w1  [jumlah]", "Teleport ke Pos 1, opsional langsung drop WL" },
        { p .. "win2  |  " .. p .. "w2  [jumlah]", "Teleport ke Pos 2, opsional langsung drop WL" },
        { p .. "pos", "Lihat posisi sekarang & pos tersimpan" },
        { p .. "rejoin  |  " .. p .. "rj", "Masuk ulang ke world ini" },
        { p .. "noclip  [on/off]", "Tembus blok & terbang (mode ghost game)" },
        { p .. "unlimitedjump  |  " .. p .. "uj", "Lompat di udara tanpa batas" },
        { p .. "blink  [on/off]", "Warna skin berganti otomatis" },
        { p .. "longhand [n]  |  " .. p .. "lh", "Jangkauan punch & build lebih jauh" },
        { p .. "visualitem  |  " .. p .. "vi", "GUI item visual (Kuyang, LegendBot, Rayman...)" },
        { p .. "settingsgb  |  " .. p .. "sgb", "Buka/tutup menu ini (tab Setelan)" },
        { p .. "afk", "Anti-AFK (tidak kena kick idle)" },
        { p .. "autorejoin  |  " .. p .. "arj", "Rejoin otomatis kalau terputus" },
        { p .. "session  |  " .. p .. "sesi", "Buka tab Sesi (simpan & pulihkan otomatis)" },
        { p .. "af  |  " .. p .. "autofarm  [on/off]", "Buka GUI Auto Farm (on/off untuk langsung jalan/berhenti)" },
        { p .. "ctp  |  " .. p .. "clicktp  [on/off]", "Click TP: klik tujuan, karakter menyusuri path (terlihat seperti teleport)" },
        { p .. "ac  |  " .. p .. "autoclear  [on/off]", "Auto Clear World: GrowScan, break 1-4 block per pukulan (bisa diatur), ambil drop (lock & bedrock aman)" },
        { p .. "move  |  " .. p .. "mv  <walk/fly/mix>", "Mode gerak: jalan, terbang, atau campur (jalan dulu, buntu = terbang)" },
        { p .. "spam  [on/off]", "Kirim teks spam ke chat berulang (teks diatur lewat setspam / tab Spam)" },
        { p .. "setspam  <teks>", "Atur teks spam, contoh: " .. p .. "setspam Halo semua!" },
        { p .. "df  |  " .. p .. "autodf  [on/off]", "Auto DF: dig ke bawah, break block di bawah karakter sampai mentok" },
        { p .. "aq  |  " .. p .. "autoquest  [on/off/scan]", "Auto quest; scan = lihat hasil baca quest" },
        { p .. "gs  |  " .. p .. "growscan", "Buka GrowScan" },
        { p .. "god  [on/off]", "God mode: kebal lava, spike, api" },
        { p .. "blockid <nama>  |  " .. p .. "bid", "Cari ID block dari nama" },
        { p .. "hpx", "Buka/tutup daftar fitur" },
    }
end

hub.builders.help = function(page)
    AddNote(page, "Semua fitur Peex HUB. Fitur on/off: ketik tanpa argumen untuk toggle.")
    for _, entry in ipairs(HelpEntries()) do
        local card = AddCard(page, 52)
        Label(card, {
            Text = entry[1],
            Font = Enum.Font.Code,
            TextColor3 = C.accent2,
            TextSize = 12,
            Position = UDim2.fromOffset(12, 7),
            Size = UDim2.new(1, -24, 0, 16),
            TextWrapped = false,
        })
        Label(card, {
            Text = entry[2],
            TextColor3 = C.mute,
            TextSize = 11,
            Position = UDim2.fromOffset(12, 25),
            Size = UDim2.new(1, -24, 0, 24),
            TextYAlignment = Enum.TextYAlignment.Top,
        })
    end
end

-- Komponen: kotak pencarian item (database ItemDB) ------------------
local function CopyId(id)
    if setclipboard then
        pcall(setclipboard, tostring(id))
    end
end

local function AddItemSearch(page, onPick, placeholder)
    local card = AddCard(page, 38)
    local box = New("TextBox", {
        Position = UDim2.fromOffset(10, 5),
        Size = UDim2.new(1, -20, 0, 28),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = placeholder or "Cari nama block atau ID...",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 12,
        ClearTextOnFocus = false,
    }, card)
    Corner(box, 8)
    Stroke(box, C.stroke, 1, 0.2)

    local results = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, results)

    local function Populate()
        for _, child in ipairs(results:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("TextLabel") then
                child:Destroy()
            end
        end
        if Trim(box.Text) == "" then
            return
        end
        local found = SearchItems(box.Text, 25)
        if #found == 0 then
            Label(results, {
                Size = UDim2.new(1, 0, 0, 20),
                Text = "Tidak ada hasil.",
                TextColor3 = C.mute,
                TextSize = 11,
            })
            return
        end
        for index, entry in ipairs(found) do
            local row = MakeButton(results, string.format("%s   [ID %d]", entry.name, entry.id), "ghost", {
                Size = UDim2.new(1, 0, 0, 28),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = index,
            })
            New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, row)
            row.MouseButton1Click:Connect(function()
                CopyId(entry.id)
                onPick(entry)
            end)
        end
    end

    local pending = 0
    box:GetPropertyChangedSignal("Text"):Connect(function()
        pending += 1
        local mine = pending
        task.delay(0.25, function()
            if mine == pending then
                Populate()
            end
        end)
    end)
    return box
end

-- Halaman: Auto Farm -------------------------------------------------
local function GridCount()
    local n = 0
    for _, on in pairs(Config.farmGrid) do
        if on then
            n += 1
        end
    end
    return n
end

hub.builders.farm = function(page)
    local status = AddCard(page, 78)
    local statusLabel = Label(status, {
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 1, -12),
        Text = "...",
        TextSize = 12,
        Font = CARTOON_FONT,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local function UpdateStatus()
        local id = Config.farmPlaceId
        local blockText = (type(id) == "number" and id > 0) and (ItemName(id) .. " (ID " .. id .. ")") or "belum dipilih"
        statusLabel.Text = string.format(
            "Status: %s\nBlock: %s\nKotak target: %d  |  jeda %.2f dtk\nPlace %d  Break %d  Ambil %d  Siklus %d",
            farmStats.status, blockText, GridCount(), Config.farmDelay,
            farmStats.placed, farmStats.broken, farmStats.picked, farmStats.cycles)
    end
    UpdateStatus()
    local owner = hub.frame
    task.spawn(function()
        while hub.frame == owner and owner and owner.Parent do
            task.wait(0.4)
            pcall(UpdateStatus)
        end
    end)

    AddSwitchCard(page, "Auto Farm", "Place, pukul, lalu ambil item. Berdiri di posisi farm sebelum menyalakan.",
        Features.autofarm.get, function(on) SetFeature("autofarm", on) end)

    AddSection(page, "Pengaturan")

    local idBox
    AddInputCard(page, "Kecepatan pukulan", "Jeda antar pukulan (detik). Normal game 0.22, minimum 0.03.",
        Config.farmDelay, "0.22", function(text, box)
            local value = tonumber(text)
            if value and value >= 0.03 and value <= 5 then
                Config.farmDelay = value
                SaveConfig()
            else
                box.Text = tostring(Config.farmDelay)
                Notify("Isi angka 0.03 sampai 5.")
            end
        end)

    idBox = AddInputCard(page, "ID block", "Block yang di-place. Cari nama di bawah supaya ID terisi.",
        Config.farmPlaceId, "ID", function(text, box)
            local value = tonumber(text)
            if value and value > 0 and ItemName(value) ~= "?" then
                Config.farmPlaceId = value
                SaveConfig()
                Notify("Block: " .. ItemName(value) .. " (ID " .. value .. ")")
            else
                box.Text = tostring(Config.farmPlaceId)
                Notify("ID tidak ada di database item.")
            end
        end)

    AddSection(page, "Pola place (grid 5x5)")
    AddNote(page, "Kotak tengah (KAMU) = posisi player. Tap kotak sampai HIJAU: block akan di-place di kotak itu. Merah = dilewati.")
    local gridCard = AddCard(page, 5 * 34 + 12)
    local gridFrame = New("Frame", {
        Position = UDim2.fromOffset(8, 6),
        Size = UDim2.new(1, -16, 1, -12),
        BackgroundTransparency = 1,
    }, gridCard)
    New("UIGridLayout", {
        CellSize = UDim2.new(0.2, -4, 0, 30),
        CellPadding = UDim2.fromOffset(4, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, gridFrame)
    local gridButtons = {}
    local function PaintCell(key)
        local cell = gridButtons[key]
        if cell then
            cell.BackgroundColor3 = Config.farmGrid[key] and C.ok or C.bad
        end
    end
    for dy = -2, 2 do
        for dx = -2, 2 do
            local key = dx .. "," .. dy
            local cell = New("TextButton", {
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = (dx == 0 and dy == 0) and "KAMU" or "",
                TextColor3 = C.text,
                Font = CARTOON_FONT,
                TextSize = (dx == 0 and dy == 0) and 10 or 13,
                LayoutOrder = (dy + 2) * 5 + (dx + 2),
            }, gridFrame)
            Corner(cell, 6)
            if dx == 0 and dy == 0 then
                cell.BackgroundColor3 = C.accent2
            else
                gridButtons[key] = cell
                PaintCell(key)
                cell.MouseButton1Click:Connect(function()
                    Config.farmGrid[key] = (not Config.farmGrid[key]) or nil
                    SaveConfig()
                    PaintCell(key)
                end)
            end
        end
    end
    AddButton(page, "Kosongkan semua kotak", "ghost", function()
        Config.farmGrid = {}
        SaveConfig()
        for key in pairs(gridButtons) do
            PaintCell(key)
        end
    end)

    AddSwitchCard(page, "Ambil item otomatis", "Setelah break, teleport ke item yang jatuh lalu kembali ke posisi farm.",
        function() return Config.farmTake end,
        function(on)
            Config.farmTake = on
            SaveConfig()
        end)

    AddSection(page, "Database item")
    AddNote(page, "Ketik nama block atau ID, lalu tap hasilnya untuk dipakai di Auto Farm (ID juga disalin kalau executor mendukung).")
    AddItemSearch(page, function(entry)
        Config.farmPlaceId = entry.id
        SaveConfig()
        if idBox then
            idBox.Text = tostring(entry.id)
        end
        Notify("Block: " .. entry.name .. " (ID " .. entry.id .. ")")
    end)
end

-- Halaman: Auto Clear World ------------------------------------------
hub.builders.clear = function(page)
    local status = AddCard(page, 84)
    local statusLabel = Label(status, {
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 1, -12),
        Text = "...",
        TextSize = 12,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local function UpdateStatus()
        local st = Clear.stats
        statusLabel.Text = string.format(
            "Status: %s  (pass %d)  |  Mode: %s\nTarget %d  |  Sisa %d  |  Dilewati %d\nPecah %d  Ambil %d\nDelay break %.2f dtk  |  delay gerak %.2f dtk",
            Clear.status, st.pass, Config.clearMoveMode == "walk" and "Jalan" or "Teleport",
            st.scanned, st.left, st.skipped, st.broken, st.picked,
            Config.clearBreakDelay, Config.clearTpDelay)
    end
    UpdateStatus()
    local owner = hub.frame
    task.spawn(function()
        while hub.frame == owner and owner and owner.Parent do
            task.wait(0.4)
            pcall(UpdateStatus)
        end
    end)

    AddSwitchCard(page, "Auto Clear World", "GrowScan dulu, lalu pecah semua block (kecuali lock & bedrock).",
        Features.autoclear.get, function(on) SetFeature("autoclear", on) end)

    AddSection(page, "Pengaturan")
    AddNote(page, "Jalan = lewat jalur kosong (pathfinding). Teleport = pindah langsung ke posisi target.")
    local walkButton, teleportButton
    local function UpdateClearMoveButtons()
        local walkActive = Config.clearMoveMode == "walk"
        walkButton.Text = walkActive and "✓ Jalan (aktif)" or "Jalan"
        teleportButton.Text = (not walkActive) and "✓ Teleport (aktif)" or "Teleport"
    end
    walkButton = AddButton(page, "Jalan", "ghost", function()
        Config.clearMoveMode = "walk"
        SaveConfig()
        UpdateClearMoveButtons()
        Notify("Mode Auto Clear: Jalan")
    end)
    teleportButton = AddButton(page, "Teleport", "ghost", function()
        Config.clearMoveMode = "teleport"
        SaveConfig()
        UpdateClearMoveButtons()
        Notify("Mode Auto Clear: Teleport")
    end)
    UpdateClearMoveButtons()

    AddInputCard(page, "Tile per grup", "Jumlah tile yang dipukul bersama (1 sampai 4). Default 3.",
        Config.clearBatch, "3", function(text, box)
            local value = tonumber(text)
            if value and value >= 1 and value <= 4 then
                Config.clearBatch = math.floor(value)
                SaveConfig()
            else
                box.Text = tostring(Config.clearBatch)
                Notify("Isi angka 1 sampai 4.")
            end
        end)
    AddInputCard(page, "Delay break", "Jeda tiap putaran pukul (detik). Game memukul tiap 0.22 dtk.",
        Config.clearBreakDelay, "0.22", function(text, box)
            local value = tonumber(text)
            if value and value >= 0.03 and value <= 5 then
                Config.clearBreakDelay = value
                SaveConfig()
            else
                box.Text = tostring(Config.clearBreakDelay)
                Notify("Isi angka 0.03 sampai 5.")
            end
        end)
    AddInputCard(page, "Delay gerak", "Jeda setelah berpindah posisi / ambil drop (detik).",
        Config.clearTpDelay, "0.25", function(text, box)
            local value = tonumber(text)
            if value and value >= 0.03 and value <= 5 then
                Config.clearTpDelay = value
                SaveConfig()
            else
                box.Text = tostring(Config.clearTpDelay)
                Notify("Isi angka 0.03 sampai 5.")
            end
        end)
    AddSwitchCard(page, "Ambil item otomatis", "Bergerak ke item drop sesuai mode Auto Clear, sapu sisa di akhir.",
        function() return Config.clearTake end,
        function(on)
            Config.clearTake = on
            SaveConfig()
        end)
    AddButton(page, "GrowScan sekarang", "primary", function()
        task.spawn(function()
            local scan = ScanWorld()
            if not scan then
                Notify("World tidak terbaca.")
                return
            end
            local fg, bg, drops = 0, 0, 0
            for _, n in pairs(scan.fg) do fg += n end
            for _, n in pairs(scan.bg) do bg += n end
            for _, n in pairs(scan.drops) do drops += n end
            Notify(string.format("GrowScan: %d fg, %d bg, %d item drop (world %dx%d)", fg, bg, drops, scan.w, scan.h))
        end)
    end)
    AddNote(page, "Alur: scan isi world -> pecah per grup 1-4 tile (default 3) -> ambil drop -> ulang sampai bersih. "
        .. "Pilih Jalan atau Teleport khusus Auto Clear. Block lock, area, bedrock, dan door utama tidak disentuh.")
end

-- Halaman: Spam Chat -------------------------------------------------
hub.builders.spam = function(page)
    local status = AddCard(page, 40)
    local statusLabel = Label(status, {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = "...",
        TextSize = 12,
        TextWrapped = false,
    })
    local function UpdateStatus()
        local text = Trim(Config.spamText or "")
        statusLabel.Text = (Spam.on and "Spam: AKTIF" or "Spam: mati") .. "   |   Teks: "
            .. (text ~= "" and text or "(kosong)")
    end
    UpdateStatus()
    local owner = hub.frame
    task.spawn(function()
        while hub.frame == owner and owner and owner.Parent do
            task.wait(0.5)
            pcall(UpdateStatus)
        end
    end)

    AddSwitchCard(page, "Spam Chat", "Kirim teks di bawah ke chat berulang-ulang.",
        Features.spam.get, function(on) SetFeature("spam", on) end)

    AddSection(page, "Teks spam")
    local card = AddCard(page, 78)
    Label(card, {
        Text = "Teks yang dikirim (maks 200 huruf, tidak boleh diawali /)",
        TextColor3 = C.mute,
        TextSize = 10,
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 0, 14),
        TextWrapped = false,
    })
    local box = New("TextBox", {
        Position = UDim2.fromOffset(10, 26),
        Size = UDim2.new(1, -20, 0, 42),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Text = tostring(Config.spamText or ""),
        PlaceholderText = "Ketik teks spam di sini...",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 13,
        ClearTextOnFocus = false,
        TextWrapped = true,
        MultiLine = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    Corner(box, 8)
    local boxStroke = Stroke(box, C.stroke, 1, 0.2)
    box.Focused:Connect(function()
        Tween(boxStroke, 0.12, { Color = C.accent })
    end)
    box.FocusLost:Connect(function()
        Tween(boxStroke, 0.12, { Color = C.stroke })
        if not Spam.SetText(box.Text) then
            box.Text = tostring(Config.spamText or "")
        end
    end)

    AddInputCard(page, "Delay antar pesan", "Detik per pesan (minimal 1.5). Terlalu cepat bisa kena mute moderator.",
        Config.spamDelay, "3", function(text, inputBox)
            local value = tonumber(text)
            if value and value >= 1.5 and value <= 120 then
                Config.spamDelay = value
                SaveConfig()
            else
                inputBox.Text = tostring(Config.spamDelay)
                Notify("Isi angka 1.5 sampai 120.")
            end
        end)
    AddButton(page, "Kirim sekali (tes)", "primary", function()
        local text = Trim(Config.spamText or "")
        if text == "" then
            Notify("Teks spam masih kosong.")
            return
        end
        Spam.guardText = text:lower()
        Spam.guardT = os.clock()
        if not Spam.Send(text) then
            Notify("Gagal kirim: chat tidak ditemukan.")
        end
    end)
    AddNote(page, "Command: /spam on|off untuk nyalakan/matikan, /setspam <teks> untuk mengganti teks. "
        .. "Game punya sistem mute dari moderator, jadi pakai delay yang wajar.")
end

-- Halaman: Click TP / Pathfinding ------------------------------------
hub.builders.nav = function(page)
    local status = AddCard(page, 40)
    local statusLabel = Label(status, {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = "...",
        TextSize = 12,
        TextWrapped = false,
    })
    local function UpdateStatus()
        statusLabel.Text = "Terakhir: " .. Nav.last
    end
    UpdateStatus()
    local owner = hub.frame
    task.spawn(function()
        while hub.frame == owner and owner and owner.Parent do
            task.wait(0.4)
            pcall(UpdateStatus)
        end
    end)

    AddSwitchCard(page, "Click TP", "Klik mana saja, karakter menyusuri path ke sana.",
        Features.clicktp.get, function(on) SetFeature("clicktp", on) end)
    AddSection(page, "Pengaturan")
    AddSwitchCard(page, "Wajib tahan Shift", "Click TP hanya jalan kalau Shift (kiri atau kanan) ditahan di PC, supaya tidak ikut mukul.",
        function() return Config.clickTpShift end,
        function(on)
            Config.clickTpShift = on
            SaveConfig()
        end)
    AddSection(page, "Mode gerak (Click TP, Auto Clear, Auto Farm)")
    local modeCard = AddCard(page, 34)
    local modeLabel = Label(modeCard, {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = "...",
        TextSize = 12,
        TextWrapped = false,
    })
    local MODE_NAMES = { walk = "Jalan", fly = "Terbang", mix = "Campur" }
    local function UpdateMode()
        modeLabel.Text = "Mode aktif: " .. (MODE_NAMES[Config.moveMode] or "Campur")
    end
    UpdateMode()
    local function SetMode(mode)
        Config.moveMode = mode
        SaveConfig()
        UpdateMode()
        Notify("Mode gerak: " .. MODE_NAMES[mode])
    end
    AddButton(page, "Jalan  (lewat jalur kosong)", "primary", function() SetMode("walk") end)
    AddButton(page, "Terbang  (lurus, tembus block)", "primary", function() SetMode("fly") end)
    AddButton(page, "Campur  (jalan dulu, buntu = terbang)", "primary", function() SetMode("mix") end)
    AddInputCard(page, "Kecepatan jalan", "Tile per frame saat menyusuri path (1 sampai 12).",
        Config.navSpeed, "2", function(text, box)
            local value = tonumber(text)
            if value and value >= 1 and value <= 12 then
                Config.navSpeed = math.floor(value)
                SaveConfig()
            else
                box.Text = tostring(Config.navSpeed)
                Notify("Isi angka 1 sampai 12.")
            end
        end)
    AddNote(page, "Jalan: cari rute lewat tile kosong lalu pindah tile demi tile. Kalau tidak ada rute, gagal. "
        .. "Terbang: garis lurus menembus block (mode ghost hanya menyala selama terbang). "
        .. "Campur: jalan dulu, kalau tidak ada rute otomatis terbang. "
        .. "Klik juga bisa memukul block di titik itu; aktifkan 'Wajib tahan Shift' kalau mengganggu.")
end

-- Halaman: Auto Quest ------------------------------------------------
hub.builders.quest = function(page)
    local status = AddCard(page, 40)
    local statusLabel = Label(status, {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = "...",
        TextSize = 12,
        Font = CARTOON_FONT,
        TextWrapped = false,
    })
    local function UpdateStatus()
        statusLabel.Text = "Status: " .. questStatus
    end
    UpdateStatus()
    local owner = hub.frame
    task.spawn(function()
        while hub.frame == owner and owner and owner.Parent do
            task.wait(0.5)
            pcall(UpdateStatus)
        end
    end)

    AddSwitchCard(page, "Auto Quest", "Claim reward lalu kerjakan quest break/place lewat Auto Farm.",
        Features.autoquest.get, function(on) SetFeature("autoquest", on) end)
    AddButton(page, "Baca quest sekarang", "primary", function()
        task.spawn(QuestReport)
    end)
    AddNote(page, "Syarat: block untuk quest harus ada di inventory. Quest yang tidak dikenali dilewati. "
        .. "Kalau quest tidak terbaca, tekan tombol di atas dan lihat hasilnya.")
end

-- Halaman: GrowScan --------------------------------------------------
hub.builders.scan = function(page)
    AddButton(page, "Buka GrowScan game", "primary", function()
        if not OpenNativeGrowScan() then
            Notify("GrowScan bawaan game tidak tersedia, pakai scan dunia di bawah.")
        end
    end)

    local list = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
    }, page)
    New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, list)

    local function Render()
        for _, child in ipairs(list:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end
        local data = ScanWorld()
        if not data then
            Label(list, { Size = UDim2.new(1, 0, 0, 20), Text = "World belum terbaca.", TextColor3 = C.mute, TextSize = 11 })
            return
        end
        local order = 0
        local function AddGroup(title, counts, pickable)
            local entries = {}
            for id, count in pairs(counts) do
                table.insert(entries, { id = id, count = count })
            end
            table.sort(entries, function(a, b)
                if a.count ~= b.count then
                    return a.count > b.count
                end
                return a.id < b.id
            end)
            order += 1
            Label(list, {
                Size = UDim2.new(1, 0, 0, 18),
                Text = string.upper(title) .. " (" .. #entries .. " jenis)",
                TextColor3 = C.mute,
                Font = CARTOON_FONT,
                TextSize = 11,
                TextWrapped = false,
                LayoutOrder = order,
            })
            for _, entry in ipairs(entries) do
                order += 1
                local row = MakeButton(list, string.format("%s   [ID %d]   x%d", ItemName(entry.id), entry.id, entry.count), "ghost", {
                    Size = UDim2.new(1, 0, 0, 26),
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = order,
                })
                New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, row)
                row.MouseButton1Click:Connect(function()
                    CopyId(entry.id)
                    if pickable then
                        Config.farmPlaceId = entry.id
                        SaveConfig()
                        Notify("Block Auto Farm: " .. ItemName(entry.id) .. " (ID " .. entry.id .. ")")
                    else
                        Notify(ItemName(entry.id) .. " = ID " .. entry.id)
                    end
                end)
            end
        end
        AddGroup("Foreground", data.fg, true)
        AddGroup("Background", data.bg, true)
        AddGroup("Item tergeletak", data.drops, false)
    end

    AddButton(page, "Scan isi world", "ghost", Render)
    AddNote(page, "Tap salah satu hasil untuk menjadikannya block Auto Farm (foreground/background).")
    -- pindahkan daftar hasil ke bawah tombol dan catatan
    list.LayoutOrder = NextOrder(page)
end

-- Halaman: Auto DF (dig ke bawah) ------------------------------------
hub.builders.dig = function(page)
    local status = AddCard(page, 62)
    local statusLabel = Label(status, {
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 1, -12),
        Text = "...",
        TextSize = 12,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local function UpdateStatus()
        statusLabel.Text = string.format("Status: %s\nBreak %d  |  Kedalaman %d tile\nJeda pukul %.2f dtk",
            Dig.status, Dig.stats.broken, Dig.stats.depth, Config.dfDelay)
    end
    UpdateStatus()
    local owner = hub.frame
    task.spawn(function()
        while hub.frame == owner and owner and owner.Parent do
            task.wait(0.4)
            pcall(UpdateStatus)
        end
    end)

    AddSwitchCard(page, "Auto DF", "Break block tepat di bawah karakter, jatuh, ulangi sampai mentok.",
        Features.autodf.get, function(on) SetFeature("autodf", on) end)

    AddSection(page, "Pengaturan")
    AddInputCard(page, "Kecepatan pukulan", "Jeda antar pukulan (detik). Normal game 0.22, minimum 0.03.",
        Config.dfDelay, "0.22", function(text, box)
            local value = tonumber(text)
            if value and value >= 0.03 and value <= 5 then
                Config.dfDelay = value
                SaveConfig()
            else
                box.Text = tostring(Config.dfDelay)
                Notify("Isi angka 0.03 sampai 5.")
            end
        end)
    AddSwitchCard(page, "Balik arah", "Nyalakan kalau karakter malah nge-break ke atas (sumbu Y terbalik).",
        function() return Config.dfFlip end,
        function(on)
            Config.dfFlip = on
            SaveConfig()
        end)
    AddNote(page, "Berdiri di atas tanah, nyalakan Auto DF. Berhenti otomatis kalau ketemu bedrock, lock, "
        .. "area, atau dasar world, atau kalau kamu pindah world. Command: /df on|off.")
end

-- Jendela utama ------------------------------------------------------
local TAB_ORDER = {
    { id = "features", label = "Fitur", icon = "Ft" },
    { id = "farm", label = "Auto Farm", icon = "Fm" },
    { id = "clear", label = "Auto Clear", icon = "Cl" },
    { id = "dig", label = "Auto DF", icon = "DF" },
    { id = "spam", label = "Spam Chat", icon = "Sp" },
    { id = "nav", label = "Click TP", icon = "TP" },
    { id = "quest", label = "Auto Quest", icon = "Qs" },
    { id = "scan", label = "GrowScan", icon = "Sc" },
    { id = "pos", label = "Posisi", icon = "Ps" },
    { id = "visual", label = "Visual Item", icon = "Vs" },
    { id = "session", label = "Sesi", icon = "Ss" },
    { id = "settings", label = "Setelan", icon = "St" },
    { id = "help", label = "Bantuan", icon = "?" },
}

local function SwitchTab(id)
    hub.active = id
    for tabId, page in pairs(hub.pages) do
        page.Visible = (tabId == id)
    end

    -- bangun halaman hanya saat tab pertama kali dibuka
    local selectedPage = hub.pages[id]
    if selectedPage and not (hub.built and hub.built[id]) then
        hub.built = hub.built or {}
        hub.built[id] = true
        local builder = hub.builders[id]
        if builder then
            local okBuild, err = pcall(builder, selectedPage)
            if not okBuild then
                AddNote(selectedPage, "Gagal memuat halaman: " .. tostring(err))
            end
        end
    end

    -- animasi masuk halaman
    if selectedPage then
        selectedPage.Position = UDim2.fromOffset(0, 58)
        Tween(selectedPage, 0.22, { Position = UDim2.fromOffset(0, 46) })
    end

    for tabId, tab in pairs(hub.tabs) do
        local active = (tabId == id)
        Tween(tab.button, 0.18, { BackgroundTransparency = active and 0.8 or 1 })
        if tab.label then
            tab.label.TextColor3 = active and C.text or C.mute
        end
        tab.bar.Visible = active
        Tween(tab.badge, 0.18, { BackgroundColor3 = active and C.accent or C.cardHi })
    end

    if hub.title then
        for _, tab in ipairs(TAB_ORDER) do
            if tab.id == id then
                hub.title.Text = tab.label
            end
        end
    end
end

-- Drag: listener gerakan hanya aktif selama sedang menyeret
local function MakeDraggable(handle, target)
    local state = { moved = false }
    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        state.moved = false
        local startPos = target.Position
        local startInput = input.Position
        local moveConn
        moveConn = UserInputService.InputChanged:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseMovement
                or i.UserInputType == Enum.UserInputType.Touch then
                local d = i.Position - startInput
                if d.Magnitude > 5 then
                    state.moved = true
                end
                if state.moved then
                    target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                        startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end
        end)
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End and moveConn then
                moveConn:Disconnect()
                moveConn = nil
            end
        end)
    end)
    return state
end

local function CloseHub()
    local frame = hub.frame
    if not frame then
        return
    end

    hub.frame = nil
    hub.active = nil
    hub.minimized = false
    hub.scale = nil
    hub.title = nil

    for _, connection in ipairs(hub.dragConnections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    hub.dragConnections = {}

    local scale = frame:FindFirstChildOfClass("UIScale")
    if scale then
        Tween(scale, 0.14, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    end
    task.delay(0.16, function()
        if frame and frame.Parent then
            frame:Destroy()
        end
    end)
end
hub.close = CloseHub

local function OpenHub(tabId)
    if hub.frame and hub.frame.Parent then
        SwitchTab(tabId)
        return
    elseif hub.frame then
        hub.frame = nil
        hub.active = nil
        hub.scale = nil
    end

    local guiRoot = GetGui()
    local oldWindow = guiRoot:FindFirstChild("Hub")
    if oldWindow then
        oldWindow:Destroy()
    end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(900, 650)
    local width = math.max(280, math.min(740, viewport.X - 24))
    local height = math.max(300, math.min(600, viewport.Y - 36))
    local sidebarWidth = width < 470 and 58 or 150
    hub.narrow = width < 470

    local frame = New("Frame", {
        Name = "Hub",
        Size = UDim2.fromOffset(width, height),
        Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2),
        BackgroundColor3 = C.window,
        BorderSizePixel = 0,
        Active = true,
        ClipsDescendants = true,
    }, guiRoot)
    Corner(frame, 18)
    UI.Gradient(New("UIStroke", {
        Thickness = 1.6,
        Transparency = 0.1,
        Color = C.accent,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, frame), C.accent, C.accent2, 45)

    local scale = New("UIScale", { Scale = 0.9 }, frame)
    Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

    hub.frame = frame
    hub.scale = scale
    hub.pages = {}
    hub.tabs = {}
    hub.refreshers = {}
    hub.built = {}
    hub.dragConnections = {}
    hub.minimized = false

    -- Header -------------------------------------------------------
    local header = New("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundColor3 = Color3.fromRGB(21, 29, 52),
        BorderSizePixel = 0,
    }, frame)
    UI.Gradient(header, Color3.new(1, 1, 1), Color3.fromRGB(205, 190, 255), 0)

    local logo = New("Frame", {
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.fromOffset(40, 40),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, header)
    Corner(logo, 12)
    UI.Gradient(logo, C.accent, C.accent2, 45)
    Label(logo, {
        Text = "P",
        Size = UDim2.fromScale(1, 1),
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = 22,
        Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextWrapped = false,
    })

    Label(header, {
        Text = "PEEX HUB",
        Position = UDim2.fromOffset(66, 10),
        Size = UDim2.new(1, -160, 0, 22),
        TextSize = 17,
        Font = Enum.Font.GothamBold,
        TextWrapped = false,
    })
    local subtitle = Label(header, {
        Text = "GROWBLOX",
        Position = UDim2.fromOffset(67, 32),
        Size = UDim2.new(1, -160, 0, 16),
        TextColor3 = C.accent,
        TextSize = 10,
        Font = Enum.Font.GothamMedium,
        TextWrapped = false,
    })
    task.spawn(function()
        while hub.frame == frame and frame.Parent do
            local w = CurrentWorldName()
            subtitle.Text = "GROWBLOX  •  " .. (w ~= "" and w or "NO WORLD")
            task.wait(1)
        end
    end)

    local close = MakeButton(header, "×", "danger", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
        TextSize = 20,
        Font = Enum.Font.GothamBold,
    })
    close.MouseButton1Click:Connect(CloseHub)

    local minimize = MakeButton(header, "−", "ghost", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -52, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
        TextSize = 18,
        Font = Enum.Font.GothamBold,
    })

    local accentLine = New("Frame", {
        Position = UDim2.fromOffset(0, 59),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, frame)
    UI.Gradient(accentLine, C.accent, C.accent2, 0)

    MakeDraggable(header, frame)

    -- Sidebar ------------------------------------------------------
    local sidebar = New("ScrollingFrame", {
        Name = "Navigation",
        Position = UDim2.fromOffset(10, 72),
        Size = UDim2.new(0, sidebarWidth - 10, 1, -84),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = C.accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, frame)
    Corner(sidebar, 14)
    Stroke(sidebar, C.stroke, 1, 0.6)
    New("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
    }, sidebar)
    New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, sidebar)

    -- Panel konten -------------------------------------------------
    local panel = New("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(sidebarWidth + 8, 72),
        Size = UDim2.new(1, -(sidebarWidth + 18), 1, -84),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, frame)
    Corner(panel, 14)
    Stroke(panel, C.stroke, 1, 0.45)

    hub.title = Label(panel, {
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.new(1, -32, 0, 46),
        Text = "Fitur",
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextWrapped = false,
    })
    local sep = New("Frame", {
        Position = UDim2.fromOffset(12, 45),
        Size = UDim2.new(1, -24, 0, 1),
        BackgroundColor3 = C.stroke,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
    }, panel)

    minimize.MouseButton1Click:Connect(function()
        hub.minimized = not hub.minimized
        sidebar.Visible = not hub.minimized
        panel.Visible = not hub.minimized
        accentLine.Visible = not hub.minimized
        minimize.Text = hub.minimized and "+" or "−"
        Tween(frame, 0.2, {
            Size = UDim2.fromOffset(width, hub.minimized and 60 or height),
        }, Enum.EasingStyle.Quint)
    end)

    for index, tab in ipairs(TAB_ORDER) do
        local button = New("TextButton", {
            Name = "Tab_" .. tab.id,
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = C.accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = index,
        }, sidebar)
        Corner(button, 10)

        local marker = New("Frame", {
            Position = UDim2.new(0, -3, 0.5, -10),
            Size = UDim2.fromOffset(3, 20),
            BackgroundColor3 = C.accent,
            BorderSizePixel = 0,
            Visible = false,
        }, button)
        Corner(marker, 2)

        local badge = New("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = hub.narrow and UDim2.new(0.5, -14, 0.5, 0) or UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = C.cardHi,
            BorderSizePixel = 0,
        }, button)
        Corner(badge, 8)
        Label(badge, {
            Text = tab.icon,
            Size = UDim2.fromScale(1, 1),
            TextColor3 = Color3.new(1, 1, 1),
            TextSize = 11,
            Font = Enum.Font.GothamBold,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextWrapped = false,
        })

        local tabLabel = nil
        if not hub.narrow then
            tabLabel = Label(button, {
                Text = tab.label,
                Position = UDim2.fromOffset(42, 0),
                Size = UDim2.new(1, -46, 1, 0),
                TextColor3 = C.mute,
                TextSize = 12,
                Font = Enum.Font.GothamSemibold,
                TextWrapped = false,
            })
        end

        button.MouseEnter:Connect(function()
            if hub.active ~= tab.id then
                Tween(button, 0.1, { BackgroundTransparency = 0.92 })
            end
        end)
        button.MouseLeave:Connect(function()
            if hub.active ~= tab.id then
                Tween(button, 0.1, { BackgroundTransparency = 1 })
            end
        end)
        button.MouseButton1Click:Connect(function()
            SwitchTab(tab.id)
        end)

        hub.tabs[tab.id] = { button = button, label = tabLabel, bar = marker, badge = badge }

        local page = New("ScrollingFrame", {
            Name = "Page_" .. tab.id,
            Position = UDim2.fromOffset(0, 46),
            Size = UDim2.new(1, 0, 1, -46),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = C.accent,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
        }, panel)
        New("UIListLayout", {
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, page)
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 12),
            PaddingRight = UDim.new(0, 14),
            PaddingTop = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 14),
        }, page)
        hub.pages[tab.id] = page
    end

    SwitchTab(tabId or "features")
end

local function ToggleHub(tabId)
    if hub.frame and not hub.frame.Parent then
        hub.frame = nil
        hub.active = nil
        hub.scale = nil
    end
    OpenHub(tabId)
end

-- Launcher P: bisa digeser, klik biasa untuk buka/tutup
local function BuildLauncher()
    local guiRoot = GetGui()
    local oldLauncher = guiRoot:FindFirstChild("Launcher")
    if oldLauncher then
        oldLauncher:Destroy()
    end

    local button = New("TextButton", {
        Name = "Launcher",
        Size = UDim2.fromOffset(50, 50),
        Position = UDim2.new(0, 14, 0.5, -25),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "P",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBlack,
        TextSize = 22,
        Visible = true,
        ZIndex = 50,
    }, guiRoot)
    Corner(button, 25)
    UI.Gradient(button, C.accent, C.accent2, 45)
    Stroke(button, Color3.new(1, 1, 1), 1.5, 0.6)
    local scale = New("UIScale", { Scale = 1 }, button)
    hub.launcher = button

    local drag = MakeDraggable(button, button)

    button.MouseEnter:Connect(function()
        Tween(scale, 0.12, { Scale = 1.1 }, Enum.EasingStyle.Back)
    end)
    button.MouseLeave:Connect(function()
        Tween(scale, 0.12, { Scale = 1 })
    end)
    button.Activated:Connect(function()
        if drag.moved then
            return
        end
        if hub.frame and hub.frame.Parent then
            CloseHub()
        else
            hub.frame = nil
            OpenHub("features")
        end
    end)
end


----------------------------------------------------------------------
-- PERINTAH TAMBAHAN: GrowScan & pencarian ID
----------------------------------------------------------------------
local function OpenGrowScan()
    if not OpenNativeGrowScan() then
        ToggleHub("scan")
    end
end

local function ShowItemIds(query)
    if Trim(query) == "" then
        Notify("Contoh: " .. Config.prefix .. "blockid dirt")
        return
    end
    local found = SearchItems(query, 5)
    if #found == 0 then
        Notify("Block '" .. query .. "' tidak ditemukan.")
        return
    end
    local parts = {}
    for _, entry in ipairs(found) do
        table.insert(parts, entry.name .. " = " .. entry.id)
    end
    Notify(table.concat(parts, " | "))
end

----------------------------------------------------------------------
-- COMMAND HANDLER
----------------------------------------------------------------------
local function ParseCommand(text)
    text = Trim(text)
    if text == "" then
        return nil
    end

    local prefix = Config.prefix
    local bodyText

    if prefix == "" then
        bodyText = text
    elseif text:sub(1, #prefix) == prefix then
        bodyText = text:sub(#prefix + 1)
    elseif text:sub(1, 1) == "/" then
        -- Pengaman: settings tetap bisa dibuka dengan "/" walau prefix diganti
        local word = text:sub(2):lower()
        if word == "settingsgb" or word == "sgb" then
            bodyText = text:sub(2)
        end
    end

    if not bodyText then
        return nil
    end

    local command, args = bodyText:match("^(%S+)%s*(.-)%s*$")
    if not command then
        return nil
    end
    return command:lower(), (args or ""):lower(), (args or "")
end

-- Argumen "on"/"off" eksplisit, tanpa argumen = toggle
local function WantedState(args, current)
    if args == "on" then
        return true
    elseif args == "off" then
        return false
    end
    return not current
end

local function HandleMessage(text)
    local command, args, rawArgs = ParseCommand(text)
    if not command then
        return false
    end

    if command == "wld" or command == "wd" then
        local amount = tonumber(args:match("^(%d+)$"))
        if not amount or amount < 1 or amount > MAX_AMOUNT then
            Notify("Jumlah tidak valid! Contoh: " .. Config.prefix .. command .. " 100")
        else
            task.spawn(DropWorldLock, amount)
        end
        return true

    elseif command == "tp" or command == "warp" then
        task.spawn(WarpToWorld, args)
        return true

    elseif command == "pos1" or command == "pos2" then
        SetPos(tonumber(command:sub(4)))
        RefreshHub()
        return true

    elseif command == "pos" then
        ShowPos()
        return true

    elseif command == "win1" or command == "w1" or command == "win2" or command == "w2" then
        local slot = tonumber(command:match("%d$"))
        local amount = tonumber(args:match("^(%d+)$"))
        if amount and (amount < 1 or amount > MAX_AMOUNT) then
            Notify("Jumlah tidak valid!")
        else
            task.spawn(GoToPos, slot, amount)
        end
        return true

    elseif command == "rejoin" or command == "rj" then
        task.spawn(Rejoin)
        return true

    elseif command == "noclip" then
        SetFeature("noclip", WantedState(args, noclipOn))
        return true

    elseif command == "unlimitedjump" or command == "uj" or command == "ujump" or command == "infjump" then
        SetFeature("ujump", WantedState(args, ujumpOn))
        return true

    elseif command == "afk" or command == "antiafk" then
        SetFeature("antiafk", WantedState(args, antiAfkOn))
        return true

    elseif command == "autorejoin" or command == "arj" then
        SetFeature("autorejoin", WantedState(args, arjOn))
        return true

    elseif command == "session" or command == "sesi" then
        ToggleHub("session")
        return true

    elseif command == "blink" then
        SetFeature("blink", WantedState(args, blinkOn))
        return true

    elseif command == "longhand" or command == "lh" then
        local value = tonumber(args)
        if value and value >= 1 and value <= 20 then
            Config.longhandRange = value
            SaveConfig()
            SetFeature("longhand", true)
        else
            SetFeature("longhand", WantedState(args, longhandOn))
        end
        return true

    elseif command == "visualitem" or command == "vi" then
        ToggleHub("visual")
        return true

    elseif command == "settingsgb" or command == "sgb" then
        ToggleHub("settings")
        return true

    elseif command == "autofarm" or command == "af" then
        if args == "on" or args == "start" then
            SetFeature("autofarm", true)
        elseif args == "off" or args == "stop" then
            SetFeature("autofarm", false)
        else
            ToggleHub("farm")
        end
        return true

    elseif command == "clicktp" or command == "ctp" then
        SetFeature("clicktp", WantedState(args, Nav.clickOn))
        return true

    elseif command == "move" or command == "mv" or command == "mode" then
        local m = (args or ""):lower()
        local map = { walk = "walk", jalan = "walk", fly = "fly", terbang = "fly", mix = "mix", campur = "mix" }
        if map[m] then
            Config.moveMode = map[m]
            SaveConfig()
            Notify("Mode gerak: " .. map[m])
        else
            Notify("Mode gerak sekarang: " .. tostring(Config.moveMode) .. ". Pakai: move walk | fly | mix")
        end
        return true

    elseif command == "spam" then
        SetFeature("spam", WantedState(args, Spam.on))
        return true

    elseif command == "setspam" then
        if Trim(rawArgs or "") == "" then
            local now = Trim(Config.spamText or "")
            Notify("Contoh: " .. Config.prefix .. "setspam Halo semua!   (sekarang: "
                .. (now ~= "" and now or "kosong") .. ")")
        else
            Spam.SetText(rawArgs)
        end
        return true

    elseif command == "autoclear" or command == "ac" or command == "clear" then
        if args == "on" or args == "start" then
            SetFeature("autoclear", true)
        elseif args == "off" or args == "stop" then
            SetFeature("autoclear", false)
        else
            ToggleHub("clear")
        end
        return true

    elseif command == "autodf" or command == "df" then
        SetFeature("autodf", WantedState(args, Dig.on))
        return true

    elseif command == "autoquest" or command == "aq" then
        if args == "scan" then
            task.spawn(QuestReport)
        else
            SetFeature("autoquest", WantedState(args, questOn))
        end
        return true

    elseif command == "growscan" or command == "gs" then
        task.spawn(OpenGrowScan)
        return true

    elseif command == "god" or command == "godmode" then
        SetFeature("god", WantedState(args, godOn))
        return true

    elseif command == "blockid" or command == "bid" then
        ShowItemIds(args)
        return true

    elseif command == "hpx" then
        ToggleHub("help")
        return true
    end

    return false
end

----------------------------------------------------------------------
-- DETEKSI CHAT
-- Chat GrowBlox pakai UI sendiri, jadi hook semua TextBox + Player.Chatted.
-- Pesan identik dalam 1.5 detik dianggap event ganda.
----------------------------------------------------------------------
local hooked = {}
local lastMessage = nil
local lastHandled = 0
local DEDUPE_WINDOW = 1.5

local function Process(text)
    if type(text) ~= "string" then
        return
    end

    local normalized = Trim(text):lower()
    -- pesan yang baru dikirim oleh fitur Spam bukan command
    if Spam.guardText and normalized == Spam.guardText and os.clock() - Spam.guardT < 5 then
        return
    end
    if normalized == lastMessage and os.clock() - lastHandled < DEDUPE_WINDOW then
        return
    end

    if HandleMessage(Trim(text)) then
        lastMessage = normalized
        lastHandled = os.clock()
    end
end

local function HookTextBox(box)
    if hooked[box] or not box:IsA("TextBox") then
        return
    end
    -- Jangan hook TextBox milik GUI Peex sendiri
    if rootGui and box:IsDescendantOf(rootGui) then
        return
    end
    hooked[box] = true

    local lastText = ""

    box:GetPropertyChangedSignal("Text"):Connect(function()
        if box.Text ~= "" then
            lastText = box.Text
        end
    end)

    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local text = box.Text ~= "" and box.Text or lastText
            lastText = ""
            Process(text)
        end
    end)
end

for _, descendant in ipairs(PlayerGui:GetDescendants()) do
    HookTextBox(descendant)
end
PlayerGui.DescendantAdded:Connect(HookTextBox)

Player.Chatted:Connect(Process)

-- Launcher + menu: error GUI muncul sebagai notifikasi (tidak hilang diam-diam)
do
    local function ShowError(where, err)
        warn("[PeexHub] " .. where .. ": " .. tostring(err))
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "Peex HUB error",
                Text = where .. ": " .. tostring(err):sub(1, 160),
                Duration = 10,
            })
        end)
    end

    local okLauncher, errLauncher = pcall(BuildLauncher)
    if not okLauncher then
        ShowError("Launcher", errLauncher)
    end

    task.defer(function()
        local okOpen, errOpen = pcall(OpenHub, "features")
        if not okOpen then
            ShowError("Menu", errOpen)
        end
    end)
end

-- Pengaman: kalau setelah 2 detik tidak ada GUI sama sekali, bangun ulang
task.delay(2, function()
    local hasLauncher = hub.launcher and hub.launcher.Parent
    local hasWindow = hub.frame and hub.frame.Parent
    if not hasLauncher and not hasWindow then
        rootGui = nil
        pcall(BuildLauncher)
        pcall(OpenHub, "features")
    end
end)

-- Auto-reload: antrekan skrip untuk server/world berikutnya
pcall(QueueReload)
Player.OnTeleport:Connect(function()
    SaveConfig() -- sesi sudah tersimpan tiap fitur diubah
    pcall(QueueReload)
end)

-- Catat world terakhir
task.spawn(function()
    while true do
        task.wait(2)
        local name = CurrentWorldName()
        if name ~= "" and name ~= Config.lastWorld then
            Config.lastWorld = name
            SaveConfig()
        end
    end
end)

task.spawn(RestoreSession)

if Config.autoReload and not ReloadReady() then
    task.delay(3, function()
        Notify("Auto-reload belum siap: simpan skrip sebagai " .. SCRIPT_FILE .. " di workspace atau isi URL di tab Sesi.")
    end)
end

if FindInventory() then
    Notify("Peex HUB loaded! Tekan tombol P atau ketik " .. Config.prefix .. "hpx.")
else
    Notify("Loaded, tapi inventory game belum ditemukan (cek executor).")
end
