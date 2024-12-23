local addonName, addon = ...
local FLIPR = addon.FLIPR

-- Define default settings in a central place
local defaultSettings = {
    -- Inventory control settings
    highSaleRate = 0.4,      
    mediumSaleRate = 0.2,    
    highInventory = 100,     
    mediumInventory = 10,    
    lowInventory = 5,
    -- Profitability settings
    minProfit = 1,         -- 1g minimum profit (was 0.1g)
    highVolumeROI = 15,       -- 15% for fast movers
    mediumVolumeROI = 25,     -- 25% for regular items
    lowVolumeROI = 40,        -- 40% for slow movers
    veryLowVolumeROI = 70,    -- 70% for very slow movers
    unstableMarketMultiplier = 1.3,  -- 30% more profit needed in unstable markets
    historicalLowMultiplier = 0.8,   -- 20% less ROI needed if prices are historically low
}

-- Add this helper function at the top of the file
local function CountTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function CreateSettingRow(parent, label, yOffset, dbKey, maxValue, isProfitSetting)
    local rowContainer = CreateFrame("Frame", nil, parent)
    rowContainer:SetHeight(30)
    rowContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, yOffset)
    rowContainer:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    
    -- Label
    local labelText = rowContainer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    labelText:SetPoint("LEFT", 80, 0)
    labelText:SetText(label)
    
    -- Slider
    local slider = CreateFrame("Slider", nil, rowContainer, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", labelText, "RIGHT", 20, 0)
    slider:SetWidth(200)
    slider:SetMinMaxValues(0, maxValue)
    slider:SetValueStep(maxValue == 1 and 0.001 or 1)
    slider:SetObeyStepOnDrag(true)
    
    -- Create slider text elements
    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
    slider.valueText = valueText
    
    -- Edit Box
    local editBox = CreateFrame("EditBox", nil, rowContainer, "InputBoxTemplate")
    editBox:SetPoint("LEFT", slider, "RIGHT", 20, 0)
    editBox:SetSize(60, 20)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetJustifyH("CENTER")
    editBox:SetMaxLetters(8)
    
    -- Value display function
    local function UpdateValueText(value)
        if maxValue == 1 then
            -- Percentage values
            slider.valueText:SetText(string.format("%.1f%%", value * 100))
            editBox:SetText(string.format("%.1f", value * 100))
        else
            -- Integer values
            local intValue = math.floor(value + 0.5)  -- Round to nearest integer
            slider.valueText:SetText(tostring(intValue))
            editBox:SetText(tostring(intValue))
        end
        editBox:SetCursorPosition(0)
    end
    
    -- Update function
    local function UpdateValue(value)
        if maxValue ~= 1 then
            -- Round to nearest integer for non-percentage values
            value = math.floor(value + 0.5)
        end
        slider:SetValue(value)
        UpdateValueText(value)
        
        -- Update the database
        if isProfitSetting then
            FLIPR.db[dbKey] = value
        else
            FLIPR.groupDB[dbKey] = value
        end
    end
    
    -- Slider scripts
    slider:SetScript("OnValueChanged", function(self, value)
        UpdateValue(value)
    end)
    
    -- Edit box scripts
    editBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            if maxValue == 1 then
                value = value / 100
            else
                value = math.floor(value + 0.5)  -- Round to nearest integer
            end
            value = math.min(math.max(value, 0), maxValue)
            UpdateValue(value)
        end
        self:ClearFocus()
    end)
    
    -- Initial value
    local initialValue = isProfitSetting and FLIPR.db[dbKey] or FLIPR.groupDB[dbKey] or 0
    if maxValue ~= 1 then
        initialValue = math.floor(initialValue + 0.5)  -- Round to nearest integer
    end
    UpdateValue(initialValue)
    
    -- Force update edit box after a slight delay
    C_Timer.After(0.1, function()
        if maxValue == 1 then
            editBox:SetText(string.format("%.1f", initialValue * 100))
        else
            editBox:SetText(tostring(math.floor(initialValue + 0.5)))
        end
    end)
    
    return rowContainer
end

function FLIPR:CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "FLIPR"
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    
    -- Create tab group at the top
    local tabGroup = CreateFrame("Frame", "FliprOptionsTabGroup", panel)
    tabGroup:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -10)
    tabGroup:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 0)
    
    -- Initialize tab system
    panel.tabs = {}
    panel.numTabs = 3
    
    -- Create tab buttons
    local function CreateTab(text, index)
        local tab = CreateFrame("Button", "FliprOptionsTab"..index, panel, "PanelTabButtonTemplate")
        tab:SetText(text)
        tab:SetID(index)
        if index == 1 then
            tab:SetPoint("TOPLEFT", tabGroup, "TOPLEFT", 5, 0)
        else
            tab:SetPoint("LEFT", _G["FliprOptionsTab"..(index-1)], "RIGHT", -15, 0)
        end
        
        -- Set up tab appearance
        tab:SetSize(115, 32)
        
        -- Create tab content frame with background
        tab.content = CreateFrame("Frame", nil, tabGroup, "BackdropTemplate")
        tab.content:SetPoint("TOPLEFT", tabGroup, "TOPLEFT", 0, -30)
        tab.content:SetPoint("BOTTOMRIGHT", tabGroup, "BOTTOMRIGHT", 0, -5)
        tab.content:Hide()
        
        -- Set up backdrop with no bottom inset
        tab.content:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileEdge = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 0 }
        })
        tab.content:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        tab.content:SetBackdropBorderColor(0.4, 0.4, 0.4)
        
        -- Add tab to panel's tabs array
        panel.tabs[index] = tab
        
        return tab
    end
    
    -- Create tabs
    local generalTab = CreateTab("General", 1)
    local operationsTab = CreateTab("Operations", 2)
    local groupsTab = CreateTab("Groups", 3)
    
    -- Initialize tab system after creating tabs
    PanelTemplates_SetNumTabs(panel, panel.numTabs)
    
    -- Store references
    panel.selectedTab = 1
    
    -- Tab click handler
    local function OnTabClick(tab)
        PanelTemplates_SetTab(panel, tab:GetID())
        -- Hide all content frames
        for _, t in ipairs(panel.tabs) do
            t.content:Hide()
        end
        -- Show selected content
        tab.content:Show()
        panel.selectedTab = tab:GetID()
    end
    
    -- Set up tab click scripts
    for _, tab in ipairs(panel.tabs) do
        tab:SetScript("OnClick", function(self) OnTabClick(self) end)
    end
    
    -- Create the general settings content
    local function CreateGeneralSettings(parent)
        -- Create the scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -36, 16)
        
        -- Create the scrolling content frame
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        scrollChild:SetSize(scrollFrame:GetWidth() - 30, 1)
        scrollFrame:SetScrollChild(scrollChild)
        
        -- Create settings sections
        local yOffset = -30  -- Increased initial offset from -10 to -30
        
        -- Sale Rate Settings Header
        local saleRateHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        saleRateHeader:SetPoint("TOP", scrollChild, "TOP", 280, yOffset)
        saleRateHeader:SetText("Sale Rate Thresholds")
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "High Sale Rate", yOffset, "highSaleRate", 1, true)
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "Medium Sale Rate", yOffset, "mediumSaleRate", 1, true)
        
        yOffset = yOffset - 60  -- Increased space before next header from -40 to -60
        
        -- Inventory Settings Header
        local inventoryHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        inventoryHeader:SetPoint("TOP", scrollChild, "TOP", 280, yOffset)
        inventoryHeader:SetText("Inventory Limits")
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "High Inventory", yOffset, "highInventory", 200, true)
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "Medium Inventory", yOffset, "mediumInventory", 50, true)
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "Low Inventory", yOffset, "lowInventory", 20, true)
        
        -- Set final height of the scrollChild based on the content
        scrollChild:SetHeight(math.abs(yOffset) + 20)
        
        -- Make sure the parent frame is visible and sized
        parent:SetSize(parent:GetParent():GetWidth(), parent:GetParent():GetHeight())
        parent:Show()
        
        return scrollFrame
    end
    
    -- Create the operations content
    local function CreateOperationsContent(parent)
        -- Create the scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -36, 16)
        
        -- Create the scrolling content frame
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -20)
        scrollChild:SetWidth(scrollFrame:GetWidth() - 30)
        scrollFrame:SetScrollChild(scrollChild)
        
        local yOffset = -50
        local contentHeight = 0
        
        -- Operations Header
        local header = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetPoint("TOP", scrollChild, "TOP", 280, yOffset)
        header:SetText("TSM Operations")
        contentHeight = contentHeight + 30
        
        yOffset = yOffset - 30
        
        -- Function to create operation section
        local function CreateOperationSection(moduleName, operations, startOffset)
            local moduleHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            moduleHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 40, startOffset)
            moduleHeader:SetText(moduleName)
            contentHeight = contentHeight + 20
            
            local offset = startOffset - 20
            
            if operations then
                for opName, opSettings in pairs(operations) do
                    local opHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    opHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 60, offset)
                    opHeader:SetText(opName)
                    contentHeight = contentHeight + 20
                    
                    offset = offset - 20
                    
                    -- Display operation settings
                    for setting, value in pairs(opSettings) do
                        local settingText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                        settingText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 80, offset)
                        settingText:SetText(string.format("%s: %s", setting, tostring(value)))
                        
                        offset = offset - 15
                        contentHeight = contentHeight + 15
                    end
                    
                    -- Add groups using this operation
                    local groupsUsingOp = {}
                    for groupName, groupData in pairs(self.groupDB.groups) do
                        -- Check if this group or any of its subgroups use the operation
                        local function checkGroup(group, parentPath)
                            local currentPath = parentPath and (parentPath .. "/" .. group.name) or group.name
                            
                            -- Check if this group uses the operation
                            if group.operations and 
                               group.operations[moduleName] and 
                               group.operations[moduleName][opName] then
                                table.insert(groupsUsingOp, currentPath)
                            end
                            
                            -- Check subgroups
                            if group.subgroups then
                                for _, subgroup in pairs(group.subgroups) do
                                    checkGroup(subgroup, currentPath)
                                end
                            end
                        end
                        
                        -- Start checking from the root group
                        checkGroup(groupData)
                    end
                    
                    if #groupsUsingOp > 0 then
                        offset = offset - 15  -- Extra space before groups list
                        local groupsText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                        groupsText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 80, offset)
                        groupsText:SetTextColor(0.7, 0.7, 0.7)  -- Light gray color
                        groupsText:SetText("Groups: " .. table.concat(groupsUsingOp, ", "))
                        
                        offset = offset - 15
                        contentHeight = contentHeight + 30  -- Account for groups text and spacing
                    end
                    
                    offset = offset - 10
                    contentHeight = contentHeight + 10
                end
            else
                local noOpsText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisable")
                noOpsText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 60, offset)
                noOpsText:SetText("No operations found")
                contentHeight = contentHeight + 20
                offset = offset - 30
            end
            
            return offset
        end
        
        -- Get operations from the first group (they're shared)
        local operations = nil
        for groupName, groupData in pairs(self.groupDB.groups) do
            if groupData.operations then
                operations = groupData.operations
                break
            end
        end
        
        -- Create sections for each module type
        local moduleTypes = {"Auctioning", "Shopping", "Crafting", "Vendoring", "Warehousing", "Mailing", "Sniper"}
        for _, moduleName in ipairs(moduleTypes) do
            if operations and operations[moduleName] then
                yOffset = CreateOperationSection(moduleName, operations[moduleName], yOffset)
            else
                yOffset = CreateOperationSection(moduleName, nil, yOffset)
            end
            yOffset = yOffset - 20  -- Space between modules
            contentHeight = contentHeight + 20
        end
        
        -- Set final height with additional padding
        scrollChild:SetHeight(contentHeight + 150)
        
        scrollFrame:SetScrollChild(scrollChild)
        return scrollFrame
    end
    
    -- Create the groups content
    local function CreateGroupsContent(parent)
        print("=== CreateGroupsContent START ===")
        
        -- Create container frame first
        local container = CreateFrame("Frame", "FliprGroupsContainer", parent)
        container:SetAllPoints()
        container:SetFrameLevel(parent:GetFrameLevel() + 1)
        
        -- Initialize database tables first
        if not FLIPR.db then FLIPR.db = {} end
        if not FLIPR.db.expandedGroups then FLIPR.db.expandedGroups = {} end
        if not FLIPR.db.enabledGroups then FLIPR.db.enabledGroups = {} end

        -- Initialize available groups from existing data
        if not FLIPR.availableGroups then
            print("Getting available groups...")
            FLIPR.availableGroups = FLIPR:GetAvailableGroups()
            -- Debug print the groups structure
            for groupName, groupData in pairs(FLIPR.availableGroups) do
                print("Group:", groupName)
                if groupData.items then
                    print("  Items:", CountTable(groupData.items))
                    for itemID in pairs(groupData.items) do
                        print(string.format("  - Item %d", itemID))
                    end
                end
            end
        end
        
        -- Create all the UI elements
        local treePanel = CreateFrame("Frame", "FliprTreePanel", container, BackdropTemplateMixin and "BackdropTemplate")
        treePanel:SetPoint("TOPLEFT", container, "TOPLEFT", 16, -16)
        treePanel:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 216, 16)
        treePanel:SetWidth(200)
        treePanel:SetHeight(400)
        
        -- Set up tree panel backdrop
        treePanel:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        treePanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        treePanel:SetBackdropBorderColor(0.6, 0.6, 0.6)
        
        -- Create scroll frame
        local treeScroll = CreateFrame("ScrollFrame", "FliprTreeScroll", treePanel, "UIPanelScrollFrameTemplate")
        treeScroll:SetPoint("TOPLEFT", treePanel, "TOPLEFT", 8, -30)
        treeScroll:SetPoint("BOTTOMRIGHT", treePanel, "BOTTOMRIGHT", -28, 8)
        
        -- Create tree content
        local treeContent = CreateFrame("Frame", "FliprTreeContent", treeScroll)
        treeContent:SetWidth(treeScroll:GetWidth())
        treeContent:SetHeight(400)
        
        -- Add GROUPS label
        local groupsLabel = treePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        groupsLabel:SetPoint("TOP", treePanel, "TOP", 0, -8)
        groupsLabel:SetText("GROUPS")
        groupsLabel:SetTextColor(1, 0.82, 0, 1)
        
        -- Add debug background
        local treeBg = treeContent:CreateTexture(nil, "BACKGROUND")
        treeBg:SetAllPoints()
        treeBg:SetColorTexture(0.2, 0, 0, 0.3)
        
        treeScroll:SetScrollChild(treeContent)
        
        -- Store these in the container for reference
        container.treePanel = treePanel
        container.treeScroll = treeScroll
        container.treeContent = treeContent
        
        -- Define CreateGroupTreeItem function FIRST
        local function CreateGroupTreeItem(groupData, parentPath, yOffset, level)
            print(string.format("Creating tree item: %s (level %d, yOffset %d)", 
                groupData and groupData.name or "nil", level, yOffset))
            
            if not groupData or not groupData.name then 
                print("  Invalid group data")
                return yOffset 
            end
            
            -- Construct the full path properly
            local currentPath = parentPath and (parentPath .. "/" .. groupData.name) or groupData.name
            print("Constructed path:", currentPath)
            local indent = level * 20
            
            -- Create container frame
            local itemContainer = CreateFrame("Frame", nil, treeContent)
            itemContainer:SetSize(treeContent:GetWidth() - indent, 20)
            itemContainer:SetPoint("TOPLEFT", treeContent, "TOPLEFT", indent, yOffset)
            
            -- Add background frame BEHIND everything
            local bgFrame = CreateFrame("Frame", nil, itemContainer)
            bgFrame:SetAllPoints()
            bgFrame:SetFrameLevel(itemContainer:GetFrameLevel())  -- Put at base level
            
            -- Add background texture to bgFrame
            local containerBg = bgFrame:CreateTexture(nil, "BACKGROUND")
            containerBg:SetAllPoints()
            containerBg:SetColorTexture(0.1, 0.1, 0.1, 0.3)  -- Start with dark color
            
            -- Create expand button if needed (on top of background)
            local expandButton
            if groupData.children and next(groupData.children) then
                expandButton = CreateFrame("Button", nil, itemContainer)
                expandButton:SetFrameLevel(itemContainer:GetFrameLevel() + 1)  -- Above background
                expandButton:SetSize(16, 16)
                expandButton:SetPoint("LEFT", itemContainer, "LEFT", 0, 0)
                
                local expandTexture = expandButton:CreateTexture(nil, "ARTWORK")
                expandTexture:SetAllPoints()
                expandTexture:SetTexture(FLIPR.db.expandedGroups[currentPath] and 
                    "Interface\\Buttons\\UI-MinusButton-Up" or 
                    "Interface\\Buttons\\UI-PlusButton-Up")
                
                -- Store RefreshTreeView reference for the click handler
                expandButton:SetScript("OnClick", function()
                    print("Expand button clicked for:", currentPath)
                    FLIPR.db.expandedGroups[currentPath] = not FLIPR.db.expandedGroups[currentPath]
                    container.RefreshTreeView()  -- Use container reference
                end)
            end
            
            -- Create checkbox (on top of background)
            local checkbox = CreateFrame("CheckButton", nil, itemContainer, "ChatConfigCheckButtonTemplate")
            checkbox:SetFrameLevel(itemContainer:GetFrameLevel() + 1)  -- Above background
            checkbox:SetPoint("LEFT", expandButton or itemContainer, "LEFT", expandButton and 20 or 0, 0)
            checkbox:SetChecked(FLIPR.db.enabledGroups[currentPath] or false)
            
            checkbox.Text:SetText(groupData.name)
            checkbox.Text:SetFontObject("GameFontNormalLarge")
            checkbox.Text:SetTextColor(1, 1, 1)
            
            -- Define UpdateBackground function
            local function UpdateBackground()
                if checkbox:GetChecked() then
                    containerBg:SetColorTexture(0, 1, 0, 0.3)  -- Green when checked
                else
                    containerBg:SetColorTexture(0.1, 0.1, 0.1, 0.3)  -- Dark when unchecked
                end
            end
            
            -- Initial background update
            UpdateBackground()
            
            -- Add checkbox click handler
            checkbox:SetScript("OnClick", function()
                print("=== Checkbox OnClick START ===")
                local checked = checkbox:GetChecked()
                print("Checkbox clicked for:", currentPath, "checked:", checked)
                
                -- Update this group's state using the full path
                FLIPR.db.enabledGroups[currentPath] = checked
                UpdateBackground()
                
                -- If checked, update the content panel
                if checked then
                    print("Checkbox is checked, getting items from:", currentPath)
                    -- Get the root group name from the path
                    local rootGroupName = strsplit("/", currentPath)
                    print("Root group name:", rootGroupName)
                    -- Get the root group data
                    local rootGroup = FliprDB.groups[rootGroupName]
                    print("Root group data:", rootGroup)
                    if rootGroup then
                        print("Root group structure:")
                        for k, v in pairs(rootGroup) do
                            if type(v) == "table" then
                                print("  ", k, ":", "table with", CountTable(v), "entries")
                            else
                                print("  ", k, ":", v)
                            end
                        end
                    end
                    
                    if not rootGroup then
                        print("No root group found for:", rootGroupName)
                        return
                    end
                    
                    -- Get items from the group using the path
                    print("Getting items from group with path:", currentPath)
                    local items = {}
                    local currentNode = rootGroup
                    local pathParts = {strsplit("/", currentPath)}
                    
                    -- Navigate to the correct node
                    for i, part in ipairs(pathParts) do
                        print("Looking for part:", part)
                        if i == 1 then
                            -- We're already at the root node
                            if currentNode.name ~= part then
                                print("Root group name mismatch:", currentNode.name, "vs", part)
                                return
                            end
                        else
                            -- For subgroups, look in the children table
                            if currentNode.children and currentNode.children[part] then
                                currentNode = currentNode.children[part]
                                print("Found child group:", part)
                            else
                                print("Could not find child group:", part)
                                return
                            end
                        end
                    end
                    
                    -- Collect items from the current node and its children
                    local function collectItems(node)
                        if node.items then
                            for itemId, itemData in pairs(node.items) do
                                items[itemId] = itemData
                                print("Found item:", itemId)
                            end
                        end
                        
                        if node.children then
                            for _, childNode in pairs(node.children) do
                                collectItems(childNode)
                            end
                        end
                    end
                    
                    collectItems(currentNode)
                    print("Found items table:", items)
                    if items then
                        print("Items table structure:")
                        for k, v in pairs(items) do
                            print("  ", k, ":", type(v) == "table" and "table" or v)
                        end
                    end
                    
                    if items and next(items) then
                        print("Number of items:", CountTable(items))
                        container.UpdateContentPanel(currentPath)
                    else
                        print("No items found in group")
                        print("Debug: currentPath parts:")
                        for part in string.gmatch(currentPath, "[^/]+") do
                            print("  Path part:", part)
                        end
                    end
                else
                    print("Checkbox unchecked, clearing content panel")
                    -- Clear the content panel when unchecked
                    for _, child in pairs({container.itemContent:GetChildren()}) do
                        child:Hide()
                        child:SetParent(nil)
                    end
                end
                print("=== Checkbox OnClick END ===")
            end)
            
            -- Add click handler to the BACKGROUND frame
            bgFrame:EnableMouse(true)
            bgFrame:SetScript("OnMouseDown", function(self, button)
                print("=== Background OnMouseDown START ===")
                print("Button clicked:", button)
                if button == "LeftButton" then
                    -- Don't handle clicks on the checkbox or expand button
                    local x, y = GetCursorPosition()
                    local scale = self:GetEffectiveScale()
                    local left = self:GetLeft() * scale
                    local checkboxRight = (checkbox:GetRight() or 0) * scale
                    
                    print("Cursor position:", x, y)
                    print("Scale:", scale)
                    print("Left:", left)
                    print("Checkbox right:", checkboxRight)
                    
                    -- Only process click if it's to the right of the checkbox
                    if x > checkboxRight then
                        print("=== Click is to the right of checkbox ===")
                        print("Looking up group:", currentPath)
                        
                        -- Get the root group name from the path
                        local rootGroupName = strsplit("/", currentPath)
                        print("Root group name:", rootGroupName)
                        -- Get the root group data
                        local rootGroup = FliprDB.groups[rootGroupName]
                        print("Root group data:", rootGroup)
                        if rootGroup then
                            print("Root group structure:")
                            for k, v in pairs(rootGroup) do
                                if type(v) == "table" then
                                    print("  ", k, ":", "table with", CountTable(v), "entries")
                                else
                                    print("  ", k, ":", v)
                                end
                            end
                        end
                        
                        if not rootGroup then
                            print("No root group found for:", rootGroupName)
                            return
                        end
                        
                        -- Get items from the group using the path
                        print("Getting items from group with path:", currentPath)
                        local items = {}
                        local currentNode = rootGroup
                        local pathParts = {strsplit("/", currentPath)}
                        
                        -- Navigate to the correct node
                        for i, part in ipairs(pathParts) do
                            print("Looking for part:", part)
                            if i == 1 then
                                -- We're already at the root node
                                if currentNode.name ~= part then
                                    print("Root group name mismatch:", currentNode.name, "vs", part)
                                    return
                                end
                            else
                                -- For subgroups, look in the children table
                                if currentNode.children and currentNode.children[part] then
                                    currentNode = currentNode.children[part]
                                    print("Found child group:", part)
                                else
                                    print("Could not find child group:", part)
                                    return
                                end
                            end
                        end
                        
                        -- Collect items from the current node and its children
                        local function collectItems(node)
                            if node.items then
                                for itemId, itemData in pairs(node.items) do
                                    items[itemId] = itemData
                                    print("Found item:", itemId)
                                end
                            end
                            
                            if node.children then
                                for _, childNode in pairs(node.children) do
                                    collectItems(childNode)
                                end
                            end
                        end
                        
                        collectItems(currentNode)
                        print("Found items table:", items)
                        if items then
                            print("Items table structure:")
                            for k, v in pairs(items) do
                                print("  ", k, ":", type(v) == "table" and "table" or v)
                            end
                        end
                        
                        if items and next(items) then
                            print("Number of items:", CountTable(items))
                            for itemID, itemData in pairs(items) do
                                -- Make sure itemID is a number
                                itemID = tonumber(itemID)
                                if itemID then
                                    print(string.format("Processing item: %d", itemID))
                                    local name = GetItemInfo(itemID)
                                    print(string.format("Item %d: %s", itemID, name or "loading..."))
                                    
                                    -- Also check itemDB
                                    if FLIPR.itemDB and FLIPR.itemDB[itemID] then
                                        print(string.format("  Found in itemDB: %s", FLIPR.itemDB[itemID].name))
                                    else
                                        print("  Not found in itemDB")
                                    end
                                else
                                    print("Invalid itemID:", itemID)
                                end
                            end
                            -- Pass the group path to UpdateContentPanel
                            print("Updating content panel with group:", currentPath)
                            container.UpdateContentPanel(currentPath)
                        else
                            print("No items found in group:", currentPath)
                            print("Debug: currentPath parts:")
                            for part in string.gmatch(currentPath, "[^/]+") do
                                print("  Path part:", part)
                            end
                        end
                    else
                        print("Click was on or to the left of checkbox")
                    end
                end
                print("=== Background OnMouseDown END ===")
            end)
            
            -- Add hover effect to background
            bgFrame:SetScript("OnEnter", function()
                if not checkbox:GetChecked() then
                    containerBg:SetColorTexture(0.3, 0.3, 0.3, 0.3)  -- Hover color
                end
            end)
            
            bgFrame:SetScript("OnLeave", function()
                UpdateBackground()
            end)
            
            print(string.format("Created item: %s at yOffset: %d", groupData.name, yOffset))
            
            yOffset = yOffset - 20
            
            -- Show children if expanded
            if FLIPR.db.expandedGroups[currentPath] and groupData.children then
                for childName, childData in pairs(groupData.children) do
                    yOffset = CreateGroupTreeItem(childData, currentPath, yOffset, level + 1)
                end
            end
            
            return yOffset
        end
        
        -- THEN define RefreshTreeView function that uses CreateGroupTreeItem
        local function RefreshTreeView()
            print("=== RefreshTreeView START ===")
            if not treeContent then
                print("ERROR: treeContent is nil in RefreshTreeView!")
                return
            end
            
            -- Clear existing content
            for _, child in pairs({treeContent:GetChildren()}) do
                child:Hide()
                child:SetParent(nil)
            end
            
            if not FLIPR.availableGroups then
                print("ERROR: No available groups!")
                return
            end
            
            local yOffset = -10
            for groupName, groupData in pairs(FLIPR.availableGroups) do
                print(string.format("Processing root group: %s", groupName))
                yOffset = CreateGroupTreeItem(groupData, nil, yOffset, 0)
            end
            
            local finalHeight = math.abs(yOffset) + 20
            print(string.format("Setting tree content height to: %d", finalHeight))
            treeContent:SetHeight(math.max(finalHeight, 400))
        end
        
        -- Store functions directly on the container
        container.CreateGroupTreeItem = CreateGroupTreeItem
        container.RefreshTreeView = RefreshTreeView
        
        -- Print debug info before refresh
        print("Available groups before refresh:")
        if FLIPR.availableGroups then
            for groupName, _ in pairs(FLIPR.availableGroups) do
                print("  -", groupName)
            end
        else
            print("No available groups!")
        end
        
        -- Call initial refresh
        RefreshTreeView()
        
        -- Add right panel content display
        local contentPanel = CreateFrame("Frame", "FliprContentPanel", container, BackdropTemplateMixin and "BackdropTemplate")
        contentPanel:SetPoint("TOPLEFT", treePanel, "TOPRIGHT", 16, 0)
        contentPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -16, 16)
        
        -- Set up content panel backdrop (same style as tree panel)
        contentPanel:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        contentPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        contentPanel:SetBackdropBorderColor(0.6, 0.6, 0.6)
        
        -- Add ITEMS label (same style as GROUPS)
        local itemsLabel = contentPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        itemsLabel:SetPoint("TOP", contentPanel, "TOP", 0, -8)
        itemsLabel:SetText("ITEMS")
        itemsLabel:SetTextColor(1, 0.82, 0, 1)  -- Gold color
        
        -- Create scroll frame for items
        local itemScroll = CreateFrame("ScrollFrame", nil, contentPanel, "UIPanelScrollFrameTemplate")
        itemScroll:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 8, -30)  -- Same offset as tree panel
        itemScroll:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -28, 8)
        
        local itemContent = CreateFrame("Frame", nil, itemScroll)
        itemContent:SetWidth(itemScroll:GetWidth())
        itemContent:SetHeight(400)  -- Initial height
        
        -- Add debug background to item content
        local itemBg = itemContent:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints()
        itemBg:SetColorTexture(0, 0.2, 0, 0.3)  -- Slight green tint
        
        itemScroll:SetScrollChild(itemContent)
        
        -- Store references
        container.contentPanel = contentPanel
        container.itemContent = itemContent
        
        -- Function to update content panel with selected group's items
        local function UpdateContentPanel(groupPath)
            print("=== UpdateContentPanel START ===")
            print("Updating content panel for group:", groupPath)
            
            -- Clear existing content
            for _, child in pairs({itemContent:GetChildren()}) do
                child:Hide()
                child:SetParent(nil)
            end
            
            -- Get the root group name from the path
            local rootGroupName = strsplit("/", groupPath)
            print("Root group name:", rootGroupName)
            -- Get the root group data
            local rootGroup = FliprDB.groups[rootGroupName]
            if not rootGroup then
                print("No root group found for:", rootGroupName)
                return
            end
            
            -- Get items from the group using the path
            print("Getting items from group with path:", groupPath)
            local items = {}
            local currentNode = rootGroup
            local pathParts = {strsplit("/", groupPath)}
            
            -- Navigate to the correct node
            for i, part in ipairs(pathParts) do
                print("Looking for part:", part)
                if i == 1 then
                    -- We're already at the root node
                    if currentNode.name ~= part then
                        print("Root group name mismatch:", currentNode.name, "vs", part)
                        return
                    end
                else
                    -- For subgroups, look in the children table
                    if currentNode.children and currentNode.children[part] then
                        currentNode = currentNode.children[part]
                        print("Found child group:", part)
                    else
                        print("Could not find child group:", part)
                        return
                    end
                end
            end
            
            -- Collect items from the current node and its children
            local function collectItems(node)
                if node.items then
                    for itemId, itemData in pairs(node.items) do
                        items[itemId] = itemData
                        print("Found item:", itemId)
                    end
                end
                
                if node.children then
                    for _, childNode in pairs(node.children) do
                        collectItems(childNode)
                    end
                end
            end
            
            collectItems(currentNode)
            print("Found items table:", items)
            if items then
                print("Items table structure:")
                for k, v in pairs(items) do
                    print("  ", k, ":", type(v) == "table" and "table" or v)
                end
            end
            
            if not items or not next(items) then 
                print("No items found in group:", groupPath)
                return 
            end
            
            print("Found items in group:", groupPath)
            print("Number of items:", CountTable(items))
            
            -- Display items
            local yOffset = -10
            for itemID, itemData in pairs(items) do
                itemID = tonumber(itemID)
                if itemID then
                    print("Creating row for item:", itemID)
                    
                    -- Create item row
                    local itemRow = CreateFrame("Frame", nil, itemContent)
                    itemRow:SetHeight(24)
                    itemRow:SetPoint("TOPLEFT", itemContent, "TOPLEFT", 0, yOffset)
                    itemRow:SetPoint("RIGHT", itemContent, "RIGHT")
                    
                    -- Add row background
                    local rowBg = itemRow:CreateTexture(nil, "BACKGROUND")
                    rowBg:SetAllPoints()
                    rowBg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
                    
                    -- Add item icon and text
                    local itemIcon = itemRow:CreateTexture(nil, "ARTWORK")
                    itemIcon:SetSize(20, 20)
                    itemIcon:SetPoint("LEFT", itemRow, "LEFT", 8, 0)
                    
                    -- Make row interactive
                    itemRow:EnableMouse(true)
                    itemRow:SetScript("OnEnter", function()
                        rowBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                    end)
                    itemRow:SetScript("OnLeave", function()
                        rowBg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
                    end)
                    
                    print("Loading item data for:", itemID)
                    -- Load item data asynchronously
                    local item = Item:CreateFromItemID(itemID)
                    item:ContinueOnItemLoad(function()
                        local itemLink = item:GetItemLink()
                        local _, _, _, _, icon = GetItemInfoInstant(itemID)
                        print("Item loaded:", itemID, itemLink)
                        
                        itemIcon:SetTexture(icon)
                        
                        local itemName = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        itemName:SetPoint("LEFT", itemIcon, "RIGHT", 8, 0)
                        itemName:SetText(itemLink)
                        
                        local itemIDText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        itemIDText:SetPoint("LEFT", itemName, "RIGHT", 8, 0)
                        itemIDText:SetText(string.format("(ID: %d)", itemID))
                        itemIDText:SetTextColor(0.7, 0.7, 0.7)
                    end)
                    
                    yOffset = yOffset - 24
                end
            end
            
            -- Update content height
            local finalHeight = math.abs(yOffset) + 20
            print("Setting content height to:", finalHeight)
            itemContent:SetHeight(math.max(finalHeight, 400))
            print("=== UpdateContentPanel END ===")
        end
        
        -- Store the update function
        container.UpdateContentPanel = UpdateContentPanel
        
        return container
    end
    
    -- Create content for all tabs
    CreateGeneralSettings(generalTab.content)
    CreateOperationsContent(operationsTab.content)
    groupsTab.content.CreateGroupsContent = CreateGroupsContent
    
    -- Set up initial tab state
    PanelTemplates_SetTab(panel, 1)
    generalTab.content:Show()
    operationsTab.content:Hide()
    groupsTab.content:Hide()
    
    -- Store reference and register with Settings API
    FLIPR.optionsPanel = panel
    local category = Settings.RegisterCanvasLayoutCategory(panel, "FLIPR")
    category.ID = "FLIPR"
    Settings.RegisterAddOnCategory(category)
    
    -- Set up tab switching
    panel.OnTabClick = function(tab)
        print(string.format("=== Tab clicked: %d ===", tab:GetID()))
        PanelTemplates_SetTab(panel, tab:GetID())
        
        -- Hide all tab contents
        for _, t in ipairs(panel.tabs) do
            if t.content then
                print(string.format("Hiding content for tab: %d", t:GetID()))
                t.content:Hide()
            end
        end
        
        -- Show selected tab content
        if tab.content then
            print(string.format("Showing content for tab: %d", tab:GetID()))
            tab.content:Show()
            
            -- If this is the Groups tab, refresh the view
            if tab:GetID() == 3 then
                print("Groups tab selected, refreshing view...")
                -- Force a refresh of the groups content
                if not FLIPR.availableGroups then
                    print("Initializing available groups...")
                    FLIPR.availableGroups = FLIPR:GetAvailableGroups()
                end
                
                -- Create the groups container if it doesn't exist
                if not tab.content.groupsContainer then
                    print("Creating groups container...")
                    tab.content.groupsContainer = CreateGroupsContent(tab.content)
                end
                
                -- Refresh the tree view if it exists
                if tab.content.groupsContainer and tab.content.groupsContainer.RefreshTreeView then
                    print("Refreshing tree view...")
                    tab.content.groupsContainer.RefreshTreeView()
                else
                    print("ERROR: Groups container or RefreshTreeView not found!")
                    print("groupsContainer:", tab.content.groupsContainer)
                    if tab.content.groupsContainer then
                        print("RefreshTreeView:", tab.content.groupsContainer.RefreshTreeView)
                    end
                end
            end
        end
    end
    
    -- Set up panel refresh
    panel.OnShow = function()
        print("=== Panel OnShow START ===")
        PanelTemplates_SetTab(panel, panel.selectedTab or 1)
        for _, tab in ipairs(panel.tabs) do
            if tab.content then
                print(string.format("Hiding content for tab: %d", tab:GetID()))
                tab.content:Hide()
            end
        end
        
        local selectedTab = panel.tabs[panel.selectedTab or 1]
        if selectedTab and selectedTab.content then
            print(string.format("Showing content for selected tab: %d", selectedTab:GetID()))
            selectedTab.content:Show()
            
            -- If Groups tab is selected, ensure it's properly initialized
            if selectedTab:GetID() == 3 then
                print("Groups tab is selected, ensuring initialization...")
                if not FLIPR.availableGroups then
                    print("Initializing available groups...")
                    FLIPR.availableGroups = FLIPR:GetAvailableGroups()
                end
                
                -- Create the groups container if it doesn't exist
                if not selectedTab.content.groupsContainer then
                    print("Creating groups container...")
                    selectedTab.content.groupsContainer = CreateGroupsContent(selectedTab.content)
                end
                
                -- Refresh the tree view if it exists
                if selectedTab.content.groupsContainer and selectedTab.content.groupsContainer.RefreshTreeView then
                    print("Refreshing tree view...")
                    selectedTab.content.groupsContainer.RefreshTreeView()
                else
                    print("ERROR: Groups container or RefreshTreeView not found!")
                    print("groupsContainer:", selectedTab.content.groupsContainer)
                    if selectedTab.content.groupsContainer then
                        print("RefreshTreeView:", selectedTab.content.groupsContainer.RefreshTreeView)
                    end
                end
            end
        end
        
        print("=== Panel OnShow END ===")
    end
    
    -- Set up tab click handlers
    for _, tab in ipairs(panel.tabs) do
        tab:SetScript("OnClick", function(self)
            panel.OnTabClick(self)
        end)
    end
    
    panel:SetScript("OnShow", panel.OnShow)
    
    return panel
end 