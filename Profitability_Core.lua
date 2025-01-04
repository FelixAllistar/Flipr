local addonName, addon = ...
local FLIPR = addon.FLIPR

-- Main entry point for profitability analysis
function FLIPR:AnalyzeFlipOpportunity(results, itemID)
    if self.db.profile.useTSMMode then
        return self:AnalyzeFlipOpportunity_TSM(results, itemID)
    else
        return self:AnalyzeFlipOpportunity_Classic(results, itemID)
    end
end

-- Get sale rate from TSM (used by both modes)
function FLIPR:GetItemSaleRate(itemID)
    if not TSM_API then return 0 end
    local itemString = "i:" .. itemID
    -- Need to multiply by 1000 for sale rates according to TSM docs
    local saleRate = TSM_API.GetCustomPriceValue("DBRegionSaleRate*1000", itemString) or 0
    return saleRate / 1000
end

-- Categorize items by sale metrics (used by both modes)
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

-- Analyze market depth (used by both modes)
function FLIPR:AnalyzeMarketDepth(itemID)
    local itemString = "i:" .. itemID
    if not TSM_API then return nil end
    
    -- Get various price points
    local dbMarket = TSM_API.GetCustomPriceValue("DBMarket", itemString) or 0
    local dbMinBuyout = TSM_API.GetCustomPriceValue("DBMinBuyout", itemString) or 0
    local dbHistorical = TSM_API.GetCustomPriceValue("DBHistorical", itemString) or 0
    local avgDaily = TSM_API.GetCustomPriceValue("DBRegionSoldPerDay", itemString) or 0
    local numAuctions = TSM_API.GetCustomPriceValue("DBRegionMarketAvg", itemString) or 0
    
    -- Calculate market depth indicators
    local priceSpread = (dbMarket > 0) and ((dbMarket - dbMinBuyout) / dbMarket) or 0
    local volumeToListings = (numAuctions > 0) and (avgDaily / numAuctions) or 0
    
    return {
        priceSpread = priceSpread,           -- Higher spread indicates more price volatility
        volumeToListings = volumeToListings, -- Higher ratio means items sell through faster
        avgDailyVolume = avgDaily,
        currentListings = numAuctions,
        marketPrice = dbMarket,
        historicalPrice = dbHistorical
    }
end

-- Shared market analysis (used by both modes)
function FLIPR:AnalyzeMarketConditions(itemID)
    local itemString = "i:" .. itemID
    if not TSM_API then return nil end
    
    -- Get price sources
    local regionMarket = TSM_API.GetCustomPriceValue("DBRegionMarketAvg", itemString) or 0
    local localMarket = TSM_API.GetCustomPriceValue("DBMarket", itemString) or 0
    local historical = TSM_API.GetCustomPriceValue("DBHistorical", itemString) or 0
    
    -- Need to multiply by 1000 for sale rates according to TSM docs
    local saleRate = (TSM_API.GetCustomPriceValue("DBRegionSaleRate*1000", itemString) or 0) / 1000
    local soldPerDay = TSM_API.GetCustomPriceValue("DBRegionSoldPerDay", itemString) or 0
    
    -- Market stability check (avoid division by zero)
    local marketStability = 1
    if regionMarket > 0 then
        marketStability = localMarket / regionMarket
    end
    local isStableMarket = (marketStability >= 0.7 and marketStability <= 1.3)
    
    -- Historical price comparison (avoid division by zero)
    local historicalComparison = 1
    if historical > 0 then
        historicalComparison = localMarket / historical
    end
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

-- Calculate required ROI based on market conditions
function FLIPR:CalculateRequiredROI(marketData, itemID)
    -- Base ROI requirements from saved variables
    local baseROI = {
        HIGH_VOLUME = self.db.profile.highVolumeROI,
        MEDIUM_VOLUME = self.db.profile.mediumVolumeROI,
        LOW_VOLUME = self.db.profile.lowVolumeROI,
        VERY_LOW_VOLUME = self.db.profile.veryLowVolumeROI
    }
    
    local requiredROI = baseROI[marketData.saleCategory]
    
    -- Market volatility adjustment
    if not marketData.isStableMarket then
        local volatilityFactor = math.abs(1 - marketData.marketStability)
        requiredROI = requiredROI * (1 + volatilityFactor)
    end
    
    -- Historical price adjustment
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

-- Detect flash sale opportunities based on market data
function FLIPR:IsFlashSale(buyPrice, marketData)
    -- More aggressive for high volume items
    local discountThresholds = {
        HIGH_VOLUME = 0.7,     -- 30% discount needed
        MEDIUM_VOLUME = 0.6,   -- 40% discount needed
        LOW_VOLUME = 0.5,      -- 50% discount needed
        VERY_LOW_VOLUME = 0.4  -- 60% discount needed
    }
    
    local threshold = discountThresholds[marketData.saleCategory]
    local isSignificantDiscount = (buyPrice < marketData.localMarket * threshold)
    
    -- For very low volume items, require even steeper discounts if sale rate is extremely low
    if marketData.saleCategory == "VERY_LOW_VOLUME" and marketData.saleRate < 0.03 then
        return isSignificantDiscount and (buyPrice < marketData.localMarket * 0.3) -- 70% discount
    end
    
    return isSignificantDiscount
end 