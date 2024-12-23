local addonName, addon = ...
local FLIPR = addon.FLIPR

-- Define default settings in a central place
local defaultSettings = {
    -- Inventory control settings
    highSaleRate = 0.4,      
    mediumSaleRate = 0.2,    
    highInventory = 100,     
    mediumInventory = 10,    
    lowInventory = 5,
    -- Profitability settings
    minProfit = 1,         -- 1g minimum profit (was 0.1g)
    highVolumeROI = 15,       -- 15% for fast movers
    mediumVolumeROI = 25,     -- 25% for regular items
    lowVolumeROI = 40,        -- 40% for slow movers
    veryLowVolumeROI = 70,    -- 70% for very slow movers
    unstableMarketMultiplier = 1.3,  -- 30% more profit needed in unstable markets
    historicalLowMultiplier = 0.8,   -- 20% less ROI needed if prices are historically low
}

local function CreateSettingRow(parent, label, yOffset, dbKey, maxValue, isProfitSetting)
    local rowContainer = CreateFrame("Frame", nil, parent)
    rowContainer:SetHeight(30)
    rowContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, yOffset)
    rowContainer:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    
    -- Label
    local labelText = rowContainer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    labelText:SetPoint("LEFT", 80, 0)
    labelText:SetText(label)
    
    -- Slider
    local slider = CreateFrame("Slider", nil, rowContainer, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", labelText, "RIGHT", 20, 0)
    slider:SetWidth(200)
    slider:SetMinMaxValues(0, maxValue)
    slider:SetValueStep(maxValue == 1 and 0.001 or 1)
    slider:SetObeyStepOnDrag(true)
    
    -- Create slider text elements
    local valueText = slider:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, 0)
    slider.valueText = valueText
    
    -- Edit Box
    local editBox = CreateFrame("EditBox", nil, rowContainer, "InputBoxTemplate")
    editBox:SetPoint("LEFT", slider, "RIGHT", 20, 0)
    editBox:SetSize(60, 20)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetJustifyH("CENTER")
    editBox:SetMaxLetters(8)
    
    -- Value display function
    local function UpdateValueText(value)
        if maxValue == 1 then
            -- Percentage values
            slider.valueText:SetText(string.format("%.1f%%", value * 100))
            editBox:SetText(string.format("%.1f", value * 100))
        else
            -- Integer values
            local intValue = math.floor(value + 0.5)  -- Round to nearest integer
            slider.valueText:SetText(tostring(intValue))
            editBox:SetText(tostring(intValue))
        end
        editBox:SetCursorPosition(0)
    end
    
    -- Update function
    local function UpdateValue(value)
        if maxValue ~= 1 then
            -- Round to nearest integer for non-percentage values
            value = math.floor(value + 0.5)
        end
        slider:SetValue(value)
        UpdateValueText(value)
        
        -- Update the database
        if isProfitSetting then
            FLIPR.db[dbKey] = value
        else
            FLIPR.groupDB[dbKey] = value
        end
    end
    
    -- Slider scripts
    slider:SetScript("OnValueChanged", function(self, value)
        UpdateValue(value)
    end)
    
    -- Edit box scripts
    editBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            if maxValue == 1 then
                value = value / 100
            else
                value = math.floor(value + 0.5)  -- Round to nearest integer
            end
            value = math.min(math.max(value, 0), maxValue)
            UpdateValue(value)
        end
        self:ClearFocus()
    end)
    
    -- Initial value
    local initialValue = isProfitSetting and FLIPR.db[dbKey] or FLIPR.groupDB[dbKey] or 0
    if maxValue ~= 1 then
        initialValue = math.floor(initialValue + 0.5)  -- Round to nearest integer
    end
    UpdateValue(initialValue)
    
    -- Force update edit box after a slight delay
    C_Timer.After(0.1, function()
        if maxValue == 1 then
            editBox:SetText(string.format("%.1f", initialValue * 100))
        else
            editBox:SetText(tostring(math.floor(initialValue + 0.5)))
        end
    end)
    
    return rowContainer
end

function FLIPR:CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "FLIPR"
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    
    -- Create tab group at the top
    local tabGroup = CreateFrame("Frame", "FliprOptionsTabGroup", panel)
    tabGroup:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -10)
    tabGroup:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 0)
    
    -- Initialize tab system
    panel.tabs = {}
    panel.numTabs = 2
    
    -- Create tab buttons
    local function CreateTab(text, index)
        local tab = CreateFrame("Button", "FliprOptionsTab"..index, panel, "PanelTabButtonTemplate")
        tab:SetText(text)
        tab:SetID(index)
        if index == 1 then
            tab:SetPoint("TOPLEFT", tabGroup, "TOPLEFT", 5, 0)
        else
            tab:SetPoint("LEFT", _G["FliprOptionsTab"..(index-1)], "RIGHT", -15, 0)
        end
        
        -- Set up tab appearance
        tab:SetSize(115, 32)
        
        -- Create tab content frame with background
        tab.content = CreateFrame("Frame", nil, tabGroup, "BackdropTemplate")
        tab.content:SetPoint("TOPLEFT", tabGroup, "TOPLEFT", 0, -30)
        tab.content:SetPoint("BOTTOMRIGHT", tabGroup, "BOTTOMRIGHT", 0, -5)
        tab.content:Hide()
        
        -- Set up backdrop with no bottom inset
        tab.content:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileEdge = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 0 }
        })
        tab.content:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        tab.content:SetBackdropBorderColor(0.4, 0.4, 0.4)
        
        -- Add tab to panel's tabs array
        panel.tabs[index] = tab
        
        return tab
    end
    
    -- Create tabs
    local generalTab = CreateTab("General", 1)
    local operationsTab = CreateTab("Operations", 2)
    
    -- Initialize tab system after creating tabs
    PanelTemplates_SetNumTabs(panel, panel.numTabs)
    
    -- Store references
    panel.selectedTab = 1
    
    -- Tab click handler
    local function OnTabClick(tab)
        PanelTemplates_SetTab(panel, tab:GetID())
        -- Hide all content frames
        for _, t in ipairs(panel.tabs) do
            t.content:Hide()
        end
        -- Show selected content
        tab.content:Show()
        panel.selectedTab = tab:GetID()
    end
    
    -- Set up tab click scripts
    for _, tab in ipairs(panel.tabs) do
        tab:SetScript("OnClick", function(self) OnTabClick(self) end)
    end
    
    -- Create the general settings content
    local function CreateGeneralSettings(parent)
        -- Create the scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -36, 16)
        
        -- Create the scrolling content frame
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        scrollChild:SetSize(scrollFrame:GetWidth() - 30, 1)
        scrollFrame:SetScrollChild(scrollChild)
        
        -- Create settings sections
        local yOffset = -30  -- Increased initial offset from -10 to -30
        
        -- Sale Rate Settings Header
        local saleRateHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        saleRateHeader:SetPoint("TOP", scrollChild, "TOP", 280, yOffset)
        saleRateHeader:SetText("Sale Rate Thresholds")
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "High Sale Rate", yOffset, "highSaleRate", 1, true)
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "Medium Sale Rate", yOffset, "mediumSaleRate", 1, true)
        
        yOffset = yOffset - 60  -- Increased space before next header from -40 to -60
        
        -- Inventory Settings Header
        local inventoryHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        inventoryHeader:SetPoint("TOP", scrollChild, "TOP", 280, yOffset)
        inventoryHeader:SetText("Inventory Limits")
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "High Inventory", yOffset, "highInventory", 200, true)
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "Medium Inventory", yOffset, "mediumInventory", 50, true)
        
        yOffset = yOffset - 30
        CreateSettingRow(scrollChild, "Low Inventory", yOffset, "lowInventory", 20, true)
        
        -- Set final height of the scrollChild based on the content
        scrollChild:SetHeight(math.abs(yOffset) + 20)
        
        -- Make sure the parent frame is visible and sized
        parent:SetSize(parent:GetParent():GetWidth(), parent:GetParent():GetHeight())
        parent:Show()
        
        return scrollFrame
    end
    
    -- Create the operations content
    local function CreateOperationsContent(parent)
        -- Create the scroll frame
        local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
        scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -36, 16)
        
        -- Create the scrolling content frame
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -20)
        scrollChild:SetWidth(scrollFrame:GetWidth() - 30)
        scrollFrame:SetScrollChild(scrollChild)
        
        local yOffset = -50
        local contentHeight = 0
        
        -- Operations Header
        local header = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetPoint("TOP", scrollChild, "TOP", 280, yOffset)
        header:SetText("TSM Operations")
        contentHeight = contentHeight + 30
        
        yOffset = yOffset - 30
        
        -- Function to create operation section
        local function CreateOperationSection(moduleName, operations, startOffset)
            local moduleHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            moduleHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 40, startOffset)
            moduleHeader:SetText(moduleName)
            contentHeight = contentHeight + 20
            
            local offset = startOffset - 20
            
            if operations then
                for opName, opSettings in pairs(operations) do
                    local opHeader = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    opHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 60, offset)
                    opHeader:SetText(opName)
                    contentHeight = contentHeight + 20
                    
                    offset = offset - 20
                    
                    -- Display operation settings
                    for setting, value in pairs(opSettings) do
                        local settingText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                        settingText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 80, offset)
                        settingText:SetText(string.format("%s: %s", setting, tostring(value)))
                        
                        offset = offset - 15
                        contentHeight = contentHeight + 15
                    end
                    
                    offset = offset - 10
                    contentHeight = contentHeight + 10
                end
            else
                local noOpsText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisable")
                noOpsText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 60, offset)
                noOpsText:SetText("No operations found")
                contentHeight = contentHeight + 20
                offset = offset - 30
            end
            
            return offset
        end
        
        -- Get operations from the first group (they're shared)
        local operations = nil
        for groupName, groupData in pairs(self.groupDB.groups) do
            if groupData.operations then
                operations = groupData.operations
                break
            end
        end
        
        -- Create sections for each module type
        local moduleTypes = {"Auctioning", "Shopping", "Crafting", "Vendoring", "Warehousing", "Mailing", "Sniper"}
        for _, moduleName in ipairs(moduleTypes) do
            if operations and operations[moduleName] then
                yOffset = CreateOperationSection(moduleName, operations[moduleName], yOffset)
            else
                yOffset = CreateOperationSection(moduleName, nil, yOffset)
            end
            yOffset = yOffset - 20  -- Space between modules
            contentHeight = contentHeight + 20
        end
        
        -- Set final height with additional padding
        scrollChild:SetHeight(contentHeight + 150)
        
        scrollFrame:SetScrollChild(scrollChild)
        return scrollFrame
    end
    
    -- Create content for both tabs
    CreateGeneralSettings(generalTab.content)
    CreateOperationsContent(operationsTab.content)
    
    -- Set up initial tab state
    PanelTemplates_SetTab(panel, 1)
    generalTab.content:Show()
    operationsTab.content:Hide()
    
    -- Store reference and register with Settings API
    FLIPR.optionsPanel = panel
    local category = Settings.RegisterCanvasLayoutCategory(panel, "FLIPR")
    category.ID = "FLIPR"
    Settings.RegisterAddOnCategory(category)
    
    -- Set up panel refresh
    panel.OnShow = function()
        PanelTemplates_SetTab(panel, panel.selectedTab or 1)
        for _, tab in ipairs(panel.tabs) do
            tab.content:Hide()
        end
        local selectedTab = panel.tabs[panel.selectedTab or 1]
        selectedTab.content:Show()
        
        -- Force update all edit boxes
        C_Timer.After(0.1, function()
            for dbKey, value in pairs(FLIPR.db) do
                -- Find and update edit boxes
                -- You might need to store references to edit boxes when creating them
                -- Or traverse the UI hierarchy to find them
            end
        end)
    end
    panel:SetScript("OnShow", panel.OnShow)
    
    return panel
end 