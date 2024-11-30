local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:GetItemSaleRate(itemID)
    -- Convert to TSM item string format
    local itemString = TSM_API.ToItemString("i:" .. itemID)
    if not itemString then return 0 end
    
    -- Get sale rate and convert from TSM's format
    local saleRate = TSM_API.GetCustomPriceValue("DBRegionSaleRate*1000", itemString)
    if not saleRate then return 0 end
    
    saleRate = tonumber(saleRate)
    if not saleRate then return 0 end
    
    return saleRate/1000
end

function FLIPR:GetMaxInventoryForSaleRate(itemID)
    local saleRate = self:GetItemSaleRate(itemID)
    
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

function FLIPR:AnalyzeFlipOpportunity(results, itemID)
    -- Initial checks...
    local itemData = self.itemDB[itemID]
    if not itemData then return nil end
    
    -- Get inventory limits using direct TSM sale rate
    local maxInventory = self:GetMaxInventoryForSaleRate(itemID)
    local currentInventory = self:GetCurrentInventory(itemID)
    local roomForMore = maxInventory - currentInventory
    
    -- Get current sale rate for debug output
    local saleRate = self:GetItemSaleRate(itemID)
    
    if roomForMore <= 0 then
        print(string.format(
            "|cFFFF0000Skipping %s - Already have %d/%d (Sale Rate: %s)|r",
            GetItemInfo(itemID) or itemID,
            currentInventory,
            maxInventory,
            tostring(saleRate)
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
    
    for i = 1, #results-1 do
        local buyPrice = results[i].minPrice
        local nextPrice = results[i+1].minPrice
        local quantity = results[i].totalQuantity
        
        -- Calculate deposit for posting duration (12 hours = 1, 24 hours = 2, 48 hours = 3)
        local deposit = self:CalculateDeposit(itemID, 1, quantity, isCommodity)
        
        -- Calculate potential profit including deposit cost
        local potentialProfit = (nextPrice * (1 - ahCut)) - (buyPrice + deposit)
        
        if potentialProfit > 0 then
            table.insert(profitableAuctions, {
                index = i,
                buyPrice = buyPrice,
                sellPrice = nextPrice,
                quantity = quantity,
                profit = potentialProfit,
                deposit = deposit
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
        "- Can buy: %d/%d",
        GetItemInfo(itemID) or itemID,
        GetCoinTextureString(bestDeal.buyPrice),
        GetCoinTextureString(bestDeal.sellPrice),
        GetCoinTextureString(bestDeal.deposit),
        GetCoinTextureString(bestDeal.profit),
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
        roi = (bestDeal.profit / bestDeal.buyPrice) * 100,
        currentInventory = currentInventory,
        maxInventory = maxInventory,
        saleRate = saleRate,
        totalAvailable = bestDeal.quantity
    }
end 