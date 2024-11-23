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
    enabledGroups = {
        ["1.Very High 10000+"] = false,
        ["2.High 1000+"] = false,
        ["3.Medium 100+"] = false,
        ["4.Low 10+"] = false,
        ["5.Very low 1+"] = false
    }
}

function FLIPR:InitializeDB()
    self.itemDB = {}
    
    -- Load all database files
    local databases = {
        ["Very High"] = FLIPR_ItemDatabase_1VeryHigh10000plus,
        ["High"] = FLIPR_ItemDatabase_2High1000plus,
        ["Medium"] = FLIPR_ItemDatabase_3Medium100plus,
        ["Low"] = FLIPR_ItemDatabase_4Low10plus,
        ["Very Low"] = FLIPR_ItemDatabase_5VeryLow1plus
    }
    
    local totalItems = 0
    for dbName, db in pairs(databases) do
        if db then
            print("Loading " .. dbName .. " database...")
            for k, v in pairs(db) do
                self.itemDB[k] = v
                totalItems = totalItems + 1
            end
            print(dbName .. " database loaded")
        else
            print("Warning: " .. dbName .. " database not found!")
        end
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
    
    -- Initialize database immediately
    self:InitializeDB()
    
    print("FLIPR Settings and Database loaded")
end

function FLIPR:OnEnable()
    -- Initialize UI events
    self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnAuctionHouseShow")
    
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