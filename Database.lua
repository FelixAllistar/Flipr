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
        if groupData.items then
            -- If no groups are enabled yet, load all items
            if not next(self.db.enabledGroups) then
                print("No groups enabled, loading all items from:", tableName)
                for itemId, itemData in pairs(groupData.items) do
                    self.itemDB[itemId] = itemData
                end
            else
                for groupPath, enabled in pairs(self.db.enabledGroups) do
                    if enabled then
                        print("Loading enabled group:", groupPath)
                        local items = self:LoadGroupData(groupPath)
                        for itemId, itemData in pairs(items) do
                            self.itemDB[itemId] = itemData
                        end
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

function FLIPR:LoadGroupData(groupPath)
    local items = {}
    local addedItems = {} -- Track which items we've already added
    
    -- Find the table that contains this group
    for tableName, groupData in pairs(self.availableGroups) do
        if groupData.items then
            -- If this is a master group (matches the table's name), include all items
            if groupPath == groupData.name then
                print("Loading all items for master group:", groupPath)
                return groupData.items
            end
            
            -- Otherwise, look for specific subgroup items
            local count = 0
            for itemId, itemData in pairs(groupData.items) do
                if not addedItems[itemId] and itemData.subGroup:find(groupPath, 1, true) then
                    items[itemId] = itemData
                    addedItems[itemId] = true
                    count = count + 1
                end
            end
            
            if count > 0 then
                print(string.format("Found %d unique items in subgroup: %s", count, groupPath))
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
        end
    end
    print("No items found in group:", groupPath)
    return {}
end

function FLIPR:GetMasterGroups()
    local masterGroups = {}
    for tableName, groupData in pairs(self.availableGroups) do
        print("Processing table for master groups:", tableName)
        if groupData.name then
            print("Found master group:", groupData.name)
            -- Store both the table name and the group data
            masterGroups[tableName] = {
                name = groupData.name,
                groups = groupData.groups or {}
            }
        end
    end
    return masterGroups
end

function FLIPR:GetSubGroups(masterGroupName)
    local subGroups = {}
    for tableName, groupData in pairs(self.availableGroups) do
        if groupData.name == masterGroupName and groupData.groups then
            return groupData.groups
        end
    end
    return subGroups
end

function FLIPR:UpdateScanItems()
    self.itemIDs = {}
    local addedItems = {} -- Track which items we've already added
    
    for groupPath, enabled in pairs(self.db.enabledGroups) do
        if enabled then
            local groupData = self:LoadGroupData(groupPath)
            local count = 0
            for itemID, itemData in pairs(groupData) do
                -- Only add each item once
                if self.itemDB[itemID] and not addedItems[itemID] then
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
    local groupData = self.availableGroups[tableName]
    if groupData then
        if groupData.groups and groupData.groups[groupPath] then
            -- This is a subgroup path
            local subGroupPath = groupData.groups[groupPath]
            print("Enabling subgroup:", subGroupPath)
            self.db.enabledGroups[subGroupPath] = state
        else
            -- This is a master group, enable/disable all subgroups
            print("Enabling master group:", groupPath)
            -- Enable the master group itself
            self.db.enabledGroups[groupPath] = state
            -- And all its subgroups
            for _, subGroupPath in pairs(groupData.groups or {}) do
                self.db.enabledGroups[subGroupPath] = state
            end
        end
        self:UpdateScanItems()
    end
end 