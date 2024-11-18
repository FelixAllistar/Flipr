local addonName, addon = ...
local AceAddon = LibStub("AceAddon-3.0")
local FLIPR = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceHook-3.0")

-- Get the version from TOC using the correct API
local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "v0.070"

-- Add this near the top of the file after the version declaration
StaticPopupDialogs["FLIPR_CONFIRM_PURCHASE"] = {
    text = "%s",
    button1 = "Buy",
    button2 = "Cancel",
    OnShow = function(self)
        if not self.data then return end
        self.text:SetText(string.format(
            "Buy %s x%d for %s?",
            self.data.itemName,
            self.data.quantity,
            self.data.totalPrice
        ))
    end,
    OnAccept = function(self)
        if not self.data then return end
        
        if self.data.isCommodity then
            print("Starting commodity purchase:", self.data.itemID, self.data.quantity)
            
            -- For commodities, we need to:
            -- 1. Start the purchase
            -- 2. Wait for the system to be ready
            -- 3. Confirm the purchase
            C_AuctionHouse.StartCommoditiesPurchase(self.data.itemID, self.data.quantity)
            
            -- Register for the throttled system ready event
            FLIPR:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
                print("System ready, confirming purchase...")
                C_AuctionHouse.ConfirmCommoditiesPurchase(self.data.itemID, self.data.quantity)
                FLIPR:UnregisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
            end)
        else
            if self.data.auctionID then
                print("Placing bid:", self.data.auctionID, self.data.totalPrice)
                C_AuctionHouse.PlaceBid(self.data.auctionID, self.data.totalPrice)
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    showAlert = true,
    sound = SOUNDKIT.AUCTION_WINDOW_OPEN,
    hasItemFrame = false,
    parent = UIParent,
}

-- At the top of the file, after other StaticPopupDialogs definitions
StaticPopupDialogs["FLIPR_TEST_POPUP"] = {
    text = "Test popup window",
    button1 = "OK",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Default scan items
local defaultItems = {
    "Light Leather",
    "Medium Leather"
}

local defaultSettings = {
    items = defaultItems,
    showConfirm = true  -- Add default setting for confirmation dialog
}

-- Initialize addon
function FLIPR:OnInitialize()
    -- Create settings if they don't exist
    if not FLIPRSettings then
        FLIPRSettings = defaultSettings
    else
        -- Ensure all default settings exist
        for key, value in pairs(defaultSettings) do
            if FLIPRSettings[key] == nil then
                FLIPRSettings[key] = value
            end
        end
    end
    
    self.db = FLIPRSettings
    print("FLIPR Settings loaded. ShowConfirm:", self.db.showConfirm)  -- Debug print
    
    -- Register events
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
end

-- Create the FLIPR tab when AH opens
function FLIPR:AUCTION_HOUSE_SHOW()
    if not self.tabCreated then
        self:CreateFLIPRTab()
        self.tabCreated = true
    end
end

function FLIPR:CreateFLIPRTab()
    -- Add debug print
    print("HELLO WORLD - FLIPR DEBUG")
    
    -- Create the tab button
    local numTabs = #AuctionHouseFrame.Tabs + 1
    local fliprTab = CreateFrame("Button", "AuctionHouseFrameTab"..numTabs, AuctionHouseFrame)
    fliprTab:SetSize(115, 32)
    fliprTab:SetID(numTabs)
    
    -- Create required tab textures - corrected drawLayer parameter
    fliprTab.LeftDisabled = fliprTab:CreateTexture(nil, "BACKGROUND")
    fliprTab.MiddleDisabled = fliprTab:CreateTexture(nil, "BACKGROUND") 
    fliprTab.RightDisabled = fliprTab:CreateTexture(nil, "BACKGROUND")
    
    -- Add Active textures
    fliprTab.LeftActive = fliprTab:CreateTexture(nil, "BACKGROUND")
    fliprTab.MiddleActive = fliprTab:CreateTexture(nil, "BACKGROUND")
    fliprTab.RightActive = fliprTab:CreateTexture(nil, "BACKGROUND")
    
    -- Create the main tab textures - simplified creation
    fliprTab.Left = fliprTab:CreateTexture(nil, "BACKGROUND")
    fliprTab.Left:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.Left:SetTexCoord(0.835938, 0.902344, 0.140625, 0.203125)
    fliprTab.Left:SetSize(17, 32)
    fliprTab.Left:SetPoint("TOPLEFT", 0, 0)
    
    fliprTab.Middle = fliprTab:CreateTexture(nil, "BACKGROUND")
    fliprTab.Middle:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.Middle:SetTexCoord(0.902344, 0.935547, 0.140625, 0.203125)
    fliprTab.Middle:SetPoint("LEFT", fliprTab.Left, "RIGHT")
    fliprTab.Middle:SetPoint("RIGHT", fliprTab, "RIGHT", -16, 0)
    fliprTab.Middle:SetHeight(32)
    
    fliprTab.Right = fliprTab:CreateTexture(nil, "BACKGROUND")
    fliprTab.Right:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.Right:SetTexCoord(0.935547, 1, 0.140625, 0.203125)
    fliprTab.Right:SetSize(16, 32)
    fliprTab.Right:SetPoint("TOPRIGHT", 0, 0)
    
    -- Configure Active textures
    -- LeftActive
    fliprTab.LeftActive:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.LeftActive:SetTexCoord(0.835938, 0.902344, 0.140625, 0.203125)
    fliprTab.LeftActive:SetSize(17, 32)
    fliprTab.LeftActive:SetPoint("TOPLEFT", 0, 0)
    
    -- MiddleActive
    fliprTab.MiddleActive:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.MiddleActive:SetTexCoord(0.902344, 0.935547, 0.140625, 0.203125)
    fliprTab.MiddleActive:SetPoint("LEFT", fliprTab.LeftActive, "RIGHT")
    fliprTab.MiddleActive:SetPoint("RIGHT", fliprTab, "RIGHT", -16, 0)
    fliprTab.MiddleActive:SetHeight(32)
    
    -- RightActive
    fliprTab.RightActive:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.RightActive:SetTexCoord(0.935547, 1, 0.140625, 0.203125)
    fliprTab.RightActive:SetSize(16, 32)
    fliprTab.RightActive:SetPoint("TOPRIGHT", 0, 0)
    
    -- Create and position text
    local text = fliprTab:CreateFontString(nil, "OVERLAY")
    text:SetFontObject("GameFontHighlight")
    text:SetPoint("LEFT", fliprTab, "LEFT", 14, -3)
    text:SetPoint("RIGHT", fliprTab, "RIGHT", -14, -3)
    text:SetText("FLIPR")
    fliprTab.Text = text
    
    -- Add highlight texture
    local highTex = fliprTab:CreateTexture(nil, "HIGHLIGHT")
    highTex:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
    highTex:SetBlendMode("ADD")
    highTex:SetPoint("TOPLEFT", fliprTab, "TOPLEFT", 0, 1)
    highTex:SetPoint("BOTTOMRIGHT", fliprTab, "BOTTOMRIGHT", 0, -7)
    fliprTab:SetHighlightTexture(highTex)
    
    -- Position the tab
    fliprTab:SetPoint("LEFT", AuctionHouseFrame.Tabs[numTabs-1], "RIGHT", -19, 0)
    
    -- Create the content frame with a scroll frame
    local contentFrame = CreateFrame("Frame", nil, AuctionHouseFrame)
    contentFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 0, -60)
    contentFrame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, 0)
    
    -- Create title bar background
    local titleBar = CreateFrame("Frame", nil, contentFrame)
    titleBar:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
    titleBar:SetHeight(40)
    
    -- Add gradient texture to title bar
    local bgTexture = titleBar:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetPoint("TOPLEFT", 0, 0)
    bgTexture:SetPoint("BOTTOMRIGHT", 0, 0)
    bgTexture:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    -- Add fancy border at bottom of title bar
    local borderTexture = titleBar:CreateTexture(nil, "ARTWORK")
    borderTexture:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    borderTexture:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    borderTexture:SetHeight(2)
    borderTexture:SetColorTexture(0.7, 0.7, 0.7, 0.5)
    
    -- Create title text with glow effect
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetText("FLIPR")
    titleText:SetTextColor(1, 0.8, 0, 1) -- Golden color
    
    -- Add version text
    local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("RIGHT", titleBar, "RIGHT", -10, 0)
    versionText:SetText(version)
    versionText:SetTextColor(0.7, 0.7, 0.7, 1) -- Subtle gray color
    
    -- Create Buy button with same style as scan button
    local buyButton = CreateFrame("Button", nil, contentFrame)
    buyButton:SetSize(80, 25) -- Slightly smaller than scan button
    buyButton:SetPoint("RIGHT", versionText, "LEFT", -10, 0)
    
    -- Add button textures (same style as scan button)
    local buyNormalTexture = buyButton:CreateTexture(nil, "BACKGROUND")
    buyNormalTexture:SetAllPoints()
    buyNormalTexture:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    
    local buyHighlightTexture = buyButton:CreateTexture(nil, "HIGHLIGHT")
    buyHighlightTexture:SetAllPoints()
    buyHighlightTexture:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    
    local buyPushedTexture = buyButton:CreateTexture(nil, "BACKGROUND")
    buyPushedTexture:SetAllPoints()
    buyPushedTexture:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    
    -- Add button border
    local buyBorder = buyButton:CreateTexture(nil, "BORDER")
    buyBorder:SetAllPoints()
    buyBorder:SetColorTexture(0.5, 0.4, 0, 0.5) -- Golden border
    
    -- Create button text
    local buyButtonText = buyButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buyButtonText:SetPoint("CENTER", buyButton, "CENTER", 0, 0)
    buyButtonText:SetText("Buy")
    buyButtonText:SetTextColor(1, 0.82, 0, 1) -- Golden text
    
    -- Set button textures
    buyButton:SetNormalTexture(buyNormalTexture)
    buyButton:SetHighlightTexture(buyHighlightTexture)
    buyButton:SetPushedTexture(buyPushedTexture)
    
    -- Add mouseover effect for the text
    buyButton:SetScript("OnEnter", function()
        buyButtonText:SetTextColor(1, 0.9, 0.2, 1)
    end)
    
    buyButton:SetScript("OnLeave", function()
        buyButtonText:SetTextColor(1, 0.82, 0, 1)
    end)
    
    -- Add click handler for buy button
    buyButton:SetScript("OnClick", function()
        print("Buy button clicked!")
        print("ShowConfirm setting:", self.db.showConfirm)  -- Debug print
        
        if not self.selectedItem then
            print("No item selected")
            return
        end

        local itemID = self.selectedItem.itemID
        if not itemID then
            print("Invalid item selection - no itemID")
            return
        end

        if self.db.showConfirm then
            print("Showing confirmation dialog...")
            self:ShowConfirmDialog(itemID, self.selectedItem.totalQuantity, self.selectedItem.minPrice)
        else
            print("Direct purchase - no confirmation")
            local isCommodity = self:IsCommodityItem(itemID)
            if isCommodity then
                local quantity = self.selectedItem.totalQuantity
                if quantity and quantity > 0 then
                    C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
                end
            else
                if self.selectedItem.auctionID and self.selectedItem.minPrice then
                    C_AuctionHouse.PlaceBid(self.selectedItem.auctionID, self.selectedItem.minPrice)
                end
            end
        end
    end)
    
    -- Add glow behind text
    local glowTexture = titleBar:CreateTexture(nil, "BACKGROUND")
    glowTexture:SetPoint("CENTER", titleText, "CENTER", 0, 0)
    glowTexture:SetSize(128, 32)
    glowTexture:SetTexture("Interface\\Artifacts\\PowerGlow1")
    glowTexture:SetBlendMode("ADD")
    glowTexture:SetAlpha(0.3)
    
    -- Create a custom button template
    local scanButton = CreateFrame("Button", nil, contentFrame)
    scanButton:SetSize(120, 25)
    scanButton:SetPoint("LEFT", titleBar, "LEFT", 20, 0)
    
    -- Add button textures
    local normalTexture = scanButton:CreateTexture(nil, "BACKGROUND")
    normalTexture:SetAllPoints()
    normalTexture:SetColorTexture(0.2, 0.2, 0.2, 0.9)
    
    local highlightTexture = scanButton:CreateTexture(nil, "HIGHLIGHT")
    highlightTexture:SetAllPoints()
    highlightTexture:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    
    local pushedTexture = scanButton:CreateTexture(nil, "BACKGROUND")
    pushedTexture:SetAllPoints()
    pushedTexture:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    
    -- Add button border
    local border = scanButton:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.5, 0.4, 0, 0.5) -- Golden border
    
    -- Create button text
    local buttonText = scanButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonText:SetPoint("CENTER", scanButton, "CENTER", 0, 0)
    buttonText:SetText("Scan Items")
    buttonText:SetTextColor(1, 0.82, 0, 1) -- Golden text
    
    -- Set button textures
    scanButton:SetNormalTexture(normalTexture)
    scanButton:SetHighlightTexture(highlightTexture)
    scanButton:SetPushedTexture(pushedTexture)
    
    -- Add click handler
    scanButton:SetScript("OnClick", function() self:ScanItems() end)
    
    -- Add mouseover effect for the text
    scanButton:SetScript("OnEnter", function()
        buttonText:SetTextColor(1, 0.9, 0.2, 1) -- Brighter golden text on hover
    end)
    
    scanButton:SetScript("OnLeave", function()
        buttonText:SetTextColor(1, 0.82, 0, 1) -- Return to normal color
    end)
    
    -- Create scroll frame with adjusted position
    local scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -10)  -- Adjusted to be below title bar
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    
    -- Create scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)  -- Will expand as we add content
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Store references
    self.fliprTab = fliprTab
    self.contentFrame = contentFrame
    self.scrollFrame = scrollFrame
    self.scrollChild = scrollChild
    
    -- Add tab to AuctionHouseFrame.Tabs
    table.insert(AuctionHouseFrame.Tabs, fliprTab)
    
    -- Hook tab switching
    fliprTab:SetScript("OnClick", function()
        -- Hide all other frames first
        AuctionHouseFrame.BrowseResultsFrame:Hide()
        AuctionHouseFrame.CategoriesList:Hide()
        AuctionHouseFrame.ItemBuyFrame:Hide()
        AuctionHouseFrame.ItemSellFrame:Hide()
        AuctionHouseFrame.CommoditiesBuyFrame:Hide()
        AuctionHouseFrame.CommoditiesSellFrame:Hide()
        AuctionHouseFrame.WoWTokenResults:Hide()
        AuctionHouseFrame.AuctionsFrame:Hide()
        
        -- Update tab appearance
        PanelTemplates_SetTab(AuctionHouseFrame, numTabs)
        
        -- Show our content
        contentFrame:Show()
    end)
    
    -- Hook the AuctionHouseFrame tab system
    if not self.tabHooked then
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(frame)
            -- Hide our content when other tabs are selected
            if frame.selectedTab ~= numTabs then
                contentFrame:Hide()
            end
        end)
        self.tabHooked = true
    end
end

function FLIPR:ScanItems()
    -- Clear previous results
    if self.resultsFrame then
        self.resultsFrame:Hide()
    end

    -- Create results frame if needed
    if not self.resultsFrame then
        self.resultsFrame = CreateFrame("Frame", nil, self.contentFrame)
        self.resultsFrame:SetPoint("TOPLEFT", 20, -60)
        self.resultsFrame:SetSize(self.contentFrame:GetWidth() - 40, self.contentFrame:GetHeight() - 80)
    end

    -- Define item IDs directly
    local itemIDs = {
        6522  -- Pearl-clasped Cloak (testing with known item)
    }

    -- Track current item being scanned
    self.currentScanIndex = 1
    self.itemIDs = itemIDs

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

        print("Scanning item: " .. itemName .. " (ID: " .. itemID .. ")")

        -- Check if item is likely a commodity based on its class
        local isCommodity = (
            itemClass == Enum.ItemClass.Consumable or
            itemClass == Enum.ItemClass.Reagent or
            itemClass == Enum.ItemClass.TradeGoods or
            itemClass == Enum.ItemClass.Recipe
        )
        
        if isCommodity then
            print("Scanning commodity item")
            -- For commodities, use commodity search
            C_AuctionHouse.SendSearchQuery(nil, {}, true, itemID)
        else
            print("Scanning regular item")
            -- For regular items, use item search
            local itemKey = C_AuctionHouse.MakeItemKey(itemID)
            C_AuctionHouse.SendSearchQuery(itemKey, {}, true)
        end
        
        -- Register for both browse and commodity results
        if not self.isEventRegistered then
            self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "OnCommoditySearchResults")
            self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", "OnItemSearchResults")
            self.isEventRegistered = true
        end
    else
        -- Scanning complete
        print("Item scanning complete.")
        -- Unregister events
        if self.isEventRegistered then
            self:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
            self:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
            self.isEventRegistered = false
        end
    end
end

-- Rename event handlers to match registration
function FLIPR:OnCommoditySearchResults()
    local itemID = self.itemIDs[self.currentScanIndex]
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
                    itemID = itemID -- Add itemID to the result
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
    -- Create itemKey for search
    local itemKey = C_AuctionHouse.MakeItemKey(itemID)
    -- Get number of results first
    local numResults = C_AuctionHouse.GetNumItemSearchResults(itemKey)
    
    if numResults and numResults > 0 then
        local processedResults = {}
        -- Get each result individually
        for i = 1, numResults do
            local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
            if result then
                table.insert(processedResults, {
                    itemName = GetItemInfo(itemID),
                    minPrice = result.buyoutAmount or result.bidAmount,
                    totalQuantity = 1
                })
            end
        end
        self:ProcessAuctionResults(processedResults)
    else
        self:ProcessAuctionResults({})
    end
end

-- Update event handler for search results
function FLIPR:AUCTION_HOUSE_SEARCH_RESULTS_UPDATED(_, itemKey)
    -- Check if the itemKey matches the current item
    if itemKey.itemID == self.itemIDs[self.currentScanIndex] then
        print("Search results updated!")
        local totalResults = C_AuctionHouse.GetNumReplicateItems()
        print("Number of results: " .. totalResults)

        if totalResults > 0 then
            local processedResults = {}
            for i = 1, totalResults do
                local itemInfo = { C_AuctionHouse.GetReplicateItemInfo(i) }
                table.insert(processedResults, {
                    itemName = itemInfo[1],
                    minPrice = itemInfo[10],
                    totalQuantity = itemInfo[3]
                })
            end
            self:ProcessAuctionResults(processedResults)
        else
            print("No results found")
            -- Move to next item
            self.currentScanIndex = self.currentScanIndex + 1
            C_Timer.After(0.5, function() self:ScanNextItem() end)
        end

        -- Unregister event until next scan
        self:UnregisterEvent("AUCTION_HOUSE_SEARCH_RESULTS_UPDATED")
    end
end

-- New helper function to process auction results
function FLIPR:ProcessAuctionResults(results)
    -- Store the results for the buy button
    self.currentResults = results
    
    -- Clear previous results
    for _, child in ipairs({self.scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local itemName = GetItemInfo(self.itemIDs[self.currentScanIndex])
    local rowHeight = 25
    
    -- Create row for this item
    local row = CreateFrame("Button", nil, self.scrollChild)
    row:SetSize(self.scrollChild:GetWidth(), rowHeight)
    row:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(self.currentScanIndex - 1) * (rowHeight + 5))
    
    -- Add background texture
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    
    -- Add highlight texture
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.1)
    row:SetHighlightTexture(highlight)
    
    -- Add selection texture
    local selection = row:CreateTexture(nil, "BACKGROUND")
    selection:SetAllPoints()
    selection:SetColorTexture(1, 0.8, 0, 0.2)
    selection:Hide()
    row.selectionTexture = selection
    
    -- Add item name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetText(itemName)
    
    -- Only add price and quantity if we have results
    if results[1] then
        -- Add lowest price
        local lowestPrice = results[1].minPrice / 10000
        local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        priceText:SetPoint("CENTER", row, "CENTER", 0, 0)
        priceText:SetText(string.format("%.2fg", lowestPrice))
        
        -- Add quantity
        local quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        quantityText:SetPoint("RIGHT", row, "RIGHT", -25, 0)
        quantityText:SetText(results[1].totalQuantity)
        
        -- Store the result data with the row
        row.itemData = {
            itemID = self.itemIDs[self.currentScanIndex],
            minPrice = results[1].minPrice,
            totalQuantity = results[1].totalQuantity,
            auctionID = results[1].auctionID -- This will be nil for commodities, which is fine
        }
        
        -- Create dropdown content
        local dropdownContent = CreateFrame("Frame", nil, row)
        dropdownContent:SetSize(row:GetWidth(), rowHeight * 4)
        dropdownContent:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
        dropdownContent:Hide()
        
        -- Add background to dropdown
        local dropBg = dropdownContent:CreateTexture(nil, "BACKGROUND")
        dropBg:SetAllPoints()
        dropBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        
        -- Add next 4 auction entries to dropdown
        for i = 2, math.min(5, #results) do
            local result = results[i]
            if result then
                local dropdownRow = CreateFrame("Frame", nil, dropdownContent)
                dropdownRow:SetSize(dropdownContent:GetWidth(), rowHeight)
                dropdownRow:SetPoint("TOPLEFT", dropdownContent, "TOPLEFT", 0, -(i-2) * rowHeight)
                
                -- Add highlight on mouseover
                local dropHighlight = dropdownRow:CreateTexture(nil, "HIGHLIGHT")
                dropHighlight:SetAllPoints()
                dropHighlight:SetColorTexture(1, 1, 1, 0.1)
                
                -- Price
                local dropPrice = dropdownRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dropPrice:SetPoint("CENTER", dropdownRow, "CENTER", 0, 0)
                dropPrice:SetText(string.format("%.2fg", result.minPrice / 10000))
                
                -- Quantity
                local dropQuantity = dropdownRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dropQuantity:SetPoint("RIGHT", dropdownRow, "RIGHT", -20, 0)
                dropQuantity:SetText(result.totalQuantity)

                -- Make dropdown rows clickable
                dropdownRow:EnableMouse(true)
                dropdownRow:SetScript("OnMouseDown", function()
                    -- Deselect previous row if exists
                    if selectedRow and selectedRow.selectionTexture then
                        selectedRow.selectionTexture:Hide()
                    end
                    
                    -- Select parent row and store this result's data
                    selectedRow = row
                    selection:Show()
                    self.selectedItem = result
                end)
            end
        end
        
        -- Add dropdown arrow
        local arrow = row:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(16, 16)
        arrow:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        
        -- Store the dropdown
        row.dropdownContent = dropdownContent
        
        -- Add click handler for selection and dropdown toggle
        row:SetScript("OnClick", function()
            print("Row clicked!")  -- Debug print
            
            -- Deselect previous row if exists
            if selectedRow and selectedRow.selectionTexture then
                selectedRow.selectionTexture:Hide()
            end
            
            -- Select this row
            selectedRow = row
            selection:Show()
            
            -- Store the selected item data
            self.selectedItem = row.itemData
            print("Stored item data:", self.selectedItem.itemID, self.selectedItem.minPrice, self.selectedItem.totalQuantity)  -- Debug print
            
            -- Toggle dropdown
            dropdownContent:SetShown(not dropdownContent:IsShown())
        end)
    else
        -- If no results, just show "No auctions found"
        local noResultsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noResultsText:SetPoint("CENTER", row, "CENTER", 0, 0)
        noResultsText:SetText("No auctions found")
    end
    
    -- Update scroll child height
    self.scrollChild:SetHeight((self.currentScanIndex * (rowHeight + 5)) + 10)
end

-- Add this helper function to determine if an item is a commodity
function FLIPR:IsCommodityItem(itemID)
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    return itemInfo and itemInfo.isCommodity
end

-- Add confirmation dialog function
function FLIPR:ShowConfirmDialog(itemID, quantity, unitPrice)
    local itemName = GetItemInfo(itemID)
    local isCommodity = self:IsCommodityItem(itemID)
    
    -- Format prices nicely
    local function FormatMoney(copper)
        local gold = math.floor(copper / 10000)
        local silver = math.floor((copper % 10000) / 100)
        local copper = copper % 100
        return string.format("%dg %ds %dc", gold, silver, copper)
    end
    
    -- Calculate prices
    local priceEach = FormatMoney(unitPrice)
    local totalPrice = FormatMoney(unitPrice * quantity)
    
    -- Format the full message
    local message = string.format("%s (%s x%d = %s)", 
        itemName,
        priceEach,
        quantity,
        totalPrice
    )
    
    -- Show the popup with the formatted message
    local dialog = StaticPopup_Show(
        "FLIPR_CONFIRM_PURCHASE",
        message  -- Just pass the complete formatted message
    )
    
    if dialog then
        dialog.data = {
            itemName = itemName,
            itemID = itemID,
            quantity = quantity,
            totalPrice = unitPrice * quantity,
            isCommodity = isCommodity,
            auctionID = self.selectedItem.auctionID
        }
    end
end

-- Initialize the addon
FLIPR:OnInitialize()