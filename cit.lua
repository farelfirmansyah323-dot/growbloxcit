--[[
    Peex HUB | GrowBlox  (v13 - GUI ringan, Punch Auto Clear 1-3, Spam fix, Auto Dirt Farm)
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
      ac|autoclear [on|off]  Auto Clear World (GrowScan dulu, mode jalan / teleport, ambil drop)
      acmode <walk|tp>       Mode Auto Clear: jalan (turun 1x, sapu baris sampai ujung, ulangi) / teleport
      acpunch <1-3>          Jumlah block yang dipukul sekaligus oleh Auto Clear (1 sampai 3)
      df|dirtfarm [on|off]   Auto Dirt Farm (dig turun 2x, sapu baris, respawn, place dirt naik)
      dirtid <id|nama>       Atur block dirt untuk Auto Dirt Farm (default: otomatis cari "Dirt")
      ctp|clicktp [on|off]   Click TP: klik mana saja, jalan lewat path (tampil seperti teleport)
      move|mv <walk|tp|fly|mix> Mode gerak: jalan asli / teleport 3-5 block / terbang / campur
      spam [on|off]          Kirim teks spam ke chat berulang
      setspam <teks>         Atur teks spam
      hiddenname|hn <off|self|all>  Sembunyikan nama (lokal saja)
      breakid <id,id,...>    Scan & pecahkan block ID tertentu
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

-- Cegah dobel-eksekusi
local genv = (getgenv and getgenv()) or _G
if genv.PeexHubGB_Loaded then
    -- Diam kalau cuma eksekusi ganda otomatis (autoexec + auto-reload)
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
    -- Auto Dirt Farm
    dirtId = 0,             -- ID block dirt yang di-place (0 = otomatis cari item bernama "Dirt")
    dirtPlace = true,       -- setelah dig + respawn, place dirt dari bawah ke atas
    clearMode = "walk",     -- "walk" = jalan asli, turun 1x lalu sapu baris sampai ujung | "teleport" = pindah ke grup block
    -- Hidden Name (tampilan lokal)
    hiddenNameMode = "off", -- "off" | "self" | "all"
    -- Auto Break by Block ID
    breakIdText = "",       -- daftar ID block (pisah koma/spasi), cth: "4,112"
    -- Spam Chat
    spamText = "",         -- teks yang dikirim berulang (isi lewat /setspam atau tab Spam)
    spamDelay = 3,          -- jeda antar pesan (detik, minimal 1.5)
    -- Pathfinding / Click TP
    navPath = true,         -- (lama, tidak dipakai lagi; diganti moveMode)
    moveMode = "mix",       -- "walk" = jalan asli (analog) | "tp" = teleport per 3-5 block | "fly" = terbang tembus block | "mix" = jalan dulu, kalau buntu terbang
    hopMin = 3,             -- teleport bertahap: minimal tile per lompatan
    hopMax = 5,             -- teleport bertahap: maksimal tile per lompatan
    hopDelay = 0.12,        -- jeda antar lompatan (detik)
    navSpeed = 2,           -- jumlah tile per frame saat menyusuri path (1-12)
    clickTpShift = false,   -- Click TP hanya aktif kalau tahan Shift kiri atau kanan (PC)
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

local Nav -- didefinisikan di bagian Pathfinding

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

    local ok, err
    if Nav and Nav.Tele then
        ok, err = Nav.Tele(pos.x, pos.y)
        if not ok and err ~= "cancel" then
            -- cadangan: lompat langsung
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

local function
