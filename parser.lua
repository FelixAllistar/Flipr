local addonName, addon = ...

local Parser = {}
addon.Parser = Parser

function Parser.parseAppHelperData(data)
    -- Debug what we received
    print("FLIPR Debug: Parsing data type:", type(data))
    if type(data) == "table" then
        print("FLIPR Debug: Table contents:")
        for k,v in pairs(data) do
            print("  ", k, type(v))
        end
    end
    
    -- Initialize result structure
    local result = {
        items = {},
        regions = {},
        lastUpdate = 0
    }
    
    -- Process each data type we found in TSM_AppHelper
    if data.errorReports then
        print("FLIPR Debug: Found errorReports table")
    end
    
    if data.analytics then
        print("FLIPR Debug: Found analytics table")
    end
    
    if data.blackMarket then
        print("FLIPR Debug: Found blackMarket table")
        -- Process black market data if needed
    end
    
    -- Store the region
    if data.region then
        result.region = data.region
        print("FLIPR Debug: Found region:", data.region)
    end
    
    return result
end

return Parser 