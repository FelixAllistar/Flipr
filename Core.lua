local addonName, addon = ...
local AceAddon = LibStub("AceAddon-3.0")
local FLIPR = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceHook-3.0")
addon.FLIPR = FLIPR

-- Get the version from TOC using the correct API
local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "v0.070"
addon.version = version  -- Make version accessible to other files

-- Default scan items
local defaultItems = {
    "Light Leather",
    "Medium Leather"
}

local defaultSettings = {
    items = defaultItems,
    showConfirm = true,
    enabledGroups = {},  -- Will be populated dynamically
    expandedGroups = {}  -- Track which groups are expanded in the UI
}

function FLIPR:GetAvailableGroups()
    local groups = {}
    print("Scanning for available groups...")
    -- Look for FLIPR_ tables in _G
    for name, value in pairs(_G) do
        if type(value) == "table" and name:match("^FLIPR_") then
            print("Found group table:", name)
            -- Store reference to the table
            groups[name] = value
        end
    end
    print("Total group tables found:", #groups)
    return groups
end

function FLIPR:GetItemsFromGroup(groupTable, path)
    local items = {}
    local currentTable = groupTable
    
    -- If no path specified, return all items recursively
    if not path then
        if currentTable.items then
            for itemId, itemData in pairs(currentTable.items) do
                items[itemId] = itemData
            end
        end
        -- Recursively get items from subgroups
        for key, value in pairs(currentTable) do
            if type(value) == "table" and key ~= "items" and key ~= "name" then
                local subItems = self:GetItemsFromGroup(value)
                for itemId, itemData in pairs(subItems) do
                    items[itemId] = itemData
                end
            end
        end
        return items
    end
    
    -- Navigate through the path
    local pathParts = {strsplit("/", path)}
    for _, part in ipairs(pathParts) do
        if currentTable[part] then
            currentTable = currentTable[part]
        else
            return {}  -- Path not found
        end
    end
    
    -- Return items from this level and below
    return self:GetItemsFromGroup(currentTable)
end

function FLIPR:InitializeDB()
    print("Initializing database...")
    self.itemDB = {}
    self.availableGroups = self:GetAvailableGroups()
    
    -- Load items from enabled groups
    print("Loading items from enabled groups...")
    for tableName, groupData in pairs(self.availableGroups) do
        print("Processing table:", tableName)
        for groupPath, enabled in pairs(self.db.enabledGroups) do
            if enabled then
                print("Loading enabled group:", groupPath)
                local items = self:GetItemsFromGroup(groupData, groupPath)
                for itemId, itemData in pairs(items) do
                    self.itemDB[itemId] = itemData
                end
            end
        end
    end
    
    local totalItems = 0
    for _ in pairs(self.itemDB) do
        totalItems = totalItems + 1
    end
    print("Total items loaded into database:", totalItems)
end

function FLIPR:OnInitialize()
    -- Create settings if they don't exist
    if not FLIPRSettings then
        FLIPRSettings = defaultSettings
    else
        -- Ensure all default settings exist
        for key, value in pairs(defaultSettings) do
            if FLIPRSettings[key] == nil then
                FLIPRSettings[key] = value
            end
        end
    end
    
    self.db = FLIPRSettings
    
    -- Initialize database
    self:InitializeDB()
    
    print("FLIPR Settings and Database loaded")
end

function FLIPR:OnEnable()
    -- Initialize UI events
    self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnAuctionHouseShow")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", "OnAuctionHouseClosed")
    
    -- Initialize scanner
    self.selectedRow = nil
    self.selectedItem = nil
    self.isScanning = false
    self.isPaused = false
    self.scanButton = nil
    self.failedItems = {}
    self.maxRetries = 3
    self.retryDelay = 2
    
    -- Initialize scan timer
    self.scanTimer = 0
    self.scanStartTime = 0
    
    -- Debug print
    print("FLIPR enabled - All systems initialized")
end 