local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:GetMaxInventoryForSaleRate_Classic(itemID)
    local saleRate = self:GetItemSaleRate(itemID)
    
    -- Use the configured thresholds and inventory limits
    if saleRate >= self.db.profile.highSaleRate then
        return self.db.profile.highInventory
    elseif saleRate >= self.db.profile.mediumSaleRate then
        return self.db.profile.mediumInventory
    else
        return self.db.profile.lowInventory
    end
end

function FLIPR:AnalyzeFlipOpportunity_Classic(results, itemID)
    -- Initial checks
    local itemName = GetItemInfo(itemID)
    if not itemName then return nil end
    
    -- Get market conditions (keep this for ROI calculation)
    local marketData = self:AnalyzeMarketConditions(itemID)
    if not marketData then 
        print(string.format("%s: No market data", itemName))
        return nil 
    end
    
    -- Get inventory limits using direct sale rate
    local maxInventory = self:GetMaxInventoryForSaleRate_Classic(itemID)
    local currentInventory = self:GetCurrentInventory(itemID)
    local roomForMore = maxInventory - currentInventory
    
    if roomForMore <= 0 then
        print(string.format("%s: Full inventory %d/%d (Sale Rate: %.3f)", 
            itemName, currentInventory, maxInventory, marketData.saleRate))
        return nil
    end
    
    -- Sort results by price
    table.sort(results, function(a, b) return a.minPrice < b.minPrice end)
    
    if #results <= 1 then
        print(string.format("%s: Not enough auctions to analyze", itemName))
        return nil
    end
    
    -- Check if first auction is too big
    if results[1].totalQuantity > roomForMore then
        print(string.format("%s: First auction too big (%d), need %d or less", 
            itemName, results[1].totalQuantity, roomForMore))
        return nil
    end
    
    -- Get commodity status
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
    local isCommodity = itemInfo and itemInfo.isCommodity or false
    
    -- Find profitable auctions
    local profitableAuctions = {}
    local ahCut = 0.05
    local minProfitInCopper = self.db.profile.minProfit * 10000
    local requiredROI = self:CalculateRequiredROI(marketData, itemID)
    local allAuctions = {}  -- For UI display
    
    -- Track cumulative quantities
    local totalQuantity = 0
    local totalCost = 0
    local totalDeposit = 0
    local remainingNeeded = roomForMore
    
    for i = 1, #results-1 do
        local buyPrice = results[i].minPrice
        local nextPrice = results[i+1].minPrice
        local quantity = results[i].totalQuantity
        
        -- Always add to allAuctions for UI display
        table.insert(allAuctions, {
            buyPrice = buyPrice,
            sellPrice = nextPrice,
            quantity = quantity,
            auctionIndex = i
        })
        
        -- Calculate deposit and potential profit
        local deposit = self:CalculateDeposit(itemID, 1, quantity, isCommodity)
        local potentialProfit = (nextPrice * (1 - ahCut)) - (buyPrice + deposit)
        local roi = (potentialProfit / buyPrice) * 100
        
        -- Check both ROI and minimum profit requirements
        if potentialProfit >= minProfitInCopper and roi >= requiredROI then
            -- Calculate how many we can buy from this auction
            local quantityFromThisAuction = math.min(quantity, remainingNeeded)
            
            if quantityFromThisAuction > 0 then
                totalQuantity = totalQuantity + quantityFromThisAuction
                totalCost = totalCost + (buyPrice * quantityFromThisAuction)
                totalDeposit = totalDeposit + deposit
                remainingNeeded = remainingNeeded - quantityFromThisAuction
                
                -- Add to profitable auctions
                table.insert(profitableAuctions, {
                    buyPrice = buyPrice,
                    sellPrice = nextPrice,
                    quantity = quantityFromThisAuction,
                    profit = potentialProfit * quantityFromThisAuction,
                    deposit = deposit,
                    roi = roi,
                    isFlashSale = self:IsFlashSale(buyPrice, marketData),
                    auctionIndex = i
                })
                
                -- For commodities, we can only buy the first auction
                if isCommodity then break end
                
                -- Stop if we've hit our quantity limit
                if remainingNeeded <= 0 then break end
            end
        else
            -- Stop looking once we find unprofitable price points
            break
        end
    end
    
    if #profitableAuctions == 0 then
        print(string.format("%s: No profitable flips found", itemName))
        return nil
    end
    
    -- Calculate average values
    local avgBuyPrice = math.floor(totalCost / totalQuantity)
    local sellPrice = profitableAuctions[1].sellPrice  -- Use first profitable auction's sell price
    local totalProfit = math.floor((sellPrice * (1 - ahCut) * totalQuantity) - totalCost - totalDeposit)
    local roi = math.floor(((sellPrice * (1 - ahCut) - avgBuyPrice) / avgBuyPrice) * 100)
    
    -- Print success message
    print(string.format("%s: Found flip! Buy %d @ avg %s, Sell @ %s (ROI: %d%%)", 
        itemName,
        totalQuantity,
        C_CurrencyInfo.GetCoinTextureString(avgBuyPrice),
        C_CurrencyInfo.GetCoinTextureString(sellPrice),
        roi))
    
    -- Return in format expected by UI
    return {
        itemID = itemID,
        itemName = itemName,
        avgBuyPrice = avgBuyPrice,
        buyQuantity = totalQuantity,
        sellPrice = sellPrice,
        totalProfit = totalProfit,
        roi = roi,
        auctions = allAuctions,
        profitableAuctions = profitableAuctions,
        isCommodity = isCommodity,
        marketData = marketData,
        currentInventory = currentInventory,
        maxInventory = maxInventory
    }
end 