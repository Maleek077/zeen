--[[
  FLUFFY HUB v1.2 - versi Delta Executor (Android)

  Cara pakai:
    1. (Opsional) tambahkan di baris paling atas:
         getgenv().script_key = "FLUFFY-ABCD-1234"
    2. Tempel seluruh isi file ke kolom Script Delta, lalu tekan Execute.

  Loader satu baris (jika file di-host di GitHub / Pastebin):
         loadstring(game:HttpGet("URL_RAW_SCRIPT_SAYA"))()

  Catatan: file ini 100% ASCII, aman untuk copy-paste dari HP.
  Semua aksi game (place/break/dll) adalah PLACEHOLDER: isi bagian GameConfig.
]]

-- ============================================================
-- [0] KONFIGURASI AWAL
-- ============================================================
local script_key = "FLUFFY-DEMO-0000" -- key contoh (format: FLUFFY-XXXX-XXXX)
local REQUIRE_KEY = false             -- true = script berhenti jika key tidak valid
local KEY_API_URL = ""                -- opsional: server cek key milikmu (balasan JSON {"valid":true})
local USE_EMOJI = true                -- false jika emoji tampil sebagai kotak
local VERSION = "1.2"

-- ============================================================
-- [1] SERVICE, ENV, ANTI EKSEKUSI GANDA
-- ============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = nil
pcall(function() CoreGui = game:GetService("CoreGui") end)
local LocalPlayer = Players.LocalPlayer

-- getgenv aman (fallback ke _G)
local ENV = _G
do
    local ok, e = pcall(function() return getgenv() end)
    if ok and type(e) == "table" then ENV = e end
end

-- Jika sudah jalan, tutup yang lama dulu
if ENV.FluffyHubLoaded and type(ENV.FluffyHubUnload) == "function" then
    pcall(ENV.FluffyHubUnload)
end
ENV.FluffyHubLoaded = true
if type(ENV.script_key) == "string" and ENV.script_key ~= "" then
    script_key = ENV.script_key
end

-- Karakter khusus dibuat lewat utf8.char supaya kode tetap ASCII
local function Ch(code, fallback)
    if not USE_EMOJI then return fallback end
    local ok, s = pcall(utf8.char, code)
    if ok and s then return s end
    return fallback
end
local ICON = {
    Hub = Ch(0x1F338, "FH"), Home = Ch(0x1F3E0, "H"), Clear = Ch(0x1F9F9, "C"),
    Dirt = Ch(0x1F331, "D"), PNB = Ch(0x1F528, "P"), Farm = Ch(0x1F33E, "F"),
    Hook = Ch(0x1F514, "W"), Util = Ch(0x1F527, "U"),
}

-- Maid: kumpulan koneksi/instance yang dibersihkan saat GUI ditutup
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ t = {} }, Maid) end
function Maid:Add(x) table.insert(self.t, x) return x end
function Maid:Clean()
    for _, x in ipairs(self.t) do
        pcall(function()
            local ty = typeof(x)
            if ty == "RBXScriptConnection" then x:Disconnect()
            elseif ty == "Instance" then x:Destroy()
            elseif ty == "function" then x() end
        end)
    end
    self.t = {}
end

local function Notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = dur or 4 })
    end)
end

local function Fire(cb, ...)
    if not cb then return end
    task.spawn(function(...)
        local ok, e = pcall(cb, ...)
        if not ok then warn("[Fluffy Hub] " .. tostring(e)) end
    end, ...)
end

local function HttpRequest(opts)
    local req = nil
    if typeof(request) == "function" then req = request
    elseif typeof(http_request) == "function" then req = http_request
    elseif typeof(syn) == "table" and typeof(syn.request) == "function" then req = syn.request end
    if not req then return nil, "Executor tidak mendukung request" end
    local ok, res = pcall(req, opts)
    if not ok then return nil, tostring(res) end
    return res
end

local function ExecutorName()
    if typeof(identifyexecutor) == "function" then
        local ok, n = pcall(identifyexecutor)
        if ok and n then return tostring(n) end
    end
    return "Tidak diketahui"
end

-- ============================================================
-- [2] VALIDASI KEY (CONTOH SEDERHANA)
-- ============================================================
local function ValidateKey(key)
    if type(key) ~= "string" or key == "" then return false, "Key kosong" end
    if not key:match("^FLUFFY%-%w%w%w%w%-%w%w%w%w$") then return false, "Format key salah" end
    if KEY_API_URL ~= "" then
        local res, err = HttpRequest({
            Url = KEY_API_URL .. "?key=" .. HttpService:UrlEncode(key) .. "&uid=" .. tostring(LocalPlayer.UserId),
            Method = "GET",
        })
        if not res then return false, "Server key: " .. tostring(err) end
        local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
        if ok and type(data) == "table" and data.valid == true then return true, "Key valid (server)" end
        return false, "Key ditolak server"
    end
    return true, "Key valid (cek lokal)"
end

local keyOk, keyMsg = ValidateKey(script_key)
if not keyOk then
    warn("[Fluffy Hub] " .. keyMsg)
    Notify("Fluffy Hub", keyMsg, 5)
    if REQUIRE_KEY then
        ENV.FluffyHubLoaded = false
        return
    end
end

-- ============================================================
-- [3] SIMPAN CONFIG (writefile / readfile + fallback)
-- ============================================================
local Config = { File = "FluffyHub_config.json", AutoSave = true }
function Config.Supported()
    return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end
function Config.Load()
    local data = {}
    if not Config.Supported() then return data end
    pcall(function()
        if isfile(Config.File) then
            local d = HttpService:JSONDecode(readfile(Config.File))
            if type(d) == "table" then data = d end
        end
    end)
    return data
end
function Config.Save(flags)
    if not Config.Supported() then return false end
    return (pcall(function() writefile(Config.File, HttpService:JSONEncode(flags)) end))
end

-- ============================================================
-- [4] LIBRARY UI MODULAR
--     CreateWindow > CreateTab > CreateSection > Create{Toggle,
--     Dropdown,Button,Label,Input,Slider,KeyValue}
-- ============================================================
local Library = { Flags = Config.Load(), Maid = Maid.new(), Destroyed = false }
Config.AutoSave = Library.Flags.autosave ~= false

local TH = {
    Bg = Color3.fromRGB(249, 213, 221),      -- #F9D5DD
    Panel = Color3.fromRGB(242, 184, 198),   -- #F2B8C6
    Row = Color3.fromRGB(252, 230, 236),
    Active = Color3.fromRGB(228, 140, 165),  -- pill tab aktif
    Accent = Color3.fromRGB(181, 52, 90),    -- #B5345A
    Text = Color3.fromRGB(90, 42, 58),       -- #5A2A3A
    Border = Color3.fromRGB(201, 114, 140),
    Off = Color3.fromRGB(227, 163, 179),
    Gold = Color3.fromRGB(255, 213, 74),
    White = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamMedium,
    FontB = Enum.Font.GothamBold,
}
pcall(function() TH.Font = Enum.Font.Nunito end)

local ROW_H = 40 -- tinggi minimum elemen (ramah sentuhan)

local function New(class, props, kids)
    local i = Instance.new(class)
    local parent = nil
    if props then
        for k, v in pairs(props) do
            if k == "Parent" then parent = v else i[k] = v end
        end
    end
    if kids then for _, c in ipairs(kids) do c.Parent = i end end
    if parent then i.Parent = parent end
    return i
end
local function Corner(r) return New("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function Stroke(c, t)
    return New("UIStroke", { Color = c, Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function Pad(l, t, r, b)
    return New("UIPadding", {
        PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t),
        PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b),
    })
end
local function Tween(inst, props, t)
    pcall(function()
        TweenService:Create(inst, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad), props):Play()
    end)
end
local function IsPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function IsMove(i)
    return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end
local function OnClick(btn, fn)
    Library.Maid:Add(btn.Activated:Connect(fn))
end
local function Viewport()
    local cam = workspace.CurrentCamera
    if cam then return cam.ViewportSize end
    return Vector2.new(800, 450)
end

local saveQueued = false
local function QueueSave()
    if not Config.AutoSave or saveQueued then return end
    saveQueued = true
    task.delay(1.5, function()
        saveQueued = false
        if not Library.Destroyed then Config.Save(Library.Flags) end
    end)
end

-- Parent GUI bertingkat: gethui -> CoreGui -> PlayerGui
local function Mount(gui)
    local getters = {}
    if typeof(gethui) == "function" then
        table.insert(getters, function() return gethui() end)
    end
    table.insert(getters, function() return CoreGui end)
    table.insert(getters, function() return LocalPlayer:WaitForChild("PlayerGui", 10) end)
    for _, get in ipairs(getters) do
        local ok, parent = pcall(get)
        if ok and typeof(parent) == "Instance" then
            pcall(function()
                local old = parent:FindFirstChild(gui.Name)
                if old then old:Destroy() end
                gui.Parent = parent
            end)
            if gui.Parent == parent then return true end
        end
    end
    return false
end

-- Drag lewat mouse atau sentuhan; onTap dipanggil jika hanya diketuk
local function MakeDraggable(handle, target, onTap)
    local dragging, startInput, startPos, startTarget, moved = false, nil, nil, nil, false
    Library.Maid:Add(handle.InputBegan:Connect(function(input)
        if IsPress(input) and not dragging then
            dragging, moved = true, false
            startInput, startPos, startTarget = input, input.Position, target.Position
        end
    end))
    Library.Maid:Add(UIS.InputChanged:Connect(function(input)
        if dragging and IsMove(input) then
            local d = input.Position - startPos
            if d.Magnitude > 8 then moved = true end
            if moved then
                local vp, sz = Viewport(), target.AbsoluteSize
                local x = math.clamp(startTarget.X.Offset + d.X, 0, math.max(0, vp.X - sz.X))
                local y = math.clamp(startTarget.Y.Offset + d.Y, 0, math.max(0, vp.Y - sz.Y))
                target.Position = UDim2.fromOffset(x, y)
            end
        end
    end))
    Library.Maid:Add(UIS.InputEnded:Connect(function(input)
        if dragging and input == startInput then
            dragging = false
            if not moved and onTap then onTap() end
        end
    end))
end

function Library:CreateWindow(o)
    o = o or {}
    local HEADER, TABBAR = 46, 46
    local Window = { Tabs = {}, ActiveTab = nil, Minimized = false, Narrow = false }

    local gui = New("ScreenGui", {
        Name = "FluffyHub", ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    })
    if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then pcall(syn.protect_gui, gui) end
    if not Mount(gui) then error("Gagal memasang GUI (gethui/CoreGui/PlayerGui)") end
    Library.Maid:Add(gui)
    Window.Gui = gui

    local main = New("Frame", {
        Name = "Main", BackgroundColor3 = TH.Bg, BorderSizePixel = 0, ClipsDescendants = true, Parent = gui,
    }, { Corner(14), Stroke(TH.Border, 1.5) })
    Window.Main = main

    -- Header
    local header = New("Frame", { Size = UDim2.new(1, 0, 0, HEADER), BackgroundTransparency = 1, Parent = main })
    local iconBox = New("Frame", {
        Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = TH.Panel, Parent = header,
    }, { Corner(10), Stroke(TH.Border, 1) })
    New("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = ICON.Hub,
        TextSize = 18, Font = TH.Font, TextColor3 = TH.Text, Parent = iconBox,
    })
    New("TextLabel", {
        Position = UDim2.fromOffset(50, 4), Size = UDim2.fromOffset(120, 20), BackgroundTransparency = 1,
        Text = o.Title or "Fluffy Hub", TextSize = 16, Font = TH.FontB, TextColor3 = TH.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
    })
    local subtitle = New("TextLabel", {
        Position = UDim2.fromOffset(50, 24), Size = UDim2.fromOffset(120, 16), BackgroundTransparency = 1,
        Text = "", TextSize = 12, Font = TH.Font, TextColor3 = TH.Accent,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = header,
    })
    local collapseBtn = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(40, 40),
        BackgroundColor3 = TH.Panel, AutoButtonColor = false, Text = "<<", TextSize = 16, Font = TH.FontB,
        TextColor3 = TH.Text, Rotation = 90, Parent = header,
    }, { Corner(10), Stroke(TH.Border, 1) })
    if o.Badge then
        local badge = New("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), Size = UDim2.fromOffset(66, 22),
            BackgroundColor3 = Color3.fromRGB(15, 15, 15), Parent = header,
        }, { Corner(11) })
        New("TextLabel", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = o.Badge, TextSize = 12,
            Font = TH.FontB, TextColor3 = TH.Gold, Parent = badge,
        })
    end

    -- Tab bar (scroll horizontal)
    local tabbar = New("ScrollingFrame", {
        Position = UDim2.fromOffset(10, HEADER), Size = UDim2.new(1, -20, 0, TABBAR), BackgroundColor3 = TH.Panel,
        BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X, Parent = main,
    }, { Corner(12), Stroke(TH.Border, 1), Pad(4, 0, 4, 0) })
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabbar,
    })

    local pages = New("Frame", {
        Position = UDim2.fromOffset(10, HEADER + TABBAR + 8),
        Size = UDim2.new(1, -20, 1, -(HEADER + TABBAR + 16)),
        BackgroundTransparency = 1, ClipsDescendants = true, Parent = main,
    })

    -- Responsif
    local placed = false
    local function layout()
        local vp = Viewport()
        local w = math.clamp(math.floor(vp.X * 0.94), 280, 600)
        local h = math.clamp(math.floor(vp.Y * 0.84), 220, 400)
        local curW = Window.Minimized and math.min(w, 300) or w
        local curH = Window.Minimized and HEADER or h
        main.Size = UDim2.fromOffset(curW, curH)
        local px, py
        if not placed then
            placed = true
            px, py = (vp.X - curW) / 2, (vp.Y - curH) / 2
        else
            px, py = main.Position.X.Offset, main.Position.Y.Offset
        end
        main.Position = UDim2.fromOffset(
            math.clamp(px, 0, math.max(0, vp.X - curW)),
            math.clamp(py, 0, math.max(0, vp.Y - curH)))
        local narrow = w < 460
        if narrow ~= Window.Narrow then
            Window.Narrow = narrow
            for _, t in ipairs(Window.Tabs) do t:ApplyNarrow(narrow) end
        end
    end
    layout()
    Window.Narrow = (math.clamp(math.floor(Viewport().X * 0.94), 280, 600) < 460)
    if workspace.CurrentCamera then
        Library.Maid:Add(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
    end

    MakeDraggable(header, main)

    function Window:SetMinimized(v)
        self.Minimized = v and true or false
        tabbar.Visible = not self.Minimized
        pages.Visible = not self.Minimized
        collapseBtn.Rotation = self.Minimized and -90 or 90
        layout()
    end
    OnClick(collapseBtn, function() Window:SetMinimized(not Window.Minimized) end)

    function Window:SetVisible(v) main.Visible = v and true or false end
    function Window:IsVisible() return main.Visible end

    -- Tombol kecil mengambang untuk buka/tutup UI
    local fab = New("TextButton", {
        Name = "Fab", Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(12, 110),
        BackgroundColor3 = TH.Accent, AutoButtonColor = false, Text = ICON.Hub, TextSize = 22,
        Font = TH.FontB, TextColor3 = TH.White, ZIndex = 10, Parent = gui,
    }, { Corner(23), Stroke(TH.Border, 2) })
    MakeDraggable(fab, fab, function() Window:SetVisible(not main.Visible) end)

    function Window:SelectTab(tab)
        for _, t in ipairs(self.Tabs) do
            local on = (t == tab)
            t.Page.Visible = on
            Tween(t.Button, { BackgroundTransparency = on and 0 or 1 }, 0.12)
        end
        self.ActiveTab = tab
        subtitle.Text = tab.Name
    end

    -- ---------------- TAB ----------------
    function Window:CreateTab(name, icon)
        local Tab = { Name = name }
        local btn = New("TextButton", {
            Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = TH.Active,
            BackgroundTransparency = 1, AutoButtonColor = false, Text = (icon or "") .. " " .. name,
            TextSize = 14, Font = TH.FontB, TextColor3 = TH.Text, LayoutOrder = #Window.Tabs + 1, Parent = tabbar,
        }, { Corner(19), Pad(12, 0, 12, 0) })
        Tab.Button = btn

        local page = New("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
            ScrollBarImageColor3 = TH.Accent, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, Parent = pages,
        })
        Tab.Page = page
        local cols = New("Frame", {
            Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = page,
        })
        local colsLayout = New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder, Parent = cols,
        })
        local function Col(order)
            local f = New("Frame", {
                Size = UDim2.new(0.5, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, LayoutOrder = order, Parent = cols,
            })
            New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
            return f
        end
        local Left, Right = Col(1), Col(2)
        local secOrder = 0

        function Tab:ApplyNarrow(n)
            colsLayout.FillDirection = n and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
            local sz = n and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -4, 0, 0)
            Left.Size = sz
            Right.Size = sz
        end

        OnClick(btn, function() Window:SelectTab(Tab) end)

        -- ---------------- SECTION (collapsible) ----------------
        function Tab:CreateSection(title, side, startCollapsed)
            local col = (side == "Right") and Right or Left
            local Section = {}
            local collapsed = startCollapsed and true or false
            secOrder = secOrder + 1

            local frame = New("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = TH.Panel,
                BorderSizePixel = 0, LayoutOrder = secOrder, Parent = col,
            }, { Corner(12), Stroke(TH.Border, 1) })
            New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
            local head = New("TextButton", {
                Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1, Text = "",
                AutoButtonColor = false, LayoutOrder = 0, Parent = frame,
            })
            New("TextLabel", {
                Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -44, 1, 0), BackgroundTransparency = 1,
                Text = title, TextSize = 15, Font = TH.FontB, TextColor3 = TH.Text,
                TextXAlignment = Enum.TextXAlignment.Left, Parent = head,
            })
            local arrow = New("TextLabel", {
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(20, 20),
                BackgroundTransparency = 1, Text = collapsed and ">" or "v", TextSize = 14, Font = TH.FontB,
                TextColor3 = TH.Accent, Parent = head,
            })
            local content = New("Frame", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                Visible = not collapsed, LayoutOrder = 1, Parent = frame,
            }, { Pad(8, 0, 8, 8) })
            New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
            OnClick(head, function()
                collapsed = not collapsed
                content.Visible = not collapsed
                arrow.Text = collapsed and ">" or "v"
            end)

            local order = 0
            local function NextOrder() order = order + 1 return order end
            local function Row(h)
                return New("Frame", {
                    Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = TH.Row, BorderSizePixel = 0,
                    LayoutOrder = NextOrder(), Parent = content,
                }, { Corner(10) })
            end
            local function RowText(parent, text, pos, size, align)
                return New("TextLabel", {
                    Position = pos, Size = size, BackgroundTransparency = 1, Text = text, TextSize = 13,
                    Font = TH.Font, TextColor3 = TH.Text, TextXAlignment = align or Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent,
                })
            end
            local function Persist(opt, v)
                if opt.Flag and opt.Persist ~= false then
                    Library.Flags[opt.Flag] = v
                    QueueSave()
                end
            end
            local function Saved(opt, default)
                if opt.Flag and opt.Persist ~= false and Library.Flags[opt.Flag] ~= nil then
                    return Library.Flags[opt.Flag]
                end
                return default
            end

            -- Toggle
            function Section:CreateToggle(opt)
                opt = opt or {}
                local value = (Saved(opt, opt.Default or false) == true)
                local row = Row(ROW_H)
                RowText(row, opt.Name or "Toggle", UDim2.fromOffset(12, 0), UDim2.new(1, -78, 1, 0))
                local track = New("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(48, 26),
                    BackgroundColor3 = TH.Off, Parent = row,
                }, { Corner(13) })
                local knob = New("Frame", {
                    Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = TH.White, Parent = track,
                }, { Corner(10) })
                local hit = New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = row })
                local Toggle = {}
                local function render()
                    Tween(track, { BackgroundColor3 = value and TH.Accent or TH.Off })
                    Tween(knob, { Position = UDim2.fromOffset(value and 25 or 3, 3) })
                end
                render()
                function Toggle:Get() return value end
                function Toggle:Set(v, silent)
                    value = v and true or false
                    render()
                    Persist(opt, value)
                    if not silent then Fire(opt.Callback, value) end
                end
                OnClick(hit, function() Toggle:Set(not value) end)
                if value then Fire(opt.Callback, value) end
                return Toggle
            end

            -- Dropdown
            function Section:CreateDropdown(opt)
                opt = opt or {}
                local options = opt.Options or {}
                local value = Saved(opt, opt.Default or options[1])
                if not table.find(options, value) then value = opt.Default or options[1] end
                local holder = New("Frame", {
                    Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                    LayoutOrder = NextOrder(), Parent = content,
                })
                New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
                local row = New("Frame", {
                    Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = TH.Row, BorderSizePixel = 0,
                    LayoutOrder = 0, Parent = holder,
                }, { Corner(10) })
                RowText(row, opt.Name or "Dropdown", UDim2.fromOffset(12, 3), UDim2.new(1, -24, 0, 18))
                local vbtn = New("TextButton", {
                    Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 34), BackgroundColor3 = TH.Panel,
                    AutoButtonColor = false, Text = "", Parent = row,
                }, { Corner(8), Stroke(TH.Border, 1) })
                local vlabel = New("TextLabel", {
                    Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -34, 1, 0), BackgroundTransparency = 1,
                    Text = tostring(value), TextSize = 13, Font = TH.Font, TextColor3 = TH.Text,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = vbtn,
                })
                New("TextLabel", {
                    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(18, 18),
                    BackgroundTransparency = 1, Text = "v", TextSize = 13, Font = TH.FontB, TextColor3 = TH.Accent, Parent = vbtn,
                })
                local list = New("ScrollingFrame", {
                    Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = TH.Row, BorderSizePixel = 0, Visible = false,
                    ScrollBarThickness = 3, ScrollBarImageColor3 = TH.Accent, CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = holder,
                }, { Corner(10), Stroke(TH.Border, 1), Pad(4, 4, 4, 4) })
                New("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

                local Dropdown = {}
                local conns = {}
                local function mark()
                    for _, c in ipairs(list:GetChildren()) do
                        if c:IsA("TextButton") then
                            local sel = (c.Name == tostring(value))
                            c.BackgroundTransparency = sel and 0 or 1
                            c.TextColor3 = sel and TH.White or TH.Text
                        end
                    end
                end
                function Dropdown:Get() return value end
                function Dropdown:Set(v, silent)
                    value = v
                    vlabel.Text = tostring(v)
                    mark()
                    Persist(opt, value)
                    if not silent then Fire(opt.Callback, value) end
                end
                local function build()
                    for _, c in ipairs(conns) do c:Disconnect() end
                    conns = {}
                    for _, c in ipairs(list:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for i, name in ipairs(options) do
                        local b = New("TextButton", {
                            Name = tostring(name), Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = TH.Accent,
                            BackgroundTransparency = 1, AutoButtonColor = false, Text = tostring(name), TextSize = 13,
                            Font = TH.Font, TextColor3 = TH.Text, TextXAlignment = Enum.TextXAlignment.Left,
                            TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = i, Parent = list,
                        }, { Corner(8), Pad(10, 0, 10, 0) })
                        table.insert(conns, b.Activated:Connect(function()
                            Dropdown:Set(name)
                            list.Visible = false
                        end))
                    end
                    mark()
                end
                Library.Maid:Add(function() for _, c in ipairs(conns) do c:Disconnect() end end)
                build()
                OnClick(vbtn, function()
                    list.Visible = not list.Visible
                    if list.Visible then list.Size = UDim2.new(1, 0, 0, math.min(#options * 39 + 8, 160)) end
                end)
                if opt.Callback then Fire(opt.Callback, value) end
                return Dropdown
            end

            -- Button
            function Section:CreateButton(opt)
                opt = opt or {}
                local btn = New("TextButton", {
                    Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = TH.Accent, AutoButtonColor = false,
                    Text = opt.Name or "Button", TextSize = 14, Font = TH.FontB, TextColor3 = TH.White,
                    LayoutOrder = NextOrder(), Parent = content,
                }, { Corner(10) })
                Library.Maid:Add(btn.MouseButton1Down:Connect(function()
                    Tween(btn, { BackgroundColor3 = TH.Accent:Lerp(Color3.new(0, 0, 0), 0.2) }, 0.08)
                end))
                local function release() Tween(btn, { BackgroundColor3 = TH.Accent }, 0.12) end
                Library.Maid:Add(btn.MouseButton1Up:Connect(release))
                Library.Maid:Add(btn.MouseLeave:Connect(release))
                OnClick(btn, function() Fire(opt.Callback) end)
                return btn
            end

            -- Label (teks petunjuk)
            function Section:CreateLabel(text)
                local lbl = New("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
                    Text = text or "", TextSize = 12, Font = TH.Font, TextColor3 = TH.Text, TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                    LayoutOrder = NextOrder(), Parent = content,
                }, { Pad(2, 2, 2, 2) })
                return { Set = function(_, t) lbl.Text = t end }
            end

            -- Key-Value (panel Status)
            function Section:CreateKeyValue(name, initial)
                local row = Row(32)
                RowText(row, name, UDim2.fromOffset(12, 0), UDim2.new(0.42, -12, 1, 0))
                local val = New("TextLabel", {
                    Position = UDim2.new(0.42, 0, 0, 0), Size = UDim2.new(0.58, -12, 1, 0), BackgroundTransparency = 1,
                    Text = tostring(initial or "-"), TextSize = 13, Font = TH.FontB, TextColor3 = TH.Accent,
                    TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
                })
                return { Set = function(_, t) val.Text = tostring(t) end }
            end

            -- Input (TextBox)
            function Section:CreateInput(opt)
                opt = opt or {}
                local value = tostring(Saved(opt, opt.Default or ""))
                local row = Row(64)
                RowText(row, opt.Name or "Input", UDim2.fromOffset(12, 3), UDim2.new(1, -24, 0, 18))
                local box = New("TextBox", {
                    Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 34), BackgroundColor3 = TH.Panel,
                    Text = value, PlaceholderText = opt.Placeholder or "", PlaceholderColor3 = TH.Off, TextSize = 13,
                    Font = TH.Font, TextColor3 = TH.Text, ClearTextOnFocus = false,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
                }, { Corner(8), Stroke(TH.Border, 1), Pad(10, 0, 10, 0) })
                local Input = {}
                function Input:Get() return value end
                function Input:Set(v, silent)
                    value = tostring(v)
                    box.Text = value
                    Persist(opt, value)
                    if not silent then Fire(opt.Callback, value) end
                end
                Library.Maid:Add(box.FocusLost:Connect(function() Input:Set(box.Text) end))
                if opt.Callback then Fire(opt.Callback, value) end
                return Input
            end

            -- Slider (delay dll)
            function Section:CreateSlider(opt)
                opt = opt or {}
                local min, max, step = opt.Min or 0, opt.Max or 100, opt.Step or 1
                local value = math.clamp(Saved(opt, opt.Default or min), min, max)
                local row = Row(56)
                RowText(row, opt.Name or "Slider", UDim2.fromOffset(12, 3), UDim2.new(0.6, -12, 0, 18))
                local vt = New("TextLabel", {
                    Position = UDim2.new(0.6, 0, 0, 3), Size = UDim2.new(0.4, -12, 0, 18), BackgroundTransparency = 1,
                    Text = "", TextSize = 13, Font = TH.FontB, TextColor3 = TH.Accent,
                    TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
                })
                local bar = New("Frame", {
                    Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 8), BackgroundColor3 = TH.Panel, Parent = row,
                }, { Corner(4) })
                local fill = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = TH.Accent, Parent = bar }, { Corner(4) })
                local knob = New("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(22, 22),
                    BackgroundColor3 = TH.White, Parent = bar,
                }, { Corner(11), Stroke(TH.Accent, 2) })
                local hit = New("TextButton", {
                    Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "", Parent = row,
                })
                local Slider = {}
                local function render()
                    local rel = (max == min) and 0 or (value - min) / (max - min)
                    fill.Size = UDim2.fromScale(rel, 1)
                    knob.Position = UDim2.fromScale(rel, 0.5)
                    vt.Text = string.format("%g", value) .. (opt.Suffix or "")
                end
                render()
                function Slider:Get() return value end
                function Slider:Set(v, silent)
                    v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
                    v = math.floor(v * 1000 + 0.5) / 1000
                    if v == value and not silent then return end
                    value = v
                    render()
                    Persist(opt, value)
                    if not silent then Fire(opt.Callback, value) end
                end
                local dragging = false
                local function setX(x)
                    local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
                    Slider:Set(min + rel * (max - min))
                end
                Library.Maid:Add(hit.InputBegan:Connect(function(input)
                    if IsPress(input) then
                        dragging = true
                        page.ScrollingEnabled = false -- cegah scroll saat geser slider
                        setX(input.Position.X)
                    end
                end))
                Library.Maid:Add(UIS.InputChanged:Connect(function(input)
                    if dragging and IsMove(input) then setX(input.Position.X) end
                end))
                Library.Maid:Add(UIS.InputEnded:Connect(function(input)
                    if dragging and IsPress(input) then
                        dragging = false
                        page.ScrollingEnabled = true
                    end
                end))
                if opt.Callback then Fire(opt.Callback, value) end
                return Slider
            end

            return Section
        end

        table.insert(Window.Tabs, Tab)
        Tab:ApplyNarrow(Window.Narrow)
        if not Window.ActiveTab then Window:SelectTab(Tab) end
        return Tab
    end

    return Window
end

-- ============================================================
-- [5] STATE (data murni, terpisah dari UI)
-- ============================================================
local State = {
    PNB = { TileDir = "Otomatis", StartX = 1, OffsetY = 0, Rows = 1, Enabled = false, Block = "Sugar Cane [954]", BlockId = 954, Mode = "PNB Only", Placed = 0, Broken = 0,
            Batch = 0, DropsLeft = 0, BatchSize = 3, Hits = 3, Delay = 0.15, Status = "Idle", Spot = nil },
    Clear = { Enabled = false, Mode = "Area", Width = 5, Height = 5, Hits = 3, Delay = 0.15, Cleared = 0,
              Status = "Idle", Spot = nil },
    Dirt = { TileDir = "Otomatis", StartX = 1, OffsetY = 0, Rows = 1, Enabled = false, Block = "Dirt [2]", BlockId = 2, Mode = "PNB Dirt", AutoCollect = true, Placed = 0,
             Broken = 0, Batch = 0, DropsLeft = 0, BatchSize = 3, Hits = 3, Delay = 0.15, Status = "Idle", Spot = nil },
    Farm = { TileDir = "Otomatis", StartX = 1, OffsetY = 0, Rows = 1, Enabled = false, Seed = "Sugar Cane Seed [955]", SeedId = 955, Mode = "Plant & Harvest", Width = 5,
             GrowTime = 30, Delay = 0.15, AutoCollect = true, Planted = 0, Harvested = 0, Status = "Idle", Spot = nil },
    Webhook = { Enabled = false, Url = "", Interval = 5, Sent = 0, Status = "Idle" },
    Utils = { AntiAFK = false },
}

-- CONTOH daftar block/seed: GANTI dengan nama & ID asli dari game kamu
local BlockList = { { "Dirt", 2 }, { "Stone", 4 }, { "Sand", 6 }, { "Sugar Cane", 954 }, { "Wood", 8 } }
local SeedList = { { "Sugar Cane Seed", 955 }, { "Dirt Seed", 3 }, { "Wood Seed", 9 } }
local function BuildOptions(list)
    local out = {}
    for _, e in ipairs(list) do table.insert(out, string.format("%s [%d]", e[1], e[2])) end
    return out
end
local function ParseId(text) return tonumber(tostring(text):match("%[(%d+)%]")) end

-- Unload didaftarkan lebih awal agar tetap bisa dipanggil walau pembuatan UI gagal
local Modules = {}
local function Unload()
    if Library.Destroyed then return end
    pcall(function() if Config.AutoSave then Config.Save(Library.Flags) end end)
    Library.Destroyed = true
    for _, m in pairs(Modules) do pcall(m.SetEnabled, false) end
    Library.Maid:Clean() -- putuskan semua koneksi + hancurkan GUI
    ENV.FluffyHubLoaded = false
    ENV.FluffyHubUnload = nil
end
ENV.FluffyHubUnload = Unload

-- ============================================================
-- [6] KONFIGURASI GAME + AKSI GAME (PLACEHOLDER)
--
--  CARA MENEMUKAN REMOTE / STRUKTUR GAME:
--   1. Tab Utilities > tombol "Scan Remotes": mencetak semua RemoteEvent /
--      RemoteFunction di ReplicatedStorage ke console (dan clipboard).
--   2. Atau buka Dex/Explorer: ReplicatedStorage > cari nama seperti
--      "PlaceTile", "HitTile", "Plant", "Harvest", "Collect".
--   3. Untuk melihat ARGUMEN remote, pakai remote logger (mis. SimpleSpy):
--      pasang/pukul block manual di game, lihat parameter yang terkirim,
--      lalu samakan di GameConfig.BuildArgs.
--   4. Lokasi drop: lihat workspace saat ada drop (mis. workspace.Drops).
--   5. Inventory: cek leaderstats / PlayerGui / ReplicatedStorage.PlayerData.
-- ============================================================
local GameConfig = {
    GridSize = 4, -- TODO: ukuran 1 tile (studs); cek jarak antar block di game

    -- TODO: isi dengan NAMA remote asli. Kosong = belum diisi.
    Remotes = { Place = "", Break = "", Plant = "", Harvest = "", Collect = "" },

    -- TODO: sesuaikan urutan/tipe argumen dengan hasil remote logger.
    BuildArgs = {
        Place = function(blockId, gx, gy) return blockId, gx, gy end,
        Break = function(gx, gy) return gx, gy end,
        Plant = function(seedId, gx, gy) return seedId, gx, gy end,
        Harvest = function(gx, gy) return gx, gy end,
        Collect = function(drop) return drop end,
    },

    -- TODO: kembalikan Instance (Folder) tempat item drop berada.
    DropFolder = function() return workspace:FindFirstChild("Drops") end,

    -- TODO: kembalikan jumlah item di inventory (nil = tidak diketahui, cek stok dilewati).
    GetInventoryCount = function(itemId) return nil end,
}

local Actions = {}
local remoteCache, warned = {}, {}
local function WarnOnce(key, msg)
    if not warned[key] then
        warned[key] = true
        warn("[Fluffy Hub] " .. msg)
    end
end

function Actions.FindRemote(kind)
    local name = GameConfig.Remotes[kind]
    if not name or name == "" then
        WarnOnce("e" .. kind, "Remote '" .. kind .. "' belum diisi di GameConfig.Remotes")
        return nil
    end
    local c = remoteCache[kind]
    if c and c.Parent then return c end
    local r = RS:FindFirstChild(name, true)
    if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then
        remoteCache[kind] = r
        return r
    end
    WarnOnce("m" .. kind, "Remote '" .. name .. "' tidak ditemukan di ReplicatedStorage")
    return nil
end

function Actions.Invoke(kind, ...)
    local remote = Actions.FindRemote(kind)
    if not remote then return false end
    local ok, res = pcall(function(...)
        if remote:IsA("RemoteFunction") then return remote:InvokeServer(...) end
        remote:FireServer(...)
        return true
    end, ...)
    if not ok then WarnOnce("x" .. kind, "Remote '" .. kind .. "' error: " .. tostring(res)) end
    return ok, res
end

function Actions.GetRoot()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end
function Actions.WorldToGrid(pos)
    -- TODO: sesuaikan sumbu (default: X horizontal, Y vertikal / game 2D)
    local g = GameConfig.GridSize
    return math.floor(pos.X / g + 0.5), math.floor(pos.Y / g + 0.5)
end
function Actions.GetFacing()
    local root = Actions.GetRoot()
    if root and root.CFrame.LookVector.X < 0 then return -1 end
    return 1
end
function Actions.TeleportTo(pos)
    local root = Actions.GetRoot()
    if root then root.CFrame = CFrame.new(pos) end
end

function Actions.PlaceBlock(blockId, gx, gy)
    local ok, res = Actions.Invoke("Place", GameConfig.BuildArgs.Place(blockId, gx, gy))
    return ok and res ~= false
end
function Actions.BreakBlock(gx, gy)
    local ok, res = Actions.Invoke("Break", GameConfig.BuildArgs.Break(gx, gy))
    return ok and res ~= false
end
function Actions.PlantSeed(seedId, gx, gy)
    local ok, res = Actions.Invoke("Plant", GameConfig.BuildArgs.Plant(seedId, gx, gy))
    return ok and res ~= false
end
function Actions.HarvestTile(gx, gy)
    local ok, res = Actions.Invoke("Harvest", GameConfig.BuildArgs.Harvest(gx, gy))
    return ok and res ~= false
end

local function InstancePos(inst)
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then return inst:GetPivot().Position end
    return nil
end
function Actions.GetDrops()
    local ok, folder = pcall(GameConfig.DropFolder)
    if ok and folder then return folder:GetChildren() end
    return {}
end
function Actions.CountDrops() return #Actions.GetDrops() end
function Actions.CollectDrops()
    local root = Actions.GetRoot()
    if not root then return 0 end
    local origin = root.CFrame
    local n = 0
    for _, drop in ipairs(Actions.GetDrops()) do
        local pos = InstancePos(drop)
        if pos then
            Actions.TeleportTo(pos) -- TODO: ganti tween/pathfinding jika ada anti-teleport
            if GameConfig.Remotes.Collect ~= "" then
                Actions.Invoke("Collect", GameConfig.BuildArgs.Collect(drop))
            end
            n = n + 1
            task.wait(0.1)
        end
    end
    root = Actions.GetRoot()
    if root then root.CFrame = origin end
    return n
end
function Actions.GetInventoryCount(itemId)
    local ok, res = pcall(GameConfig.GetInventoryCount, itemId)
    if ok then return res end
    return nil
end

-- ============================================================
-- [7] MODUL LOGIKA FITUR
-- ============================================================
-- Loop berjalan di task.spawn dengan pcall; selalu yield (task.wait)
local function CreateModule(state, step)
    local M = { OnChange = nil }
    local gen = 0
    function M.SetEnabled(v, reason)
        v = v and true or false
        gen = gen + 1
        local my = gen
        state.Enabled = v
        if v then
            state.Status = "Memulai"
            local function alive() return state.Enabled and gen == my and not Library.Destroyed end
            task.spawn(function()
                while alive() do
                    local ok, err = pcall(step, alive)
                    if not ok then
                        warn("[Fluffy Hub] Error modul: " .. tostring(err))
                        state.Status = "Error (lihat console)"
                        task.wait(1)
                    end
                    task.wait()
                end
            end)
        else
            state.Status = reason or "Idle"
        end
        if M.OnChange then pcall(M.OnChange, v) end
    end
    return M
end

local function RequireRemotes(module, kinds)
    for _, kind in ipairs(kinds) do
        if not Actions.FindRemote(kind) then
            module.SetEnabled(false, "Remote '" .. kind .. "' belum diisi")
            return false
        end
    end
    return true
end

local function ResolveOrigin(s)
    local root = Actions.GetRoot()
    if not root then return nil end
    if not s.Spot then
        local gx, gy = Actions.WorldToGrid(root.Position)
        s.Spot = { Pos = root.Position, X = gx, Y = gy, Dir = Actions.GetFacing() }
    elseif (root.Position - s.Spot.Pos).Magnitude > GameConfig.GridSize * 4 then
        Actions.TeleportTo(s.Spot.Pos)
    end
    return s.Spot.X, s.Spot.Y, s.Spot.Dir
end

local function ResetSpot(s, counters)
    s.Spot = nil
    for _, k in ipairs(counters) do s[k] = 0 end
    if ResolveOrigin(s) then s.Status = "Spot baru disimpan" else s.Status = "Karakter tidak ditemukan" end
end

-- Susun daftar tile target dari pengaturan tile (arah, mulai, offset Y, baris)
local function BuildTargets(s, count)
    local ox, oy, dir = ResolveOrigin(s)
    if not ox then return nil end
    if s.TileDir == "Kiri" then dir = -1 elseif s.TileDir == "Kanan" then dir = 1 end
    local targets = {}
    for r = 0, s.Rows - 1 do
        for i = 0, count - 1 do
            table.insert(targets, { ox + dir * (s.StartX + i), oy + s.OffsetY - r })
        end
    end
    return targets
end

-- Satu siklus pasang + hancurkan (dipakai PNB & Dirt Farm)
local function PlaceBreakCycle(s, alive, blockId, doPlace, doBreak)
    local targets = BuildTargets(s, s.BatchSize)
    if not targets then
        s.Status = "Karakter tidak ditemukan"
        task.wait(1)
        return false
    end
    if doPlace then
        s.Status = "Memasang block"
        for _, t in ipairs(targets) do
            if not alive() then return false end
            if Actions.PlaceBlock(blockId, t[1], t[2]) then s.Placed = s.Placed + 1 end
            task.wait(s.Delay)
        end
    end
    if doBreak then
        s.Status = "Menghancurkan block"
        for _, t in ipairs(targets) do
            local broke = false
            for _ = 1, s.Hits do
                if not alive() then return false end
                if Actions.BreakBlock(t[1], t[2]) then broke = true end
                task.wait(s.Delay)
            end
            if broke then s.Broken = s.Broken + 1 end
        end
    end
    s.Batch = s.Batch + 1
    return true
end

-- Auto PNB
local PNB
PNB = CreateModule(State.PNB, function(alive)
    local s = State.PNB
    local doPlace = s.Mode ~= "Break Only"
    local doBreak = s.Mode ~= "Place Only"
    local need = {}
    if doPlace then table.insert(need, "Place") end
    if doBreak then table.insert(need, "Break") end
    if not RequireRemotes(PNB, need) then return end
    if doPlace then
        local stock = Actions.GetInventoryCount(s.BlockId)
        if stock ~= nil and stock < s.BatchSize * s.Rows then
            PNB.SetEnabled(false, "Stok block habis")
            return
        end
    end
    if not PlaceBreakCycle(s, alive, s.BlockId, doPlace, doBreak) then return end
    s.DropsLeft = Actions.CountDrops()
    if s.Mode == "PNB + Collect Drop" and s.DropsLeft > 0 then
        s.Status = "Mengambil drop"
        Actions.CollectDrops()
        s.DropsLeft = Actions.CountDrops()
    end
    s.Status = "Menunggu batch berikutnya"
    task.wait(s.Delay)
end)

-- Auto Clear
local Clear
Clear = CreateModule(State.Clear, function(alive)
    local s = State.Clear
    if not RequireRemotes(Clear, { "Break" }) then return end
    local ox, oy, dir = ResolveOrigin(s)
    if not ox then
        s.Status = "Karakter tidak ditemukan"
        task.wait(1)
        return
    end
    local targets = {}
    if s.Mode == "Area" then
        for dy = 0, -(s.Height - 1), -1 do
            for dx = 1, s.Width do table.insert(targets, { ox + dir * dx, oy + dy }) end
        end
    elseif s.Mode == "Baris" then
        for dx = 1, s.Width do table.insert(targets, { ox + dir * dx, oy }) end
    else
        for dy = 0, -(s.Height - 1), -1 do table.insert(targets, { ox + dir, oy + dy }) end
    end
    s.Status = "Membersihkan area"
    for _, t in ipairs(targets) do
        local broke = false
        for _ = 1, s.Hits do
            if not alive() then return end
            if Actions.BreakBlock(t[1], t[2]) then broke = true end
            task.wait(s.Delay)
        end
        if broke then s.Cleared = s.Cleared + 1 end
    end
    Clear.SetEnabled(false, "Selesai")
end)

-- Auto Dirt Farm
local Dirt
Dirt = CreateModule(State.Dirt, function(alive)
    local s = State.Dirt
    if s.Mode == "PNB Dirt" then
        if not RequireRemotes(Dirt, { "Place", "Break" }) then return end
        local stock = Actions.GetInventoryCount(s.BlockId)
        if stock ~= nil and stock < s.BatchSize * s.Rows then
            Dirt.SetEnabled(false, "Stok dirt habis")
            return
        end
        if not PlaceBreakCycle(s, alive, s.BlockId, true, true) then return end
    end
    s.DropsLeft = Actions.CountDrops()
    if s.AutoCollect and s.DropsLeft > 0 then
        s.Status = "Mengambil seed/drop"
        Actions.CollectDrops()
        s.DropsLeft = Actions.CountDrops()
    end
    s.Status = "Menunggu"
    task.wait(math.max(s.Delay, 0.25))
end)

-- Auto Farm (tanam & panen)
local Farm
Farm = CreateModule(State.Farm, function(alive)
    local s = State.Farm
    local doPlant = s.Mode ~= "Harvest Only"
    local doHarvest = s.Mode ~= "Plant Only"
    local need = {}
    if doPlant then table.insert(need, "Plant") end
    if doHarvest then table.insert(need, "Harvest") end
    if not RequireRemotes(Farm, need) then return end
    local targets = BuildTargets(s, s.Width)
    if not targets then
        s.Status = "Karakter tidak ditemukan"
        task.wait(1)
        return
    end
    if doPlant then
        s.Status = "Menanam"
        for _, t in ipairs(targets) do
            if not alive() then return end
            if Actions.PlantSeed(s.SeedId, t[1], t[2]) then s.Planted = s.Planted + 1 end
            task.wait(s.Delay)
        end
    end
    if doPlant and doHarvest then
        for remaining = s.GrowTime, 1, -1 do
            if not alive() then return end
            s.Status = "Menunggu tumbuh (" .. remaining .. "s)"
            task.wait(1)
        end
    end
    if doHarvest then
        s.Status = "Memanen"
        for _, t in ipairs(targets) do
            if not alive() then return end
            if Actions.HarvestTile(t[1], t[2]) then s.Harvested = s.Harvested + 1 end
            task.wait(s.Delay)
        end
    end
    if s.AutoCollect and Actions.CountDrops() > 0 then
        s.Status = "Mengambil drop"
        Actions.CollectDrops()
    end
    if s.Mode ~= "Plant & Harvest" then Farm.SetEnabled(false, "Selesai") end
end)

-- Webhook Discord
local function IsDiscordWebhook(url)
    if type(url) ~= "string" then return false end
    url = url:lower()
    return url:match("^https://discord%.com/api/webhooks/") ~= nil
        or url:match("^https://discordapp%.com/api/webhooks/") ~= nil
        or url:match("^https://canary%.discord%.com/api/webhooks/") ~= nil
        or url:match("^https://ptb%.discord%.com/api/webhooks/") ~= nil
end

local function SendReport(title)
    local s = State.Webhook
    if not IsDiscordWebhook(s.Url) then return false, "URL webhook tidak valid" end
    local p, c, d, f = State.PNB, State.Clear, State.Dirt, State.Farm
    local payload = {
        username = "Fluffy Hub",
        embeds = { {
            title = title or "Laporan Fluffy Hub",
            description = "Pemain: " .. LocalPlayer.Name,
            color = 11875418,
            fields = {
                { name = "Auto PNB", value = string.format("Terpasang: %d\nDihancurkan: %d\nBatch: %d", p.Placed, p.Broken, p.Batch), inline = true },
                { name = "Dirt Farm", value = string.format("Terpasang: %d\nDihancurkan: %d\nBatch: %d", d.Placed, d.Broken, d.Batch), inline = true },
                { name = "Auto Farm", value = string.format("Ditanam: %d\nDipanen: %d", f.Planted, f.Harvested), inline = true },
                { name = "Auto Clear", value = string.format("Dibersihkan: %d", c.Cleared), inline = true },
            },
            footer = { text = "Fluffy Hub v" .. VERSION },
        } },
    }
    local res, err = HttpRequest({
        Url = s.Url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(payload),
    })
    if not res then return false, err end
    local code = res.StatusCode or 0
    return code >= 200 and code < 300, "HTTP " .. tostring(code)
end

local Webhook
Webhook = CreateModule(State.Webhook, function(alive)
    local s = State.Webhook
    if not IsDiscordWebhook(s.Url) then
        Webhook.SetEnabled(false, "URL webhook tidak valid")
        return
    end
    local total = math.max(1, s.Interval) * 60
    for waited = 1, total do
        if not alive() then return end
        s.Status = "Laporan berikutnya " .. (total - waited + 1) .. "s"
        task.wait(1)
    end
    s.Status = "Mengirim laporan"
    local ok, info = SendReport("Laporan Berkala")
    if ok then s.Sent = s.Sent + 1 end
    s.Status = ok and "Terkirim" or ("Gagal: " .. tostring(info))
end)

Modules.PNB, Modules.Clear, Modules.Dirt, Modules.Farm, Modules.Webhook = PNB, Clear, Dirt, Farm, Webhook

-- Utilities: Anti-AFK
local antiAfkConn = nil
local function SetAntiAFK(v)
    State.Utils.AntiAFK = v
    if antiAfkConn then antiAfkConn:Disconnect() antiAfkConn = nil end
    if v then
        antiAfkConn = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
        Library.Maid:Add(antiAfkConn)
    end
end

local REMOTE_KEYWORDS = { "place", "break", "hit", "punch", "fist", "build", "destroy", "plant", "harvest",
    "collect", "pickup", "drop", "tile", "block", "seed" }

local function CollectRemoteLines(filtered)
    local lines = {}
    local function scan(root)
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                local full = d:GetFullName()
                local keep = not filtered
                if filtered then
                    local low = full:lower()
                    for _, k in ipairs(REMOTE_KEYWORDS) do
                        if low:find(k, 1, true) then keep = true break end
                    end
                end
                if keep then table.insert(lines, d.ClassName .. " : " .. full) end
            end
        end
    end
    scan(RS)
    pcall(scan, workspace)
    return lines
end

local function ScanRemotes(filtered)
    local lines = CollectRemoteLines(filtered)
    print("[Fluffy Hub] Daftar Remote (" .. #lines .. ")")
    for _, l in ipairs(lines) do print(l) end
    if typeof(setclipboard) == "function" then pcall(setclipboard, table.concat(lines, "\n")) end
    return #lines
end

-- Kirim daftar remote ke webhook Discord milikmu (dipecah per ~1800 karakter)
local function SendRemotesToWebhook(filtered)
    local url = State.Webhook.Url
    if not IsDiscordWebhook(url) then return false, "Isi Webhook URL dulu di tab Webhook" end
    local lines = CollectRemoteLines(filtered)
    if #lines == 0 then return false, "Tidak ada remote ditemukan" end
    local chunk, sent = "", 0
    local function flush()
        if chunk == "" then return true end
        local res, err = HttpRequest({
            Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ username = "Fluffy Hub", content = "```\n" .. chunk .. "```" }),
        })
        chunk = ""
        sent = sent + 1
        task.wait(1.2)
        if not res then return false, err end
        return true
    end
    for _, l in ipairs(lines) do
        if #chunk + #l + 1 > 1800 then
            local ok, e = flush()
            if not ok then return false, e end
        end
        chunk = chunk .. l .. "\n"
    end
    local ok, e = flush()
    if not ok then return false, e end
    return true, #lines .. " remote dalam " .. sent .. " pesan"
end

-- ============================================================
-- [8] MEMBANGUN UI
-- ============================================================
local function BuildUI()
    local Window = Library:CreateWindow({ Title = "Fluffy Hub", Badge = "Premium" })
    local Binds = {}

    local function StatusSection(tab, rows)
        local sec = tab:CreateSection("Status", "Right")
        for _, r in ipairs(rows) do
            table.insert(Binds, { tab = tab, kv = sec:CreateKeyValue(r[1], "-"), get = r[2], last = nil })
        end
    end
    -- Pengaturan tile (dipakai tab PNB, Dirt Farm, Farm)
    local function TileControls(sec, st, pre)
        sec:CreateDropdown({ Name = "Arah tile", Options = { "Otomatis", "Kiri", "Kanan" }, Default = "Otomatis",
            Flag = pre .. "_tdir", Callback = function(v) st.TileDir = v end })
        sec:CreateSlider({ Name = "Mulai dari tile ke-", Min = 1, Max = 10, Step = 1, Default = 1,
            Flag = pre .. "_tstart", Callback = function(v) st.StartX = v end })
        sec:CreateSlider({ Name = "Offset baris (Y)", Min = -5, Max = 5, Step = 1, Default = 0,
            Flag = pre .. "_toffy", Callback = function(v) st.OffsetY = v end })
        sec:CreateSlider({ Name = "Jumlah baris", Min = 1, Max = 5, Step = 1, Default = 1,
            Flag = pre .. "_trows", Callback = function(v) st.Rows = v end })
    end
    local function Link(module, toggle)
        module.OnChange = function(v) toggle:Set(v, true) end
    end

    local tHome = Window:CreateTab("Home", ICON.Home)
    local tClear = Window:CreateTab("Auto Clear", ICON.Clear)
    local tDirt = Window:CreateTab("Auto Dirt Farm", ICON.Dirt)
    local tPNB = Window:CreateTab("Auto PNB", ICON.PNB)
    local tFarm = Window:CreateTab("Auto Farm", ICON.Farm)
    local tHook = Window:CreateTab("Webhook", ICON.Hook)
    local tUtil = Window:CreateTab("Utilities", ICON.Util)

    -- HOME
    do
        local info = tHome:CreateSection("Informasi", "Left")
        info:CreateKeyValue("Pemain", LocalPlayer.DisplayName)
        info:CreateKeyValue("Executor", ExecutorName())
        info:CreateKeyValue("Versi", VERSION)
        info:CreateKeyValue("Key", keyMsg)
        info:CreateKeyValue("Simpan file", Config.Supported() and "Didukung" or "Tidak didukung")
        local ctl = tHome:CreateSection("Kontrol", "Right")
        ctl:CreateToggle({ Name = "Auto Save Config", Flag = "autosave", Default = true,
            Callback = function(v) Config.AutoSave = v end })
        ctl:CreateButton({ Name = "Simpan Config Sekarang", Callback = function()
            Notify("Fluffy Hub", Config.Save(Library.Flags) and "Config tersimpan" or "Executor tidak mendukung writefile", 3)
        end })
        ctl:CreateButton({ Name = "Tutup Hub (Unload)", Callback = Unload })
        ctl:CreateLabel("Gunakan tombol bulat mengambang untuk buka/tutup UI. Tombol << di header untuk minimize.")
    end

    -- AUTO PNB
    do
        local sec = tPNB:CreateSection("Auto PNB", "Left")
        sec:CreateDropdown({ Name = "Block", Options = BuildOptions(BlockList), Default = "Sugar Cane [954]",
            Flag = "pnb_block", Callback = function(v)
                State.PNB.Block = v
                State.PNB.BlockId = ParseId(v) or State.PNB.BlockId
            end })
        local tgl = sec:CreateToggle({ Name = "Auto PNB", Persist = false, Callback = function(v)
            if v ~= State.PNB.Enabled then PNB.SetEnabled(v) end
        end })
        Link(PNB, tgl)
        sec:CreateDropdown({ Name = "Mode", Options = { "PNB Only", "PNB + Collect Drop", "Place Only", "Break Only" },
            Default = "PNB Only", Flag = "pnb_mode", Callback = function(v) State.PNB.Mode = v end })
        sec:CreateSlider({ Name = "Tile per batch", Min = 1, Max = 8, Step = 1, Default = 3, Flag = "pnb_batch",
            Callback = function(v) State.PNB.BatchSize = v end })
        sec:CreateSlider({ Name = "Hit per block", Min = 1, Max = 6, Step = 1, Default = 3, Flag = "pnb_hits",
            Callback = function(v) State.PNB.Hits = v end })
        TileControls(sec, State.PNB, "pnb")
        sec:CreateSlider({ Name = "Delay", Min = 0.05, Max = 1, Step = 0.05, Default = 0.15, Suffix = "s",
            Flag = "pnb_delay", Callback = function(v) State.PNB.Delay = v end })
        sec:CreateButton({ Name = "Reset PNB Spot", Callback = function()
            ResetSpot(State.PNB, { "Placed", "Broken", "Batch", "DropsLeft" })
        end })
        sec:CreateLabel("Display Box kiri untuk seed\nDisplay Box kanan untuk stok block\nLetakkan di lantai yang sama di luar area PNB")
        local p = State.PNB
        StatusSection(tPNB, {
            { "Status", function() return p.Status end },
            { "Mode", function() return p.Mode end },
            { "Terpasang", function() return p.Placed end },
            { "Dihancurkan", function() return p.Broken end },
            { "Batch", function() return p.Batch end },
            { "Tile target", function() return p.BatchSize * p.Rows end },
            { "Drop tersisa", function() return p.DropsLeft end },
        })
    end

    -- AUTO CLEAR
    do
        local sec = tClear:CreateSection("Auto Clear", "Left")
        local tgl = sec:CreateToggle({ Name = "Auto Clear", Persist = false, Callback = function(v)
            if v ~= State.Clear.Enabled then Clear.SetEnabled(v) end
        end })
        Link(Clear, tgl)
        sec:CreateDropdown({ Name = "Mode", Options = { "Area", "Baris", "Kolom" }, Default = "Area",
            Flag = "clear_mode", Callback = function(v) State.Clear.Mode = v end })
        sec:CreateSlider({ Name = "Lebar (tile)", Min = 1, Max = 20, Step = 1, Default = 5, Flag = "clear_w",
            Callback = function(v) State.Clear.Width = v end })
        sec:CreateSlider({ Name = "Tinggi (tile)", Min = 1, Max = 20, Step = 1, Default = 5, Flag = "clear_h",
            Callback = function(v) State.Clear.Height = v end })
        sec:CreateSlider({ Name = "Delay", Min = 0.05, Max = 1, Step = 0.05, Default = 0.15, Suffix = "s",
            Flag = "clear_delay", Callback = function(v) State.Clear.Delay = v end })
        sec:CreateButton({ Name = "Reset Spot Clear", Callback = function() ResetSpot(State.Clear, { "Cleared" }) end })
        local c = State.Clear
        StatusSection(tClear, {
            { "Status", function() return c.Status end },
            { "Mode", function() return c.Mode end },
            { "Dibersihkan", function() return c.Cleared end },
            { "Area", function() return c.Width .. " x " .. c.Height end },
        })
    end

    -- AUTO DIRT FARM
    do
        local sec = tDirt:CreateSection("Auto Dirt Farm", "Left")
        sec:CreateDropdown({ Name = "Block Dirt", Options = BuildOptions(BlockList), Default = "Dirt [2]",
            Flag = "dirt_block", Callback = function(v)
                State.Dirt.Block = v
                State.Dirt.BlockId = ParseId(v) or State.Dirt.BlockId
            end })
        local tgl = sec:CreateToggle({ Name = "Auto Dirt Farm", Persist = false, Callback = function(v)
            if v ~= State.Dirt.Enabled then Dirt.SetEnabled(v) end
        end })
        Link(Dirt, tgl)
        sec:CreateDropdown({ Name = "Mode", Options = { "PNB Dirt", "Collect Seed Only" }, Default = "PNB Dirt",
            Flag = "dirt_mode", Callback = function(v) State.Dirt.Mode = v end })
        sec:CreateToggle({ Name = "Auto ambil drop", Default = true, Flag = "dirt_collect",
            Callback = function(v) State.Dirt.AutoCollect = v end })
        sec:CreateSlider({ Name = "Tile per batch", Min = 1, Max = 8, Step = 1, Default = 3, Flag = "dirt_batch",
            Callback = function(v) State.Dirt.BatchSize = v end })
        TileControls(sec, State.Dirt, "dirt")
        sec:CreateSlider({ Name = "Delay", Min = 0.05, Max = 1, Step = 0.05, Default = 0.15, Suffix = "s",
            Flag = "dirt_delay", Callback = function(v) State.Dirt.Delay = v end })
        sec:CreateButton({ Name = "Reset Spot Dirt", Callback = function()
            ResetSpot(State.Dirt, { "Placed", "Broken", "Batch", "DropsLeft" })
        end })
        local d = State.Dirt
        StatusSection(tDirt, {
            { "Status", function() return d.Status end },
            { "Mode", function() return d.Mode end },
            { "Terpasang", function() return d.Placed end },
            { "Dihancurkan", function() return d.Broken end },
            { "Batch", function() return d.Batch end },
            { "Drop tersisa", function() return d.DropsLeft end },
        })
    end

    -- AUTO FARM
    do
        local sec = tFarm:CreateSection("Auto Farm", "Left")
        sec:CreateDropdown({ Name = "Seed", Options = BuildOptions(SeedList), Default = "Sugar Cane Seed [955]",
            Flag = "farm_seed", Callback = function(v)
                State.Farm.Seed = v
                State.Farm.SeedId = ParseId(v) or State.Farm.SeedId
            end })
        local tgl = sec:CreateToggle({ Name = "Auto Farm", Persist = false, Callback = function(v)
            if v ~= State.Farm.Enabled then Farm.SetEnabled(v) end
        end })
        Link(Farm, tgl)
        sec:CreateDropdown({ Name = "Mode", Options = { "Plant & Harvest", "Plant Only", "Harvest Only" },
            Default = "Plant & Harvest", Flag = "farm_mode", Callback = function(v) State.Farm.Mode = v end })
        sec:CreateToggle({ Name = "Auto ambil drop", Default = true, Flag = "farm_collect",
            Callback = function(v) State.Farm.AutoCollect = v end })
        sec:CreateSlider({ Name = "Jumlah tile", Min = 1, Max = 12, Step = 1, Default = 5, Flag = "farm_w",
            Callback = function(v) State.Farm.Width = v end })
        TileControls(sec, State.Farm, "farm")
        sec:CreateSlider({ Name = "Waktu tumbuh", Min = 5, Max = 300, Step = 5, Default = 30, Suffix = "s",
            Flag = "farm_grow", Callback = function(v) State.Farm.GrowTime = v end })
        sec:CreateSlider({ Name = "Delay", Min = 0.05, Max = 1, Step = 0.05, Default = 0.15, Suffix = "s",
            Flag = "farm_delay", Callback = function(v) State.Farm.Delay = v end })
        sec:CreateButton({ Name = "Reset Spot Farm", Callback = function() ResetSpot(State.Farm, { "Planted", "Harvested" }) end })
        local f = State.Farm
        StatusSection(tFarm, {
            { "Status", function() return f.Status end },
            { "Mode", function() return f.Mode end },
            { "Ditanam", function() return f.Planted end },
            { "Dipanen", function() return f.Harvested end },
        })
    end

    -- WEBHOOK
    do
        local sec = tHook:CreateSection("Webhook Discord", "Left")
        -- Catatan: URL webhook ikut tersimpan di file config; jangan bagikan file itu.
        sec:CreateInput({ Name = "Webhook URL", Placeholder = "https://discord.com/api/webhooks/...",
            Flag = "webhook_url", Callback = function(v) State.Webhook.Url = v end })
        local tgl = sec:CreateToggle({ Name = "Laporan berkala", Persist = false, Callback = function(v)
            if v ~= State.Webhook.Enabled then Webhook.SetEnabled(v) end
        end })
        Link(Webhook, tgl)
        sec:CreateSlider({ Name = "Interval", Min = 1, Max = 60, Step = 1, Default = 5, Suffix = " mnt",
            Flag = "webhook_interval", Callback = function(v) State.Webhook.Interval = v end })
        sec:CreateButton({ Name = "Test Webhook", Callback = function()
            State.Webhook.Status = "Mengirim test"
            local ok, info = SendReport("Test Webhook Fluffy Hub")
            State.Webhook.Status = ok and "Test berhasil" or ("Gagal: " .. tostring(info))
            Notify("Fluffy Hub", State.Webhook.Status, 4)
        end })
        sec:CreateLabel("Hanya URL webhook Discord yang diterima. Butuh executor dengan request/http_request.")
        local w = State.Webhook
        StatusSection(tHook, {
            { "Status", function() return w.Status end },
            { "Terkirim", function() return w.Sent end },
            { "Interval", function() return w.Interval .. " menit" end },
        })
    end

    -- UTILITIES
    do
        local sec = tUtil:CreateSection("Utilities", "Left")
        sec:CreateToggle({ Name = "Anti-AFK", Default = true, Flag = "util_afk", Callback = SetAntiAFK })
        if typeof(setfpscap) == "function" then
            sec:CreateSlider({ Name = "FPS Cap", Min = 15, Max = 120, Step = 5, Default = 60, Flag = "util_fps",
                Callback = function(v) pcall(setfpscap, v) end })
        end
        sec:CreateButton({ Name = "Rejoin Server", Callback = function()
            pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
        end })
        local dev = tUtil:CreateSection("Bantuan Developer", "Right")
        dev:CreateButton({ Name = "Scan Remotes", Callback = function()
            Notify("Fluffy Hub", ScanRemotes() .. " remote ditemukan (lihat console)", 4)
        end })
        dev:CreateLabel("Mencetak semua RemoteEvent/RemoteFunction di ReplicatedStorage untuk mengisi GameConfig.Remotes.")
        dev:CreateButton({ Name = "Kirim Remote ke Webhook (filter)", Callback = function()
            Fire(function()
                local ok, info = SendRemotesToWebhook(true)
                Notify("Fluffy Hub", ok and ("Terkirim: " .. tostring(info)) or ("Gagal: " .. tostring(info)), 5)
            end)
        end })
        dev:CreateButton({ Name = "Kirim Semua Remote ke Webhook", Callback = function()
            Fire(function()
                local ok, info = SendRemotesToWebhook(false)
                Notify("Fluffy Hub", ok and ("Terkirim: " .. tostring(info)) or ("Gagal: " .. tostring(info)), 5)
            end)
        end })
        dev:CreateLabel("Isi dulu Webhook URL di tab Webhook. Hasil muncul di channel Discord-mu, tinggal disalin.")
    end

    -- Loop status ringan: hanya update tab yang terlihat
    task.spawn(function()
        while not Library.Destroyed do
            if Window:IsVisible() and not Window.Minimized then
                for _, b in ipairs(Binds) do
                    if Window.ActiveTab == b.tab then
                        local ok, v = pcall(b.get)
                        v = ok and tostring(v) or "-"
                        if v ~= b.last then
                            b.last = v
                            b.kv:Set(v)
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)

    Window:SelectTab(tHome)
end

local okBuild, errBuild = pcall(BuildUI)
if not okBuild then
    warn("[Fluffy Hub] Gagal membuat UI: " .. tostring(errBuild))
    Notify("Fluffy Hub", "Gagal: " .. tostring(errBuild):sub(1, 90), 10)
    Unload()
    return
end
Notify("Fluffy Hub", "Berhasil dimuat. Isi GameConfig agar aksi game aktif.", 5)
