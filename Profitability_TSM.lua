local addonName, addon = ...
local FLIPR = addon.FLIPR

-- TSM API Integration
function FLIPR:GetTSMValue(itemID, valueString)
    if not valueString then return nil end
    
    -- Get TSM API
    local TSM_API = _G.TSM_API
    if not TSM_API then return nil end
    
    -- Convert the value string to a price
    local price = TSM_API.ToPrice(valueString, itemID)
    if not price then return nil end
    
    return price
end

function FLIPR:GetTSMShoppingOperation(itemID)
    -- Convert to TSM item string
    local itemString = "i:" .. itemID
    local itemName = GetItemInfo(itemID) or itemID
    
    -- Get TSM DB
    if not TradeSkillMasterDB then 
        print(string.format("%s: TSM DB not found", itemName))
        return nil 
    end
    
    -- Get TSM API
    local TSM_API = _G.TSM_API
    if not TSM_API then 
        print(string.format("%s: TSM API not found", itemName))
        return nil 
    end
    
    -- Get item's group path from Default profile
    local items = TradeSkillMasterDB["p@Default@userData@items"]
    if not items then
        print(string.format("%s: TSM items data not found", itemName))
        return nil
    end
    
    local groupPath = items[itemString]
    if not groupPath then 
        print(string.format("%s: Not in any TSM group", itemName))
        return nil 
    end
    
    -- Get group's shopping operations
    local groups = TradeSkillMasterDB["p@Default@userData@groups"]
    if not groups then
        print(string.format("%s: TSM groups data not found", itemName))
        return nil
    end
    
    local groupData = groups[groupPath]
    if not groupData or not groupData.Shopping or #groupData.Shopping == 0 then 
        print(string.format("%s: No shopping operations in group %s", itemName, groupPath))
        return nil 
    end
    
    -- Get first shopping operation name
    local operationName = groupData.Shopping[1]
    
    -- Get operation settings
    local operations = TradeSkillMasterDB["p@Default@userData@operations"]
    if not operations or not operations.Shopping then
        print(string.format("%s: TSM shopping operations not found", itemName))
        return nil
    end
    
    local settings = operations.Shopping[operationName]
    if not settings then 
        print(string.format("%s: Shopping operation %s not found", itemName, operationName))
        return nil 
    end
    
    print(string.format("%s: Found operation %s, maxPrice string: %s", itemName, operationName, settings.maxPrice or "nil"))
    
    -- Get maxPrice value
    local maxPrice = TSM_API.GetCustomPriceValue(settings.maxPrice, itemString)
    if not maxPrice or maxPrice == 0 then
        -- Only print "No TSM operation" if the string itself is missing
        if not settings.maxPrice then
            print(string.format("%s: No maxPrice string in operation %s", itemName, operationName))
        else
            -- Get some debug values to help understand why it evaluated to nil
            local maxstack = TSM_API.GetCustomPriceValue("maxstack", itemString) or 0
            -- For individual sale rate values, we need to multiply by 1000
            local salerate = TSM_API.GetCustomPriceValue("dbregionsalerate*1000", itemString) or 0
            salerate = salerate / 1000  -- Convert back for display
            print(string.format("%s: maxPrice string '%s' evaluated to nil (maxstack=%d, salerate=%.3f)", 
                itemName, settings.maxPrice, maxstack, salerate))
        end
        return nil
    end
    
    -- Get restock quantity value
    local restockQuantity = TSM_API.GetCustomPriceValue(settings.restockQuantity, itemString)
    if not restockQuantity or restockQuantity == 0 then
        -- Only print "No TSM operation" if the string itself is missing
        if not settings.restockQuantity then
            print(string.format("%s: No restockQuantity string in operation %s", itemName, operationName))
        else
            -- Otherwise, the string exists but evaluated to nil (normal TSM behavior)
            print(string.format("%s: restockQuantity string '%s' evaluated to nil", itemName, settings.restockQuantity))
        end
        return nil
    end
    
    return {
        maxPrice = maxPrice,
        restockQuantity = restockQuantity,
        showAboveMaxPrice = settings.showAboveMaxPrice,
        evenStacks = settings.evenStacks
    }
end

function FLIPR:GetMaxInventoryForSaleRate_TSM(itemID)
    -- Get TSM operation for this item
    local itemString = "i:" .. itemID
    local operation = self:GetTSMShoppingOperation(itemString)
    if not operation then return 0 end
    
    -- Get restock quantity from TSM operation
    local restockQuantity = operation.restockQuantity or 0
    if restockQuantity == 0 then
        print(string.format("|cFFFFFF00No restock quantity set for %s in TSM operation|r", GetItemInfo(itemID) or itemID))
        return 0
    end
    
    return restockQuantity
end

function FLIPR:AnalyzeMarketConditions_TSM(itemID)
    -- Get base market conditions
    local marketData = self:AnalyzeMarketConditions(itemID)
    if not marketData then return nil end
    
    -- Get TSM shopping operation
    local operation = self:GetTSMShoppingOperation(itemID)
    if not operation then return nil end
    
    -- Add TSM-specific data
    marketData.maxPrice = operation.maxPrice
    marketData.restockQuantity = operation.restockQuantity
    marketData.showAboveMaxPrice = operation.showAboveMaxPrice
    marketData.evenStacks = operation.evenStacks
    
    return marketData
end

function FLIPR:AnalyzeFlipOpportunity_TSM(results, itemID)
    -- Initial checks...
    local itemName = GetItemInfo(itemID)
    if not itemName then return nil end
    
    -- Get market conditions with TSM operation data
    local marketData = self:AnalyzeMarketConditions_TSM(itemID)
    if not marketData then 
        print(string.format("%s: No TSM operation", itemName))
        return nil 
    end
    
    -- Get inventory limits from TSM operation
    local maxInventory = marketData.restockQuantity
    if maxInventory == 0 then
        print(string.format("%s: No restock quantity", itemName))
        return nil
    end
    
    local currentInventory = self:GetCurrentInventory(itemID)
    local roomForMore = maxInventory - currentInventory
    
    if roomForMore <= 0 then
        print(string.format("%s: Full inventory %d/%d", itemName, currentInventory, maxInventory))
        return nil
    end
    
    -- Sort results by price
    table.sort(results, function(a, b) return a.minPrice < b.minPrice end)
    
    if #results == 0 then
        print(string.format("%s: No auctions found", itemName))
        return nil
    end
    
    -- Check if first auction is too big for our inventory limit
    if results[1].totalQuantity > roomForMore then
        print(string.format("%s: First auction too big (%d), need %d or less", 
            itemName, results[1].totalQuantity, roomForMore))
        return nil
    end
    
    local cheapestPrice = results[1].minPrice
    if cheapestPrice > marketData.maxPrice then
        print(string.format("%s: Cheapest (%s) > maxPrice (%s)", itemName, 
            C_CurrencyInfo.GetCoinTextureString(cheapestPrice), C_CurrencyInfo.GetCoinTextureString(marketData.maxPrice)))
        return nil
    end
    
    -- Determine if item is a commodity
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
    local isCommodity = itemInfo and itemInfo.isCommodity or false
    
    -- Track cumulative quantities
    local cumulativeQuantity = 0
    local remainingNeeded = roomForMore
    
    -- Find profitable auctions by comparing to TSM maxPrice
    local profitableAuctions = {}
    local ahCut = 0.05  -- 5% AH fee
    local minProfitInCopper = self.db.profile.minProfit * 10000  -- Convert gold to copper
    local allAuctions = {}  -- Store all auctions for UI display
    
    -- Check for unreasonable quantity jumps
    local baseQuantity = results[1].totalQuantity
    for i = 2, math.min(5, #results) do
        local quantityJump = results[i].totalQuantity / baseQuantity
        -- If next auction is 5x bigger, skip this item
        if quantityJump > 5 and results[i].minPrice <= marketData.maxPrice then
            print(string.format("%s: Skipping due to large quantity jump (%d -> %d)", 
                itemName, baseQuantity, results[i].totalQuantity))
            return nil
        end
        baseQuantity = results[i].totalQuantity
    end
    
    for i = 1, #results do
        local auction = results[i]
        local buyPrice = auction.minPrice
        
        -- Always add to allAuctions for UI display
        table.insert(allAuctions, {
            buyPrice = buyPrice,
            sellPrice = marketData.maxPrice,
            quantity = auction.totalQuantity,
            auctionIndex = i
        })
        
        -- Only process if we still need more items and price is below maxPrice
        if remainingNeeded > 0 and buyPrice <= marketData.maxPrice then
            -- Calculate how many we can buy from this auction
            local quantityFromThisAuction = math.min(auction.totalQuantity, remainingNeeded)
            
            -- Calculate deposit
            local deposit = self:CalculateDeposit(itemID, 1, quantityFromThisAuction, isCommodity)
            
            -- Calculate potential profit
            local potentialProfit = math.floor((marketData.maxPrice * (1 - ahCut) - buyPrice) * quantityFromThisAuction - deposit)
            local roi = math.floor(((marketData.maxPrice * (1 - ahCut) - buyPrice) / buyPrice) * 100)
            
            -- Check if profit meets minimum requirements
            if potentialProfit >= minProfitInCopper then
                -- Add to profitable auctions
                table.insert(profitableAuctions, {
                    buyPrice = buyPrice,
                    sellPrice = marketData.maxPrice,
                    quantity = quantityFromThisAuction,
                    profit = potentialProfit,
                    roi = roi,
                    isFlashSale = false,  -- Not used in TSM mode
                    deposit = deposit,
                    auctionIndex = i
                })
                
                cumulativeQuantity = cumulativeQuantity + quantityFromThisAuction
                remainingNeeded = remainingNeeded - quantityFromThisAuction
                
                -- For commodities, we can only buy the first auction
                if isCommodity then break end
            end
        end
    end
    
    if #profitableAuctions == 0 then
        local minProfit = self.db.profile.minProfit * 10000
        local profit = math.floor((marketData.maxPrice * 0.95 - cheapestPrice) * results[1].totalQuantity)
        
        -- Debug prints
        print(string.format("%s: Debug - maxPrice: %d, cheapestPrice: %d, quantity: %d, profit: %d", 
            itemName, marketData.maxPrice or 0, cheapestPrice or 0, results[1].totalQuantity or 0, profit or 0))
        
        -- Ensure we have valid numbers
        if type(profit) ~= "number" or profit < 0 then
            print(string.format("%s: Invalid profit calculation", itemName))
            return nil
        end
        
        if type(minProfit) ~= "number" or minProfit < 0 then
            print(string.format("%s: Invalid minProfit value", itemName))
            return nil
        end
        
        print(string.format("%s: Profit %s < min %s", itemName, 
            C_CurrencyInfo.GetCoinTextureString(profit) or "0", 
            C_CurrencyInfo.GetCoinTextureString(minProfit) or "0"))
        return nil
    end
    
    -- If we found profitable auctions, print success and continue...
    print(string.format("%s: Found flip! Buy @ %s x%d, Sell @ %s", itemName,
        C_CurrencyInfo.GetCoinTextureString(profitableAuctions[1].buyPrice),
        profitableAuctions[1].quantity,
        C_CurrencyInfo.GetCoinTextureString(marketData.maxPrice)))
        
    -- Sort by ROI
    table.sort(profitableAuctions, function(a, b) return a.roi > b.roi end)
    
    -- Calculate aggregated values
    local totalQuantity = 0
    local totalCost = 0
    local totalProfit = 0
    
    for _, auction in ipairs(profitableAuctions) do
        totalQuantity = totalQuantity + auction.quantity
        totalCost = totalCost + (auction.buyPrice * auction.quantity)
        totalProfit = totalProfit + auction.profit
    end
    
    local avgBuyPrice = math.floor(totalCost / totalQuantity)
    local avgSellPrice = marketData.maxPrice  -- Use TSM maxPrice
    
    -- Return in format expected by UI
    return {
        itemID = itemID,
        itemName = itemName,
        avgBuyPrice = avgBuyPrice,
        buyQuantity = totalQuantity,
        sellPrice = avgSellPrice,
        totalProfit = totalProfit,
        roi = profitableAuctions[1].roi,  -- Use best ROI
        auctions = allAuctions,  -- Show all auctions in UI
        profitableAuctions = profitableAuctions,  -- But keep track of which ones are profitable
        isCommodity = isCommodity,
        marketData = marketData,
        currentInventory = currentInventory,
        maxInventory = maxInventory
    }
end 