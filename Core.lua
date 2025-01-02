local addonName, addon = ...
local AceAddon = LibStub("AceAddon-3.0")
local FLIPR = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceHook-3.0", "AceConsole-3.0")
addon.FLIPR = FLIPR

-- Get the version from TOC using the correct API
local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "v0.070"
addon.version = version  -- Make version accessible to other files

local defaultSettings = {
    showConfirm = true,
    enabledGroups = {},  -- Will be populated with TSM groups
    expandedGroups = {}  -- Track which groups are expanded in the UI
}

-- Helper function to get TSM group path for an item
function FLIPR:GetTSMGroupPath(itemID)
    if not TradeSkillMasterDB then return nil end
    local itemString = "i:" .. itemID
    return TradeSkillMasterDB["p@Default@userData@items"][itemString]
end

-- Helper function to get TSM operations for a group
function FLIPR:GetTSMGroupOperations(groupPath)
    if not TradeSkillMasterDB then return {} end
    local operationsTable = TradeSkillMasterDB["p@Default@userData@groups"]
    if not operationsTable or not operationsTable[groupPath] then return {} end
    
    local ops = {}
    for moduleName, moduleData in pairs(operationsTable[groupPath]) do
        if type(moduleData) == "table" then
            ops[moduleName] = {
                override = moduleData.override,
                operations = moduleData
            }
        end
    end
    return ops
end

-- Helper function to get operation details
function FLIPR:GetTSMOperationDetails(moduleName, operationName)
    if not TradeSkillMasterDB then return nil end
    local operationsData = TradeSkillMasterDB["p@Default@userData@operations"]
    if not operationsData or not operationsData[moduleName] or not operationsData[moduleName][operationName] then
        return nil
    end
    return operationsData[moduleName][operationName]
end

-- Get all TSM shopping operations for an item
function FLIPR:GetTSMShoppingOperations(itemID)
    local groupPath = self:GetTSMGroupPath(itemID)
    if not groupPath then return nil end
    
    local groupOps = self:GetTSMGroupOperations(groupPath)
    if not groupOps or not groupOps.Shopping then return nil end
    
    local operations = {}
    for _, opName in ipairs(groupOps.Shopping.operations) do
        local details = self:GetTSMOperationDetails("Shopping", opName)
        if details then
            table.insert(operations, {
                name = opName,
                maxPrice = details.maxPrice,
                restockQuantity = details.restockQuantity
            })
        end
    end
    
    return operations
end

-- Get all unique TSM groups
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

-- Get all items in a TSM group
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

-- Initialize addon
function FLIPR:OnInitialize()
    -- Initialize saved variables
    self.db = LibStub("AceDB-3.0"):New("FliprDB", {
        profile = defaultSettings
    })
    
    -- Initialize settings
    self.settings = LibStub("AceDB-3.0"):New("FliprSettings", {
        profile = {}
    })
end

function FLIPR:OnEnable()
    -- Register AH events
    self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnAuctionHouseShow")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", "OnAuctionHouseClosed")
    
    -- Initialize scanner state
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
end 