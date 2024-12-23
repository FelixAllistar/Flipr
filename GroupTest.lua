local LibDeflate = LibStub("LibDeflate")
local LibSerialize = LibStub("LibSerialize")
local AceSerializer = LibStub("AceSerializer-3.0")

local MAGIC_STR = "TSM_EXPORT"
local VERSION = 1

-- Helper function to get TSM market data
local function GetTSMPriceData(itemId)
    -- Try TSM4 API first
    if TSMAPI_FOUR then
        local dbMarket = TSMAPI_FOUR.CustomPrice.GetValue("DBMarket", "i:"..itemId)
        local dbSaleRate = TSMAPI_FOUR.CustomPrice.GetValue("DBSaleRate", "i:"..itemId)
        return dbMarket, dbSaleRate
    end
    
    -- Try newer TSM API
    if TSM_API then
        local dbMarket = TSM_API.GetCustomPriceValue("DBMarket", "i:"..itemId)
        local dbSaleRate = TSM_API.GetCustomPriceValue("DBSaleRate", "i:"..itemId)
        return dbMarket, dbSaleRate
    end
    
    return nil, nil
end

-- Helper function to process item info asynchronously
local function ProcessItemInfo(itemId, callback)
    -- Convert itemId to number
    itemId = tonumber(itemId)
    if not itemId then return end
    
    local item = Item:CreateFromItemID(itemId)
    if not item then return end

    item:ContinueOnItemLoad(function()
        local itemName = item:GetItemName()
        local itemLink = item:GetItemLink()
        local marketValue, saleRate = GetTSMPriceData(itemId)
        
        callback({
            id = itemId,
            name = itemName,
            link = itemLink,
            marketValue = marketValue or 0,
            saleRate = saleRate or 0
        })
    end)
end

local function DecodeNewImport(str)
    -- Step 1: Base64 decode
    local decoded = LibDeflate:DecodeForPrint(str)
    if not decoded then
        return false
    end

    -- Step 2: Decompress
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return false
    end

    -- Step 3: Deserialize using LibSerialize (new format)
    local success, magicStr, version, groupName, items, groups, groupOperations, operations, customSources = LibSerialize:Deserialize(decompressed)
    if not success then
        return false
    end

    -- Validate magic string and version
    if magicStr ~= MAGIC_STR then
        return false
    end
    if version ~= VERSION then
        return false
    end

    return true, {
        groupName = groupName,
        items = items,
        groups = groups,
        groupOperations = groupOperations,
        operations = operations,
        customSources = customSources
    }
end

local function DecodeOldImport(str)
    if strsub(str, 1, 1) ~= "^" then
        return false
    end

    -- Deserialize using AceSerializer (old format)
    local success, data = AceSerializer:Deserialize(str)
    if not success then
        return false
    end

    return true, data
end

local function DecodeOldGroupOrItemList(str)
    -- Handle simple item list format
    if strmatch(str, "^[ip0-9%-:;]+$") then
        str = gsub(str, ";", ",")
    end
    if strmatch(str, "^[0-9, ]+$") then
        str = gsub(str, "[0-9]+", "i:%1")
    end

    local items = {}
    local groups = {}
    local relativePath = "" -- Root path

    for part in string.gmatch(str, "[^,]+") do
        part = strtrim(part)
        local groupPath = strmatch(part, "^group:(.+)$")
        local itemString = strmatch(part, "^[ip]?:?[0-9%-:]+$")

        if groupPath then
            groupPath = gsub(groupPath, "``", ",")
            relativePath = groupPath
            groups[groupPath] = true
        elseif itemString then
            items[itemString] = relativePath
            groups[relativePath] = true
        end
    end

    return true, {
        items = items,
        groups = groups
    }
end

-- Add this conversion function
local function ConvertFliprToTSM(fliprData)
    local tsmData = {
        groupName = nil,
        items = {},
        groups = {},
        groupOperations = {},
        operations = {},
        customSources = {}
    }
    
    -- Helper function to process groups recursively
    local function processGroup(groupData, parentPath)
        local currentPath = parentPath and (parentPath .. "/" .. groupData.name) or groupData.name
        
        -- Set root group name if not set
        if not tsmData.groupName then
            tsmData.groupName = groupData.name
        end
        
        -- Add group to groups table
        tsmData.groups[currentPath] = true
        
        -- Process items in this group
        if groupData.items then
            for itemId, itemInfo in pairs(groupData.items) do
                tsmData.items["i:" .. itemId] = currentPath
            end
        end
        
        -- Process subgroups
        if groupData.children then
            for _, childGroup in pairs(groupData.children) do
                processGroup(childGroup, currentPath)
            end
        end
    end
    
    -- Start processing from root level
    for groupName, groupData in pairs(fliprData) do
        processGroup(groupData)
    end
    
    return tsmData
end

local function PrintTable(tbl, indent)
    indent = indent or ""
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            print(indent .. tostring(k) .. ":")
            PrintTable(v, indent .. "  ")
        else
            print(indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

local function TestTSMImport(importString)
    -- Try each decode method in order
    local success, data = DecodeNewImport(importString)
    if not success then
        success, data = DecodeOldImport(importString)
    end
    if not success then
        success, data = DecodeOldGroupOrItemList(importString)
    end

    if not success then
        return false, nil
    end

    print("\n|cFF00FF00=== TSM Import Debug Information ===|r")
    
    -- Print groups
    print("\n|cFFFFFF00Groups:|r")
    if data.groups then
        for groupPath, _ in pairs(data.groups) do
            print("  - " .. groupPath)
        end
    else
        print("  No groups found")
    end

    -- Print operations in detail
    print("\n|cFFFFFF00Operations:|r")
    if data.operations then
        print("Global Operations:")
        for moduleName, moduleOps in pairs(data.operations) do
            print("  Module: " .. moduleName)
            for opName, opSettings in pairs(moduleOps) do
                print("    Operation: " .. opName)
                print("    Settings:")
                PrintTable(opSettings, "      ")
            end
        end
    else
        print("  No global operations found")
    end

    -- Print group operations
    print("\n|cFFFFFF00Group Operations:|r")
    if data.groupOperations then
        for groupPath, modules in pairs(data.groupOperations) do
            print("  Group: " .. groupPath)
            for moduleName, operations in pairs(modules) do
                print("    Module: " .. moduleName)
                print("    Operations:")
                PrintTable(operations, "      ")
            end
        end
    else
        print("  No group operations found")
    end

    -- Print raw operation data for analysis
    print("\n|cFFFFFF00Raw Operation Data:|r")
    if data.operations then
        print("Operations Table Structure:")
        PrintTable(data.operations, "  ")
    end

    print("\n|cFFFFFF00Custom Sources:|r")
    if data.customSources then
        for sourceName, sourceData in pairs(data.customSources) do
            print("  " .. sourceName .. ":")
            if type(sourceData) == "table" then
                PrintTable(sourceData, "    ")
            else
                print("    = " .. tostring(sourceData))
            end
        end
    else
        print("  No custom sources found")
    end

    print("|cFF00FF00=== End of TSM Import Debug ===|r\n")

    return true, data
end

-- Add this function before TestTSMImport
local function ConvertToFliprFormat(tsmData)
    local fliprData = {}
    
    -- Get the root group name from TSM data
    local rootGroup = tsmData.groupName
    if not rootGroup then
        return nil
    end
    
    -- Initialize root group
    fliprData[rootGroup] = {
        name = rootGroup,
        items = {},
        children = {},
        operations = tsmData.operations or {},  -- Store global operations
        groupOperations = tsmData.groupOperations or {}  -- Store group operations
    }
    
    -- Helper function to ensure group path exists
    local function ensureGroupPath(path)
        local current = fliprData[rootGroup]
        
        -- Split the subpath
        local parts = {strsplit("/", path)}
        for i = 1, #parts do
            local partName = parts[i]
            if not current.children then
                current.children = {}
            end
            current.children[partName] = current.children[partName] or {
                name = partName,
                items = {},
                children = {}
            }
            current = current.children[partName]
        end
        
        return current
    end
    
    -- Process items
    for itemString, groupPath in pairs(tsmData.items) do
        local itemId = itemString:match("i:(%d+)")
        if itemId then
            local group = ensureGroupPath(groupPath)
            if group then
                group.items[itemId] = {
                    name = GetItemInfo(itemId) or itemId,
                    marketValue = 0,
                    saleRate = 0
                }
            end
        end
    end
    
    return fliprData
end

local function SaveImportedGroup(fliprData)
    -- Get reference to FLIPR addon
    local FLIPR = LibStub("AceAddon-3.0"):GetAddon("Flipr")
    if not FLIPR then
        return false
    end
    
    -- Initialize operations storage if it doesn't exist
    FLIPR.groupDB.operations = FLIPR.groupDB.operations or {}
    FLIPR.groupDB.groupOperations = FLIPR.groupDB.groupOperations or {}
    
    -- For each root group in the imported data
    for groupName, groupData in pairs(fliprData) do
        -- If group exists, remove it first
        if FLIPR.groupDB.groups[groupName] then
            FLIPR.groupDB.groups[groupName] = nil
        end
        
        -- Save new group data
        FLIPR.groupDB.groups[groupName] = groupData
        
        -- Save operations if they exist
        if groupData.operations then
            FLIPR.groupDB.operations[groupName] = groupData.operations
        end
        
        -- Save group operations if they exist
        if groupData.groupOperations then
            FLIPR.groupDB.groupOperations[groupName] = groupData.groupOperations
        end
        
        -- Enable the root group
        FLIPR.db.enabledGroups[groupName] = true
        
        -- Helper function to recursively enable all groups
        local function enableAllGroups(node, parentPath)
            if node.children then
                for childName, childNode in pairs(node.children) do
                    local childPath = parentPath .. "/" .. childName
                    FLIPR.db.enabledGroups[childPath] = true
                    enableAllGroups(childNode, childPath)
                end
            end
        end
        
        -- Enable all child groups
        enableAllGroups(groupData, groupName)
    end
    
    -- Rebuild everything
    FLIPR.availableGroups = FLIPR:GetAvailableGroups()
    FLIPR.groupStructure = {}
    for groupName, groupData in pairs(FLIPR.availableGroups) do
        FLIPR.groupStructure[groupName] = FLIPR:BuildGroupStructure(groupData)
    end
    
    -- Initialize database and refresh UI
    FLIPR:InitializeDB()
    if FLIPR.RefreshGroupList then
        FLIPR:RefreshGroupList()
    end
    
    return true
end

-- Add this new combined function
local function ImportTSMGroup(importString)
    -- Step 1: Import and test TSM data
    local success, tsmData = TestTSMImport(importString)
    if not success then
        print("Failed to import TSM group")
        return false
    end
    
    -- Step 2: Convert to Flipr format
    local fliprData = ConvertToFliprFormat(tsmData)
    if not fliprData then
        print("Failed to convert TSM data to Flipr format")
        return false
    end
    
    -- Step 3: Save the group
    if not SaveImportedGroup(fliprData) then
        print("Failed to save imported group")
        return false
    end
    
    return true
end

-- Make the new function available globally
_G.ImportTSMGroup = ImportTSMGroup

-- Keep these existing global exports as they might be used elsewhere
_G.TestTSMImport = TestTSMImport
_G.ConvertToFliprFormat = ConvertToFliprFormat
_G.SaveImportedGroup = SaveImportedGroup