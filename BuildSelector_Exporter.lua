--[[
 ============================================
 BUILD SELECTOR & F3X EXPORTER
 Left-click drag-select | Xeno workspace save
 Exports in F3X-compatible JSON format
 Place in StarterPlayerScripts as LocalScript
 ============================================
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

-- ==================== XENO FILE API ====================
local writefile = writefile
local makefolder = makefolder
local isfolder = isfolder
local delfile = delfile
local readfile = readfile
local listfiles = listfiles
local setclipboard = setclipboard

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

-- Config
local CONFIG = {
 SelectionColor = Color3.fromRGB(0, 170, 255),
 BoxFillTransparency = 0.88,
 MaxParts = 10000,
 VisualLimit = 300,
 DragThreshold = 5,
}

-- State
local selectedParts = {}
local selectionBoxes = {}
local isDragging = false
local dragStartPos = nil
local dragCurrentPos = nil
local clickMode = false
local clickTarget = nil
local mouseDownPos = nil
local exportInProgress = false
local selectionEnabled = true

-- ==================== UI ====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuildSelector"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 320, 0, 540)
mainFrame.Position = UDim2.new(1, -340, 0.5, -270)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)

-- Title
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, -90, 1, 0)
titleText.Position = UDim2.new(0, 14, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "🏗️ Build Selector"
titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
titleText.TextSize = 16
titleText.Font = Enum.Font.GothamBold
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.Parent = titleBar

local countText = Instance.new("TextLabel")
countText.Size = UDim2.new(0, 80, 0, 44)
countText.Position = UDim2.new(1, -85, 0, 0)
countText.BackgroundTransparency = 1
countText.Text = "0 parts"
countText.TextColor3 = Color3.fromRGB(160, 160, 170)
countText.TextSize = 13
countText.Font = Enum.Font.Gotham
countText.TextXAlignment = Enum.TextXAlignment.Right
countText.Parent = titleBar

-- Status
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 22)
statusLabel.Position = UDim2.new(0, 10, 0, 48)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "🖱️ Click empty space & drag to select"
statusLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.Parent = mainFrame

-- Progress Bar
local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(1, -20, 0, 4)
progressFrame.Position = UDim2.new(0, 10, 0, 74)
progressFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
progressFrame.BorderSizePixel = 0
progressFrame.Visible = false
progressFrame.Parent = mainFrame
Instance.new("UICorner", progressFrame).CornerRadius = UDim.new(1, 0)

local progressFill = Instance.new("Frame")
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = CONFIG.SelectionColor
progressFill.BorderSizePixel = 0
progressFill.Parent = progressFrame
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

-- Scroll List
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -310)
scrollFrame.Position = UDim2.new(0, 10, 0, 84)
scrollFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 4
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 70)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = mainFrame
Instance.new("UICorner", scrollFrame).CornerRadius = UDim.new(0, 8)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.Parent = scrollFrame

-- Toggles
local togglesFrame = Instance.new("Frame")
togglesFrame.Size = UDim2.new(1, -20, 0, 70)
togglesFrame.Position = UDim2.new(0, 10, 1, -218)
togglesFrame.BackgroundTransparency = 1
togglesFrame.Parent = mainFrame

local togglesLayout = Instance.new("UIListLayout")
togglesLayout.FillDirection = Enum.FillDirection.Horizontal
togglesLayout.Padding = UDim.new(0, 6)
togglesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
togglesLayout.Parent = togglesFrame

local toggles = {}
local function createToggle(text, default)
 local frame = Instance.new("Frame")
 frame.Size = UDim2.new(0.5, -3, 0, 32)
 frame.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
 frame.BorderSizePixel = 0
 frame.Parent = togglesFrame
 Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

 local circle = Instance.new("Frame")
 circle.Size = UDim2.new(0, 16, 0, 16)
 circle.Position = UDim2.new(0, 8, 0.5, -8)
 circle.BackgroundColor3 = default and CONFIG.SelectionColor or Color3.fromRGB(80, 80, 90)
 circle.BorderSizePixel = 0
 circle.Parent = frame
 Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)

 local label = Instance.new("TextLabel")
 label.Size = UDim2.new(1, -32, 1, 0)
 label.Position = UDim2.new(0, 30, 0, 0)
 label.BackgroundTransparency = 1
 label.Text = text
 label.TextColor3 = Color3.fromRGB(180, 180, 190)
 label.TextSize = 11
 label.Font = Enum.Font.Gotham
 label.TextXAlignment = Enum.TextXAlignment.Left
 label.Parent = frame

 local btn = Instance.new("TextButton")
 btn.Size = UDim2.new(1, 0, 1, 0)
 btn.BackgroundTransparency = 1
 btn.Text = ""
 btn.Parent = frame

 local state = default
 btn.MouseButton1Click:Connect(function()
 state = not state
 TweenService:Create(circle, TweenInfo.new(0.2), {
 BackgroundColor3 = state and CONFIG.SelectionColor or Color3.fromRGB(80, 80, 90)
 }):Play()
 end)

 return {Frame = frame, Get = function() return state end}
end

toggles.Hierarchy = createToggle("Preserve Hierarchy", true)
toggles.Welds = createToggle("Include Welds", true)
toggles.Decals = createToggle("Include Decals", true)
toggles.Meshes = createToggle("Include Meshes", true)
toggles.Lights = createToggle("Include Lights", true)

-- Buttons
local btnFrame = Instance.new("Frame")
btnFrame.Size = UDim2.new(1, -20, 0, 142)
btnFrame.Position = UDim2.new(0, 10, 1, -142)
btnFrame.BackgroundTransparency = 1
btnFrame.Parent = mainFrame

local btnLayout = Instance.new("UIListLayout")
btnLayout.FillDirection = Enum.FillDirection.Vertical
btnLayout.Padding = UDim.new(0, 6)
btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
btnLayout.Parent = btnFrame

local function makeBtn(text, color, height)
 local btn = Instance.new("TextButton")
 btn.Size = UDim2.new(1, 0, 0, height or 34)
 btn.BackgroundColor3 = color
 btn.Text = text
 btn.TextColor3 = Color3.fromRGB(255, 255, 255)
 btn.TextSize = 14
 btn.Font = Enum.Font.GothamBold
 btn.AutoButtonColor = true
 Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
 return btn
end

local toggleSelectBtn = makeBtn("🟢 Selection: ON", Color3.fromRGB(0, 130, 80), 32)
toggleSelectBtn.Parent = btnFrame

local exportF3XBtn = makeBtn("📋 Export F3X JSON", Color3.fromRGB(0, 130, 220), 34)
exportF3XBtn.Parent = btnFrame

local exportLuaBtn = makeBtn("📄 Export Lua Script", Color3.fromRGB(0, 150, 100), 32)
exportLuaBtn.Parent = btnFrame

local clearBtn = makeBtn("❌ Clear Selection", Color3.fromRGB(180, 50, 50), 30)
clearBtn.Parent = btnFrame

-- Marquee
local marquee = Instance.new("Frame")
marquee.BackgroundColor3 = CONFIG.SelectionColor
marquee.BackgroundTransparency = CONFIG.BoxFillTransparency
marquee.BorderSizePixel = 0
marquee.Visible = false
marquee.ZIndex = 1000
marquee.Parent = screenGui

local marqueeStroke = Instance.new("UIStroke")
marqueeStroke.Color = CONFIG.SelectionColor
marqueeStroke.Thickness = 2
marqueeStroke.Parent = marquee

-- Notification
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

-- ==================== HELPERS ====================
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

local function updateCount()
 countText.Text = string.format("%d parts", #selectedParts)
end

local function clearList()
 for _, child in ipairs(scrollFrame:GetChildren()) do
 if child:IsA("Frame") then child:Destroy() end
 end
end

local function addListItem(name, class)
 local row = Instance.new("Frame")
 row.Size = UDim2.new(1, -10, 0, 26)
 row.BackgroundTransparency = 1
 row.Parent = scrollFrame

 local dot = Instance.new("TextLabel")
 dot.Size = UDim2.new(0, 20, 1, 0)
 dot.BackgroundTransparency = 1
 dot.Text = "•"
 dot.TextColor3 = CONFIG.SelectionColor
 dot.TextSize = 14
 dot.Font = Enum.Font.GothamBold
 dot.Parent = row

 local label = Instance.new("TextLabel")
 label.Size = UDim2.new(1, -25, 1, 0)
 label.Position = UDim2.new(0, 20, 0, 0)
 label.BackgroundTransparency = 1
 label.Text = string.format("%s (%s)", name, class)
 label.TextColor3 = Color3.fromRGB(200, 200, 210)
 label.TextSize = 12
 label.Font = Enum.Font.Gotham
 label.TextXAlignment = Enum.TextXAlignment.Left
 label.TextTruncate = Enum.TextTruncate.AtEnd
 label.Parent = row
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
 if selectionBoxes[part] then
 selectionBoxes[part]:Destroy()
 selectionBoxes[part] = nil
 end
 end
end

local function clearSelection()
 for part, box in pairs(selectionBoxes) do
 if box then box:Destroy() end
 end
 selectedParts = {}
 selectionBoxes = {}
 updateCount()
 clearList()
 statusLabel.Text = "🖱️ Click empty space & drag to select"
end

local function addPart(part)
 if #selectedParts >= CONFIG.MaxParts then return end
 if table.find(selectedParts, part) then return end
 table.insert(selectedParts, part)
 setVisual(part, true)
 addListItem(part.Name, part.ClassName)
 updateCount()
end

local function removePart(part)
 local idx = table.find(selectedParts, part)
 if idx then
 table.remove(selectedParts, idx)
 setVisual(part, false)
 updateCount()
 clearList()
 for _, p in ipairs(selectedParts) do
 addListItem(p.Name, p.ClassName)
 end
 end
end

local function getPartUnderMouse()
 local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
 local params = RaycastParams.new()
 params.FilterType = Enum.RaycastFilterType.Blacklist
 params.FilterDescendantsInstances = {player.Character or Instance.new("Model")}

 local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
 if result and result.Instance then
 local obj = result.Instance
 while obj and not obj:IsA("BasePart") do
 obj = obj.Parent
 end
 return obj
 end
 return nil
end

local function partInMarquee(part, startPos, endPos)
 local minX, maxX = math.min(startPos.X, endPos.X), math.max(startPos.X, endPos.X)
 local minY, maxY = math.min(startPos.Y, endPos.Y), math.max(startPos.Y, endPos.Y)

 local centerScreen, onScreen = camera:WorldToViewportPoint(part.Position)
 if not onScreen then return false end

 if centerScreen.X >= minX and centerScreen.X <= maxX
 and centerScreen.Y >= minY and centerScreen.Y <= maxY then
 return true
 end

 local size = part.Size / 2
 local cf = part.CFrame
 for sx = -1, 1, 2 do
 for sy = -1, 1, 2 do
 for sz = -1, 1, 2 do
 local corner = cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
 local sp, vis = camera:WorldToViewportPoint(corner)
 if vis and sp.X >= minX and sp.X <= maxX and sp.Y >= minY and sp.Y <= maxY then
 return true
 end
 end
 end
 end
 return false
end

-- ==================== ENABLE/DISABLE ====================
toggleSelectBtn.MouseButton1Click:Connect(function()
 selectionEnabled = not selectionEnabled
 if selectionEnabled then
 toggleSelectBtn.Text = "🟢 Selection: ON"
 toggleSelectBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 80)
 statusLabel.Text = "🖱️ Click empty space & drag to select"
 notify("Selection enabled")
 else
 toggleSelectBtn.Text = "🔴 Selection: OFF"
 toggleSelectBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
 statusLabel.Text = "❌ Selection disabled — click to re-enable"
 notify("Selection disabled")
 isDragging = false
 marquee.Visible = false
 clickMode = false
 clickTarget = nil
 mouseDownPos = nil
 dragStartPos = nil
 dragCurrentPos = nil
 end
end)

-- ==================== INPUT ====================
UserInputService.InputBegan:Connect(function(input, gpe)
 if not selectionEnabled then return end
 if gpe then return end
 if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
 if exportInProgress then return end

 local guiObjects = player.PlayerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
 for _, obj in ipairs(guiObjects) do
 if obj:IsDescendantOf(mainFrame) or obj:IsDescendantOf(notif) then return end
 end

 mouseDownPos = Vector2.new(mouse.X, mouse.Y)
 dragStartPos = mouseDownPos
 dragCurrentPos = mouseDownPos
 isDragging = true

 clickTarget = getPartUnderMouse()
 if clickTarget then
 clickMode = true
 else
 clickMode = false
 marquee.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
 marquee.Size = UDim2.new(0, 0, 0, 0)
 marquee.Visible = true
 end
end)

UserInputService.InputChanged:Connect(function(input)
 if not selectionEnabled then return end
 if not isDragging then return end
 if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

 dragCurrentPos = Vector2.new(mouse.X, mouse.Y)
 local dist = (dragCurrentPos - mouseDownPos).Magnitude

 if clickMode and dist > CONFIG.DragThreshold then
 clickMode = false
 clickTarget = nil
 marquee.Position = UDim2.new(0, mouseDownPos.X, 0, mouseDownPos.Y)
 marquee.Size = UDim2.new(0, 0, 0, 0)
 marquee.Visible = true
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
 if not selectionEnabled then return end
 if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
 if not isDragging then return end

 isDragging = false
 marquee.Visible = false

 local dist = (dragCurrentPos - mouseDownPos).Magnitude
 local ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or
 UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

 if clickMode and dist <= CONFIG.DragThreshold then
 if clickTarget then
 if ctrlHeld then
 if table.find(selectedParts, clickTarget) then
 removePart(clickTarget)
 else
 addPart(clickTarget)
 end
 else
 if not table.find(selectedParts, clickTarget) then
 clearSelection()
 addPart(clickTarget)
 end
 end
 statusLabel.Text = string.format("Selected: %s", clickTarget.Name)
 end
 elseif not clickMode and dist > CONFIG.DragThreshold then
 if not ctrlHeld then clearSelection() end

 local found = 0
 for _, obj in ipairs(workspace:GetDescendants()) do
 if obj:IsA("BasePart") and obj ~= player.Character
 and not obj:IsDescendantOf(player.Character or Instance.new("Model")) then
 if partInMarquee(obj, dragStartPos, dragCurrentPos) then
 addPart(obj)
 found += 1
 if found >= CONFIG.MaxParts then break end
 end
 end
 end

 statusLabel.Text = string.format("Box-selected %d parts", found)
 if found > CONFIG.VisualLimit then
 statusLabel.Text = statusLabel.Text .. string.format(" (showing %d visuals)", CONFIG.VisualLimit)
 end
 elseif not clickMode and dist <= CONFIG.DragThreshold then
 if not ctrlHeld then clearSelection() end
 end

 clickMode = false
 clickTarget = nil
 mouseDownPos = nil
 dragStartPos = nil
 dragCurrentPos = nil
end)

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
 mainFrame.Position = UDim2.new(
 uiStartPos.X.Scale, uiStartPos.X.Offset + delta.X,
 uiStartPos.Y.Scale, uiStartPos.Y.Offset + delta.Y
 )
 end
end)

UserInputService.InputEnded:Connect(function(input)
 if input.UserInputType == Enum.UserInputType.MouseButton1 then
 draggingUI = false
 end
end)

clearBtn.MouseButton1Click:Connect(function()
 clearSelection()
 notify("Selection cleared")
end)

-- ==================== EXPORT FORMATTERS ====================
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
 elseif t == "EnumItem" then return tostring(v)
 else return string.format("%q", tostring(v))
 end
end

-- ==================== F3X JSON EXPORT ====================
exportF3XBtn.MouseButton1Click:Connect(function()
 if #selectedParts == 0 then
 notify("No parts selected!")
 return
 end
 if exportInProgress then return end
 exportInProgress = true

 notify("Generating F3X JSON...")
 statusLabel.Text = "⏳ Exporting F3X JSON..."
 progressFrame.Visible = true
 progressFill.Size = UDim2.new(0, 0, 1, 0)

 local buildData = {
 BuildName = "ExportedBuild",
 PlaceId = game.PlaceId,
 Timestamp = os.date("%Y-%m-%d %H:%M:%S"),
 PartCount = #selectedParts,
 Parts = {}
 }

 local partMap = {}
 local modelMap = {}

 -- Hierarchy pass
 if toggles.Hierarchy.Get() then
 for i, part in ipairs(selectedParts) do
 local parent = part.Parent
 while parent and parent ~= workspace do
 if (parent:IsA("Model") or parent:IsA("Folder")) and not modelMap[parent] then
 modelMap[parent] = {
 Name = parent.Name,
 ClassName = parent.ClassName,
 Parent = parent.Parent and parent.Parent.Name or nil
 }
 end
 parent = parent.Parent
 end
 end
 buildData.Models = modelMap
 end

 -- Parts
 for i, part in ipairs(selectedParts) do
 partMap[part] = i
 local data = {
 Index = i,
 ClassName = part.ClassName,
 Name = part.Name,
 }

 if part:IsA("BasePart") then
 local cf = part.CFrame
 data.CFrame = {cf:GetComponents()}
 data.Size = {part.Size.X, part.Size.Y, part.Size.Z}
 data.Color = {math.floor(part.Color.R * 255 + 0.5), math.floor(part.Color.G * 255 + 0.5), math.floor(part.Color.B * 255 + 0.5)}
 data.Material = tostring(part.Material)
 data.Transparency = part.Transparency
 data.Reflectance = part.Reflectance
 data.CanCollide = part.CanCollide
 data.Anchored = part.Anchored
 data.CastShadow = part.CastShadow
 data.Locked = part.Locked
 data.TopSurface = tostring(part.TopSurface)
 data.BottomSurface = tostring(part.BottomSurface)
 data.LeftSurface = tostring(part.LeftSurface)
 data.RightSurface = tostring(part.RightSurface)
 data.FrontSurface = tostring(part.FrontSurface)
 data.BackSurface = tostring(part.BackSurface)

 if part:IsA("Part") then
 data.Shape = tostring(part.Shape)
 end
 end

 if part:IsA("MeshPart") then
 local ok1, meshId = pcall(function() return part.MeshId end)
 local ok2, texId = pcall(function() return part.TextureID end)
 if ok1 then data.MeshId = meshId end
 if ok2 then data.TextureID = texId end
 local ok3, rf = pcall(function() return tostring(part.RenderFidelity) end)
 if ok3 then data.RenderFidelity = rf end
 local ok4, cf = pcall(function() return tostring(part.CollisionFidelity) end)
 if ok4 then data.CollisionFidelity = cf end
 end

 local okMass, massless = pcall(function() return part.Massless end)
 if okMass and massless then data.Massless = true end

 local okCid, cid = pcall(function() return part.CollisionGroupId end)
 if okCid and cid ~= 0 then data.CollisionGroupId = cid end

 local okCpp, cpp = pcall(function() return part.CustomPhysicalProperties end)
 if okCpp and cpp then
 data.CustomPhysicalProperties = {
 Density = cpp.Density,
 Friction = cpp.Friction,
 Elasticity = cpp.Elasticity,
 FrictionWeight = cpp.FrictionWeight,
 ElasticityWeight = cpp.ElasticityWeight
 }
 end

 -- Parent reference
 if toggles.Hierarchy.Get() then
 local parent = part.Parent
 if parent and parent ~= workspace then
 data.ParentName = parent.Name
 data.ParentClass = parent.ClassName
 else
 data.ParentName = "workspace"
 end
 else
 data.ParentName = "workspace"
 end

 -- Children
 data.Children = {}

 if toggles.Decals.Get() then
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("Decal") or child:IsA("Texture") then
 local childData = {
 ClassName = child.ClassName,
 Texture = child.Texture,
 Transparency = child.Transparency,
 Face = tostring(child.Face)
 }
 local ok, c3 = pcall(function() return child.Color3 end)
 if ok then
 childData.Color3 = {math.floor(c3.R * 255 + 0.5), math.floor(c3.G * 255 + 0.5), math.floor(c3.B * 255 + 0.5)}
 end
 table.insert(data.Children, childData)
 end
 end
 end

 if toggles.Meshes.Get() then
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("SpecialMesh") then
 table.insert(data.Children, {
 ClassName = "SpecialMesh",
 MeshType = tostring(child.MeshType),
 MeshId = child.MeshId,
 TextureId = child.TextureId,
 Scale = {child.Scale.X, child.Scale.Y, child.Scale.Z},
 Offset = {child.Offset.X, child.Offset.Y, child.Offset.Z}
 })
 elseif child:IsA("BlockMesh") then
 table.insert(data.Children, {
 ClassName = "BlockMesh",
 Scale = {child.Scale.X, child.Scale.Y, child.Scale.Z},
 Offset = {child.Offset.X, child.Offset.Y, child.Offset.Z}
 })
 elseif child:IsA("CylinderMesh") then
 table.insert(data.Children, {
 ClassName = "CylinderMesh",
 Scale = {child.Scale.X, child.Scale.Y, child.Scale.Z},
 Offset = {child.Offset.X, child.Offset.Y, child.Offset.Z}
 })
 end
 end
 end

 if toggles.Lights.Get() then
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("SurfaceLight") or child:IsA("PointLight") or child:IsA("SpotLight") then
 local lightData = {
 ClassName = child.ClassName,
 Color = {math.floor(child.Color.R * 255 + 0.5), math.floor(child.Color.G * 255 + 0.5), math.floor(child.Color.B * 255 + 0.5)},
 Brightness = child.Brightness,
 Range = child.Range,
 Shadows = child.Shadows,
 Face = tostring(child.Face)
 }
 if child:IsA("SurfaceLight") or child:IsA("SpotLight") then
 local okA, angle = pcall(function() return child.Angle end)
 if okA then lightData.Angle = angle end
 end
 table.insert(data.Children, lightData)
 end
 end
 end

 -- Welds
 if toggles.Welds.Get() then
 data.Welds = {}
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("Weld") or child:IsA("Motor") or child:IsA("Motor6D") then
 if partMap[child.Part0] and partMap[child.Part1] then
 table.insert(data.Welds, {
 ClassName = child.ClassName,
 Part0Index = partMap[child.Part0],
 Part1Index = partMap[child.Part1],
 C0 = {child.C0:GetComponents()},
 C1 = {child.C1:GetComponents()}
 })
 end
 elseif child:IsA("WeldConstraint") then
 if partMap[child.Part0] and partMap[child.Part1] then
 table.insert(data.Welds, {
 ClassName = "WeldConstraint",
 Part0Index = partMap[child.Part0],
 Part1Index = partMap[child.Part1]
 })
 end
 end
 end
 end

 table.insert(buildData.Parts, data)

 if i % 100 == 0 then
 progressFill.Size = UDim2.new(i / #selectedParts * 0.9, 0, 1, 0)
 task.wait()
 end
 end

 local jsonData = HttpService:JSONEncode(buildData)
 progressFill.Size = UDim2.new(0.95, 0, 1, 0)

 local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
 local filename = SAVE_FOLDER .. "/F3X_Build_" .. timestamp .. ".json"

 local ok, err = pcall(function()
 writefile(filename, jsonData)
 end)

 progressFill.Size = UDim2.new(1, 0, 1, 0)
 task.wait(0.3)
 progressFrame.Visible = false
 exportInProgress = false

 if ok then
 notify(string.format("F3X JSON saved! %d parts", #selectedParts))
 statusLabel.Text = string.format("✅ F3X JSON: %s", filename)
 print("[BuildSelector] Saved: " .. filename)

 if setclipboard then
 pcall(function() setclipboard(jsonData) end)
 print("[BuildSelector] Also copied to clipboard")
 end
 else
 if setclipboard then
 pcall(function() setclipboard(jsonData) end)
 notify("File write failed! Copied to clipboard.")
 else
 notify("Export failed: " .. tostring(err))
 end
 statusLabel.Text = "❌ Export failed"
 end
end)

-- ==================== LUA EXPORT ====================
exportLuaBtn.MouseButton1Click:Connect(function()
 if #selectedParts == 0 then
 notify("No parts selected!")
 return
 end
 if exportInProgress then return end
 exportInProgress = true

 notify("Generating Lua script...")
 statusLabel.Text = "⏳ Exporting Lua..."
 progressFrame.Visible = true
 progressFill.Size = UDim2.new(0, 0, 1, 0)

 local lines = {}
 table.insert(lines, "--[[")
 table.insert(lines, " Build Export - Standalone Rebuild Script")
 table.insert(lines, " Total Parts: " .. #selectedParts)
 table.insert(lines, " PlaceId: " .. tostring(game.PlaceId))
 table.insert(lines, " Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
 table.insert(lines, "]]")
 table.insert(lines, "")
 table.insert(lines, "local build = Instance.new(\"Model\")")
 table.insert(lines, "build.Name = \"ExportedBuild\"")
 table.insert(lines, "")

 local partMap = {}
 local modelMap = {}
 local welds = {}
 local constraints = {}
 local total = #selectedParts

 if toggles.Hierarchy.Get() then
 for i, part in ipairs(selectedParts) do
 local parent = part.Parent
 while parent and parent ~= workspace do
 if (parent:IsA("Model") or parent:IsA("Folder")) and not modelMap[parent] then
 local mVar = "m" .. (table.getn(modelMap) + 1)
 modelMap[parent] = mVar
 end
 parent = parent.Parent
 end
 if i % 200 == 0 then
 progressFill.Size = UDim2.new(i / total * 0.15, 0, 1, 0)
 task.wait()
 end
 end

 local created = {}
 for model, var in pairs(modelMap) do
 if not created[model] then
 table.insert(lines, string.format("local %s = Instance.new(%q)", var, model.ClassName))
 table.insert(lines, string.format("%s.Name = %q", var, model.Name))
 local parent = model.Parent
 if parent == workspace or parent == nil then
 table.insert(lines, string.format("%s.Parent = build", var))
 elseif modelMap[parent] then
 table.insert(lines, string.format("%s.Parent = %s", var, modelMap[parent]))
 else
 table.insert(lines, string.format("%s.Parent = build", var))
 end
 table.insert(lines, "")
 created[model] = true
 end
 end
 end

 for i, part in ipairs(selectedParts) do
 local var = "p" .. i
 partMap[part] = var

 table.insert(lines, string.format("local %s = Instance.new(%q)", var, part.ClassName))

 local props = {"Name", "Size", "CFrame", "Color", "Material", "Transparency",
 "Reflectance", "CanCollide", "Anchored", "CastShadow", "Locked"}
 for _, prop in ipairs(props) do
 local ok, val = pcall(function() return part[prop] end)
 if ok then
 table.insert(lines, string.format("%s.%s = %s", var, prop, fmtVal(val)))
 end
 end

 local surfaces = {"TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface"}
 for _, prop in ipairs(surfaces) do
 local ok, val = pcall(function() return part[prop] end)
 if ok then
 table.insert(lines, string.format("%s.%s = %s", var, prop, fmtVal(val)))
 end
 end

 if part:IsA("Part") then
 local ok, val = pcall(function() return part.Shape end)
 if ok then
 table.insert(lines, string.format("%s.Shape = %s", var, fmtVal(val)))
 end
 end

 if part:IsA("MeshPart") then
 local ok1, meshId = pcall(function() return part.MeshId end)
 local ok2, texId = pcall(function() return part.TextureID end)
 if ok1 and meshId ~= "" then
 table.insert(lines, string.format("%s.MeshId = %s", var, fmtVal(meshId)))
 end
 if ok2 and texId ~= "" then
 table.insert(lines, string.format("%s.TextureID = %s", var, fmtVal(texId)))
 end
 local ok3, rf = pcall(function() return part.RenderFidelity end)
 if ok3 then
 table.insert(lines, string.format("%s.RenderFidelity = %s", var, fmtVal(rf)))
 end
 local ok4, cf = pcall(function() return part.CollisionFidelity end)
 if ok4 then
 table.insert(lines, string.format("%s.CollisionFidelity = %s", var, fmtVal(cf)))
 end
 end

 local okMass, massless = pcall(function() return part.Massless end)
 if okMass and massless then
 table.insert(lines, string.format("%s.Massless = true", var))
 end

 local okCid, cid = pcall(function() return part.CollisionGroupId end)
 if okCid and cid ~= 0 then
 table.insert(lines, string.format("%s.CollisionGroupId = %d", var, cid))
 end

 local okCpp, cpp = pcall(function() return part.CustomPhysicalProperties end)
 if okCpp and cpp then
 table.insert(lines, string.format("%s.CustomPhysicalProperties = PhysicalProperties.new(%s, %s, %s, %s, %s)",
 var, fmtN(cpp.Density), fmtN(cpp.Friction), fmtN(cpp.Elasticity), fmtN(cpp.FrictionWeight), fmtN(cpp.ElasticityWeight)))
 end

 if toggles.Decals.Get() then
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("Decal") or child:IsA("Texture") then
 local cv = var .. "_d" .. tostring(math.random(1000, 9999))
 table.insert(lines, string.format("local %s = Instance.new(%q)", cv, child.ClassName))
 local cprops = {"Texture", "Transparency", "Face", "Color3"}
 for _, p in ipairs(cprops) do
 local ok, v = pcall(function() return child[p] end)
 if ok then table.insert(lines, string.format("%s.%s = %s", cv, p, fmtVal(v))) end
 end
 table.insert(lines, string.format("%s.Parent = %s", cv, var))
 end
 end
 end

 if toggles.Meshes.Get() then
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("SpecialMesh") then
 local cv = var .. "_m" .. tostring(math.random(1000, 9999))
 table.insert(lines, string.format("local %s = Instance.new(\"SpecialMesh\")", cv))
 local cprops = {"MeshType", "MeshId", "TextureId", "Scale", "Offset", "VertexColor"}
 for _, p in ipairs(cprops) do
 local ok, v = pcall(function() return child[p] end)
 if ok then table.insert(lines, string.format("%s.%s = %s", cv, p, fmtVal(v))) end
 end
 table.insert(lines, string.format("%s.Parent = %s", cv, var))
 elseif child:IsA("BlockMesh") then
 local cv = var .. "_bm" .. tostring(math.random(1000, 9999))
 table.insert(lines, string.format("local %s = Instance.new(\"BlockMesh\")", cv))
 local cprops = {"Scale", "Offset", "VertexColor"}
 for _, p in ipairs(cprops) do
 local ok, v = pcall(function() return child[p] end)
 if ok then table.insert(lines, string.format("%s.%s = %s", cv, p, fmtVal(v))) end
 end
 table.insert(lines, string.format("%s.Parent = %s", cv, var))
 elseif child:IsA("CylinderMesh") then
 local cv = var .. "_cm" .. tostring(math.random(1000, 9999))
 table.insert(lines, string.format("local %s = Instance.new(\"CylinderMesh\")", cv))
 local cprops = {"Scale", "Offset", "VertexColor"}
 for _, p in ipairs(cprops) do
 local ok, v = pcall(function() return child[p] end)
 if ok then table.insert(lines, string.format("%s.%s = %s", cv, p, fmtVal(v))) end
 end
 table.insert(lines, string.format("%s.Parent = %s", cv, var))
 end
 end
 end

 if toggles.Lights.Get() then
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("SurfaceLight") or child:IsA("PointLight") or child:IsA("SpotLight") then
 local cv = var .. "_l" .. tostring(math.random(1000, 9999))
 table.insert(lines, string.format("local %s = Instance.new(%q)", cv, child.ClassName))
 local cprops = {"Color", "Brightness", "Range", "Shadows", "Face"}
 for _, p in ipairs(cprops) do
 local ok, v = pcall(function() return child[p] end)
 if ok then table.insert(lines, string.format("%s.%s = %s", cv, p, fmtVal(v))) end
 end
 if child:IsA("SurfaceLight") or child:IsA("SpotLight") then
 local okA, angle = pcall(function() return child.Angle end)
 if okA then table.insert(lines, string.format("%s.Angle = %s", cv, fmtVal(angle))) end
 end
 table.insert(lines, string.format("%s.Parent = %s", cv, var))
 end
 end
 end

 if toggles.Welds.Get() then
 for _, child in ipairs(part:GetChildren()) do
 if child:IsA("Weld") or child:IsA("Motor") or child:IsA("Motor6D") then
 table.insert(welds, {
 var = var, class = child.ClassName,
 c0 = child.C0, c1 = child.C1,
 part0 = child.Part0, part1 = child.Part1
 })
 elseif child:IsA("WeldConstraint") then
 table.insert(constraints, {
 var = var,
 part0 = child.Part0, part1 = child.Part1
 })
 end
 end
 end

 if toggles.Hierarchy.Get() then
 local parent = part.Parent
 if modelMap[parent] then
 table.insert(lines, string.format("%s.Parent = %s", var, modelMap[parent]))
 else
 table.insert(lines, string.format("%s.Parent = build", var))
 end
 else
 table.insert(lines, string.format("%s.Parent = build", var))
 end

 table.insert(lines, "")

 if i % 100 == 0 then
 progressFill.Size = UDim2.new(0.15 + (i / total * 0.7), 0, 1, 0)
 task.wait()
 end
 end

 if toggles.Welds.Get() then
 if #constraints > 0 then
 table.insert(lines, "-- Weld Constraints")
 for _, w in ipairs(constraints) do
 if partMap[w.part0] and partMap[w.part1] then
 local wv = w.var .. "_wc" .. tostring(math.random(1000, 9999))
 table.insert(lines, string.format("local %s = Instance.new(\"WeldConstraint\")", wv))
 table.insert(lines, string.format("%s.Part0 = %s", wv, partMap[w.part0]))
 table.insert(lines, string.format("%s.Part1 = %s", wv, partMap[w.part1]))
 table.insert(lines, string.format("%s.Parent = %s", wv, w.var))
 end
 end
 table.insert(lines, "")
 end

 if #welds > 0 then
 table.insert(lines, "-- Welds / Motors")
 for _, w in ipairs(welds) do
 if partMap[w.part0] and partMap[w.part1] then
 local wv = w.var .. "_w" .. tostring(math.random(1000, 9999))
 table.insert(lines, string.format("local %s = Instance.new(%q)", wv, w.class))
 table.insert(lines, string.format("%s.Part0 = %s", wv, partMap[w.part0]))
 table.insert(lines, string.format("%s.Part1 = %s", wv, partMap[w.part1]))
 table.insert(lines, string.format("%s.C0 = %s", wv, fmtVal(w.c0)))
 table.insert(lines, string.format("%s.C1 = %s", wv, fmtVal(w.c1)))
 table.insert(lines, string.format("%s.Parent = %s", wv, w.var))
 end
 end
 table.insert(lines, "")
 end
 end

 table.insert(lines, "build.Parent = workspace")
local content = table.concat(lines, "\n")

 progressFill.Size = UDim2.new(0.95, 0, 1, 0)

 local content = table.concat(lines, "\n")
 local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
 local filename = SAVE_FOLDER .. "/Build_" .. timestamp .. ".lua"

 local ok, err = pcall(function()
 writefile(filename, content)
 end)

 progressFill.Size = UDim2.new(1, 0, 1, 0)
 task.wait(0.3)
 progressFrame.Visible = false
 exportInProgress = false

 if ok then
 notify(string.format("Lua saved! %d parts", #selectedParts))
 statusLabel.Text = string.format("✅ Lua: %s", filename)
 print("[BuildSelector] Saved: " .. filename)
 else
 if setclipboard then
 pcall(function() setclipboard(content) end)
 notify("File write failed! Copied to clipboard.")
 else
 notify("Export failed: " .. tostring(err))
 end
 statusLabel.Text = "❌ Export failed"
 end
end)

-- ==================== INIT ====================
if hasFileAccess then
 notify("Build Selector loaded! Selection is ON")
else
 notify("Build Selector loaded! (Clipboard fallback)")
end
