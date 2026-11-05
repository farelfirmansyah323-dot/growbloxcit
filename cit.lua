--[[
    PEEX HUB | GrowBlox  -  GUI REDESIGN (drop-in)

    CARA PASANG (2 blok, sisanya TIDAK diubah):

    BLOK 1  -> hapus dari baris   local C = {
               sampai fungsi      local function ClearPage(page) ... end
               (tepat sebelum komentar "-- Halaman: Fitur"), lalu tempel BLOK 1 di bawah.

    BLOK 2  -> hapus dari komentar "-- Jendela utama"
               sampai akhir fungsi BuildLauncher()
               (tepat sebelum "-- PERINTAH TAMBAHAN"), lalu tempel BLOK 2 di bawah.

    Semua nama fungsi/variabel tetap sama (AddCard, AddSwitchCard, AddInputCard,
    MakeButton, hub.*, dst.) sehingga builder halaman lama tetap kompatibel.
]]

----------------------------------------------------------------------
-- ===================== BLOK 1 : TEMA + KOMPONEN =====================
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
    local existing = PlayerGui:FindFirstChild("PeexHubGB")
    if existing and existing:IsA("ScreenGui") then
        rootGui = existing
        return rootGui
    end
    rootGui = Instance.new("ScreenGui")
    rootGui.Name = "PeexHubGB"
    rootGui.ResetOnSpawn = false
    rootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    rootGui.DisplayOrder = 999
    rootGui.Parent = PlayerGui
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

----------------------------------------------------------------------
-- ===================== BLOK 2 : JENDELA UTAMA ========================
----------------------------------------------------------------------
-- Jendela utama ------------------------------------------------------
local TAB_ORDER = {
    { id = "features", label = "Fitur", icon = "Ft" },
    { id = "farm", label = "Auto Farm", icon = "Fm" },
    { id = "clear", label = "Auto Clear", icon = "Cl" },
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
        Visible = Config.launcher,
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
