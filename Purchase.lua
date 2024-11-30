local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:IsCommodityItem(itemID)
    local itemInfo = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    return itemInfo and itemInfo.isCommodity
end

function FLIPR:ClearPurchaseSelections()
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
    print("=== DEBUG: Creating Buy Frame ===")
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
    frame.itemText:SetPoint("TOP", title, "BOTTOM", 0, -10)
    
    local priceContainer = CreateFrame("Frame", nil, frame)
    priceContainer:SetPoint("TOP", frame.itemText, "BOTTOM", 0, -10)
    priceContainer:SetSize(200, 100)
    
    frame.priceLines = {}
    for i = 1, 5 do
        local priceLine = priceContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        priceLine:SetPoint("TOP", priceContainer, "TOP", 0, -(i-1) * 15)
        priceLine:SetJustifyH("CENTER")
        frame.priceLines[i] = priceLine
    end
    
    frame.totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.totalText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 50)
    
    local buyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    buyButton:SetSize(100, 22)
    buyButton:SetPoint("BOTTOMRIGHT", -20, 20)
    buyButton:SetText("Buy")
    
    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 22)
    cancelButton:SetPoint("BOTTOMLEFT", 20, 20)
    cancelButton:SetText("Cancel")
    
    buyButton:SetScript("OnClick", function()
        if not self.selectedItem then return end
        
        local itemID = self.selectedItem.itemID
        local isCommodity = self:IsCommodityItem(itemID)
        
        self:StartPurchaseThrottle()
        
        if isCommodity then
            local totalQty = 0
            for _, auction in pairs(self.selectedItem.selectedAuctions) do
                totalQty = totalQty + auction.totalQuantity
            end
            
            C_AuctionHouse.StartCommoditiesPurchase(itemID, totalQty)
            self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
                C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, totalQty)
                self:UnregisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
                self:EndPurchaseThrottle()
                self:RemoveItemRowAndUpdate(itemID)
            end)
        else
            for _, auction in pairs(self.selectedItem.selectedAuctions) do
                C_AuctionHouse.PlaceBid(auction.auctionID, auction.minPrice * auction.totalQuantity)
            end
            C_Timer.After(0.5, function()
                self:EndPurchaseThrottle()
                self:RemoveItemRowAndUpdate(itemID)
            end)
        end
        
        frame:Hide()
    end)
    
    cancelButton:SetScript("OnClick", function() 
        frame:Hide() 
    end)
    
    frame.UpdateDisplay = function(self, itemData)
        if not itemData then return end
        
        local itemName = GetItemInfo(itemData.itemID)
        self.itemText:SetText("Item: " .. itemName)
        
        for _, line in ipairs(self.priceLines) do
            line:SetText("")
        end
        
        local totalCost = 0
        local totalQuantity = 0
        
        if itemData.selectedAuctions then
            for i, auction in pairs(itemData.selectedAuctions) do
                if i <= #self.priceLines then
                    local subtotal = auction.minPrice * auction.totalQuantity
                    totalCost = totalCost + subtotal
                    totalQuantity = totalQuantity + auction.totalQuantity
                    
                    self.priceLines[i]:SetText(string.format(
                        "%s x%d = %s",
                        GetCoinTextureString(auction.minPrice),
                        auction.totalQuantity,
                        GetCoinTextureString(subtotal)
                    ))
                end
            end
        end
        
        self.totalText:SetText(string.format("Total: %s", GetCoinTextureString(totalCost)))
    end
    
    frame:Hide()
    return frame
end

function FLIPR:BuySelectedAuctions()
    if not self.selectedItem then
        print("No items selected!")
        return
    end
    
    if not self.buyConfirmFrame then
        self.buyConfirmFrame = self:CreateBuyConfirmationFrame()
    end
    
    self.buyConfirmFrame:UpdateDisplay(self.selectedItem)
    self.buyConfirmFrame:Show()
end

function FLIPR:StartPurchaseThrottle()
    self.isPurchaseThrottled = true
end

function FLIPR:EndPurchaseThrottle()
    self.isPurchaseThrottled = false
end 