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
        print("Failed to decode Base64 string")
        return false
    end

    -- Step 2: Decompress
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        print("Failed to decompress data")
        return false
    end

    -- Step 3: Deserialize using LibSerialize (new format)
    local success, magicStr, version, groupName, items, groups, groupOperations, operations, customSources = LibSerialize:Deserialize(decompressed)
    if not success then
        print("Failed to deserialize data")
        return false
    end

    -- Validate magic string and version
    if magicStr ~= MAGIC_STR then
        print("Invalid magic string:", magicStr)
        return false
    end
    if version ~= VERSION then
        print("Invalid version:", version)
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
        print("Not an old import string")
        return false
    end

    -- Deserialize using AceSerializer (old format)
    local success, data = AceSerializer:Deserialize(str)
    if not success then
        print("Failed to deserialize old format data")
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
        print("Failed to decode import string using any method")
        return
    end

    -- Print the decoded data structure
    print("Successfully decoded TSM group import!")
    print("Structure:")
    
    -- Print groups
    print("\nGroups:")
    if data.groups then
        for groupPath, _ in pairs(data.groups) do
            print("  - " .. groupPath)
        end
    else
        print("  No groups found")
    end

    -- Print items with enhanced information
    print("\nItems:")
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
                    
                    print(string.format("  - %s (%s)", itemInfo.link or itemId, groupPath))
                    print(string.format("    Market Value: %dg %ds %dc", goldValue, silverValue, copperValue))
                    print(string.format("    Sale Rate: %.2f%%", (itemInfo.saleRate or 0) * 100))
                    
                    -- If this is the last item, print summary
                    if processedCount == itemCount then
                        print(string.format("\nProcessed %d items", processedCount))
                    end
                end)
            end
        end
    else
        print("  No items found")
    end

    -- Print operations
    print("\nOperations:")
    if data.groupOperations then
        for groupPath, modules in pairs(data.groupOperations) do
            print("  Group: " .. groupPath)
            for moduleName, operations in pairs(modules) do
                print("    - Module: " .. moduleName)
                for i, op in ipairs(operations) do
                    print("      Operation " .. i .. ": " .. op)
                end
            end
        end
    else
        print("  No operations found")
    end

    -- Print raw data for debugging
    print("\nRaw Data:")
    for k,v in pairs(data) do
        print("  " .. k .. " = " .. type(v))
    end
end

-- Make function available globally for testing
_G.TestTSMImport = TestTSMImport