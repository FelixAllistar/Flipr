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

    -- Print the decoded data structure
    -- print("Successfully decoded TSM group import!")
    -- print("Structure:")
    
    -- Print groups
    -- print("\nGroups:")
    if data.groups then
        for groupPath, _ in pairs(data.groups) do
            -- print("  - " .. groupPath)
        end
    else
        -- print("  No groups found")
    end

    -- Print items with enhanced information
    -- print("\nItems:")
    if data.items then
        local itemCount = 0
        local processedCount = 0
        
        for itemString, groupPath in pairs(data.items) do
            itemCount = itemCount + 1
            local itemId = itemString:match("i:(%d+)")
            
            if itemId then
                ProcessItemInfo(itemId, function(itemInfo)
                    processedCount = processedCount + 1
                    
                    -- Format gold value
                    local marketValue = itemInfo.marketValue
                    local goldValue = marketValue and math.floor(marketValue / 10000) or 0
                    local silverValue = marketValue and math.floor((marketValue % 10000) / 100) or 0
                    local copperValue = marketValue and (marketValue % 100) or 0
                    
                    -- print(string.format("  - %s (%s)", itemInfo.link or itemId, groupPath))
                    -- print(string.format("    Market Value: %dg %ds %dc", goldValue, silverValue, copperValue))
                    -- print(string.format("    Sale Rate: %.2f%%", (itemInfo.saleRate or 0) * 100))
                    
                    -- If this is the last item, print summary
                    if processedCount == itemCount then
                        -- print(string.format("\nProcessed %d items", processedCount))
                    end
                end)
            end
        end
    else
        -- print("  No items found")
    end

    -- Print operations
    -- print("\nOperations:")
    if data.groupOperations then
        for groupPath, modules in pairs(data.groupOperations) do
            -- print("  Group: " .. groupPath)
            for moduleName, operations in pairs(modules) do
                -- print("    - Module: " .. moduleName)
                for i, op in ipairs(operations) do
                    -- print("      Operation " .. i .. ": " .. op)
                end
            end
        end
    else
        -- print("  No operations found")
    end

    -- Print raw data for debugging
    -- print("\nRaw Data:")
    for k,v in pairs(data) do
        -- print("  " .. k .. " = " .. type(v))
    end

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
        children = {}
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
    
    -- Print group structure and count items
    local totalFliprItems = 0
    local function printGroupStructure(group, indent)
        indent = indent or 0
        local prefix = string.rep("  ", indent)
        
        -- Count items in this group AND its children
        local function countGroupItems(g)
            local count = 0
            -- Count direct items
            for itemId, _ in pairs(g.items) do
                count = count + 1
                if indent == 0 then  -- Only increment total once at root level
                    totalFliprItems = totalFliprItems + 1
                end
            end
            -- Count items in children
            for _, child in pairs(g.children) do
                count = count + countGroupItems(child)
            end
            return count
        end
        
        -- Get total items for this group and its children
        local totalItems = countGroupItems(group)
        
        -- Always show item count for debugging purposes
        -- print(prefix .. group.name .. " (" .. totalItems .. " items)")
        
        -- Print children in sorted order
        local children = {}
        for _, child in pairs(group.children) do
            table.insert(children, child)
        end
        table.sort(children, function(a,b) return a.name < b.name end)
        
        for _, child in ipairs(children) do
            printGroupStructure(child, indent + 1)
        end
    end
    
    -- print("\nConverted group structure:")
    printGroupStructure(fliprData[rootGroup])
    -- print("\nTotal Flipr items:", totalFliprItems)
    
    return fliprData
end

local function SaveImportedGroup(fliprData)
    -- Get reference to FLIPR addon
    local FLIPR = LibStub("AceAddon-3.0"):GetAddon("Flipr")
    if not FLIPR then
        return false
    end
    
    -- For each root group in the imported data
    for groupName, groupData in pairs(fliprData) do
        -- If group exists, remove it first
        if FLIPR.groupDB.groups[groupName] then
            -- print("Updating existing group:", groupName)
            FLIPR.groupDB.groups[groupName] = nil
        else
            -- print("Adding new group:", groupName)
        end
        
        -- Save new group data
        FLIPR.groupDB.groups[groupName] = groupData
    end
    
    -- Trigger UI refresh if needed
    if FLIPR.RefreshGroupList then
        FLIPR:RefreshGroupList()
    end
    
    return true
end

-- Make functions available globally
_G.TestTSMImport = TestTSMImport
_G.ConvertToFliprFormat = ConvertToFliprFormat
_G.SaveImportedGroup = SaveImportedGroup