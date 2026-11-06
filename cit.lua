-- Unpacked by ZeroVector: the script inside the packed file, as it was written
--[[
    Fian792  v1.2  (untuk Growblox versi ByteNet, game v1084)
    Script tester Growtopia (Roblox) dengan UI WindUI.

    Fitur:
      - Auto Farm   : place block di tile pilihan (Grid 5x5), lalu break (multi target / Rayman)
      - Clear World : bersihkan world dari baris atas ke bawah, jalan pakai A*
      - Farmer      : panen pohon yang sudah siap + tanam seed otomatis
      - Auto Chat   : kirim beberapa pesan bergantian
      - Misc        : walkspeed, infinite jump, fly
      - Staff       : buka backpack staff & pilih title (dikunci server)
      - Penjaga     : deteksi Mod / Dev / pemain masuk world -> diam / keluar world,
                      lalu masuk lagi & lanjut aktivitas setelah aman
      - Bonus       : auto claim quest & auto redeem code
      - Growscan    : daftar Floating Items, World Blocks & pohon siap panen
      - Splice      : tanam Seed A lalu splice Seed B, keliling world pakai A* (atau tile Grid)
      - Lahan       : bangun farm world (baris block + tangga zig-zag), hitung & produksi block dulu
      - Pabrik      : break -> tanam -> panen -> break, seed lebihan di-drop (bisa ke world lain)
      - Statistik   : gems / block / drop per jam selama sesi
      - Tas         : auto recycle item sampah & auto convert lock
      - Discord     : notifikasi ke webhook (Penjaga, berhenti, penuh, bonus, laporan)
      - Reconnect   : masuk lagi kalau terlempar / disconnect / di luar world, rejoin manual, lalu lanjut
      - Config      : pengaturan tersimpan otomatis & dimuat saat execute
      - Watermark   : nama Fian792 beranimasi (selalu aktif, hanya di layar sendiri)
      - Bahasa      : pilih Indonesia / English saat execute (bisa diganti di tab Koneksi)

    Catatan:
      - Semua aksi pakai fungsi asli game (place, pukul, ambil drop), bukan klik layar.
      - Auto collect cek tiap frame & ambil semua drop sekaligus (paralel).
      - Server menolak fly / noclip / infinite jump, jadi Clear & Farmer selalu jalan menapak.
        Kalau tidak ada pijakan, script menaruh block dari inventori.
]]

---------------------------------------------------------------------
-- SESI: jalankan ulang script = sesi lama dibersihkan dulu
---------------------------------------------------------------------
local G = (getgenv and getgenv()) or _G
for _, key in ipairs({ "__Alfian", "__GTFarm" }) do -- __GTFarm = nama versi lama
    if G[key] and G[key].Cleanup then pcall(G[key].Cleanup) end
    G[key] = nil
end
local Session = {}
G.__Alfian = Session
local function alive()
    return G.__Alfian == Session
end

---------------------------------------------------------------------
-- SERVICES & MODULE GAME
---------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldRemotes = ReplicatedStorage:WaitForChild("WorldRemotes")
-- Remote lama (versi game sebelum ByteNet). Hanya dipakai kalau fungsi baru tidak ada.
local SetTileRemote = WorldRemotes:FindFirstChild("SetTile")

local ItemDB = require(Shared.ItemDB)
local InventoryModule = require(Shared.Inventory)
local NetOk, Net = pcall(require, Shared.Net)

local GameGui = PlayerGui:WaitForChild("GameGui")
local ParticlesOk, ParticlesModule = pcall(require, GameGui:WaitForChild("Particles"))
local MenuModOk, MenuModule = pcall(require, GameGui:WaitForChild("WorldMenu"))
local RolesOk, RolesModule = pcall(require, Shared:FindFirstChild("Roles"))
local SfxOk, SfxModule = pcall(require, Shared:FindFirstChild("Sfx"))

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

---------------------------------------------------------------------
-- PENGATURAN & DATA
---------------------------------------------------------------------
local State = {
    Running = false,
    Mode = "Place + Break",       -- "Place + Break" | "Break saja" | "Place saja"
    PlaceMs = 250,                -- jeda setelah tiap place
    BreakMs = 220,                -- jeda tiap pukulan (normal 220)
    AfterBreakMs = 300,           -- jeda setelah block hancur
    HitsOverride = 0,             -- jumlah pukulan manual (0 = otomatis)
    BreakBackground = true,       -- selalu ikut pecah background (tanpa tombol)
    MultiTarget = 1,              -- jumlah tile dipukul bergantian (1 = biasa)
    SelectedId = nil,
    Offsets = {},                 -- tile yang dipilih di Grid
    CalibX = 0,
    CalibY = 0,
    AntiAfk = true,
    MutePunch = true,
    LiteMode = false,
    Role = "none",
    AutoCollect = true,           -- ambil drop di tile yang dipilih
    CollectAround = false,        -- ambil drop di sekitar karakter (radius) kapan saja
    CollectRadius = 3,            -- jari-jari collect (tile)
    Override = nil,               -- Pabrik memakai tile & block sendiri
    Quiet = false,                -- tanpa notifikasi (dipakai Pabrik)
    Cycles = 0,
    Placed = 0,
    Broken = 0,
    Collected = 0,                -- jumlah drop yang diambil
    CollectFail = 0,              -- jumlah drop yang ditolak server
    LastAction = "-",
}

local Misc = {
    Speed = 100,      -- walkspeed % (100 = normal)
    InfJump = false,
    Ghost = false,    -- fly + tembus block
    UpHeld = false,   -- tombol ▲ di layar ditahan
    DownHeld = false, -- tombol ▼ di layar ditahan
    CustomName = true,          -- watermark nama (selalu aktif, mati hanya saat script ditutup)
    NameText = "Fian792",  -- teks watermark
}

-- Auto Clear World
local Clear = {
    Running = false,
    IncludeBg = true,         -- ikut pecah background
    UseBlock = true,          -- taruh block kalau tidak ada pijakan
    ScaffoldId = nil,         -- block yang dipakai untuk pijakan
    Collect = true,           -- ambil drop tiap habis pecah
    Sweep = "Kiri → Kanan",   -- "Kiri → Kanan" atau "Zig-zag"
    Skip = {},                -- tile yang dilewati sementara
    TopRow = -1,              -- baris yang sedang dibersihkan
    DirRow = nil,             -- arah zig-zag untuk baris ini
    Dir = nil,
    Broken = 0,
    Remaining = -1,
    Status = "-",
}

-- Auto Splice: tanam Seed A lalu splice Seed B
local Splice = {
    Running = false,
    Roam = true,        -- keliling world pakai A* (false = hanya tile Grid)
    Roaming = false,
    A = nil,
    B = nil,
    Ms = 300,
    Made = 0,
    Planted = 0,
    Fail = {},
    Skip = {},
    Status = "-",
}

-- Lahan (farm world): baris block dari atas ke bawah
local Land = {
    X0 = 0, X1 = 99,  -- kolom awal & akhir
    Y0 = 2,           -- baris block paling atas
    Gap = 2,          -- jarak antar baris (2 = ada 1 tile kosong untuk pohon)
    Rows = 10,        -- jumlah baris
    Stairs = true,    -- ujung baris dibuka bergantian kiri/kanan (jalan naik-turun seperti tangga)
}

-- Bangun Lahan
local Build = {
    Running = false,
    BlockId = nil,
    UseBlock = true,     -- boleh taruh block pijakan kalau baris pertama tidak terjangkau
    Produce = true,      -- block kurang -> produksi dulu (tanam & panen) sampai cukup
    ThenPabrik = false,  -- selesai -> langsung jalankan Pabrik
    Placed = 0,
    Phase = "-",
    Status = "-",
    Skip = {},
}

-- Pabrik: break block -> tanam seed -> panen -> break lagi, seed lebihan di-drop
local Pabrik = {
    Running = false,
    SeedId = nil,
    BlockId = nil,
    WholeWorld = false,  -- tanam & panen di seluruh world (bukan hanya lahan)
    Tiles = {},          -- tile break, relatif ke posisi break ("dx,dy")
    BreakX = -1, BreakY = -1,
    BreakSec = 60,       -- lama 1 sesi break sebelum cek pohon lagi
    Drop = true,
    Keep = 50,           -- seed yang disisakan untuk ditanam lagi
    DropAt = 200,        -- drop kalau seed sudah sebanyak ini
    DropWorld = "",      -- "" = world ini | "WORLD" | "WORLD:ID"
    DropX = -1, DropY = -1,
    Harvested = 0,
    Planted = 0,
    Dropped = 0,
    Skip = {},
    Status = "-",
    Traveling = false,
    Home = "",
    Zone = nil,          -- tempat drop (tidak ikut di-collect)
}

local Guard = {
    On = false,
    Who = "Staff (Mod/Dev)",   -- "Staff (Mod/Dev)" | "Semua pemain"
    StopAll = true,            -- diam semua aktivitas
    Leave = false,             -- keluar world
    AutoBack = true,           -- lanjut lagi setelah aman
    BackSec = 60,              -- (keluar world) tunggu sebelum masuk lagi
    CalmSec = 5,               -- (diam) tunggu sepi dulu sebelum lanjut
    Mode = "idle",             -- idle | pause | away | out | back
    Allow = {},                -- pemain biasa yang sudah ada saat Penjaga dinyalakan (diabaikan)
    Alerted = {},              -- sudah diberi peringatan
    Saved = nil,               -- aktivitas sebelum dihentikan
    Token = 0,
    BackAt = 0,
    CalmAt = nil,
    LeftFg = nil,
    BackText = nil,
    Status = "Mati",
    Detected = 0,
}

-- Farmer: panen & tanam otomatis
local Farmer = {
    Running = false,
    Harvest = true,
    Plant = true,
    Collect = true,
    UseBlock = false,   -- taruh block kalau tidak ada jalan
    ScaffoldId = nil,
    HarvestMs = 250,    -- jeda setelah tiap panen
    PlantMs = 250,      -- jeda setelah tiap tanam
    SeedId = nil,
    Skip = {},
    Harvested = 0,
    Planted = 0,
    Status = "-",
}

-- Tombol gerak buatan (dipakai Clear & Farmer)
local AutoInput = { active = false, left = false, right = false, jump = false, down = false }

-- Auto Chat
local Spam = {
    On = false,
    Texts = {},         -- daftar pesan, dikirim bergantian
    IntervalSec = 6,
    Index = 1,
    Sent = 0,
    Last = "-",
}

local Refs = {
    World = nil,      -- data world (fg, bg, ukuran)
    Inv = nil,        -- inventori
    SetTile = nil,    -- fungsi place game
    State = nil,      -- posisi karakter
    Punch = nil,      -- fungsi pukul game
    Particles = {},   -- particle (untuk mode Lite)
    Menu = nil,       -- menu game (untuk Staff)
    Gems = nil,       -- update angka gems
    Hud = nil,        -- jangkauan pukul & place
    Trees = nil,      -- data pohon (waktu tanam)
    Others = nil,     -- daftar pemain lain di world (untuk Penjaga)
}

-- Daftar drop di world (diambil dari game)
local Drops = { list = nil, update = nil }
local DropFailUntil = {}   -- drop yang ditolak, dicoba lagi nanti

local UI = {}
local Connections = {}
local HitCount = {}   -- hitung pukulan (cadangan)
local PlacedAt = {}   -- kapan tile di-place

---------------------------------------------------------------------
-- BAHASA (Indonesia / English)
---------------------------------------------------------------------
-- Cara kerja:
--   - Semua teks script ditulis dalam Bahasa Indonesia.
--   - Kalau English dipilih, I18N.T(teks) menerjemahkan:
--       1. teks utuh (judul & deskripsi menu) dari daftar EN
--       2. teks yang berubah-ubah (status, notifikasi) per frasa dari daftar PH
--   - Menu WindUI dibungkus (I18N.wrap) supaya judul, deskripsi & isi status ikut diterjemahkan.
local I18N = { Lang = "id", Saved = "id", Ask = true }

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local

I18N.EN = {
    -- grup sidebar & tab
    ["Fitur"] = "Features", ["Keamanan"] = "Security", ["Setelan"] = "Setup",
    ["Pengaturan"] = "Settings", ["Penjaga"] = "Guard", ["Statistik"] = "Stats", ["Tas"] = "Bag",
    ["Lahan"] = "Land", ["Pabrik"] = "Factory", ["Koneksi"] = "Connection",
    -- kotak
    ["Kontrol"] = "Controls", ["Mode & Kecepatan"] = "Mode & Speed", ["Kecepatan"] = "Speed",
    ["Karakter"] = "Character", ["Opsi"] = "Options", ["Pesan"] = "Messages",
    ["Aksi saat terdeteksi"] = "Action when detected", ["Waktu"] = "Timing", ["Lainnya"] = "Other",
    ["Quest Harian"] = "Daily Quests", ["Pohon (siap panen)"] = "Trees (ready to harvest)",
    ["Auto Recycle (buang item)"] = "Auto Recycle (trash items)", ["Bentuk lahan"] = "Land shape",
    ["Pilihan"] = "Options", ["Posisi & tile break"] = "Break position & tiles",
    ["Koreksi posisi"] = "Position correction", ["Yang dikirim"] = "What to send",
    -- Farm
    ["Bisa juga lewat tombol START di Grid"] = "Can also use the START button in the Grid",
    ["Ambil drop di tile yang dipilih"] = "Pick up drops on the selected tiles",
    ["Collect di sekitar karakter"] = "Collect around character",
    ["Ambil semua drop dalam radius, kapan saja"] = "Pick up all drops within the radius, anytime",
    ["Radius collect (tile)"] = "Collect radius (tiles)",
    ["Dipakai juga Clear, Farmer, Splice & Pabrik. Terlalu jauh bisa ditolak server"] =
        "Also used by Clear, Farmer, Splice & Factory. Too far may be rejected by the server",
    ["Buka Grid Tile"] = "Open Tile Grid",
    ["Kotak 5x5, tengah = karakter"] = "5x5 grid, center = character",
    -- Clear
    ["Status Clear"] = "Clear Status",
    ["Bersihkan dari baris atas ke bawah"] = "Clear from the top row down",
    ["Arah sapu"] = "Sweep direction",
    ["Zig-zag lebih cepat (tidak balik ke kiri)"] = "Zig-zag is faster (no going back left)",
    ["Pakai block pijakan"] = "Use scaffold blocks",
    ["Taruh block untuk lewat jurang / naik ke block melayang"] = "Place blocks to cross gaps / reach floating blocks",
    ["Block pijakan"] = "Scaffold block",
    ["Block yang dipakai untuk pijakan"] = "Block used as scaffold",
    ["Auto collect tiap habis pecah"] = "Auto collect after each break",
    ["Ambil drop di sekitar karakter"] = "Pick up drops around the character",
    ["Reset tile yang dilewati"] = "Reset skipped tiles",
    ["Coba lagi tile yang tadi gagal"] = "Retry tiles that failed",
    -- Farmer
    ["Status Farmer"] = "Farmer Status",
    ["Jalankan Farmer"] = "Run Farmer",
    ["Panen pohon siap & tanam seed otomatis"] = "Harvest ready trees & plant seeds automatically",
    ["Seed untuk ditanam"] = "Seed to plant",
    ["Hanya seed yang ada di inventori"] = "Only seeds in your inventory",
    ["Refresh daftar seed"] = "Refresh seed list",
    ["Hanya pohon yang sudah siap"] = "Only trees that are ready",
    ["Tanam di atas block yang kosong"] = "Plant on top of empty blocks",
    ["Ambil hasil panen di sekitar karakter"] = "Pick up harvest drops around the character",
    ["Jeda setelah tiap panen"] = "Delay after each harvest",
    ["Jeda setelah tiap tanam seed"] = "Delay after each seed planted",
    ["Taruh block kalau tidak ada jalan (block tetap tertinggal)"] = "Place blocks when there is no path (blocks stay behind)",
    -- Speed & opsi
    ["Place semua tile dulu, lalu break"] = "Place all tiles first, then break",
    ["Jeda setelah tiap place"] = "Delay after each place",
    ["Jeda tiap pukulan (normal 220). Dipakai juga Clear"] = "Delay per hit (normal 220). Also used by Clear",
    ["Auto Farm: tile dipukul bergantian (seperti 2 jari). Pakai Rayman's Fist = 2-3 tile segaris sekali pukul"] =
        "Auto Farm: tiles are hit in turns (like 2 fingers). With Rayman's Fist = 2-3 tiles in a line per punch",
    ["Jeda setelah hancur (ms)"] = "Delay after break (ms)",
    ["Tunggu sebelum lanjut ke tile berikutnya"] = "Wait before moving to the next tile",
    ["Mode Lite"] = "Lite Mode",
    ["Matikan particle & suara (HP low-end)"] = "Turn off particles & sounds (low-end phones)",
    ["Mute suara pukulan"] = "Mute punch sounds",
    ["Pukulan per block (cadangan)"] = "Hits per block (fallback)",
    ["Dipakai kalau 'Pukul: TIDAK'. 0 = otomatis"] = "Used when 'Punch: NO'. 0 = automatic",
    ["Pilih Block"] = "Select Block",
    ["Hanya item yang bisa di-place"] = "Only placeable items",
    ["Refresh daftar"] = "Refresh list",
    ["Lompat di udara (bisa kena rollback)"] = "Jump mid-air (may get rolled back)",
    ["Fly + Tembus Block"] = "Fly + Noclip",
    ["Tembus block, pakai tombol ▲/▼ (bisa kena rollback)"] = "Pass through blocks, use the ▲/▼ buttons (may get rolled back)",
    ["Bahasa / Language"] = "Language / Bahasa",
    ["Ganti bahasa, lalu execute ulang"] = "Change language, then re-execute",
    -- Chat
    ["Status Chat"] = "Chat Status",
    ["Daftar pesan"] = "Message list",
    ["Pisahkan dengan |   contoh: halo|jual dirt"] = "Separate with |   example: hi|selling dirt",
    ["pesan 1|pesan 2|pesan 3"] = "message 1|message 2|message 3",
    ["Interval (detik)"] = "Interval (seconds)",
    ["Jeda antar pesan (min 3 detik)"] = "Delay between messages (min 3 seconds)",
    ["Kirim pesan bergantian sesuai urutan"] = "Send messages in order, one after another",
    ["Kirim 1 pesan sekarang"] = "Send 1 message now",
    ["Tes kirim pesan berikutnya"] = "Test sending the next message",
    ["Isi daftar pesan dulu (tekan Enter setelah mengetik)"] = "Fill in the message list first (press Enter after typing)",
    -- Staff
    ["Buka Staff Backpack"] = "Open Staff Backpack",
    ["UI staff bawaan game (dikunci server)"] = "Game's built-in staff UI (locked by server)",
    ["Title yang kamu punya"] = "Titles you own",
    ["Refresh daftar role"] = "Refresh role list",
    ["Pakai Role"] = "Use Role",
    ["Sama seperti menu Title game"] = "Same as the game's Title menu",
    ["Menu game belum ketemu. Tekan 'Hubungkan ke game' dulu"] = "Game menu not found. Press 'Connect to game' first",
    ["Fungsi PickTitle tidak ada"] = "PickTitle function not found",
    -- Penjaga
    ["Status Penjaga"] = "Guard Status",
    ["Mati"] = "Off",
    ["Aktifkan Penjaga"] = "Enable Guard",
    ["Pantau Mod / Dev / pemain yang masuk world"] = "Watch for Mods / Devs / players entering the world",
    ["Yang dideteksi"] = "Detect",
    ["Semua pemain: yang sudah ada saat dinyalakan diabaikan"] = "All players: those already here when enabled are ignored",
    ["Diam semua aktivitas"] = "Pause all activities",
    ["Keluar world"] = "Leave world",
    ["Langsung keluar world saat terdeteksi"] = "Leave the world immediately when detected",
    ["Lanjut otomatis setelah aman"] = "Auto resume when safe",
    ["Keluar world: masuk lagi, cek, lalu lanjut aktivitas sebelumnya"] = "Leave world: rejoin, check, then resume previous activity",
    ["Masuk world lagi setelah (detik)"] = "Rejoin world after (seconds)",
    ["Untuk mode keluar world"] = "For leave-world mode",
    ["Tunggu aman (detik)"] = "Safe wait (seconds)",
    ["Untuk mode diam: jeda setelah mereka pergi"] = "For pause mode: delay after they leave",
    ["Abaikan pemain yang ada sekarang"] = "Ignore players here now",
    ["Untuk teman / akun sendiri (staff tetap dideteksi)"] = "For friends / alt accounts (staff are still detected)",
    ["Batalkan tunggu / lanjut"] = "Cancel wait / resume",
    ["Hentikan proses keluar-masuk & lanjut otomatis"] = "Stop the leave-rejoin process & auto resume",
    ["Dibatalkan"] = "Cancelled",
    -- Bonus
    ["Klaim hadiah quest yang sudah selesai"] = "Claim rewards for finished quests",
    ["Cek quest sekarang"] = "Check quests now",
    ["Tukar semua code aktif yang belum dipakai"] = "Redeem all active codes not used yet",
    ["Cek code sekarang"] = "Check codes now",
    ["Redeem code manual"] = "Redeem code manually",
    ["Ketik code lalu tekan Enter"] = "Type a code then press Enter",
    ["KODE"] = "CODE",
    -- Growscan
    ["Info World"] = "World Info",
    ["Tekan Scan sekarang"] = "Press Scan now",
    ["Update otomatis tiap 2 detik"] = "Auto update every 2 seconds",
    ["Scan sekarang"] = "Scan now",
    ["Cari item"] = "Search item",
    ["Saring nama item (kosongkan = semua)"] = "Filter item name (empty = all)",
    ["contoh: seed"] = "example: seed",
    ["Daftar"] = "List",
    -- Statistik
    ["Sesi ini"] = "This session",
    ["Reset statistik"] = "Reset stats",
    ["Mulai hitung dari nol"] = "Start counting from zero",
    ["Kirim ke Discord sekarang"] = "Send to Discord now",
    ["Perlu webhook di tab Discord"] = "Needs a webhook in the Discord tab",
    ["Aktifkan webhook Discord dulu"] = "Enable the Discord webhook first",
    ["Direset"] = "Reset",
    ["Masuk antrian kirim"] = "Added to send queue",
    -- Tas
    ["Item yang dipilih di-recycle otomatis"] = "Selected items are recycled automatically",
    ["Item yang di-recycle"] = "Items to recycle",
    ["Bisa pilih banyak. Tool & lock tidak ditampilkan"] = "Multiple allowed. Tools & locks are not shown",
    ["Recycle kalau jumlah >="] = "Recycle when amount >=",
    ["200 = hanya saat penuh 1 slot"] = "200 = only when a slot is full",
    ["Sisakan"] = "Keep",
    ["Jumlah yang tidak ikut di-recycle"] = "Amount not recycled",
    ["Refresh daftar item"] = "Refresh item list",
    ["100 WL -> 1 DL, 100 DL -> 1 BGL (sama seperti game)"] = "100 WL -> 1 DL, 100 DL -> 1 BGL (same as the game)",
    -- Splice
    ["Status Splice"] = "Splice Status",
    ["Tanam Seed A lalu splice Seed B"] = "Plant Seed A then splice Seed B",
    ["Seed A (ditanam)"] = "Seed A (planted)",
    ["Seed B (di-splice)"] = "Seed B (spliced)",
    ["Keliling world (A*)"] = "Roam world (A*)",
    ["Nyala: jalan ke seluruh world. Mati: hanya tile Grid 5x5"] = "On: walk the whole world. Off: only the 5x5 Grid tiles",
    ["Jeda tanam / splice (ms)"] = "Plant / splice delay (ms)",
    -- Lahan
    ["Status Lahan"] = "Land Status",
    ["Bangun Lahan"] = "Build Land",
    ["Hitung block, produksi kalau kurang, lalu pasang dari baris bawah"] = "Count blocks, produce if short, then place from the bottom row",
    ["Block lahan"] = "Land block",
    ["Block padat dari inventori"] = "Solid block from inventory",
    ["X awal"] = "Start X",
    ["Kolom paling kiri"] = "Leftmost column",
    ["X akhir"] = "End X",
    ["Kolom paling kanan (lebih dari lebar world = sampai ujung)"] = "Rightmost column (beyond world width = to the edge)",
    ["Y baris atas"] = "Top row Y",
    ["Baris block paling atas (minimal 1)"] = "Topmost block row (minimum 1)",
    ["Jarak antar baris"] = "Row spacing",
    ["2 = y1, y3, y5.. | 3 = y1, y4, y7.. (maks 3 supaya bisa lompat naik)"] = "2 = y1, y3, y5.. | 3 = y1, y4, y7.. (max 3 so you can jump up)",
    ["Jumlah baris"] = "Number of rows",
    ["Tangga di pojok kiri-kanan"] = "Stairs at left-right corners",
    ["Ujung baris dibuka bergantian, jadi bisa turun-naik zig-zag"] = "Row ends open alternately, so you can go up/down in a zig-zag",
    ["Pakai posisi karakter sebagai pojok kiri-atas"] = "Use character position as top-left corner",
    ["X awal = kolom karakter, Y baris atas = tile di bawah kaki"] = "Start X = character column, top row Y = tile under the feet",
    ["Produksi block kalau kurang"] = "Produce blocks if short",
    ["Tanam & panen seed block itu dulu sampai cukup"] = "Plant & harvest that block's seed first until enough",
    ["Boleh taruh block pijakan"] = "Allow scaffold blocks",
    ["Kalau baris paling bawah tidak terjangkau dari tanah"] = "If the bottom row can't be reached from the ground",
    ["Lanjut Pabrik setelah selesai"] = "Start Factory when finished",
    -- Pabrik
    ["Status Pabrik"] = "Factory Status",
    ["Jalankan Pabrik"] = "Run Factory",
    ["Break -> tanam -> panen -> break lagi, seed lebihan di-drop"] = "Break -> plant -> harvest -> break again, extra seeds are dropped",
    ["Seed pabrik"] = "Factory seed",
    ["Block-nya otomatis (contoh: Dirt Seed -> Dirt)"] = "Block is automatic (example: Dirt Seed -> Dirt)",
    ["Tanam di seluruh world"] = "Plant in the whole world",
    ["Mati = hanya di lahan (tab Lahan)"] = "Off = only on the land (Land tab)",
    ["Pakai posisi sekarang untuk break"] = "Use current position for breaking",
    ["Berdiri di tempat break, lalu tekan"] = "Stand at the break spot, then press",
    ["Pilih tile break (Grid)"] = "Select break tiles (Grid)",
    ["Grid terbuka dalam mode Pabrik (terpisah dari tile Auto Farm)"] = "Grid opens in Factory mode (separate from Auto Farm tiles)",
    ["Lama 1 sesi break (detik)"] = "Break session length (seconds)",
    ["Setelah ini cek pohon siap dulu"] = "After this, check for ready trees first",
    ["Sisakan seed"] = "Seeds to keep",
    ["Untuk ditanam lagi"] = "For replanting",
    ["Drop kalau seed sudah"] = "Drop when seeds reach",
    ["Contoh 200 & sisakan 50 = drop 150"] = "Example 200 & keep 50 = drop 150",
    ["World drop"] = "Drop world",
    ["Kosong = world ini | WORLD | WORLD:ID (masuk lewat pintu ID)"] = "Empty = this world | WORLD | WORLD:ID (enter via door ID)",
    ["Pakai posisi sekarang untuk drop"] = "Use current position for dropping",
    ["Berdiri di tempat drop (boleh di world lain), lalu tekan"] = "Stand at the drop spot (can be another world), then press",
    ["Hapus posisi drop"] = "Clear drop position",
    ["Drop di titik kedatangan (pintu) saja"] = "Drop at the arrival point (door) instead",
    ["Ada block tapi posisi / tile break belum diatur"] = "Has blocks but break position / tiles are not set",
    ["Gagal jalan ke posisi break, dicoba lagi nanti"] = "Failed to walk to break position, retrying later",
    -- Koneksi & config
    ["Referensi game"] = "Game references",
    ["Hubungkan ke game"] = "Connect to game",
    ["Pakai setelah pindah world"] = "Use after changing worlds",
    ["Simpan pengaturan otomatis, dimuat lagi saat execute"] = "Save settings automatically, loaded again on execute",
    ["Simpan config sekarang"] = "Save config now",
    ["Hapus file config, lalu execute ulang"] = "Delete the config file, then re-execute",
    ["Koreksi posisi X"] = "Position correction X",
    ["Isi 1 / -1 kalau tile meleset"] = "Enter 1 / -1 if tiles are off",
    ["Koreksi posisi Y"] = "Position correction Y",
    ["Masuk lagi & lanjut aktivitas kalau terlempar"] = "Rejoin & resume activity if kicked out",
    ["Terlempar dari world"] = "Kicked from world",
    ["World ditutup / di-kick: masuk lagi ke world yang sama"] = "World closed / kicked: rejoin the same world",
    ["Selalu kembali ke world"] = "Always return to world",
    ["Kalau berada di luar world (layar pilih world), masuk lagi otomatis"] = "If outside a world (world select screen), rejoin automatically",
    ["World tujuan"] = "Target world",
    ["Kosongkan = world terakhir yang kamu masuki"] = "Empty = the last world you entered",
    ["NAMAWORLD"] = "WORLDNAME",
    ["Rejoin world sekarang"] = "Rejoin world now",
    ["Keluar lalu masuk lagi, aktivitas dilanjutkan"] = "Leave and rejoin, activity resumes",
    ["Disconnect dari server"] = "Disconnected from server",
    ["Teleport ulang ke game lalu masuk world terakhir"] = "Teleport back to the game and enter the last world",
    ["Jeda sebelum masuk lagi (detik)"] = "Delay before rejoining (seconds)",
    ["URL script (untuk rejoin server)"] = "Script URL (for server rejoin)",
    ["Link raw script ini, supaya jalan lagi setelah teleport. Kosong = pakai autoexec"] =
        "Raw link of this script, so it runs again after teleport. Empty = use autoexec",
    ["Sedang proses masuk world, tunggu dulu"] = "Already entering a world, please wait",
    ["World tujuan belum ada. Isi 'World tujuan' atau masuk world dulu"] = "No target world yet. Fill in 'Target world' or enter a world first",
    -- Discord
    ["Notifikasi Discord"] = "Discord Notifications",
    ["Kirim kabar penting ke channel Discord kamu"] = "Send important updates to your Discord channel",
    ["URL Webhook"] = "Webhook URL",
    ["Channel Discord > Edit > Integrasi > Webhook > Salin URL"] = "Discord channel > Edit > Integrations > Webhook > Copy URL",
    ["Tes kirim"] = "Test send",
    ["Laporan statistik (menit)"] = "Stats report (minutes)",
    ["Kirim statistik sesi tiap X menit. 0 = mati"] = "Send session stats every X minutes. 0 = off",
    ["Mod / Dev / pemain masuk world"] = "Mod / Dev / player entered world",
    ["Aktivitas berhenti (block habis / error)"] = "Activity stopped (out of blocks / error)",
    ["Quest diklaim / redeem berhasil"] = "Quest claimed / redeem successful",
    ["Terlempar / disconnect / masuk lagi"] = "Kicked / disconnected / rejoined",
    ["Pabrik drop seed / lahan selesai / berhenti"] = "Factory dropped seeds / land done / stopped",
    ["Isi URL webhook dulu"] = "Fill in the webhook URL first",
    ["Pesan tes masuk antrian"] = "Test message queued",
    ["URL webhook tidak valid"] = "Invalid webhook URL",
    ["Tes notifikasi dari Fian792"] = "Test notification from Fian792",
    -- pilihan dropdown
    ["Kiri → Kanan"] = "Left → Right", ["Semua pemain"] = "All players", ["Semua"] = "All",
    ["Depan"] = "Front", ["Break saja"] = "Break only", ["Place saja"] = "Place only",
    ["(memuat...)"] = "(loading...)", ["(inventori kosong)"] = "(inventory empty)",
    ["(inventori belum terbaca)"] = "(inventory not read yet)",
    ["(inventori kosong / belum terbaca)"] = "(inventory empty / not read yet)",
    ["Channel chat world belum ada (masuk world dulu)"] = "World chat channel not found (enter a world first)",
    ["Daftar pesan kosong"] = "Message list is empty",
    ["Inventori penuh"] = "Inventory full",
    ["Tanya bahasa saat execute"] = "Ask language on execute",
    ["Execute ulang untuk ganti bahasa / Re-execute to apply"] = "Re-execute to apply the new language",
    ["Munculkan pilihan bahasa tiap execute"] = "Show the language choice on every execute",
    -- Grid
    ["Grid Tile"] = "Tile Grid", ["Bersihkan pilihan"] = "Clear selection",
    ["Tile Break Pabrik"] = "Factory Break Tiles", ["START PABRIK"] = "START FACTORY", ["STOP PABRIK"] = "STOP FACTORY",
}

-- Frasa untuk teks yang berubah-ubah (status, notifikasi, pesan Discord)
I18N.PH = {
    { "Data world belum ketemu", "World data not found" }, { "Data drop belum ketemu", "Drop data not found" },
    { "Data pohon belum ketemu", "Tree data not found" }, { "Data pohon tidak ketemu", "Tree data not found" },
    { "Tekan 'Hubungkan ke game'", "Press 'Connect to game'" }, { "Hubungkan ke game", "Connect to game" },
    { "Kamu belum masuk world", "You are not in a world yet" }, { "belum masuk world", "not in a world yet" },
    { "tidak di world", "not in a world" },
    { "Menunggu karakter / world...", "Waiting for character / world..." },
    { "Menunggu pohon siap", "Waiting for trees to be ready" }, { "Menunggu", "Waiting" },
    { "Dihentikan karena", "Stopped because" }, { "Dihentikan", "Stopped" }, { "dimulai", "started" },
    { "hubungkan ulang ke game", "reconnecting to game" },
    { "Dijeda Penjaga", "Paused by Guard" }, { "Dijeda", "Paused" }, { "Waspada", "Alert" }, { "Ada:", "Present:" },
    { "Aman", "Safe" }, { "Pemain di world", "Players in world" }, { "Staff online di server", "Staff online on server" },
    { "Terdeteksi", "Detected" }, { "kali", "times" }, { "tidak ada", "none" },
    { "pemain diabaikan", "players ignored" },
    { "Masuk world", "Entered world" }, { "Keluar world", "Leave world" },
    { "Masuk lagi dalam", "Rejoining in" }, { "Masuk lagi ke", "Rejoining" }, { "Masuk lagi berhasil", "Rejoined" },
    { "Masuk lagi", "Rejoin" }, { "Masuk ke", "Entering" }, { "Masih ada", "Still here:" }, { "Keluar lagi", "Leaving again" },
    { "Sudah keluar world", "Already left the world" }, { "lanjut otomatis mati", "auto resume off" },
    { "Di luar world", "Outside the world" }, { "Mereka sudah pergi", "They left" }, { "Lanjut dalam", "Resuming in" },
    { "Sudah aman", "Safe now" }, { "World aman", "World is safe" }, { "World sudah beda", "Different world" },
    { "aktivitas tidak dilanjutkan", "activity not resumed" }, { "aktivitas dilanjutkan", "activity resumed" },
    { "aktivitas hanya dijeda", "activity only paused" },
    { "lanjut aktivitas", "resuming activity" }, { "Lanjut aktivitas", "Resuming activity" },
    { "Gagal balik ke posisi farm", "Failed to return to farm position" },
    { "Auto Farm tidak dilanjutkan", "Auto Farm not resumed" },
    { "Jalan balik ke posisi farm", "Walking back to farm position" },
    { "Jalan ke posisi break", "Walking to break position" }, { "Jalan ke posisi drop", "Walking to drop position" },
    { "Cari jalan A* ke", "Finding A* path to" }, { "Jalan ke", "Walking to" }, { "Lompati lubang ke", "Jumping gap to" },
    { "Lompat ke", "Jumping to" }, { "Turun ke", "Dropping down to" }, { "Naik pakai block ke", "Climbing with block to" },
    { "Taruh block pijakan", "Placing scaffold block" },
    { "di bawahnya berbahaya", "dangerous below" }, { "di bawahnya jurang", "pit below" },
    { "Lewati pijakan", "Skip foothold" }, { "Lewati", "Skip" },
    { "Pukul", "Hit" }, { "Pecah", "Broke" }, { "Panen", "Harvest" }, { "Tanam", "Plant" },
    { "Pasang lahan: sisa", "Placing land: remaining" }, { "Pasang", "Place" },
    { "Produksi block", "Producing blocks" }, { "total butuh", "total needed" },
    { "Lahan selesai", "Land finished" }, { "Block cukup", "Enough blocks" }, { "mulai pasang", "starting to place" },
    { "Block habis, masih kurang", "Out of blocks, still short" }, { "Seed & block habis", "Seeds & blocks used up" },
    { "tidak ada pohon tumbuh", "no trees growing" }, { "Butuh", "Need" }, { "Seed habis", "Out of seeds" },
    { "seed-nya tidak ketemu", "its seed was not found" }, { "Block kurang", "Blocks short" },
    { "Sisa tile belum terjangkau / terhalang, dicoba lagi", "Remaining tiles unreachable / blocked, retrying" },
    { "Lahan penuh, menunggu", "Land is full, waiting" }, { "Bukan di world pabrik", "Not in the factory world" },
    { "menunggu...", "waiting..." }, { "Pergi ke", "Going to" }, { "untuk drop", "to drop" }, { "Pulang ke", "Returning to" },
    { "Gagal pulang ke world pabrik", "Failed to return to factory world" }, { "Drop gagal", "Drop failed" },
    { "tidak bisa drop di posisi ini", "can't drop at this position" },
    { "tidak bisa jalan ke posisi drop", "can't walk to the drop position" },
    { "Posisi drop belum diatur", "Drop position not set" }, { "drop dilewati", "drop skipped" },
    { "Posisi drop dihapus", "Drop position cleared" }, { "Posisi drop", "Drop position" }, { "Posisi break", "Break position" },
    { "di posisi pabrik", "at the factory position" }, { "Pabrik berhenti", "Factory stopped" },
    { "Bangun Lahan", "Build Land" }, { "Pabrik", "Factory" }, { "Penjaga", "Guard" }, { "Lahan", "Land" },
    { "Gagal masuk lagi ke", "Failed to rejoin" }, { "Gagal masuk", "Failed to enter" }, { "Gagal keluar world", "Failed to leave world" },
    { "Dicoba lagi nanti", "Will retry later" }, { "dicoba lagi", "retrying" },
    { "Gagal splice", "Splice failed" }, { "ditolak server", "rejected by server" }, { "Splice jadi", "Spliced into" },
    { "Menunggu tile Grid kosong (panen dulu pohonnya)", "Waiting for empty Grid tiles (harvest the trees first)" },
    { "Seed A habis, tidak ada pohon A yang bisa di-splice", "Seed A used up, no A trees to splice" },
    { "tidak ada tempat tanam / pohon untuk di-splice", "no planting spot / tree to splice" },
    { "Karakter tidak ditemukan (keluar world?)", "Character not found (left the world?)" },
    { "di inventori habis", "in inventory is used up" }, { "Auto Farm berhenti", "Auto Farm stopped" },
    { "Auto Clear berhenti", "Auto Clear stopped" }, { "Farmer berhenti", "Farmer stopped" },
    { "Inventori penuh", "Inventory full" }, { "tidak bisa diambil lagi", "can't be picked up anymore" },
    { "Laporan statistik", "Stats report" }, { "Quest diklaim", "Quest claimed" }, { "Redeem berhasil", "Redeem successful" },
    { "Redeem gagal", "Redeem failed" }, { "Terlempar dari world", "Kicked from world" }, { "Terlempar dari", "Kicked from" },
    { "Kembali otomatis", "Auto return" }, { "berhasil", "succeeded" },
    { "Rejoin: menunggu masuk", "Rejoin: waiting to enter" }, { "Rejoin: gagal masuk", "Rejoin: failed to enter" },
    { "Disconnect dari server", "Disconnected from server" }, { "script tidak di-queue", "script not queued" },
    { "Berhasil masuk lagi", "Rejoined" }, { "World tujuan", "Target world" },
    { "Mode diganti, nyalakan lagi", "Mode changed, turn it on again" }, { "World sudah bersih!", "World is clean!" },
    { "Block pijakan belum dipilih / habis: jalan tanpa block pijakan", "Scaffold block not selected / empty: moving without scaffold" },
    { "Auto Harvest tidak bisa cek pohon siap", "Auto Harvest can't check ready trees" },
    { "Aktifkan Auto Harvest atau Auto Plant", "Enable Auto Harvest or Auto Plant" },
    { "Pilih seed dulu untuk Auto Plant", "Select a seed for Auto Plant first" },
    { "Pilih seed pabrik dulu", "Select a factory seed first" }, { "Block dari seed ini tidak ketemu", "Block for this seed not found" },
    { "Atur lahan dulu", "Set up the land first" }, { "Pilih block padat untuk lahan", "Select a solid block for the land" },
    { "Pilih Seed A dan Seed B dulu", "Select Seed A and Seed B first" }, { "Seed A dan Seed B harus beda", "Seed A and Seed B must differ" },
    { "Kombinasi ini tidak bisa di-splice", "This combination can't be spliced" },
    { "Pilih tile dulu di Grid Tile", "Select tiles in the Tile Grid first" }, { "Pilih block dari inventori", "Select a block from inventory" },
    { "Hentikan Auto Farm / Clear / Farmer dulu", "Stop Auto Farm / Clear / Farmer first" },
    { "atau nyalakan Keliling world", "or turn on Roam world" },
    { "Kontrol gerak game (WorldMenu.isDown) tidak ketemu", "Game movement control (WorldMenu.isDown) not found" },
    { "Fungsi pukul game belum ketemu", "Game punch function not found" },
    { "Seed habis: atur posisi & tile break di tab Pabrik supaya bisa dapat seed", "Out of seeds: set break position & tiles in the Factory tab to get seeds" },
    { "Config dihapus. Execute ulang untuk default", "Config deleted. Re-execute for defaults" },
    { "Config dimuat", "Config loaded" }, { "Belum ada config", "No config yet" }, { "Tersimpan", "Saved" },
    { "Executor tidak bisa simpan file", "Executor can't save files" }, { "Executor tidak bisa hapus file", "Executor can't delete files" },
    { "Executor tidak punya fungsi request", "Executor has no request function" },
    { "Gagal simpan file", "Failed to save file" }, { "Gagal hapus file", "Failed to delete file" },
    { "Gagal kirim", "Failed to send" }, { "Terkirim", "Sent" }, { "Antrian", "Queue" },
    { "Role dikirim", "Role sent" }, { "Gagal buka", "Failed to open" }, { "Gagal", "Failed" },
    -- label status
    { "BERHENTI", "STOPPED" }, { "JALAN", "RUNNING" }, { "fase", "phase" }, { "PANEN", "HARVEST" }, { "TANAM", "PLANT" },
    { "TUNGGU", "WAIT" }, { "TIDAK terbaca (harvest mati)", "NOT readable (harvest off)" }, { "terbaca", "readable" },
    { "TIDAK", "NO" }, { "cadangan", "fallback" }, { "Inventori", "Inventory" }, { "Posisi", "Position" },
    { "Karakter", "Character" }, { "Aksi", "Action" }, { "Baris", "Row" }, { "Pohon", "Trees" }, { "Pijakan", "Scaffold" },
    { "Pemain", "Players" }, { "belum dipilih", "not selected" }, { "belum diatur", "not set" }, { "ditolak", "rejected" },
    { "Bentuk", "Shape" }, { "baris", "rows" }, { "jarak", "spacing" }, { "tangga", "stairs" }, { "punya", "have" },
    { "butuh", "need" }, { "kurang", "short" }, { "cukup", "enough" }, { "Terpasang", "Placed" },
    { "terhalang block lain", "blocked by other blocks" }, { "Celah tanam terisi block", "Planting gaps filled with blocks" },
    { "bersihkan dulu", "clear it first" }, { "Celah tanam: bersih", "Planting gaps: clear" }, { "Seed block", "Block seed" },
    { "Hasil", "Result" }, { "panen", "harvest" }, { "tanam", "plant" }, { "di-drop", "dropped" }, { "sisakan", "keep" },
    { "drop saat", "drop at" }, { "world ini", "this world" }, { "pintu", "door" }, { "Lama sesi", "Session time" },
    { "Block pecah", "Blocks broken" }, { "Block di-place", "Blocks placed" }, { "Drop diambil", "Drops collected" },
    { "Item terbanyak", "Top items" }, { "Selesai", "Done" }, { "diklaim script", "claimed by script" },
    { "Quest baru dalam", "New quests in" }, { "Quest belum bisa diambil", "Quests not available yet" },
    { "Gagal ambil quest", "Failed to get quests" }, { "Gagal ambil daftar code", "Failed to get code list" },
    { "Pesan terakhir", "Last message" }, { "Cek lagi dalam", "Checking again in" }, { "detik", "seconds" },
    { "Auto klaim mati", "Auto claim off" }, { "Code aktif", "Active codes" }, { "sudah ditukar", "redeemed" },
    { "ditukar script", "redeemed by script" }, { "Auto redeem mati", "Auto redeem off" },
    { "Redeem sedang ditutup", "Redeem is closed" }, { "Block depan", "Front blocks" }, { "tumpukan", "piles" },
    { "siap panen", "ready" }, { "tumbuh", "growing" }, { "Scan terakhir", "Last scan" }, { "siap", "ready" },
    { "berikut", "next" }, { "Tidak ada yang cocok", "No matches" }, { "Kosong", "Empty" }, { "Tidak ada pohon", "No trees" },
    { "item lain", "more items" }, { "jenis lain", "more types" }, { "pakai Cari item", "use Search item" },
    { "(pohon)", "(tree)" }, { "Di-recycle", "Recycled" }, { "Item dipilih", "Items selected" }, { "Ditanam", "Planted" },
    { "tidak bisa di-splice", "can't be spliced" }, { "Pilih Seed A dan Seed B", "Select Seed A and Seed B" },
    { "Menghitung...", "Calculating..." }, { "Mulai...", "Starting..." }, { "Lanjut aktivitas...", "Resuming activity..." },
    { "data pemain belum ketemu", "player data not found" }, { "belum ketemu", "not found" },
    { "tidak ketemu", "not found" }, { "ketemu", "found" }, { "tekan", "press" },
    { "tidak ada block padat di inventori", "no solid blocks in inventory" },
    { "tidak ada seed di inventori", "no seeds in inventory" }, { "tidak ada pohon", "no trees" },
    { "tidak ada tempat tanam", "no planting spot" },
    { "Y baris atas", "top row Y" }, { "baris atas", "top row" }, { "Y awal", "start Y" }, { "X awal", "start X" },
    { "jumlah baris", "row count" }, { "masuk lagi dalam", "rejoining in" }, { "masuk ke", "entering" },
    { "dalam", "in" }, { "Executor tidak punya", "Executor has no" },
    { "tidak bisa dijangkau / dipecah", "can't be reached / broken" }, { "Sisa", "Remaining" },
    { "dilewati, coba ulang", "skipped, retrying" }, { "Gagal membaca pengaturan", "Failed to read settings" },
    { "balasan kosong", "empty reply" }, { "fungsi drop game tidak ketemu", "game drop function not found" },
    { "fungsi masuk world tidak ketemu", "game enter-world function not found" },
    { "fungsi splice game tidak ketemu", "game splice function not found" },
    { "gagal masuk", "failed to enter" }, { "nama world tidak diketahui", "unknown world name" },
    { "tidak bisa ke server", "can't reach the server" }, { "tunggu", "wait" },
    { "world penuh / dikunci / gagal", "world full / locked / failed" }, { "aman", "safe" }, { "Fase", "Phase" },
    { "Mati", "Off" }, { "mati", "off" }, { "pohon siap", "trees ready" }, { "pohon", "trees" },
    { "di-recycle", "recycled" }, { "di-splice", "spliced" }, { "di-place", "placed" }, { "di-queue", "queued" }, { "habis", "used up" }, { "dan", "and" }, { "atau", "or" }, { "dari", "from" }, { "untuk", "for" },
    { "sudah", "already" }, { "belum", "not yet" }, { "lagi", "again" }, { "di", "at" }, { "ke", "to" },
}

-- Pola tambahan (format waktu "1j 2m 3d" -> "1h 2m 3s", "/jam" -> "/hour")
I18N.RAW = {
    { "(%d+)j (%d+)m (%d+)d", "%1h %2m %3s" },
    { "(%d+)m (%d+)d", "%1m %2s" },
    { "(%d+)j (%d+)m", "%1h %2m" },
    { "/jam", "/hour" },
    { "(%d+) dtk", "%1 s" },
}

function I18N.prep()
    local list = {}
    for _, p in ipairs(I18N.PH) do
        if p[1] ~= p[2] then
            local pat = p[1]:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
            if p[1]:match("^%w") then pat = "%f[%w]" .. pat end
            if p[1]:match("%w$") then pat = pat .. "%f[%W]" end
            list[#list + 1] = { pat, (p[2]:gsub("%%", "%%%%")), #p[1] }
        end
    end
    table.sort(list, function(a, b) return a[3] > b[3] end)
    I18N.list = list
end

-- Terjemahkan teks (kalau bahasa = English)
function I18N.T(s)
    if I18N.Lang ~= "en" or type(s) ~= "string" or s == "" then return s end
    local e = I18N.EN[s]
    if e then return e end
    if not I18N.list then I18N.prep() end
    for _, r in ipairs(I18N.list) do s = s:gsub(r[1], r[2]) end
    for _, r in ipairs(I18N.RAW) do s = s:gsub(r[1], r[2]) end
    return s
end

-- Teks pilihan dropdown: hanya terjemahan utuh (nama item game tidak diubah)
function I18N.V(s)
    if I18N.Lang ~= "en" or type(s) ~= "string" then return s end
    return I18N.EN[s] or s
end

-- Bungkus objek WindUI: judul, deskripsi, pilihan dropdown & isi status ikut diterjemahkan
I18N.Backs = setmetatable({}, { __mode = "k" })

local function mapList(list, back)
    local out = {}
    for i, val in ipairs(list) do
        local tr = I18N.V(val)
        out[i] = tr
        if type(tr) == "string" then back[tr] = val end
    end
    return out
end

function I18N.wrap(obj)
    if I18N.Lang ~= "en" or type(obj) ~= "table" then return obj end
    return setmetatable({}, {
        __index = function(_, k)
            local v = obj[k]
            if type(v) ~= "function" then return v end
            return function(_, cfg, ...)
                local back
                if k == "Dropdown" and type(cfg) == "table" then
                    back = {}
                    if type(cfg.Values) == "table" then cfg.Values = mapList(cfg.Values, back) end
                    if type(cfg.Value) == "string" then
                        cfg.Value = I18N.V(cfg.Value)
                    elseif type(cfg.Value) == "table" then
                        cfg.Value = mapList(cfg.Value, back)
                    end
                    local cb = cfg.Callback
                    if cb then
                        -- tampil dalam English, callback tetap terima teks asli
                        cfg.Callback = function(opt, ...)
                            if type(opt) == "string" then
                                opt = back[opt] or opt
                            elseif type(opt) == "table" then
                                local o2 = {}
                                for i, x in ipairs(opt) do o2[i] = back[x] or x end
                                opt = o2
                            end
                            return cb(opt, ...)
                        end
                    end
                elseif (k == "Refresh" or k == "Select") and I18N.Backs[obj] then
                    local b = I18N.Backs[obj]
                    if type(cfg) == "table" then
                        cfg = mapList(cfg, b)
                    elseif type(cfg) == "string" then
                        cfg = I18N.V(cfg)
                    end
                end
                if type(cfg) == "table" and k ~= "Refresh" and k ~= "Select" and cfg[1] == nil then
                    for _, f in ipairs({ "Title", "Desc", "Placeholder", "Content" }) do
                        if type(cfg[f]) == "string" then cfg[f] = I18N.T(cfg[f]) end
                    end
                elseif type(cfg) == "string" and (k == "SetDesc" or k == "SetTitle") then
                    cfg = I18N.T(cfg)
                end
                local r = v(obj, cfg, ...)
                if back and type(r) == "table" then I18N.Backs[r] = back end
                if type(r) == "table" and r ~= obj then return I18N.wrap(r) end
                return r
            end
        end,
    })
end
end)() end

local function notify(title, content, dur)
    task.defer(function()
        pcall(function()
            WindUI:Notify({ Title = I18N.T(title), Content = I18N.T(content), Duration = dur or 3, Icon = "info" })
        end)
    end)
end

---------------------------------------------------------------------
-- CONFIG: simpan & muat pengaturan otomatis
---------------------------------------------------------------------
-- Cara kerja:
--   1. Saat execute, file config dibaca lalu nilainya dipasang ke pengaturan
--      SEBELUM UI dibuat, jadi tombol & slider langsung tampil sesuai config.
--   2. Tiap 3 detik pengaturan sekarang dibandingkan dengan yang terakhir disimpan.
--      Ada yang berubah -> langsung disimpan (auto save).
--   3. File per akun: workspace/Alfian/config_<UserId>.json
--   Yang tidak disimpan: tombol jalan (Auto Farm / Clear / Farmer / Chat), fly & inf jump.
local Config = {
    AutoSave = true,
    Paused = false,      -- true setelah reset (supaya file tidak dibuat lagi)
    Folder = "Alfian",
    Data = {},           -- isi file saat execute
    List = {},           -- tabel pengaturan yang disimpan
    LastJson = nil,
    Status = "-",
}

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
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
    Config.Found = loaded ~= nil
    Config.Data = loaded or {}
    if Config.Data.AutoSave == false then Config.AutoSave = false end
    Config.Status = Config.Found and "Config dimuat" or (canFile and "Belum ada config" or "Executor tidak bisa simpan file")

    -- Daftarkan tabel pengaturan. Nilai dari file langsung dipasang
    -- (kecuali key di 'later', dipasang sendiri setelah terhubung ke game).
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
        local out = { AutoSave = Config.AutoSave, Version = 1 }
        for _, e in ipairs(Config.List) do
            local t = {}
            for _, k in ipairs(e.keys) do t[k] = e.tbl[k] end
            out[e.name] = t
        end
        return out
    end

    function Config.save(force)
        if not canFile then
            Config.Status = "Executor tidak bisa simpan file"
            return false
        end
        if Config.Paused and not force then return false end
        local okJ, json = pcall(HttpService.JSONEncode, HttpService, collect())
        if not okJ then
            Config.Status = "Gagal membaca pengaturan"
            return false
        end
        if not force and json == Config.LastJson then return true end
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local okF, has = pcall(isfolder, Config.Folder)
            if okF and not has then pcall(makefolder, Config.Folder) end
        end
        local ok = pcall(writefile, Config.Path, json)
        if ok then
            Config.LastJson = json
            Config.Paused = false
            Config.Status = "Tersimpan " .. os.date("%H:%M:%S")
        else
            Config.Status = "Gagal simpan file"
        end
        return ok
    end

    -- Hapus file config (execute ulang = kembali ke default)
    function Config.reset()
        Config.Paused = true
        Config.LastJson = nil
        if canFile and type(delfile) == "function" then
            local ok = pcall(delfile, Config.Path)
            Config.Status = ok and "Config dihapus. Execute ulang untuk default" or "Gagal hapus file"
            return ok
        end
        Config.Status = "Executor tidak bisa hapus file"
        return false
    end

    function Config.start()
        -- tandai kondisi sekarang sebagai "sudah tersimpan" kalau sama dengan file
        if Config.Found then
            local okJ, json = pcall(HttpService.JSONEncode, HttpService, collect())
            if okJ then Config.LastJson = json end
        end
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
    "CalibX", "CalibY", "AntiAfk", "MutePunch", "LiteMode", "AutoCollect", "MultiTarget",
    "CollectAround", "CollectRadius",
})
Config.add("Clear", Clear, { "UseBlock", "ScaffoldId", "Collect", "Sweep" })
Config.add("Farmer", Farmer, { "Harvest", "Plant", "Collect", "UseBlock", "ScaffoldId", "HarvestMs", "PlantMs", "SeedId" })
-- update 1084: game memberi jeda minimal antar aksi (place ~0.135 dtk, pukul ~0.19 dtk)
State.PlaceMs = math.max(State.PlaceMs, 140)
State.BreakMs = math.max(State.BreakMs, 200)
Farmer.HarvestMs = math.max(Farmer.HarvestMs, 140)
Farmer.PlantMs = math.max(Farmer.PlantMs, 140)
Config.add("Misc", Misc, { "Speed" })
Config.add("Chat", Spam, { "Texts", "IntervalSec" })
Config.add("Lahan", Land, { "X0", "X1", "Y0", "Gap", "Rows", "Stairs" })
Config.add("Bangun", Build, { "BlockId", "UseBlock", "Produce", "ThenPabrik" })
Config.add("Pabrik", Pabrik, {
    "SeedId", "WholeWorld", "Tiles", "BreakX", "BreakY", "BreakSec",
    "Drop", "Keep", "DropAt", "DropWorld", "DropX", "DropY",
})
Config.add("Bahasa", I18N, { "Saved", "Ask" })
I18N.Lang = (I18N.Saved == "en") and "en" or "id"

---------------------------------------------------------------------
-- STATISTIK SESI & NOTIFIKASI DISCORD (data; tampilan ada di tab Statistik / Discord)
---------------------------------------------------------------------
local Stats = { T0 = os.clock(), Gems0 = nil, Items = {}, Base = {} }

-- Cara kerja webhook:
--   Hook.send(jenis, teks) memasukkan pesan ke antrian.
--   Antrian dikirim satu per satu tiap 2.5 detik (supaya tidak kena batas Discord).
local Hook = {
    On = false,
    Url = "",
    Penjaga = true,   -- mod / dev / pemain masuk world
    Stop = true,      -- aktivitas berhenti (block habis, error)
    Full = true,      -- inventori penuh
    Bonus = true,     -- quest diklaim / redeem berhasil
    Rejoin = true,    -- terlempar / masuk lagi
    Pabrik = true,    -- pabrik drop / lahan selesai / berhenti
    ReportMin = 0,    -- laporan statistik tiap X menit (0 = mati)
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

    -- jenis: "penjaga" | "stop" | "full" | "bonus" | "rejoin" | "report" | "test"
    function Hook.send(kind, text)
        if not Hook.On or not Hook.valid(Hook.Url) then return end
        local allow = kind == "test" or kind == "report"
            or (kind == "penjaga" and Hook.Penjaga) or (kind == "stop" and Hook.Stop)
            or (kind == "full" and Hook.Full) or (kind == "bonus" and Hook.Bonus)
            or (kind == "rejoin" and Hook.Rejoin) or (kind == "pabrik" and Hook.Pabrik)
        if not allow or #Hook.Queue >= 20 then return end
        table.insert(Hook.Queue, I18N.T(tostring(text)))
    end

    task.spawn(function()
        while alive() do
            local text = table.remove(Hook.Queue, 1)
            if not text then
                task.wait(0.5)
            else
                local req = requester()
                if not req then
                    Hook.Status = "Executor tidak punya fungsi request"
                else
                    local body = HttpService:JSONEncode({
                        username = "Fian792",
                        content = ("**[%s]** %s"):format(LocalPlayer.Name, text),
                    })
                    local ok, res = pcall(req, {
                        Url = Hook.Url, Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" }, Body = body,
                    })
                    local code = ok and type(res) == "table" and tonumber(res.StatusCode or res.Status) or nil
                    if ok and (code == nil or code < 300) then
                        Hook.Status = "Terkirim " .. os.date("%H:%M:%S")
                    else
                        Hook.Status = "Gagal kirim (" .. tostring(code or res) .. ")"
                    end
                end
                task.wait(2.5)
            end
        end
    end)
end)() end

---------------------------------------------------------------------
-- CARI DATA & FUNGSI GAME (getgc)
---------------------------------------------------------------------
local getconsts = (debug and debug.getconstants) or getconstants

-- Fungsi place game: satu-satunya yang memakai "placedAt" + "flips" sekaligus.
-- Kirimnya "tile" (game baru, ByteNet) atau "SetTile" (game lama).
local function isSetTileFn(fn)
    if not getconsts then return false end
    if islclosure and not islclosure(fn) then return false end
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

-- Fungsi pukul game: teks "Empty the Vending Machine first!" + "newCrack"
-- (game lama: "HarvestProvider")
local function isPunchFn(fn)
    if not getconsts then return false end
    if islclosure and not islclosure(fn) then return false end
    local ok, consts = pcall(getconsts, fn)
    if not ok or type(consts) ~= "table" then return false end
    local hasVend, hasMark = false, false
    for _, c in pairs(consts) do
        if c == "Empty the Vending Machine first!" then hasVend = true
        elseif c == "newCrack" or c == "HarvestProvider" then hasMark = true end
    end
    return hasVend and hasMark
end

local function isStateHolder(v)
    local fn = rawget(v, "state")
    if type(fn) ~= "function" then return false end
    local ok, s = pcall(fn)
    return ok and type(s) == "table" and type(s.x) == "number" and type(s.y) == "number"
        and s.facing ~= nil and s.vx ~= nil
end

-- Pastikan fungsi milik game, bukan milik script ini
local function isGameFn(fn)
    if fn == isSetTileFn or fn == isPunchFn then return false end
    if isexecutorclosure then
        local ok, res = pcall(isexecutorclosure, fn)
        if ok and res then return false end
    end
    local ok, src = pcall(debug.info, fn, "s")
    if ok and type(src) == "string" and src ~= "" and not string.find(src, "GameGui", 1, true) then
        return false
    end
    return true
end

local function findRefs()
    Refs.World, Refs.Inv, Refs.SetTile, Refs.State, Refs.Punch, Refs.Menu = nil, nil, nil, nil, nil, nil
    Refs.Gems = nil
    Refs.Hud = nil
    Refs.Others = nil
    Refs.Particles = {}
    if not getgc then
        return false, "Executor tidak punya getgc()"
    end
    for _, v in ipairs(getgc(true)) do
        local tv = type(v)
        if tv == "table" then
            if not Refs.World then
                local ok, isWorld = pcall(function()
                    return type(rawget(v, "fg")) == "table" and type(rawget(v, "bg")) == "table"
                        and type(rawget(v, "w")) == "number" and type(rawget(v, "h")) == "number"
                        and rawget(v, "spawn") ~= nil
                end)
                if ok and isWorld then Refs.World = v end
            end
            if not Refs.Inv then
                local ok, isInv = pcall(function()
                    return getmetatable(v) == InventoryModule and type(rawget(v, "slots")) == "table"
                        and rawget(v, "capacity") ~= nil
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
                -- data pemain lain: punya list(), where(), playerAt()
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
                if ok and isP then table.insert(Refs.Particles, v) end
            end
        elseif tv == "function" and (not Refs.SetTile or not Refs.Punch) and isGameFn(v) then
            if not Refs.SetTile and isSetTileFn(v) then
                Refs.SetTile = v
            elseif not Refs.Punch and isPunchFn(v) then
                Refs.Punch = v
            end
        end
        if Refs.World and Refs.Inv and Refs.SetTile and Refs.State and Refs.Punch
            and Refs.Menu and Refs.Gems and Refs.Hud and Refs.Others then break end
    end
    return Refs.World ~= nil
end

local function refsText()
    return "World: " .. (Refs.World and "OK" or "TIDAK")
        .. " | Inventori: " .. (Refs.Inv and "OK" or "TIDAK")
        .. " | setTile: " .. (Refs.SetTile and "OK" or "cadangan")
        .. " | Posisi: " .. (Refs.State and "OK" or "cadangan")
        .. " | Pukul: " .. (Refs.Punch and "OK" or "TIDAK")
        .. " | Drop: " .. (Drops.list and "OK" or "TIDAK")
        .. " | Pohon: " .. (Refs.Trees and "OK" or "TIDAK")
        .. " | Pemain: " .. (Refs.Others and "OK" or "TIDAK")
end

---------------------------------------------------------------------
-- ITEM & INVENTORI
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
    if #out == 0 then out = { "(inventori kosong / belum terbaca)" } end
    return out
end

-- Dropdown cuma di-refresh kalau jenis item berubah (biar tidak lag)
local lastInvSig = nil
local invRefreshPending = false

local lastSeedSig = nil
local lastBlockSig = nil

-- Seed di inventori (untuk Farmer)
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

-- Setelah daftar di-refresh, pilih lagi item yang sedang dipakai (dari config / pilihan lama)
local function selectSaved(dd, labels, id)
    if not dd or not id then return end
    local want = "[" .. tostring(id) .. "]"
    for _, label in ipairs(labels) do
        if string.sub(label, -#want) == want then
            pcall(function() dd:Select(label) end)
            return
        end
    end
end

local function doInvRefresh(force)
    local ids = placeableIds()
    local sig = table.concat(ids, ",")
    if force or sig ~= lastInvSig then
        lastInvSig = sig
        local labels = inventoryLabels(ids)
        pcall(function() UI.InvDropdown:Refresh(labels) end)
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
        if #labels == 0 then labels = { "(tidak ada seed di inventori)" } end
        pcall(function() UI.SeedDropdown:Refresh(labels) end)
        selectSaved(UI.SeedDropdown, labels, Farmer.SeedId)
        if UI.PabrikSeedDropdown then
            pcall(function() UI.PabrikSeedDropdown:Refresh(labels) end)
            selectSaved(UI.PabrikSeedDropdown, labels, Pabrik.SeedId)
        end
    end
    -- block padat untuk pijakan
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
        if #labels == 0 then labels = { "(tidak ada block padat di inventori)" } end
        pcall(function() UI.ClearBlockDropdown:Refresh(labels) end)
        pcall(function() UI.FarmerBlockDropdown:Refresh(labels) end)
        selectSaved(UI.ClearBlockDropdown, labels, Clear.ScaffoldId)
        selectSaved(UI.FarmerBlockDropdown, labels, Farmer.ScaffoldId)
        if UI.BuildBlockDropdown then
            pcall(function() UI.BuildBlockDropdown:Refresh(labels) end)
            selectSaved(UI.BuildBlockDropdown, labels, Build.BlockId)
        end
    end
    -- daftar Splice & Tas (dibuat di bagian bawah script)
    if UI.SpliceRefresh then pcall(UI.SpliceRefresh, force) end
    if UI.TrashRefresh then pcall(UI.TrashRefresh, force) end
end

local function refreshInvDropdown(force)
    if force then
        task.defer(function()
            if alive() then doInvRefresh(true) end
        end)
        return
    end
    if invRefreshPending then return end
    invRefreshPending = true
    task.delay(1, function()
        invRefreshPending = false
        if alive() then doInvRefresh(false) end
    end)
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
-- WORLD: tile & posisi karakter
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

-- Tile, block & mode Auto Farm yang dipakai sekarang (Pabrik memakai miliknya sendiri)
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
-- AKSI DASAR: place & pukul
---------------------------------------------------------------------
local function sendSetTile(layer, x, y, id)
    if Refs.SetTile then
        local ok, err = pcall(Refs.SetTile, layer, x, y, id, false, false)
        if ok then return true end
        warn("[Fian792] setTile game gagal, pakai remote langsung: " .. tostring(err))
    end
    if NetOk and type(Net) == "table" and type(Net.tile) == "table" then
        -- sama seperti game: layer 1 = fg, 2 = bg
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
    if grid and grid[y] then grid[y][x] = id end
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

-- Game abaikan pukulan ke tile yang baru di-place (< 0.3 detik)
local PLACE_GUARD = 0.32

-- Place 1 tile kalau kosong. Hasil: "place" / "habis" / nil
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
    if invCount(sel) <= 0 then return "habis" end

    sendSetTile(layer, x, y, sel)
    if Refs.Inv then pcall(function() Refs.Inv:remove(sel, 1) end) end
    local key = x .. "," .. y
    HitCount[key] = nil
    PlacedAt[key] = os.clock()
    State.Placed += 1
    State.LastAction = "Place " .. itemName(sel) .. " (" .. x .. "," .. y .. ")"
    return "place"
end

-- Masih ada yang bisa dipecah di tile ini? (block depan / background)
local function breakableAt(x, y)
    local fg = tileAt("fg", x, y)
    if fg == nil then return false end
    if fg ~= 0 then return canBreak(fg) end
    local bg = tileAt("bg", x, y)
    return State.BreakBackground and bg ~= nil and bg ~= 0 and canBreak(bg)
end

-- Pukul 1 kali. Hasil: "hit" / "broke" / nil
-- includeBg = ikut pecah background
local function tryBreak(x, y, includeBg)
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

    -- tunggu sebentar kalau tile baru di-place
    local t = PlacedAt[key]
    if t then
        local age = os.clock() - t
        if age < PLACE_GUARD then task.wait(PLACE_GUARD - age) end
        PlacedAt[key] = nil
    end

    if Refs.Punch then
        local ok, err = pcall(Refs.Punch, x, y, State.MutePunch or nil, nil)
        if not ok then
            State.LastAction = "Error pukul: " .. tostring(err)
            return nil
        end
        if tileAt(layer, x, y) ~= id then
            State.Broken += 1
            State.LastAction = "Break " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            return "broke"
        end
        State.LastAction = "Pukul " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
        return "hit"
    end

    -- Cadangan: hitung pukulan sendiri
    local hc = HitCount[key]
    if not hc or hc.id ~= id or hc.layer ~= layer then
        hc = { id = id, layer = layer, n = 0 }
        HitCount[key] = hc
    end
    hc.n += 1
    sendHitFx(x, y)
    local need = hitsNeeded(id)
    if hc.n >= need then
        sendSetTile(layer, x, y, 0)
        HitCount[key] = nil
        State.Broken += 1
        State.LastAction = "Break " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
        return "broke"
    end
    State.LastAction = "Pukul " .. itemName(id) .. " " .. hc.n .. "/" .. need
    return "hit"
end

---------------------------------------------------------------------
-- AUTO COLLECT
---------------------------------------------------------------------
-- Cara game: World.takeDrop(uid, jumlah) -> server balas jumlahnya -> masuk inventori.
-- Game cuma ambil drop yang disentuh badan; di sini drop diambil langsung.
local TakeDropRemote = WorldRemotes:FindFirstChild("TakeDrop") -- game lama saja

local function getUpvalues(fn)
    if debug and debug.getupvalues then
        local ok, ups = pcall(debug.getupvalues, fn)
        if ok and type(ups) == "table" then return ups end
    end
    local out = {}
    local gu = (debug and debug.getupvalue) or getupvalue
    if gu then
        for i = 1, 60 do
            local ok, v = pcall(gu, fn, i)
            if not ok then break end
            out[i] = v
        end
    end
    return out
end

-- Cek apakah tabel ini daftar drop game
local function isDropList(t)
    if type(t) ~= "table" or t == Refs.World then return false end
    local first = rawget(t, 1)
    if first == nil then return next(t) == nil end
    return type(first) == "table" and rawget(first, "uid") ~= nil and rawget(first, "frame") ~= nil
end

local function findDropRefs()
    Drops.list, Drops.update = nil, nil
    -- 1) dari fungsi World.dropTaken (isinya: daftar drop + fungsi update)
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
    -- 2) dari handler DropTaken game
    local ev = WorldRemotes:FindFirstChild("DropTaken")
    if not Drops.list and ev and getconnections then
        local ok, conns = pcall(getconnections, ev.OnClientEvent)
        if ok and type(conns) == "table" then
            for _, c in ipairs(conns) do
                local okf, fn = pcall(function() return c.Function end)
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
    -- 3) cadangan: cari lewat getgc
    if not Drops.list and getgc then
        for _, v in ipairs(getgc(true)) do
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

local function takeDrop(d)
    local worldTake = Refs.World and rawget(Refs.World, "takeDrop")
    if type(worldTake) ~= "function" and not TakeDropRemote then return false end
    if d.taking or d.pending or d.display or (d.n or 0) <= 0 then return false end
    -- drop yang kamu buang sendiri belum boleh dipungut lagi (aturan game), kecuali gems
    if d.armed == false and d.id ~= 112 then return false end
    local now = os.clock()
    if DropFailUntil[d.uid] and now < DropFailUntil[d.uid] then return false end

    local amount = d.n
    if d.id ~= 112 and Refs.Inv then -- 112 = gems, tidak makan slot
        local okr, room = pcall(function() return Refs.Inv:room(d.id) end)
        if okr and type(room) == "number" then amount = math.min(amount, room) end
    end
    if amount <= 0 then -- inventori penuh: coba lagi 1 detik lagi
        DropFailUntil[d.uid] = now + 1
        local last = Hook.LastFull[d.id]
        if not last or now - last > 120 then
            Hook.LastFull[d.id] = now
            Hook.send("full", "Inventori penuh: " .. itemName(d.id) .. " tidak bisa diambil lagi")
        end
        return false
    end

    d.taking = true -- cegah diambil dobel
    -- langsung hilang dari layar (sama seperti game saat memungut drop)
    d.flown = true
    if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = false end) end
    local ok, taken
    if type(worldTake) == "function" then
        ok, taken = pcall(worldTake, d.uid, amount) -- cara game baru
    else
        ok, taken = pcall(TakeDropRemote.InvokeServer, TakeDropRemote, d.uid, amount)
    end
    d.taking = false

    if not (ok and type(taken) == "number" and taken > 0) then
        State.CollectFail += 1
        d.refused = os.clock() -- tanda ditolak, sama seperti game
        DropFailUntil[d.uid] = os.clock() + 1 -- coba lagi 1 detik lagi (sama seperti game)
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
    if Drops.list and Drops.update and table.find(Drops.list, d) then
        pcall(Drops.update, d, d.n - taken) -- kurangi / hapus drop seperti game
    end
    State.Collected += taken
    Stats.Items[d.id] = (Stats.Items[d.id] or 0) + taken
    State.LastAction = "Collect " .. itemName(d.id) .. " x" .. taken
    return true
end

local function inTile(t, x, y)
    return x >= t.x - 0.15 and x < t.x + 1.15 and y >= t.y - 0.15 and y < t.y + 1.15
end

-- ---------- Collector cepat ----------
-- Cek daftar drop TIAP FRAME. Drop di area langsung diambil, semuanya sekaligus
-- (paralel), jadi tidak antri menunggu balasan server satu per satu.
--   Auto Farm  : drop di tile yang dipilih di Grid
--   Clear / Farmer : drop di sekitar karakter
local OffsetParse = {}
local nextDropScan = 0

local function canTry(d, now)
    if type(d) ~= "table" or d.taking or (d.n or 0) <= 0 or type(d.x) ~= "number" then return false end
    if d.armed == false and d.id ~= 112 then return false end
    local fail = DropFailUntil[d.uid]
    return not (fail and now < fail)
end

local function collectTick()
    local offs = farmOffsets()
    local farmArea = (State.AutoCollect or State.Override ~= nil) and next(offs) ~= nil
    local nearArea = State.CollectAround or (Clear.Running and Clear.Collect) or (Farmer.Running and Farmer.Collect)
        or Pabrik.Running or Build.Running or Splice.Roaming
    if not farmArea and not nearArea then return end

    local list = Drops.list
    if not list then
        local now = os.clock()
        if now >= nextDropScan then -- cari daftar drop paling sering tiap 5 detik
            nextDropScan = now + 5
            findDropRefs()
        end
        return
    end
    if #list == 0 then return end

    local ok, s = false, nil
    if Refs.State then ok, s = pcall(Refs.State) end
    if not (ok and type(s) == "table" and type(s.x) == "number") then return end
    local cx, cy = s.x, s.y - 0.475
    local ptx, pty = getPlayerTile()
    local now = os.clock()
    local R = (State.CollectRadius or 3) + 0.2
    -- tempat drop pabrik tidak ikut diambil lagi
    local z = Pabrik.Zone
    if z and z.world ~= (Refs.World and rawget(Refs.World, "name")) then z = nil end

    for i = #list, 1, -1 do
        local d = list[i]
        if canTry(d, now) and not (z and math.abs(d.x - z.x) <= 2.5 and math.abs(d.y - z.y) <= 2.5) then
            local hit = nearArea and math.abs(d.x - cx) <= R and math.abs(d.y - cy) <= R
            if not hit and farmArea and ptx then
                for key in pairs(offs) do
                    local o = OffsetParse[key]
                    if not o then
                        local dx, dy = string.match(key, "^(-?%d+),(-?%d+)$")
                        o = { tonumber(dx), tonumber(dy) }
                        OffsetParse[key] = o
                    end
                    if inTile({ x = ptx + o[1], y = pty + o[2] }, d.x, d.y) then
                        hit = true
                        break
                    end
                end
            end
            if hit then task.spawn(takeDrop, d) end
        end
    end
end

table.insert(Connections, RunService.Heartbeat:Connect(function()
    if alive() then collectTick() end
end))

-- Tunggu sebentar sampai drop di tile ini terambil (supaya tidak tertimpa block baru)
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
    local txt = "Status   : " .. (State.Running and "JALAN" or "BERHENTI")
        .. "\nBlock    : " .. (sel and (itemName(sel) .. " x" .. invCount(sel)) or "-")
        .. "\nKarakter : " .. (px and ("(" .. px .. "," .. py .. ")") or "tidak di world")
        .. "\nTile     : " .. offsetsText()
        .. "\nPlace/Break/Collect : " .. State.Placed .. " / " .. State.Broken .. " / " .. State.Collected
        .. (State.CollectFail > 0 and (" (ditolak " .. State.CollectFail .. ")") or "")
        .. "\nAksi     : " .. State.LastAction
    if txt == lastStatusText then return end
    lastStatusText = txt
    task.defer(function()
        pcall(function() UI.Status:SetDesc(txt) end)
    end)
end

---------------------------------------------------------------------
-- MODE LITE (matikan particle + suara)
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
-- MISC: walkspeed, infinite jump, fly + tembus block
---------------------------------------------------------------------
-- Infinite jump: game dibuat mengira ada Antigravity Generator, jadi bisa lompat di udara
local OrigJammerOn = nil
local function infJumpWrapper(id, ...)
    -- dimatikan saat Clear / Farmer jalan (lompat harus normal)
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

local function setGhost(on)
    Misc.Ghost = on
    if not on then
        Misc.UpHeld, Misc.DownHeld = false, false
        if Refs.World then Refs.World.ghost = false end
    end
    if UI.FlyPad then UI.FlyPad.Enabled = on end
end

local function setSpeed(pct)
    Misc.Speed = math.clamp(math.floor(tonumber(pct) or 100), 50, 500)
    if Misc.Speed == 100 and Refs.World then Refs.World.speedScale = 1 end
end

-- Tombol gerak game dibaca dari WorldMenu.isDown. Dibungkus supaya
-- tombol ▲/▼ Fly bisa dipakai, dan Clear / Farmer bisa "menekan" tombol sendiri.
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
    return OrigIsDown(saved, key, ...)
end

if MenuModOk and type(MenuModule) == "table" and type(rawget(MenuModule, "isDown")) == "function" then
    OrigIsDown = rawget(MenuModule, "isDown")
    MenuModule.isDown = isDownWrapper
end

-- Pasang walkspeed & fly tiap frame (game bisa menimpanya)
table.insert(Connections, RunService.Heartbeat:Connect(function()
    local w = Refs.World
    if not w or not alive() then return end
    if Misc.Speed ~= 100 then w.speedScale = Misc.Speed / 100 end
    if Misc.Ghost and w.ghost ~= true then w.ghost = true end
end))

---------------------------------------------------------------------
-- FARM LOOP: place semua dulu, baru break satu per satu
---------------------------------------------------------------------
local stopFarm

local function waitMs(ms)
    task.wait(math.max(ms or 0, 10) / 1000)
    return State.Running and alive()
end

local function validate()
    local doPlace = farmMode() ~= "Break saja"
    if not Refs.World then return "Data world belum ketemu. Tekan 'Hubungkan ke game'" end
    if next(farmOffsets()) == nil then return "Pilih tile dulu di Grid Tile" end
    if not getPlayerTile() then return "Kamu belum masuk world" end
    if doPlace and not farmBlock() then return "Pilih block dari inventori" end
    return nil
end

-- Rayman's Fist sedang dipakai? (fungsi asli game)
local function raymanOn()
    local w = Refs.World
    local f = w and rawget(w, "raymanOn")
    if type(f) ~= "function" then return false end
    local ok, on = pcall(f)
    return ok and on == true
end

-- Cari 2-3 tile target yang segaris dari karakter (8 arah, jarak 1-3),
-- sama seperti pukulan Rayman di game.
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

-- Kabarkan gerakan Rayman ke server (paket yang sama dengan game saat pukulan Rayman)
local function raymanAct(dir)
    local ok, s = pcall(Refs.State)
    if not ok or type(s) ~= "table" or not s.x then return end
    if NetOk and type(Net) == "table" and Net.act then
        pcall(Net.act.send, { kind = 4, x = s.x + dir[1], y = s.y - 0.475 + dir[2] })
    end
end

local function farmLoop(runId)
    local lastStatus = 0
    while State.Running and alive() and State.RunId == runId do
        local doPlace = farmMode() ~= "Break saja"
        local doBreak = farmMode() ~= "Place saja"

        local px, py = getPlayerTile()
        if not px then
            stopFarm("Karakter tidak ditemukan (keluar world?)")
            return
        end

        local tiles = {}
        for _, o in ipairs(sortedOffsets()) do
            tiles[#tiles + 1] = { x = px + o.dx, y = py + o.dy }
        end

        local acted, outOfBlock = false, false

        -- 1) Place semua tile kosong (tunggu drop di tile itu terambil dulu)
        if doPlace then
            for _, t in ipairs(tiles) do
                if not State.Running then break end
                if State.AutoCollect then waitTileDrops(t, 0.5) end
                local r = tryPlace(t.x, t.y)
                if r == "habis" then
                    outOfBlock = true
                    break
                elseif r == "place" then
                    acted = true
                    if not waitMs(State.PlaceMs) then break end
                end
            end
        end

        -- 2) Pukul tile sampai habis (block depan lalu background).
        --    Server hanya terima 1 pukulan tiap ~0.22 detik (tangan biasa), jadi multi target
        --    = beberapa tile dipukul BERGANTIAN (sama seperti 2 jari). Semua tile benar-benar pecah.
        --    Pakai Rayman's Fist: 2-3 tile segaris dipukul sekali jalan (seperti Rayman asli).
        if doBreak then
            local K = math.clamp(math.floor(State.MultiTarget or 1), 1, 5)
            local nextI, active = 1, {}
            while State.Running and alive() do
                while #active < K and nextI <= #tiles do
                    local t = tiles[nextI]
                    nextI += 1
                    active[#active + 1] = { x = t.x, y = t.y, n = 0 }
                end
                if #active == 0 then break end

                -- pilih tile yang dipukul sekarang
                local hits, rayDir = nil, nil
                if K > 1 and raymanOn() then
                    hits, rayDir = raymanLine(px, py, active)
                end
                if not rayDir then hits = { active[1] } end -- giliran depan antrian

                local t0 = os.clock()
                if rayDir then raymanAct(rayDir) end
                local hit, broke = false, false
                for i, a in ipairs(hits) do
                    if not State.Running then break end
                    if i > 1 then task.wait(0.05) end -- jarak antar tile seperti animasi Rayman
                    local r = tryBreak(a.x, a.y)
                    a.n += 1
                    if r then hit, acted = true, true end
                    if r == "broke" then broke = true end
                    -- selesai kalau kosong / tidak bisa dipecah / sudah habis sampai background
                    if r == nil or a.n > 80 or (r == "broke" and not breakableAt(a.x, a.y)) then
                        a.done = true
                    end
                    a.used = true
                end

                -- tile yang barusan dipukul pindah ke belakang antrian (bergantian)
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
                    if rayDir then gap = math.max(gap, 0.35) end -- jeda Rayman asli
                    local rest = gap - (os.clock() - t0)
                    if rest > 0.005 then task.wait(rest) end
                    if not (State.Running and alive()) then break end
                end
                -- drop diambil otomatis oleh collector cepat
                if broke and State.AfterBreakMs > 0 then task.wait(State.AfterBreakMs / 1000) end
            end
        end

        if not State.Running or not alive() then break end

        if not acted then
            local sel = farmBlock()
            if outOfBlock or (doPlace and sel and invCount(sel) <= 0) then
                stopFarm("Block " .. itemName(sel) .. " di inventori habis")
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
    if State.Override then return end -- dijalankan Pabrik: tombol Auto Farm tidak diubah
    if UI.FarmToggle then pcall(function() UI.FarmToggle:Set(State.Running) end) end
    if UI.GridStart and UI.GridMode ~= "pabrik" then
        UI.GridStart.Text = State.Running and "STOP" or "START"
        UI.GridStart.BackgroundColor3 = State.Running and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(46, 160, 90)
    end
end

stopFarm = function(reason)
    State.Running = false
    setRunningVisual()
    if reason and not State.Quiet then
        notify("Auto Farm berhenti", reason, 4)
        Hook.send("stop", "Auto Farm berhenti: " .. reason)
    end
    updateStatus()
end

-- Auto Farm, Clear & Farmer tidak boleh jalan bersamaan
local stopClear, stopFarmer

local function startFarm()
    if State.Running then return end
    local err = validate()
    if err then
        stopFarm(err)
        return
    end
    if Splice.Running and Splice.stop then Splice.stop("Dihentikan karena Auto Farm dimulai") end
    if Pabrik.Running and Pabrik.stop then Pabrik.stop("Dihentikan karena Auto Farm dimulai") end
    if Build.Running and Build.stop then Build.stop("Dihentikan karena Auto Farm dimulai") end
    if Clear.Running and stopClear then stopClear("Dihentikan karena Auto Farm dimulai") end
    if Farmer.Running and stopFarmer then stopFarmer("Dihentikan karena Auto Farm dimulai") end
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    setRunningVisual()
    updateStatus()
    task.spawn(farmLoop, State.RunId)
end


-- Fungsi untuk UI dikumpulkan di sini (Luau batasi 200 variabel per file)
local Auto = {}
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
---------------------------------------------------------------------
-- GERAK OTOMATIS (dipakai Clear World & Farmer)
---------------------------------------------------------------------
-- Cara kerja:
--   - Jalan dicari pakai A* sesuai fisika game (jalan, jatuh, lompat naik 1-3 tile).
--   - Karakter digerakkan dengan "menekan" tombol, sama seperti main biasa.
--   - Tidak pakai fly / noclip karena server me-rollback.
--   - Kalau tidak ada pijakan, taruh block dari inventori (jembatan / tangga).
local floor, abs = math.floor, math.abs

local Move = { Placed = 0 }  -- jumlah block pijakan yang dipasang
local BadEdge = {}           -- jalur yang barusan gagal (dihindari dulu)
local ClearFail, FarmerFail = {}, {}
local BreakTimes = {}        -- tile yang terus balik lagi setelah pecah
local Reach = nil            -- daftar tile yang bisa dijangkau (cache)

local function autoOn()
    return (Clear.Running or Farmer.Running or Splice.Roaming or Pabrik.Running or Build.Running or Move.Homing)
        and alive()
end

local function setMoveStatus(text)
    if Clear.Running then
        Clear.Status = text
    elseif Farmer.Running then
        Farmer.Status = text
    elseif Splice.Roaming then
        Splice.Status = text
    elseif Build.Running then
        Build.Status = text
    elseif Pabrik.Running then
        Pabrik.Status = text
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

-- Tile padat? (sama dengan cek tabrakan game)
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
    if it.vip then -- pintu VIP: padat kalau kamu tidak punya akses
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

-- Tile berbahaya (lava, duri, laser)
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

-- Ada pijakan aman di bawah tile ini?
local function realSupport(x, y)
    return not hazardAt(x, y + 1) and (solidAt(x, y + 1) or platformAt(x, y + 1))
end

-- Tile masuk jangkauan? (bentuk kotak di sekitar badan)
local function stateReaches(s, tx, ty, R)
    return abs(tx + 0.5 - s.x) <= R and abs(ty + 0.5 - (s.y - 0.475)) <= R
end

-- Boleh pecah di sini? (cek lock)
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

-- ---------- Block pijakan ----------
local function scaffoldId()
    local id, use
    if Clear.Running then
        id, use = Clear.ScaffoldId, Clear.UseBlock
    elseif Farmer.Running then
        id, use = Farmer.ScaffoldId, Farmer.UseBlock
    elseif Build.Running then
        id, use = Build.BlockId, Build.UseBlock
    end
    if use and id and invCount(id) > 0 then return id end
    return nil
end

-- Boleh taruh block di sini? (kosong + izin bangun)
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
    sendSetTile("fg", x, y, id) -- place lewat fungsi game
    if Refs.Inv then pcall(function() Refs.Inv:remove(id, 1) end) end
    Move.Placed += 1
    return true
end

local function worldVersion()
    return Clear.Broken + Farmer.Harvested + Farmer.Planted + Move.Placed + Splice.Planted
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

-- ---------- Antrian prioritas untuk A* ----------
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
-- Cari jalan termurah ke tempat yang bisa memukul salah satu target.
-- Langkah yang bisa dipakai:
--   walk   : geser 1 tile (+ taruh block kalau perlu)
--   fall   : jalan ke pinggir lalu jatuh
--   jump   : lompat naik 1-3 tile
--   gap    : lompati lubang 1-2 tile
--   pillar : lompat lalu taruh block di bawah kaki (naik 1)
local MAX_EXPAND = 8000
local BLOCK_COST = 2

local function reachOffsets(R)
    return floor(R), math.ceil(-R + 0.025), floor(R + 0.025)
end

local function astar(sx, sy, goals, gx, gy, R, useBlock)
    local w = Refs.World
    if not w then return nil, false, {} end
    local W, H = w.w, w.h
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

    local function h(x, y)
        local dx = abs(gx - x) - R
        local dyRaw = gy - y
        local dy = abs(dyRaw) - R
        local vw = (dyRaw < 0) and 1.5 or 0.5
        return (dx > 0 and dx or 0) + vw * (dy > 0 and dy or 0)
    end

    local function isGoal(nx, ny)
        for ty = ny + dyLo, ny + dyHi do
            if ty >= 0 and ty < H then
                local base = ty * W
                for tx = nx - dxm, nx + dxm do
                    -- jangan berdiri tepat di atas target
                    if tx >= 0 and tx < W and goals[base + tx] and not (tx == nx and ty == ny + 1) then
                        return true
                    end
                end
            end
        end
        return false
    end

    local ex, ey, ek, ec, eb = {}, {}, {}, {}, {}
    local n = 0
    local function add(x, y, kind, cost, build)
        n += 1
        ex[n], ey[n], ek[n], ec[n], eb[n] = x, y, kind, cost, build
    end

    local function expand(x, y)
        n = 0
        for s = -1, 1, 2 do
            local ax = x + s
            if open(ax, y) then
                if sup(ax, y) then
                    add(ax, y, "walk", 1, false)
                else
                    if buildable(ax, y + 1) then
                        add(ax, y, "walk", 1 + BLOCK_COST, true)
                    end
                    -- jatuh sampai ketemu pijakan
                    local fy = y + 1
                    while fy < H and fy - y <= 40 and open(ax, fy) and not sup(ax, fy) do
                        fy += 1
                    end
                    if fy < H and open(ax, fy) and sup(ax, fy) then
                        add(ax, fy, "fall", 1 + 0.5 * (fy - y), false)
                    end
                    -- lompati lubang 1-2 tile
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
                                        add(bx, y + k, "gap", dist + 0.5 + 0.5 * k, false)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- lompat naik (atas kepala harus kosong)
            for dy = 1, 3 do
                if not open(x, y - dy) then break end
                if open(x, y - dy - 1) and open(ax, y - dy) and sup(ax, y - dy) and open(ax, y - dy - 1) then
                    add(ax, y - dy, "jump", 1 + 1.5 * dy, false)
                end
            end
        end
        -- naik 1 pakai block
        if useBlock and open(x, y - 1) and open(x, y - 2) and open(x, y - 3) and buildable(x, y) then
            add(x, y - 1, "pillar", 2 + BLOCK_COST, true)
        end
        return n
    end

    local startI = sy * W + sx
    local g, came, kind, buildOf, closed = { [startI] = 0 }, {}, {}, {}, {}
    local hf, hi, hn = {}, {}, 0
    hn = heapPush(hf, hi, hn, h(sx, sy), startI)
    local expanded = 0
    local now = os.clock()

    while hn > 0 do
        local cur
        cur, hn = heapPop(hf, hi, hn)
        if not closed[cur] then
            closed[cur] = true
            local cx, cy = cur % W, cur // W
            if isGoal(cx, cy) then
                local path = {}
                local i = cur
                while i ~= startI do
                    local p = came[i]
                    table.insert(path, 1, {
                        fx = p % W, fy = p // W, x = i % W, y = i // W,
                        kind = kind[i], build = buildOf[i], key = p * WH + i,
                    })
                    i = p
                end
                return path, false, closed
            end
            expanded += 1
            if expanded > MAX_EXPAND then return nil, false, closed end
            if expanded % 400 == 0 then
                task.wait()
                if not autoOn() then return nil, false, closed end
            end
            local gc = g[cur]
            local cnt = expand(cx, cy)
            for k = 1, cnt do
                local ni = ey[k] * W + ex[k]
                if not closed[ni] then
                    local bad = BadEdge[cur * WH + ni]
                    if not (bad and bad > now) then
                        local ng = gc + ec[k]
                        local old = g[ni]
                        if old == nil or ng < old then
                            g[ni], came[ni], kind[ni], buildOf[ni] = ng, cur, ek[k], eb[k]
                            hn = heapPush(hf, hi, hn, ng + h(ex[k], ey[k]), ni)
                        end
                    end
                end
            end
        end
    end
    return nil, true, closed -- tidak ada jalan sama sekali
end

-- Semua tile yang bisa dijangkau dari area ini
local function reachableTileSet(closed, W, R)
    local set = {}
    local dxm, dyLo, dyHi = reachOffsets(R)
    local n = 0
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
        if n % 500 == 0 then task.wait() end
    end
    return set
end

-- Simpan daftar tile terjangkau, supaya tile di seberang jurang langsung dilewati
-- (tidak cari jalan berulang yang bikin karakter diam).
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

-- ---------- Gerakkan karakter ----------
local function releaseInput()
    AutoInput.left, AutoInput.right, AutoInput.jump, AutoInput.down = false, false, false, false
end

local function frame()
    task.wait()
    return autoOn()
end

local function waitAuto(ms)
    task.wait(math.max(ms or 0, 30) / 1000)
    return autoOn()
end

-- Jalan ke targetX, lepas tombol saat sudah cukup dekat untuk berhenti
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

-- Jalan sampai berdiri di tengah tile tujuan
local function execWalk(tx, ty)
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
        steerX(s, cx, 0.1)
        if nx == tx and abs(s.x - cx) <= 0.2 and s.grounded and abs(s.vx or 0) < 2 then
            AutoInput.left, AutoInput.right = false, false
            return true
        end
        if os.clock() - t0 > limit then return false end
    end
    return false
end

-- Jalan ke pinggir lalu jatuh ke tile tujuan
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

-- Lompat naik ke tile sebelah
local function execJump(e)
    if not execWalk(e.fx, e.fy) then return false end
    local dy = e.fy - e.y
    local top = e.y + 1                               -- tinggi kaki di tujuan
    local releaseY = top - ((dy == 1) and 0 or 0.4)   -- lepas lompat di sini (kepala tidak kebentur)
    local cx = e.x + 0.5
    releaseInput()
    if not frame() then return false end              -- lepas 1 frame supaya lompat terbaca
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

-- Lompati lubang: ancang-ancang, lompat di ujung, rem di udara
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

-- Naik 1 tile: lompat, taruh block di bawah kaki, lalu mendarat di atasnya.
-- Block ditaruh agak telat supaya posisi di server sudah ikut naik.
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

local function followPath(path)
    local i = 1
    while i <= #path do
        if not autoOn() then return false end
        local e = path[i]
        local last, ok = i, false
        if e.kind == "walk" then
            -- langkah searah digabung jadi satu gerakan
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
                -- perlu block: taruh block di depan, lalu melangkah
                ok = true
                for j = i, last do
                    local st = path[j]
                    if st.build and not realSupport(st.x, st.y) then
                        setMoveStatus(("Taruh block pijakan (%d,%d)"):format(st.x, st.y + 1))
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
                setMoveStatus(("Jalan ke (%d,%d)"):format(path[last].x, path[last].y))
                ok = execWalk(path[last].x, path[last].y)
            end
        elseif e.kind == "pillar" then
            setMoveStatus(("Naik pakai block ke (%d,%d)"):format(e.x, e.y))
            ok = execPillar(e)
        elseif e.kind == "fall" then
            setMoveStatus(("Turun ke (%d,%d)"):format(e.x, e.y))
            ok = execFall(e)
        elseif e.kind == "jump" then
            setMoveStatus(("Lompat ke (%d,%d)"):format(e.x, e.y))
            ok = execJump(e)
        elseif e.kind == "gap" then
            setMoveStatus(("Lompati lubang ke (%d,%d)"):format(e.x, e.y))
            ok = execGap(e)
        end
        releaseInput()
        if not ok then
            BadEdge[e.key] = os.clock() + 20 -- hindari jalur ini sementara
            return false
        end
        i = last + 1
    end
    return true
end

-- Cari jalan ke grup target, lalu jalan ke sana
local function travelGroup(sx, sy, group, R, useBlock, skipTbl, failTbl)
    local w = Refs.World
    local goals = {}
    for _, t in ipairs(group) do goals[t.idx] = true end
    local first = group[1]
    setMoveStatus(("Cari jalan A* ke (%d,%d)"):format(first.x, first.y))
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
    -- tidak ada jalan ke grup ini
    for _, t in ipairs(group) do skipTile(skipTbl, t.idx, exhausted and 60 or 30) end
    if exhausted and w then storeReach(sy * w.w + sx, R, useBlock, closed) end
    releaseInput()
    return false
end

local function autoBegin()
    AutoInput.active = true
    releaseInput()
    Reach = nil
    if Misc.Ghost then
        setGhost(false) -- fly dimatikan (kena rollback)
        if UI.GhostToggle then pcall(function() UI.GhostToggle:Set(false) end) end
    end
end

local function autoEnd()
    if Clear.Running or Farmer.Running or Splice.Roaming or Pabrik.Running or Build.Running or Move.Homing then
        return
    end
    AutoInput.active = false
    releaseInput()
end

local function blockText(useBlock, id)
    if not useBlock then return "mati" end
    if not id then return "belum dipilih" end
    local n = invCount(id)
    return itemName(id) .. " x" .. n .. (n <= 0 and " (habis)" or "")
end

---------------------------------------------------------------------
-- CLEAR WORLD: bersihkan dari baris atas ke bawah, 2 baris sekali sapu
---------------------------------------------------------------------
-- Boleh dipecah? (lock, vending, display tidak disentuh)
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

-- Layer yang dipecah: fg dulu, lalu bg
local function clearLayerAt(x, y)
    local w = Refs.World
    local sp = w and w.spawn
    if sp ~= nil and (typeof(sp) == "Vector2" or type(sp) == "table") and x == sp.X and y == sp.Y then
        return nil
    end
    local fg = tileAt("fg", x, y)
    if fg == nil then return nil end
    if fg ~= 0 then
        if clearCanBreak(fg) then return "fg", fg end
        return nil -- fg tidak bisa dipecah, bg juga tidak
    end
    if Clear.IncludeBg then
        local bg = tileAt("bg", x, y)
        if bg and bg ~= 0 and clearCanBreak(bg) then return "bg", bg end
    end
    return nil
end

-- Cari baris paling atas yang masih ada block
local function scanTopRow()
    local w = Refs.World
    local W, H = w.w, w.h
    local now = os.clock()
    for y = 0, H - 1 do
        local frow, brow = w.fg[y], w.bg[y]
        for x = 0, W - 1 do
            local fid = frow and frow[x] or 0
            local bid = brow and brow[x] or 0
            if (fid ~= 0 or (Clear.IncludeBg and bid ~= 0)) and clearLayerAt(x, y)
                and not skipped(Clear.Skip, y * W + x, now) then
                return y
            end
        end
    end
    return nil
end

local function countRemaining()
    local w = Refs.World
    if not w then return -1 end
    local W, H = w.w, w.h
    local n, scanned = 0, 0
    for y = 0, H - 1 do
        local frow, brow = w.fg[y], w.bg[y]
        for x = 0, W - 1 do
            local fid = frow and frow[x] or 0
            local bid = brow and brow[x] or 0
            if (fid ~= 0 or (Clear.IncludeBg and bid ~= 0)) and clearLayerAt(x, y) then n += 1 end
        end
        scanned += W
        if scanned >= 8000 then
            scanned = 0
            task.wait()
        end
    end
    return n
end

-- Arah sapu. Zig-zag: arah dipilih sekali per baris (dari ujung terdekat),
-- lalu dipegang sampai baris selesai supaya tidak bolak-balik.
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

-- Semua target di baris ini, urut sesuai arah sapu.
-- Tile yang tidak terjangkau langsung dilewati.
local function bandTargets(top, bottom, dir, filter)
    local w = Refs.World
    local W = w.w
    local list = {}
    local now = os.clock()
    for y = top, math.min(bottom, w.h - 1) do
        for x = 0, W - 1 do
            local idx = y * W + x
            if clearLayerAt(x, y) and not skipped(Clear.Skip, idx, now) then
                if filter and not filter[idx] then
                    skipTile(Clear.Skip, idx, 60) -- di seberang jurang / tidak ada jalan
                elseif canWorkAt(x, y) then
                    list[#list + 1] = { x = x, y = y, idx = idx }
                else
                    skipTile(Clear.Skip, idx, 300) -- tidak ada izin
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.x ~= b.x then return a.x * dir < b.x * dir end
        return a.y < b.y
    end)
    return list
end

-- Tile yang bisa dipukul dari sini. Pijakan kaki dipecah paling akhir.
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

-- Kalau pijakan dipecah, jatuh berapa tile? (nil = jatuh ke lava/duri)
local function fallAfterBreak(s, x, footRow)
    local colA, colB = floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001)
    for c = colA, colB do
        if c ~= x and (solidAt(c, footRow) or platformAt(c, footRow)) then return 0 end -- masih menapak kolom lain
    end
    local w = Refs.World
    for y = footRow + 1, math.min(w.h - 1, footRow + 60) do
        if hazardAt(x, y) then return nil end
        if solidAt(x, y) or platformAt(x, y) then return y - footRow end
    end
    return 60
end

-- Pukul satu tile sampai bersih (fg lalu bg)
local function clearBreakTile(t)
    local x, y, idx = t.x, t.y, t.idx
    local layer, id = clearLayerAt(x, y)
    if not layer then return end
    local hits, maxHits = 0, hitsNeeded(id) * 3 + 6
    while Clear.Running and alive() do
        layer, id = clearLayerAt(x, y)
        if not layer then return end
        local r = tryBreak(x, y, Clear.IncludeBg)
        if r == nil then
            skipTile(Clear.Skip, idx, 60)
            return
        end
        if r == "broke" then
            Clear.Broken += 1
            Clear.Status = "Pecah " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            BreakTimes[idx] = (BreakTimes[idx] or 0) + 1
            if BreakTimes[idx] > 6 then -- server terus mengembalikan tile ini
                skipTile(Clear.Skip, idx, 120)
                return
            end
            hits = 0
            local _, nid = clearLayerAt(x, y)
            if nid then maxHits = hitsNeeded(nid) * 3 + 6 end
        else
            hits += 1
            Clear.Status = "Pukul " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            if hits > maxHits then
                skipTile(Clear.Skip, idx, 45)
                return
            end
        end
        if not waitAuto(State.BreakMs) then return end
        if r == "broke" then
            local s = playerState()
            if not s or not s.grounded then return end -- jatuh, cek ulang posisi
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
                Clear.Status = ("Lewati (%d,%d): di bawahnya berbahaya"):format(t.x, t.y)
            elseif d > 3 then
                -- di bawahnya jurang: pecah nanti dari samping
                skipIt = true
                Clear.Status = ("Lewati pijakan (%d,%d): di bawahnya jurang"):format(t.x, t.y)
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
    if not UI.ClearStatus then return end
    local txt = "Status   : " .. (Clear.Running and "JALAN" or "BERHENTI")
        .. "\nBaris    : " .. (Clear.TopRow >= 0 and (Clear.TopRow .. "-" .. (Clear.TopRow + 1)) or "-")
        .. "  | arah: " .. ((Clear.Dir == -1 and Clear.Sweep == "Zig-zag") and "kanan→kiri" or "kiri→kanan")
        .. "\nDipecah  : " .. Clear.Broken .. "  | collect: " .. State.Collected
        .. "\nSisa     : " .. (Clear.Remaining >= 0 and tostring(Clear.Remaining) or "-")
        .. "  | dilewati: " .. skippedCount(Clear.Skip)
        .. "\nPijakan  : " .. blockText(Clear.UseBlock, Clear.ScaffoldId) .. "  | dipasang: " .. Move.Placed
        .. "\nAksi     : " .. Clear.Status
    if txt == lastClearText then return end
    lastClearText = txt
    task.defer(function()
        pcall(function() UI.ClearStatus:SetDesc(txt) end)
    end)
end

local function clearLoop()
    local idle, lastUi, lastCount = 0, 0, -10
    while Clear.Running and alive() do
        task.wait()
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
            Clear.Status = "Menunggu karakter / world..."
            task.wait(0.5)
            continue
        end
        if not s.grounded then
            releaseInput() -- masih di udara, tunggu mendarat
            continue
        end
        releaseInput()

        local topRow = scanTopRow()
        if not topRow then
            local remaining = countRemaining()
            Clear.Remaining = remaining
            if remaining == 0 then
                stopClear("World sudah bersih!")
                return
            end
            idle += 1
            if idle >= 3 then
                stopClear(("Selesai. Sisa %d tile tidak bisa dijangkau / dipecah"):format(remaining))
                return
            end
            Clear.Status = ("Sisa %d tile dilewati, coba ulang (%d/3)..."):format(remaining, idle)
            updateClearStatus()
            table.clear(Clear.Skip)
            table.clear(ClearFail)
            table.clear(BadEdge)
            Reach = nil
            if not waitAuto(2000) then break end
            continue
        end

        Clear.TopRow = topRow
        local bottom = topRow + 1 -- 2 baris dibersihkan dulu sebelum turun
        local dir = bandDir(topRow, s)

        -- 1) Pecahkan yang terjangkau
        local list = clearInReach(s, bottom, dir)
        if #list > 0 then
            if clearBreakList(list, s) > 0 then idle = 0 end
            continue
        end

        -- 2) Jalan ke bagian berikutnya
        local R = punchReach() - 0.35
        local useBlock = scaffoldId() ~= nil
        local sx, sy = startNode(s)
        local band = bandTargets(topRow, bottom, dir, reachFilter(sy * w.w + sx, R, useBlock))
        if #band > 0 then
            -- tujuan: 5 kolom berikutnya sesuai arah sapu
            local group = {}
            for _, t in ipairs(band) do
                if (t.x - band[1].x) * dir <= 4 then group[#group + 1] = t end
            end
            travelGroup(sx, sy, group, R, useBlock, Clear.Skip, ClearFail)
        end
    end
    releaseInput()
end

local function setClearVisual()
    if UI.ClearToggle then pcall(function() UI.ClearToggle:Set(Clear.Running) end) end
end

stopClear = function(reason)
    Clear.Running = false
    autoEnd()
    setClearVisual()
    Clear.Status = reason or "Dihentikan"
    if reason then
        notify("Auto Clear", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("stop", "Auto Clear berhenti: " .. reason) end
    end
    updateClearStatus()
end

local function checkAutoStart()
    if not Refs.World then return "Data world belum ketemu. Tekan 'Hubungkan ke game'" end
    if not Refs.Punch then return "Fungsi pukul game belum ketemu. Tekan 'Hubungkan ke game'" end
    if not OrigIsDown then return "Kontrol gerak game (WorldMenu.isDown) tidak ketemu" end
    if not playerState() then return "Kamu belum masuk world" end
    return nil
end

local function startClear()
    if Clear.Running then return end
    local err = checkAutoStart()
    if err then
        notify("Auto Clear", err, 4)
        setClearVisual()
        return
    end
    if Clear.UseBlock and (not Clear.ScaffoldId or invCount(Clear.ScaffoldId) <= 0) then
        notify("Auto Clear", "Block pijakan belum dipilih / habis: jalan tanpa block pijakan", 5)
    end
    if Splice.Running and Splice.stop then Splice.stop("Dihentikan karena Auto Clear dimulai") end
    if Pabrik.Running and Pabrik.stop then Pabrik.stop("Dihentikan karena Auto Clear dimulai") end
    if Build.Running and Build.stop then Build.stop("Dihentikan karena Auto Clear dimulai") end
    if State.Running then stopFarm("Dihentikan karena Auto Clear dimulai") end
    if Farmer.Running then stopFarmer("Dihentikan karena Auto Clear dimulai") end
    table.clear(Clear.Skip)
    table.clear(ClearFail)
    table.clear(BadEdge)
    table.clear(BreakTimes)
    Clear.Broken = 0
    Clear.Remaining = -1
    Clear.TopRow = -1
    Clear.DirRow, Clear.Dir = nil, nil
    Clear.Status = "Mulai..."
    Clear.Running = true
    autoBegin()
    setClearVisual()
    updateClearStatus()
    task.spawn(function()
        local ok, e = pcall(clearLoop)
        if not ok then
            warn("[Fian792] Auto Clear error: " .. tostring(e))
            if Clear.Running then stopClear("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- FARMER: panen pohon yang siap + tanam seed
---------------------------------------------------------------------
-- Pohon siap kalau: waktu server >= waktu tanam + lama tumbuh (sama dengan game).
-- Seed ditanam di tile kosong yang di bawahnya ada block.
local function findTreeRefs()
    Refs.Trees = nil
    local ev = WorldRemotes:FindFirstChild("TreeChanged")
    if not (ev and getconnections) then return false end
    local ok, conns = pcall(getconnections, ev.OnClientEvent)
    if not ok or type(conns) ~= "table" then return false end
    for _, c in ipairs(conns) do
        local okf, fn = pcall(function() return c.Function end)
        if okf and type(fn) == "function" then
            local ups = getUpvalues(fn)
            local cands = {}
            for i = 1, 12 do
                local u = ups[i]
                if type(u) == "table" and u ~= Refs.World and rawget(u, "fg") == nil then
                    cands[#cands + 1] = u
                end
            end
            -- cari tabel pohon (isinya waktu tanam)
            for _, t in ipairs(cands) do
                local _, v = next(t)
                if type(v) == "table" and type(rawget(v, "p")) == "number" then
                    Refs.Trees = t
                    break
                end
            end
            if not Refs.Trees then
                for _, t in ipairs(cands) do
                    if next(t) == nil then
                        Refs.Trees = t
                        break
                    end
                end
            end
        end
        if Refs.Trees then break end
    end
    return Refs.Trees ~= nil
end

local function farmReach()
    return math.min(punchReach(), buildReach())
end

local function seedCount()
    return Farmer.SeedId and invCount(Farmer.SeedId) or 0
end

-- Kapan pohon ini siap panen (nil = bukan pohon)
local function treeReadyAt(x, y, id)
    local trees, w = Refs.Trees, Refs.World
    if not trees or not w then return nil end
    local it = ItemDB[id]
    if not (it and it.kind == "seed") then return nil end
    local t = trees[y * w.w + x]
    if type(t) ~= "table" or type(t.p) ~= "number" then return nil end
    return t.p + (it.grow or 0)
end

-- Bisa tanam seed di sini? (seedId kosong = seed Farmer)
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

-- Mesin panen & tanam dipakai bersama oleh Farmer dan Pabrik.
-- FC = pengaturan yang sedang dipakai (seed, area, kecepatan, dll).
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
        area = nil,      -- function(x, y): boleh panen di sini?
        plantSet = nil,  -- [idx] = true: hanya tanam di tile ini
        exclude = nil,   -- [idx] = true: jangan tanam di tile ini
        status = function(t) Farmer.Status = t end,
        onHarvest = function() Farmer.Harvested += 1 end,
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
    return (not FC.plantSet or FC.plantSet[idx]) and not (FC.exclude and FC.exclude[idx])
end

local function plantSeed(x, y)
    local id = FC.seed
    if not id or invCount(id) <= 0 then return false end
    sendSetTile("fg", x, y, id)
    if Refs.Inv then pcall(function() Refs.Inv:remove(id, 1) end) end
    FC.onPlant()
    FC.status("Tanam " .. itemName(id) .. " (" .. x .. "," .. y .. ")")
    return true
end

-- Panen & tanam semua yang terjangkau dari sini
local function farmerWorkInReach(s)
    local w = Refs.World
    local W = w.w
    local R = farmReach() - 0.08
    local cx, cy = s.x, s.y - 0.475
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local doPlant = FC.plant and fcSeeds() > 0
    local harvest, plant = {}, {}
    for ty = math.max(0, floor(cy - R - 0.5)), math.min(floor(cy + R + 0.5), w.h - 1) do
        for tx = math.max(0, floor(cx - R - 0.5)), math.min(floor(cx + R + 0.5), W - 1) do
            if stateReaches(s, tx, ty, R) then
                local idx = ty * W + tx
                if not skipped(FC.skip, idx, now) then
                    local id = fgIdAt(tx, ty)
                    if id ~= 0 and fcHarvestOk(tx, ty) then
                        local ra = treeReadyAt(tx, ty, id)
                        if ra and st >= ra then
                            if canWorkAt(tx, ty) then
                                harvest[#harvest + 1] = { x = tx, y = ty, idx = idx }
                            else
                                skipTile(FC.skip, idx, 120)
                            end
                        end
                    elseif doPlant and id == 0 and fcPlantOk(idx) and plantSpotOk(tx, ty, FC.seed) then
                        plant[#plant + 1] = { x = tx, y = ty, idx = idx }
                    end
                end
            end
        end
    end
    local function byX(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end
    table.sort(harvest, byX)
    table.sort(plant, byX)

    local done = 0
    for _, t in ipairs(harvest) do
        if not FC.run() or not alive() then return done end
        local cur = playerState()
        if not cur or not stateReaches(cur, t.x, t.y, R) then return done end
        local id = fgIdAt(t.x, t.y)
        local r = tryBreak(t.x, t.y, false) -- pohon siap: 1 pukulan = panen
        if r == "broke" then
            FC.onHarvest()
            FC.status("Panen " .. itemName(id) .. " (" .. t.x .. "," .. t.y .. ")")
        else
            skipTile(FC.skip, t.idx, 30)
        end
        done += 1
        if not waitAuto(FC.hms) then return done end
    end
    for _, t in ipairs(plant) do
        if not FC.run() or not alive() then return done end
        if fcSeeds() <= 0 then break end
        local cur = playerState()
        if not cur or not stateReaches(cur, t.x, t.y, R) then return done end
        if fgIdAt(t.x, t.y) == 0 then
            if not plantSeed(t.x, t.y) then break end
            done += 1
            if not waitAuto(FC.pms) then return done end
        end
    end
    return done
end

-- Cari target terdekat + kapan pohon berikutnya siap
local function farmerScan(px, py, maxN, filter)
    local w = Refs.World
    local W, H = w.w, w.h
    local best = {}
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local nextReady = nil
    local doPlant = FC.plant and fcSeeds() > 0
    local scanned = 0
    for y = 0, H - 1 do
        local frow, below = w.fg[y], w.fg[y + 1]
        for x = 0, W - 1 do
            local id = frow and frow[x] or 0
            local kind = nil
            if id ~= 0 then
                if fcHarvestOk(x, y) then
                    local ra = treeReadyAt(x, y, id)
                    if ra then
                        if st >= ra then
                            kind = "harvest"
                        elseif not nextReady or ra - st < nextReady then
                            nextReady = ra - st
                        end
                    end
                end
            elseif doPlant then
                local b = below and below[x] or 0
                if b ~= 0 and fcPlantOk(y * W + x) then kind = "plant" end
            end
            if kind then
                local idx = y * W + x
                if not skipped(FC.skip, idx, now) then
                    if filter and not filter[idx] then
                        skipTile(FC.skip, idx, 60)
                    else
                        local dx, dy = x - px, (y - py) * 1.3
                        local d = dx * dx + dy * dy - ((kind == "harvest") and 4 or 0) -- panen sedikit diutamakan
                        if #best < maxN or d < best[#best].d then
                            local ok
                            if kind == "harvest" then ok = canWorkAt(x, y) else ok = plantSpotOk(x, y, FC.seed) end
                            if ok then
                                local pos = #best + 1
                                while pos > 1 and best[pos - 1].d > d do pos -= 1 end
                                table.insert(best, pos, { x = x, y = y, idx = idx, d = d, kind = kind })
                                if #best > maxN then best[#best] = nil end
                            else
                                skipTile(FC.skip, idx, 120)
                            end
                        end
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
    return best, nextReady
end

local lastFarmerText = nil
local function updateFarmerStatus()
    if not UI.FarmerStatus then return end
    local seed = Farmer.SeedId
    local txt = "Status  : " .. (Farmer.Running and "JALAN" or "BERHENTI")
        .. "\nPanen   : " .. Farmer.Harvested .. "  | tanam: " .. Farmer.Planted .. "  | collect: " .. State.Collected
        .. "\nSeed    : " .. (seed and (itemName(seed) .. " x" .. invCount(seed)) or "-")
        .. "\nPohon   : " .. (Refs.Trees and "terbaca" or "TIDAK terbaca (harvest mati)")
        .. "\nPijakan : " .. blockText(Farmer.UseBlock, Farmer.ScaffoldId)
        .. "\nAksi    : " .. Farmer.Status
    if txt == lastFarmerText then return end
    lastFarmerText = txt
    task.defer(function()
        pcall(function() UI.FarmerStatus:SetDesc(txt) end)
    end)
end

-- 1 langkah mesin panen/tanam (pakai FC):
--   kerjakan yang terjangkau, atau jalan ke target terdekat.
-- Hasil: "work" | "move" | "wait" | "idle" (+ detik ke pohon siap berikutnya)
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
        task.wait()
        return "wait"
    end
    releaseInput()
    if farmerWorkInReach(s) > 0 then return "work" end
    local R = farmReach() - 0.35
    local useBlock = scaffoldId() ~= nil
    local sx, sy = startNode(s)
    local px, py = floor(s.x), floor(s.y - 0.475)
    local targets, nextReady = farmerScan(px, py, 8, reachFilter(sy * w.w + sx, R, useBlock))
    if not FC.run() or not alive() then return "wait" end
    if #targets == 0 then return "idle", nextReady end
    travelGroup(sx, sy, targets, R, useBlock, FC.skip, FarmerFail)
    return "move"
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
            Farmer.Status = "Menunggu karakter / world..."
            task.wait(0.5)
            continue
        end
        local r, nextReady = fieldStep()
        if r == "wait" and not playerState() then
            Farmer.Status = "Menunggu karakter / world..."
        end
        if r == "idle" then
            local parts = {}
            if Farmer.Harvest then
                parts[#parts + 1] = nextReady and ("pohon siap ±" .. math.ceil(nextReady) .. " dtk") or "tidak ada pohon"
            end
            if Farmer.Plant then
                parts[#parts + 1] = (seedCount() <= 0) and "seed habis / belum dipilih" or "tidak ada tempat tanam"
            end
            Farmer.Status = "Menunggu: " .. table.concat(parts, ", ")
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
    Farmer.Status = reason or "Dihentikan"
    if reason then
        notify("Farmer", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("stop", "Farmer berhenti: " .. reason) end
    end
    updateFarmerStatus()
end

local function startFarmer()
    if Farmer.Running then return end
    local err = checkAutoStart()
    if not err and not Farmer.Harvest and not Farmer.Plant then
        err = "Aktifkan Auto Harvest atau Auto Plant"
    end
    if not err and not Farmer.Harvest and not Farmer.SeedId then
        err = "Pilih seed dulu untuk Auto Plant"
    end
    if err then
        notify("Farmer", err, 4)
        setFarmerVisual()
        return
    end
    if Farmer.Harvest and not Refs.Trees and not findTreeRefs() then
        notify("Farmer", "Data pohon tidak ketemu: Auto Harvest tidak bisa cek pohon siap", 5)
    end
    if Splice.Running and Splice.stop then Splice.stop("Dihentikan karena Farmer dimulai") end
    if Pabrik.Running and Pabrik.stop then Pabrik.stop("Dihentikan karena Farmer dimulai") end
    if Build.Running and Build.stop then Build.stop("Dihentikan karena Farmer dimulai") end
    if State.Running then stopFarm("Dihentikan karena Farmer dimulai") end
    if Clear.Running then stopClear("Dihentikan karena Farmer dimulai") end
    table.clear(Farmer.Skip)
    table.clear(FarmerFail)
    table.clear(BadEdge)
    Farmer.Status = "Mulai..."
    Farmer.Running = true
    autoBegin()
    setFarmerVisual()
    updateFarmerStatus()
    task.spawn(function()
        local ok, e = pcall(farmerLoop)
        if not ok then
            warn("[Fian792] Farmer error: " .. tostring(e))
            if Farmer.Running then stopFarmer("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- SPLICE KELILING: tanam Seed A + splice Seed B di seluruh world
---------------------------------------------------------------------
-- Cara kerja (sama seperti Farmer, tapi aksinya splice):
--   1. Kerjakan semua tile yang terjangkau dari posisi sekarang:
--        tile kosong (di bawahnya block) -> tanam A, lalu splice B ke pohon A itu
--        pohon A yang belum di-splice     -> splice B
--   2. Kalau tidak ada lagi yang terjangkau: cari tile terdekat, jalan ke sana pakai A*.
--   Pohon yang sudah siap panen tidak bisa di-splice (aturan game), jadi dilewati.
local SpliceFail = {}

local function spliceInv()
    return invCount(Splice.A or 0), invCount(Splice.B or 0)
end

-- Jenis kerja di tile ini: "plant" | "splice" | nil
local function spliceKind(x, y, st)
    local A = Splice.A
    local id = fgIdAt(x, y)
    if id == 0 then
        local a, b = spliceInv()
        if a > 0 and b > 0 and plantSpotOk(x, y, A) then return "plant" end
        return nil
    end
    if id ~= A then return nil end
    local trees, w = Refs.Trees, Refs.World
    local t = trees and trees[y * w.w + x]
    if type(t) == "table" and t.s == true then return nil end -- sudah di-splice
    local ra = treeReadyAt(x, y, id)
    if ra and st >= ra then return nil end -- sudah siap panen
    local _, b = spliceInv()
    if b > 0 and canWorkAt(x, y) then return "splice" end
    return nil
end

local function spliceOnce(x, y)
    local w = Refs.World
    local f = w and rawget(w, "spliceSeed")
    if type(f) ~= "function" then return false, "fungsi splice game tidak ketemu" end
    local ok, made = pcall(f, x, y, Splice.B)
    if ok and made and ItemDB[made] then
        pcall(function() Refs.Inv:remove(Splice.B, 1) end)
        if Refs.SetTile then pcall(Refs.SetTile, "fg", x, y, made, true) end -- ganti di layar saja
        Splice.Made += 1
        Splice.Status = ("Splice jadi %s (%d,%d)"):format(itemName(made), x, y)
        return true
    end
    return false, "ditolak server"
end

-- Kerjakan 1 tile: tanam A (kalau kosong) lalu splice B
local function spliceTile(t)
    local A = Splice.A
    if fgIdAt(t.x, t.y) == 0 then
        if invCount(A) <= 0 then return false end
        sendSetTile("fg", t.x, t.y, A)
        pcall(function() Refs.Inv:remove(A, 1) end)
        Splice.Planted += 1
        Splice.Status = ("Tanam %s (%d,%d)"):format(itemName(A), t.x, t.y)
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
        Splice.Status = ("Gagal splice (%d,%d): %s"):format(t.x, t.y, tostring(why))
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
                if not skipped(Splice.Skip, idx, now) and spliceKind(tx, ty, st) then
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

-- Tile kerja terdekat di seluruh world
local function spliceScan(px, py, maxN, filter)
    local w = Refs.World
    local W, H = w.w, w.h
    local best = {}
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local scanned = 0
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            local idx = y * W + x
            if not skipped(Splice.Skip, idx, now) then
                local dx, dy = x - px, (y - py) * 1.3
                local d = dx * dx + dy * dy
                if (#best < maxN or d < best[#best].d) and spliceKind(x, y, st) then
                    if filter and not filter[idx] then
                        skipTile(Splice.Skip, idx, 60)
                    else
                        local pos = #best + 1
                        while pos > 1 and best[pos - 1].d > d do pos -= 1 end
                        table.insert(best, pos, { x = x, y = y, idx = idx, d = d })
                        if #best > maxN then best[#best] = nil end
                    end
                end
            end
        end
        scanned += W
        if scanned > 6000 then
            scanned = 0
            task.wait()
            if not Splice.Roaming then return best end
        end
    end
    return best
end

local function spliceRoamLoop(runId)
    while Splice.Roaming and Splice.Running and alive() and Splice.RunId == runId do
        task.wait()
        local w = Refs.World
        local s = playerState()
        if not w or not s or s.dead then
            releaseInput()
            Splice.Status = "Menunggu karakter / world..."
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
            if Splice.stop then Splice.stop("Seed habis") end
            break
        end
        -- 1) kerjakan yang terjangkau
        if spliceWorkInReach(s) > 0 then continue end
        -- 2) jalan ke tile terdekat
        local R = farmReach() - 0.35
        local sx, sy = startNode(s)
        local px, py = floor(s.x), floor(s.y - 0.475)
        local targets = spliceScan(px, py, 8, reachFilter(sy * w.w + sx, R, false))
        if not Splice.Roaming or not alive() then break end
        if #targets == 0 then
            Splice.Status = (a <= 0) and "Seed A habis, tidak ada pohon A yang bisa di-splice"
                or "Menunggu: tidak ada tempat tanam / pohon untuk di-splice"
            if not waitAuto(1000) then break end
            continue
        end
        travelGroup(sx, sy, targets, R, false, Splice.Skip, SpliceFail)
    end
    releaseInput()
end

local function startSpliceRoam()
    if not OrigIsDown then return "Kontrol gerak game (WorldMenu.isDown) tidak ketemu" end
    if not playerState() then return "Kamu belum masuk world" end
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
            warn("[Fian792] Splice error: " .. tostring(e))
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

-- Jalan ke 1 tile tertentu (dipakai Penjaga: balik ke posisi Auto Farm).
-- Pakai A* yang sama, tanpa taruh block.
local function walkTo(tx, ty, maxSec)
    local w = Refs.World
    if not w or not OrigIsDown then return false end
    if tx < 0 or ty < 0 or tx >= w.w or ty >= w.h then return false end
    Move.Homing = true
    autoBegin()
    local goal = { [ty * w.w + tx] = true }
    local t0, ok = os.clock(), false
    while alive() and Move.Homing and os.clock() - t0 < (maxSec or 30) do
        local s = playerState()
        if not s or s.dead then
            task.wait(0.3) -- tunggu respawn / world selesai dimuat
        else
            local sx, sy = startNode(s)
            if sx == tx and sy == ty and s.grounded then
                ok = true
                break
            end
            local path = astar(sx, sy, goal, tx, ty, 0.5, false)
            if not path then break end -- tidak ada jalan
            if #path > 0 then followPath(path) end
            releaseInput()
            task.wait(0.15)
        end
    end
    Move.Homing = false
    autoEnd()
    return ok
end

---------------------------------------------------------------------
-- LAHAN: bentuk farm world
---------------------------------------------------------------------
-- Baris block dari Y0 ke bawah, tiap baris berjarak Gap.
-- Kalau Tangga nyala, ujung baris dibuka bergantian:
--   baris ke-1, 3, 5.. ujung KANAN kosong, baris ke-2, 4, 6.. ujung KIRI kosong.
--   Jadi ada jalan zig-zag turun-naik di pojok (lompat naik maksimal 3 tile).
local function landRows()
    local w = Refs.World
    local rows = {}
    if not w then return rows end
    local gap = math.clamp(math.floor(Land.Gap), 2, 3)
    for k = 0, math.max(0, math.floor(Land.Rows)) - 1 do
        local y = math.floor(Land.Y0) + k * gap
        if y < 1 or y >= w.h - 1 then break end
        rows[#rows + 1] = y
    end
    return rows
end

-- Kolom awal & akhir block untuk baris ke-k (0 = paling atas)
local function landSpan(k)
    local w = Refs.World
    local x0 = math.clamp(math.floor(Land.X0), 0, w.w - 1)
    local x1 = math.clamp(math.floor(Land.X1), 0, w.w - 1)
    if x1 < x0 then x0, x1 = x1, x0 end
    if Land.Stairs and x1 - x0 >= 3 then
        if k % 2 == 0 then x1 -= 1 else x0 += 1 end
    end
    return x0, x1
end

local function inLandRect(x, y)
    local rows = landRows()
    if #rows == 0 then return false end
    local x0 = math.min(Land.X0, Land.X1)
    local x1 = math.max(Land.X0, Land.X1)
    return x >= x0 and x <= x1 and y >= rows[1] - 1 and y <= rows[#rows]
end

-- Tile block lahan: [idx] = true
local function landBlockSet()
    local set = {}
    local w = Refs.World
    if not w then return set end
    for k, y in ipairs(landRows()) do
        local x0, x1 = landSpan(k - 1)
        for x = x0, x1 do set[y * w.w + x] = true end
    end
    return set
end

-- Tile tanam lahan (di atas block yang sudah terpasang): [idx] = true
local function landPlantSet()
    local set = {}
    local w = Refs.World
    if not w then return set end
    for k, y in ipairs(landRows()) do
        local x0, x1 = landSpan(k - 1)
        for x = x0, x1 do
            if fgIdAt(x, y) ~= 0 and y - 1 >= 0 then set[(y - 1) * w.w + x] = true end
        end
    end
    return set
end

-- Hitung kebutuhan block lahan
local function landInfo(blockId)
    local info = { rows = 0, total = 0, need = 0, done = 0, blocked = 0, gap = 0 }
    local w = Refs.World
    if not w then return info end
    local rows = landRows()
    info.rows = #rows
    for k, y in ipairs(rows) do
        local x0, x1 = landSpan(k - 1)
        for x = x0, x1 do
            info.total += 1
            local id = fgIdAt(x, y)
            local it = ItemDB[id]
            if id == 0 then
                info.need += 1
            elseif id == blockId or (it and it.solid and it.kind ~= "seed") then
                info.done += 1
            else
                info.blocked += 1
            end
            local up = fgIdAt(x, y - 1)
            local upIt = ItemDB[up]
            if up ~= 0 and not (upIt and upIt.kind == "seed") then info.gap += 1 end
        end
    end
    return info
end

-- Seed <-> block (seed biasanya id block + 1, kecuali item khusus yang punya seedId)
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

local function readyTreeCount(whole)
    local w = Refs.World
    if not w then return 0 end
    local st = workspace:GetServerTimeNow()
    local x0, x1, y0, y1 = 0, w.w - 1, 0, w.h - 1
    if not whole then
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
            if id ~= 0 then
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
-- PABRIK
---------------------------------------------------------------------
-- Fase (berputar terus):
--   PANEN : panen semua pohon siap di lahan (berhenti kalau block / seed hampir 200)
--   TANAM : tanam seed di semua tile lahan yang kosong
--   BREAK : jalan ke posisi break, Auto Farm (place + break) di tile pabrik sampai block habis
--   TUNGGU: tunggu pohon siap, lalu kembali ke PANEN
--   Kapan saja seed >= batas drop -> pergi drop (seed - sisakan), lalu pulang.
-- Inventori maksimal 200 per item, jadi semua fase dijaga supaya tidak penuh.
-- Drop yang jatuh di tempat drop tidak di-collect lagi.
local BOOT_SEEDS = 10 -- (mode produksi) cukup seed segini untuk mulai tanam
local CAP = 190       -- batas aman jumlah item (maksimal 200 per item)

local function pabrikCfg(o, harvest, plant)
    local plantSet, area = nil, nil
    if not o.whole then
        plantSet = landPlantSet()
        area = inLandRect
    end
    return {
        run = o.live,
        harvest = harvest,
        plant = plant and invCount(o.seed) > 0,
        seed = o.seed,
        skip = Pabrik.Skip,
        hms = Farmer.HarvestMs,
        pms = Farmer.PlantMs,
        area = area,
        plantSet = plantSet,
        exclude = o.exclude,
        status = function(t) Pabrik.Status = t end,
        onHarvest = function() Pabrik.Harvested += 1 end,
        onPlant = function() Pabrik.Planted += 1 end,
    }
end

-- Break block di posisi pabrik (pakai Auto Farm dengan tile & block pabrik)
local function pabrikBreak(o)
    if os.clock() < (Pabrik.BreakFailUntil or 0) then return false end
    local s = playerState()
    if not s then return false end
    local hx, hy = startNode(s)
    if hx ~= Pabrik.BreakX or hy ~= Pabrik.BreakY then
        Pabrik.Status = ("Jalan ke posisi break (%d,%d)"):format(Pabrik.BreakX, Pabrik.BreakY)
        if not walkTo(Pabrik.BreakX, Pabrik.BreakY, 45) then
            Pabrik.Status = "Gagal jalan ke posisi break, dicoba lagi nanti"
            Pabrik.BreakFailUntil = os.clock() + 30
            return false
        end
    end
    if not o.live() then return false end
    State.Override = { offsets = Pabrik.Tiles, block = o.block, mode = "Place + Break" }
    State.Quiet = true
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    local id = State.RunId
    local t0 = os.clock()
    task.spawn(function() -- pengawas sesi break
        while State.Running and State.RunId == id do
            task.wait(1)
            local sd = invCount(o.seed)
            if not o.live() or os.clock() - t0 > Pabrik.BreakSec or sd >= CAP
                or (o.drop and Pabrik.Drop and sd >= Pabrik.DropAt)
                or (o.breakMode ~= "always" and sd >= BOOT_SEEDS) then
                State.Running = false
            end
        end
    end)
    Pabrik.Status = "Break " .. itemName(o.block) .. " di posisi pabrik"
    local ok, e = pcall(farmLoop, id)
    if not ok then warn("[Fian792] Pabrik break error: " .. tostring(e)) end
    State.Running = false
    State.Override = nil
    State.Quiet = false
    return true
end

-- "WORLD" / "WORLD:ID" / ":ID" -> nama world, id pintu
local function parseDropTarget()
    local raw = tostring(Pabrik.DropWorld or ""):gsub("%s", "")
    local name, door = string.match(raw, "^([^:]*):(.+)$")
    if not name then name = raw end
    name = string.upper(name):gsub("[^A-Z0-9]", "")
    if door == "" then door = nil end
    return name, door
end

-- Pindah world (lewat menu game), bisa langsung ke pintu tertentu
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

-- Drop pakai fungsi drop game (item jatuh di depan karakter)
local function dropItems(id, n, live)
    local hud = Refs.Hud
    local f = hud and rawget(hud, "onDrop")
    if type(f) ~= "function" then return 0, "fungsi drop game tidak ketemu" end
    local left, flipped = n, false
    while left > 0 and live() do
        local before = invCount(id)
        pcall(f, id, math.min(left, 200))
        task.wait(0.7) -- game menolak drop yang terlalu cepat (0.3 dtk)
        local got = before - invCount(id)
        if got > 0 then
            left -= got
            Pabrik.Dropped += got
        elseif not flipped then
            -- di depan tembok / tidak boleh drop: hadap ke arah lain lalu coba lagi
            flipped = true
            local st = playerState()
            local right = st and (st.facing or 1) < 0
            AutoInput.active = true
            AutoInput.right, AutoInput.left = right, not right
            task.wait(0.06)
            AutoInput.right, AutoInput.left = false, false
            task.wait(0.3)
        else
            return n - left, "tidak bisa drop di posisi ini"
        end
    end
    return n - left, nil
end

local function pabrikDrop(seed, n, live)
    local name, door = parseDropTarget()
    local home = Guard.worldName()
    if name == "" then name = home end
    if Pabrik.DropX < 0 and not door and name == home then
        Pabrik.Status = "Posisi drop belum diatur (drop dilewati)"
        Pabrik.DropOffUntil = os.clock() + 60
        return
    end
    Pabrik.Traveling = true
    local away = name ~= home
    local ok, why = true, nil
    if away or door then
        Pabrik.Status = "Pergi ke " .. name .. (door and (":" .. door) or "") .. " untuk drop"
        local okw, err = goWorld(name, door)
        if not okw then ok, why = false, "gagal masuk " .. name .. " (" .. tostring(err) .. ")" end
    end
    if ok and live() and Pabrik.DropX >= 0 then
        Pabrik.Status = ("Jalan ke posisi drop (%d,%d)"):format(Pabrik.DropX, Pabrik.DropY)
        if not walkTo(Pabrik.DropX, Pabrik.DropY, 60) then ok, why = false, "tidak bisa jalan ke posisi drop" end
    end
    if ok and live() then
        local s = playerState()
        if s then Pabrik.Zone = { world = Guard.worldName(), x = s.x, y = s.y - 0.475 } end
        local got, err = dropItems(seed, n, live)
        if got > 0 then
            local msg = ("Drop %s x%d di %s"):format(itemName(seed), got, Guard.worldName())
            Pabrik.Status = msg
            notify("Pabrik", msg, 4)
            Hook.send("pabrik", msg)
        end
        if err then ok, why = false, err end
    end
    if not ok then
        Pabrik.DropOffUntil = os.clock() + 120
        Pabrik.Status = "Drop gagal: " .. tostring(why)
        notify("Pabrik", Pabrik.Status, 5)
        Hook.send("pabrik", Pabrik.Status)
    end
    -- pulang ke world pabrik
    if away and home ~= "" and live() then
        Pabrik.Status = "Pulang ke " .. home
        local okh = goWorld(home, nil)
        if not okh and live() then
            task.wait(5)
            okh = goWorld(home, nil)
        end
        if not okh then
            Pabrik.Traveling = false
            if Pabrik.stop then Pabrik.stop("Gagal pulang ke world pabrik " .. home) end
            return
        end
    end
    Pabrik.Traveling = false
end

local PHASE_NAME = { panen = "PANEN", tanam = "TANAM", ["break"] = "BREAK", tunggu = "TUNGGU" }

local function breakReady()
    return Pabrik.BreakX >= 0 and next(Pabrik.Tiles) ~= nil and os.clock() >= (Pabrik.BreakFailUntil or 0)
end

-- 1 langkah pabrik. o = { seed, block, drop, breakMode, whole, exclude, live, phase }
-- Hasil: "drop" | "work" | "move" | "wait" | "break" | "next" | "idle" (+ detik ke pohon siap)
local function pabrikStep(o)
    local seeds, blocks = invCount(o.seed), invCount(o.block)
    o.phase = o.phase or "panen"
    Pabrik.Phase = PHASE_NAME[o.phase]
    -- drop seed lebihan (kapan saja)
    if o.drop and Pabrik.Drop and seeds >= Pabrik.DropAt and seeds > Pabrik.Keep
        and os.clock() >= (Pabrik.DropOffUntil or 0) then
        pabrikDrop(o.seed, seeds - Pabrik.Keep, o.live)
        return "drop"
    end

    if o.phase == "panen" then
        -- 1x panen bisa kena beberapa pohon, jadi sisakan ruang ~20 item
        if blocks >= CAP - 20 or seeds >= CAP - 20 then
            o.phase = "tanam"
            return "next"
        end
        FC = pabrikCfg(o, true, false)
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
            FC = pabrikCfg(o, false, true)
            local r = fieldStep()
            if r ~= "idle" then return r end
        end
        o.phase = "break"
        return "next"
    end

    if o.phase == "break" then
        local want
        if o.breakMode == "always" then
            want = blocks > 0
        else -- mode produksi: break hanya untuk dapat seed awal
            local _, nxt = readyTreeCount(o.whole)
            want = blocks > 0 and seeds < BOOT_SEEDS and nxt == nil
        end
        if want and breakReady() and pabrikBreak(o) then
            if invCount(o.block) <= 0 or o.breakMode ~= "always" then o.phase = "tanam" end
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
    if o.breakMode == "always" and blocks > 0 and breakReady() then
        o.phase = "break"
        return "next"
    end
    if seeds > 0 and os.clock() - (o.plantAt or 0) > 10 then
        o.plantAt = os.clock() -- sesekali cek tile kosong (misal pohon dipanen orang lain)
        o.phase = "tanam"
        return "next"
    end
    return "idle", nxt
end

local function waitText(sec)
    sec = math.max(0, math.ceil(sec or 0))
    if sec >= 60 then return ("%dm %dd"):format(sec // 60, sec % 60) end
    return sec .. " dtk"
end

local function pabrikLoop(runId)
    local function live() return Pabrik.Running and alive() and Pabrik.RunId == runId end
    local o = { seed = Pabrik.SeedId, block = Pabrik.BlockId, drop = true, breakMode = "always", live = live }
    while live() do
        task.wait()
        o.whole = Pabrik.WholeWorld
        local here = Guard.worldName()
        if not Pabrik.Traveling and Pabrik.Home ~= "" and here ~= Pabrik.Home then
            Pabrik.Status = "Bukan di world pabrik (" .. Pabrik.Home .. "), menunggu..."
            task.wait(2)
            continue
        end
        local r, nextReady = pabrikStep(o)
        if r == "idle" then
            local seeds, blocks = invCount(o.seed), invCount(o.block)
            if not nextReady and seeds <= 0 and blocks <= 0 then
                if Pabrik.stop then Pabrik.stop("Seed & block habis, tidak ada pohon tumbuh") end
                break
            end
            if nextReady then
                Pabrik.Status = "Menunggu pohon siap ±" .. waitText(nextReady)
            elseif blocks > 0 and (Pabrik.BreakX < 0 or next(Pabrik.Tiles) == nil) then
                Pabrik.Status = "Ada block tapi posisi / tile break belum diatur"
            elseif seeds > 0 then
                Pabrik.Status = "Lahan penuh, menunggu"
            else
                Pabrik.Status = "Menunggu..."
            end
            if not waitAuto(1000) then break end
        end
    end
    releaseInput()
end

function Pabrik.stop(reason)
    Pabrik.Running = false
    Pabrik.Traveling = false
    if State.Override then State.Running = false end
    autoEnd()
    releaseInput()
    Pabrik.Status = reason or "Dihentikan"
    if UI.PabrikToggle then pcall(function() UI.PabrikToggle:Set(false) end) end
    if reason then
        notify("Pabrik", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("pabrik", "Pabrik berhenti: " .. reason) end
    end
end

function Pabrik.start()
    if Pabrik.Running then return end
    local err
    local block = blockOfSeed(Pabrik.SeedId)
    if not Refs.World then
        err = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
    elseif not OrigIsDown then
        err = "Kontrol gerak game (WorldMenu.isDown) tidak ketemu"
    elseif not playerState() then
        err = "Kamu belum masuk world"
    elseif not Pabrik.SeedId then
        err = "Pilih seed pabrik dulu"
    elseif not block then
        err = "Block dari seed ini tidak ketemu"
    elseif not Pabrik.WholeWorld and #landRows() == 0 then
        err = "Atur lahan dulu (tab Lahan)"
    end
    if err then
        notify("Pabrik", err, 4)
        if UI.PabrikToggle then pcall(function() UI.PabrikToggle:Set(false) end) end
        return
    end
    if State.Running and not State.Override then stopFarm("Dihentikan karena Pabrik dimulai") end
    if Clear.Running then stopClear("Dihentikan karena Pabrik dimulai") end
    if Farmer.Running then stopFarmer("Dihentikan karena Pabrik dimulai") end
    if Splice.Running and Splice.stop then Splice.stop("Dihentikan karena Pabrik dimulai") end
    if not Refs.Trees then findTreeRefs() end
    Pabrik.BlockId = block
    Pabrik.Home = Guard.worldName()
    table.clear(Pabrik.Skip)
    table.clear(BadEdge)
    Pabrik.DropOffUntil, Pabrik.BreakFailUntil = 0, 0
    Pabrik.Running = true
    Pabrik.RunId = (Pabrik.RunId or 0) + 1
    Pabrik.Status = "Mulai..."
    autoBegin()
    if UI.PabrikToggle then pcall(function() UI.PabrikToggle:Set(true) end) end
    local id = Pabrik.RunId
    task.spawn(function()
        local ok, e = pcall(pabrikLoop, id)
        if not ok then
            warn("[Fian792] Pabrik error: " .. tostring(e))
            if Pabrik.Running then Pabrik.stop("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- BANGUN LAHAN
---------------------------------------------------------------------
-- Cara kerja:
--   1. Hitung tile lahan yang masih kosong = block yang dibutuhkan.
--   2. Block kurang & Produksi nyala -> tanam seed block itu di seluruh world,
--      panen, (kalau seed habis: break sedikit block untuk dapat seed) sampai block cukup.
--   3. Pasang block dari baris PALING BAWAH ke atas: berdiri di baris bawah,
--      pasang baris di atasnya (jarak 2-3 tile masih terjangkau).
local BuildFail = {}

local function overlapsPlayer(x, y, s)
    return x + 1 > s.x - 0.3 and x < s.x + 0.3 and y + 1 > s.y - 0.95 and y < s.y
end

-- Tile kosong di baris paling bawah yang belum selesai
local function buildTargetsRow(now)
    local w = Refs.World
    local rows = landRows()
    for k = #rows, 1, -1 do
        local y = rows[k]
        local x0, x1 = landSpan(k - 1)
        local list = {}
        for x = x0, x1 do
            local idx = y * w.w + x
            if fgIdAt(x, y) == 0 and not skipped(Build.Skip, idx, now) then
                list[#list + 1] = { x = x, y = y, idx = idx }
            end
        end
        if #list > 0 then return list end
    end
    return {}
end

local function placeBuild(t, s)
    local id = Build.BlockId
    if invCount(id) <= 0 or overlapsPlayer(t.x, t.y, s) then return false end
    if not placeOk(t.x, t.y) then
        skipTile(Build.Skip, t.idx, 120)
        return false
    end
    sendSetTile("fg", t.x, t.y, id)
    pcall(function() Refs.Inv:remove(id, 1) end)
    Build.Placed += 1
    Build.Status = ("Pasang %s (%d,%d)"):format(itemName(id), t.x, t.y)
    return true
end

local function buildStep()
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then
        releaseInput()
        task.wait(0.5)
        return "wait"
    end
    if not s.grounded then
        releaseInput()
        task.wait()
        return "wait"
    end
    releaseInput()
    local list = buildTargetsRow(os.clock())
    if #list == 0 then return "none" end
    -- pasang semua yang terjangkau
    local R = buildReach() - 0.08
    local done = 0
    for _, t in ipairs(list) do
        if not Build.Running or not alive() then return "wait" end
        local cur = playerState()
        if not cur then break end
        if fgIdAt(t.x, t.y) == 0 and stateReaches(cur, t.x, t.y, R) and placeBuild(t, cur) then
            done += 1
            if not waitAuto(State.PlaceMs) then return "wait" end
        end
    end
    if done > 0 then return "work" end
    -- jalan ke tile terdekat di baris itu
    local px = floor(s.x)
    table.sort(list, function(a, b) return abs(a.x - px) < abs(b.x - px) end)
    local group = {}
    for i = 1, math.min(8, #list) do group[i] = list[i] end
    local sx, sy = startNode(s)
    travelGroup(sx, sy, group, buildReach() - 0.35, scaffoldId() ~= nil, Build.Skip, BuildFail)
    return "move"
end

function Build.stop(reason)
    Build.Running = false
    if Pabrik.Running == false and State.Override then State.Running = false end
    autoEnd()
    releaseInput()
    Build.Phase = reason or "Dihentikan"
    if UI.BuildToggle then pcall(function() UI.BuildToggle:Set(false) end) end
    if reason then
        notify("Bangun Lahan", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("pabrik", "Bangun Lahan: " .. reason) end
    end
end

local function buildLoop(runId)
    local function live() return Build.Running and alive() and Build.RunId == runId end
    local seed = seedOfBlock(Build.BlockId)
    local o = { seed = seed, block = Build.BlockId, drop = false, breakMode = "bootstrap", whole = true, live = live }
    local phase = nil
    while live() do
        task.wait()
        local info = landInfo(Build.BlockId)
        Build.Info = info
        if info.need == 0 then
            Build.stop("Lahan selesai (" .. info.done .. " block)")
            if Build.ThenPabrik then
                if not Pabrik.SeedId then Pabrik.SeedId = seed end
                Pabrik.start()
            end
            break
        end
        local have = invCount(Build.BlockId)
        local target = math.min(info.need, CAP) -- inventori maksimal 200 per item
        if phase == nil then
            phase = (have >= target or not Build.Produce) and "bangun" or "produksi"
        end
        if phase == "produksi" then
            if have >= target then
                phase = "bangun"
                notify("Bangun Lahan", "Block cukup (" .. have .. "), mulai pasang", 4)
            elseif not seed then
                Build.stop(("Block kurang %d dan seed-nya tidak ketemu"):format(info.need - have))
                break
            else
                Build.Phase = ("Produksi block %d / %d (total butuh %d)"):format(have, target, info.need)
                o.exclude = landBlockSet() -- jangan tanam di tempat block lahan
                local r, nextReady = pabrikStep(o)
                Build.Status = Pabrik.Status
                if r == "idle" then
                    if not nextReady and invCount(seed) <= 0 and have <= 0 then
                        Build.stop("Seed & block habis. Butuh " .. info.need .. " block")
                        break
                    end
                    if not nextReady and invCount(seed) <= 0 and (Pabrik.BreakX < 0 or next(Pabrik.Tiles) == nil) then
                        Build.Status = "Seed habis: atur posisi & tile break di tab Pabrik supaya bisa dapat seed"
                    end
                    if not waitAuto(1000) then break end
                end
            end
        else
            if have <= 0 then
                if Build.Produce and seed then
                    phase = "produksi"
                else
                    Build.stop("Block habis, masih kurang " .. info.need)
                    break
                end
            else
                Build.Phase = ("Pasang lahan: sisa %d tile"):format(info.need)
                local r = buildStep()
                if r == "none" then
                    Build.Status = "Sisa tile belum terjangkau / terhalang, dicoba lagi"
                    if not waitAuto(1500) then break end
                end
            end
        end
    end
    releaseInput()
end

function Build.start()
    if Build.Running then return end
    local err
    local it = Build.BlockId and ItemDB[Build.BlockId]
    if not Refs.World then
        err = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
    elseif not OrigIsDown then
        err = "Kontrol gerak game (WorldMenu.isDown) tidak ketemu"
    elseif not playerState() then
        err = "Kamu belum masuk world"
    elseif not (it and it.solid) then
        err = "Pilih block padat untuk lahan"
    elseif #landRows() == 0 then
        err = "Atur lahan dulu (Y awal / jumlah baris)"
    end
    if err then
        notify("Bangun Lahan", err, 4)
        if UI.BuildToggle then pcall(function() UI.BuildToggle:Set(false) end) end
        return
    end
    if State.Running and not State.Override then stopFarm("Dihentikan karena Bangun Lahan dimulai") end
    if Clear.Running then stopClear("Dihentikan karena Bangun Lahan dimulai") end
    if Farmer.Running then stopFarmer("Dihentikan karena Bangun Lahan dimulai") end
    if Splice.Running and Splice.stop then Splice.stop("Dihentikan karena Bangun Lahan dimulai") end
    if Pabrik.Running then Pabrik.stop("Dihentikan karena Bangun Lahan dimulai") end
    if not Refs.Trees then findTreeRefs() end
    table.clear(Build.Skip)
    table.clear(BuildFail)
    table.clear(Pabrik.Skip)
    table.clear(BadEdge)
    Pabrik.BreakFailUntil = 0
    Build.Running = true
    Build.RunId = (Build.RunId or 0) + 1
    Build.Phase = "Menghitung..."
    autoBegin()
    if UI.BuildToggle then pcall(function() UI.BuildToggle:Set(true) end) end
    local id = Build.RunId
    task.spawn(function()
        local ok, e = pcall(buildLoop, id)
        if not ok then
            warn("[Fian792] Bangun Lahan error: " .. tostring(e))
            if Build.Running then Build.stop("Error: " .. tostring(e)) end
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
end)() end -- do (gerak otomatis)

---------------------------------------------------------------------
-- AUTO CHAT
---------------------------------------------------------------------
-- Pesan dikirim ke chat world, bergantian sesuai urutan
local TextChatService = game:GetService("TextChatService")

local function worldChannel()
    local folder = TextChatService:FindFirstChild("WorldChannels")
    if not folder then return nil end
    local name = Refs.World and Refs.World.name
    if type(name) == "string" and name ~= "" then
        local ch = folder:FindFirstChild(name)
        if ch then return ch end
    end
    -- cadangan: cari channel yang ada kita
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
    local txt = "Status   : " .. (Spam.On and "JALAN" or "BERHENTI")
        .. "\nPesan    : " .. #Spam.Texts .. " (bergantian)"
        .. "\nTerkirim : " .. Spam.Sent
        .. "\nTerakhir : " .. Spam.Last
    if txt == lastSpamText then return end
    lastSpamText = txt
    task.defer(function()
        pcall(function() UI.SpamStatus:SetDesc(txt) end)
    end)
end

-- Kirim pesan berikutnya
local function sendNextChat()
    if #Spam.Texts == 0 then
        Spam.Last = "Daftar pesan kosong"
        return false
    end
    local ch = worldChannel()
    if not ch then
        Spam.Last = "Channel chat world belum ada (masuk world dulu)"
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
        Spam.Last = "Gagal: " .. tostring(err)
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
-- WATERMARK NAMA FIAN792 (hanya di layar sendiri)
---------------------------------------------------------------------
-- Nama asli (huruf gambar "BitmapText") disembunyikan, diganti teks beranimasi:
-- warna gradient mengalir + denyut halus. Pemain lain tetap melihat nama asli.
-- Selalu aktif sebagai penanda script (tidak ada tombol on/off).
local TextService = game:GetService("TextService")
local NameFx = { t0 = os.clock() }

local NAME_COLORS = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(170, 90, 255)),  -- ungu
    ColorSequenceKeypoint.new(0.25, Color3.fromRGB(60, 205, 255)),  -- biru muda
    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 110, 210)), -- pink
    ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 205, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(170, 90, 255)),
})
local NAME_FONT = Enum.Font.FredokaOne

-- Tempat nama: di atas karakter & panel kiri atas
local function nameHolders()
    local gg = PlayerGui:FindFirstChild("GameGui")
    local world = gg and gg:FindFirstChild("World")
    local cam = world and world:FindFirstChild("Camera")
    local chat = PlayerGui:FindFirstChild("ChatGui")
    local hud = chat and chat:FindFirstChild("HUD")
    local panel = hud and hud:FindFirstChild("PlayerPanel")
    return cam and cam:FindFirstChild("NameTag"), panel and panel:FindFirstChild("Name")
end

local function textWidth(text, size)
    local ok, v = pcall(TextService.GetTextSize, TextService, text, size, NAME_FONT, Vector2.new(2000, 200))
    return (ok and v.X or #text * size * 0.55) + 6 -- +6 untuk garis tepi
end

local function makeLabel(holder, size, isTag)
    local lb = Instance.new("TextLabel")
    lb.Name = "FianName"
    lb.BackgroundTransparency = 1
    lb.Font = NAME_FONT
    lb.TextSize = size
    lb.TextColor3 = Color3.new(1, 1, 1)
    lb.Text = Misc.NameText
    lb.ZIndex = isTag and 1017 or 10
    if isTag then
        lb.AnchorPoint = Vector2.new(0.5, 0.5) -- denyut dari tengah
        lb.Position = UDim2.fromScale(0.5, 0.5)
    else
        lb.AnchorPoint = Vector2.new(0, 0.5)
        lb.Position = UDim2.new(0, 3, 0.5, 0)
        lb.TextXAlignment = Enum.TextXAlignment.Left
    end
    local st = Instance.new("UIStroke")
    st.Thickness = 2
    st.Color = Color3.fromRGB(25, 12, 40)
    st.Transparency = 0.1
    st.Parent = lb
    local gr = Instance.new("UIGradient")
    gr.Color = NAME_COLORS
    gr.Rotation = 12
    gr.Parent = lb
    local sc = Instance.new("UIScale")
    sc.Parent = lb
    lb.Parent = holder
    return { holder = holder, bitmap = holder:FindFirstChild("BitmapText"), label = lb, gr = gr, sc = sc,
        size = size, isTag = isTag, text = nil, w = 0 }
end

local function dropEntry(e)
    if not e then return end
    pcall(function() e.label:Destroy() end)
    if e.bitmap then pcall(function() e.bitmap.Visible = true end) end
    if e.isTag and e.bitmap then
        -- kembalikan ukuran tag & posisi wrench sesuai nama asli
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
end

-- Pastikan label ada, nama asli tersembunyi, ukuran tag pas dengan teks
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
    if e.bitmap and e.bitmap.Visible then e.bitmap.Visible = false end
    if isTag then
        local h = math.max(holder.Size.Y.Offset, size + 6)
        if e.label.Size.X.Offset ~= e.w or e.label.Size.Y.Offset ~= h then
            e.label.Size = UDim2.fromOffset(e.w, h)
        end
        if holder.Size.X.Offset ~= e.w then
            holder.Size = UDim2.fromOffset(e.w, holder.Size.Y.Offset) -- bendera tetap di kiri nama
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

-- Animasi tiap frame: gradient mengalir + denyut halus
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
-- GUI TAMBAHAN: Grid Tile 5x5 + tombol Fly ▲/▼
---------------------------------------------------------------------
local guiParent = (gethui and gethui()) or game:GetService("CoreGui")

local function newScreenGui(name)
    local sg = Instance.new("ScreenGui")
    sg.Name = name
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 999
    sg.Enabled = false
    if syn and syn.protect_gui then pcall(syn.protect_gui, sg) end
    sg.Parent = guiParent
    return sg
end

local GRID_RADIUS = 2
local CELL = 38
local GAP = 4

local GridGui = newScreenGui("FianGrid")
UI.GridGui = GridGui

local side = GRID_RADIUS * 2 + 1
local gridSize = side * CELL + (side - 1) * GAP

local Panel = Instance.new("Frame")
Panel.Size = UDim2.fromOffset(gridSize + 20, gridSize + 96)
Panel.Position = UDim2.fromOffset(20, 80)
Panel.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
Panel.BorderSizePixel = 0
Panel.Parent = GridGui
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 10)
local pStroke = Instance.new("UIStroke", Panel)
pStroke.Color = Color3.fromRGB(70, 70, 90)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 0, 28)
Title.Position = UDim2.fromOffset(10, 4)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = Color3.fromRGB(235, 235, 245)
Title.Text = I18N.T("Grid Tile")
Title.Parent = Panel

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(24, 24)
CloseBtn.Position = UDim2.new(1, -30, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
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

local COLOR_OFF = Color3.fromRGB(48, 48, 60)
local COLOR_ON = Color3.fromRGB(46, 160, 90)
local COLOR_ME = Color3.fromRGB(60, 110, 220)
local CellButtons = {}

-- Grid dipakai untuk 2 hal: tile Auto Farm, atau tile break Pabrik
UI.GridMode = "farm"
UI.gridTarget = function()
    return (UI.GridMode == "pabrik") and Pabrik.Tiles or State.Offsets
end

local function paintCell(key)
    local b = CellButtons[key]
    if b then b.BackgroundColor3 = UI.gridTarget()[key] and COLOR_ON or COLOR_OFF end
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
        else
            btn.Text = ""
            btn.BackgroundColor3 = UI.gridTarget()[key] and COLOR_ON or COLOR_OFF
            CellButtons[key] = btn
            btn.MouseButton1Click:Connect(function()
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
    if UI.GridMode == "pabrik" then
        if Pabrik.Running then Pabrik.stop() else Pabrik.start() end
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
ClearBtn.TextColor3 = Color3.fromRGB(180, 180, 195)
ClearBtn.Text = I18N.T("Bersihkan pilihan")
ClearBtn.Parent = Panel
ClearBtn.MouseButton1Click:Connect(function()
    local tgt = UI.gridTarget()
    for key in pairs(tgt) do
        tgt[key] = nil
        paintCell(key)
    end
    updateStatus()
end)

-- Tombol ganti mode Grid: Farm (tile Auto Farm) / Pabrik (tile break pabrik)
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
        local pab = UI.GridMode == "pabrik"
        ModeBtn.Text = pab and I18N.T("Pabrik") or "Farm"
        ModeBtn.BackgroundColor3 = pab and Color3.fromRGB(200, 120, 40) or Color3.fromRGB(60, 60, 75)
        Title.Text = I18N.T(pab and "Tile Break Pabrik" or "Grid Tile")
        for key in pairs(CellButtons) do paintCell(key) end
        if pab then
            GridStart.Text = I18N.T(Pabrik.Running and "STOP PABRIK" or "START PABRIK")
            GridStart.BackgroundColor3 = Pabrik.Running and Color3.fromRGB(200, 60, 60) or COLOR_ON
        else
            local run = State.Running and not State.Override
            GridStart.Text = run and "STOP" or "START"
            GridStart.BackgroundColor3 = run and Color3.fromRGB(200, 60, 60) or COLOR_ON
        end
    end

    UI.setGridMode = function(m)
        UI.GridMode = m
        apply()
    end
    ModeBtn.MouseButton1Click:Connect(function()
        UI.setGridMode(UI.GridMode == "pabrik" and "farm" or "pabrik")
    end)
    apply()
end)() end

-- Panel bisa digeser lewat judul
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
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
            local t = px and ("ME (" .. px .. "," .. py .. ")") or I18N.T("Grid Tile | tidak di world")
            if Title.Text ~= t then Title.Text = t end
        end
        task.wait(0.5)
    end
end)

-- Tombol ▲/▼ untuk Fly (muncul saat Fly aktif)
local FlyPad = newScreenGui("FianFlyPad")
UI.FlyPad = FlyPad

local function flyButton(text, yOffset, onHold)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(64, 64)
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Position = UDim2.new(1, -24, 0.5, yOffset)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    b.BackgroundTransparency = 0.2
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 28
    b.TextColor3 = Color3.new(1, 1, 1)
    b.AutoButtonColor = true
    b.Parent = FlyPad
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", b)
    st.Color = Color3.fromRGB(90, 90, 120)
    st.Thickness = 2
    -- dilepas saat jari diangkat (walau sudah geser keluar), supaya tidak nyangkut
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

flyButton("▲", -40, function(v) Misc.UpHeld = v end)
flyButton("▼", 40, function(v) Misc.DownHeld = v end)

---------------------------------------------------------------------
-- UI WINDUI
---------------------------------------------------------------------
-- Pilih bahasa saat execute (sebelum menu dibuat, karena teks menu dipasang sekali)
do (function()
    if not I18N.Ask and Config.saved("Bahasa", "Saved") then return end
    local chosen, late = false, false
    local function pick(lang)
        if late then
            I18N.Saved = lang
            Config.save(true)
            notify("Bahasa / Language", "Execute ulang untuk ganti bahasa / Re-execute to apply", 5)
            return
        end
        I18N.Lang, I18N.Saved, chosen = lang, lang, true
    end
    local ok = pcall(function()
        WindUI:Popup({
            Title = "Fian792",
            Icon = "languages",
            Content = "Pilih bahasa menu\nChoose menu language",
            Buttons = {
                { Title = "Indonesia", Variant = I18N.Lang == "id" and "Primary" or "Secondary",
                    Callback = function() pick("id") end },
                { Title = "English", Variant = I18N.Lang == "en" and "Primary" or "Secondary",
                    Callback = function() pick("en") end },
            },
        })
    end)
    if not ok then return end
    local t0 = os.clock()
    while not chosen and os.clock() - t0 < 30 and alive() do task.wait(0.1) end
    late = not chosen -- tidak dipilih dalam 30 detik: pakai bahasa terakhir
    if chosen then Config.save(true) end
end)() end

local Window = I18N.wrap(WindUI:CreateWindow({
    Title = "Fian792",
    Icon = "sprout",
    Author = "v1.2 | Tester",
    Folder = "Alfian792",
    Size = UDim2.fromOffset(640, 380),
    Theme = "Dark",
    Transparent = true,
    SideBarWidth = 150,
}))
pcall(function()
    Window:EditOpenButton({ Title = "Fian792", Icon = "sprout", Draggable = true })
end)

-- Kalau 1 elemen error, tab lain tetap dibuat
local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[Fian792] UI error: " .. tostring(err)) end
end

-- Sidebar dikelompokkan: grup utama bisa dibuka / ditutup (isinya tab-tab)
local Groups = {}
for _, g in ipairs({
    { key = "farm", title = "Farming", icon = "sprout", opened = true },
    { key = "fitur", title = "Fitur", icon = "sparkles" },
    { key = "aman", title = "Keamanan", icon = "shield" },
    { key = "setel", title = "Setelan", icon = "settings" },
}) do
    local ok, sec = pcall(function()
        return Window:Section({ Title = g.title, Icon = g.icon, Opened = g.opened == true })
    end)
    if ok and type(sec) == "table" and type(sec.Tab) == "function" then Groups[g.key] = sec end
end

local function makeTab(title, icon, group)
    local parent = (group and Groups[group]) or Window
    local ok, tab = pcall(function() return parent:Tab({ Title = title, Icon = icon }) end)
    if ok and tab then return tab end
    return Window:Tab({ Title = title })
end

-- Kotak di dalam tab yang bisa dibuka / ditutup (supaya tab tidak terlihat penuh).
-- WindUI lama tanpa fitur ini: cuma judul, elemen tetap di tab.
local function box(tab, title, opened)
    local ok, sec = pcall(function()
        return tab:Section({ Title = title, Box = true, BoxBorder = true, Opened = opened == true })
    end)
    if ok and type(sec) == "table" and type(sec.Toggle) == "function" then return sec end
    pcall(function() tab:Section({ Title = title }) end)
    return tab
end
local Box = {}

-- Angka pakai Slider; kalau gagal, pakai kotak input
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
local FarmTab = makeTab("Farm", "pickaxe", "farm")

safe(function()
    UI.Status = FarmTab:Paragraph({ Title = "Status", Desc = "-" })
end)

Box.FarmCtl = box(FarmTab, "Kontrol", true)
Box.FarmBlock = box(FarmTab, "Block", true)
Box.FarmSpeed = box(FarmTab, "Mode & Kecepatan", false)

safe(function()
    UI.FarmToggle = Box.FarmCtl:Toggle({
        Title = "Auto Farm",
        Desc = "Bisa juga lewat tombol START di Grid",
        Value = false,
        Callback = function(on)
            if on then startFarm() elseif State.Running then stopFarm() end
        end,
    })
end)

safe(function()
    Box.FarmCtl:Toggle({
        Title = "Auto Collect",
        Desc = "Ambil drop di tile yang dipilih",
        Value = State.AutoCollect,
        Callback = function(on) State.AutoCollect = on end,
    })
end)

safe(function()
    Box.FarmCtl:Toggle({
        Title = "Collect di sekitar karakter",
        Desc = "Ambil semua drop dalam radius, kapan saja",
        Value = State.CollectAround,
        Callback = function(on) State.CollectAround = on end,
    })
end)

addNumber(Box.FarmCtl, {
    Title = "Radius collect (tile)",
    Desc = "Dipakai juga Clear, Farmer, Splice & Pabrik. Terlalu jauh bisa ditolak server",
    Min = 1, Max = 8, Step = 1, Default = State.CollectRadius,
    Callback = function(v) State.CollectRadius = math.floor(v) end,
})

safe(function()
    Box.FarmCtl:Button({
        Title = "Buka Grid Tile",
        Desc = "Kotak 5x5, tengah = karakter",
        Callback = function() GridGui.Enabled = true end,
    })
end)

-- ===== TAB: CLEAR WORLD =====
local ClearTab = makeTab("Clear World", "eraser", "farm")

safe(function()
    UI.ClearStatus = ClearTab:Paragraph({ Title = "Status Clear", Desc = "-" })
end)

Box.ClearCtl = box(ClearTab, "Kontrol", true)
Box.ClearSet = box(ClearTab, "Pengaturan", false)

safe(function()
    UI.ClearToggle = Box.ClearCtl:Toggle({
        Title = "Auto Clear World",
        Desc = "Bersihkan dari baris atas ke bawah",
        Value = false,
        Callback = function(on)
            if on then Auto.startClear() elseif Clear.Running then stopClear() end
        end,
    })
end)

safe(function()
    Box.ClearSet:Dropdown({
        Title = "Arah sapu",
        Desc = "Zig-zag lebih cepat (tidak balik ke kiri)",
        Values = { "Kiri → Kanan", "Zig-zag" },
        Value = Clear.Sweep,
        Callback = function(opt) Clear.Sweep = opt end,
    })
end)

safe(function()
    Box.ClearSet:Toggle({
        Title = "Pakai block pijakan",
        Desc = "Taruh block untuk lewat jurang / naik ke block melayang",
        Value = Clear.UseBlock,
        Callback = function(on)
            Clear.UseBlock = on
            Auto.resetReach()
        end,
    })
end)

safe(function()
    UI.ClearBlockDropdown = Box.ClearSet:Dropdown({
        Title = "Block pijakan",
        Desc = "Block yang dipakai untuk pijakan",
        Values = { "(memuat...)" },
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
        Title = "Auto collect tiap habis pecah",
        Desc = "Ambil drop di sekitar karakter",
        Value = Clear.Collect,
        Callback = function(on) Clear.Collect = on end,
    })
end)

safe(function()
    Box.ClearCtl:Button({
        Title = "Reset tile yang dilewati",
        Desc = "Coba lagi tile yang tadi gagal",
        Callback = function()
            table.clear(Clear.Skip)
            table.clear(Auto.BadEdge)
            table.clear(Auto.ClearFail)
            Auto.updateClearStatus()
        end,
    })
end)

-- ===== TAB: FARMER =====
local FarmerTab = makeTab("Farmer", "leaf", "farm")

safe(function()
    UI.FarmerStatus = FarmerTab:Paragraph({ Title = "Status Farmer", Desc = "-" })
end)

Box.FarmerCtl = box(FarmerTab, "Kontrol", true)
Box.FarmerSeed = box(FarmerTab, "Seed", true)
Box.FarmerSpeed = box(FarmerTab, "Kecepatan", false)
Box.FarmerBlock = box(FarmerTab, "Block pijakan", false)

safe(function()
    UI.FarmerToggle = Box.FarmerCtl:Toggle({
        Title = "Jalankan Farmer",
        Desc = "Panen pohon siap & tanam seed otomatis",
        Value = false,
        Callback = function(on)
            if on then Auto.startFarmer() elseif Farmer.Running then stopFarmer() end
        end,
    })
end)

safe(function()
    UI.SeedDropdown = Box.FarmerSeed:Dropdown({
        Title = "Seed untuk ditanam",
        Desc = "Hanya seed yang ada di inventori",
        Values = { "(memuat...)" },
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
        Title = "Refresh daftar seed",
        Callback = function() refreshInvDropdown(true) end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Harvest",
        Desc = "Hanya pohon yang sudah siap",
        Value = Farmer.Harvest,
        Callback = function(on) Farmer.Harvest = on end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Plant",
        Desc = "Tanam di atas block yang kosong",
        Value = Farmer.Plant,
        Callback = function(on) Farmer.Plant = on end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Collect",
        Desc = "Ambil hasil panen di sekitar karakter",
        Value = Farmer.Collect,
        Callback = function(on) Farmer.Collect = on end,
    })
end)

addNumber(Box.FarmerSpeed, {
    Title = "Speed Harvest (ms)",
    Desc = "Jeda setelah tiap panen",
    Min = 140, Max = 2000, Step = 10, Default = Farmer.HarvestMs,
    Callback = function(v) Farmer.HarvestMs = math.floor(v) end,
})

addNumber(Box.FarmerSpeed, {
    Title = "Speed Plant (ms)",
    Desc = "Jeda setelah tiap tanam seed",
    Min = 140, Max = 2000, Step = 10, Default = Farmer.PlantMs,
    Callback = function(v) Farmer.PlantMs = math.floor(v) end,
})

safe(function()
    Box.FarmerBlock:Toggle({
        Title = "Pakai block pijakan",
        Desc = "Taruh block kalau tidak ada jalan (block tetap tertinggal)",
        Value = Farmer.UseBlock,
        Callback = function(on)
            Farmer.UseBlock = on
            Auto.resetReach()
        end,
    })
end)

safe(function()
    UI.FarmerBlockDropdown = Box.FarmerBlock:Dropdown({
        Title = "Block pijakan",
        Desc = "Block yang dipakai untuk pijakan",
        Values = { "(memuat...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                Farmer.ScaffoldId = id
                Auto.resetReach()
            end
        end,
    })
end)

-- ===== FARM: MODE & KECEPATAN =====
local SpeedTab = Box.FarmSpeed -- digabung ke tab Farm

safe(function()
    SpeedTab:Dropdown({
        Title = "Mode",
        Desc = "Place semua tile dulu, lalu break",
        Values = { "Place + Break", "Break saja", "Place saja" },
        Value = State.Mode,
        Callback = function(opt) State.Mode = opt end,
    })
end)

addNumber(SpeedTab, {
    Title = "Speed Place (ms)",
    Desc = "Jeda setelah tiap place",
    Min = 140, Max = 1000, Step = 10, Default = State.PlaceMs,
    Callback = function(v) State.PlaceMs = math.floor(v) end,
})

addNumber(SpeedTab, {
    Title = "Speed Break (ms)",
    Desc = "Jeda tiap pukulan (normal 220). Dipakai juga Clear",
    Min = 200, Max = 1000, Step = 10, Default = State.BreakMs,
    Callback = function(v) State.BreakMs = math.floor(v) end,
})

addNumber(SpeedTab, {
    Title = "Multi target break",
    Desc = "Auto Farm: tile dipukul bergantian (seperti 2 jari). Pakai Rayman's Fist = 2-3 tile segaris sekali pukul",
    Min = 1, Max = 5, Step = 1, Default = State.MultiTarget,
    Callback = function(v) State.MultiTarget = math.clamp(math.floor(v), 1, 5) end,
})

addNumber(SpeedTab, {
    Title = "Jeda setelah hancur (ms)",
    Desc = "Tunggu sebelum lanjut ke tile berikutnya",
    Min = 0, Max = 1500, Step = 50, Default = State.AfterBreakMs,
    Callback = function(v) State.AfterBreakMs = math.floor(v) end,
})

-- ===== TAB: PENGATURAN (Opsi + Misc digabung) =====
local SetTab = makeTab("Pengaturan", "sliders-horizontal", "setel")
Box.SetChar = box(SetTab, "Karakter", true)
Box.SetOpt = box(SetTab, "Opsi", true)
local OptTab = Box.SetOpt

safe(function()
    OptTab:Toggle({
        Title = "Mode Lite",
        Desc = "Matikan particle & suara (HP low-end)",
        Value = State.LiteMode,
        Callback = function(on) setLite(on) end,
    })
end)

safe(function()
    OptTab:Toggle({
        Title = "Mute suara pukulan",
        Value = State.MutePunch,
        Callback = function(on) State.MutePunch = on end,
    })
end)

safe(function()
    OptTab:Toggle({
        Title = "Anti AFK",
        Value = State.AntiAfk,
        Callback = function(on) State.AntiAfk = on end,
    })
end)

addNumber(OptTab, {
    Title = "Pukulan per block (cadangan)",
    Desc = "Dipakai kalau 'Pukul: TIDAK'. 0 = otomatis",
    Min = 0, Max = 20, Step = 1, Default = State.HitsOverride,
    Callback = function(v) State.HitsOverride = math.floor(v) end,
})

-- ===== FARM: PILIH BLOCK =====
local InvTab = Box.FarmBlock -- digabung ke tab Farm

safe(function()
    UI.InvDropdown = InvTab:Dropdown({
        Title = "Pilih Block",
        Desc = "Hanya item yang bisa di-place",
        Values = { "(memuat...)" },
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
    InvTab:Button({
        Title = "Refresh daftar",
        Callback = function() refreshInvDropdown(true) end,
    })
end)

-- ===== PENGATURAN: KARAKTER =====
local MiscTab = Box.SetChar

addNumber(MiscTab, {
    Title = "Walkspeed (%)",
    Desc = "100 = normal",
    Min = 50, Max = 500, Step = 10, Default = Misc.Speed,
    Callback = function(v) setSpeed(v) end,
})

safe(function()
    MiscTab:Toggle({
        Title = "Infinite Jump",
        Desc = "Lompat di udara (bisa kena rollback)",
        Value = false,
        Callback = function(on) setInfJump(on) end,
    })
end)

safe(function()
    UI.GhostToggle = MiscTab:Toggle({
        Title = "Fly + Tembus Block",
        Desc = "Tembus block, pakai tombol ▲/▼ (bisa kena rollback)",
        Value = false,
        Callback = function(on) setGhost(on) end,
    })
end)

-- ===== TAB: AUTO CHAT =====
local ChatTab = makeTab("Auto Chat", "message-circle", "fitur")

safe(function()
    UI.SpamStatus = ChatTab:Paragraph({ Title = "Status Chat", Desc = "-" })
end)

Box.ChatCtl = box(ChatTab, "Kontrol", true)
Box.ChatMsg = box(ChatTab, "Pesan", true)

safe(function()
    Box.ChatMsg:Input({
        Title = "Daftar pesan",
        Desc = "Pisahkan dengan |   contoh: halo|jual dirt",
        Value = table.concat(Spam.Texts, "|"),
        Placeholder = "pesan 1|pesan 2|pesan 3",
        Callback = function(text)
            Spam.Texts = parseSpamTexts(text)
            Spam.Index = 1
            updateSpamStatus()
        end,
    })
end)

addNumber(Box.ChatMsg, {
    Title = "Interval (detik)",
    Desc = "Jeda antar pesan (min 3 detik)",
    Min = 3, Max = 120, Step = 1, Default = Spam.IntervalSec,
    Callback = function(v) Spam.IntervalSec = math.max(3, math.floor(v)) end,
})

safe(function()
    UI.SpamToggle = Box.ChatCtl:Toggle({
        Title = "Auto Chat",
        Desc = "Kirim pesan bergantian sesuai urutan",
        Value = false,
        Callback = function(on)
            Spam.On = on
            if on then
                if #Spam.Texts == 0 then notify("Auto Chat", "Isi daftar pesan dulu (tekan Enter setelah mengetik)", 4) end
                Spam.NextAt = 0 -- langsung kirim pesan pertama
            end
            updateSpamStatus()
        end,
    })
end)

safe(function()
    Box.ChatCtl:Button({
        Title = "Kirim 1 pesan sekarang",
        Desc = "Tes kirim pesan berikutnya",
        Callback = function()
            task.spawn(function()
                sendNextChat()
                updateSpamStatus()
            end)
        end,
    })
end)

-- ===== TAB: STAFF =====
local function roleOptions()
    local out, seen = { "none" }, { none = true }
    if RolesOk and type(RolesModule) == "table" and type(RolesModule.titlesOf) == "function" then
        local ok, list = pcall(RolesModule.titlesOf, LocalPlayer.UserId)
        if ok and type(list) == "table" then
            for _, code in ipairs(list) do
                if type(code) == "string" and not seen[code] then
                    seen[code] = true
                    local label = code
                    if type(RolesModule.titleName) == "function" then
                        local okn, nm = pcall(RolesModule.titleName, code)
                        if okn and type(nm) == "string" and nm ~= "" and nm ~= code then
                            label = nm .. " [" .. code .. "]"
                        end
                    end
                    table.insert(out, label)
                end
            end
        end
    end
    return out
end

local function roleFromLabel(label)
    return string.match(label or "", "%[(.-)%]$") or label
end

local function refreshRoles()
    if UI.RoleDropdown then pcall(function() UI.RoleDropdown:Refresh(roleOptions()) end) end
end

local StaffTab = makeTab("Staff", "user-cog", "aman")

safe(function()
    StaffTab:Button({
        Title = "Buka Staff Backpack",
        Desc = "UI staff bawaan game (dikunci server)",
        Callback = function()
            if Refs.Menu and type(Refs.Menu.openBackpack) == "function" then
                local target = { name = LocalPlayer.DisplayName or LocalPlayer.Name, userId = LocalPlayer.UserId }
                local ok, err = pcall(Refs.Menu.openBackpack, target)
                if not ok then notify("Staff", "Gagal buka: " .. tostring(err), 4) end
            else
                notify("Staff", "Menu game belum ketemu. Tekan 'Hubungkan ke game' dulu", 4)
            end
        end,
    })
end)

safe(function()
    UI.RoleDropdown = StaffTab:Dropdown({
        Title = "Role / Title",
        Desc = "Title yang kamu punya",
        Values = { "none" },
        Callback = function(opt) State.Role = roleFromLabel(opt) end,
    })
end)

safe(function()
    StaffTab:Button({
        Title = "Refresh daftar role",
        Callback = refreshRoles,
    })
end)

safe(function()
    StaffTab:Button({
        Title = "Pakai Role",
        Desc = "Sama seperti menu Title game",
        Callback = function()
            local role = (State.Role ~= "" and State.Role) or "none"
            if NetOk and type(Net) == "table" and type(Net.call) == "function" then
                -- sama seperti menu Title game
                task.spawn(function()
                    local ok, err = pcall(Net.call, "PickTitle", role)
                    notify("Staff", ok and ("Role dikirim: " .. role) or ("Gagal: " .. tostring(err)), 4)
                end)
            else
                local pt = WorldRemotes:FindFirstChild("PickTitle")
                if pt then
                    pcall(function() pt:FireServer(role) end)
                    notify("Staff", "Role dikirim: " .. role)
                else
                    notify("Staff", "Fungsi PickTitle tidak ada")
                end
            end
        end,
    })
end)

---------------------------------------------------------------------
-- PENJAGA: deteksi Mod / Dev / pemain yang masuk world
---------------------------------------------------------------------
-- Cara kerja:
--   1. Tiap 0.5 detik baca daftar pemain di world (data game "Others").
--   2. Role dicek pakai modul Roles game (Developer / Moderator, undercover juga ketahuan).
--   3. Ada yang dicari -> semua aktivitas dihentikan, bisa juga langsung keluar world.
--   4. Setelah aman -> aktivitas sebelumnya dilanjutkan.
--      Mode keluar: tunggu X detik, masuk world lagi, cek lagi.
--      Masih ada orangnya -> keluar lagi. Sudah aman -> lanjut (Auto Farm jalan balik ke posisi awal).

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
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

    -- Pemain lain di world ini: { id, name, role }
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
            if p.role or (Guard.Who == "Semua pemain" and not Guard.Allow[p.id]) then
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
        return p.name .. " (" .. (p.role or "Pemain") .. (under and ", undercover" or "") .. ")"
    end

    local function names(list, max)
        local t = {}
        for i, p in ipairs(list) do
            if i > (max or 4) then
                t[#t + 1] = "+" .. (#list - i + 1) .. " lagi"
                break
            end
            t[#t + 1] = label(p)
        end
        return table.concat(t, ", ")
    end

    local function anyRunning()
        return State.Running or Clear.Running or Farmer.Running or Splice.Running or Spam.On
            or Pabrik.Running or Build.Running
    end

    -- Catat aktivitas yang sedang jalan (untuk dilanjutkan nanti)
    local function snapshot()
        local tx, ty = Auto.here()
        return {
            farm = State.Running and not State.Override, clear = Clear.Running, farmer = Farmer.Running,
            spam = Spam.On, splice = Splice.Running, pabrik = Pabrik.Running, build = Build.Running,
            world = worldName(), tx = tx, ty = ty,
        }
    end

    local function stopAll()
        Auto.stopWalk()
        if Pabrik.Running then Pabrik.stop() end
        if Build.Running then Build.stop() end
        if State.Running then stopFarm() end
        if Clear.Running then
            stopClear()
            Clear.Status = "Dijeda Penjaga"
        end
        if Farmer.Running then
            stopFarmer()
            Farmer.Status = "Dijeda Penjaga"
        end
        if Splice.Running and Splice.stop then Splice.stop() end
        if Spam.On then
            Spam.On = false
            if UI.SpamToggle then pcall(function() UI.SpamToggle:Set(false) end) end
        end
        Auto.releaseInput()
    end

    -- Keluar world = sama seperti tombol "Exit World" game
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

    -- Masuk world lewat menu game (sama seperti ketik nama world lalu Enter)
    local function enterWorld(name)
        local w = Refs.World
        if not w or name == "" then return false, "nama world tidak diketahui" end
        local oldFg = rawget(w, "fg")
        local m = Refs.Menu
        if m and type(rawget(m, "enter")) == "function" then
            pcall(m.enter, name)
        elseif type(rawget(w, "enter")) == "function" then
            local ok, res, msg = pcall(w.enter, name)
            if ok and not res then return false, strip(msg) end
        else
            return false, "fungsi masuk world tidak ketemu"
        end
        -- berhasil kalau data world sudah diganti yang baru
        local t0 = os.clock()
        while alive() and os.clock() - t0 < 8 do
            if rawget(w, "fg") ~= oldFg then return true end
            task.wait(0.25)
        end
        return false, "world penuh / dikunci / gagal"
    end

    local function stillBack(token)
        return alive() and Guard.Token == token and Guard.Mode == "back"
    end

    -- Lanjutkan aktivitas yang tadi dihentikan
    local function resumeAll(saved, token)
        if not saved then return end
        if saved.world ~= "" and worldName() ~= saved.world then
            notify("Penjaga", "World sudah beda, aktivitas tidak dilanjutkan", 5)
            return
        end
        if saved.spam and not Spam.On and stillBack(token) then
            if UI.SpamToggle then pcall(function() UI.SpamToggle:Set(true) end) end
            Spam.On = true
        end
        if saved.build then
            if stillBack(token) then Build.start() end
        elseif saved.pabrik then
            if stillBack(token) then Pabrik.start() end
        elseif saved.farm then
            -- Auto Farm memakai tile di sekitar karakter, jadi harus balik ke posisi awal
            local hx, hy = Auto.here()
            if saved.tx and (hx ~= saved.tx or hy ~= saved.ty) then
                Guard.BackText = ("Jalan balik ke posisi farm (%d,%d)"):format(saved.tx, saved.ty)
                local ok = Auto.walkTo(saved.tx, saved.ty, 45)
                if not ok and stillBack(token) then ok = Auto.walkTo(saved.tx, saved.ty, 30) end
                if not ok then
                    if stillBack(token) then
                        notify("Penjaga", "Gagal balik ke posisi farm. Auto Farm tidak dilanjutkan", 6)
                    end
                    return
                end
            end
            if stillBack(token) then startFarm() end
        elseif saved.clear then
            if stillBack(token) then Auto.startClear() end
        elseif saved.farmer then
            if stillBack(token) then Auto.startFarmer() end
        elseif saved.splice then
            if stillBack(token) and Splice.start then Splice.start() end
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
            if not ok then warn("[Fian792] Penjaga lanjut error: " .. tostring(err)) end
            if Guard.Token == token and Guard.Mode == "back" then
                Guard.Mode, Guard.Saved, Guard.BackText = "idle", nil, nil
            end
        end)
    end

    local function goAway()
        if not leaveWorld() then
            notify("Penjaga", "Gagal keluar world, aktivitas hanya dijeda", 5)
            Guard.Mode = "pause"
            return
        end
        task.wait(0.3)
        Guard.LeftFg = Refs.World and rawget(Refs.World, "fg")
        Guard.BackAt = os.clock() + Guard.BackSec
        Guard.Mode = Guard.AutoBack and "away" or "out"
        Guard.Status = "Keluar world"
    end

    -- Ada orang baru yang dicari masuk world
    local function trigger(fresh)
        Guard.Detected += #fresh
        notify("Penjaga", "Masuk world: " .. names(fresh), 6)
        Hook.send("penjaga", "Masuk world " .. worldName() .. ": " .. names(fresh))
        if not Guard.StopAll and not Guard.Leave then return end -- hanya peringatan
        -- simpan aktivitas (kalau sedang jalan balik, pakai catatan lama)
        if Guard.Mode ~= "back" and (anyRunning() or not Guard.Saved) then
            Guard.Saved = snapshot()
        end
        Guard.Token += 1
        stopAll()
        Guard.CalmAt = nil
        if Guard.Leave then
            goAway()
            if Guard.Mode == "away" then
                notify("Penjaga", "Keluar world. Masuk lagi dalam " .. Guard.BackSec .. " detik", 5)
                Hook.send("penjaga", "Keluar world, masuk lagi dalam " .. Guard.BackSec .. " detik")
            elseif Guard.Mode == "out" then
                notify("Penjaga", "Keluar world", 4)
            end
        else
            Guard.Mode = "pause"
        end
    end

    -- Setelah masuk world lagi: cek dulu, masih ada orangnya atau tidak
    local function checkAfterEnter()
        Auto.resetReach()
        pcall(findDropRefs)
        pcall(Auto.findTreeRefs)
        table.clear(DropFailUntil)
        task.wait(1.5) -- tunggu daftar pemain terisi
        local th = threatsOf(playersHere())
        if #th > 0 then
            for _, p in ipairs(th) do Guard.Alerted[p.id] = true end
            notify("Penjaga", "Masih ada " .. names(th) .. ". Keluar lagi", 5)
            goAway()
            return
        end
        notify("Penjaga", "World aman, lanjut aktivitas", 4)
        Hook.send("penjaga", "World " .. worldName() .. " aman, lanjut aktivitas")
        beginResume()
    end

    -- Staff yang online di server (bukan hanya di world ini)
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
        staffText = (#t > 0) and table.concat(t, ", ") or "tidak ada"
        return staffText
    end

    function Guard.tick(here)
        if not Guard.On then
            Guard.Status = "Mati"
            return
        end
        local now = os.clock()
        local mode = Guard.Mode

        -- ===== sedang di luar world =====
        if mode == "away" or mode == "out" then
            local fgNow = Refs.World and rawget(Refs.World, "fg")
            if Guard.LeftFg and fgNow ~= Guard.LeftFg then
                -- sudah masuk world lagi secara manual
                if mode == "away" and Guard.Saved and worldName() == Guard.Saved.world then
                    checkAfterEnter()
                else
                    Guard.Mode, Guard.Saved = "idle", nil
                end
                return
            end
            local name = Guard.Saved and Guard.Saved.world or ""
            if mode == "out" or name == "" then
                Guard.Status = "Sudah keluar world (lanjut otomatis mati)"
                return
            end
            local left = Guard.BackAt - now
            if left > 0 then
                Guard.Status = ("Di luar world. Masuk lagi ke %s dalam %d detik"):format(name, math.ceil(left))
                return
            end
            Guard.Status = "Masuk lagi ke " .. name .. "..."
            Guard.updateStatus({})
            local ok, err = enterWorld(name)
            if not ok then
                Guard.BackAt = os.clock() + math.max(15, Guard.BackSec)
                notify("Penjaga", "Gagal masuk " .. name .. ": " .. tostring(err) .. ". Dicoba lagi nanti", 5)
                return
            end
            checkAfterEnter()
            return
        end

        -- ===== di dalam world =====
        local present = {}
        for _, p in ipairs(here) do present[p.id] = true end
        for id in pairs(Guard.Alerted) do
            if not present[id] then Guard.Alerted[id] = nil end -- sudah pergi
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
            Guard.Status = (Guard.Mode == "pause" and "Dijeda. Ada: " or "Waspada. Ada: ") .. names(threats)
            return
        end

        if Guard.Mode == "pause" then
            Guard.CalmAt = Guard.CalmAt or now
            local wait = Guard.CalmSec - (now - Guard.CalmAt)
            if wait > 0 then
                Guard.Status = ("Mereka sudah pergi. Lanjut dalam %d detik"):format(math.ceil(wait))
                return
            end
            Guard.CalmAt = nil
            if Guard.AutoBack and Guard.Saved then
                notify("Penjaga", "Sudah aman, lanjut aktivitas", 4)
                beginResume()
            else
                Guard.Mode, Guard.Saved = "idle", nil
            end
            return
        end

        if Guard.Mode == "back" then
            Guard.Status = Guard.BackText or "Lanjut aktivitas..."
            return
        end
        Guard.Status = "Aman"
    end

    function Guard.updateStatus(here)
        local txt = table.concat({
            "Status: " .. Guard.Status .. (Refs.Others and "" or " (data pemain belum ketemu: tekan 'Hubungkan ke game')"),
            "Pemain di world: " .. ((#here == 0) and "tidak ada" or names(here, 6)),
            "Staff online di server: " .. serverStaff(),
            "Terdeteksi: " .. Guard.Detected .. " kali",
        }, "\n")
        if txt ~= Guard.LastTxt then
            Guard.LastTxt = txt
            if UI.GuardStatus then pcall(function() UI.GuardStatus:SetDesc(txt) end) end
        end
    end

    -- Nyalakan / matikan Penjaga
    function Guard.set(on)
        Guard.On = on
        Guard.Token += 1
        Auto.stopWalk()
        Guard.Mode, Guard.Saved, Guard.CalmAt, Guard.BackText = "idle", nil, nil, nil
        table.clear(Guard.Alerted)
        table.clear(Guard.Allow)
        if on then
            -- pemain biasa yang sudah ada sekarang diabaikan (teman / akun sendiri)
            for _, p in ipairs(playersHere()) do
                if not p.role then Guard.Allow[p.id] = true end
            end
        end
    end

    -- dipakai fitur lain (Auto Reconnect)
    Guard.snapshot = snapshot
    Guard.stopAll = stopAll
    Guard.enterWorld = enterWorld
    Guard.leaveWorld = leaveWorld
    Guard.worldName = worldName
    Guard.anyRunning = anyRunning
    function Guard.afterEnter()
        Auto.resetReach()
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
            if not ok then warn("[Fian792] Penjaga error: " .. tostring(err)) end
            Guard.updateStatus(here)
            task.wait(0.5)
        end
    end)
end)() end

Config.add("Penjaga", Guard, { "On", "Who", "StopAll", "Leave", "AutoBack", "BackSec", "CalmSec" }, { On = true })

-- ===== TAB: PENJAGA =====
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local GuardTab = makeTab("Penjaga", "eye", "aman")

    safe(function()
        UI.GuardStatus = GuardTab:Paragraph({ Title = "Status Penjaga", Desc = "Mati" })
    end)

    local gCtl = box(GuardTab, "Kontrol", true)
    local gAct = box(GuardTab, "Aksi saat terdeteksi", true)
    local gTime = box(GuardTab, "Waktu", false)
    local gMore = box(GuardTab, "Lainnya", false)

    safe(function()
        UI.GuardToggle = gCtl:Toggle({
            Title = "Aktifkan Penjaga",
            Desc = "Pantau Mod / Dev / pemain yang masuk world",
            Value = false,
            Callback = function(on) Guard.set(on) end,
        })
    end)

    safe(function()
        gCtl:Dropdown({
            Title = "Yang dideteksi",
            Desc = "Semua pemain: yang sudah ada saat dinyalakan diabaikan",
            Values = { "Staff (Mod/Dev)", "Semua pemain" },
            Value = Guard.Who,
            Callback = function(opt) Guard.Who = opt end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Diam semua aktivitas",
            Desc = "Stop Auto Farm, Clear, Farmer & Auto Chat",
            Value = Guard.StopAll,
            Callback = function(on) Guard.StopAll = on end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Keluar world",
            Desc = "Langsung keluar world saat terdeteksi",
            Value = Guard.Leave,
            Callback = function(on) Guard.Leave = on end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Lanjut otomatis setelah aman",
            Desc = "Keluar world: masuk lagi, cek, lalu lanjut aktivitas sebelumnya",
            Value = Guard.AutoBack,
            Callback = function(on) Guard.AutoBack = on end,
        })
    end)

    addNumber(gTime, {
        Title = "Masuk world lagi setelah (detik)",
        Desc = "Untuk mode keluar world",
        Min = 20, Max = 600, Step = 5, Default = Guard.BackSec,
        Callback = function(v) Guard.BackSec = math.floor(v) end,
    })

    addNumber(gTime, {
        Title = "Tunggu aman (detik)",
        Desc = "Untuk mode diam: jeda setelah mereka pergi",
        Min = 2, Max = 60, Step = 1, Default = Guard.CalmSec,
        Callback = function(v) Guard.CalmSec = math.floor(v) end,
    })

    safe(function()
        gMore:Button({
            Title = "Abaikan pemain yang ada sekarang",
            Desc = "Untuk teman / akun sendiri (staff tetap dideteksi)",
            Callback = function()
                notify("Penjaga", Guard.allowNow() .. " pemain diabaikan", 3)
            end,
        })
    end)

    safe(function()
        gMore:Button({
            Title = "Batalkan tunggu / lanjut",
            Desc = "Hentikan proses keluar-masuk & lanjut otomatis",
            Callback = function()
                Guard.set(Guard.On)
                notify("Penjaga", "Dibatalkan", 3)
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- BONUS: auto klaim quest & auto redeem code
---------------------------------------------------------------------
-- Pakai panggilan yang sama dengan menu Quest & Redeem game:
--   Net.call("Quests", "list")            -> daftar quest hari ini
--   Net.call("Quests", "claim", id)       -> klaim hadiah (server yang cek syaratnya)
--   Net.call("ActiveCodes")               -> daftar code aktif
--   Net.call("ModCommand", "redeemcode", code) -> tukar code (dipakai menu Redeem game)
local Bonus = {
    Quest = false,
    Redeem = false,
    QuestEvery = 30,   -- cek quest tiap 30 detik
    CodeEvery = 300,   -- cek code tiap 5 menit
    NextQuest = 0,
    NextCode = 0,
    Claimed = 0,
    Redeemed = 0,
    Tried = {},        -- code yang sudah dicoba
    QuestFail = {},    -- quest yang ditolak server (dicoba lagi nanti)
    QuestText = "-",
    CodeText = "-",
    ResetAt = nil,
}

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local function strip(s) return (tostring(s or ""):gsub("`.", "")) end

    local function netCall(...)
        if NetOk and type(Net) == "table" and type(Net.call) == "function" then
            return pcall(Net.call, ...)
        end
        return false, "Net.call tidak ada"
    end

    local function timeText(sec)
        sec = math.max(0, math.floor(sec or 0))
        if sec >= 3600 then return ("%dj %dm"):format(sec // 3600, sec % 3600 // 60) end
        return ("%dm %dd"):format(sec // 60, sec % 60)
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
            Bonus.QuestText = "Gagal ambil quest: " .. strip(good)
        elseif not good or type(data) ~= "table" or type(data.quests) ~= "table" then
            Bonus.QuestText = "Quest belum bisa diambil" .. (type(data) == "string" and (": " .. strip(data)) or "")
        else
            local total, done, wait = 0, 0, 0
            local now = os.clock()
            for _, q in ipairs(data.quests) do
                total += 1
                local have, need = tonumber(q.have) or 0, tonumber(q.need) or math.huge
                if q.claimed then
                    done += 1
                elseif have >= need and not ((Bonus.QuestFail[q.id] or 0) > now) then
                    -- syarat sama seperti tombol Claim game
                    local okc, success, msg, _, gems = netCall("Quests", "claim", q.id)
                    if okc and success then
                        done += 1
                        Bonus.Claimed += 1
                        local reward = q.xp and (tostring(q.reward) .. " XP") or (tostring(q.reward) .. " gems")
                        notify("Quest diklaim", strip(q.text or q.id) .. "  +" .. reward, 4)
                        Hook.send("bonus", "Quest diklaim: " .. strip(q.text or q.id) .. " +" .. reward)
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
            Bonus.QuestText = ("Selesai %d/%d | diklaim script: %d"):format(done, total, Bonus.Claimed)
                .. ((wait > 0) and (" | ditolak: " .. wait) or "")
        end
        Bonus.BusyQ = false
    end

    -- Tukar 1 code. Berhasil kalau balasan server diawali warna hijau (`2)
    function Bonus.redeem(code)
        local ok, res = netCall("ModCommand", "redeemcode", code)
        if not ok then return nil, "tidak bisa ke server" end
        local lines = type(res) == "table" and type(res.lines) == "table" and res.lines or nil
        if not lines then return false, "balasan kosong" end
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
            Bonus.CodeText = "Gagal ambil daftar code"
        elseif list.note ~= nil then
            Bonus.CodeText = "Redeem sedang ditutup: " .. strip(list.note)
        else
            local total, have, newOk = 0, 0, 0
            for _, c in ipairs(list) do
                total += 1
                local code = c.code and tostring(c.code)
                if c.done then
                    have += 1
                elseif code and not Bonus.Tried[code] and not (type(c.uses) == "number" and c.uses == 0) then
                    local success, msg = Bonus.redeem(code)
                    if success ~= nil then Bonus.Tried[code] = true end -- server sudah jawab
                    if success then
                        have += 1
                        newOk += 1
                        Bonus.Redeemed += 1
                        notify("Redeem berhasil", code .. ": " .. tostring(msg), 5)
                        Hook.send("bonus", "Redeem berhasil " .. code .. ": " .. tostring(msg))
                    elseif success == false then
                        Bonus.LastCodeMsg = code .. ": " .. tostring(msg)
                    end
                    task.wait(1)
                end
            end
            Bonus.CodeText = ("Code aktif: %d | sudah ditukar: %d | ditukar script: %d"):format(total, have, Bonus.Redeemed)
        end
        Bonus.BusyR = false
    end

    function Bonus.updateStatus()
        local now = os.clock()
        local q = Bonus.QuestText
        if Bonus.ResetAt then q = q .. "\nQuest baru dalam " .. timeText(Bonus.ResetAt - now) end
        if Bonus.LastQuestMsg then q = q .. "\nPesan terakhir: " .. Bonus.LastQuestMsg end
        q = q .. "\n" .. (Bonus.Quest and ("Cek lagi dalam " .. math.max(0, math.ceil(Bonus.NextQuest - now)) .. " detik") or "Auto klaim mati")
        local c = Bonus.CodeText
        if Bonus.LastCodeMsg then c = c .. "\nPesan terakhir: " .. Bonus.LastCodeMsg end
        c = c .. "\n" .. (Bonus.Redeem and ("Cek lagi dalam " .. timeText(Bonus.NextCode - now)) or "Auto redeem mati")
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
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local BonusTab = makeTab("Bonus", "gift", "fitur")
    local bQuest = box(BonusTab, "Quest Harian", true)
    local bCode = box(BonusTab, "Redeem Code", true)

    safe(function()
        UI.QuestStatus = bQuest:Paragraph({ Title = "Status", Desc = "-" })
    end)

    safe(function()
        bQuest:Toggle({
            Title = "Auto Claim Quest",
            Desc = "Klaim hadiah quest yang sudah selesai",
            Value = Bonus.Quest,
            Callback = function(on)
                Bonus.Quest = on
                if on then Bonus.NextQuest = 0 end
            end,
        })
    end)

    safe(function()
        bQuest:Button({
            Title = "Cek quest sekarang",
            Callback = function() task.spawn(Bonus.checkQuests) end,
        })
    end)

    safe(function()
        UI.CodeStatus = bCode:Paragraph({ Title = "Status", Desc = "-" })
    end)

    safe(function()
        bCode:Toggle({
            Title = "Auto Redeem Code",
            Desc = "Tukar semua code aktif yang belum dipakai",
            Value = Bonus.Redeem,
            Callback = function(on)
                Bonus.Redeem = on
                if on then Bonus.NextCode = 0 end
            end,
        })
    end)

    safe(function()
        bCode:Button({
            Title = "Cek code sekarang",
            Callback = function()
                table.clear(Bonus.Tried)
                task.spawn(Bonus.checkCodes)
            end,
        })
    end)

    safe(function()
        bCode:Input({
            Title = "Redeem code manual",
            Desc = "Ketik code lalu tekan Enter",
            Value = "",
            Placeholder = "KODE",
            Callback = function(text)
                local code = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if code == "" then return end
                task.spawn(function()
                    local success, msg = Bonus.redeem(code)
                    if success then Bonus.Redeemed += 1 end
                    notify(success and "Redeem berhasil" or "Redeem gagal", code .. ": " .. tostring(msg), 5)
                end)
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- GROWSCAN: Floating Items & World Blocks (seperti Growscan 9000 di Growtopia)
---------------------------------------------------------------------
-- Cara kerja:
--   - Floating Items: daftar drop di world (data drop game), dijumlah per item.
--   - World Blocks: semua tile world dihitung per item (block depan + background).
--     Seed yang tertanam di block depan = pohon.
--   - Auto Scan: diulang tiap 2 detik. Hasil diurutkan dari jumlah terbanyak.
local Scan = {
    Auto = false,
    Layer = "Semua",      -- "Semua" | "Depan" | "Background"
    Filter = "",          -- cari nama item
    Every = 2,
    Limit = 60,           -- maksimal baris per daftar
    Last = nil,
}

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local function fmtNum(n)
        local str = tostring(math.floor(n))
        local out = str:reverse():gsub("(%d%d%d)", "%1."):reverse()
        return (out:gsub("^%.", ""))
    end

    local function blockName(id)
        local it = ItemDB[id]
        local nm = itemName(id)
        if it and it.kind == "seed" then nm = nm .. " (pohon)" end
        return nm
    end

    -- Ubah hitungan {id = jumlah} jadi teks, urut dari terbanyak
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
        if total > Scan.Limit then lines[#lines + 1] = ("... +%d item lain (pakai Cari item)"):format(total - Scan.Limit) end
        if #lines == 0 then lines[1] = (filter ~= "") and "Tidak ada yang cocok" or "Kosong" end
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
        local fgC, bgC, nf, nb = {}, {}, 0, 0
        local trees = {} -- [seed] = { r = siap, g = tumbuh, nxt = detik ke panen berikutnya }
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
            end
            if y % 64 == 63 then task.wait() end -- world besar: jangan bikin lag
        end
        return fgC, bgC, nf, nb, trees
    end

    local function waitText(sec)
        sec = math.max(0, math.floor(sec or 0))
        if sec >= 3600 then return ("%dj %dm"):format(sec // 3600, sec % 3600 // 60) end
        return ("%dm %dd"):format(sec // 60, sec % 60)
    end

    -- Daftar pohon: siap panen dulu, lalu yang paling cepat siap
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
                lines[#lines + 1] = ("... +%d jenis lain"):format(#list - Scan.Limit)
                break
            end
            local line = ("%s: %d siap | %d tumbuh"):format(v.name, v.e.r, v.e.g)
            if v.e.nxt then line = line .. " (berikut " .. waitText(v.e.nxt) .. ")" end
            lines[#lines + 1] = line
        end
        if #lines == 0 then lines[1] = (filter ~= "") and "Tidak ada yang cocok" or "Tidak ada pohon" end
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
        local treeTxt, treeR, treeG = "Data pohon belum ketemu", nil, nil
        if trees then treeTxt, treeR, treeG = treeText(trees) end

        local floatText = fl and select(1, listText(fl, itemName)) or "Data drop belum ketemu. Tekan 'Hubungkan ke game'"
        local blockText = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
        if fgC then
            local pick
            if Scan.Layer == "Depan" then
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
            "Block depan: " .. (nf and fmtNum(nf) or "-") .. " | Background: " .. (nb and fmtNum(nb) or "-"),
            "Floating: " .. (flTotal and (fmtNum(flTotal) .. " item (" .. piles .. " tumpukan)") or "-"),
            "Pohon: " .. (treeR and (fmtNum(treeR) .. " siap panen | " .. fmtNum(treeG) .. " tumbuh") or "-"),
            "Scan terakhir: " .. os.date("%H:%M:%S"),
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
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local ScanTab = makeTab("Growscan", "scan-search", "fitur")

    safe(function()
        UI.ScanInfo = ScanTab:Paragraph({ Title = "Info World", Desc = "Tekan Scan sekarang" })
    end)

    local sCtl = box(ScanTab, "Kontrol", true)
    local sFloat = box(ScanTab, "Floating Items", true)
    local sBlock = box(ScanTab, "World Blocks", false)
    local sTree = box(ScanTab, "Pohon (siap panen)", true)

    safe(function()
        sCtl:Toggle({
            Title = "Auto Scan",
            Desc = "Update otomatis tiap 2 detik",
            Value = Scan.Auto,
            Callback = function(on)
                Scan.Auto = on
                if on then task.spawn(Scan.run) end
            end,
        })
    end)

    safe(function()
        sCtl:Button({
            Title = "Scan sekarang",
            Callback = function() task.spawn(Scan.run) end,
        })
    end)

    safe(function()
        sCtl:Input({
            Title = "Cari item",
            Desc = "Saring nama item (kosongkan = semua)",
            Value = "",
            Placeholder = "contoh: seed",
            Callback = function(text)
                Scan.Filter = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                task.spawn(Scan.run)
            end,
        })
    end)

    safe(function()
        UI.ScanFloat = sFloat:Paragraph({ Title = "Daftar", Desc = "-" })
    end)

    safe(function()
        sBlock:Dropdown({
            Title = "Layer",
            Values = { "Semua", "Depan", "Background" },
            Value = Scan.Layer,
            Callback = function(opt)
                Scan.Layer = opt
                task.spawn(Scan.run)
            end,
        })
    end)

    safe(function()
        UI.ScanBlocks = sBlock:Paragraph({ Title = "Daftar", Desc = "-" })
    end)

    safe(function()
        UI.ScanTrees = sTree:Paragraph({ Title = "Daftar", Desc = "-" })
    end)
end)() end

---------------------------------------------------------------------
-- STATISTIK SESI
---------------------------------------------------------------------
-- Cara kerja:
--   - Saat execute (atau tombol Reset), angka awal dicatat.
--   - Tiap detik: angka sekarang - angka awal = hasil sesi. Dibagi lama sesi = per jam.
--   - Gems dibaca dari angka gems di HUD game (nilai di dalam fungsi addGems).
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
        return ("%dj %dm %dd"):format(sec // 3600, sec % 3600 // 60, sec % 60)
    end

    -- angka yang dihitung (semuanya naik terus selama script jalan)
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
            return ("%s: %s  (%s/jam)"):format(label, fmt(v), fmt(v / hours))
        end
        local g = gemsNow()
        if g and not Stats.Gems0 then Stats.Gems0 = g end
        local gemLine = "Gems: -"
        if g and Stats.Gems0 then
            local d = g - Stats.Gems0
            gemLine = ("Gems: %s  (%s%s, %s/jam)"):format(fmt(g), d >= 0 and "+" or "", fmt(d), fmt(d / hours))
        end
        -- 5 item terbanyak yang terkumpul
        local top = {}
        for id, n in pairs(Stats.Items) do top[#top + 1] = { id = id, n = n } end
        table.sort(top, function(a, b) return a.n > b.n end)
        local tops = {}
        for i = 1, math.min(5, #top) do tops[i] = itemName(top[i].id) .. " x" .. fmt(top[i].n) end
        return table.concat({
            "Lama sesi: " .. dur(os.clock() - Stats.T0),
            gemLine,
            line("Block pecah", "broken"),
            line("Block di-place", "placed"),
            line("Drop diambil", "collected"),
            line("Panen", "harvested"),
            line("Tanam", "planted"),
            "Item terbanyak: " .. ((#tops > 0) and table.concat(tops, ", ") or "-"),
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
            -- laporan berkala ke Discord
            if Hook.ReportMin > 0 and os.clock() - lastReport >= Hook.ReportMin * 60 then
                lastReport = os.clock()
                if ok then Hook.send("report", "Laporan statistik\n```\n" .. txt .. "\n```") end
            elseif Hook.ReportMin <= 0 then
                lastReport = os.clock()
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: STATISTIK =====
do (function()
    local StatTab = makeTab("Statistik", "bar-chart-3", "fitur")

    safe(function()
        UI.StatsText = StatTab:Paragraph({ Title = "Sesi ini", Desc = "-" })
    end)

    safe(function()
        StatTab:Button({
            Title = "Reset statistik",
            Desc = "Mulai hitung dari nol",
            Callback = function()
                Stats.reset()
                notify("Statistik", "Direset", 2)
            end,
        })
    end)

    safe(function()
        StatTab:Button({
            Title = "Kirim ke Discord sekarang",
            Desc = "Perlu webhook di tab Discord",
            Callback = function()
                local ok, txt = pcall(Stats.text)
                if not (Hook.On and Hook.valid(Hook.Url)) then
                    notify("Statistik", "Aktifkan webhook Discord dulu", 3)
                elseif ok then
                    Hook.send("report", "Laporan statistik\n```\n" .. txt .. "\n```")
                    notify("Statistik", "Masuk antrian kirim", 2)
                end
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- TAS: auto recycle item sampah & auto convert lock
---------------------------------------------------------------------
-- Cara kerja (sama seperti tombol di inventori game):
--   Recycle : hapus dari inventori lalu World.call("Recycle", id, jumlah)
--   Convert : 100 World Lock -> 1 Diamond Lock, 100 Diamond Lock -> 1 Blue Gem Lock
--             lewat World.call("ConvertLock", dari, ke)
-- Tool & lock tidak bisa dipilih untuk recycle (supaya tidak terbuang tidak sengaja).
local Bag = {
    TrashOn = false,
    TrashList = {},    -- daftar id item yang di-recycle
    TrashAt = 150,     -- recycle kalau jumlahnya sudah segini
    Keep = 0,          -- sisakan sebanyak ini
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

    -- sama seperti cek tombol convert di game (muat atau tidak)
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
            Bag.Status = "Convert ke " .. step.name
        end
        return ok
    end

    function Bag.tick()
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

    -- label dropdown: item di inventori yang boleh di-recycle
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
        -- item yang sudah dipilih tetap tampil walau sedang habis
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
                local txt = ("Status: %s\nDi-recycle: %d item | Convert lock: %d kali\nItem dipilih: %d"):format(
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

Config.add("Tas", Bag, { "TrashOn", "TrashList", "TrashAt", "Keep", "LockOn" })

-- ===== TAB: TAS =====
do (function()
    local BagTab = makeTab("Tas", "backpack", "fitur")

    safe(function()
        UI.BagStatus = BagTab:Paragraph({ Title = "Status", Desc = "-" })
    end)

    local bTrash = box(BagTab, "Auto Recycle (buang item)", true)
    local bLock = box(BagTab, "Auto Convert Lock", false)

    safe(function()
        bTrash:Toggle({
            Title = "Auto Recycle",
            Desc = "Item yang dipilih di-recycle otomatis",
            Value = Bag.TrashOn,
            Callback = function(on) Bag.TrashOn = on end,
        })
    end)

    safe(function()
        local labels, picked = Bag.labels()
        UI.TrashDropdown = bTrash:Dropdown({
            Title = "Item yang di-recycle",
            Desc = "Bisa pilih banyak. Tool & lock tidak ditampilkan",
            Values = (#labels > 0) and labels or { "(inventori belum terbaca)" },
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

    -- dipanggil saat inventori berubah
    local lastSig = nil
    UI.TrashRefresh = function(force)
        local labels, picked = Bag.labels()
        local sig = table.concat(labels, "|")
        if not force and sig == lastSig then return end
        lastSig = sig
        if not UI.TrashDropdown then return end
        pcall(function() UI.TrashDropdown:Refresh((#labels > 0) and labels or { "(inventori kosong)" }) end)
        if #picked > 0 then pcall(function() UI.TrashDropdown:Select(picked) end) end
    end

    addNumber(bTrash, {
        Title = "Recycle kalau jumlah >=",
        Desc = "200 = hanya saat penuh 1 slot",
        Min = 1, Max = 200, Step = 1, Default = Bag.TrashAt,
        Callback = function(v) Bag.TrashAt = math.floor(v) end,
    })

    addNumber(bTrash, {
        Title = "Sisakan",
        Desc = "Jumlah yang tidak ikut di-recycle",
        Min = 0, Max = 199, Step = 1, Default = Bag.Keep,
        Callback = function(v) Bag.Keep = math.floor(v) end,
    })

    safe(function()
        bTrash:Button({
            Title = "Refresh daftar item",
            Callback = function() UI.TrashRefresh(true) end,
        })
    end)

    safe(function()
        bLock:Toggle({
            Title = "Auto Convert Lock",
            Desc = "100 WL -> 1 DL, 100 DL -> 1 BGL (sama seperti game)",
            Value = Bag.LockOn,
            Callback = function(on) Bag.LockOn = on end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- AUTO SPLICE
---------------------------------------------------------------------
-- Cara kerja (sama seperti splice manual di game):
--   1. Tanam Seed A di tile Grid yang kosong (di bawahnya harus ada block).
--   2. Taruh Seed B di atas pohon A -> World.spliceSeed(x, y, B).
--   3. Server membalas id pohon hasil splice, tile langsung diganti di layar.
--   Hasil splice diperkirakan dulu pakai modul Splice game; kalau tidak bisa, tidak dijalankan.
do (function()
    local okMod, SpliceMod = pcall(require, Shared:FindFirstChild("Splice"))

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
        Splice.Status = reason or "Dihentikan"
        setVisual()
        if reason then notify("Auto Splice", reason, 4) end
    end

    local function treeSpliced(x, y)
        local trees, w = Refs.Trees, Refs.World
        local t = trees and w and trees[y * w.w + x]
        return type(t) == "table" and t.s == true
    end

    local function spliceAt(x, y)
        local w = Refs.World
        local f = w and rawget(w, "spliceSeed")
        if type(f) ~= "function" then return false, "fungsi splice game tidak ketemu" end
        local ok, made = pcall(f, x, y, Splice.B)
        if ok and made and ItemDB[made] then
            pcall(function() Refs.Inv:remove(Splice.B, 1) end)
            if Refs.SetTile then pcall(Refs.SetTile, "fg", x, y, made, true) end -- ganti di layar saja
            Splice.Made += 1
            Splice.Status = ("Splice jadi %s (%d,%d)"):format(itemName(made), x, y)
            return true
        end
        return false, "ditolak server"
    end

    local function loop(runId)
        while Splice.Running and alive() and Splice.RunId == runId do
            local px, py = getPlayerTile()
            if not px then
                Splice.stop("Karakter tidak ditemukan (keluar world?)")
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
                    -- 1) tanam Seed A
                    if fg == 0 and invCount(A) > 0 and invCount(B) > 0 and Auto.plantSpotOk(x, y, A) then
                        sendSetTile("fg", x, y, A)
                        pcall(function() Refs.Inv:remove(A, 1) end)
                        Splice.Planted += 1
                        Splice.Status = ("Tanam %s (%d,%d)"):format(itemName(A), x, y)
                        acted = true
                        task.wait(Splice.Ms / 1000)
                        fg = tileAt("fg", x, y)
                    end
                    -- 2) splice Seed B ke pohon A
                    if fg == A and invCount(B) > 0 and not treeSpliced(x, y) then
                        local ok, why = spliceAt(x, y)
                        if not ok then
                            Splice.Fail[key] = os.clock() + 30
                            Splice.Status = ("Gagal splice (%d,%d): %s"):format(x, y, why)
                        end
                        acted = true
                        task.wait(Splice.Ms / 1000)
                    end
                end
            end
            if not acted then
                if invCount(A) <= 0 or invCount(B) <= 0 then
                    Splice.stop("Seed habis")
                    return
                end
                Splice.Status = "Menunggu tile Grid kosong (panen dulu pohonnya)"
                task.wait(1)
            end
        end
    end

    function Splice.start()
        if Splice.Running then return end
        local err
        if not Refs.World then
            err = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
        elseif not (Splice.A and Splice.B) then
            err = "Pilih Seed A dan Seed B dulu"
        elseif Splice.A == Splice.B then
            err = "Seed A dan Seed B harus beda"
        elseif not Splice.result(Splice.A, Splice.B) then
            err = "Kombinasi ini tidak bisa di-splice"
        elseif not Splice.Roam and next(State.Offsets) == nil then
            err = "Pilih tile dulu di Grid Tile (tab Farm), atau nyalakan Keliling world"
        elseif State.Running or Clear.Running or Farmer.Running then
            err = "Hentikan Auto Farm / Clear / Farmer dulu"
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
        if not (Splice.A and Splice.B) then return "Pilih Seed A dan Seed B" end
        local r = Splice.result(Splice.A, Splice.B)
        if not r then return "Hasil: tidak bisa di-splice" end
        return "Hasil: " .. itemName(r)
    end

    task.spawn(function()
        while alive() do
            if UI.SpliceStatus then
                local txt = ("Status: %s\n%s\nSeed A: %s (x%d) | Seed B: %s (x%d)\nDitanam: %d | Splice jadi: %d"):format(
                    Splice.Running and Splice.Status or ("BERHENTI - " .. Splice.Status), Splice.resultText(),
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
    local SpTab = makeTab("Splice", "git-merge", "farm")

    safe(function()
        UI.SpliceStatus = SpTab:Paragraph({ Title = "Status Splice", Desc = "-" })
    end)

    local sCtl = box(SpTab, "Kontrol", true)
    local sSeed = box(SpTab, "Seed", true)
    local sSpeed = box(SpTab, "Kecepatan", false)

    safe(function()
        UI.SpliceToggle = sCtl:Toggle({
            Title = "Auto Splice",
            Desc = "Tanam Seed A lalu splice Seed B",
            Value = false,
            Callback = function(on)
                if on then Splice.start() elseif Splice.Running then Splice.stop() end
            end,
        })
    end)

    local function seedLabels()
        local labels = {}
        for _, id in ipairs(seedIds()) do labels[#labels + 1] = ("%s [%d]"):format(itemName(id), id) end
        if #labels == 0 then labels = { "(tidak ada seed di inventori)" } end
        return labels
    end
    local function idOf(opt) return tonumber(string.match(tostring(opt or ""), "%[(%d+)%]$")) end

    safe(function()
        UI.SpliceA = sSeed:Dropdown({
            Title = "Seed A (ditanam)",
            Values = { "(memuat...)" },
            Callback = function(opt)
                local id = idOf(opt)
                if id then Splice.A = id end
            end,
        })
    end)

    safe(function()
        UI.SpliceB = sSeed:Dropdown({
            Title = "Seed B (di-splice)",
            Values = { "(memuat...)" },
            Callback = function(opt)
                local id = idOf(opt)
                if id then Splice.B = id end
            end,
        })
    end)

    -- dipanggil saat inventori berubah
    local lastSig = nil
    UI.SpliceRefresh = function(force)
        local labels = seedLabels()
        local sig = table.concat(labels, "|")
        if not force and sig == lastSig then return end
        lastSig = sig
        for _, pair in ipairs({ { UI.SpliceA, Splice.A }, { UI.SpliceB, Splice.B } }) do
            local dd, id = pair[1], pair[2]
            if dd then
                pcall(function() dd:Refresh(labels) end)
                if id then
                    local want = "[" .. id .. "]"
                    for _, l in ipairs(labels) do
                        if string.sub(l, -#want) == want then
                            pcall(function() dd:Select(l) end)
                            break
                        end
                    end
                end
            end
        end
    end

    safe(function()
        sSeed:Button({
            Title = "Refresh daftar seed",
            Callback = function() UI.SpliceRefresh(true) end,
        })
    end)

    safe(function()
        sCtl:Toggle({
            Title = "Keliling world (A*)",
            Desc = "Nyala: jalan ke seluruh world. Mati: hanya tile Grid 5x5",
            Value = Splice.Roam,
            Callback = function(on)
                if Splice.Running then Splice.stop("Mode diganti, nyalakan lagi") end
                Splice.Roam = on
            end,
        })
    end)

    addNumber(sSpeed, {
        Title = "Jeda tanam / splice (ms)",
        Min = 140, Max = 2000, Step = 10, Default = Splice.Ms,
        Callback = function(v) Splice.Ms = math.floor(v) end,
    })
end)() end

-- ===== TAB: LAHAN (bangun farm world) =====
do (function()
    local LTab = makeTab("Lahan", "layout-grid", "farm")

    safe(function()
        UI.LahanStatus = LTab:Paragraph({ Title = "Status Lahan", Desc = "-" })
    end)

    local lCtl = box(LTab, "Bangun Lahan", true)
    local lShape = box(LTab, "Bentuk lahan", true)
    local lOpt = box(LTab, "Pilihan", false)

    safe(function()
        UI.BuildToggle = lCtl:Toggle({
            Title = "Bangun Lahan",
            Desc = "Hitung block, produksi kalau kurang, lalu pasang dari baris bawah",
            Value = false,
            Callback = function(on)
                if on then Build.start() elseif Build.Running then Build.stop() end
            end,
        })
    end)

    safe(function()
        UI.BuildBlockDropdown = lCtl:Dropdown({
            Title = "Block lahan",
            Desc = "Block padat dari inventori",
            Values = { "(memuat...)" },
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
            Title = "X awal",
            Desc = "Kolom paling kiri",
            Value = tostring(Land.X0),
            Placeholder = "0",
            Callback = function(t) Land.X0 = math.max(0, num(t, Land.X0)) end,
        })
    end)

    safe(function()
        lShape:Input({
            Title = "X akhir",
            Desc = "Kolom paling kanan (lebih dari lebar world = sampai ujung)",
            Value = tostring(Land.X1),
            Placeholder = "99",
            Callback = function(t) Land.X1 = math.max(0, num(t, Land.X1)) end,
        })
    end)

    safe(function()
        lShape:Input({
            Title = "Y baris atas",
            Desc = "Baris block paling atas (minimal 1)",
            Value = tostring(Land.Y0),
            Placeholder = "2",
            Callback = function(t) Land.Y0 = math.max(1, num(t, Land.Y0)) end,
        })
    end)

    addNumber(lShape, {
        Title = "Jarak antar baris",
        Desc = "2 = y1, y3, y5.. | 3 = y1, y4, y7.. (maks 3 supaya bisa lompat naik)",
        Min = 2, Max = 3, Step = 1, Default = Land.Gap,
        Callback = function(v) Land.Gap = math.floor(v) end,
    })

    addNumber(lShape, {
        Title = "Jumlah baris",
        Min = 1, Max = 60, Step = 1, Default = Land.Rows,
        Callback = function(v) Land.Rows = math.floor(v) end,
    })

    safe(function()
        lShape:Toggle({
            Title = "Tangga di pojok kiri-kanan",
            Desc = "Ujung baris dibuka bergantian, jadi bisa turun-naik zig-zag",
            Value = Land.Stairs,
            Callback = function(on) Land.Stairs = on end,
        })
    end)

    safe(function()
        lShape:Button({
            Title = "Pakai posisi karakter sebagai pojok kiri-atas",
            Desc = "X awal = kolom karakter, Y baris atas = tile di bawah kaki",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Lahan", "Kamu belum masuk world", 3)
                    return
                end
                Land.X0, Land.Y0 = x, y + 1
                notify("Lahan", ("X awal %d, Y baris atas %d"):format(Land.X0, Land.Y0), 4)
            end,
        })
    end)

    safe(function()
        lOpt:Toggle({
            Title = "Produksi block kalau kurang",
            Desc = "Tanam & panen seed block itu dulu sampai cukup",
            Value = Build.Produce,
            Callback = function(on) Build.Produce = on end,
        })
    end)

    safe(function()
        lOpt:Toggle({
            Title = "Boleh taruh block pijakan",
            Desc = "Kalau baris paling bawah tidak terjangkau dari tanah",
            Value = Build.UseBlock,
            Callback = function(on)
                Build.UseBlock = on
                Auto.resetReach()
            end,
        })
    end)

    safe(function()
        lOpt:Toggle({
            Title = "Lanjut Pabrik setelah selesai",
            Value = Build.ThenPabrik,
            Callback = function(on) Build.ThenPabrik = on end,
        })
    end)

    task.spawn(function()
        while alive() do
            local txt
            if Refs.World then
                local info = Auto.landInfo(Build.BlockId)
                local rows = Auto.landRows()
                local have = Build.BlockId and invCount(Build.BlockId) or 0
                local seed = Auto.seedOfBlock(Build.BlockId)
                txt = table.concat({
                    "Status   : " .. (Build.Running and "JALAN" or "BERHENTI") .. " - " .. Build.Phase,
                    ("Bentuk   : %d baris (y %s), x %d-%d, jarak %d%s"):format(#rows,
                        (#rows > 0) and (rows[1] .. "-" .. rows[#rows]) or "-", math.min(Land.X0, Land.X1),
                        math.max(Land.X0, Land.X1), Land.Gap, Land.Stairs and ", tangga" or ""),
                    ("Block    : %s | punya %d | butuh %d%s"):format(Build.BlockId and itemName(Build.BlockId) or "-",
                        have, info.need, (info.need > have) and (" (kurang " .. (info.need - have) .. ")") or " (cukup)"),
                    ("Terpasang: %d / %d%s"):format(info.done, info.total,
                        info.blocked > 0 and (" | terhalang block lain: " .. info.blocked) or ""),
                    (info.gap > 0) and ("Celah tanam terisi block: " .. info.gap .. " (bersihkan dulu)") or "Celah tanam: bersih",
                    "Seed block: " .. (seed and (itemName(seed) .. " x" .. invCount(seed)) or "-"),
                    "Aksi     : " .. Build.Status,
                }, "\n")
            else
                txt = "Data world belum ketemu"
            end
            if UI.LahanStatus and txt ~= Build.Shown then
                Build.Shown = txt
                pcall(function() UI.LahanStatus:SetDesc(txt) end)
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: PABRIK =====
do (function()
    local PTab = makeTab("Pabrik", "factory", "farm")

    safe(function()
        UI.PabrikStatus = PTab:Paragraph({ Title = "Status Pabrik", Desc = "-" })
    end)

    local pCtl = box(PTab, "Kontrol", true)
    local pBreak = box(PTab, "Posisi & tile break", true)
    local pDrop = box(PTab, "Drop seed", true)

    safe(function()
        UI.PabrikToggle = pCtl:Toggle({
            Title = "Jalankan Pabrik",
            Desc = "Break -> tanam -> panen -> break lagi, seed lebihan di-drop",
            Value = false,
            Callback = function(on)
                if on then Pabrik.start() elseif Pabrik.Running then Pabrik.stop() end
            end,
        })
    end)

    safe(function()
        UI.PabrikSeedDropdown = pCtl:Dropdown({
            Title = "Seed pabrik",
            Desc = "Block-nya otomatis (contoh: Dirt Seed -> Dirt)",
            Values = { "(memuat...)" },
            Callback = function(opt)
                local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
                if id then Pabrik.SeedId = id end
            end,
        })
    end)

    safe(function()
        pCtl:Toggle({
            Title = "Tanam di seluruh world",
            Desc = "Mati = hanya di lahan (tab Lahan)",
            Value = Pabrik.WholeWorld,
            Callback = function(on) Pabrik.WholeWorld = on end,
        })
    end)

    safe(function()
        pBreak:Button({
            Title = "Pakai posisi sekarang untuk break",
            Desc = "Berdiri di tempat break, lalu tekan",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Pabrik", "Kamu belum masuk world", 3)
                    return
                end
                Pabrik.BreakX, Pabrik.BreakY = x, y
                notify("Pabrik", ("Posisi break (%d,%d)"):format(x, y), 3)
            end,
        })
    end)

    safe(function()
        pBreak:Button({
            Title = "Pilih tile break (Grid)",
            Desc = "Grid terbuka dalam mode Pabrik (terpisah dari tile Auto Farm)",
            Callback = function()
                if UI.setGridMode then UI.setGridMode("pabrik") end
                if UI.GridGui then UI.GridGui.Enabled = true end
            end,
        })
    end)

    addNumber(pBreak, {
        Title = "Lama 1 sesi break (detik)",
        Desc = "Setelah ini cek pohon siap dulu",
        Min = 15, Max = 300, Step = 5, Default = Pabrik.BreakSec,
        Callback = function(v) Pabrik.BreakSec = math.floor(v) end,
    })

    safe(function()
        pDrop:Toggle({
            Title = "Auto drop seed",
            Value = Pabrik.Drop,
            Callback = function(on) Pabrik.Drop = on end,
        })
    end)

    addNumber(pDrop, {
        Title = "Sisakan seed",
        Desc = "Untuk ditanam lagi",
        Min = 0, Max = 199, Step = 1, Default = Pabrik.Keep,
        Callback = function(v) Pabrik.Keep = math.floor(v) end,
    })

    addNumber(pDrop, {
        Title = "Drop kalau seed sudah",
        Desc = "Contoh 200 & sisakan 50 = drop 150",
        Min = 2, Max = 200, Step = 1, Default = Pabrik.DropAt,
        Callback = function(v) Pabrik.DropAt = math.floor(v) end,
    })

    safe(function()
        UI.DropWorldInput = pDrop:Input({
            Title = "World drop",
            Desc = "Kosong = world ini | WORLD | WORLD:ID (masuk lewat pintu ID)",
            Value = Pabrik.DropWorld,
            Placeholder = "STORAGE:1",
            Callback = function(t) Pabrik.DropWorld = tostring(t or "") end,
        })
    end)

    safe(function()
        pDrop:Button({
            Title = "Pakai posisi sekarang untuk drop",
            Desc = "Berdiri di tempat drop (boleh di world lain), lalu tekan",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Pabrik", "Kamu belum masuk world", 3)
                    return
                end
                Pabrik.DropX, Pabrik.DropY = x, y
                -- world ikut diisi, kecuali sudah pakai format WORLD:ID
                if not string.find(Pabrik.DropWorld or "", ":", 1, true) then
                    Pabrik.DropWorld = Guard.worldName()
                    if UI.DropWorldInput then pcall(function() UI.DropWorldInput:Set(Pabrik.DropWorld) end) end
                end
                notify("Pabrik", ("Posisi drop (%d,%d) di %s"):format(x, y, Pabrik.DropWorld), 4)
            end,
        })
    end)

    safe(function()
        pDrop:Button({
            Title = "Hapus posisi drop",
            Desc = "Drop di titik kedatangan (pintu) saja",
            Callback = function()
                Pabrik.DropX, Pabrik.DropY = -1, -1
                notify("Pabrik", "Posisi drop dihapus", 3)
            end,
        })
    end)

    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n += 1 end
        return n
    end

    task.spawn(function()
        while alive() do
            local seed, block = Pabrik.SeedId, Auto.blockOfSeed(Pabrik.SeedId)
            local name, door = Auto.parseDropTarget()
            local dropAt = (name ~= "" and name or "world ini") .. (door and (" pintu " .. door) or "")
                .. (Pabrik.DropX >= 0 and (" (" .. Pabrik.DropX .. "," .. Pabrik.DropY .. ")") or "")
            local txt = table.concat({
                "Status : " .. (Pabrik.Running and ("JALAN - fase " .. tostring(Pabrik.Phase or "-")) or "BERHENTI"),
                ("Seed   : %s x%d | block %s x%d"):format(seed and itemName(seed) or "-", seed and invCount(seed) or 0,
                    block and itemName(block) or "-", block and invCount(block) or 0),
                ("Break  : %s | tile %d"):format(Pabrik.BreakX >= 0 and ("(" .. Pabrik.BreakX .. "," .. Pabrik.BreakY .. ")")
                    or "belum diatur", countKeys(Pabrik.Tiles)),
                ("Drop   : %s | sisakan %d, drop saat >= %d"):format(Pabrik.Drop and dropAt or "mati", Pabrik.Keep, Pabrik.DropAt),
                ("Hasil  : panen %d | tanam %d | di-drop %d"):format(Pabrik.Harvested, Pabrik.Planted, Pabrik.Dropped),
                "Aksi   : " .. Pabrik.Status,
            }, "\n")
            if UI.PabrikStatus and txt ~= Pabrik.Shown then
                Pabrik.Shown = txt
                pcall(function() UI.PabrikStatus:SetDesc(txt) end)
            end
            -- tombol START di Grid (mode pabrik)
            if UI.GridMode == "pabrik" and UI.GridStart then
                UI.GridStart.Text = I18N.T(Pabrik.Running and "STOP PABRIK" or "START PABRIK")
                UI.GridStart.BackgroundColor3 = Pabrik.Running and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(46, 160, 90)
            end
            task.wait(1)
        end
    end)
end)() end

---------------------------------------------------------------------
-- AUTO RECONNECT
---------------------------------------------------------------------
-- Cara kerja:
--   Terlempar dari world (event WorldClosed dari server):
--     catat aktivitas -> tunggu -> masuk world yang sama lagi -> lanjut aktivitas.
--   Disconnect dari server Roblox (layar error muncul):
--     catat aktivitas ke file -> teleport ulang ke game dengan data world
--     (game otomatis masuk world itu) -> script jalan lagi -> lanjut aktivitas.
--     Supaya script jalan lagi setelah teleport: isi URL script (queue_on_teleport)
--     atau taruh script di folder autoexec executor.
local Rejoin = {
    On = false,
    World = true,       -- masuk lagi kalau terlempar dari world
    Server = true,      -- rejoin kalau disconnect dari server
    DelaySec = 5,
    ScriptUrl = "",
    Keep = false,       -- selalu kembali ke world tujuan kalau berada di luar world
    Target = "",        -- world tujuan (kosong = world terakhir)
    LastWorld = "",     -- world terakhir yang dimasuki
    Last = nil,         -- catatan aktivitas terakhir
    LastAt = 0,
    Busy = false,
    Count = 0,
    Status = "-",
}

do (function()
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")
    local GuiService = game:GetService("GuiService")
    local canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    local PENDING = "Fian/rejoin_" .. tostring(LocalPlayer.UserId) .. ".json"

    -- catat aktivitas selagi masih jalan
    task.spawn(function()
        while alive() do
            local now = os.clock()
            local wn = Guard.worldName and Guard.worldName() or ""
            if wn ~= "" and not Pabrik.Traveling then Rejoin.LastWorld = wn end
            if Guard.anyRunning and Guard.anyRunning() and Guard.Mode == "idle" then
                Rejoin.Last = Guard.snapshot()
                Rejoin.LastAt = now
            elseif now - Rejoin.LastAt > 3 and Guard.Mode == "idle" and wn ~= "" then
                -- masih di world tapi aktivitas dihentikan sendiri: jangan dilanjutkan
                Rejoin.Last = nil
            end
            task.wait(1)
        end
    end)

    local function resume(saved, reason)
        Guard.afterEnter()
        Rejoin.Count += 1
        Rejoin.Status = "Masuk lagi berhasil, lanjut aktivitas"
        notify("Auto Reconnect", reason .. ": lanjut aktivitas", 4)
        Hook.send("rejoin", reason .. " ke " .. tostring(saved.world) .. ", aktivitas dilanjutkan")
        Guard.resumeSaved(saved)
    end

    -- ===== terlempar dari world =====
    local function onWorldClosed(msg)
        if not (Rejoin.On and Rejoin.World) or Rejoin.Busy or Pabrik.Traveling then return end
        if Guard.Mode == "away" or Guard.Mode == "out" then return end -- Penjaga yang keluar
        local saved = Rejoin.Last
        if not saved or saved.world == "" or os.clock() - Rejoin.LastAt > 10 then return end
        Rejoin.Busy = true
        task.spawn(function()
            Guard.stopAll()
            local text = tostring(msg or ""):gsub("`.", "")
            Rejoin.Status = "Terlempar dari " .. saved.world .. ". Masuk lagi..."
            Hook.send("rejoin", "Terlempar dari world " .. saved.world .. (text ~= "" and (" (" .. text .. ")") or ""))
            task.wait(Rejoin.DelaySec + 1.5) -- tunggu animasi pintu selesai
            for try = 1, 3 do
                if not (alive() and Rejoin.On) then break end
                local ok, err = Guard.enterWorld(saved.world)
                if ok then
                    task.wait(1.5)
                    resume(saved, "Masuk lagi")
                    Rejoin.Busy = false
                    return
                end
                Rejoin.Status = ("Gagal masuk (%d/3): %s"):format(try, tostring(err))
                task.wait(10)
            end
            Rejoin.Status = "Gagal masuk lagi ke " .. saved.world
            notify("Auto Reconnect", Rejoin.Status, 5)
            Hook.send("rejoin", Rejoin.Status)
            Rejoin.Busy = false
        end)
    end

    local closed = WorldRemotes:FindFirstChild("WorldClosed")
    if closed and closed:IsA("RemoteEvent") then
        table.insert(Connections, closed.OnClientEvent:Connect(function(msg)
            if alive() then onWorldClosed(msg) end
        end))
    end

    -- ===== rejoin manual & selalu kembali ke world =====
    -- Cara kerja:
    --   Rejoin manual : catat aktivitas -> keluar world -> masuk lagi -> lanjut aktivitas.
    --   Selalu kembali: tiap 2 detik cek, kalau kamu di luar world (layar pilih world)
    --                   lebih lama dari jeda -> masuk ke world tujuan -> lanjut aktivitas.
    function Rejoin.targetWorld()
        local t = tostring(Rejoin.Target or ""):upper():gsub("[^A-Z0-9]", "")
        if t ~= "" then return t end
        return Rejoin.LastWorld or ""
    end

    local function enterAndResume(world, saved, reason)
        for try = 1, 3 do
            if not alive() then return false end
            local ok, err = Guard.enterWorld(world)
            if ok then
                task.wait(1.5)
                if saved and saved.world == world then
                    resume(saved, reason)
                else
                    Guard.afterEnter()
                    Rejoin.Count += 1
                    Rejoin.Status = reason .. " ke " .. world .. " berhasil"
                    Hook.send("rejoin", reason .. " ke " .. world)
                end
                return true
            end
            Rejoin.Status = ("Gagal masuk %s (%d/3): %s"):format(world, try, tostring(err))
            task.wait(8)
        end
        notify("Auto Rejoin", "Gagal masuk " .. world, 5)
        Hook.send("rejoin", "Gagal masuk " .. world)
        return false
    end

    function Rejoin.now()
        if Rejoin.Busy then
            notify("Auto Rejoin", "Sedang proses masuk world, tunggu dulu", 3)
            return
        end
        local world = Rejoin.targetWorld()
        if world == "" then
            notify("Auto Rejoin", "World tujuan belum ada. Isi 'World tujuan' atau masuk world dulu", 4)
            return
        end
        Rejoin.Busy = true
        task.spawn(function()
            local saved = nil
            if Guard.worldName() ~= "" then
                if Guard.anyRunning() then saved = Guard.snapshot() end
                Guard.stopAll()
                Rejoin.Status = "Keluar world..."
                if not Guard.leaveWorld() then
                    Rejoin.Status = "Gagal keluar world"
                    notify("Auto Rejoin", Rejoin.Status, 4)
                    Rejoin.Busy = false
                    return
                end
                task.wait(math.max(2, Rejoin.DelaySec))
            end
            if saved and saved.world ~= world then saved = nil end -- world lain: aktivitas tidak dilanjutkan
            Rejoin.Status = "Masuk ke " .. world .. "..."
            enterAndResume(world, saved, "Rejoin")
            Rejoin.Busy = false
        end)
    end

    task.spawn(function()
        local outSince = nil
        while alive() do
            task.wait(2)
            local out = Guard.worldName() == ""
            local free = Rejoin.On and Rejoin.Keep and not Rejoin.Busy and not Rejoin.Leaving and not Pabrik.Traveling
                and Guard.Mode == "idle"
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
                    Rejoin.Status = "Di luar world, masuk ke " .. world .. "..."
                    enterAndResume(world, saved, "Kembali otomatis")
                    Rejoin.Busy = false
                end
            end
        end
    end)

    -- ===== disconnect dari server =====
    local function queueScript()
        local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        local url = tostring(Rejoin.ScriptUrl or "")
        if type(q) == "function" and string.sub(url, 1, 8) == "https://" then
            pcall(q, ("loadstring(game:HttpGet(%q))()"):format(url))
            return true
        end
        return false
    end

    local function onDisconnect(msg)
        if not (Rejoin.On and Rejoin.Server) or Rejoin.Leaving then return end
        Rejoin.Leaving = true
        local saved = Rejoin.Last or (Guard.anyRunning() and Guard.snapshot()) or nil
        local world = saved and saved.world or Guard.worldName()
        if canFile and saved then
            local data = {
                world = saved.world, farm = saved.farm, clear = saved.clear, farmer = saved.farmer,
                spam = saved.spam, splice = saved.splice, pabrik = saved.pabrik, build = saved.build,
                tx = saved.tx, ty = saved.ty, at = os.time(),
            }
            pcall(function() writefile(PENDING, HttpService:JSONEncode(data)) end)
        end
        local queued = queueScript()
        Rejoin.Status = "Disconnect: rejoin..." .. (queued and "" or " (script tidak di-queue)")
        Hook.send("rejoin", "Disconnect dari server (" .. tostring(msg) .. "). Rejoin ke " .. (world ~= "" and world or "game"))
        task.spawn(function()
            task.wait(Rejoin.DelaySec)
            while alive() do
                pcall(function()
                    TeleportService:Teleport(game.PlaceId, LocalPlayer, (world ~= "") and { world = world } or nil)
                end)
                task.wait(15) -- belum pindah: coba lagi
            end
        end)
    end

    pcall(function()
        table.insert(Connections, GuiService.ErrorMessageChanged:Connect(function(msg)
            if alive() and type(msg) == "string" and msg ~= "" then onDisconnect(msg) end
        end))
    end)

    -- ===== setelah execute: lanjutkan dari catatan rejoin =====
    function Rejoin.startup(reconnectFn)
        if not canFile then return end
        local okE, has = pcall(isfile, PENDING)
        if not okE or not has then return end
        local okR, raw = pcall(readfile, PENDING)
        if type(delfile) == "function" then pcall(delfile, PENDING) end
        if not okR or type(raw) ~= "string" then return end
        local okD, saved = pcall(HttpService.JSONDecode, HttpService, raw)
        if not okD or type(saved) ~= "table" or type(saved.world) ~= "string" or saved.world == "" then return end
        if os.time() - (tonumber(saved.at) or 0) > 15 * 60 then return end -- terlalu lama
        Rejoin.Busy = true
        Rejoin.Status = "Rejoin: menunggu masuk " .. saved.world
        -- tunggu game masuk world (lewat data teleport); kalau tidak, masuk sendiri
        local t0 = os.clock()
        local tried = false
        while alive() and os.clock() - t0 < 60 do
            if Refs.World and Guard.worldName() == saved.world and Auto.here() then break end
            if not Refs.World then pcall(reconnectFn) end
            if Refs.World and not tried and os.clock() - t0 > 12 then
                tried = true
                Guard.enterWorld(saved.world)
            end
            task.wait(2)
        end
        if alive() and Guard.worldName() == saved.world then
            pcall(reconnectFn)
            task.wait(1)
            resume(saved, "Rejoin server")
        else
            Rejoin.Status = "Rejoin: gagal masuk " .. saved.world
            Hook.send("rejoin", Rejoin.Status)
        end
        Rejoin.Busy = false
    end
end)() end

Config.add("Reconnect", Rejoin, { "On", "World", "Server", "DelaySec", "ScriptUrl", "Keep", "Target" })
Config.add("Discord", Hook, { "On", "Url", "Penjaga", "Stop", "Full", "Bonus", "Rejoin", "Pabrik", "ReportMin" })

-- ===== TAB: KONEKSI =====
local ConnTab = makeTab("Koneksi", "plug", "setel")

safe(function()
    UI.RefInfo = ConnTab:Paragraph({ Title = "Referensi game", Desc = "-" })
end)

Box.ConnMain = box(ConnTab, "Koneksi", true)
Box.ConnCfg = box(ConnTab, "Config", true)
Box.ConnCalib = box(ConnTab, "Koreksi posisi", false)
Box.ConnLang = box(ConnTab, "Bahasa / Language", false)

local function reconnect(show)
    -- hentikan Clear / Farmer dulu
    if Clear.Running then stopClear("Dihentikan: hubungkan ulang ke game") end
    if Farmer.Running then stopFarmer("Dihentikan: hubungkan ulang ke game") end
    Auto.resetReach()
    findRefs()
    findDropRefs()
    Auto.findTreeRefs()
    table.clear(DropFailUntil)
    watchInventory()
    refreshInvDropdown(true)
    refreshRoles()
    if State.LiteMode then setLite(true) end
    if Misc.InfJump then hookJammer() end
    pcall(function() UI.RefInfo:SetDesc(refsText()) end)
    updateStatus()
    if show then notify(show, refsText(), 5) end
end

safe(function()
    Box.ConnMain:Button({
        Title = "Hubungkan ke game",
        Desc = "Pakai setelah pindah world",
        Callback = function()
            task.spawn(reconnect, "Koneksi")
        end,
    })
end)

safe(function()
    UI.ConfigStatus = Box.ConnCfg:Paragraph({ Title = "Status", Desc = Config.Status })
end)

safe(function()
    Box.ConnCfg:Toggle({
        Title = "Auto Save Config",
        Desc = "Simpan pengaturan otomatis, dimuat lagi saat execute",
        Value = Config.AutoSave,
        Callback = function(on)
            Config.AutoSave = on
            Config.save(true) -- simpan pilihan ini juga
        end,
    })
end)

safe(function()
    Box.ConnCfg:Button({
        Title = "Simpan config sekarang",
        Callback = function()
            local ok = Config.save(true)
            notify("Config", ok and "Tersimpan" or Config.Status, 3)
        end,
    })
end)

safe(function()
    Box.ConnCfg:Button({
        Title = "Reset config (default)",
        Desc = "Hapus file config, lalu execute ulang",
        Callback = function()
            Config.reset()
            notify("Config", Config.Status, 4)
        end,
    })
end)

safe(function()
    Box.ConnLang:Dropdown({
        Title = "Bahasa / Language",
        Desc = "Ganti bahasa, lalu execute ulang",
        Values = { "Indonesia", "English" },
        Value = I18N.Saved == "en" and "English" or "Indonesia",
        Callback = function(v)
            local lang = (v == "English") and "en" or "id"
            if lang == I18N.Saved then return end
            I18N.Saved = lang
            Config.save(true)
            notify("Bahasa / Language", "Execute ulang untuk ganti bahasa / Re-execute to apply", 5)
        end,
    })
end)

safe(function()
    Box.ConnLang:Toggle({
        Title = "Tanya bahasa saat execute",
        Desc = "Munculkan pilihan bahasa tiap execute",
        Value = I18N.Ask,
        Callback = function(on) I18N.Ask = on end,
    })
end)

safe(function()
    Box.ConnCalib:Input({
        Title = "Koreksi posisi X",
        Desc = "Isi 1 / -1 kalau tile meleset",
        Value = tostring(State.CalibX),
        Callback = function(text) State.CalibX = tonumber(text) or 0 end,
    })
end)

safe(function()
    Box.ConnCalib:Input({
        Title = "Koreksi posisi Y",
        Value = tostring(State.CalibY),
        Callback = function(text) State.CalibY = tonumber(text) or 0 end,
    })
end)

-- ===== KONEKSI: AUTO RECONNECT =====
do (function()
    local rBox = box(ConnTab, "Auto Reconnect", false)

    safe(function()
        UI.RejoinStatus = rBox:Paragraph({ Title = "Status", Desc = Rejoin.Status })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Auto Reconnect",
            Desc = "Masuk lagi & lanjut aktivitas kalau terlempar",
            Value = Rejoin.On,
            Callback = function(on) Rejoin.On = on end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Terlempar dari world",
            Desc = "World ditutup / di-kick: masuk lagi ke world yang sama",
            Value = Rejoin.World,
            Callback = function(on) Rejoin.World = on end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Selalu kembali ke world",
            Desc = "Kalau berada di luar world (layar pilih world), masuk lagi otomatis",
            Value = Rejoin.Keep,
            Callback = function(on) Rejoin.Keep = on end,
        })
    end)

    safe(function()
        rBox:Input({
            Title = "World tujuan",
            Desc = "Kosongkan = world terakhir yang kamu masuki",
            Value = Rejoin.Target,
            Placeholder = "NAMAWORLD",
            Callback = function(text) Rejoin.Target = tostring(text or "") end,
        })
    end)

    safe(function()
        rBox:Button({
            Title = "Rejoin world sekarang",
            Desc = "Keluar lalu masuk lagi, aktivitas dilanjutkan",
            Callback = function() Rejoin.now() end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Disconnect dari server",
            Desc = "Teleport ulang ke game lalu masuk world terakhir",
            Value = Rejoin.Server,
            Callback = function(on) Rejoin.Server = on end,
        })
    end)

    addNumber(rBox, {
        Title = "Jeda sebelum masuk lagi (detik)",
        Min = 2, Max = 60, Step = 1, Default = Rejoin.DelaySec,
        Callback = function(v) Rejoin.DelaySec = math.floor(v) end,
    })

    safe(function()
        rBox:Input({
            Title = "URL script (untuk rejoin server)",
            Desc = "Link raw script ini, supaya jalan lagi setelah teleport. Kosong = pakai autoexec",
            Value = Rejoin.ScriptUrl,
            Placeholder = "https://...",
            Callback = function(text)
                Rejoin.ScriptUrl = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            end,
        })
    end)
end)() end

-- ===== TAB: DISCORD =====
do (function()
    local DcTab = makeTab("Discord", "bell", "setel")

    safe(function()
        UI.HookStatus = DcTab:Paragraph({ Title = "Status", Desc = Hook.Status })
    end)

    local dMain = box(DcTab, "Webhook", true)
    local dWhat = box(DcTab, "Yang dikirim", false)

    safe(function()
        dMain:Toggle({
            Title = "Notifikasi Discord",
            Desc = "Kirim kabar penting ke channel Discord kamu",
            Value = Hook.On,
            Callback = function(on) Hook.On = on end,
        })
    end)

    safe(function()
        dMain:Input({
            Title = "URL Webhook",
            Desc = "Channel Discord > Edit > Integrasi > Webhook > Salin URL",
            Value = Hook.Url,
            Placeholder = "https://discord.com/api/webhooks/...",
            Callback = function(text)
                text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                Hook.Url = text
                if text ~= "" and not Hook.valid(text) then
                    notify("Discord", "URL webhook tidak valid", 4)
                end
            end,
        })
    end)

    safe(function()
        dMain:Button({
            Title = "Tes kirim",
            Callback = function()
                if not Hook.valid(Hook.Url) then
                    notify("Discord", "Isi URL webhook dulu", 3)
                    return
                end
                local was = Hook.On
                Hook.On = true
                Hook.send("test", "Tes notifikasi dari Fian792")
                Hook.On = was
                notify("Discord", "Pesan tes masuk antrian", 3)
            end,
        })
    end)

    addNumber(dMain, {
        Title = "Laporan statistik (menit)",
        Desc = "Kirim statistik sesi tiap X menit. 0 = mati",
        Min = 0, Max = 180, Step = 5, Default = Hook.ReportMin,
        Callback = function(v) Hook.ReportMin = math.floor(v) end,
    })

    for _, item in ipairs({
        { "Penjaga", "Mod / Dev / pemain masuk world" },
        { "Stop", "Aktivitas berhenti (block habis / error)" },
        { "Full", "Inventori penuh" },
        { "Bonus", "Quest diklaim / redeem berhasil" },
        { "Rejoin", "Terlempar / disconnect / masuk lagi" },
        { "Pabrik", "Pabrik drop seed / lahan selesai / berhenti" },
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
task.spawn(function()
    reconnect("Fian792 v1.2")
    -- Penjaga dari config dinyalakan setelah data pemain ketemu
    -- (supaya pemain yang sudah ada dicatat dulu)
    if Config.saved("Penjaga", "On") == true and alive() then
        if UI.GuardToggle then pcall(function() UI.GuardToggle:Set(true) end) end
        if not Guard.On then Guard.set(true) end
    end
    Config.start()
    -- habis rejoin server: lanjutkan aktivitas sebelumnya
    Rejoin.startup(reconnect)
end)

task.spawn(function()
    while alive() do
        if not State.Running then updateStatus() end
        Auto.updateClearStatus()
        Auto.updateFarmerStatus()
        updateSpamStatus()
        if UI.ConfigStatus and Config.Status ~= Config.Shown then
            Config.Shown = Config.Status
            pcall(function() UI.ConfigStatus:SetDesc(Config.Status) end)
        end
        local rj = ("%s\nWorld tujuan: %s\nBerhasil masuk lagi: %d kali"):format(
            Rejoin.Status, (Rejoin.targetWorld and Rejoin.targetWorld() ~= "") and Rejoin.targetWorld() or "-", Rejoin.Count)
        if UI.RejoinStatus and rj ~= Rejoin.Shown then
            Rejoin.Shown = rj
            pcall(function() UI.RejoinStatus:SetDesc(rj) end)
        end
        local hk = ("%s\nAntrian: %d pesan"):format(Hook.Status, #Hook.Queue)
        if UI.HookStatus and hk ~= Hook.Shown then
            Hook.Shown = hk
            pcall(function() UI.HookStatus:SetDesc(hk) end)
        end
        task.wait(1)
    end
end)

---------------------------------------------------------------------
-- CLEANUP (otomatis saat script dijalankan ulang)
---------------------------------------------------------------------
Session.Cleanup = function()
    State.Running = false
    Clear.Running = false
    Farmer.Running = false
    Spam.On = false
    if Config.AutoSave then pcall(Config.save, false) end -- simpan sebelum ditutup
    Guard.On = false
    Bonus.Quest, Bonus.Redeem = false, false
    Scan.Auto = false
    Splice.Running = false
    Rejoin.On = false
    Pabrik.Running = false
    Build.Running = false
    State.Override = nil
    pcall(Auto.stopWalk)
    AutoInput.active = false
    pcall(Auto.releaseInput)
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    -- kembalikan nama asli (watermark dilepas)
    Misc.CustomName = false
    pcall(nameRestore)
    -- kembalikan fungsi game ke asal
    pcall(setLite, false)
    pcall(unhookJammer)
    if OrigIsDown and MenuModOk and rawget(MenuModule, "isDown") == isDownWrapper then
        MenuModule.isDown = OrigIsDown
    end
    if Refs.World then
        if Misc.Ghost then pcall(function() Refs.World.ghost = false end) end
        if Misc.Speed ~= 100 then pcall(function() Refs.World.speedScale = 1 end) end
    end
    pcall(function() GridGui:Destroy() end)
    pcall(function() FlyPad:Destroy() end)
    pcall(function() Window:Destroy() end)
end
