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

function FLIPR:GetTSMGroups()
    print("=== GetAvailableGroups START ===")
    -- Check for TSM's database
    if not TradeSkillMasterDB then
        print("TSM database not found")
        return
    end

    -- Get the items, operations tables, and operations data
    local itemsTable = TradeSkillMasterDB["p@Default@userData@items"]
    local operationsTable = TradeSkillMasterDB["p@Default@userData@groups"]
    local operationsData = TradeSkillMasterDB["p@Default@userData@operations"]
    if not itemsTable then
        print("No TSM items/groups found")
        return
    end

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

    -- Function to get operation details
    local function getOperationDetails(moduleName, operationName)
        if not operationsData or not operationsData[moduleName] or not operationsData[moduleName][operationName] then
            return nil
        end
        return operationsData[moduleName][operationName]
    end

    -- Function to get operations for a group
    local function getGroupOperations(groupPath)
        if not operationsTable or not operationsTable[groupPath] then
            return {}
        end
        
        local ops = {}
        for moduleName, moduleData in pairs(operationsTable[groupPath]) do
            if type(moduleData) == "table" then
                ops[moduleName] = {
                    override = moduleData.override,
                    operations = {}
                }
                -- Add each operation with its details
                for i, opName in ipairs(moduleData) do
                    local details = getOperationDetails(moduleName, opName)
                    ops[moduleName].operations[opName] = details
                end
            end
        end
        return ops
    end

    -- Function to print group hierarchy
    local function printGroupHierarchy(basePath, level)
        level = level or 0
        local indent = string.rep("  ", level)
        
        if level == 0 then
            print("Group:", basePath)
            -- Print operations for root group
            local ops = getGroupOperations(basePath)
            for module, moduleData in pairs(ops) do
                if moduleData.override then
                    print(indent .. "  " .. module .. " Operations (Override):")
                else
                    print(indent .. "  " .. module .. " Operations:")
                end
                for opName, opDetails in pairs(moduleData.operations) do
                    print(indent .. "    - " .. opName)
                    if opDetails then
                        -- Print key operation settings
                        if opDetails.maxPrice then
                            print(indent .. "      maxPrice: " .. opDetails.maxPrice)
                        end
                        if opDetails.minPrice then
                            print(indent .. "      minPrice: " .. opDetails.minPrice)
                        end
                        if opDetails.restockQuantity then
                            print(indent .. "      restockQuantity: " .. opDetails.restockQuantity)
                        end
                    end
                end
            end
        end
        
        -- Find all direct children of this path
        local children = {}
        for path in pairs(groups) do
            -- Check if this is a direct child (one level deeper)
            local parent = basePath == "" and "^[^`]+" or "^" .. basePath .. "`[^`]+"
            if path:match(parent) then
                local childName = path:match(basePath == "" and "^([^`]+)" or basePath .. "`([^`]+)")
                if childName then
                    children[childName] = path
                end
            end
        end
        
        -- Sort and print children
        local sortedChildren = {}
        for childName in pairs(children) do
            table.insert(sortedChildren, childName)
        end
        table.sort(sortedChildren)
        
        for _, childName in ipairs(sortedChildren) do
            local fullPath = children[childName]
            print(indent .. "- Child:", childName)
            -- Print operations for this child
            local ops = getGroupOperations(fullPath)
            for module, moduleData in pairs(ops) do
                if moduleData.override then
                    print(indent .. "    " .. module .. " Operations (Override):")
                else
                    print(indent .. "    " .. module .. " Operations:")
                end
                for opName, opDetails in pairs(moduleData.operations) do
                    print(indent .. "      - " .. opName)
                    if opDetails then
                        -- Print key operation settings
                        if opDetails.maxPrice then
                            print(indent .. "        maxPrice: " .. opDetails.maxPrice)
                        end
                        if opDetails.minPrice then
                            print(indent .. "        minPrice: " .. opDetails.minPrice)
                        end
                        if opDetails.restockQuantity then
                            print(indent .. "        restockQuantity: " .. opDetails.restockQuantity)
                        end
                    end
                end
            end
            -- Recursively print this child's children
            printGroupHierarchy(fullPath, level + 1)
        end
    end

    -- Print the groups in a tree structure
    print("Found groups in TSM:")
    -- First find all root groups
    local rootGroups = {}
    for path in pairs(groups) do
        if not string.find(path, "`") then
            table.insert(rootGroups, path)
        end
    end
    
    -- Sort and print root groups
    table.sort(rootGroups)
    for _, rootGroup in ipairs(rootGroups) do
        printGroupHierarchy(rootGroup)
    end

    print("=== GetAvailableGroups END ===")
end

-- Register our event handler
FLIPR:RegisterEvent("PLAYER_LOGIN", function()
    FLIPR:GetTSMGroups()
end)

function FLIPR:OnInitialize()
    -- Initialize groups database
    FliprDB = FliprDB or {
        groups = {},
        version = 1,
        -- UI settings
        showConfirm = true,
        enabledGroups = {},      
        expandedGroups = {}      
    }
    
    -- Initialize profitability settings separately
    FliprSettings = FliprSettings or {
        version = 1,
        -- Inventory control settings
        highSaleRate = 0.4,      
        mediumSaleRate = 0.2,    
        highInventory = 100,     
        mediumInventory = 10,    
        lowInventory = 5,
        -- Profitability settings
        minProfit = 1000,         -- 10 silver minimum profit
        highVolumeROI = 15,       -- 15% for fast movers
        mediumVolumeROI = 25,     -- 25% for regular items
        lowVolumeROI = 40,        -- 40% for slow movers
        veryLowVolumeROI = 70,    -- 70% for very slow movers
        unstableMarketMultiplier = 1.3,  -- 30% more profit needed in unstable markets
        historicalLowMultiplier = 0.8,   -- 20% less ROI needed if prices are historically low
    }
    
    -- Set references
    self.db = FliprSettings      -- For profitability settings
    self.groupDB = FliprDB       -- For groups data and UI settings
    
    -- Initialize database
    self:InitializeDB()
    
    -- Initialize available groups
    self.availableGroups = self:GetAvailableGroups()
    
    -- Check TSM groups
    self:GetTSMGroups()
    
    -- Create options panel (moved to after database initialization)
    self:CreateOptionsPanel()
    
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