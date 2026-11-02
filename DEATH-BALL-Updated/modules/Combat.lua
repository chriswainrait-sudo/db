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
    local modules = ReplicatedStorage:WaitForChild("Modules", 10)
    local Bitbuf = PrimeRuntime.Require(modules and modules:WaitForChild("Bitbuf", 10))
    local Actions = PrimeRuntime.Require(ReplicatedStorage:WaitForChild("Actions", 10))
    local Values = PrimeRuntime.Require(ReplicatedStorage:WaitForChild("Values", 10))
    if combatClosed or PrimeRuntime.IsShuttingDown then error("Death Ball combat initialization cancelled", 0) end
    local connections = {}
    local actionConnections = {}
    local actionRemotes = {}
    local updateIds = {}
    local deflectButton
    local gameUI, gameInputs, playerControl
    task.spawn(function()
        local core = ReplicatedFirst:FindFirstChild("Core")
        local module = core and core:FindFirstChild("Inputs")
        if module then
            local ok, value = pcall(require, module)
            if ok and not controller.Destroyed then gameInputs = value end
        end
    end)
    task.spawn(function()
        local classes = ReplicatedFirst:FindFirstChild("Classes")
        local module = classes and classes:FindFirstChild("PlayerControl")
        if module and classes:FindFirstChild("lSword") then
            local ok, value = pcall(require, module)
            if ok and not controller.Destroyed then playerControl = value end
        end
    end)
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
                local input = button.Manifest and button.Manifest.Input
                local callable = type(button.OnClick) == "function" or (input and type(input._InputBegan) == "function" and type(input.Release) == "function")
                local playerGui = player:FindFirstChildOfClass("PlayerGui")
                return callable and playerGui ~= nil and typeof(button.Object) == "Instance"
                    and button.Object:IsDescendantOf(playerGui)
            end)
            return ok and result == true
        end
        local manifest = gameInputs and gameInputs.Deflect
        if manifest and valid(manifest.Button) then
            deflectButton = manifest.Button
            env.__DeflectButton = deflectButton
            return true
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
        local input = deflectButton.Manifest and deflectButton.Manifest.Input
        local onClick = deflectButton.OnClick
        if type(onClick) ~= "function" and not (input and type(input._InputBegan) == "function" and type(input.Release) == "function") then
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
        if button.Lock and button.Lock.Locked then return false end
        if input and (not input.Enabled or input.IsPressed or input.Lock and input.Lock.Locked) then return false end
        if button.UseLock and button.UseLock.Locked then return false end
        if button.CanUse == false or button.Debounce then return false end
        if not spam and button.IsOnCooldown and not button.OverrideCooldown then return false end
        deflectBusy = true
        local ok, accepted = pcall(function()
            if input then
                input:_InputBegan(nil, nil, true)
                local pressed = input.IsPressed == true
                if pressed then task.defer(function() pcall(input.Release, input) end) end
                return pressed
            end
            onClick(button)
            return true
        end)
        deflectBusy = false
        if not ok then
            deflectButton = nil
            env.__DeflectButton = nil
        end
        return ok and accepted == true
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
            local c = playerControl or (gameUI and gameUI.PlayerControl)
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
            local c = playerControl or (gameUI and gameUI.PlayerControl)
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
    if combatClosed or PrimeRuntime.IsShuttingDown then return end
    if combat then combat:SetFeatures(parryEnabled, spamEnabled); return end
    if combatStarting or not parryEnabled then return end
    combatStarting = true
    task.spawn(function()
        local ok, result = pcall(createCombatController)
        combatStarting = false
        if not ok then
            if combatClosed or PrimeRuntime.IsShuttingDown then return end
            if buildingCombat then buildingCombat:Destroy() end
            buildingCombat = nil
            parryEnabled, spamEnabled = false, false
            warn("[DeathBall] AutoParry / AutoSpam: " .. tostring(result))
            for _, id in ipairs({"autoparry", "AutoSpam"}) do
                local option = Options[id]
                if option and option.SetValue then pcall(function() option:SetValue(false) end) end
            end
            return
        end
        buildingCombat = nil
        if combatClosed or PrimeRuntime.IsShuttingDown then result:Destroy(); return end
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

Tabs.Main:AddToggle("autoparry", {
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

Tabs.Main:AddToggle("AutoSpam", {
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


TrackRuntimeCleanup(stopCombat)
