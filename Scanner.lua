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
    if not itemID then 
        -- This might be a rescan of a specific item
        itemID = self.selectedItem and self.selectedItem.itemID
        if not itemID then return end
    end
    
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
    local itemID = self.itemIDs[self.currentScanIndex - 1]
    if not itemID then 
        -- This might be a rescan of a specific item
        itemID = self.selectedItem and self.selectedItem.itemID
        if not itemID then return end
    end
    
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
                    
                    -- Dropdown background
                    local dropBg = dropDown:CreateTexture(nil, "BACKGROUND")
                    dropBg:SetAllPoints()
                    dropBg:SetColorTexture(0.1, 0.1, 0.1, 0.95)
                    
                    -- Create rows for additional auctions
                    for i = 1, #results do
                        local dropRow = CreateFrame("Button", nil, dropDown)
                        dropRow:SetSize(dropDown:GetWidth(), ROW_HEIGHT)
                        dropRow:SetPoint("TOPLEFT", dropDown, "TOPLEFT", 0, -(i-1) * ROW_HEIGHT)
                        
                        -- Background for dropdown row
                        local dropRowBg = dropRow:CreateTexture(nil, "BACKGROUND")
                        dropRowBg:SetAllPoints()
                        dropRowBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
                        dropRow.defaultBg = dropRowBg
                        
                        -- Selection texture for dropdown row
                        local dropRowSelection = dropRow:CreateTexture(nil, "BACKGROUND")
                        dropRowSelection:SetAllPoints()
                        dropRowSelection:SetColorTexture(0.7, 0.7, 0.1, 0.2)
                        dropRowSelection:Hide()
                        dropRow.selectionTexture = dropRowSelection
                        
                        -- Price text
                        local dropPrice = dropRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        dropPrice:SetPoint("LEFT", dropRow, "LEFT", 5, 0)
                        dropPrice:SetText(GetCoinTextureString(results[i].minPrice))
                        
                        -- Quantity text
                        local dropQuantity = dropRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        dropQuantity:SetPoint("RIGHT", dropRow, "RIGHT", -5, 0)
                        dropQuantity:SetText("Qty: " .. results[i].totalQuantity)
                        
                        -- Store auction data with the row
                        dropRow.auctionData = {
                            itemID = itemID,
                            minPrice = results[i].minPrice,
                            totalQuantity = results[i].totalQuantity,
                            auctionID = results[i].auctionID,
                            index = i
                        }
                        
                        -- Click handler for dropdown rows
                        dropRow:SetScript("OnClick", function(self)
                            -- Clear previous dropdown selections
                            for _, child in pairs({dropDown:GetChildren()}) do
                                if child.selectionTexture then
                                    child.selectionTexture:Hide()
                                end
                            end
                            
                            -- Show selection for this row
                            self.selectionTexture:Show()
                            
                            -- Update selected item data
                            row.itemData.minPrice = self.auctionData.minPrice
                            row.itemData.totalQuantity = self.auctionData.totalQuantity
                            row.itemData.auctionID = self.auctionData.auctionID
                            FLIPR.selectedItem = row.itemData
                        end)
                    end
                    
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
  