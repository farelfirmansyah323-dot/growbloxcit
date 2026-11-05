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
Nav = { clickOn = false, token = 0, conn = nil, last = "-" }
local Clear = { on = false, token = 0, status = "Mati", stats = { scanned = 0, broken = 0, picked = 0, skipped = 0, left = 0, pass = 0 } }
local BreakId = { on = false, token = 0, status = "Mati", stats = { found = 0, broken = 0, picked = 0, skipped = 0, left = 0 } }
local DirtFarm = { on = false, token = 0, status = "Mati", stats = { rows = 0, broken = 0, picked = 0, placed = 0, skipped = 0 } }
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
-- Rute dicari lewat tile yang bisa dilewati (BFS). Ada 2 cara bergerak:
--  * JALAN  : karakter digerakkan lewat analog/keyboard bawaan game (fisika asli)
--  * TELEPORT: pindah bertahap 3-5 block per lompatan + jeda kecil (tidak ditolak)
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
        -- Hazard (lava, spike, api) tidak dilewati / dijadikan tempat berdiri
        -- (God Mode mematikan flag ini, jadi otomatis boleh kalau God Mode aktif)
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

    Nav.Passable = Passable

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

    ------------------------------------------------------------------
    -- INPUT GERAK (analog / keyboard bawaan game)
    -- Game membaca arah dari MobileControls.dir() + tombol keyboard di
    -- RenderStepped, lalu menggerakkan karakter dengan fisika normal
    -- (kecepatan 7.2 tile/detik, lompat, tabrakan). Di sini kita menyuntik
    -- "analog" itu, jadi karakter BENAR-BENAR berjalan, bukan teleport.
    ------------------------------------------------------------------
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

    -- dir: -1 kiri, 0 diam, 1 kanan. jump: tahan lompat.
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

    -- JALAN ASLI: ikuti rute (BFS) memakai analog. Kecepatan = kecepatan jalan game,
    -- jadi tidak pernah ditolak anti-teleport. Return: ok, detik (atau alasan gagal)
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

                -- deteksi macet total
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
                    -- keluar jalur (jatuh / meleset): hitung rute ulang dari tile sekarang
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
                    -- sudah di tile tujuan tapi masih meluncur: rem
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
                -- rem sebelum tile tujuan akhir supaya tidak kebablasan
                if idx + 1 == #cur and dx ~= 0 then
                    local dist = (node.x + 0.5 - px) * dx
                    if dist < (vx * vx) / 80 + 0.1 then
                        inDir = 0
                    end
                end
                -- tersangkut di sisi block (naik 1 tile): lompat
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

    ------------------------------------------------------------------
    -- TELEPORT BERTAHAP: loncat 3-5 tile per langkah (bukan satu lompatan
    -- jauh) dengan jeda kecil, supaya tidak ditolak server / anti-teleport.
    ------------------------------------------------------------------
    local function HopRange()
        local lo = math.clamp(math.floor(tonumber(Config.hopMin) or 3), 1, 8)
        local hi = math.clamp(math.floor(tonumber(Config.hopMax) or 5), lo, 10)
        return lo, hi
    end

    local function HopWait()
        task.wait(math.clamp(tonumber(Config.hopDelay) or 0.12, 0.03, 1))
    end

    -- TERBANG: garis lurus tembus block, tapi tetap per 3-5 tile
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

    -- Teleport lewat rute kosong, per 3-5 tile. Kalau tidak ada rute -> Nav.Fly (juga bertahap)
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
                -- ditolak / terseret balik: perpendek lompatan lalu hitung rute dari posisi sekarang
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

    -- Dipakai mode teleport (Auto Clear / Break ID / Pos): bertahap, cadangan terbang
    function Nav.Tele(tx, ty, cancel)
        local ok, info = Nav.Hop(tx, ty, cancel)
        if ok or info == "cancel" then
            return ok, info
        end
        return Nav.Fly(tx, ty, cancel)
    end

    -- Pindah sesuai mode (Config.moveMode): walk / tp / fly / mix
    function Nav.Go(tx, ty, cancel)
        local mode = Config.moveMode
        if mode == "fly" then
            return Nav.Fly(tx, ty, cancel)
        elseif mode == "tp" then
            return Nav.Tele(tx, ty, cancel)
        elseif mode == "walk" then
            return Nav.Walk(tx, ty, cancel)
        end
        -- mix: jalan dulu; kalau tidak ada jalan, terbang (bertahap)
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
        -- Hanya mouse (PC). Sentuhan layar di HP tidak memicu Click TP
        -- supaya gerakan jari saat jalan tidak ikut memicu teleport.
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

----------------------------------------------------------------------
-- AUTO CLEAR WORLD
-- 1) GrowScan dulu (hitung isi world) -> 2) kumpulkan semua tile yang boleh
-- dipecah (lock, area & bedrock DILEWATI) -> 3) teleport ke dekat grup 4 tile
-- -> 4) pukul 4 tile SEKALIGUS dalam satu putaran -> 5) ambil item drop.
-- Delay teleport & delay break bisa diatur di tab Clear.
----------------------------------------------------------------------
do
    local function BatchSize()
        return math.clamp(math.floor(tonumber(Config.clearPunch) or 3), 1, 3)
    end

    local function IsStaff(world)
        local ok, staff = pcall(function()
            return world and world.areas and world.areas.staff
        end)
        return ok and staff and true or false
    end

    -- Jumlah pukulan yang dibutuhkan game untuk memecah item ini (nil = tidak bisa).
    -- Sama seperti fungsi hit milik game: hits <= 0 hanya bisa dipecah lewat staffHits
    -- (khusus staff). Blok seperti lava / rock yang punya staffHits sebelumnya selalu
    -- dilewati karena dianggap hits <= 0.
    local function HitsOf(world, item)
        if type(item) ~= "table" then
            return nil
        end
        if item.kind == "seed" then
            return 3
        end
        local h = item.hits
        if type(h) == "number" and h > 0 then
            return h
        end
        if type(item.staffHits) == "number" and item.staffHits > 0 and IsStaff(world) then
            return item.staffHits
        end
        return nil
    end

    -- Tile yang TIDAK boleh dipecah: lock, area, bedrock, tidak bisa dipukul, door utama
    local function Protected(db, id, world)
        local item = db and db[id]
        if type(item) ~= "table" then
            return true
        end
        if item.lock or item.area then
            return true
        end
        if type(item.hits) == "number" and item.hits <= 0 and not HitsOf(world or FindWorld(), item) then
            return true
        end
        local name = type(item.name) == "string" and item.name:lower() or ""
        if name:find("bedrock", 1, true) or name:find("main door", 1, true)
            or name:find("white door", 1, true) or name:find("world lock", 1, true) then
            return true
        end
        return false
    end

    -- Waktu maksimal menunggu 1 tile pecah (block keras seperti rock butuh lebih lama)
    local function HitTimeout(world, db, id)
        local need = HitsOf(world, db and db[id]) or 8
        return math.clamp(need * math.max(0.03, Config.clearBreakDelay) * 2.5 + 4, 8, 90)
    end

    local reported = {}
    local function ReportFail(db, id)
        if reported[id] then
            return
        end
        reported[id] = true
        local item = db and db[id]
        if type(item) ~= "table" then
            Notify("Gagal pecah ID " .. tostring(id))
            return
        end
        Notify(string.format("Gagal pecah %s (ID %s, hits=%s, staffHits=%s). hits <= 0 berarti hanya staff yang bisa memecahnya.",
            tostring(item.name), tostring(id), tostring(item.hits), tostring(item.staffHits)))
    end

    local function Alive(world, t)
        return TileValue(world, t.layer, t.x, t.y) == t.id
    end

    local function IsHazard(db, id)
        local item = db and db[id]
        return type(item) == "table" and (item.hurts or item.deadly) and true or false
    end

    -- Kumpulkan tile target (fg dulu; bg hanya kalau fg di atasnya sudah kosong)
    local function Collect(world, db, fails)
        local list = {}
        for y = 0, world.h - 1 do
            for x = 0, world.w - 1 do
                local f = TileValue(world, "fg", x, y)
                if f and f ~= 0 then
                    if not Protected(db, f, world) and (fails[x .. "," .. y .. ",fg"] or 0) < 3 then
                        table.insert(list, { x = x, y = y, id = f, layer = "fg" })
                    end
                else
                    local b = TileValue(world, "bg", x, y)
                    if b and b ~= 0 and not Protected(db, b, world) and (fails[x .. "," .. y .. ",bg"] or 0) < 3 then
                        table.insert(list, { x = x, y = y, id = b, layer = "bg" })
                    end
                end
            end
        end
        -- urutan ular (kiri->kanan lalu kanan->kiri) supaya teleport pendek
        table.sort(list, function(p, q)
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

    -- Bentuk grup maksimal 4 tile yang saling berdekatan
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
                    if not used[j] and math.abs(t.x - first.x) <= reach and math.abs(t.y - first.y) <= reach then
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
    -- owner = Clear / BreakId (pemilik token yang menghentikan loop).
    local function BreakGroup(world, hit, group, token, owner)
        owner = owner or Clear
        local db = GetItemDB()
        local started = os.clock()
        local limit = 8
        for _, t in ipairs(group) do
            limit = math.max(limit, HitTimeout(world, db, t.id))
        end
        local failed = {}
        while owner.token == token do
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
            if os.clock() - started > limit then
                for _, t in ipairs(group) do
                    if Alive(world, t) then
                        table.insert(failed, t)
                        ReportFail(db, t.id)
                    end
                end
                break
            end
            task.wait(math.max(0.03, Config.clearBreakDelay))
        end
        return failed
    end

    -- owner = Clear / BreakId, mover = fungsi pindah (default Nav.To; mode jalan pakai Nav.Walk)
    local function TakeDrops(world, before, token, home, owner, mover)
        owner = owner or Clear
        mover = mover or (Config.clearMode == "teleport" and Nav.Tele or Nav.To)
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
            if owner.token ~= token then
                break
            end
            if table.find(list, drop) then
                local reached = mover(math.floor(drop.x), math.floor(drop.y), function() return owner.token ~= token end)
                task.wait(math.max(0.03, Config.clearTpDelay))
                local waited = os.clock()
                while reached and owner.token == token and table.find(list, drop) and os.clock() - waited < 0.8 do
                    task.wait(0.05)
                end
                if not table.find(list, drop) then
                    picked += 1
                end
            end
        end
        if home then
            if not mover(home.x, home.y, function() return owner.token ~= token end) then
                Nav.Tele(home.x, home.y, function() return owner.token ~= token end)
            end
            task.wait(math.max(0.03, Config.clearTpDelay))
        end
        return picked
    end

    ------------------------------------------------------------------
    -- MODE TELEPORT: pindah ke grup block, pukul beberapa tile sekaligus
    ------------------------------------------------------------------
    local function TeleportClearLoop(token, home)
        local db = GetItemDB()
        local hit = FindGameFn("hit")
        local inv = FindInventory()
        if not db or not hit then
            Clear.status = "Fungsi game tidak ditemukan"
            return
        end

        table.clear(reported)
        local fails = {}
        local function Fail(t, n)
            local key = t.x .. "," .. t.y .. "," .. t.layer
            fails[key] = (fails[key] or 0) + (n or 1)
        end
        local lastLeft = nil
        for pass = 1, 10 do
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

            if lastLeft and #targets >= lastLeft and pass > 3 then
                -- tidak ada kemajuan, tandai sisa agar tidak berputar terus
                for _, t in ipairs(targets) do
                    Fail(t, 1)
                end
            end
            lastLeft = #targets

            local groups = MakeGroups(targets, math.max(1, math.floor(reach / 2)))
            for index, group in ipairs(groups) do
                if Clear.token ~= token then
                    return
                end
                local spot = StandingSpot(world, group, reach)
                if not spot then
                    -- belum ada tempat berdiri; dicoba lagi di pass berikutnya
                    for _, t in ipairs(group) do
                        Fail(t, 1)
                        Clear.stats.skipped += 1
                    end
                else
                    Clear.status = string.format("Break grup %d/%d (pass %d)", index, #groups, pass)
                    local px, py = GetTile()
                    local reachable = true
                    if px ~= spot.x or py ~= spot.y then
                        reachable = Nav.Tele(spot.x, spot.y, function() return Clear.token ~= token end)
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
                        Nav.Tele(spot.x, spot.y, function() return Clear.token ~= token end)
                        task.wait(math.max(0.05, Config.clearTpDelay))
                        reachable = InReach()
                    end
                    if not reachable then
                        for _, t in ipairs(group) do
                            Fail(t, 1)
                        end
                        Clear.stats.skipped += #group
                        Clear.status = "Posisi tidak tercapai, dicoba lagi di pass berikutnya"
                        continue
                    end
                    local before = DropSet(world)
                    local failedFg = BreakGroup(world, hit, group, token)

                    -- Dirt/block (fg) sudah pecah -> pecahkan juga background (cave) di tile yang sama
                    local follow = {}
                    for _, t in ipairs(group) do
                        if t.layer == "fg" and not table.find(failedFg, t) then
                            local b = TileValue(world, "bg", t.x, t.y)
                            if b and b ~= 0 and not Protected(db, b, world)
                                and (fails[t.x .. "," .. t.y .. ",bg"] or 0) < 3 then
                                table.insert(follow, { x = t.x, y = t.y, id = b, layer = "bg" })
                            end
                        end
                    end
                    local failedBg = {}
                    if #follow > 0 and Clear.token == token then
                        failedBg = BreakGroup(world, hit, follow, token)
                    end

                    for _, t in ipairs(failedFg) do
                        Fail(t, 1)
                        Clear.stats.skipped += 1
                    end
                    for _, t in ipairs(failedBg) do
                        Fail(t, 1)
                        Clear.stats.skipped += 1
                    end
                    local brokenNow = (#group - #failedFg) + (#follow - #failedBg)
                    Clear.stats.broken += brokenNow
                    Clear.stats.left = math.max(0, Clear.stats.left - #group + #failedFg)
                    if Config.clearTake and brokenNow > 0 then
                        task.wait(0.25) -- drop muncul sedikit setelah tile pecah
                        Clear.status = "Ambil item"
                        Clear.stats.picked += TakeDrops(world, before, token, nil)
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
            Nav.Tele(home.x, home.y, function() return Clear.token ~= token end)
        end
        Clear.status = "Selesai"
        Notify(string.format("Auto Clear selesai: %d pecah, %d diambil, %d dilewati.",
            Clear.stats.broken, Clear.stats.picked, Clear.stats.skipped))
    end

    ------------------------------------------------------------------
    -- MODE JALAN (jalan asli lewat analog, tanpa teleport)
    -- 1) Jalan dulu lewat tile kosong sampai ujung (BELUM break apa pun).
    -- 2) Turun: break tile di BAWAH player 1x saja.
    -- 3) Sapu baris: break N block (default 3) di DEPAN player sekaligus, jalan
    --    maju, ulangi sampai ujung baris. Tidak break ke bawah selama menyapu.
    -- 4) Turun 1x lagi, sapu ke arah sebaliknya, dan seterusnya sampai habis.
    -- 5) Sisa block yang terlewat dibersihkan satu per satu di akhir.
    -- Lava/spike tidak pernah dilewati atau dijadikan tempat berdiri.
    ------------------------------------------------------------------
    local NEIGH = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

    local function WalkClearLoop(token, home)
        local db = GetItemDB()
        local hit = FindGameFn("hit")
        local inv = FindInventory()
        if not db or not hit or not inv then
            Clear.status = "Fungsi game tidak ditemukan"
            return
        end
        local Passable = Nav.Passable
        if not Passable then
            Clear.status = "Fungsi path tidak ditemukan"
            return
        end
        if not Nav.InputReady() then
            Clear.status = "Kontrol jalan game tidak ditemukan"
            Notify("Mode jalan butuh kontrol analog game (getgc). Pakai mode Teleport.")
            return
        end
        local world = FindWorld()
        if not world or type(rawget(world, "w")) ~= "number" or CurrentWorldName() ~= home.world then
            Clear.status = "World tidak ditemukan"
            return
        end
        local W, H = world.w, world.h

        table.clear(reported)
        local function Cancelled()
            return Clear.token ~= token
        end
        local fails = {}
        local function Fail(t, n)
            local key = t.x .. "," .. t.y .. "," .. t.layer
            fails[key] = (fails[key] or 0) + (n or 1)
        end
        local function Walker(x, y, cancel)
            local ok = Nav.Walk(x, y, cancel)
            return ok
        end
        local function Batch()
            return math.clamp(math.floor(tonumber(Config.clearPunch) or 3), 1, 3)
        end

        -- tile yang boleh dipecah sekarang (fg dulu; bg/cave hanya kalau fg sudah kosong)
        local function TargetAt(x, y)
            if not InBounds(world, x, y) then
                return nil
            end
            local f = TileValue(world, "fg", x, y)
            if f and f ~= 0 then
                if Protected(db, f, world) or (fails[x .. "," .. y .. ",fg"] or 0) >= 3 then
                    return nil
                end
                return { x = x, y = y, id = f, layer = "fg" }
            end
            local b = TileValue(world, "bg", x, y)
            if b and b ~= 0 and not Protected(db, b, world) and (fails[x .. "," .. y .. ",bg"] or 0) < 3 then
                return { x = x, y = y, id = b, layer = "bg" }
            end
            return nil
        end

        -- Aman kalau jatuh dari (x, y0) ke bawah? (tidak jatuh ke lava/spike)
        local function LandingSafe(x, y0)
            for y = math.max(0, y0), H - 1 do
                local f = TileValue(world, "fg", x, y)
                if f and f ~= 0 then
                    if IsHazard(db, f) then
                        return false
                    end
                    local item = db[f]
                    if type(item) == "table" and item.solid then
                        return true
                    end
                end
            end
            return false
        end

        -- tile ada dalam jangkauan pukul dari posisi player sekarang?
        local function InRange(tx, ty)
            local x, y = GetGridState()
            if not x then
                return false
            end
            local okR, r = pcall(function() return inv.buildRange() end)
            r = (okR and type(r) == "number") and r or 2.5
            return math.abs(tx + 0.5 - x) <= r - 0.05 and math.abs(ty + 0.5 - (y - 0.475)) <= r - 0.05
        end

        local sinceDrop = 0

        -- pukul beberapa tile SEKALIGUS (satu putaran = 1 pukulan per tile) sampai semuanya hilang
        local function HitTiles(tiles)
            local started = os.clock()
            local limit = 8
            for _, t in ipairs(tiles) do
                limit = math.max(limit, HitTimeout(world, db, t.id))
            end
            local failed = {}
            while not Cancelled() do
                local any = false
                for _, t in ipairs(tiles) do
                    if Alive(world, t) then
                        any = true
                        pcall(hit, t.x, t.y, true)
                    end
                end
                if not any then
                    break
                end
                if os.clock() - started > limit then
                    for _, t in ipairs(tiles) do
                        if Alive(world, t) then
                            table.insert(failed, t)
                        end
                    end
                    break
                end
                task.wait(math.max(0.03, Config.clearBreakDelay))
            end
            for _, t in ipairs(failed) do
                Fail(t, 1)
                Clear.stats.skipped += 1
                ReportFail(db, t.id)
            end
            local okN = #tiles - #failed
            if not Cancelled() then
                Clear.stats.broken += okN
                Clear.stats.left = math.max(0, Clear.stats.left - okN)
                sinceDrop += okN
            end
            return okN
        end

        -- tunggu sampai posisi player stabil (setelah block bawah pecah player jatuh)
        local function SettledTile()
            local lx, ly = GetTile()
            for _ = 1, 16 do
                task.wait(0.05)
                local cx, cy = GetTile()
                if cx == lx and cy == ly then
                    return cx, cy
                end
                lx, ly = cx, cy
            end
            return lx, ly
        end

        -- Maju ke arah d (1 = kanan, -1 = kiri) sampai ujung: pukul N block di depan
        -- sekaligus, lalu jalan maju. TIDAK memecah ke bawah selama menyusuri baris.
        local function SweepRow(d)
            local walkFails = 0
            for _ = 1, 6000 do
                if Cancelled() then
                    return
                end
                local fx, fy = GetGridState()
                if not fx then
                    return
                end
                local px, py = math.floor(fx), math.floor(fy - 0.475)
                local n = Batch()

                local targets = {}
                local own = TargetAt(px, py) -- background tile tempat berdiri
                if own and InRange(px, py) then
                    table.insert(targets, own)
                end
                for k = 1, n do
                    local tx = px + d * k
                    local t = TargetAt(tx, py)
                    if t then
                        if not InRange(tx, py) then
                            break
                        end
                        table.insert(targets, t)
                    elseif not InBounds(world, tx, py) or not Passable(db, world, tx, py) then
                        break
                    end
                end

                if #targets > 0 then
                    Clear.status = string.format("Break %d block depan (%d,%d)", #targets, px + d, py)
                    HitTiles(targets)
                else
                    -- tidak ada yang perlu dipecah di N tile depan: maju lewat tile kosong
                    local run = 0
                    for k = 1, n do
                        local tx = px + d * k
                        if InBounds(world, tx, py) and not TargetAt(tx, py)
                            and Passable(db, world, tx, py) and LandingSafe(tx, py + 1) then
                            run = k
                        else
                            break
                        end
                    end
                    if run == 0 then
                        return -- ujung baris (block lock/bedrock/lava/tepi world)
                    end
                    Clear.status = string.format("Jalan maju %d tile", run)
                    local ok = Walker(px + d * run, py, Cancelled)
                    if Cancelled() then
                        return
                    end
                    if not ok then
                        local _, ny = GetTile()
                        if ny == py then
                            walkFails += 1
                            if walkFails >= 3 then
                                return
                            end
                        end
                    end
                    task.wait(0.03)
                end
            end
        end

        -- Pecah tile di bawah player SATU kali (fg lalu bg), tunggu player jatuh/menetap.
        -- Return false kalau tidak bisa turun lagi.
        local function DownOnce()
            local px, py = GetTile()
            if not px then
                return false
            end
            for _ = 1, 3 do
                local t = TargetAt(px, py + 1)
                if not t then
                    break
                end
                if t.layer == "fg" and not LandingSafe(px, py + 2) then
                    return false -- di bawahnya lava/spike
                end
                Clear.status = string.format("Break bawah (%d,%d)", px, py + 1)
                if HitTiles({ t }) < 1 then
                    return false
                end
                local nx, ny = SettledTile()
                if nx ~= px or ny ~= py then
                    return ny > py
                end
            end
            local nx, ny = SettledTile()
            if ny and ny > py then
                return true
            end
            return false
        end

        -- GrowScan
        Clear.status = "GrowScan world..."
        local scan = ScanWorld()
        local fgTotal, bgTotal = 0, 0
        if scan then
            for _, n in pairs(scan.fg) do fgTotal += n end
            for _, n in pairs(scan.bg) do bgTotal += n end
        end

        local px, py = GetTile()
        local _, _, facing = GetGridState()
        if not px then
            Clear.status = "Posisi tidak terdeteksi"
            return
        end

        -- jumlah target (untuk status)
        local total = 0
        for y = 0, H - 1 do
            for x = 0, W - 1 do
                if TargetAt(x, y) then
                    total += 1
                end
            end
            if y % 20 == 0 then
                task.wait()
            end
        end
        Clear.stats.scanned = total
        Clear.stats.left = total
        Notify(string.format("GrowScan: %d fg, %d bg. Mode jalan: %d tile dipecah (turun 1x, sapu baris sampai ujung, ulangi).",
            fgTotal, bgTotal, total))

        -- FASE 1: jalan (analog) dulu sampai ujung, belum ada yang dipecahkan
        local function RunLen(d)
            local n = 0
            while Passable(db, world, px + d * (n + 1), py) do
                n += 1
            end
            return n
        end
        local walkDir = facing or 1
        if RunLen(walkDir) == 0 and RunLen(-walkDir) > 0 then
            walkDir = -walkDir
        end
        local Ex = px + walkDir * RunLen(walkDir)
        if Ex ~= px then
            Clear.status = "Jalan ke ujung..."
            Walker(Ex, py, Cancelled)
            if Cancelled() then
                return
            end
            task.wait(0.1)
            local ax = GetTile()
            Ex = ax or Ex
        end
        local startDrops = DropSet(world)

        -- FASE 2: turun 1x -> sapu baris ke depan sampai ujung -> turun 1x -> sapu arah sebaliknya -> ...
        local dir = -walkDir
        for row = 1, H + 5 do
            if Cancelled() then
                return
            end
            if CurrentWorldName() ~= home.world then
                Clear.status = "World berubah, berhenti"
                Notify("Auto Clear berhenti: kamu pindah world.")
                return
            end
            Clear.stats.pass = row
            if not DownOnce() then
                break
            end
            if Cancelled() then
                return
            end
            SweepRow(dir)
            dir = -dir
            if Config.clearTake and sinceDrop >= 12 then
                Clear.status = "Ambil item"
                Clear.stats.picked += TakeDrops(world, startDrops, token, nil, Clear, Walker)
                sinceDrop = 0
            end
        end

        -- FASE 3: sisa block yang terlewat (mis. di belakang block lock) dibersihkan satu per satu
        local list = {}
        for y = 0, H - 1 do
            for x = 0, W - 1 do
                if TargetAt(x, y) then
                    local o = (Ex - x) * walkDir
                    local g = o // 3
                    table.insert(list, { x = x, y = y, g = g, cx = Ex - walkDir * (3 * g + 1) })
                end
            end
            if y % 20 == 0 then
                task.wait()
            end
        end
        table.sort(list, function(p, q)
            if p.g ~= q.g then
                return p.g < q.g
            end
            if p.y ~= q.y then
                return p.y < q.y
            end
            return math.abs(p.x - p.cx) < math.abs(q.x - q.cx)
        end)
        if #list > 0 then
            Clear.status = string.format("Sapu sisa %d tile", #list)
        end

        local function Reach(sx, sy)
            local seen = { [sy * W + sx] = true }
            local queue, head = { sy * W + sx }, 1
            while head <= #queue do
                local key = queue[head]
                head += 1
                local x, y = key % W, key // W
                for _, d in ipairs(NEIGH) do
                    local nx, ny = x + d[1], y + d[2]
                    if InBounds(world, nx, ny) then
                        local nk = ny * W + nx
                        if not seen[nk] and Passable(db, world, nx, ny) then
                            seen[nk] = true
                            table.insert(queue, nk)
                        end
                    end
                end
                if head % 2000 == 0 then
                    task.wait()
                end
            end
            return seen
        end

        local cursor = 1
        local function NextStand(seen)
            while cursor <= #list and not TargetAt(list[cursor].x, list[cursor].y) do
                cursor += 1
            end
            for i = cursor, #list do
                local e = list[i]
                local t = TargetAt(e.x, e.y)
                if t then
                    local stands = { { e.x, e.y - 1 }, { e.x - 1, e.y }, { e.x + 1, e.y }, { e.x, e.y + 1 } }
                    local best, bestScore
                    for rank, s in ipairs(stands) do
                        if InBounds(world, s[1], s[2]) and seen[s[2] * W + s[1]]
                            and LandingSafe(s[1], s[2] + 1) then
                            local score = math.abs(s[1] - e.cx) * 10 + rank
                            if not bestScore or score < bestScore then
                                best, bestScore = s, score
                            end
                        end
                    end
                    if best then
                        return best, t
                    end
                end
            end
            return nil, nil
        end

        local lastKey, repeats = nil, 0
        for step = 1, 100000 do
            if Cancelled() then
                return
            end
            if #list == 0 then
                break
            end
            if CurrentWorldName() ~= home.world then
                Clear.status = "World berubah, berhenti"
                Notify("Auto Clear berhenti: kamu pindah world.")
                return
            end
            Clear.stats.pass = H + step

            local cx, cy = GetTile()
            if not cx then
                break
            end
            Clear.status = "Cari posisi berikutnya..."
            local stand, tile = NextStand(Reach(cx, cy))
            if not stand then
                break
            end
            local key = tile.x .. "," .. tile.y
            if key == lastKey then
                repeats += 1
            else
                lastKey, repeats = key, 0
            end
            if repeats >= 4 then
                Fail(tile, 3)
                Clear.stats.skipped += 1
                ReportFail(db, tile.id)
            else
                if cx ~= stand[1] or cy ~= stand[2] then
                    Clear.status = string.format("Jalan ke (%d,%d)", stand[1], stand[2])
                    Walker(stand[1], stand[2], Cancelled)
                    if Cancelled() then
                        return
                    end
                    task.wait(0.08)
                end
                -- pukul tile target + tile lain di sekitarnya (maks N) sekaligus
                local batch, seenKey = {}, {}
                local function Add(t)
                    local k2 = t.x .. "," .. t.y .. "," .. t.layer
                    if t and not seenKey[k2] and #batch < Batch() and InRange(t.x, t.y) then
                        seenKey[k2] = true
                        table.insert(batch, t)
                    end
                end
                local t0 = TargetAt(tile.x, tile.y)
                if t0 then
                    Add(t0)
                end
                for i = cursor, math.min(#list, cursor + 400) do
                    if #batch >= Batch() then
                        break
                    end
                    local t = TargetAt(list[i].x, list[i].y)
                    if t then
                        Add(t)
                    end
                end
                if #batch > 0 then
                    Clear.status = string.format("Break %d block sisa", #batch)
                    HitTiles(batch)
                end
                SettledTile()
            end

            if Config.clearTake and sinceDrop >= 12 then
                Clear.status = "Ambil item"
                Clear.stats.picked += TakeDrops(world, startDrops, token, nil, Clear, Walker)
                sinceDrop = 0
            end
        end

        if Config.clearTake and Clear.token == token then
            Clear.status = "Ambil sisa item"
            local w2 = FindWorld()
            if w2 then
                Clear.stats.picked += TakeDrops(w2, startDrops, token, home, Clear, Walker)
            end
        end
        Nav.SetInput(0, false)
        Clear.status = "Selesai"
        Notify(string.format("Auto Clear selesai: %d pecah, %d diambil, %d dilewati.",
            Clear.stats.broken, Clear.stats.picked, Clear.stats.skipped))
    end

    -- Pilih mode sesuai pengaturan (default: jalan)
    local function ClearLoop(token, home)
        if Config.clearMode == "teleport" then
            return TeleportClearLoop(token, home)
        end
        return WalkClearLoop(token, home)
    end

    -- Ambil daftar ID dari teks ("4, 112  8" -> {4, 112, 8})
    local function ParseIds(text)
        local ids, seen = {}, {}
        for num in tostring(text or ""):gmatch("%d+") do
            local id = tonumber(num)
            if id and not seen[id] then
                seen[id] = true
                table.insert(ids, id)
            end
        end
        return ids
    end
    BreakId.ParseIds = ParseIds

    -- Kumpulkan tile yang ID-nya cocok dengan daftar, DAN lolos Protected
    -- (lock/area/bedrock tetap dilewati, sama seperti Auto Clear biasa, supaya
    -- hanya block yang benar-benar boleh kita pecah yang disentuh).
    local function CollectById(world, db, idSet, fails)
        local list = {}
        for y = 0, world.h - 1 do
            for x = 0, world.w - 1 do
                local f = TileValue(world, "fg", x, y)
                if f and f ~= 0 and idSet[f] and not Protected(db, f)
                    and (fails[x .. "," .. y .. ",fg"] or 0) < 3 then
                    table.insert(list, { x = x, y = y, id = f, layer = "fg" })
                end
                local b = TileValue(world, "bg", x, y)
                if b and b ~= 0 and idSet[b] and not Protected(db, b)
                    and (fails[x .. "," .. y .. ",bg"] or 0) < 3 then
                    table.insert(list, { x = x, y = y, id = b, layer = "bg" })
                end
            end
        end
        table.sort(list, function(p, q)
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

    local function BreakIdLoop(token, home, ids, names)
        local db = GetItemDB()
        local hit = FindGameFn("hit")
        local inv = FindInventory()
        if not db or not hit then
            BreakId.status = "Fungsi game tidak ditemukan"
            return
        end

        local idSet = {}
        for _, id in ipairs(ids) do
            idSet[id] = true
        end

        local fails = {}
        local function Fail(t, n)
            local key = t.x .. "," .. t.y .. "," .. t.layer
            fails[key] = (fails[key] or 0) + (n or 1)
        end

        BreakId.status = "Scan world untuk ID: " .. table.concat(names, ", ")
        local lastLeft = nil
        for pass = 1, 10 do
            if BreakId.token ~= token then
                return
            end
            local world = FindWorld()
            if not world or CurrentWorldName() ~= home.world then
                BreakId.status = "World berubah, berhenti"
                Notify("Auto Break ID berhenti: kamu pindah world.")
                return
            end

            local targets = CollectById(world, db, idSet, fails)
            BreakId.stats.left = #targets
            if pass == 1 then
                BreakId.stats.found = #targets
                if #targets == 0 then
                    Notify("Tidak ada block dengan ID " .. table.concat(names, ", ") .. " di world ini (atau tertutup lock/area).")
                else
                    Notify(string.format("Ditemukan %d block ID %s. Mulai break.", #targets, table.concat(names, ", ")))
                end
            end
            if #targets == 0 then
                break
            end

            local okRange, range = pcall(function() return inv.buildRange() end)
            local reach = 2
            if okRange and type(range) == "number" then
                reach = math.max(1, math.floor(range - 0.05))
            end
            reach = math.min(reach, 6)

            if lastLeft and #targets >= lastLeft and pass > 3 then
                for _, t in ipairs(targets) do
                    Fail(t, 1)
                end
            end
            lastLeft = #targets

            local groups = MakeGroups(targets, math.max(1, math.floor(reach / 2)))
            for index, group in ipairs(groups) do
                if BreakId.token ~= token then
                    return
                end
                local spot = StandingSpot(world, group, reach)
                if not spot then
                    for _, t in ipairs(group) do
                        Fail(t, 1)
                        BreakId.stats.skipped += 1
                    end
                else
                    BreakId.status = string.format("Break grup %d/%d (pass %d)", index, #groups, pass)
                    local px, py = GetTile()
                    local reachable = true
                    if px ~= spot.x or py ~= spot.y then
                        reachable = Nav.Tele(spot.x, spot.y, function() return BreakId.token ~= token end)
                        task.wait(math.max(0.03, Config.clearTpDelay))
                    end
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
                        Nav.Tele(spot.x, spot.y, function() return BreakId.token ~= token end)
                        task.wait(math.max(0.05, Config.clearTpDelay))
                        reachable = InReach()
                    end
                    if not reachable then
                        for _, t in ipairs(group) do
                            Fail(t, 1)
                        end
                        BreakId.stats.skipped += #group
                        BreakId.status = "Posisi tidak tercapai (mungkin area/lock orang lain), dicoba lagi"
                        continue
                    end
                    local before = DropSet(world)
                    local failed = BreakGroup(world, hit, group, token, BreakId)
                    for _, t in ipairs(failed) do
                        Fail(t, 1)
                        BreakId.stats.skipped += 1
                    end
                    BreakId.stats.broken += #group - #failed
                    if Config.clearTake and #group - #failed > 0 then
                        task.wait(0.25)
                        BreakId.status = "Ambil item"
                        BreakId.stats.picked += TakeDrops(world, before, token, nil, BreakId)
                    end
                end
            end
        end

        if Config.clearTake and BreakId.token == token then
            BreakId.status = "Ambil sisa item"
            local world = FindWorld()
            if world then
                BreakId.stats.picked += TakeDrops(world, nil, token, home, BreakId)
            end
        end
        local world = FindWorld()
        if world and BreakId.token == token then
            Nav.Tele(home.x, home.y, function() return BreakId.token ~= token end)
        end
        BreakId.status = "Selesai"
        Notify(string.format("Auto Break ID selesai: %d pecah, %d diambil, %d dilewati.",
            BreakId.stats.broken, BreakId.stats.picked, BreakId.stats.skipped))
    end

    function BreakId.Stop()
        if not BreakId.on then
            return false
        end
        BreakId.token += 1
        BreakId.on = false
        BreakId.status = "Mati"
        return true
    end

    function BreakId.Start(text)
        if BreakId.on then
            return true
        end
        local ids = ParseIds(text or Config.breakIdText)
        if #ids == 0 then
            Notify("Isi dulu ID block. Contoh: " .. Config.prefix .. "breakid 4,112")
            return false
        end
        local db = GetItemDB()
        local names = {}
        for _, id in ipairs(ids) do
            local item = db and db[id]
            table.insert(names, item and item.name and (item.name .. " (" .. id .. ")") or ("ID " .. id))
        end
        if not (FindGameFn("hit") and db) then
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
        Config.breakIdText = table.concat(ids, ",")
        SaveConfig()

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
        BreakId.token += 1
        local token = BreakId.token
        BreakId.on = true
        BreakId.status = "Mulai"
        BreakId.stats = { found = 0, broken = 0, picked = 0, skipped = 0, left = 0 }
        task.spawn(function()
            local ok, err = pcall(BreakIdLoop, token, home, ids, names)
            if not ok then
                warn(err)
                Notify("Auto Break ID error: " .. tostring(err))
            end
            if BreakId.token == token then
                BreakId.on = false
                if BreakId.status ~= "Selesai" then
                    BreakId.status = "Mati"
                end
                if RefreshHub then
                    RefreshHub()
                end
            end
        end)
        return true
    end

    ------------------------------------------------------------------
    -- AUTO DIRT FARM
    -- FASE 1 (DIG)  : jalan ke ujung -> break bawah 2x -> sapu baris ke depan sampai
    --                 ujung (block + background cave ikut hancur) -> di ujung break
    --                 ATAS dulu -> break bawah 2x lagi -> sapu arah sebaliknya ...
    --                 sampai paling bawah.
    -- FASE 2        : respawn.
    -- FASE 3 (PLACE): dari baris paling bawah: berdiri di bagian lantai yang AMAN
    --                 (ujung yang sudah di-break dilewati supaya tidak jatuh), place
    --                 dirt DI ATAS player sepanjang baris, teleport naik ke baris yang
    --                 baru di-place, ulangi sampai paling atas.
    ------------------------------------------------------------------
    local function DirtId()
        local id = math.floor(tonumber(Config.dirtId) or 0)
        if id > 0 then
            return id
        end
        for _, entry in ipairs(SearchItems("dirt", 40)) do
            if entry.lower == "dirt" then
                return entry.id
            end
        end
        return nil
    end
    DirtFarm.ResolveId = DirtId

    local function DirtFarmLoop(token, home)
        local DF = DirtFarm
        local db = GetItemDB()
        local hit = FindGameFn("hit")
        local inv = FindInventory()
        if not db or not hit or not inv then
            DF.status = "Fungsi game tidak ditemukan"
            return
        end
        local Passable = Nav.Passable
        if not Passable then
            DF.status = "Fungsi path tidak ditemukan"
            return
        end
        if not Nav.InputReady() then
            DF.status = "Kontrol jalan game tidak ditemukan"
            Notify("Auto Dirt Farm butuh kontrol analog game (getgc).")
            return
        end
        local world = FindWorld()
        if not world or type(rawget(world, "w")) ~= "number" or CurrentWorldName() ~= home.world then
            DF.status = "World tidak ditemukan"
            return
        end
        local W, H = world.w, world.h
        local dirt = DirtId()
        if Config.dirtPlace and not dirt then
            DF.status = "ID dirt tidak ditemukan"
            Notify("ID block dirt tidak ketemu. Isi manual: " .. Config.prefix .. "dirtid <id>")
            return
        end

        table.clear(reported)
        local function Cancelled()
            return DF.token ~= token
        end
        local fails = {}
        local function Fail(t, n)
            local key = t.x .. "," .. t.y .. "," .. t.layer
            fails[key] = (fails[key] or 0) + (n or 1)
        end
        local function Walker(x, y, cancel)
            local ok = Nav.Walk(x, y, cancel)
            return ok
        end

        -- tile yang boleh dipecah (fg dulu; bg/cave hanya kalau fg sudah kosong)
        local function TargetAt(x, y)
            if not InBounds(world, x, y) then
                return nil
            end
            local f = TileValue(world, "fg", x, y)
            if f and f ~= 0 then
                if Protected(db, f, world) or (fails[x .. "," .. y .. ",fg"] or 0) >= 3 then
                    return nil
                end
                return { x = x, y = y, id = f, layer = "fg" }
            end
            local b = TileValue(world, "bg", x, y)
            if b and b ~= 0 and not Protected(db, b, world) and (fails[x .. "," .. y .. ",bg"] or 0) < 3 then
                return { x = x, y = y, id = b, layer = "bg" }
            end
            return nil
        end

        -- Aman kalau jatuh dari (x, y0) ke bawah? (tidak jatuh ke lava/spike)
        local function LandingSafe(x, y0)
            for y = math.max(0, y0), H - 1 do
                local f = TileValue(world, "fg", x, y)
                if f and f ~= 0 then
                    if IsHazard(db, f) then
                        return false
                    end
                    local item = db[f]
                    if type(item) == "table" and item.solid then
                        return true
                    end
                end
            end
            return false
        end

        local function InRange(tx, ty)
            local x, y = GetGridState()
            if not x then
                return false
            end
            local okR, r = pcall(function() return inv.buildRange() end)
            r = (okR and type(r) == "number") and r or 2.5
            return math.abs(tx + 0.5 - x) <= r - 0.05 and math.abs(ty + 0.5 - (y - 0.475)) <= r - 0.05
        end

        local sinceDrop = 0

        -- pukul beberapa tile sekaligus (1 pukulan per tile per putaran) sampai hilang
        local function HitTiles(tiles)
            local started = os.clock()
            local limit = 8
            for _, t in ipairs(tiles) do
                limit = math.max(limit, HitTimeout(world, db, t.id))
            end
            local failed = {}
            while not Cancelled() do
                local any = false
                for _, t in ipairs(tiles) do
                    if Alive(world, t) then
                        any = true
                        pcall(hit, t.x, t.y, true)
                    end
                end
                if not any then
                    break
                end
                if os.clock() - started > limit then
                    for _, t in ipairs(tiles) do
                        if Alive(world, t) then
                            table.insert(failed, t)
                        end
                    end
                    break
                end
                task.wait(math.max(0.03, Config.clearBreakDelay))
            end
            for _, t in ipairs(failed) do
                Fail(t, 1)
                DF.stats.skipped += 1
                ReportFail(db, t.id)
            end
            local okN = #tiles - #failed
            if not Cancelled() then
                DF.stats.broken += okN
                sinceDrop += okN
            end
            return okN
        end

        local function SettledTile()
            local lx, ly = GetTile()
            for _ = 1, 16 do
                task.wait(0.05)
                local cx, cy = GetTile()
                if cx == lx and cy == ly then
                    return cx, cy
                end
                lx, ly = cx, cy
            end
            return lx, ly
        end

        -- Maju ke arah d sampai ujung: pukul N block di depan (fg lalu background cave)
        -- sekaligus, lalu jalan maju. Tidak memecah ke bawah selama menyusuri baris.
        local function SweepRow(d)
            local walkFails = 0
            for _ = 1, 6000 do
                if Cancelled() then
                    return
                end
                local fx, fy = GetGridState()
                if not fx then
                    return
                end
                local px, py = math.floor(fx), math.floor(fy - 0.475)
                local n = BatchSize()

                local targets = {}
                local own = TargetAt(px, py) -- background tile tempat berdiri
                if own and InRange(px, py) then
                    table.insert(targets, own)
                end
                for k = 1, n do
                    local tx = px + d * k
                    local t = TargetAt(tx, py)
                    if t then
                        if not InRange(tx, py) then
                            break
                        end
                        table.insert(targets, t)
                    elseif not InBounds(world, tx, py) or not Passable(db, world, tx, py) then
                        break
                    end
                end

                if #targets > 0 then
                    DF.status = string.format("Break %d block depan (%d,%d)", #targets, px + d, py)
                    HitTiles(targets)
                else
                    local run = 0
                    for k = 1, n do
                        local tx = px + d * k
                        if InBounds(world, tx, py) and not TargetAt(tx, py)
                            and Passable(db, world, tx, py) and LandingSafe(tx, py + 1) then
                            run = k
                        else
                            break
                        end
                    end
                    if run == 0 then
                        return -- ujung baris
                    end
                    DF.status = string.format("Jalan maju %d tile", run)
                    local ok = Walker(px + d * run, py, Cancelled)
                    if Cancelled() then
                        return
                    end
                    if not ok then
                        local _, ny = GetTile()
                        if ny == py then
                            walkFails += 1
                            if walkFails >= 3 then
                                return
                            end
                        end
                    end
                    task.wait(0.03)
                end
            end
        end

        -- Pecah tile di bawah player SATU kali (fg lalu bg), tunggu player jatuh/menetap.
        local function DownOnce()
            local px, py = GetTile()
            if not px then
                return false
            end
            for _ = 1, 3 do
                local t = TargetAt(px, py + 1)
                if not t then
                    break
                end
                if t.layer == "fg" and not LandingSafe(px, py + 2) then
                    return false -- di bawahnya lava/spike
                end
                DF.status = string.format("Break bawah (%d,%d)", px, py + 1)
                if HitTiles({ t }) < 1 then
                    return false
                end
                local nx, ny = SettledTile()
                if nx ~= px or ny ~= py then
                    return ny > py
                end
            end
            local _, ny = SettledTile()
            if ny and ny > py then
                return true
            end
            return false
        end

        -- Pecah tile di atas player (fg lalu background)
        local function BreakAbove()
            local px, py = GetTile()
            if not px then
                return
            end
            for _ = 1, 3 do
                if Cancelled() then
                    return
                end
                local t = TargetAt(px, py - 1)
                if not t or not InRange(px, py - 1) then
                    return
                end
                DF.status = string.format("Break atas (%d,%d)", px, py - 1)
                if HitTiles({ t }) < 1 then
                    return
                end
            end
        end

        ------------------------------------------------------------------
        -- FASE 1: DIG
        ------------------------------------------------------------------
        DF.status = "Jalan ke ujung..."
        local px, py = GetTile()
        local _, _, facing = GetGridState()
        if not px then
            DF.status = "Posisi tidak terdeteksi"
            return
        end
        local startRow = py
        local startDrops = DropSet(world)

        local function RunLen(d)
            local n = 0
            while Passable(db, world, px + d * (n + 1), py) and LandingSafe(px + d * (n + 1), py + 1) do
                n += 1
            end
            return n
        end
        local walkDir = facing or 1
        if RunLen(walkDir) == 0 and RunLen(-walkDir) > 0 then
            walkDir = -walkDir
        end
        local Ex = px + walkDir * RunLen(walkDir)
        if Ex ~= px then
            Walker(Ex, py, Cancelled)
            if Cancelled() then
                return
            end
            task.wait(0.1)
        end

        local rows = {} -- baris terowongan yang disapu (atas -> bawah)
        local dir = -walkDir
        for _ = 1, H + 5 do
            if Cancelled() then
                return
            end
            if CurrentWorldName() ~= home.world then
                DF.status = "World berubah, berhenti"
                Notify("Auto Dirt Farm berhenti: kamu pindah world.")
                return
            end

            -- break ke bawah 2x
            local moved = 0
            for _ = 1, 2 do
                if Cancelled() then
                    return
                end
                if not DownOnce() then
                    break
                end
                moved += 1
            end
            if moved == 0 then
                break -- sudah paling bawah
            end

            local _, ry = GetTile()
            table.insert(rows, ry)
            DF.stats.rows = #rows

            -- break depan sampai ujung (background cave ikut)
            SweepRow(dir)
            if Cancelled() then
                return
            end

            -- ambil drop baris ini, lalu balik ke ujung
            if Config.clearTake and sinceDrop >= 8 then
                DF.status = "Ambil item"
                local ex, ey = GetTile()
                if ex then
                    DF.stats.picked += TakeDrops(world, startDrops, token, { x = ex, y = ey }, DF, Walker)
                end
                sinceDrop = 0
                if Cancelled() then
                    return
                end
            end

            if moved < 2 then
                break -- tidak bisa turun 2x lagi = paling bawah
            end

            -- di ujung: break ATAS dulu, baru turun lagi
            BreakAbove()
            dir = -dir
        end

        if Config.clearTake and not Cancelled() then
            DF.status = "Ambil sisa item"
            local w2 = FindWorld()
            if w2 then
                DF.stats.picked += TakeDrops(w2, startDrops, token, nil, DF, Walker)
            end
        end
        if Cancelled() then
            return
        end

        ------------------------------------------------------------------
        -- FASE 2: RESPAWN
        ------------------------------------------------------------------
        DF.status = "Respawn"
        Nav.SetInput(0, false)
        do
            local bx, by = GetTile()
            local die = FindGameFn("die")
            if die then
                pcall(die)
                local started = os.clock()
                while not Cancelled() and os.clock() - started < 7 do
                    task.wait(0.25)
                    local cx, cy = GetTile()
                    if cx and (cx ~= bx or cy ~= by) then
                        break
                    end
                end
                task.wait(0.6)
            end
            local cx, cy = GetTile()
            if cx == bx and cy == by then
                -- cadangan: teleport bertahap ke titik spawn world
                local okS, sp = pcall(function() return world.spawn end)
                if okS and typeof(sp) == "Vector2" then
                    Nav.Tele(math.floor(sp.X), math.floor(sp.Y), Cancelled)
                end
            end
        end
        if Cancelled() then
            return
        end

        ------------------------------------------------------------------
        -- FASE 3: PLACE dirt dari bawah ke atas
        ------------------------------------------------------------------
        if Config.dirtPlace and #rows > 0 then
            local tunnel = {}
            for _, r in ipairs(rows) do
                tunnel[r] = true
            end

            local function Solid(x, y)
                if not InBounds(world, x, y) then
                    return false
                end
                local id = TileValue(world, "fg", x, y)
                if not id or id == 0 then
                    return false
                end
                local item = db[id]
                return type(item) == "table" and item.solid and not (item.hurts or item.deadly) and true or false
            end
            -- tempat berdiri aman = kosong + lantai solid di bawahnya
            -- (kolom ujung yang sudah di-break tidak punya lantai -> otomatis dilewati)
            local function StandSafe(x, y)
                return InBounds(world, x, y) and Passable(db, world, x, y) and Solid(x, y + 1)
            end
            local function NearestStand(x, y)
                for d = 0, W do
                    if StandSafe(x - d, y) then
                        return x - d
                    end
                    if StandSafe(x + d, y) then
                        return x + d
                    end
                end
                return nil
            end
            local function Segment(x, y)
                local l, r = x, x
                while StandSafe(l - 1, y) do
                    l -= 1
                end
                while StandSafe(r + 1, y) do
                    r += 1
                end
                return l, r
            end

            local outOfDirt = false
            local function PlaceAbove(x, y)
                local okR, range = pcall(function() return inv.buildRange() end)
                local reach = math.clamp(math.floor(((okR and type(range) == "number") and range or 2.5) - 0.05), 1, 6)
                local _, _, face = GetGridState()
                local ty = y - 1
                for c = x - reach, x + reach do
                    if Cancelled() or outOfDirt then
                        return
                    end
                    if InBounds(world, c, ty) and TileValue(world, "fg", c, ty) == 0 and InRange(c, ty) then
                        local have = CountItem(dirt)
                        if have ~= nil and have <= 0 then
                            outOfDirt = true
                            return
                        end
                        if PlaceCell(dirt, { x = c, y = ty }, face or 1) then
                            DF.stats.placed += 1
                        end
                        task.wait(0.1)
                    end
                end
            end

            for i = #rows, 1, -1 do
                if Cancelled() or outOfDirt then
                    break
                end
                local r = rows[i]
                local cx, cy = GetTile()
                local x = NearestStand(cx or home.x, r)
                if not x then
                    DF.stats.skipped += 1
                else
                    -- teleport ke baris ini (lantainya = baris yang barusan di-place)
                    if cx ~= x or cy ~= r then
                        DF.status = string.format("Teleport ke baris %d", r)
                        Nav.Tele(x, r, Cancelled)
                        task.wait(math.max(0.03, Config.clearTpDelay))
                    end
                    if Cancelled() then
                        return
                    end

                    -- place dirt di atas player sepanjang baris (hanya bagian lantai aman)
                    if not tunnel[r - 1] and r - 1 > startRow then
                        local l, rr = Segment(x, r)
                        local gx = GetTile()
                        gx = gx or x
                        local a, b, step = l, rr, 3
                        if math.abs(gx - rr) < math.abs(gx - l) then
                            a, b, step = rr, l, -3
                        end
                        local c = a
                        while not Cancelled() and not outOfDirt do
                            DF.status = string.format("Place dirt baris %d (x %d)", r - 1, c)
                            Walker(c, r, Cancelled)
                            task.wait(0.05)
                            local ax, ay = GetTile()
                            if ax and ay == r then
                                PlaceAbove(ax, ay)
                            end
                            if c == b then
                                break
                            end
                            if step > 0 then
                                c = math.min(b, c + step)
                            else
                                c = math.max(b, c + step)
                            end
                        end
                        Nav.SetInput(0, false)
                    end
                end
            end
            if Cancelled() then
                return
            end
            if outOfDirt then
                Notify("Auto Dirt Farm: dirt habis di inventory, place berhenti.")
            else
                -- naik ke atas baris yang sudah di-place (paling atas)
                local cx = GetTile()
                local x = NearestStand(cx or home.x, startRow)
                if x then
                    DF.status = "Teleport ke atas"
                    Nav.Tele(x, startRow, Cancelled)
                end
            end
        end

        Nav.SetInput(0, false)
        DF.status = "Selesai"
        Notify(string.format("Auto Dirt Farm selesai: %d baris, %d pecah, %d diambil, %d place, %d dilewati.",
            DF.stats.rows, DF.stats.broken, DF.stats.picked, DF.stats.placed, DF.stats.skipped))
    end

    function DirtFarm.Stop()
        if not DirtFarm.on then
            return false
        end
        DirtFarm.token += 1
        DirtFarm.on = false
        DirtFarm.status = "Mati"
        pcall(Nav.SetInput, 0, false)
        return true
    end

    function DirtFarm.Start()
        if DirtFarm.on then
            return true
        end
        if Clear.on then
            Clear.Stop()
        end
        if BreakId.on then
            BreakId.Stop()
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
        if Config.dirtPlace and not DirtId() then
            Notify("ID block dirt tidak ketemu. Isi manual: " .. Config.prefix .. "dirtid <id>")
            return false
        end
        -- jangkauan: beberapa block di depan harus terjangkau (mode jalan)
        local inv = FindInventory()
        local okRange, range = pcall(function() return inv.buildRange() end)
        if okRange and type(range) == "number" and range < 4.0 then
            if longhandOn then
                StopLonghand()
            end
            Config.longhandRange = math.max(Config.longhandRange, 1.5)
            ApplyLonghand()
        end

        local home = {
            x = math.floor(x),
            y = math.floor(y - 0.475),
            world = CurrentWorldName(),
        }
        DirtFarm.token += 1
        local token = DirtFarm.token
        DirtFarm.on = true
        DirtFarm.status = "Mulai"
        DirtFarm.stats = { rows = 0, broken = 0, picked = 0, placed = 0, skipped = 0 }
        task.spawn(function()
            local ok, err = pcall(DirtFarmLoop, token, home)
            if not ok then
                warn(err)
                Notify("Auto Dirt Farm error: " .. tostring(err))
            end
            if DirtFarm.token == token then
                DirtFarm.on = false
                if DirtFarm.status ~= "Selesai" then
                    DirtFarm.status = "Mati"
                end
                pcall(Nav.SetInput, 0, false)
                if RefreshHub then
                    RefreshHub()
                end
            end
        end)
        return true
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
        if DirtFarm.on then
            DirtFarm.Stop()
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
        -- Mode teleport: Longhand otomatis supaya 4 tile sekaligus terjangkau
        local inv = FindInventory()
        local okRange, range = pcall(function() return inv.buildRange() end)
        if Config.clearMode == "teleport" and okRange and type(range) == "number" and range < 4.5 then
            if longhandOn then
                StopLonghand()
            end
            Config.longhandRange = math.max(Config.longhandRange, 3)
            ApplyLonghand()
        elseif Config.clearMode ~= "teleport" and okRange and type(range) == "number" and range < 4.0 then
            -- mode jalan: 3 block di depan harus terjangkau
            if longhandOn then
                StopLonghand()
            end
            Config.longhandRange = math.max(Config.longhandRange, 1.5)
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

end

----------------------------------------------------------------------
-- HIDDEN NAME (tampilan lokal saja)
-- Nama ditampilkan lewat modul ReplicatedStorage.Shared.Roles (dipakai game
-- untuk NameTag di atas kepala & nama di chat). Modul ini di-override di sisi
-- kita saja: tidak mengubah apa pun di server, jadi pemain lain TETAP melihat
-- nama asli di layar mereka. Reset otomatis saat prefix diubah/respawn tidak
-- berpengaruh karena hook ini permanen selama script jalan.
----------------------------------------------------------------------
local HiddenName = { ready = false }
do
    local okRoles, Roles = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Roles", 5))
    end)
    if okRoles and type(Roles) == "table" and type(Roles.nameOf) == "function" then
        local originalNameOf = Roles.nameOf
        local function ShouldHide(player)
            if Config.hiddenNameMode == "all" then
                return true
            end
            if Config.hiddenNameMode == "self" then
                return player == Player
            end
            return false
        end
        Roles.nameOf = function(player, ...)
            if ShouldHide(player) then
                return "[HIDDEN]"
            end
            return originalNameOf(player, ...)
        end
        HiddenName.ready = true
    end

    -- Game hanya menggambar ulang NameTag saat atribut pemain berubah, jadi setelah
    -- mode diganti kita paksa gambar ulang: (1) panggil fungsi drawTagName milik game
    -- kalau ketemu, (2) pancing event atribut "Nick" (hanya lokal, tidak ke server).
    function HiddenName.Redraw()
        task.spawn(function()
            local called = false
            if getgcFn and debug and debug.info then
                pcall(function()
                    for _, fn in ipairs(getgcFn()) do
                        if type(fn) == "function" then
                            local okName, fnName = pcall(debug.info, fn, "n")
                            if okName and fnName == "drawTagName" then
                                if pcall(fn) then
                                    called = true
                                end
                            end
                        end
                    end
                end)
            end
            for _, plr in ipairs(Players:GetPlayers()) do
                pcall(function()
                    local cur = plr:GetAttribute("Nick")
                    plr:SetAttribute("Nick", "\u{200B}" .. tostring(cur or ""))
                    task.wait()
                    plr:SetAttribute("Nick", cur)
                end)
            end
        end)
    end

    function HiddenName.SetMode(mode)
        if mode ~= "off" and mode ~= "self" and mode ~= "all" then
            return false
        end
        if not HiddenName.ready and mode ~= "off" then
            Notify("Hidden Name tidak tersedia (modul nama game tidak ditemukan).")
            return false
        end
        Config.hiddenNameMode = mode
        SaveConfig()
        HiddenName.Redraw()
        local labels = { off = "mati", self = "nama sendiri", all = "semua pemain" }
        Notify("Hidden Name: " .. labels[mode])
        if RefreshHub then
            RefreshHub()
        end
        return true
    end

    task.defer(function()
        task.wait(2)
        if HiddenName.ready and Config.hiddenNameMode ~= "off" then
            HiddenName.Redraw()
        end
    end)
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

    ------------------------------------------------------------------
    -- Kirim pesan. GrowBlox memakai UI chat buatan sendiri (TextBox di PlayerGui),
    -- jadi cara paling pasti adalah meniru orang mengetik: isi kotak chat lalu
    -- submit (Enter). TextChatService / chat lama hanya cadangan.
    -- Kotak chat dikenali otomatis (nama mengandung "chat") atau dipelajari saat
    -- kamu mengetik command (mis. /spam on) lewat kotak chat itu.
    ------------------------------------------------------------------
    Spam.chatBox = nil
    Spam.method = nil

    local function IsBoxUsable(box)
        return box and box.Parent and box:IsA("TextBox") and box:IsDescendantOf(PlayerGui)
            and not box:FindFirstAncestor("PeexHubGB")
    end

    function Spam.FindBox()
        if IsBoxUsable(Spam.chatBox) then
            return Spam.chatBox
        end
        Spam.chatBox = nil
        local best, bestScore = nil, 0
        for _, obj in ipairs(PlayerGui:GetDescendants()) do
            if obj:IsA("TextBox") and IsBoxUsable(obj) then
                local score = 0
                if obj:GetFullName():lower():find("chat", 1, true) then
                    score += 5
                end
                if obj.PlaceholderText ~= "" and obj.PlaceholderText:lower():find("chat", 1, true) then
                    score += 5
                end
                if score > 0 and obj.Visible then
                    score += 1
                end
                if score > bestScore then
                    best, bestScore = obj, score
                end
            end
        end
        if best then
            Spam.chatBox = best
        end
        return best
    end

    local function SendViaBox(box, text)
        local ok = pcall(function()
            box:CaptureFocus()
            task.wait(0.06)
            box.Text = text
            task.wait(0.06)
            box:ReleaseFocus(true) -- FocusLost(enterPressed = true) = submit
        end)
        task.wait(0.15)
        -- kalau teks masih nempel, game belum memprosesnya: picu handler FocusLost langsung
        if (not ok or box.Text == text) and getconnections then
            pcall(function()
                box.Text = text
                for _, conn in ipairs(getconnections(box.FocusLost)) do
                    pcall(function() conn:Fire(true, nil) end)
                end
            end)
            task.wait(0.1)
            pcall(function()
                if box.Text == text then
                    box.Text = ""
                end
            end)
            return true
        end
        return ok
    end

    function Spam.Send(text)
        local box = Spam.FindBox()
        if box and SendViaBox(box, text) then
            Spam.method = "kotak chat game"
            return true
        end

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
            Spam.method = "TextChatService"
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
        if sent then
            Spam.method = "chat lama"
        end
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
                        if Spam.method ~= Spam.notified then
                            Spam.notified = Spam.method
                            Notify("Spam terkirim lewat: " .. tostring(Spam.method)
                                .. (Spam.chatBox and "" or ". Kalau tidak muncul di chat, ketik 1 command (mis. "
                                .. Config.prefix .. "pos) lewat kotak chat supaya script mengenalinya."))
                        end
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
    dirtfarm = {
        label = "Auto Dirt Farm",
        noSession = true,
        get = function() return DirtFarm.on end,
        set = function(on)
            if on then return DirtFarm.Start() end
            return DirtFarm.Stop()
        end,
    },
    breakid = {
        label = "Auto Break ID",
        noSession = true,
        get = function() return BreakId.on end,
        set = function(on)
            if on then return BreakId.Start() end
            return BreakId.Stop()
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
-- GUI (versi ringan)
-- - Halaman dibangun saat pertama kali dibuka (bukan semuanya sekaligus)
-- - Satu loop update untuk tab yang sedang aktif saja
-- - Koneksi drag dilepas saat menu ditutup (tidak menumpuk)
-- - Tombol P membuka menu hanya saat benar-benar di-tap
----------------------------------------------------------------------
local C = {
    window = Color3.fromRGB(255, 236, 179),
    panel = Color3.fromRGB(255, 249, 226),
    card = Color3.fromRGB(255, 255, 255),
    cardHi = Color3.fromRGB(255, 214, 102),
    stroke = Color3.fromRGB(74, 44, 42),
    accent = Color3.fromRGB(255, 140, 66),
    accent2 = Color3.fromRGB(77, 196, 255),
    text = Color3.fromRGB(74, 44, 42),
    mute = Color3.fromRGB(153, 110, 84),
    ok = Color3.fromRGB(94, 214, 92),
    bad = Color3.fromRGB(255, 96, 96),
}
local CARTOON_FONT = Enum.Font.FredokaOne

local function New(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local function Corner(obj, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius) }, obj)
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
    for k, v in pairs(props) do
        p[k] = v
    end
    return New("TextLabel", p, parent)
end

local rootGui = nil
local function GetGui()
    if rootGui and rootGui.Parent then
        return rootGui
    end
    rootGui = Instance.new("ScreenGui")
    rootGui.Name = "PeexHubGB"
    rootGui.ResetOnSpawn = false
    rootGui.DisplayOrder = 999
    local okParent = pcall(function()
        rootGui.Parent = (gethui and gethui()) or PlayerGui
    end)
    if not okParent or not rootGui.Parent then
        rootGui.Parent = PlayerGui
    end
    return rootGui
end

local function CopyId(id)
    if setclipboard then
        pcall(setclipboard, tostring(id))
    end
end

-- Notifikasi: maksimal 3, otomatis hilang, tanpa animasi berat
local toastHolder = nil
local toasts = {}
local toastOrder = 0
ToastHook = function(message)
    if not (toastHolder and toastHolder.Parent) then
        toastHolder = New("Frame", {
            Name = "Toasts",
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 250, 1, -70),
            Position = UDim2.new(1, -260, 0, 58),
            ZIndex = 100,
        }, GetGui())
        New("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, toastHolder)
    end
    toastOrder += 1
    local toast = New("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Text = message,
        TextColor3 = C.text,
        Font = CARTOON_FONT,
        TextSize = 12,
        TextWrapped = true,
        LayoutOrder = toastOrder,
        ZIndex = 100,
    }, toastHolder)
    Corner(toast, 10)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
    }, toast)
    table.insert(toasts, toast)
    if #toasts > 3 then
        local old = table.remove(toasts, 1)
        if old then
            old:Destroy()
        end
    end
    task.delay(3.5, function()
        if toast.Parent then
            for i, t in ipairs(toasts) do
                if t == toast then
                    table.remove(toasts, i)
                    break
                end
            end
            toast:Destroy()
        end
    end)
end

-- State hub -----------------------------------------------------------
local hub = {
    frame = nil,
    active = nil,
    pages = {},     -- id -> ScrollingFrame
    built = {},     -- id -> sudah dibangun?
    updaters = {},  -- id -> fungsi update status (dipanggil loop)
    refresh = {},   -- page -> { fungsi refresh }
    tabBtns = {},
    conns = {},     -- koneksi yang dilepas saat menu ditutup
    narrow = false,
    launcher = nil,
}

local orders = setmetatable({}, { __mode = "k" })
local function NextOrder(parent)
    local n = (orders[parent] or 0) + 1
    orders[parent] = n
    return n
end

local function OnRefresh(page, fn)
    local list = hub.refresh[page]
    if not list then
        list = {}
        hub.refresh[page] = list
    end
    table.insert(list, fn)
end

RefreshHub = function()
    for _, list in pairs(hub.refresh) do
        for _, fn in ipairs(list) do
            pcall(fn)
        end
    end
end

-- Komponen ------------------------------------------------------------
local function AddCard(page, height)
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        LayoutOrder = NextOrder(page),
    }, page)
    Corner(card, 10)
    return card
end

local function StatusCard(page, height)
    local card = AddCard(page, height)
    return Label(card, {
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 1, -12),
        TextSize = 12,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
end

local function AddSection(page, text)
    return Label(page, {
        Size = UDim2.new(1, 0, 0, 18),
        Text = string.upper(text),
        TextColor3 = C.mute,
        TextSize = 11,
        TextWrapped = false,
        LayoutOrder = NextOrder(page),
    })
end

local function AddNote(page, text)
    return Label(page, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = text,
        TextColor3 = C.mute,
        TextSize = 12,
        LayoutOrder = NextOrder(page),
    })
end

local function StyleOf(style)
    if style == "primary" then
        return C.accent, Color3.fromRGB(255, 168, 102)
    elseif style == "danger" then
        return C.bad, Color3.fromRGB(255, 134, 134)
    end
    return C.cardHi, Color3.fromRGB(255, 229, 150)
end

local function MakeButton(parent, text, style, props)
    local base, hover = StyleOf(style)
    local p = {
        Size = UDim2.new(1, 0, 0, 34),
        Text = text,
        TextColor3 = C.text,
        Font = CARTOON_FONT,
        TextSize = 12,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        BackgroundColor3 = base,
    }
    for k, v in pairs(props or {}) do
        p[k] = v
    end
    local button = New("TextButton", p, parent)
    Corner(button, 8)
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = hover
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = base
    end)
    return button
end

local function AddButton(page, text, style, callback)
    local button = MakeButton(page, text, style, { LayoutOrder = NextOrder(page) })
    button.MouseButton1Click:Connect(callback)
    return button
end

local function AddSwitch(page, title, subtitle, getState, onToggle)
    local card = AddCard(page, 60)
    Label(card, {
        Text = title,
        Font = CARTOON_FONT,
        TextSize = 13,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -80, 0, 18),
        TextWrapped = false,
    })
    Label(card, {
        Text = subtitle,
        TextColor3 = C.mute,
        TextSize = 11,
        Position = UDim2.fromOffset(12, 26),
        Size = UDim2.new(1, -80, 0, 30),
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local track = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(46, 24),
        BackgroundColor3 = C.cardHi,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
    }, card)
    Corner(track, 12)
    local knob = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    Corner(knob, 9)

    local function Refresh()
        local on = getState() and true or false
        track.BackgroundColor3 = on and C.ok or C.cardHi
        knob.Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
    end
    track.MouseButton1Click:Connect(function()
        onToggle(not getState())
        Refresh()
    end)
    OnRefresh(page, Refresh)
    Refresh()
end

-- Kotak angka satu baris (judul kiri, kotak kanan)
local function AddInput(page, title, subtitle, value, placeholder, onCommit)
    local card = AddCard(page, 58)
    Label(card, {
        Text = title,
        Font = CARTOON_FONT,
        TextSize = 12,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -140, 0, 16),
        TextWrapped = false,
    })
    Label(card, {
        Text = subtitle,
        TextColor3 = C.mute,
        TextSize = 10,
        Position = UDim2.fromOffset(12, 25),
        Size = UDim2.new(1, -140, 0, 28),
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    local box = New("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(110, 32),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Text = tostring(value),
        PlaceholderText = placeholder or "",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 13,
        ClearTextOnFocus = false,
    }, card)
    Corner(box, 8)
    box.FocusLost:Connect(function()
        onCommit(box.Text, box)
    end)
    return box
end

-- Kotak teks lebar (ID block, teks spam, URL)
local function AddTextArea(page, hint, value, placeholder, onCommit)
    local card = AddCard(page, 78)
    Label(card, {
        Text = hint,
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
        Text = tostring(value or ""),
        PlaceholderText = placeholder or "",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 13,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    Corner(box, 8)
    box.FocusLost:Connect(function()
        if onCommit then
            onCommit(box.Text, box)
        end
    end)
    return box
end

-- Input angka dengan batas, otomatis simpan ke Config[key]
local function NumberInput(page, title, subtitle, key, placeholder, minV, maxV, onSet)
    return AddInput(page, title, subtitle, Config[key], placeholder, function(text, box)
        local v = tonumber(text)
        if v and v >= minV and v <= maxV then
            Config[key] = v
            SaveConfig()
            if onSet then
                onSet(v)
            end
        else
            box.Text = tostring(Config[key])
            Notify("Isi angka " .. minV .. " sampai " .. maxV .. ".")
        end
    end)
end

-- Pencarian item dari ItemDB
local function AddItemSearch(page, onPick)
    local card = AddCard(page, 38)
    local box = New("TextBox", {
        Position = UDim2.fromOffset(10, 5),
        Size = UDim2.new(1, -20, 0, 28),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Cari nama block atau ID...",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 12,
        ClearTextOnFocus = false,
    }, card)
    Corner(box, 8)

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
        for _, c in ipairs(results:GetChildren()) do
            if c:IsA("GuiButton") or c:IsA("TextLabel") then
                c:Destroy()
            end
        end
        if Trim(box.Text) == "" then
            return
        end
        local found = SearchItems(box.Text, 20)
        if #found == 0 then
            Label(results, {
                Size = UDim2.new(1, 0, 0, 20),
                Text = "Tidak ada hasil.",
                TextColor3 = C.mute,
                TextSize = 11,
            })
            return
        end
        for i, entry in ipairs(found) do
            local row = MakeButton(results, entry.name .. "   [ID " .. entry.id .. "]", "ghost", {
                Size = UDim2.new(1, 0, 0, 28),
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                LayoutOrder = i,
            })
            New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, row)
            row.MouseButton1Click:Connect(function()
                CopyId(entry.id)
                onPick(entry)
            end)
        end
    end

    local token = 0
    box:GetPropertyChangedSignal("Text"):Connect(function()
        token += 1
        local mine = token
        task.delay(0.3, function()
            if mine == token then
                Populate()
            end
        end)
    end)
    return box
end

-- Drag (koneksinya dicatat supaya dilepas saat menu ditutup)
local function MakeDraggable(handle, frame)
    local dragging, startInput, startPos = false, nil, nil
    table.insert(hub.conns, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInput = input.Position
            startPos = frame.Position
        end
    end))
    table.insert(hub.conns, UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startInput
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end))
    table.insert(hub.conns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

----------------------------------------------------------------------
-- BUILDER HALAMAN
----------------------------------------------------------------------
local FEATURE_SWITCHES = {
    { "blink", "Blink Skin", "Warna skin berganti otomatis tiap 0.2-0.5 detik." },
    { "longhand", "Longhand", "Jangkauan punch & build lebih jauh (atur di Setelan)." },
    { "noclip", "Noclip", "Tembus blok & terbang (mode ghost). Naik: lompat, turun: bawah/S." },
    { "ujump", "Unlimited Jump", "Lompat di udara tanpa batas, bahkan tanpa sayap." },
    { "antiafk", "Anti-AFK", "Mencegah kick karena idle." },
    { "autorejoin", "Auto Rejoin", "Rejoin otomatis ke world ini kalau terputus." },
    { "god", "God Mode", "Kebal lava, spike, api. Tidak mencakup kick/ban staff." },
    { "autofarm", "Auto Farm", "Atur kecepatan, ID block, dan pola di tab Auto Farm." },
    { "autoclear", "Auto Clear World", "GrowScan, pecah block, ambil drop (tab Auto Clear)." },
    { "dirtfarm", "Auto Dirt Farm", "Dig, respawn, lalu place dirt (tab Dirt Farm)." },
    { "clicktp", "Click TP", "Klik tujuan, karakter menyusuri path." },
    { "autoquest", "Auto Quest", "Claim dan kerjakan quest otomatis (tab Auto Quest)." },
}

local function BuildFeatures(page)
    local lbl = StatusCard(page, 40)
    local function Upd()
        local tx, ty = GetTile()
        local w = CurrentWorldName()
        lbl.Text = tx and string.format("World: %s  |  Tile: %d, %d", w ~= "" and w or "-", tx, ty)
            or "Posisi tidak terdeteksi"
    end
    Upd()

    AddSection(page, "Fitur")
    for _, d in ipairs(FEATURE_SWITCHES) do
        local key = d[1]
        AddSwitch(page, d[2], d[3], Features[key].get, function(on)
            SetFeature(key, on)
        end)
    end

    AddSection(page, "Aksi cepat")
    local card = AddCard(page, 96)
    Label(card, {
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
    }, card)
    Corner(amountBox, 8)
    local dropBtn = MakeButton(card, "Drop", "primary", {
        Position = UDim2.new(0.5, 5, 0, 30),
        Size = UDim2.new(0.5, -17, 0, 28),
    })
    dropBtn.MouseButton1Click:Connect(function()
        local n = tonumber(amountBox.Text)
        if n and n >= 1 and n <= MAX_AMOUNT and n == math.floor(n) then
            task.spawn(DropWorldLock, n)
        else
            Notify("Jumlah tidak valid (1-" .. MAX_AMOUNT .. ")")
        end
    end)
    local row = New("Frame", {
        Position = UDim2.fromOffset(12, 64),
        Size = UDim2.new(1, -24, 0, 24),
        BackgroundTransparency = 1,
    }, card)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
    }, row)
    for _, v in ipairs({ 1, 10, 50, 100 }) do
        local chip = MakeButton(row, tostring(v), "ghost", {
            Size = UDim2.new(0.25, -5, 1, 0),
            TextSize = 11,
        })
        chip.MouseButton1Click:Connect(function()
            amountBox.Text = tostring(v)
        end)
    end

    AddButton(page, "Rejoin World", "ghost", function()
        task.spawn(Rejoin)
    end)
    return Upd
end

local function GridCount()
    local n = 0
    for _, on in pairs(Config.farmGrid) do
        if on then
            n += 1
        end
    end
    return n
end

local function BuildFarm(page)
    local lbl = StatusCard(page, 78)
    local function Upd()
        local id = Config.farmPlaceId
        local blockText = (type(id) == "number" and id > 0) and (ItemName(id) .. " (ID " .. id .. ")") or "belum dipilih"
        lbl.Text = string.format(
            "Status: %s\nBlock: %s\nKotak: %d  |  jeda %.2f dtk\nPlace %d  Break %d  Ambil %d  Siklus %d",
            farmStats.status, blockText, GridCount(), Config.farmDelay,
            farmStats.placed, farmStats.broken, farmStats.picked, farmStats.cycles)
    end
    Upd()

    AddSwitch(page, "Auto Farm", "Place, pukul, lalu ambil item. Berdiri di posisi farm dulu.",
        Features.autofarm.get, function(on) SetFeature("autofarm", on) end)

    AddSection(page, "Pengaturan")
    NumberInput(page, "Kecepatan pukulan", "Jeda antar pukulan (detik). Min 0.03.", "farmDelay", "0.22", 0.03, 5)
    local idBox = AddInput(page, "ID block", "Block yang di-place. Cari di bawah.", Config.farmPlaceId, "ID", function(text, box)
        local v = tonumber(text)
        if v and v > 0 and ItemName(v) ~= "?" then
            Config.farmPlaceId = v
            SaveConfig()
            Notify("Block: " .. ItemName(v))
        else
            box.Text = tostring(Config.farmPlaceId)
            Notify("ID tidak ada di database item.")
        end
    end)

    AddSection(page, "Pola place (grid 5x5)")
    AddNote(page, "Tap kotak sampai HIJAU = block di-place di situ. Kotak KAMU = posisi player.")
    local gridCard = AddCard(page, 5 * 34 + 12)
    local grid = New("Frame", {
        Position = UDim2.fromOffset(8, 6),
        Size = UDim2.new(1, -16, 1, -12),
        BackgroundTransparency = 1,
    }, gridCard)
    New("UIGridLayout", {
        CellSize = UDim2.new(0.2, -4, 0, 30),
        CellPadding = UDim2.fromOffset(4, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)
    local cells = {}
    local function Paint(key)
        local c = cells[key]
        if c then
            c.BackgroundColor3 = Config.farmGrid[key] and C.ok or C.bad
        end
    end
    for dy = -2, 2 do
        for dx = -2, 2 do
            local order = (dy + 2) * 5 + dx + 3
            if dx == 0 and dy == 0 then
                New("TextLabel", {
                    BackgroundColor3 = C.accent2,
                    BorderSizePixel = 0,
                    Text = "KAMU",
                    TextColor3 = C.text,
                    Font = CARTOON_FONT,
                    TextSize = 10,
                    LayoutOrder = order,
                }, grid)
            else
                local key = dx .. "," .. dy
                local c = New("TextButton", {
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = "",
                    LayoutOrder = order,
                }, grid)
                cells[key] = c
                Paint(key)
                c.MouseButton1Click:Connect(function()
                    Config.farmGrid[key] = (not Config.farmGrid[key]) or nil
                    SaveConfig()
                    Paint(key)
                end)
            end
        end
    end
    AddButton(page, "Kosongkan semua kotak", "ghost", function()
        Config.farmGrid = {}
        SaveConfig()
        for key in pairs(cells) do
            Paint(key)
        end
    end)

    AddSwitch(page, "Ambil item otomatis", "Setelah break, teleport ambil item lalu kembali.",
        function() return Config.farmTake end,
        function(on) Config.farmTake = on SaveConfig() end)

    AddSection(page, "Database item")
    AddItemSearch(page, function(entry)
        Config.farmPlaceId = entry.id
        SaveConfig()
        idBox.Text = tostring(entry.id)
        Notify("Block: " .. entry.name .. " (ID " .. entry.id .. ")")
    end)
    return Upd
end

local function BuildClear(page)
    local lbl = StatusCard(page, 78)
    local modeLbl = StatusCard(page, 34)
    local MODE_NAMES = { walk = "Jalan", teleport = "Teleport" }
    local function Upd()
        local st = Clear.stats
        lbl.Text = string.format(
            "Status: %s (pass %d)  |  Mode %s\nTarget %d  |  Sisa %d  |  Dilewati %d\nPecah %d  Ambil %d",
            Clear.status, st.pass, MODE_NAMES[Config.clearMode] or "Jalan",
            st.scanned, st.left, st.skipped, st.broken, st.picked)
        modeLbl.Text = "Mode aktif: " .. (MODE_NAMES[Config.clearMode] or "Jalan")
    end
    Upd()

    AddSwitch(page, "Auto Clear World", "GrowScan dulu, lalu pecah block (lock & bedrock aman).",
        Features.autoclear.get, function(on) SetFeature("autoclear", on) end)

    AddSection(page, "Mode clear")
    AddButton(page, "Jalan (turun 1x, sapu baris sampai ujung)", "primary", function()
        Config.clearMode = "walk"
        SaveConfig()
        Upd()
        Notify("Mode clear: Jalan")
    end)
    AddButton(page, "Teleport (pindah ke grup block)", "primary", function()
        Config.clearMode = "teleport"
        SaveConfig()
        Upd()
        Notify("Mode clear: Teleport")
    end)

    AddSection(page, "Pengaturan")
    NumberInput(page, "Block per pukulan", "1 sampai 3 block sekaligus.", "clearPunch", "3", 1, 3)
    NumberInput(page, "Delay break", "Detik per putaran pukul (min 0.03).", "clearBreakDelay", "0.22", 0.03, 5)
    NumberInput(page, "Delay teleport", "Detik setelah pindah / ambil drop.", "clearTpDelay", "0.25", 0.03, 5)
    AddSwitch(page, "Ambil item otomatis", "Ambil drop setelah break, sapu sisa di akhir.",
        function() return Config.clearTake end,
        function(on) Config.clearTake = on SaveConfig() end)
    AddButton(page, "GrowScan sekarang", "primary", function()
        task.spawn(function()
            local scan = ScanWorld()
            if not scan then
                Notify("World tidak terbaca.")
                return
            end
            local fg, bg = 0, 0
            for _, n in pairs(scan.fg) do fg += n end
            for _, n in pairs(scan.bg) do bg += n end
            Notify(string.format("GrowScan: %d fg, %d bg (world %dx%d)", fg, bg, scan.w, scan.h))
        end)
    end)
    AddNote(page, "Berdiri di world milikmu sebelum menyalakan. Block lock, area, bedrock, dan door utama tidak disentuh.")
    return Upd
end

local function BuildDirt(page)
    local lbl = StatusCard(page, 78)
    local function DirtName()
        local id = DirtFarm.ResolveId and DirtFarm.ResolveId()
        return id and (ItemName(id) .. " (ID " .. id .. ")") or "belum ketemu"
    end
    local nameText = DirtName() -- di-cache supaya tidak mencari ulang tiap update
    local function Upd()
        local st = DirtFarm.stats
        lbl.Text = string.format(
            "Status: %s  |  Baris %d\nPecah %d  Ambil %d  Place %d  Dilewati %d\nDirt: %s",
            DirtFarm.status, st.rows, st.broken, st.picked, st.placed, st.skipped, nameText)
    end
    Upd()

    AddSwitch(page, "Auto Dirt Farm", "Dig, sapu baris, respawn, lalu place dirt naik.",
        Features.dirtfarm.get, function(on) SetFeature("dirtfarm", on) end)

    AddSection(page, "Pengaturan")
    NumberInput(page, "Block per pukulan", "1 sampai 3 (sama dengan Auto Clear).", "clearPunch", "3", 1, 3)
    local dirtInput
    dirtInput = AddInput(page, "ID block dirt", "0 = otomatis cari item bernama Dirt.", Config.dirtId, "0", function(text, box)
        local v = tonumber(text)
        if v and v >= 0 then
            Config.dirtId = math.floor(v)
            SaveConfig()
            nameText = DirtName()
            Upd()
        else
            box.Text = tostring(Config.dirtId)
        end
    end)
    AddSwitch(page, "Place dirt setelah dig", "Place dirt dari baris bawah naik ke atas.",
        function() return Config.dirtPlace end,
        function(on) Config.dirtPlace = on SaveConfig() end)
    AddSwitch(page, "Ambil item otomatis", "Ambil drop hasil break.",
        function() return Config.clearTake end,
        function(on) Config.clearTake = on SaveConfig() end)

    AddSection(page, "Pilih block dirt dari database")
    AddItemSearch(page, function(entry)
        Config.dirtId = entry.id
        SaveConfig()
        dirtInput.Text = tostring(entry.id)
        nameText = DirtName()
        Upd()
        Notify("Block dirt: " .. entry.name)
    end)
    return Upd
end

local function BuildBreakId(page)
    local lbl = StatusCard(page, 56)
    local function Upd()
        local s = BreakId.stats
        lbl.Text = string.format("%s\n%s  |  ditemukan %d, pecah %d, diambil %d, lewat %d",
            BreakId.on and "AKTIF" or "Mati", BreakId.status, s.found, s.broken, s.picked, s.skipped)
    end
    Upd()

    AddSection(page, "ID block")
    local box = AddTextArea(page, "ID block, pisah koma. Contoh: 4,112",
        Config.breakIdText, "cth: 4, 112", function(text)
            Config.breakIdText = Trim(text)
            SaveConfig()
        end)
    AddButton(page, "Mulai Break ID", "primary", function()
        BreakId.Stop()
        BreakId.Start(box.Text)
        RefreshHub()
    end)
    AddButton(page, "Berhenti", "danger", function()
        SetFeature("breakid", false)
    end)
    AddNote(page, "Scan world, pindah dekat block, pecahkan, ambil drop. Delay & punch memakai pengaturan Auto Clear.")
    return Upd
end

local function BuildSpam(page)
    local lbl = StatusCard(page, 40)
    local function Upd()
        local t = Trim(Config.spamText or "")
        lbl.Text = (Spam.on and "Spam: AKTIF" or "Spam: mati") .. "   |   Teks: " .. (t ~= "" and t or "(kosong)")
    end
    Upd()

    AddSwitch(page, "Spam Chat", "Kirim teks di bawah ke chat berulang-ulang.",
        Features.spam.get, function(on) SetFeature("spam", on) end)

    AddSection(page, "Teks spam")
    AddTextArea(page, "Maks 200 huruf, tidak boleh diawali /", Config.spamText, "Ketik teks spam...", function(text, box)
        if not Spam.SetText(text) then
            box.Text = tostring(Config.spamText or "")
        end
        Upd()
    end)
    NumberInput(page, "Delay antar pesan", "Detik per pesan (min 1.5).", "spamDelay", "3", 1.5, 120)
    AddButton(page, "Kirim sekali (tes)", "primary", function()
        local t = Trim(Config.spamText or "")
        if t == "" then
            Notify("Teks spam masih kosong.")
            return
        end
        Spam.guardText = t:lower()
        Spam.guardT = os.clock()
        if not Spam.Send(t) then
            Notify("Gagal kirim: chat tidak ditemukan.")
        end
    end)
    AddNote(page, "Command: /spam on|off, /setspam <teks>. Pakai delay yang wajar supaya tidak kena mute.")
    return Upd
end

local function BuildHidden(page)
    local lbl = StatusCard(page, 40)
    local MODE_NAMES = { off = "Mati", self = "Nama sendiri", all = "Semua pemain" }
    local function Upd()
        lbl.Text = "Hidden Name: " .. (MODE_NAMES[Config.hiddenNameMode] or "Mati")
            .. (HiddenName.ready and "" or "   (tidak tersedia)")
    end
    Upd()
    AddSection(page, "Pilih target")
    AddButton(page, "Mati (tampilkan nama asli)", "ghost", function() HiddenName.SetMode("off") Upd() end)
    AddButton(page, "Sembunyikan nama saya saja", "primary", function() HiddenName.SetMode("self") Upd() end)
    AddButton(page, "Sembunyikan semua pemain", "primary", function() HiddenName.SetMode("all") Upd() end)
    AddNote(page, "Hanya tampilan di layar kamu. Pemain lain tetap melihat nama asli.")
    return Upd
end

local function BuildNav(page)
    local lbl = StatusCard(page, 40)
    local function Upd()
        lbl.Text = "Terakhir: " .. Nav.last
    end
    Upd()

    AddSwitch(page, "Click TP", "Klik tujuan dengan mouse, karakter menyusuri path.",
        Features.clicktp.get, function(on) SetFeature("clicktp", on) end)
    AddSwitch(page, "Wajib tahan Shift", "Hanya aktif kalau Shift ditahan (PC).",
        function() return Config.clickTpShift end,
        function(on) Config.clickTpShift = on SaveConfig() end)

    AddSection(page, "Mode gerak")
    local modeLbl = StatusCard(page, 34)
    local NAMES = { walk = "Jalan", tp = "Teleport 3-5 block", fly = "Terbang", mix = "Campur" }
    local function UpdMode()
        modeLbl.Text = "Mode aktif: " .. (NAMES[Config.moveMode] or "Campur")
    end
    UpdMode()
    local function SetMode(m)
        Config.moveMode = m
        SaveConfig()
        UpdMode()
        Notify("Mode gerak: " .. NAMES[m])
    end
    AddButton(page, "Jalan (asli, pakai analog)", "primary", function() SetMode("walk") end)
    AddButton(page, "Teleport (bertahap 3-5 block)", "primary", function() SetMode("tp") end)
    AddButton(page, "Terbang (lurus, tembus block)", "primary", function() SetMode("fly") end)
    AddButton(page, "Campur (jalan dulu, buntu = terbang)", "primary", function() SetMode("mix") end)
    AddInput(page, "Lompatan teleport", "Isi min-max, contoh 3-5.",
        tostring(Config.hopMin) .. "-" .. tostring(Config.hopMax), "3-5", function(text, box)
            local lo, hi = tostring(text):match("^%s*(%d+)%s*[-,%s]%s*(%d+)%s*$")
            lo, hi = tonumber(lo), tonumber(hi)
            if lo and hi and lo >= 1 and hi >= lo and hi <= 10 then
                Config.hopMin, Config.hopMax = lo, hi
                SaveConfig()
            else
                box.Text = tostring(Config.hopMin) .. "-" .. tostring(Config.hopMax)
                Notify("Isi seperti 3-5 (maksimal 10).")
            end
        end)
    return function()
        Upd()
        UpdMode()
    end
end

local function BuildQuest(page)
    local lbl = StatusCard(page, 40)
    local function Upd()
        lbl.Text = "Status: " .. questStatus
    end
    Upd()
    AddSwitch(page, "Auto Quest", "Claim reward lalu kerjakan quest break/place lewat Auto Farm.",
        Features.autoquest.get, function(on) SetFeature("autoquest", on) end)
    AddButton(page, "Baca quest sekarang", "primary", function()
        task.spawn(QuestReport)
    end)
    AddNote(page, "Block untuk quest harus ada di inventory. Quest yang tidak dikenali dilewati.")
    return Upd
end

local function BuildScan(page)
    local list
    local Render
    AddButton(page, "Buka GrowScan game", "primary", function()
        if not OpenNativeGrowScan() then
            Notify("GrowScan bawaan game tidak tersedia, pakai scan di bawah.")
        end
    end)
    AddButton(page, "Scan isi world", "ghost", function()
        Render()
    end)
    AddNote(page, "Tap hasil untuk jadikan block Auto Farm.")

    list = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, list)

    Render = function()
        for _, c in ipairs(list:GetChildren()) do
            if not c:IsA("UIListLayout") then
                c:Destroy()
            end
        end
        local data = ScanWorld()
        if not data then
            Label(list, { Size = UDim2.new(1, 0, 0, 20), Text = "World belum terbaca.", TextColor3 = C.mute, TextSize = 11 })
            return
        end
        local n = 0
        local function Section(title, counts, pick)
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
            n += 1
            Label(list, {
                Size = UDim2.new(1, 0, 0, 18),
                Text = string.upper(title) .. " (" .. #entries .. " jenis)",
                TextColor3 = C.mute,
                Font = CARTOON_FONT,
                TextSize = 11,
                TextWrapped = false,
                LayoutOrder = n,
            })
            for _, e in ipairs(entries) do
                n += 1
                local row = MakeButton(list, string.format("%s  [ID %d]  x%d", ItemName(e.id), e.id, e.count), "ghost", {
                    Size = UDim2.new(1, 0, 0, 26),
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    LayoutOrder = n,
                })
                row.MouseButton1Click:Connect(function()
                    CopyId(e.id)
                    if pick then
                        Config.farmPlaceId = e.id
                        SaveConfig()
                        Notify("Block Auto Farm: " .. ItemName(e.id))
                    else
                        Notify(ItemName(e.id) .. " = ID " .. e.id)
                    end
                end)
            end
        end
        Section("Foreground", data.fg, true)
        Section("Background", data.bg, true)
        Section("Item tergeletak", data.drops, false)
    end
end

local function AddPosCard(page, slot)
    local card = AddCard(page, 100)
    Label(card, {
        Text = "Pos " .. slot,
        Font = CARTOON_FONT,
        TextSize = 14,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 18),
        TextWrapped = false,
    })
    local info = Label(card, {
        Position = UDim2.fromOffset(12, 28),
        Size = UDim2.new(1, -24, 0, 16),
        TextColor3 = C.mute,
        TextSize = 11,
        TextWrapped = false,
    })
    local function Upd()
        local pos = Config["pos" .. slot]
        if type(pos) == "table" and type(pos.x) == "number" then
            info.Text = string.format("Tile %d, %d  -  world %s", pos.x, pos.y,
                (pos.world and pos.world ~= "") and pos.world or "-")
            info.TextColor3 = C.ok
        else
            info.Text = "Belum diset"
            info.TextColor3 = C.mute
        end
    end
    Upd()
    OnRefresh(page, Upd)

    local setB = MakeButton(card, "Set di sini", "primary", {
        Position = UDim2.new(0, 12, 1, -44),
        Size = UDim2.new(0.5, -17, 0, 32),
    })
    local goB = MakeButton(card, "Teleport (win" .. slot .. ")", "ghost", {
        Position = UDim2.new(0.5, 5, 1, -44),
        Size = UDim2.new(0.5, -17, 0, 32),
    })
    setB.MouseButton1Click:Connect(function()
        SetPos(slot)
        RefreshHub()
    end)
    goB.MouseButton1Click:Connect(function()
        task.spawn(GoToPos, slot)
    end)
end

local function BuildPos(page)
    AddNote(page, "Berdiri di posisi lalu tekan Set. Teleport untuk kembali. Atau pakai command win.")
    AddPosCard(page, 1)
    AddPosCard(page, 2)
    AddNote(page, string.format("Tips: %sw1 50 = teleport ke Pos 1 lalu langsung drop 50 WL.", Config.prefix))
end

local function BuildVisual(page)
    local list = GetWearables()
    if not list then
        AddNote(page, "ItemDB game tidak ditemukan.")
        return
    end
    AddNote(page, "Hanya tampilan lokal. Tap item untuk memakai atau melepas.")

    local search = New("TextBox", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.card,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Cari nama item...",
        TextColor3 = C.text,
        PlaceholderColor3 = C.mute,
        Font = CARTOON_FONT,
        TextSize = 13,
        ClearTextOnFocus = false,
        LayoutOrder = NextOrder(page),
    }, page)
    Corner(search, 8)

    local chipRow = New("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 5),
    }, chipRow)

    local Rebuild
    AddButton(page, "Kembalikan Semua Item", "danger", function()
        ResetVisuals()
        Rebuild()
    end)

    local resultsF = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(page),
    }, page)
    New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, resultsF)

    local filter, limit = "Semua", 60
    local chips = {}
    for _, name in ipairs({ "Semua", "Kuyang", "LegendBot", "Rayman" }) do
        local chip = MakeButton(chipRow, name, "ghost", {
            Size = UDim2.new(0.25, -4, 1, 0),
            TextSize = 11,
        })
        chip.MouseButton1Click:Connect(function()
            filter = name
            limit = 60
            Rebuild()
        end)
        chips[name] = chip
    end

    Rebuild = function()
        for name, chip in pairs(chips) do
            chip.BackgroundColor3 = (name == filter) and C.accent or C.cardHi
        end
        for _, c in ipairs(resultsF:GetChildren()) do
            if not c:IsA("UIListLayout") then
                c:Destroy()
            end
        end
        local q = Trim(search.Text):lower()
        local shown, total = 0, 0
        for _, e in ipairs(list) do
            local passFilter = filter == "Semua" or table.find(e.tags, filter) ~= nil
            if passFilter and (q == "" or e.lower:find(q, 1, true)) then
                total += 1
                if shown < limit then
                    shown += 1
                    local worn = IsVisualWorn(e.id)
                    local tagText = #e.tags > 0 and (" - " .. table.concat(e.tags, ",")) or ""
                    local row = MakeButton(resultsF, e.name .. "   " .. e.slot .. tagText, worn and "primary" or "ghost", {
                        Size = UDim2.new(1, 0, 0, 32),
                        TextSize = 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        LayoutOrder = shown,
                    })
                    row.MouseButton1Click:Connect(function()
                        if ToggleVisual(e.id) then
                            Rebuild()
                        end
                    end)
                end
            end
        end
        Label(resultsF, {
            Size = UDim2.new(1, 0, 0, 18),
            Text = string.format("Menampilkan %d dari %d", shown, total),
            TextColor3 = C.mute,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Center,
            LayoutOrder = 1000,
        })
        if total > shown then
            local more = MakeButton(resultsF, "Muat lebih banyak", "ghost", {
                Size = UDim2.new(1, 0, 0, 30),
                LayoutOrder = 1001,
            })
            more.MouseButton1Click:Connect(function()
                limit += 60
                Rebuild()
            end)
        end
    end
    search:GetPropertyChangedSignal("Text"):Connect(function()
        limit = 60
        Rebuild()
    end)
    Rebuild()
end

local function BuildSession(page)
    AddNote(page, "Sesi menyimpan fitur aktif, Pos 1/2, dan world terakhir. Setelah ganti world atau rejoin, fitur dipulihkan otomatis.")
    local info = StatusCard(page, 90)
    local function Upd()
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
            "Auto-reload: " .. (ReloadReady() and "siap" or "belum siap (simpan skrip / isi URL)"),
        }, "\n")
    end
    Upd()

    AddSection(page, "Otomatis")
    AddSwitch(page, "Pulihkan fitur", "Nyalakan lagi fitur yang aktif sebelumnya.",
        function() return Config.autoRestore end,
        function(on) Config.autoRestore = on SaveConfig() end)
    AddSwitch(page, "Auto-reload skrip", "Jalankan ulang skrip setelah pindah world / rejoin.",
        function() return Config.autoReload end,
        function(on)
            Config.autoReload = on
            SaveConfig()
            if on then QueueReload() end
            Upd()
        end)
    AddSwitch(page, "Masuk world terakhir", "Setelah buka Roblox, warp ke world terakhir.",
        function() return Config.autoWarp end,
        function(on) Config.autoWarp = on SaveConfig() end)

    AddSection(page, "Sumber skrip")
    AddTextArea(page, "URL skrip (opsional) untuk auto-reload", Config.scriptUrl, "https://...", function(text, box)
        Config.scriptUrl = Trim(text)
        box.Text = Config.scriptUrl
        SaveConfig()
        QueueReload()
        Upd()
    end)

    AddSection(page, "Aksi")
    AddButton(page, "Simpan sesi sekarang", "primary", function()
        SaveSessionNow()
        Notify("Sesi disimpan.")
        Upd()
    end)
    AddButton(page, "Pasang auto-execute (autoexec)", "ghost", InstallAutoexec)
    AddButton(page, "Reset sesi", "danger", function()
        Config.session = {}
        Config.lastWorld = ""
        SaveConfig()
        Notify("Sesi direset.")
        Upd()
    end)
    return Upd
end

local function BuildSettings(page)
    AddNote(page, "Prefix boleh apa saja atau dikosongkan. /sgb selalu bisa dibuka.")

    AddSection(page, "Command")
    AddInput(page, "Prefix", "Kosong = tanpa prefix", Config.prefix, "(kosong)", function(text, box)
        Config.prefix = Trim(text)
        box.Text = Config.prefix
        SaveConfig()
        Notify(Config.prefix == "" and "Prefix dikosongkan." or ("Prefix: " .. Config.prefix))
        hub.invalidate("help")
    end)
    NumberInput(page, "ID item drop", "Dipakai oleh wld / wd.", "dropId", "242", 1, 1000000)
    NumberInput(page, "Auto-drop saat win", "Jumlah WL otomatis (0 = mati).", "winDrop", "0", 0, MAX_AMOUNT)

    AddSection(page, "Fitur")
    NumberInput(page, "Jangkauan longhand", "Tile tambahan (1-20).", "longhandRange", "3", 1, 20, function()
        if longhandOn then
            ApplyLonghand()
        end
    end)
    NumberInput(page, "Blink minimum", "Detik (0.05-10).", "blinkMin", "0.2", 0.05, 10)
    NumberInput(page, "Blink maksimum", "Detik (0.05-10).", "blinkMax", "0.5", 0.05, 10)

    AddSection(page, "Lainnya")
    AddSwitch(page, "Tombol P melayang", "Tombol P untuk buka/tutup menu.",
        function() return Config.launcher end,
        function(on)
            Config.launcher = on
            SaveConfig()
            if hub.launcher then
                hub.launcher.Visible = on
            end
        end)
    AddButton(page, "Tutup Menu", "danger", function()
        hub.close()
    end)
end

local function HelpEntries()
    local p = Config.prefix
    return {
        { p .. "wld <jumlah> | " .. p .. "wd", "Drop World Lock" },
        { p .. "tp <world> | " .. p .. "warp", "Pindah ke world lain" },
        { p .. "pos1 | pos2", "Simpan posisi sekarang" },
        { p .. "win1 | w1 [jumlah]", "Teleport ke Pos 1, opsional langsung drop" },
        { p .. "win2 | w2 [jumlah]", "Teleport ke Pos 2, opsional langsung drop" },
        { p .. "pos", "Lihat posisi sekarang & pos tersimpan" },
        { p .. "rejoin | rj", "Masuk ulang ke world ini" },
        { p .. "noclip [on/off]", "Tembus blok & terbang" },
        { p .. "uj", "Lompat di udara tanpa batas" },
        { p .. "blink [on/off]", "Warna skin berganti otomatis" },
        { p .. "lh [n|off]", "Jangkauan punch & build lebih jauh" },
        { p .. "vi", "GUI item visual" },
        { p .. "sgb", "Buka/tutup menu Setelan" },
        { p .. "afk", "Anti-AFK" },
        { p .. "arj", "Rejoin otomatis kalau terputus" },
        { p .. "sesi", "Buka tab Sesi" },
        { p .. "af [on/off]", "Buka / jalankan Auto Farm" },
        { p .. "ctp [on/off]", "Click TP" },
        { p .. "ac [on/off]", "Auto Clear World" },
        { p .. "acmode <walk|tp>", "Mode Auto Clear" },
        { p .. "acpunch <1-3>", "Block per pukulan" },
        { p .. "df [on/off]", "Auto Dirt Farm" },
        { p .. "dirtid <id|nama>", "Block dirt untuk Dirt Farm" },
        { p .. "mv <walk|tp|fly|mix>", "Mode gerak" },
        { p .. "spam [on/off]", "Kirim teks spam berulang" },
        { p .. "setspam <teks>", "Atur teks spam" },
        { p .. "hn <off|self|all>", "Sembunyikan nama (lokal)" },
        { p .. "bid <id,id,...>", "Pecahkan block ID tertentu" },
        { p .. "aq [on/off|scan]", "Auto quest" },
        { p .. "gs", "Buka GrowScan" },
        { p .. "god [on/off]", "God mode" },
        { p .. "blockid <nama>", "Cari ID block dari nama" },
        { p .. "hpx", "Buka/tutup daftar fitur ini" },
    }
end

local function BuildHelp(page)
    AddNote(page, "Semua command Peex HUB. Fitur on/off: ketik tanpa argumen untuk toggle.")
    for _, e in ipairs(HelpEntries()) do
        local card = AddCard(page, 52)
        Label(card, {
            Text = e[1],
            Font = Enum.Font.Code,
            TextColor3 = C.accent2,
            TextSize = 12,
            Position = UDim2.fromOffset(12, 7),
            Size = UDim2.new(1, -24, 0, 16),
            TextWrapped = false,
        })
        Label(card, {
            Text = e[2],
            TextColor3 = C.mute,
            TextSize = 11,
            Position = UDim2.fromOffset(12, 25),
            Size = UDim2.new(1, -24, 0, 24),
            TextYAlignment = Enum.TextYAlignment.Top,
        })
    end
end

-- Daftar builder: id tab -> fungsi. Setiap builder boleh mengembalikan fungsi update.
local BUILDERS = {
    features = BuildFeatures,
    farm = BuildFarm,
    clear = BuildClear,
    dirt = BuildDirt,
    breakid = BuildBreakId,
    spam = BuildSpam,
    hidden = BuildHidden,
    nav = BuildNav,
    quest = BuildQuest,
    scan = BuildScan,
    pos = BuildPos,
    visual = BuildVisual,
    session = BuildSession,
    settings = BuildSettings,
    help = BuildHelp,
}

local TAB_ORDER = {
    { id = "features", label = "Fitur", icon = "Ft" },
    { id = "farm", label = "Auto Farm", icon = "Fm" },
    { id = "clear", label = "Auto Clear", icon = "Cl" },
    { id = "dirt", label = "Dirt Farm", icon = "Df" },
    { id = "breakid", label = "Break ID", icon = "Id" },
    { id = "spam", label = "Spam", icon = "Sp" },
    { id = "hidden", label = "Hidden Name", icon = "Hn" },
    { id = "nav", label = "Click TP", icon = "TP" },
    { id = "quest", label = "Auto Quest", icon = "Qs" },
    { id = "scan", label = "GrowScan", icon = "Sc" },
    { id = "pos", label = "Posisi", icon = "Ps" },
    { id = "visual", label = "Visual", icon = "Vs" },
    { id = "session", label = "Sesi", icon = "Ss" },
    { id = "settings", label = "Setelan", icon = "St" },
    { id = "help", label = "Bantuan", icon = "?" },
}

-- Bangun halaman hanya saat pertama kali dibuka
local function EnsureBuilt(id)
    if hub.built[id] then
        return
    end
    hub.built[id] = true
    local page = hub.pages[id]
    local ok, updater = pcall(BUILDERS[id], page)
    if not ok then
        AddNote(page, "Gagal memuat halaman: " .. tostring(updater))
        updater = nil
    end
    hub.updaters[id] = (type(updater) == "function") and updater or nil
end

local function SwitchTab(id)
    hub.active = id
    EnsureBuilt(id)
    for tid, page in pairs(hub.pages) do
        page.Visible = (tid == id)
    end
    for tid, tab in pairs(hub.tabBtns) do
        local on = tid == id
        tab.btn.BackgroundTransparency = on and 0 or 1
        tab.lbl.TextColor3 = on and C.text or C.mute
        tab.bar.Visible = on
    end
    local up = hub.updaters[id]
    if up then
        pcall(up)
    end
end

-- Bangun ulang satu halaman (dipakai saat setelan berubah)
function hub.invalidate(id)
    local page = hub.pages[id]
    if not page then
        return
    end
    hub.refresh[page] = nil
    for _, child in ipairs(page:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
    orders[page] = 0
    hub.built[id] = false
    hub.updaters[id] = nil
    if hub.active == id then
        SwitchTab(id)
    end
end

local function CloseHub()
    local frame = hub.frame
    if not frame then
        return
    end
    for _, c in ipairs(hub.conns) do
        c:Disconnect()
    end
    hub.conns = {}
    hub.frame = nil
    hub.active = nil
    frame:Destroy()
    hub.pages, hub.built, hub.updaters, hub.refresh, hub.tabBtns = {}, {}, {}, {}, {}
end
hub.close = CloseHub

local function OpenHub(tabId)
    if hub.frame then
        SwitchTab(tabId)
        return
    end

    local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 600)
    local width = math.clamp(viewport.X - 20, 300, 560)
    local height = math.clamp(viewport.Y - 40, 270, 400)
    local sideW = (width < 440) and 52 or 124
    hub.narrow = width < 440

    local frame = New("Frame", {
        Name = "Hub",
        Size = UDim2.fromOffset(width, height),
        Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2),
        BackgroundColor3 = C.window,
        BorderSizePixel = 0,
        Active = true,
    }, GetGui())
    Corner(frame, 14)
    hub.frame = frame
    hub.conns = {}
    hub.pages, hub.built, hub.updaters, hub.refresh, hub.tabBtns = {}, {}, {}, {}, {}

    -- Header
    local header = New("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
    }, frame)
    Label(header, {
        Text = "PEEX HUB",
        Font = CARTOON_FONT,
        TextSize = 19,
        TextColor3 = C.accent,
        Position = UDim2.fromOffset(16, 0),
        Size = UDim2.fromOffset(110, 44),
        TextWrapped = false,
    })
    Label(header, {
        Text = "GrowBlox",
        TextColor3 = C.mute,
        TextSize = 11,
        Position = UDim2.fromOffset(120, 3),
        Size = UDim2.fromOffset(100, 44),
        TextWrapped = false,
    })
    local closeBtn = MakeButton(header, "X", "danger", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        TextSize = 12,
    })
    closeBtn.MouseButton1Click:Connect(CloseHub)
    local minBtn = MakeButton(header, "-", "ghost", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -46, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        TextSize = 14,
    })
    MakeDraggable(header, frame)

    -- Sidebar & panel
    local sidebar = New("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 50),
        Size = UDim2.new(0, sideW - 8, 1, -58),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, frame)
    New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)

    local panel = New("Frame", {
        Position = UDim2.fromOffset(sideW, 50),
        Size = UDim2.new(1, -(sideW + 8), 1, -58),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
    }, frame)
    Corner(panel, 10)

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        sidebar.Visible = not minimized
        panel.Visible = not minimized
        minBtn.Text = minimized and "+" or "-"
        frame.Size = UDim2.fromOffset(width, minimized and 46 or height)
    end)

    for index, tab in ipairs(TAB_ORDER) do
        local btn = New("TextButton", {
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = C.cardHi,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = index,
        }, sidebar)
        Corner(btn, 8)
        local bar = New("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(3, 18),
            BackgroundColor3 = C.accent2,
            BorderSizePixel = 0,
            Visible = false,
        }, btn)
        local lbl = Label(btn, {
            Text = hub.narrow and tab.icon or tab.label,
            Font = CARTOON_FONT,
            TextSize = hub.narrow and 14 or 12,
            TextColor3 = C.mute,
            TextXAlignment = hub.narrow and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,
            Position = hub.narrow and UDim2.fromOffset(0, 0) or UDim2.fromOffset(12, 0),
            Size = hub.narrow and UDim2.fromScale(1, 1) or UDim2.new(1, -14, 1, 0),
            TextWrapped = false,
        })
        btn.MouseButton1Click:Connect(function()
            SwitchTab(tab.id)
        end)
        hub.tabBtns[tab.id] = { btn = btn, lbl = lbl, bar = bar }

        local page = New("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = C.stroke,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
        }, panel)
        New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
            PaddingTop = UDim.new(0, 10),
            PaddingBottom = UDim.new(0, 10),
        }, page)
        hub.pages[tab.id] = page
    end

    -- Satu loop update saja, untuk tab aktif. Berhenti otomatis saat menu ditutup.
    local owner = frame
    task.spawn(function()
        while hub.frame == owner do
            task.wait(0.5)
            local up = hub.active and hub.updaters[hub.active]
            if up then
                pcall(up)
            end
        end
    end)

    SwitchTab(tabId)
end

local function ToggleHub(tabId)
    if hub.frame and hub.active == tabId then
        CloseHub()
    else
        OpenHub(tabId)
    end
end

-- Tombol P melayang. Buka menu hanya jika di-tap (gerak > 8 px dianggap geser).
local function BuildLauncher()
    local holder = New("TextButton", {
        Name = "Launcher",
        Size = UDim2.fromOffset(44, 44),
        Position = UDim2.new(0, 12, 0.5, -22),
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "P",
        TextColor3 = Color3.new(1, 1, 1),
        Font = CARTOON_FONT,
        TextSize = 20,
        Visible = Config.launcher,
        ZIndex = 50,
    }, GetGui())
    Corner(holder, 22)
    hub.launcher = holder

    local dragging, moved = false, false
    local startInput, startPos = nil, nil

    holder.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            startInput = input.Position
            startPos = holder.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - startInput
            if d.Magnitude > 8 then
                moved = true
            end
            if moved then
                holder.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if not moved then
                if hub.frame then
                    CloseHub()
                else
                    OpenHub("features")
                end
            end
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
        local map = { walk = "walk", jalan = "walk", tp = "tp", teleport = "tp", fly = "fly", terbang = "fly", mix = "mix", campur = "mix" }
        if map[m] then
            Config.moveMode = map[m]
            SaveConfig()
            Notify("Mode gerak: " .. map[m])
        else
            Notify("Mode gerak sekarang: " .. tostring(Config.moveMode) .. ". Pakai: move walk | tp | fly | mix")
        end
        return true

    elseif command == "hiddenname" or command == "hn" then
        local map = { off = "off", mati = "off", self = "self", sendiri = "self", all = "all", semua = "all" }
        if map[args] then
            HiddenName.SetMode(map[args])
        else
            Notify("Hidden Name sekarang: " .. Config.hiddenNameMode .. ". Pakai: hiddenname off | self | all")
        end
        return true

    elseif command == "breakid" or command == "bid2" or command == "autobreak" then
        if args == "off" then
            SetFeature("breakid", false)
        elseif Trim(rawArgs or "") ~= "" then
            SetFeature("breakid", false) -- hentikan sesi lama sebelum ganti ID
            BreakId.Start(rawArgs)
            if RefreshHub then RefreshHub() end
        else
            SetFeature("breakid", WantedState(args, BreakId.on))
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

    elseif command == "acpunch" or command == "punch" then
        local n = tonumber(args)
        if n and n >= 1 and n <= 3 then
            Config.clearPunch = math.floor(n)
            SaveConfig()
            Notify("Punch Auto Clear: " .. Config.clearPunch .. " block")
        else
            Notify("Punch Auto Clear sekarang: " .. tostring(Config.clearPunch) .. " block. Pakai: acpunch 1 | 2 | 3")
        end
        if RefreshHub then RefreshHub() end
        return true

    elseif command == "dirtfarm" or command == "df" or command == "dirt" then
        if args == "on" or args == "start" then
            SetFeature("dirtfarm", true)
        elseif args == "off" or args == "stop" then
            SetFeature("dirtfarm", false)
        else
            ToggleHub("dirt")
        end
        return true

    elseif command == "dirtid" then
        local query = Trim(rawArgs or "")
        if query == "" then
            local id = DirtFarm.ResolveId and DirtFarm.ResolveId()
            Notify("Block dirt sekarang: " .. (id and (ItemName(id) .. " (ID " .. id .. ")") or "belum ketemu")
                .. ". Pakai: " .. Config.prefix .. "dirtid <id atau nama>")
        else
            local found = SearchItems(query, 1)[1]
            if found then
                Config.dirtId = found.id
                SaveConfig()
                Notify("Block dirt: " .. found.name .. " (ID " .. found.id .. ")")
            else
                Notify("Block tidak ditemukan: " .. query)
            end
        end
        return true

    elseif command == "acmode" or command == "clearmode" then
        local m = (args or ""):lower()
        local map = { walk = "walk", jalan = "walk", tp = "teleport", teleport = "teleport" }
        if map[m] then
            Config.clearMode = map[m]
            SaveConfig()
            Notify("Mode Auto Clear: " .. map[m])
        else
            Notify("Mode Auto Clear sekarang: " .. tostring(Config.clearMode) .. ". Pakai: acmode walk | tp")
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
            -- command yang diketik lewat kotak ini = kotak chat game (dipakai fitur Spam)
            local trimmed = Trim(text)
            if trimmed ~= "" and ((Config.prefix ~= "" and trimmed:sub(1, #Config.prefix) == Config.prefix)
                or trimmed:sub(1, 1) == "/") then
                if not Spam.guardText or trimmed:lower() ~= Spam.guardText then
                    Spam.chatBox = box
                end
            end
            Process(text)
        end
    end)
end

for _, descendant in ipairs(PlayerGui:GetDescendants()) do
    HookTextBox(descendant)
end
PlayerGui.DescendantAdded:Connect(HookTextBox)

Player.Chatted:Connect(Process)

BuildLauncher()

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
    Notify("Peex HUB v13 loaded! Tekan tombol P atau ketik " .. Config.prefix .. "hpx.")
else
    Notify("Loaded, tapi inventory game belum ditemukan (cek executor).")
end
