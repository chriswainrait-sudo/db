local v = {Alive = true, Choice = {}}
local assets = ReplicatedStorage:WaitForChild("Assets", 10)
local bins = ReplicatedStorage:WaitForChild("DataBins", 10)
local scripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
local skinData = PrimeRuntime.Require(bins:WaitForChild("SkinData", 10))
local itemModule = bins:WaitForChild("ItemData", 10)
local itemData = PrimeRuntime.Require(itemModule:FindFirstChild("SheetItemData") or itemModule)
local function destroy(object)
    if object then pcall(function()
        if typeof(object) == "RBXScriptConnection" then object:Disconnect()
        elseif object.Destroy then object:Destroy() end
    end) end
end
local function notify(failure)
    if v.Alive then NexusUI:Notify({Title = "Visual", Content = tostring(failure), Duration = 5}) end
end
local function clear(kind)
    local state = v[kind]
    v[kind] = nil
    if not state then return end
    destroy(state.Connection)
    if state.Track then pcall(state.Track.Stop, state.Track, 0.1); destroy(state.Track) end
    destroy(state.Animation)
    destroy(state.Effect)
    destroy(state.Body)
    for object, values in pairs(state.Hidden or {}) do pcall(function()
        for property, value in pairs(values) do object[property] = value end
    end) end
end
local function current(kind, state)
    return v.Alive and v[kind] == state and LocalPlayer.Character == state.Character and state.Character.Parent ~= nil
end
local function moduleAt(handler, group, id)
    local root = scripts:FindFirstChild(handler)
    root = root and root:FindFirstChild(group)
    local module = root and root:FindFirstChild(id)
    assert(module and module:IsA("ModuleScript"), "Missing visual module: " .. tostring(id))
    return module
end
local function hide(state, object)
    local property = object:IsA("BasePart") and "LocalTransparencyModifier" or (object:IsA("Decal") or object:IsA("Texture")) and "Transparency"
    if property then
        state.Hidden[object] = state.Hidden[object] or {}
        if state.Hidden[object][property] == nil then state.Hidden[object][property] = object[property] end
        object[property] = 1
    end
end
local function skin(state, id)
    local source = assets:FindFirstChild("Skins")
    source = source and source:FindFirstChild(id)
    assert(source and source:FindFirstChild("Body"), "Skin model is unavailable")
    local character, exceptions = state.Character, {}
    for _, part in ipairs(source:GetChildren()) do
        if part:HasTag("SkinDisableBodyHide") then exceptions[part.Name] = true end
    end
    local body = source.Body:Clone()
    state.Body = body
    body.Name = "PRIME_LocalSkin"
    local hidden = {}
    for _, object in ipairs(body:GetDescendants()) do
        if object:IsA("LuaSourceContainer") then object:Destroy()
        elseif object:IsA("BasePart") then
            object.Anchored, object.CanCollide, object.CanTouch, object.CanQuery, object.Massless = false, false, false, false, true
        elseif object:IsA("JointInstance") then
            for _, property in ipairs({"Part0", "Part1"}) do
                local original = object[property]
                if original and not original:IsDescendantOf(body) then
                    local target = character:FindFirstChild(original.Name)
                    assert(target and target:IsA("BasePart"), "Skin requires body part: " .. original.Name)
                    object[property] = target
                    if not exceptions[target.Name] then hidden[target] = true end
                end
            end
        end
    end
    if not current("Skin", state) then destroy(body); return end
    for target in pairs(hidden) do
        hide(state, target)
        for _, child in ipairs(target:GetDescendants()) do hide(state, child) end
    end
    local previous = character:FindFirstChild("Body")
    if previous then for _, object in ipairs(previous:GetDescendants()) do hide(state, object) end end
    body.Parent = character
end
local function aura(state, id)
    local class = PrimeRuntime.Require(moduleAt("LocalAuraHandler", "Aura", "BaseAura"):WaitForChild(id, 10))
    if not current("Aura", state) then return end
    local effect = class(state.Character, true, id)
    if not current("Aura", state) then destroy(effect); return end
    state.Effect = effect
    if effect.Update then
        state.Connection = RunService.RenderStepped:Connect(function(dt)
            if not current("Aura", state) then return end
            local ok, failure = pcall(effect.Update, effect, dt)
            if not ok then clear("Aura"); notify(failure) end
        end)
    end
end
local function pose(state, id)
    local character = state.Character
    local humanoid = character:WaitForChild("Humanoid", 10)
    local animator = humanoid and humanoid:WaitForChild("Animator", 10)
    if not current("Pose", state) then return end
    assert(animator, "Character animator is unavailable")
    local data = itemData[id]
    local animationId = data and data.UsageData and tostring(data.UsageData[1]):match("%d+")
    assert(animationId, "Pose animation is unavailable")

    local animation = Instance.new("Animation")
    animation.AnimationId = "rbxassetid://" .. animationId
    state.Animation = animation
    local track = animator:LoadAnimation(animation)
    state.Track = track
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true

    state.Connection = RunService.PreAnimation:Connect(function()
        if not current("Pose", state) then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        local velocity = root and root.AssemblyLinearVelocity
        local idle = velocity and humanoid.Health > 0 and not humanoid.Sit
            and humanoid.MoveDirection.Magnitude < 0.05
            and Vector3.new(velocity.X, 0, velocity.Z).Magnitude < 2
            and humanoid.FloorMaterial ~= Enum.Material.Air
            and not LocalPlayer:GetAttribute("isDeflecting") and not character:GetAttribute("isDeflecting")
        if idle then
            for _, other in ipairs(animator:GetPlayingAnimationTracks()) do
                local priority = other.Priority
                if other ~= track and priority ~= Enum.AnimationPriority.Core
                    and priority.Value >= Enum.AnimationPriority.Action.Value then
                    idle = false
                    break
                end
            end
        end
        if idle and not track.IsPlaying then track:Play(0.15)
        elseif not idle and track.IsPlaying then track:Stop(0.1) end
    end)
end

local apply
apply = function(kind)
    clear(kind)
    local character, id = LocalPlayer.Character, v.Choice[kind]
    if not v.Alive or not character or not id then return end
    local state = {Character = character, Hidden = {}}
    v[kind] = state
    task.spawn(function()
        local ok, failure = PrimeRuntime.Protect(function()
            local root = character:WaitForChild("HumanoidRootPart", 10)
            if not root or not current(kind, state) then return end
            if kind == "Skin" then skin(state, id)
            elseif kind == "Aura" then aura(state, id)
            else pose(state, id) end
        end)
        if not ok and current(kind, state) then clear(kind); notify(failure) end
    end)
end
local function characterOf(value)
    if typeof(value) ~= "Instance" then
        if value == LocalPlayer.UserId or value == LocalPlayer.Name then return LocalPlayer.Character end
        return nil
    end
    if value:IsA("Player") then return value.Character end
    if value:IsA("Model") then return value end
end
local function mine(source)
    local character = LocalPlayer.Character
    return character ~= nil and source ~= nil and characterOf(source) == character
end
local deathHandler, originalDeath, deathWrapper
local function bindDeath()
    if deathWrapper then return end
    local handler = scripts:WaitForChild("LocalDeathExplosions", 10)
    local module = handler and handler:WaitForChild("DeathExplosionHandler", 5)
    local result = PrimeRuntime.Require(module)
    local deferred = ReplicatedFirst:FindFirstChild("DeferredContent")
    local moduleArt = deferred and deferred:FindFirstChild("ModuleArt")
    local art = moduleArt and PrimeRuntime.Require(moduleArt)
    if not v.Alive or deathWrapper then return end
    local playForSettings, play = result.PlayForSettings, result.Play
    local base = handler:FindFirstChild("BaseExplosion")
    assert(type(playForSettings) == "function" and type(play) == "function", "Death explosion handler is unavailable")

    local function wrapper(object, id, position, source, target, ...)
        local selected = v.Choice.Explosion
        local effect = selected and base and base:FindFirstChild(selected)
        if v.Alive and effect and mine(source) then
            local pending = art and art.IsPending(effect)
            local effectId = pending and id or selected
            local ok, failure = PrimeRuntime.Protect(play, object, effectId, position, characterOf(source), characterOf(target))
            if ok then return end
            notify(failure)
        end
        return playForSettings(object, id, position, source, target, ...)
    end

    result.PlayForSettings = wrapper
    deathHandler, originalDeath, deathWrapper = result, playForSettings, wrapper
end
local definitions = {{"Skin", "Skin Changer"}, {"Aura", "Aura Changer"}, {"Pose", "Pose Changer"}, {"Explosion", "Death Explosion Changer"}}
local maps = {}
for _, entry in ipairs(definitions) do
    local kind, title = entry[1], entry[2]
    local values, map = {"Default"}, {}
    local source = kind == "Skin" and skinData or itemData
    for id, data in pairs(source) do
        if type(id) == "string" and type(data) == "table" and (kind == "Skin" or data.Category == kind) and not data.IsHidden then
            local valid = true
            if kind == "Skin" then valid = assets:FindFirstChild("Skins") and assets.Skins:FindFirstChild(id)
            elseif kind == "Aura" then
                local root = scripts:FindFirstChild("LocalAuraHandler")
                root = root and root:FindFirstChild("Aura")
                root = root and root:FindFirstChild("BaseAura")
                valid = root and root:FindFirstChild(id)
            elseif kind == "Explosion" then
                local root = scripts:FindFirstChild("LocalDeathExplosions")
                root = root and root:FindFirstChild("BaseExplosion")
                valid = root and root:FindFirstChild(id)
            else valid = data.UsageData and data.UsageData[1] end
            if valid then
                local name = tostring(data.DisplayName or id)
                if map[name] then name = name .. " (" .. id .. ")" end
                map[name], values[#values + 1] = id, name
            end
        end
    end
    table.sort(values, function(a, b) if a == "Default" then return b ~= "Default" elseif b == "Default" then return false end return a:lower() < b:lower() end)
    maps[kind] = map
    Tabs.Visual:AddDropdown("Visual" .. kind, {Title = title, Values = values, Default = "Default", Callback = function(value)
        if not v.Alive or PrimeRuntime.IsShuttingDown then return end
        v.Choice[kind] = map[value]
        if kind ~= "Explosion" then apply(kind)
        elseif v.Choice.Explosion then
            task.spawn(function()
                local ok, failure = PrimeRuntime.Protect(bindDeath)
                if not ok then notify(failure) end
            end)
        end
    end})
end
TrackRuntimeConnection(LocalPlayer.CharacterRemoving:Connect(function()
    for _, kind in ipairs({"Skin", "Pose", "Aura"}) do clear(kind) end
end))
TrackRuntimeConnection(LocalPlayer.CharacterAdded:Connect(function()
    for _, kind in ipairs({"Skin", "Pose", "Aura"}) do apply(kind) end
end))
TrackRuntimeConnection(LocalPlayer.CharacterAppearanceLoaded:Connect(function(character)
    if v.Alive and LocalPlayer.Character == character then apply("Skin") end
end))
TrackRuntimeCleanup(function()
    v.Alive = false
    for _, kind in ipairs({"Skin", "Pose", "Aura"}) do clear(kind) end
    if deathHandler and deathHandler.PlayForSettings == deathWrapper then
        deathHandler.PlayForSettings = originalDeath
    end
end)

do
    local colors = {
        Cyan = Color3.fromRGB(75, 225, 255),
        Crimson = Color3.fromRGB(255, 65, 95),
        Silver = Color3.fromRGB(235, 242, 255),
    }
    local selected, connection, flash, generation
    generation = 0
    local tweenService = game:GetService("TweenService")

    local function clearFlash()
        if flash then flash:Destroy(); flash = nil end
    end

    local function changeEffect(value)
        generation = generation + 1
        local token = generation
        selected = colors[value]
        clearFlash()
        if connection then connection:Disconnect(); connection = nil end
        if not selected or not v.Alive then return end

        task.spawn(function()
            local ok, failure = PrimeRuntime.Protect(function()
                local actions = PrimeRuntime.Require(ReplicatedStorage:FindFirstChild("Actions"))
                if token ~= generation or not v.Alive then return end
                connection = actions.DEFLECT_RESULT:Connect(function(failed)
                    if failed or token ~= generation or not v.Alive then return end
                    local character = LocalPlayer.Character
                    if not character or not character.Parent then return end
                    clearFlash()
                    local effect = Instance.new("Highlight")
                    effect.Name = "DeathBallParryFlash"
                    effect.Adornee = character
                    effect.DepthMode = Enum.HighlightDepthMode.Occluded
                    effect.FillColor, effect.OutlineColor = selected, selected
                    effect.FillTransparency, effect.OutlineTransparency = 0.28, 0.05
                    effect.Parent = character
                    flash = effect
                    tweenService:Create(effect, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                        FillTransparency = 1,
                        OutlineTransparency = 1,
                    }):Play()
                    task.delay(0.34, function()
                        if flash == effect then clearFlash() end
                    end)
                end)
            end)
            if not ok and token == generation then notify(failure) end
        end)
    end

    Tabs.Visual:AddDropdown("VisualHitEffect", {
        Title = "Hit Effect Changer",
        Values = {"Default", "Cyan", "Crimson", "Silver"},
        Default = "Default",
        Callback = changeEffect,
    })
    TrackRuntimeConnection(LocalPlayer.CharacterRemoving:Connect(clearFlash))
    TrackRuntimeCleanup(function() changeEffect("Default") end)
end

do
    local soundService = game:GetService("SoundService")
    local packages = soundService:FindFirstChild("Packages")
    local nonPreload = packages and packages:FindFirstChild("NonPreload")
    local enchants = nonPreload and nonPreload:FindFirstChild("DeflectSounds")
    local swords = assets:FindFirstChild("Swords")
    local names = {"Default", "Frost", "Fire", "Wind", "Electric", "Prism", "Deagle", "Uzi", "Fire Dragon Bow"}
    local sources, impactKeys = {}, {Deflect = true, DeflectImpact = true, DeflectImpactPerfect = true}
    if enchants then
        for _, sound in ipairs(enchants:GetChildren()) do
            if sound:IsA("Sound") then impactKeys[sound.Name] = true end
        end
    end
    for index, name in ipairs(names) do
        if index >= 2 and index <= 6 then
            sources[name] = enchants and enchants:FindFirstChild("Deflect" .. name)
        elseif index >= 7 then
            local sword = swords and swords:FindFirstChild(name)
            local sounds = sword and sword:FindFirstChild("Sounds")
            sources[name] = sounds and sounds:FindFirstChild("Deflect")
        end
    end

    local selected, channel, original, wrapper
    local generation = 0

    local function changeSound(value)
        generation = generation + 1
        local token = generation
        selected = sources[value]
        if channel and channel.PlayAt == wrapper then channel.PlayAt = original end
        channel, original, wrapper = nil, nil, nil
        if not selected or not v.Alive then return end

        task.spawn(function()
            local ok, failure = PrimeRuntime.Protect(function()
                local core = ReplicatedFirst:FindFirstChild("Core")
                local audio = PrimeRuntime.Require(core and core:FindFirstChild("Audio"))
                if token ~= generation or not v.Alive then return end
                local gameplay, replacement = audio.Gameplay, selected
                local playAt = gameplay.PlayAt
                local function replaceImpact(object, source, position, ...)
                    local character = LocalPlayer.Character
                    local key = typeof(source) == "Instance" and source.Name or source
                    if object == gameplay and impactKeys[key] and character and typeof(position) == "Instance"
                        and position:IsDescendantOf(character) then
                        return playAt(object, replacement, position, ...)
                    end
                    return playAt(object, source, position, ...)
                end
                gameplay.PlayAt = replaceImpact
                channel, original, wrapper = gameplay, playAt, replaceImpact

            end)
            if not ok and token == generation then notify(failure) end
        end)
    end

    Tabs.Visual:AddDropdown("VisualParrySound", {
        Title = "Parry Sound",
        Values = names,
        Default = "Default",
        Callback = changeSound,
    })
    TrackRuntimeCleanup(function() changeSound("Default") end)
end

do
    local lighting = game:GetService("Lighting")
    local faces = {"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp"}
    local presets = {
        Pink = {
            Color3.fromRGB(255, 175, 218), Color3.fromRGB(143, 88, 135),
            {151165214, 151165197, 151165224, 151165191, 151165206, 151165227},
        },
        Green = {
            Color3.fromRGB(175, 240, 173), Color3.fromRGB(68, 113, 79),
            {11941775243, 11941774975, 11941774655, 11941774369, 11941774042, 11941773718},
        },
        Red = {
            Color3.fromRGB(255, 148, 142), Color3.fromRGB(139, 63, 72),
            {108929045660200, 78646480540009, 90546017435179, 109838453114563, 94190734796082, 126944775797063},
        },
    }
    local sky, fog, parked, watcher

    local function restoreAtmosphere()
        if watcher then watcher:Disconnect(); watcher = nil end
        destroy(sky)
        destroy(fog)
        sky, fog = nil, nil
        if parked then
            for _, object in ipairs(parked:GetChildren()) do object.Parent = lighting end
            parked:Destroy()
            parked = nil
        end
    end

    local function applyAtmosphere(value)
        local preset = presets[value]
        if not v.Alive or not preset then restoreAtmosphere(); return end
        if not sky then
            parked = Instance.new("Folder")
            sky, fog = Instance.new("Sky"), Instance.new("Atmosphere")
            sky.Name, fog.Name = "DeathBallPresetSky", "DeathBallPresetFog"
            sky.CelestialBodiesShown = false
            sky.StarCount = 0
            fog.Density = 0.28
            fog.Offset = 0.23
            fog.Haze = 2.45
            fog.Glare = 0.08
            local function park(object)
                if object ~= sky and object ~= fog and (object:IsA("Sky") or object:IsA("Atmosphere")) then
                    object.Parent = parked
                end
            end
            for _, object in ipairs(lighting:GetChildren()) do park(object) end
            watcher = lighting.ChildAdded:Connect(park)
        end
        fog.Color, fog.Decay = preset[1], preset[2]
        for index, property in ipairs(faces) do sky[property] = "rbxassetid://" .. preset[3][index] end
        sky.Parent, fog.Parent = lighting, lighting
    end

    Tabs.Visual:AddDropdown("VisualAtmosphere", {
        Title = "Atmosphere",
        Values = {"Default", "Pink", "Green", "Red"},
        Default = "Default",
        Callback = applyAtmosphere,
    })
    TrackRuntimeCleanup(restoreAtmosphere)
end
