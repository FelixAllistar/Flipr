local addonName, addon = ...
local FLIPR = addon.FLIPR
local ROW_HEIGHT = 25

function FLIPR:ScanItems()
    -- Get items from enabled groups
    self:UpdateScanItems()
    
    if #self.itemIDs == 0 then
        print("No groups selected!")
        return
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
    if self.currentScanIndex <= #self.itemIDs then
        local itemID = self.itemIDs[self.currentScanIndex]

        -- Wait for item info to be available
        local itemName, _, _, _, _, itemClass, itemSubClass = GetItemInfo(itemID)
        if not itemName then
            -- Request item info and wait for it
            local item = Item:CreateFromItemID(itemID)
            item:ContinueOnItemLoad(function()
                self:ScanNextItem()
            end)
            return
        end

        -- Check if item is likely a commodity based on its class
        local isCommodity = (
            itemClass == Enum.ItemClass.Consumable or
            itemClass == Enum.ItemClass.Reagent or
            itemClass == Enum.ItemClass.TradeGoods or
            itemClass == Enum.ItemClass.Recipe
        )
        
        if isCommodity then
            C_AuctionHouse.SendSearchQuery(nil, {}, true, itemID)
        else
            local itemKey = C_AuctionHouse.MakeItemKey(itemID)
            C_AuctionHouse.SendSearchQuery(itemKey, {}, true)
        end
    else
        -- Scanning complete
        if self.isEventRegistered then
            self:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
            self:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
            self.isEventRegistered = false
        end
    end
end

function FLIPR:OnCommoditySearchResults()
    local itemID = self.itemIDs[self.currentScanIndex]
    if not itemID then return end
    
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    if not itemInfo or not itemInfo.isCommodity then
        return
    end
    
    local numResults = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    
    if numResults and numResults > 0 then
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
    else
        self:ProcessAuctionResults({})
    end
end

function FLIPR:OnItemSearchResults()
    local itemID = self.itemIDs[self.currentScanIndex]
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    local numResults = C_AuctionHouse.GetNumItemSearchResults(itemKey)
    
    if numResults and numResults > 0 then
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
    else
        self:ProcessAuctionResults({})
    end
end

function FLIPR:ProcessAuctionResults(results)
    local itemID = self.itemIDs[self.currentScanIndex]
    local itemName = GetItemInfo(itemID)
    
    if not itemName then return end

    -- Create row for this item
    local rowContainer = CreateFrame("Frame", nil, self.scrollChild)
    rowContainer:SetSize(self.scrollChild:GetWidth(), ROW_HEIGHT)
    rowContainer:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(self.currentScanIndex - 1) * (ROW_HEIGHT + 5))

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
            local dropDown = CreateFrame("Frame", nil, row)
            dropDown:SetFrameStrata("DIALOG")
            dropDown:SetSize(row:GetWidth(), ROW_HEIGHT * math.min(4, #results-1))
            dropDown:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
            dropDown:Hide()

            -- Dropdown background
            local dropBg = dropDown:CreateTexture(nil, "BACKGROUND")
            dropBg:SetAllPoints()
            dropBg:SetColorTexture(0.15, 0.15, 0.15, 0.95)

            -- Create rows for additional auctions
            for i = 2, #results do
                local dropRow = CreateFrame("Button", nil, dropDown)
                dropRow:SetSize(dropDown:GetWidth(), ROW_HEIGHT)
                dropRow:SetPoint("TOPLEFT", dropDown, "TOPLEFT", 0, -(i-2) * ROW_HEIGHT)
                
                -- Selection texture
                local dropRowSelection = dropRow:CreateTexture(nil, "BACKGROUND")
                dropRowSelection:SetAllPoints()
                dropRowSelection:SetColorTexture(0.7, 0.7, 0.1, 0.2)
                dropRowSelection:Hide()
                dropRow.selectionTexture = dropRowSelection

                -- Store auction data
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
                dropRow:SetScript("OnClick", function()
                    -- Clear any previous selections
                    if self.selectedItem and self.selectedItem.itemID ~= itemID then
                        self:ClearAllSelections()
                    end

                    -- Select all auctions up to this one
                    for j = 1, dropRow.auctionData.index do
                        if j == 1 then
                            row.selectionTexture:Show()
                            row.defaultBg:Hide()
                        else
                            local prevRow = dropDown:GetChildren()[j-1]
                            if prevRow then
                                prevRow.selectionTexture:Show()
                            end
                        end
                    end
                    dropRow.selectionTexture:Show()

                    -- Update selected item data
                    local totalQty = 0
                    local totalCost = 0
                    for j = 1, dropRow.auctionData.index do
                        totalQty = totalQty + results[j].totalQuantity
                        totalCost = totalCost + (results[j].minPrice * results[j].totalQuantity)
                    end

                    self.selectedItem = {
                        itemID = itemID,
                        totalQuantity = totalQty,
                        minPrice = totalCost / totalQty,
                        selected = true,
                        selectedAuctions = {unpack(results, 1, dropRow.auctionData.index)}
                    }
                end)
            end

            -- Toggle dropdown on main row click
            row:SetScript("OnClick", function()
                if self.openDropDown and self.openDropDown ~= dropDown then
                    self.openDropDown:Hide()
                end
                dropDown:SetShown(not dropDown:IsShown())
                self.openDropDown = dropDown:IsShown() and dropDown or nil
            end)
        else
            -- Single auction click handler
            row:SetScript("OnClick", function()
                if self.selectedItem and self.selectedItem.itemID ~= itemID then
                    self:ClearAllSelections()
                end
                
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
end 