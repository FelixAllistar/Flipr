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

function FLIPR:ScanItems()
    -- If paused, resume scanning
    if self.isPaused then
        self.isPaused = false
        self.isScanning = true
        if self.scanButton then
            self.scanButton:SetText("Pause Scan")
            self.scanButton.buttonText:SetText("Pause Scan")
        end
        self:ScanNextItem()
        return
    end

    -- If scanning, pause it
    if self.isScanning then
        self.isPaused = true
        self.isScanning = false
        if self.scanButton then
            self.scanButton:SetText("Resume Scan")
            self.scanButton.buttonText:SetText("Resume Scan")
        end
        return
    end

    -- Start new scan
    self.isScanning = true
    self.isPaused = false
    if self.scanButton then
        self.scanButton:SetText("Pause Scan")
        self.scanButton.buttonText:SetText("Pause Scan")
    end

    -- Get items from enabled groups
    self:UpdateScanItems()
    
    if #self.itemIDs == 0 then
        print("No groups selected!")
        self.isScanning = false
        if self.scanButton then
            self.scanButton:SetText("Scan Items")
            self.scanButton.buttonText:SetText("Scan Items")
        end
        if self.scanProgressText then
            self.scanProgressText:SetText("")
        end
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
        self.isEventRegistered = true
    end

    -- Start scanning first item
    self:ScanNextItem()
end

function FLIPR:ScanNextItem()
    -- Check if scan was cancelled
    if not self.isScanning then
        return
    end

    -- First handle any failed items that need retry
    if self.failedItems and #self.failedItems > 0 then
        local failedItem = self.failedItems[1]
        if not failedItem or not failedItem.itemID then
            tremove(self.failedItems, 1)
            C_Timer.After(0.1, function() self:ScanNextItem() end)
            return
        end
        
        -- Wait for throttle
        if not C_AuctionHouse.IsThrottledMessageSystemReady() then
            C_Timer.After(0.5, function() self:ScanNextItem() end)
            return
        end

        -- Only remove and process if we're ready to send query
        if failedItem.retries < self.maxRetries then
            tremove(self.failedItems, 1)
            failedItem.retries = failedItem.retries + 1
            
            if failedItem.isCommodity then
                pcall(function()
                    C_AuctionHouse.SendSearchQuery(nil, {}, true, failedItem.itemID)
                end)
            else
                local itemKey = C_AuctionHouse.MakeItemKey(failedItem.itemID)
                if itemKey then
                    pcall(function()
                        C_AuctionHouse.SendSearchQuery(itemKey, {}, true)
                    end)
                end
            end
            return
        else
            tremove(self.failedItems, 1)
        end
        
        C_Timer.After(0.1, function() self:ScanNextItem() end)
        return
    end

    -- Continue with normal scanning
    if self.currentScanIndex <= #self.itemIDs then
        -- Wait for throttle
        if not C_AuctionHouse.IsThrottledMessageSystemReady() then
            C_Timer.After(0.5, function() self:ScanNextItem() end)
            return
        end

        local itemID = self.itemIDs[self.currentScanIndex]
        print("Scanning item:", itemID)

        -- Wait for item info to be available
        local itemName, _, _, _, _, itemClass = GetItemInfo(itemID)
        if not itemName then
            local item = Item:CreateFromItemID(itemID)
            item:ContinueOnItemLoad(function()
                self:ScanNextItem()
            end)
            return
        end

        -- Check if item is likely a commodity
        local isCommodity = (
            itemClass == Enum.ItemClass.Consumable or
            itemClass == Enum.ItemClass.Reagent or
            itemClass == Enum.ItemClass.TradeGoods or
            itemClass == Enum.ItemClass.Recipe
        )
        
        -- Increment scan index before sending query
        self.currentScanIndex = self.currentScanIndex + 1
        
        if isCommodity then
            C_AuctionHouse.SendSearchQuery(nil, {}, true, itemID)
        else
            local itemKey = C_AuctionHouse.MakeItemKey(itemID)
            C_AuctionHouse.SendSearchQuery(itemKey, {}, true)
        end
    else
        -- Scan complete
        self.isScanning = false
        if self.scanButton then
            self.scanButton:SetText("Scan Items")
            self.scanButton.buttonText:SetText("Scan Items")
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
    local itemID = self.itemIDs[self.currentScanIndex - 1]
    if not itemID then return end
    
    -- First check if we have any results at all
    local numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    if not numResults or numResults == 0 then
        -- Add to retry queue
        table.insert(self.failedItems, {
            itemID = itemID,
            isCommodity = true,
            retries = 0
        })
        C_Timer.After(self.retryDelay, function()
            self:ScanNextItem()
        end)
        return
    end

    -- Check if we have all results yet
    if not C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
        print("Requesting more results for item:", itemID)
        C_AuctionHouse.RequestMoreCommoditySearchResults(itemID)
        return  -- Wait for another COMMODITY_SEARCH_RESULTS_UPDATED event
    end

    local itemInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    if not itemInfo or not itemInfo.isCommodity then
        return
    end
    
    print("Processing all results for item:", itemID)
    local processedResults = {}
    for i = 1, numResults do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if result then
            table.insert(processedResults, {
                itemName = GetItemInfo(itemID),
                minPrice = result.unitPrice,
                totalQuantity = result.quantity,
                itemID = itemID
            })
        end
    end
    
    self:ProcessAuctionResults(processedResults)
    self:ScanNextItem()
end

function FLIPR:OnItemSearchResults()
    -- Get the current item ID from the previous scan index since we incremented already
    local itemID = self.itemIDs[self.currentScanIndex - 1]
    if not itemID then return end
    
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local numResults = C_AuctionHouse.GetNumItemSearchResults(itemKey)
    
    if not numResults or numResults == 0 then
        -- Add to retry queue
        table.insert(self.failedItems, {
            itemID = itemID,
            isCommodity = false,
            retries = 0
        })
        C_Timer.After(self.retryDelay, function()
            self:ScanNextItem()
        end)
        return
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
                auctionID = result.auctionID
            })
        end
    end
    self:ProcessAuctionResults(processedResults)
    self:ScanNextItem()
end

function FLIPR:ProcessAuctionResults(results)
    local itemID = self.itemIDs[self.currentScanIndex - 1]
    local itemName = GetItemInfo(itemID)
    
    if not itemName then return end

    -- Analyze flip opportunity first
    local flipOpportunity = nil
    if results and #results > 1 then
        flipOpportunity = self:AnalyzeFlipOpportunity(results, itemID)
    end

    -- Only proceed if profitable
    if flipOpportunity then
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
        nameText:SetText(itemName)
        nameText:SetWidth(150)  -- Fixed width for name
        
        -- Price text (center-aligned)
        local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        priceText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
        priceText:SetText(GetCoinTextureString(flipOpportunity.avgBuyPrice))
        
        -- Profit text (right-aligned)
        local profitText = row:CreateFontString(nil, "OVERLAY", "GameFontGreen")
        profitText:SetPoint("LEFT", priceText, "RIGHT", 10, 0)
        profitText:SetText(string.format(
            "Profit: %s (%d%% ROI) - Stock: %d/%d",
            GetCoinTextureString(flipOpportunity.totalProfit),
            flipOpportunity.roi,
            flipOpportunity.currentInventory,
            flipOpportunity.maxInventory
        ))

        -- Store all auction data with the row
        row.itemData = {
            itemID = itemID,
            minPrice = results[1].minPrice,
            totalQuantity = results[1].totalQuantity,
            auctionID = results[1].auctionID,
            selected = false,
            allAuctions = results  -- Store all auctions for this item
        }

        -- Click handler for dropdown functionality
        row:SetScript("OnClick", function()
            -- Clear any previous selections
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
            
            -- Create or toggle dropdown
            if row.itemData.selected then
                if not row.dropDown then
                    -- Create dropdown for additional auctions
                    local dropDown = CreateFrame("Frame", nil, row)
                    dropDown:SetFrameStrata("DIALOG")
                    dropDown:SetSize(row:GetWidth(), ROW_HEIGHT * (#results - 1))
                    dropDown:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
                    
                    -- Create dropdown rows...
                    -- (Previous dropdown creation code here)
                    
                    row.dropDown = dropDown
                end
                row.dropDown:Show()
                self.selectedRow = row
                self.selectedItem = row.itemData
            else
                if row.dropDown then
                    row.dropDown:Hide()
                end
                self.selectedRow = nil
                self.selectedItem = nil
            end
        end)
    end

    -- Update progress text
    if self.scanProgressText then
        self.scanProgressText:SetText(string.format("%d/%d items", self.currentScanIndex, #self.itemIDs))
    end

    -- Queue next scan
    self.currentScanIndex = self.currentScanIndex + 1
    if self.currentScanIndex <= #self.itemIDs then
        C_Timer.After(0.5, function() self:ScanNextItem() end)
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
    -- Get total count across bags and bank
    -- true = include bank, nil = don't include charges
    return GetItemCount(itemID, true)
end

function FLIPR:AnalyzeFlipOpportunity(results, itemID)
    -- Debug prints
    if not self.itemDB then
        print("Error: itemDB is nil!")
        return nil
    end
    
    -- Get item data from our database
    local itemData = self.itemDB[itemID]
    if not itemData then 
        print("Warning: No data found for item", itemID)
        return nil 
    end
    
    -- Get current inventory and max allowed based on sale rate
    local currentInventory = self:GetCurrentInventory(itemID)
    local maxInventory = self:GetMaxInventoryForSaleRate(itemData.saleRate)
    
    -- If we're already at or above max inventory, skip this item
    if currentInventory >= maxInventory then
        return nil
    end
    
    local bestProfit = 0
    local bestSplit = nil
    
    -- Calculate how many more we can buy
    local roomForMore = maxInventory - currentInventory
    
    -- Try different split points
    for split = 1, #results-1 do
        -- Calculate average buy price for items up to split
        local totalBuyCost = 0
        local totalBuyQuantity = 0
        
        for i = 1, split do
            totalBuyCost = totalBuyCost + (results[i].minPrice * results[i].totalQuantity)
            totalBuyQuantity = totalBuyQuantity + results[i].totalQuantity
        end
        
        -- Skip if we'd be buying more than we have room for
        if totalBuyQuantity > roomForMore then
            -- If possible, adjust quantity to just buy what we have room for
            if split == 1 then
                totalBuyQuantity = roomForMore
                totalBuyCost = (totalBuyCost / results[1].totalQuantity) * roomForMore
            else
                break
            end
        end
        
        local avgBuyPrice = totalBuyCost / totalBuyQuantity
        
        -- Calculate potential sell price (minimum price after our split)
        local sellPrice = results[split + 1].minPrice * 0.95 -- Account for AH cut
        
        -- Calculate potential profit
        local profitPerItem = sellPrice - avgBuyPrice
        local totalProfit = profitPerItem * totalBuyQuantity
        
        -- If this split is more profitable, store it
        if totalProfit > bestProfit then
            bestProfit = totalProfit
            bestSplit = {
                numAuctions = split,
                buyQuantity = totalBuyQuantity,
                avgBuyPrice = avgBuyPrice,
                sellPrice = sellPrice,
                totalProfit = totalProfit,
                profitPerItem = profitPerItem,
                roi = (profitPerItem / avgBuyPrice) * 100,
                currentInventory = currentInventory,
                maxInventory = maxInventory,
                saleRate = itemData.saleRate
            }
        end
    end
    
    -- Only return opportunities with meaningful profit and ROI
    if bestSplit and bestSplit.roi >= 20 then -- Minimum 20% ROI
        return bestSplit
    end
    
    return nil
end 