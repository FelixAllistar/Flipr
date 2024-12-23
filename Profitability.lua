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
    -- Backward compatibility function
    local itemString = TSM_API.ToItemString("i:" .. itemID)
    return self:GetTSMValue("DBRegionSaleRate*1000", itemString, true)
end

function FLIPR:GetMaxInventoryForSaleRate(itemID)
    local itemString = TSM_API.ToItemString("i:" .. itemID)
    local saleRate = self:GetTSMValue("DBRegionSaleRate*1000", itemString, true)
    
    if saleRate >= self.db.highSaleRate then
        return self.db.highInventory
    elseif saleRate >= self.db.mediumSaleRate then
        return self.db.mediumInventory
    else
        return self.db.lowInventory
    end
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
    if not itemString then return nil end
    
    -- Get price sources (with proper decimal handling)
    local regionMarket = self:GetTSMValue("DBRegionMarketAvg*1000", itemString, true)
    local localMarket = self:GetTSMValue("DBMarket*1000", itemString, true)
    local historical = self:GetTSMValue("DBRegionHistorical*1000", itemString, true)
    local saleRate = self:GetTSMValue("DBRegionSaleRate*1000", itemString, true)
    local soldPerDay = self:GetTSMValue("DBRegionSoldPerDay", itemString, false)
    
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
        regionMarket = regionMarket
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
    local itemData = self.itemDB[itemID]
    if not itemData then return nil end
    
    -- Get market conditions
    local marketData = self:AnalyzeMarketConditions(itemID)
    if not marketData then return nil end
    
    -- Get inventory limits using direct TSM sale rate
    local maxInventory = self:GetMaxInventoryForSaleRate(itemID)
    local currentInventory = self:GetCurrentInventory(itemID)
    local roomForMore = maxInventory - currentInventory
    
    if roomForMore <= 0 then
        print(string.format(
            "|cFFFF0000Skipping %s - Already have %d/%d (Sale Rate: %s)|r",
            GetItemInfo(itemID) or itemID,
            currentInventory,
            maxInventory,
            tostring(marketData.saleRate)
        ))
        return nil
    end
    
    -- Check if the minimum purchase quantity is too high
    if results[1].totalQuantity > roomForMore then
        print(string.format(
            "|cFFFF0000Skipping %s - First auction quantity (%d) exceeds our limit (%d)|r",
            GetItemInfo(itemID) or itemID,
            results[1].totalQuantity,
            roomForMore
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
    
    -- Get required ROI for this item
    local requiredROI = self:CalculateRequiredROI(marketData, itemID)
    
    for i = 1, #results-1 do
        local buyPrice = results[i].minPrice
        local nextPrice = results[i+1].minPrice
        local quantity = results[i].totalQuantity
        
        -- Calculate deposit for posting duration (12 hours = 1, 24 hours = 2, 48 hours = 3)
        local deposit = self:CalculateDeposit(itemID, 1, quantity, isCommodity)
        
        -- Calculate potential profit including deposit cost
        local potentialProfit = (nextPrice * (1 - ahCut)) - (buyPrice + deposit)
        local roi = (potentialProfit / buyPrice) * 100
        
        -- Check both ROI and minimum profit requirements
        local minProfitInCopper = self.db.minProfit * 10000  -- Convert gold to copper (1g = 10000c)
        if potentialProfit >= minProfitInCopper and roi >= requiredROI then
            table.insert(profitableAuctions, {
                index = i,
                buyPrice = buyPrice,
                sellPrice = nextPrice,
                quantity = quantity,
                profit = potentialProfit,
                deposit = deposit,
                roi = roi
            })
        else
            -- Stop looking once we find unprofitable price points
            break
        end
    end
    
    if #profitableAuctions == 0 then
        return nil
    end
    
    -- Take the first profitable auction group
    local bestDeal = profitableAuctions[1]
    local buyQuantity = math.min(roomForMore, bestDeal.quantity)
    
    -- Debug output with deposit info
    print(string.format(
        "Analysis for %s:\n" ..
        "- Buy price: %s\n" ..
        "- Sell price: %s\n" ..
        "- Deposit cost: %s\n" ..
        "- Profit per item: %s\n" ..
        "- ROI: %.2f%%\n" ..
        "- Can buy: %d/%d",
        GetItemInfo(itemID) or itemID,
        GetCoinTextureString(bestDeal.buyPrice),
        GetCoinTextureString(bestDeal.sellPrice),
        GetCoinTextureString(bestDeal.deposit),
        GetCoinTextureString(bestDeal.profit),
        bestDeal.roi,
        buyQuantity,
        bestDeal.quantity
    ))
    
    return {
        numAuctions = 1,
        buyQuantity = buyQuantity,
        avgBuyPrice = bestDeal.buyPrice,
        sellPrice = bestDeal.sellPrice,
        deposit = bestDeal.deposit,
        totalProfit = bestDeal.profit * buyQuantity,
        profitPerItem = bestDeal.profit,
        roi = bestDeal.roi,
        currentInventory = currentInventory,
        maxInventory = maxInventory,
        saleRate = marketData.saleRate,
        totalAvailable = bestDeal.quantity
    }
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