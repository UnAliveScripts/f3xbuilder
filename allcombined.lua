--[[
 ==============================================================================
 F3X BUILD SYSTEM — ULTIMATE PRODUCTION EDITION v3.0
 Merged: Build Loader + Build Selector/Exporter
 Single LocalScript — Place in StarterPlayerScripts
 ==============================================================================
]]

-- 1. SERVICES & CONSTANTS
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player and player:GetMouse()

-- Fallback mouse position if GetMouse() fails
local function getMouseX()
	if mouse then return mouse.X end
	return UserInputService:GetMouseLocation().X
end

local function getMouseY()
	if mouse then return mouse.Y end
	return UserInputService:GetMouseLocation().Y
end

local readfile = readfile
local isfile = isfile
local listfiles = listfiles
local isfolder = isfolder
local writefile = writefile
local makefolder = makefolder
local delfile = delfile
local appendfile = appendfile
local setclipboard = setclipboard

if not math.clamp then math.clamp = function(v, mn, mx) return math.max(mn, math.min(mx, v)) end end

-- Wrap any function call in pcall to suppress all errors
local function safeCall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then warn("[F3X] Suppressed:", tostring(err):sub(1, 80)) end
	return ok, err
end

local function safeClick(btn, fn)
	btn.MouseButton1Click:Connect(function(...)
		pcall(fn, ...)
	end)
end

local function safeReadFile(path)
	local ok, result = xpcall(function()
		if not isfile then return nil end
		if not isfile(path) then return nil end
		local f = readfile(path)
		if type(f) ~= "string" then return nil end
		return f
	end, function(err) return nil end)
	if not ok then return nil end
	return result
end

local function safeHttpGet(url)
	local ok, result = pcall(function() return game:HttpGet(url) end)
	if ok and result then return result end
	return nil
end

local hasFileAccess = false
local SAVE_FOLDER = "BuildExports"

if writefile and makefolder and isfolder then
	local testOk = pcall(function()
		if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
		writefile(SAVE_FOLDER .. "/_xeno_test.txt", "ok")
	end)
	if testOk then
		pcall(function() delfile(SAVE_FOLDER .. "/_xeno_test.txt") end)
		hasFileAccess = true
	end
end

-- 2. CONFIG
local CONFIG = {
	GitHubRepo = "UnAliveScripts/f3xbuildsjson",
	GitHubBranch = "main",
	LocalFolder = "BuildExports",
	BuildSpeed = 0.005,
	BatchSize = 10,
	BtoolsTimeout = 12,
	Debug = false,
	BuildAnchored = false,
	HyperMode = false,
	HyperThreads = 4,
	SelectionColor = Color3.fromRGB(0, 170, 255),
	BoxFillTransparency = 0.88,
	MaxParts = 100000,
	VisualLimit = 500,
	DragThreshold = 5,
	StreamBatch = 2000,
	FileChunkSize = 5000,
	ListCap = 500,
	UndoDepth = 10,
}

local function dprint(...)
	if CONFIG.Debug then print("[F3X System]", ...) end
end

-- 3. CONFIG PERSISTENCE + BUILD QUEUE
local buildQueue = {}
local queueActive = false
local CONFIG_FILE = CONFIG.LocalFolder .. "/build_config.json"

local function saveConfig()
	if not hasFileAccess then return end
	local configData = {
		BuildAnchored = CONFIG.BuildAnchored,
		BuildSpeed = CONFIG.BuildSpeed,
		BatchSize = CONFIG.BatchSize,
		HyperThreads = CONFIG.HyperThreads,
		LocalFolder = CONFIG.LocalFolder,
		GitHubRepo = CONFIG.GitHubRepo,
	}
	local ok, json = pcall(function() return HttpService:JSONEncode(configData) end)
	if ok then pcall(function() writefile(CONFIG_FILE, json) end) end
end

local function loadConfig()
	if not hasFileAccess then return end
	local ok, content = pcall(function() return readfile(CONFIG_FILE) end)
	if ok and content and #content > 0 then
		local parseOk, data = pcall(function() return HttpService:JSONDecode(content) end)
		if parseOk and type(data) == "table" then
			if data.BuildAnchored ~= nil then CONFIG.BuildAnchored = data.BuildAnchored end
			if data.BuildSpeed ~= nil then CONFIG.BuildSpeed = data.BuildSpeed end
			if data.BatchSize ~= nil then CONFIG.BatchSize = data.BatchSize end
			if data.HyperThreads ~= nil then CONFIG.HyperThreads = data.HyperThreads end
			if data.LocalFolder then CONFIG.LocalFolder = data.LocalFolder end
			if data.GitHubRepo then CONFIG.GitHubRepo = data.GitHubRepo end
		end
	end
end

loadConfig()

-- Btool helper functions (must be before F3X table)
local function hasBuildingTool()
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()
	local function check(c)
		if not c then return nil end
		for _, item in ipairs(c:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then return item end
		end
		return nil
	end
	return check(backpack) or check(char)
end

local function equipBuildingTool()
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()
	local tool = nil
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then tool = item; break end
		end
	end
	if not tool then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then tool = item; break end
		end
	end
	if tool and tool.Parent == backpack then char.Humanoid:EquipTool(tool) end
	return tool ~= nil
end

local function sendBtoolsCommand()
	local success = false
	pcall(function()
		local tc = TextChatService:FindFirstChild("TextChannels")
		if tc then
			local rb = tc:FindFirstChild("RBXGeneral")
			if rb then rb:SendAsync(";btools"); success = true end
		end
	end)
	if not success then pcall(function() Players:Chat(";btools"); success = true end) end
	return success
end

local function waitForBtools(timeout)
	local elapsed = 0
	while elapsed < timeout do
		if hasBuildingTool() then return true end
		task.wait(0.5); elapsed += 0.5
	end
	return hasBuildingTool()
end

-- 4. F3X API WRAPPER (Full SyncAPI Coverage)
local F3X = {}
F3X._tool = nil
F3X._syncAPI = nil
F3X._serverEndpoint = nil

function F3X:Init()
	if self._serverEndpoint and self._serverEndpoint:FindFirstAncestorOfClass("DataModel") then return true end
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()
	local function findIn(container)
		if not container then return nil end
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then return item end
		end
		return nil
	end
	local tool = findIn(backpack) or findIn(char)
	if not tool then return false end
	self._tool = tool
	self._syncAPI = tool:WaitForChild("SyncAPI", 5)
	if not self._syncAPI then return false end
	self._serverEndpoint = self._syncAPI:WaitForChild("ServerEndpoint", 5)
	if not self._serverEndpoint then return false end
	dprint("F3X initialized:", tool.Name)
	return true
end

function F3X:Invoke(...)
	if not self:Init() then return nil end
	local args = {...}
	local ok, result = pcall(function() return self._serverEndpoint:InvokeServer(unpack(args)) end)
	if not ok then dprint("Invoke FAILED:", args[1], tostring(result)); return nil end
	return result
end

local function F3XRetry(method, ...)
	for retry = 1, 3 do
		local result = F3X[method](F3X, ...)
		if result ~= nil then return result end
		task.wait(0.2 * retry)
	end
	return nil
end

function F3X:ValidateTool()
	if not self:Init() then
		notify("F3X tool lost — re-equipping...")
		equipBuildingTool()
		task.wait(0.5)
		if not self:Init() then
			warn("F3X tool unavailable — build paused")
			return false
		end
	end
	return true
end

function F3X:CreatePart(partType, cframe)
	return self:Invoke("CreatePart", partType or "Normal", cframe or CFrame.new(0, 5000, 0), workspace)
end
function F3X:SyncMove(ch) return self:Invoke("SyncMove", ch) end
function F3X:SyncResize(ch) return self:Invoke("SyncResize", ch) end
function F3X:SyncColor(ch) return self:Invoke("SyncColor", ch) end
function F3X:SyncMaterial(ch) return self:Invoke("SyncMaterial", ch) end
function F3X:SyncSurface(ch) return self:Invoke("SyncSurface", ch) end
function F3X:SyncAnchor(ch) return self:Invoke("SyncAnchor", ch) end
function F3X:SyncCollision(ch) return self:Invoke("SyncCollision", ch) end
function F3X:SyncRotate(ch) return self:Invoke("SyncRotate", ch) end
function F3X:CreateMeshes(parts)
	local c = {}
	for _, p in ipairs(parts) do table.insert(c, {Part = p}) end
	return self:Invoke("CreateMeshes", c)
end
function F3X:SyncMesh(ch) return self:Invoke("SyncMesh", ch) end
function F3X:CreateTextures(ch) return self:Invoke("CreateTextures", ch) end
function F3X:SyncTexture(ch) return self:Invoke("SyncTexture", ch) end
function F3X:CreateLights(ch) return self:Invoke("CreateLights", ch) end
function F3X:SyncLighting(ch) return self:Invoke("SyncLighting", ch) end
function F3X:CreateDecorations(ch) return self:Invoke("CreateDecorations", ch) end
function F3X:SyncDecorate(ch) return self:Invoke("SyncDecorate", ch) end
function F3X:CreateWelds(parts, target) return self:Invoke("CreateWelds", parts, target) end
function F3X:RemoveWelds(w) return self:Invoke("RemoveWelds", w) end
function F3X:Remove(objects) return self:Invoke("Remove", objects) end
function F3X:Clone(items, p) return self:Invoke("Clone", items, p) end
function F3X:Ungroup(g) return self:Invoke("Ungroup", g) end
function F3X:SetParent(items, p)
	if typeof(items) ~= "table" then items = {items} end
	return self:Invoke("SetParent", items, p)
end
function F3X:SetName(items, n)
	if typeof(items) ~= "table" then items = {items} end
	return self:Invoke("SetName", items, n)
end
function F3X:CreateGroup(gtype, parent, items)
	return self:Invoke("CreateGroup", gtype or "Model", parent or workspace, items or {})
end
function F3X:SetLocked(items, locked)
	if typeof(items) ~= "table" then items = {items} end
	return self:Invoke("SetLocked", items, locked)
end

		
-- 4. DATA PARSERS
local function parseCFrame(data)
	if not data then return CFrame.new(0, 10, 0) end
	if typeof(data) == "CFrame" then return data end
	if typeof(data) == "table" then
		if #data >= 12 then return CFrame.new(unpack(data))
		elseif #data >= 3 then return CFrame.new(data[1], data[2], data[3]) end
		return CFrame.new(0, 10, 0)
	end
	if typeof(data) == "string" then
		local x, y, z = data:match("CFrame%.new%(([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)%)")
		if x and y and z then return CFrame.new(tonumber(x), tonumber(y), tonumber(z)) end
	end
	return CFrame.new(0, 10, 0)
end

local function getCFramePosition(data) return parseCFrame(data).Position end

local function parseVector3(data)
	if not data then return Vector3.new(1, 1, 1) end
	if typeof(data) == "Vector3" then return data end
	if typeof(data) == "table" and #data >= 3 then return Vector3.new(unpack(data)) end
	return Vector3.new(1, 1, 1)
end

local function parseColor3(data)
	if not data then return Color3.new(1, 1, 1) end
	if typeof(data) == "Color3" then return data end
	if typeof(data) == "table" and #data >= 3 then return Color3.fromRGB(unpack(data)) end
	return Color3.new(1, 1, 1)
end

local function parseEnum(enumType, str)
	if not str then return enumType:GetEnumItems()[1] end
	local enumName, itemName = str:match("Enum%.(%w+)%.(.+)")
	if enumName and itemName then
		local ok, enum = pcall(function() return Enum[enumName] end)
		if ok and enum then
			local ok2, item = pcall(function() return enum[itemName] end)
			if ok2 and item then return item end
		end
	end
	for _, e in ipairs(enumType:GetEnumItems()) do if e.Name == str then return e end end
	return enumType:GetEnumItems()[1]
end

local function parseMaterial(str) return parseEnum(Enum.Material, str) end
local function parseSurface(str) return parseEnum(Enum.SurfaceType, str) end
local function parseNormalId(str) return parseEnum(Enum.NormalId, str) end
local function parseMeshType(str) return parseEnum(Enum.MeshType, str) end
local function parseShape(str) return parseEnum(Enum.PartType, str) end

local function parseLightType(str)
	if not str then return "PointLight" end
	local name = str:match("Enum%.LightType%.(.+)") or str
	if name:find("Surface") then return "SurfaceLight"
	elseif name:find("Point") then return "PointLight"
	elseif name:find("Spot") then return "SpotLight" end
	return "PointLight"
end

local function parseDecoType(str)
	if not str then return "Smoke" end
	local name = str:match("Enum%.DecorationType%.(.+)") or str
	if name:find("Smoke") then return "Smoke"
	elseif name:find("Fire") then return "Fire"
	elseif name:find("Sparkles") then return "Sparkles" end
	return "Smoke"
end

local function getPartType(className)
	if className == "WedgePart" then return "Wedge"
	elseif className == "CornerWedgePart" then return "Corner"
	elseif className == "TrussPart" then return "Truss"
	elseif className == "Seat" then return "Seat"
	elseif className == "VehicleSeat" then return "Vehicle Seat"
	elseif className == "SpawnLocation" then return "Spawn"
	end
	return "Normal"
end

-- Format helpers for Lua export
local function fmtN(n)
	if n ~= n then return "0.0000" end
	if n == math.huge then return "math.huge" end
	if n == -math.huge then return "-math.huge" end
	return string.format("%.4f", n)
end
local function fmtV3(v) return string.format("Vector3.new(%s, %s, %s)", fmtN(v.X), fmtN(v.Y), fmtN(v.Z)) end
local function fmtC3(c) return string.format("Color3.fromRGB(%d,%d,%d)", math.floor(c.R*255+.5), math.floor(c.G*255+.5), math.floor(c.B*255+.5)) end
local function fmtCF(cf)
	local c = table.pack(cf:GetComponents())
	return string.format("CFrame.new(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
		fmtN(c[1]),fmtN(c[2]),fmtN(c[3]),fmtN(c[4]),fmtN(c[5]),fmtN(c[6]),
		fmtN(c[7]),fmtN(c[8]),fmtN(c[9]),fmtN(c[10]),fmtN(c[11]),fmtN(c[12]))
end
local function fmtVal(v)
	local t = typeof(v)
	if t == "number" then return fmtN(v)
	elseif t == "boolean" then return tostring(v)
	elseif t == "string" then return string.format("%q", v)
	elseif t == "Vector3" then return fmtV3(v)
	elseif t == "Color3" then return fmtC3(v)
	elseif t == "CFrame" then return fmtCF(v)
	elseif t == "EnumItem" then return tostring(v):gsub("Enum%.%w+%.", "")
	else return string.format("%q", tostring(v)) end
end

-- 5. UI SYSTEM (Modern Dark Theme)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "F3XBuildSystem"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 520, 0, 780)
mainFrame.Position = UDim2.new(0.5, -260, 0.5, -390)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(40, 40, 48)
mainStroke.Thickness = 1
mainStroke.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, -20, 1, 0)
titleText.Position = UDim2.new(0, 14, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "🏗️ F3X Build System"
titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
titleText.TextSize = 17
titleText.Font = Enum.Font.GothamBold
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Parent = titleBar

local selCountLabel = Instance.new("TextLabel")
selCountLabel.Size = UDim2.new(0, 100, 1, 0)
selCountLabel.Position = UDim2.new(1, -130, 0, 0)
selCountLabel.BackgroundTransparency = 1
selCountLabel.Text = "0 selected"
selCountLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
selCountLabel.TextSize = 12
selCountLabel.Font = Enum.Font.Gotham
selCountLabel.TextXAlignment = Enum.TextXAlignment.Right
selCountLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.Parent = titleBar
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

-- NOTIFICATION
local notif = Instance.new("Frame")
notif.Size = UDim2.new(0, 400, 0, 50)
notif.Position = UDim2.new(0.5, -200, 0, -70)
notif.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
notif.BorderSizePixel = 0
notif.ZIndex = 2000
notif.Parent = screenGui
Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 10)

local notifText = Instance.new("TextLabel")
notifText.Size = UDim2.new(1, -20, 1, 0)
notifText.Position = UDim2.new(0, 10, 0, 0)
notifText.BackgroundTransparency = 1
notifText.Text = ""
notifText.TextColor3 = Color3.fromRGB(255, 255, 255)
notifText.TextSize = 14
notifText.Font = Enum.Font.Gotham
notifText.TextWrapped = true
notifText.Parent = notif

local function notify(msg)
	notifText.Text = msg
	TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0.5, -200, 0, 28)}):Play()
	task.delay(3, function()
		TweenService:Create(notif, TweenInfo.new(0.3), {Position = UDim2.new(0.5, -200, 0, -70)}):Play()
	end)
end

-- Toggle button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 50, 0, 50)
toggleBtn.Position = UDim2.new(0, 20, 0, 20)
toggleBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
toggleBtn.Text = "🏗️"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 24
toggleBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(1, 0)
toggleBtn.Parent = screenGui
toggleBtn.MouseButton1Click:Connect(function() mainFrame.Visible = not mainFrame.Visible end)

-- MAIN TABS
local tabFrame = Instance.new("Frame")
tabFrame.Size = UDim2.new(1, -20, 0, 36)
tabFrame.Position = UDim2.new(0, 10, 0, 50)
tabFrame.BackgroundTransparency = 1
tabFrame.Parent = mainFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.Parent = tabFrame

local currentTab = "Builder"
local tabButtons = {}

local function makeTabBtn(text)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.33, -3, 1, 0)
	btn.BackgroundColor3 = text == "Builder" and Color3.fromRGB(0, 130, 220) or Color3.fromRGB(40, 40, 50)
	btn.Text = text == "Builder" and "📦 Builder" or text == "Selector" and "🎯 Selector" or "⚙️ Settings"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.Parent = tabFrame
	tabButtons[text] = btn
	return btn
end

makeTabBtn("Builder")
makeTabBtn("Selector")
makeTabBtn("Settings")

-- ==================== BUILDER TAB ====================
local BUILDER_CONTROLS_HEIGHT = 284
local builderFrame = Instance.new("Frame")
builderFrame.Size = UDim2.new(1, -20, 1, -90)
builderFrame.Position = UDim2.new(0, 10, 0, 90)
builderFrame.BackgroundTransparency = 1
builderFrame.Parent = mainFrame

local builderListFrame = Instance.new("Frame")
builderListFrame.Size = UDim2.new(1, 0, 1, -BUILDER_CONTROLS_HEIGHT)
builderListFrame.BackgroundTransparency = 1
builderListFrame.Parent = builderFrame

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 34)
tabBar.BackgroundTransparency = 1
tabBar.Parent = builderListFrame

local tabBarLayout = Instance.new("UIListLayout")
tabBarLayout.FillDirection = Enum.FillDirection.Horizontal
tabBarLayout.Padding = UDim.new(0, 4)
tabBarLayout.Parent = tabBar

local builderCurrentTab = "Local"
local builderTabBtns = {}

local function makeBuilderTab(text)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.5, -2, 1, 0)
	btn.BackgroundColor3 = text == "Local" and Color3.fromRGB(0, 130, 220) or Color3.fromRGB(40, 40, 50)
	btn.Text = text == "Local" and "📁 Local" or "🌐 GitHub"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 12
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.Parent = tabBar
	builderTabBtns[text] = btn
	return btn
end

makeBuilderTab("Local")
makeBuilderTab("GitHub")

local localFrame = Instance.new("Frame")
localFrame.Size = UDim2.new(1, 0, 1, -38)
localFrame.Position = UDim2.new(0, 0, 0, 38)
localFrame.BackgroundTransparency = 1
localFrame.Parent = builderListFrame

local githubFrame = Instance.new("Frame")
githubFrame.Size = UDim2.new(1, 0, 1, -38)
githubFrame.Position = UDim2.new(0, 0, 0, 38)
githubFrame.BackgroundTransparency = 1
githubFrame.Visible = false
githubFrame.Parent = builderListFrame

local refreshLocalBtn = Instance.new("TextButton")
refreshLocalBtn.Size = UDim2.new(1, 0, 0, 26)
refreshLocalBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
refreshLocalBtn.Text = "🔄 Refresh"
refreshLocalBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshLocalBtn.TextSize = 12
refreshLocalBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", refreshLocalBtn).CornerRadius = UDim.new(0, 6)
refreshLocalBtn.Parent = localFrame

local localScroll = Instance.new("ScrollingFrame")
localScroll.Size = UDim2.new(1, 0, 1, -30)
localScroll.Position = UDim2.new(0, 0, 0, 28)
localScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
localScroll.BorderSizePixel = 0
localScroll.ScrollBarThickness = 6
localScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
localScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", localScroll).CornerRadius = UDim.new(0, 6)
localScroll.Parent = localFrame

local localListLayout = Instance.new("UIListLayout")
localListLayout.Padding = UDim.new(0, 4)
localListLayout.Parent = localScroll

local githubInput = Instance.new("TextBox")
githubInput.Size = UDim2.new(1, 0, 0, 26)
githubInput.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
githubInput.Text = "UnAliveScripts/f3xbuildsjson"
githubInput.PlaceholderText = "user/repo"
githubInput.TextColor3 = Color3.fromRGB(255, 255, 255)
githubInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
githubInput.TextSize = 12
githubInput.Font = Enum.Font.Gotham
githubInput.ClearTextOnFocus = false
Instance.new("UICorner", githubInput).CornerRadius = UDim.new(0, 6)
githubInput.Parent = githubFrame

local fetchGithubBtn = Instance.new("TextButton")
fetchGithubBtn.Size = UDim2.new(1, 0, 0, 26)
fetchGithubBtn.Position = UDim2.new(0, 0, 0, 30)
fetchGithubBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 220)
fetchGithubBtn.Text = "🌐 Fetch"
fetchGithubBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
fetchGithubBtn.TextSize = 12
fetchGithubBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", fetchGithubBtn).CornerRadius = UDim.new(0, 6)
fetchGithubBtn.Parent = githubFrame

local githubScroll = Instance.new("ScrollingFrame")
githubScroll.Size = UDim2.new(1, 0, 1, -62)
githubScroll.Position = UDim2.new(0, 0, 0, 60)
githubScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
githubScroll.BorderSizePixel = 0
githubScroll.ScrollBarThickness = 6
githubScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
githubScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", githubScroll).CornerRadius = UDim.new(0, 6)
githubScroll.Parent = githubFrame

local githubListLayout = Instance.new("UIListLayout")
githubListLayout.Padding = UDim.new(0, 4)
githubListLayout.Parent = githubScroll

-- Build controls under builder list
local buildCtrlFrame = Instance.new("Frame")
buildCtrlFrame.Size = UDim2.new(1, 0, 0, 240)
buildCtrlFrame.Position = UDim2.new(0, 0, 1, -284)
buildCtrlFrame.BackgroundTransparency = 1
buildCtrlFrame.Parent = builderFrame

-- Toggles
local bToggleFrame = Instance.new("Frame")
bToggleFrame.Size = UDim2.new(1, 0, 0, 32)
bToggleFrame.BackgroundTransparency = 1
bToggleFrame.Parent = buildCtrlFrame

local bToggleLayout = Instance.new("UIListLayout")
bToggleLayout.FillDirection = Enum.FillDirection.Horizontal
bToggleLayout.Padding = UDim.new(0, 6)
bToggleLayout.Parent = bToggleFrame

local anchorToggleBtn = Instance.new("TextButton")
anchorToggleBtn.Size = UDim2.new(0.5, -2, 1, 0)
anchorToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
anchorToggleBtn.Text = "⚓ As Original"
anchorToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
anchorToggleBtn.TextSize = 11
anchorToggleBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", anchorToggleBtn).CornerRadius = UDim.new(0, 6)
anchorToggleBtn.Parent = bToggleFrame
anchorToggleBtn.MouseButton1Click:Connect(function()
	CONFIG.BuildAnchored = not CONFIG.BuildAnchored
	anchorToggleBtn.Text = CONFIG.BuildAnchored and "⚓ Fully Anchored" or "⚓ As Original"
	anchorToggleBtn.BackgroundColor3 = CONFIG.BuildAnchored and Color3.fromRGB(0, 130, 80) or Color3.fromRGB(60, 40, 80)
end)

local hyperToggleBtn = Instance.new("TextButton")
hyperToggleBtn.Size = UDim2.new(0.5, -2, 1, 0)
hyperToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
hyperToggleBtn.Text = "🚀 Normal Mode"
hyperToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
hyperToggleBtn.TextSize = 11
hyperToggleBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", hyperToggleBtn).CornerRadius = UDim.new(0, 6)
hyperToggleBtn.Parent = bToggleFrame
hyperToggleBtn.MouseButton1Click:Connect(function()
	CONFIG.HyperMode = not CONFIG.HyperMode
	hyperToggleBtn.Text = CONFIG.HyperMode and "🚀 HYPER MODE" or "🚀 Normal Mode"
	hyperToggleBtn.BackgroundColor3 = CONFIG.HyperMode and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(40, 40, 50)
	notify(CONFIG.HyperMode and "HYPER MODE enabled!" or "Normal mode enabled.")
end)

-- Second toggle row
local bToggleFrame2 = Instance.new("Frame")
bToggleFrame2.Size = UDim2.new(1, 0, 0, 28)
bToggleFrame2.Position = UDim2.new(0, 0, 0, 36)
bToggleFrame2.BackgroundTransparency = 1
bToggleFrame2.Parent = buildCtrlFrame

local bToggleLayout2 = Instance.new("UIListLayout")
bToggleLayout2.FillDirection = Enum.FillDirection.Horizontal
bToggleLayout2.Padding = UDim.new(0, 6)
bToggleLayout2.Parent = bToggleFrame2

local autoAnchorBtn = Instance.new("TextButton")
autoAnchorBtn.Size = UDim2.new(0.5, -2, 1, 0)
autoAnchorBtn.BackgroundColor3 = Color3.fromRGB(40, 50, 60)
autoAnchorBtn.Text = "🔗 Auto-Anchor: ON"
autoAnchorBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
autoAnchorBtn.TextSize = 11
autoAnchorBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", autoAnchorBtn).CornerRadius = UDim.new(0, 6)
autoAnchorBtn.Parent = bToggleFrame2
autoAnchorBtn.MouseButton1Click:Connect(function()
	CONFIG.BuildAnchored = not CONFIG.BuildAnchored
	autoAnchorBtn.Text = CONFIG.BuildAnchored and "🔗 Auto-Anchor: ON" or "🔗 Auto-Anchor: OFF"
	autoAnchorBtn.BackgroundColor3 = CONFIG.BuildAnchored and Color3.fromRGB(0, 130, 80) or Color3.fromRGB(40, 50, 60)
	anchorToggleBtn.Text = CONFIG.BuildAnchored and "⚓ Fully Anchored" or "⚓ As Original"
	anchorToggleBtn.BackgroundColor3 = CONFIG.BuildAnchored and Color3.fromRGB(0, 130, 80) or Color3.fromRGB(60, 40, 80)
end)

local saveCfgBtn = Instance.new("TextButton")
saveCfgBtn.Size = UDim2.new(0.5, -2, 1, 0)
saveCfgBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
saveCfgBtn.Text = "💾 Save Config"
saveCfgBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
saveCfgBtn.TextSize = 11
saveCfgBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", saveCfgBtn).CornerRadius = UDim.new(0, 6)
saveCfgBtn.Parent = bToggleFrame2
saveCfgBtn.MouseButton1Click:Connect(function()
	saveConfig()
	notify("Config saved!")
end)

-- Sliders
local slidersFrame = Instance.new("Frame")
slidersFrame.Size = UDim2.new(1, 0, 0, 126)
slidersFrame.Position = UDim2.new(0, 0, 0, 68)
slidersFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
slidersFrame.BorderSizePixel = 0
Instance.new("UICorner", slidersFrame).CornerRadius = UDim.new(0, 8)
slidersFrame.Parent = buildCtrlFrame

local slidersTitle = Instance.new("TextLabel")
slidersTitle.Size = UDim2.new(1, -10, 0, 14)
slidersTitle.Position = UDim2.new(0, 5, 0, 2)
slidersTitle.BackgroundTransparency = 1
slidersTitle.Text = "⚙️ Settings"
slidersTitle.TextColor3 = Color3.fromRGB(180, 180, 190)
slidersTitle.TextSize = 10
slidersTitle.Font = Enum.Font.GothamBold
slidersTitle.TextXAlignment = Enum.TextXAlignment.Left
slidersTitle.Parent = slidersFrame

local function makeSliderRow(frame, yOff, label, color, minVal, maxVal, defaultVal, formatStr, unit)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 50, 0, 16)
	lbl.Position = UDim2.new(0, 6, 0, yOff)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
	lbl.TextSize = 11
	lbl.Font = Enum.Font.Gotham
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = frame

	local valBox = Instance.new("TextBox")
	valBox.Size = UDim2.new(0, 60, 0, 18)
	valBox.Position = UDim2.new(0, 56, 0, yOff-1)
	valBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	valBox.Text = tostring(defaultVal)
	valBox.TextColor3 = color
	valBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
	valBox.TextSize = 11
	valBox.Font = Enum.Font.GothamBold
	valBox.ClearTextOnFocus = false
	Instance.new("UICorner", valBox).CornerRadius = UDim.new(0, 4)
	valBox.Parent = frame

	local unitLbl = Instance.new("TextLabel")
	unitLbl.Size = UDim2.new(0, 40, 0, 16)
	unitLbl.Position = UDim2.new(0, 118, 0, yOff)
	unitLbl.BackgroundTransparency = 1
	unitLbl.Text = unit
	unitLbl.TextColor3 = Color3.fromRGB(150, 150, 160)
	unitLbl.TextSize = 10
	unitLbl.Font = Enum.Font.Gotham
	unitLbl.TextXAlignment = Enum.TextXAlignment.Left
	unitLbl.Parent = frame

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, -130, 0, 6)
	bg.Position = UDim2.new(0, 125, 0, yOff+4)
	bg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	bg.BorderSizePixel = 0
	Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)
	bg.Parent = frame

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0.01, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = bg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("TextButton")
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.Position = UDim2.new(0.01, -7, 0.5, -7)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.Text = ""
	knob.Parent = bg
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local value = defaultVal
	local function updateFromSlider(ratio)
		ratio = math.clamp(ratio, 0, 1)
		value = minVal + (maxVal - minVal) * ratio
		if formatStr == "int" then value = math.floor(value + .5) end
		valBox.Text = tostring(value)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, -7, 0.5, -7)
	end

	local function updateFromValue(val)
		val = math.clamp(val, minVal, maxVal)
		if formatStr == "int" then val = math.floor(val + .5) end
		value = val
		valBox.Text = tostring(val)
		local ratio = (val - minVal) / (maxVal - minVal)
		fill.Size = UDim2.new(ratio, 0, 1, 0)
		knob.Position = UDim2.new(ratio, -7, 0.5, -7)
	end

	valBox.FocusLost:Connect(function()
		local v = tonumber(valBox.Text)
		if v then updateFromValue(v) else valBox.Text = tostring(value) end
	end)

	local dragging = false
	knob.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
	end)
	bg.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			local r = (i.Position.X - bg.AbsolutePosition.X) / bg.AbsoluteSize.X
			updateFromSlider(r)
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			local r = (i.Position.X - bg.AbsolutePosition.X) / bg.AbsoluteSize.X
			updateFromSlider(r)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)

	updateFromValue(defaultVal)
	return {Get = function() return value end, Set = updateFromValue}
end

local speedSlider = makeSliderRow(slidersFrame, 20, "Delay:", Color3.fromRGB(0, 200, 255), 0, 10, 0.005, "float", "sec")
local batchSlider = makeSliderRow(slidersFrame, 48, "Batch:", Color3.fromRGB(0, 255, 100), 1, 1000, 10, "int", "prts")
local threadSlider = makeSliderRow(slidersFrame, 76, "Thread:", Color3.fromRGB(255, 100, 50), 1, 32, 4, "int", "par")

-- Offset/Rotate/Scale controls
local offsetFrame = Instance.new("Frame")
offsetFrame.Size = UDim2.new(1, 0, 0, 42)
offsetFrame.Position = UDim2.new(0, 0, 1, -42)
offsetFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
offsetFrame.BorderSizePixel = 0
Instance.new("UICorner", offsetFrame).CornerRadius = UDim.new(0, 8)
offsetFrame.Parent = buildCtrlFrame

local offsetLabel = Instance.new("TextLabel")
offsetLabel.Size = UDim2.new(0, 28, 1, 0)
offsetLabel.Position = UDim2.new(0, 4, 0, 0)
offsetLabel.BackgroundTransparency = 1
offsetLabel.Text = "XYZ:"
offsetLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
offsetLabel.TextSize = 10
offsetLabel.Font = Enum.Font.GothamBold
offsetLabel.TextXAlignment = Enum.TextXAlignment.Left
offsetLabel.Parent = offsetFrame

local offsetBoxes = {}
for _, axis in ipairs({"X", "Y", "Z"}) do
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 42, 0, 18)
	box.Position = UDim2.new(0, #axis == 1 and 32 or (#axis == 2 and 78 or 124), 0.5, -9)
	box.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	box.Text = "0"
	box.TextColor3 = Color3.fromRGB(200, 200, 210)
	box.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
	box.TextSize = 10
	box.Font = Enum.Font.GothamBold
	box.ClearTextOnFocus = false
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
	box.Parent = offsetFrame
	offsetBoxes[axis] = box
end

local rot90Btn = Instance.new("TextButton")
rot90Btn.Size = UDim2.new(0, 28, 0, 22)
rot90Btn.Position = UDim2.new(0, 172, 0.5, -11)
rot90Btn.BackgroundColor3 = Color3.fromRGB(40, 50, 60)
rot90Btn.Text = "↻"
rot90Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
rot90Btn.TextSize = 12
rot90Btn.Font = Enum.Font.GothamBold
Instance.new("UICorner", rot90Btn).CornerRadius = UDim.new(0, 4)
rot90Btn.Parent = offsetFrame

local scaleBox = Instance.new("TextBox")
scaleBox.Size = UDim2.new(0, 50, 0, 18)
scaleBox.Position = UDim2.new(0, 206, 0.5, -9)
scaleBox.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
scaleBox.Text = "1.0"
scaleBox.TextColor3 = Color3.fromRGB(200, 200, 210)
scaleBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
scaleBox.TextSize = 10
scaleBox.Font = Enum.Font.GothamBold
scaleBox.ClearTextOnFocus = false
Instance.new("UICorner", scaleBox).CornerRadius = UDim.new(0, 4)
scaleBox.Parent = offsetFrame

local scaleLabel = Instance.new("TextLabel")
scaleLabel.Size = UDim2.new(0, 20, 1, 0)
scaleLabel.Position = UDim2.new(0, 260, 0, 0)
scaleLabel.BackgroundTransparency = 1
scaleLabel.Text = "×"
scaleLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
scaleLabel.TextSize = 10
scaleLabel.Font = Enum.Font.Gotham
scaleLabel.TextXAlignment = Enum.TextXAlignment.Left
scaleLabel.Parent = offsetFrame

CONFIG.BuildOffset = Vector3.new(0, 0, 0)
CONFIG.BuildScale = 1
CONFIG.BuildRot90 = 0

local function updateOffset()
	local x = tonumber(offsetBoxes.X.Text) or 0
	local y = tonumber(offsetBoxes.Y.Text) or 0
	local z = tonumber(offsetBoxes.Z.Text) or 0
	CONFIG.BuildOffset = Vector3.new(x, y, z)
end
for _, axis in ipairs({"X", "Y", "Z"}) do
	offsetBoxes[axis].FocusLost:Connect(function()
		updateOffset()
	end)
end

rot90Btn.MouseButton1Click:Connect(function()
	CONFIG.BuildRot90 = (CONFIG.BuildRot90 + 90) % 360
	rot90Btn.Text = CONFIG.BuildRot90 == 0 and "↻" or string.format("↻%d°", CONFIG.BuildRot90)
	notify("Rotation: " .. CONFIG.BuildRot90 .. "°")
end)

scaleBox.FocusLost:Connect(function()
	local v = tonumber(scaleBox.Text)
	if v and v >= 0.1 and v <= 10 then
		CONFIG.BuildScale = v
	else
		scaleBox.Text = tostring(CONFIG.BuildScale)
	end
end)

local buildBtn = Instance.new("TextButton")
buildBtn.Size = UDim2.new(0.48, -2, 0, 40)
buildBtn.Position = UDim2.new(0, 0, 1, -44)
buildBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
buildBtn.Text = "🔨 Build"
buildBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
buildBtn.TextSize = 15
buildBtn.Font = Enum.Font.GothamBold
buildBtn.Visible = false
Instance.new("UICorner", buildBtn).CornerRadius = UDim.new(0, 8)
buildBtn.Parent = builderFrame

local queueBtn = Instance.new("TextButton")
queueBtn.Size = UDim2.new(0.48, -2, 0, 40)
queueBtn.Position = UDim2.new(0.52, 4, 1, -44)
queueBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
queueBtn.Text = "📋 Queue"
queueBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
queueBtn.TextSize = 15
queueBtn.Font = Enum.Font.GothamBold
queueBtn.Visible = false
Instance.new("UICorner", queueBtn).CornerRadius = UDim.new(0, 8)
queueBtn.Parent = builderFrame

local buildAllBtn = Instance.new("TextButton")
buildAllBtn.Size = UDim2.new(1, 0, 0, 36)
buildAllBtn.Position = UDim2.new(0, 0, 1, -88)
buildAllBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 0)
buildAllBtn.Text = "▶️ Build All (%d in queue)"
buildAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
buildAllBtn.TextSize = 12
buildAllBtn.Font = Enum.Font.GothamBold
buildAllBtn.Visible = false
Instance.new("UICorner", buildAllBtn).CornerRadius = UDim.new(0, 8)
buildAllBtn.Parent = builderFrame

local function refreshQueueUI()
	buildAllBtn.Text = string.format("▶️ Build All (%d in queue)", #buildQueue)
end

-- ==================== SELECTOR TAB ====================
local selectorFrame = Instance.new("Frame")
selectorFrame.Size = UDim2.new(1, -20, 1, -90)
selectorFrame.Position = UDim2.new(0, 10, 0, 90)
selectorFrame.BackgroundTransparency = 1
selectorFrame.Visible = false
selectorFrame.Parent = mainFrame

local selectorStatus = Instance.new("TextLabel")
selectorStatus.Size = UDim2.new(1, 0, 0, 20)
selectorStatus.Position = UDim2.new(0, 0, 0, 0)
selectorStatus.BackgroundTransparency = 1
selectorStatus.Text = "🖱️ Click empty space & drag to select"
selectorStatus.TextColor3 = Color3.fromRGB(140, 140, 150)
selectorStatus.TextSize = 12
selectorStatus.Font = Enum.Font.Gotham
selectorStatus.TextXAlignment = Enum.TextXAlignment.Left
selectorStatus.Parent = selectorFrame

local selScroll = Instance.new("ScrollingFrame")
selScroll.Size = UDim2.new(1, 0, 1, -188)
selScroll.Position = UDim2.new(0, 0, 0, 24)
selScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
selScroll.BorderSizePixel = 0
selScroll.ScrollBarThickness = 6
selScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
selScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", selScroll).CornerRadius = UDim.new(0, 8)
selScroll.Parent = selectorFrame

local selListLayout = Instance.new("UIListLayout")
selListLayout.Padding = UDim.new(0, 3)
selListLayout.Parent = selScroll

local selToggleFrame = Instance.new("Frame")
selToggleFrame.Size = UDim2.new(1, 0, 0, 78)
selToggleFrame.Position = UDim2.new(0, 0, 1, -160)
selToggleFrame.BackgroundTransparency = 1
selToggleFrame.Parent = selectorFrame

local selToggleLayout = Instance.new("UIGridLayout")
selToggleLayout.CellSize = UDim2.new(0.5, -2, 0, 22)
selToggleLayout.CellPadding = UDim2.new(0, 4, 0, 4)
selToggleLayout.FillDirection = Enum.FillDirection.Horizontal
selToggleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
selToggleLayout.Parent = selToggleFrame

local selToggles = {}

local function makeSelToggle(text, default)
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0.5, -2, 0, 22)
	f.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	f.BorderSizePixel = 0
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
	f.Parent = selToggleFrame

	local c = Instance.new("Frame")
	c.Size = UDim2.new(0, 14, 0, 14)
	c.Position = UDim2.new(0, 6, 0.5, -7)
	c.BackgroundColor3 = default and CONFIG.SelectionColor or Color3.fromRGB(80, 80, 90)
	c.BorderSizePixel = 0
	Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
	c.Parent = f

	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -26, 1, 0)
	l.Position = UDim2.new(0, 24, 0, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(180, 180, 190)
	l.TextSize = 10
	l.Font = Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = f

	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 1, 0)
	b.BackgroundTransparency = 1
	b.Text = ""
	b.Parent = f

	local state = default
	b.MouseButton1Click:Connect(function()
		state = not state
		TweenService:Create(c, TweenInfo.new(0.2), {BackgroundColor3 = state and CONFIG.SelectionColor or Color3.fromRGB(80, 80, 90)}):Play()
	end)
	return {Get = function() return state end}
end

selToggles.Hierarchy = makeSelToggle("Preserve Hierarchy", true)
selToggles.Welds = makeSelToggle("Include Welds", true)
selToggles.Decals = makeSelToggle("Include Decals", true)
selToggles.Meshes = makeSelToggle("Include Meshes", true)
selToggles.Lights = makeSelToggle("Include Lights", true)

local selBtnFrame = Instance.new("Frame")
selBtnFrame.Size = UDim2.new(1, 0, 0, 78)
selBtnFrame.Position = UDim2.new(0, 0, 1, -78)
selBtnFrame.BackgroundTransparency = 1
selBtnFrame.Parent = selectorFrame

local selBtnLayout = Instance.new("UIListLayout")
selBtnLayout.FillDirection = Enum.FillDirection.Vertical
selBtnLayout.Padding = UDim.new(0, 4)
selBtnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
selBtnLayout.Parent = selBtnFrame

local toggleSelBtn = Instance.new("TextButton")
toggleSelBtn.Size = UDim2.new(1, 0, 0, 22)
toggleSelBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 80)
toggleSelBtn.Text = "🔵 Selection: ON"
toggleSelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleSelBtn.TextSize = 11
toggleSelBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", toggleSelBtn).CornerRadius = UDim.new(0, 6)
toggleSelBtn.Parent = selBtnFrame

local exportRow = Instance.new("Frame")
exportRow.Size = UDim2.new(1, 0, 0, 22)
exportRow.BackgroundTransparency = 1
exportRow.Parent = selBtnFrame

local exportF3XBtn = Instance.new("TextButton")
exportF3XBtn.Size = UDim2.new(0.5, -2, 1, 0)
exportF3XBtn.Position = UDim2.new(0, 0, 0, 0)
exportF3XBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 220)
exportF3XBtn.Text = "📋 Export JSON"
exportF3XBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
exportF3XBtn.TextSize = 11
exportF3XBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", exportF3XBtn).CornerRadius = UDim.new(0, 6)
exportF3XBtn.Parent = exportRow

local exportLuaBtn = Instance.new("TextButton")
exportLuaBtn.Size = UDim2.new(0.5, -2, 1, 0)
exportLuaBtn.Position = UDim2.new(0.5, 2, 0, 0)
exportLuaBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
exportLuaBtn.Text = "📄 Export Lua"
exportLuaBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
exportLuaBtn.TextSize = 11
exportLuaBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", exportLuaBtn).CornerRadius = UDim.new(0, 6)
exportLuaBtn.Parent = exportRow

local clearSelBtn = Instance.new("TextButton")
clearSelBtn.Size = UDim2.new(0.5, -2, 0, 22)
clearSelBtn.Position = UDim2.new(0.25, 1, 0, 0)
clearSelBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
clearSelBtn.Text = "❌ Clear"
clearSelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
clearSelBtn.TextSize = 11
clearSelBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", clearSelBtn).CornerRadius = UDim.new(0, 6)
clearSelBtn.Parent = selBtnFrame

-- ==================== SETTINGS TAB ====================
local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(1, -20, 1, -90)
settingsFrame.Position = UDim2.new(0, 10, 0, 90)
settingsFrame.BackgroundTransparency = 1
settingsFrame.Visible = false
settingsFrame.Parent = mainFrame

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, 0, 0, 24)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Text = "Build History"
settingsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
settingsTitle.TextSize = 14
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextXAlignment = Enum.TextXAlignment.Left
settingsTitle.Parent = settingsFrame

local historyScroll = Instance.new("ScrollingFrame")
historyScroll.Size = UDim2.new(1, 0, 1, -28)
historyScroll.Position = UDim2.new(0, 0, 0, 28)
historyScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
historyScroll.BorderSizePixel = 0
historyScroll.ScrollBarThickness = 6
historyScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 90)
historyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", historyScroll).CornerRadius = UDim.new(0, 8)
historyScroll.Parent = settingsFrame

local historyListLayout = Instance.new("UIListLayout")
historyListLayout.Padding = UDim.new(0, 4)
historyListLayout.Parent = historyScroll

-- Tab switching
local function switchTab(tab)
	for t, btn in pairs(tabButtons) do
		btn.BackgroundColor3 = t == tab and Color3.fromRGB(0, 130, 220) or Color3.fromRGB(40, 40, 50)
	end
	builderFrame.Visible = tab == "Builder"
	selectorFrame.Visible = tab == "Selector"
	settingsFrame.Visible = tab == "Settings"
	currentTab = tab
	if tab == "Selector" then updateSelCount() end
end

tabButtons.Builder.MouseButton1Click:Connect(function() switchTab("Builder") end)
tabButtons.Selector.MouseButton1Click:Connect(function() switchTab("Selector") end)
tabButtons.Settings.MouseButton1Click:Connect(function() switchTab("Settings") end)

local function switchBuilderTab(tab)
	for t, btn in pairs(builderTabBtns) do
		btn.BackgroundColor3 = t == tab and Color3.fromRGB(0, 130, 220) or Color3.fromRGB(40, 40, 50)
	end
	localFrame.Visible = tab == "Local"
	githubFrame.Visible = tab == "GitHub"
	builderCurrentTab = tab
end

builderTabBtns.Local.MouseButton1Click:Connect(function() switchBuilderTab("Local") end)
builderTabBtns.GitHub.MouseButton1Click:Connect(function() switchBuilderTab("GitHub") end)

-- Draggable UI
local draggingUI = false
local uiDragStart = nil
local uiStartPos = nil

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		draggingUI = true
		uiDragStart = Vector2.new(input.Position.X, input.Position.Y)
		uiStartPos = mainFrame.Position
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if draggingUI and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = Vector2.new(input.Position.X, input.Position.Y) - uiDragStart
		mainFrame.Position = UDim2.new(uiStartPos.X.Scale, uiStartPos.X.Offset + delta.X, uiStartPos.Y.Scale, uiStartPos.Y.Offset + delta.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingUI = false end
end)

-- Progress bar (shared)
local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(1, -20, 0, 4)
progressFrame.Position = UDim2.new(0, 10, 1, -44)
progressFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
progressFrame.BorderSizePixel = 0
progressFrame.Visible = false
progressFrame.Parent = mainFrame
Instance.new("UICorner", progressFrame).CornerRadius = UDim.new(1, 0)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
progressFill.BorderSizePixel = 0
progressFill.Parent = progressFrame
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 18)
statusLabel.Position = UDim2.new(0, 10, 1, -38)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Ready"
statusLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham
statusLabel.Parent = mainFrame

-- 6. SELECTION SYSTEM
local selectedParts = {}
local selectedSet = {}
local selectionBoxes = {}
local isDragging = false
local dragStartPos = nil
local dragCurrentPos = nil
local clickMode = false
local clickTarget = nil
local mouseDownPos = nil
local exportInProgress = false
local selectionEnabled = true

local marquee = Instance.new("Frame")
marquee.BackgroundColor3 = CONFIG.SelectionColor
marquee.BackgroundTransparency = CONFIG.BoxFillTransparency
marquee.BorderSizePixel = 0
marquee.Visible = false
marquee.ZIndex = 1000
marquee.Parent = screenGui
Instance.new("UIStroke", marquee).Color = CONFIG.SelectionColor
Instance.new("UIStroke", marquee).Thickness = 2

local listItemPool = {}
local listItemUsed = 0

local function getListItem()
	listItemUsed += 1
	if listItemPool[listItemUsed] then
		listItemPool[listItemUsed].Frame.Visible = true
		return listItemPool[listItemUsed]
	end
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 22)
	row.BackgroundTransparency = 1
	row.Parent = selScroll

	local dot = Instance.new("TextLabel")
	dot.Size = UDim2.new(0, 18, 1, 0)
	dot.BackgroundTransparency = 1
	dot.Text = "•"
	dot.TextColor3 = CONFIG.SelectionColor
	dot.TextSize = 12
	dot.Font = Enum.Font.GothamBold
	dot.Parent = row

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -22, 1, 0)
	label.Position = UDim2.new(0, 18, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(200, 200, 210)
	label.TextSize = 11
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = row

	local item = {Frame = row, Label = label}
	listItemPool[listItemUsed] = item
	return item
end

local function resetListPool()
	for i = 1, listItemUsed do
		if listItemPool[i] then listItemPool[i].Frame.Visible = false; listItemPool[i].Label.Text = "" end
	end
	listItemUsed = 0
end

local function addSelListItem(name, class)
	if listItemUsed >= CONFIG.ListCap then
		if listItemUsed == CONFIG.ListCap then
			local item = getListItem()
			item.Label.Text = string.format("... and %d more parts", #selectedParts - CONFIG.ListCap)
		end
		return
	end
	local item = getListItem()
	item.Label.Text = string.format("%s (%s)", name, class)
end

local function refreshSelList()
	resetListPool()
	for _, p in ipairs(selectedParts) do addSelListItem(p.Name, p.ClassName) end
end

local function updateSelCount()
	selCountLabel.Text = string.format("%d selected", #selectedParts)
end

local function setVisual(part, enabled)
	if enabled then
		if #selectionBoxes >= CONFIG.VisualLimit then return end
		if selectionBoxes[part] then return end
		local box = Instance.new("SelectionBox")
		box.Name = "BuildSelBox"
		box.Color3 = CONFIG.SelectionColor
		box.LineThickness = 0.04
		box.Adornee = part
		box.Parent = part
		selectionBoxes[part] = box
	else
		if selectionBoxes[part] then selectionBoxes[part]:Destroy(); selectionBoxes[part] = nil end
	end
end

local function clearSelection()
	for part, box in pairs(selectionBoxes) do
		if box then pcall(function() box:Destroy() end) end
	end
	selectedParts = {}; selectedSet = {}; selectionBoxes = {}
	updateSelCount(); resetListPool()
end

local function addPart(part)
	if #selectedParts >= CONFIG.MaxParts then return end
	if selectedSet[part] then return end
	selectedParts[#selectedParts + 1] = part
	selectedSet[part] = true
	setVisual(part, true)
	addSelListItem(part.Name, part.ClassName)
	updateSelCount()
end

local function removePart(part)
	if not selectedSet[part] then return end
	selectedSet[part] = nil
	local idx = nil; for i = 1, #selectedParts do if selectedParts[i] == part then idx = i; break end end
	if idx then table.remove(selectedParts, idx) end
	setVisual(part, false)
	updateSelCount()
	refreshSelList()
end

local function isOverGui()
	local ok, objs = pcall(function() return player:WaitForChild("PlayerGui"):GetGuiObjectsAtPosition(getMouseX(), getMouseY()) end)
	if ok and objs then
		for _, obj in ipairs(objs) do
			if obj:IsDescendantOf(mainFrame) or obj:IsDescendantOf(notif) then return true end
		end
	end
	return false
end

local function getPartUnderMouse()
	local ray = camera:ViewportPointToRay(getMouseX(), getMouseY())
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = {player.Character or Instance.new("Model")}
	local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if result and result.Instance then
		local obj = result.Instance
		while obj and not obj:IsA("BasePart") do obj = obj.Parent end
		return obj
	end
	return nil
end

local function partInMarquee(part, startPos, endPos)
	local minX, maxX = math.min(startPos.X, endPos.X), math.max(startPos.X, endPos.X)
	local minY, maxY = math.min(startPos.Y, endPos.Y), math.max(startPos.Y, endPos.Y)
	local center, onScreen = camera:WorldToViewportPoint(part.Position)
	if onScreen and center.X >= minX and center.X <= maxX and center.Y >= minY and center.Y <= maxY then return true end
	local size = part.Size / 2
	local cf = part.CFrame
	for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
		local corner = cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
		local sp, vis = camera:WorldToViewportPoint(corner)
		if vis and sp.X >= minX and sp.X <= maxX and sp.Y >= minY and sp.Y <= maxY then return true end
	end end end
	return false
end

toggleSelBtn.MouseButton1Click:Connect(function()
	selectionEnabled = not selectionEnabled
	toggleSelBtn.Text = selectionEnabled and "🟢 Selection: ON" or "🔴 Selection: OFF"
	toggleSelBtn.BackgroundColor3 = selectionEnabled and Color3.fromRGB(0, 130, 80) or Color3.fromRGB(60, 60, 70)
	selectorStatus.Text = selectionEnabled and "🖱️ Click empty space & drag to select" or "❌ Selection disabled"
	if not selectionEnabled then
		isDragging = false; marquee.Visible = false; clickMode = false
		clickTarget = nil; mouseDownPos = nil; dragStartPos = nil; dragCurrentPos = nil
	end
end)

UserInputService.InputBegan:Connect(function(input, gpe)
	if not selectionEnabled or gpe or input.UserInputType ~= Enum.UserInputType.MouseButton1 or exportInProgress then return end
	if currentTab ~= "Selector" then return end
	if isOverGui() then return end

	local mx, my = getMouseX(), getMouseY()
	mouseDownPos = Vector2.new(mx, my)
	dragStartPos = mouseDownPos; dragCurrentPos = mouseDownPos
	isDragging = true
	clickTarget = getPartUnderMouse()
	clickMode = clickTarget ~= nil
	if not clickMode then
		marquee.Position = UDim2.new(0, mx, 0, my)
		marquee.Size = UDim2.new(0, 0, 0, 0)
		marquee.Visible = true
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not selectionEnabled or not isDragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	dragCurrentPos = Vector2.new(getMouseX(), getMouseY())
	local dist = (dragCurrentPos - mouseDownPos).Magnitude
	if clickMode and dist > CONFIG.DragThreshold then
		clickMode = false; clickTarget = nil
		marquee.Position = UDim2.new(0, mouseDownPos.X, 0, mouseDownPos.Y)
		marquee.Size = UDim2.new(0, 0, 0, 0); marquee.Visible = true
	end
	if not clickMode then
		local minX = math.min(dragStartPos.X, dragCurrentPos.X)
		local minY = math.min(dragStartPos.Y, dragCurrentPos.Y)
		local maxX = math.max(dragStartPos.X, dragCurrentPos.X)
		local maxY = math.max(dragStartPos.Y, dragCurrentPos.Y)
		marquee.Position = UDim2.new(0, minX, 0, minY)
		marquee.Size = UDim2.new(0, maxX - minX, 0, maxY - minY)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not selectionEnabled or input.UserInputType ~= Enum.UserInputType.MouseButton1 or not isDragging then return end
	isDragging = false; marquee.Visible = false
	local dist = (dragCurrentPos - mouseDownPos).Magnitude
	local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

	if clickMode and dist <= CONFIG.DragThreshold then
		if clickTarget then
			if ctrlHeld then
				if selectedSet[clickTarget] then removePart(clickTarget) else addPart(clickTarget) end
			else
				if not selectedSet[clickTarget] then clearSelection(); addPart(clickTarget) end
			end
			selectorStatus.Text = string.format("Selected: %s", clickTarget.Name)
		end
	elseif not clickMode and dist > CONFIG.DragThreshold then
		if not ctrlHeld then clearSelection() end
		local found = 0
		local char = player.Character
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("BasePart") and not obj:IsDescendantOf(char or Instance.new("Model")) then
				if partInMarquee(obj, dragStartPos, dragCurrentPos) then
					addPart(obj); found += 1
					if found >= CONFIG.MaxParts then break end
				end
			end
		end
		selectorStatus.Text = string.format("Box-selected %d parts", found)
	elseif not clickMode and dist <= CONFIG.DragThreshold then
		if not ctrlHeld then clearSelection() end
	end
	clickMode = false; clickTarget = nil; mouseDownPos = nil; dragStartPos = nil; dragCurrentPos = nil
end)

clearSelBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function() clearSelection(); notify("Selection cleared") end) if not ok then warn("[F3X] Error:", err) end end)

-- 7. BUILD AUTOMATION (btools, equip, teleport)
local function calculateBuildCenter(parts)
	if not parts or #parts == 0 then return Vector3.new(0, 50, 0) end
	local sx, sy, sz, cnt = 0, 0, 0, 0
	for _, pd in ipairs(parts) do
		local pos = getCFramePosition(pd.CFrame)
		sx += pos.X; sy += pos.Y; sz += pos.Z; cnt += 1
	end
	if cnt == 0 then return Vector3.new(0, 50, 0) end
	return Vector3.new(sx / cnt, sy / cnt, sz / cnt)
end

local function teleportToBuild(target)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local tp = target + Vector3.new(0, 30, 0)
	hrp.CFrame = CFrame.new(tp)
	workspace.CurrentCamera.CFrame = CFrame.new(tp, target)
end

-- 8. PROPERTY APPLIER
local function applyPartProperties(part, partData, targetCF, partMap)
	local szC, colC, matC, surfC, ancC, collC, rotC = {}, {}, {}, {}, {}, {}, {}
	if partData.Size then
		local sz = parseVector3(partData.Size)
		if CONFIG.BuildScale and CONFIG.BuildScale ~= 1 then
			sz = sz * CONFIG.BuildScale
		end
		table.insert(szC, {Part = part, Size = sz})
	end
	if partData.Color then table.insert(colC, {Part = part, Color = parseColor3(partData.Color)}) end
	local md = {Part = part}
	if partData.Material then md.Material = parseMaterial(partData.Material) end
	if partData.Transparency ~= nil then md.Transparency = partData.Transparency end
	if partData.Reflectance ~= nil then md.Reflectance = partData.Reflectance end
	if next(md) then table.insert(matC, md) end
	table.insert(ancC, {Part = part, Anchored = CONFIG.BuildAnchored or (partData.Anchored == true)})
	if partData.CanCollide ~= nil then table.insert(collC, {Part = part, CanCollide = partData.CanCollide}) end
	local surfs = {}
	if partData.TopSurface then surfs.Top = parseSurface(partData.TopSurface) end
	if partData.BottomSurface then surfs.Bottom = parseSurface(partData.BottomSurface) end
	if partData.LeftSurface then surfs.Left = parseSurface(partData.LeftSurface) end
	if partData.RightSurface then surfs.Right = parseSurface(partData.RightSurface) end
	if partData.FrontSurface then surfs.Front = parseSurface(partData.FrontSurface) end
	if partData.BackSurface then surfs.Back = parseSurface(partData.BackSurface) end
	if next(surfs) then table.insert(surfC, {Part = part, Surfaces = surfs}) end
	if partData.Orientation then
		local ori = parseVector3(partData.Orientation)
		table.insert(rotC, {Part = part, CFrame = targetCF * CFrame.Angles(math.rad(ori.X), math.rad(ori.Y), math.rad(ori.Z))})
	elseif CONFIG.BuildRot90 ~= 0 then
		table.insert(rotC, {Part = part, CFrame = targetCF * CFrame.Angles(0, math.rad(CONFIG.BuildRot90), 0)})
	end

	pcall(function() if #szC > 0 then F3XRetry("SyncResize", szC) end end)
	pcall(function() if #colC > 0 then F3XRetry("SyncColor", colC) end end)
	pcall(function() if #matC > 0 then F3XRetry("SyncMaterial", matC) end end)
	pcall(function() if #surfC > 0 then F3XRetry("SyncSurface", surfC) end end)
	pcall(function() if #ancC > 0 then F3XRetry("SyncAnchor", ancC) end end)
	pcall(function() if #collC > 0 then F3XRetry("SyncCollision", collC) end end)
	pcall(function() if #rotC > 0 then F3XRetry("SyncRotate", rotC) end end)

	if partData.Name or partData.Locked ~= nil then
		local nameBatch = {}
		local lockBatch = {}
		if partData.Name then table.insert(nameBatch, part) end
		if partData.Locked ~= nil then table.insert(lockBatch, {Part = part, Locked = partData.Locked}) end
		if #nameBatch > 0 then pcall(function() F3XRetry("SetName", nameBatch, partData.Name) end) end
		if #lockBatch > 0 then pcall(function() F3XRetry("SetLocked", lockBatch) end) end
	end

	if partData.CastShadow ~= nil then part.CastShadow = partData.CastShadow end
	if partData.Shape then pcall(function() part.Shape = parseShape(partData.Shape) end) end
	if partData.Massless ~= nil then part.Massless = partData.Massless end
	if partData.CollisionGroupId then part.CollisionGroupId = partData.CollisionGroupId end

	if partData.CustomPhysicalProperties then
		local cpp = partData.CustomPhysicalProperties
		pcall(function() part.CustomPhysicalProperties = PhysicalProperties.new(cpp.Density or .7, cpp.Friction or .3, cpp.Elasticity or .5, cpp.FrictionWeight or 1, cpp.ElasticityWeight or 1) end)
	end

	local function isValidAssetUrl(url)
		if not url or url == "" then return false end
		if type(url) ~= "string" then return false end
		if url:find("^rbxasset") then return true end
		if url:find("^https?://") then return true end
		return false
	end

	local cn = partData.ClassName or "Part"
	if cn == "MeshPart" and (isValidAssetUrl(partData.MeshId) or isValidAssetUrl(partData.TextureID) or partData.RenderFidelity) then
		pcall(function()
			F3XRetry("CreateMeshes", {part})
			local mc = {Part = part}
			if isValidAssetUrl(partData.MeshId) then mc.MeshId = partData.MeshId end
			if isValidAssetUrl(partData.TextureID) then mc.TextureId = partData.TextureID end
			if partData.RenderFidelity then mc.RenderFidelity = partData.RenderFidelity end
			if partData.CollisionFidelity then mc.CollisionFidelity = partData.CollisionFidelity end
			F3XRetry("SyncMesh", {mc})
		end)
	end

	if partData.Children then
		for _, cd in ipairs(partData.Children) do
			pcall(function()
				if cd.ClassName == "Decal" or cd.ClassName == "Texture" then
					if not isValidAssetUrl(cd.Texture) then return end
					F3XRetry("CreateTextures", {{Part = part, Face = parseNormalId(cd.Face), TextureType = cd.ClassName}})
					local tc = {Part = part, Face = parseNormalId(cd.Face), TextureType = cd.ClassName, Texture = cd.Texture}
					if cd.Transparency ~= nil then tc.Transparency = cd.Transparency end
					F3XRetry("SyncTexture", {tc})
				elseif cd.ClassName == "SpecialMesh" then
					if not isValidAssetUrl(cd.MeshId) and not isValidAssetUrl(cd.TextureId) and not cd.MeshType then return end
					F3XRetry("CreateMeshes", {part})
					local mc = {Part = part}
					if cd.MeshType then mc.MeshType = parseMeshType(cd.MeshType) end
					if isValidAssetUrl(cd.MeshId) then mc.MeshId = cd.MeshId end
					if isValidAssetUrl(cd.TextureId) then mc.TextureId = cd.TextureId end
					if cd.Scale then mc.Scale = parseVector3(cd.Scale) end
					if cd.Offset then mc.Offset = parseVector3(cd.Offset) end
					F3XRetry("SyncMesh", {mc})
				elseif cd.ClassName == "BlockMesh" or cd.ClassName == "CylinderMesh" then
					F3XRetry("CreateMeshes", {part})
					local mc = {Part = part, MeshType = cd.ClassName == "BlockMesh" and Enum.MeshType.Brick or Enum.MeshType.Cylinder}
					if cd.Scale then mc.Scale = parseVector3(cd.Scale) end
					if cd.Offset then mc.Offset = parseVector3(cd.Offset) end
					F3XRetry("SyncMesh", {mc})
				elseif cd.ClassName == "SurfaceLight" or cd.ClassName == "PointLight" or cd.ClassName == "SpotLight" then
					F3XRetry("CreateLights", {{Part = part, LightType = cd.ClassName}})
					local lc = {Part = part, LightType = cd.ClassName}
					if cd.Color then lc.Color = parseColor3(cd.Color) end
					if cd.Brightness ~= nil then lc.Brightness = cd.Brightness end
					if cd.Range ~= nil then lc.Range = cd.Range end
					if cd.Shadows ~= nil then lc.Shadows = cd.Shadows end
					if cd.Face then lc.Face = parseNormalId(cd.Face) end
					if cd.Angle ~= nil then lc.Angle = cd.Angle end
					F3XRetry("SyncLighting", {lc})
				elseif cd.ClassName == "Smoke" or cd.ClassName == "Fire" or cd.ClassName == "Sparkles" then
					F3XRetry("CreateDecorations", {{Part = part, DecorationType = cd.ClassName}})
					local dc = {Part = part, DecorationType = cd.ClassName}
					if cd.Color then dc.Color = parseColor3(cd.Color) end
					if cd.Size ~= nil then dc.Size = cd.Size end
					if cd.Opacity ~= nil then dc.Opacity = cd.Opacity end
					if cd.RiseVelocity ~= nil then dc.RiseVelocity = cd.RiseVelocity end
					if cd.Brightness ~= nil then dc.Brightness = cd.Brightness end
					if cd.Heat ~= nil then dc.Heat = cd.Heat end
					if cd.SecondaryColor then dc.SecondaryColor = parseColor3(cd.SecondaryColor) end
					if cd.SparkleColor then dc.SparkleColor = parseColor3(cd.SparkleColor) end
					F3XRetry("SyncDecorate", {dc})
				elseif (cd.ClassName == "Weld" or cd.ClassName == "WeldConstraint" or cd.ClassName == "Motor" or cd.ClassName == "Motor6D") and cd.Part0Index and cd.Part1Index and partMap then
					local p0, p1 = partMap[cd.Part0Index], partMap[cd.Part1Index]
					if p0 and p1 then pcall(function()
						pcall(function() F3XRetry("RemoveWelds", {{p0}, p1}) end)
						local weldObj = F3XRetry("CreateWelds", {p0}, p1)
					if not weldObj or typeof(weldObj) ~= "Instance" then
						local containers = {p1, p0, p1.Parent, p0.Parent}
						for _, ctn in ipairs(containers) do
							if ctn then
								for _, child in ipairs(ctn:GetChildren()) do
									if (child:IsA("Weld") or child:IsA("Motor") or child:IsA("Motor6D")) and child.Part0 == p0 and child.Part1 == p1 then
										weldObj = child; break
									end
								end
								if weldObj and typeof(weldObj) == "Instance" then break end
							end
						end
					end
					if weldObj and typeof(weldObj) == "Instance" and (cd.ClassName ~= "WeldConstraint") then
							if cd.C0 then pcall(function() weldObj.C0 = parseCFrame(cd.C0) end) end
							if cd.C1 then pcall(function() weldObj.C1 = parseCFrame(cd.C1) end) end
						end
					end) end
				end
			end)
		end
	end
end

-- 9. BUILD ENGINE (Normal + Hyper)
local function normalBuild(parts, total, partMap)
	local bs = CONFIG.BatchSize
	local bd = CONFIG.BuildSpeed
	local failed = 0
	for i, pd in ipairs(parts) do
		if not F3X:ValidateTool() then break end
		local pt = getPartType(pd.ClassName or "Part")
		local cf = parseCFrame(pd.CFrame)
		if CONFIG.BuildOffset and CONFIG.BuildOffset.Magnitude > 0 then
			cf = cf * CFrame.new(CONFIG.BuildOffset)
		end
		local part
		local ok, res = pcall(function() return F3XRetry("CreatePart", pt, CFrame.new(0, 5000, 0)) end)
		if not ok or not res then failed += 1 else
			part = res
			partMap[i] = part
			pcall(function() F3XRetry("SyncMove", {{Part = part, CFrame = cf}}) end)
			applyPartProperties(part, pd, cf, partMap)
		end
		if i % bs == 0 or i == total then
			progressFill.Size = UDim2.new(i / total, 0, 1, 0)
			statusLabel.Text = string.format("Building... %d/%d (%d fail) [b:%d d:%.4f]", i, total, failed, bs, bd)
			if bd > 0 then task.wait(bd) end
		end
	end
	return failed
end

local function hyperBuild(parts, total, partMap)
	local tc = CONFIG.HyperThreads
	local bs = CONFIG.BatchSize
	local bd = CONFIG.BuildSpeed
	local failed = 0
	local completed = 0
	local chunks = {}
	for t = 1, tc do chunks[t] = {} end
	for i, pd in ipairs(parts) do table.insert(chunks[((i-1) % tc) + 1], {Index = i, Data = pd}) end

	local function buildChunk(chunk)
		for _, entry in ipairs(chunk) do
			local i = entry.Index; local pd = entry.Data
			if not F3X:ValidateTool() then break end
			local pt = getPartType(pd.ClassName or "Part")
			local cf = parseCFrame(pd.CFrame)
			if CONFIG.BuildOffset and CONFIG.BuildOffset.Magnitude > 0 then
				cf = cf * CFrame.new(CONFIG.BuildOffset)
			end
			local part
			local ok, res = pcall(function() return F3XRetry("CreatePart", pt, CFrame.new(0, 5000, 0)) end)
			if not ok or not res then failed += 1 else
				part = res
				partMap[i] = part
				pcall(function() F3XRetry("SyncMove", {{Part = part, CFrame = cf}}) end)
				applyPartProperties(part, pd, cf, partMap)
			end
			completed += 1
			if completed % bs == 0 or completed == total then
				statusLabel.Text = string.format("HYPER %d/%d (%d fail) [t:%d]", completed, total, failed, tc)
			end
			if bd > 0 then task.wait(bd) end
		end
	end

	local threads = {}
	local doneCount = 0
	for t = 1, tc do
		threads[t] = task.spawn(function()
			buildChunk(chunks[t])
			doneCount += 1
		end)
	end
	while doneCount < tc do
		progressFill.Size = UDim2.new(completed / total, 0, 1, 0)
		task.wait(0.1)
	end
	return failed
end

-- 10. FILE I/O (Local + GitHub)
local selectedBuildData = nil
local selectedBuildName = nil
local buildHistory = {}

local function clearLocalList()
	for _, c in ipairs(localScroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
end

local function addLocalFile(filename)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 32)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	btn.Text = ""
	btn.TextColor3 = Color3.fromRGB(200, 200, 210)
	btn.TextSize = 12
	btn.Font = Enum.Font.Gotham
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.Parent = localScroll

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -14, 1, 0)
	nameLabel.Position = UDim2.new(0, 10, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "📄 " .. (filename:match("([^/\\]+)$") or filename)
	nameLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = btn

	btn.MouseButton1Click:Connect(function() pcall(function()
		for _, b in ipairs(localScroll:GetChildren()) do
			if b:IsA("TextButton") then
				b.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
				local l = b:FindFirstChildOfClass("TextLabel")
				if l then l.TextColor3 = Color3.fromRGB(200, 200, 210) end
			end
		end
		btn.BackgroundColor3 = Color3.fromRGB(0, 100, 60)
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		local fileOk = false
		if isfile then
			local ok = pcall(isfile, filename)
			if ok then fileOk = true end
		end
		if not fileOk then notify("File not found!"); return end
		local content = safeReadFile(filename)
		if content and #content > 0 then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(content) end)
			if parseOk then
				selectedBuildData = data; selectedBuildName = filename:match("([^/\\]+)$")
				statusLabel.Text = "Selected: " .. selectedBuildName .. " (" .. (data.PartCount or #data.Parts) .. " parts)"
				buildBtn.Visible = true; queueBtn.Visible = true; refreshQueueUI()
				notify("Loaded: " .. selectedBuildName)
			else notify("Invalid JSON!") end
		else notify("Failed to read file!") end
	end) end)
end

refreshLocalBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function()
	clearLocalList(); selectedBuildData = nil; buildBtn.Visible = false
	statusLabel.Text = "Scanning local files..."
	local foldOk, foldExists = pcall(isfolder, CONFIG.LocalFolder)
	if not foldOk or not foldExists then
		statusLabel.Text = "No BuildExports folder"; notify("No local builds!"); return
	end
	local filesOk, files = pcall(listfiles, CONFIG.LocalFolder)
	if not filesOk or not files then notify("Error scanning folder!"); statusLabel.Text = "Scan failed"; return end
	local cnt = 0
	for _, f in ipairs(files) do
		local lower = f:lower()
		if lower:match("%.json$") then
			local valid = true
			if isfile then
				local ok = pcall(isfile, f)
				if not ok then valid = false end
			end
			if valid then addLocalFile(f); cnt += 1 end
		end
	end
	statusLabel.Text = string.format("Found %d build files", cnt)
	notify(string.format("Found %d local builds", cnt))
end) if not ok then warn("[F3X] Error:", err) end end)

local function clearGithubList()
	for _, c in ipairs(githubScroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
end

local function addGithubFile(name, url)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 32)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	btn.Text = ""
	btn.TextColor3 = Color3.fromRGB(200, 200, 210)
	btn.TextSize = 12
	btn.Font = Enum.Font.Gotham
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.Parent = githubScroll

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -14, 1, 0)
	nameLabel.Position = UDim2.new(0, 10, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "🌐 " .. name
	nameLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = btn

	btn.MouseButton1Click:Connect(function() pcall(function()
		for _, b in ipairs(githubScroll:GetChildren()) do
			if b:IsA("TextButton") then
				b.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
				local l = b:FindFirstChildOfClass("TextLabel")
				if l then l.TextColor3 = Color3.fromRGB(200, 200, 210) end
			end
		end
		btn.BackgroundColor3 = Color3.fromRGB(0, 100, 60)
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		statusLabel.Text = "Downloading " .. name .. "..."
		local content = safeHttpGet(url)
		if content then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(content) end)
			if parseOk then
				selectedBuildData = data; selectedBuildName = name
				statusLabel.Text = "Selected: " .. name .. " (" .. (data.PartCount or #data.Parts) .. " parts)"
				buildBtn.Visible = true; queueBtn.Visible = true; refreshQueueUI(); notify("Loaded: " .. name)
				pcall(function() if not isfolder(CONFIG.LocalFolder) then makefolder(CONFIG.LocalFolder) end; writefile(CONFIG.LocalFolder .. "/" .. name, content) end)
			else notify("Invalid JSON!"); statusLabel.Text = "Invalid JSON" end
		else notify("Download failed!"); statusLabel.Text = "Download failed" end
	end) end)
end

fetchGithubBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function()
	clearGithubList(); selectedBuildData = nil; buildBtn.Visible = false
	statusLabel.Text = "Fetching from GitHub..."
	local repo = githubInput.Text:gsub("%s+", "")
	if repo == "" then repo = CONFIG.GitHubRepo end
	local resp = safeHttpGet("https://api.github.com/repos/" .. repo .. "/contents/")
	if not resp then notify("Failed to fetch repo!"); statusLabel.Text = "Fetch failed"; return end
	local parseOk, files = pcall(function() return HttpService:JSONDecode(resp) end)
	if not parseOk then notify("Failed to parse response!"); statusLabel.Text = "Parse failed"; return end
	local cnt = 0
	for _, f in ipairs(files) do if f.type == "file" and f.name:match("%.json$") then addGithubFile(f.name, f.download_url); cnt += 1 end end
	statusLabel.Text = string.format("Found %d GitHub builds", cnt)
	notify(string.format("Found %d GitHub builds", cnt))
end) if not ok then warn("[F3X] Error:", err) end end)

-- 11. EXPORT SYSTEM
local function streamExport(builderFunc, baseFilename, totalParts, ext)
	if not hasFileAccess then notify("No file access!"); return false end
	exportInProgress = true; progressFrame.Visible = true; progressFill.Size = UDim2.new(0, 0, 1, 0)
	local canStream = appendfile ~= nil
	local chunkCount = canStream and 1 or math.ceil(totalParts / CONFIG.FileChunkSize)
	local ts = os.date("%Y-%m-%d_%H-%M-%S")
	if not canStream and chunkCount > 1 then notify(string.format("Large build! %d files...", chunkCount)) end
	local success = true
	for chunk = 1, chunkCount do
		local startIdx = canStream and 1 or (chunk-1) * CONFIG.FileChunkSize + 1
		local endIdx = canStream and totalParts or math.min(chunk * CONFIG.FileChunkSize, totalParts)
		local filename
		if canStream then
			filename = SAVE_FOLDER .. "/" .. baseFilename .. "_" .. ts .. "." .. ext
			if chunk == 1 then
				local ok = pcall(function() writefile(filename, "") end)
				if not ok then success = false; break end
			end
		else filename = SAVE_FOLDER .. "/" .. baseFilename .. "_Chunk" .. chunk .. "_" .. ts .. "." .. ext end
		local ok, err = pcall(function() builderFunc(filename, startIdx, endIdx, totalParts, canStream, chunk, chunkCount) end)
		if not ok then warn("[Export] Error:", tostring(err)); notify("Export error!"); success = false; break end
		if not canStream then notify(string.format("Saved chunk %d/%d", chunk, chunkCount)) end
		progressFill.Size = UDim2.new(chunk / chunkCount, 0, 1, 0)
		task.wait(0.05)
	end
	progressFill.Size = UDim2.new(1, 0, 1, 0); task.wait(0.2); progressFrame.Visible = false; exportInProgress = false
	if success then notify(string.format("Export complete! %d parts", totalParts)); statusLabel.Text = "✅ Saved " .. baseFilename .. "_" .. ts .. "." .. ext end
	return success
end

exportF3XBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function()
	if #selectedParts == 0 then notify("No parts selected!"); return end
	if exportInProgress then return end
	local total = #selectedParts
	local partMap = {}; for i, p in ipairs(selectedParts) do partMap[p] = i end
	local hier = selToggles.Hierarchy.Get()
	local incWelds = selToggles.Welds.Get()
	local incDecals = selToggles.Decals.Get()
	local incMeshes = selToggles.Meshes.Get()
	local incLights = selToggles.Lights.Get()

	coroutine.wrap(function()
		streamExport(function(filename, si, ei, total, canStream, cn, tc)
			local buf = {}; local bc = 0
			local function flush() if bc > 0 then local d = table.concat(buf); if canStream then appendfile(filename, d) else writefile(filename, d) end; buf = {}; bc = 0 end end
			local function push(s) bc += 1; buf[bc] = s; if bc >= CONFIG.StreamBatch then flush(); progressFill.Size = UDim2.new((si+bc)/total*0.95, 0, 1, 0); task.wait() end end
			if cn == 1 then push(string.format('{"BuildName":"ExportedBuild","PlaceId":%d,"Timestamp":"%s","PartCount":%d,"Parts":[', game.PlaceId, os.date("%Y-%m-%d %H:%M:%S"), total)) else push(",") end
			for i = si, ei do
				local part = selectedParts[i]
				local partOk, partJson = pcall(function()
					local pb = {}; local pc = 0
					local function pp(s) pc += 1; pb[pc] = s end
					pp('{"Index":'); pp(tostring(i)); pp(',"ClassName":"'); pp(part.ClassName); pp('","Name":"'); pp(part.Name:gsub('"', '\\"')); pp('"')
					if part:IsA("BasePart") then
						local c = table.pack(part.CFrame:GetComponents())
						pp(',"CFrame":['); pp(string.format("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f", c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9],c[10],c[11],c[12])); pp(']')
						pp(',"Size":['); pp(string.format("%.4f,%.4f,%.4f", part.Size.X, part.Size.Y, part.Size.Z)); pp(']')
						pp(',"Color":['); pp(string.format("%d,%d,%d", math.floor(part.Color.R*255+.5), math.floor(part.Color.G*255+.5), math.floor(part.Color.B*255+.5))); pp(']')
						pp(',"Material":"'); pp(tostring(part.Material)); pp('","Transparency":'); pp(string.format("%.4f", part.Transparency))
						pp(',"Reflectance":'); pp(string.format("%.4f", part.Reflectance))
						pp(',"CanCollide":'); pp(tostring(part.CanCollide)); pp(',"Anchored":'); pp(tostring(part.Anchored))
						pp(',"CastShadow":'); pp(tostring(part.CastShadow)); pp(',"Locked":'); pp(tostring(part.Locked))
						local surfs = {"TopSurface","BottomSurface","LeftSurface","RightSurface","FrontSurface","BackSurface"}
						for _, s in ipairs(surfs) do pp(',"' .. s .. '":"'); pp(tostring(part[s])); pp('"') end
						if part:IsA("Part") then pp(',"Shape":"'); pp(tostring(part.Shape)); pp('"') end
					end
					if part:IsA("MeshPart") then
						if part.MeshId and part.MeshId ~= "" then pp(',"MeshId":"'); pp(part.MeshId); pp('"') end
						if part.TextureID and part.TextureID ~= "" then pp(',"TextureID":"'); pp(part.TextureID); pp('"') end
						pp(',"RenderFidelity":"'); pp(tostring(part.RenderFidelity)); pp('","CollisionFidelity":"'); pp(tostring(part.CollisionFidelity)); pp('"')
					end
					if part.Massless then pp(',"Massless":true') end
					if part.CollisionGroupId ~= 0 then pp(',"CollisionGroupId":'); pp(tostring(part.CollisionGroupId)) end
					local cpp = part.CustomPhysicalProperties
					if cpp then pp(',"CustomPhysicalProperties":{"Density":'); pp(string.format("%.4f", cpp.Density)); pp(',"Friction":'); pp(string.format("%.4f", cpp.Friction)); pp(',"Elasticity":'); pp(string.format("%.4f", cpp.Elasticity)); pp(',"FrictionWeight":'); pp(string.format("%.4f", cpp.FrictionWeight)); pp(',"ElasticityWeight":'); pp(string.format("%.4f", cpp.ElasticityWeight)); pp('}') end
					if hier then
						local parent = part.Parent
						if parent and parent ~= workspace then pp(',"ParentName":"'); pp(parent.Name:gsub('"', '\\"')); pp('","ParentClass":"'); pp(parent.ClassName); pp('"') else pp(',"ParentName":"workspace"') end
					else pp(',"ParentName":"workspace"') end
					pp(',"Children":[')
					local cj = {}; local cc = 0
					if incDecals then
						for _, child in ipairs(part:GetChildren()) do
							if child:IsA("Decal") or child:IsA("Texture") then
								local cbuf = {'{"ClassName":"', child.ClassName, '","Texture":"', child.Texture, '","Transparency":', string.format("%.4f", child.Transparency), ',"Face":"', tostring(child.Face), '"'}
								local okC3, c3 = pcall(function() return child.Color3 end)
								if okC3 then cbuf[#cbuf+1] = ',"Color3":['; cbuf[#cbuf+1] = string.format("%d,%d,%d", math.floor(c3.R*255+.5), math.floor(c3.G*255+.5), math.floor(c3.B*255+.5)); cbuf[#cbuf+1] = ']' end
								cbuf[#cbuf+1] = '}'; cc += 1; cj[cc] = table.concat(cbuf)
							end
						end
					end
					if incMeshes then
						for _, child in ipairs(part:GetChildren()) do
							if child:IsA("SpecialMesh") then
								cc += 1; cj[cc] = string.format('{"ClassName":"SpecialMesh","MeshType":"%s","MeshId":"%s","TextureId":"%s","Scale":[%.4f,%.4f,%.4f],"Offset":[%.4f,%.4f,%.4f]}', tostring(child.MeshType), child.MeshId, child.TextureId, child.Scale.X, child.Scale.Y, child.Scale.Z, child.Offset.X, child.Offset.Y, child.Offset.Z)
							elseif child:IsA("BlockMesh") then
								cc += 1; cj[cc] = string.format('{"ClassName":"BlockMesh","Scale":[%.4f,%.4f,%.4f],"Offset":[%.4f,%.4f,%.4f]}', child.Scale.X, child.Scale.Y, child.Scale.Z, child.Offset.X, child.Offset.Y, child.Offset.Z)
							elseif child:IsA("CylinderMesh") then
								cc += 1; cj[cc] = string.format('{"ClassName":"CylinderMesh","Scale":[%.4f,%.4f,%.4f],"Offset":[%.4f,%.4f,%.4f]}', child.Scale.X, child.Scale.Y, child.Scale.Z, child.Offset.X, child.Offset.Y, child.Offset.Z)
							end
						end
					end
					if incLights then
						for _, child in ipairs(part:GetChildren()) do
							if child:IsA("SurfaceLight") or child:IsA("PointLight") or child:IsA("SpotLight") then
								local cbuf = {'{"ClassName":"', child.ClassName, '","Color":[', string.format("%d,%d,%d", math.floor(child.Color.R*255+.5), math.floor(child.Color.G*255+.5), math.floor(child.Color.B*255+.5)), '],"Brightness":', string.format("%.4f", child.Brightness), ',"Range":', string.format("%.4f", child.Range), ',"Shadows":', tostring(child.Shadows)}
								if not child:IsA("PointLight") then cbuf[#cbuf+1] = ',"Face":"'; cbuf[#cbuf+1] = tostring(child.Face); cbuf[#cbuf+1] = '"' end
								if child:IsA("SurfaceLight") or child:IsA("SpotLight") then cbuf[#cbuf+1] = ',"Angle":'; cbuf[#cbuf+1] = string.format("%.4f", child.Angle) end
								cbuf[#cbuf+1] = '}'; cc += 1; cj[cc] = table.concat(cbuf)
							end
						end
					end
					pp(table.concat(cj, ",")); pp(']')
					if incWelds then
						local wj = {}; local wc = 0
						for _, child in ipairs(part:GetChildren()) do
							if (child:IsA("Weld") or child:IsA("Motor") or child:IsA("Motor6D")) and partMap[child.Part0] and partMap[child.Part1] then
								local c0 = table.pack(child.C0:GetComponents()); local c1 = table.pack(child.C1:GetComponents())
								wc += 1; wj[wc] = string.format('{"ClassName":"%s","Part0Index":%d,"Part1Index":%d,"C0":[%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f],"C1":[%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f]}', child.ClassName, partMap[child.Part0], partMap[child.Part1], c0[1],c0[2],c0[3],c0[4],c0[5],c0[6],c0[7],c0[8],c0[9],c0[10],c0[11],c0[12], c1[1],c1[2],c1[3],c1[4],c1[5],c1[6],c1[7],c1[8],c1[9],c1[10],c1[11],c1[12])
							elseif child:IsA("WeldConstraint") and partMap[child.Part0] and partMap[child.Part1] then
								wc += 1; wj[wc] = string.format('{"ClassName":"WeldConstraint","Part0Index":%d,"Part1Index":%d}', partMap[child.Part0], partMap[child.Part1])
							end
						end
						if wc > 0 then pp(',"Welds":['); pp(table.concat(wj, ",")); pp(']') end
					end
					pp('}'); return table.concat(pb)
				end)
				if partOk then if i > si then push(",") end; push(partJson) else warn("[Export] Part", i, "failed:", tostring(partJson)); if i > si then push(",") end; push('{"Index":'..tostring(i)..',"Name":'..string.format("%q",part.Name)..',"Error":'..string.format("%q",tostring(partJson):sub(1,200))..'}') end
			end
			if cn == tc then push(']}') end; flush()
		end, "F3X_Build", total, "json")
	end)()
end) if not ok then warn("[F3X] Error:", err) end end)

exportLuaBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function()
	if #selectedParts == 0 then notify("No parts selected!"); return end
	if exportInProgress then return end
	local total = #selectedParts
	local partMap = {}; for i, p in ipairs(selectedParts) do partMap[p] = "p" .. i end
	local hier = selToggles.Hierarchy.Get()
	local incWelds = selToggles.Welds.Get()
	local incDecals = selToggles.Decals.Get()
	local incMeshes = selToggles.Meshes.Get()
	local incLights = selToggles.Lights.Get()

	local modelMap = {}; local modelVars = {}
	if hier then
		for i, part in ipairs(selectedParts) do
			local parent = part.Parent
			while parent and parent ~= workspace do
				if (parent:IsA("Model") or parent:IsA("Folder")) and not modelMap[parent] then
					local mv = "m" .. (#modelVars + 1); modelMap[parent] = mv; modelVars[#modelVars+1] = {Object = parent, Var = mv}
				end
				parent = parent.Parent
			end
		end
	end

	coroutine.wrap(function()
		streamExport(function(filename, si, ei, total, canStream, cn, tc)
			local buf = {}; local bc = 0
			local function flush() if bc > 0 then local d = table.concat(buf, "\n"); if canStream then appendfile(filename, d.."\n") else writefile(filename, d) end; buf = {}; bc = 0 end end
			local function push(s) bc += 1; buf[bc] = s; if bc >= CONFIG.StreamBatch then flush(); progressFill.Size = UDim2.new((si+bc)/total*0.95, 0, 1, 0); task.wait() end end
			if cn == 1 then
				push("--[[\n Build Export\n Total: "..totalParts.."\n Date: "..os.date().."\n]]"); push("")
				push('local build = Instance.new("Model")'); push('build.Name = "ExportedBuild"'); push("")
				if hier then
					table.sort(modelVars, function(a,b)
						local da, db = 0, 0; local p = a.Object.Parent; while p and p ~= workspace do da += 1; p = p.Parent end
						p = b.Object.Parent; while p and p ~= workspace do db += 1; p = p.Parent end; return da < db
					end)
					for _, m in ipairs(modelVars) do
						push(string.format("local %s = Instance.new(%q)", m.Var, m.Object.ClassName))
						push(string.format("%s.Name = %q", m.Var, m.Object.Name))
						local parent = m.Object.Parent
						if parent == workspace or not parent then push(string.format("%s.Parent = build", m.Var))
						elseif modelMap[parent] then push(string.format("%s.Parent = %s", m.Var, modelMap[parent]))
						else push(string.format("%s.Parent = build", m.Var)) end
						push("")
					end
				end
			end
			local welds = {}; local constraints = {}
			for i = si, ei do
				local part = selectedParts[i]; local var = partMap[part]
				push(string.format("local %s = Instance.new(%q)", var, part.ClassName))
				local props = {"Name","Size","CFrame","Color","Material","Transparency","Reflectance","CanCollide","Anchored","CastShadow","Locked"}
				for _, prop in ipairs(props) do
					local ok, val = pcall(function() return part[prop] end)
					if ok then push(string.format("%s.%s = %s", var, prop, fmtVal(val))) end
				end
				local surfs = {"TopSurface","BottomSurface","LeftSurface","RightSurface","FrontSurface","BackSurface"}
				for _, s in ipairs(surfs) do local ok, val = pcall(function() return part[s] end); if ok then push(string.format("%s.%s = %s", var, s, fmtVal(val))) end end
				if part:IsA("Part") then local ok, val = pcall(function() return part.Shape end); if ok then push(string.format("%s.Shape = %s", var, fmtVal(val))) end end
				if part:IsA("MeshPart") then
					local ok1, mId = pcall(function() return part.MeshId end); if ok1 and mId ~= "" then push(string.format("%s.MeshId = %s", var, fmtVal(mId))) end
					local ok2, tId = pcall(function() return part.TextureID end); if ok2 and tId ~= "" then push(string.format("%s.TextureID = %s", var, fmtVal(tId))) end
					local ok3, rf = pcall(function() return part.RenderFidelity end); if ok3 then push(string.format("%s.RenderFidelity = %s", var, fmtVal(rf))) end
					local ok4, cf = pcall(function() return part.CollisionFidelity end); if ok4 then push(string.format("%s.CollisionFidelity = %s", var, fmtVal(cf))) end
				end
				local okM, mass = pcall(function() return part.Massless end); if okM and mass then push(string.format("%s.Massless = true", var)) end
				local okCid, cid = pcall(function() return part.CollisionGroupId end); if okCid and cid ~= 0 then push(string.format("%s.CollisionGroupId = %d", var, cid)) end
				local okCpp, cpp = pcall(function() return part.CustomPhysicalProperties end); if okCpp and cpp then push(string.format("%s.CustomPhysicalProperties = PhysicalProperties.new(%s,%s,%s,%s,%s)", var, fmtN(cpp.Density), fmtN(cpp.Friction), fmtN(cpp.Elasticity), fmtN(cpp.FrictionWeight), fmtN(cpp.ElasticityWeight))) end
				if incDecals then
					for _, child in ipairs(part:GetChildren()) do
						if child:IsA("Decal") or child:IsA("Texture") then
							local cv = var.."_d"..tostring(i); push(string.format("local %s = Instance.new(%q)", cv, child.ClassName))
							local cprops = {"Texture","Transparency","Face","Color3"}; for _, p in ipairs(cprops) do local ok, v = pcall(function() return child[p] end); if ok then push(string.format("%s.%s = %s", cv, p, fmtVal(v))) end end
							push(string.format("%s.Parent = %s", cv, var))
						end
					end
				end
				if incMeshes then
					for _, child in ipairs(part:GetChildren()) do
						local cv = var.."_m"..tostring(i)
						if child:IsA("SpecialMesh") then
							push(string.format("local %s = Instance.new(%q)", cv, "SpecialMesh"))
							local cprops = {"MeshType","MeshId","TextureId","Scale","Offset","VertexColor"}; for _, p in ipairs(cprops) do local ok, v = pcall(function() return child[p] end); if ok then push(string.format("%s.%s = %s", cv, p, fmtVal(v))) end end
							push(string.format("%s.Parent = %s", cv, var))
						elseif child:IsA("BlockMesh") then
							push(string.format("local %s = Instance.new(%q)", cv, "BlockMesh"))
							local cprops = {"Scale","Offset","VertexColor"}; for _, p in ipairs(cprops) do local ok, v = pcall(function() return child[p] end); if ok then push(string.format("%s.%s = %s", cv, p, fmtVal(v))) end end
							push(string.format("%s.Parent = %s", cv, var))
						elseif child:IsA("CylinderMesh") then
							push(string.format("local %s = Instance.new(%q)", cv, "CylinderMesh"))
							local cprops = {"Scale","Offset","VertexColor"}; for _, p in ipairs(cprops) do local ok, v = pcall(function() return child[p] end); if ok then push(string.format("%s.%s = %s", cv, p, fmtVal(v))) end end
							push(string.format("%s.Parent = %s", cv, var))
						end
					end
				end
				if incLights then
					for _, child in ipairs(part:GetChildren()) do
						if child:IsA("SurfaceLight") or child:IsA("PointLight") or child:IsA("SpotLight") then
							local cv = var.."_l"..tostring(i); push(string.format("local %s = Instance.new(%q)", cv, child.ClassName))
							local cprops = {"Color","Brightness","Range","Shadows","Face"}; for _, p in ipairs(cprops) do local ok, v = pcall(function() return child[p] end); if ok then push(string.format("%s.%s = %s", cv, p, fmtVal(v))) end end
							if child:IsA("SurfaceLight") or child:IsA("SpotLight") then local okA, angle = pcall(function() return child.Angle end); if okA then push(string.format("%s.Angle = %s", cv, fmtVal(angle))) end end
							push(string.format("%s.Parent = %s", cv, var))
						end
					end
				end
				if incWelds then
					for _, child in ipairs(part:GetChildren()) do
						if child:IsA("Weld") or child:IsA("Motor") or child:IsA("Motor6D") then welds[#welds+1] = {var=var, class=child.ClassName, c0=child.C0, c1=child.C1, p0=child.Part0, p1=child.Part1}
						elseif child:IsA("WeldConstraint") then constraints[#constraints+1] = {var=var, p0=child.Part0, p1=child.Part1} end
					end
				end
				if hier then
					local parent = part.Parent
					if modelMap[parent] then push(string.format("%s.Parent = %s", var, modelMap[parent])) else push(string.format("%s.Parent = build", var)) end
				else push(string.format("%s.Parent = build", var)) end
				push("")
				if i % 500 == 0 then progressFill.Size = UDim2.new(0.15 + (i/total * 0.7), 0, 1, 0); task.wait() end
			end
			if cn == tc then
				if #constraints > 0 then push("-- Weld Constraints")
					for _, w in ipairs(constraints) do if partMap[w.p0] and partMap[w.p1] then local wv = w.var.."_wc"..tostring(math.random(1000,9999)); push(string.format("local %s = Instance.new(%q)", wv, "WeldConstraint")); push(string.format("%s.Part0 = %s", wv, partMap[w.p0])); push(string.format("%s.Part1 = %s", wv, partMap[w.p1])); push(string.format("%s.Parent = %s", wv, w.var)) end end; push("") end
				if #welds > 0 then push("-- Welds / Motors")
					for _, w in ipairs(welds) do if partMap[w.p0] and partMap[w.p1] then local wv = w.var.."_w"..tostring(math.random(1000,9999)); push(string.format("local %s = Instance.new(%q)", wv, w.class)); push(string.format("%s.Part0 = %s", wv, partMap[w.p0])); push(string.format("%s.Part1 = %s", wv, partMap[w.p1])); push(string.format("%s.C0 = %s", wv, fmtVal(w.c0))); push(string.format("%s.C1 = %s", wv, fmtVal(w.c1))); push(string.format("%s.Parent = %s", wv, w.var)) end end; push("") end
				push("build.Parent = workspace")
			end
			flush()
		end, "Build", total, "lua")
	end)()
end) if not ok then warn("[F3X] Error:", err) end end)

-- 12. HISTORY SYSTEM
local function addHistory(name, parts, failed)
	local entry = {Name = name or "Unknown", Timestamp = os.date("%Y-%m-%d %H:%M:%S"), PartCount = parts, Failed = failed, Success = parts - failed}
	table.insert(buildHistory, 1, entry)
	if #buildHistory > CONFIG.UndoDepth then table.remove(buildHistory) end
	refreshHistory()
end

local function refreshHistory()
	for _, c in ipairs(historyScroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
	for _, entry in ipairs(buildHistory) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -10, 0, 28)
		btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
		btn.Text = string.format("[%s] %s — %d/%d ✓", entry.Timestamp, entry.Name, entry.Success, entry.PartCount)
		btn.TextColor3 = entry.Failed > 0 and Color3.fromRGB(255, 150, 100) or Color3.fromRGB(150, 255, 150)
		btn.TextSize = 10
		btn.Font = Enum.Font.Gotham
		btn.TextXAlignment = Enum.TextXAlignment.Left
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		btn.Parent = historyScroll
	end
end

-- 13. MAIN BUILD TRIGGER

local function doBuild(name, data, isQueueItem)
	if not data then notify("No build data!"); return end
	local parts = data.Parts
	if not parts or typeof(parts) ~= "table" then notify("Invalid build data!"); return end

	CONFIG.BuildSpeed = speedSlider.Get()
	CONFIG.BatchSize = batchSlider.Get()
	CONFIG.HyperThreads = threadSlider.Get()

	if not isQueueItem then buildBtn.Visible = false; queueBtn.Visible = false; buildAllBtn.Visible = false end
	progressFrame.Visible = true; progressFill.Size = UDim2.new(0, 0, 1, 0)

	local buildCenter = calculateBuildCenter(parts)
	statusLabel.Text = "Teleporting..."; teleportToBuild(buildCenter); notify("Teleported!"); task.wait(0.5)

	if not hasBuildingTool() then
		statusLabel.Text = "Requesting btools..."; notify("Sending ;btools...")
		local sent = sendBtoolsCommand()
		if not sent then notify("Chat failed!"); progressFrame.Visible = false; if not isQueueItem then buildBtn.Visible = true; queueBtn.Visible = true; buildAllBtn.Visible = #buildQueue > 0 end; statusLabel.Text = "Chat failed"; return end
		local received = waitForBtools(CONFIG.BtoolsTimeout)
		if not received then
			for retry = 1, 3 do
				notify(string.format("Retrying btools (%d/3)...", retry)); sendBtoolsCommand()
				received = waitForBtools(CONFIG.BtoolsTimeout)
				if received then break end
			end
		end
		if not received then notify("Failed to get btools! Try ;btools manually."); progressFrame.Visible = false; if not isQueueItem then buildBtn.Visible = true; queueBtn.Visible = true; buildAllBtn.Visible = #buildQueue > 0 end; statusLabel.Text = "Timed out"; return end
	end

	statusLabel.Text = "Equipping tools..."
	if not equipBuildingTool() then notify("Failed to equip!"); progressFrame.Visible = false; if not isQueueItem then buildBtn.Visible = true; queueBtn.Visible = true; buildAllBtn.Visible = #buildQueue > 0 end; return end
	task.wait(0.5)

	if not F3X:Init() then notify("F3X init failed!"); progressFrame.Visible = false; if not isQueueItem then buildBtn.Visible = true; queueBtn.Visible = true; buildAllBtn.Visible = #buildQueue > 0 end; return end

	local total = #parts
	local partMap = {}
	local modelMap = {}
	local failedCount = 0

	statusLabel.Text = string.format("Building %d parts...", total)
	notify("Starting: " .. name)

	if data.Models then
		for ref, info in pairs(data.Models) do
			local model
			local ok, res = pcall(function() return F3X:CreateGroup(info.ClassName or "Model", workspace, {}) end)
			if ok and res then model = res; pcall(function() F3X:SetName({model}, info.Name or "Model") end)
			else model = Instance.new(info.ClassName or "Model"); model.Name = info.Name or "Model"; model.Parent = workspace end
			modelMap[ref] = model
			if info.Name and info.Name ~= ref then modelMap[info.Name] = model end
		end
	end

	if CONFIG.HyperMode then failedCount = hyperBuild(parts, total, partMap)
	else failedCount = normalBuild(parts, total, partMap) end

	local parentGroups = {}
	for i, pd in ipairs(parts) do
		local part = partMap[i]
		if part then
			local target = workspace
			if pd.ParentName and pd.ParentName ~= "workspace" then
				target = modelMap[pd.ParentName] or workspace
			end
			if not parentGroups[target] then parentGroups[target] = {} end
			table.insert(parentGroups[target], part)
		end
	end
	if next(parentGroups) then
		statusLabel.Text = "Setting parents..."
		for target, plist in pairs(parentGroups) do pcall(function() F3X:SetParent(plist, target) end) end
	end

	if data.Welds then
		statusLabel.Text = "Applying welds..."
		for _, wd in ipairs(data.Welds) do
			if wd.Part0Index and wd.Part1Index then
				local p0, p1 = partMap[wd.Part0Index], partMap[wd.Part1Index]
				if p0 and p1 then pcall(function()
					pcall(function() F3XRetry("RemoveWelds", {{p0}, p1}) end)
					local weldObj = F3XRetry("CreateWelds", {p0}, p1)
					if not weldObj or typeof(weldObj) ~= "Instance" then
						local containers = {p1, p0, p1.Parent, p0.Parent}
						for _, ctn in ipairs(containers) do
							if ctn then
								for _, child in ipairs(ctn:GetChildren()) do
									if (child:IsA("Weld") or child:IsA("Motor") or child:IsA("Motor6D")) and child.Part0 == p0 and child.Part1 == p1 then
										weldObj = child; break
									end
								end
								if weldObj and typeof(weldObj) == "Instance" then break end
							end
						end
					end
					if weldObj and typeof(weldObj) == "Instance" and (wd.ClassName or "Weld") ~= "WeldConstraint" then
						if wd.C0 then pcall(function() weldObj.C0 = parseCFrame(wd.C0) end) end
						if wd.C1 then pcall(function() weldObj.C1 = parseCFrame(wd.C1) end) end
						if wd.ClassName == "Motor6D" then
							if wd.MaxVelocity then pcall(function() weldObj.MaxVelocity = wd.MaxVelocity end) end
							if wd.CurrentAngle then pcall(function() weldObj.CurrentAngle = wd.CurrentAngle end) end
							if wd.DesiredAngle then pcall(function() weldObj.DesiredAngle = wd.DesiredAngle end) end
						end
					end
				end) end
			end
		end
	end

	local builtCount = 0
	for i, part in pairs(partMap) do
		if part and part:FindFirstAncestorOfClass("DataModel") then builtCount += 1 end
	end
	if builtCount < total then
		notify(string.format("⚠️ Validation: %d/%d parts exist", builtCount, total))
	else
		notify(string.format("✅ All %d parts confirmed", builtCount))
	end

	progressFill.Size = UDim2.new(1, 0, 1, 0); task.wait(0.5); progressFrame.Visible = false
	if not isQueueItem then
		buildBtn.Visible = true; queueBtn.Visible = true; buildAllBtn.Visible = #buildQueue > 0
	end

	addHistory(name, total, failedCount)
	local msg = string.format("✅ Built %d/%d!%s%s", total-failedCount, total, CONFIG.BuildAnchored and " [ALL ANCHORED]" or " [AS ORIGINAL]", CONFIG.HyperMode and " [HYPER]" or "")
	if failedCount > 0 then msg = msg .. string.format(" (%d failed)", failedCount) end
	statusLabel.Text = msg; notify(msg)
end

buildBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function()
	doBuild(selectedBuildName, selectedBuildData, false)
end) if not ok then warn("[F3X] Error:", err) end end)

queueBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function()
	if not selectedBuildData then notify("No build selected!"); return end
	table.insert(buildQueue, {Name = selectedBuildName, Data = selectedBuildData})
	notify(string.format("📋 Queued: %s (%d in queue)", selectedBuildName, #buildQueue))
	buildAllBtn.Visible = true
	refreshQueueUI()
end) if not ok then warn("[F3X] Error:", err) end end)

buildAllBtn.MouseButton1Click:Connect(function() local ok, err = pcall(function()
	if #buildQueue == 0 then notify("Queue is empty!"); return end
	queueActive = true
	buildBtn.Visible = false; queueBtn.Visible = false; buildAllBtn.Visible = false
	notify(string.format("▶️ Building queue (%d items)...", #buildQueue))
	task.spawn(function()
		while #buildQueue > 0 do
			local item = table.remove(buildQueue, 1)
			refreshQueueUI()
			statusLabel.Text = string.format("Queue: building %s (%d remaining)", item.Name, #buildQueue)
			doBuild(item.Name, item.Data, true)
			task.wait(1)
		end
		queueActive = false
		buildBtn.Visible = true; queueBtn.Visible = true
		notify("✅ Queue completed!")
		statusLabel.Text = "All queued builds completed."
	end)
end) if not ok then warn("[F3X] Error:", err) end end)

-- 14. INIT
if hasFileAccess then notify("F3X Build System loaded!") else notify("F3X Build System loaded! (Limited file access)") end
