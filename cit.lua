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
                Hook.send("test", "Tes notifikasi dari n4th")
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
        { "Finder", "World Finder: hasil hunting world" },
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
for field, title in pairs({ InvDropdown = "Farm", SeedDropdown = "Farmer", PabrikSeedDropdown = "Pabrik",
    ClearBlockDropdown = "Clear World", FarmerBlockDropdown = "Farmer", BuildBlockDropdown = "Lahan" }) do
    if UI[field] then UI.DropdownTabs[UI[field]] = title end
end
-- Thread pekerjaan UI: dibuat di sini (sama seperti thread status yang terbukti bisa mengubah UI).
-- Callback tombol / event game di sebagian executor tidak punya izin mengubah dropdown.
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
    reconnect("n4th v5.2")
    -- Input dapat tersambung belakangan pada executor yang mulai sebelum client game selesai.
    if not Refs.Punch then
        task.spawn(function()
            for attempt = 1, 5 do
                task.wait(2)
                if not alive() or Refs.Punch then return end
                pcall(Anim.quickRefs)
                if attempt == 3 and not Refs.Punch then pcall(findRefs) end
                if Refs.Inv then pcall(watchInventory) end
                pcall(function() UI.RefInfo:SetDesc(refsText()) end)
                if Refs.Punch then
                    print("[n4th] Fungsi pukul ditemukan setelah input game siap.")
                    return
                end
            end
            if alive() and not Refs.Punch then
                warn("[n4th] Pukul belum ditemukan setelah mencoba GC dan koneksi input. Jalankan n4th-diagnose.lua untuk laporan API executor.")
            end
        end)
    end
    -- Penjaga dari config dinyalakan setelah data pemain ketemu
    -- (supaya pemain yang sudah ada dicatat dulu)
    if Config.saved("Penjaga", "On") == true and alive() then
        if UI.GuardToggle then pcall(function() UI.GuardToggle:Set(true) end) end
        if not Guard.On then Guard.set(true) end
    end
    Config.start()
    if I18N.SavePending then
        I18N.SavePending = nil
        Config.save(true)
    end
    -- Finder mendapat prioritas supaya catatan rejoin farming tidak memindahkan world lagi.
    if not WorldFinder.startup(reconnect) then Rejoin.startup(reconnect) end
end)

task.spawn(function()
    while alive() do
        if not State.Running then updateStatus() end
        Auto.updateClearStatus()
