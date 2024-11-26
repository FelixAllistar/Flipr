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
    print("Available groups:")
    for tableName, groupData in pairs(self.availableGroups) do
        print("  Found table:", tableName)
        print("  Group data name:", groupData.name)
        print("  Keys in group data:")
        for k, v in pairs(groupData) do
            if type(v) == "table" then
                print("    -", k, "(table)")
            else
                print("    -", k, "=", v)
            end
        end
        self.groupStructure[tableName] = self:BuildGroupStructure(groupData)
    end
    
    -- Create checkboxes
    self:RefreshGroupList()
    print("=== CreateGroupButtons END ===")
end

function FLIPR:BuildGroupStructure(groupData)
    print("Building structure for:", groupData.name)
    local structure = {
        name = groupData.name,
        children = {},
        items = groupData.items or {}
    }
    
    -- Process each subgroup
    for key, value in pairs(groupData) do
        -- Skip special keys and non-table values
        if type(value) == "table" and key ~= "items" and key ~= "name" then
            -- If it has a name field, it's a subgroup
            if value.name then
                print("  Found subgroup:", value.name)
                -- Store using the actual name as the key
                structure.children[value.name] = {
                    name = value.name,
                    children = {},
                    items = value.items or {}
                }
                -- Process children recursively
                for subKey, subValue in pairs(value) do
                    if type(subValue) == "table" and subKey ~= "items" and subKey ~= "name" then
                        if subValue.name then
                            structure.children[value.name].children[subValue.name] = self:BuildGroupStructure(subValue)
                        end
                    end
                end
            end
        end
    end
    
    -- Debug print children
    if next(structure.children) then
        print("  Children for", groupData.name .. ":")
        for childName, childData in pairs(structure.children) do
            print("    -", childName)
            if next(childData.children) then
                for grandChildName, _ in pairs(childData.children) do
                    print("      *", grandChildName)
                end
            end
        end
    else
        print("  No children for", groupData.name)
    end
    
    return structure
end

function FLIPR:RefreshGroupList()
    if not self.groupFrame then 
        print("No group frame found!")
        return 
    end
    
    print("Refreshing group list...")
    
    -- Clear existing checkboxes
    for _, child in pairs({self.groupFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = -10
    
    -- Helper function to add groups recursively
    local function addGroups(node, prefix, level, tableName)
        if not node then 
            print("Nil node encountered")
            return yOffset 
        end
        
        -- Create checkbox for current node if it has a name
        if node.name then
            local fullPath = prefix and (prefix .. "/" .. node.name) or node.name
            local displayName = node.name
            
            print(string.format("Creating checkbox for '%s' at level %d", displayName, level))
            local container, expandButton = self:CreateGroupCheckbox(self.groupFrame, displayName, fullPath, tableName, level)
            container:SetPoint("TOPLEFT", self.groupFrame, "TOPLEFT", 0, yOffset)
            
            if expandButton then
                print("  Created expand button for", displayName)
            end
            
            -- Update yOffset for next item
            yOffset = yOffset - 25
            
            -- If expanded and has children, add them
            if self.db.expandedGroups[fullPath] and next(node.children) then
                print("  Group is expanded:", fullPath)
                for childName, childNode in pairs(node.children) do
                    yOffset = addGroups(childNode, fullPath, level + 1, tableName)
                end
            else
                print("  Group is collapsed:", fullPath)
            end
        end
        
        return yOffset
    end
    
    -- Add groups for each table
    print("Processing available groups:")
    for tableName, structure in pairs(self.groupStructure) do
        print("Processing table:", tableName)
        yOffset = addGroups(structure, nil, 0, tableName)
    end
    
    -- Update parent frame height
    self.groupFrame:SetHeight(math.abs(yOffset) + 10)
end

function FLIPR:CreateGroupCheckbox(parent, text, groupPath, tableName, level)
    print("Creating checkbox for:", text, "path:", groupPath)
    
    -- Create container frame for checkbox and expand button
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(parent:GetWidth(), 20)
    
    -- Create expand button first if needed
    local expandButton
    local structure = self.groupStructure[tableName]
    if not structure then
        print("  No structure found for table:", tableName)
        return container
    end
    
    -- Find the correct node in the structure
    local node = structure
    if groupPath ~= structure.name then
        local pathParts = {strsplit("/", groupPath)}
        print("  Looking for path parts:", table.concat(pathParts, ", "))
        
        -- Skip the first part if it matches the root
        local startIndex = 1
        if pathParts[1] == structure.name then
            startIndex = 2
        end
        
        -- Navigate through children using names
        for i = startIndex, #pathParts do
            if node and node.children and node.children[pathParts[i]] then
                node = node.children[pathParts[i]]
                print("    Found child:", pathParts[i])
            else
                print("    Could not find child:", pathParts[i])
                node = nil
                break
            end
        end
    end
    
    -- Create expand button if the node has children
    if node and node.children and next(node.children) then
        print("  Creating expand button for", text, "(has children)")
        expandButton = CreateFrame("Button", nil, container)
        expandButton:SetSize(16, 16)
        expandButton:SetPoint("LEFT", container, "LEFT", 20 * level, 0)
        
        -- Set texture based on state
        local isExpanded = self.db.expandedGroups[groupPath]
        expandButton:SetNormalTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        
        expandButton:SetScript("OnClick", function()
            print("Expand button clicked for:", groupPath)
            self.db.expandedGroups[groupPath] = not self.db.expandedGroups[groupPath]
            self:RefreshGroupList()
        end)
    end
    
    -- Create checkbox after expand button
    local checkbox = CreateFrame("CheckButton", nil, container, "ChatConfigCheckButtonTemplate")
    if expandButton then
        checkbox:SetPoint("LEFT", expandButton, "RIGHT", 2, 0)
    else
        checkbox:SetPoint("LEFT", container, "LEFT", 20 * level, 0)
    end
    checkbox.Text:SetText(text)
    
    -- Set initial state
    checkbox:SetChecked(self.db.enabledGroups[groupPath] or false)
    
    -- Checkbox click handler
    checkbox:SetScript("OnClick", function()
        local checked = checkbox:GetChecked()
        print("Checkbox clicked:", groupPath, checked)
        self:ToggleGroupState(tableName, groupPath, checked)
    end)
    
    return container, expandButton
end

function FLIPR:ToggleGroupState(tableName, groupPath, checked)
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
            TestTSMImport(editbox:GetText())
        end)
        frame:AddChild(testButton)
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
        
        -- Rescan the item before showing buy confirmation
        self:RescanSingleItem(self.selectedItem.itemID)
        
        if not self.buyConfirmFrame then
            self.buyConfirmFrame = self:CreateBuyConfirmationFrame()
        end
        
        local itemName = GetItemInfo(self.selectedItem.itemID)
        if not itemName then
            print("Error: Could not get item info")
            return
        end
        
        local totalQty = self.selectedItem.totalQuantity or 0
        local totalPrice = (self.selectedItem.minPrice or 0) * totalQty
        
        self.buyConfirmFrame.itemText:SetText("Item: " .. itemName)
        self.buyConfirmFrame.qtyText:SetText(string.format("Quantity: %d", totalQty))
        self.buyConfirmFrame.priceText:SetText(string.format("Price Each: %s", GetCoinTextureString(self.selectedItem.minPrice)))
        self.buyConfirmFrame.totalText:SetText(string.format("Total: %s", GetCoinTextureString(totalPrice)))
        
        self.buyConfirmFrame:Show()
    end)
    
    -- Store references and set up click handlers
    self.scanButton = scanButton
    self.buyButton = buyButton
    scanButton:SetScript("OnClick", function() self:ScanItems() end)
    cancelButton:SetScript("OnClick", function() self:CancelScan() end)
end

function FLIPR:CreateProfitableItemRow(flipOpportunity, results)
    -- Play sound for profitable item
    PlaySoundFile("Interface\\AddOns\\FLIPR\\sounds\\VO_GoblinVenM_Greeting06.ogg", "Master")
    
    local itemID = results[1].itemID
    
    -- Create row container
    local rowContainer = CreateFrame("Frame", nil, self.scrollChild)
    rowContainer:SetSize(self.scrollChild:GetWidth(), ROW_HEIGHT)
    
    -- Store row index
    self.profitableItemCount = (self.profitableItemCount or 0) + 1
    rowContainer.rowIndex = self.profitableItemCount
    
    -- Store in our itemRows table
    self.itemRows[itemID] = {
        frame = rowContainer,
        rowIndex = self.profitableItemCount,
        results = results,
        flipOpportunity = flipOpportunity
    }
    
    -- Initial position
    self:UpdateRowPositions()

    -- Create the main row button
    local row = CreateFrame("Button", nil, rowContainer)
    row:SetAllPoints(rowContainer)
    
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

    -- Item name (left-aligned)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    local itemID = results[1].itemID
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        local itemLink = item:GetItemLink()
        nameText:SetText(itemLink)  -- This will show a clickable link with proper quality color
    end)
    
    -- Price text (center-aligned)
    local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
    priceText:SetText(GetCoinTextureString(flipOpportunity.avgBuyPrice))
    
    -- Stock text
    local stockText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stockText:SetPoint("LEFT", priceText, "RIGHT", 10, 0)
    stockText:SetText(string.format("Inv:%d/%d", flipOpportunity.currentInventory, flipOpportunity.maxInventory))
    
    -- Sale Rate text (just the decimal)
    local saleRateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    saleRateText:SetPoint("LEFT", stockText, "RIGHT", 10, 0)
    saleRateText:SetText(string.format(".%d", math.floor(flipOpportunity.saleRate * 1000)))
    
    -- Profit text with ROI
    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profitText:SetPoint("LEFT", saleRateText, "RIGHT", 10, 0)
    profitText:SetText(string.format(
        "%s (ROI: %d%%)",
        GetCoinTextureString(flipOpportunity.totalProfit),
        flipOpportunity.roi
    ))

    -- Store item data with the row
    row.itemData = {
        itemID = results[1].itemID,
        minPrice = results[1].minPrice,
        totalQuantity = results[1].totalQuantity,
        auctionID = results[1].auctionID,
        isCommodity = results[1].isCommodity,
        selected = false,
        allAuctions = results
    }

    -- Click handler for row selection
    row:SetScript("OnClick", function()
        if self.expandedItemID == itemID then
            -- Collapse if clicking same item
            self:CollapseDropdown()
            row.itemData.selected = false
            row.selectionTexture:Hide()
            row.defaultBg:Show()
            self.selectedItem = nil
        else
            -- Collapse previous and expand new
            self:CollapseDropdown()
            self:ExpandDropdown(itemID)
            row.itemData.selected = true
            row.selectionTexture:Show()
            row.defaultBg:Hide()
            self.selectedItem = row.itemData
        end
    end)
    
    -- Auto-scroll if we're near the bottom
    if self.scrollFrame then
        local scrollBar = self.scrollFrame.ScrollBar
        if scrollBar then
            local currentScroll = scrollBar:GetValue() or 0
            local maxScroll = (self.profitableItemCount * ROW_HEIGHT) - self.scrollFrame:GetHeight()
            
            -- If we're within 100 pixels of the bottom, or if this is the first item
            if maxScroll <= 0 or (maxScroll - currentScroll) < 100 then
                -- Use After to ensure the scroll happens after the frame updates
                C_Timer.After(0.1, function()
                    if scrollBar and scrollBar.SetValue then
                        scrollBar:SetValue(maxScroll)
                    end
                end)
            end
        end
    end
end

function FLIPR:UpdateRowPositions()
    local expandedIndex = self.expandedItemID and self.itemRows[self.expandedItemID].rowIndex or 0
    
    for id, rowData in pairs(self.itemRows) do
        local yOffset = (rowData.rowIndex - 1) * ROW_HEIGHT
        
        -- If this row is below an expanded row, add dropdown height
        if expandedIndex > 0 and rowData.rowIndex > expandedIndex then
            yOffset = yOffset + DROPDOWN_TOTAL_HEIGHT
        end
        
        rowData.frame:ClearAllPoints()
        rowData.frame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -yOffset)
        rowData.frame:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, -yOffset)
    end
    
    -- Update scroll child height
    local totalHeight = (self.profitableItemCount * ROW_HEIGHT)
    if self.expandedItemID then
        totalHeight = totalHeight + DROPDOWN_TOTAL_HEIGHT
    end
    self.scrollChild:SetHeight(math.max(1, totalHeight))
end

function FLIPR:CollapseDropdown()
    if not self.expandedItemID then return end
    
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
    local rowData = self.itemRows[itemID]
    if not rowData then return end
    
    -- Create dropdown
    local dropdown = CreateFrame("Frame", nil, rowData.frame)
    dropdown:SetPoint("TOPLEFT", rowData.frame, "BOTTOMLEFT", 0, 0)
    dropdown:SetPoint("TOPRIGHT", rowData.frame, "BOTTOMRIGHT", 0, 0)
    dropdown:SetHeight(MAX_DROPDOWN_ROWS * ROW_HEIGHT)
    
    -- Create child auction rows
    self:CreateDropdownRows(dropdown, rowData.results)
    
    rowData.dropdown = dropdown
    self.expandedItemID = itemID
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
    -- Update selection visuals and gather selected auctions
    local selectedAuctions = {}
    local totalCost = 0
    local totalQuantity = 0
    
    for i, row in ipairs(dropdown.rows) do
        local isSelected = i <= selectedIndex
        row.selectionTexture:SetShown(isSelected)
        
        if isSelected then
            selectedAuctions[i] = row.auctionData
            totalCost = totalCost + (row.auctionData.minPrice * row.auctionData.totalQuantity)
            totalQuantity = totalQuantity + row.auctionData.totalQuantity
        end
    end
    
    -- Store selected auctions info
    local rowData = self.itemRows[self.expandedItemID]
    if rowData then
        rowData.selectedAuctions = selectedAuctions
        rowData.totalCost = totalCost
        rowData.totalQuantity = totalQuantity
    end
end

function FLIPR:BuySelectedAuctions()
    if not self.selectedItem then
        print("No items selected!")
        return
    end
    
    local itemData = self.selectedItem
    local totalCost = itemData.minPrice * itemData.totalQuantity
    
    -- If we have expanded auctions selected, use those instead
    if self.expandedItemID and self.itemRows[self.expandedItemID].selectedAuctions then
        local rowData = self.itemRows[self.expandedItemID]
        totalCost = rowData.totalCost
        itemData.totalQuantity = rowData.totalQuantity
        itemData.selectedAuctions = rowData.selectedAuctions
    end

    StaticPopupDialogs["FLIPR_CONFIRM_PURCHASE"] = {
        text = string.format("Purchase %d items for %s?", 
            itemData.totalQuantity, 
            GetCoinTextureString(totalCost)),
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if itemData.selectedAuctions then
                -- Buy multiple selected auctions
                for _, auction in pairs(itemData.selectedAuctions) do
                    if auction.isCommodity then
                        C_AuctionHouse.PurchaseCommodity(auction.itemID, auction.quantity, auction.minPrice)
                    else
                        C_AuctionHouse.PlaceBid(auction.auctionID, auction.minPrice)
                    end
                end
            else
                -- Buy single auction
                if itemData.isCommodity then
                    C_AuctionHouse.PurchaseCommodity(itemData.itemID, itemData.totalQuantity, itemData.minPrice)
                else
                    C_AuctionHouse.PlaceBid(itemData.auctionID, itemData.minPrice)
                end
            end
            
            -- Collapse and refresh
            self:CollapseDropdown()
            self:RescanItem(itemData.itemID)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("FLIPR_CONFIRM_PURCHASE")
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
 