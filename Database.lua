local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:LoadGroupData(groupName)
    local tableName = self:GetTableNameFromGroup(groupName)
    print("Looking for table:", tableName)
    local data = _G[tableName]
    print("Found data:", data and "yes" or "no")
    return data or {}
end

function FLIPR:UpdateScanItems()
    self.itemIDs = {}
    print("Checking enabled groups:")
    
    for groupName, enabled in pairs(self.db.enabledGroups) do
        print(groupName, enabled)
        if enabled then
            local groupData = self:LoadGroupData(groupName)
            print("Group data size:", groupName, next(groupData) and "has data" or "empty")
            for itemID, _ in pairs(groupData) do
                table.insert(self.itemIDs, itemID)
            end
        end
    end
    
    print("Total items found:", #self.itemIDs)
    self.currentScanIndex = 1
    
    if self.scrollChild then
        self.scrollChild:SetHeight(1)
        for _, child in pairs({self.scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
    end
end

function FLIPR:GetTableNameFromGroup(groupName)
    local tableName = "FLIPR_ItemDatabase_" .. groupName:gsub("[%.]", ""):gsub(" ", ""):gsub("[%+]", "plus")
    print("Generated table name:", tableName)
    return tableName
end 