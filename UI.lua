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
    groupTestButton:SetText("Import Groups")
    
    local defaultGroupString = "m15ZQx0ZYvDedxidYenZCYDMdcC575C27ZEVDUGdmyigeNjkgJxiAUeJio1NaXhbFu8j4sEI8ZQQ1QQFNrlQtV7)wD1vvD1D)p4)7FX)6)0)D)Z)3(N9V6p)V4F4V7x)N93839V)V7N)P)3(1)N(R)T)UF3V9)6F1V(393(38F63(x)x(RF9638ZV5Z)7)j)J)p8B)N96NxN))E)B(x8B)R(p)RF9Zp)8N8)QO99Zp)9N)M)n)L)T)p)1)1)n)p(1Vc5VV(9)kNIVV))C8B(xQ)8N)KoJUY)DDCB473VU)7)8B(t)l)p(B)V)FrfqNrV)C(63)h2WZJx)()OaFVWp)()O)2kb3N)()aJ((7(h9QRvtf(N)K()E(XP6ZpupkAF(HQHrpb96hx1(CD)11bGpd85CsWZLPE8ZtsWXRFoc1x)CUW7b((Nf(EHFDB7417jFF9z(SpVM89ZRV)()GQl54ZXhxZpPW6EKtAH)HnIVPBHNhFhuA1NN3Up588jF73F(9)X9xWyPZVVPwEE9ZB36bsjxvIZRx3UUFE9MbU(7P7ZL9dFFt7jJAFPtOlNVhx(J)E)o9TFV)gULV3xzib4MG7Wd99MrNFvXIDrZTQsxNd32157KYRVh01xP8(hxO3VFowygXHAQvaZ3dK(PQaU)8ZKdF(jCOqnCOaZ4fqgAYNLHzOofH4eB2DOgoP7pVP3YuFF4rCOUz27Wha1nZO92ChqDZSpB99ZRjbFEVWT0(WukNdF267NRL6weFEgQ07MpBM0E)5y7sGznnOJT35iZsiTZaWhylsxcIlg42GoZ0OBjTOh3bUL25N5ZoNX4pNBPDUL25wAmxiLgtgs9DKSD)zMoaCBqFdVhu3rONH14y7O(EadBxFFgHb3pxHLh4Ma4utAF((7)JRp75NRb(IjFM6RxpdeENES45f8ojbW7mWnhG3zOUzg8oHkmmdmmmpV(KgpWWEcm8oad7jWW7aClc6ss(cVZa3sdENH6NfUnOH3551ihbyyyEEb)qpAcCRVWe0dSqnmbpVy4ULt9qFA3PdkmQpVrMIZlw2AHrMWZBgm9NXcBlCQcVNz0KwMy1fM6qmI(JgTDhNubCD9ul11vRZzbNNVJSbGt76RY)oTFhzdaN69xgFtcqSS7MFGH1fXdITRfwzPB(QgjbOkxrUncQQpcilAoqZelQUtuqZpdKAB1hjOLMlilweQ7NbFxOIGQb6fE4ZGzBO(l(ST0O(MeGiPbUzgmqd1ToeHpA5PnFzABA8HTIeaBvYbeZmjyZ3WHrAVtbZKspw(61bnZ(ZaAzwcMmdO5rfvZdkOx1vWuZEDqZmzgZEgOzIiTuW14UGPfdmJBa3mlYyjTtlg4wjPf3nEOMwmWT(gbRkbM37ftkNA2jjO5DEDY64UMDIwwfB4lMuArOcof8xQzoTFJUIKGi9xqZ)l40r9nc3HkIXtoGy8uAigFOoDuF)UzgkMmjWRcQmBQ6FrDf3G(E5jtKGll3uWT0qHLuWOAZarUznDtcFkHeGyzlJOZ1O0UEZkcUwbmDsaZqYB6D9a17xZafWmqbmmwaN8vIe7X33VYcCcUzglA18yiDmt7q64(z3zAhuZOoWmPbyyHao57B66C((MUUboF2B66gQ)IplC0VFV1S3xzomuNk5BQKjhOsoWmf997Ts(ERKYEJjTBPDN5p8zBPf7gE9wgG4EY3iJn5aYyhQBBdvshQBBJL)hQBPfTtvrmTnPDQtR0o1LM0onqwFQz3ER57nh97dMiu6S)s1X())aZN))pAX9oBbAtMEnkKccTKAEFGEPBb9Ylc6LUbY0aNxVrBMbMoVpVhXbFKsBoFprpwN2ZOUpvlgu62aqBvd6CyB(azBzq5dM1xTWp0c726hniyu64)Ov)6(QJFOhSlsGjbh)8k1FGHLayAkaZuJdmMYL6Xp2QiYlBh6Rdn3Sk)d0k2LeAr6w0Xt0xhnyqaxNaGzSaB7YNDEgdqywo11Ei88818zNSsB3UoVJfCco5WngR4I4wv2K2mUCEVz290ha1nhM2J0DPZGVs30aNvx)oAQrcIsXazGRRJatnhvespcWSuc62ewoGPP9Tgs7CGo)KzQZ35R69h4Kzyh)8zXQrKTplR)9oUh4fWWv89b16CPjn3BgXVpsOYFUGPOU060DcVoMfNV2LwbMjGxXKLxxN0Al7BFjleAagDvznQowegzz3)qJSRbatjdmJF3IBTRem(svS)(0yUFJwzDpZTMI0t7Upy415QyxDcoI6KKGzbU7Zz5H7Zzi5(CgsU)YCyNdFhDFGAMXHf)tPDr3SRd3JOU7NzkjWmu)GAZULbmnsGryjW0lamdfpVgHLat)aWiv4jAo(MUoVo77FEZcM10lGSKBnb(9pOEwnG8wM83apCOvJrXQIgCr1c81IFgP1hkAKFMgzxBpa0s6ughAwOc)l6K40zBjW(dBmdi3qaL6574yiOzbsGSaj5uUuxKblDoh92Xgg5ZPQLd094c6ECb98mbnlOGtUIMRodU00GQa(qVt3W(GshDNYh4pdkvKpsdn)VEvH3WOAJkf02LauQ3uj9imuVp0qCXqjOxJsqRuMGEnkbTszcAJzfmJ8aTkGIQDecqn(6Ia23bAvavc8kIcMgbWTiySivYPPrcst7a(QjbSuEsRSOQBWSsDnfJL3ZkjcozRSEWFLKkfyS7K0cx)qD6N0kuU9CObNUiKF1cuIumvuk25qPjCX6lL1RA43HP9B8HjAhe28VXc93FFIHqcMwfWWJDPfL7s)sZ)m8JKA2urwDOEjUSM6v0TvqpTxWWgFDtbxY8q)XPGbMj0adZnqViIsRTFcymxwW0VamZFaATyvc2co2LjQBreVAiQBrit0Qo0R4CsHS(oOJlcSQ)wR23ZL0I9bzDLGM9a8BTeN)cP4x)fXlvOs80zF)jkca1S8GGwvm0zMUQEiGkCgnaMk)9zCIkkvtFPt75iEaQwknjy6lbM(sGw6Vsq6wbgXsat3kWP6CgZD1Nn1SZOccuPBnvNyFPOULwmcwuZGiWWgaCBMdNgRngoTA9UMx9wozON0CldBn1ROD177RODLGtd6k(BcQXFtcovYROyIOoDjxXVlI60RFffEe1Px)k(DbQFM(3lMz4ENRDm(AhcV2XTR4cgYHDWc9FMCqgD0n(ROiRGtxYLwETeEGQ99K3774OebNSANqc1zyDNqEFV1GDwi6vmd2pXMpS(ikVk40n9eR7e1PBst4CBqgomWPM9eLq4ZIMhysy08qW8zathcQ5KP)athcWWAHYpwvkYbT1lvVdWnZIkAI6(zmS29Kp)eF3IjFuDAEVh5dadLTVoFhBFF)aN6sDQKAeAsRlnmafDdlbPcANWkOfVkOLziOfVkOD1IGoFf0Aydm7IJG2ivbTEKcULwgwWi4i1by0Lvq3Ge0nibnBeWmBtqpClO7QbgNrlOf1iO5DeCZSOi5NFyei9opr4QO6T1e5PPbt)4cJowFwNPiO54ag2SpL2JfljWiZwqZMjyQJTUFoTr6bjiEIvW9ZYmprDZHm3)Z7ZSzwaJLtcApujOx6wqV2UGwribN89ejyfVfuJembN674AaOU13R44YpVVIm7pVFgMKpZkeYndzG)ZiOgQzdFemvDGH9fyyFbgUiG)ImlSVqntl(CgZCjFJ7UemtwaUL2mzbQPJcy6OaMokGPlbOfrr(Q9JT6(kxK0Zhbgok0)2IsGA8(JGB1r7EB)zs5Ts8aqMeoWmjeQtlw7LH)Shj(vAu85GPnLoiGSM9ylHTfaen8(FzDIsheq2dOGSHpG8oDJXhZ3Qb5(lKj0gz9IHMnYbKnhbKDLf2TyFcbAYp5C4oxyepOm58GX7qJUeNU09ECNTu6ZzC8ZNAMqLWtuWQRQYbngnso(QDoThX((jB8TGHT67OfZhGzmhnN9QzqnUNxWWFaCtB0wNeefFfm8OF)gZx)89B2VpbJqAGHtaygZ)oBkcPnoY4Z3RSn3WEeVmiyMY89EMRcmSRxVgEPRxX1PFq1MuAat9fTCwy28cs7mve4MG4czsalW3YwaMEhGBAJj(mseUQRyJc02A72rd1WIDflrjP2wDqWMuJ(YOeJYoo)5MLyDvcvz(fWi9fQrQ(n8zEoiqVW9Ns5UEMjWWswk3zQkCk6Y9wDXgL6YD2iHp3pztpaIeLUNc9FYQGSewgdF0A5Dw9KT4euy(afPmaTcl6)t5JIfMPhugHbsP6mns0E(ilvQQcWi5bywMayAFpX3sK0HVb4KRZkzyT5uvI3U5JggtGtTAIeasWiu(Hog3d98jw9855y0P4zSnhQB)2SZEI60hizITmGhmSCHz(h6G6(Zd02X9Yc6Cqq3HD8Z4YDb90lGujRr0duf0tdaIvpfVXXpqSCmdiR)TCO9uwL7j7V)KAqnIC8Z4JVJxsNJUaa6bNdw5WnNJDFipEDgoLdQ3PE96j6rCGaalD7494SobD3eq6O76WBTheDbd0lLkyQdaT0BOoF1Ny2pRmbhqPMSGEk2X7YnYvhY74x)JpysAj9hKfLxXMv3Xj3K15tT2BxNquUNadmQVcxqeBXIGrVnbTvFcMbPJk(EQs4CrX5QYRmmildNoyiQMZFCjFivoM8iCShxA3l70fnUbS)91WRa1mSFDpd7anh)XLcwRU59iXJfKL5IQBaZQiSKx29rbDBcTaZ8tGXKFb9qjWShscA)ZjOJNfbTCpGYr5DD4mg5jOz9e0Jbc6Uyu)mElxq32agwpuknr8MGwdkGXymbTajbPQRE3ZyaX573zV8qP2e)zcA9if0cuf0SMO1BmvqqZAkyA6aTd(evpzvq70lGjune0EftqBoOG21KaJhafCtqcIlr1AVlygja6zkIAgjaAwqrndkVLUknpcqZAjy6ZHfztq0vHeKPWatKqj424zCVMWD((BSRay2inb90qbNst(XSKDa14JjmWGEhtvB4LRVAXtxe3BD4w1HEWonYp)K94aduIBlemJWm32oZfQi2TZ1pVIfRNYyUwelWeRBNiEj1wGEPur12Liy4ObgMiGPPdCQKhZCnewTz2mTR0j31HzBkPiI71aM96rWTiI(cqDMbcmZ3)CKqxGemtfkLK7o6s34U7hJrMwHIfexD(gXKNyxY0ILMRtccRfjWlwP0oDQ7m7pFZ26rcITYcULwCfNOgjCa3slMSQeSL2oeQyF1TTVXrcK24ibbdxgWiFc422s4sP0UTTO6KOUTTSH5qnwflOxWuWTTLvKe1WEd0ABa14mdGXtMcUzwCMNO61zfC7OqoDgwIw5kbddJwmYZauKY4oQR4ZMZpxjGGeCynu4iBUKz3dvcIevGtR4kRGQemf81iP)Z1Y9P9Fm1HOhdF2iha40mLRzRLJzHlBmiiRLpstTJ1bLQDTpoD1wkhTWFrcs7IeKz2athkWihzdCCLzPDb0kjavB6cOPMcJBQaZcRhkcF6bbGB(hZaevBqHGB(BBBG4qtl619jdd(HgwAMaGt2VdlhAntx(3r1iwbj2bjyynaMbaGz4g40UUJwP6ZMULkQX76WDIsxbZAiaZkwadp5HC6R7VEgjxSGvMdbmZ5zTlBGeMhoTyG)IeK6W5kccy6Do35XN7KxG2DgKVPTFQ9TPzubgE2kyngQPlRcwJM6x5kTU9amdfFVNzEFFq(rpuCnEpxWix6(f90DcaM17bMEpGzvM73jyKobgECGPMbm84atnRIU9ES6wU)yGrdhOMrfmloZOaMzuTj0fBOuwTmSbJv8wNbYoIbueLDpBCbeNv5ag5xOaqgEbUFw8UcFwcXjbZy699m(d)Cyf2DXadeIVCakxt1n87S3icUzwoCeqLgrsBImQZBz6DffkKtTMWpYpw9OpW0AaMLKbMQ1dgm4mf7pJmhGZNHg)BcMpBoWmSID2AeMym8AadVgWSO(ZShOK24FBbNIqDnUQp7bkjyR6JvjNpkqa6H8ksM7gCfV9MOdgciARZaPEj93F1wZuZlaLahxqhKcaDdauoFlF)jEmhuKEGIkzfyG)cQitPQuO(s23fGX0eb9umKDOqcPt7z2giGX7EF)rcuDc0YybghKqcIY(cMm712YWen3ZIcqXn5O1tu2bO8eBvha6beGHfhOQ6vFNwCWOWEIopjmuaMkailEsethkqZkkQEqeOTMgKn7anIYMnlOf4l489NXiuOgdmaMnKvqZGdmZ9)QDoQ5Ze0tbbgVajONdbmoKfOIUq)zWuLCiRiGi8iPtW0j(rXlsnZfQXQaGXqlb9eEbNQJcgjxekqEtomnZpk6DD15De6GIFtFU22Mjbr5cLaprN1z20kd4CPjd4cms7iTr1pb96LO6yS2ay2iDGXpUcoL234XNVOx202K(EU0KgcUzELq2L0U96JpYe1zaqXEH)SzjmQxkakLPAFJTRFpNW3uqlwsUd3s3)EoBcoWH1cL0tT9RC6t3NdmZy(kpo0Tb(L61xfigDArL1KGlfZdM6vcsNViX1RLjy4YyPvRN23Ab3(ZQfCdm6Oa1OLJGBoeV8(9wBgAl5aOTHxqVMoWy0W39GUjO9yaWrGdWuFR4ePB8atZSczKHAyVzKAsR8yQBfsDsxZogzdOcsKyamZ4bg(uGHpL1nMwbAZLcwrLIRdkQuAEKkQumv4cwQzk2TSTpPLbwxZ0gSv6broenEao8oaTsII6u1l9fl2WSOkGy1hq01Z9cYomxV0UUmWPnmEYGplEYqWm)b407kMExB)Q9tRR46KP5MJceLKa5lyNGCcliTZYeadJ89CSkib5yvG6KrzBGjq4fmZRaoSatuh)fv)N67T2WWUomQri4W0xb7xNGkqlnm(pcjorTAbZa4ZRzXzGP6uNITEeUoVAdC)SrI8EeZqmrSMdyIixGZk9OlDK0)8HsR7ubMzfaZSIN5G68fy49aM22ZXmSamdHpJrZFboz234o3VpsEA5wAa2Iuq291GC1cuKujO7pe09haLvcDojpliM4rreaWu4YHAxPvfe92VcYS9LvF9NcJCbu1QbwT8YR11GGqPQaKH8oHMpbq8leW4ZFbDpHGURsqluqqZijO7HbI6l1yKGEwKGBPf7Ke1Tis4SiQwqQGBrKdYhuJDQcAbEc(lsRNscvDi2D1j7qVO6zgxk(As3K27RA6ludldWOYGGtdA2DlOg)3F9sb3TlTzBQGA2VxbTKhbN(m59q3NPzNUoCNtt61lwWyOMdwQOAl(f0lOamXJQGHf9LCtyXojgGGSMbxVvOUxZ(bgBIfCtquUtuT6LaP8RmDSgfuKIkyAwaZ4pql(xjiJ)a9cPIA42aAz2IAgEb61QH6m4a0(MxuthdWT0yYvp4a1msdmCBadVnWmqcmmtVRy)35q8FhzwKzl42pMJ3gursEpM(w29mqBcLO6Lbf0ot569RC)dCnQFcA4eQamY5L0YyGwzQRkMYBjaBmLdm7BKGt1vHsUBAkwYBUXkyYh4mcQJW9K2zeuhH7uAX)xkhMrqfDX5ZMPm9od2L2CateCgTLpatcItAibXrZcovh5TUjTwjaLGTiI3Lf1PfVtqFpNqusq80pWrCWBTcIlI5yuCPqcCPABqHA8ATG7NX6vEWsbN9ahU(hfY518kPNy3NckdX1oI0mYadpnWmdQ2NKjbHNgQHNgODOd5GvdrOmUdmJ7aZIBadRfWmwcmRZu7etQU5i(s(oZWagUBGBTzMH95hDogCtl7en5q8fUGo8LagolqHfby6NbgowGz4byyraAZOuEfwK12urnSiyM6weXmksq8UQGBreZOe1Tis0FkQBVx0SgQjSeeCBfjMwe1TiIPYI6we52vru3Iibp(f2AmTcfjanFmuNoQXyBrD6O0r2Ofda1inSmbpuZEYqcIlRfCQVZUzlQrobWPxxxGltMTLwcEt(SSh9ahbuaJqFGdJ6RChtO0oSz6iYLIqhUr3GsSdsAtG2cChaKHFUJQwWR)m5qfdviTyUEfvsoTZrL46JoQed1jZKFkn1747XlfvmTFGU05VPZwqog7a6nHaKpesGI2LO(rkjGPwbmJdaZGkWmoCm3ekxatN)rD4J6kGuhkWzf3JvDiGr)dmv06RFvBsq)zNAj5bgHAqnTrGzXQZFuSv0FgsP9a15v8o(L8MRLsGPItoGw6M63FIDHmkeNTE99oUcrNULuZQaORlnGPMbm9oY0YjbX3VK2rNEGP(I9zP6amApDnxbexxsfIwahqhpNaZK1lfGhDT5Ao49ahoEGoiJUUgMyqrgaWSosDuACEnUZ5A3rcbdJX1ZiT9EmK76wEoRRTL7n6mRCVrZ5cm8iatVa2DMcgy6ObgEFGPGbgoY9yus(osgaULwC4kji(tfyCX41EIyeCQoZPCbQjEZfCAqtiva1zjmmapCzaJ0PNFI7DXO8PfxXLx37amJ7vi6fQXZ0KGzIhWnTXthKGrIog)ojOU6T6Iqx4rbg)Gc1ey4cg9kEMZ011ZC(SV)rkaxcaf0TnbnFOGw6KoCSErdDIyDD4USPTycUXq2jh(e7eGA6hUH93SNc6QoWirhOUGnKupGBsJxzzEBu(rqR8d8PtTzJwlydfhxLxsR4I7fUf1CAIAa2iBko0sVX7tDU36)ot7bLDZ4(ToWoDnTc61gLfJXGmTNLfrfhCDpCfcg1WLGP5)roQS7a)qnnj4jhYH7ppXxfcMwcqReMOAD3e0k)XC(elZaJNmf0l1kONqHqHOpW9HwBRRomU41aUpgVQbmlOamI4zsKIw(QbRq(V7zQGjRrrrhwSlHWnqlJ8(RSWStzDOMnYb8E5hpttolU)x5zoJSe67VLl3BIZG23Fjm3hq3YRXUR(7CMUGAe3GO8Ou491e92cMUAGHdfy6uVM78gsB25Bwbi7sLGwWVGwncb96McAnkemtOqCU1QbQja4qCu2iybt3aIR9cvqn7(RGHL76oH8euZzqdywChyupqWWLamCQsYI5saAz43aTmCbtxY94lmT5R2RgaZILaZoDrzfvKqLbfcOfJiW0vdm5BDRv1CQ1TwvpZcyey9mN4COoZHkFo2ti3R1kbtvhy6j7B4QIH6rBAVrwM6nZ7Swjco5QwMPMaGDHEPfmlmNfFb9WUGUnkOTGtqxccApcamhBzbnpKGBMLlZkr9x8z2ulr19(c6f0bgpji4MVXJBqnM8iOLiam78RGB9nEW4bb4wnmbThkeCQV6mhvdep)OZC0aDhPOAolb98obTavbnhGGtn7ERVJqYhS2W6IiOvncyuO65LwYQRdaTJLKFTtLeO55f1ujbA5WIQ5He08qcoL2OFTOUL2mw8sJfflTUH42slU7wu3sB6s0zrAQ6jGZuATj)c6zUcUTTyOVUe6YaaWTMfhSjN6NrZY7NPJkRhPeS1S4zjrDZSyDVUC72MzMWlQELhb9I7cMrEGBZmkGReyHKcUnZiEr3FEBPfvLf1T0I9EI6wAjStevl0rqVgUG2Ksb3ov4(kXwA3p2okw0Subru32MUclc1TTf9nvA322m1thFK5ZqBXKdr7d(SCfGj4Y9Liavu3HL4vaKCgTaeCQ6h6AnTRK6mEnWmpgQEblLGijayebbmIGk9ZMCWEdvcYhMlf0mjbmcnWTiYL9L(STiY5RtY)NHWjOWfvReVGtNQ2et39nhTETSXWWOnX0tivGKuRXOey90e0lnj4WLOyjFsRx2vRbnIGQJVMZSSbmkbZCO5iDkQZqOIGfp17m7RRwqBRVjqif1rg1zmZsuNEhf(APoKTVtljUTnTCETqMomWEOyIYliMay551OeGGZCH54lc1yIPGJyYNSWUO6LWfCZH4LHN6gzRRdRFYf0(i9rwy2l7kdmdYQ2dT0wQq0WPZ(y5rEtVwDhK1ReK1)e0KltpY7ehH8VzrEmFiYuaMHsGw1HhSQifDo3KpAfOMvbuw0ay6naAnRjbHPb0(vXfg6)ZyhqRFROoDCFZo5iQB2o1AfE1PYed2jPXvEcULq84IOUv8rLhOMjba3MJudT7QtqVi0wUjqRf1TnKnvwu9oIcC))etLI4wzIP9I6wzYLPduZmaqBniM(R)pZ5lB)sxt8wLsWwyXJnI6wyX92qn2Kiyek8Eu(fQX5bcUf8mldQ2QssqwPd0wXIPO8)BbiRo7o8ONTqt9woDk)VDEHCJX()lpJoVojPt9BUjn4R2H56EWWL6u)U2PzX)y8rAKXPCAEAbxtBRD209o(a6)v(50Oz2A8Yj)B8rGGrOdWSulWiAfy0wcywvaOdQrYHHzt(tRLcdXSojWiVv3ElEzfGzjEG22C9zz1iGB5MZ5JsqwI)9DcMe5WOOFoWT0YwBQeSfXOKlu3IyzhLFNtRi72IUAk2Iiosxu3g0Oegu3wrchaL2T3l79PCW12NnkHPRlLitxheOuDYrPtFwwW7TuR3Y)veS3lBd1SEgWTXp6n9gl38QCaNP73JArqDMSohBsDOzNENNe4jpVN7onbNbGzt)e1P00TqHfy8ehPqcwb3pJoaqDebJYzP(IQkPl5jBDPYHP(o31YI6wFh1bQDBm1H41vs7kexUnV1baQZ0IkWNd1rqdjzYSviToEWECtkbKsBfDR92CsWSuzT)gUigJtElfgc1e6vuSjObeClIvKVuJifr8pGs7wezBkLpv3Iyf0lhRLCyLUlVPL(Hv6(ZkD)zmVH8D7D2L0F2LSLN1tBBx57zmV59t24CQKJ5na3XIvO)ZkFxB3rQKztpjhgZBaU9zJ5nqDBBJ5nqn6gdCwZUo46Ty2epwcTTNXkeO6amPIxRUlDJdyGdZPUGyChcW0595NXRa1H)R1JREqamkZQ2J(h)T22j))rmcwUhBnWY9i7aymWayeJamgyamQlbmc4agBy0nfJL(uXdCliQIh4w8eWiZh4wDYoBQeePAaT7QG62YLwOUVtQxoWm4qAZ0YpVN1DagLobgzhaZSdGBML78Dk4z2bWigr3anz4r(kpnZXIFDtXmTyfVAUXNqQH8nB4VG7yrUg5G6ypzDN36IOUdd7mtg0789tIlAOMRjAbNEY1g8pZ17GUXcg(fz2Cpb8ZAW5hTrp90hGrkmWixeyMOamYVQR7gNzZrULCyCSrDj44XT5MVrjyZ3z6(ED3OlaHmzf4KwTCLRKyjt6sKCC3rj54UJsYXhQZWTePpjy6uLiDxj1zvkF24gWpZL)aw1nktbCyWNRvqLGT0YrMvuNrO1YWpRLH66Di9K1DCtpwSc6bo9dR9IqD7sgJe39kHCy5uLBat33oWkP7PXNaGvF2mjBLUd1H35zCz4hjDp5W48kOoZcxP7htO1rtpNwsGjOMem9daZQr7vLSsq6h2Bnzrn8K1Dmr39bm13AFG6k5XetgcMjV1zJS28f6OJzWtKisp(m(amtqoQD5PZ15EBsW05bmsOagzChZ92ePDude4MzjcDucM2RU3MsPnlwrcYCqGBPL7TaYHCE20XYktZbMXhGrkjWmnh40p(DKzuB2vZebmJ7adllWm1f4u11z0WdkZvkiAMmgpdCkyzFupj94AC)lWPxFocfkbtrCnghd1mRayuCa40G0bVZ9K6G31Z4p0fZJBB6OzmuZeAsqMfFOaAj5WW)d1yJbWnTJdopMJahLwIakb3k54GtOommkK3tnlXIdFwIfhbZCBGZOPIj(5Z2UKXZFK2HHrx(NoT1v(z3LCN4bwWzaq3eOtAN(mT3Bd1P0uyMmuNst3wOMFyo2PueJTaa3sB8Ndu3slb5H(ST0YMVlQrQ(HU9r9O594AqOoZ30wopjy6(MJjaz2ObdWTbn7zXXAl7HmvnDFZ(8a1zYRUzQMemIkUhLdiTBvFKOESMFcCRKJoWhZ5385qQo75qs15bM18ibX06dP6CNGZ5j4qWiwbyynoRB1mN2e3RK2eHRSyYyAY3ZSf5Os)4DgGXpG6WA1k2Q9iUr1P03O4uJ6m6BAXfK1j030CWsW3g3LOPH(FNzHxRhAagXGadtWLeG0TnGHJcy6hUUY1zcjixNjcgEhGrJaGr)zGzSayKpam6pdmJfx6U7Pzebgv0bgzua3sBu3eQBPbZvpAc1mYdmt9aMrZ6cmoT4XenOMXyGzrcGBBBCyOIfRnhcRmuJSpGBPno)OcwR0mNv9GA4QRlpOEkcWmBPU8GgQB33Su311SuhWTiMTDcQB33ivgQBPnB7eu3sBKkd1m38ssLtRywleQ7G1SFmqD7(YL0d2wo6QS3iZ6ysNvtvGBL(37z1jfxwPFyUL70NnCQswspWQalYsAvGfTWSEmuZNDpbW7dIudRbW0tcmTTnEguANmtxjRTC9BDnUnWOD2T2dLUpdy6s2tHOOMH76YaOhURZMyZvVxgaate9i4wjZztuu3sB2PEOMj6a3slbcK(SP7BUeuFyrKixFVfce1PlrN7d32Kv3Ea49SuhR9e5okWSMemRVb1S(wDwkDJxgGpWS4tfSHd1WtwbByOol1vbB4qnCuvWgouJUrqnlnZQIBMn(6cQdh1CPTs)WyloWmN)EoxRKGrd6kCftVZSHcSA7W7OqqZ8oZD8Lo8)dNQSzojyKgXI0BV(43gwVERotqrCpbhm5BIBDb3ENrP375P3Hem6CbCtBcIlLGPomNvVN60U667Ckge1PfpxpBI6mBzc4rrDgH0HK1DFkGAs(UCuZHUNpB2cdGB(MywvjyRVJ9Fke6cRXNrDXBTF4U0oYTLZtDIBnBVo8jMJsh(KHAuMM0gFjbmRfcmcZbM1cvq4nzwEHcO0gl)bgR3U11xvQzZorExwY1snMRKkGiwXYsogLPVp2b2JrSnuNjKAB0tMLypJmB8BEDd17HLDB0rzWPMT7DouN5q6v2X57Un6KGHxx3dBjbJdLzHHri25OTcRrmscuy86XcTnOUMPndQZShD(uAQad7PIHOnbPMb1uAaZs(atLeyQKaJaKhfSSU0MlusDTASuhRf1gEpPD6QFMBEADXBe(3NvIiWO7yfnELoHRl4FQloXM44wqmxAYjD0L79D7zm0MVp9xaZOoWPHV(ThQtdxE2XTw5zh33UE2HQqe6x1MjbBPnrcajyQJYf(tAdpgjiI1EK38tc2bv56NH6wAJAe8zZG6C2NFG6wAJAe19AsYSr1Gh56N0Ihh7d1HfsU(zsW2toAnsA3UVXsgglcVlWHlDDHFnyL8DCHpu3rOXRiqDlIzPGN5k7Nw84veGBF2Suau3rOXbjqDlTrtfOUL2yapLXocLJbcehzoa3rODIaD7tV(48ts7mTJIBtqZ9HAk6QNrdwfS7(ky32kypcvWUTvWEeQGDBRGn)qb72wb3sZBMNO61Gk4weEnOI6MVEh8kQDeHi4whDuyue3gH3aVIA3LvWTryhjvu3cZrHrrT7Ye063uWTiCyavu3IWYekQ9IJfSvnRGB)K1fQO2INeCRJw6qrClxlDOOULR97BrT5gk420S(7f1D8XshevlDOGBPzPdf1T0Soyf1T0Sh)lQBR0shkQT0bb9jYrWnP6zQ09cBVVJ(FszEoJaMTnsql8ayupcyUSslyVsEbBTHlyRcHG2YKc2Ytl4uXYvpCrD4OL)ztAD0OOeylvl40JL3qWI60JLNTSIApBTGBL0sIevFRwwW2kMcoZeYY3qnxyKfCAqk08D3VIwOa1U52D6EPnHS82con4lhOnI6wDL10UMN7RlLaFkDk4WVj7BtA9Q3Ka5jrtnEsSOoIgYv1rrDYS8QakQRua5VUKz7uufhld1PhjgwRCW2siO3tnb3XvTcU7YYMSOZ9)mzdyYxGH1rpzRUGFffY5ZKc5DMbmJG6XUCtBgGGA4xaM5ZaNIi6MxzwMHvbJDkcV5XkbEdVky44QqCT7DaMPfviU2SzviUoWwp(IARhFbBJelyRhFbB94l4uA5SxwuN6B96u60o8SVK6)d1nT2tTkhC49xWTM5TmOOMXTkmBtM57vCLa7Jt9Q75T4a4xBNFbNEN88hPR5HzfKx5zRcQ66LWT4C1rQl)b72H3)G2PPz(wNa7oTat)B9aU29KVJbAfmmbyRCRnLU(YgENp5Ea49paJ8dGPp7tDTGwFgWW9bmCFad3hWW9bmfmWW9bmCFat)lWP0uWa2CFFKJcDblhf2RGRW9oOW58rhAu)r6QhSxkqCwT0BAIPZL2vskM3L1zb2h0DD1zKCfB(s)1H2m8UQCKi1UGTdzkywbsN9IUx(yxEO2ZUUgw7zNtqcLuDlC4qjTGzK(ix)UI6OzcW0HFihA7mlxdz6E8yuZb4uA5(JvjWM4lOJncb9UtlO99OUjq2slpkgf1mMw7yHRd5(ISsqe)FOO(ljWMZOeyZze0BjDbNbf5LX8z2qpDBK4D0SGZyP0D3dq5PUsjyhSRqMPhaKwVoFX(atf7OZ42CjRPl8ehN1cAd8kyYSZCPnPBeLzzDDPR7IqxV6lSVacvAJgPkSY761z9cw2)T6CnkmM6DeY0KZi6)vBAPrzcsz4EtB09du6Ea2rcQ()md9um1DxIUWBZ)ptfHLDAW6waZv4STS6ADX2xOR1LHL8uRA3C91DzAxSFDyNkuACF9ZRHO1EyauckRcIaI)dIQJdlbgT2bgjfaZCYRDSRot4DUcmsmVYDKOO6iyPGHZgyyCb27MKsqQH1zlSfaCLNYZ3)uBxyLYBVBHcn5u5G5UVU8sBlSQuOOr(vxrOOBVuSOl86w2ZOO(L24UqR32kLUEBReAQoAPltBknPKwtBgGYLnROf(R6ui40LX05QMvjCSsayyu1nqV7jMXCDq9dTnDDKVr(ms3RRs5IMm3VyIEvpRzYBlcA(DqM1uiRKOGEoUGE8uqpEkOx9rqpGkLY8KvbnF(l4jhQ6YlR6hEvR8A0836uJwR5WF77wOc27Uqb7ZJdqP86a79IRO2rEubB)pwqVwMG9EXvuNstBd(qDknTn4HQdop9zz1wGrbpGX8Wx)KBuzsRC6LZbfLsdCQzYxwd1PMjFznuNAM0eEO2H897xVIkdyKM3gxiMtjLGyDrpORZxAXtu3aS1856nI2zkW2LVfvRkdqKT0LkqRJkqVvEqT8vwLTvSkAKzDHw4zERnEOZFevBvWe0kfjy6IaA5qIA4qbAvCf1WFbS3iQkFt9g4wA2xRkbokblOL6jy6pa2ogVsGxlvWT0822wjODmEbZKG36WYeQo2tucI2ycUTnVTTvc2sZXSErDBBEBBlQBBlQwbv7loLGOXMGBP5DWTsW2t6DWTOA1SeCBBznfOod7a9cbIQLJl42t6TIv5R3ZVcUJqXKNxV1EX4(mDh31YRG6uj1UU4X4SRlvcMkPUMjsoeTZib(ArwP1XRwbJiXsv)5ZMbGXEps7ijSE(w6zcaZKI5HAbQ5jzrqhbVfCkI8SfkQ2t)fmYDHnB6(Y7pOsG3dnG62L11b9OlmWmjMee5faNkzE0fuoeRFeCg3KGz3pOBvYbodasTdpaKxXvMU)cP0DAR3WKa9PaxuJzI6miNMzfzW1A4YUyR6KGwRV6fGCtG1wxu3CiUnquT1LcgHnvW8ofH1yqhZ5T0ShXvDWEeVGzHpGt(MBnjsqoBTcombaZkfWVeMR(bkSBMk0DAUAGPNSETchQzb169kmFMDMV(mhcifmsUaULMdB3kbHvgyw(g4wAJSeOAJh11(TDDHGDi4PmlMji4mwOLvMeSTnV1n1NfjxZZftrDlTrwYNdFiKvcIJ1emtgaATMe1T0IU0I6228narLzBpPDXVO6TvSGBpzubxu3sZ70AL2TN0U4VOg5zaN2woDUKaTdJUJs7W4aNXnTdJd1zClhu3khMEsjHXmm5TxvjiUyWp5K94w9Mtg40NPdQ7qDMTOJQzllPEGCgywpUEGCmvfOMU(QNbANz61uyGtlwbIvsBCAUo)6tlwbI18ztntQdpuN5XkqS8uAfiwjFNv0)OaXAOo8ojUrPTLR07cAxKj4ietbILfILaXsPDNfM7(JI60)w(xP7(KWXbUTTDwOI(TjbBBBNfIzrtcMv0rSZwAX926G(pseZlqHQdZSWZ6KzuQKvBdDJ8MQcsIzBAssKr2UcOz7kEvxI(9)63nvHSPpVk)X3)RFNneYgJdAkx)ipY)QTyU)cfAYgftdoJdg0TbCggbMowGr7Y6DtV(CDvI1mhGYIhatpmWW9CnEAG0kpn4mWg1vVTBDFrXh2ihJFG0fEtZJCLJ8GEIMhv2bMLGbMLGb2pTe6nCgLDmYgHcnB6jOW1akDj1Zow)j(oFsiB9lO5JvOY501NazLUuFRhH8Ecs9iKpWmDeQraeWmD8rBwOtBDj2uzRowgD3WJumQzPvOTUWWO)irCoTkikCETI4EwZjagPhaNQRCQR)m1ADML3dik48EavWiVeyKvbmRfuVPMjZCKbQpBwla4wAXXxkbBM5qIvVc3z2kOFbmkXc1PrKxc86RMUHNr1wOoDz64y6(u96y2dQY3CH4iZhItpMoJMULLZOz9vzQtf3cTCCGHnfyytR4wijWhQxL2rilWO0iWzKi3PxV1wzyvuf0QOkOlybDblOl4Ahq6cwBnGnTO2gHEWwqRIQGUGf0QOw7OWMwZZlQwKUGMLvB5Gn4qq39j4ue5gcKcoxlGf0Iwe0IEf0YEe0cCe0cC02iy1oRDuOLtj4MdzBYe1nZIJFHACXRGwjmb3Ci2PiQBoep2iQBnllKc1OZTGBBZrzKQKrNBbTUXcUfr05wu3IWrzKYbhfkfClIOZTOUTIOZTOATteCZ3ifx7cZ2Pg)flQBLmldkQBM5NmDvDYoOk4oS4aJVsW2vh3ocvhGukboArk422Cytvu3QJdlTI6wDY2S)(NC7Utcsajk42RRB4AZ7mwKqc2EsPtyNaw8o9oS2vMTamtraMPiaZuKxstMEw4lfCZdCYHeCZvcMmlNE)IQfCjyMV9A2BxOgNIiOfxjOf5kOfxjOftkOnBsqlMuqltwWT0gwJxYhSTaK6QGPKEk4we(g8VOU5RpRwIQFa8lOL)QfqNCqYYD(kz5EayeGR0A1KbMOXrWi3bOvUtudlNUlJM8n7PLsWwez3af1PxxNY(uhYUJOLR3Q(ietxLm96fkbBP5RkLI60RNdCFrnti1jjEQKjohibJOnDKv3eyLducMU6C4lv(g7jKMed)RcrVujJxwvc2oQrU(lDkk9WDUXjv(oZHa6ft10WEzvnjZvX3jSxHyc71cADhKlkTUdcM6fWWidmDPaTIvkTzzkGPlfO1urjimYVLDKDB49yhPGzaey6ZRxm4M3dygalFsnutFE94b3mgLNQ6U06XdoPDyol)xLemmN1JhCYbFVpOCiBvTGBPTDu6QDkzMpGU6Z8PIPGrss9kEL06ZZxLGTlXhTprnoMuEIDgwuu6KCikqQeS1HSBCIAKVaCgwYZCUkIOaPGdtGSFj9zjedKlGhMa9uaL6GpAjkZIZeeClTeXdIAMfdCgw(g9kLRLhMGVoM1jFZBLBbhMGCtnvuNHLVrftrnZIR7VPwwFDRnzUp5ka3m1BL7qntXQlWj3m1UUpjygn1D50KGOQxDToL0MikroiFRK(q8PQZiQbyeSv3ftPMLqdu(vplbdCMxmXCLsqwnUUHMMCyMxKxZmvWJSi0pzlTSBf6zMFlT4BdrDhagvYGAeA)wVLsPX7JXQkTDgGUyMMeKfMjbBFw2Gb9(2hnLbUdlzxfuc2HLSRcI6we(MWr1Hzb01jXAdi2r(4KyrDBfzRee1DKN1stRiBLGsW2kY(ha1S)bcUTIyNNOUTcFcWu9ng2k42rfV0RDjj2Cam2CaC411ETB2(6vtQNbKxD4covhDMgDdkpcsvcM5XJFbe1r86SD3A7zMzw55Au5WoZsV6WE2ICSXahH55(sV(SzMvES6lQJmkDGkt9DxOkhOsL2Sv)cULMVHDQemJMx7cv6(ZkDu(MzqPnXQRGJ8xDQWtRyf8RtY5qD7(gRcjh2IySk8DoFNQ0g7)aUz2ywZB94aMIWpOn6ZqSDQ6RyBDIahQrLxs7oCVCuAdQtNA26dLVd3N2GANaTb1dCMMQnOEOomxZguRDyl2mdC4FZfwfTI6bUT5uRx42aNAMuJDsWWiQnVnu3flxnAFx(tYz2UyzULLvPTZchVTiQrtoGZYxYBlPMTlwQ3yHH6WAiVTmuhPN5IWsfCCQKcsViiT8VDpUnVd7combFY1LNOoM5cmkpbmfmWydkWmFdywKayKNbmntGPt9JE2d6wr90PpWT0glCMNo9kTBPncOHAgcRNo9ECdyyU(ODXluJtI17x0wAJXoqnDQa3sZNgdLVJDpa32w2QgsWyOmWTTngkd1OyiWT0Yw1OCy7jhggOgnqaggMp5sSq1SHHb422gggOULw8cP(SHlzINurDBBJ2vZlrkL2ecGcoLMwdWJMAnGbo9K5joVYHmzOE557PtaN22e5GqD0Uc4wAzVPvcIiiGrkhWPNuRbKQZy)hjiQj9rRbyUe5u7bUL2OzoPDBBjeBPomRbaClTeBVkbEBaao8aA1GuXg1Z4)ZuEGzLoGB5olma1zem3riQJmB9KGZmVzRNG6yQiWT0sOhQeKfgaUJGjysucIYGah(LzRNibJJvaU9PRufDha0gjrc222kvroHzsW2Now7WNT9PBsh7EM3OhvcztOeCl3XdkqDBLJhuG6wUJZ1(m78ez24rTDNNe1DQq25jrnAvx78ug4hxUb1TJC8(2hD(fsAxHk6W(NoNvMXCQgO0wzg5kyr9dZImaJxYagv0bU9oRmJCfSu5W2vhh9lQZuxTEURV5cWIpl3mJfCKMLRJrfZt(upxWjZuy46MPcdxpZuHHRlcDe6gQZKFDe6gQZse1vFxXXD8kHmJGrJaGzXlGPscC)SeYm8zjKzem1mGPMDiNK3vDGzW6iVhvI6SEdWu1bMQoWT6KZCZ7JCx8Py)AmZfyewbCQd5OzxPDkIjiHe107uVqiU3rbjuGBlEoui8zBlEcsirnJfa3sZN7FvhgLXbMLRbUL2ii(i3q)6ZsmPlyeicmcnaMjVaZmR6fWkTIrqmu3sBe)EKBOFvAJN6aU9KJ4xOUTTX6yOULwokokZ2slbhmuhRJbUJBJ1XqDBBJI7qDBBzN)vMnCQ5j9sTICC5emZHaMj61R7Lzp)mk1b1Ht9ZOuhuJWEGzvZd5M90)oBybu38D2WcOU57S3fqDZ3r8ku3IyCq9bRxN6Roq8Tkdh6aXpqhkVqftdkpwQhm4A3Db1VkncHchg5Od9D9(w000Avg59ngAtUmEDRUNZYNKLHM4B)9HwWP16gy2OVJCNuPaWmhzjbJffaJToaJAnaJToh3(Ybu5GFyqkySe8yoHpqDSLeizMISDTrwTKX5DyRGPXOls(AJRHyFMYfYr0niVT2GYG0Po3nnNuh1)bg2sOUPnheosBckybdBjWW(am2AamSpa3slNieLdBP9lQzZ(jEQydShpagZfbg3Dam6HcmE(4u(QS5ViPHRdy46ao9CA9PU)s()XiFEDGMpWqGY6nGcROoEL5tM6XAD(5UW(zE4Wl)6M5eaNUW8gIxjy6SetMhAYBMx5o4zOr3kzjbZ2OCQJzWqD6JNZZi5WomohTrrDyeMdRJOUL2o0OxWOueJNjpfh7qDg9NZ4JCu9MzZECCQaejF24xrOUTIXW3tDfNL0ocgp1XjiuN1IpZ1uTC(CI8lbZS8ZNenfY70zTnGr()xD6rAXLaZQyaJKEGzvmGP(cmRRamRqdmn(V64F31xGrImWT0MvXGAKPamRIbmRRamti(Q99PNXamsWagzR5v7YE4T43LxDBPlyoEgvXC8W6vVrJnFE5mZcT(7dtNIMuatFeMoLUaGPRfy6cWmQ0famY3aM5U69Q19961MDHt(MNhTYdDXIj9YO6MJERsNpB2VrOU57OMJE0rTqdGz2mw1T1SzBWG60mLcnDNhuZGdWiUayuwd40pSQUG1It3xECHuMnQUaCZ3CM)Fx3Uz9i9LmTX1HC7MvuN8vM2mjWbv2BzmIhlLBN7rv51zJ8zAcAzb36G)1)RISiJgocTTqMgtpmYHSfFrKTG0RS0Ro(G9SlqXf11Rfy3YQ77Pbg2zOMLfaYYcvrP1y7cTojIgLvdRBortlRgkbBDfwVQ7(F9f5IOLvgQ7TgNUSoBE12u6M1dk5CoHzs)TEbHcXW7JuWW7dmRDcmIbbgzjaJeCGtp3SdY364W0IsQljPEHpGz0h40lRZ96KGWvrcCumwVMcEarhxx3ZoA7QxKW0yKYUDBvUAWOnFMgDoXx1ZOGRN7M1cXPjnA8ExVtpDwMOee005KhKf5UyhHJ1tHWVQ0vA8a3DDTl20Ia9BfQa9ubSZnEm)wNqVwtlzQTa5cphG84SQm1RqDX)xp1ZvfeKBP1d9CttpMJbzwN6rCo0s(vMR2FroSFGMVqlI7)D(c9kVAAUFdR6CRSoP)vDNu9h3aKruaDOfAatZAadVnWIbqouYYY2IQy(O3V3cjf76gV0RR4ma5aWfKfC8blbA2bqPAxVL7MMNZHXsEohihsQGsDr2a4YqhaQ(B15FYOKlJUTyKKdOxSgAqjKDXwilMcKftbkdIs7UUvwBYxHQ7HtJYqC5CRMMSsYiRoi0s5wpiW9)Q9R3ilpbAPgu6k6)1tI4FNYvCY9)Q7sWcvhT6gLGvf5doxyoVRPmL3SrGCR8OUET03cY1EqZ)kJ9Q)vUzXOm6ZGVRbGSiDqUVc2aZwcBGhlbzl7aLYTEkSRYqXww1YHDjFBj9QOvV42gL6IE5))JedRmkSynay2pqlnpCaT5d8SGXGraPqvSGutAQ3fXgWAonG(1gaBzdOaBadnnab9nazdfqUYuaTfovoRqiXalJspDyv7dRSCpszqw1JaYvU2ARMwSRRnAQPLr2tz)RPLldHZZ5BpdNYP2)OQhgdRSikqPgO9oU)361s1ipVgAiuPPPiCOrARkluznC1yLgKnj5gwJCu3xVx4v3LI3Ko3k3nAu6vQx5LkzA7lBaRH1aw3PbWh2apOOWdPsScoKgOiSRaA6FdyUxd8GR21i)x0u7)YIp1g6xLL2IidCfREdE7)YcDRTgQP42O2c)knAZOR)QEOBBadIfqlO2aNHAldmfej0)vsSw0VOOOZq9zaSufqw2jilD8sCifpfilffKNGaYtq0WOZ3u)0Q2Dj5XeaEqeK7wQDlOYEfkxbzbaqZcaaL2F4tVQWQQ)0CK4V0(y20Qh1lJSenOLYVEo27)vN4nJmBh0m)eilfbKLAcYmLG8QjGs)LCrq3FvHaIrEga0spNmtYPtgevDuYrdnWRWk9VnfZfQnqOy61BEUBckKt7gtDD6AuQKv8MAAzGqrBAp2iZQAG7qULMhvfdK7qazMfmJZnzqo3U1ZqqvcyXV5c01Aun9rk5w1xajpKNcRsxVrx(pd)qD2pQ)to4RbEz36g1SADG8WmkoAoeqwOgOuZQZey)frOgipKcYmg1TCzNU6S1ufRc92g4P719wqrrpIvnWInQn2VOilEBGhDEKEzfjfaPvhREMMmjzwErAM6bYcXFKYkv7fKhDE06pMwy1HM7zbzgx9Ip4Iq(oUZKSQsDHmwKQtwRrMZbAMv(5mQnbY8qOK78f5Kb9OWmSZfTPJ1a6J2ZXULvZWR2VI2Og0sjXK9UIdWZwbPaCQ(tBNaArlVqxjlJXGS6wyvVv0hl5vq6vPtxk)b19MIwV(oiZhjuZHJQ1EL(p6HUwvxaUub0TfrQvVqix1b1CZqJUHciNx3a3wEP4dOOOL2AqZ3cWkVasrJzttxEJg18rIwlqtOEivOEKuOMxrOE0aKIiaJA1ffTj)S9hIM7Ja1JZIwYLAR6kAAj1(F1z2jOutvaFN01YJu6snvr7D(3jNLxw60POP1OjNTvm6FN8Zc6fTm6uVFA93QROzHE)JL1iKthiNoDBQ40Ply7QCv4s31zqUoRJ80qZdT6(PUt2BTBNg5ULooPnnxLHwpXsFrk26I0UPPaBWO5lsttbuF(3TCTOp9Svzwqa90ErlnJ32dgIwAqVLFKC661H0)2t31BFLzZb5HJ(sIO(x9QHxZlRRh7cyvjaK(96Q6QsEfL3gLIssEnnVWjPt(DQsxohKGSvWcLUm9OM2vefQhDxwfPhg55bqlDzYYD)VERn4lSXnFQxvYUMwUHPr(zOfJyDOVluVWliZcu(CuuQJJI(qKg5rrqMj7tDNe3)RvNfKpmNc5IVp1)v6KFOQkC9cFzAwm(Np(v9bG85DLSdFMifQvstipexM62zNuTpOur16dHM77iD7x0R3W3knfmAYfFgx5F1BVr9V5mZku6OSjpqQ1bqGu70UUOfdGMxmqVY41imQhKowfUXDFTISRcivJQuDz1N)GbTUkwxLy1Fgp5juVGoilNwVMy1qACmHaTvvGS4caz8tNfgN(EvEsLNciFW1uuCyjqDFdQQaMf36TiKNlugnx1(YO58VTjWIwRMiOm)OIRGo)qSv34o0dmFJ0fMxJ0ROVrwvQ6MnOZoPfB1cQNmTIuodVc5vDQ3Di)Vwdb(3WqdYZfp0k6fpbi31dYD9G86u17nuxN0MIgKN9cnZUxp7q5F3VWCrhkaiQmP2GZgzvkaLACU4QuupAU4t0MRhuoLVzBG5Hp1XOOYStDITdYIVRnnSAH8NU3bKhja1ATP)1Z7aL8RK7ufM35pbsvQo089F65eaSeqqw5GSPGKQia8CetH1REseOKV6uPwDHO)QzoazMdqEycuAe60)uS81lACdAZqRqU0apTOIh(6VIQn1ZCCtXYVaywamh2tBLRWQQf294EEqUhfKRmGsMin36VqpHsbLmU2QYQu9gpO4M0S0FL6j1WcO2ttc5PJG8eoqURhKh0azUmqwjYV6OO5Cr72xNF(gCsOjx0U(4)DYfFTUROY0dVG8QQGsxqD(Y6V1whiKzQaz2BqEmh0ug6aM3FRcUCJMYiZw4FNYG1Ak5akKnR(2RFKGlJmtc088aqETbqEM5vSkuXNPLhwHOFLjVShzfkzIobYDr8kIvynCp5hKxQHvZTyLR6K2w1tTEDdmhvfoLff1MBGBYxXEoD3vyjkm5YCrLr99hevoa4ryqEzL(o3RQT1zBWipHhATNEQ4)RMixb3xLkn(w)3T27Vg4vTQxWRIYKgnW3uAF(Sluj)ZwnXAdNAG7O12nvDL3kwVQH87k(ymYTvO5oFqEMf2m7jaGmBfi3pbYJVyvSNZEpYib51MV1nDr3s018vd8k560S2uyGSMUGn0wcSoYQvF5D5qSgHGGozAPGUjOaJO)3Qd2iZycnZ2ckv8ROm)DDFp3Fr04cKhDazwzqPPwp7C9xOTnZOuxQB)5IwD5pBu6IRBbAtlFBfFfMwkJ69HRP57IdHMYqrOC)VXOuqtze9zG2ugrzwOnLM31fYfVlKcL(pPQRlJORj)7ud8vtR(IPoRiSORvEl6ek9KkMkC(5x9D9VZ3AxvaTSseOPff1eG20IIcdqBY5yYp0M6sKpG9VtBlkwaTz8WUOGAG3pcHM2BenaTPo7DDH05RQfHMYiAccTPNCMwvrns3xLf7an15HNug370j392Frw2dB2N6xe5cTu)K5i9xuVh5gLYqgpBAzjZ76us3PB46gtMH2KZ2jEKUH)Roj093oCIAnjNFJGI6PeVtxuif0uxgUU6So70n5suxLVyQldxxDpM3FXW1jDDCUeDDUhnCanTx7mu(2HZrV2R(B9M9Y)oCo179rxAdNt9mEBAzKPUVynTPUmcFvuk7Vy4sQN5J(lgEJ8mCROHEQvJ8kTpC(l8(MP0L55vqf15NcamJMYn2uY)o1EV1Y6lCD(rVPg13w3Xnb5YTUHBcn3YFQBaK6lEpFB5ndjTVunPbTVK)mmbaCvhDqSIy61C2zMIr2oBL1TbzMpOzLKa5fIbzwUhfMRD1uB0CTmcOuA6oBRZVAh0Au8haO0WuaowDOpX9(GYq6tCrVcrDVeeilcaKzsF05XPwCduQ91JbyrB8FwDN201fP4zqPfv38b9)o15zIQE1HY)gX(1TsJ)IOQF983yAXwV(TIPZzlM5OEeqenH6EdH6VfK3CiqwCjilAuOUpvOU3qOjx8DTSESKBgn9wjpPZmK6rtUBr6ntU71ek5CIHbrRBLcnFHfmPhz5MXvO0IEzF7O3D5HMnorpaZPMk1r93AlA1BY8KFEzj94mp1klwq0MCz6HQltRUU47(lqMBsOP08YdqZJmcnLbtEf3e08MPE8JcjVoNJRdfQ5jfk1z9Q7L0L6NEj2BA1vQPrThFpQxrdJ8cEh)KfJek15A7uRVilgjugpYImqZQ2iulSsxj(T68GC2XyVRYGCvgKRYGCh5RSzuhGgAHn41mu(6LoC3QWaLCooW)q3kODJeoJEsRqPUibsvtt3yLb5v1HwyIFPxsUF1FUsxYdP(CNBhARxnkLFEiU5F1MJ2)BgMbLY6Wx2BhVsGmbY2Ekul7vhRepqcYdKGsRqBBtxgN2vHGY0oqPoRn4QRZ6UsO)IyKKqjN1oH7)16xOJWsQl6KD15sDQFmk)BTt(MMN4t6s5QtTB(32YzLl9IcczgYxztCGMo1j9)A3HjulG94vT2QgxIqbDts01ja9oWCuU0Ub9wQcOTadqVN)1d2G)lZV8UgZRCQEDlmYJ1qZCSkGxY)MElD6FgAt6SbCkyyMCjJM6iDKVicFQOdXLRTuwbnZuRIq56MqPtNCfB36vK6wt8QBT1IKm0nOubQNE8(Fd7uhWanTi5u7ZEzpk0AR0eO3kumFSDBIaMr8Dw57au73MkMD6KfTwbzDgbz)OdYBKnOi(cu6fJUw8V2IqqrosTpJDvxB0yXJaknhwdS)3p)KEmqUtbKNNaYDkG6nouFH5n)ON8)kNb5wuTBMf3milnsBSz3LPybS6OQ7S5g0oq64J2D9(dFzR6fYS3GA3bjAMTuBx5qZtCGwQC66F05NEVk7VvNalJAB5fT2bs6uDLMZl7KkrZt6aLMJwTnFXug2Bc6lMYiRXoBQHoFwEi4Zie(tDyLQAWh7nyH6qkPoyvDHvUZOj1bmGaDeYuh0kts3eH9FQnUR(tVl0c0ELTocwDUMnRsiZEkDo9FAtV150k17edb68y5jQ1njC3cIFteYll0xSV9)QRuaJM8txZInnR3OqEwzFV4w)REYncYS2O0ByzRNS8oDw7yDyUMVvggvTB7WBbSS7kIg7UAD2ABq7dNJsRHgyzi157QPeMaDRT0nVVYZE9FM(J6EeOjLHQi2IH4m5Qoj6vQSNLRZ7vpbXrvfG2cdaTxap0w(09i127yu6BkhJ0jlZMJViGKvvwO0vxpt1DMOTfR)0uM6wnQO496bGvNPI16(VAhMdiJTLrBnP2hGOnq7WsaUxVIK6MILsurrDtXSqO8INGlLm6APuOyqU7gAESaKxDqQc0Do9br1OjD(kTL)1o8huV9eh1APnWTX6Ky1usguxw4vMwxHHgzTsHM5l16qU6Q1H6MqD5HBuAQJec(xlKwlyL0fnPRWc1FBe)RLPgAPPwxQHDzK5HGMwOhQy(9uerxpOnnJWdbTjJTT5KX22CH28Zk(Q19sfitWH2u5T96h15NT7wQJpBJcJDDCw7MHo8hbLoOSzG8VzD0(KSwFHcCO(lsObjuAhkwuZ)MYiBcmPBgaLqoNUzyB0bH0L2BEBF4B929iuAV6Dj25s0QIQxQFJ(lhjySOIodV1T9v1okTwl(q)u1iqAgFJTIqRDpXr2IAar)WJ6UrOYTS1Jk6Fdh)WoChf4qOSxx4OEzCRpvrBsqPZlUHI)1B5hO0nEwp9W6BpRhw4gPxZ5cvVWWnkSnG88kqM)gKlnq5luWOuTwzpqnb(07CoaZWlZc6)sv8gyj0No4nHZWd0N6LbRRR1fmwH0LhHr2n9qlgkDwx2av26nMhqYnfXC9xQiBQr1L(yJKLS1xgjRYWLU94q1fqYR69WT)pxG6(FRYta(7gUKX0M6S3vFNSXPkU6UGRbw(RUh4CAC)OUd4QA53YO0k1YDffWXKlaRm03p(Y8M5o(HisOKfFIWNk4uRSiSeFVvSPRc6QUS)0Fw9TfWHvjaVQsDaq1FvlIvGmhDoYkhkWfQ(LNFIqm0628VpJPnOHTNI(uxMr1xOnevvIZk2wAqRufSXD7)8hD5fqQHjwZalsEShlz76oMV2lG0VKznOBeNsdtdsAKVOQ)YgIapUpH2NV1dYv9NkKQuTeGdNwqw0TqDRrOU9lulHqOE2JqTOhqwWKqnV(57CagazxPluYVQT0PZrqOqPmEzbXqZ68cY(htOwlzHAnXfQh8bPltvJAfvfTw6JqTM4c1SCc12riuRQaiRzPqtUOBFr)VtUOlXltZJLv8V1PRE8YnkTTefk6FtFL8eLtNDnd)R3obHM)D6HQ775oNTzWcL(06gEU)x7kdHMCXotbA2hWNKDTQrG8blsO22hHAzScLECDqLmnlr)SVWnlgmlYgWWUOalRZUC2fa5GstO0nNWPbAwFnHshzDN605InrsOWsMGTr0cZzc2gOznxfkDgjSBeTPmSqCrlDK6Ym2LR9NG(3Pm8YrqZkYj0ug2yhrldrzhBfTP2pm71tZB3kT6Bc1lEi0KZE9DrBQ9EbfrBQ9wrorBYzVKc0MP(viH1LHxMrOjN9YrNVV19DuLo57OEu9zMwQDOX0SrB8V2GdHMVv3)I93otg1JQEO1wVQ)TnA9S8AGr(euanRlciVZPGSzXc1lddsXJUrUgaTwCT(xp9fKRbGSGgqwWai32(upYR936GAwO23yNYo4QJed7AhObQx(dnm6Lp7trudADTWsu)zO2xRbkAweUBPk4qZJIOIxRuYPuXSkNkQ1AqBbgGuooiaR3qYon2wraEvkDkU66s4uoQRzGQUO1y7VZh7HtP1zvi68LyGhvzDolubK7Nb5zaGAneoRlV3g0QtaOdWqajnzsYz2sWtqw(5PyUQkiAM0AhjKliusXtda5PAGChiAUy276S6xTCf(Kv9OUJxBW8xUxgLs6r)V6i20fP6cmYUncAEd8afPpFLT013ELtHTooxTdheY5hi3Fu3)yQEuNvXgy217OzYji3Ib5wmiZcdYSWGA9g1vyrRlJqEAciZ4bYdFG8W3TETe6Vqgtxnwq7)AHZqZAyaYJs36k9V)w9kAfKzPHwQvYQy)Vomf4lCeZkuk36w9VZpBvSqtzeogOLwUSk25SUbP6V1VbMcnFBexcTP27WUH05ZIqFPCOrJeGiN3XlvcLE(JPNxBzrnW)OBHIQ8XWiZtcY9fGM)1HJcPZHJIqEm4jEhtXXO1haK5SFI5IO5VT9riZJaYAkkV9wmxYzVQoP7BJMnRUulufgG5kfQZcH6ohMnjF9wFGDyoGw1uaTvda6MNajhu4N6)S7kz6yRJkGEAaaVmMqDFf2uyX)GCazkuRF9x9kCuvF9gCuPht(AEaHAnfb5fNeQv(qOUVvOMptOMptixXb18kIM7e0Z3ssNT)K)12Fk0KFPdeAZ3AZ4riKTftOwSRqUVaKRlGCDbupBxPZ9p6bUFO5A1BT4PtN3If(cRBUqtoBVbiAt(HYB))RURMEBRRJOiPggifibocPPaLPno21bMPm2KswI8TmoF0fTbi1UnDziL0tIeMMKLF4y3L6NG)jy0TDtqr7(8lqiR4A)til66EoZ5mxPejNydKnnij8O5D)CUZDUZCF378Y8MLh)MClA8RTxWnIVaNMMnxb(45B3grzPWJ7TsxUjYazpbaY6UHBH(LEbKTmgiFx73HkkO5Ma4XpOsqZCajRULipMcK0OrAARUjs6Sis2Ttu2ZYl8iPvkzRFc0S(jIk1H1prAshdr5yvEkjiTsDyZ(iTsDW4URYR3SzIsPG8JClPvQdRhJ0s5bg2vfxMxEw13yOsmrsBeODYt9LQK0K5sejZLislTtKw)biVgcrAFN3jEvwbW74la6(ycGSUaapHNEEe5IbsgABhw91V4eIS(hG0gSdAsV6oXL8i4r8ISO(jVGkfKNVbAwYgipoaNxk5iN5Tv6dew13VelIYCer)MOoyK)lrwEElE5EulGbne908qZdK2kaaSIj(obc(bVtN6r8m1kG5IBzlYafl1gBCEu2a5X9yRZtAECh0KLF7eV38ayZebW6xJ78OEKmYbaplggokZd3jUCrcO3(lMl5gmd1drAy3upIRljGfyGnVwmz74EDYMECxZJKXzzbtGtEIr(D45wlAur8Qva3rHBHwXD3CBPX0aFejaYFv1bYgCauoOa7N8Wnqz5fRzXATlFpZblmUx2gLQ)HlLw8bOsoSbw7aNlTcp4CPvVcxX8eREPbNy6xQyQxybm7AXHDnaP64E8lBv0M6LBsjrw0QhVgq6P0R6OD2JtNfT807suwk5P3L08kTXnEmQvAwIaU5cll80TQ4tafFiVRer5Jv88ekGC5dK6lDdxLeqhMzaK8r3WpjbKz1airpauTaGg3bq7GaaYlga0nNaGSKP7LbfQ2sajDcGEZqLtBF3or8NbDGUXbOGAoisZrjsmsI0qprsqdiVxFej2mrAahOtkzFgQanVFlevYH91a0S9iejbsI0edIeBLinqdK3ebIe7NOs68ltG00WerL6169anVIarL0z7zbngyfuE9lDGOsRYXwHWdfQ8hagn6jAt6SaN5s0wfKwKG00wSrK2ITUBYxqFIY0XxEUP5RsesNppsyAppDjrEJJxIrsqL0Sury98DijO8j(1IuBYDuii4bUy3gIomqAjFIq5Wu5ybb(1sgXN03OeT3GDt1WDVf)WGhTdGmpbiTXymyqi)8islM29w8RcsmqDlE2smn7ufPjv9ej9uejToe5wlqUXbKfBbYIT3IXvexYE3pqEtXmGk1H9kNp1CKy)0DETzo4P2mhI0cqDXcdwObilkduwYrym3PllzgeZv)iIH5gLTEgbZ9tT2qKoVTOezHFGkLNV8Q8PLYZxEvstMsbKp2QejNCjQ0p8XuG080kGSIcGSIcG8ehG8emGY6G34aX1IihQrw(g0sPK0TfMoP0LlVKJwreBW0kLN3PnMUs559aL0Y2xpFN2inzGhrPebv8yA(GnWfZsEq(27jTCCJQGYCidU4tlTzFL7an)sejsR6tuPLYnLY00UQH1gtfO3INt(ymFB68rKxGCpABgjhnnFdlymmX9TDAtlOyo2HlzeLcqoVa52mqwcdilHbpfTSlqEoi9OuYgaz5a6rzwY2Dp(ulRbuPK9gQGNAJHjYkqbQuY2On(ulfduPnZG6GAbCZ1cuhFJYjYYga5XnGSSgqMJdK54azooqzjZVgMQo4hdtxhP8h8Bo5gCBEcvEm2VgPpdKmeL8h6CM488dTQr(vuaAER4iQKJu7hO5zrWtmVanqfA5cLqXuYhZxTkdmnL0L6OGAlllbujh5cLGwPLMlzcAEgnqNuEPms(jhg1wU4jqLCugDJx4zWd4hW6eLLc)ItzAP(dOcnRn(nMYpTWRIDAuLxHxX9AmPDsEl1H3QzgQDYEz81GsLsA8bm3UuBPXhGwYRIppjkhPXhWU8KNgxXv900meGk5OWDP7Tz6kT5c3LU36N63QbdfqL6WUUrALsUW7txz5tlLI30lggHk8(YSxEdxDTzR1z6kTkVznmWdv4l2PqslNJTtz2B8Har8GYSxE4RsALs22RZ0LTuUAPAlLvlPJkYwv6VUkK8ApbuPBKrTeslzU0gEvCzulbiURsXuwOKM)Mm24(Mgt6XQzMXgHl2i1(wwGF9l7GiR(PBeQQJCM37BImRPBEc6aTueeipqaKz)a52nqUD3LHESWAn((yJFHIM4xREfDmR2SI7Bv0(bs(gdKDbiVIXDbW9sGS7f8eYQK7RFCx4xJBlvmCERsnoIZgz1OGMvJwfrKj90uGcOsPKJeGMNAcK5Av5Xxc5nfTuOlsLN3vwIkLxk8aAzPKHjJUvChkuEP1PjkRxg(DnT0eQk(5giPL5LQEd)W4T1YaD8naffpMaq(M2LFgjef)QTaqByda2WCyfTLyaslRa)D9rDNiXFH)xE0LiT4jqEjtIKQaIuRMi1QjsJdejNoHxCQdd308WfJPwozajwup4EHM9rKRcGCvaKM4WtgV(vcb4xBJlrYYrIK4prYEhIY6mohIMMMuZNMTJB5nLL0KLJazxmjQuh(06tAL6WwirAAWkEhlbFi(utlG2Cha0ESaGo1094juuPXrIaa0COEmAlP04TEcaTjpaK8ez3aC(1wttu224nVp4VBgH2fH8QCazvcejnOaXJsbRa(9LoyIaO5Je5HgG8Op)Cf4cMrQfvf8GThfhQvZSJJAUP5yLdEQvMtKBarSJ1Plft2IxP(OKbss)9IloxaCqTca5BaSP3ResuwSX3cNi9(GyPWjSO4sFB(1(o688uJzGBnBNgx1diz(lq(ygaKxkLil6VDAOcVI5sJjrMBbKfU99pVxeG0JuXxNI6VWggxAWizZtbYLgqU7TdNxQ8UDY1aY5f(u5sgiPtQhCg3cea5rvGC5bK5jaz9bWlm3caQKJC0h0k5WhpSEf3X7H1MYAld)SGMpAgazZ3ikBFmYRf9iSIuMx6CTA9HZ1CKINwJyWOlhRfk3ejEX4nBPBUbk8kYB2hqEWfOStMXwZ4kOhIa8DShsAXflxaT)CaODnoUb5knoOVYBnUL3HVEY4Dql1EcKNIcp8mxfiZvJ4QxmVp(clZScGzVa52kq6uc2lcwkcKu8Ukh3Jy9iUrhcOT2lIQZ(rEsv(bsUxf)cOgZ5XYnwIfip2ufFt40tT5D9WApESjwZrn6cBTk2AzqRQD8whnssL8E5QsgmFZ)QAtLZ0bNkScIwAGiXeaYhD)kECtzNaan3TIE)X(xv82VdGp57aO1NQOAu9iFSfR64nFf(alMbuNk2d8fwBMzv8z)paEB0H6vFecRITIkEMFVbaigxv81RKMuXBvEKMiY8haVz6aOLfaWnAECPJklUOXcK5Ybd1kU16rvaG5rBXW4HOXnZjqXb4o4LXDzkQ5mM4Y4QOhgIJ)c9TmIFom5WTpuSbfmtH)A)oQ6YlFmfQbY70rfCDvMyaKV0nejHFIYCKHBisd92dE5(h)g9p(c9p(v7F8R0)4l2)Gx(GN8bR2B5OPtgn5WxB(I6XJb4OPpOE(8r7x3)OpC(GdwYNn7xSNHxE80V8Y)TvdMSC0YhTUXVU)r3D40zZuIwy4zs0U3DYOz1ZFT7SG)YS94pVEY(tNZ8D0v)O6dgSA8ss)R(RdMxpC6Qf8jRBCns7434G1nA8Rw34Tw343GFE71nUm(5Dw34k4NRUUXVf)Gu(U8NJVWlsIF1xKe)kVij(INnXVj7mOr7FpDRMjgKFR)7rd2f8)pDWdp6(dE4NnF0E1pz3r7)z1Z3REYYp7cTVr3T)69gmzV6X3PE20fl7JHMt9N)5HZRXOW49NTbY)1FqWK5aBRolA(uLY)YK9rXTAz)J2F18bC4)Nn71hD4KPZR)Jt)YpkP913RUE2FYJ0B0(jO8(4hoBek)nAVUX1N9fScGPxxBX9hmF5GhC4URE0nBFJQTBrI3F0KRVj(D)DNxFiQIfdgxJ0eplPnC0ILqeyVbJBLKqrDVAwynBEekIGbm7FXcJ)xNoNxTbIP0zu)n)DrAV5PRA0pRB1PD72T6Ct2u4F389IEWIBIFwSCWE3R1oTV2jCSMNTr9SA9NthT5xb(59hmo6bRBS5Coy9HdMn7Fo6GdxE9sv2Pf)76O7DgMWls99(QtNDo0pp3()pANUZET2g8P2TA3e)7tMX2)DQxuVCxjIC0kl(CL27HPJqO9T)KzxkgaI(6NwVC409N9FC3cC4Z0oAFJ2DqHFJoTuVwd6UZEkHIZt(b(YuKFory5NScQjfZr3D509U3SRgcXKxeckf5HfC(v989h8OMnFCiLo9GrlN9v)WD5Spp6GXy8oLyB1D7yUYpax4C7XXW9Z7G93tW(90S09AIE7OjU3Yj1xgJMVZNGj3p8L(hpdX0NX453TZHoZOjqDW0vlJrgnPceAXzWF)U(ZRkHwN30SFIe7LIJ)VQX2SzZVfkJPKAQLEwOgrtFPiBzMxrGfd9DA1PzZN6CE3PRWkllE3Jgidbw0)27oyY96p71XQiF5h41IIj2d1kxx9nFYU1WiGG2dFPlE(YjNTML23NNPiBfddyDIteB6DkPMT0IlO4EUwi57Od1Rc189Jj0)qklFFWMA3(htBPeBW)aBqaV5A)7hxpzWUJRV9Qh1)jcExS4BFOFdRLU8ryz0CiJ)X6gF8bxzWWH3EW4LlgoN))Va)56g)(H35WvJgV)WBF)bJgpC2L4s4FWblRNRLG3)kB2(Binm(nE3PqL8WN(GfFeKgMp9rF(GXRQpkvO8npyXNg6xdYRB85ZEDs5HNoXqv(Slfupvsd97Vl7vp4BzZ)2do8eRbMDjrAsr2BJ2F99HLlNkj)s3v)dNjLRB8HB0E2LszqU27Dh93R3O9JJ1Hf(N))(d"
    
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
        
        -- Add import button to the same frame
        local importButton = AceGUI:Create("Button")
        importButton:SetText("Import")
        importButton:SetWidth(150)
        importButton:SetCallback("OnClick", function()
            local success = ImportTSMGroup(editbox:GetText())
            if success then
                print("Group successfully imported!")
                frame:Hide()  -- Close the dialog after successful import
            end
        end)
        frame:AddChild(importButton)
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
            if prevRowData then
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
 