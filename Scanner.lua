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
FLIPR.isThrottled = false

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
    if self.retryTimer then
        self.retryTimer:Cancel()
        self.retryTimer = nil
    end
    
    -- Don't start a new timer if we're paused
    if self.isPaused or self.shouldPauseAfterItem then
        print("|cFFFF0000PAUSED|r")
        self.isPaused = true
        self.isScanning = false
        self.shouldPauseAfterItem = false
        if self.scanButton then
            self.scanButton:SetText("Resume Scan")
        end
        return
    end
    
    -- Initialize retry state
    self.retryState = {
        itemID = itemID,
        retryCount = 0,
        isRetrying = true
    }
    
    -- Start retry timer
    self.retryTimer = C_Timer.NewTicker(1, function()
        -- Check if we should stop
        if not self.isScanning or self.isPaused then
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
        self.scanProgressText:SetText(string.format("Scanning: 0/%d items", #self.itemIDs))
    end
    
    -- Start timer
    self.scanStartTime = time()
    if self.timerFrame then
        self.timerFrame:Show()
    end

    -- Track current item being scanned
    self.currentScanIndex = 1

    -- Register for search results events if not already registered
    if not self.isEventRegistered then
        self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "OnCommoditySearchResults")
        self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", "OnItemSearchResults")
        self:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "OnThrottleResponse")
        self:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", function() self.isThrottled = true end)
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
    self.isThrottled = false
    if self.throttleTimer then
        self.throttleTimer:Cancel()
        self.throttleTimer = nil
    end
    -- Add a small delay after throttle response before continuing
    C_Timer.After(0.5, function()
        if self.isScanning and not self.isPaused then
            -- Don't increment currentScanIndex, retry the same item
            self:ScanNextItem()
        end
    end)
end

-- Helper function to create a basic search query
function FLIPR:CreateSearchQuery()
    return {
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
    }
end

function FLIPR:ScanNextItem()
    -- Check if scan was cancelled or paused
    if not self.isScanning or self.isPaused then
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

    -- Check if we're throttled
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        if not self.isThrottled then
            self.isThrottled = true
            print(string.format("|cFFFFFF00Throttled on item %d/%d, waiting...|r", 
                self.currentScanIndex, #self.itemIDs))
            
            -- Add safety timeout in case we miss the throttle response event
            if self.throttleTimer then
                self.throttleTimer:Cancel()
            end
            self.throttleTimer = C_Timer.NewTimer(5, function()
                print("|cFFFFFF00Throttle timeout reached, retrying item...|r")
                self.isThrottled = false
                self.throttleTimer = nil
                if self.isScanning and not self.isPaused then
                    -- Don't increment currentScanIndex, retry the same item
                    self:ScanNextItem()
                end
            end)
        end
        return -- Don't continue until we get the throttle response event or timeout
    end

    -- Continue with normal scanning
    if self.currentScanIndex <= #self.itemIDs then
        local itemID = self.itemIDs[self.currentScanIndex]
        
        -- Get item info
        local itemName = GetItemInfo(itemID)
        if not itemName then
            -- Queue item info request and retry
            local item = Item:CreateFromItemID(itemID)
            item:ContinueOnItemLoad(function()
                if self.isScanning and not self.isPaused then
                    self:ScanNextItem()
                end
            end)
            return
        end
        
        -- Update progress text
        self:UpdateScanProgress()
        
        -- Print scanning message
        print(string.format("|cFFFFFFFFScanning item %d/%d: %s (%d)|r", 
            self.currentScanIndex, #self.itemIDs, itemName, itemID))

        -- Check if item is a commodity using AH API
        local itemKey = C_AuctionHouse.MakeItemKey(itemID)
        if not itemKey then
            print(string.format("|cFFFF0000Failed to create item key for item ID: %d|r", itemID))
            self.currentScanIndex = self.currentScanIndex + 1
            self:UpdateScanProgress()
            self:ScanNextItem()
            return
        end

        local itemInfo = C_AuctionHouse.GetItemKeyInfo(itemKey)
        if not itemInfo then
            print(string.format("|cFFFF0000Failed to get item info for item ID: %d|r", itemID))
            self.currentScanIndex = self.currentScanIndex + 1
            self:UpdateScanProgress()
            self:ScanNextItem()
            return
        end
        
        -- Create basic query
        local query = self:CreateSearchQuery()
        
        -- Send appropriate search query
        if itemInfo.isCommodity then
            print(string.format("|cFF00FFFFItem is a commodity: %s|r", itemName))
            C_AuctionHouse.SendSearchQuery(itemKey, query, true, itemID)
        else
            print(string.format("|cFFFF00FFItem is NOT a commodity: %s|r", itemName))
            C_AuctionHouse.SendSearchQuery(itemKey, query, true)
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

function FLIPR:UpdateScanProgress()
    if self.scanProgressText then
        self.scanProgressText:SetText(string.format("%d/%d items", 
            self.currentScanIndex, #self.itemIDs))
    end
end

function FLIPR:OnCommoditySearchResults()
    -- Don't process events if we're paused
    if self.isPaused or self.shouldPauseAfterItem then
        return
    end

    local itemID = self.itemIDs[self.currentScanIndex]
    if not itemID then return end
    
    -- For commodities, request more results if needed
    if not C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
        if not C_AuctionHouse.IsThrottledMessageSystemReady() then
            if not self.isThrottled then
                self.isThrottled = true
                print("|cFFFFFF00Throttled while requesting more results, waiting...|r")
            end
            return -- Wait for throttle response event
        end
        print("Requesting more commodity results...")
        C_AuctionHouse.RequestMoreCommoditySearchResults(itemID)
        return
    end
    
    -- Process results only if we have full data
    local numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    local processedResults = {}
    
    if numResults and numResults > 0 then
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
    end
    
    if #processedResults > 0 then
        self:ProcessAuctionResults(processedResults)
    else
        print(string.format("|cFFFF8000NO AUCTIONS FOUND: %s|r", GetItemInfo(itemID) or itemID))
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
    self:UpdateScanProgress()
    self:ScanNextItem()
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
    local processedResults = {}
    
    if numResults and numResults > 0 then
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
    end
    
    if #processedResults > 0 then
        self:ProcessAuctionResults(processedResults)
    else
        print(string.format("|cFFFF8000NO AUCTIONS FOUND: %s|r", GetItemInfo(itemID) or itemID))
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
    self:UpdateScanProgress()
    self:ScanNextItem()
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
    
    -- Get sale rate for debug output
    local saleRate = self:GetItemSaleRate(itemID)
    
    -- Check inventory limits based on mode
    local maxInventory
    local currentInventory = self:GetCurrentInventory(itemID)
    
    if self.db.profile.useTSM then
        -- For TSM mode, get restock quantity from TSM operation
        local operation = self:GetTSMShoppingOperation(itemID)
        if not operation then
            print(string.format("|cFFFFFF00%s: No TSM operation found|r", itemName))
            return
        end
        maxInventory = operation.restockQuantity
    else
        -- For Classic mode, use our sale rate based limits
        maxInventory = self:GetMaxInventoryForSaleRate_Classic(itemID)
    end
    
    -- Skip if we're at or over inventory limit
    if currentInventory >= maxInventory then
        print(string.format("|cFFFFFF00%s: Full inventory %d/%d|r", itemName, currentInventory, maxInventory))
        return
    end
    
    -- Skip if first auction is too big
    if results[1].totalQuantity > (maxInventory - currentInventory) then
        print(string.format("|cFFFFFF00%s: First auction too big (%d), need %d or less|r", 
            itemName, results[1].totalQuantity, maxInventory - currentInventory))
        return
    end
    
    -- Use the correct analysis function based on mode
    local flipOpportunity
    if self.db.profile.useTSM then
        flipOpportunity = self:AnalyzeFlipOpportunity_TSM(results, itemID)
    else
        flipOpportunity = self:AnalyzeFlipOpportunity_Classic(results, itemID)
    end
    
    if flipOpportunity then
        -- Debug print in green for profitable items
        print(string.format(
            "|cFF00FF00Found flip for %s: Buy @ %s (x%d), Sell @ %s, Profit: %s, ROI: %d%%, Sale Rate: %s|r",
            itemName,
            C_CurrencyInfo.GetCoinTextureString(tonumber(flipOpportunity.avgBuyPrice) or 0),
            flipOpportunity.buyQuantity or 0,
            C_CurrencyInfo.GetCoinTextureString(tonumber(flipOpportunity.sellPrice) or 0),
            C_CurrencyInfo.GetCoinTextureString(tonumber(flipOpportunity.totalProfit) or 0),
            tonumber(flipOpportunity.roi) or 0,
            tostring(saleRate)
        ))
        
        -- Create UI row for profitable item using UI function
        self:CreateProfitableItemRow(flipOpportunity, results)
    else
        -- Debug print in yellow for unprofitable items
        print(string.format(
            "|cFFFFFF00No profitable flip found for %s (Sale Rate: %s)|r",
            itemName,
            tostring(saleRate)
        ))
    end

    -- Update scan progress
    if self.scanProgressText then
        self.scanProgressText:SetText(string.format("Scanning: %d/%d items", self.currentScanIndex, #self.itemIDs))
    end
end

function FLIPR:ClearScanSelections()
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

-- Add a function to cancel any pending timers
function FLIPR:CancelPendingScans()
    self.isScanning = false
    self.isThrottled = false
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

function FLIPR:OnScanComplete()
    self.isScanning = false
    self.isPaused = false
    
    -- Update UI
    if self.scanProgressText then
        self.scanProgressText:SetText("Scan Complete!")
    end
    if self.scanButton then
        self.scanButton:SetText("Scan Items")
    end
    
    -- Hide timer after 5 seconds
    C_Timer.After(5, function()
        if self.timerFrame then
            self.timerFrame:Hide()
        end
        if self.scanProgressText then
            self.scanProgressText:SetText("")
        end
    end)
end

function FLIPR:StartScan()
    -- If we're already scanning, this acts as a pause/resume toggle
    if self.isScanning then
        if self.isPaused then
            -- Resume scan
            print("|cFF00FF00RESUMED|r")
            self.isPaused = false
            if self.scanButton then
                self.scanButton:SetText("Pause Scan")
            end
            self:ScanNextItem()
        else
            -- Pause scan
            print("|cFFFF0000PAUSED|r")
            self.isPaused = true
            if self.scanButton then
                self.scanButton:SetText("Resume Scan")
            end
        end
        return
    end

    -- Start new scan
    self:ScanItems()
end
  