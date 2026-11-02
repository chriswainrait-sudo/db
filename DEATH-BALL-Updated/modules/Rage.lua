local rageConnections = {}
local originalStates = { InfJump = nil, NoDash = nil, NoParry = nil }

local function GetPlayerControl()
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local Classes = ReplicatedFirst:FindFirstChild("Classes")
    if not Classes then return nil end
    local PlayerControl = Classes:FindFirstChild("PlayerControl")
    if not PlayerControl then return nil end
    local success, result = PrimeRuntime.Protect(require, PlayerControl)
    if success then return result end
    return nil
end

local function ToggleLoop(name, callback)
    if rageConnections[name] then rageConnections[name]:Disconnect(); rageConnections[name] = nil end
    if callback then rageConnections[name] = RunService.Heartbeat:Connect(callback) end
end

Tabs.Rage:AddToggle("InfiniteDoubleJump", {
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

Tabs.Rage:AddToggle("NoDashCooldown", {
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

Tabs.Rage:AddToggle("NoParryCooldown", {
    Title = "Infinite Parry",
    Description = "Removes parry cooldown for constant defense capability",
    Default = false,
    Callback = function(Value)
        local control = GetPlayerControl()
        if Value then
            if not control or not control.Sword then return end
            originalStates.NoParry = originalStates.NoParry or {Sword = control.Sword, Cooldown = control.Sword.Cooldown, Ready = control.Sword.Ready}
            ToggleLoop("NoParry", function()
                if control and control.Sword and control.Sword.Cooldown == true then
                    control.Sword.Cooldown = false
                    control.Sword.Ready = true
                end
            end)
        else
            ToggleLoop("NoParry", nil)
            local original = originalStates.NoParry
            originalStates.NoParry = nil
            if original then original.Sword.Cooldown, original.Sword.Ready = original.Cooldown, original.Ready end
        end
    end
})


TrackRuntimeCleanup(function()
    for _, id in ipairs({"InfiniteDoubleJump", "NoDashCooldown", "NoParryCooldown"}) do
        local option = Options[id]
        if option then pcall(option.SetValue, option, false) end
    end
    for _, connection in pairs(rageConnections) do connection:Disconnect() end
    table.clear(rageConnections)
end)
