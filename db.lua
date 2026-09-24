local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera



local platform = UserInputService:GetPlatform()
local IS_MOBILE = platform == Enum.Platform.IOS or platform == Enum.Platform.Android

local Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/chriswainrait-sudo/PrimeLibrary-/refs/heads/main/.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/chriswainrait-sudo/SaveManager/refs/heads/main/.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/chriswainrait-sudo/InterfaceManager/refs/heads/main/.lua"))()

local tierEnv = getgenv and getgenv() or _G
local tier = tostring(tierEnv.PRIME_TIER or _G.PRIME_TIER or "Freemium"):lower()
local UserInfoSubtitle = (tier == "premium" or tier == "preemium") and "Premium" or "Freemium"

local windowSize = IS_MOBILE and UDim2.fromOffset(550,350) or UDim2.fromOffset(550,350)

local Window = Fluent:CreateWindow({
    Title = "NEXUS",
    SubTitle = "Death Ball",
    TabWidth = 130,
    Size = windowSize,
    Theme = "Slate",
    MinimizeKey = Enum.KeyCode.LeftAlt,
    Tier = UserInfoSubtitle,
    IsPremium = UserInfoSubtitle == "Premium",
    UserInfoSubtitle = UserInfoSubtitle
})

local Tabs = {
    main = Window:AddTab({ Title = "Main", Icon = "home" }),
    rage = Window:AddTab({ Title = "Rage", Icon = "flame" }),
    movement = Window:AddTab({ Title = "Movement", Icon = "move" }),
    settings = Window:AddTab({ Title = "Settings", Icon = "settings-2" })
}

Tabs.main:AddParagraph({
    Title = "Welcome",
    Content = "Thank you for being with us!\nUse the toggles below to configure features."
})

local Minimizer

if IS_MOBILE then
    Minimizer = Fluent:CreateMinimizer({
        Icon = "crown",
        Size = UDim2.fromOffset(36, 36),
        Position = UDim2.new(0, 320, 0, 24),
        Corner = 1,
        Transparency = 1,
        Draggable = true,
        Visible = true
    })
else
    Minimizer = nil
end

local Options = Fluent.Options

-- HUD watcher safety net
task.spawn(function()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    while true do
        local hud = playerGui:FindFirstChild("HUD")
        if hud then
            hud.AncestryChanged:Connect(function()
                if not hud.Parent then
                    task.wait(0.5)
                    local newHud = playerGui:FindFirstChild("HUD")
                    if newHud then
                        for _, v in ipairs(newHud:GetDescendants()) do
                            if v:IsA("GuiObject") then
                                pcall(function() v.Visible = true end)
                            end
                        end
                    end
                end
            end)
        end
        task.wait(1)
    end
end)

local combat, buildingCombat
local combatStarting, combatClosed = false, false
local parryEnabled, spamEnabled = false, false
local combatEnv = getgenv and getgenv() or _G
local function createCombatController()
    local env = combatEnv
    local controller = {
        Enabled = false,
        AutoPing = true,
        CloseDistance = 15,
        Cooldown = 0.05,
        MaxPacketAge = 1,
        PacketLossAge = 0.1,
        Ping = 0,
        Jitter = 0,
        TriggerDistance = 15,
        AutoParry = false,
        AutoSpam = false,
        SpamBallDistance = 14,
        SpamEnemyDistance = 18.2,
        SpamExitDistance = 22,
        SpamTargetGrace = 0.18,
        SpamMinInterval = 0.025,
        SpamMaxInterval = 0.05,
        SpamMinSpeed = 15,
        SpamMinAccel = 120,
        SpamMode = false,
    }

    local player = Players.LocalPlayer
    local Bitbuf = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Bitbuf"))
    local Actions = require(ReplicatedStorage:WaitForChild("Actions"))
    local Values = require(ReplicatedStorage:WaitForChild("Values"))
    local connections = {}
    local actionConnections = {}
    local actionRemotes = {}
    local updateIds = {}
    local deflectButton
    local gameUI
    task.spawn(function()
        local m = game:GetService("ReplicatedFirst"):WaitForChild("ui", 15)
        if not m then return end
        local o, u = pcall(require, m)
        if o and not controller.Destroyed then gameUI = u end
    end)
    local buttonSearchRunning = false
    local targetObject
    local lastButtonSearch = -math.huge
    local lastParry = -math.huge
    local parryPending = false
    local deflectBusy = false
    local lastSpam = -math.huge
    local lastTargetMe = -math.huge
    local targetAimTime = -math.huge
    local targetAimPosition
    local targetAimSpeed = 0
    local lastPacketTime = -math.huge
    local packetPosition
    local packetVelocity
    local packetAcceleration = Vector3.zero
    local previousPacketVelocity
    local previousPacketTime
    local targeted = false
    local mapOffset = Vector3.zero
    local activeMap
    local offsetPart
    local lastOffsetSearch = -math.huge
    local smoothPing
    local smoothJitter = 0
    local lastPingSample = -math.huge
    local lastRemoteRefresh = -math.huge
    local trackedRoot
    local previousRootPosition
    local previousRootTime
    local measuredRootVelocity = Vector3.zero
    local function addConnection(connection, list)
        table.insert(list or connections, connection)
        return connection
    end

    local function b64decode(data)
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        data = data:gsub("[^" .. chars .. "=]", "")
        return (data:gsub(".", function(char)
            if char == "=" then return "" end
            local value = chars:find(char, 1, true)
            if not value then return "" end
            value -= 1
            local bits = ""
            for index = 6, 1, -1 do
                bits ..= value % 2 ^ index - value % 2 ^ (index - 1) > 0 and "1" or "0"
            end
            return bits
        end):gsub("%d%d%d%d%d%d%d%d", function(bits)
            local value = 0
            for index = 1, 8 do
                if bits:sub(index, index) == "1" then value += 2 ^ (8 - index) end
            end
            return string.char(value)
        end))
    end

    local function refreshMapOffset()
        local map = Workspace:FindFirstChild("ActiveMap")
        if map == activeMap and offsetPart and offsetPart.Parent then
            mapOffset = offsetPart.Position
            return
        end
        if map == activeMap and os.clock() - lastOffsetSearch < 1 then return end
        lastOffsetSearch = os.clock()
        activeMap = map
        offsetPart = nil
        mapOffset = Vector3.zero
        if not map then return end
        for _, object in ipairs(map:GetDescendants()) do
            if object:IsA("Folder") and object.Name == "BallSpawns" then
                local part = object:FindFirstChild("Part")
                if part and part:IsA("BasePart") then
                    offsetPart = part
                    mapOffset = part.Position
                    return
                end
            end
        end
    end

    local function decodePacket(payload)
        local buffer = Bitbuf.fromString(payload)
        buffer:ReadUint(10)
        buffer:ReadFloat(64)
        local position = Vector3.new(buffer:ReadInt(23) / 1000, buffer:ReadInt(23) / 1000, buffer:ReadInt(23) / 1000)
        local velocity = Vector3.new(buffer:ReadInt(24) / 1000, buffer:ReadInt(24) / 1000, buffer:ReadInt(24) / 1000)
        if position.X ~= position.X or velocity.X ~= velocity.X or position.Magnitude > 100000 or velocity.Magnitude > 2000 then
            error("invalid ball packet")
        end
        return position + mapOffset, velocity
    end

    local function findDeflectButton()
        if controller.Destroyed then return false end
        local function valid(button)
            if type(button) ~= "table" then return false end
            local ok, result = pcall(function()
                return type(button.OnClick) == "function" and typeof(button.Object) == "Instance"
                    and button.Object:IsDescendantOf(player:FindFirstChildOfClass("PlayerGui"))
            end)
            return ok and result == true
        end
        if gameUI then
            local ok, button = pcall(function()
                local holder = gameUI.AllUI.GameplayButtons
                return holder and holder.DeflectButton
            end)
            if ok and valid(button) then
                deflectButton = button
                env.__DeflectButton = button
                return true
            end
        end
        if valid(deflectButton) then return true end
        deflectButton = nil
        local cached = rawget(env, "__DeflectButton")
        if valid(cached) then deflectButton = cached return true end
        env.__DeflectButton = nil
        if type(getgc) ~= "function" then return false end
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then return false end
        for index, object in ipairs(objects) do
            if controller.Destroyed then return false end
            if type(object) == "table" and rawget(object, "AllButtons") ~= nil then
                local button = rawget(object, "DeflectButton")
                if valid(button) then
                    deflectButton = button
                    env.__DeflectButton = button
                    return true
                end
            end
            if index % 400 == 0 then task.wait() end
        end
        return false
    end

    local function pressDeflect(spam)
        if deflectBusy then return false end
        if type(deflectButton) ~= "table" then return false end
        local onClick = deflectButton.OnClick
        if type(onClick) ~= "function" then
            deflectButton = nil
            return false
        end
        local button = deflectButton
        local valid, attached = pcall(function()
            local playerGui = player:FindFirstChildOfClass("PlayerGui")
            return playerGui ~= nil and typeof(button.Object) == "Instance" and button.Object:IsDescendantOf(playerGui)
        end)
        if not valid or not attached then
            deflectButton = nil
            env.__DeflectButton = nil
            return false
        end
        if button.UseLock and button.UseLock.Locked then return false end
        if button.CanUse == false or button.Debounce then return false end
        if not spam and button.IsOnCooldown and not button.OverrideCooldown then return false end
        deflectBusy = true
        local ok = pcall(onClick, button)
        deflectBusy = false
        if not ok then
            deflectButton = nil
            env.__DeflectButton = nil
        end
        return ok
    end

    local function updateRootVelocity(root, now)
        if root ~= trackedRoot then
            trackedRoot = root
            previousRootPosition = root.Position
            previousRootTime = now
            measuredRootVelocity = root.AssemblyLinearVelocity
            return measuredRootVelocity
        end
        local dt = previousRootTime and now - previousRootTime or 0
        if dt > 0.002 and dt < 0.2 then
            local sampled = (root.Position - previousRootPosition) / dt
            if sampled.Magnitude <= 250 then
                measuredRootVelocity = measuredRootVelocity:Lerp(sampled, math.clamp(dt * 18, 0.2, 0.75))
            end
        elseif dt >= 0.2 then
            measuredRootVelocity = root.AssemblyLinearVelocity
        end
        previousRootPosition = root.Position
        previousRootTime = now
        local assembly = root.AssemblyLinearVelocity
        local velocity = assembly.Magnitude > measuredRootVelocity.Magnitude * 0.5 and assembly or measuredRootVelocity
        return velocity.Magnitude > 250 and velocity.Unit * 250 or velocity
    end

    local function updatePing(now)
        if now - lastPingSample < 0.2 then return end
        lastPingSample = now
        local sample = math.clamp(player:GetNetworkPing(), 0, 0.35)
        if smoothPing then
            local delta = math.abs(sample - smoothPing)
            smoothJitter += (delta - smoothJitter) * 0.2
            smoothPing += (sample - smoothPing) * 0.18
        else
            smoothPing = sample
        end
        controller.Ping = smoothPing
        controller.Jitter = smoothJitter
    end

    local function rawPredict(now)
        local age = math.max(now - lastPacketTime, 0)
        local k = math.clamp(1 - age / 0.16, 0, 1)
        local a = packetAcceleration * k
        return packetPosition + packetVelocity * age + a * (0.5 * age * age), packetVelocity + a * age, a, age
    end

    local function predictBall(now, root)
        local p, v, a, age = rawPredict(now)
        if targeted and root and targetAimPosition and targetAimTime > lastPacketTime and now - targetAimTime <= controller.MaxPacketAge then
            local d = root.Position - targetAimPosition
            if d.Magnitude > 0 and targetAimSpeed > 5 then
                v = d.Unit * targetAimSpeed
                p = targetAimPosition + v * (now - targetAimTime)
                a = Vector3.zero
            end
        end
        return p, v, a, age
    end

    local function shouldParry(now, position, velocity, acceleration, root)
        local pingMs = controller.AutoPing and (smoothPing or 0) * 2000 or 0
        local loss = math.max(now - lastPacketTime - controller.PacketLossAge, 0)
        controller.TriggerDistance = 15 + math.min(math.max(pingMs - 80, 0) * 0.01, 3) + math.min((smoothJitter or 0) * 30, 2) + math.min(loss * 8, 3)
        if not targeted or not targetObject then return false end
        local character = player.Character
        if targetObject ~= player and (typeof(targetObject) ~= "Instance" or not character
            or (targetObject ~= character and not targetObject:IsDescendantOf(character))) then return false end
        local delta = position - root.Position
        if delta.Magnitude > controller.TriggerDistance or velocity.Magnitude < 5 then return false end
        local relative = velocity - updateRootVelocity(root, now)
        if delta:Dot(relative) < 0 then return true end
        local t = math.clamp(0.035 + loss * 0.35, 0.035, 0.12)
        return (delta + relative * t + acceleration * (0.5 * t * t)).Magnitude < delta.Magnitude
    end

    local function ne(r, d)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player then
                local c = p.Character
                local h = c and c:FindFirstChildOfClass("Humanoid")
                local x = c and c:FindFirstChild("HumanoidRootPart")
                if h and h.Health > 0 and x and (x.Position - r.Position).Magnitude <= d then return true end
            end
        end
        return false
    end

    local function tryParry(now, position, velocity, acceleration)
        if controller.Destroyed or not controller.Enabled then controller.SpamMode = false return end
        local ok, active = pcall(function() return Values.PLAYER_ACTIVE_STATE:Get() end)
        if ok and active == false then controller.SpamMode = false return end
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health <= 0 or not root then controller.SpamMode = false return end
        local a = acceleration or Vector3.zero
        local d = (position - root.Position).Magnitude
        local md = controller.SpamMode and controller.SpamExitDistance or controller.SpamBallDistance
        local s = controller.AutoSpam and (targeted or now - lastTargetMe <= controller.SpamTargetGrace)
            and d <= md and ne(root, controller.SpamEnemyDistance)
            and (velocity.Magnitude >= controller.SpamMinSpeed or a.Magnitude >= controller.SpamMinAccel)
        controller.SpamMode = s == true
        if s then
            local c = gameUI and gameUI.PlayerControl
            local w = c and c.Sword
            if w and w.Cooldown == true then w.Cooldown = false w.Ready = true end
            local i = math.clamp(0.06 - velocity.Magnitude / 10000, controller.SpamMinInterval, controller.SpamMaxInterval)
            if now - lastSpam >= i and pressDeflect(true) then
                lastSpam = now
                lastParry = now
                parryPending = true
            end
            return
        end
        if controller.AutoParry and not parryPending and shouldParry(now, position, velocity, a, root) then
            local c = gameUI and gameUI.PlayerControl
            local w = c and c.Sword
            local cd = w and w.Cooldown == true or deflectButton and deflectButton.IsOnCooldown and not deflectButton.OverrideCooldown
            if not cd and now - lastParry >= controller.Cooldown then
                parryPending = true
                lastParry = now
                if not pressDeflect() then parryPending = false end
            end
        end
    end

    for key, encodedName in pairs(Actions.ACTIONS_OBF_TO_REAL or {}) do
        local ok, name = pcall(b64decode, encodedName)
        if ok and type(name) == "string" then
            local upper = name:upper()
            if upper == "UPDATE" or upper:find("BALL_UPDATE", 1, true) or upper:find("UPDATE_BALL", 1, true) then
                updateIds[key] = true
                updateIds[name] = true
            end
        end
    end
    updateIds.Update = true

    local function onAction(_, actionId, payload)
        if controller.Destroyed then return end
        if type(payload) ~= "string" then return end
        if next(updateIds) and not updateIds[actionId] then
            local valid = pcall(decodePacket, payload)
            if not valid then return end
        end
        refreshMapOffset()
        local ok, position, velocity = pcall(decodePacket, payload)
        if not ok then return end
        local now = os.clock()
        if previousPacketVelocity and previousPacketTime then
            local dt = now - previousPacketTime
            if dt > 0.003 and dt < 0.12 then
                local acceleration = (velocity - previousPacketVelocity) / dt
                if acceleration.Magnitude <= 6000 then
                    packetAcceleration = packetAcceleration:Lerp(acceleration, 0.55)
                else
                    packetAcceleration = Vector3.zero
                end
            else
                packetAcceleration = Vector3.zero
            end
        end
        previousPacketVelocity = velocity
        previousPacketTime = now
        packetPosition = position
        packetVelocity = velocity
        lastPacketTime = now
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if parryPending and root then
            local delta = position - root.Position
            if delta.Magnitude > controller.TriggerDistance + 2 and delta:Dot(velocity) > 0 then
                parryPending = false
            end
        end
        tryParry(now, position, velocity, packetAcceleration)
    end

    local function addActionRemote(remote)
        if controller.Destroyed then return end
        if typeof(remote) ~= "Instance" or actionRemotes[remote] or remote.Name ~= "Action" or not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end
        actionRemotes[remote] = true
        local ok, connection = pcall(function()
            return remote.OnClientEvent:Connect(function(actionId, payload)
                onAction(remote, actionId, payload)
            end)
        end)
        if ok and connection then addConnection(connection, actionConnections) end
    end

    function controller:SetFeatures(parry, spam)
        if self.Destroyed then return end
        self.AutoParry = parry == true
        self.AutoSpam = self.AutoParry and spam == true
        self.Enabled = self.AutoParry
        if not self.Enabled then parryPending = false end
        if not self.AutoSpam then self.SpamMode = false end
    end

    function controller:Destroy()
        if self.Destroyed then return end
        self.Destroyed = true
        self.Enabled, self.AutoParry, self.AutoSpam, self.SpamMode = false, false, false, false
        for _, list in ipairs({connections, actionConnections}) do
            for _, connection in ipairs(list) do pcall(function() connection:Disconnect() end) end
            table.clear(list)
        end
        table.clear(actionRemotes)
        if env.__DeflectButton == deflectButton then env.__DeflectButton = nil end
        deflectButton = nil
        if env.DeathBallMainCombat == self then env.DeathBallMainCombat = nil end
    end
    buildingCombat = controller

    for _, object in ipairs(ReplicatedStorage:GetDescendants()) do addActionRemote(object) end
    if type(getnilinstances) == "function" then
        pcall(function()
            for _, object in ipairs(getnilinstances()) do addActionRemote(object) end
        end)
    end
    addConnection(ReplicatedStorage.DescendantAdded:Connect(addActionRemote))

    local function findAction(realName)
        for key, encodedName in pairs(Actions.ACTIONS_OBF_TO_REAL or {}) do
            local ok, name = pcall(b64decode, encodedName)
            if ok and name == realName then return Actions[key] or Actions[name] end
        end
        return Actions[realName]
    end

    local function vp(o)
        for _, p in ipairs(Players:GetPlayers()) do
            local c = p.Character
            if o == p or typeof(o) == "Instance" and c and (o == c or o:IsDescendantOf(c)) then return p end
        end
    end

    local targetSignal = findAction("SET_ROUND_BALL_TARGET")
    if targetSignal then
        local ok, connection = pcall(function()
            return targetSignal:Connect(function(object)
                targetObject = object
                local p = vp(object)
                local wasTargeted = targeted
                targeted = p == player
                if not targeted or not wasTargeted then parryPending = false end
                if targeted then
                    local n = os.clock()
                    lastTargetMe = n
                    targetAimTime = n
                    if packetPosition and packetVelocity then
                        local q, v = rawPredict(n)
                        targetAimPosition = q
                        targetAimSpeed = v.Magnitude
                    else
                        targetAimPosition = nil
                        targetAimSpeed = 0
                    end
                else
                    targetAimTime = -math.huge
                    targetAimPosition = nil
                    targetAimSpeed = 0
                end
            end)
        end)
        if ok and connection then addConnection(connection) end
    end

    refreshMapOffset()
    addConnection(player.CharacterAdded:Connect(function(character)
        targeted = false
        parryPending = false
        targetObject = nil
        controller.SpamMode = false
        lastTargetMe = -math.huge
        targetAimTime = -math.huge
        targetAimPosition = nil
        targetAimSpeed = 0
        lastSpam = -math.huge
        packetPosition = nil
        previousPacketVelocity = nil
        trackedRoot = nil
        deflectButton = nil
        env.__DeflectButton = nil
    end))
    pcall(function()
        addConnection(Values.PLAYER_ACTIVE_STATE:Connect(function(_, active)
            if active == false then
                targeted = false
                parryPending = false
                targetObject = nil
                controller.SpamMode = false
                lastTargetMe = -math.huge
                targetAimTime = -math.huge
                targetAimPosition = nil
                targetAimSpeed = 0
                lastSpam = -math.huge
                        packetPosition = nil
                packetVelocity = nil
                packetAcceleration = Vector3.zero
                previousPacketVelocity = nil
                previousPacketTime = nil
            end
        end))
    end)

    addConnection(RunService.Heartbeat:Connect(function()
        if controller.Destroyed or not controller.Enabled then return end
        local now = os.clock()
        updatePing(now)
        if not buttonSearchRunning and now - lastButtonSearch >= 2 then
            lastButtonSearch = now
            buttonSearchRunning = true
            task.spawn(function()
                pcall(findDeflectButton)
                buttonSearchRunning = false
            end)
        end
        if type(getnilinstances) == "function" and now - lastRemoteRefresh >= 5 then
            lastRemoteRefresh = now
            pcall(function()
                for _, object in ipairs(getnilinstances()) do addActionRemote(object) end
            end)
        end
        if packetPosition and packetVelocity then
            local age = now - lastPacketTime
            local maxAge = targeted and controller.MaxPacketAge or math.min(controller.MaxPacketAge, 0.55)
            if age <= maxAge then
                local c = player.Character
                local r = c and c:FindFirstChild("HumanoidRootPart")
                local p, v, a = predictBall(now, r)
                tryParry(now, p, v, a)
            else
                packetPosition = nil
                packetVelocity = nil
                packetAcceleration = Vector3.zero
                previousPacketVelocity = nil
                previousPacketTime = nil
                if not targeted then
                    targetAimTime = -math.huge
                    targetAimPosition = nil
                    targetAimSpeed = 0
                end
            end
        end
    end))
return controller
end

local function stopCombat()
    combatClosed = true
    parryEnabled, spamEnabled = false, false
    if combat then combat:Destroy(); combat = nil end
    if buildingCombat then buildingCombat:Destroy(); buildingCombat = nil end
end

local function syncCombat()
    if combatClosed then return end
    if combat then combat:SetFeatures(parryEnabled, spamEnabled); return end
    if combatStarting or not parryEnabled then return end
    combatStarting = true
    task.spawn(function()
        local ok, result = pcall(createCombatController)
        combatStarting = false
        if not ok then
            if buildingCombat then buildingCombat:Destroy() end
            buildingCombat = nil
            parryEnabled, spamEnabled = false, false
            warn("[DeathBall] AutoParry / AutoSpam: " .. tostring(result))
            for _, id in ipairs({"autoparry", "AutoSpam"}) do
                local option = Fluent.Options[id]
                if option and option.SetValue then pcall(function() option:SetValue(false) end) end
            end
            return
        end
        buildingCombat = nil
        if combatClosed then result:Destroy(); return end
        combat = result
        combatEnv.DeathBallMainCombat = result
        combat:SetFeatures(parryEnabled, spamEnabled)
    end)
end

if combatEnv.DeathBallMainCombat then
    pcall(function() combatEnv.DeathBallMainCombat:Destroy() end)
end
if combatEnv.DeathBallModuleAutoParry then
    pcall(function() combatEnv.DeathBallModuleAutoParry:Destroy() end)
end

Tabs.main:AddToggle("autoparry", {
    Title = "AutoParry",
    Default = false,
    Callback = function(value)
        parryEnabled = value == true
        local spam = Options.AutoSpam
        if not parryEnabled then
            spamEnabled = false
            if spam then spam:SetValue(false) end
        end
        if spam then spam:SetDisabled(not parryEnabled) end
        syncCombat()
    end
})

Tabs.main:AddToggle("AutoSpam", {
    Title = "AutoSpam",
    Default = false,
    DependsOn = "autoparry",
    Callback = function(value)
        spamEnabled = value == true and parryEnabled
        if value and not parryEnabled then
            Options.AutoSpam:SetValue(false)
        end
        syncCombat()
    end
})
Options.AutoSpam:SetDisabled(not parryEnabled)

local player = Players.LocalPlayer

local autoReadyConnection = nil
local originalReadyZoneState = nil

Tabs.main:AddToggle("autoready", {
    Title = "Auto Ready",
    Description = "Automatically readies you at the start of rounds",
    Default = false,
    Callback = function(Value)
        if Value then
            task.spawn(function()
                local lobby = workspace:WaitForChild("New Lobby", 5)
                if not lobby then return end
                local readyArea = lobby:WaitForChild("ReadyArea", 5)
                if not readyArea then return end
                local readyZone = readyArea:WaitForChild("ReadyZone", 5)
                if readyZone and readyZone:IsA("BasePart") then
                    if not originalReadyZoneState or originalReadyZoneState.Part ~= readyZone then
                        originalReadyZoneState = {
                            Part = readyZone,
                            Size = readyZone.Size,
                            Transparency = readyZone.Transparency,
                            CanCollide = readyZone.CanCollide
                        }
                    end
                    local targetSize = originalReadyZoneState.Size * 60
                    if autoReadyConnection then autoReadyConnection:Disconnect() end
                    autoReadyConnection = RunService.Heartbeat:Connect(function()
                        if readyZone and readyZone.Parent then
                            readyZone.Size = targetSize
                            readyZone.CanCollide = false
                            readyZone.Transparency = 1
                        else
                            if autoReadyConnection then autoReadyConnection:Disconnect(); autoReadyConnection = nil end
                        end
                    end)
                end
            end)
        else
            if autoReadyConnection then autoReadyConnection:Disconnect(); autoReadyConnection = nil end
            if originalReadyZoneState and originalReadyZoneState.Part and originalReadyZoneState.Part.Parent then
                originalReadyZoneState.Part.Size = originalReadyZoneState.Size
                originalReadyZoneState.Part.Transparency = originalReadyZoneState.Transparency
                originalReadyZoneState.Part.CanCollide = originalReadyZoneState.CanCollide
            end
        end
    end
})

local fovInicialPadrao = Camera and math.clamp(Camera.FieldOfView, 70, 120) or 70
local desiredFOV = fovInicialPadrao

Tabs.main:AddSlider("fov", {
    Title = "FOV Value",
    Description = "Adjust your field of view (70-120)",
    Default = fovInicialPadrao,
    Min = 70,
    Max = 120,
    Rounding = 0,
    Callback = function(Value) desiredFOV = Value end
})

local runService = game:GetService("RunService")
runService.RenderStepped:Connect(function()
    local cam = workspace.CurrentCamera
    if cam and desiredFOV then
        if cam.FieldOfView ~= desiredFOV then cam.FieldOfView = desiredFOV end
    end
end)

Tabs.main:AddSlider("maxzoom", {
    Title = "Max Zoom",
    Description = "",
    Default = 45,
    Min = 45,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        local currentPlayer = Players.LocalPlayer
        if currentPlayer then currentPlayer.CameraMaxZoomDistance = Value end
    end
})

local flyConnection = nil
local flyEnabled = false
local flySpeed = 50
local speedHackEnabled = false
local speedHackValue = 50
local speedHackConnection = nil
local originalSpeedValue = nil
local jumpPowerEnabled = false
local jumpPowerValue = 50
local jumpPowerConnection = nil
local originalJumpPowerValue = nil
local allConnections = {}
local allToggles = {}

local function enableFly()
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    if flyConnection then flyConnection:Disconnect() end
    local wasBodyVelocity = false
    flyConnection = RunService.RenderStepped:Connect(function()
        local currentChar = player.Character
        local currentRootPart = currentChar and currentChar:FindFirstChild("HumanoidRootPart")
        if not flyEnabled or not currentRootPart then return end
        local camCF = workspace.CurrentCamera.CFrame
        local moveVec = Vector3.new()
        if IS_MOBILE then
            moveVec = moveVec + camCF.LookVector
        else
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVec = moveVec + camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVec = moveVec - camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVec = moveVec - camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVec = moveVec + camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVec = moveVec + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                moveVec = moveVec - Vector3.new(0, 1, 0)
            end
        end
        if moveVec.Magnitude > 0 then
            moveVec = moveVec.Unit * flySpeed
            currentRootPart.Velocity = moveVec
            wasBodyVelocity = true
        else
            if wasBodyVelocity then currentRootPart.Velocity = Vector3.zero end
        end
    end)
end

local function disableFly()
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    local character = player.Character
    if character then
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then rootPart.Velocity = Vector3.zero end
    end
end

local function getMovementHandler()
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local Classes = ReplicatedFirst:FindFirstChild("Classes")
    if not Classes then return nil end
    local PlayerControl = Classes:FindFirstChild("PlayerControl")
    if not PlayerControl then return nil end
    local success, result = pcall(require, PlayerControl)
    if success then return result end
    return nil
end

local function applySpeedHack()
    if not speedHackEnabled then return end
    if originalSpeedValue == nil then
        local control = getMovementHandler()
        if control and control.Movement then originalSpeedValue = control.Movement.RunSpeed or 16 end
    end
    if speedHackConnection then speedHackConnection:Disconnect() end
    speedHackConnection = RunService.Heartbeat:Connect(function()
        if speedHackEnabled then
            local control = getMovementHandler()
            if control and control.Movement then
                control.Movement.RunSpeed = speedHackValue
                control.Movement.OverrideWalkSpeed = speedHackValue
            end
        end
    end)
    table.insert(allConnections, speedHackConnection)
end

local function disableSpeedHack()
    if speedHackConnection then speedHackConnection:Disconnect(); speedHackConnection = nil end
    if originalSpeedValue ~= nil then
        local control = getMovementHandler()
        if control and control.Movement then
            control.Movement.RunSpeed = originalSpeedValue
            control.Movement.OverrideWalkSpeed = originalSpeedValue
        end
        originalSpeedValue = nil
    end
end

local function applyJumpPower()
    if not jumpPowerEnabled then return end
    if originalJumpPowerValue == nil then
        local control = getMovementHandler()
        if control and control.Movement then originalJumpPowerValue = control.Movement.DoubleJumpPower or 50 end
    end
    if jumpPowerConnection then jumpPowerConnection:Disconnect() end
    jumpPowerConnection = RunService.Heartbeat:Connect(function()
        if jumpPowerEnabled then
            local control = getMovementHandler()
            if control and control.Movement then
                control.Movement.DoubleJumpPower = jumpPowerValue
                if control.Movement.Humanoid then control.Movement.Humanoid.JumpPower = jumpPowerValue end
            end
        end
    end)
    table.insert(allConnections, jumpPowerConnection)
end

local function disableJumpPower()
    if jumpPowerConnection then jumpPowerConnection:Disconnect(); jumpPowerConnection = nil end
    if originalJumpPowerValue ~= nil then
        local control = getMovementHandler()
        if control and control.Movement then control.Movement.DoubleJumpPower = originalJumpPowerValue end
        originalJumpPowerValue = nil
    end
end

local function disableAllToggles()
    flyEnabled = false; speedHackEnabled = false; jumpPowerEnabled = false
    disableFly(); disableSpeedHack(); disableJumpPower()
    for _, toggle in ipairs(allToggles) do
        if toggle and toggle.Set then toggle:Set(false) end
    end
end

local function cleanupAllConnections()
    for _, connection in ipairs(allConnections) do
        if connection and connection.Connected then connection:Disconnect() end
    end
    allConnections = {}
end

local flyToggle = Tabs.movement:AddToggle("flyToggle", {
    Title = "Fly",
    Description = "Enable flight mode to freely move in any direction",
    Default = false,
    Callback = function(value)
        flyEnabled = value
        if value then enableFly() else disableFly() end
    end
})
table.insert(allToggles, flyToggle)

Tabs.movement:AddSlider("flySpeed", {
    Title = "Fly speed", Default = 50, Min = 10, Max = 200, Rounding = 0,
    Callback = function(value) flySpeed = value end
})

local speedHackToggle = Tabs.movement:AddToggle("speedHackToggle", {
    Title = "Speed Hack",
    Description = "Increase your movement speed",
    Default = false,
    Callback = function(value)
        speedHackEnabled = value
        if value then applySpeedHack() else disableSpeedHack() end
    end
})
table.insert(allToggles, speedHackToggle)

Tabs.movement:AddSlider("speedValue", {
    Title = "Speed Value", Default = 50, Min = 0, Max = 200, Rounding = 0,
    Callback = function(value) speedHackValue = value end
})

local jumpPowerToggle = Tabs.movement:AddToggle("jumpPowerToggle", {
    Title = "Jump Power",
    Description = "Increase your jump power",
    Default = false,
    Callback = function(value)
        jumpPowerEnabled = value
        if value then applyJumpPower() else disableJumpPower() end
    end
})
table.insert(allToggles, jumpPowerToggle)

Tabs.movement:AddSlider("jumpPowerValue", {
    Title = "Jump Power Value", Default = 50, Min = 0, Max = 200, Rounding = 0,
    Callback = function(value) jumpPowerValue = value end
})

local rageConnections = {}
local originalStates = { InfJump = nil, NoDash = nil, NoParry = nil }

local function GetPlayerControl()
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local Classes = ReplicatedFirst:FindFirstChild("Classes")
    if not Classes then return nil end
    local PlayerControl = Classes:FindFirstChild("PlayerControl")
    if not PlayerControl then return nil end
    local success, result = pcall(require, PlayerControl)
    if success then return result end
    return nil
end

local function ToggleLoop(name, callback)
    if rageConnections[name] then rageConnections[name]:Disconnect(); rageConnections[name] = nil end
    if callback then rageConnections[name] = RunService.Heartbeat:Connect(callback) end
end

Tabs.rage:AddToggle("InfiniteDoubleJump", {
    Title = "Infinite Double Jump",
    Description = "Enables infinite double jump for unrestricted aerial mobility",
    Default = false,
    Callback = function(Value)
        local control = GetPlayerControl()
        if Value then
            if not control or not control.Movement then return end
            if not originalStates.InfJump then
                originalStates.InfJump = {
                    ExtraJumpCount = control.Movement.ExtraJumpCount,
                    UsedJumpCount = control.Movement.UsedJumpCount,
                    ReadyForDoubleJump = control.Movement.ReadyForDoubleJump
                }
            end
            ToggleLoop("InfJump", function()
                if control and control.Movement then
                    control.Movement.UsedJumpCount = 0
                    control.Movement.ExtraJumpCount = 999
                    control.Movement.ReadyForDoubleJump = true
                end
            end)
        else
            ToggleLoop("InfJump", nil)
            if control and control.Movement and originalStates.InfJump then
                control.Movement.ExtraJumpCount = originalStates.InfJump.ExtraJumpCount
                control.Movement.UsedJumpCount = originalStates.InfJump.UsedJumpCount
                control.Movement.ReadyForDoubleJump = originalStates.InfJump.ReadyForDoubleJump
                originalStates.InfJump = nil
            end
        end
    end
})

Tabs.rage:AddToggle("NoDashCooldown", {
    Title = "No Dash Cooldown",
    Description = "Removes dash cooldown for unlimited dash ability usage",
    Default = false,
    Callback = function(Value)
        local control = GetPlayerControl()
        if Value then
            if not control or not control.Movement then return end
            if not originalStates.NoDash then
                originalStates.NoDash = {
                    IsDashOnCooldown = control.Movement.IsDashOnCooldown,
                    DashCooldown = control.Movement.DashCooldown
                }
            end
            ToggleLoop("NoDash", function()
                if control and control.Movement then
                    control.Movement.IsDashOnCooldown = false
                    control.Movement.DashCooldown = 0
                end
            end)
        else
            ToggleLoop("NoDash", nil)
            if control and control.Movement and originalStates.NoDash then
                control.Movement.IsDashOnCooldown = originalStates.NoDash.IsDashOnCooldown
                control.Movement.DashCooldown = originalStates.NoDash.DashCooldown
                originalStates.NoDash = nil
            end
        end
    end
})

Tabs.rage:AddToggle("NoParryCooldown", {
    Title = "Infinite Parry",
    Description = "Removes parry cooldown for constant defense capability",
    Default = false,
    Callback = function(Value)
        local control = GetPlayerControl()
        if Value then
            if not control or not control.Sword then return end
            ToggleLoop("NoParry", function()
                if control and control.Sword and control.Sword.Cooldown == true then
                    control.Sword.Cooldown = false
                    control.Sword.Ready = true
                end
            end)
        else
            ToggleLoop("NoParry", nil)
        end
    end
})

local function Shutdown()
    stopCombat()
    disableAllToggles()
    cleanupAllConnections()
    for _, conn in ipairs(rageConnections) do
        if conn and conn.Connected then conn:Disconnect() end
    end
end

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("NEXUS")
SaveManager:SetFolder("Nexus/DeathBall")
InterfaceManager:BuildInterfaceSection(Tabs.settings)
SaveManager:BuildConfigSection(Tabs.settings)
Window:SelectTab(1)

task.spawn(function()
    if game:IsLoaded() then
        local player = game:GetService("Players").LocalPlayer
        if not player.Character then player.CharacterAdded:Wait() end
        task.wait(2)
        SaveManager:LoadAutoloadConfig()
    end
end)

if Fluent then
    local originalDestroy = Fluent.Destroy
    Fluent.Destroy = function(...)
        Shutdown()
        if originalDestroy then return originalDestroy(...) end
    end
end

local function CleanupAll()
    stopCombat()
    disableFly()
    disableSpeedHack()
    disableJumpPower()
    for _, conn in ipairs(allConnections) do
        if conn and conn.Disconnect then conn:Disconnect() end
    end
end
