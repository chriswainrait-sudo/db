Window:SelectTab(1)
local screen = UIEnvironment.GuiParent:FindFirstChild("NexusDeathBallUI")
assert(screen, "Death Ball: GUI root is unavailable")
TrackRuntimeConnection(screen.AncestryChanged:Connect(function(_, parent)
    if not parent and not PrimeRuntime.IsShuttingDown then Shutdown() end
end))
TrackRuntimeConnection(LocalPlayer.AncestryChanged:Connect(function(_, parent)
    if not parent and not PrimeRuntime.IsShuttingDown then Shutdown() end
end))
