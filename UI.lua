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
    self:CreateTitleButtons(titleSection, contentFrame)
    
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
    -- Store reference to the group frame
    self.groupFrame = parent
    
    -- Get TSM groups
    local tsmGroups = self:GetTSMGroups()
    
    -- Build group structure from TSM groups
    self.groupStructure = {}
    
    -- Helper function to ensure parent groups exist
    local function ensureParentGroups(path)
        local parts = {strsplit("`", path)}
        local currentPath = ""
        local currentNode = self.groupStructure
        
        for i, part in ipairs(parts) do
            if i == 1 then
                currentPath = part
                if not currentNode[part] then
                    currentNode[part] = {
                        name = part,
                        path = currentPath,
                        children = {}
                    }
                end
                currentNode = currentNode[part].children
            else
                currentPath = currentPath .. "`" .. part
                if not currentNode[part] then
                    currentNode[part] = {
                        name = part,
                        path = currentPath,
                        children = {}
                    }
                end
                currentNode = currentNode[part].children
            end
        end
    end
    
    -- Build hierarchical structure
    for groupPath in pairs(tsmGroups) do
        ensureParentGroups(groupPath)
    end
    
    -- Create checkboxes
    self:RefreshGroupList()
end

function FLIPR:GetTSMGroups()
    if not TradeSkillMasterDB then return {} end
    
    local itemsTable = TradeSkillMasterDB["p@Default@userData@items"]
    if not itemsTable then return {} end
    
    -- Build a table of unique groups
    local groups = {}
    for _, groupPath in pairs(itemsTable) do
        -- Split the path into parts
        local parts = {strsplit("`", groupPath)}
        local currentPath = ""
        
        -- Add each level of the group hierarchy
        for i, part in ipairs(parts) do
            if i == 1 then
                currentPath = part
            else
                currentPath = currentPath .. "`" .. part
            end
            groups[currentPath] = true
        end
    end
    
        return groups
    end
    
function FLIPR:GetTSMGroupItems(groupPath)
    if not TradeSkillMasterDB then return {} end
    
    local itemsTable = TradeSkillMasterDB["p@Default@userData@items"]
    if not itemsTable then return {} end
    
    local items = {}
    for itemString, path in pairs(itemsTable) do
        if path == groupPath or path:match("^" .. groupPath .. "`") then
            local itemID = itemString:match("i:(%d+)")
            if itemID then
                items[tonumber(itemID)] = true
            end
        end
    end
    
    return items
end

function FLIPR:RefreshGroupList()
    if not self.groupFrame then return end
    
    -- Clear existing buttons
    for _, child in pairs({self.groupFrame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = -5
    
    -- Helper function to create group checkbox with expand button
    local function createGroupCheckbox(name, path, parent, level)
        -- Create container frame
        local container = CreateFrame("Frame", nil, parent)
        container:SetSize(parent:GetWidth(), 24)
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        
        -- Check if this group has any children
        local hasChildren = false
        for checkPath in pairs(self:GetTSMGroups()) do
            if checkPath:match("^" .. path .. "`") then
                hasChildren = true
                break
        end
    end
    
        -- Create expand button only if the group has children
        local expandButton = CreateFrame("Button", nil, container)
        expandButton:SetSize(16, 16)
        expandButton:SetPoint("LEFT", container, "LEFT", level * 15, 0)
        
        local expandTexture = expandButton:CreateTexture(nil, "ARTWORK")
        expandTexture:SetAllPoints()
        
        if hasChildren then
            local isExpanded = self.db.profile.expandedGroups[path] or false
            expandTexture:SetTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            
            -- Expand button scripts
            expandButton:SetScript("OnClick", function()
                self.db.profile.expandedGroups[path] = not self.db.profile.expandedGroups[path]
                self:RefreshGroupList()
            end)
        else
            expandTexture:SetTexture(nil)
            expandButton:SetScript("OnClick", nil)
        end
        
        -- Create checkbox
        local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
        checkbox:SetPoint("LEFT", expandButton, "RIGHT", 2, 0)
        checkbox:SetSize(24, 24)
        
        -- Create label
        local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        label:SetText(name)
        
        -- Set initial states
        checkbox:SetChecked(self.db.profile.enabledGroups[path] or false)
        
        -- Checkbox scripts
        checkbox:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            FLIPR.db.profile.enabledGroups[path] = checked
            
            -- Recursively set all children
            local function setChildrenState(nodePath, state)
                for childPath in pairs(FLIPR:GetTSMGroups()) do
                    if childPath:match("^" .. nodePath .. "`") then
                        FLIPR.db.profile.enabledGroups[childPath] = state
                    end
                end
            end
            
            setChildrenState(path, checked)
            
            -- Update scan items
            if FLIPR.UpdateScanItems then
                FLIPR:UpdateScanItems()
            end
            
            -- Refresh to update child checkboxes
            FLIPR:RefreshGroupList()
        end)
        
        -- Create highlight
        local highlight = checkbox:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(label)
        highlight:SetColorTexture(1, 1, 1, 0.2)
        highlight:SetBlendMode("ADD")
        
        yOffset = yOffset - 25
        return container, hasChildren and (self.db.profile.expandedGroups[path] or false)
    end
    
    -- Recursive function to create group hierarchy
    local function createGroupHierarchy(node, parent, level)
        if not node then return end
        
        -- Sort groups alphabetically
    local sortedGroups = {}
        for name, data in pairs(node) do
            table.insert(sortedGroups, {name = name, data = data})
        end
        table.sort(sortedGroups, function(a, b) return a.name < b.name end)
        
        for _, group in ipairs(sortedGroups) do
            local container, isExpanded = createGroupCheckbox(group.name, group.data.path, parent, level)
            
            -- If expanded and has children, create them
            if isExpanded and group.data.children and next(group.data.children) then
                createGroupHierarchy(group.data.children, parent, level + 1)
            end
        end
    end
    
    -- Create all group checkboxes
    createGroupHierarchy(self.groupStructure, self.groupFrame, 0)
    
    -- Update frame height
    self.groupFrame:SetHeight(math.abs(yOffset) + 5)
end

function FLIPR:UpdateScanItems()
    -- Reset scan items
    self.itemIDs = {}
    local processedItems = {}  -- Track items we've already added
    
    -- Get all enabled groups
    for groupPath, enabled in pairs(self.db.profile.enabledGroups) do
        if enabled then
            -- Get all items in this TSM group
            local items = self:GetTSMGroupItems(groupPath)
            for itemID in pairs(items) do
                if not processedItems[itemID] then
                    -- Create item info
                    local itemName = GetItemInfo(itemID)
                    if itemName then
                        table.insert(self.itemIDs, itemID)
                        processedItems[itemID] = true
                        print(string.format("Added item to scan list: %d - %s from group %s", 
                            itemID, itemName, groupPath))
                    else
                        -- Queue item info request
                        local item = Item:CreateFromItemID(itemID)
                        item:ContinueOnItemLoad(function()
                            if not processedItems[itemID] then
                                table.insert(self.itemIDs, itemID)
                                processedItems[itemID] = true
                                print(string.format("Added item to scan list (after load): %d - %s from group %s", 
                                    itemID, item:GetItemName(), groupPath))
                            end
                        end)
                    end
                end
            end
        end
    end
    
    -- Sort itemIDs for consistent scanning order
    table.sort(self.itemIDs)
    
    -- Print summary
    print(string.format("Total unique items in scan list: %d", #self.itemIDs))
    
    -- Reset scan state
    self.currentScanIndex = 1
    
    -- Clear results display
    if self.scrollChild then
        self.scrollChild:SetHeight(1)
        for _, child in pairs({self.scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
    end
    
    -- Return the number of items to be scanned
    return #self.itemIDs
end

function FLIPR:CreateGroupCheckbox(parent, text, groupPath, level)
    -- Create container frame for checkbox and expand button
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(parent:GetWidth(), 20)
    
    -- Store the groupPath on the container for later reference
    container.groupPath = groupPath
    
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

    -- Create custom text with smaller font and ellipsis
    checkbox.Text:SetFontObject("GameFontNormalSmall")  -- Smaller font
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 0, 0)
    checkbox.Text:SetPoint("RIGHT", container, "RIGHT", -5, 0)  -- Right margin
    checkbox.Text:SetText(text)
    checkbox.Text:SetWordWrap(false)  -- Prevent wrapping
    checkbox.Text:SetJustifyH("LEFT")  -- Left align
    checkbox.Text:SetHeight(20)

    -- Add tooltip for full text
    checkbox:SetScript("OnEnter", function()
        if checkbox.Text:IsTruncated() then
            GameTooltip:SetOwner(checkbox, "ANCHOR_RIGHT")
            GameTooltip:SetText(text)
            GameTooltip:Show()
        end
    end)
    checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
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
    
    -- Add delete button for root level groups
    if level == 0 then
        local deleteBtn = CreateFrame("Button", nil, container)
        deleteBtn:SetSize(16, 16)
        deleteBtn:SetPoint("RIGHT", container, "RIGHT", -5, 0)
        
        -- Raise the button's frame level above the container
        deleteBtn:SetFrameLevel(container:GetFrameLevel() + 2)
        
        -- Set the X texture
        deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        
        -- Add hover effect
        deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
        
        -- Make the button more visible and clickable
        deleteBtn:EnableMouse(true)
        
        -- Click handler with confirmation dialog
        deleteBtn:SetScript("OnClick", function()
            -- Create confirmation dialog if it doesn't exist
            if not StaticPopupDialogs["FLIPR_CONFIRM_DELETE_GROUP"] then
                StaticPopupDialogs["FLIPR_CONFIRM_DELETE_GROUP"] = {
                    text = "Delete group '%s'?",
                    button1 = "Yes",
                    button2 = "No",
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                    OnAccept = function(self, data)
                        -- Remove from saved variables
                        if self.FLIPR.groupDB.groups[data.groupPath] then
                            self.FLIPR.groupDB.groups[data.groupPath] = nil
                        end

                        -- Remove from group structure
                        if self.FLIPR.groupStructure[data.groupPath] then
                            self.FLIPR.groupStructure[data.groupPath] = nil
                        end

                        -- Get all frames in the scroll child
                        local scrollChild = self.FLIPR.groupFrame
                        if scrollChild then
                            -- Find and remove the specific root group frame
                            for _, child in pairs({scrollChild:GetChildren()}) do
                                -- Check if this is our root group frame
                                if child.groupPath == data.groupPath then
                                    -- Hide and cleanup all children of this frame
                                    for _, subChild in pairs({child:GetChildren()}) do
                                        subChild:Hide()
                                        subChild:SetParent(nil)
                                        subChild = nil
                                    end
                                    -- Hide and cleanup the root frame itself
                                    child:Hide()
                                    child:SetParent(nil)
                                    child:ClearAllPoints()
                                    child = nil
                                end
                            end
                        end

                        -- Clear any expanded states for this group
                        if self.FLIPR.db.expandedGroups then
                            self.FLIPR.db.expandedGroups[data.groupPath] = nil
                        end

                        -- Clear any enabled states for this group
                        if self.FLIPR.db.enabledGroups then
                            self.FLIPR.db.enabledGroups[data.groupPath] = nil
                        end

                        -- Rebuild group structure from current saved variables
                        self.FLIPR.availableGroups = self.FLIPR:GetAvailableGroups()
                        self.FLIPR.groupStructure = {}
                        for groupName, groupData in pairs(self.FLIPR.availableGroups) do
                            self.FLIPR.groupStructure[groupName] = self.FLIPR:BuildGroupStructure(groupData)
                        end

                        -- Refresh UI to rebuild the group list
                        self.FLIPR:RefreshGroupList()
                    end,
                }
            end
            
            -- Show the confirmation dialog
            local dialog = StaticPopup_Show("FLIPR_CONFIRM_DELETE_GROUP", text)
            if dialog then
                dialog.FLIPR = self
                dialog.data = {
                    groupPath = groupPath,
                }
            end
        end)
        
        -- Adjust text width to make room for delete button
        checkbox.Text:SetPoint("RIGHT", deleteBtn, "LEFT", -5, 0)
    end
    
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

function FLIPR:CreateTitleButtons(titleSection, frame)
    -- Create scan button
    local scanButton = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    scanButton:SetSize(100, 20)
    scanButton:SetPoint("LEFT", titleSection, "LEFT", 10, 0)
    scanButton:SetText("Scan Items")
    scanButton:SetScript("OnClick", function() self:StartScan() end)
    self.scanButton = scanButton
    
    -- Create cancel button
    local cancelButton = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 20)
    cancelButton:SetPoint("LEFT", scanButton, "RIGHT", 10, 0)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function() self:CancelScan() end)
    self.cancelButton = cancelButton

    -- Create TSM toggle button
    local tsmToggle = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    tsmToggle:SetSize(100, 20)
    tsmToggle:SetPoint("LEFT", cancelButton, "RIGHT", 10, 0)
    tsmToggle:SetText(self.db.profile.useTSM and "TSM Mode" or "Classic Mode")
    
    tsmToggle:SetScript("OnClick", function()
        self.db.profile.useTSM = not self.db.profile.useTSM
        tsmToggle:SetText(self.db.profile.useTSM and "TSM Mode" or "Classic Mode")
        print(string.format("|cFF00FF00FLIPR: Switched to %s mode|r", self.db.profile.useTSM and "TSM" or "Classic"))
        -- Clear current results when switching modes
        self:CancelScan()
    end)
    self.modeButton = tsmToggle
    
    -- Create scan progress text (centered)
    local scanProgressText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanProgressText:SetPoint("CENTER", titleSection, "CENTER", 0, 0)
    scanProgressText:SetText("")
    self.scanProgressText = scanProgressText
    
    -- Create purchase button (far right)
    local purchaseButton = CreateFrame("Button", nil, titleSection, "UIPanelButtonTemplate")
    purchaseButton:SetSize(100, 20)
    purchaseButton:SetPoint("RIGHT", titleSection, "RIGHT", -10, 0)
    purchaseButton:SetText("Purchase")
    purchaseButton:SetEnabled(false)
    self.purchaseButton = purchaseButton
    frame.purchaseButton = purchaseButton
    
    purchaseButton:SetScript("OnClick", function()
        if self.selectedItem then
            self:BuySelectedAuctions()
        end
    end)
end

function FLIPR:UpdateScanProgress(current, total)
    if self.scanProgressText then
        if total > 0 then
            self.scanProgressText:SetText(string.format("Scanning: %d/%d items", current, total))
        else
            self.scanProgressText:SetText("Scanning...")
        end
    end
    
    -- Update timer
    if self.timerFrame and self.timerText then
        if not self.timerFrame:IsShown() then
            self.timerFrame:Show()
        end
        
        local elapsed = time() - self.scanStartTime
        if elapsed >= 0 then
            self.timerText:SetText(string.format("Time: %d:%02d", math.floor(elapsed/60), elapsed%60))
        end
    end
end

function FLIPR:OnScanComplete()
    if self.scanProgressText then
        self.scanProgressText:SetText("Scan Complete!")
    end
    
    if self.scanButton then
        self.scanButton:SetText("Scan Items")
    end
    
    -- Hide timer after 5 seconds
    C_Timer.After(5, function()
        if self.timerFrame then
            self.timerFrame:Hide()
        end
        if self.scanProgressText then
            self.scanProgressText:SetText("")
        end
    end)
end

function FLIPR:HandleItemSelection(itemID, row)
    print("HandleItemSelection called for itemID:", itemID)
    
    -- If clicking currently selected item, deselect everything
    if self.selectedItem and self.selectedItem.itemID == itemID then
        print("Deselecting current item")
        -- Clean up current selection
        row.selectionTexture:Hide()
        row.defaultBg:Show()
        
        -- Clean up last selection if it exists
        if self.lastSelectedItem and self.lastSelectedItem.itemID ~= itemID then
            local lastRowData = self.itemRows[self.lastSelectedItem.itemID]
            if lastRowData then
                local lastRow = lastRowData.row
                if lastRow then
                    lastRow.selectionTexture:Hide()
                    lastRow.defaultBg:Show()
                end
            end
        end
        
        self:CollapseDropdown()
        self.lastSelectedItem = nil
        self.selectedItem = nil
        
        -- Disable purchase button when deselecting
        if self.contentFrame and self.contentFrame.purchaseButton then
            self.contentFrame.purchaseButton:SetEnabled(false)
        end
        return
    end
    
    -- Store current selection as last selection before changing
    if self.selectedItem then
        self.lastSelectedItem = self.selectedItem
        -- Clean up last selection's visuals
        local lastRowData = self.itemRows[self.lastSelectedItem.itemID]
        if lastRowData then
            local lastRow = lastRowData.row
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
    
    -- Enable purchase button when selecting an item
    if self.contentFrame and self.contentFrame.purchaseButton then
        self.contentFrame.purchaseButton:SetEnabled(true)
    end
    
    print("Selection complete - selectedItem:", self.selectedItem.itemID)
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
    local itemData = {
        itemID = itemID,
        minPrice = results[1].minPrice,
        totalQuantity = results[1].totalQuantity,
        auctionID = results[1].auctionID,
        isCommodity = results[1].isCommodity,
        selected = false,
        allAuctions = results
    }
    row.itemData = itemData
    
    -- First store the new item with index 1
    self.itemRows[itemID] = {
        frame = rowContainer,
        row = row,
        rowIndex = 1,  -- Always set new item to index 1
        results = results,
        flipOpportunity = flipOpportunity
    }
    
    -- Then shift all other items down
    for existingID, existingRow in pairs(self.itemRows) do
        if existingID ~= itemID then  -- Don't shift the new item
            existingRow.rowIndex = existingRow.rowIndex + 1
        end
    end
    
    -- Create item object
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        local itemLink = item:GetItemLink()
        nameText:SetText(itemLink)
        itemIcon:SetTexture(item:GetItemIcon())
        
        -- Set click handlers
        local function handleClick()
            FLIPR:HandleItemSelection(itemID, row)
        end
        
        row:SetScript("OnClick", handleClick)
        
        -- Add tooltip handlers
        itemLinkButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink(itemLink)
            GameTooltip:Show()
        end)
        
        itemLinkButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        itemLinkButton:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                handleClick()
            elseif button == "RightButton" then
                if itemLink then
                    ChatEdit_InsertLink(itemLink)
                end
            end
        end)
    end)
    
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
    saleRateText:SetText(string.format("%.3f", flipOpportunity.marketData.saleRate))
    
    -- Profit text with ROI
    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profitText:SetPoint("LEFT", saleRateText, "RIGHT", 10, 0)
    profitText:SetText(string.format(
        "%s (ROI: %d%%)",
        GetCoinTextureString(flipOpportunity.totalProfit),
        flipOpportunity.roi
    ))
    
    -- Initial position
    if self.expandedItemID then
        local currentExpanded = self.expandedItemID
        self:CollapseDropdown()
        self:UpdateRowPositions()
        self:ExpandDropdown(currentExpanded)
    else
        self:UpdateRowPositions()
    end
end

function FLIPR:UpdateRowPositions()
    -- Remove this condition entirely
    -- if not self.isScanning then
    --     self:CollapseDropdown()
    -- end

    -- Create sorted array of rows
    local sortedRows = {}
    for id, rowData in pairs(self.itemRows) do
        table.insert(sortedRows, {id = id, data = rowData})
    end
    
    -- Sort by index
    table.sort(sortedRows, function(a, b)
        return a.data.rowIndex < b.data.rowIndex
    end)

    -- Position rows sequentially
    local yOffset = 0
    for _, rowInfo in ipairs(sortedRows) do
        local rowData = rowInfo.data
        if rowData.frame and rowData.frame:IsShown() then
            rowData.frame:ClearAllPoints()
            rowData.frame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -yOffset)
            rowData.frame:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, -yOffset)
            
            -- Add dropdown height if expanded
            if self.expandedItemID == rowInfo.id then
                local dropdownHeight = math.min(#rowData.results, MAX_DROPDOWN_ROWS) * ROW_HEIGHT
                yOffset = yOffset + dropdownHeight + DROPDOWN_PADDING
            end
            
            yOffset = yOffset + ROW_HEIGHT
        end
    end

    -- Update scroll child height
    self.scrollChild:SetHeight(math.max(1, yOffset))
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
            self.selectedItem.auctions = rowData.results  -- Make sure auctions are passed through
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
            )  -- Add this closing parenthesis
        end
    end
    
    self.buyConfirmFrame.itemText:SetText("Item: " .. itemName)
    self.buyConfirmFrame.qtyText:SetText(string.format("Total Quantity: %d", totalQuantity))
    self.buyConfirmFrame.priceText:SetText(priceBreakdown)
    self.buyConfirmFrame.totalText:SetText(string.format("Total Cost: %s", GetCoinTextureString(totalCost)))
    
    self.buyConfirmFrame:Show()
end

function FLIPR:RemoveItemRowAndUpdate(itemID)
    -- Get the row data
    local rowData = self.itemRows[itemID]
    if not rowData then return end
    
    -- Hide and cleanup the frame
    if rowData.frame then
        rowData.frame:Hide()
        rowData.frame:SetParent(nil)
    end
    
    -- Clear from our tracking table
    self.itemRows[itemID] = nil
    
    -- Decrease count
    self.profitableItemCount = math.max(0, (self.profitableItemCount or 1) - 1)
    
    -- Clear selection if this was the selected item
    if self.selectedItem and self.selectedItem.itemID == itemID then
        self.selectedItem = nil
    end
    
    -- Collapse any expanded dropdown
    self:CollapseDropdown()
    
    -- Create sorted array of remaining rows
    local sortedRows = {}
    for id, row in pairs(self.itemRows) do
        table.insert(sortedRows, {id = id, data = row})
    end
    
    -- Sort by current index
    table.sort(sortedRows, function(a, b)
        return a.data.rowIndex < b.data.rowIndex
    end)
    
    -- Reindex sequentially without gaps
    for i, rowInfo in ipairs(sortedRows) do
        local row = rowInfo.data
        row.rowIndex = i
        if row.frame then
            row.frame.rowIndex = i
        end
    end
    
    -- Update positions of remaining rows
    self:UpdateRowPositions()
end

function FLIPR:CreateOptionsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    
    -- Create a button to open the interface options
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(200, 30)
    button:SetPoint("CENTER")
    button:SetText("Open Settings")
    button:SetScript("OnClick", function()
        -- Hide the main FLIPR frame
        self.mainFrame:Hide()
        -- Open the interface options panel
        InterfaceOptionsFrame_OpenToCategory("FLIPR")
        InterfaceOptionsFrame_OpenToCategory("FLIPR") -- Call twice to ensure it opens
    end)
    
    return panel
end

function FLIPR:InitializeUI()
    -- Create the AH tab button
    self:CreateAHButton()
end

function FLIPR:CreateAHButton()
    -- Wait for AH to be loaded
    if not AuctionHouseFrame then
        C_Timer.After(1, function() self:CreateAHButton() end)
        return
    end
    
    -- Create the FLIPR tab button
    local button = CreateFrame("Button", nil, AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate") 
    button.Text:SetText("FLIPR")
    button:SetScript("OnClick", function()
        self:ShowFliprTab()
    end)
    
    -- Position it after the last tab
    local numTabs = 1
    local lastTab = _G["AuctionHouseFrameTab" .. numTabs]
    while lastTab do
        numTabs = numTabs + 1
        lastTab = _G["AuctionHouseFrameTab" .. numTabs]
    end
    numTabs = numTabs - 1
    
    -- Create our tab
    local tabID = numTabs + 1
    button:SetID(tabID)
    button:SetPoint("LEFT", _G["AuctionHouseFrameTab" .. numTabs], "RIGHT", -15, 0)
    
    -- Add it to the tab system
    PanelTemplates_SetNumTabs(AuctionHouseFrame, tabID)
    PanelTemplates_EnableTab(AuctionHouseFrame, tabID)
end

function FLIPR:CreateGroupsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    
    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    -- Create scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1) -- Will be adjusted dynamically
    
    -- Store references
    panel.scrollFrame = scrollFrame
    panel.scrollChild = scrollChild
    
    return panel
end

function FLIPR:CreateResultsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    
    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    -- Create scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1) -- Will be adjusted dynamically
    
    -- Store references
    panel.scrollFrame = scrollFrame
    panel.scrollChild = scrollChild
    
    return panel
end

function FLIPR:CreateMainFrame()
    -- Create the main frame
    local frame = CreateFrame("Frame", "FliprFrame", UIParent)
    frame:SetSize(800, 600)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Add a background texture
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    
    -- Create title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(30)
    
    -- Title background
    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    
    -- Title text
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 10, 0)
    title:SetText("FLIPR")
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 0, 0)
    closeButton:SetScript("OnClick", function() frame:Hide() end)
    
    -- Create TSM toggle button
    local tsmToggle = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
    tsmToggle:SetSize(100, 20)
    tsmToggle:SetPoint("LEFT", cancelButton, "RIGHT", 10, 0)
    tsmToggle:SetText(self.db.profile.useTSM and "TSM Mode" or "Classic Mode")
    
    tsmToggle:SetScript("OnClick", function()
        self.db.profile.useTSM = not self.db.profile.useTSM
        tsmToggle:SetText(self.db.profile.useTSM and "TSM Mode" or "Classic Mode")
        print(string.format("|cFF00FF00FLIPR: Switched to %s mode|r", self.db.profile.useTSM and "TSM" or "Classic"))
        -- Clear current results when switching modes
        self:CancelScan()
    end)
    
    -- Create scan progress text
    local scanProgressText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanProgressText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    scanProgressText:SetText("")
    self.scanProgressText = scanProgressText
    
    -- Create timer frame
    local timerFrame = CreateFrame("Frame", nil, titleSection)
    timerFrame:SetSize(100, 20)
    timerFrame:SetPoint("RIGHT", titleSection, "RIGHT", -10, 0)
    timerFrame:Hide()
    
    local timerText = timerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerText:SetAllPoints()
    timerText:SetJustifyH("RIGHT")
    timerText:SetText("")
    
    self.timerFrame = timerFrame
    self.timerText = timerText
    
    -- Create content area
    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -30)  -- Leave room for button row
    contentFrame:SetPoint("BOTTOMRIGHT")
    frame.contentFrame = contentFrame
    
    -- Create button row (BEFORE content area)
    local buttonRow = CreateFrame("Frame", "FliprButtonRow", frame)
    buttonRow:SetHeight(30)
    buttonRow:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    buttonRow:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    
    -- Button row background
    local buttonRowBg = buttonRow:CreateTexture(nil, "BACKGROUND")
    buttonRowBg:SetAllPoints()
    buttonRowBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    
    -- Create scan items button (leftmost)
    local scanButton = CreateFrame("Button", "FliprScanButton", buttonRow, "UIPanelButtonTemplate")
    scanButton:SetSize(100, 22)
    scanButton:SetPoint("LEFT", 10, 0)
    scanButton:SetText("Scan Items")
    frame.scanButton = scanButton
    
    -- Create cancel button (second from left)
    local cancelButton = CreateFrame("Button", "FliprCancelButton", buttonRow, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 22)
    cancelButton:SetPoint("LEFT", scanButton, "RIGHT", 10, 0)
    cancelButton:SetText("Cancel")
    cancelButton:SetEnabled(false)
    frame.cancelButton = cancelButton
    
    -- Create mode toggle button (third from left)
    local modeButton = CreateFrame("Button", "FliprModeButton", buttonRow, "UIPanelButtonTemplate")
    modeButton:SetSize(100, 22)
    modeButton:SetPoint("LEFT", cancelButton, "RIGHT", 10, 0)
    modeButton:SetText(self.db.profile.useTSM and "TSM Mode" or "Classic Mode")
    frame.modeButton = modeButton
    
    -- Create scan progress text (centered)
    local scanProgressText = buttonRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scanProgressText:SetPoint("CENTER", buttonRow, "CENTER", 0, 0)
    scanProgressText:SetText("")
    self.scanProgressText = scanProgressText
    
    -- Button scripts
    scanButton:SetScript("OnClick", function()
        if not self.isScanning then
            self:StartScan()
        else
            self:PauseScan()
        end
    end)
    
    cancelButton:SetScript("OnClick", function()
        self:CancelScan()
    end)
    
    modeButton:SetScript("OnClick", function()
        self.db.profile.useTSM = not self.db.profile.useTSM
        modeButton:SetText(self.db.profile.useTSM and "TSM Mode" or "Classic Mode")
        print(string.format("|cFF00FF00FLIPR: Switched to %s mode|r", self.db.profile.useTSM and "TSM" or "Classic"))
    end)
    
    -- Store frame reference
    self.frame = frame
    
    return frame
end

function FLIPR:PurchaseSelectedItem_TSM()
    if not self.selectedItem then return end
    
    local itemData = self.selectedItem
    local rowData = self.itemRows[itemData.itemID]
    
    if not rowData or not rowData.selectedAuctions then
        print("|cFFFF0000Error: No selected auctions found|r")
        return
    end
    
    -- Get the selected auctions
    local selectedAuctions = rowData.selectedAuctions
    if not selectedAuctions or #selectedAuctions == 0 then
        print("|cFFFF0000Error: No auctions selected for purchase|r")
        return
    end
    
    -- Purchase each selected auction
    for _, auction in ipairs(selectedAuctions) do
        if auction.isCommodity then
            C_AuctionHouse.StartCommoditiesPurchase(auction.itemID, auction.totalQuantity, auction.minPrice)
            C_AuctionHouse.ConfirmCommoditiesPurchase(auction.itemID, auction.totalQuantity, auction.minPrice)
        else
            C_AuctionHouse.PlaceBid(auction.auctionID, auction.minPrice)
        end
    end
    
    -- Clear selection after purchase
    self:HandleItemSelection(itemData.itemID, self.itemRows[itemData.itemID].row)
end

function FLIPR:PurchaseSelectedItem_Classic()
    if not self.selectedItem then return end
    
    local itemData = self.selectedItem
    local rowData = self.itemRows[itemData.itemID]
    
    if not rowData or not rowData.selectedAuctions then
        print("|cFFFF0000Error: No selected auctions found|r")
        return
    end
    
    -- Get the selected auctions
    local selectedAuctions = rowData.selectedAuctions
    if not selectedAuctions or #selectedAuctions == 0 then
        print("|cFFFF0000Error: No auctions selected for purchase|r")
        return
    end
    
    -- Purchase each selected auction
    for _, auction in ipairs(selectedAuctions) do
        if auction.isCommodity then
            C_AuctionHouse.StartCommoditiesPurchase(auction.itemID, auction.totalQuantity, auction.minPrice)
            C_AuctionHouse.ConfirmCommoditiesPurchase(auction.itemID, auction.totalQuantity, auction.minPrice)
        else
            C_AuctionHouse.PlaceBid(auction.auctionID, auction.minPrice)
        end
    end
    
    -- Clear selection after purchase
    self:HandleItemSelection(itemData.itemID, self.itemRows[itemData.itemID].row)
end
 