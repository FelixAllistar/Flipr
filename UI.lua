local addonName, addon = ...
local FLIPR = addon.FLIPR
local ROW_HEIGHT = 25

FLIPR.scanTimer = 0
FLIPR.scanStartTime = 0

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
        self.scanButton.buttonText:SetText("Scan Items")
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
    local SIDEBAR_WIDTH = 350
    local BOTTOM_MARGIN = 25
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
    
    -- Our tab's click handler
    fliprTab:SetScript("OnClick", function()
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
    self:CreateOptionsSection(sidebarContainer)
    self:CreateResultsSection(resultsContainer)
end

function FLIPR:CreateOptionsSection(parent)
    -- Create scrollable container for the options, positioned below the "Groups" title
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -30)  -- Leave space for title
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -25, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Create the group buttons in the scroll child
    self:CreateGroupButtons(scrollChild)
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

function FLIPR:CreateGroupCheckbox(parent, text, groupPath, tableName, level)
    local checkbox = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", 20 * (level or 0), 0)
    checkbox.Text:SetText(text)
    
    -- Set initial state
    checkbox:SetChecked(self.db.enabledGroups[groupPath] or false)
    
    -- Set up expand/collapse button if needed
    local structure = self.groupStructure[tableName]
    local node = structure
    for part in groupPath:gmatch("[^/]+") do
        node = node[part]
        if not node then break end
    end
    
    local expandButton
    if node and next(node.children) then
        expandButton = CreateFrame("Button", nil, checkbox)
        expandButton:SetSize(16, 16)
        expandButton:SetPoint("RIGHT", checkbox, "LEFT", -2, 0)
        
        -- Set texture based on state
        local isExpanded = self.db.expandedGroups[groupPath]
        expandButton:SetNormalTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        
        expandButton:SetScript("OnClick", function()
            self.db.expandedGroups[groupPath] = not self.db.expandedGroups[groupPath]
            self:RefreshGroupList()
        end)
    end
    
    -- Checkbox click handler
    checkbox:SetScript("OnClick", function()
        local checked = checkbox:GetChecked()
        self:ToggleGroupState(tableName, groupPath, checked)
    end)
    
    return checkbox, expandButton
end

function FLIPR:RefreshGroupList()
    if not self.groupFrame then return end
    
    -- Clear existing checkboxes
    for _, child in pairs({self.groupFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = -10
    
    -- Helper function to add groups recursively
    local function addGroups(node, prefix, level)
        for name, data in pairs(node) do
            local fullPath = prefix and (prefix .. "/" .. name) or name
            
            -- Create checkbox for this group
            local checkbox, expandButton = self:CreateGroupCheckbox(
                self.groupFrame, 
                name, 
                fullPath, 
                data.tableName, 
                level
            )
            checkbox:SetPoint("TOPLEFT", 10 + (20 * level), yOffset)
            
            yOffset = yOffset - 25
            
            -- If expanded and has children, add them
            if self.db.expandedGroups[fullPath] and next(data.children) then
                addGroups(data.children, fullPath, level + 1)
            end
        end
    end
    
    -- Add groups for each table
    for tableName, structure in pairs(self.groupStructure) do
        -- Add table name header
        local header = self.groupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 10, yOffset)
        header:SetText(tableName:gsub("FLIPR_", ""))
        yOffset = yOffset - 30
        
        -- Add groups
        addGroups(structure, nil, 0)
        yOffset = yOffset - 10  -- Extra space between tables
    end
    
    -- Update frame height
    self.groupFrame:SetHeight(math.abs(yOffset) + 20)
end

function FLIPR:CreateGroupButtons(scrollChild)
    print("Creating group buttons in scrollChild")
    local yOffset = -5
    local masterFrames = {}
    local allContainers = {}  -- Track all containers for positioning
    
    -- Function to recalculate total height and positions
    local function UpdateFramePositions()
        -- First position all root frames
        local currentY = -5
        
        -- Function to get total height of visible children
        local function GetVisibleHeight(container)
            if not container or not container:IsShown() then return 0 end
            local height = 0
            for _, child in ipairs({container:GetChildren()}) do
                if child:IsShown() then
                    height = height + 25  -- Height of the child itself
                    -- Add height of child's visible children
                    if child.subgroupContainer and child.subgroupContainer:IsShown() then
                        height = height + GetVisibleHeight(child.subgroupContainer)
                    end
                end
            end
            return height
        end
        
        -- Function to position a container's children
        local function PositionChildren(container, parentY, depth)
            if not container or not container:IsShown() then return end
            local y = parentY - 25  -- Start below parent
            
            for _, child in ipairs({container:GetChildren()}) do
                if child:IsShown() then
                    -- Position this child
                    child:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5 + (depth * 20), y)
                    
                    -- If this child has visible children, position them
                    if child.subgroupContainer and child.subgroupContainer:IsShown() then
                        child.subgroupContainer:SetPoint("TOPLEFT", child, "BOTTOMLEFT", 0, 0)
                        PositionChildren(child.subgroupContainer, y, depth + 1)
                        -- Move down by height of child's container
                        y = y - GetVisibleHeight(child.subgroupContainer)
                    end
                    
                    y = y - 25  -- Move down for next sibling
                end
            end
        end
        
        -- Position each root group and its children
        for i, frameData in ipairs(masterFrames) do
            -- Position root frame
            frameData.frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, currentY)
            
            -- If this root has visible children, position them
            if frameData.frame.subgroupContainer and frameData.frame.subgroupContainer:IsShown() then
                frameData.frame.subgroupContainer:SetPoint("TOPLEFT", frameData.frame, "BOTTOMLEFT", 0, 0)
                PositionChildren(frameData.frame.subgroupContainer, currentY, 1)
                -- Move down by height of container
                currentY = currentY - GetVisibleHeight(frameData.frame.subgroupContainer)
            end
            
            currentY = currentY - 25  -- Move down for next root
        end
        
        -- Set scroll height
        scrollChild:SetHeight(math.max(math.abs(currentY) + 5, 40))
    end
    
    -- Function to handle group expansion
    local function ToggleGroup(button)
        if not button.subgroupContainer then return end
        
        -- Toggle container visibility
        local show = not button.subgroupContainer:IsShown()
        button.subgroupContainer:SetShown(show)
        
        -- Update button texture
        if button.expandButton then
            button.expandButton:SetNormalTexture(show and 
                "Interface\\Buttons\\UI-MinusButton-Up" or 
                "Interface\\Buttons\\UI-PlusButton-Up")
        end
        
        -- Recalculate all positions
        UpdateFramePositions()
    end
    
    -- Function to organize groups into a tree structure
    local function BuildGroupTree(groups)
        local tree = {}
        for key, path in pairs(groups) do
            local parts = {strsplit("/", path)}
            local current = tree
            for _, part in ipairs(parts) do
                if not current[part] then
                    current[part] = {
                        children = {},
                        path = current.path and (current.path .. "/" .. part) or part
                    }
                end
                current = current[part].children
            end
        end
        return tree
    end
    
    -- Function to create group UI recursively
    local function CreateGroupUI(container, node, level, parentPath)
        local height = 0
        
        for name, data in pairs(node) do
            if name ~= "children" and name ~= "path" then
                -- Create group frame
                local groupFrame = CreateFrame("Frame", nil, container)
                groupFrame:SetSize(container:GetWidth() - (level * 20), 20)
                
                -- Add background
                local bg = groupFrame:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                
                -- Create checkbox
                local checkbox = CreateFrame("CheckButton", nil, groupFrame, "ChatConfigCheckButtonTemplate")
                checkbox:SetPoint("LEFT", groupFrame, "LEFT", 5, 0)
                checkbox:SetSize(20, 20)
                checkbox.Text:SetText(name)
                checkbox.Text:SetFontObject("GameFontNormalSmall")
                checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
                
                local fullPath = parentPath and (parentPath .. "/" .. name) or name
                checkbox:SetChecked(self.db.enabledGroups[fullPath] or false)
                
                checkbox:SetScript("OnClick", function()
                    local checked = checkbox:GetChecked()
                    print("Group clicked:", fullPath, checked)
                    self:ToggleGroupState(nil, fullPath, checked)
                end)
                
                -- If has children, add expand button
                if data.children and next(data.children) then
                    local expandButton = CreateFrame("Button", nil, groupFrame)
                    expandButton:SetSize(14, 14)
                    expandButton:SetPoint("RIGHT", groupFrame, "RIGHT", -5, 0)
                    expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                    expandButton:EnableMouse(true)
                    expandButton:SetFrameLevel(checkbox:GetFrameLevel() + 1)
                    
                    -- Create container for children
                    local childContainer = CreateFrame("Frame", nil, container)
                    childContainer:SetWidth(container:GetWidth() - ((level + 1) * 20))
                    childContainer:Hide()
                    
                    -- Create children recursively
                    CreateGroupUI(childContainer, data.children, level + 1, fullPath)
                    
                    groupFrame.subgroupContainer = childContainer
                    groupFrame.expandButton = expandButton
                    
                    -- Set up expand button handler
                    expandButton:SetScript("OnMouseDown", function(self, mouseButton)
                        if mouseButton == "LeftButton" then
                            ToggleGroup(groupFrame)
                        end
                    end)
                end
                
                height = height + 25
            end
        end
        
        return height
    end
    
    -- Get available master groups
    local masterGroups = self:GetMasterGroups()
    local numGroups = 0
    for name, groupData in pairs(masterGroups) do
        print("Found group:", name, groupData.name)
        numGroups = numGroups + 1
    end
    
    if numGroups == 0 then
        local text = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("CENTER", scrollChild, "CENTER", 0, 0)
        text:SetText("No TSM groups loaded. Use the scraper to download some groups.")
        scrollChild:SetHeight(40)
        return
    end
    
    -- Create master groups
    for tableName, groupData in pairs(masterGroups) do
        -- Create master group frame
        local masterFrame = CreateFrame("Frame", nil, scrollChild)
        masterFrame:SetSize(scrollChild:GetWidth() - 10, 25)
        
        -- Add background
        local bg = masterFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        
        -- Create master checkbox
        local masterCheckbox = CreateFrame("CheckButton", nil, masterFrame, "ChatConfigCheckButtonTemplate")
        masterCheckbox:SetPoint("LEFT", masterFrame, "LEFT", 5, 0)
        masterCheckbox.Text:SetText(groupData.name)
        masterCheckbox.Text:SetFontObject("GameFontNormalSmall")
        masterCheckbox:SetChecked(self.db.enabledGroups[groupData.name] or false)
        
        -- Create expand button if has subgroups
        if groupData.groups then
            local expandButton = CreateFrame("Button", nil, masterFrame)
            expandButton:SetSize(14, 14)
            expandButton:SetPoint("RIGHT", masterFrame, "RIGHT", -5, 0)
            expandButton:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
            expandButton:EnableMouse(true)
            
            -- Create subgroup container
            local subgroupContainer = CreateFrame("Frame", nil, scrollChild)
            subgroupContainer:SetWidth(scrollChild:GetWidth() - 10)
            subgroupContainer:Hide()
            
            -- Build and create subgroup tree
            local groupTree = BuildGroupTree(groupData.groups)
            CreateGroupUI(subgroupContainer, groupTree, 1, groupData.name)  -- Actually create the subgroup frames
            
            masterFrame.subgroupContainer = subgroupContainer
            masterFrame.expandButton = expandButton
            
            -- Set up expand button handler
            expandButton:SetScript("OnMouseDown", function(self, mouseButton)
                if mouseButton == "LeftButton" then
                    ToggleGroup(masterFrame)
                end
            end)
        end
        
        -- Master checkbox handler
        masterCheckbox:SetScript("OnClick", function()
            local checked = masterCheckbox:GetChecked()
            print("Master group clicked:", groupData.name, checked)
            self:ToggleGroupState(tableName, groupData.name, checked)
        end)
        
        table.insert(masterFrames, {frame = masterFrame})
    end
    
    -- Initial positioning
    UpdateFramePositions()
    print("Group buttons creation complete")
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
    
    -- Add progress text
    local progressText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressText:SetPoint("LEFT", cancelButton, "RIGHT", 10, 0)
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
 