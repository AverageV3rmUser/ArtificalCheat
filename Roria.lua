-- Roria Unbound encounter farm. Run with the executor after joining the game.
-- Linoria settings are stored by its ThemeManager and SaveManager.
local env = getgenv()
if env.RoriaEncounterFarm then
    env.RoriaEncounterFarm.running = false
    if env.RoriaEncounterFarm.restoreFast then
        env.RoriaEncounterFarm.restoreFast()
    end
    if env.RoriaEncounterFarm.restorePerfect then
        env.RoriaEncounterFarm.restorePerfect()
    end
    if env.RoriaEncounterFarm.restoreMovement then
        env.RoriaEncounterFarm.restoreMovement()
    end
    if env.RoriaEncounterFarm.library then
        pcall(function() env.RoriaEncounterFarm.library:Unload() end)
    elseif env.RoriaEncounterFarm.gui then
        env.RoriaEncounterFarm.gui:Destroy()
    end
end

local p = filtergc("table", {Keys = {"Battle", "DataManager"}}, true)
assert(p and p.Network, "Roria game data was not found")

local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
Library.ScreenGui.Parent = gethui()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local state = {
    running = false,
    entries = {},
    byDisplay = {},
    selected = nil,
    noneEncounter = nil,
    catchOnFind = false,
    autoRefresh = true,
    ballRunning = false,
    perfectBall = false,
    noclip = false,
    speedEnabled = false,
    hipEnabled = false,
    library = Library
}
env.RoriaEncounterFarm = state

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
    Settings = Window:AddTab("Configs")
}
local MovementGroup = Tabs.Main:AddLeftGroupbox("Movement")
local EncounterGroup = Tabs.Main:AddRightGroupbox("Encounter")
local FarmGroup = Tabs.Farm:AddLeftGroupbox("Encounter Farm")
local BallGroup = Tabs.Farm:AddLeftGroupbox("Poké Ball Farm")
local InfoGroup = Tabs.Farm:AddRightGroupbox("Encounter Status")
local BallInfoGroup = Tabs.Farm:AddRightGroupbox("Poké Ball Status")
local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu")
local regionLabel = InfoGroup:AddLabel("Loading region...", true)
local statusLabel = InfoGroup:AddLabel("Idle", true)
local ballStatusLabel = BallInfoGroup:AddLabel("Idle", true)

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
    if state.restorePerfect then state.restorePerfect() end
    if env.RoriaEncounterFarm == state then env.RoriaEncounterFarm = nil end
end)

FarmGroup:AddDropdown("RoriaTarget", {
    Values = {"None"},
    Default = 1,
    Multi = false,
    Text = "Pokémon (regional chance)"
})
Options.RoriaTarget:OnChanged(function()
    state.selected = state.byDisplay[Options.RoriaTarget.Value]
    if Options.RoriaTarget.Value == "None" then
        setStatus("None selected: encounter and run continuously")
    elseif state.selected then
        setStatus("Selected " .. state.selected.species)
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
    state.selected = nil
    state.noneEncounter = nil
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
    end
    table.sort(state.entries, function(a, b) return a.display < b.display end)
    local values = {"None"}
    for _, entry in state.entries do
        values[#values + 1] = entry.display
    end
    uiChange(function()
        Options.RoriaTarget:SetValues(values)
        Options.RoriaTarget:SetValue(state.byDisplay[previous] and previous or "None")
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

local function autoCatch(battle, species)
    local throws = 0
    local lastRequestId
    setStatus("Found " .. species .. "; catching...")
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
            setStatus("Perfect Poké Ball throw " .. throws .. " · " .. count .. " left")
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
    local entry = state.selected
    local encounter = entry and entry.encounter or state.noneEncounter
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
        deadline = os.clock() + 20
        while state.running and p.Battle.currentBattle == battle and not foe and os.clock() < deadline do
            local readOk, found = pcall(function()
                local active = battle.p2 and battle.p2.active and battle.p2.active[1]
                return active and active.species
            end)
            if readOk then foe = found end
            if not foe then task.wait(0.05) end
        end
        if not state.running then break end
        if not foe then
            stop("Could not read wild Pokémon")
            break
        end
        if entry and string.lower(foe) == string.lower(entry.species) then
            if state.catchOnFind then
                autoCatch(battle, foe)
            else
                stop("Found " .. foe .. " on encounter " .. attempts .. "!")
            end
            break
        end
        setStatus("Found " .. foe .. "; running...")
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
MenuGroup:AddToggle("TungKeybindList", {
    Text = "Keybind list",
    Default = false
})
Toggles.TungKeybindList:OnChanged(function()
    Library.KeybindFrame.Visible = Toggles.TungKeybindList.Value
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
    local ok, err = pcall(refresh)
    if not ok then setStatus("Refresh error: " .. tostring(err)) end
end)
task.spawn(function()
    while env.RoriaEncounterFarm == state do
        task.wait(2)
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
