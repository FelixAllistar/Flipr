local addonName, addon = ...
local FLIPR = addon.FLIPR
local ROW_HEIGHT = 25

FLIPR.selectedRow = nil
FLIPR.selectedItem = nil
FLIPR.isScanning = false
FLIPR.isPaused = false
FLIPR.scanButton = nil
FLIPR.failedItems = {}
FLIPR.maxRetries = 3
FLIPR.retryDelay = 2 -- seconds
FLIPR.retryState = {
    itemID = nil,
    retryCount = 0,
    isRetrying = false
}
FLIPR.retryTimer = nil

function FLIPR:FormatGoldAndSilver(goldValue)
    local gold = math.floor(goldValue)
    local silver = math.floor((goldValue - gold) * 100)
    if silver > 0 then
        return string.format("%dg%ds", gold, silver)
    else
        return string.format("%dg", gold)
    end
end

function FLIPR:StartRetryCheck(itemID, itemKey)
    -- Clear any existing retry timer
    self.retryTimer = nil
    
    -- Initialize retry state
    self.retryState = {
        itemID = itemID,
        retryCount = 0,
        isRetrying = true
    }
    
    -- Start retry timer
    self.retryTimer = C_Timer.NewTicker(1, function()
        -- Check pause state first
        if self.isPaused or self.shouldPauseAfterItem then
            print("|cFFFF0000PAUSED|r")
            self.isPaused = true
            self.isScanning = false
            self.shouldPauseAfterItem = false
            if self.scanButton then
                self.scanButton:SetText("Resume Scan")
            end
            -- Cancel the timer
            if self.retryTimer then
                self.retryTimer:Cancel()
                self.retryTimer = nil
            end
            return
        end
        
        -- Check if AH is still open
        if not AuctionHouseFrame or not AuctionHouseFrame:IsVisible() then
            print("|cFFFF0000Auction House closed, stopping scan.|r")
            self.isScanning = false
            if self.scanButton then
                self.scanButton:SetText("Scan Items")
            end
            -- Cancel the timer
            if self.retryTimer then
                self.retryTimer:Cancel()
                self.retryTimer = nil
            end
            return
        end
        
        -- Check results
        local function checkResults()
            if C_AuctionHouse.HasFullCommoditySearchResults and C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
                local commodityResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
                if commodityResults and commodityResults > 0 then
                    return true
                end
            elseif C_AuctionHouse.HasFullCommoditySearchResults then
                return "waiting"
            end
            
            if itemKey then
                local itemResults = C_AuctionHouse.GetNumItemSearchResults(itemKey)
                if itemResults and itemResults > 0 then
                    return true
                end
            end
            
            return false
        end
        
        local hasResults = checkResults()
        if hasResults == true then
            -- Found results, process them
            if self.retryTimer then
                self.retryTimer:Cancel()
                self.retryTimer = nil
            end
            if itemKey then
                self:OnItemSearchResults()
            else
                self:OnCommoditySearchResults()
            end
        elseif hasResults == "waiting" and self.retryState.retryCount < 2 then
            -- Still waiting, increment retry count
            self.retryState.retryCount = self.retryState.retryCount + 1
            print(string.format("Still waiting for results for %s - Retry %d/3", GetItemInfo(itemID) or itemID, self.retryState.retryCount))
        else
            -- No results or max retries reached
            if self.retryTimer then
                self.retryTimer:Cancel()
                self.retryTimer = nil
            end
            print(string.format("|cFFFF8000NO AUCTIONS FOUND: %s|r", GetItemInfo(itemID) or itemID))
            if self.isScanning and not self.isPaused then
                self.currentScanIndex = self.currentScanIndex + 1
                C_Timer.After(0.5, function()
                    if self.isScanning and not self.isPaused then
                        self:ScanNextItem()
                    end
                end)
            end
        end
    end)
end

function FLIPR:DoubleCheckAuctions(itemID, itemKey, isRetry)
    -- If this is the first check, start the retry process
    if not isRetry then
        self:StartRetryCheck(itemID, itemKey)
        return "waiting"
    end
    return false
end

function FLIPR:ScanItems()
    -- If we're already scanning and not paused, set flag to pause after current item
    if self.isScanning and not self.isPaused then
        print("|cFFFF0000PAUSED|r")
        self.shouldPauseAfterItem = true
        self.isPaused = true  -- Set this immediately to stop event processing
        -- Update UI immediately
        if self.scanButton then
            self.scanButton:SetText("Resume Scan")
        end
        return
    -- If we're paused, resume scanning
    elseif self.isPaused then
        print("|cFF00FF00RESUMED|r")
        self.shouldPauseAfterItem = false
        self.isPaused = false
        -- Update UI immediately
        if self.scanButton then
            self.scanButton:SetText("Pause Scan")
        end
        -- Resume scanning from where we left off
        self:ScanNextItem()
        return
    end

    -- Check if Auction House is open
    if not AuctionHouseFrame or not AuctionHouseFrame:IsVisible() then
        print("|cFFFF0000Error: Please open the Auction House before scanning.|r")
        return
    end

    -- Cancel any pending scans before starting new one
    self:CancelPendingScans()

    -- Start new scan
    self.isScanning = true
    self.isPaused = false
    self.shouldPauseAfterItem = false  -- Initialize the flag
    if self.scanButton then
        self.scanButton:SetText("Pause Scan")
    end

    -- Get items from enabled groups
    self:UpdateScanItems()
    
    if #self.itemIDs == 0 then
        print("No groups selected!")
        self:CancelPendingScans()
        return
    end

    -- Update initial progress
    if self.scanProgressText then
        self.scanProgressText:SetText(string.format("0/%d items", #self.itemIDs))
    end

    -- Track current item being scanned
    self.currentScanIndex = 1

    -- Register for search results events if not already registered
    if not self.isEventRegistered then
        self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "OnCommoditySearchResults")
        self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", "OnItemSearchResults")
        self:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "OnThrottleResponse")
        self.isEventRegistered = true
    end

    -- Reset processed items tracking at start of new scan
    self.processedItems = {}
    self.failedItems = {}
    self.waitingForThrottle = false

    -- Start scanning first item
    self:ScanNextItem()
end

function FLIPR:OnThrottleResponse()
    if self.waitingForThrottle then
        self.waitingForThrottle = false
        -- Add a small delay after throttle response before continuing
        C_Timer.After(0.5, function()
            self:ScanNextItem()  -- Continue with the current item
        end)
    end
end

function FLIPR:ScanNextItem()
    -- Check if scan was cancelled
    if not self.isScanning then
        return
    end

    -- Check if Auction House is still open
    if not AuctionHouseFrame or not AuctionHouseFrame:IsVisible() then
        print("|cFFFF0000Error: Auction House was closed. Stopping scan.|r")
        self.isScanning = false
        if self.scanButton then
            self.scanButton:SetText("Scan Items")
        end
        return
    end

    -- Continue with normal scanning
    if self.currentScanIndex <= #self.itemIDs then
        local itemID = self.itemIDs[self.currentScanIndex]
        local itemData = self.itemDB[itemID]
        
        -- Check if we have data for this item
        if not itemData then
            print(string.format("|cFFFF0000Item %d not found in database, skipping|r", itemID))
            self.currentScanIndex = self.currentScanIndex + 1
            C_Timer.After(0.5, function() self:ScanNextItem() end)
            return
        end
        
        -- Always print scanning message first
        print(string.format("|cFFFFFFFFScanning item %d/%d: %s (%d)|r", 
            self.currentScanIndex, #self.itemIDs, itemData.name, itemID))

        -- Wait for throttle with a longer timeout
        if not C_AuctionHouse.IsThrottledMessageSystemReady() then
            local itemID = self.itemIDs[self.currentScanIndex]
            local itemInfo = itemID and C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
            
            -- Wait even longer if it's a commodity
            local waitTime = (itemInfo and itemInfo.isCommodity) and 15 or 10
            print(string.format("Throttled, waiting %ds...", waitTime))
            C_Timer.After(waitTime, function() self:ScanNextItem() end)
            return
        end

        -- Update progress text
        if self.scanProgressText then
            self.scanProgressText:SetText(string.format("%d/%d items", 
                self.currentScanIndex, #self.itemIDs))
        end

        -- Check if item is a commodity using AH API
        local itemKey = C_AuctionHouse.MakeItemKey(itemID)
        if not itemKey then
            print(string.format("|cFFFF0000Failed to create item key for item ID: %d|r", itemID))
            -- Add to failed items and retry later
            if not self.failedItems[itemID] then
                self.failedItems[itemID] = 0
            end
            self.failedItems[itemID] = self.failedItems[itemID] + 1
            
            if self.failedItems[itemID] <= self.maxRetries then
                print(string.format("Retry %d/%d for item %d", self.failedItems[itemID], self.maxRetries, itemID))
                C_Timer.After(2, function() self:ScanNextItem() end)
            else
                print(string.format("|cFFFF0000Max retries reached for item %d, skipping|r", itemID))
                self.currentScanIndex = self.currentScanIndex + 1
                C_Timer.After(0.5, function() self:ScanNextItem() end)
            end
            return
        end

        local itemInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
        if not itemInfo then
            print(string.format("|cFFFF0000Failed to get item info for item ID: %d|r", itemID))
            -- Add to failed items and retry later
            if not self.failedItems[itemID] then
                self.failedItems[itemID] = 0
            end
            self.failedItems[itemID] = self.failedItems[itemID] + 1
            
            if self.failedItems[itemID] <= self.maxRetries then
                print(string.format("Retry %d/%d for item %d", self.failedItems[itemID], self.maxRetries, itemID))
                C_Timer.After(2, function() self:ScanNextItem() end)
            else
                print(string.format("|cFFFF0000Max retries reached for item %d, skipping|r", itemID))
                self.currentScanIndex = self.currentScanIndex + 1
                C_Timer.After(0.5, function() self:ScanNextItem() end)
            end
            return
        end
        
        -- Debug print commodity status
        if itemInfo.isCommodity then
            print(string.format("|cFF00FFFFItem is a commodity: %s|r", itemData.name))
            -- For commodities, use specific commodity search
            C_AuctionHouse.SendSearchQuery(itemKey, {
                searchString = "",
                minLevel = 0,
                maxLevel = 0,
                filters = {},
                itemClassFilters = {},
                sorts = {},
                separateOwnerItems = false,
                exactMatch = false,
                isFavorite = false,
                allowFavorites = true,
                onlyUsable = false
            }, true)
        else
            print(string.format("|cFFFF00FFItem is NOT a commodity: %s|r", itemData.name))
            -- For regular items, use item search
            C_AuctionHouse.SendSearchQuery(itemKey, {
                searchString = "",
                minLevel = 0,
                maxLevel = 0,
                filters = {},
                itemClassFilters = {},
                sorts = {},
                separateOwnerItems = false,
                exactMatch = false,
                isFavorite = false,
                allowFavorites = true,
                onlyUsable = false
            }, true)
        end
    else
        -- Scan complete
        self.isScanning = false
        if self.scanButton then
            self.scanButton:SetText("Scan Items")
        end
        
        if self.scanProgressText then
            self.scanProgressText:SetText("Complete!")
            C_Timer.After(2, function()
                if not self.isScanning then
                    self.scanProgressText:SetText("")
                end
            end)
        end
        
        if self.isEventRegistered then
            self:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
            self:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
            self.isEventRegistered = false
        end
    end
end

function FLIPR:OnCommoditySearchResults()
    -- Don't process events if we're paused
    if self.isPaused or self.shouldPauseAfterItem then
        return
    end

    local itemID = self.itemIDs[self.currentScanIndex]
    if not itemID then return end
    
    -- For commodities, ALWAYS wait for full results
    if not C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
        print("Waiting for full commodity results...")
        C_Timer.After(1, function()
            C_AuctionHouse.RequestMoreCommoditySearchResults(itemID)
        end)
        return
    end
    
    -- First check if we have any results at all
    local numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    if not numResults or numResults == 0 then
        -- For commodities, do an extra thorough check
        if not self.commodityRetries then
            self.commodityRetries = {}
        end
        
        if not self.commodityRetries[itemID] then
            self.commodityRetries[itemID] = 0
        end
        
        self.commodityRetries[itemID] = self.commodityRetries[itemID] + 1
        
        if self.commodityRetries[itemID] <= 3 then  -- Try up to 3 times
            print(string.format("Commodity retry %d/3 for %s", self.commodityRetries[itemID], GetItemInfo(itemID) or itemID))
            -- Wait longer for commodities
            C_Timer.After(3, function()
                -- Resend the search query
                local itemKey = C_AuctionHouse.MakeItemKey(itemID)
                C_AuctionHouse.SendSearchQuery(itemKey, {
                    searchString = "",
                    minLevel = 0,
                    maxLevel = 0,
                    filters = {},
                    itemClassFilters = {},
                    sorts = {},
                    separateOwnerItems = false,
                    exactMatch = false,
                    isFavorite = false,
                    allowFavorites = true,
                    onlyUsable = false
                }, true)
            end)
            return
        end
        
        -- If we've tried enough times and still no results
        print(string.format("|cFFFF8000NO AUCTIONS FOUND: %s|r", GetItemInfo(itemID) or itemID))
        self.currentScanIndex = self.currentScanIndex + 1
        -- Clear retry counter for this item
        self.commodityRetries[itemID] = nil
        C_Timer.After(0.5, function() self:ScanNextItem() end)
        return
    end

    -- Process results only if we have full data
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    if not itemInfo then 
        self.currentScanIndex = self.currentScanIndex + 1
        C_Timer.After(0.5, function() self:ScanNextItem() end)
        return 
    end
    
    local processedResults = {}
    for i = 1, numResults do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if result then
            table.insert(processedResults, {
                itemName = GetItemInfo(itemID),
                minPrice = result.unitPrice,
                totalQuantity = result.quantity,
                itemID = itemID,
                isCommodity = true
            })
        end
    end
    
    if #processedResults > 0 then
        -- Clear retry counter on success
        if self.commodityRetries then
            self.commodityRetries[itemID] = nil
        end
        self:ProcessAuctionResults(processedResults)
    end
    
    -- Check if we should pause after this item
    if self.shouldPauseAfterItem then
        self.isPaused = true
        self.isScanning = false
        self.shouldPauseAfterItem = false  -- Clear the flag
        if self.scanButton then
            self.scanButton:SetText("Resume Scan")
        end
        return
    end
    
    -- Move to next item if not pausing
    self.currentScanIndex = self.currentScanIndex + 1
    C_Timer.After(0.5, function() self:ScanNextItem() end)
end

function FLIPR:OnItemSearchResults()
    -- Don't process events if we're paused
    if self.isPaused or self.shouldPauseAfterItem then
        return
    end

    local itemID = self.itemIDs[self.currentScanIndex]
    if not itemID then return end
    
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local numResults = C_AuctionHouse.GetNumItemSearchResults(itemKey)
    
    if not numResults or numResults == 0 then
        -- Double check before giving up
        local checkResult = self:DoubleCheckAuctions(itemID, itemKey)
        if checkResult == "waiting" then
            return -- Will retry from DoubleCheckAuctions
        elseif not checkResult then
            print(string.format("|cFFFF8000NO AUCTIONS FOUND: %s|r", GetItemInfo(itemID) or itemID))
            self.currentScanIndex = self.currentScanIndex + 1
            C_Timer.After(0.5, function() self:ScanNextItem() end)
            return
        end
    end

    local processedResults = {}
    for i = 1, numResults do
        local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if result then
            table.insert(processedResults, {
                itemName = GetItemInfo(itemID),
                minPrice = result.buyoutAmount or result.bidAmount,
                totalQuantity = 1,
                itemID = itemID,
                auctionID = result.auctionID,
                isCommodity = false
            })
        end
    end
    
    if #processedResults > 0 then
        self:ProcessAuctionResults(processedResults)
    end
    
    -- Check if we should pause after this item
    if self.shouldPauseAfterItem then
        self.isPaused = true
        self.isScanning = false
        self.shouldPauseAfterItem = false  -- Clear the flag
        if self.scanButton then
            self.scanButton:SetText("Resume Scan")
        end
        return
    end
    
    -- Move to next item if not pausing
    self.currentScanIndex = self.currentScanIndex + 1
    C_Timer.After(0.5, function() self:ScanNextItem() end)
end

function FLIPR:ProcessAuctionResults(results)
    if not results or #results == 0 then return end
    
    local itemID = results[1].itemID
    if not itemID then return end
    
    -- Wait for item info to be available
    local itemName = GetItemInfo(itemID)
    if not itemName then
        local item = Item:CreateFromItemID(itemID)
        item:ContinueOnItemLoad(function()
            self:ProcessAuctionResults(results)
        end)
        return
    end
    
    -- Debug print for database lookup
    local itemData = self.itemDB[itemID]
    if not itemData then 
        print(string.format("|cFFFF0000No item data found in database for: %s (ID: %d)|r", itemName, itemID))
        return 
    end
    
    -- Analyze flip opportunity
    local flipOpportunity = self:AnalyzeFlipOpportunity(results, itemID)
    if flipOpportunity then
        -- Debug print in green for profitable items
        print(string.format(
            "|cFF00FF00Found flip for %s: Buy @ %s (x%d), Sell @ %s, Profit: %s, ROI: %d%%, Sale Rate: %.1f%%|r",
            itemName,
            GetCoinTextureString(flipOpportunity.avgBuyPrice),
            flipOpportunity.buyQuantity,
            GetCoinTextureString(flipOpportunity.sellPrice),
            GetCoinTextureString(flipOpportunity.totalProfit),
            flipOpportunity.roi,
            itemData.saleRate * 100
        ))
        
        -- Create UI row for profitable item
        self:CreateProfitableItemRow(flipOpportunity, results)
    else
        -- Debug print in yellow for unprofitable items
        print(string.format(
            "|cFFFFFF00No profitable flip found for %s (Sale Rate: %.1f%%)|r",
            itemName,
            itemData.saleRate * 100
        ))
    end
end

function FLIPR:ClearAllSelections()
    -- Clear previous selection if it exists
    if self.selectedRow then
        self.selectedRow.itemData.selected = false
        self.selectedRow.selectionTexture:Hide()
        self.selectedRow.defaultBg:Show()
        
        -- Clear dropdown selections if they exist
        if self.selectedRow.dropDown then
            for _, dropChild in pairs({self.selectedRow.dropDown:GetChildren()}) do
                if dropChild.selectionTexture then
                    dropChild.selectionTexture:Hide()
                end
            end
        end
    end
    
    self.selectedRow = nil
    self.selectedItem = nil
end

function FLIPR:GetMaxInventoryForSaleRate(saleRate)
    if saleRate >= 0.4 then
        return 100  -- High sale rate (40%+) - can hold up to 100
    elseif saleRate >= 0.2 then
        return 10   -- Medium sale rate (20-39%) - can hold up to 10
    else
        return 5    -- Low sale rate (<20%) - only hold 5 max
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

function FLIPR:AnalyzeFlipOpportunity(results, itemID)
    -- Initial checks...
    local itemData = self.itemDB[itemID]
    if not itemData then return nil end
    
    -- Get inventory limits first
    local maxInventory = self:GetMaxInventoryForSaleRate(itemData.saleRate)
    local currentInventory = self:GetCurrentInventory(itemID)
    local roomForMore = maxInventory - currentInventory
    
    if roomForMore <= 0 then
        print(string.format(
            "|cFFFF0000Skipping %s - Already have %d/%d (Sale Rate: %.1f%%)|r",
            GetItemInfo(itemID) or itemID,
            currentInventory,
            maxInventory,
            itemData.saleRate * 100
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
    
    -- Find profitable auctions
    local profitableAuctions = {}
    local currentPrice = results[1].minPrice
    local deposit = 0  -- TODO: Calculate actual deposit
    local ahCut = 0.05  -- 5% AH fee
    
    for i = 1, #results-1 do
        local buyPrice = results[i].minPrice
        local nextPrice = results[i+1].minPrice
        local potentialProfit = (nextPrice * (1 - ahCut)) - (buyPrice + deposit)
        
        if potentialProfit > 0 then
            table.insert(profitableAuctions, {
                index = i,
                buyPrice = buyPrice,
                sellPrice = nextPrice,
                quantity = results[i].totalQuantity,
                profit = potentialProfit
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
    
    -- Debug output
    print(string.format(
        "Analysis for %s:\n" ..
        "- Buy price: %s\n" ..
        "- Sell price: %s\n" ..
        "- Profit per item: %s\n" ..
        "- Can buy: %d/%d",
        GetItemInfo(itemID) or itemID,
        GetCoinTextureString(bestDeal.buyPrice),
        GetCoinTextureString(bestDeal.sellPrice),
        GetCoinTextureString(bestDeal.profit),
        buyQuantity,
        bestDeal.quantity
    ))
    
    return {
        numAuctions = 1,  -- We're only buying from one price point at a time
        buyQuantity = buyQuantity,
        avgBuyPrice = bestDeal.buyPrice,
        sellPrice = bestDeal.sellPrice,
        totalProfit = bestDeal.profit * buyQuantity,
        profitPerItem = bestDeal.profit,
        roi = (bestDeal.profit / bestDeal.buyPrice) * 100,
        currentInventory = currentInventory,
        maxInventory = maxInventory,
        saleRate = itemData.saleRate,
        totalAvailable = bestDeal.quantity
    }
end

function FLIPR:RemoveItemRow(itemID)
    if not self.scrollChild then return end
    
    -- Find and remove the row for this item
    for _, child in pairs({self.scrollChild:GetChildren()}) do
        if child.itemData and child.itemData.itemID == itemID then
            child:Hide()
            child:SetParent(nil)
            
            -- Decrease profitable items count
            self.profitableItemCount = (self.profitableItemCount or 1) - 1
            
            -- Reposition remaining rows
            local yOffset = 0
            for _, remainingChild in pairs({self.scrollChild:GetChildren()}) do
                if remainingChild:IsShown() then
                    remainingChild:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -yOffset)
                    yOffset = yOffset + ROW_HEIGHT
                end
            end
            
            -- Update scroll child height
            self.scrollChild:SetHeight(math.max(1, self.profitableItemCount * ROW_HEIGHT))
            break
        end
    end
end

function FLIPR:BuyItem(itemData)
    -- ... existing purchase code ...
    
    -- After successful purchase:
    self:RemoveItemRow(itemData.itemID)
    
    -- Rescan this item
    local itemKey = C_AuctionHouse.MakeItemKey(itemData.itemID)
    if itemData.isCommodity then
        C_AuctionHouse.SendSearchQuery(nil, {}, true, itemData.itemID)
    else
        C_AuctionHouse.SendSearchQuery(itemKey, {}, true)
    end
end

function FLIPR:RescanSingleItem(itemID)
    if not itemID then
        print("Error: No itemID provided to RescanSingleItem")
        return
    end

    -- Clear any existing data for this item
    self:RemoveItemRow(itemID)
    
    -- Get item class to determine if it's a commodity
    local _, _, _, _, _, itemClass = GetItemInfo(itemID)
    local isCommodity = (
        itemClass == Enum.ItemClass.Consumable or
        itemClass == Enum.ItemClass.Reagent or
        itemClass == Enum.ItemClass.TradeGoods or
        itemClass == Enum.ItemClass.Recipe
    )
    
    -- Debug output
    print("Rescanning item:", itemID, "IsCommodity:", isCommodity)
    
    -- Send appropriate search query
    if isCommodity then
        C_AuctionHouse.SendSearchQuery(nil, {}, true, itemID)
    else
        local itemKey = C_AuctionHouse.MakeItemKey(itemID)
        if itemKey then
            C_AuctionHouse.SendSearchQuery(itemKey, {}, true)
        else
            print("Error: Failed to create item key for", itemID)
        end
    end
end

function FLIPR:CreateProfitableItemRow(flipOpportunity, results)
    -- Play sound for profitable item
    PlaySoundFile("Interface\\AddOns\\FLIPR\\sounds\\VO_GoblinVenM_Greeting06.ogg", "Master")
    
    -- Create or get profitable items counter
    if not self.profitableItemCount then
        self.profitableItemCount = 0
    end
    self.profitableItemCount = self.profitableItemCount + 1

    -- Create row container
    local rowContainer = CreateFrame("Frame", nil, self.scrollChild)
    rowContainer:SetSize(self.scrollChild:GetWidth(), ROW_HEIGHT)
    
    -- Position based on profitable items count
    rowContainer:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -((self.profitableItemCount - 1) * ROW_HEIGHT))
    self.scrollChild:SetHeight(self.profitableItemCount * ROW_HEIGHT)

    -- Main row
    local row = CreateFrame("Button", nil, rowContainer)
    row:SetAllPoints(rowContainer)
    
    -- Default background
    local defaultBg = row:CreateTexture(nil, "BACKGROUND")
    defaultBg:SetAllPoints()
    defaultBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    row.defaultBg = defaultBg
    
    -- Selection background
    local selection = row:CreateTexture(nil, "BACKGROUND")
    selection:SetAllPoints()
    selection:SetColorTexture(0.7, 0.7, 0.1, 0.2)
    selection:Hide()
    row.selectionTexture = selection

    -- Item name (left-aligned)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetText(results[1].itemName)
    nameText:SetWidth(150)  -- Fixed width for name
    
    -- Price text (center-aligned)
    local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priceText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
    priceText:SetText(GetCoinTextureString(flipOpportunity.avgBuyPrice))
    
    -- Stock text
    local stockText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stockText:SetPoint("LEFT", priceText, "RIGHT", 10, 0)
    stockText:SetText(string.format("Stock: %d/%d", flipOpportunity.currentInventory, flipOpportunity.maxInventory))
    
    -- Sale Rate text
    local saleRateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    saleRateText:SetPoint("LEFT", stockText, "RIGHT", 10, 0)
    saleRateText:SetText(string.format("Sale Rate: %.1f%%", flipOpportunity.saleRate * 100))
    
    -- Profit text with ROI
    local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontGreen")
    profitText:SetPoint("LEFT", saleRateText, "RIGHT", 10, 0)
    profitText:SetText(string.format(
        "Profit: %s (%d%% ROI)",
        GetCoinTextureString(flipOpportunity.totalProfit),
        flipOpportunity.roi
    ))

    -- Store auction data with the row
    row.itemData = {
        itemID = results[1].itemID,
        minPrice = results[1].minPrice,
        totalQuantity = results[1].totalQuantity,
        auctionID = results[1].auctionID,
        isCommodity = results[1].isCommodity,
        selected = false,
        allAuctions = results  -- Store all auctions for this item
    }

    -- Click handler for row selection
    row:SetScript("OnClick", function()
        -- Clear previous selection
        if self.selectedRow and self.selectedRow ~= row then
            self.selectedRow.itemData.selected = false
            self.selectedRow.selectionTexture:Hide()
            self.selectedRow.defaultBg:Show()
            if self.selectedRow.dropDown then
                self.selectedRow.dropDown:Hide()
            end
        end

        -- Toggle selection
        row.itemData.selected = not row.itemData.selected
        row.selectionTexture:SetShown(row.itemData.selected)
        row.defaultBg:SetShown(not row.itemData.selected)
        
        -- Update selected item
        if row.itemData.selected then
            self.selectedRow = row
            self.selectedItem = row.itemData
        else
            self.selectedRow = nil
            self.selectedItem = nil
        end
    end)
end

-- Add a function to cancel any pending timers
function FLIPR:CancelPendingScans()
    self.isScanning = false
    -- Cancel retry timer if it exists
    if self.retryTimer then
        self.retryTimer:Cancel()
        self.retryTimer = nil
    end
    if self.scanButton then
        self.scanButton:SetText("Scan Items")
    end
    if self.scanProgressText then
        self.scanProgressText:SetText("")
    end
end

function FLIPR:OnAuctionHouseClosed()
    self:CancelPendingScans()
end
  