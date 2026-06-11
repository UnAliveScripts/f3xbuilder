--[[
 ============================================
 F3X UNIFIED BUILD SYSTEM v4.0
 Merges Build Loader + Build Selector/Exporter
 Single LocalScript for StarterPlayerScripts
 ============================================
]]

-- ==================== 1. SERVICES & CONSTANTS ====================
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local THEME = {
	Background = Color3.fromRGB(18, 18, 24),
	TitleBar = Color3.fromRGB(28, 28, 36),
	Accent = Color3.fromRGB(0, 130, 220),
	Success = Color3.fromRGB(0, 150, 80),
	Danger = Color3.fromRGB(180, 50, 50),
	Warning = Color3.fromRGB(200, 150, 0),
	TextPrimary = Color3.fromRGB(255, 255, 255),
	TextSecondary = Color3.fromRGB(180, 180, 190),
	TextMuted = Color3.fromRGB(140, 140, 150),
	ListBg = Color3.fromRGB(12, 12, 16),
	ButtonBg = Color3.fromRGB(40, 40, 50),
	InputBg = Color3.fromRGB(35, 35, 45),
	SelectionColor = Color3.fromRGB(0, 170, 255),
	GhostColor = Color3.fromRGB(0, 170, 255),
	BoundsColor = Color3.fromRGB(255, 100, 0),
	CornerRadius = UDim.new(0, 12),
	BoxFillTransparency = 0.88,
}

-- ==================== 2. FILE API LAYER ====================
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

local function safeReadFile(path)
	local ok, result = pcall(function() return readfile(path) end)
	if ok then return result end
	return nil
end

local function safeWriteFile(path, content)
	local ok = pcall(function() writefile(path, content) end)
	return ok
end

local function safeListFiles(folder)
	local ok, result = pcall(function() return listfiles(folder) end)
	if ok then return result end
	return {}
end

local function safeIsFolder(path)
	local ok, result = pcall(function() return isfolder(path) end)
	if ok then return result end
	return false
end

local function safeAppendFile(path, content)
	if appendfile then
		local ok = pcall(function() appendfile(path, content) end)
		return ok
	end
	local ok = pcall(function() writefile(path, content) end)
	return ok
end

local function safeHttpGet(url)
	local ok, result = pcall(function() return game:HttpGet(url) end)
	if ok then return result end
	return nil
end

-- ==================== 3. CONFIG TABLE + PERSISTENCE ====================
local CONFIG = {
	GitHubRepo = "UnAliveScripts/f3xbuildsjson",
	GitHubBranch = "main",
	LocalFolder = "BuildExports",
	BuildSpeed = 0.005,
	BatchSize = 10,
	BtoolsTimeout = 12,
	Debug = true,
	BuildAnchored = false,
	HyperMode = false,
	HyperThreads = 4,
	BuildOffset = Vector3.new(0, 0, 0),
	BuildRot90 = 0,
	BuildScale = 1,
	AutoAnchorAfter = false,
	PreserveHierarchy = true,
	IncludeWelds = true,
	IncludeDecals = true,
	IncludeMeshes = true,
	IncludeLights = true,
	MaxParts = 100000,
	VisualLimit = 500,
	DragThreshold = 5,
	StreamBatch = 2000,
	FileChunkSize = 5000,
	ListCap = 500,
	GhostLimit = 200,
	SoundEnabled = true,
}


local function saveConfig()
	if not hasFileAccess then return end
	local ok, json = pcall(function() return HttpService:JSONEncode(CONFIG) end)
	if ok then safeWriteFile(CONFIG_FILE, json) end
end

local function loadConfig()
	if not hasFileAccess then return end
	local content = safeReadFile(CONFIG_FILE)
	if content then
		local ok, data = pcall(function() return HttpService:JSONDecode(content) end)
		if ok and type(data) == "table" then
			for k, v in pairs(data) do
				CONFIG[k] = v
			end
		end
	end
end

loadConfig()

-- ==================== 4. F3X API WRAPPER ====================
-- Tool detection functions (MUST be defined before F3X table)
local function hasBuildingTool()
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()
	local function checkContainer(c)
		if not c then return nil end
		for _, item in ipairs(c:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				return item
			end
		end
		return nil
	end
	return checkContainer(backpack) or checkContainer(char)
end

local function equipBuildingTool()
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()
	local tool = nil
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item; break
			end
		end
	end
	if not tool then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item; break
			end
		end
	end
	if tool and tool.Parent == backpack and char:FindFirstChild("Humanoid") then
		char.Humanoid:EquipTool(tool)
		return true
	end
	return tool ~= nil
end

local function sendBtoolsCommand()
	local success = false
	pcall(function()
		local textChannels = TextChatService:FindFirstChild("TextChannels")
		if textChannels then
			local rb = textChannels:FindFirstChild("RBXGeneral")
			if rb then
				rb:SendAsync(";btools"); success = true
			end
		end
	end)
	if not success then pcall(function() Players:Chat(";btools"); success = true end) end
	return success
end

local function waitForBtools(timeout)
	local elapsed = 0
	while elapsed < timeout do
		if hasBuildingTool() then return true end
		task.wait(0.5); elapsed = elapsed + 0.5
	end
	return hasBuildingTool()
end

local F3X = {}
F3X._tool = nil; F3X._syncAPI = nil; F3X._serverEndpoint = nil

function F3X:Init()
	if self._serverEndpoint and self._serverEndpoint:FindFirstAncestorOfClass("DataModel") then return true end
	local backpack = player:WaitForChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()
	local tool = backpack:FindFirstChild("Building Tools")
	if not tool then tool = backpack:FindFirstChild("F3X") end
	if not tool then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item; break
			end
		end
	end
	if not tool then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item; break
			end
		end
	end
	if not tool then return false end
	self._tool = tool
	self._syncAPI = tool:WaitForChild("SyncAPI", 5)
	if not self._syncAPI then return false end
	self._serverEndpoint = self._syncAPI:WaitForChild("ServerEndpoint", 5)
	if not self._serverEndpoint then return false end
	return true
end

function F3X:ValidateTool()
	if not self._tool or not self._tool:FindFirstAncestorOfClass("DataModel") then return self:Init() end
	if not self._tool.Parent then return self:Init() end
	local char = player.Character
	if char and self._tool.Parent ~= char then
		if not hasBuildingTool() then equipBuildingTool() end
		return self:Init()
	end
	return true
end

function F3X:Invoke(...)
	if not self:Init() then return nil end
	local args = {...}
	local ok, result = pcall(function() return self._serverEndpoint:InvokeServer(unpack(args)) end)
	if not ok then return nil end
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

function F3X:CreatePart(partType, cframe)
	return self:Invoke("CreatePart", partType or "Normal", cframe or CFrame.new(0, 10, 0), workspace)
end

function F3X:SyncMove(changes) return self:Invoke("SyncMove", changes) end
function F3X:SyncResize(changes) return self:Invoke("SyncResize", changes) end
function F3X:SyncColor(changes) return self:Invoke("SyncColor", changes) end
function F3X:SyncMaterial(changes) return self:Invoke("SyncMaterial", changes) end
function F3X:SyncSurface(changes) return self:Invoke("SyncSurface", changes) end
function F3X:SyncAnchor(changes) return self:Invoke("SyncAnchor", changes) end
function F3X:SyncCollision(changes) return self:Invoke("SyncCollision", changes) end
function F3X:SyncRotate(changes) return self:Invoke("SyncRotate", changes) end

function F3X:CreateMeshes(parts)
	local c = {}
	for _, p in ipairs(parts) do c[#c + 1] = {Part = p} end
	return self:Invoke("CreateMeshes", c)
end
function F3X:SyncMesh(changes) return self:Invoke("SyncMesh", changes) end
function F3X:CreateTextures(changes) return self:Invoke("CreateTextures", changes) end
function F3X:SyncTexture(changes) return self:Invoke("SyncTexture", changes) end
function F3X:CreateLights(changes) return self:Invoke("CreateLights", changes) end
function F3X:SyncLighting(changes) return self:Invoke("SyncLighting", changes) end
function F3X:CreateDecorations(changes) return self:Invoke("CreateDecorations", changes) end
function F3X:SyncDecorate(changes) return self:Invoke("SyncDecorate", changes) end
function F3X:CreateWelds(parts, targetPart) return self:Invoke("CreateWelds", parts, targetPart) end
function F3X:RemoveWelds(welds) return self:Invoke("RemoveWelds", welds) end
function F3X:Remove(objects) return self:Invoke("Remove", objects) end
function F3X:Clone(items, parent) return self:Invoke("Clone", items, parent) end
function F3X:Ungroup(groups) return self:Invoke("Ungroup", groups) end

function F3X:SetParent(items, parent)
	if typeof(items) ~= "table" then items = {items} end
	return self:Invoke("SetParent", items, parent)
end

function F3X:SetName(items, name)
	if typeof(items) ~= "table" then items = {items} end
	return self:Invoke("SetName", items, name)
end

function F3X:CreateGroup(gtype, parent, items)
	return self:Invoke("CreateGroup", gtype or "Model", parent or workspace, items or {})
end

function F3X:SetLocked(items, locked)
	if typeof(items) ~= "table" then items = {items} end
	return self:Invoke("SetLocked", items, locked)
end

-- ==================== 5. DATA PARSERS ====================
local function parseCFrame(data)
	if not data then return CFrame.new(0, 5000, 0) end
	if typeof(data) == "CFrame" then return data end
	if typeof(data) == "table" then
		if #data >= 12 then return CFrame.new(unpack(data))
		elseif #data >= 3 then return CFrame.new(data[1], data[2], data[3])
		else return CFrame.new(0, 5000, 0) end
	end
	if typeof(data) == "string" then
		local x, y, z = data:match("CFrame%.new%(([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)%)")
		if x and y and z then return CFrame.new(tonumber(x), tonumber(y), tonumber(z)) end
	end
	return CFrame.new(0, 5000, 0)
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

local function parseMaterial(str)
	if not str then return Enum.Material.SmoothPlastic end
	local name = str:match("Enum%.Material%.(.+)") or str
	for _, enum in ipairs(Enum.Material:GetEnumItems()) do if enum.Name == name then return enum end end
	return Enum.Material.SmoothPlastic
end

local function parseSurface(str)
	if not str then return Enum.SurfaceType.Smooth end
	local name = str:match("Enum%.SurfaceType%.(.+)") or str
	for _, enum in ipairs(Enum.SurfaceType:GetEnumItems()) do if enum.Name == name then return enum end end
	return Enum.SurfaceType.Smooth
end

local function parseNormalId(str)
	if not str then return Enum.NormalId.Top end
	local name = str:match("Enum%.NormalId%.(.+)") or str
	for _, enum in ipairs(Enum.NormalId:GetEnumItems()) do if enum.Name == name then return enum end end
	return Enum.NormalId.Top
end

local function parseMeshType(str)
	if not str then return Enum.MeshType.Brick end
	local ok, result = pcall(function()
		local name = tostring(str):gsub("Enum%.MeshType%.", "")
		for _, enum in ipairs(Enum.MeshType:GetEnumItems()) do if enum.Name == name then return enum end end
		return Enum.MeshType.Brick
	end)
	return ok and result or Enum.MeshType.Brick
end

local function parseShape(str)
	if not str then return Enum.PartType.Block end
	local name = str:match("Enum%.PartType%.(.+)") or str
	for _, enum in ipairs(Enum.PartType:GetEnumItems()) do if enum.Name == name then return enum end end
	return Enum.PartType.Block
end

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

local function isValidAssetUrl(url)
	if not url or url == "" then return false end
	if url:match("^rbxassetid://%d+$") then return true end
	if url:match("^rbxasset://") then return true end
	if url:match("^https?://") then return true end
	return false
end

-- Formatters for Lua export
local function fmtN(n)
	if n ~= n then return "0.0000" end
	if n == math.huge then return "math.huge" end
	if n == -math.huge then return "-math.huge" end
	return string.format("%.4f", n)
end

local function fmtV3(v)
	return string.format("Vector3.new(%s, %s, %s)", fmtN(v.X), fmtN(v.Y), fmtN(v.Z))
end

local function fmtCF(cf)
	local c = table.pack(cf:GetComponents())
	return string.format("CFrame.new(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
		fmtN(c[1]), fmtN(c[2]), fmtN(c[3]), fmtN(c[4]), fmtN(c[5]), fmtN(c[6]),
		fmtN(c[7]), fmtN(c[8]), fmtN(c[9]), fmtN(c[10]), fmtN(c[11]), fmtN(c[12]))
end

local function fmtC3(c)
	return string.format("Color3.fromRGB(%d, %d, %d)",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function fmtVal(v)
	local t = typeof(v)
	if t == "number" then return fmtN(v)
	elseif t == "boolean" then return tostring(v)
	elseif t == "string" then return string.format("%q", v)
	elseif t == "Vector3" then return fmtV3(v)
	elseif t == "Color3" then return fmtC3(v)
	elseif t == "CFrame" then return fmtCF(v)
	elseif t == "EnumItem" then
		local s = tostring(v)
		return string.format("%q", s:gsub("Enum%.%w+%.", ""))
	else return string.format("%q", tostring(v)) end
end

local function initUI()
-- ==================== 6. UI SYSTEM ====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "F3XUnifiedBuildSystem"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 460, 0, 720)
mainFrame.Position = UDim2.new(0.5, -230, 0.5, -360)
mainFrame.BackgroundColor3 = THEME.Background
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = THEME.CornerRadius

local uiStroke = Instance.new("UIStroke")
uiStroke.Color = Color3.fromRGB(50, 50, 60)
uiStroke.Thickness = 1; uiStroke.Parent = mainFrame

-- Title Bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = THEME.TitleBar
titleBar.BorderSizePixel = 0; titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = THEME.CornerRadius

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, -90, 1, 0)
titleText.Position = UDim2.new(0, 14, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "??? F3X Build Loader"
titleText.TextColor3 = THEME.TextPrimary
titleText.TextSize = 17; titleText.Font = Enum.Font.GothamBold
titleText.TextXAlignment = Enum.TextXAlignment.Left; titleText.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 7)
closeBtn.BackgroundColor3 = THEME.Danger
closeBtn.Text = "?"; closeBtn.TextColor3 = THEME.TextPrimary
closeBtn.TextSize = 14; closeBtn.Font = Enum.Font.GothamBold; closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

-- Tab Bar
local tabFrame = Instance.new("Frame")
tabFrame.Size = UDim2.new(1, -20, 0, 36)
tabFrame.Position = UDim2.new(0, 10, 0, 50)
tabFrame.BackgroundTransparency = 1; tabFrame.Parent = mainFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; tabLayout.Parent = tabFrame

local currentTab = "Build"
local tabButtons = {}

local function makeTabBtn(text)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.33, -4, 1, 0)
	btn.BackgroundColor3 = text == "Build" and THEME.Accent or THEME.ButtonBg
	btn.Text = text; btn.TextColor3 = THEME.TextPrimary
	btn.TextSize = 13; btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6); btn.Parent = tabFrame
	tabButtons[text] = btn
end

makeTabBtn("Build"); makeTabBtn("Selector"); makeTabBtn("Settings")

local buildTab = Instance.new("Frame")
buildTab.Size = UDim2.new(1, -20, 1, -92)
buildTab.Position = UDim2.new(0, 10, 0, 92)
buildTab.BackgroundTransparency = 1; buildTab.Parent = mainFrame

local selectorTab = Instance.new("Frame")
selectorTab.Size = UDim2.new(1, -20, 1, -92)
selectorTab.Position = UDim2.new(0, 10, 0, 92)
selectorTab.BackgroundTransparency = 1
selectorTab.Visible = false; selectorTab.Parent = mainFrame

local settingsTab = Instance.new("Frame")
settingsTab.Size = UDim2.new(1, -20, 1, -92)
settingsTab.Position = UDim2.new(0, 10, 0, 92)
settingsTab.BackgroundTransparency = 1
settingsTab.Visible = false; settingsTab.Parent = mainFrame

local function switchTab(tab)
	currentTab = tab
	buildTab.Visible = (tab == "Build")
	selectorTab.Visible = (tab == "Selector")
	settingsTab.Visible = (tab == "Settings")
	for name, btn in pairs(tabButtons) do
		btn.BackgroundColor3 = (name == tab) and THEME.Accent or THEME.ButtonBg
	end
end

tabButtons.Build.MouseButton1Click:Connect(function() switchTab("Build") end)
tabButtons.Selector.MouseButton1Click:Connect(function() switchTab("Selector") end)
tabButtons.Settings.MouseButton1Click:Connect(function() switchTab("Settings") end)

-- Notification Toast
local notif = Instance.new("Frame")
notif.Size = UDim2.new(0, 400, 0, 50)
notif.Position = UDim2.new(0.5, -200, 0, -70)
notif.BackgroundColor3 = THEME.TitleBar
notif.BorderSizePixel = 0; notif.ZIndex = 2000; notif.Parent = screenGui
Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 10)

local notifText = Instance.new("TextLabel")
notifText.Size = UDim2.new(1, -20, 1, 0)
notifText.Position = UDim2.new(0, 10, 0, 0)
notifText.BackgroundTransparency = 1
notifText.Text = ""; notifText.TextColor3 = THEME.TextPrimary
notifText.TextSize = 14; notifText.Font = Enum.Font.Gotham
notifText.TextWrapped = true; notifText.Parent = notif

local function notify(msg)
	notifText.Text = msg
	TweenService:Create(notif, TweenInfo.new(0.3), {
		Position = UDim2.new(0.5, -200, 0, 28)
	}):Play()
	task.delay(3, function()
		TweenService:Create(notif, TweenInfo.new(0.3), {
			Position = UDim2.new(0.5, -200, 0, -70)
		}):Play()
	end)
end

-- Shared Progress Bar
local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(1, -20, 0, 4)
progressFrame.Position = UDim2.new(0, 10, 0, 74)
progressFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
progressFrame.BorderSizePixel = 0; progressFrame.Visible = false; progressFrame.Parent = mainFrame
Instance.new("UICorner", progressFrame).CornerRadius = UDim.new(1, 0)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = THEME.SelectionColor
progressFill.BorderSizePixel = 0; progressFill.Parent = progressFrame
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

-- Shared Status Label
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 22)
statusLabel.Position = UDim2.new(0, 10, 1, -68)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Ready"; statusLabel.TextColor3 = THEME.TextMuted
statusLabel.TextSize = 12; statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true; statusLabel.Parent = mainFrame

-- Toggle button (shows/hides mainFrame)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 50, 0, 50)
toggleBtn.Position = UDim2.new(0, 20, 0, 20)
toggleBtn.BackgroundColor3 = THEME.TitleBar
toggleBtn.Text = "???"; toggleBtn.TextColor3 = THEME.TextPrimary
toggleBtn.TextSize = 24; toggleBtn.Font = Enum.Font.GothamBold
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(1, 0); toggleBtn.Parent = screenGui

toggleBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = not mainFrame.Visible
end)

-- Draggable UI
local draggingUI = false; local uiDragStart = nil; local uiStartPos = nil

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
		mainFrame.Position = UDim2.new(
			uiStartPos.X.Scale, uiStartPos.X.Offset + delta.X,
			uiStartPos.Y.Scale, uiStartPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingUI = false end
end)

-- ==================== 7. BUILD TAB ====================
-- File list
local fileListScroll = Instance.new("ScrollingFrame")
fileListScroll.Size = UDim2.new(1, 0, 1, -314)
fileListScroll.Position = UDim2.new(0, 0, 0, 0)
fileListScroll.BackgroundColor3 = THEME.ListBg
fileListScroll.BorderSizePixel = 0
fileListScroll.ScrollBarThickness = 4
fileListScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 70)
fileListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
fileListScroll.CanvasSize = UDim2.new(0, 0, 0, 0); fileListScroll.Parent = buildTab
Instance.new("UICorner", fileListScroll).CornerRadius = UDim.new(0, 8)

local fileListLayout = Instance.new("UIListLayout")
fileListLayout.Padding = UDim.new(0, 4); fileListLayout.Parent = fileListScroll

-- Build controls frame
local buildCtrlFrame = Instance.new("Frame")
buildCtrlFrame.Size = UDim2.new(1, 0, 0, 314)
buildCtrlFrame.Position = UDim2.new(0, 0, 1, -314)
buildCtrlFrame.BackgroundTransparency = 1; buildCtrlFrame.Parent = buildTab

-- File source switcher (Local/GitHub)
local fileSourceFrame = Instance.new("Frame")
fileSourceFrame.Size = UDim2.new(1, 0, 0, 30)
fileSourceFrame.BackgroundTransparency = 1; fileSourceFrame.Parent = buildCtrlFrame

local fileSourceLayout = Instance.new("UIListLayout")
fileSourceLayout.FillDirection = Enum.FillDirection.Horizontal
fileSourceLayout.Padding = UDim.new(0, 6)
fileSourceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; fileSourceLayout.Parent = fileSourceFrame

local fileSourceBtns = {}; local currentFileSource = "Local"

local function makeFileSourceBtn(text)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.5, -3, 1, 0)
	btn.BackgroundColor3 = text == "Local" and THEME.Accent or THEME.ButtonBg
	btn.Text = text; btn.TextColor3 = THEME.TextPrimary
	btn.TextSize = 12; btn.Font = Enum.Font.GothamBold; btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6); btn.Parent = fileSourceFrame
	fileSourceBtns[text] = btn
end

makeFileSourceBtn("Local"); makeFileSourceBtn("GitHub")

local localPanel = Instance.new("Frame")
localPanel.Size = UDim2.new(1, 0, 1, -34)
localPanel.Position = UDim2.new(0, 0, 0, 34)
localPanel.BackgroundTransparency = 1; localPanel.Parent = buildCtrlFrame

local refreshLocalBtn = Instance.new("TextButton")
refreshLocalBtn.Size = UDim2.new(1, 0, 0, 30)
refreshLocalBtn.BackgroundColor3 = THEME.ButtonBg
refreshLocalBtn.Text = "?? Refresh Local Files"
refreshLocalBtn.TextColor3 = THEME.TextPrimary
refreshLocalBtn.TextSize = 12; refreshLocalBtn.Font = Enum.Font.GothamBold; refreshLocalBtn.AutoButtonColor = true
Instance.new("UICorner", refreshLocalBtn).CornerRadius = UDim.new(0, 6); refreshLocalBtn.Parent = localPanel

local githubPanel = Instance.new("Frame")
githubPanel.Size = UDim2.new(1, 0, 1, -34)
githubPanel.Position = UDim2.new(0, 0, 0, 34)
githubPanel.BackgroundTransparency = 1
githubPanel.Visible = false; githubPanel.Parent = buildCtrlFrame

local githubInput = Instance.new("TextBox")
githubInput.Size = UDim2.new(1, 0, 0, 30)
githubInput.BackgroundColor3 = THEME.InputBg
githubInput.Text = CONFIG.GitHubRepo
githubInput.PlaceholderText = "user/repo"
githubInput.TextColor3 = THEME.TextPrimary
githubInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
githubInput.TextSize = 12; githubInput.Font = Enum.Font.Gotham
githubInput.ClearTextOnFocus = false
Instance.new("UICorner", githubInput).CornerRadius = UDim.new(0, 6); githubInput.Parent = githubPanel

githubInput.FocusLost:Connect(function()
	local repo = githubInput.Text:gsub("%s+", "")
	if repo ~= "" then CONFIG.GitHubRepo = repo; saveConfig() end
end)

local fetchGithubBtn = Instance.new("TextButton")
fetchGithubBtn.Size = UDim2.new(1, 0, 0, 30)
fetchGithubBtn.Position = UDim2.new(0, 0, 0, 36)
fetchGithubBtn.BackgroundColor3 = THEME.Accent
fetchGithubBtn.Text = "?? Fetch Builds from GitHub"
fetchGithubBtn.TextColor3 = THEME.TextPrimary
fetchGithubBtn.TextSize = 12; fetchGithubBtn.Font = Enum.Font.GothamBold; fetchGithubBtn.AutoButtonColor = true
Instance.new("UICorner", fetchGithubBtn).CornerRadius = UDim.new(0, 6); fetchGithubBtn.Parent = githubPanel

local function switchFileSource(src)
	currentFileSource = src
	localPanel.Visible = (src == "Local")
	githubPanel.Visible = (src == "GitHub")
	for name, btn in pairs(fileSourceBtns) do
		btn.BackgroundColor3 = (name == src) and THEME.Accent or THEME.ButtonBg
	end
end

fileSourceBtns.Local.MouseButton1Click:Connect(function() switchFileSource("Local") end)
fileSourceBtns.GitHub.MouseButton1Click:Connect(function() switchFileSource("GitHub") end)

-- Sliders section
local slidersFrame = Instance.new("Frame")
slidersFrame.Size = UDim2.new(1, 0, 0, 150)
slidersFrame.Position = UDim2.new(0, 0, 0, 34)
slidersFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
slidersFrame.BorderSizePixel = 0; slidersFrame.Parent = localPanel
Instance.new("UICorner", slidersFrame).CornerRadius = UDim.new(0, 8)

local slidersTitle = Instance.new("TextLabel")
slidersTitle.Size = UDim2.new(1, -10, 0, 18)
slidersTitle.Position = UDim2.new(0, 5, 0, 4)
slidersTitle.BackgroundTransparency = 1
slidersTitle.Text = "?? Build Settings (Click numbers to type exact values)"
slidersTitle.TextColor3 = THEME.TextSecondary
slidersTitle.TextSize = 11; slidersTitle.Font = Enum.Font.GothamBold
slidersTitle.TextXAlignment = Enum.TextXAlignment.Left; slidersTitle.Parent = slidersFrame

-- Speed slider
local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 80, 0, 16)
speedLabel.Position = UDim2.new(0, 8, 0, 24)
speedLabel.BackgroundTransparency = 1
speedLabel.Text = "Delay:"; speedLabel.TextColor3 = THEME.TextSecondary
speedLabel.TextSize = 11; speedLabel.Font = Enum.Font.Gotham
speedLabel.TextXAlignment = Enum.TextXAlignment.Left; speedLabel.Parent = slidersFrame

local speedValueBox = Instance.new("TextBox")
speedValueBox.Size = UDim2.new(0, 70, 0, 20)
speedValueBox.Position = UDim2.new(0, 85, 0, 22)
speedValueBox.BackgroundColor3 = THEME.InputBg
speedValueBox.Text = tostring(CONFIG.BuildSpeed)
speedValueBox.PlaceholderText = "0.005"
speedValueBox.TextColor3 = Color3.fromRGB(0, 200, 255)
speedValueBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
speedValueBox.TextSize = 12; speedValueBox.Font = Enum.Font.GothamBold
speedValueBox.ClearTextOnFocus = false
Instance.new("UICorner", speedValueBox).CornerRadius = UDim.new(0, 4); speedValueBox.Parent = slidersFrame

local speedUnitLabel = Instance.new("TextLabel")
speedUnitLabel.Size = UDim2.new(0, 50, 0, 16)
speedUnitLabel.Position = UDim2.new(0, 158, 0, 24)
speedUnitLabel.BackgroundTransparency = 1
speedUnitLabel.Text = "seconds"; speedUnitLabel.TextColor3 = THEME.TextMuted
speedUnitLabel.TextSize = 10; speedUnitLabel.Font = Enum.Font.Gotham
speedUnitLabel.TextXAlignment = Enum.TextXAlignment.Left; speedUnitLabel.Parent = slidersFrame

local speedSliderBg = Instance.new("Frame")
speedSliderBg.Size = UDim2.new(1, -16, 0, 8)
speedSliderBg.Position = UDim2.new(0, 8, 0, 46)
speedSliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
speedSliderBg.BorderSizePixel = 0; speedSliderBg.Parent = slidersFrame
Instance.new("UICorner", speedSliderBg).CornerRadius = UDim.new(1, 0)

local speedSliderFill = Instance.new("Frame")
speedSliderFill.Size = UDim2.new(0.001, 0, 1, 0)
speedSliderFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
speedSliderFill.BorderSizePixel = 0; speedSliderFill.Parent = speedSliderBg
Instance.new("UICorner", speedSliderFill).CornerRadius = UDim.new(1, 0)

local speedSliderKnob = Instance.new("TextButton")
speedSliderKnob.Size = UDim2.new(0, 16, 0, 16)
speedSliderKnob.Position = UDim2.new(0.001, -8, 0.5, -8)
speedSliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
speedSliderKnob.Text = ""; speedSliderKnob.Parent = speedSliderBg
Instance.new("UICorner", speedSliderKnob).CornerRadius = UDim.new(1, 0)

local speedValue = CONFIG.BuildSpeed
local function updateSpeedFromValue(val)
	val = math.max(0, val); speedValue = val
	CONFIG.BuildSpeed = val; speedValueBox.Text = string.format("%.4f", val)
	local ratio = math.min(val / 10, 1)
	speedSliderFill.Size = UDim2.new(ratio, 0, 1, 0)
	speedSliderKnob.Position = UDim2.new(ratio, -8, 0.5, -8)
end

local function updateSpeedFromSlider(ratio)
	ratio = math.clamp(ratio, 0, 1)
	local val = (ratio ^ 2) * 10
	if val < 0.001 then val = 0 end
	updateSpeedFromValue(val)
end

speedValueBox.FocusLost:Connect(function()
	local val = tonumber(speedValueBox.Text)
	if val then updateSpeedFromValue(val) else updateSpeedFromValue(speedValue) end
end)

-- Batch slider
local batchLabel = Instance.new("TextLabel")
batchLabel.Size = UDim2.new(0, 80, 0, 16)
batchLabel.Position = UDim2.new(0, 8, 0, 66)
batchLabel.BackgroundTransparency = 1
batchLabel.Text = "Batch:"; batchLabel.TextColor3 = THEME.TextSecondary
batchLabel.TextSize = 11; batchLabel.Font = Enum.Font.Gotham
batchLabel.TextXAlignment = Enum.TextXAlignment.Left; batchLabel.Parent = slidersFrame

local batchValueBox = Instance.new("TextBox")
batchValueBox.Size = UDim2.new(0, 70, 0, 20)
batchValueBox.Position = UDim2.new(0, 85, 0, 64)
batchValueBox.BackgroundColor3 = THEME.InputBg
batchValueBox.Text = tostring(CONFIG.BatchSize)
batchValueBox.PlaceholderText = "10"
batchValueBox.TextColor3 = Color3.fromRGB(0, 255, 100)
batchValueBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
batchValueBox.TextSize = 12; batchValueBox.Font = Enum.Font.GothamBold
batchValueBox.ClearTextOnFocus = false
Instance.new("UICorner", batchValueBox).CornerRadius = UDim.new(0, 4); batchValueBox.Parent = slidersFrame

local batchUnitLabel = Instance.new("TextLabel")
batchUnitLabel.Size = UDim2.new(0, 50, 0, 16)
batchUnitLabel.Position = UDim2.new(0, 158, 0, 66)
batchUnitLabel.BackgroundTransparency = 1
batchUnitLabel.Text = "parts"; batchUnitLabel.TextColor3 = THEME.TextMuted
batchUnitLabel.TextSize = 10; batchUnitLabel.Font = Enum.Font.Gotham
batchUnitLabel.TextXAlignment = Enum.TextXAlignment.Left; batchUnitLabel.Parent = slidersFrame

local batchSliderBg = Instance.new("Frame")
batchSliderBg.Size = UDim2.new(1, -16, 0, 8)
batchSliderBg.Position = UDim2.new(0, 8, 0, 88)
batchSliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
batchSliderBg.BorderSizePixel = 0; batchSliderBg.Parent = slidersFrame
Instance.new("UICorner", batchSliderBg).CornerRadius = UDim.new(1, 0)

local batchSliderFill = Instance.new("Frame")
batchSliderFill.Size = UDim2.new(0.01, 0, 1, 0)
batchSliderFill.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
batchSliderFill.BorderSizePixel = 0; batchSliderFill.Parent = batchSliderBg
Instance.new("UICorner", batchSliderFill).CornerRadius = UDim.new(1, 0)

local batchSliderKnob = Instance.new("TextButton")
batchSliderKnob.Size = UDim2.new(0, 16, 0, 16)
batchSliderKnob.Position = UDim2.new(0.01, -8, 0.5, -8)
batchSliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
batchSliderKnob.Text = ""; batchSliderKnob.Parent = batchSliderBg
Instance.new("UICorner", batchSliderKnob).CornerRadius = UDim.new(1, 0)

local batchValue = CONFIG.BatchSize
local function updateBatchFromValue(val)
	val = math.max(1, math.floor(val)); batchValue = val
	CONFIG.BatchSize = val; batchValueBox.Text = tostring(val)
	local ratio = math.min((val - 1) / 999, 1)
	batchSliderFill.Size = UDim2.new(ratio, 0, 1, 0)
	batchSliderKnob.Position = UDim2.new(ratio, -8, 0.5, -8)
end

local function updateBatchFromSlider(ratio)
	ratio = math.clamp(ratio, 0, 1)
	local val = math.floor(ratio * 999) + 1
	updateBatchFromValue(val)
end

batchValueBox.FocusLost:Connect(function()
	local val = tonumber(batchValueBox.Text)
	if val then updateBatchFromValue(val) else updateBatchFromValue(batchValue) end
end)

-- Threads slider
local threadsLabel = Instance.new("TextLabel")
threadsLabel.Size = UDim2.new(0, 80, 0, 16)
threadsLabel.Position = UDim2.new(0, 8, 0, 108)
threadsLabel.BackgroundTransparency = 1
threadsLabel.Text = "Threads:"; threadsLabel.TextColor3 = THEME.TextSecondary
threadsLabel.TextSize = 11; threadsLabel.Font = Enum.Font.Gotham
threadsLabel.TextXAlignment = Enum.TextXAlignment.Left; threadsLabel.Parent = slidersFrame

local threadsValueBox = Instance.new("TextBox")
threadsValueBox.Size = UDim2.new(0, 70, 0, 20)
threadsValueBox.Position = UDim2.new(0, 85, 0, 106)
threadsValueBox.BackgroundColor3 = THEME.InputBg
threadsValueBox.Text = tostring(CONFIG.HyperThreads)
threadsValueBox.PlaceholderText = "4"
threadsValueBox.TextColor3 = Color3.fromRGB(255, 100, 50)
threadsValueBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
threadsValueBox.TextSize = 12; threadsValueBox.Font = Enum.Font.GothamBold
threadsValueBox.ClearTextOnFocus = false
Instance.new("UICorner", threadsValueBox).CornerRadius = UDim.new(0, 4); threadsValueBox.Parent = slidersFrame

local threadsUnitLabel = Instance.new("TextLabel")
threadsUnitLabel.Size = UDim2.new(0, 50, 0, 16)
threadsUnitLabel.Position = UDim2.new(0, 158, 0, 108)
threadsUnitLabel.BackgroundTransparency = 1
threadsUnitLabel.Text = "parallel"; threadsUnitLabel.TextColor3 = THEME.TextMuted
threadsUnitLabel.TextSize = 10; threadsUnitLabel.Font = Enum.Font.Gotham
threadsUnitLabel.TextXAlignment = Enum.TextXAlignment.Left; threadsUnitLabel.Parent = slidersFrame

local threadsSliderBg = Instance.new("Frame")
threadsSliderBg.Size = UDim2.new(1, -16, 0, 8)
threadsSliderBg.Position = UDim2.new(0, 8, 0, 130)
threadsSliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
threadsSliderBg.BorderSizePixel = 0; threadsSliderBg.Parent = slidersFrame
Instance.new("UICorner", threadsSliderBg).CornerRadius = UDim.new(1, 0)

local threadsSliderFill = Instance.new("Frame")
threadsSliderFill.Size = UDim2.new(0.04, 0, 1, 0)
threadsSliderFill.BackgroundColor3 = Color3.fromRGB(255, 100, 50)
threadsSliderFill.BorderSizePixel = 0; threadsSliderFill.Parent = threadsSliderBg
Instance.new("UICorner", threadsSliderFill).CornerRadius = UDim.new(1, 0)

local threadsSliderKnob = Instance.new("TextButton")
threadsSliderKnob.Size = UDim2.new(0, 16, 0, 16)
threadsSliderKnob.Position = UDim2.new(0.04, -8, 0.5, -8)
threadsSliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
threadsSliderKnob.Text = ""; threadsSliderKnob.Parent = threadsSliderBg
Instance.new("UICorner", threadsSliderKnob).CornerRadius = UDim.new(1, 0)

local threadsValue = CONFIG.HyperThreads
local function updateThreadsFromValue(val)
	val = math.max(1, math.min(32, math.floor(val))); threadsValue = val
	CONFIG.HyperThreads = val; threadsValueBox.Text = tostring(val)
	local ratio = (val - 1) / 31
	threadsSliderFill.Size = UDim2.new(ratio, 0, 1, 0)
	threadsSliderKnob.Position = UDim2.new(ratio, -8, 0.5, -8)
end

local function updateThreadsFromSlider(ratio)
	ratio = math.clamp(ratio, 0, 1)
	local val = math.floor(ratio * 31) + 1
	updateThreadsFromValue(val)
end

threadsValueBox.FocusLost:Connect(function()
	local val = tonumber(threadsValueBox.Text)
	if val then updateThreadsFromValue(val) else updateThreadsFromValue(threadsValue) end
end)

-- Slider dragging
local function makeSliderDraggable(knob, bg, updateFunc)
	local dragging = false
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
	end)
	bg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local pos = input.Position.X; local bgPos = bg.AbsolutePosition.X; local bgSize = bg.AbsoluteSize.X
			local ratio = (pos - bgPos) / bgSize; updateFunc(ratio); dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local pos = input.Position.X; local bgPos = bg.AbsolutePosition.X; local bgSize = bg.AbsoluteSize.X
			local ratio = (pos - bgPos) / bgSize; updateFunc(ratio)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
end

makeSliderDraggable(speedSliderKnob, speedSliderBg, updateSpeedFromSlider)
makeSliderDraggable(batchSliderKnob, batchSliderBg, updateBatchFromSlider)
makeSliderDraggable(threadsSliderKnob, threadsSliderBg, updateThreadsFromSlider)

updateSpeedFromValue(CONFIG.BuildSpeed)
updateBatchFromValue(CONFIG.BatchSize)
updateThreadsFromValue(CONFIG.HyperThreads)

-- File source and GitHub are defined above. Now toggles, offset/scale, ghost, queue, save config.
-- Toggle row
local toggleRow = Instance.new("Frame")
toggleRow.Size = UDim2.new(1, 0, 0, 32)
toggleRow.Position = UDim2.new(0, 0, 0, 188)
toggleRow.BackgroundTransparency = 1; toggleRow.Parent = localPanel

local toggleRowLayout = Instance.new("UIListLayout")
toggleRowLayout.FillDirection = Enum.FillDirection.Horizontal
toggleRowLayout.Padding = UDim.new(0, 6)
toggleRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; toggleRowLayout.Parent = toggleRow

local anchorToggleBtn = Instance.new("TextButton")
anchorToggleBtn.Size = UDim2.new(0.5, -3, 1, 0)
anchorToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
anchorToggleBtn.Text = "? As Original"; anchorToggleBtn.TextColor3 = THEME.TextPrimary
anchorToggleBtn.TextSize = 12; anchorToggleBtn.Font = Enum.Font.GothamBold; anchorToggleBtn.AutoButtonColor = true
Instance.new("UICorner", anchorToggleBtn).CornerRadius = UDim.new(0, 6); anchorToggleBtn.Parent = toggleRow

anchorToggleBtn.MouseButton1Click:Connect(function()
	CONFIG.BuildAnchored = not CONFIG.BuildAnchored
	if CONFIG.BuildAnchored then
		anchorToggleBtn.Text = "? Fully Anchored"; anchorToggleBtn.BackgroundColor3 = THEME.Success
	else
		anchorToggleBtn.Text = "? As Original"; anchorToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 80)
	end
	saveConfig()
end)

local hyperToggleBtn = Instance.new("TextButton")
hyperToggleBtn.Size = UDim2.new(0.5, -3, 1, 0)
hyperToggleBtn.BackgroundColor3 = THEME.ButtonBg
hyperToggleBtn.Text = "?? Normal Mode"; hyperToggleBtn.TextColor3 = THEME.TextPrimary
hyperToggleBtn.TextSize = 12; hyperToggleBtn.Font = Enum.Font.GothamBold; hyperToggleBtn.AutoButtonColor = true
Instance.new("UICorner", hyperToggleBtn).CornerRadius = UDim.new(0, 6); hyperToggleBtn.Parent = toggleRow

hyperToggleBtn.MouseButton1Click:Connect(function()
	CONFIG.HyperMode = not CONFIG.HyperMode
	if CONFIG.HyperMode then
		hyperToggleBtn.Text = "?? HYPER MODE"; hyperToggleBtn.BackgroundColor3 = THEME.Danger
		notify("HYPER MODE enabled!")
	else
		hyperToggleBtn.Text = "?? Normal Mode"; hyperToggleBtn.BackgroundColor3 = THEME.ButtonBg
		notify("Normal mode enabled.")
	end
	saveConfig()
end)

-- Offset/Rotate/Scale row
local adjRow = Instance.new("Frame")
adjRow.Size = UDim2.new(1, 0, 0, 28)
adjRow.Position = UDim2.new(0, 0, 0, 222)
adjRow.BackgroundTransparency = 1; adjRow.Parent = localPanel

local adjRowLayout = Instance.new("UIListLayout")
adjRowLayout.FillDirection = Enum.FillDirection.Horizontal
adjRowLayout.Padding = UDim.new(0, 4)
adjRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; adjRowLayout.Parent = adjRow

local function makeOffsetBox(default, placeholder)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, 50, 1, 0); box.BackgroundColor3 = THEME.InputBg
	box.Text = tostring(default); box.PlaceholderText = placeholder
	box.TextColor3 = THEME.TextPrimary; box.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
	box.TextSize = 12; box.Font = Enum.Font.Gotham; box.ClearTextOnFocus = false
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4); box.Parent = adjRow
	return box
end

local offsetXBox = makeOffsetBox(0, "X")
local offsetYBox = makeOffsetBox(0, "Y")
local offsetZBox = makeOffsetBox(0, "Z")

local function updateOffset()
	local x = tonumber(offsetXBox.Text) or 0; local y = tonumber(offsetYBox.Text) or 0; local z = tonumber(offsetZBox.Text) or 0
	CONFIG.BuildOffset = Vector3.new(x, y, z); saveConfig()
end

offsetXBox.FocusLost:Connect(updateOffset); offsetYBox.FocusLost:Connect(updateOffset); offsetZBox.FocusLost:Connect(updateOffset)

local rotBtn = Instance.new("TextButton")
rotBtn.Size = UDim2.new(0, 36, 1, 0); rotBtn.BackgroundColor3 = THEME.ButtonBg
rotBtn.Text = "?"; rotBtn.TextColor3 = THEME.TextPrimary; rotBtn.TextSize = 14
rotBtn.Font = Enum.Font.GothamBold; rotBtn.AutoButtonColor = true
Instance.new("UICorner", rotBtn).CornerRadius = UDim.new(0, 4); rotBtn.Parent = adjRow

rotBtn.MouseButton1Click:Connect(function()
	CONFIG.BuildRot90 = CONFIG.BuildRot90 + 90
	if CONFIG.BuildRot90 >= 360 then CONFIG.BuildRot90 = 0 end
	notify("Rotation: " .. CONFIG.BuildRot90 .. " "); saveConfig()
end)

local scaleBox = Instance.new("TextBox")
scaleBox.Size = UDim2.new(0, 50, 1, 0); scaleBox.BackgroundColor3 = THEME.InputBg
scaleBox.Text = "1.0"; scaleBox.PlaceholderText = "Scale"
scaleBox.TextColor3 = THEME.TextPrimary; scaleBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 110)
scaleBox.TextSize = 12; scaleBox.Font = Enum.Font.Gotham; scaleBox.ClearTextOnFocus = false
Instance.new("UICorner", scaleBox).CornerRadius = UDim.new(0, 4); scaleBox.Parent = adjRow

scaleBox.FocusLost:Connect(function()
	local val = tonumber(scaleBox.Text) or 1; CONFIG.BuildScale = math.clamp(val, 0.1, 10)
	scaleBox.Text = tostring(CONFIG.BuildScale); saveConfig()
end)

-- Ghost preview row
local ghostRow = Instance.new("Frame")
ghostRow.Size = UDim2.new(1, 0, 0, 28)
ghostRow.Position = UDim2.new(0, 0, 0, 252)
ghostRow.BackgroundTransparency = 1; ghostRow.Parent = localPanel

local ghostRowLayout = Instance.new("UIListLayout")
ghostRowLayout.FillDirection = Enum.FillDirection.Horizontal
ghostRowLayout.Padding = UDim.new(0, 6)
ghostRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; ghostRowLayout.Parent = ghostRow

local previewBtn = Instance.new("TextButton")
previewBtn.Size = UDim2.new(0.5, -3, 1, 0); previewBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 80)
previewBtn.Text = "?? Preview"; previewBtn.TextColor3 = THEME.TextPrimary
previewBtn.TextSize = 12; previewBtn.Font = Enum.Font.GothamBold; previewBtn.AutoButtonColor = true
Instance.new("UICorner", previewBtn).CornerRadius = UDim.new(0, 6); previewBtn.Parent = ghostRow

local clearGhostBtn = Instance.new("TextButton")
clearGhostBtn.Size = UDim2.new(0.5, -3, 1, 0); clearGhostBtn.BackgroundColor3 = THEME.Danger
clearGhostBtn.Text = "? Clear"; clearGhostBtn.TextColor3 = THEME.TextPrimary
clearGhostBtn.TextSize = 12; clearGhostBtn.Font = Enum.Font.GothamBold; clearGhostBtn.AutoButtonColor = true
Instance.new("UICorner", clearGhostBtn).CornerRadius = UDim.new(0, 6); clearGhostBtn.Parent = ghostRow

-- Queue row
local queueRow = Instance.new("Frame")
queueRow.Size = UDim2.new(1, 0, 0, 28)
queueRow.Position = UDim2.new(0, 0, 0, 282)
queueRow.BackgroundTransparency = 1; queueRow.Parent = localPanel

local queueRowLayout = Instance.new("UIListLayout")
queueRowLayout.FillDirection = Enum.FillDirection.Horizontal
queueRowLayout.Padding = UDim.new(0, 6)
queueRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; queueRowLayout.Parent = queueRow

local queueBtn = Instance.new("TextButton")
queueBtn.Size = UDim2.new(0.5, -3, 1, 0); queueBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 40)
queueBtn.Text = "?? Queue"; queueBtn.TextColor3 = THEME.TextPrimary
queueBtn.TextSize = 12; queueBtn.Font = Enum.Font.GothamBold; queueBtn.AutoButtonColor = true
Instance.new("UICorner", queueBtn).CornerRadius = UDim.new(0, 6); queueBtn.Parent = queueRow

local buildAllBtn = Instance.new("TextButton")
buildAllBtn.Size = UDim2.new(0.5, -3, 1, 0); buildAllBtn.BackgroundColor3 = THEME.Success
buildAllBtn.Text = "?? Build All (0 in queue)"; buildAllBtn.TextColor3 = THEME.TextPrimary
buildAllBtn.TextSize = 11; buildAllBtn.Font = Enum.Font.GothamBold; buildAllBtn.AutoButtonColor = true
Instance.new("UICorner", buildAllBtn).CornerRadius = UDim.new(0, 6); buildAllBtn.Parent = queueRow

-- Save Config
local saveCfgBtn = Instance.new("TextButton")
saveCfgBtn.Size = UDim2.new(1, 0, 0, 28)
saveCfgBtn.Position = UDim2.new(0, 0, 0, 312)
saveCfgBtn.BackgroundColor3 = THEME.ButtonBg
saveCfgBtn.Text = "?? Save Config"; saveCfgBtn.TextColor3 = THEME.TextPrimary
saveCfgBtn.TextSize = 12; saveCfgBtn.Font = Enum.Font.GothamBold; saveCfgBtn.AutoButtonColor = true
Instance.new("UICorner", saveCfgBtn).CornerRadius = UDim.new(0, 6); saveCfgBtn.Parent = localPanel

saveCfgBtn.MouseButton1Click:Connect(function() saveConfig(); notify("Config saved!") end)

-- Build button (at bottom of mainFrame)
local buildBtn = Instance.new("TextButton")
buildBtn.Size = UDim2.new(1, -20, 0, 38)
buildBtn.Position = UDim2.new(0, 10, 1, -40)
buildBtn.BackgroundColor3 = THEME.Success; buildBtn.Text = "?? Build Selected"
buildBtn.TextColor3 = THEME.TextPrimary; buildBtn.TextSize = 15; buildBtn.Font = Enum.Font.GothamBold
buildBtn.AutoButtonColor = true; buildBtn.Visible = false
Instance.new("UICorner", buildBtn).CornerRadius = UDim.new(0, 8); buildBtn.Parent = mainFrame

-- State variables
local selectedBuildData = nil; local selectedBuildName = nil
local buildQueue = {}; local ghostActive = false; local ghostFolder = nil; local ghostParts = {}

-- ==================== LOCAL FILE LOADING ====================
local function clearFileList()
	for _, child in ipairs(fileListScroll:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function addLocalFile(filename)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 36)
	btn.BackgroundColor3 = THEME.TitleBar
	btn.Text = "?? " .. filename:match("([^/\\\\]+)$")
	btn.TextColor3 = THEME.TextSecondary; btn.TextSize = 12; btn.Font = Enum.Font.Gotham
	btn.TextXAlignment = Enum.TextXAlignment.Left; btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6); btn.Parent = fileListScroll

	btn.MouseButton1Click:Connect(function()
		for _, b in ipairs(fileListScroll:GetChildren()) do
			if b:IsA("TextButton") then b.BackgroundColor3 = THEME.TitleBar; b.TextColor3 = THEME.TextSecondary end
		end
		btn.BackgroundColor3 = Color3.fromRGB(0, 100, 60); btn.TextColor3 = THEME.TextPrimary

		local ok, content = pcall(function() return readfile(filename) end)
		if ok then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(content) end)
			if parseOk then
				selectedBuildData = data; selectedBuildName = filename:match("([^/\\\\]+)$")
				local pc = data.PartCount or (data.Parts and #data.Parts) or 0
				statusLabel.Text = "Selected: " .. selectedBuildName .. " (" .. pc .. " parts)"
				buildBtn.Visible = true; notify("Loaded: " .. selectedBuildName)
			else notify("Invalid JSON file!") end
		else notify("Failed to read file!") end
	end)
end

refreshLocalBtn.MouseButton1Click:Connect(function()
	clearFileList(); selectedBuildData = nil; buildBtn.Visible = false
	statusLabel.Text = "Scanning local files..."
	if not isfolder(CONFIG.LocalFolder) then
		statusLabel.Text = "No BuildExports folder found"; notify("No local builds found!"); return
	end
	local files = safeListFiles(CONFIG.LocalFolder); local count = 0
	for _, file in ipairs(files) do
		if file:lower():match("%.json$") then addLocalFile(file); count = count + 1 end
	end
	statusLabel.Text = string.format("Found %d build files", count); notify(string.format("Found %d local builds", count))
end)

-- ==================== GITHUB LOADING ====================
local function addGithubFile(name, url)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 36)
	btn.BackgroundColor3 = THEME.TitleBar; btn.Text = "?? " .. name
	btn.TextColor3 = THEME.TextSecondary; btn.TextSize = 12; btn.Font = Enum.Font.Gotham
	btn.TextXAlignment = Enum.TextXAlignment.Left; btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6); btn.Parent = fileListScroll

	btn.MouseButton1Click:Connect(function()
		for _, b in ipairs(fileListScroll:GetChildren()) do
			if b:IsA("TextButton") then b.BackgroundColor3 = THEME.TitleBar; b.TextColor3 = THEME.TextSecondary end
		end
		btn.BackgroundColor3 = Color3.fromRGB(0, 100, 60); btn.TextColor3 = THEME.TextPrimary
		statusLabel.Text = "Downloading " .. name .. "..."

		local content = safeHttpGet(url)
		if content then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(content) end)
			if parseOk then
				selectedBuildData = data; selectedBuildName = name
				local pc = data.PartCount or (data.Parts and #data.Parts) or 0
				statusLabel.Text = "Selected: " .. name .. " (" .. pc .. " parts)"
				buildBtn.Visible = true; notify("Loaded from GitHub: " .. name)
				pcall(function()
					if not isfolder(CONFIG.LocalFolder) then makefolder(CONFIG.LocalFolder) end
					writefile(CONFIG.LocalFolder .. "/" .. name, content)
				end)
			else notify("Invalid JSON from GitHub!"); statusLabel.Text = "Invalid JSON" end
		else notify("Failed to download from GitHub!"); statusLabel.Text = "Download failed" end
	end)
end

fetchGithubBtn.MouseButton1Click:Connect(function()
	clearFileList(); selectedBuildData = nil; buildBtn.Visible = false; statusLabel.Text = "Fetching from GitHub..."
	local repo = githubInput.Text:gsub("%s+", ""); if repo == "" then repo = CONFIG.GitHubRepo end
	local apiUrl = "https://api.github.com/repos/" .. repo .. "/contents/"
	local response = safeHttpGet(apiUrl)
	if not response then notify("Failed to fetch GitHub repo!"); statusLabel.Text = "GitHub fetch failed"; return end
	local parseOk, files = pcall(function() return HttpService:JSONDecode(response) end)
	if not parseOk then notify("Failed to parse GitHub response!"); statusLabel.Text = "Parse failed"; return end
	local count = 0
	for _, file in ipairs(files) do
		if file.type == "file" and file.name:match("%.json$") then addGithubFile(file.name, file.download_url); count = count + 1 end
	end
	statusLabel.Text = string.format("Found %d builds on GitHub", count); notify(string.format("Found %d GitHub builds", count))
end)

-- ==================== 10. PROPERTY APPLIER ====================
local function applyF3XMesh(part, meshData)
	if not part or not part:FindFirstAncestorOfClass("DataModel") then return false end
	local mc = {Part = part}
	for k, v in pairs(meshData) do if k ~= "_meshCount" then mc[k] = v end end
	local createOk = pcall(function() F3X:Invoke("CreateMeshes", {{Part = part}}) end)
	if not createOk then return false end
	return pcall(function() F3X:Invoke("SyncMesh", {mc}) end)
end
local function applyPartProperties(part, partData, cf, partMap)
	local resizeChanges = {}; local colorChanges = {}; local materialChanges = {}
	local surfaceChanges = {}; local anchorChanges = {}; local collisionChanges = {}

	if partData.Size then
		local size = parseVector3(partData.Size) * CONFIG.BuildScale
		resizeChanges[#resizeChanges + 1] = {Part = part, Size = size, CFrame = cf}
	end
	if partData.Color then
		local color = parseColor3(partData.Color)
		colorChanges[#colorChanges + 1] = {Part = part, Color = color}
	end
	local matData = {Part = part}
	if partData.Material then matData.Material = parseMaterial(partData.Material) end
	if partData.Transparency ~= nil then matData.Transparency = partData.Transparency end
	if partData.Reflectance ~= nil then matData.Reflectance = partData.Reflectance end
	if next(matData) then materialChanges[#materialChanges + 1] = matData end

	local shouldAnchor = CONFIG.BuildAnchored or (partData.Anchored == true)
	anchorChanges[#anchorChanges + 1] = {Part = part, Anchored = shouldAnchor}
	if partData.CanCollide ~= nil then collisionChanges[#collisionChanges + 1] = {Part = part, CanCollide = partData.CanCollide} end

	local surfaces = {}
	if partData.TopSurface then surfaces.Top = parseSurface(partData.TopSurface) end
	if partData.BottomSurface then surfaces.Bottom = parseSurface(partData.BottomSurface) end
	if partData.LeftSurface then surfaces.Left = parseSurface(partData.LeftSurface) end
	if partData.RightSurface then surfaces.Right = parseSurface(partData.RightSurface) end
	if partData.FrontSurface then surfaces.Front = parseSurface(partData.FrontSurface) end
	if partData.BackSurface then surfaces.Back = parseSurface(partData.BackSurface) end
	if next(surfaces) then surfaceChanges[#surfaceChanges + 1] = {Part = part, Surfaces = surfaces} end

	pcall(function() if #resizeChanges > 0 then F3XRetry("SyncResize", resizeChanges) end end)
	pcall(function() if #colorChanges > 0 then F3XRetry("SyncColor", colorChanges) end end)
	pcall(function() if #materialChanges > 0 then F3XRetry("SyncMaterial", materialChanges) end end)
	pcall(function() if #surfaceChanges > 0 then F3XRetry("SyncSurface", surfaceChanges) end end)
	pcall(function() if #anchorChanges > 0 then F3XRetry("SyncAnchor", anchorChanges) end end)
	pcall(function() if #collisionChanges > 0 then F3XRetry("SyncCollision", collisionChanges) end end)

	if partData.Name then pcall(function() F3XRetry("SetName", {part}, partData.Name) end) end
	if partData.Locked ~= nil then pcall(function() F3XRetry("SetLocked", {part}, partData.Locked) end) end

	if partData.CastShadow ~= nil then part.CastShadow = partData.CastShadow end
	if partData.Shape then
		local shapeName = partData.Shape:match("Enum%.PartType%.(.+)") or partData.Shape
		if shapeName == "Cylinder" then
			local mc = {Part = part, MeshType = Enum.MeshType.Cylinder, Scale = Vector3.new(1, 1, 1), Offset = Vector3.new(0, 0, 0)}
			pcall(function() F3X:Invoke("CreateMeshes", {{Part = part}}) end)
			pcall(function() F3X:Invoke("SyncMesh", {mc}) end)
		elseif shapeName == "Ball" then
			local mc = {Part = part, MeshType = Enum.MeshType.Sphere, Scale = Vector3.new(1, 1, 1), Offset = Vector3.new(0, 0, 0)}
			pcall(function() F3X:Invoke("CreateMeshes", {{Part = part}}) end)
			pcall(function() F3X:Invoke("SyncMesh", {mc}) end)
		else
			pcall(function() part.Shape = parseShape(partData.Shape) end)
		end
	end
	if partData.Massless ~= nil then part.Massless = partData.Massless end
	if partData.CollisionGroupId then part.CollisionGroupId = partData.CollisionGroupId end
	if partData.CustomPhysicalProperties then
		local cpp = partData.CustomPhysicalProperties
		pcall(function() part.CustomPhysicalProperties = PhysicalProperties.new(cpp.Density or 0.7, cpp.Friction or 0.3, cpp.Elasticity or 0.5, cpp.FrictionWeight or 1, cpp.ElasticityWeight or 1) end)
	end

	local className = partData.ClassName or "Part"
	if className == "MeshPart" then
		-- F3X can only create Parts, so create a SpecialMesh(FileMesh) child
		if partData.MeshId and isValidAssetUrl(partData.MeshId) then
			applyF3XMesh(part, {MeshType = Enum.MeshType.FileMesh, MeshId = partData.MeshId, TextureId = partData.TextureID or "", Scale = Vector3.new(1, 1, 1), Offset = Vector3.new(0, 0, 0)})
		end
	end

	if partData.Children then
		for _, cd in ipairs(partData.Children) do
			pcall(function()
				if cd.ClassName == "Decal" or cd.ClassName == "Texture" then
					if not cd.Texture or not isValidAssetUrl(cd.Texture) then return end
					F3XRetry("CreateTextures", {{Part = part, Face = parseNormalId(cd.Face), TextureType = "Decal"}})
					local tc = {Part = part, Face = parseNormalId(cd.Face), TextureType = "Decal"}
					tc.Texture = cd.Texture
					if cd.Transparency ~= nil then tc.Transparency = cd.Transparency end
					F3XRetry("SyncTexture", {tc})
				elseif cd.ClassName == "SpecialMesh" then
					if CONFIG.Debug then print("Applying SpecialMesh to", part.Name, "MeshType:", cd.MeshType, "Scale:", cd.Scale and table.concat(cd.Scale, ",") or "nil", "Offset:", cd.Offset and table.concat(cd.Offset, ",") or "nil", "MeshId:", cd.MeshId or "nil", "TextureId:", cd.TextureId or "nil") end
					local meshData = {}
					if cd.MeshType then
						local ok, mt = pcall(function() return parseMeshType(cd.MeshType) end)
						if ok then meshData.MeshType = mt end
					end
					if cd.MeshId and cd.MeshId ~= "" and isValidAssetUrl(cd.MeshId) then meshData.MeshId = cd.MeshId end
					if cd.TextureId and cd.TextureId ~= "" and isValidAssetUrl(cd.TextureId) then meshData.TextureId = cd.TextureId end
					if cd.Scale then
						local ok, s = pcall(function() return parseVector3(cd.Scale) end)
						meshData.Scale = ok and s or Vector3.new(1, 1, 1)
					else meshData.Scale = Vector3.new(1, 1, 1) end
					if cd.Offset then
						local ok, o = pcall(function() return parseVector3(cd.Offset) end)
						meshData.Offset = ok and o or Vector3.new(0, 0, 0)
					else meshData.Offset = Vector3.new(0, 0, 0) end
					applyF3XMesh(part, meshData)
				elseif cd.ClassName == "BlockMesh" then
					local bmS = Vector3.new(1, 1, 1)
					if cd.Scale then local ok, v = pcall(parseVector3, cd.Scale); if ok then bmS = v end end
					local bmO = Vector3.new(0, 0, 0)
					if cd.Offset then local ok, v = pcall(parseVector3, cd.Offset); if ok then bmO = v end end
					applyF3XMesh(part, {MeshType = Enum.MeshType.Brick, Scale = bmS, Offset = bmO})
				elseif cd.ClassName == "CylinderMesh" then
					local cmS = Vector3.new(1, 1, 1)
					if cd.Scale then local ok, v = pcall(parseVector3, cd.Scale); if ok then cmS = v end end
					local cmO = Vector3.new(0, 0, 0)
					if cd.Offset then local ok, v = pcall(parseVector3, cd.Offset); if ok then cmO = v end end
					applyF3XMesh(part, {MeshType = Enum.MeshType.Cylinder, Scale = cmS, Offset = cmO})
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
				elseif cd.ClassName == "Weld" or cd.ClassName == "WeldConstraint" then
					if cd.Part0Index and cd.Part1Index and partMap then
						local p0 = partMap[cd.Part0Index]; local p1 = partMap[cd.Part1Index]
						if p0 and p1 then pcall(function() F3XRetry("CreateWelds", {p0}, p1) end) end
					end
				end
			end)
		end
	end
end

-- ==================== 9. BUILD AUTOMATION ====================
local function calculateBuildCenter(parts)
	if not parts or #parts == 0 then return Vector3.new(0, 50, 0) end
	local sumX, sumY, sumZ = 0, 0, 0; local count = 0
	for _, partData in ipairs(parts) do
		local cfData = partData.CFrame
		if cfData then local pos = getCFramePosition(cfData); sumX = sumX + pos.X; sumY = sumY + pos.Y; sumZ = sumZ + pos.Z; count = count + 1 end
	end
	if count == 0 then return Vector3.new(0, 50, 0) end
	return Vector3.new(sumX / count, sumY / count, sumZ / count)
end

local function teleportToBuild(targetPosition)
	local char = player.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local tp = targetPosition + Vector3.new(0, 30, 0)
	hrp.CFrame = CFrame.new(tp); camera.CFrame = CFrame.new(tp, targetPosition)
end

-- ==================== 11. BUILD ENGINE ====================
local function getPartType(className)
	if className == "WedgePart" then return "Wedge"
	elseif className == "CornerWedgePart" then return "Corner"
	elseif className == "TrussPart" then return "Truss"
	elseif className == "Seat" then return "Seat"
	elseif className == "VehicleSeat" then return "Vehicle Seat"
	elseif className == "SpawnLocation" then return "Spawn"
	elseif className == "MeshPart" then return "Normal" end
	return "Normal"
end

local function applyBuildTransform(cf)
	local result = cf + CONFIG.BuildOffset
	if CONFIG.BuildRot90 ~= 0 then result = result * CFrame.Angles(0, math.rad(CONFIG.BuildRot90), 0) end
	return result
end

local function normalBuild(parts, total, partMap)
	local batchSize = CONFIG.BatchSize; local buildSpeed = CONFIG.BuildSpeed; local failedCount = 0
	for i, partData in ipairs(parts) do
		if not F3X:ValidateTool() then task.wait(1); F3X:ValidateTool() end
		local className = partData.ClassName or "Part"; local partType = getPartType(className)
		local cf = applyBuildTransform(parseCFrame(partData.CFrame))
		local part; local createOk = pcall(function() part = F3XRetry("CreatePart", partType, CFrame.new(0, 5000 + i * 10, 0)) end)
		if not createOk or not part then failedCount = failedCount + 1
		else
			partMap[i] = part
			local moveOk = pcall(function() F3XRetry("SyncMove", {{Part = part, CFrame = cf}}) end)
			if not moveOk then pcall(function() part.CFrame = cf end) end
			applyPartProperties(part, partData, cf, partMap)
		end
		local hasMesh = false
		if partData.Children then
			for _, cd in ipairs(partData.Children) do
				if cd.ClassName == "SpecialMesh" or cd.ClassName == "BlockMesh" or cd.ClassName == "CylinderMesh" then hasMesh = true; break end
			end
		end
		if hasMesh then task.wait(0.03) end
		if i % batchSize == 0 or i == total then
			progressFill.Size = UDim2.new(i / total, 0, 1, 0)
			statusLabel.Text = string.format("Building... %d/%d parts (%d failed) [batch:%d delay:%.4fs]", i, total, failedCount, batchSize, buildSpeed)
			if buildSpeed > 0 then task.wait(buildSpeed) end
		end
	end
	return failedCount
end

local function hyperBuild(parts, total, partMap)
	local threadCount = CONFIG.HyperThreads; local batchSize = CONFIG.BatchSize; local buildSpeed = CONFIG.BuildSpeed
	local failedCount = 0; local completedCount = 0
	local chunks = {}; for t = 1, threadCount do chunks[t] = {} end
	for i, partData in ipairs(parts) do
		local ci = ((i - 1) % threadCount) + 1; chunks[ci][#chunks[ci] + 1] = {Index = i, Data = partData}
	end
		local function buildChunk(chunkParts)
		for _, entry in ipairs(chunkParts) do
			local i = entry.Index; local partData = entry.Data
			local partType = getPartType(partData.ClassName or "Part")
			local cf = applyBuildTransform(parseCFrame(partData.CFrame))
			if not F3X:ValidateTool() then task.wait(1); F3X:ValidateTool() end
			local part; local createOk = pcall(function() part = F3XRetry("CreatePart", partType, CFrame.new(0, 5000 + i * 10, 0)) end)
			if not createOk or not part then failedCount = failedCount + 1
			else
				partMap[i] = part
				local moveOk = pcall(function() F3XRetry("SyncMove", {{Part = part, CFrame = cf}}) end)
				if not moveOk then pcall(function() part.CFrame = cf end) end
				applyPartProperties(part, partData, cf, partMap)
			end
			local hasMesh = false
			if partData.Children then
				for _, cd in ipairs(partData.Children) do
					if cd.ClassName == "SpecialMesh" or cd.ClassName == "BlockMesh" or cd.ClassName == "CylinderMesh" then hasMesh = true; break end
				end
			end
			if hasMesh then task.wait(0.03) end
			completedCount = completedCount + 1
			if completedCount % (batchSize * threadCount) == 0 or completedCount >= total then
				progressFill.Size = UDim2.new(completedCount / total, 0, 1, 0)
				statusLabel.Text = string.format("?? HYPER BUILD... %d/%d parts (%d failed) [threads:%d]", completedCount, total, failedCount, threadCount)
			end
			if buildSpeed > 0 then task.wait(buildSpeed) end
		end
	end
	local threads = {}; for t = 1, threadCount do threads[t] = task.spawn(function() buildChunk(chunks[t]) end) end
	for t = 1, threadCount do while coroutine.status(threads[t]) ~= "dead" do task.wait(0.1) end end
	return failedCount
end

-- ==================== 12. GHOST PREVIEW SYSTEM ====================
local function buildGhost()
	if ghostActive and ghostFolder then ghostFolder:Destroy(); ghostParts = {}; ghostActive = false end
	if not selectedBuildData or not selectedBuildData.Parts then notify("No build selected!"); return end
	local parts = selectedBuildData.Parts; local total = #parts; if total == 0 then return end
	ghostFolder = Instance.new("Folder"); ghostFolder.Name = "F3XGhostPreview"; ghostFolder.Parent = workspace
	local sampleRate = math.max(1, math.floor(total / CONFIG.GhostLimit)); local shown = 0
	local minPos = Vector3.new(math.huge, math.huge, math.huge); local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)
	for i, partData in ipairs(parts) do
		if i == 1 or i == total or i % sampleRate == 0 then
			if shown < CONFIG.GhostLimit then
				local cf = applyBuildTransform(parseCFrame(partData.CFrame))
				local size = parseVector3(partData.Size or Vector3.new(1, 1, 1)) * CONFIG.BuildScale
				local g = Instance.new("Part"); g.Name = "Ghost_" .. i
				g.Size = size; g.CFrame = cf; g.Anchored = true; g.CanCollide = false; g.CanQuery = false; g.CanTouch = false
				g.Transparency = 0.85; g.Color = THEME.GhostColor; g.Material = Enum.Material.ForceField; g.CastShadow = false
				g.Parent = ghostFolder; ghostParts[i] = g; shown = shown + 1
			end
		end
		local cf = parseCFrame(partData.CFrame); local pos = cf.Position
		if pos.X < minPos.X then minPos = Vector3.new(pos.X, minPos.Y, minPos.Z) end
		if pos.Y < minPos.Y then minPos = Vector3.new(minPos.X, pos.Y, minPos.Z) end
		if pos.Z < minPos.Z then minPos = Vector3.new(minPos.X, minPos.Y, pos.Z) end
		if pos.X > maxPos.X then maxPos = Vector3.new(pos.X, maxPos.Y, maxPos.Z) end
		if pos.Y > maxPos.Y then maxPos = Vector3.new(maxPos.X, pos.Y, maxPos.Z) end
		if pos.Z > maxPos.Z then maxPos = Vector3.new(maxPos.X, maxPos.Y, pos.Z) end
	end
	local bs = (maxPos - minPos)
	if bs.Magnitude > 0 then
		local center = (minPos + maxPos) / 2
		local bp = Instance.new("Part"); bp.Name = "GhostBounds"
		bp.Size = bs + Vector3.new(2, 2, 2); bp.CFrame = CFrame.new(center)
		bp.Anchored = true; bp.CanCollide = false; bp.Transparency = 0.95; bp.Color = THEME.BoundsColor
		bp.Material = Enum.Material.SmoothPlastic; bp.CastShadow = false; bp.Parent = ghostFolder; ghostParts.bounds = bp
		local box = Instance.new("SelectionBox"); box.Color3 = THEME.BoundsColor; box.LineThickness = 0.05; box.Adornee = bp; box.Parent = bp
	end
	ghostActive = true; notify("Ghost preview created (" .. shown .. " parts)")
end

local function clearGhost()
	if ghostFolder then ghostFolder:Destroy(); ghostFolder = nil end
	ghostParts = {}; ghostActive = false
end

previewBtn.MouseButton1Click:Connect(buildGhost)
clearGhostBtn.MouseButton1Click:Connect(clearGhost)

-- ==================== 13. SETTINGS TAB ====================
do
	local yPos = 0
	local function makeSettingLabel(text)
		local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, 0, 0, 24)
		l.Position = UDim2.new(0, 0, 0, yPos); l.BackgroundTransparency = 1
		l.Text = text; l.TextColor3 = THEME.TextSecondary; l.TextSize = 13
		l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = settingsTab
		yPos = yPos + 28; return l
	end

	makeSettingLabel("GitHub Repository:")
	local repoInput = Instance.new("TextBox")
	repoInput.Size = UDim2.new(1, 0, 0, 28)
	repoInput.Position = UDim2.new(0, 0, 0, yPos)
	repoInput.BackgroundColor3 = THEME.InputBg; repoInput.Text = CONFIG.GitHubRepo
	repoInput.PlaceholderText = "user/repo"
	repoInput.TextColor3 = THEME.TextPrimary; repoInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
	repoInput.TextSize = 12; repoInput.Font = Enum.Font.Gotham; repoInput.ClearTextOnFocus = false
	Instance.new("UICorner", repoInput).CornerRadius = UDim.new(0, 6); repoInput.Parent = settingsTab
	repoInput.FocusLost:Connect(function() CONFIG.GitHubRepo = repoInput.Text:gsub("%s+", ""); saveConfig() end)
	yPos = yPos + 36

	makeSettingLabel("GitHub Branch:")
	local branchInput = Instance.new("TextBox")
	branchInput.Size = UDim2.new(1, 0, 0, 28)
	branchInput.Position = UDim2.new(0, 0, 0, yPos)
	branchInput.BackgroundColor3 = THEME.InputBg; branchInput.Text = CONFIG.GitHubBranch
	branchInput.PlaceholderText = "main"
	branchInput.TextColor3 = THEME.TextPrimary; branchInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
	branchInput.TextSize = 12; branchInput.Font = Enum.Font.Gotham; branchInput.ClearTextOnFocus = false
	Instance.new("UICorner", branchInput).CornerRadius = UDim.new(0, 6); branchInput.Parent = settingsTab
	branchInput.FocusLost:Connect(function() CONFIG.GitHubBranch = branchInput.Text:gsub("%s+", ""); saveConfig() end)
	yPos = yPos + 36

	local function makeSettingToggle(text, configKey)
		local frame = Instance.new("Frame"); frame.Size = UDim2.new(1, 0, 0, 28)
		frame.Position = UDim2.new(0, 0, 0, yPos); frame.BackgroundTransparency = 1; frame.Parent = settingsTab
		local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(0.7, -5, 1, 0); lbl.BackgroundTransparency = 1
		lbl.Text = text; lbl.TextColor3 = THEME.TextSecondary; lbl.TextSize = 12; lbl.Font = Enum.Font.Gotham
		lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = frame
		local btn = Instance.new("TextButton"); btn.Size = UDim2.new(0.3, -5, 1, 0)
		btn.Position = UDim2.new(0.7, 5, 0, 0)
		btn.BackgroundColor3 = CONFIG[configKey] and THEME.Success or THEME.Danger
		btn.Text = CONFIG[configKey] and "ON" or "OFF"
		btn.TextColor3 = THEME.TextPrimary; btn.TextSize = 11; btn.Font = Enum.Font.GothamBold
		btn.AutoButtonColor = true
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6); btn.Parent = frame
		btn.MouseButton1Click:Connect(function()
			CONFIG[configKey] = not CONFIG[configKey]
			btn.BackgroundColor3 = CONFIG[configKey] and THEME.Success or THEME.Danger
			btn.Text = CONFIG[configKey] and "ON" or "OFF"; saveConfig()
		end)
		yPos = yPos + 32
	end

	makeSettingToggle("Debug Mode", "Debug"); makeSettingToggle("Sound FX", "SoundEnabled")

	local clearHistBtn = Instance.new("TextButton")
	clearHistBtn.Size = UDim2.new(1, 0, 0, 30)
	clearHistBtn.Position = UDim2.new(0, 0, 0, yPos)
	clearHistBtn.BackgroundColor3 = THEME.Warning; clearHistBtn.Text = "??? Clear History"
	clearHistBtn.TextColor3 = THEME.TextPrimary; clearHistBtn.TextSize = 12; clearHistBtn.Font = Enum.Font.GothamBold
	clearHistBtn.AutoButtonColor = true
	Instance.new("UICorner", clearHistBtn).CornerRadius = UDim.new(0, 6); clearHistBtn.Parent = settingsTab
	clearHistBtn.MouseButton1Click:Connect(function() notify("History cleared") end)
	yPos = yPos + 38

	local resetCfgBtn = Instance.new("TextButton")
	resetCfgBtn.Size = UDim2.new(1, 0, 0, 30)
	resetCfgBtn.Position = UDim2.new(0, 0, 0, yPos)
	resetCfgBtn.BackgroundColor3 = THEME.Danger; resetCfgBtn.Text = "?? Reset Config"
	resetCfgBtn.TextColor3 = THEME.TextPrimary; resetCfgBtn.TextSize = 12; resetCfgBtn.Font = Enum.Font.GothamBold
	resetCfgBtn.AutoButtonColor = true
	Instance.new("UICorner", resetCfgBtn).CornerRadius = UDim.new(0, 6); resetCfgBtn.Parent = settingsTab
	resetCfgBtn.MouseButton1Click:Connect(function()
		CONFIG = {GitHubRepo = "UnAliveScripts/f3xbuildsjson", GitHubBranch = "main", LocalFolder = "BuildExports", BuildSpeed = 0.005, BatchSize = 10, BtoolsTimeout = 12, Debug = true, BuildAnchored = false, HyperMode = false, HyperThreads = 4, BuildOffset = Vector3.new(0, 0, 0), BuildRot90 = 0, BuildScale = 1, AutoAnchorAfter = false, PreserveHierarchy = true, IncludeWelds = true, IncludeDecals = true, IncludeMeshes = true, IncludeLights = true, MaxParts = 100000, VisualLimit = 500, DragThreshold = 5, StreamBatch = 2000, FileChunkSize = 5000, ListCap = 500, GhostLimit = 200, SoundEnabled = true}
		saveConfig(); notify("Config reset!")
	end)
end

-- ==================== 14. SELECTION SYSTEM ====================
local selectedParts = {}; local selectedSet = {}; local selectionBoxes = {}
local selectionEnabled = true; local isDragging = false; local dragStartPos = nil
local dragCurrentPos = nil; local clickMode = false; local clickTarget = nil
local mouseDownPos = nil; local exportInProgress = false

local function updateCount()
	if countText then countText.Text = string.format("%d parts", #selectedParts) end
end

local function setVisual(part, enabled)
	if enabled then
		if #selectionBoxes >= CONFIG.VisualLimit then return end
		if selectionBoxes[part] then return end
		local box = Instance.new("SelectionBox")
		box.Color3 = Color3.fromRGB(80, 180, 255); box.LineThickness = 0.04
		box.Adornee = part; box.Parent = part; selectionBoxes[part] = box
	else
		if selectionBoxes[part] then selectionBoxes[part]:Destroy(); selectionBoxes[part] = nil end
	end
end

local function clearSelection()
	for part, box in pairs(selectionBoxes) do
		if box then pcall(function() box:Destroy() end) end
	end
	selectedParts = {}; selectedSet = {}; selectionBoxes = {}; updateCount()
	if resetListPool then resetListPool() end
end

local function addPart(part)
	if #selectedParts >= CONFIG.MaxParts then return end
	if selectedSet[part] then return end
	selectedParts[#selectedParts + 1] = part; selectedSet[part] = true
	setVisual(part, true); updateCount()
	if addListItem then addListItem(part.Name, part.ClassName) end
end

local function removePart(part)
	if not selectedSet[part] then return end
	selectedSet[part] = nil
	for i = 1, #selectedParts do
		if selectedParts[i] == part then table.remove(selectedParts, i); break end
	end
	setVisual(part, false); updateCount()
	if refreshList then refreshList() end
end

local function getPartUnderMouse()
	local mPos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mPos.X, mPos.Y)
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Blacklist
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
	local centerScreen, onScreen = camera:WorldToViewportPoint(part.Position)
	if onScreen and centerScreen.X >= minX and centerScreen.X <= maxX and centerScreen.Y >= minY and centerScreen.Y <= maxY then return true end
	local size = part.Size / 2; local cf = part.CFrame
	for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
		local corner = cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
		local sp, vis = camera:WorldToViewportPoint(corner)
		if vis and sp.X >= minX and sp.X <= maxX and sp.Y >= minY and sp.Y <= maxY then return true end
	end end end
	return false
end

local function getSelectionBounds(parts)
	if #parts == 0 then return CFrame.new(0, 50, 0), Vector3.new(1, 1, 1) end
	local minPos = Vector3.new(math.huge, math.huge, math.huge); local maxPos = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(parts) do
		if p and p:IsA("BasePart") then
			local pos = p.Position; local half = p.Size / 2
			for _, sign in ipairs({{1, 1, 1}, {-1, 1, 1}, {1, -1, 1}, {1, 1, -1}, {-1, -1, 1}, {1, -1, -1}, {-1, 1, -1}, {-1, -1, -1}}) do
				local c = pos + Vector3.new(half.X * sign[1], half.Y * sign[2], half.Z * sign[3])
				if c.X < minPos.X then minPos = Vector3.new(c.X, minPos.Y, minPos.Z) end
				if c.Y < minPos.Y then minPos = Vector3.new(minPos.X, c.Y, minPos.Z) end
				if c.Z < minPos.Z then minPos = Vector3.new(minPos.X, minPos.Y, c.Z) end
				if c.X > maxPos.X then maxPos = Vector3.new(c.X, maxPos.Y, maxPos.Z) end
				if c.Y > maxPos.Y then maxPos = Vector3.new(minPos.X, c.Y, maxPos.Z) end
				if c.Z > maxPos.Z then maxPos = Vector3.new(minPos.X, minPos.Y, c.Z) end
			end
		end
	end
	return CFrame.new((minPos + maxPos) / 2), maxPos - minPos + Vector3.new(1, 1, 1)
end

local exportBuildToJSON, exportBuildToLua
-- ==================== SELECTOR UI ====================
local selectorScroll = Instance.new("ScrollingFrame")
selectorScroll.Size = UDim2.new(1, -10, 1, -210)
selectorScroll.Position = UDim2.new(0, 5, 0, 5)
selectorScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
selectorScroll.BorderSizePixel = 0; selectorScroll.ScrollBarThickness = 4
selectorScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 70)
selectorScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
selectorScroll.CanvasSize = UDim2.new(0, 0, 0, 0); selectorScroll.Parent = selectorTab
Instance.new("UICorner", selectorScroll).CornerRadius = UDim.new(0, 8)

local selListLayout = Instance.new("UIListLayout")
selListLayout.Padding = UDim.new(0, 3); selListLayout.Parent = selectorScroll

local listItemPool = {}; local listItemUsed = 0
local function getListItem()
	listItemUsed = listItemUsed + 1
	if listItemPool[listItemUsed] then listItemPool[listItemUsed].Frame.Visible = true; return listItemPool[listItemUsed] end
	local row = Instance.new("Frame"); row.Size = UDim2.new(1, -10, 0, 26); row.BackgroundTransparency = 1; row.Parent = selectorScroll
	local dot = Instance.new("TextLabel"); dot.Size = UDim2.new(0, 20, 1, 0); dot.BackgroundTransparency = 1
	dot.Text = "?"; dot.TextColor3 = Color3.fromRGB(80, 180, 255); dot.TextSize = 14; dot.Font = Enum.Font.GothamBold; dot.Parent = row
	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, -25, 1, 0); label.Position = UDim2.new(0, 20, 0, 0)
	label.BackgroundTransparency = 1; label.TextColor3 = Color3.fromRGB(200, 200, 210); label.TextSize = 12
	label.Font = Enum.Font.Gotham; label.TextXAlignment = Enum.TextXAlignment.Left; label.TextTruncate = Enum.TextTruncate.AtEnd; label.Parent = row
	local item = {Frame = row, Label = label}; listItemPool[listItemUsed] = item; return item
end

local function resetListPool()
	for i = 1, listItemUsed do local item = listItemPool[i]; if item then item.Frame.Visible = false; item.Label.Text = "" end end
	listItemUsed = 0
end

local function addListItem(name, class)
	if listItemUsed >= CONFIG.ListCap then
		if listItemUsed == CONFIG.ListCap then
			local item = getListItem()
			item.Label.Text = string.format("... and %d more parts", #selectedParts - CONFIG.ListCap)
		end
		return
	end
	local item = getListItem(); item.Label.Text = string.format("%s (%s)", name, class)
end

local function refreshList()
	resetListPool()
	for _, p in ipairs(selectedParts) do addListItem(p.Name, p.ClassName) end
end

-- Toggles
local toggleFrame = Instance.new("Frame")
toggleFrame.Size = UDim2.new(1, -10, 0, 90)
toggleFrame.Position = UDim2.new(0, 5, 1, -195)
toggleFrame.BackgroundTransparency = 1; toggleFrame.Parent = selectorTab

local toggleGrid = Instance.new("UIGridLayout")
toggleGrid.CellSize = UDim2.new(0.5, -4, 0, 26); toggleGrid.CellPadding = UDim2.new(0, 4, 0, 2)
toggleGrid.FillDirection = Enum.FillDirection.Horizontal; toggleGrid.Parent = toggleFrame

local toggles = {}
local function makeSelToggle(text, default)
	local frame = Instance.new("Frame"); frame.BackgroundColor3 = Color3.fromRGB(28, 28, 36); frame.BorderSizePixel = 0; frame.Parent = toggleFrame
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
	local circle = Instance.new("Frame"); circle.Size = UDim2.new(0, 14, 0, 14); circle.Position = UDim2.new(0, 6, 0.5, -7)
	circle.BackgroundColor3 = default and Color3.fromRGB(80, 180, 255) or Color3.fromRGB(80, 80, 90); circle.BorderSizePixel = 0; circle.Parent = frame
	Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, -24, 1, 0); label.Position = UDim2.new(0, 24, 0, 0)
	label.BackgroundTransparency = 1; label.Text = text; label.TextColor3 = Color3.fromRGB(180, 180, 190); label.TextSize = 11
	label.Font = Enum.Font.Gotham; label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = frame
	local btn = Instance.new("TextButton"); btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = frame
	local state = default
	btn.MouseButton1Click:Connect(function()
		state = not state
		TweenService:Create(circle, TweenInfo.new(0.2), {BackgroundColor3 = state and Color3.fromRGB(80, 180, 255) or Color3.fromRGB(80, 80, 90)}):Play()
	end)
	toggles[#toggles + 1] = {Get = function() return state end}
	return {Get = function() return state end}
end
makeSelToggle("Hierarchy", true); makeSelToggle("Welds", true); makeSelToggle("Decals", true); makeSelToggle("Meshes", true); makeSelToggle("Lights", true)

-- Buttons
local selBtnFrame = Instance.new("Frame")
selBtnFrame.Size = UDim2.new(1, -10, 0, 100)
selBtnFrame.Position = UDim2.new(0, 5, 1, -100)
selBtnFrame.BackgroundTransparency = 1; selBtnFrame.Parent = selectorTab

local selBtnGrid = Instance.new("UIGridLayout")
selBtnGrid.CellSize = UDim2.new(0.5, -4, 0, 28); selBtnGrid.CellPadding = UDim2.new(0, 4, 0, 4)
selBtnGrid.FillDirection = Enum.FillDirection.Horizontal; selBtnGrid.Parent = selBtnFrame

local function makeSelBtn(text, color, cb)
	local btn = Instance.new("TextButton"); btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundColor3 = color
	btn.Text = text; btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.TextSize = 11; btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true; Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6); btn.Parent = selBtnFrame
	btn.MouseButton1Click:Connect(cb); return btn
end
local toggleSelBtn = makeSelBtn("?? Selection: ON", Color3.fromRGB(0, 130, 80), function()
	selectionEnabled = not selectionEnabled
	if selectionEnabled then
		toggleSelBtn.Text = "?? Selection: ON"; toggleSelBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 80)
		statusLabel.Text = "Click empty space & drag to select"; notify("Selection enabled")
	else
		toggleSelBtn.Text = "?? Selection: OFF"; toggleSelBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		statusLabel.Text = "Selection disabled"; notify("Selection disabled")
		isDragging = false; marquee.Visible = false; clickMode = false; clickTarget = nil; mouseDownPos = nil; dragStartPos = nil; dragCurrentPos = nil
	end
end)
makeSelBtn("?? Export JSON", Color3.fromRGB(0, 130, 220), function()
	if #selectedParts == 0 then notify("No parts selected!"); return end; exportBuildToJSON(selectedParts)
end)
makeSelBtn("?? Export Lua", Color3.fromRGB(0, 150, 100), function()
	if #selectedParts == 0 then notify("No parts selected!"); return end; exportBuildToLua(selectedParts)
end)
makeSelBtn("?? Clear Sel", Color3.fromRGB(180, 50, 50), function()
	clearSelection(); notify("Selection cleared")
end)

-- Marquee visual
local marquee = Instance.new("Frame")
marquee.BackgroundColor3 = Color3.fromRGB(80, 180, 255); marquee.BackgroundTransparency = 0.88
marquee.BorderSizePixel = 0; marquee.Visible = false; marquee.ZIndex = 1000; marquee.Parent = screenGui
local marqueeStroke = Instance.new("UIStroke"); marqueeStroke.Color = Color3.fromRGB(80, 180, 255)
marqueeStroke.Thickness = 2; marqueeStroke.Parent = marquee

-- ==================== EXPORT FUNCTIONS ====================
exportBuildToJSON = function(buildParts)
	if #buildParts == 0 then notify("No parts to export!"); return end
	if exportInProgress then notify("Export already in progress!"); return end
	exportInProgress = true; progressFrame.Visible = true; progressFill.Size = UDim2.new(0, 0, 1, 0)
	local total = #buildParts; local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
	local baseName = (selectedBuildName or "export"):gsub("[^%w_%-]", "_"):match("(.+)%..+$") or (selectedBuildName or "export"):gsub("[^%w_%-]", "_")
	if not isfolder(CONFIG.LocalFolder) then pcall(function() makefolder(CONFIG.LocalFolder) end) end
	local canStream = (type(appendfile) == "function")
	local filename = CONFIG.LocalFolder .. "/" .. baseName .. "_" .. timestamp .. ".json"
	local ok, err

	if canStream then
		pcall(function() writefile(filename, "") end)
		local buf = {}; local bufCount = 0
		local function flush()
			if bufCount == 0 then return end
			local data = table.concat(buf); buf = {}; bufCount = 0
			pcall(function() appendfile(filename, data) end)
		end
		local function push(s)
			bufCount = bufCount + 1; buf[bufCount] = s
			if bufCount >= CONFIG.StreamBatch then flush(); task.wait() end
		end
		ok, err = pcall(function()
			push('{"BuildName":"' .. (selectedBuildName or "Export"):gsub('"', '\\"') .. '","PlaceId":' .. tostring(game.PlaceId) .. ',"Timestamp":"' .. os.date("%Y-%m-%d %H:%M:%S") .. '","PartCount":' .. tostring(total) .. ',"Parts":[')
			for i = 1, total do
				local part = buildParts[i]
				if i > 1 then push(",") end
				local partOk, partJson = pcall(function()
					if not part or not part:IsA("BasePart") then return "null" end
					local pb = {}; local pc = 0
					local function pp(s) pc = pc + 1; pb[pc] = s end
					pp('{"Index":'); pp(tostring(i)); pp(',"ClassName":"'); pp(part.ClassName); pp('","Name":"'); pp(part.Name:gsub('"', '\\"')); pp('"')
					local cf = part.CFrame; local c = {cf:GetComponents()}
					pp(',"CFrame":['); pp(string.format("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f", c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9],c[10],c[11],c[12])); pp(']')
					pp(',"Size":['); pp(string.format("%.4f,%.4f,%.4f", part.Size.X, part.Size.Y, part.Size.Z)); pp(']')
					pp(',"Color":['); pp(string.format("%d,%d,%d", math.floor(part.Color.R*255+0.5), math.floor(part.Color.G*255+0.5), math.floor(part.Color.B*255+0.5))); pp(']')
					pp(',"Material":"'); pp(tostring(part.Material)); pp('","Transparency":'); pp(string.format("%.4f", part.Transparency))
					pp(',"Reflectance":'); pp(string.format("%.4f", part.Reflectance))
					pp(',"CanCollide":'); pp(tostring(part.CanCollide)); pp(',"Anchored":'); pp(tostring(part.Anchored))
					pp(',"CastShadow":'); pp(tostring(part.CastShadow)); pp(',"Locked":'); pp(tostring(part.Locked))
					pp(',"TopSurface":"'); pp(tostring(part.TopSurface)); pp('","BottomSurface":"'); pp(tostring(part.BottomSurface))
					pp('","LeftSurface":"'); pp(tostring(part.LeftSurface)); pp('","RightSurface":"'); pp(tostring(part.RightSurface))
					pp('","FrontSurface":"'); pp(tostring(part.FrontSurface)); pp('","BackSurface":"'); pp(tostring(part.BackSurface)); pp('"')
					if part:IsA("Part") then
						local shape; pcall(function() shape = part.Shape end)
						if shape then pp(',"Shape":"'); pp(tostring(shape)); pp('"') end
					end
					if part:IsA("MeshPart") then
						if part.MeshId and part.MeshId ~= "" then pp(',"MeshId":"'); pp(part.MeshId:gsub('"', '\\"')); pp('"') end
						if part.TextureID and part.TextureID ~= "" then pp(',"TextureID":"'); pp(part.TextureID:gsub('"', '\\"')); pp('"') end
						pp(',"RenderFidelity":"'); pp(tostring(part.RenderFidelity)); pp('","CollisionFidelity":"'); pp(tostring(part.CollisionFidelity)); pp('"')
					end
					if part.Massless then pp(',"Massless":true') end
					if part.CollisionGroupId ~= 0 then pp(',"CollisionGroupId":'); pp(tostring(part.CollisionGroupId)) end
					local cpp = part.CustomPhysicalProperties
					if cpp then pp(',"CustomPhysicalProperties":{"Density":'); pp(string.format("%.4f", cpp.Density))
						pp(',"Friction":'); pp(string.format("%.4f", cpp.Friction))
						pp(',"Elasticity":'); pp(string.format("%.4f", cpp.Elasticity))
						pp(',"FrictionWeight":'); pp(string.format("%.4f", cpp.FrictionWeight))
						pp(',"ElasticityWeight":'); pp(string.format("%.4f", cpp.ElasticityWeight)); pp('}') end
					pp(',"ParentName":"'); local parent = part.Parent
					if parent and parent ~= workspace then pp(parent.Name:gsub('"', '\\"'))
					else pp("workspace") end; pp('"')
					pp(',"Children":['); local childCount = 0
					local function ac(s) if childCount > 0 then pp(",") end; childCount = childCount + 1; pcall(function() pp(s) end) end
					for _, child in ipairs(part:GetChildren()) do
						if child:IsA("Decal") or child:IsA("Texture") then
							ac('{"ClassName":"' .. child.ClassName .. '","Texture":"' .. child.Texture:gsub('"', '\\"') .. '","Face":"' .. tostring(child.Face) .. '","Transparency":' .. string.format("%.4f", child.Transparency) .. '}')
						elseif child:IsA("SpecialMesh") then
							local j = '{"ClassName":"SpecialMesh"'
							local mt; pcall(function() mt = tostring(child.MeshType):gsub("Enum%.MeshType%.", "") end)
							if mt and mt ~= "Brick" then j = j .. ',"MeshType":"' .. mt .. '"' end
							local mi; pcall(function() if child.MeshId ~= "" then mi = child.MeshId end end)
							if mi then j = j .. ',"MeshId":"' .. mi:gsub('"', '\\"') .. '"' end
							local ti; pcall(function() if child.TextureId ~= "" then ti = child.TextureId end end)
							if ti then j = j .. ',"TextureId":"' .. ti:gsub('"', '\\"') .. '"' end
							local sx, sy, sz = 1, 1, 1; pcall(function() sx, sy, sz = child.Scale.X, child.Scale.Y, child.Scale.Z end)
							local ox, oy, oz = 0, 0, 0; pcall(function() ox, oy, oz = child.Offset.X, child.Offset.Y, child.Offset.Z end)
							j = j .. ',"Scale":[' .. string.format("%.4f,%.4f,%.4f", sx, sy, sz) .. '],"Offset":[' .. string.format("%.4f,%.4f,%.4f", ox, oy, oz) .. ']'
							ac(j .. '}')
						elseif child:IsA("BlockMesh") then
							local j = '{"ClassName":"BlockMesh"'
							local sx, sy, sz = 1, 1, 1; pcall(function() sx, sy, sz = child.Scale.X, child.Scale.Y, child.Scale.Z end)
							local ox, oy, oz = 0, 0, 0; pcall(function() ox, oy, oz = child.Offset.X, child.Offset.Y, child.Offset.Z end)
							j = j .. ',"Scale":[' .. string.format("%.4f,%.4f,%.4f", sx, sy, sz) .. '],"Offset":[' .. string.format("%.4f,%.4f,%.4f", ox, oy, oz) .. ']'
							ac(j .. '}')
						elseif child:IsA("CylinderMesh") then
							local j = '{"ClassName":"CylinderMesh"'
							local sx, sy, sz = 1, 1, 1; pcall(function() sx, sy, sz = child.Scale.X, child.Scale.Y, child.Scale.Z end)
							local ox, oy, oz = 0, 0, 0; pcall(function() ox, oy, oz = child.Offset.X, child.Offset.Y, child.Offset.Z end)
							j = j .. ',"Scale":[' .. string.format("%.4f,%.4f,%.4f", sx, sy, sz) .. '],"Offset":[' .. string.format("%.4f,%.4f,%.4f", ox, oy, oz) .. ']'
							ac(j .. '}') end
					end
					pp(']'); pp('}')
					return table.concat(pb)
				end)
				push(partOk and partJson or "null")
				if i % CONFIG.StreamBatch == 0 then
					progressFill.Size = UDim2.new(i / total * 0.95, 0, 1, 0); task.wait()
				end
			end
			push(']}')
			flush()
		end)
	else
		local allBuf = {}; local allCount = 0
		local function add(s) allCount = allCount + 1; allBuf[allCount] = s end
			local buildOk, buildErr = pcall(function()
			add('{"BuildName":"' .. (selectedBuildName or "Export"):gsub('"', '\\"') .. '","PlaceId":' .. tostring(game.PlaceId) .. ',"Timestamp":"' .. os.date("%Y-%m-%d %H:%M:%S") .. '","PartCount":' .. tostring(total) .. ',"Parts":[')
			for i = 1, total do
				local part = buildParts[i]
				if i > 1 then add(",") end
				local partOk, partJson = pcall(function()
					if not part or not part:IsA("BasePart") then return "null" end
					local pb = {}; local pc = 0
					local function pp(s) pc = pc + 1; pb[pc] = s end
					pp('{"Index":'); pp(tostring(i)); pp(',"ClassName":"'); pp(part.ClassName); pp('","Name":"'); pp(part.Name:gsub('"', '\\"')); pp('"')
					local cf = part.CFrame; local c = {cf:GetComponents()}
					pp(',"CFrame":['); pp(string.format("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f", c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9],c[10],c[11],c[12])); pp(']')
					pp(',"Size":['); pp(string.format("%.4f,%.4f,%.4f", part.Size.X, part.Size.Y, part.Size.Z)); pp(']')
					pp(',"Color":['); pp(string.format("%d,%d,%d", math.floor(part.Color.R*255+0.5), math.floor(part.Color.G*255+0.5), math.floor(part.Color.B*255+0.5))); pp(']')
					pp(',"Material":"'); pp(tostring(part.Material)); pp('","Transparency":'); pp(string.format("%.4f", part.Transparency))
					pp(',"Reflectance":'); pp(string.format("%.4f", part.Reflectance))
					pp(',"CanCollide":'); pp(tostring(part.CanCollide)); pp(',"Anchored":'); pp(tostring(part.Anchored))
					pp(',"CastShadow":'); pp(tostring(part.CastShadow)); pp(',"Locked":'); pp(tostring(part.Locked))
					pp(',"TopSurface":"'); pp(tostring(part.TopSurface)); pp('","BottomSurface":"'); pp(tostring(part.BottomSurface))
					pp('","LeftSurface":"'); pp(tostring(part.LeftSurface)); pp('","RightSurface":"'); pp(tostring(part.RightSurface))
					pp('","FrontSurface":"'); pp(tostring(part.FrontSurface)); pp('","BackSurface":"'); pp(tostring(part.BackSurface)); pp('"')
					if part:IsA("Part") then
						local shape; pcall(function() shape = part.Shape end)
						if shape then pp(',"Shape":"'); pp(tostring(shape)); pp('"') end
					end
					if part:IsA("MeshPart") then
						if part.MeshId and part.MeshId ~= "" then pp(',"MeshId":"'); pp(part.MeshId:gsub('"', '\\"')); pp('"') end
						if part.TextureID and part.TextureID ~= "" then pp(',"TextureID":"'); pp(part.TextureID:gsub('"', '\\"')); pp('"') end
						pp(',"RenderFidelity":"'); pp(tostring(part.RenderFidelity)); pp('","CollisionFidelity":"'); pp(tostring(part.CollisionFidelity)); pp('"')
					end
					if part.Massless then pp(',"Massless":true') end
					if part.CollisionGroupId ~= 0 then pp(',"CollisionGroupId":'); pp(tostring(part.CollisionGroupId)) end
					local cpp = part.CustomPhysicalProperties
					if cpp then pp(',"CustomPhysicalProperties":{"Density":'); pp(string.format("%.4f", cpp.Density))
						pp(',"Friction":'); pp(string.format("%.4f", cpp.Friction))
						pp(',"Elasticity":'); pp(string.format("%.4f", cpp.Elasticity))
						pp(',"FrictionWeight":'); pp(string.format("%.4f", cpp.FrictionWeight))
						pp(',"ElasticityWeight":'); pp(string.format("%.4f", cpp.ElasticityWeight)); pp('}') end
					pp(',"ParentName":"'); local parent = part.Parent
					if parent and parent ~= workspace then pp(parent.Name:gsub('"', '\\"'))
					else pp("workspace") end; pp('"')
					pp(',"Children":['); local childCount = 0
					local function ac(s) if childCount > 0 then pp(",") end; childCount = childCount + 1; pcall(function() pp(s) end) end
					for _, child in ipairs(part:GetChildren()) do
						if child:IsA("Decal") or child:IsA("Texture") then
							ac('{"ClassName":"' .. child.ClassName .. '","Texture":"' .. child.Texture:gsub('"', '\\"') .. '","Face":"' .. tostring(child.Face) .. '","Transparency":' .. string.format("%.4f", child.Transparency) .. '}')
						elseif child:IsA("SpecialMesh") then
							local j = '{"ClassName":"SpecialMesh"'
							local mt; pcall(function() mt = tostring(child.MeshType):gsub("Enum%.MeshType%.", "") end)
							if mt and mt ~= "Brick" then j = j .. ',"MeshType":"' .. mt .. '"' end
							local mi; pcall(function() if child.MeshId ~= "" then mi = child.MeshId end end)
							if mi then j = j .. ',"MeshId":"' .. mi:gsub('"', '\\"') .. '"' end
							local ti; pcall(function() if child.TextureId ~= "" then ti = child.TextureId end end)
							if ti then j = j .. ',"TextureId":"' .. ti:gsub('"', '\\"') .. '"' end
							local sx, sy, sz = 1, 1, 1; pcall(function() sx, sy, sz = child.Scale.X, child.Scale.Y, child.Scale.Z end)
							local ox, oy, oz = 0, 0, 0; pcall(function() ox, oy, oz = child.Offset.X, child.Offset.Y, child.Offset.Z end)
							j = j .. ',"Scale":[' .. string.format("%.4f,%.4f,%.4f", sx, sy, sz) .. '],"Offset":[' .. string.format("%.4f,%.4f,%.4f", ox, oy, oz) .. ']'
							ac(j .. '}')
						elseif child:IsA("BlockMesh") then
							local j = '{"ClassName":"BlockMesh"'
							local sx, sy, sz = 1, 1, 1; pcall(function() sx, sy, sz = child.Scale.X, child.Scale.Y, child.Scale.Z end)
							local ox, oy, oz = 0, 0, 0; pcall(function() ox, oy, oz = child.Offset.X, child.Offset.Y, child.Offset.Z end)
							j = j .. ',"Scale":[' .. string.format("%.4f,%.4f,%.4f", sx, sy, sz) .. '],"Offset":[' .. string.format("%.4f,%.4f,%.4f", ox, oy, oz) .. ']'
							ac(j .. '}')
						elseif child:IsA("CylinderMesh") then
							local j = '{"ClassName":"CylinderMesh"'
							local sx, sy, sz = 1, 1, 1; pcall(function() sx, sy, sz = child.Scale.X, child.Scale.Y, child.Scale.Z end)
							local ox, oy, oz = 0, 0, 0; pcall(function() ox, oy, oz = child.Offset.X, child.Offset.Y, child.Offset.Z end)
							j = j .. ',"Scale":[' .. string.format("%.4f,%.4f,%.4f", sx, sy, sz) .. '],"Offset":[' .. string.format("%.4f,%.4f,%.4f", ox, oy, oz) .. ']'
							ac(j .. '}') end
					end
					pp(']'); pp('}')
					return table.concat(pb)
				end)
				add(partOk and partJson or "null")
				if i % CONFIG.StreamBatch == 0 then
					progressFill.Size = UDim2.new(i / total * 0.95, 0, 1, 0); task.wait()
				end
			end
			add(']}')
			fullJson = table.concat(allBuf)
		end)
		if buildOk then ok, err = pcall(function() writefile(filename, fullJson) end)
		else ok = false; err = buildErr end
	end
	progressFill.Size = UDim2.new(1, 0, 1, 0); task.wait(0.3)
	progressFrame.Visible = false; exportInProgress = false
	if ok then notify("Exported " .. total .. " parts to " .. filename); statusLabel.Text = "Saved: " .. filename
	else notify("Export failed: " .. tostring(err):sub(1, 60)) end
end

exportBuildToLua = function(buildParts)
	if #buildParts == 0 then notify("No parts to export!"); return end
	local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
	local baseName = (selectedBuildName or "export"):gsub("[^%w_%-]", "_"):match("(.+)%..+$") or (selectedBuildName or "export"):gsub("[^%w_%-]", "_")
	local filename = CONFIG.LocalFolder .. "/" .. baseName .. "_" .. timestamp .. ".lua"
	if not isfolder(CONFIG.LocalFolder) then pcall(function() makefolder(CONFIG.LocalFolder) end) end
	local canStream = (type(appendfile) == "function")
	local ok, err; local fullLua

	if canStream then
		pcall(function() writefile(filename, "") end)
		local buf = {}; local bufCount = 0
		local function flush()
			if bufCount == 0 then return end
			local data = table.concat(buf); buf = {}; bufCount = 0
			pcall(function() appendfile(filename, data) end)
		end
		local function push(s)
			bufCount = bufCount + 1; buf[bufCount] = s
			if bufCount >= CONFIG.StreamBatch then flush() end
		end
		ok, err = pcall(function()
			push("-- F3X Build Export\nlocal buildData = {\n  Name = " .. string.format("%q", selectedBuildName or "Export") .. ",\n  PartCount = " .. tostring(#buildParts) .. ",\n  Parts = {\n")
			for i, part in ipairs(buildParts) do
				if part and part:IsA("BasePart") then
					local pd = string.format("    {ClassName=%q,Size=%s,Position=%s,Rotation=%s,Color=%s,Material=%q,Anchored=%s,Transparency=%s,Reflectance=%s}", part.ClassName, fmtV3(part.Size), fmtV3(part.Position), fmtV3(Vector3.new(part.Orientation.X, part.Orientation.Y, part.Orientation.Z)), fmtC3(part.Color), tostring(part.Material), fmtVal(part.Anchored), fmtVal(part.Transparency), fmtVal(part.Reflectance))
					if i > 1 then push(",\n") end; push(pd)
				end
			end
			push("\n  }\n}\n"); flush()
		end)
	else
		local allBuf = {}; local allCount = 0
		local function add(s) allCount = allCount + 1; allBuf[allCount] = s end
		local buildOk, buildErr = pcall(function()
			add("-- F3X Build Export\nlocal buildData = {\n  Name = " .. string.format("%q", selectedBuildName or "Export") .. ",\n  PartCount = " .. tostring(#buildParts) .. ",\n  Parts = {\n")
			for i, part in ipairs(buildParts) do
				if part and part:IsA("BasePart") then
					local pd = string.format("    {ClassName=%q,Size=%s,Position=%s,Rotation=%s,Color=%s,Material=%q,Anchored=%s,Transparency=%s,Reflectance=%s}", part.ClassName, fmtV3(part.Size), fmtV3(part.Position), fmtV3(Vector3.new(part.Orientation.X, part.Orientation.Y, part.Orientation.Z)), fmtC3(part.Color), tostring(part.Material), fmtVal(part.Anchored), fmtVal(part.Transparency), fmtVal(part.Reflectance))
					if i > 1 then add(",\n") end; add(pd)
				end
			end
			add("\n  }\n}\n")
			fullLua = table.concat(allBuf)
		end)
		if buildOk then ok, err = pcall(function() writefile(filename, fullLua) end)
		else ok = false; err = buildErr end
	end
	if ok then notify("Exported as Lua to " .. filename); statusLabel.Text = "Saved: " .. filename
	else notify("Lua export failed!") end
end

-- ==================== INPUT ====================
UserInputService.InputBegan:Connect(function(input, gpe)
	if not selectionEnabled then return end; if gpe then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if exportInProgress then return end
	local mPos = UserInputService:GetMouseLocation()
	local guiObjects = player.PlayerGui:GetGuiObjectsAtPosition(mPos.X, mPos.Y)
	for _, obj in ipairs(guiObjects) do
		if obj:IsDescendantOf(mainFrame) or obj:IsDescendantOf(notif) then return end
	end
	mouseDownPos = mPos; dragStartPos = mPos; dragCurrentPos = mPos; isDragging = true
	clickTarget = getPartUnderMouse()
	if clickTarget then clickMode = true
	else
		clickMode = false; marquee.Position = UDim2.new(0, mPos.X, 0, mPos.Y)
		marquee.Size = UDim2.new(0, 0, 0, 0); marquee.Visible = true
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not selectionEnabled then return end; if not isDragging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
	local mPos = UserInputService:GetMouseLocation(); dragCurrentPos = mPos
	local dist = (dragCurrentPos - mouseDownPos).Magnitude
	if clickMode and dist > CONFIG.DragThreshold then
		clickMode = false; clickTarget = nil
		marquee.Position = UDim2.new(0, mouseDownPos.X, 0, mouseDownPos.Y)
		marquee.Size = UDim2.new(0, 0, 0, 0); marquee.Visible = true
	end
	if not clickMode then
		local minX = math.min(dragStartPos.X, dragCurrentPos.X); local minY = math.min(dragStartPos.Y, dragCurrentPos.Y)
		local maxX = math.max(dragStartPos.X, dragCurrentPos.X); local maxY = math.max(dragStartPos.Y, dragCurrentPos.Y)
		marquee.Position = UDim2.new(0, minX, 0, minY); marquee.Size = UDim2.new(0, maxX - minX, 0, maxY - minY)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not selectionEnabled then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not isDragging then return end; isDragging = false; marquee.Visible = false
	local dist = (dragCurrentPos - mouseDownPos).Magnitude
	local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	if clickMode and dist <= CONFIG.DragThreshold then
		if clickTarget then
			if ctrlHeld then
				if selectedSet[clickTarget] then removePart(clickTarget) else addPart(clickTarget) end
			else
				if not selectedSet[clickTarget] then clearSelection(); addPart(clickTarget) end
			end
			statusLabel.Text = string.format("Selected: %s", clickTarget.Name)
		end
	elseif not clickMode and dist > CONFIG.DragThreshold then
		if not ctrlHeld then clearSelection() end
		local found = 0; local char = player.Character
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("BasePart") and obj ~= char and not obj:IsDescendantOf(char or Instance.new("Model")) then
				if partInMarquee(obj, dragStartPos, dragCurrentPos) then
					addPart(obj); found = found + 1; if found >= CONFIG.MaxParts then break end
				end
			end
		end
		statusLabel.Text = string.format("Box-selected %d parts", found)
		if found > CONFIG.VisualLimit then statusLabel.Text = statusLabel.Text .. string.format(" (showing %d visuals)", CONFIG.VisualLimit) end
	elseif not clickMode and dist <= CONFIG.DragThreshold then
		if not ctrlHeld then clearSelection() end
	end
	clickMode = false; clickTarget = nil; mouseDownPos = nil; dragStartPos = nil; dragCurrentPos = nil
end)

-- ==================== 15. BUILD QUEUE ====================
local buildQueue = {}; local isBuilding = false

local function processQueue()
	if isBuilding then return end
	while #buildQueue > 0 do
		local item = table.remove(buildQueue, 1)
		isBuilding = true
		local parts = item.Parts; local total = #parts
		notify("Starting build: " .. (item.Name or "Build"))
		if CONFIG.HyperMode and total > 50 then
			notify("Hyper build engaged with " .. CONFIG.HyperThreads .. " threads")
		end
		statusLabel.Text = "Initializing build..."
		buildBtn.Visible = false; buildBtn.Text = "Building..."
		local partMap = {}; local buildStart = tick(); local failedCount = 0
		progressFill.Size = UDim2.new(0, 0, 1, 0); progressFrame.Visible = true
		local nc = pcall(function() F3XRetry("New", item.Name or "Imported Build") end)
		if not nc then notify("F3X init failed!"); statusLabel.Text = "F3X init failed"; isBuilding = false; buildBtn.Visible = false; return end
		task.wait(0.2)
		if CONFIG.HyperMode and total > 50 then
			failedCount = hyperBuild(parts, total, partMap)
		else
			failedCount = normalBuild(parts, total, partMap)
		end
		local buildTime = tick() - buildStart; progressFrame.Visible = false
		notify(string.format("Build complete! %d/%d parts (%d failed) in %.2fs", total - failedCount, total, failedCount, buildTime))
		statusLabel.Text = string.format("Done: %d/%d (%d failed, %.2fs)", total - failedCount, total, failedCount, buildTime)
		buildBtn.Text = "? Build Complete"; buildBtn.Visible = true
		if CONFIG.AutoAnchorAfter then
			for _, p in pairs(partMap) do if p and p:IsA("BasePart") then p.Anchored = true end end
		end
		for i, partData in ipairs(parts) do
			local part = partMap[i]
			if part and partData.Children then
				for _, childData in ipairs(partData.Children) do
					if childData.ClassName == "Decal" or childData.ClassName == "Texture" then
						pcall(function()
							for _, child in ipairs(part:GetChildren()) do
								if (child:IsA("Decal") or child:IsA("Texture")) and tostring(child.Face) == tostring(parseNormalId(childData.Face)) then
									child.Texture = childData.Texture
								end
							end
						end)
					end
				end
			end
			if part then
				pcall(function()
					for _, child in ipairs(part:GetChildren()) do
						if child:IsA("Decal") or child:IsA("Texture") then
							if child.Texture == "" or not child.Texture:match("^rbxassetid://%d+$") then
								if CONFIG.Debug then warn("BAD TEXTURE on", part.Name, ":", child.Texture) end
								child:Destroy()
							end
						end
					end
				end)
			end
		end
		local centerPos = calculateBuildCenter(parts)
		teleportToBuild(centerPos)
		isBuilding = false
	end end

local function buildCurrentNow()
	if isBuilding then notify("Already building!"); return end
	if not selectedBuildData or not selectedBuildData.Parts then notify("No build selected!"); return end
	if CONFIG.MaxParts > 0 and #selectedBuildData.Parts > CONFIG.MaxParts then
		notify(string.format("Too many parts! Max: %d, Found: %d", CONFIG.MaxParts, #selectedBuildData.Parts))
		return
	end
	clearGhost()
	buildQueue[#buildQueue + 1] = {Parts = selectedBuildData.Parts, Name = selectedBuildName or "Build"}
	processQueue()
end

buildBtn.MouseButton1Click:Connect(buildCurrentNow)

-- ==================== 17. INITIALIZATION ====================
local function findF3XTool()
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return nil end
	local tool = backpack:FindFirstChild("Building Tools")
	if not tool then tool = backpack:FindFirstChild("F3X") end
	if not tool then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item; break
			end
		end
	end
	if not tool then
		local char = player.Character
		if char then
			for _, item in ipairs(char:GetChildren()) do
				if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
					tool = item; break
				end
			end
		end
	end
	return tool
end

local function f3xConnect()
	F3X = {}
	local tool; local retryCount = 0; local maxRetries = 20
	while not tool and retryCount < maxRetries do
		retryCount = retryCount + 1
		tool = findF3XTool()
		if not tool then task.wait(0.5) end
	end
	if not tool then notify("Building Tools not found! Use ;btools"); return end
	F3X._tool = tool
	F3X._syncAPI = tool:FindFirstChild("SyncAPI")
	if not F3X._syncAPI then F3X._syncAPI = tool:WaitForChild("SyncAPI", 5) end
	if not F3X._syncAPI then notify("SyncAPI missing on " .. tool.Name); return end
	F3X._serverEndpoint = F3X._syncAPI:FindFirstChild("ServerEndpoint")
	if not F3X._serverEndpoint then F3X._serverEndpoint = F3X._syncAPI:WaitForChild("ServerEndpoint", 5) end
	if not F3X._serverEndpoint then notify("ServerEndpoint missing!"); return end

	F3X.ValidateTool = function()
		if not F3X._tool or not F3X._tool.Parent then
			local t = findF3XTool()
			if not t then return false end
			F3X._tool = t
		end
		return F3X._tool and F3X._tool.Parent ~= nil
	end

	hasBuildingTool = function(toolName)
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, item in ipairs(backpack:GetChildren()) do
				if item:IsA("Tool") and item.Name:find(toolName) then return true end
			end
		end
		local char = player.Character
		if char then
			for _, item in ipairs(char:GetChildren()) do
				if item:IsA("Tool") and item.Name:find(toolName) then return true end
			end
		end
		return false
	end

	equipBuildingTool = function(toolName)
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, item in ipairs(backpack:GetChildren()) do
				if item:IsA("Tool") and item.Name:find(toolName) then
					local char = player.Character
					if char then
						item.Parent = char
						task.wait(0.1)
						item:Activate()
					end
					return true
				end
			end
		end
		return false
	end

	function F3X:Invoke(...)
		if not F3X:ValidateTool() then return nil, "No tool" end
		local args = {...}
		if F3X._serverEndpoint and F3X._serverEndpoint:IsA("RemoteFunction") then
			return F3X._serverEndpoint:InvokeServer(unpack(args))
		end
		return nil, "No ServerEndpoint"
	end

	F3XRetry = function(cmd, ...)
		local args = {...}; local maxRetries = 3; local lastErr
		for attempt = 1, maxRetries do
			if not F3X:ValidateTool() then
				if attempt > 1 then task.wait(0.5 * attempt) end
				local t = findF3XTool()
				if t then F3X._tool = t end
			end
			if F3X:ValidateTool() then
				local ok, result = pcall(function()
					if cmd == "CreatePart" then
						local partType = args[1] or "Normal"; local cf = args[2] or CFrame.new(0, 5000, 0)
						local part = F3X:Invoke("CreatePart", partType, cf, workspace)
						if type(part) == "userdata" and part:IsA("PVInstance") then return part end
						return workspace:FindFirstChildWhichIsA("BasePart", true)
					elseif cmd == "SyncMove" then
						return F3X:Invoke("SyncMove", args[1])
					elseif cmd == "SyncColor" then
						return F3X:Invoke("SyncColor", args[1])
					elseif cmd == "SyncMaterial" then
						return F3X:Invoke("SyncMaterial", args[1])
					elseif cmd == "SyncResize" then
						return F3X:Invoke("SyncResize", args[1])
					elseif cmd == "SyncSurface" then
						return F3X:Invoke("SyncSurface", args[1])
					elseif cmd == "SyncAnchor" then
						return F3X:Invoke("SyncAnchor", args[1])
					elseif cmd == "SyncCollision" then
						return F3X:Invoke("SyncCollision", args[1])
					elseif cmd == "SetName" then
						return F3X:Invoke("SetName", args[1], args[2])
					elseif cmd == "SetLocked" then
						return F3X:Invoke("SetLocked", args[1], args[2])
					elseif cmd == "CreateMeshes" then
						-- F3X expects {{Part = p1}, {Part = p2}, ...}
						local c = {}
						for _, p in ipairs(args[1]) do c[#c + 1] = {Part = p} end
						return F3X:Invoke("CreateMeshes", c)
					elseif cmd == "SyncMesh" then
						return F3X:Invoke("SyncMesh", args[1])
					elseif cmd == "CreateTextures" then
						return F3X:Invoke("CreateTextures", args[1])
					elseif cmd == "SyncTexture" then
						return F3X:Invoke("SyncTexture", args[1])
					elseif cmd == "CreateLights" then
						return F3X:Invoke("CreateLights", args[1])
					elseif cmd == "SyncLighting" then
						return F3X:Invoke("SyncLighting", args[1])
					elseif cmd == "CreateDecorations" then
						return F3X:Invoke("CreateDecorations", args[1])
					elseif cmd == "SyncDecorate" then
						return F3X:Invoke("SyncDecorate", args[1])
					elseif cmd == "CreateWelds" then
						return F3X:Invoke("CreateWelds", args[1], args[2])
					elseif cmd == "RemoveWelds" then
						return F3X:Invoke("RemoveWelds", args[1])
					elseif cmd == "RemovePart" then
						return F3X:Invoke("RemovePart", args[1])
					elseif cmd == "Undo" then return F3X:Invoke("Undo")
					elseif cmd == "Redo" then return F3X:Invoke("Redo")
					elseif cmd == "New" then return F3X:Invoke("New")
					else return F3X:Invoke(cmd, unpack(args))
					end
				end)
				if ok then return result end
				lastErr = result
			end
			if attempt < maxRetries then task.wait(0.2 * (2 ^ (attempt - 1))) end
		end
		if CONFIG.Debug then warn("F3XRetry failed:", cmd, lastErr) end
		return nil, lastErr
	end
end

-- ==================== STARTUP ====================
local connected = false; local connectionAttempts = 0
while not connected and connectionAttempts < 5 do
	connectionAttempts = connectionAttempts + 1
	local ok = pcall(f3xConnect)
	if ok and F3X and F3X.ValidateTool and F3X:ValidateTool() then connected = true; break end
	task.wait(1)
end
if connected then
	notify("F3X Unified Build System v4.0 initialized")
	statusLabel.Text = "Ready   load or select a build"
	if CONFIG.Debug then print("F3X Unified Build System v4.0 initialized") end
	if CONFIG.LocalFolder ~= "" and isfolder(CONFIG.LocalFolder) then
		local files = safeListFiles(CONFIG.LocalFolder); local jsonCount = 0
		for _, f in ipairs(files) do if f:match("%.json$") then jsonCount = jsonCount + 1 end end
		if jsonCount > 0 then notify(jsonCount .. " local builds available") end
	end
else
	notify("Failed to connect to F3X   some features may not work")
	statusLabel.Text = "?? F3X not connected"
end
end
initUI()
