local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:GetTSMValue(source, itemString, needsDecimalConversion)
    local value = TSM_API.GetCustomPriceValue(source, itemString)
    if not value then return 0 end
    
    -- Convert from TSM's integer format if needed
    if needsDecimalConversion then
        return value / 1000
    end
    return value
end

function FLIPR:GetItemSaleRate(itemID)
    local itemString = TSM_API.ToItemString("i:" .. itemID)
    return self:GetTSMValue("DBRegionSaleRate*1000", itemString, true)
end

function FLIPR:GetMaxInventoryForSaleRate(itemID)
    -- Get TSM shopping operations for this item
    local operations = self:GetTSMShoppingOperations(itemID)
    if not operations or #operations == 0 then return 0 end
    
    -- Use the first operation's restockQuantity
    -- TSM only uses the first operation for shopping
    local restockQuantity = operations[1].restockQuantity
    if not restockQuantity then return 0 end
    
    -- Evaluate the restock quantity string
    local itemString = TSM_API.ToItemString("i:" .. itemID)
    local maxQuantity = TSM_API.GetCustomPriceValue(restockQuantity, itemString)
    
    return maxQuantity or 0
end

function FLIPR:GetCurrentInventory(itemID)
    -- Get inventory count (bags + bank)
    local inventoryCount = GetItemCount(itemID, true)
    
    -- Get count of items we have listed
    local auctionCount = 0
    local numOwnedAuctions = C_AuctionHouse.GetNumOwnedAuctions()
    
    for i = 1, numOwnedAuctions do
        local auctionInfo = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if auctionInfo and auctionInfo.itemKey.itemID == itemID then
            -- For commodities, quantity is per auction
            -- For items, each auction is quantity 1
            auctionCount = auctionCount + (auctionInfo.quantity or 1)
        end
    end
    
    -- Return total of inventory + listed auctions
    return inventoryCount + auctionCount
end

function FLIPR:CalculateDeposit(itemID, duration, quantity, isCommodity)
    -- Default duration is 12 hours (1) if not specified
    duration = duration or 1
    
    -- Ensure itemID is a number
    itemID = tonumber(itemID)
    if not itemID then return 0 end
    
    if isCommodity then
        return C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, quantity) or 0
    else
        -- For regular items, we need to create a temporary item
        local item = Item:CreateFromItemID(itemID)
        if item then
            -- Need to wait for item to load
            local deposit = 0
            item:ContinueOnItemLoad(function()
                deposit = C_AuctionHouse.CalculateItemDeposit(item, duration, quantity) or 0
            end)
            return deposit
        end
        return 0
    end
end

function FLIPR:AnalyzeMarketConditions(itemID)
    local itemString = TSM_API.ToItemString("i:" .. itemID)
    
    -- Get TSM shopping operations for this item
    local operations = self:GetTSMShoppingOperations(itemID)
    if not operations or #operations == 0 then 
        print(string.format("|cFFFFFF00No TSM shopping operations found for %s|r", GetItemInfo(itemID) or itemID))
        return nil 
    end
    
    -- Use the first operation's maxPrice
    local maxPrice = operations[1].maxPrice
    if not maxPrice then 
        print(string.format("|cFFFFFF00TSM operation has no maxPrice defined for %s|r", GetItemInfo(itemID) or itemID))
        return nil 
    end
    
    -- Get price sources (with proper decimal handling)
    local regionMarket = self:GetTSMValue("DBRegionMarketAvg*1000", itemString, true)
    local localMarket = self:GetTSMValue("DBMarket*1000", itemString, true)
    local historical = self:GetTSMValue("DBRegionHistorical*1000", itemString, true)
    local saleRate = self:GetTSMValue("DBRegionSaleRate*1000", itemString, true)
    local soldPerDay = self:GetTSMValue("DBRegionSoldPerDay", itemString, false)
    
    -- Get the evaluated maxPrice from TSM
    local evaluatedMaxPrice = TSM_API.GetCustomPriceValue(maxPrice, itemString)
    print(string.format("DEBUG: MaxPrice formula for %s: %s", GetItemInfo(itemID) or itemID, maxPrice))
    print(string.format("DEBUG: Evaluated MaxPrice for %s: %s", GetItemInfo(itemID) or itemID, GetCoinTextureString(evaluatedMaxPrice or 0)))
    
    -- If evaluation fails or returns 0, skip this item
    if not evaluatedMaxPrice or evaluatedMaxPrice == 0 then
        print(string.format("|cFFFFFF00MaxPrice evaluated to %s for %s (formula: %s)|r", 
            evaluatedMaxPrice and "0" or "nil",
            GetItemInfo(itemID) or itemID,
            maxPrice
        ))
        return nil
    end
    
    -- Market stability check
    local marketStability = localMarket / regionMarket
    local isStableMarket = (marketStability >= 0.7 and marketStability <= 1.3)
    
    -- Historical price comparison
    local historicalComparison = localMarket / historical
    local isPriceLow = (historicalComparison < 0.8)
    
    -- Categorize item by sale metrics
    local saleCategory = self:GetSaleCategory(saleRate, soldPerDay)
    
    return {
        isStableMarket = isStableMarket,
        isPriceLow = isPriceLow,
        marketStability = marketStability,
        historicalComparison = historicalComparison,
        saleRate = saleRate,
        soldPerDay = soldPerDay,
        saleCategory = saleCategory,
        localMarket = localMarket,
        regionMarket = regionMarket,
        maxPrice = evaluatedMaxPrice
    }
end

function FLIPR:GetSaleCategory(saleRate, soldPerDay)
    if saleRate >= 0.3 and soldPerDay >= 5 then
        return "HIGH_VOLUME"    -- Fast movers
    elseif saleRate >= 0.1 then
        return "MEDIUM_VOLUME"  -- Regular items
    elseif saleRate >= 0.06 then
        return "LOW_VOLUME"     -- Slow movers
    else
        return "VERY_LOW_VOLUME" -- Very slow movers
    end
end

function FLIPR:CalculateRequiredROI(marketData, itemID)
    -- Base ROI requirements from saved variables
    local baseROI = {
        HIGH_VOLUME = self.db.highVolumeROI,
        MEDIUM_VOLUME = self.db.mediumVolumeROI,
        LOW_VOLUME = self.db.lowVolumeROI,
        VERY_LOW_VOLUME = self.db.veryLowVolumeROI
    }
    
    local requiredROI = baseROI[marketData.saleCategory]
    
    -- Market volatility adjustment
    if not marketData.isStableMarket then
        local volatilityFactor = math.abs(1 - marketData.marketStability)
        requiredROI = requiredROI * (1 + volatilityFactor)
    end
    
    -- Historical price adjustment - REVERSED logic
    if marketData.isPriceLow then
        -- When prices are historically low, reduce required ROI to buy more
        -- But only if market is stable
        if marketData.isStableMarket then
            requiredROI = requiredROI * 0.8  -- 20% lower requirements
        end
    end
    
    -- Add market depth considerations
    if itemID then
        local depthData = self:AnalyzeMarketDepth(itemID)
        if depthData then
            if depthData.volumeToListings < 0.1 then  -- Market is oversaturated
                requiredROI = requiredROI * 1.5       -- Require 50% more ROI
            end
            if depthData.priceSpread > 0.5 then      -- Large price gaps
                requiredROI = requiredROI * 1.3       -- Require 30% more ROI
            end
        end
    end
    
    return requiredROI
end

function FLIPR:IsFlashSale(currentPrice, marketData)
    -- More aggressive for high volume items
    local discountThresholds = {
        HIGH_VOLUME = 0.7,     -- 30% discount needed
        MEDIUM_VOLUME = 0.6,   -- 40% discount needed
        LOW_VOLUME = 0.5,      -- 50% discount needed
        VERY_LOW_VOLUME = 0.4  -- 60% discount needed
    }
    
    local threshold = discountThresholds[marketData.saleCategory]
    local isSignificantDiscount = (currentPrice < marketData.localMarket * threshold)
    
    -- For very low volume items, require even steeper discounts if sale rate is extremely low
    if marketData.saleCategory == "VERY_LOW_VOLUME" and marketData.saleRate < 0.03 then
        return isSignificantDiscount and (currentPrice < marketData.localMarket * 0.3) -- 70% discount
    end
    
    return isSignificantDiscount
end

function FLIPR:AnalyzeFlipOpportunity(results, itemID)
    -- Initial checks...
    local itemName = GetItemInfo(itemID)
    if not itemName then return nil end
    
    -- Get market conditions (includes TSM maxPrice)
    local marketData = self:AnalyzeMarketConditions(itemID)
    if not marketData then 
        -- Don't print here since AnalyzeMarketConditions already printed a specific error
        return nil 
    end
    
    -- Get inventory limits from TSM operation
    local maxInventory = self:GetMaxInventoryForSaleRate(itemID)
    if maxInventory == 0 then
        print(string.format("|cFFFFFF00No restock quantity defined for %s|r", itemName))
        return nil
    end
    
    local currentInventory = self:GetCurrentInventory(itemID)
    local roomForMore = maxInventory - currentInventory
    
    if roomForMore <= 0 then
        print(string.format(
            "|cFFFF0000Skipping %s - Already have %d/%d (Sale Rate: %.3f)|r",
            itemName,
            currentInventory,
            maxInventory,
            marketData.saleRate
        ))
        return nil
    end
    
    -- Determine if item is a commodity
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
    local isCommodity = itemInfo and itemInfo.isCommodity or false
    
    -- Find profitable auctions
    local profitableAuctions = {}
    local ahCut = 0.05  -- 5% AH fee
    local minProfitInCopper = self.db.profile.minProfit * 10000  -- Convert gold to copper (1g = 10000c)
    
    -- Sort results by price
    table.sort(results, function(a, b) return a.minPrice < b.minPrice end)
    
    -- Track cumulative quantities for profit calculation
    local cumulativeQuantity = 0
    local remainingNeeded = roomForMore  -- Track how many we still need to buy
    local allAuctions = {}  -- Store all auctions for UI display
    
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
        
        -- Only process for profitability if we still need more and price is good
        if remainingNeeded > 0 and buyPrice <= marketData.maxPrice then
            -- Calculate how many we can buy from this auction
            local quantityFromThisAuction = math.min(auction.totalQuantity, remainingNeeded)
            
            -- Calculate deposit for posting duration (12 hours = 1)
            local deposit = self:CalculateDeposit(itemID, 1, quantityFromThisAuction, isCommodity)
            
            -- Calculate potential profit including deposit cost
            local sellPrice = marketData.maxPrice
            local potentialProfit = math.floor((sellPrice * (1 - ahCut) - buyPrice) * quantityFromThisAuction - deposit)
            local roi = math.floor(((sellPrice * (1 - ahCut) - buyPrice) / buyPrice) * 100)
            
            -- Check both ROI and minimum profit requirements
            if potentialProfit >= minProfitInCopper and roi >= self.db.profile.highVolumeROI then
                -- Check if this is a flash sale opportunity
                local isFlash = self:IsFlashSale(buyPrice, marketData)
                
                -- Add to profitable auctions
                table.insert(profitableAuctions, {
                    buyPrice = buyPrice,
                    sellPrice = sellPrice,
                    quantity = quantityFromThisAuction,
                    profit = potentialProfit,
                    roi = roi,
                    isFlashSale = isFlash,
                    deposit = deposit,
                    auctionIndex = i
                })
                
                cumulativeQuantity = cumulativeQuantity + quantityFromThisAuction
                remainingNeeded = remainingNeeded - quantityFromThisAuction
                
                -- For commodities, we can only buy the first auction
                if isCommodity then break end
            end
        elseif remainingNeeded <= 0 then
            print(string.format("|cFFFFFF00Already found enough quantity for %s - showing remaining auctions for info only|r", itemName))
        elseif buyPrice > marketData.maxPrice then
            print(string.format(
                "|cFFFFFF00Skipping remaining auctions for %s - Price %s above maxPrice %s|r",
                itemName,
                GetCoinTextureString(buyPrice),
                GetCoinTextureString(marketData.maxPrice)
            ))
            break  -- No point checking more auctions as they're sorted by price
        end
    end
    
    -- If we found profitable auctions, return all of them
    if #profitableAuctions > 0 then
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
        
        -- Return in format expected by UI
        return {
            itemID = itemID,
            itemName = itemName,
            avgBuyPrice = avgBuyPrice,
            buyQuantity = totalQuantity,
            sellPrice = marketData.maxPrice,
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
    
    print(string.format("|cFFFFFF00No profitable flip found for %s|r", itemName))
    return nil
end

function FLIPR:AnalyzeMarketDepth(itemID)
    local itemString = TSM_API.ToItemString("i:" .. itemID)
    if not itemString then return nil end
    
    -- Get various price points
    local dbMarket = self:GetTSMValue("DBMarket*1000", itemString, true)
    local dbMinBuyout = self:GetTSMValue("DBMinBuyout*1000", itemString, true)
    local dbHistorical = self:GetTSMValue("DBHistorical*1000", itemString, true)
    
    -- Get volume metrics
    local avgDaily = self:GetTSMValue("DBRegionSoldPerDay", itemString, false)
    local numAuctions = self:GetTSMValue("DBRegionMarketAvg", itemString, false)
    
    -- Calculate market depth indicators
    local priceSpread = (dbMarket - dbMinBuyout) / dbMarket
    local volumeToListings = avgDaily / (numAuctions or 1)
    
    return {
        priceSpread = priceSpread,           -- Higher spread indicates more price volatility
        volumeToListings = volumeToListings, -- Higher ratio means items sell through faster
        avgDailyVolume = avgDaily,
        currentListings = numAuctions,
        marketPrice = dbMarket,
        historicalPrice = dbHistorical
    }
end 