local addonName, addon = ...
local AceAddon = LibStub("AceAddon-3.0")
local FLIPR = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceHook-3.0", "AceConsole-3.0")
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

function FLIPR:OnInitialize()
    -- Initialize settings with defaults
    FliprSettings = FliprSettings or {
        version = 1,
        -- Inventory control settings
        highSaleRate = 0.4,      
        mediumSaleRate = 0.2,    
        highInventory = 100,     
        mediumInventory = 10,    
        lowInventory = 5,
        -- UI settings
        showConfirm = true,
        enabledGroups = {},      
        expandedGroups = {}      
    }
    
    -- Initialize groups database separately
    FliprDB = FliprDB or {
        groups = {},
        version = 1
    }
    
    -- Set references
    self.db = FliprSettings      -- For addon settings
    self.groupDB = FliprDB       -- For groups data
    
    -- Create options panel
    self:CreateOptionsPanel()
    
    -- Initialize database
    self:InitializeDB()
    
    -- Register slash commands
    self:RegisterChatCommand("flipr", "HandleSlashCommand")
    
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

function FLIPR:HandleSlashCommand(input)
    -- Split input into command and value
    local command, value = strsplit(" ", input)
    
    if not command or command == "" then
        -- Open options panel if no command
        Settings.OpenToCategory("FLIPR")
        return
    end
    
    -- Convert value to number if provided
    local numValue = tonumber(value)
    
    -- Handle different commands
    if command == "hsr" or command == "highsale" then
        if not numValue then
            self:Print("Usage: /flipr hsr <value> (0-1)")
            return
        end
        numValue = math.min(math.max(math.floor(numValue * 1000) / 1000, 0), 1)
        self.db.highSaleRate = numValue
        self:Print("High sale rate set to:", numValue)
        
    elseif command == "msr" or command == "medsale" then
        if not numValue then
            self:Print("Usage: /flipr msr <value> (0-1)")
            return
        end
        numValue = math.min(math.max(math.floor(numValue * 1000) / 1000, 0), 1)
        self.db.mediumSaleRate = numValue
        self:Print("Medium sale rate set to:", numValue)
        
    elseif command == "hi" or command == "highinv" then
        if not numValue then
            self:Print("Usage: /flipr hi <value> (1-200)")
            return
        end
        numValue = math.min(math.max(math.floor(numValue), 1), 200)
        self.db.highInventory = numValue
        self:Print("High inventory limit set to:", numValue)
        
    elseif command == "mi" or command == "medinv" then
        if not numValue then
            self:Print("Usage: /flipr mi <value> (1-50)")
            return
        end
        numValue = math.min(math.max(math.floor(numValue), 1), 50)
        self.db.mediumInventory = numValue
        self:Print("Medium inventory limit set to:", numValue)
        
    elseif command == "li" or command == "lowinv" then
        if not numValue then
            self:Print("Usage: /flipr li <value> (1-20)")
            return
        end
        numValue = math.min(math.max(math.floor(numValue), 1), 20)
        self.db.lowInventory = numValue
        self:Print("Low inventory limit set to:", numValue)
        
    else
        -- Print usage
        self:Print("FLIPR Commands:")
        self:Print("  /flipr - Open settings")
        self:Print("  /flipr hsr <0-1> - Set high sale rate")
        self:Print("  /flipr msr <0-1> - Set medium sale rate")
        self:Print("  /flipr hi <1-200> - Set high inventory limit")
        self:Print("  /flipr mi <1-50> - Set medium inventory limit")
        self:Print("  /flipr li <1-20> - Set low inventory limit")
    end
end 