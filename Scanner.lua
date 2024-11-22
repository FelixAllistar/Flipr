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

    -- Create row for this item
    local rowContainer = CreateFrame("Frame", nil, self.scrollChild)
    rowContainer:SetSize(self.scrollChild:GetWidth(), ROW_HEIGHT)
    
    -- Get number of existing rows and subtract 1 to start at 0
    local numExistingRows = select("#", self.scrollChild:GetChildren()) - 1
    
    -- Position based on number of existing rows, starting at 0
    rowContainer:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(numExistingRows * ROW_HEIGHT))

    -- Update scroll child height (keep the +1 here)
    self.scrollChild:SetHeight((numExistingRows + 1) * ROW_HEIGHT)

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

    -- Item name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetText(itemName)

    if results and #results > 0 then
        -- Store all auction data with the row
        row.itemData = {
            itemID = itemID,
            minPrice = results[1].minPrice,
            totalQuantity = results[1].totalQuantity,
            auctionID = results[1].auctionID,
            selected = false,
            allAuctions = results  -- Store all auctions for this item
        }
        
        -- Price and quantity for main row
        local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        priceText:SetPoint("CENTER", row, "CENTER", 0, 0)
        priceText:SetText(GetCoinTextureString(results[1].minPrice))
        
        local quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        quantityText:SetPoint("RIGHT", row, "RIGHT", -25, 0)
        quantityText:SetText(results[1].totalQuantity)

        -- Create dropdown for additional auctions
        if #results > 1 then
            -- Create dropdown as child of row
            local dropDown = CreateFrame("Frame", nil, row)
            dropDown:SetFrameStrata("DIALOG")
            dropDown:SetSize(row:GetWidth(), ROW_HEIGHT * (#results - 1))
            dropDown:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
            dropDown:Hide()

            -- Store dropdown reference
            row.dropDown = dropDown

            -- Dropdown background (create as child of dropdown)
            local dropBg = dropDown:CreateTexture(nil, "BACKGROUND")
            dropBg:SetAllPoints()
            dropBg:SetColorTexture(0.15, 0.15, 0.15, 0.95)

            -- Create rows for additional auctions
            local dropDownRows = {}
            for i = 2, #results do
                -- Create each dropdown row as child of dropdown
                local dropRow = CreateFrame("Button", nil, dropDown)
                dropRow:SetSize(dropDown:GetWidth(), ROW_HEIGHT)
                dropRow:SetPoint("TOPLEFT", dropDown, "TOPLEFT", 0, -(i-2) * ROW_HEIGHT)
                
                -- Create background for dropdown row
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

                dropDownRows[i] = dropRow
                dropRow.auctionData = {
                    itemID = itemID,
                    minPrice = results[i].minPrice,
                    totalQuantity = results[i].totalQuantity,
                    auctionID = results[i].auctionID,
                    index = i
                }

                -- Price and quantity
                local dropPrice = dropRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dropPrice:SetPoint("CENTER", dropRow, "CENTER", 0, 0)
                dropPrice:SetText(GetCoinTextureString(results[i].minPrice))
                
                local dropQuantity = dropRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dropQuantity:SetPoint("RIGHT", dropRow, "RIGHT", -20, 0)
                dropQuantity:SetText(results[i].totalQuantity)

                -- Click handler for dropdown rows
                dropRow:SetScript("OnClick", function(self)
                    -- Hide any other open dropdowns
                    if FLIPR.openDropDown and FLIPR.openDropDown ~= dropDown then
                        FLIPR.openDropDown:Hide()
                        FLIPR.openDropDown = nil
                    end

                    -- Clear any previous selections
                    if FLIPR.selectedRow then
                        FLIPR.selectedRow.itemData.selected = false
                        FLIPR.selectedRow.selectionTexture:Hide()
                        FLIPR.selectedRow.defaultBg:Show()
                        
                        -- Clear previous dropdown selections
                        if FLIPR.selectedRow.dropDown then
                            for _, child in pairs({FLIPR.selectedRow.dropDown:GetChildren()}) do
                                if child.selectionTexture then
                                    child.selectionTexture:Hide()
                                end
                            end
                        end
                    end

                    -- Select this item's main row
                    row.itemData.selected = true
                    row.selectionTexture:Show()
                    row.defaultBg:Hide()
                    FLIPR.selectedRow = row
                    FLIPR.openDropDown = dropDown

                    -- Show selection on all rows up to clicked one
                    local totalQty = 0
                    local totalCost = 0
                    for j = 1, dropRow.auctionData.index do
                        if j > 1 then
                            dropDownRows[j].selectionTexture:Show()
                        end
                        totalQty = totalQty + results[j].totalQuantity
                        totalCost = totalCost + (results[j].minPrice * results[j].totalQuantity)
                    end

                    FLIPR.selectedItem = {
                        itemID = itemID,
                        totalQuantity = totalQty,
                        minPrice = totalCost / totalQty,
                        selected = true,
                        selectedAuctions = {unpack(results, 1, dropRow.auctionData.index)}
                    }
                end)
            end

            -- Main row click handler
            row:SetScript("OnClick", function()
                -- Hide any other open dropdowns
                if FLIPR.openDropDown and FLIPR.openDropDown ~= dropDown then
                    FLIPR.openDropDown:Hide()
                    FLIPR.openDropDown = nil
                end

                -- Clear any previous selections
                if FLIPR.selectedRow and FLIPR.selectedRow ~= row then
                    FLIPR.selectedRow.itemData.selected = false
                    FLIPR.selectedRow.selectionTexture:Hide()
                    FLIPR.selectedRow.defaultBg:Show()
                    
                    -- Clear previous dropdown selections
                    if FLIPR.selectedRow.dropDown then
                        for _, child in pairs({FLIPR.selectedRow.dropDown:GetChildren()}) do
                            if child.selectionTexture then
                                child.selectionTexture:Hide()
                            end
                        end
                    end
                end

                -- Toggle dropdown
                dropDown:SetShown(not dropDown:IsShown())
                if dropDown:IsShown() then
                    FLIPR.openDropDown = dropDown
                else
                    FLIPR.openDropDown = nil
                end

                -- Select this row
                row.itemData.selected = true
                row.selectionTexture:Show()
                row.defaultBg:Hide()
                FLIPR.selectedRow = row
                FLIPR.selectedItem = {
                    itemID = itemID,
                    totalQuantity = results[1].totalQuantity,
                    minPrice = results[1].minPrice,
                    selected = true,
                    selectedAuctions = {results[1]}
                }
            end)
        else
            -- Single auction click handler
            row:SetScript("OnClick", function()
                -- Clear previous selection first
                self:ClearAllSelections()
                
                row.itemData.selected = not row.itemData.selected
                row.selectionTexture:SetShown(row.itemData.selected)
                row.defaultBg:SetShown(not row.itemData.selected)
                
                if row.itemData.selected then
                    self.selectedItem = row.itemData
                else
                    self.selectedItem = nil
                end
            end)
        end
    else
        local noResultsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noResultsText:SetPoint("CENTER", row, "CENTER", 0, 0)
        noResultsText:SetText("No auctions found")
    end

    self.scrollChild:SetHeight(self.currentScanIndex * (ROW_HEIGHT + 5))

    self.currentScanIndex = self.currentScanIndex + 1
    if self.currentScanIndex <= #self.itemIDs then
        C_Timer.After(0.5, function() self:ScanNextItem() end)
    end

    -- After processing results, update progress text
    if self.scanProgressText then
        self.scanProgressText:SetText(string.format("%d/%d items", self.currentScanIndex, #self.itemIDs))
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