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

function FLIPR:CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "FLIPR"
    
    -- Create the scroll frame with wider area
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate") 
    scrollFrame:SetPoint("TOPLEFT", 20, -50)  -- Reduced left padding to 20
    scrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)
    
    -- Create the scrolling content frame with padding
    local scrollChild = CreateFrame("Frame")
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth() - 20)
    
    -- Title centered at top, slightly left-adjusted
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", panel, "TOP", -30, -20)  -- Added -30 to X offset to shift left
    title:SetText("FLIPR Settings")
    
    -- Store rows for refresh
    local rows = {}
    
    -- Add OnShow handler to refresh values when panel is displayed
    panel:SetScript("OnShow", function()
        -- Force refresh all values from saved variables
        for _, row in pairs(rows) do
            if row.isProfitSetting then
                row.UpdateValue(FLIPR.db[row.dbKey] or 0)
            else
                row.UpdateValue(FLIPR.groupDB[row.dbKey] or 0)
            end
        end
    end)
    
    -- Create Reset to Defaults button (now at top right)
    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(120, 22)
    resetButton:SetPoint("TOPRIGHT", -60, -20)  -- Positioned in top right
    resetButton:SetText("Reset All")
    
    resetButton:SetScript("OnClick", function()
        -- Create confirmation dialog
        StaticPopupDialogs["FLIPR_RESET_CONFIRM"] = {
            text = "Are you sure you want to reset all settings to default values?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                -- Reset all settings to defaults
                for key, value in pairs(defaultSettings) do
                    FLIPR.db[key] = value
                end
                
                -- Refresh all rows
                for _, row in pairs(rows) do
                    if row.isProfitSetting then
                        row.UpdateValue(FLIPR.db[row.dbKey])
                    end
                end
                
                print("FLIPR: All settings have been reset to defaults")
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("FLIPR_RESET_CONFIRM")
    end)
    
    -- Create a function to make setting rows
    local function CreateSettingRow(parent, label, yOffset, dbKey, maxValue, isProfitSetting)
        local rowContainer = CreateFrame("Frame", nil, parent)
        rowContainer:SetHeight(30)
        rowContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)  -- Reduced padding
        rowContainer:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        
        -- Label
        local labelText = rowContainer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        labelText:SetPoint("LEFT", 20, 0)
        labelText:SetText(label)
        labelText:SetJustifyH("LEFT")
        
        -- Slider
        local slider = CreateFrame("Slider", nil, rowContainer, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", labelText, "RIGHT", 20, 0)
        slider:SetWidth(200)
        slider:SetMinMaxValues(0, maxValue)
        slider:SetValueStep(0.001)
        slider:SetObeyStepOnDrag(true)
        
        -- Edit Box for direct input
        local editBox = CreateFrame("EditBox", nil, rowContainer, "InputBoxTemplate")
        editBox:SetPoint("LEFT", slider, "RIGHT", 20, 0)
        editBox:SetSize(60, 20)
        editBox:SetAutoFocus(false)
        editBox:SetJustifyH("CENTER")
        
        -- Current Value Label
        local valueLabel = rowContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        valueLabel:SetPoint("LEFT", editBox, "RIGHT", 10, 0)
        valueLabel:SetJustifyH("LEFT")
        
        -- Unified update function
        local function UpdateValue(value, source)
            -- Handle nil value
            if value == nil then
                value = 0
            end
            
            -- Validate and format value
            if maxValue == 1 then
                value = math.min(math.max(value, 0), 1)
                value = math.floor(value * 1000) / 1000
            else
                value = math.min(math.max(math.floor(value), 0), maxValue)
            end
            
            -- Update correct database
            if isProfitSetting then
                FLIPR.db[dbKey] = value
            else
                FLIPR.groupDB[dbKey] = value
            end
            
            -- Update UI elements (skip the source to avoid loops)
            if source ~= "slider" then
                slider:SetValue(value)
            end
            
            -- Always update editBox text
            editBox:SetText(maxValue == 1 and string.format("%.3f", value) or tostring(value))
            editBox:SetCursorPosition(0)  -- Reset cursor to start
            
            -- Update current value label
            valueLabel:SetText(maxValue == 1 and 
                string.format("(Current: %.3f)", value) or 
                string.format("(Current: %d)", value))
        end
        
        -- Event handlers
        slider:SetScript("OnValueChanged", function(self, value)
            UpdateValue(value, "slider")
        end)
        
        editBox:SetScript("OnEnterPressed", function(self)
            local value = tonumber(self:GetText())
            if value then
                UpdateValue(value, "editBox")
                self:ClearFocus()
            end
        end)
        
        -- Get initial value with nil check
        local initialValue
        if isProfitSetting then
            initialValue = FLIPR.db[dbKey] or 0
        else
            initialValue = FLIPR.groupDB[dbKey] or 0
        end
        
        -- Set initial value for both slider and editBox
        slider:SetValue(initialValue)
        UpdateValue(initialValue)
        
        -- Store row info for refresh
        rowContainer.dbKey = dbKey
        rowContainer.isProfitSetting = isProfitSetting
        table.insert(rows, {
            UpdateValue = UpdateValue,
            dbKey = dbKey,
            isProfitSetting = isProfitSetting
        })
        
        return rowContainer
    end
    
    -- Create settings sections
    local yOffset = -40  -- Start below title
    
    -- Sale Rate Settings Header as a row
    local saleRateRow = CreateFrame("Frame", nil, scrollChild)
    saleRateRow:SetHeight(30)
    saleRateRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 20, yOffset)
    saleRateRow:SetPoint("RIGHT", scrollChild, "RIGHT", -20, 0)
    
    local saleRateHeader = saleRateRow:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    saleRateHeader:SetPoint("LEFT", saleRateRow, "LEFT", 220, 0)  -- Changed to 200px padding
    saleRateHeader:SetText("Sale Rate Thresholds")
    
    yOffset = yOffset - 40  -- Space after header
    CreateSettingRow(scrollChild, "High Sale Rate", yOffset, "highSaleRate", 1, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Medium Sale Rate", yOffset, "mediumSaleRate", 1, true)
    
    yOffset = yOffset - 60  -- Extra space before next header
    
    -- Inventory Settings Header as a row
    local inventoryRow = CreateFrame("Frame", nil, scrollChild)
    inventoryRow:SetHeight(30)
    inventoryRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 20, yOffset)
    inventoryRow:SetPoint("RIGHT", scrollChild, "RIGHT", -20, 0)
    
    local inventoryHeader = inventoryRow:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    inventoryHeader:SetPoint("LEFT", inventoryRow, "LEFT", 220, 0)  -- Changed to 200px padding
    inventoryHeader:SetText("Inventory Limits")
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "High Inventory Limit", yOffset, "highInventory", 200, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Medium Inventory Limit", yOffset, "mediumInventory", 50, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Low Inventory Limit", yOffset, "lowInventory", 20, true)
    
    yOffset = yOffset - 60  -- Extra space before next header
    
    -- Profitability Settings Header as a row
    local profitRow = CreateFrame("Frame", nil, scrollChild)
    profitRow:SetHeight(30)
    profitRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 20, yOffset)
    profitRow:SetPoint("RIGHT", scrollChild, "RIGHT", -20, 0)
    
    local profitHeader = profitRow:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    profitHeader:SetPoint("LEFT", profitRow, "LEFT", 220, 0)  -- Changed to 200px padding
    profitHeader:SetText("Profitability Settings")
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Minimum Profit (g)", yOffset, "minProfit", 10000, true)  -- Up to 10000g
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "High Volume ROI %", yOffset, "highVolumeROI", 100, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Medium Volume ROI %", yOffset, "mediumVolumeROI", 100, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Low Volume ROI %", yOffset, "lowVolumeROI", 200, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Very Low Volume ROI %", yOffset, "veryLowVolumeROI", 300, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Unstable Market Multiplier", yOffset, "unstableMarketMultiplier", 2, true)
    
    yOffset = yOffset - 40
    CreateSettingRow(scrollChild, "Historical Low Multiplier", yOffset, "historicalLowMultiplier", 1, true)
    
    -- Set the scroll child's height based on the final yOffset
    scrollChild:SetHeight(math.abs(yOffset) + 40)  -- Add padding at bottom
    
    -- Store reference and register
    FLIPR.optionsPanel = panel
    local category = Settings.RegisterCanvasLayoutCategory(panel, "FLIPR")
    category.ID = "FLIPR"
    Settings.RegisterAddOnCategory(category)
end 