local swordPreview
local swordPreviewEnv = getgenv and getgenv() or _G
if swordPreviewEnv.PRIME_SWORD_PREVIEW then
    pcall(function() swordPreviewEnv.PRIME_SWORD_PREVIEW:Destroy() end)
end

local function createSwordPreview()
    local state = { Active = true }
    local ui, page, assets, catalog, inventoryApi, grid, cardClass
    local records, cards, patches, connections, hidden = {}, {}, {}, {}, {}
    local model, selected, offset, folder, sourceSword
    local folderConnection, renderConnection
    local function inventoryData()
        return inventoryApi and inventoryApi:Get() or ui.Inventory
    end
    local function refreshPage()
        if grid then
            grid:Update(true)
        else
            page:GetInvTable()
            page:CreateAndFilterSortedList(true)
        end
    end

    local function patch(object, key, value)
        patches[#patches + 1] = { object, key, rawget(object, key), value }
        object[key] = value
    end

    local function restoreVisibility()
        for object, entry in pairs(hidden) do
            pcall(function() object[entry[1]] = entry[2] end)
        end
        table.clear(hidden)
    end

    local function hide(object)
        if not model or hidden[object] then return end
        local property
        if object:IsA("BasePart") then
            property = "LocalTransparencyModifier"
        elseif object:IsA("Decal") then
            property = "Transparency"
        elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
            property = "Enabled"
        end
        if property then
            hidden[object] = { property, object[property] }
            if property == "Enabled" then object[property] = false else object[property] = 1 end
            if object:IsA("ParticleEmitter") then object:Clear() end
        end
    end

    local function bindFolder(value)
        if folderConnection then folderConnection:Disconnect(); folderConnection = nil end
        restoreVisibility()
        folder, sourceSword = value, nil
        if not folder then return end
        sourceSword = folder:FindFirstChild("Sword")
        for _, object in ipairs(folder:GetDescendants()) do hide(object) end
        folderConnection = folder.DescendantAdded:Connect(function(object)
            if object.Name == "Sword" and object:IsA("BasePart") then sourceSword = object end
            hide(object)
        end)
    end

    local function clearModel()
        if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
        if model then model:Destroy(); model = nil end
        selected, offset = nil, nil
        restoreVisibility()
    end

    local function targetCFrame()
        local character = LocalPlayer.Character
        if not character then return nil end
        if sourceSword and sourceSword.Parent and sourceSword:IsA("BasePart") then
            local weld = sourceSword:FindFirstChild("Weld")
            if weld and weld:IsA("JointInstance") and weld.Part0 == sourceSword
                and weld.Part1 and weld.Part1:IsDescendantOf(character) then
                return weld.Part1.CFrame * offset * weld.C0:Inverse()
            end
        end
        local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
        return hand and hand.CFrame * offset
    end

    local function equip(id)
        local data = records[id]
        if not state.Active or not data then return end
        local asset = assets:FindFirstChild(data.Type)
        local original = asset and asset:FindFirstChild("Sword")
        assert(original and original:IsA("BasePart"), "Sword model is unavailable")
        local nextModel = Instance.new("Model")
        nextModel.Name = "PRIME_SwordPreview"
        local ok, err = pcall(function()
            local root = original:Clone()
            root.Parent = nextModel
            root.PivotOffset = CFrame.identity
            nextModel.PrimaryPart = root
            for _, object in ipairs(nextModel:GetDescendants()) do
                if object:IsA("LuaSourceContainer") or object:IsA("JointInstance") or object:IsA("WeldConstraint") then
                    object:Destroy()
                elseif object:IsA("BasePart") then
                    object.Anchored = true
                    object.CanCollide = false
                    object.CanTouch = false
                    object.CanQuery = false
                    object.Massless = true
                end
            end
        end)
        if not ok then nextModel:Destroy(); error(err) end
        clearModel()
        local value = asset:FindFirstChild("Offset")
        offset = value and value:IsA("CFrameValue") and value.Value or CFrame.new(0, -1, 0)
        model, selected = nextModel, id
        local cf = targetCFrame()
        if cf then model:PivotTo(cf); model.Parent = Workspace end
        if folder then
            for _, object in ipairs(folder:GetDescendants()) do hide(object) end
        end
        renderConnection = RunService.RenderStepped:Connect(function()
            if not state.Active or not model then return end
            local target = targetCFrame()
            if target then
                model:PivotTo(target)
                if not model.Parent then model.Parent = Workspace end
            else
                model.Parent = nil
            end
            for object, entry in pairs(hidden) do
                if object.Parent then
                    if entry[1] == "Enabled" then object[entry[1]] = false else object[entry[1]] = 1 end
                else
                    hidden[object] = nil
                end
            end
        end)
        page:UpdateUI()
    end

    function state:Destroy()
        if not self.Active then return end
        self.Active = false
        clearModel()
        if folderConnection then folderConnection:Disconnect(); folderConnection = nil end
        for _, connection in ipairs(connections) do connection:Disconnect() end
        local previewSelected = page and records[page.SelectedId] ~= nil
        for i = #patches, 1, -1 do
            local entry = patches[i]
            if entry[1][entry[2]] == entry[4] then entry[1][entry[2]] = entry[3] end
        end
        for id, card in pairs(cards) do
            if grid then
                if grid.AllClasses[id] == card then
                    grid.AllClasses[id] = nil
                    grid._itemTypeOf[id] = nil
                    grid.maid["item_" .. id] = nil
                end
            else
                if page and page.AllItems[id] and page.AllItems[id].Class == card then
                    page.AllItems[id] = nil
                end
                pcall(function() card:Destroy() end)
            end
        end
        if page then
            if previewSelected then
                page.SelectedId = (inventoryData().EquippedSwords or {})[1] or ""
                page._previousClass = nil
            end
            pcall(function()
                refreshPage()
                page._focusDisplay:Update(page:_getClassFromId(page.SelectedId))
                page:UpdateUI()
            end)
        end
        if swordPreviewEnv.PRIME_SWORD_PREVIEW == self then swordPreviewEnv.PRIME_SWORD_PREVIEW = nil end
        table.clear(cards)
        table.clear(records)
    end

    function state:Start()
        ui = PrimeRuntime.Require(ReplicatedFirst:WaitForChild("ui", 15))
        local core = ReplicatedFirst:FindFirstChild("Core")
        local invModule = core and core:FindFirstChild("Inventory")
        if invModule and ui.RegisteredPages then inventoryApi = PrimeRuntime.Require(invModule) end
        local deadline = os.clock() + 30
        repeat
            if not self.Active then return end
            local pages = ui.RegisteredPages or ui.AllUI or {}
            local inventory = pages.InventoryPage
            page = inventory and inventory.AllPages and inventory.AllPages.Swords
            page = page or pages.SwordPage
            if page and page.EquipButton and page._focusDisplay and (page.Grid or page._isReadyToSort) then break end
            task.wait(0.1)
        until os.clock() >= deadline
        assert(page and page.EquipButton and page._focusDisplay and (page.Grid or page._isReadyToSort), "Sword inventory is not ready")
        if not self.Active then return end
        assets = ReplicatedStorage.Assets.Swords
        catalog = PrimeRuntime.Require(ReplicatedStorage.DataBins.SwordData)
        assert(type(inventoryData().Swords) == "table", "Sword inventory is unavailable")
        grid = page.Grid
        if grid then
            cardClass = PrimeRuntime.Require(ui.Injected:WaitForChild("SwordGridButton", 15))
            local getSource = grid.GetItemSource
            patch(grid, "GetItemSource", function(object, ...)
                local source = table.clone(getSource(object, ...))
                source.Swords = table.clone(source.Swords or {})
                for id, data in pairs(records) do source.Swords[id] = data end
                return source
            end)
        else
            local getInventory = page.GetInvTable
            patch(page, "GetInvTable", function(object, ...)
                getInventory(object, ...)
                local inventory = table.clone(object.InventoryTable)
                inventory.Swords = table.clone(inventory.Swords or {})
                for id, data in pairs(records) do inventory.Swords[id] = data end
                object.InventoryTable = inventory
            end)
        end

        local updateUI = page.UpdateUI
        patch(page, "UpdateUI", function(object, ...)
            if records[object.SelectedId] then
                object.LockButton.Object.Visible = false
                object.EquipButton.Object.Visible = true
                object.EquipButton.CanUse = true
                object.EquipButton.Object.AutoButtonColor = true
                object.EquipButton.Object.BackgroundColor3 = ui.Palette.Colors.Green
                object.EquipButton.Object.TextLabel.TextColor3 = ui.Palette.Colors.Black
                object.EquipButton.Object.TextLabel.Text = selected == object.SelectedId and "Unequip preview" or "Equip preview"
                return
            end
            return updateUI(object, ...)
        end)
        local updateFocus = page._focusDisplay.Update
        patch(page._focusDisplay, "Update", function(object, card, ...)
            updateFocus(object, card, ...)
            if card and records[card.Id] and object.CurrentClass then
                local data = records[card.Id]
                object.CurrentClass.UpdateData = function(current) current.Data = data end
                object.CurrentClass.NotLocal = true
            end
        end)
        local equipFunction = page.EquipButton.Function
        patch(page.EquipButton, "Function", function(...)
            if not self.Active then return end
            local id = page.SelectedId
            if records[id] then
                if selected == id then
                    clearModel()
                    page:UpdateUI()
                else
                    local ok, err = pcall(equip, id)
                    if not ok then
                        NexusUI:Notify({ Title = "Sword preview", Content = tostring(err), Duration = 5 })
                    end
                end
                return
            end
            clearModel()
            return equipFunction(...)
        end)
        local lockFunction = page.LockButton.Function
        patch(page.LockButton, "Function", function(...)
            if self.Active and not records[page.SelectedId] then return lockFunction(...) end
        end)

        bindFolder(Workspace:FindFirstChild(LocalPlayer.Name .. " SwordWelds"))
        connections[#connections + 1] = Workspace.ChildAdded:Connect(function(child)
            if child.Name == LocalPlayer.Name .. " SwordWelds" then bindFolder(child) end
        end)
        connections[#connections + 1] = Workspace.ChildRemoved:Connect(function(child)
            if child == folder then bindFolder(nil) end
        end)
        connections[#connections + 1] = LocalPlayer.CharacterRemoving:Connect(function()
            clearModel()
            if page then pcall(page.UpdateUI, page) end
        end)

        local owned, names = {}, {}
        for _, data in pairs(inventoryData().Swords) do owned[data.Type] = true end
        for name, data in pairs(catalog) do
            if type(name) == "string" and type(data) == "table" and not owned[name] then
                local asset = assets:FindFirstChild(name)
                if asset and asset:FindFirstChild("Sword") then names[#names + 1] = name end
            end
        end
        table.sort(names)
        for index, name in ipairs(names) do
            if not self.Active then return end
            local id = "PRIME_PREVIEW:" .. name
            local data = { Type = name, Shiny = catalog[name].ShinyOnly == true, CreatedAt = false }
            local card
            local props = {
                Id = id,
                Data = data,
                Parent = page,
                Holder = page.Holder,
                Function = function()
                    if not self.Active or not card then return end
                    page.SelectedId = id
                    page._focusDisplay:Update(card)
                    if page._previousClass and page._previousClass.Highlight then
                        page._previousClass:Highlight(false)
                    end
                    page._previousClass = card
                    card:Highlight(true)
                    page:UpdateUI()
                end
            }
            card = grid and cardClass(nil, props) or ui:Create("SwordGridButton", nil, props)
            card.UpdateData = function(object) object.Data = data end
            card.NotLocal = true
            records[id], cards[id] = data, card
            if grid then
                card.Grid = grid
                grid:_applyCellAspect(card)
                grid.AllClasses[id] = card
                grid._itemTypeOf[id] = "Swords"
                grid.maid["item_" .. id] = card
            else
                page.AllItems[id] = { Class = card, RawObj = card.Raw, Type = "Swords" }
                if page.AspectRatioConstraint then page.AspectRatioConstraint:Clone().Parent = card.Raw end
            end
            if index % 8 == 0 then task.wait() end
        end
        if not self.Active then return end
        refreshPage()
        page:UpdateUI()
    end

    return state
end

local function stopSwordPreview()
    if swordPreview then swordPreview:Destroy(); swordPreview = nil end
end

Tabs.Main:AddToggle("VisualAllSwords", {
    Title = "All Swords (Visual)",
    Description = "Show swords in inventory and equip a local preview",
    Default = false,
    Callback = function(value)
        stopSwordPreview()
        if not value or PrimeRuntime.IsShuttingDown then return end
        local controller = createSwordPreview()
        swordPreview = controller
        swordPreviewEnv.PRIME_SWORD_PREVIEW = controller
        task.spawn(function()
            local ok, err = pcall(controller.Start, controller)
            if not ok and controller.Active then
                controller:Destroy()
                if swordPreview == controller then
                    swordPreview = nil
                    Options.VisualAllSwords:SetValue(false)
                    NexusUI:Notify({ Title = "Sword preview", Content = tostring(err), Duration = 6 })
                end
            end
        end)
    end
})

TrackRuntimeCleanup(stopSwordPreview)
