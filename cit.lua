---------------------------------------------------------------------
-- AUTO DF (Dirt Farm)
-- Tempel di script Fian792, tepat di atas blok "-- INIT".
---------------------------------------------------------------------
-- Cara kerja (memakai mesin yang sudah ada, tidak membuat mesin baru):
--   1. Bangun Lahan : pasang baris block Dirt (produksi dulu kalau kurang)
--   2. Pabrik       : break dirt -> tanam Dirt Seed -> panen -> break lagi,
--                     seed lebihan di-drop
--   Satu tombol menjalankan keduanya berurutan. Pengaturan bentuk lahan,
--   posisi break & drop diisi dari tab ini (nilainya masuk ke Land / Pabrik,
--   jadi ikut tersimpan di config).
--   Penjaga & Auto Reconnect tetap bekerja karena memakai Build / Pabrik asli.
local DF = {
    Running = false,
    SeedId = nil,        -- Dirt Seed (otomatis dicari kalau ada di inventori)
    Produce = true,      -- produksi dirt kalau block kurang
    SkipBuild = false,   -- lahan sudah jadi: langsung Pabrik
    Status = "-",
    Stage = "-",
}

do (function()
    local function seedLabels()
        local out = {}
        for _, id in ipairs(seedIds()) do out[#out + 1] = ("%s [%d]"):format(itemName(id), id) end
        if #out == 0 then out = { "(tidak ada seed di inventori)" } end
        return out
    end

    -- cari Dirt Seed lewat ItemDB (nama block "Dirt")
    local function findDirtSeed()
        local ok, res = pcall(function()
            for id, it in pairs(ItemDB) do
                if type(it) == "table" and it.name == "Dirt" and it.kind ~= "seed" then
                    local sid = Auto.seedOfBlock(id)
                    if sid then return sid end
                end
            end
        end)
        return ok and res or nil
    end

    local function setToggle(v)
        if UI.DFToggle then pcall(function() UI.DFToggle:Set(v) end) end
    end

    function DF.stop(reason)
        if not DF.Running and not reason then return end
        DF.Running = false
        if Build.Running then Build.stop() end
        if Pabrik.Running then Pabrik.stop() end
        DF.Status = reason or "Dihentikan"
        DF.Stage = "-"
        setToggle(false)
        if reason then
            notify("Auto DF", reason, 5)
            if not string.find(reason, "^Dihentikan") then Hook.send("pabrik", "Auto DF: " .. reason) end
        end
    end

    function DF.start()
        if DF.Running then return end
        local seed = DF.SeedId
        local block = seed and Auto.blockOfSeed(seed)
        local err
        if not Refs.World then
            err = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
        elseif not Auto.here() then
            err = "Kamu belum masuk world"
        elseif not seed then
            err = "Pilih seed dirt dulu"
        elseif not block then
            err = "Block dari seed ini tidak ketemu"
        elseif #Auto.landRows() == 0 then
            err = "Atur lahan dulu (Y baris atas / jumlah baris)"
        elseif not DF.SkipBuild and not (ItemDB[block] and ItemDB[block].solid) then
            err = "Block dari seed ini bukan block padat"
        elseif Pabrik.BreakX < 0 or next(Pabrik.Tiles) == nil then
            err = "Atur posisi break & tile break dulu"
        end
        if err then
            notify("Auto DF", err, 4)
            setToggle(false)
            return
        end

        -- pasang ke mesin yang sudah ada
        Pabrik.SeedId = seed
        Pabrik.WholeWorld = false
        Build.BlockId = block
        Build.Produce = DF.Produce
        Build.ThenPabrik = true

        DF.Running = true
        DF.Status = "Mulai..."
        if DF.SkipBuild then Pabrik.start() else Build.start() end
        if not (Build.Running or Pabrik.Running) then
            DF.Running = false
            DF.Status = "Gagal mulai"
            setToggle(false)
            return
        end
        setToggle(true)

        local runId = (DF.RunId or 0) + 1
        DF.RunId = runId
        task.spawn(function()
            local idleSince = nil
            while alive() and DF.Running and DF.RunId == runId do
                task.wait(1)
                if Build.Running then
                    DF.Stage = "Bangun lahan: " .. tostring(Build.Phase)
                    DF.Status = Build.Status
                    idleSince = nil
                elseif Pabrik.Running then
                    DF.Stage = "Pabrik: " .. tostring(Pabrik.Phase or "-")
                    DF.Status = Pabrik.Status
                    idleSince = nil
                elseif Guard.Mode ~= "idle" then
                    DF.Stage = "Dijeda Penjaga"
                    idleSince = nil
                else
                    idleSince = idleSince or os.clock()
                    if os.clock() - idleSince > 3 then
                        DF.stop("Berhenti: " .. tostring(Pabrik.Status ~= "-" and Pabrik.Status or Build.Phase))
                        return
                    end
                end
            end
        end)
    end
end)() end

Config.add("DF", DF, { "SeedId", "Produce", "SkipBuild" })

-- ===== TAB: AUTO DF =====
do (function()
    local DTab = makeTab("Auto DF", "shovel", "farm")

    safe(function()
        UI.DFStatus = DTab:Paragraph({ Title = "Status Auto DF", Desc = "-" })
    end)

    local dCtl = box(DTab, "Kontrol", true)
    local dLand = box(DTab, "Bentuk lahan", true)
    local dBreak = box(DTab, "Posisi & tile break", true)
    local dDrop = box(DTab, "Drop seed", false)

    local function idOf(opt) return tonumber(string.match(tostring(opt or ""), "%[(%d+)%]$")) end
    local function num(text, def)
        local v = tonumber(tostring(text or ""):match("%-?%d+"))
        return v or def
    end

    -- ----- kontrol -----
    safe(function()
        UI.DFToggle = dCtl:Toggle({
            Title = "Jalankan Auto DF",
            Desc = "Bangun lahan dirt, lalu break -> tanam -> panen -> drop",
            Value = false,
            Callback = function(on)
                if on then DF.start() elseif DF.Running then DF.stop() end
            end,
        })
    end)

    safe(function()
        UI.DFSeed = dCtl:Dropdown({
            Title = "Seed dirt",
            Desc = "Block-nya otomatis (Dirt Seed -> Dirt)",
            Values = { "(memuat...)" },
            Callback = function(opt)
                local id = idOf(opt)
                if id then DF.SeedId = id end
            end,
        })
    end)

    safe(function()
        dCtl:Button({
            Title = "Refresh daftar seed",
            Callback = function() if UI.DFRefresh then UI.DFRefresh(true) end end,
        })
    end)

    safe(function()
        dCtl:Toggle({
            Title = "Produksi dirt kalau kurang",
            Desc = "Tanam & panen dulu sampai block cukup untuk lahan",
            Value = DF.Produce,
            Callback = function(on) DF.Produce = on end,
        })
    end)

    safe(function()
        dCtl:Toggle({
            Title = "Lewati bangun lahan",
            Desc = "Pakai kalau lahan sudah jadi: langsung ke Pabrik",
            Value = DF.SkipBuild,
            Callback = function(on) DF.SkipBuild = on end,
        })
    end)

    -- ----- bentuk lahan (menulis ke tabel Land) -----
    safe(function()
        dLand:Input({
            Title = "X awal",
            Desc = "Kolom paling kiri",
            Value = tostring(Land.X0),
            Placeholder = "0",
            Callback = function(t) Land.X0 = math.max(0, num(t, Land.X0)) end,
        })
    end)

    safe(function()
        dLand:Input({
            Title = "X akhir",
            Desc = "Kolom paling kanan",
            Value = tostring(Land.X1),
            Placeholder = "99",
            Callback = function(t) Land.X1 = math.max(0, num(t, Land.X1)) end,
        })
    end)

    safe(function()
        dLand:Input({
            Title = "Y baris atas",
            Desc = "Baris block paling atas (minimal 1)",
            Value = tostring(Land.Y0),
            Placeholder = "2",
            Callback = function(t) Land.Y0 = math.max(1, num(t, Land.Y0)) end,
        })
    end)

    addNumber(dLand, {
        Title = "Jarak antar baris",
        Desc = "2 atau 3 (maks 3 supaya bisa lompat naik)",
        Min = 2, Max = 3, Step = 1, Default = Land.Gap,
        Callback = function(v) Land.Gap = math.floor(v) end,
    })

    addNumber(dLand, {
        Title = "Jumlah baris",
        Min = 1, Max = 60, Step = 1, Default = Land.Rows,
        Callback = function(v) Land.Rows = math.floor(v) end,
    })

    safe(function()
        dLand:Toggle({
            Title = "Tangga di pojok kiri-kanan",
            Value = Land.Stairs,
            Callback = function(on) Land.Stairs = on end,
        })
    end)

    safe(function()
        dLand:Button({
            Title = "Pakai posisi karakter sebagai pojok kiri-atas",
            Desc = "X awal = kolom karakter, Y baris atas = tile di bawah kaki",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Auto DF", "Kamu belum masuk world", 3)
                    return
                end
                Land.X0, Land.Y0 = x, y + 1
                notify("Auto DF", ("X awal %d, Y baris atas %d"):format(Land.X0, Land.Y0), 4)
            end,
        })
    end)

    -- ----- posisi & tile break (menulis ke tabel Pabrik) -----
    safe(function()
        dBreak:Button({
            Title = "Pakai posisi sekarang untuk break",
            Desc = "Berdiri di tempat break, lalu tekan",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Auto DF", "Kamu belum masuk world", 3)
                    return
                end
                Pabrik.BreakX, Pabrik.BreakY = x, y
                notify("Auto DF", ("Posisi break (%d,%d)"):format(x, y), 3)
            end,
        })
    end)

    safe(function()
        dBreak:Button({
            Title = "Pilih tile break (Grid)",
            Desc = "Grid terbuka dalam mode Pabrik",
            Callback = function()
                if UI.setGridMode then UI.setGridMode("pabrik") end
                if UI.GridGui then UI.GridGui.Enabled = true end
            end,
        })
    end)

    addNumber(dBreak, {
        Title = "Lama 1 sesi break (detik)",
        Min = 15, Max = 300, Step = 5, Default = Pabrik.BreakSec,
        Callback = function(v) Pabrik.BreakSec = math.floor(v) end,
    })

    -- ----- drop seed -----
    safe(function()
        dDrop:Toggle({
            Title = "Auto drop seed",
            Value = Pabrik.Drop,
            Callback = function(on) Pabrik.Drop = on end,
        })
    end)

    addNumber(dDrop, {
        Title = "Sisakan seed",
        Desc = "Untuk ditanam lagi",
        Min = 0, Max = 199, Step = 1, Default = Pabrik.Keep,
        Callback = function(v) Pabrik.Keep = math.floor(v) end,
    })

    addNumber(dDrop, {
        Title = "Drop kalau seed sudah",
        Min = 2, Max = 200, Step = 1, Default = Pabrik.DropAt,
        Callback = function(v) Pabrik.DropAt = math.floor(v) end,
    })

    safe(function()
        dDrop:Input({
            Title = "World drop",
            Desc = "Kosong = world ini | WORLD | WORLD:ID",
            Value = Pabrik.DropWorld,
            Placeholder = "STORAGE:1",
            Callback = function(t) Pabrik.DropWorld = tostring(t or "") end,
        })
    end)

    safe(function()
        dDrop:Button({
            Title = "Pakai posisi sekarang untuk drop",
            Desc = "Berdiri di tempat drop, lalu tekan",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Auto DF", "Kamu belum masuk world", 3)
                    return
                end
                Pabrik.DropX, Pabrik.DropY = x, y
                if not string.find(Pabrik.DropWorld or "", ":", 1, true) then
                    Pabrik.DropWorld = Guard.worldName()
                end
                notify("Auto DF", ("Posisi drop (%d,%d) di %s"):format(x, y, Pabrik.DropWorld), 4)
            end,
        })
    end)

    -- ----- refresh dropdown seed + auto pilih Dirt Seed -----
    local lastSig = nil
    UI.DFRefresh = function(force)
        local labels = seedLabels()
        local sig = table.concat(labels, "|")
        if not force and sig == lastSig then return end
        lastSig = sig
        if not UI.DFSeed then return end
        pcall(function() UI.DFSeed:Refresh(labels) end)
        if not DF.SeedId then
            -- pilih Dirt Seed otomatis kalau ada di inventori
            for _, id in ipairs(seedIds()) do
                local b = Auto.blockOfSeed(id)
                if b and ItemDB[b] and ItemDB[b].name == "Dirt" then
                    DF.SeedId = id
                    break
                end
            end
        end
        if DF.SeedId then
            local want = "[" .. DF.SeedId .. "]"
            for _, l in ipairs(labels) do
                if string.sub(l, -#want) == want then
                    pcall(function() UI.DFSeed:Select(l) end)
                    break
                end
            end
        end
    end

    task.spawn(function()
        task.wait(2)
        while alive() do
            pcall(UI.DFRefresh, false)
            task.wait(3)
        end
    end)

    -- ----- status -----
    task.spawn(function()
        while alive() do
            local txt
            if Refs.World then
                local seed = DF.SeedId
                local block = seed and Auto.blockOfSeed(seed)
                local info = Auto.landInfo(block)
                local rows = Auto.landRows()
                txt = table.concat({
                    "Status : " .. (DF.Running and "JALAN" or "BERHENTI") .. " - " .. DF.Stage,
                    ("Seed   : %s x%d | block %s x%d"):format(seed and itemName(seed) or "-", seed and invCount(seed) or 0,
                        block and itemName(block) or "-", block and invCount(block) or 0),
                    ("Lahan  : %d baris, terpasang %d / %d, butuh %d"):format(#rows, info.done, info.total, info.need),
                    ("Break  : %s | tile %d"):format(Pabrik.BreakX >= 0 and ("(" .. Pabrik.BreakX .. "," .. Pabrik.BreakY .. ")")
                        or "belum diatur", (function() local n = 0 for _ in pairs(Pabrik.Tiles) do n += 1 end return n end)()),
                    ("Hasil  : panen %d | tanam %d | di-drop %d"):format(Pabrik.Harvested, Pabrik.Planted, Pabrik.Dropped),
                    "Aksi   : " .. tostring(DF.Status),
                }, "\n")
            else
                txt = "Data world belum ketemu"
            end
            if UI.DFStatus and txt ~= DF.Shown then
                DF.Shown = txt
                pcall(function() UI.DFStatus:SetDesc(txt) end)
            end
            task.wait(1)
        end
    end)
end)() end
