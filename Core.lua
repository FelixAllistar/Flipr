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
    -- Merge all our database files into one
    if FLIPR_ItemDatabase_1VeryHigh10000plus then
        print("Loading Very High database...")
        for k, v in pairs(FLIPR_ItemDatabase_1VeryHigh10000plus) do
            self.itemDB[k] = v
        end
        print("Database loaded with", #self.itemDB, "items")
    else
        print("Warning: Very High database not found!")
    end
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