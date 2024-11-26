local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:InitializeDB()
    print("Initializing database...")
    self.itemDB = {}
    self.availableGroups = self:GetAvailableGroups()
    
    -- Load items from enabled groups
    print("Loading items from enabled groups...")
    for tableName, groupData in pairs(self.availableGroups) do
        print("Processing table:", tableName)
        -- If no groups are enabled yet, load all items
        if not next(self.db.enabledGroups) then
            print("No groups enabled, loading all items from:", tableName)
            self:LoadAllItems(groupData)
        else
            for groupPath, enabled in pairs(self.db.enabledGroups) do
                if enabled then
                    print("Loading enabled group:", groupPath)
                    local items = self:LoadGroupData(groupData, groupPath)
                    for itemId, itemData in pairs(items) do
                        self.itemDB[itemId] = itemData
                    end
                end
            end
        end
    end
    
    local totalItems = 0
    for itemId, itemData in pairs(self.itemDB) do
        totalItems = totalItems + 1
        if totalItems <= 10 then
            print(string.format("Loaded item: %d - %s", itemId, itemData.name))
        elseif totalItems == 11 then
            print("... and more items")
        end
    end
    print("Total items loaded into database:", totalItems)
end

function FLIPR:LoadAllItems(groupData)
    -- Recursively load all items from a group and its subgroups
    if groupData.items then
        for itemId, itemData in pairs(groupData.items) do
            self.itemDB[itemId] = itemData
        end
    end
    
    -- Process subgroups
    for key, value in pairs(groupData) do
        if type(value) == "table" and key ~= "items" and key ~= "name" then
            self:LoadAllItems(value)
        end
    end
end

function FLIPR:LoadGroupData(groupData, groupPath)
    local items = {}
    local addedItems = {} -- Track which items we've already added
    
    -- If this is a root group, check if it matches the name
    if groupData.name == groupPath then
        -- Load all items from this level and below
        self:LoadAllItemsFromLevel(groupData, items, addedItems)
        return items
    end
    
    -- Function to recursively search for matching groups
    local function searchGroups(currentTable, remainingPath)
        -- Check if current table's name matches what we want
        if currentTable.name == remainingPath then
            self:LoadAllItemsFromLevel(currentTable, items, addedItems)
            return true
        end
        
        -- Check all subtables
        for key, value in pairs(currentTable) do
            if type(value) == "table" and key ~= "items" then
                if value.name and value.name == remainingPath then
                    self:LoadAllItemsFromLevel(value, items, addedItems)
                    return true
                end
                if searchGroups(value, remainingPath) then
                    return true
                end
            end
        end
        return false
    end
    
    -- Try to find the group by its name
    if not searchGroups(groupData, groupPath) then
        print("Path not found:", groupPath)
    end
    
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    print(string.format("Found %d unique items in group: %s", count, groupPath))
    
    -- Print first few items for debugging
    local printed = 0
    for itemId, itemData in pairs(items) do
        if printed < 3 then
            print(string.format("  Sample item: %d - %s", itemId, itemData.name))
            printed = printed + 1
        else
            break
        end
    end
    
    return items
end

function FLIPR:LoadAllItemsFromLevel(groupData, items, addedItems)
    -- Load items from this level
    if groupData.items then
        for itemId, itemData in pairs(groupData.items) do
            if not addedItems[itemId] then
                items[itemId] = itemData
                addedItems[itemId] = true
            end
        end
    end
    
    -- Recursively load items from subgroups
    for key, value in pairs(groupData) do
        if type(value) == "table" and key ~= "items" and key ~= "name" then
            self:LoadAllItemsFromLevel(value, items, addedItems)
        end
    end
end

function FLIPR:GetMasterGroups()
    local masterGroups = {}
    for tableName, groupData in pairs(self.availableGroups) do
        print("Processing table for master groups:", tableName)
        if groupData.name then
            print("Found master group:", groupData.name)
            masterGroups[tableName] = groupData
        end
    end
    return masterGroups
end

function FLIPR:UpdateScanItems()
    self.itemIDs = {}
    local addedItems = {} -- Track which items we've already added
    
    for groupPath, enabled in pairs(self.db.enabledGroups) do
        if enabled then
            for tableName, groupData in pairs(self.availableGroups) do
                local items = self:LoadGroupData(groupData, groupPath)
                local count = 0
                for itemID, itemData in pairs(items) do
                    -- Only add each item once
                    if not addedItems[itemID] then
                        count = count + 1
                        table.insert(self.itemIDs, itemID)
                        addedItems[itemID] = true
                        print(string.format("Adding item to scan list: %d - %s from group %s", 
                            itemID, itemData.name, groupPath))
                    end
                end
                print("Added", count, "new items from group:", groupPath)
            end
        end
    end
    
    -- Sort itemIDs for consistent scanning order
    table.sort(self.itemIDs)
    
    -- Print first few items for debugging
    print("First 5 items in scan list:")
    for i = 1, math.min(5, #self.itemIDs) do
        local itemID = self.itemIDs[i]
        local itemData = self.itemDB[itemID]
        if itemData then
            print(string.format("  %d: %d - %s", i, itemID, itemData.name))
        end
    end
    
    print("Total unique items in scan list:", #self.itemIDs)
    self.currentScanIndex = 1
    
    if self.scrollChild then
        self.scrollChild:SetHeight(1)
        for _, child in pairs({self.scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
    end
end

-- Helper function to toggle a group and all its children
function FLIPR:ToggleGroupState(tableName, groupPath, state)
    print("ToggleGroupState called with:", tableName, groupPath, state)
    
    if not tableName then
        print("No tableName provided for group:", groupPath)
        return
    end
    
    local groupData = self.availableGroups[tableName]
    if not groupData then
        print("No group data found for table:", tableName)
        return
    end
    
    -- Enable/disable the specified group
    self.db.enabledGroups[groupPath] = state
    
    -- Print enabled groups for debugging
    print("Currently enabled groups:")
    for group, enabled in pairs(self.db.enabledGroups) do
        if enabled then
            print("  -", group)
        end
    end
    
    self:UpdateScanItems()
end 