local v = {Alive = true, Choice = {}, Hidden = {}, Motors = {}, Effects = {}, Epoch = 0}
local assets = ReplicatedStorage:WaitForChild("Assets", 10)
local bins = ReplicatedStorage:WaitForChild("DataBins", 10)
local scripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
local skinData = PrimeRuntime.Require(bins:WaitForChild("SkinData", 10))
local itemData = PrimeRuntime.Require(bins:WaitForChild("ItemData", 10))
local maps, lists = {}, {}
local rebuild, bindAura, stopCinema
local function notify(failure)
    if v.Alive then NexusUI:Notify({Title = "Visual", Content = tostring(failure), Duration = 5}) end
end
local function destroy(object)
    if not object then return end
    pcall(function()
        if typeof(object) == "RBXScriptConnection" then object:Disconnect()
        elseif type(object) == "function" then object()
        elseif object.Destroy then object:Destroy() end
    end)
end
local function restore()
    for part, value in pairs(v.Hidden) do pcall(function() part.LocalTransparencyModifier = value end) end
    table.clear(v.Hidden)
end
local function clearRig()
    v.Epoch = v.Epoch + 1
    destroy(v.Render); v.Render = nil
    if v.PoseTrack then pcall(v.PoseTrack.Stop, v.PoseTrack, 0); destroy(v.PoseTrack); v.PoseTrack = nil end
    destroy(v.PoseAnimation); v.PoseAnimation = nil
    destroy(v.Rig); v.Rig = nil
    table.clear(v.Motors)
    restore()
end
local function strip(root)
    local objects = root:GetDescendants()
    table.insert(objects, root)
    for _, object in ipairs(objects) do
        if object:IsA("LuaSourceContainer") or object:IsA("Tool") or object:IsA("BillboardGui") or object:IsA("ForceField") or object:IsA("Sound") then
            object:Destroy()
        else
            for _, tag in ipairs(object:GetTags()) do object:RemoveTag(tag) end
            if object:IsA("BasePart") then
                object.CanCollide, object.CanTouch, object.CanQuery, object.Massless = false, false, false, true
                object.LocalTransparencyModifier = 0
            end
        end
    end
    for _, tag in ipairs(root:GetTags()) do root:RemoveTag(tag) end
    root:SetAttribute("_EquippedAura", nil)
end
local function wear(rig, id)
    local source = assets.Skins:FindFirstChild(id)
    assert(source and source:FindFirstChild("Body"), "Skin model is unavailable")
    local exemptions = {}
    for _, child in ipairs(source:GetChildren()) do
        if child:HasTag("SkinDisableBodyHide") then exemptions[child.Name] = true end
    end
    local body = source.Body:Clone()
    local previous = rig:FindFirstChild("Body")
    if previous then previous:Destroy() end
    strip(body)
    for _, object in ipairs(body:GetDescendants()) do
        if object:IsA("BasePart") then object.Anchored = false
        elseif object:IsA("JointInstance") then
            for _, key in ipairs({"Part0", "Part1"}) do
                local old = object[key]
                if old and not old:IsDescendantOf(body) then
                    local target = rig:FindFirstChild(old.Name)
                    if target and target:IsA("BasePart") then
                        object[key] = target
                        if not exemptions[target.Name] then
                            target.Transparency = 1
                            for _, part in ipairs(target:GetDescendants()) do
                                if part:IsA("BasePart") or part:IsA("Decal") then part.Transparency = 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    body.Parent = rig
end
local function matching(root, object, clone)
    local path = {}
    while object and object ~= root do table.insert(path, 1, object.Name); object = object.Parent end
    for _, name in ipairs(path) do clone = clone and clone:FindFirstChild(name) end
    return clone
end
rebuild = function()
    clearRig()
    local epoch = v.Epoch
    local character = LocalPlayer.Character
    if not v.Alive or not character or not (v.Choice.Skin or v.Choice.Pose) then return end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then return end
    local archivable = character.Archivable
    character.Archivable = true
    local ok, rig = pcall(character.Clone, character)
    character.Archivable = archivable
    if not ok or not rig then notify(rig or "Character model is unavailable"); return end
    if not v.Alive or epoch ~= v.Epoch or LocalPlayer.Character ~= character then destroy(rig); return end
    v.Rig = rig
    local success, failure = PrimeRuntime.Protect(function()
        rig.Name = "PRIME_LocalAppearance"
        strip(rig)
        for _, object in ipairs(character:GetDescendants()) do
            if object:IsA("Motor6D") then
                local copy = matching(character, object, rig)
                if copy and copy:IsA("Motor6D") then v.Motors[#v.Motors + 1] = {object, copy} end
            end
        end
        local copyRoot = rig:FindFirstChild("HumanoidRootPart")
        assert(copyRoot, "Character root is unavailable")
        for _, part in ipairs(rig:GetDescendants()) do
            if part:IsA("BasePart") then part.Anchored = part == copyRoot end
        end
        local copyHumanoid = rig:FindFirstChildOfClass("Humanoid")
        if copyHumanoid then copyHumanoid.EvaluateStateMachine = false; copyHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
        if v.Choice.Skin then wear(rig, v.Choice.Skin) end
        rig.PrimaryPart = copyRoot
        rig:PivotTo(character:GetPivot())
        rig.Parent = Workspace
        if v.Choice.Pose then
            local data = itemData[v.Choice.Pose]
            local id = data and data.UsageData and data.UsageData[1]
            assert(id, "Pose animation is unavailable")
            local animator = copyHumanoid and copyHumanoid:FindFirstChildOfClass("Animator")
            if not animator then
                local controller = copyHumanoid or Instance.new("AnimationController", rig)
                animator = Instance.new("Animator", controller)
            end
            local animation = Instance.new("Animation")
            v.PoseAnimation = animation
            animation.AnimationId = tostring(id):find("rbxassetid://", 1, true) and tostring(id) or "rbxassetid://" .. tostring(id)
            local track = animator:LoadAnimation(animation)
            if not v.Alive or epoch ~= v.Epoch or v.Rig ~= rig then destroy(track); return end
            v.PoseTrack = track
            track.Looped, track.Priority = true, Enum.AnimationPriority.Action
        end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then v.Hidden[part] = part.LocalTransparencyModifier; part.LocalTransparencyModifier = 1 end
        end
        v.Render = RunService.PreSimulation:Connect(function()
            if not v.Alive or LocalPlayer.Character ~= character or not root.Parent or not rig.Parent then return end
            copyRoot.CFrame = root.CFrame
            local idle = humanoid.Health > 0 and humanoid.MoveDirection.Magnitude < 0.05 and root.AssemblyLinearVelocity.Magnitude < 3
                and humanoid.FloorMaterial ~= Enum.Material.Air and not LocalPlayer:GetAttribute("isDeflecting")
            if v.PoseTrack then
                if idle and not v.PoseTrack.IsPlaying then v.PoseTrack:Play(0.12)
                elseif not idle and v.PoseTrack.IsPlaying then v.PoseTrack:Stop(0.1) end
            end
            if not (v.PoseTrack and idle) then
                for _, pair in ipairs(v.Motors) do if pair[1].Parent and pair[2].Parent then pair[2].Transform = pair[1].Transform end end
            end
            for part in pairs(v.Hidden) do if part.Parent then part.LocalTransparencyModifier = 1 else v.Hidden[part] = nil end end
        end)
    end)
    if not success then
        if epoch == v.Epoch then clearRig(); notify(failure) else destroy(rig) end
    end
end
local function clearAura()
    local state = v.Aura
    v.Aura = nil
    if not state then return end
    destroy(state.Connection)
    if not state.Character.Parent then return end
    if state.Original ~= nil then state.Character:SetAttribute("_EquippedAura", state.Original)
    else
        v.AuraReset = state
        state.Character:SetAttribute("_EquippedAura", "Default")
        task.defer(function()
            task.wait()
            if v.AuraReset == state and not v.Aura and state.Character.Parent and state.Character:GetAttribute("_EquippedAura") == "Default" then
                state.Character:SetAttribute("_EquippedAura", nil)
            end
            if v.AuraReset == state then v.AuraReset = nil end
        end)
    end
end
bindAura = function()
    local character = LocalPlayer.Character
    local state = v.Aura
    if state and state.Character == character and v.Choice.Aura then
        state.Busy = true; character:SetAttribute("_EquippedAura", v.Choice.Aura); state.Busy = false
        return
    end
    clearAura()
    if not v.Alive or not character or not v.Choice.Aura then return end
    local original = character:GetAttribute("_EquippedAura")
    if v.AuraReset and v.AuraReset.Character == character and original == "Default" then original = nil end
    v.AuraReset = nil
    state = {Character = character, Original = original}
    v.Aura = state
    state.Connection = character:GetAttributeChangedSignal("_EquippedAura"):Connect(function()
        if not v.Alive or v.Aura ~= state or state.Busy then return end
        local current = character:GetAttribute("_EquippedAura")
        if current ~= v.Choice.Aura then
            state.Original, state.Busy = current, true
            character:SetAttribute("_EquippedAura", v.Choice.Aura)
            state.Busy = false
        end
    end)
    state.Busy = true; character:SetAttribute("_EquippedAura", v.Choice.Aura); state.Busy = false
end
stopCinema = function()
    v.PendingFinisher = nil
    local state = v.Cinema
    v.Cinema = nil
    if not state then return end
    state.Alive = false
    destroy(state.Render)
    for _, track in ipairs(state.Tracks) do pcall(track.Stop, track, 0); destroy(track) end
    destroy(state.Native)
    destroy(state.Effect)
    destroy(state.Scene)
    if state.Camera and state.Camera.Parent and Workspace.CurrentCamera == state.Camera then
        state.Camera.CameraType, state.Camera.CameraSubject = state.Type, state.Subject
        state.Camera.CFrame, state.Camera.FieldOfView = state.CFrame, state.FOV
    end
end
local function cinema(id, source, target, token)
    if not v.Alive or v.PendingFinisher ~= token or v.Choice.Finisher ~= id then return end
    local prefab = ReplicatedStorage:FindFirstChild("Finishers")
    prefab = prefab and prefab:FindFirstChild(id)
    assert(prefab, "Finisher model is unavailable")
    local state = {Alive = true, Tracks = {}, Token = token}
    v.Cinema = state
    v.PendingFinisher = nil
    local scene = Instance.new("Model")
    state.Scene, scene.Name = scene, "PRIME_LocalFinisher"
    for _, child in ipairs(prefab:GetChildren()) do child:Clone().Parent = scene end
    local animated = scene:FindFirstChild("AnimatedObjects")
    local winner = animated and animated:FindFirstChild("Winner")
    local loser = animated and animated:FindFirstChild("Loser")
    assert(winner and loser, "Finisher characters are unavailable")
    local shift = CFrame.new(20000, 20000, 20000) * winner:GetPivot():Inverse()
    for _, object in ipairs(scene:GetDescendants()) do
        if object:IsA("BaseScript") then object:Destroy()
        elseif object:IsA("BasePart") then
            object.CanCollide, object.CanTouch, object.CanQuery = false, false, false
            local model = object:FindFirstAncestorOfClass("Model")
            local controller = model and (model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController"))
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("RootPart"))
            object.Anchored = not controller or object == root
            if object.Name == "ReferencePart" or object.Parent.Name:match("^Cam") then object.Transparency = 1 end
        end
    end
    if v.Choice.Skin then wear(winner, v.Choice.Skin) end
    local camera = Workspace.CurrentCamera
    if camera then
        state.Camera, state.Type, state.Subject = camera, camera.CameraType, camera.CameraSubject
        state.CFrame, state.FOV = camera.CFrame, camera.FieldOfView
    end
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local native = playerGui and playerGui:FindFirstChild("LocalFinisherHandler")
    native = native and native:FindFirstChild("Finisher")
    if native then
        local class = PrimeRuntime.Require(native)
        if not v.Alive or v.Cinema ~= state then destroy(scene); return end
        local instance = class(nil, nil, scene, CFrame.new(20000, 20000, 20000), {})
        if not v.Alive or v.Cinema ~= state then destroy(instance); return end
        state.Native, instance.ForceSkipped = instance, true
        local loaded = instance:Load()
        if not v.Alive or v.Cinema ~= state then destroy(instance); return end
        assert(loaded, "Finisher failed to load")
        instance._winnerCharacter, instance._loserCharacter = winner, loser
        instance:Play()
        if v.Cinema == state then stopCinema() end
        return
    end
    scene:PivotTo(shift * scene:GetPivot())
    scene.Parent = Workspace:FindFirstChild("FX") or Workspace
    if camera then camera.CameraType = Enum.CameraType.Scriptable end
    for _, object in ipairs(scene:GetDescendants()) do
        if object:IsA("Animation") and object.Parent:IsA("Animator") then
            local ok, track = pcall(object.Parent.LoadAnimation, object.Parent, object)
            if ok then
                if not v.Alive or v.Cinema ~= state then destroy(track); return end
                state.Tracks[#state.Tracks + 1] = track; track.Looped = false; track:Play(0)
            end
        end
    end
    local cameraPart
    for _, object in ipairs(animated:GetDescendants()) do
        if object:IsA("BasePart") and object.Name == "CamPart" then cameraPart = object; break end
    end
    local cameraData
    if prefab:FindFirstChild("CameraData") then local ok, data = PrimeRuntime.Protect(PrimeRuntime.Require, prefab.CameraData); if ok then cameraData = data end end
    if not v.Alive or v.Cinema ~= state then return end
    local fps = math.max(1, tonumber(prefab:GetAttribute("FPS")) or 60)
    local duration = math.clamp((tonumber(prefab:GetAttribute("Length")) or fps * 8) / fps, 1, 90)
    local timelines = {}
    for _, object in ipairs(scene:GetDescendants()) do
        for _, property in ipairs({"CFrame", "Size", "Transparency", "Color"}) do
            local raw = object:GetAttribute("_" .. property)
            if type(raw) == "string" then
                local points = {}
                for frame, text in raw:gmatch("([%d%.%-]+):([^|]+)") do
                    local numbers = {}
                    for number in text:gmatch("[^,]+") do numbers[#numbers + 1] = tonumber(number) end
                    local value
                    if property == "CFrame" and #numbers == 12 then value = shift * CFrame.new(table.unpack(numbers))
                    elseif property == "Size" and #numbers == 3 then value = Vector3.new(table.unpack(numbers))
                    elseif property == "Color" and #numbers == 3 then value = Color3.new(table.unpack(numbers))
                    elseif property == "Transparency" then value = numbers[1] end
                    if value ~= nil then points[#points + 1] = {tonumber(frame), value} end
                end
                table.sort(points, function(a, b) return a[1] < b[1] end)
                if #points > 0 then timelines[#timelines + 1] = {Object = object, Property = property, Points = points, Index = 1} end
            end
        end
    end
    local savedSound = prefab:FindFirstChild("Sound")
    if savedSound then
        local placeholder = scene:FindFirstChild("Sound")
        if placeholder then placeholder:Destroy() end
        local sound = savedSound:IsA("Sound") and savedSound:Clone() or Instance.new("Sound")
        sound.Name = "Sound"
        if not savedSound:IsA("Sound") then
            for key, value in pairs(savedSound:GetAttributes()) do pcall(function() sound[key] = value end) end
        end
        sound.Parent = scene
        sound:Play()
    end
    local started = os.clock()
    state.Render = RunService.RenderStepped:Connect(function()
        if not state.Alive or not v.Alive or v.Cinema ~= state then return end
        local elapsed = os.clock() - started
        if elapsed >= duration then stopCinema(); return end
        local position = elapsed * fps
        for _, timeline in ipairs(timelines) do
            local points = timeline.Points
            while timeline.Index < #points and points[timeline.Index + 1][1] <= position do timeline.Index = timeline.Index + 1 end
            local a, b = points[timeline.Index], points[math.min(timeline.Index + 1, #points)]
            local alpha = b[1] > a[1] and math.clamp((position - a[1]) / (b[1] - a[1]), 0, 1) or 0
            if timeline.Object.Parent then
                timeline.Object[timeline.Property] = type(a[2]) == "number" and a[2] + (b[2] - a[2]) * alpha or a[2]:Lerp(b[2], alpha)
            end
        end
        if camera and Workspace.CurrentCamera == camera then
            local frame = type(cameraData) == "table" and cameraData[math.floor(elapsed * fps)]
            local cf = typeof(frame) == "CFrame" and frame or type(frame) == "table" and (frame.CFrame or frame[1])
            if typeof(cf) == "CFrame" then camera.CFrame = shift * cf
            elseif cameraPart and cameraPart.Parent then camera.CFrame = cameraPart.CFrame
            else camera.CFrame = CFrame.lookAt(winner:GetPivot().Position + Vector3.new(8, 4, 8), winner:GetPivot().Position) end
        end
    end)
    if prefab:FindFirstChild("VFXClass") then
        local class = PrimeRuntime.Require(prefab.VFXClass)
        if not v.Alive or v.Cinema ~= state then return end
        state.Effect = class(scene, winner, loser, true)
        if v.Cinema ~= state then destroy(state.Effect) end
    end
end
local function playFinisher(source, target, manual)
    if not v.Alive or not v.Choice.Finisher or v.Cinema or v.PendingFinisher then return end
    if not manual and os.clock() < (v.NativeFinisherUntil or 0) then return end
    local id, token = v.Choice.Finisher, {}
    v.PendingFinisher = token
    task.spawn(function()
        local ok, failure = PrimeRuntime.Protect(cinema, id, source, target, token)
        local current = v.PendingFinisher == token or v.Cinema and v.Cinema.Token == token
        if v.PendingFinisher == token then v.PendingFinisher = nil end
        if not ok and current then stopCinema(); notify(failure) end
    end)
end
local deathHandler, originalDeath, deathWrapper, deathLoading
local function bindDeath()
    if deathWrapper or deathLoading then return end
    local handler = scripts:FindFirstChild("LocalDeathExplosions")
    handler = handler and handler:FindFirstChild("DeathExplosionHandler")
    assert(handler, "Client death effects are unavailable")
    deathLoading = true
    local ok, result = PrimeRuntime.Protect(PrimeRuntime.Require, handler)
    deathLoading = false
    if not ok then error(result, 0) end
    deathHandler = result
    if not v.Alive then return end
    originalDeath = deathHandler.Play
    deathWrapper = function(object, id, position, source, target, ...)
        local mine = source == LocalPlayer.Character
        if v.Alive and mine then
            id = v.Choice.Explosion or id
        end
        return originalDeath(object, id, position, source, target, ...)
    end
    deathHandler.Play = deathWrapper
end
local finisherBridge, finisherEvent
local function clearBridge()
    local state = finisherBridge
    finisherBridge = nil
    if not state then return end
    destroy(state.Connection)
    for _, connection in ipairs(state.Originals) do pcall(function() connection:Enable() end) end
end
local function bindFinisher()
    if not finisherEvent then
        local actions = PrimeRuntime.Require(ReplicatedStorage:WaitForChild("Actions", 10))
        if not v.Alive or not v.Choice.Finisher then return end
        finisherEvent = actions.DEATH_EXPLOSION_PLAY:Connect(function(_, _, source, target)
            if v.Alive and source == LocalPlayer.Character then playFinisher(source, target) end
        end)
    end
    if not v.Alive or not v.Choice.Finisher then return end
    clearBridge()
    local remote = ReplicatedStorage:FindFirstChild("FinisherRemote")
    if not remote or type(getconnections) ~= "function" then return end
    local state = {Originals = {}, Functions = {}}
    local ok, connections = pcall(getconnections, remote.OnClientEvent)
    if not ok or type(connections) ~= "table" then return end
    for _, connection in ipairs(connections) do
        pcall(function()
            if type(connection.Function) == "function" and connection.Enabled ~= false and connection.Connected ~= false
                and type(connection.Disable) == "function" and type(connection.Enable) == "function" then
                connection:Disable()
                state.Originals[#state.Originals + 1] = connection
                state.Functions[#state.Functions + 1] = connection.Function
            end
        end)
    end
    if #state.Functions == 0 then return end
    finisherBridge = state
    state.Connection = remote.OnClientEvent:Connect(function(...)
        local args, mine = table.pack(...), false
        for index = 1, args.n do
            local value = args[index]
            if value == LocalPlayer or value == LocalPlayer.Character or value == LocalPlayer.UserId or value == LocalPlayer.Name then mine = true end
            if type(value) == "table" and (value.Winner == LocalPlayer or value.Source == LocalPlayer.Character or value.WinnerUserId == LocalPlayer.UserId) then mine = true end
        end
        if v.Alive and v.Choice.Finisher and mine then
            local remapped = false
            for index = 1, args.n do
                local value = args[index]
                if type(value) == "string" and ReplicatedStorage.Finishers:FindFirstChild(value) then args[index] = v.Choice.Finisher; remapped = true
                elseif type(value) == "table" then
                    local copy
                    for _, key in ipairs({"Finisher", "FinisherId"}) do
                        if type(value[key]) == "string" and ReplicatedStorage.Finishers:FindFirstChild(value[key]) then
                            copy = copy or table.clone(value); copy[key] = v.Choice.Finisher; remapped = true
                        end
                    end
                    args[index] = copy or value
                end
            end
            if remapped then
                stopCinema()
                local model = ReplicatedStorage.Finishers:FindFirstChild(v.Choice.Finisher)
                local duration = model and (tonumber(model:GetAttribute("Length")) or 480) / math.max(1, tonumber(model:GetAttribute("FPS")) or 60) or 8
                v.NativeFinisherUntil = os.clock() + math.clamp(duration, 1, 90)
            end
        end
        for _, callback in ipairs(state.Functions) do task.spawn(callback, table.unpack(args, 1, args.n)) end
    end)
end
local definitions = {{"Skin", "Skin Changer"}, {"Aura", "Aura Changer"}, {"Pose", "Pose Changer"}, {"Explosion", "Death Explosion Changer"}, {"Finisher", "Finisher Changer"}}
local function catalog(kind)
    local values, map = {"Default"}, {}
    local source = kind == "Skin" and skinData or itemData
    for id, data in pairs(source) do
        if type(id) == "string" and type(data) == "table" and (kind == "Skin" or data.Category == kind) and not data.IsHidden then
            local valid = true
            if kind == "Skin" then valid = assets:FindFirstChild("Skins") and assets.Skins:FindFirstChild(id)
            elseif kind == "Finisher" then valid = ReplicatedStorage:FindFirstChild("Finishers") and ReplicatedStorage.Finishers:FindFirstChild(id)
            elseif kind == "Pose" then valid = data.UsageData and data.UsageData[1] end
            if valid then
                local name = tostring(data.DisplayName or id)
                if map[name] then name = name .. " (" .. id .. ")" end
                map[name], values[#values + 1] = id, name
            end
        end
    end
    table.sort(values, function(a, b) if a == "Default" then return b ~= "Default" elseif b == "Default" then return false end return a:lower() < b:lower() end)
    return values, map
end
for _, entry in ipairs(definitions) do
    local kind, title = entry[1], entry[2]
    lists[kind], maps[kind] = catalog(kind)
    Tabs.Visual:AddDropdown("Visual" .. kind, {Title = title, Values = lists[kind], Default = "Default", Callback = function(value)
        if not v.Alive or PrimeRuntime.IsShuttingDown then return end
        v.Choice[kind] = maps[kind][value]
        if kind == "Skin" or kind == "Pose" then rebuild()
        elseif kind == "Aura" then bindAura()
        else
            if kind == "Finisher" then v.NativeFinisherUntil = nil; stopCinema(); clearBridge() end
            if v.Choice[kind] then
                local ok, failure = PrimeRuntime.Protect(bindDeath)
                if ok and kind == "Finisher" then ok, failure = PrimeRuntime.Protect(bindFinisher) end
                if not ok then v.Choice[kind] = nil; notify(failure) end
            end
        end
    end})
end
Tabs.Visual:AddButton({Title = "Preview Death Explosion", Callback = function()
    if not v.Alive or not v.Choice.Explosion then return end
    local id = v.Choice.Explosion
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    task.spawn(function()
        local ok, failure = PrimeRuntime.Protect(function()
            local handler = scripts:FindFirstChild("LocalDeathExplosions")
            local base = handler and handler:FindFirstChild("BaseExplosion")
            local module = base and base:FindFirstChild(id)
            assert(module, "Explosion model is unavailable")
            local class = PrimeRuntime.Require(module)
            if not v.Alive or v.Choice.Explosion ~= id or not root.Parent or character ~= LocalPlayer.Character then return end
            local effect = class(root.Position, character, character, id)
            if not v.Alive then destroy(effect); return end
            v.Effects[effect] = true
            task.delay(15, function() if v.Effects[effect] then v.Effects[effect] = nil; destroy(effect) end end)
        end)
        if not ok then notify(failure) end
    end)
end})
Tabs.Visual:AddButton({Title = "Preview Finisher", Callback = function() playFinisher(LocalPlayer.Character, LocalPlayer.Character, true) end})
Tabs.Visual:AddButton({Title = "Stop Preview", Callback = stopCinema})
TrackRuntimeConnection(LocalPlayer.CharacterRemoving:Connect(function() clearRig(); clearAura(); stopCinema() end))
TrackRuntimeConnection(LocalPlayer.CharacterAdded:Connect(function(character)
    task.spawn(function()
        local root = character:WaitForChild("HumanoidRootPart", 10)
        if root and v.Alive and LocalPlayer.Character == character then rebuild(); bindAura() end
    end)
end))
TrackRuntimeConnection(LocalPlayer.CharacterAppearanceLoaded:Connect(function(character)
    if v.Alive and LocalPlayer.Character == character then rebuild() end
end))
TrackRuntimeCleanup(function()
    v.Alive = false
    clearRig(); clearAura(); stopCinema(); clearBridge(); destroy(finisherEvent)
    if deathHandler and deathHandler.Play == deathWrapper then deathHandler.Play = originalDeath end
    for effect in pairs(v.Effects) do destroy(effect) end
    table.clear(v.Effects)
end)
