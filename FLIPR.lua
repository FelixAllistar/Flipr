local addonName, addon = ...
local AceAddon = LibStub("AceAddon-3.0")
local FLIPR = AceAddon:NewAddon(addonName, "AceEvent-3.0", "AceHook-3.0")
local ROW_HEIGHT = 25

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
    showConfirm = true,
    enabledGroups = {
        ["1.Very High 10000+"] = false,
        ["2.High 1000+"] = false,
        ["3.Medium 100+"] = false,
        ["4.Low 10+"] = false,
        ["5.Very low 1+"] = false
    }
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
    fliprTab.LeftActive:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.LeftActive:SetTexCoord(0.835938, 0.902344, 0.140625, 0.203125)
    fliprTab.LeftActive:SetSize(17, 32)
    fliprTab.LeftActive:SetPoint("TOPLEFT", 0, 0)
    
    fliprTab.MiddleActive:SetTexture("Interface\\FrameGeneral\\UI-Frame")
    fliprTab.MiddleActive:SetTexCoord(0.902344, 0.935547, 0.140625, 0.203125)
    fliprTab.MiddleActive:SetPoint("LEFT", fliprTab.LeftActive, "RIGHT")
    fliprTab.MiddleActive:SetPoint("RIGHT", fliprTab, "RIGHT", -16, 0)
    fliprTab.MiddleActive:SetHeight(32)
    
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

    -- Create our content frame
    local contentFrame = CreateFrame("Frame", nil, AuctionHouseFrame)
    contentFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 0, -60)
    contentFrame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, 0)
    contentFrame:Hide()  -- Start hidden

    -- Create the title section frame
    local titleSection = CreateFrame("Frame", nil, contentFrame)
    titleSection:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    titleSection:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    titleSection:SetHeight(40)
    
    -- Add background to title section
    local titleBg = titleSection:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Create scan button in title section
    local scanButton = CreateFrame("Button", nil, titleSection)
    scanButton:SetSize(120, 25)
    scanButton:SetPoint("LEFT", titleSection, "LEFT", 20, 0)
    
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
    border:SetColorTexture(0.5, 0.4, 0, 0.5)
    
    -- Create button text
    local buttonText = scanButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonText:SetPoint("CENTER", scanButton, "CENTER", 0, 0)
    buttonText:SetText("Scan Items")
    buttonText:SetTextColor(1, 0.82, 0, 1)
    
    -- Set button textures
    scanButton:SetNormalTexture(normalTexture)
    scanButton:SetHighlightTexture(highlightTexture)
    scanButton:SetPushedTexture(pushedTexture)
    
    -- Add click handler
    scanButton:SetScript("OnClick", function() self:ScanItems() end)
    
    -- Add mouseover effect for the text
    scanButton:SetScript("OnEnter", function()
        buttonText:SetTextColor(1, 0.9, 0.2, 1)
    end)
    
    scanButton:SetScript("OnLeave", function()
        buttonText:SetTextColor(1, 0.82, 0, 1)
    end)

    -- Create title text
    local titleText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", titleSection, "CENTER", 0, 0)
    titleText:SetText("FLIPR")
    titleText:SetTextColor(1, 0.8, 0, 1)

    -- Add version text
    local versionText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("RIGHT", titleSection, "RIGHT", -10, 0)
    versionText:SetText(version)
    versionText:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Create buy button
    local buyButton = CreateFrame("Button", nil, titleSection)
    buyButton:SetSize(80, 25)
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
    buyBorder:SetColorTexture(0.5, 0.4, 0, 0.5)
    
    -- Create button text
    local buyButtonText = buyButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buyButtonText:SetPoint("CENTER", buyButton, "CENTER", 0, 0)
    buyButtonText:SetText("Buy")
    buyButtonText:SetTextColor(1, 0.82, 0, 1)
    
    -- Set button textures
    buyButton:SetNormalTexture(buyNormalTexture)
    buyButton:SetHighlightTexture(buyHighlightTexture)
    buyButton:SetPushedTexture(buyPushedTexture)
    
    -- Create the options section frame
    local optionsSection = CreateFrame("Frame", nil, contentFrame)
    optionsSection:SetPoint("TOPLEFT", titleSection, "BOTTOMLEFT", 0, 0)
    optionsSection:SetPoint("TOPRIGHT", titleSection, "BOTTOMRIGHT", 0, 0)
    optionsSection:SetHeight(40)  -- Same height as title section
    
    -- Add background to options section
    local optionsBg = optionsSection:CreateTexture(nil, "BACKGROUND")
    optionsBg:SetAllPoints()
    optionsBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Create checkboxes in the options section
    local xOffset = 10  -- Start padding
    local groups = {
        "1.Very High 10000+",
        "2.High 1000+",
        "3.Medium 100+",
        "4.Low 10+",
        "5.Very low 1+"
    }

    for i, groupName in ipairs(groups) do
        local checkbox = CreateFrame("CheckButton", nil, optionsSection, "UICheckButtonTemplate")
        checkbox:SetPoint("LEFT", xOffset, 0)
        checkbox:SetChecked(self.db.enabledGroups[groupName])
        
        local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        label:SetText(groupName)
        label:SetTextColor(1, 0.82, 0, 1)  -- Golden text to match theme
        
        checkbox:SetScript("OnClick", function(self)
            FLIPR.db.enabledGroups[groupName] = self:GetChecked()
            FLIPR:UpdateScanItems()
        end)
        
        -- Calculate next xOffset based on label width
        xOffset = xOffset + checkbox:GetWidth() + label:GetStringWidth() + 15
    end

    -- Create divider below options section
    local divider = contentFrame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(2)
    divider:SetPoint("TOPLEFT", optionsSection, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", optionsSection, "BOTTOMRIGHT", 0, 0)
    divider:SetColorTexture(0.6, 0.6, 0.6, 0.8)

    -- Add gradient edges to divider
    local leftGradient = contentFrame:CreateTexture(nil, "ARTWORK")
    leftGradient:SetSize(50, 2)
    leftGradient:SetPoint("RIGHT", divider, "LEFT", 0, 0)
    leftGradient:SetColorTexture(0.6, 0.6, 0.6, 0)
    leftGradient:SetGradient("HORIZONTAL", CreateColor(0.6, 0.6, 0.6, 0), CreateColor(0.6, 0.6, 0.6, 0.8))

    local rightGradient = contentFrame:CreateTexture(nil, "ARTWORK")
    rightGradient:SetSize(50, 2)
    rightGradient:SetPoint("LEFT", divider, "RIGHT", 0, 0)
    rightGradient:SetColorTexture(0.6, 0.6, 0.6, 0)
    rightGradient:SetGradient("HORIZONTAL", CreateColor(0.6, 0.6, 0.6, 0.8), CreateColor(0.6, 0.6, 0.6, 0))

    -- Create results section with ScrollFrame
    local resultsSection = CreateFrame("Frame", nil, contentFrame)
    resultsSection:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -20)
    resultsSection:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    
    -- Add background to results section
    local resultsBg = resultsSection:CreateTexture(nil, "BACKGROUND")
    resultsBg:SetAllPoints()
    resultsBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    -- Create ScrollFrame inside resultsSection
    local scrollFrame = CreateFrame("ScrollFrame", nil, resultsSection, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", resultsSection, "TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", resultsSection, "BOTTOMRIGHT", -30, 10)  -- Leave room for scroll bar

    -- Create the scrolling content frame
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1) -- Will be adjusted as we add content

    -- Store references
    self.scrollFrame = scrollFrame
    self.scrollChild = scrollChild

    -- Hook tab switching (keep original hook code)
    fliprTab:SetScript("OnClick", function()
        PanelTemplates_SetTab(AuctionHouseFrame, numTabs)
        -- Hide all other frames
        AuctionHouseFrame.BrowseResultsFrame:Hide()
        AuctionHouseFrame.CategoriesList:Hide()
        AuctionHouseFrame.ItemBuyFrame:Hide()
        AuctionHouseFrame.ItemSellFrame:Hide()
        AuctionHouseFrame.CommoditiesBuyFrame:Hide()
        AuctionHouseFrame.CommoditiesSellFrame:Hide()
        AuctionHouseFrame.WoWTokenResults:Hide()
        AuctionHouseFrame.AuctionsFrame:Hide()
        -- Show our content
        contentFrame:Show()
    end)

    -- Add tab to AuctionHouseFrame.Tabs
    table.insert(AuctionHouseFrame.Tabs, fliprTab)
    
    -- Hook the AuctionHouseFrame tab system
    if not self.tabHooked then
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(frame)
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
        self.resultsFrame = CreateFrame("Frame", nil, self.resultsSection)  -- Parent to resultsSection
        self.resultsFrame:SetPoint("TOPLEFT", self.resultsSection, "TOPLEFT", 20, -20)  -- Added padding
        self.resultsFrame:SetPoint("BOTTOMRIGHT", self.resultsSection, "BOTTOMRIGHT", -20, 20)  -- Added padding
    end

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
    if not itemID then return end  -- Safety check
    
    -- Check if item is actually a commodity
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    if not itemInfo or not itemInfo.isCommodity then
        -- Not a commodity, skip processing
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
    local itemID = self.itemIDs[self.currentScanIndex]
    local itemName = GetItemInfo(itemID)
    
    if not itemName then
        print("Item info not available for ID:", itemID)
        return
    end

    -- Create row for this item
    local rowContainer = CreateFrame("Frame", nil, self.scrollChild)
    rowContainer:SetSize(self.scrollChild:GetWidth(), ROW_HEIGHT)
    rowContainer:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(self.currentScanIndex - 1) * (ROW_HEIGHT + 5))

    -- Main row
    local row = CreateFrame("Button", nil, rowContainer)
    row:SetAllPoints(rowContainer)
    
    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    -- Item name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetText(itemName)

    if results and #results > 0 then
        -- Price and quantity for main row
        local priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        priceText:SetPoint("CENTER", row, "CENTER", 0, 0)
        priceText:SetText(GetCoinTextureString(results[1].minPrice))
        
        local quantityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        quantityText:SetPoint("RIGHT", row, "RIGHT", -25, 0)
        quantityText:SetText(results[1].totalQuantity)

        -- Create dropdown container
        local dropDown = CreateFrame("Frame", nil, rowContainer)
        dropDown:SetSize(row:GetWidth(), ROW_HEIGHT * math.min(4, #results-1))
        dropDown:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
        dropDown:Hide()

        -- Add dropdown rows
        for i = 2, math.min(5, #results) do
            local dropDownRow = CreateFrame("Button", nil, dropDown)
            dropDownRow:SetSize(dropDown:GetWidth(), ROW_HEIGHT)
            dropDownRow:SetPoint("TOPLEFT", dropDown, "TOPLEFT", 0, -(i-2) * ROW_HEIGHT)
            
            -- Add dropdown row content...
        end

        -- Toggle dropdown on click
        row:SetScript("OnClick", function()
            dropDown:SetShown(not dropDown:IsShown())
        end)
    else
        local noResultsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noResultsText:SetPoint("CENTER", row, "CENTER", 0, 0)
        noResultsText:SetText("No auctions found")
    end

    -- Update scroll child height for just the main rows
    self.scrollChild:SetHeight(self.currentScanIndex * (ROW_HEIGHT + 5))

    -- Move to next item
    self.currentScanIndex = self.currentScanIndex + 1
    if self.currentScanIndex <= #self.itemIDs then
        C_Timer.After(0.5, function() self:ScanNextItem() end)
    end
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

-- Add this function to load a specific group's data
function FLIPR:LoadGroupData(groupName)
    local tableName = self:GetTableNameFromGroup(groupName)
    print(string.format("Loading group data for: %s (table: %s)", groupName, tableName))  -- Debug print
    local data = _G[tableName]
    print(string.format("Data found: %s", data and "yes" or "no"))  -- Debug print
    return data or {}
end

-- Add function to update scan items based on enabled groups
function FLIPR:UpdateScanItems()
    self.itemIDs = {}
    
    print("Updating scan items...")  -- Debug print
    for groupName, enabled in pairs(self.db.enabledGroups) do
        print(string.format("Group: %s, Enabled: %s", groupName, tostring(enabled)))  -- Debug print
        if enabled then
            local groupData = self:LoadGroupData(groupName)
            print(string.format("Group data loaded, size: %d", next(groupData) and #groupData or 0))  -- Debug print
            for itemID, _ in pairs(groupData) do
                table.insert(self.itemIDs, itemID)
            end
        end
    end
    
    print(string.format("Total items to scan: %d", #self.itemIDs))  -- Debug print
    
    -- Reset scan index
    self.currentScanIndex = 1
    
    -- Update display
    if self.scrollChild then
        self.scrollChild:SetHeight(1) -- Reset height
        -- Clear existing content
        for _, child in pairs({self.scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
    end
end

-- Add function to get table name from group name
function FLIPR:GetTableNameFromGroup(groupName)
    -- Match the format used in split_data.py exactly
    local tableName = "FLIPR_ItemDatabase_" .. groupName:gsub("[%.]", ""):gsub(" ", ""):gsub("[%+]", "plus")
    print(string.format("Generated table name: %s", tableName))  -- Debug print
    return tableName
end

-- Initialize the addon
FLIPR:OnInitialize()