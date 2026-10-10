-- Roria Unbound encounter farm. Run with the executor after joining the game.
-- Linoria settings are stored by its ThemeManager and SaveManager.
local env = getgenv()
local previous = env.RoriaEncounterFarm
local p
local deadline = os.clock() + 30
repeat
    if type(filtergc) == "function" then
        local ok, found = pcall(filtergc, "table", {
            Keys = {"Battle", "DataManager", "Network"}
        }, true)
        if ok and type(found) == "table" and found.Battle
            and found.DataManager and found.Network then
            p = found
        end
        if not p then
            local fallbackOk, matches = pcall(filtergc, "table", {
                Keys = {"Battle", "DataManager"}
            }, false)
            if fallbackOk and type(matches) == "table" then
                if matches.Battle and matches.DataManager and matches.Network then
                    p = matches
                else
                    for _, candidate in matches do
                        if type(candidate) == "table" and candidate.Battle
                            and candidate.DataManager and candidate.Network then
                            p = candidate
                            break
                        end
                    end
                end
            end
        end
    end
    if not p and previous and previous.placeId == game.PlaceId
        and previous.jobId == game.JobId then
        local cached = previous.gameData
        if cached and cached.Battle and cached.DataManager and cached.Network then
            p = cached
        end
    end
    if not p then task.wait(0.5) end
until p or os.clock() >= deadline
assert(p, "Roria game data was not found after 30 seconds; wait until the game finishes loading and run the script again")

if previous then
    previous.running = false
    if previous.restoreFast then
        previous.restoreFast()
    end
    if previous.restorePerfect then
        previous.restorePerfect()
    end
    if previous.restoreMovement then
        previous.restoreMovement()
    end
    if previous.restoreEsp then
        previous.restoreEsp()
    end
    if previous.library then
        pcall(function() previous.library:Unload() end)
    elseif previous.gui then
        previous.gui:Destroy()
    end
end

local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
Library.ScreenGui.Parent = gethui()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
ThemeManager.BuiltInThemes["Amber Graphite"] = {9, {
    FontColor = "ffffff",
    MainColor = "151515",
    AccentColor = "ffc845",
    BackgroundColor = "0c0c0c",
    OutlineColor = "383838"
}}
ThemeManager.DefaultTheme = "Amber Graphite"

local state = {
    gameData = p,
    placeId = game.PlaceId,
    jobId = game.JobId,
    running = false,
    entries = {},
    byDisplay = {},
    chancesByMethod = {},
    chancesBySpecies = {},
    selectedKeys = {},
    encounterChoices = {},
    targetLabel = "None",
    noneWasSelected = true,
    noneEncounter = nil,
    catchOnFind = false,
    stopOnShiny = false,
    chanceThreshold = 0,
    notifyOnEncounter = false,
    notificationSounds = true,
    notificationSoundId = "17208361335",
    npcEspEnabled = false,
    webhookEnabled = false,
    webhookEveryEncounter = false,
    webhookUrl = "",
    autoRefresh = true,
    autoHeal = false,
    ballRunning = false,
    perfectBall = false,
    noclip = false,
    speedEnabled = false,
    hipEnabled = false,
    library = Library
}
env.RoriaEncounterFarm = state

local originalNotify = Library.Notify
Library.Notify = function(self, message, duration)
    local result = originalNotify(self, message, duration)
    if state.notificationSounds then
        local id = string.match(tostring(state.notificationSoundId), "^%s*(%d+)%s*$")
        if id then
            local sound = Instance.new("Sound")
            sound.SoundId = "rbxassetid://" .. id
            sound.Volume = 0.5
            sound.Parent = game:GetService("SoundService")
            game:GetService("Debris"):AddItem(sound, 10)
            sound:Play()
        end
    end
    return result
end

local Window = Library:CreateWindow({
    Title = "ArtificalCheat",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})
local Tabs = {
    Main = Window:AddTab("Main"),
    Farm = Window:AddTab("Farm"),
    ESP = Window:AddTab("ESP"),
    Settings = Window:AddTab("Configs")
}
local MovementGroup = Tabs.Main:AddLeftGroupbox("Movement")
local EncounterGroup = Tabs.Main:AddRightGroupbox("Encounter")
local EspGroup = Tabs.ESP:AddLeftGroupbox("NPC")
local PlayerEspGroup = Tabs.ESP:AddRightGroupbox("Player")
local FarmGroup = Tabs.Farm:AddLeftGroupbox("Encounter Farm")
local BallGroup = Tabs.Farm:AddLeftGroupbox("Poké Ball Farm")
local InfoGroup = Tabs.Farm:AddRightGroupbox("Encounter Status")
local WebhookGroup = Tabs.Farm:AddRightGroupbox("Encounter Webhook")
local BallInfoGroup = Tabs.Farm:AddRightGroupbox("Poké Ball Status")
local HealGroup = Tabs.Farm:AddRightGroupbox("Auto Heal")
local MenuGroup = Tabs.Settings:AddRightGroupbox("Menu")
local regionLabel = InfoGroup:AddLabel("Loading region...", true)
local statusLabel = InfoGroup:AddLabel("Idle", true)
local webhookStatusLabel = WebhookGroup:AddLabel("Disabled", true)
local ballStatusLabel = BallInfoGroup:AddLabel("Idle", true)
local healStatusLabel = HealGroup:AddLabel("Disabled", true)

local player = game:GetService("Players").LocalPlayer
local initialHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
local originalHumanoids = setmetatable({}, {__mode = "k"})
local originalCollisions = setmetatable({}, {__mode = "k"})
state.desiredSpeed = 30
state.desiredHip = 2
if initialHumanoid then
    originalHumanoids[initialHumanoid] = {hip = initialHumanoid.HipHeight}
end

local function restoreCollisions()
    for part, canCollide in originalCollisions do
        if part.Parent then part.CanCollide = canCollide end
        originalCollisions[part] = nil
    end
end

state.restoreMovement = function()
    state.noclip = false
    state.speedEnabled = false
    state.hipEnabled = false
    restoreCollisions()
    for humanoid, values in originalHumanoids do
        if humanoid.Parent then
            humanoid.HipHeight = values.hip
        end
    end
end

local throwSystem = p.PokeThrow
if throwSystem and type(throwSystem.doThrow) == "function" then
    local originalDoThrow = throwSystem.doThrow
    local originalGetRating = throwSystem.getRating
    local function perfectRating(self, size)
        if state.perfectBall then return originalGetRating(self, 0) end
        return originalGetRating(self, size)
    end
    local function perfectThrow(self, target, ballId)
        local result = originalDoThrow(self, target, ballId)
        if state.perfectBall and result and result.ball then
            result.success = true
            result.missed = false
            result.dodged = false
            result.deflected = false
            result.hit = true
            result.rating = originalGetRating(self, 0)
            result.bonus = 0.6
        end
        return result
    end
    throwSystem.getRating = perfectRating
    throwSystem.doThrow = perfectThrow
    state.restorePerfect = function()
        if throwSystem.getRating == perfectRating then
            throwSystem.getRating = originalGetRating
        end
        if throwSystem.doThrow == perfectThrow then
            throwSystem.doThrow = originalDoThrow
        end
    end
end

local function movementActive(toggleId, keyId)
    local picker = Options[keyId]
    return Toggles[toggleId].Value and (picker.Value == "None" or picker:GetState())
end

MovementGroup:AddToggle("TungNoclip", {Text = "Noclip", Default = false})
    :AddKeyPicker("TungNoclipKey", {
        Default = "None", Text = "Noclip"
    })
MovementGroup:AddToggle("TungHipEnabled", {Text = "HipHeight", Default = false})
    :AddKeyPicker("TungHipKey", {
        Default = "None", Text = "HipHeight"
    })
MovementGroup:AddSlider("TungHipHeight", {
    Text = "HipHeight", Default = state.desiredHip, Min = 0, Max = 50, Rounding = 2
})
Options.TungHipHeight:OnChanged(function()
    state.desiredHip = Options.TungHipHeight.Value
end)
MovementGroup:AddToggle("TungSpeedEnabled", {Text = "Speed", Default = false})
    :AddKeyPicker("TungSpeedKey", {
        Default = "None", Text = "Speed"
    })
MovementGroup:AddSlider("TungSpeed", {
    Text = "Speed", Default = state.desiredSpeed, Min = 0, Max = 200, Rounding = 0
})
Options.TungSpeed:OnChanged(function()
    state.desiredSpeed = Options.TungSpeed.Value
end)
EncounterGroup:AddToggle("TungPerfectBall", {
    Text = "Perfect pokeball", Default = false,
    Tooltip = "Applies the maximum 0.60 throw bonus to normal ball throws."
})
Toggles.TungPerfectBall:OnChanged(function()
    state.perfectBall = Toggles.TungPerfectBall.Value
end)
EncounterGroup:AddToggle("RoriaNotifyOnEncounter", {
    Text = "Notify on encounter", Default = false,
    Tooltip = "Show a Linoria notification with the Pokémon's encounter chance."
})
Toggles.RoriaNotifyOnEncounter:OnChanged(function()
    state.notifyOnEncounter = Toggles.RoriaNotifyOnEncounter.Value
end)

local npcEspObjects = {}
local playerEspObjects = {}
state.espDrawings = npcEspObjects
state.playerEspDrawings = playerEspObjects
state.espFadeStart = 100
state.espFadeWidth = 50
state.playerEspFadeStart = 100
state.playerEspFadeWidth = 50
local function removeNpcDrawing(model)
    local objects = npcEspObjects[model]
    if not objects then return end
    for _, drawing in objects do
        pcall(function() drawing:Remove() end)
    end
    npcEspObjects[model] = nil
end
local function restoreEsp()
    for model in npcEspObjects do
        removeNpcDrawing(model)
    end
end
local function removePlayerDrawing(model)
    local objects = playerEspObjects[model]
    if not objects then return end
    for _, drawing in objects do
        pcall(function() drawing:Remove() end)
    end
    playerEspObjects[model] = nil
end
local function restorePlayerEsp()
    for model in playerEspObjects do
        removePlayerDrawing(model)
    end
end
state.restoreEsp = function()
    restoreEsp()
    restorePlayerEsp()
end

local vertices = {
    Vector3.new(1, 1, 1),
    Vector3.new(-1, 1, 1),
    Vector3.new(1, -1, 1),
    Vector3.new(1, 1, -1),
    Vector3.new(-1, -1, 1),
    Vector3.new(-1, 1, -1),
    Vector3.new(1, -1, -1),
    Vector3.new(-1, -1, -1)
}

local function getCorners(size)
    local half = size / 2
    local corners = {}
    for i, factor in vertices do
        corners[i] = half * factor
    end
    return corners
end

local function createEspDrawing(model, registry)
    local objects = {}
    for i = 1, 8 do
        local shadow = Drawing.new("Line")
        shadow.Color = Color3.new(0, 0, 0)
        shadow.Thickness = 1
        shadow.Visible = false
        objects[14 + i] = shadow
    end
    for i = 1, 8 do
        local line = Drawing.new("Line")
        line.Thickness = 1
        line.Visible = false
        objects[i] = line
    end
    for i = 9, 14 do
        local label = Drawing.new("Text")
        label.Color = i % 2 == 1 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
        label.Font = Drawing.Fonts.Plex
        label.Size = 13
        label.Center = i ~= 13 and i ~= 14
        label.Outline = false
        label.Visible = false
        objects[i] = label
    end
    registry[model] = objects
    return objects
end

local function setCornerLine(line, x1, y1, x2, y2)
    line.From = Vector2.new(x1, y1) // 1
    line.To = Vector2.new(x2, y2) // 1
end

local function setEspText(objects, shadowIndex, value, position, color, visible, opacity,
    shadowOffset, shadowOpacity)
    local shadow = objects[shadowIndex]
    local label = objects[shadowIndex + 1]
    local offset = shadowOffset or Options.RoriaNpcEspShadowOffset.Value
    shadow.Text = value
    shadow.Position = (position + Vector2.new(offset, offset)) // 1
    shadow.Transparency = opacity * (shadowOpacity or Options.RoriaNpcEspShadowOpacity.Value)
    shadow.Visible = visible
    label.Text = value
    label.Position = position // 1
    label.Color = color
    label.Transparency = opacity
    label.Visible = visible
end

local function hasTrainerMarker(model)
    local head = model:FindFirstChild("Head")
    local marker = head and head:FindFirstChild("BillboardGui")
    if not marker or not marker:IsA("BillboardGui") or not marker.Enabled then
        return false
    end
    for _, child in marker:GetDescendants() do
        if child:IsA("ImageLabel") and child.Visible
            and child.Image == "rbxassetid://121875200442778" then
            return true
        end
    end
    return false
end

EspGroup:AddToggle("RoriaNpcEsp", {
    Text = "Enabled", Default = false,
    Tooltip = "Show NPC ESP in the current map."
})
Toggles.RoriaNpcEsp:OnChanged(function()
    state.npcEspEnabled = Toggles.RoriaNpcEsp.Value
    if not state.npcEspEnabled then restoreEsp() end
end)
EspGroup:AddToggle("RoriaNpcEspBoxes", {Text = "Boxes", Default = true})
    :AddColorPicker("RoriaNpcEspBoxColor", {
        Default = Color3.fromRGB(255, 220, 90), Title = "Box Color"
    })
EspGroup:AddToggle("RoriaNpcEspNames", {Text = "Names", Default = true})
    :AddColorPicker("RoriaNpcEspNameColor", {
        Default = Color3.fromRGB(255, 245, 180), Title = "Name Color"
    })
EspGroup:AddToggle("RoriaNpcEspDistance", {Text = "Distance", Default = false})
    :AddColorPicker("RoriaNpcEspDistanceColor", {
        Default = Color3.fromRGB(255, 245, 180), Title = "Distance Color"
    })
EspGroup:AddDropdown("RoriaNpcEspFlags", {
    Values = {"Trainer"}, Default = 1, Multi = true, Text = "Flags"
})
EspGroup:AddLabel("Flag Color"):AddColorPicker("RoriaNpcEspFlagColor", {
    Default = Color3.fromRGB(100, 255, 100), Title = "Flag Color"
})
EspGroup:AddSlider("RoriaNpcEspShadowOffset", {
    Text = "Shadow Offset", Default = 2, Min = 0, Max = 10, Rounding = 0
})
EspGroup:AddSlider("RoriaNpcEspShadowOpacity", {
    Text = "Shadow Opacity", Default = 0.5, Min = 0, Max = 1, Rounding = 2
})
EspGroup:AddSlider("RoriaNpcEspFadeStart", {
    Text = "Fade Distance", Default = state.espFadeStart, Min = 0, Max = 1000, Rounding = 0,
    Tooltip = "Distance in studs before NPC ESP begins to fade."
})
Options.RoriaNpcEspFadeStart:OnChanged(function()
    state.espFadeStart = Options.RoriaNpcEspFadeStart.Value
end)
EspGroup:AddSlider("RoriaNpcEspFadeWidth", {
    Text = "Fade Width", Default = state.espFadeWidth, Min = 1, Max = 500, Rounding = 0,
    Tooltip = "Distance in studs over which NPC ESP fades to invisible."
})
Options.RoriaNpcEspFadeWidth:OnChanged(function()
    state.espFadeWidth = Options.RoriaNpcEspFadeWidth.Value
end)

PlayerEspGroup:AddToggle("RoriaPlayerEsp", {
    Text = "Enabled", Default = false,
    Tooltip = "Show ESP for other players."
})
Toggles.RoriaPlayerEsp:OnChanged(function()
    state.playerEspEnabled = Toggles.RoriaPlayerEsp.Value
    if not state.playerEspEnabled then restorePlayerEsp() end
end)
PlayerEspGroup:AddToggle("RoriaPlayerEspBoxes", {Text = "Boxes", Default = true})
    :AddColorPicker("RoriaPlayerEspBoxColor", {
        Default = Color3.fromRGB(255, 220, 90), Title = "Player Box Color"
    })
PlayerEspGroup:AddToggle("RoriaPlayerEspNames", {Text = "Names", Default = true})
    :AddColorPicker("RoriaPlayerEspNameColor", {
        Default = Color3.fromRGB(255, 245, 180), Title = "Player Name Color"
    })
PlayerEspGroup:AddToggle("RoriaPlayerEspDistance", {Text = "Distance", Default = false})
    :AddColorPicker("RoriaPlayerEspDistanceColor", {
        Default = Color3.fromRGB(255, 245, 180), Title = "Player Distance Color"
    })
PlayerEspGroup:AddSlider("RoriaPlayerEspShadowOffset", {
    Text = "Shadow Offset", Default = 2, Min = 0, Max = 10, Rounding = 0
})
PlayerEspGroup:AddSlider("RoriaPlayerEspShadowOpacity", {
    Text = "Shadow Opacity", Default = 0.5, Min = 0, Max = 1, Rounding = 2
})
PlayerEspGroup:AddSlider("RoriaPlayerEspFadeStart", {
    Text = "Fade Distance", Default = state.playerEspFadeStart,
    Min = 0, Max = 1000, Rounding = 0
})
Options.RoriaPlayerEspFadeStart:OnChanged(function()
    state.playerEspFadeStart = Options.RoriaPlayerEspFadeStart.Value
end)
PlayerEspGroup:AddSlider("RoriaPlayerEspFadeWidth", {
    Text = "Fade Width", Default = state.playerEspFadeWidth,
    Min = 1, Max = 500, Rounding = 0
})
Options.RoriaPlayerEspFadeWidth:OnChanged(function()
    state.playerEspFadeWidth = Options.RoriaPlayerEspFadeWidth.Value
end)

Library:GiveSignal(game:GetService("RunService").RenderStepped:Connect(function()
    if not state.npcEspEnabled then return end
    local chunk = p.DataManager.currentChunk
    local npcs = chunk and chunk.npcs
    local camera = workspace.CurrentCamera
    if not npcs or not camera then
        restoreEsp()
        return
    end
    local seen = {}
    for _, npc in npcs do
        local model = npc and npc.model
        local root = model and (model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart or model:FindFirstChild("Head"))
        if model and model.Parent and root then
            seen[model] = true
            local objects = npcEspObjects[model] or createEspDrawing(model, npcEspObjects)
            local center, onScreen = camera:WorldToViewportPoint(root.Position)
            local distance = (camera.CFrame.Position - root.Position).Magnitude
            local range = state.espFadeStart + state.espFadeWidth
            local opacity = math.clamp((range - distance) / state.espFadeWidth, 0, 1)
            local visible = onScreen and center.Z > 0 and opacity > 0
            local minX, minY = math.huge, math.huge
            local maxX, maxY = -math.huge, -math.huge
            if visible then
                local projected = false
                for _, part in model:GetChildren() do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        local size = part.Name == "Head" and Vector3.new(1.2, 1.2, 1.2)
                            or part.Size
                        for _, corner in getCorners(size) do
                            local worldPoint = part.CFrame:PointToWorldSpace(corner)
                            local screen = camera:WorldToViewportPoint(worldPoint)
                            if screen.Z > 0 then
                                projected = true
                                minX = math.min(minX, screen.X)
                                minY = math.min(minY, screen.Y)
                                maxX = math.max(maxX, screen.X)
                                maxY = math.max(maxY, screen.Y)
                            end
                        end
                    end
                end
                visible = projected
            end
            if visible and maxX - minX >= 2 and maxY - minY >= 2 then
                local length = math.clamp(math.min(maxX - minX, maxY - minY) * 0.22, 4, 14)
                setCornerLine(objects[1], minX, minY, minX + length, minY)
                setCornerLine(objects[2], minX, minY, minX, minY + length)
                setCornerLine(objects[3], maxX, minY, maxX - length, minY)
                setCornerLine(objects[4], maxX, minY, maxX, minY + length)
                setCornerLine(objects[5], minX, maxY, minX + length, maxY)
                setCornerLine(objects[6], minX, maxY, minX, maxY - length)
                setCornerLine(objects[7], maxX - length, maxY, maxX + 1, maxY)
                setCornerLine(objects[8], maxX, maxY - length, maxX, maxY + 1)
                for i = 1, 8 do
                    local line = objects[i]
                    local shadow = objects[14 + i]
                    local offset = Options.RoriaNpcEspShadowOffset.Value
                    local shift = Vector2.new(offset, offset)
                    shadow.From = line.From + shift
                    shadow.To = line.To + shift
                    shadow.Transparency = opacity * Options.RoriaNpcEspShadowOpacity.Value
                    shadow.Visible = Toggles.RoriaNpcEspBoxes.Value
                    line.Color = Options.RoriaNpcEspBoxColor.Value
                    line.Transparency = opacity
                    line.Visible = Toggles.RoriaNpcEspBoxes.Value
                end
                local middle = (minX + maxX) * 0.5
                setEspText(objects, 9, model.Name, Vector2.new(middle, minY - 16),
                    Options.RoriaNpcEspNameColor.Value,
                    Toggles.RoriaNpcEspNames.Value, opacity)
                setEspText(objects, 11, string.format("%d studs", math.floor(distance + 0.5)),
                    Vector2.new(middle, maxY + 2), Options.RoriaNpcEspDistanceColor.Value,
                    Toggles.RoriaNpcEspDistance.Value, opacity)
                local showTrainer = Options.RoriaNpcEspFlags.Value.Trainer
                    and hasTrainerMarker(model)
                setEspText(objects, 13, "BP", Vector2.new(maxX + 5, minY - 1),
                    Options.RoriaNpcEspFlagColor.Value, showTrainer, opacity)
            end
            if not visible or maxX - minX < 2 or maxY - minY < 2 then
                for _, drawing in objects do drawing.Visible = false end
            end
        end
    end
    for model in npcEspObjects do
        if not seen[model] then removeNpcDrawing(model) end
    end
end))

Library:GiveSignal(game:GetService("RunService").RenderStepped:Connect(function()
    if not state.playerEspEnabled then return end
    local camera = workspace.CurrentCamera
    if not camera then
        restorePlayerEsp()
        return
    end
    local seen = {}
    for _, other in game:GetService("Players"):GetPlayers() do
        if other ~= player then
            local model = other.Character
            local humanoid = model and model:FindFirstChildOfClass("Humanoid")
            local root = model and (model:FindFirstChild("HumanoidRootPart")
                or model.PrimaryPart or model:FindFirstChild("Head"))
            if model and model.Parent and root and humanoid and humanoid.Health > 0 then
                seen[model] = true
                local objects = playerEspObjects[model]
                    or createEspDrawing(model, playerEspObjects)
                local center, onScreen = camera:WorldToViewportPoint(root.Position)
                local distance = (camera.CFrame.Position - root.Position).Magnitude
                local range = state.playerEspFadeStart + state.playerEspFadeWidth
                local opacity = math.clamp((range - distance) / state.playerEspFadeWidth, 0, 1)
                local visible = onScreen and center.Z > 0 and opacity > 0
                local minX, minY = math.huge, math.huge
                local maxX, maxY = -math.huge, -math.huge
                if visible then
                    local projected = false
                    for _, part in model:GetChildren() do
                        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                            local size = part.Name == "Head" and Vector3.new(1.2, 1.2, 1.2)
                                or part.Size
                            for _, corner in getCorners(size) do
                                local screen = camera:WorldToViewportPoint(
                                    part.CFrame:PointToWorldSpace(corner))
                                if screen.Z > 0 then
                                    projected = true
                                    minX = math.min(minX, screen.X)
                                    minY = math.min(minY, screen.Y)
                                    maxX = math.max(maxX, screen.X)
                                    maxY = math.max(maxY, screen.Y)
                                end
                            end
                        end
                    end
                    visible = projected
                end
                if visible and maxX - minX >= 2 and maxY - minY >= 2 then
                    local length = math.clamp(math.min(maxX - minX, maxY - minY) * 0.22, 4, 14)
                    setCornerLine(objects[1], minX, minY, minX + length, minY)
                    setCornerLine(objects[2], minX, minY, minX, minY + length)
                    setCornerLine(objects[3], maxX, minY, maxX - length, minY)
                    setCornerLine(objects[4], maxX, minY, maxX, minY + length)
                    setCornerLine(objects[5], minX, maxY, minX + length, maxY)
                    setCornerLine(objects[6], minX, maxY, minX, maxY - length)
                    setCornerLine(objects[7], maxX - length, maxY, maxX + 1, maxY)
                    setCornerLine(objects[8], maxX, maxY - length, maxX, maxY + 1)
                    local offset = Options.RoriaPlayerEspShadowOffset.Value
                    local shift = Vector2.new(offset, offset)
                    local showBox = Toggles.RoriaPlayerEspBoxes.Value
                    for i = 1, 8 do
                        local line = objects[i]
                        local shadow = objects[14 + i]
                        shadow.From = line.From + shift
                        shadow.To = line.To + shift
                        shadow.Transparency = opacity
                            * Options.RoriaPlayerEspShadowOpacity.Value
                        shadow.Visible = showBox
                        line.Color = Options.RoriaPlayerEspBoxColor.Value
                        line.Transparency = opacity
                        line.Visible = showBox
                    end
                    local middle = (minX + maxX) * 0.5
                    local shadowOpacity = Options.RoriaPlayerEspShadowOpacity.Value
                    setEspText(objects, 9, other.Name, Vector2.new(middle, minY - 16),
                        Options.RoriaPlayerEspNameColor.Value,
                        Toggles.RoriaPlayerEspNames.Value, opacity, offset, shadowOpacity)
                    setEspText(objects, 11,
                        string.format("%d studs", math.floor(distance + 0.5)),
                        Vector2.new(middle, maxY + 2),
                        Options.RoriaPlayerEspDistanceColor.Value,
                        Toggles.RoriaPlayerEspDistance.Value, opacity, offset, shadowOpacity)
                end
                if not visible or maxX - minX < 2 or maxY - minY < 2 then
                    for _, drawing in objects do drawing.Visible = false end
                end
            end
        end
    end
    for model in playerEspObjects do
        if not seen[model] then removePlayerDrawing(model) end
    end
end))

Library:GiveSignal(game:GetService("RunService").Heartbeat:Connect(function()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if not originalHumanoids[humanoid] then
        originalHumanoids[humanoid] = {hip = humanoid.HipHeight}
    end
    local activeHip = movementActive("TungHipEnabled", "TungHipKey")
    if state.hipEnabled and not activeHip then
        for oldHumanoid, values in originalHumanoids do
            if oldHumanoid.Parent then oldHumanoid.HipHeight = values.hip end
        end
    end
    state.hipEnabled = activeHip
    state.speedEnabled = movementActive("TungSpeedEnabled", "TungSpeedKey")
    local activeNoclip = movementActive("TungNoclip", "TungNoclipKey")
    if state.noclip and not activeNoclip then restoreCollisions() end
    state.noclip = activeNoclip
    if state.hipEnabled and humanoid.HipHeight ~= state.desiredHip then
        humanoid.HipHeight = state.desiredHip
    end
    if state.speedEnabled and p.MasterControl.WalkEnabled
        and not state.running and not state.ballRunning and not p.Battle.currentBattle then
        local root = character:FindFirstChild("HumanoidRootPart")
        if root then
            local direction = humanoid.MoveDirection
            local velocity = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(
                direction.X * state.desiredSpeed,
                velocity.Y,
                direction.Z * state.desiredSpeed
            )
        end
    end
    if state.noclip then
        for _, part in character:QueryDescendants("BasePart") do
            if originalCollisions[part] == nil then
                originalCollisions[part] = part.CanCollide
            end
            if part.CanCollide then part.CanCollide = false end
        end
    end
end))

local function uiChange(callback)
    local oldIdentity = getthreadidentity()
    setthreadidentity(8)
    local ok, err = pcall(callback)
    setthreadidentity(oldIdentity)
    if not ok then warn("[RoriaFarm] UI error: " .. tostring(err)) end
end

local function setStatus(message)
    uiChange(function() statusLabel:SetText(message) end)
    warn("[RoriaFarm] " .. message)
end

local function setBallStatus(message)
    if state.ballStatus == message then return end
    state.ballStatus = message
    uiChange(function() ballStatusLabel:SetText(message) end)
    warn("[RoriaBalls] " .. message)
end

local function setHealStatus(message)
    if state.healStatus == message then return end
    state.healStatus = message
    uiChange(function() healStatusLabel:SetText(message) end)
end

local function setWebhookStatus(message)
    if state.webhookStatus == message then return end
    state.webhookStatus = message
    uiChange(function() webhookStatusLabel:SetText(message) end)
end

local function webhookPayload(event)
    local kind = event.kind or "encounter"
    local title = "🌿 Wild encounter"
    local color = 0x3498DB
    local description = "A wild Pokémon appeared."
    if kind == "shiny" then
        title = "✨ Shiny found!"
        color = 0xF1C40F
        description = "A shiny Pokémon appeared in the wild."
    elseif kind == "target" then
        title = "🎯 Target found!"
        color = 0x2ECC71
        description = "The encounter farm found its selected Pokémon."
    elseif kind == "test" then
        title = "🔔 Webhook test"
        color = 0x9B59B6
        description = "ArtificalCheat encounter alerts are ready."
    end
    local chance = "Unknown"
    if type(event.chance) == "number" and event.chance > 0 then
        chance = string.format("%.2f%%", event.chance)
        local odds = math.floor(100 / event.chance + 0.5)
        chance ..= string.format(" (about 1 in %d)", odds)
    end
    local fields = {
        {name = "Pokémon", value = event.species or "Test alert", inline = true},
        {name = "Encounter chance", value = chance, inline = true},
        {name = "Area", value = event.region or "Unknown", inline = true},
        {name = "Method", value = event.method or "—", inline = true},
        {name = "Encounter #", value = tostring(event.attempts or "—"), inline = true},
        {name = "Target", value = event.target or "None", inline = true}
    }
    if event.matchReason then
        fields[#fields + 1] = {name = "Matched by", value = event.matchReason, inline = true}
    end
    return {
        embeds = {{
            title = title,
            description = description,
            color = color,
            fields = fields,
            footer = {text = "ArtificalCheat • Encounter Farm"},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }},
        allowed_mentions = {parse = {}}
    }
end
state.webhookPayload = webhookPayload

local function sendWebhook(event, force)
    if not force and not state.webhookEnabled then return end
    local url = string.match(state.webhookUrl, "^%s*(.-)%s*$")
    if not string.match(url, "^https://") then
        setWebhookStatus("Enter an HTTPS webhook URL")
        return
    end
    local sendRequest = request or http_request or (syn and syn.request)
        or (http and http.request)
    if type(sendRequest) ~= "function" then
        setWebhookStatus("Executor HTTP request unavailable")
        return
    end
    local body = game:GetService("HttpService"):JSONEncode(webhookPayload(event))
    task.spawn(function()
        setthreadidentity(8)
        if env.RoriaEncounterFarm ~= state then return end
        local ok, response = pcall(sendRequest, {
            Url = url,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = body
        })
        local code = ok and response and tonumber(response.StatusCode or response.Status)
        if not ok or not response or response.Success == false
            or (code and (code < 200 or code >= 300)) then
            setWebhookStatus("Webhook send failed")
        else
            setWebhookStatus("Last alert sent")
        end
    end)
end
state.sendWebhook = sendWebhook

local function stop(message)
    state.running = false
    if Toggles.RoriaAutoFarm and Toggles.RoriaAutoFarm.Value then
        uiChange(function() Toggles.RoriaAutoFarm:SetValue(false) end)
    end
    if message then setStatus(message) end
end

Library:OnUnload(function()
    state.running = false
    state.ballRunning = false
    state.restoreMovement()
    state.restoreEsp()
    if state.restorePerfect then state.restorePerfect() end
    if env.RoriaEncounterFarm == state then env.RoriaEncounterFarm = nil end
end)

FarmGroup:AddDropdown("RoriaTarget", {
    Values = {"None"},
    Default = 1,
    Multi = true,
    Text = "Pokémon (regional chance)",
    Tooltip = "Select multiple Pokémon. Their encounter methods are rotated. None encounters and runs."
})
Options.RoriaTarget:OnChanged(function()
    local selected = Options.RoriaTarget.Value
    local hasPokemon = false
    for display, enabled in selected do
        if enabled and display ~= "None" then hasPokemon = true end
    end
    if selected.None and hasPokemon then
        local useNone = not state.noneWasSelected
        local normalized = {None = useNone or nil}
        if not useNone then
            for display, enabled in selected do
                if display ~= "None" and enabled then normalized[display] = true end
            end
        end
        Options.RoriaTarget:SetValue(normalized)
        return
    end
    if not selected.None and not hasPokemon then
        Options.RoriaTarget:SetValue({None = true})
        return
    end
    state.noneWasSelected = selected.None == true
    state.selectedKeys = {}
    state.encounterChoices = {}
    local methodsAdded = {}
    local names = {}
    for _, entry in state.entries do
        if selected[entry.display] then
            state.selectedKeys[entry.method .. "|" .. string.lower(entry.species)] = true
            names[#names + 1] = entry.species
            if not methodsAdded[entry.method] then
                methodsAdded[entry.method] = true
                state.encounterChoices[#state.encounterChoices + 1] = {
                    method = entry.method, encounter = entry.encounter
                }
            end
        end
    end
    state.targetLabel = #names == 0 and "None" or
        (#names == 1 and names[1] or tostring(#names) .. " Pokémon")
    if #names == 0 then
        setStatus("None selected: encounter and run continuously")
    else
        setStatus("Selected " .. state.targetLabel)
    end
end)

FarmGroup:AddToggle("RoriaCatchOnFind", {
    Text = "Catch on find",
    Default = false,
    Tooltip = "Throw Poké Balls with the maximum timing bonus when the target appears."
})
Toggles.RoriaCatchOnFind:OnChanged(function()
    state.catchOnFind = Toggles.RoriaCatchOnFind.Value
end)
WebhookGroup:AddInput("RoriaWebhookUrl", {
    Text = "Webhook URL", Default = "", Finished = false,
    Placeholder = "https://discord.com/api/webhooks/..."
})
Options.RoriaWebhookUrl:OnChanged(function()
    state.webhookUrl = Options.RoriaWebhookUrl.Value
end)
WebhookGroup:AddToggle("RoriaWebhookEnabled", {
    Text = "Webhook alerts", Default = false
})
Toggles.RoriaWebhookEnabled:OnChanged(function()
    state.webhookEnabled = Toggles.RoriaWebhookEnabled.Value
    setWebhookStatus(state.webhookEnabled and "Ready" or "Disabled")
end)
WebhookGroup:AddToggle("RoriaWebhookEveryEncounter", {
    Text = "Alert every encounter", Default = false
})
Toggles.RoriaWebhookEveryEncounter:OnChanged(function()
    state.webhookEveryEncounter = Toggles.RoriaWebhookEveryEncounter.Value
end)
WebhookGroup:AddButton("Send test alert", function()
    sendWebhook({kind = "test", region = state.region}, true)
end)

local methods = {
    "Grass", "Surf", "OldRod", "GoodRod", "SuperRod",
    "PalmTree", "PineTree", "MiscEncounter", "InsideEnc"
}

local function refresh()
    if state.running then
        setStatus("Stop the farm before refreshing")
        return
    end
    local chunk = p.DataManager.currentChunk
    local region = chunk and chunk.currentRegion and chunk.currentRegion.Name
    local regionData = chunk and chunk.regionData
    if not regionData then
        setStatus("No region data here")
        return
    end
    local data = p.Network:get("PDS", "getChunkData")
    if not data or not data.encounterLists then
        setStatus("Pokédex encounter data unavailable")
        return
    end
    local previous = Options.RoriaTarget.Value
    state.entries = {}
    state.byDisplay = {}
    state.chancesByMethod = {}
    state.chancesBySpecies = {}
    state.selectedKeys = {}
    state.encounterChoices = {}
    state.noneEncounter = nil
    state.noneMethod = nil
    state.chunk = chunk
    state.region = region
    local byKey = {}
    for _, method in methods do
        local encounter = regionData[method]
        local info = encounter and data.encounterLists[encounter.id]
        if info and info.list then
            if not state.noneEncounter or method == "Grass" then
                state.noneEncounter = encounter
                state.noneMethod = method
            end
            local totalWeight = 0
            for _, row in info.list do
                if type(row[4]) == "number" and row[4] > 0 then
                    totalWeight += row[4]
                end
            end
            for _, row in info.list do
                local species = row[1]
                local weight = row[4]
                if type(species) == "string" and type(weight) == "number"
                    and weight > 0 and totalWeight > 0 then
                    local key = species .. "|" .. method
                    local entry = byKey[key]
                    if not entry then
                        entry = {
                            species = species,
                            method = method,
                            encounter = encounter,
                            weight = 0,
                            totalWeight = totalWeight
                        }
                        byKey[key] = entry
                        state.entries[#state.entries + 1] = entry
                    end
                    entry.weight += weight
                end
            end
        end
    end
    for _, entry in state.entries do
        entry.chance = entry.weight / entry.totalWeight * 100
        entry.display = string.format("%s — %s (%.2f%%)", entry.species, entry.method, entry.chance)
        state.byDisplay[entry.display] = entry
        state.chancesByMethod[entry.method .. "|" .. string.lower(entry.species)] = entry.chance
        local speciesKey = string.lower(entry.species)
        local knownChance = state.chancesBySpecies[speciesKey]
        if knownChance == nil then
            state.chancesBySpecies[speciesKey] = entry.chance
        elseif knownChance ~= false and math.abs(knownChance - entry.chance) > 0.0001 then
            state.chancesBySpecies[speciesKey] = false
        end
    end
    table.sort(state.entries, function(a, b) return a.display < b.display end)
    local values = {"None"}
    for _, entry in state.entries do
        values[#values + 1] = entry.display
    end
    uiChange(function()
        Options.RoriaTarget:SetValues(values)
        local valid = {}
        for display, enabled in previous do
            if enabled and state.byDisplay[display] then valid[display] = true end
        end
        local hasValid = false
        for _, enabled in valid do
            if enabled then hasValid = true end
        end
        if not hasValid then valid.None = true end
        Options.RoriaTarget:SetValue(valid)
        regionLabel:SetText((region or regionData.Name or chunk.id) ..
            " · " .. #state.entries .. " choices")
    end)
    setStatus(state.noneEncounter and "Ready" or "No supported wild encounters")
end
state.refresh = refresh

local function getBallCount()
    local item = p.Network:get("PDS", "getBagDataById", "pokeball", 3)
    return item and tonumber(item.quantity) or 0
end

local function autoCatch(battle, species, chanceText)
    local throws = 0
    local lastRequestId
    setStatus("Found " .. species .. chanceText .. "; catching...")
    while state.running and p.Battle.currentBattle == battle do
        local request = battle.fulfillingRequest
        if request and request.requestType == "move"
            and battle.readyForInputFlag and request.rqid ~= lastRequestId then
            local count = getBallCount()
            if count <= 0 then
                stop("Out of Poké Balls; battle left open")
                return
            end
            lastRequestId = request.rqid
            throws += 1
            setStatus("Perfect Poké Ball throw " .. throws .. " · " .. count ..
                " left · " .. species .. chanceText)
            local accepted = false
            for attempt = 1, 4 do
                if not state.running or p.Battle.currentBattle ~= battle then break end
                local bonus = state.perfectBall and "0.6" or "0.5"
                battle.InputChosen:fire("useitem pokeball|" .. bonus .. "|false|false|false")
                task.wait(0.5)
                if battle.fulfillingRequest ~= request or getBallCount() < count then
                    accepted = true
                    break
                end
            end
            if state.running and p.Battle.currentBattle == battle and not accepted then
                stop("Throw was not accepted; battle left open")
                return
            end
        end
        task.wait(0.2)
    end
    if state.running then stop("Battle ended after " .. throws .. " throw(s)") end
end

local function farm()
    setthreadidentity(2)
    local chunk = state.chunk
    local region = state.region
    local attempts = 0
    while state.running do
        local current = p.DataManager.currentChunk
        if current ~= chunk or (current.currentRegion and current.currentRegion.Name) ~= region then
            stop("Region changed; refresh the list")
            break
        end
        if p.Battle.currentBattle then
            stop("Another battle is already active")
            break
        end
        if not p.MasterControl.WalkEnabled or p.MasterControl.PreventWalk then
            task.wait(0.4)
            continue
        end
        attempts += 1
        local choices = state.encounterChoices
        local choice = #choices > 0 and choices[((attempts - 1) % #choices) + 1]
        local encounter = choice and choice.encounter or state.noneEncounter
        local method = choice and choice.method or state.noneMethod
        state.pendingEncounterMethod = method
        setStatus("Encounter " .. attempts .. ": starting...")
        task.spawn(function()
            setthreadidentity(2)
            local ok, err = pcall(function()
                p.Battle:doWildBattle(encounter, {skipCoopWild = true})
            end)
            if not ok and state.running then stop("Encounter error: " .. tostring(err)) end
        end)
        local deadline = os.clock() + 25
        while state.running and not p.Battle.currentBattle and os.clock() < deadline do
            task.wait(0.05)
        end
        local battle = p.Battle.currentBattle
        if not state.running then break end
        if not battle then
            stop("Encounter did not start")
            break
        end
        local foe
        local shiny = false
        deadline = os.clock() + 20
        while state.running and p.Battle.currentBattle == battle and not foe and os.clock() < deadline do
            local readOk, found, foundShiny = pcall(function()
                local active = battle.p2 and battle.p2.active and battle.p2.active[1]
                return active and active.species, active and active.shiny
            end)
            if readOk then
                foe = found
                shiny = foundShiny == true
            end
            if not foe then task.wait(0.05) end
        end
        if not state.running then break end
        if not foe then
            stop("Could not read wild Pokémon")
            break
        end
        local chance = state.chancesByMethod[method .. "|" .. string.lower(foe)]
        local chanceText = chance and string.format(" (%.2f%%)", chance) or " (chance unknown)"
        setStatus("Encounter " .. attempts .. ": " .. foe .. chanceText)
        local targetFound = state.selectedKeys[method .. "|" .. string.lower(foe)] == true
        local shinyMatch = shiny and state.stopOnShiny
        local chanceMatch = state.chanceThreshold > 0 and chance ~= nil
            and chance <= state.chanceThreshold
        local matched = targetFound or shinyMatch or chanceMatch
        local matchReason = targetFound and "Selected Pokémon"
            or shinyMatch and "Shiny"
            or chanceMatch and "Chance threshold"
        local place = region or "Unknown region"
        local alert = {
            species = foe,
            chance = chance,
            region = place,
            method = method,
            attempts = attempts,
            target = state.targetLabel,
            matchReason = matchReason
        }
        if shiny then
            alert.kind = "shiny"
            sendWebhook(alert)
        elseif matched then
            alert.kind = "target"
            sendWebhook(alert)
        elseif state.webhookEveryEncounter then
            alert.kind = "encounter"
            sendWebhook(alert)
        end
        if matched then
            if state.catchOnFind then
                autoCatch(battle, foe, chanceText)
            else
                stop("Found " .. foe .. chanceText .. " on encounter " .. attempts ..
                    "! Matched: " .. matchReason)
            end
            break
        end
        setStatus("Found " .. foe .. chanceText .. "; running...")
        if battle.kind ~= "wild" or battle.cantRun or battle.noRunAfterFaint then
            stop("Cannot run from this battle")
            break
        end
        local ok, result = pcall(function()
            return p.Network:get("BattleFunction", battle.battleId, "tryRun")
        end)
        if not ok or result ~= true then
            stop("Run failed; handle this battle manually")
            break
        end
        battle.pickup = false
        battle.ended = true
        battle.BattleEnded:fire()
        deadline = os.clock() + 20
        while state.running and p.Battle.currentBattle and os.clock() < deadline do
            task.wait(0.05)
        end
        if p.Battle.currentBattle then
            stop("Battle did not close")
            break
        end
        task.wait(1)
    end
end

local function start()
    if state.running then return end
    if state.ballRunning then
        stop("Stop the Poké Ball farm first")
        return
    end
    if not state.noneEncounter then
        setStatus("Refresh in a wild-encounter region")
        return
    end
    if p.Battle.currentBattle then
        setStatus("Finish the current battle first")
        return
    end
    state.running = true
    task.spawn(function()
        local ok, err = pcall(farm)
        if not ok then stop("Farm error: " .. tostring(err)) end
    end)
end
state.start = start
state.stop = stop

local function stopBallFarm(message)
    state.ballRunning = false
    if Toggles.RoriaBallFarm and Toggles.RoriaBallFarm.Value then
        uiChange(function() Toggles.RoriaBallFarm:SetValue(false) end)
    end
    if message then setBallStatus(message) end
end

local function nearestBall(map, root, tried)
    local chosen
    local chosenTop
    local distance = math.huge
    for _, model in map:QueryDescendants("Model") do
        if (model.Name == "#Item" or model.Name == "#Item2")
            and (not tried[model] or tried[model] < os.clock()) then
            local top = model:FindFirstChild("Top")
            local itemId = model:FindFirstChild("ItemId")
            if top and top:IsA("BasePart") and itemId then
                local d = (root.Position - top.Position).Magnitude
                if d < distance then
                    chosen, chosenTop, distance = model, top, d
                end
            end
        end
    end
    return chosen, chosenTop
end

local function ballFarm()
    setthreadidentity(8)
    local player = game:GetService("Players").LocalPlayer
    local input = game:GetService("VirtualInputManager")
    local tried = {}
    local previousMap
    local collected = 0
    while state.ballRunning do
        if p.Battle.currentBattle then
            task.wait(0.5)
            continue
        end
        local chunk = p.DataManager.currentChunk
        local map = chunk and chunk.map
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not map or not root or not p.MasterControl.WalkEnabled then
            task.wait(0.5)
            continue
        end
        if map ~= previousMap then
            tried = {}
            previousMap = map
        end
        local model, top = nearestBall(map, root, tried)
        if not model then
            setBallStatus("Waiting for map pickups · " .. collected .. " collected")
            task.wait(3)
            continue
        end
        tried[model] = os.clock() + 15
        setBallStatus("Going to pickup · " .. collected .. " collected")
        local oldCFrame = root.CFrame
        root.CFrame = CFrame.new(top.Position + Vector3.new(0, 3, 0))
        task.wait(0.35)
        if state.ballRunning and model.Parent and not p.Battle.currentBattle then
            input:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.08)
            input:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            local deadline = os.clock() + 10
            while state.ballRunning and model.Parent and os.clock() < deadline do
                task.wait(0.15)
            end
            if not model.Parent then
                collected += 1
                setBallStatus("Collected " .. collected .. " pickup(s)")
            else
                setBallStatus("Pickup not collected; trying another")
            end
        end
        if root.Parent and not p.Battle.currentBattle then
            root.CFrame = oldCFrame
            root.AssemblyLinearVelocity = Vector3.zero
        end
        task.wait(0.3)
    end
end

local function startBallFarm()
    if state.running or p.Battle.currentBattle then
        stopBallFarm("Finish the encounter farm and battle first")
        return
    end
    state.ballRunning = true
    task.spawn(function()
        local ok, err = pcall(ballFarm)
        if not ok then stopBallFarm("Poké Ball farm error: " .. tostring(err)) end
    end)
end
state.stopBallFarm = stopBallFarm

FarmGroup:AddToggle("RoriaAutoFarm", {
    Text = "Start / Stop autofarm",
    Default = false
})
Toggles.RoriaAutoFarm:OnChanged(function()
    if Toggles.RoriaAutoFarm.Value then
        start()
    elseif state.running then
        stop("Stopped")
    end
end)
FarmGroup:AddButton({Text = "Refresh region list", Func = function()
    task.spawn(function()
        local ok, err = pcall(refresh)
        if not ok then setStatus("Refresh error: " .. tostring(err)) end
    end)
end})
FarmGroup:AddToggle("RoriaAutoRefresh", {
    Text = "Auto refresh region",
    Default = true
})
Toggles.RoriaAutoRefresh:OnChanged(function()
    state.autoRefresh = Toggles.RoriaAutoRefresh.Value
end)
FarmGroup:AddDivider()
FarmGroup:AddToggle("RoriaStopOnShiny", {
    Text = "Stop on shiny", Default = false,
    Tooltip = "Treat a shiny as a match. Catch on find will catch it when enabled."
})
Toggles.RoriaStopOnShiny:OnChanged(function()
    state.stopOnShiny = Toggles.RoriaStopOnShiny.Value
end)
FarmGroup:AddSlider("RoriaChanceThreshold", {
    Text = "Chance threshold", Default = 0, Min = 0, Max = 100,
    Rounding = 2, Suffix = "%",
    Tooltip = "Treat encounters at or below this chance as a match. 0% disables it."
})
Options.RoriaChanceThreshold:OnChanged(function()
    state.chanceThreshold = Options.RoriaChanceThreshold.Value
end)
BallGroup:AddToggle("RoriaBallFarm", {
    Text = "Auto collect map Poké Balls",
    Default = false
})
Toggles.RoriaBallFarm:OnChanged(function()
    if Toggles.RoriaBallFarm.Value then
        startBallFarm()
    elseif state.ballRunning then
        stopBallFarm("Stopped")
    end
end)
HealGroup:AddToggle("RoriaAutoHeal", {
    Text = "Auto Heal", Default = false,
    Tooltip = "Heal damaged or fainted party Pokémon while out of battle."
})
Toggles.RoriaAutoHeal:OnChanged(function()
    state.autoHeal = Toggles.RoriaAutoHeal.Value
    setHealStatus(state.autoHeal and "Checking party..." or "Disabled")
end)
MenuGroup:AddToggle("TungKeybindList", {
    Text = "Keybind list",
    Default = false
})
Toggles.TungKeybindList:OnChanged(function()
    Library.KeybindFrame.Visible = Toggles.TungKeybindList.Value
end)
MenuGroup:AddToggle("RoriaNotificationSounds", {
    Text = "Notification sounds", Default = true
})
Toggles.RoriaNotificationSounds:OnChanged(function()
    state.notificationSounds = Toggles.RoriaNotificationSounds.Value
end)
MenuGroup:AddInput("RoriaNotificationSoundId", {
    Text = "Notification sound ID", Default = "17208361335",
    Numeric = true, Finished = false,
    Placeholder = "Roblox sound asset ID"
})
Options.RoriaNotificationSoundId:OnChanged(function()
    state.notificationSoundId = tostring(Options.RoriaNotificationSoundId.Value)
end)
MenuGroup:AddButton("Test notification", function()
    Library:Notify("ArtificalCheat test notification", 4)
end)
MenuGroup:AddButton("Unload", function() Library:Unload() end)
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "End", NoUI = true, Text = "Menu keybind"
})
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({"MenuKeybind", "RoriaTarget", "RoriaAutoFarm", "RoriaBallFarm"})
ThemeManager:SetFolder("RoriaEncounterFarm")
SaveManager:SetFolder("RoriaEncounterFarm/RoriaUnbound")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
local function enableRepeatToClear(picker)
    local previous = picker.Value
    local originalSetValue = picker.SetValue
    local originalChangedCallback = picker.ChangedCallback
    picker.SetValue = function(self, data)
        originalSetValue(self, data)
        previous = self.Value
    end
    picker.ChangedCallback = function(newKey)
        local selected = picker.Value
        if selected == previous and selected ~= "None" then
            task.defer(function()
                if picker.Value == selected then
                    picker:SetValue({"None", picker.Mode or "Toggle"})
                end
            end)
        else
            previous = selected
        end
        if originalChangedCallback then originalChangedCallback(newKey) end
    end
end
for id, option in Options do
    if id ~= "MenuKeybind" and option.Type == "KeyPicker" then
        enableRepeatToClear(option)
    end
end
SaveManager:LoadAutoloadConfig()
task.spawn(function()
    setthreadidentity(2)
    local nextAttempt = 0
    while env.RoriaEncounterFarm == state do
        if state.autoHeal and os.clock() >= nextAttempt then
            if p.Battle.currentBattle then
                setHealStatus("Waiting for battle to end")
            else
                local ok, party = pcall(function()
                    return p.Network:get("PDS", "getParty")
                end)
                if not ok or type(party) ~= "table" then
                    setHealStatus("Could not read party")
                    nextAttempt = os.clock() + 15
                else
                    local needsHeal = false
                    for _, pokemon in party do
                        if type(pokemon) == "table" and
                            ((type(pokemon.hp) == "number" and
                                type(pokemon.maxhp) == "number" and
                                pokemon.hp < pokemon.maxhp) or
                            (type(pokemon.status) == "string" and
                                pokemon.status ~= "")) then
                            needsHeal = true
                            break
                        end
                    end
                    if needsHeal then
                        setHealStatus("Healing party...")
                        local callOk, result = pcall(function()
                            return p.Network:get("PDS", "getPartyPokeBalls")
                        end)
                        local verifyOk, after = pcall(function()
                            return p.Network:get("PDS", "getParty")
                        end)
                        local stillDamaged = false
                        if verifyOk and type(after) == "table" then
                            for _, pokemon in after do
                                if type(pokemon) == "table" and
                                    type(pokemon.hp) == "number" and
                                    type(pokemon.maxhp) == "number" and
                                    pokemon.hp < pokemon.maxhp then
                                    stillDamaged = true
                                    break
                                end
                            end
                        end
                        local healed = callOk and result ~= false and verifyOk and not stillDamaged
                        setHealStatus(healed and "Party healed" or "Heal unavailable")
                        nextAttempt = os.clock() + (healed and 10 or 30)
                    else
                        setHealStatus("Party healthy")
                    end
                end
            end
        end
        task.wait(3)
    end
end)

local function formatEncounterNotification(species, chance, shiny)
    local chanceDisplay = "unknown chance"
    if type(chance) == "number" and chance > 0 then
        chanceDisplay = string.format("%.2f%% (about 1 in %d)",
            chance, math.floor(100 / chance + 0.5))
    end
    local shinyDisplay = shiny and "Shiny" or "Not shiny"
    if shiny and chance and chance > 0
        and not string.find(string.lower(species), "shiny", 1, true) then
        shinyDisplay ..= string.format(" (estimated 1 in %d overall)",
            math.floor(100 * 2048 / chance + 0.5))
    end
    return species .. " | " .. chanceDisplay .. " | " .. shinyDisplay
end
state.formatEncounterNotification = formatEncounterNotification

task.spawn(function()
    local observedBattle = p.Battle.currentBattle
    local notified = observedBattle ~= nil
    while env.RoriaEncounterFarm == state do
        local battle = p.Battle.currentBattle
        if battle ~= observedBattle then
            observedBattle = battle
            notified = false
        end
        if state.notifyOnEncounter and battle and not notified then
            local ok, species, shiny = pcall(function()
                local foe = battle.p2 and battle.p2.active and battle.p2.active[1]
                return foe and foe.species, foe and foe.shiny == true
            end)
            if ok and species and battle.kind == "wild" then
                notified = true
                local key = string.lower(species)
                local method = state.running and state.pendingEncounterMethod
                local chunk = p.DataManager.currentChunk
                local region = chunk and chunk.currentRegion and chunk.currentRegion.Name
                local sameRegion = chunk == state.chunk and region == state.region
                local chance = sameRegion and
                    (method and state.chancesByMethod[method .. "|" .. key]
                    or state.chancesBySpecies[key])
                if chance == false then chance = nil end
                local message = formatEncounterNotification(species, chance, shiny)
                uiChange(function() Library:Notify(message, 4) end)
            end
        end
        task.wait(0.05)
    end
end)

task.spawn(function()
    local ok, err = pcall(refresh)
    if not ok then setStatus("Refresh error: " .. tostring(err)) end
end)
task.spawn(function()
    while env.RoriaEncounterFarm == state do
        task.wait(0.25)
        if state.autoRefresh and not state.running then
            local chunk = p.DataManager.currentChunk
            local region = chunk and chunk.currentRegion and chunk.currentRegion.Name
            if chunk and (chunk ~= state.chunk or region ~= state.region) then
                local ok, err = pcall(refresh)
                if not ok then setStatus("Auto refresh error: " .. tostring(err)) end
            end
        end
    end
end)
