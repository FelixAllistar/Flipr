local addonName, addon = ...
local FLIPR = addon.FLIPR
local ROW_HEIGHT = 25

FLIPR.scanTimer = 0
FLIPR.scanStartTime = 0

function FLIPR:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW", "OnAuctionHouseShow")
end

function FLIPR:OnAuctionHouseShow()
    if not self.tabCreated then
        self:CreateFLIPRTab()
        self.tabCreated = true
    end
end

function FLIPR:CreateFLIPRTab()
    local numTabs = #AuctionHouseFrame.Tabs + 1
    local fliprTab = CreateFrame("Button", "AuctionHouseFrameTab"..numTabs, AuctionHouseFrame, "AuctionHouseFrameTabTemplate") 
    fliprTab:SetID(numTabs)
    fliprTab:SetText("FLIPR")
    fliprTab:SetPoint("LEFT", AuctionHouseFrame.Tabs[numTabs-1], "RIGHT", -15, 0)

    local contentFrame = CreateFrame("Frame", nil, AuctionHouseFrame)
    contentFrame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 0, -60)
    contentFrame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, 0)
    contentFrame:Hide()

    -- Our tab's click handler
    fliprTab:SetScript("OnClick", function()
        -- Hide all default frames
        AuctionHouseFrame.BrowseResultsFrame:Hide()
        AuctionHouseFrame.CategoriesList:Hide()
        AuctionHouseFrame.ItemBuyFrame:Hide()
        AuctionHouseFrame.ItemSellFrame:Hide()
        AuctionHouseFrame.CommoditiesBuyFrame:Hide()
        AuctionHouseFrame.CommoditiesSellFrame:Hide()
        AuctionHouseFrame.WoWTokenResults:Hide()
        AuctionHouseFrame.AuctionsFrame:Hide()
        
        PanelTemplates_SetTab(AuctionHouseFrame, numTabs)
        contentFrame:Show()
    end)

    -- Hook the AuctionHouseFrame display mode
    if not self.displayModeHooked then
        hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(frame, displayMode)
            -- Hide our content when not on our tab
            if frame.selectedTab ~= numTabs then
                contentFrame:Hide()
            end
        end)
        self.displayModeHooked = true
    end

    table.insert(AuctionHouseFrame.Tabs, fliprTab)
    PanelTemplates_SetNumTabs(AuctionHouseFrame, numTabs)

    self.fliprTab = fliprTab
    self.contentFrame = contentFrame

    self:CreateTitleSection(contentFrame)
    self:CreateOptionsSection(contentFrame)
    self:CreateResultsSection(contentFrame)
end

function FLIPR:CreateTitleSection(contentFrame)
    local titleSection = CreateFrame("Frame", nil, contentFrame)
    titleSection:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    titleSection:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    titleSection:SetHeight(40)
    
    -- Add background
    local titleBg = titleSection:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Create scan button
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
    
    -- Set button textures
    scanButton:SetNormalTexture(normalTexture)
    scanButton:SetHighlightTexture(highlightTexture)
    scanButton:SetPushedTexture(pushedTexture)
    
    -- Store reference to button
    self.scanButton = scanButton

    -- Create button text
    local buttonText = scanButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buttonText:SetPoint("CENTER", scanButton, "CENTER", 0, 0)
    buttonText:SetText("Scan Items")
    buttonText:SetTextColor(1, 0.82, 0, 1)
    scanButton.buttonText = buttonText  -- Store reference to text
    
    -- Add click handler
    scanButton:SetScript("OnClick", function() self:ScanItems() end)
    
    -- Add mouseover effect for the text
    scanButton:SetScript("OnEnter", function()
        buttonText:SetTextColor(1, 0.9, 0.2, 1)
    end)
    
    scanButton:SetScript("OnLeave", function()
        buttonText:SetTextColor(1, 0.82, 0, 1)
    end)

    -- Add progress text
    local progressText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressText:SetPoint("LEFT", scanButton, "RIGHT", 10, 0)
    progressText:SetText("")  -- Start empty
    progressText:SetTextColor(0.7, 0.7, 0.7, 1)
    self.scanProgressText = progressText  -- Store reference

    -- Add timer text
    local timerText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerText:SetPoint("LEFT", progressText, "RIGHT", 10, 0)
    timerText:SetText("")
    timerText:SetTextColor(0.7, 0.7, 0.7, 1)
    self.scanTimerText = timerText

    -- Create OnUpdate handler for the timer
    local timerFrame = CreateFrame("Frame")
    timerFrame:Hide()
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        if FLIPR.isScanning and not FLIPR.isPaused then
            FLIPR.scanTimer = GetTime() - FLIPR.scanStartTime
            local minutes = math.floor(FLIPR.scanTimer / 60)
            local seconds = math.floor(FLIPR.scanTimer % 60)
            FLIPR.scanTimerText:SetText(string.format("Time: %d:%02d", minutes, seconds))
        end
    end)
    self.timerFrame = timerFrame

    -- Modify scan button click handler to handle timer
    scanButton:SetScript("OnClick", function() 
        if not FLIPR.isScanning then
            -- Starting new scan
            FLIPR.scanStartTime = GetTime()
            FLIPR.scanTimer = 0
            timerFrame:Show()
        elseif FLIPR.isPaused then
            -- Resuming scan
            FLIPR.scanStartTime = GetTime() - FLIPR.scanTimer
            timerFrame:Show()
        else
            -- Pausing scan
            timerFrame:Hide()
        end
        FLIPR:ScanItems() 
    end)

    -- Create title text
    local titleText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", titleSection, "CENTER", 0, 0)
    titleText:SetText("FLIPR")
    titleText:SetTextColor(1, 0.8, 0, 1)

    -- Add version text
    local versionText = titleSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("RIGHT", titleSection, "RIGHT", -10, 0)
    versionText:SetText(addon.version)
    versionText:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Create buy button
    local buyButton = CreateFrame("Button", nil, titleSection)
    buyButton:SetSize(80, 25)
    buyButton:SetPoint("RIGHT", versionText, "LEFT", -10, 0)
    
    -- Add button textures
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
    
    -- Add click handler
    buyButton:SetScript("OnClick", function()
        if not self.buyConfirmFrame then
            self.buyConfirmFrame = self:CreateBuyConfirmationFrame()
        end
        
        if not self.selectedItem then
            print("No items selected!")
            return
        end
        
        local itemName = GetItemInfo(self.selectedItem.itemID)
        local totalQty = self.selectedItem.totalQuantity
        local totalPrice = self.selectedItem.minPrice * totalQty
        
        self.buyConfirmFrame.itemText:SetText("Item: " .. itemName)
        self.buyConfirmFrame.qtyText:SetText(string.format("Quantity: %d", totalQty))
        self.buyConfirmFrame.priceText:SetText(string.format("Price Each: %s", GetCoinTextureString(self.selectedItem.minPrice)))
        self.buyConfirmFrame.totalText:SetText(string.format("Total: %s", GetCoinTextureString(totalPrice)))
        
        self.buyConfirmFrame:Show()
    end)

    self.titleSection = titleSection
end

function FLIPR:CreateOptionsSection(contentFrame)
    local optionsSection = CreateFrame("Frame", nil, contentFrame)
    optionsSection:SetPoint("TOPLEFT", self.titleSection, "BOTTOMLEFT", 0, 0)
    optionsSection:SetPoint("TOPRIGHT", self.titleSection, "BOTTOMRIGHT", 0, 0)
    optionsSection:SetHeight(40)
    
    local optionsBg = optionsSection:CreateTexture(nil, "BACKGROUND")
    optionsBg:SetAllPoints()
    optionsBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Create checkboxes
    local xOffset = 10
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
        label:SetTextColor(1, 0.82, 0, 1)
        
        checkbox:SetScript("OnClick", function(self)
            FLIPR.db.enabledGroups[groupName] = self:GetChecked()
            FLIPR:UpdateScanItems()
        end)
        
        xOffset = xOffset + checkbox:GetWidth() + label:GetStringWidth() + 15
    end

    -- Create divider
    local divider = contentFrame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(2)
    divider:SetPoint("TOPLEFT", optionsSection, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", optionsSection, "BOTTOMRIGHT", 0, 0)
    divider:SetColorTexture(0.6, 0.6, 0.6, 0.8)

    -- Add gradient edges
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

    self.optionsSection = optionsSection
    self.divider = divider
end

function FLIPR:CreateResultsSection(contentFrame)
    local resultsSection = CreateFrame("Frame", nil, contentFrame)
    resultsSection:SetPoint("TOPLEFT", self.divider, "BOTTOMLEFT", 0, -20)
    resultsSection:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    
    local resultsBg = resultsSection:CreateTexture(nil, "BACKGROUND")
    resultsBg:SetAllPoints()
    resultsBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    local scrollFrame = CreateFrame("ScrollFrame", nil, resultsSection, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", resultsSection, "TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", resultsSection, "BOTTOMRIGHT", -30, 10)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)

    self.resultsSection = resultsSection
    self.scrollFrame = scrollFrame
    self.scrollChild = scrollChild
end
 