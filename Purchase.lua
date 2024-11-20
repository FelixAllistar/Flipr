local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:IsCommodityItem(itemID)
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    return itemInfo and itemInfo.isCommodity
end

function FLIPR:ClearAllSelections()
    self.oldSelectedItem = self.selectedItem
    
    if self.oldSelectedItem then
        for _, child in pairs({self.scrollChild:GetChildren()}) do
            if child.itemData and child.itemData.itemID == self.oldSelectedItem.itemID then
                child.itemData.selected = false
                if child.selectionTexture then
                    child.selectionTexture:Hide()
                end
                if child.defaultBg then
                    child.defaultBg:Show()
                end
                break
            end
        end
    end
    
    self.selectedItem = nil
end

function FLIPR:SelectItem(row)
    if self.selectedRow then
        self.selectedRow.itemData.selected = false
        self.selectedRow.selectionTexture:Hide()
        self.selectedRow.defaultBg:Show()
    end
    
    row.itemData.selected = true
    row.defaultBg:Hide()
    row.selectionTexture:Show()
    
    self.selectedRow = row
    self.selectedItem = row.itemData
end

function FLIPR:CreateBuyConfirmationFrame()
    local frame = CreateFrame("Frame", "FLIPRBuyConfirmFrame", UIParent)
    frame:SetSize(300, 200)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.9)
    
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.6, 0.6, 0.6, 0.6)
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Purchase Confirmation")
    
    frame.itemText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.itemText:SetPoint("TOPLEFT", 20, -50)
    
    frame.qtyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.qtyText:SetPoint("TOPLEFT", 20, -70)
    
    frame.priceText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.priceText:SetPoint("TOPLEFT", 20, -90)
    
    frame.totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.totalText:SetPoint("TOPLEFT", 20, -120)
    
    local buyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buyButton:SetSize(100, 22)
    buyButton:SetPoint("BOTTOMRIGHT", -20, 20)
    buyButton:SetText("Buy")
    buyButton:SetScript("OnClick", function()
        if not self.selectedItem then return end
        
        local itemID = self.selectedItem.itemID
        local quantity = self.selectedItem.totalQuantity
        local unitPrice = self.selectedItem.minPrice
        local isCommodity = self:IsCommodityItem(itemID)
        
        if isCommodity then
            C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
            self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
                C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
                self:UnregisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
            end)
        else
            C_AuctionHouse.PlaceBid(self.selectedItem.auctionID, unitPrice * quantity)
        end
        
        frame:Hide()
    end)
    
    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 22)
    cancelButton:SetPoint("BOTTOMLEFT", 20, 20)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function() frame:Hide() end)
    
    frame:Hide()
    return frame
end 