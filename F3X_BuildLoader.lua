--[[
 ============================================
 F3X BUILD LOADER (FULLY WORKING + TELEPORT)
 Loads builds from GitHub or local files
 Auto-builds using F3X Building Tools
 Place in StarterPlayerScripts as LocalScript
 ============================================
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

-- ==================== FILE APIs ====================
local readfile = readfile
local isfile = isfile
local listfiles = listfiles
local isfolder = isfolder
local writefile = writefile
local makefolder = makefolder
local setclipboard = setclipboard

-- ==================== CONFIG ====================
local CONFIG = {
	GitHubRepo = "UnAliveScripts/f3xbuildsjson",
	GitHubBranch = "main",
	LocalFolder = "BuildExports",
	BuildSpeed = 0.005,
	BtoolsTimeout = 12,
	Debug = true,
}

-- ==================== DEBUG LOGGER ====================
local function dprint(...)
	if CONFIG.Debug then
		print("[F3X Loader]", ...)
	end
end

-- ==================== F3X API (Direct ServerEndpoint) ====================
local F3X = {}
F3X._tool = nil
F3X._syncAPI = nil
F3X._serverEndpoint = nil

function F3X:Init()
	if self._serverEndpoint and self._serverEndpoint:FindFirstAncestorOfClass("DataModel") then
		return true
	end

	local backpack = player:WaitForChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()

	local tool = backpack:FindFirstChild("Building Tools")
	if not tool then tool = backpack:FindFirstChild("F3X") end
	if not tool then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item
				break
			end
		end
	end
	if not tool then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item
				break
			end
		end
	end

	if not tool then return false end

	self._tool = tool
	self._syncAPI = tool:WaitForChild("SyncAPI", 5)
	if not self._syncAPI then return false end
	self._serverEndpoint = self._syncAPI:WaitForChild("ServerEndpoint", 5)
	if not self._serverEndpoint then return false end

	dprint("F3X initialized! Tool:", tool.Name)
	return true
end

function F3X:Invoke(...)
	if not self:Init() then return nil end
	local args = {...}
	local ok, result = pcall(function()
		return self._serverEndpoint:InvokeServer(unpack(args))
	end)
	if not ok then
		dprint("Invoke FAILED:", args[1], "Error:", tostring(result))
		return nil
	end
	return result
end

-- CRITICAL: Always pass workspace as parent. F3X server ONLY accepts workspace as valid parent for CreatePart.
function F3X:CreatePart(partType, cframe)
	if partType == "VehicleSeat" then partType = "Vehicle Seat" end
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
	for _, p in ipairs(parts) do table.insert(c, {Part = p}) end
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

-- ==================== CFRAME PARSER (Robust) ====================
local function parseCFrame(data)
	if not data then
		return CFrame.new(0, 10, 0)
	end
	if typeof(data) == "CFrame" then
		return data
	end
	if typeof(data) == "table" then
		if #data >= 12 then
			return CFrame.new(unpack(data))
		elseif #data >= 3 then
			return CFrame.new(data[1], data[2], data[3])
		else
			return CFrame.new(0, 10, 0)
		end
	end
	if typeof(data) == "string" then
		local x, y, z = data:match("CFrame%.new%(([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)%)")
		if x and y and z then
			return CFrame.new(tonumber(x), tonumber(y), tonumber(z))
		end
	end
	return CFrame.new(0, 10, 0)
end

local function getCFramePosition(data)
	local cf = parseCFrame(data)
	return cf.Position
end

local function parseVector3(data)
	if not data then return Vector3.new(1, 1, 1) end
	if typeof(data) == "Vector3" then return data end
	if typeof(data) == "table" and #data >= 3 then
		return Vector3.new(unpack(data))
	end
	return Vector3.new(1, 1, 1)
end

local function parseColor3(data)
	if not data then return Color3.new(1, 1, 1) end
	if typeof(data) == "Color3" then return data end
	if typeof(data) == "table" and #data >= 3 then
		return Color3.fromRGB(unpack(data))
	end
	return Color3.new(1, 1, 1)
end

-- ==================== UI ====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "F3XBuildLoader"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 380, 0, 520)
mainFrame.Position = UDim2.new(0.5, -190, 0.5, -260)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

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
titleText.Text = "🏗️ F3X Build Loader"
titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
titleText.TextSize = 17
titleText.Font = Enum.Font.GothamBold
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 7)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

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

local currentTab = "Local"
local tabButtons = {}

local function makeTabBtn(text)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.5, -3, 1, 0)
	btn.BackgroundColor3 = text == "Local" and Color3.fromRGB(0, 130, 220) or Color3.fromRGB(40, 40, 50)
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 13
	btn.Font = Enum.Font.GothamBold
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.Parent = tabFrame
	tabButtons[text] = btn
	return btn
end

makeTabBtn("Local")
makeTabBtn("GitHub")

local localFrame = Instance.new("Frame")
localFrame.Size = UDim2.new(1, -20, 1, -160)
localFrame.Position = UDim2.new(0, 10, 0, 92)
localFrame.BackgroundTransparency = 1
localFrame.Parent = mainFrame

local githubFrame = Instance.new("Frame")
githubFrame.Size = UDim2.new(1, -20, 1, -160)
githubFrame.Position = UDim2.new(0, 10, 0, 92)
githubFrame.BackgroundTransparency = 1
githubFrame.Visible = false
githubFrame.Parent = mainFrame

-- Local tab
local refreshLocalBtn = Instance.new("TextButton")
refreshLocalBtn.Size = UDim2.new(1, 0, 0, 32)
refreshLocalBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
refreshLocalBtn.Text = "🔄 Refresh Local Files"
refreshLocalBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshLocalBtn.TextSize = 13
refreshLocalBtn.Font = Enum.Font.GothamBold
refreshLocalBtn.AutoButtonColor = true
Instance.new("UICorner", refreshLocalBtn).CornerRadius = UDim.new(0, 6)
refreshLocalBtn.Parent = localFrame

local localScroll = Instance.new("ScrollingFrame")
localScroll.Size = UDim2.new(1, 0, 1, -40)
localScroll.Position = UDim2.new(0, 0, 0, 38)
localScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
localScroll.BorderSizePixel = 0
localScroll.ScrollBarThickness = 4
localScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 70)
localScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
localScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
localScroll.Parent = localFrame
Instance.new("UICorner", localScroll).CornerRadius = UDim.new(0, 8)

local localListLayout = Instance.new("UIListLayout")
localListLayout.Padding = UDim.new(0, 4)
localListLayout.Parent = localScroll

-- GitHub tab
local githubInput = Instance.new("TextBox")
githubInput.Size = UDim2.new(1, 0, 0, 32)
githubInput.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
githubInput.Text = "UnAliveScripts/f3xbuildsjson"
githubInput.PlaceholderText = "user/repo"
githubInput.TextColor3 = Color3.fromRGB(255, 255, 255)
githubInput.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
githubInput.TextSize = 13
githubInput.Font = Enum.Font.Gotham
githubInput.ClearTextOnFocus = false
Instance.new("UICorner", githubInput).CornerRadius = UDim.new(0, 6)
githubInput.Parent = githubFrame

local fetchGithubBtn = Instance.new("TextButton")
fetchGithubBtn.Size = UDim2.new(1, 0, 0, 32)
fetchGithubBtn.Position = UDim2.new(0, 0, 0, 38)
fetchGithubBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 220)
fetchGithubBtn.Text = "🌐 Fetch Builds from GitHub"
fetchGithubBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
fetchGithubBtn.TextSize = 13
fetchGithubBtn.Font = Enum.Font.GothamBold
fetchGithubBtn.AutoButtonColor = true
Instance.new("UICorner", fetchGithubBtn).CornerRadius = UDim.new(0, 6)
fetchGithubBtn.Parent = githubFrame

local githubScroll = Instance.new("ScrollingFrame")
githubScroll.Size = UDim2.new(1, 0, 1, -78)
githubScroll.Position = UDim2.new(0, 0, 0, 76)
githubScroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
githubScroll.BorderSizePixel = 0
githubScroll.ScrollBarThickness = 4
githubScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 70)
githubScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
githubScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
githubScroll.Parent = githubFrame
Instance.new("UICorner", githubScroll).CornerRadius = UDim.new(0, 8)

local githubListLayout = Instance.new("UIListLayout")
githubListLayout.Padding = UDim.new(0, 4)
githubListLayout.Parent = githubScroll

-- Progress
local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(1, -20, 0, 4)
progressFrame.Position = UDim2.new(0, 10, 1, -56)
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
statusLabel.Size = UDim2.new(1, -20, 0, 22)
statusLabel.Position = UDim2.new(0, 10, 1, -48)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Ready"
statusLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true
statusLabel.Parent = mainFrame

local buildBtn = Instance.new("TextButton")
buildBtn.Size = UDim2.new(1, -20, 0, 38)
buildBtn.Position = UDim2.new(0, 10, 1, -40)
buildBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
buildBtn.Text = "🔨 Build Selected"
buildBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
buildBtn.TextSize = 15
buildBtn.Font = Enum.Font.GothamBold
buildBtn.AutoButtonColor = true
buildBtn.Visible = false
Instance.new("UICorner", buildBtn).CornerRadius = UDim.new(0, 8)
buildBtn.Parent = mainFrame

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

toggleBtn.MouseButton1Click:Connect(function()
	mainFrame.Visible = not mainFrame.Visible
end)

-- ==================== NOTIFICATION ====================
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

-- ==================== TAB SWITCHING ====================
local function switchTab(tab)
	currentTab = tab
	if tab == "Local" then
		localFrame.Visible = true
		githubFrame.Visible = false
		tabButtons.Local.BackgroundColor3 = Color3.fromRGB(0, 130, 220)
		tabButtons.GitHub.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	else
		localFrame.Visible = false
		githubFrame.Visible = true
		tabButtons.Local.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
		tabButtons.GitHub.BackgroundColor3 = Color3.fromRGB(0, 130, 220)
	end
end

tabButtons.Local.MouseButton1Click:Connect(function() switchTab("Local") end)
tabButtons.GitHub.MouseButton1Click:Connect(function() switchTab("GitHub") end)

-- ==================== DRAGGABLE UI ====================
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

local UserInputService = game:GetService("UserInputService")
UserInputService.InputChanged:Connect(function(input)
	if draggingUI and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = Vector2.new(input.Position.X, input.Position.Y) - uiDragStart
		mainFrame.Position = UDim2.new(uiStartPos.X.Scale, uiStartPos.X.Offset + delta.X, uiStartPos.Y.Scale, uiStartPos.Y.Offset + delta.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingUI = false end
end)

-- ==================== BUILD DATA ====================
local selectedBuildData = nil
local selectedBuildName = nil

-- ==================== LOCAL FILE LOADING ====================
local function clearLocalList()
	for _, child in ipairs(localScroll:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function addLocalFile(filename)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 36)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	btn.Text = "📄 " .. filename:match("([^/]+)$")
	btn.TextColor3 = Color3.fromRGB(200, 200, 210)
	btn.TextSize = 12
	btn.Font = Enum.Font.Gotham
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.Parent = localScroll

	btn.MouseButton1Click:Connect(function()
		for _, b in ipairs(localScroll:GetChildren()) do
			if b:IsA("TextButton") then b.BackgroundColor3 = Color3.fromRGB(28, 28, 36) end
		end
		btn.BackgroundColor3 = Color3.fromRGB(0, 100, 60)

		local ok, content = pcall(function() return readfile(filename) end)
		if ok then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(content) end)
			if parseOk then
				selectedBuildData = data
				selectedBuildName = filename:match("([^/]+)$")
				statusLabel.Text = "Selected: " .. selectedBuildName .. " (" .. (data.PartCount or #data.Parts) .. " parts)"
				buildBtn.Visible = true
				notify("Loaded: " .. selectedBuildName)
			else
				notify("Invalid JSON file!")
			end
		else
			notify("Failed to read file!")
		end
	end)
end

refreshLocalBtn.MouseButton1Click:Connect(function()
	clearLocalList()
	selectedBuildData = nil
	buildBtn.Visible = false
	statusLabel.Text = "Scanning local files..."

	if not isfolder(CONFIG.LocalFolder) then
		statusLabel.Text = "No BuildExports folder found"
		notify("No local builds found!")
		return
	end

	local files = listfiles(CONFIG.LocalFolder)
	local count = 0
	for _, file in ipairs(files) do
		if file:match("%.json$") then
			addLocalFile(file)
			count += 1
		end
	end
	statusLabel.Text = string.format("Found %d build files", count)
	notify(string.format("Found %d local builds", count))
end)

-- ==================== GITHUB LOADING ====================
local function clearGithubList()
	for _, child in ipairs(githubScroll:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function addGithubFile(name, url)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -10, 0, 36)
	btn.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	btn.Text = "🌐 " .. name
	btn.TextColor3 = Color3.fromRGB(200, 200, 210)
	btn.TextSize = 12
	btn.Font = Enum.Font.Gotham
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.AutoButtonColor = true
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	btn.Parent = githubScroll

	btn.MouseButton1Click:Connect(function()
		for _, b in ipairs(githubScroll:GetChildren()) do
			if b:IsA("TextButton") then b.BackgroundColor3 = Color3.fromRGB(28, 28, 36) end
		end
		btn.BackgroundColor3 = Color3.fromRGB(0, 100, 60)
		statusLabel.Text = "Downloading " .. name .. "..."

		local ok, content = pcall(function() return game:HttpGet(url) end)
		if ok and content then
			local parseOk, data = pcall(function() return HttpService:JSONDecode(content) end)
			if parseOk then
				selectedBuildData = data
				selectedBuildName = name
				statusLabel.Text = "Selected: " .. name .. " (" .. (data.PartCount or #data.Parts) .. " parts)"
				buildBtn.Visible = true
				notify("Loaded from GitHub: " .. name)
				pcall(function()
					if not isfolder(CONFIG.LocalFolder) then makefolder(CONFIG.LocalFolder) end
					writefile(CONFIG.LocalFolder .. "/" .. name, content)
				end)
			else
				notify("Invalid JSON from GitHub!")
				statusLabel.Text = "Invalid JSON"
			end
		else
			notify("Failed to download from GitHub!")
			statusLabel.Text = "Download failed"
		end
	end)
end

fetchGithubBtn.MouseButton1Click:Connect(function()
	clearGithubList()
	selectedBuildData = nil
	buildBtn.Visible = false
	statusLabel.Text = "Fetching from GitHub..."

	local repo = githubInput.Text:gsub("%s+", "")
	if repo == "" then repo = CONFIG.GitHubRepo end
	local apiUrl = "https://api.github.com/repos/" .. repo .. "/contents/"

	local ok, response = pcall(function() return game:HttpGet(apiUrl) end)
	if not ok or not response then
		notify("Failed to fetch GitHub repo!")
		statusLabel.Text = "GitHub fetch failed"
		return
	end

	local parseOk, files = pcall(function() return HttpService:JSONDecode(response) end)
	if not parseOk then
		notify("Failed to parse GitHub response!")
		statusLabel.Text = "Parse failed"
		return
	end

	local count = 0
	for _, file in ipairs(files) do
		if file.type == "file" and file.name:match("%.json$") then
			addGithubFile(file.name, file.download_url)
			count += 1
		end
	end
	statusLabel.Text = string.format("Found %d builds on GitHub", count)
	notify(string.format("Found %d GitHub builds", count))
end)

-- ==================== ENUM PARSERS ====================
local function parseMaterial(str)
	if not str then return Enum.Material.SmoothPlastic end
	local name = str:match("Enum%.Material%.(.+)") or str
	for _, enum in ipairs(Enum.Material:GetEnumItems()) do
		if enum.Name == name then return enum end
	end
	return Enum.Material.SmoothPlastic
end

local function parseSurface(str)
	if not str then return Enum.SurfaceType.Smooth end
	local name = str:match("Enum%.SurfaceType%.(.+)") or str
	for _, enum in ipairs(Enum.SurfaceType:GetEnumItems()) do
		if enum.Name == name then return enum end
	end
	return Enum.SurfaceType.Smooth
end

local function parseNormalId(str)
	if not str then return Enum.NormalId.Top end
	local name = str:match("Enum%.NormalId%.(.+)") or str
	for _, enum in ipairs(Enum.NormalId:GetEnumItems()) do
		if enum.Name == name then return enum end
	end
	return Enum.NormalId.Top
end

local function parseMeshType(str)
	if not str then return Enum.MeshType.Brick end
	local name = str:match("Enum%.MeshType%.(.+)") or str
	for _, enum in ipairs(Enum.MeshType:GetEnumItems()) do
		if enum.Name == name then return enum end
	end
	return Enum.MeshType.Brick
end

local function parseShape(str)
	if not str then return Enum.PartType.Block end
	local name = str:match("Enum%.PartType%.(.+)") or str
	for _, enum in ipairs(Enum.PartType:GetEnumItems()) do
		if enum.Name == name then return enum end
	end
	return Enum.PartType.Block
end

-- ==================== BTOOLS AUTO-REQUEST ====================
local function hasBuildingTool()
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character or player.CharacterAdded:Wait()
	local function checkContainer(container)
		if not container then return nil end
		for _, item in ipairs(container:GetChildren()) do
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
				tool = item
				break
			end
		end
	end

	if not tool then
		for _, item in ipairs(char:GetChildren()) do
			if item:IsA("Tool") and (item.Name:find("Building") or item.Name:find("F3X") or item:FindFirstChild("SyncAPI")) then
				tool = item
				break
			end
		end
	end

	if tool and tool.Parent == backpack then
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
				rb:SendAsync(";btools")
				success = true
			end
		end
	end)
	if not success then
		pcall(function()
			Players:Chat(";btools")
			success = true
		end)
	end
	return success
end

local function waitForBtools(timeout)
	local elapsed = 0
	while elapsed < timeout do
		if hasBuildingTool() then return true end
		task.wait(0.5)
		elapsed += 0.5
	end
	return hasBuildingTool()
end

-- ==================== TELEPORT TO BUILD ====================
local function calculateBuildCenter(parts)
	if not parts or #parts == 0 then
		return Vector3.new(0, 50, 0)
	end

	local sumX, sumY, sumZ = 0, 0, 0
	local count = 0

	for _, partData in ipairs(parts) do
		local cfData = partData.CFrame
		if cfData then
			local pos = getCFramePosition(cfData)
			sumX += pos.X
			sumY += pos.Y
			sumZ += pos.Z
			count += 1
		end
	end

	if count == 0 then
		return Vector3.new(0, 50, 0)
	end

	return Vector3.new(sumX / count, sumY / count, sumZ / count)
end

local function teleportToBuild(targetPosition)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Teleport 20 studs above the build center so player can see it being built
	local teleportPos = targetPosition + Vector3.new(0, 30, 0)
	hrp.CFrame = CFrame.new(teleportPos)

	-- Also set camera to look at the build area
	local camera = workspace.CurrentCamera
	camera.CFrame = CFrame.new(teleportPos, targetPosition)

	dprint("Teleported to build location:", teleportPos)
end

-- ==================== BUILD FUNCTION ====================
buildBtn.MouseButton1Click:Connect(function()
	if not selectedBuildData then
		notify("No build selected!")
		return
	end

	local parts = selectedBuildData.Parts
	if not parts or typeof(parts) ~= "table" then
		notify("Invalid build data: no Parts array found!")
		return
	end

	buildBtn.Visible = false
	progressFrame.Visible = true
	progressFill.Size = UDim2.new(0, 0, 1, 0)

	-- STEP 0: Calculate build center and teleport
	local buildCenter = calculateBuildCenter(parts)
	statusLabel.Text = "Teleporting to build location..."
	teleportToBuild(buildCenter)
	notify("Teleported to build location!")
	task.wait(0.5)

	-- STEP 1: Request btools if missing
	if not hasBuildingTool() then
		statusLabel.Text = "Requesting building tools via chat..."
		notify("Sending ;btools command...")
		local sent = sendBtoolsCommand()
		if not sent then
			notify("Failed to send chat command!")
			progressFrame.Visible = false
			buildBtn.Visible = true
			statusLabel.Text = "Chat command failed"
			return
		end
		local received = waitForBtools(CONFIG.BtoolsTimeout)
		if not received then
			notify("Building tools not received! Try ;btools manually.")
			progressFrame.Visible = false
			buildBtn.Visible = true
			statusLabel.Text = "Timed out waiting for btools"
			return
		end
		notify("Building tools received!")
	end

	-- STEP 1b: Equip the tool (CRITICAL - F3X only works when equipped)
	statusLabel.Text = "Equipping building tools..."
	local equipped = equipBuildingTool()
	if not equipped then
		notify("Failed to equip building tools!")
		progressFrame.Visible = false
		buildBtn.Visible = true
		return
	end
	task.wait(0.5) -- Give time for tool to fully equip

	-- STEP 2: Init F3X
	if not F3X:Init() then
		notify("F3X initialization failed!")
		progressFrame.Visible = false
		buildBtn.Visible = true
		return
	end

	local total = #parts
	local builtParts = {}
	local partMap = {}
	local modelMap = {}
	local failedCount = 0

	statusLabel.Text = string.format("Building %d parts...", total)
	notify("Starting build: " .. selectedBuildName)
	dprint("Build started:", total, "parts at center", tostring(buildCenter))

	-- Create models via F3X CreateGroup so server knows them
	if selectedBuildData.Models then
		for modelRef, modelInfo in pairs(selectedBuildData.Models) do
			dprint("Creating model:", modelRef, modelInfo.Name)
			local model
			local ok, result = pcall(function()
				return F3X:CreateGroup(modelInfo.ClassName or "Model", workspace, {})
			end)
			if ok and result then
				model = result
				pcall(function() F3X:SetName({model}, modelInfo.Name or "Model") end)
				dprint("Model created via F3X:", modelInfo.Name)
			else
				model = Instance.new(modelInfo.ClassName or "Model")
				model.Name = modelInfo.Name or "Model"
				model.Parent = workspace
				dprint("Model created locally (fallback):", modelInfo.Name)
			end
			modelMap[modelRef] = model
			if modelInfo.Name and modelInfo.Name ~= modelRef then
				modelMap[modelInfo.Name] = model
			end
		end
	end

	-- Build all parts into workspace first (F3X CreatePart ONLY accepts workspace as parent)
	for i, partData in ipairs(parts) do
		local className = partData.ClassName or "Part"
		local partType = "Normal"

		if className == "WedgePart" then partType = "Wedge"
		elseif className == "CornerWedgePart" then partType = "Corner"
		elseif className == "TrussPart" then partType = "Truss"
		elseif className == "Seat" then partType = "Seat"
		elseif className == "VehicleSeat" then partType = "Vehicle Seat"
		elseif className == "SpawnLocation" then partType = "Spawn"
		elseif className == "MeshPart" then partType = "Normal"
		end

		-- Parse CFrame robustly
		local cf = parseCFrame(partData.CFrame)
		dprint("Part", i, "Type:", partType, "CF:", tostring(cf))

		-- CRITICAL: Always pass workspace. Never pass a model as parent.
		local part
		local createOk, createResult = pcall(function()
			part = F3X:CreatePart(partType, cf)
			return part
		end)

		if not createOk or not part then
			failedCount += 1
			dprint("FAILED to create part", i, "Error:", tostring(createResult))
		else
			table.insert(builtParts, part)
			partMap[i] = part

			-- Apply properties in batches
			local resizeChanges = {}
			local colorChanges = {}
			local materialChanges = {}
			local surfaceChanges = {}
			local anchorChanges = {}
			local collisionChanges = {}

			if partData.Size then
				local size = parseVector3(partData.Size)
				table.insert(resizeChanges, {Part = part, Size = size, CFrame = cf})
			end

			if partData.Color then
				local color = parseColor3(partData.Color)
				table.insert(colorChanges, {Part = part, Color = color})
			end

			local matData = {Part = part}
			if partData.Material then matData.Material = parseMaterial(partData.Material) end
			if partData.Transparency ~= nil then matData.Transparency = partData.Transparency end
			if partData.Reflectance ~= nil then matData.Reflectance = partData.Reflectance end
			if next(matData) then table.insert(materialChanges, matData) end

			if partData.Anchored ~= nil then
				table.insert(anchorChanges, {Part = part, Anchored = partData.Anchored})
			end
			if partData.CanCollide ~= nil then
				table.insert(collisionChanges, {Part = part, CanCollide = partData.CanCollide})
			end

			local surfaces = {}
			if partData.TopSurface then surfaces.Top = parseSurface(partData.TopSurface) end
			if partData.BottomSurface then surfaces.Bottom = parseSurface(partData.BottomSurface) end
			if partData.LeftSurface then surfaces.Left = parseSurface(partData.LeftSurface) end
			if partData.RightSurface then surfaces.Right = parseSurface(partData.RightSurface) end
			if partData.FrontSurface then surfaces.Front = parseSurface(partData.FrontSurface) end
			if partData.BackSurface then surfaces.Back = parseSurface(partData.BackSurface) end
			if next(surfaces) then
				table.insert(surfaceChanges, {Part = part, Surfaces = surfaces})
			end

			-- Apply all sync operations
			pcall(function() if #resizeChanges > 0 then F3X:SyncResize(resizeChanges) end end)
			pcall(function() if #colorChanges > 0 then F3X:SyncColor(colorChanges) end end)
			pcall(function() if #materialChanges > 0 then F3X:SyncMaterial(materialChanges) end end)
			pcall(function() if #surfaceChanges > 0 then F3X:SyncSurface(surfaceChanges) end end)
			pcall(function() if #anchorChanges > 0 then F3X:SyncAnchor(anchorChanges) end end)
			pcall(function() if #collisionChanges > 0 then F3X:SyncCollision(collisionChanges) end end)

			-- Name
			if partData.Name then
				pcall(function() F3X:SetName({part}, partData.Name) end)
			end

			-- Locked
			if partData.Locked ~= nil then
				pcall(function() F3X:SetLocked({part}, partData.Locked) end)
			end

			-- Direct properties
			if partData.CastShadow ~= nil then part.CastShadow = partData.CastShadow end
			if partData.Shape then pcall(function() part.Shape = parseShape(partData.Shape) end) end
			if partData.Massless then part.Massless = true end
			if partData.CollisionGroupId then part.CollisionGroupId = partData.CollisionGroupId end

			if partData.CustomPhysicalProperties then
				local cpp = partData.CustomPhysicalProperties
				pcall(function()
					part.CustomPhysicalProperties = PhysicalProperties.new(
						cpp.Density or 0.7, cpp.Friction or 0.3, cpp.Elasticity or 0.5,
						cpp.FrictionWeight or 1, cpp.ElasticityWeight or 1
					)
				end)
			end

			-- MeshPart extras
			if className == "MeshPart" then
				if partData.MeshId or partData.TextureID or partData.RenderFidelity then
					pcall(function()
						F3X:CreateMeshes({part})
						local meshChanges = {Part = part}
						if partData.MeshId then meshChanges.MeshId = partData.MeshId end
						if partData.TextureID then meshChanges.TextureId = partData.TextureID end
						if partData.RenderFidelity then meshChanges.RenderFidelity = partData.RenderFidelity end
						if partData.CollisionFidelity then meshChanges.CollisionFidelity = partData.CollisionFidelity end
						F3X:SyncMesh({meshChanges})
					end)
				end
			end

			-- Children (decals, meshes, lights, etc.)
			if partData.Children then
				for _, childData in ipairs(partData.Children) do
					pcall(function()
						if childData.ClassName == "Decal" or childData.ClassName == "Texture" then
							F3X:CreateTextures({{Part = part, Face = parseNormalId(childData.Face), TextureType = childData.ClassName}})
							local texChanges = {Part = part, Face = parseNormalId(childData.Face), TextureType = childData.ClassName}
							if childData.Texture then texChanges.Texture = childData.Texture end
							if childData.Transparency ~= nil then texChanges.Transparency = childData.Transparency end
							F3X:SyncTexture({texChanges})

						elseif childData.ClassName == "SpecialMesh" then
							F3X:CreateMeshes({part})
							local meshChanges = {Part = part}
							if childData.MeshType then meshChanges.MeshType = parseMeshType(childData.MeshType) end
							if childData.MeshId then meshChanges.MeshId = childData.MeshId end
							if childData.TextureId then meshChanges.TextureId = childData.TextureId end
							if childData.Scale then meshChanges.Scale = parseVector3(childData.Scale) end
							if childData.Offset then meshChanges.Offset = parseVector3(childData.Offset) end
							F3X:SyncMesh({meshChanges})

						elseif childData.ClassName == "BlockMesh" or childData.ClassName == "CylinderMesh" then
							F3X:CreateMeshes({part})
							local meshChanges = {Part = part}
							if childData.ClassName == "BlockMesh" then meshChanges.MeshType = Enum.MeshType.Brick end
							if childData.ClassName == "CylinderMesh" then meshChanges.MeshType = Enum.MeshType.Cylinder end
							if childData.Scale then meshChanges.Scale = parseVector3(childData.Scale) end
							if childData.Offset then meshChanges.Offset = parseVector3(childData.Offset) end
							F3X:SyncMesh({meshChanges})

						elseif childData.ClassName == "SurfaceLight" or childData.ClassName == "PointLight" or childData.ClassName == "SpotLight" then
							F3X:CreateLights({{Part = part, LightType = childData.ClassName}})
							local lightChanges = {Part = part, LightType = childData.ClassName}
							if childData.Color then lightChanges.Color = parseColor3(childData.Color) end
							if childData.Brightness ~= nil then lightChanges.Brightness = childData.Brightness end
							if childData.Range ~= nil then lightChanges.Range = childData.Range end
							if childData.Shadows ~= nil then lightChanges.Shadows = childData.Shadows end
							if childData.Face then lightChanges.Face = parseNormalId(childData.Face) end
							if childData.Angle ~= nil then lightChanges.Angle = childData.Angle end
							F3X:SyncLighting({lightChanges})
						end
					end)
				end
			end
		end

		-- Progress
		if i % 10 == 0 or i == total then
			progressFill.Size = UDim2.new(i / total, 0, 1, 0)
			statusLabel.Text = string.format("Building... %d/%d parts (%d failed)", i, total, failedCount)
			if CONFIG.BuildSpeed > 0 then task.wait(CONFIG.BuildSpeed) end
		end
	end

	-- Reparent parts to models AFTER all creation (batch by target)
	local parentGroups = {}
	for i, partData in ipairs(parts) do
		local part = partMap[i]
		if part and partData.ParentName and partData.ParentName ~= "workspace" then
			local target = modelMap[partData.ParentName]
			if target then
				if not parentGroups[target] then parentGroups[target] = {} end
				table.insert(parentGroups[target], part)
			end
		end
	end

	if next(parentGroups) then
		statusLabel.Text = "Setting part parents..."
		for targetParent, partList in pairs(parentGroups) do
			pcall(function()
				F3X:SetParent(partList, targetParent)
				dprint("Reparented", #partList, "parts to", targetParent.Name)
			end)
		end
	end

	-- Welds
	if selectedBuildData.Welds then
		statusLabel.Text = "Applying welds..."
		for _, weldData in ipairs(selectedBuildData.Welds) do
			if weldData.Part0Index and weldData.Part1Index then
				local p0 = partMap[weldData.Part0Index]
				local p1 = partMap[weldData.Part1Index]
				if p0 and p1 then
					pcall(function() F3X:CreateWelds({p0}, p1) end)
				end
			end
		end
	end

	for i, partData in ipairs(parts) do
		if partData.Welds then
			for _, weldData in ipairs(partData.Welds) do
				if weldData.Part0Index and weldData.Part1Index then
					local p0 = partMap[weldData.Part0Index]
					local p1 = partMap[weldData.Part1Index]
					if p0 and p1 then
						pcall(function() F3X:CreateWelds({p0}, p1) end)
					end
				end
			end
		end
	end

	progressFill.Size = UDim2.new(1, 0, 1, 0)
	task.wait(0.5)
	progressFrame.Visible = false
	buildBtn.Visible = true

	local msg = string.format("✅ Built %d/%d parts!", total - failedCount, total)
	if failedCount > 0 then
		msg = msg .. string.format(" (%d failed)", failedCount)
	end
	statusLabel.Text = msg
	notify(msg)
	dprint("Build complete. Failed:", failedCount)
end)

-- ==================== INIT ====================
notify("F3X Build Loader ready! Click 🏗️ to open.")
