local addonName, addon = ...
local FLIPR = addon.FLIPR
local ROW_HEIGHT = 25
local MAX_DROPDOWN_ROWS = 10
local DROPDOWN_PADDING = 2
local DROPDOWN_TOTAL_HEIGHT = (MAX_DROPDOWN_ROWS * ROW_HEIGHT) + DROPDOWN_PADDING

FLIPR.scanTimer = 0
FLIPR.scanStartTime = 0

-- Store rows by itemID
FLIPR.itemRows = {}
FLIPR.expandedItemID = nil

function FLIPR:CancelScan()
    -- Stop scanning
    self.isScanning = false
    self.isPaused = false
    
    -- Reset scan progress
    if self.scanProgressText then
        self.scanProgressText:SetText("")
    end
    
    -- Reset timer
    self.scanTimer = 0
    self.scanStartTime = 0
    if self.scanTimerText then
        self.scanTimerText:SetText("")
    end
    if self.timerFrame then
        self.timerFrame:Hide()
    end
    
    -- Reset scan button text
    if self.scanButton then
        self.scanButton:SetText("Scan Items")
    end
    
    -- Clear all rows
    if self.scrollChild then
        for _, child in pairs({self.scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        self.scrollChild:SetHeight(1)
    end
    
    -- Reset row counter
    self.profitableItemCount = 0
    
    -- Reset scanner variables
    self.currentScanIndex = 1
    self.selectedRow = nil
    self.selectedItem = nil
    self.failedItems = {}
    
    -- Unregister events if they're registered
    if self.isEventRegistered then
        self:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
        self:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
        self.isEventRegistered = false
    end
    
    print("|cFFFF9999Scan cancelled - All data cleared|r")
end

function FLIPR:OnAuctionHouseShow()
    if not self.tabCreated then
        self:CreateFLIPRTab()
        self.tabCreated = true
    end
end

function FLIPR:CreateFLIPRTab()
    print("=== CreateFLIPRTab START ===")
    local numTabs = #AuctionHouseFrame.Tabs + 1
    local fliprTab = CreateFrame("Button", "AuctionHouseFrameTab"..numTabs, AuctionHouseFrame, "AuctionHouseFrameTabTemplate") 
    fliprTab:SetID(numTabs)
    fliprTab:SetText("FLIPR")
    fliprTab:SetPoint("LEFT", AuctionHouseFrame.Tabs[numTabs-1], "RIGHT", -15, 0)

    -- Create main content frame
    local contentFrame = CreateFrame("Frame", "FLIPRContentFrame", AuctionHouseFrame)
    contentFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 0, -60)
    contentFrame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, 0)
    contentFrame:Hide()
    
    -- Constants
    local SIDEBAR_WIDTH = 200
    local BOTTOM_MARGIN = 5
    local TITLE_HEIGHT = 30
    
    -- Create title section at the top
    local titleSection = CreateFrame("Frame", nil, contentFrame)
    titleSection:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    titleSection:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    titleSection:SetHeight(TITLE_HEIGHT)
    
    -- Add title background
    local titleBg = titleSection:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    -- Add scan and cancel buttons to title section
    self:CreateTitleButtons(titleSection)
    
    -- Create sidebar container
    local sidebarContainer = CreateFrame("Frame", "FLIPRSidebarContainer", contentFrame)
    sidebarContainer:SetPoint("TOPLEFT", titleSection, "BOTTOMLEFT", 0, 0)
    sidebarContainer:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", 0, BOTTOM_MARGIN)
    sidebarContainer:SetWidth(SIDEBAR_WIDTH)
    
    -- Add background for sidebar
    local sidebarBg = sidebarContainer:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
    
    -- Add "Groups" title to sidebar
    local groupsTitle = sidebarContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    groupsTitle:SetPoint("TOP", sidebarContainer, "TOP", 0, -5)
    groupsTitle:SetText("Groups")
    groupsTitle:SetTextColor(1, 0.82, 0, 1)
    
    -- Create results container
    local resultsContainer = CreateFrame("Frame", "FLIPRResultsContainer", contentFrame)
    resultsContainer:SetPoint("TOPLEFT", titleSection, "BOTTOMLEFT", SIDEBAR_WIDTH + 5, 0)
    resultsContainer:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, BOTTOM_MARGIN)
    
    -- Store frame references
    self.contentFrame = contentFrame
    self.titleSection = titleSection
    self.sidebarContainer = sidebarContainer
    self.resultsContainer = resultsContainer
    
    print("Created all main frames")
    
    -- Our tab's click handler
    fliprTab:SetScript("OnClick", function()
        print("FLIPR tab clicked")
        -- Hide all default frames
        AuctionHouseFrame.BrowseResultsFrame:Hide()
        AuctionHouseFrame.CategoriesList:Hide()
        AuctionHouseFrame.ItemBuyFrame:Hide()
        AuctionHouseFrame.ItemSellFrame:Hide()
        AuctionHouseFrame.CommoditiesBuyFrame:Hide()
        AuctionHouseFrame.CommoditiesSellFrame:Hide()
        AuctionHouseFrame.WoWTokenResults:Hide()
        AuctionHouseFrame.AuctionsFrame:Hide()
        
        PanelTemplates_SetTab(AuctionHouseFrame, numTabs)
        contentFrame:Show()
    end)

    -- Hook the AuctionHouseFrame display mode
    if not self.displayModeHooked then
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(frame, displayMode)
            if frame.selectedTab ~= numTabs then
                contentFrame:Hide()
            end
        end)
        self.displayModeHooked = true
    end

    table.insert(AuctionHouseFrame.Tabs, fliprTab)
    PanelTemplates_SetNumTabs(AuctionHouseFrame, numTabs)

    self.fliprTab = fliprTab

    -- Create UI sections in the correct order
    print("Creating UI sections...")
    self:CreateOptionsSection(sidebarContainer)
    self:CreateResultsSection(resultsContainer)
    print("=== CreateFLIPRTab END ===")
end

function FLIPR:CreateOptionsSection(parent)
    print("=== CreateOptionsSection START ===")
    -- Create scrollable container for the options, positioned below the "Groups" title
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -30)  -- Leave space for title
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -25, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(scrollChild)
    
    print("Created scroll frame and child")
    
    -- Create the group buttons in the scroll child
    self:CreateGroupButtons(scrollChild)
    print("=== CreateOptionsSection END ===")
end

function FLIPR:CreateResultsSection(parent)
    -- Create scrollable results area
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -25, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Store references
    self.scrollFrame = scrollFrame
    self.scrollChild = scrollChild
end

function FLIPR:CreateGroupButtons(parent)
    print("=== CreateGroupButtons START ===")
    -- Store reference to the group frame
    self.groupFrame = parent
    
    -- Build group structure
    self.groupStructure = {}
    print("Building group structure from available groups:")
    for groupName, groupData in pairs(self.availableGroups) do
        print(string.format("Processing root group: %s", groupName))
        self.groupStructure[groupName] = self:BuildGroupStructure(groupData)
    end
    
    -- Create checkboxes
    self:RefreshGroupList()
    print("=== CreateGroupButtons END ===")
end

function FLIPR:GetAvailableGroups()
    print("=== GetAvailableGroups START ===")
    local groups = {}
    
    -- Check if FliprDB exists
    if not FliprDB then
        print("ERROR: FliprDB is nil!")
        return groups
    end
    
    if not FliprDB.groups then
        print("ERROR: FliprDB.groups is nil!")
        return groups
    end
    
    print("Found groups in FliprDB:")
    for groupName, groupData in pairs(FliprDB.groups) do
        print(string.format("  Group: %s", groupName))
        if groupData.children then
            for childName, _ in pairs(groupData.children) do
                print(string.format("    - Child: %s", childName))
            end
        end
    end
    
    print("=== GetAvailableGroups END ===")
    return FliprDB.groups
end

function FLIPR:GetItemsFromGroup(groupData, path)
    local items = {}
    
    -- Helper function to recursively collect items
    local function collectItems(node)
        -- Add items from current node
        if node.items then
            for itemId, itemData in pairs(node.items) do
                items[itemId] = itemData
            end
        end
        
        -- Recursively process children
        if node.children then
            for _, childNode in pairs(node.children) do
                collectItems(childNode)
            end
        end
    end
    
    -- If no path specified, collect all items recursively
    if not path then
        collectItems(groupData)
        return items
    end
    
    -- Navigate to specific path
    local currentNode = groupData
    local pathParts = {strsplit("/", path)}
    
    for _, part in ipairs(pathParts) do
        if currentNode.children and currentNode.children[part] then
            currentNode = currentNode.children[part]
        else
            return {}  -- Path not found
        end
    end
    
    -- Collect items from the specified path
    collectItems(currentNode)
    return items
end

function FLIPR:BuildGroupStructure(groupData)
    if not groupData then
        print("ERROR: Received nil groupData in BuildGroupStructure")
        return nil
    end
    
    print(string.format("Building structure for: %s", groupData.name or "unnamed group"))
    local structure = {
        name = groupData.name,
        children = {},
        items = groupData.items or {}
    }
    
    -- Process children
    if groupData.children then
        print("  Processing children:")
        for childName, childData in pairs(groupData.children) do
            print(string.format("    Child: %s", childName))
            structure.children[childName] = self:BuildGroupStructure(childData)
        end
    else
        print("  No children found")
    end
    
    return structure
end

function FLIPR:RefreshGroupList()
    print("=== RefreshGroupList START ===")
    if not self.groupFrame then 
        print("ERROR: No group frame found!")
        return 
    end
    
    -- Clear existing checkboxes
    print("Clearing existing checkboxes")
    for _, child in pairs({self.groupFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = -10
    
    -- Helper function to add groups recursively
    local function addGroups(node, prefix, level)
        if not node then 
            print("ERROR: Nil node encountered")
            return yOffset 
        end
        
        print(string.format("Processing node: %s (level %d)", node.name or "unnamed", level))
        
        -- Create checkbox for current node if it has a name
        if node.name then
            local fullPath = prefix and (prefix .. "/" .. node.name) or node.name
            local displayName = node.name
            
            print(string.format("Creating checkbox for '%s' at level %d (path: %s)", displayName, level, fullPath))
            local container, expandButton = self:CreateGroupCheckbox(self.groupFrame, displayName, fullPath, level)
            container:SetPoint("TOPLEFT", self.groupFrame, "TOPLEFT", 0, yOffset)
            
            -- Update yOffset for next item
            yOffset = yOffset - 25
            
            -- If expanded and has children, add them
            if self.db.expandedGroups[fullPath] and node.children and next(node.children) then
                print(string.format("  Expanding children of %s", fullPath))
                for childName, childNode in pairs(node.children) do
                    print(string.format("    Processing child: %s", childName))
                    yOffset = addGroups(childNode, fullPath, level + 1)
                end
            else
                print(string.format("  Group %s is collapsed or has no children", fullPath))
            end
        else
            print("WARNING: Node has no name, skipping")
        end
        
        return yOffset
    end
    
    -- Add groups from saved variables
    print("Processing available groups:")
    for groupName, structure in pairs(self.groupStructure) do
        print(string.format("Processing root group: %s", groupName))
        yOffset = addGroups(structure, nil, 0)
    end
    
    -- Update parent frame height
    local newHeight = math.abs(yOffset) + 10
    print(string.format("Setting group frame height to: %d", newHeight))
    self.groupFrame:SetHeight(newHeight)
    print("=== RefreshGroupList END ===")
end

function FLIPR:CreateGroupCheckbox(parent, text, groupPath, level)
    -- Create container frame for checkbox and expand button
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(parent:GetWidth(), 20)
    
    -- Increase indentation (change 20 to a larger number for more indent)
    local INDENT_WIDTH = 30  -- Was 20 before, increased to 30
    
    -- Create expand button first if needed
    local expandButton
    
    -- Find the correct node in the structure
    local function findNode(path)
        if not path then return nil end
        
        local parts = {strsplit("/", path)}
        local currentNode = nil
        
        -- Start from root groups
        for groupName, groupData in pairs(self.availableGroups) do
            if groupData.name == parts[1] then
                currentNode = groupData
                break
            end
        end
        
        if not currentNode then return nil end
        
        -- Navigate through children
        for i = 2, #parts do
            if currentNode.children and currentNode.children[parts[i]] then
                currentNode = currentNode.children[parts[i]]
            else
                return nil
            end
        end
        
        return currentNode
    end
    
    local node = findNode(groupPath)
    
    -- Create expand button if the node has children
    if node and node.children and next(node.children) then
        expandButton = CreateFrame("Button", nil, container)
        expandButton:SetSize(16, 16)
        expandButton:SetPoint("LEFT", container, "LEFT", INDENT_WIDTH * level, 0)
        
        -- Set texture based on state
        local isExpanded = self.db.expandedGroups[groupPath]
        expandButton:SetNormalTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        
        expandButton:SetScript("OnClick", function()
            self.db.expandedGroups[groupPath] = not self.db.expandedGroups[groupPath]
            self:RefreshGroupList()
        end)
    end
    
    -- Create checkbox after expand button
    local checkbox = CreateFrame("CheckButton", nil, container, "ChatConfigCheckButtonTemplate")
    if expandButton then
        checkbox:SetPoint("LEFT", expandButton, "RIGHT", 2, 0)
    else
        checkbox:SetPoint("LEFT", container, "LEFT", INDENT_WIDTH * level, 0)
    end
    checkbox.Text:SetText(text)
    
    -- Set initial state
    checkbox:SetChecked(self.db.enabledGroups[groupPath] or false)
    
    -- Enhanced checkbox click handler for root group behavior
    checkbox:SetScript("OnClick", function()
        local checked = checkbox:GetChecked()
        
        -- If this is a root group (level == 0), toggle all children
        if level == 0 then
            self:ToggleAllChildren(groupPath, checked)
        else
            -- Normal behavior for non-root groups
            self:ToggleGroupState(groupPath, checked)
        end
    end)
    
    return container, expandButton
end

-- Add this new function to handle toggling all children
function FLIPR:ToggleAllChildren(rootPath, state)
    print(string.format("Toggling all children of %s to %s", rootPath, state and "enabled" or "disabled"))
    
    -- First toggle the root group itself
    self.db.enabledGroups[rootPath] = state
    
    -- Find the root node
    local rootNode = nil
    for groupName, groupData in pairs(self.availableGroups) do
        if groupData.name == rootPath then
            rootNode = groupData
            break
        end
    end
    
    if not rootNode then return end
    
    -- Helper function to recursively toggle groups
    local function toggleChildren(node, parentPath)
        if node.children then
            for childName, childNode in pairs(node.children) do
                local childPath = parentPath .. "/" .. childName
                self.db.enabledGroups[childPath] = state
                toggleChildren(childNode, childPath)
            end
        end
    end
    
    -- Toggle all children
    toggleChildren(rootNode, rootPath)
    
    -- Refresh the database and UI
    self:InitializeDB()
    self:RefreshGroupList()
end

function FLIPR:ToggleGroupState(groupPath, checked)
    print(string.format("Toggling group: %s to %s", groupPath, checked and "enabled" or "disabled"))
    
    -- Update enabled state
    self.db.enabledGroups[groupPath] = checked
    
    -- Reinitialize database to update available items
    self:InitializeDB()
end

function FLIPR:UpdateGroupContainerHeights()
    -- Recursively update container heights when expanding/collapsing
    local function UpdateContainerHeight(container)
        local height = 0
        for _, child in pairs({container:GetChildren()}) do
            if child:IsShown() then
                local childBottom = math.abs((select(5, child:GetPoint())))
                local childHeight = child:GetHeight()
                height = math.max(height, childBottom + childHeight)
            end
        end
        container:SetHeight(height)
        
        -- Update parent containers
        local parent = container:GetParent()
        if parent and parent.UpdateHeight then
            parent:UpdateHeight()
        end
    end
    
    -- Update all visible containers
    for _, button in pairs(self.groupButtons or {}) do
        local container = button:GetParent()
        if container then
            UpdateContainerHeight(container)
        end
    end
end

function FLIPR:CreateOptionsUI()
    -- ... (keep existing UI creation code)
    
    -- Create group buttons
    self:CreateGroupButtons(self.optionsFrame)
    
    -- ... (rest of your UI code)
end

function FLIPR:CreateTitleButtons(titleSection)
    -- Create scan button
    local scanButton = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    scanButton:SetSize(120, 22)
    scanButton:SetPoint("LEFT", titleSection, "LEFT", 10, 0)
    scanButton:SetText("Scan Items")
    
    -- Create cancel button
    local cancelButton = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    cancelButton:SetSize(25, 22)
    cancelButton:SetPoint("LEFT", scanButton, "RIGHT", 5, 0)
    cancelButton:SetText("X")
    
    -- Create GROUP TEST button
    local groupTestButton = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    groupTestButton:SetSize(100, 22)
    groupTestButton:SetPoint("LEFT", cancelButton, "RIGHT", 5, 0)
    groupTestButton:SetText("GROUP TEST")
    
    local defaultGroupString = "vj9VojtquCy4OUHcALcl5kWm)FMd9yNbJFKOfM4QIXpsqGGwyTvED4v0gVICb25DKUNmN93zNZjZrFp9FxE)4BVAY1tpz9zkZ5dhV8P))WY3NV8LHtwmB4nR2Sy2x3958rATky0)8N6F43ESj5T21NEW51tx96ZVLR6A6LPFpTPykwOafvH6cnfAl0vyxFDArLAQ2rNvfAQ2mFKngu2dU32TNMIHyZGojzfDipkGszLmilIVlr)AhOS0iYkCde6SKZMuEuarvTgzqwucrcdjmu1swl)nNcrchFNNZIre9lr1e9J9s7hIkj4(XUkjmhIdr)ydjkfsJSihkGY)xrtwdjmKWqct(olSRelvzxjo6IRuLSE6mVRe2AcBdHDGKNY2HuH2FdCbv39ZBIbBwB73JTQD229WpenTpN71j)ofDX2bV6IJRBgu3uv30RUF)()("
    
    -- Add click handler for GROUP TEST
    groupTestButton:SetScript("OnClick", function()
        local AceGUI = LibStub("AceGUI-3.0")
        local tempTSMData = nil  -- Will store the temporary TSM table
        
        -- Create a container frame
        local frame = AceGUI:Create("Frame")
        frame:SetTitle("TSM Group Import Test")
        frame:SetLayout("Flow")
        frame:SetWidth(500)
        frame:SetHeight(300)
        
        -- Add instructions text
        local label = AceGUI:Create("Label")
        label:SetText("Paste TSM Group Export String:")
        label:SetFullWidth(true)
        frame:AddChild(label)
        
        -- Add multiline editbox
        local editbox = AceGUI:Create("MultiLineEditBox")
        editbox:SetLabel("")
        editbox:SetFullWidth(true)
        editbox:SetHeight(200)
        editbox:SetText(defaultGroupString)  -- Set default text
        frame:AddChild(editbox)
        
        -- Add test button
        local testButton = AceGUI:Create("Button")
        testButton:SetText("Test Import")
        testButton:SetWidth(150)
        testButton:SetCallback("OnClick", function()
            local success, data = TestTSMImport(editbox:GetText())
            if success then
                tempTSMData = data  -- Store the imported data temporarily
                print("TSM data stored in temporary variable")
            end
        end)
        frame:AddChild(testButton)
        
        -- Add convert button to the same frame
        local convertBtn = AceGUI:Create("Button")
        convertBtn:SetText("Convert to Flipr")
        convertBtn:SetWidth(150)
        convertBtn:SetCallback("OnClick", function()
            if tempTSMData then
                print("Converting temporary TSM data to Flipr format...")
                local fliprData = ConvertToFliprFormat(tempTSMData)
                if fliprData then
                    if SaveImportedGroup(fliprData) then
                        print("Group successfully imported and saved!")
                    else
                        print("Error saving group data")
                    end
                end
            else
                print("No TSM data available - click Test Import first!")
            end
        end)
        frame:AddChild(convertBtn)
    end)
    
    -- Add progress text
    local progressText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressText:SetPoint("LEFT", groupTestButton, "RIGHT", 10, 0)
    progressText:SetText("")  -- Start empty
    progressText:SetTextColor(0.7, 0.7, 0.7, 1)
    self.scanProgressText = progressText
    
    -- Add timer text
    local timerText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerText:SetPoint("LEFT", progressText, "RIGHT", 10, 0)
    timerText:SetText("")
    timerText:SetTextColor(0.7, 0.7, 0.7, 1)
    self.scanTimerText = timerText
    
    -- Create OnUpdate handler for the timer
    local timerFrame = CreateFrame("Frame")
    timerFrame:Hide()
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        if FLIPR.isScanning and not FLIPR.isPaused then
            FLIPR.scanTimer = GetTime() - FLIPR.scanStartTime
            local minutes = math.floor(FLIPR.scanTimer / 60)
            local seconds = math.floor(FLIPR.scanTimer % 60)
            FLIPR.scanTimerText:SetText(string.format("Time: %d:%02d", minutes, seconds))
        end
    end)
    self.timerFrame = timerFrame
    
    -- Add version text
    local versionText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("RIGHT", titleSection, "RIGHT", -10, 0)
    versionText:SetText(addon.version)
    versionText:SetTextColor(0.7, 0.7, 0.7, 1)
    
    -- Create buy button
    local buyButton = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    buyButton:SetSize(80, 22)
    buyButton:SetPoint("RIGHT", versionText, "LEFT", -10, 0)
    buyButton:SetText("Buy")
    
    -- Add click handler
    buyButton:SetScript("OnClick", function()
        if not self.selectedItem then
            print("No items selected!")
            return
        end
        
        if not self.selectedItem.itemID then
            print("Selected item has no itemID!")
            return
        end
        
        -- Debug output
        print("Attempting to buy item:", self.selectedItem.itemID)
        
        -- Call BuySelectedAuctions from Purchase.lua
        self:BuySelectedAuctions()
    end)
    
    -- Store references and set up click handlers
    self.scanButton = scanButton
    self.buyButton = buyButton
    scanButton:SetScript("OnClick", function() self:ScanItems() end)
    cancelButton:SetScript("OnClick", function() self:CancelScan() end)
end

function FLIPR:HandleItemSelection(itemID, row)
    -- If clicking currently selected item, deselect everything
    if self.selectedItem and self.selectedItem.itemID == itemID then
        -- Clean up current selection
        row.selectionTexture:Hide()
        row.defaultBg:Show()
        
        -- Clean up last selection if it exists
        if self.lastSelectedItem and self.lastSelectedItem.itemID ~= itemID then
            local lastRowData = self.itemRows[self.lastSelectedItem.itemID]
            if lastRowData then
                local lastRow = lastRowData.frame:GetChildren()
                if lastRow then
                    lastRow.selectionTexture:Hide()
                    lastRow.defaultBg:Show()
                end
            end
        end
        
        self:CollapseDropdown()
        self.lastSelectedItem = nil
        self.selectedItem = nil
        return
    end
    
    -- Store current selection as last selection before changing
    if self.selectedItem then
        self.lastSelectedItem = self.selectedItem
        -- Clean up last selection's visuals
        local lastRowData = self.itemRows[self.lastSelectedItem.itemID]
        if lastRowData then
            local lastRow = lastRowData.frame:GetChildren()
            if lastRow then
                lastRow.selectionTexture:Hide()
                lastRow.defaultBg:Show()
            end
        end
    end
    
    -- Collapse any existing dropdown
    self:CollapseDropdown()
    
    -- Set up new selection
    row.selectionTexture:Show()
    row.defaultBg:Hide()
    self.selectedItem = row.itemData
    self:ExpandDropdown(itemID)
end

function FLIPR:CreateProfitableItemRow(flipOpportunity, results)
    -- Play sound for profitable item
    PlaySoundFile("Interface\\AddOns\\FLIPR\\sounds\\VO_GoblinVenM_Greeting06.ogg", "Master")
    
    local itemID = tonumber(results[1].itemID)
    print("Creating row for itemID:", itemID)
    
    -- Create row container
    local rowContainer = CreateFrame("Frame", nil, self.scrollChild)
    rowContainer:SetSize(self.scrollChild:GetWidth(), ROW_HEIGHT)
    
    -- Store row index
    self.profitableItemCount = (self.profitableItemCount or 0) + 1
    rowContainer.rowIndex = self.profitableItemCount
    
    -- Create the main row button
    local row = CreateFrame("Button", nil, rowContainer)
    row:SetAllPoints(rowContainer)
    
    -- Enable mouse interaction and register for click events
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Default background
    local defaultBg = row:CreateTexture(nil, "BACKGROUND")
    defaultBg:SetAllPoints()
    defaultBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    row.defaultBg = defaultBg
    
    -- Selection background
    local selection = row:CreateTexture(nil, "BACKGROUND")
    selection:SetAllPoints()
    selection:SetColorTexture(0.7, 0.7, 0.1, 0.2)
    selection:Hide()
    row.selectionTexture = selection

    -- Item icon
    local iconSize = ROW_HEIGHT - 2
    local itemIcon = row:CreateTexture(nil, "OVERLAY")
    itemIcon:SetSize(iconSize, iconSize)
    itemIcon:SetPoint("LEFT", row, "LEFT", 2, 0)
    
    -- Item name (left-aligned)
    local itemLinkButton = CreateFrame("Button", nil, row)
    itemLinkButton:SetSize(150, ROW_HEIGHT)  -- Fixed width for item name
    itemLinkButton:SetPoint("LEFT", itemIcon, "RIGHT", 5, 0)
    itemLinkButton:EnableMouse(true)
    itemLinkButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    local nameText = itemLinkButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetAllPoints()
    
    -- Store item data with the row
    row.itemData = {
        itemID = itemID,
        minPrice = results[1].minPrice,
        totalQuantity = results[1].totalQuantity,
        auctionID = results[1].auctionID,
        isCommodity = results[1].isCommodity,
        selected = false,
        allAuctions = results
    }
    
    -- Store in our itemRows table
    self.itemRows[itemID] = {
        frame = rowContainer,
        row = row,
        rowIndex = self.profitableItemCount,
        results = results,
        flipOpportunity = flipOpportunity
    }
    
    -- Create item object
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        local itemLink = item:GetItemLink()
        nameText:SetText(itemLink)
        itemIcon:SetTexture(item:GetItemIcon())
    end)
    
    -- Make the text interactive
    itemLinkButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(item:GetItemLink())
        GameTooltip:Show()
    end)
    
    itemLinkButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handlers
    local function handleClick()
        print("Row clicked for itemID:", itemID)
        print("Current selectedItem:", FLIPR.selectedItem and FLIPR.selectedItem.itemID)
        print("Current expandedItemID:", FLIPR.expandedItemID)
        
        -- Clear previous selection's visual state if it exists
        if FLIPR.selectedItem and FLIPR.itemRows[FLIPR.selectedItem.itemID] then
            local prevRowData = FLIPR.itemRows[FLIPR.selectedItem.itemID]
            if prevRowData.row then
                print("Clearing previous selection:", FLIPR.selectedItem.itemID)
                prevRowData.row.selectionTexture:Hide()
                prevRowData.row.defaultBg:Show()
            end
        end
        
        if FLIPR.expandedItemID == itemID then
            -- Collapse if clicking same item
            print("Collapsing dropdown for:", itemID)
            FLIPR:CollapseDropdown()
            row.itemData.selected = false
            row.selectionTexture:Hide()
            row.defaultBg:Show()
            FLIPR.selectedItem = nil
        else
            -- Collapse previous and expand new
            print("Expanding dropdown for:", itemID)
            FLIPR:CollapseDropdown()
            FLIPR:ExpandDropdown(itemID)
            row.itemData.selected = true
            row.selectionTexture:Show()
            row.defaultBg:Hide()
            FLIPR.selectedItem = row.itemData
            
            -- Add this section to initialize auction data
            local rowData = FLIPR.itemRows[itemID]
            if rowData and rowData.results and rowData.results[1] then
                local initialAuction = rowData.results[1]
                rowData.selectedAuctions = {initialAuction}
                rowData.totalCost = initialAuction.minPrice * initialAuction.totalQuantity
                rowData.totalQuantity = initialAuction.totalQuantity
                
                -- Update selectedItem with the same data
                FLIPR.selectedItem.selectedAuctions = {initialAuction}
                FLIPR.selectedItem.totalQuantity = initialAuction.totalQuantity
                FLIPR.selectedItem.totalCost = initialAuction.minPrice * initialAuction.totalQuantity
                FLIPR.selectedItem.auctions = rowData.results
                
                print("=== DEBUG: Initialized auction data on main row click ===")
                print(string.format("Selected auction price: %s, qty: %d", 
                    GetCoinTextureString(initialAuction.minPrice),
                    initialAuction.totalQuantity
                ))
            end
        end
    end
    
    -- Set click handlers
    itemLinkButton:SetScript("OnClick", function(self, button)
        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(item:GetItemLink())
            return
        end
        handleClick()
    end)
    
    row:SetScript("OnClick", handleClick)
    
    -- Price text (center-aligned)
    local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
    priceText:SetText(GetCoinTextureString(flipOpportunity.avgBuyPrice))
    
    -- Stock text
    local stockText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stockText:SetPoint("LEFT", priceText, "RIGHT", 10, 0)
    stockText:SetText(string.format("Inv:%d/%d", flipOpportunity.currentInventory, flipOpportunity.maxInventory))
    
    -- Sale Rate text (raw value from TSM)
    local saleRateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    saleRateText:SetPoint("LEFT", stockText, "RIGHT", 10, 0)
    saleRateText:SetText(string.format("%.3f", flipOpportunity.saleRate))  -- Force 3 decimal places
    
    -- Profit text with ROI
    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profitText:SetPoint("LEFT", saleRateText, "RIGHT", 10, 0)
    profitText:SetText(string.format(
        "%s (ROI: %d%%)",
        GetCoinTextureString(flipOpportunity.totalProfit),
        flipOpportunity.roi
    ))
    
    -- Initial position
    self:UpdateRowPositions()
end

function FLIPR:UpdateRowPositions()
    local expandedIndex = self.expandedItemID and self.itemRows[self.expandedItemID].rowIndex or 0
    local expandedRowData = self.expandedItemID and self.itemRows[self.expandedItemID]
    local dropdownHeight = expandedRowData and (math.min(#expandedRowData.results, MAX_DROPDOWN_ROWS) * ROW_HEIGHT) or 0
    
    -- Update positions for all rows
    for id, rowData in pairs(self.itemRows) do
        local yOffset = (rowData.rowIndex - 1) * ROW_HEIGHT
        
        -- If this row is below an expanded row, add dropdown height
        if expandedIndex > 0 and rowData.rowIndex > expandedIndex then
            yOffset = yOffset + dropdownHeight + DROPDOWN_PADDING
        end
        
        rowData.frame:ClearAllPoints()
        rowData.frame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -yOffset)
        rowData.frame:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, -yOffset)
    end
    
    -- Update scroll child height
    local totalHeight = (self.profitableItemCount * ROW_HEIGHT)
    if self.expandedItemID then
        totalHeight = totalHeight + dropdownHeight + DROPDOWN_PADDING
    end
    self.scrollChild:SetHeight(math.max(1, totalHeight))
end

function FLIPR:CollapseDropdown()
    if not self.expandedItemID then return end
    print("Collapsing dropdown for itemID:", self.expandedItemID)
    
    local rowData = self.itemRows[self.expandedItemID]
    if rowData and rowData.dropdown then
        rowData.dropdown:Hide()
        rowData.dropdown:SetParent(nil)
        rowData.dropdown = nil
    end
    
    self.expandedItemID = nil
    self:UpdateRowPositions()
end

function FLIPR:ExpandDropdown(itemID)
    print("=== DEBUG: ExpandDropdown ===")
    print("ItemID:", itemID)
    local rowData = self.itemRows[itemID]
    print("Number of results:", rowData and #rowData.results or "no results")
    
    -- Get actual number of auctions (capped at MAX_DROPDOWN_ROWS)
    local numAuctions = math.min(#rowData.results, MAX_DROPDOWN_ROWS)
    print("Creating dropdown with", numAuctions, "rows")
    
    -- Create dropdown
    local dropdown = CreateFrame("Frame", nil, rowData.frame)
    dropdown:SetPoint("TOPLEFT", rowData.frame, "BOTTOMLEFT", 0, 0)
    dropdown:SetPoint("TOPRIGHT", rowData.frame, "BOTTOMRIGHT", 0, 0)
    dropdown:SetHeight(numAuctions * ROW_HEIGHT)
    
    -- Set background
    local bg = dropdown:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
    
    -- Create child auction rows
    self:CreateDropdownRows(dropdown, rowData.results)
    
    rowData.dropdown = dropdown
    self.expandedItemID = itemID
    
    -- Make sure dropdown is shown
    dropdown:Show()
    print("Dropdown created and shown")
    
    -- Update positions after creating dropdown
    self:UpdateRowPositions()
    
    -- Auto-select first row
    self:SelectAuctionRange(dropdown, 1)
end

function FLIPR:CreateDropdownRows(dropdown, results)
    local numRows = math.min(MAX_DROPDOWN_ROWS, #results)
    dropdown.rows = {}
    
    for i = 1, numRows do
        local auction = results[i]
        local row = CreateFrame("Button", nil, dropdown)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 0, -ROW_HEIGHT * (i-1))
        row:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", 0, -ROW_HEIGHT * (i-1))
        
        -- Background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
        row.defaultBg = bg
        
        -- Selection highlight
        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.7, 0.7, 0.1, 0.2)
        highlight:Hide()
        row.selectionTexture = highlight
        
        -- Price text
        local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        priceText:SetPoint("LEFT", row, "LEFT", 155, 0)  -- Align with main row price
        priceText:SetText(GetCoinTextureString(auction.minPrice))
        
        -- Quantity text
        local quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        quantityText:SetPoint("LEFT", priceText, "RIGHT", 10, 0)
        quantityText:SetText("x" .. auction.totalQuantity)
        
        -- Store data
        row.auctionData = auction
        row.index = i
        dropdown.rows[i] = row
        
        -- Click handler
        row:SetScript("OnClick", function()
            self:SelectAuctionRange(dropdown, i)
        end)
    end
end

function FLIPR:SelectAuctionRange(dropdown, selectedIndex)
    print("=== DEBUG: SelectAuctionRange ===")
    print("SelectedIndex:", selectedIndex)
    print("Number of dropdown rows:", #dropdown.rows)
    
    local selectedAuctions = {}
    local totalCost = 0
    local totalQuantity = 0
    
    -- First, clear all selected flags
    local rowData = self.itemRows[self.expandedItemID]
    if rowData and rowData.auctions then
        for _, auction in ipairs(rowData.auctions) do
            auction.selected = false
        end
    end
    
    -- Update selections and visuals
    for i, row in ipairs(dropdown.rows) do
        local isSelected = i <= selectedIndex
        row.selectionTexture:SetShown(isSelected)  -- Show/hide selection highlight
        
        if isSelected then
            selectedAuctions[i] = row.auctionData
            row.auctionData.selected = true  -- Set selected flag
            totalCost = totalCost + (row.auctionData.minPrice * row.auctionData.totalQuantity)
            totalQuantity = totalQuantity + row.auctionData.totalQuantity
        else
            row.selectionTexture:Hide()  -- Ensure unselected rows have no highlight
        end
    end
    
    -- Store selected auctions info
    if rowData then
        rowData.selectedAuctions = selectedAuctions
        rowData.totalCost = totalCost
        rowData.totalQuantity = totalQuantity
        
        -- Update the main itemData to reflect all selected auctions
        if self.selectedItem and self.selectedItem.itemID == self.expandedItemID then
            self.selectedItem.totalQuantity = totalQuantity
            self.selectedItem.selectedAuctions = selectedAuctions
            self.selectedItem.totalCost = totalCost
            self.selectedItem.auctions = rowData.auctions  -- Make sure auctions are passed through
        end
    end
    
    print("=== DEBUG: Stored Selected Auctions ===")
    if self.selectedItem and self.selectedItem.selectedAuctions then
        print("Number of selected auctions:", #self.selectedItem.selectedAuctions)
        for i, auction in pairs(self.selectedItem.selectedAuctions) do
            print(string.format("  [%d] price: %s, qty: %d", 
                i, 
                GetCoinTextureString(auction.minPrice), 
                auction.totalQuantity
            ))
        end
    else
        print("No auctions stored!")
    end
end

function FLIPR:RescanItem(itemID)
    local rowData = self.itemRows[itemID]
    if not rowData then return end
    
    -- Remove the row
    rowData.frame:Hide()
    rowData.frame:SetParent(nil)
    self.itemRows[itemID] = nil
    
    -- Rescan the item
    if rowData.flipOpportunity.isCommodity then
        C_AuctionHouse.SendSearchQuery(nil, {}, true, itemID)
    else
        local itemKey = C_AuctionHouse.MakeItemKey(itemID)
        C_AuctionHouse.SendSearchQuery(itemKey, {}, true)
    end
end

function FLIPR:BuySelectedAuctions()
    if not self.selectedItem then
        print("No items selected!")
        return
    end
    
    local itemData = self.selectedItem
    local totalCost = 0
    local totalQuantity = 0
    
    -- DETAILED DEBUG OUTPUT
    print("=== DEBUG: Buy Selected Auctions ===")
    print("ExpandedItemID:", self.expandedItemID)
    print("Selected Item ID:", itemData.itemID)
    
    if itemData.selectedAuctions then
        print("Number of selected auctions:", #itemData.selectedAuctions)
        for i, auction in pairs(itemData.selectedAuctions) do
            print(string.format("Auction[%d]: Price=%s, Qty=%d, Total=%s",
                i,
                GetCoinTextureString(auction.minPrice),
                auction.totalQuantity,
                GetCoinTextureString(auction.minPrice * auction.totalQuantity)
            ))
        end
    else
        print("selectedAuctions is nil!")
        -- Let's check what we do have
        for k,v in pairs(itemData) do
            print("itemData has key:", k)
        end
    end
    print("=== End Debug ===")
    
    -- Show confirmation frame
    if not self.buyConfirmFrame then
        self.buyConfirmFrame = self:CreateBuyConfirmationFrame()
    end
    
    local itemName = GetItemInfo(itemData.itemID)
    if not itemName then
        print("Error: Could not get item info")
        return
    end
    
    -- Calculate totals and build price breakdown text
    local priceBreakdown = "Price Breakdown:"
    if itemData.selectedAuctions then
        for i, auction in pairs(itemData.selectedAuctions) do
            local subtotal = auction.minPrice * auction.totalQuantity
            totalCost = totalCost + subtotal
            totalQuantity = totalQuantity + auction.totalQuantity
            priceBreakdown = priceBreakdown .. string.format(
                "\n%s x%d = %s", 
                GetCoinTextureString(auction.minPrice),
                auction.totalQuantity,
                GetCoinTextureString(subtotal)
            )
        end
    end
    
    self.buyConfirmFrame.itemText:SetText("Item: " .. itemName)
    self.buyConfirmFrame.qtyText:SetText(string.format("Total Quantity: %d", totalQuantity))
    self.buyConfirmFrame.priceText:SetText(priceBreakdown)
    self.buyConfirmFrame.totalText:SetText(string.format("Total Cost: %s", GetCoinTextureString(totalCost)))
    
    self.buyConfirmFrame:Show()
end
 