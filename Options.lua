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

-- Add this helper function at the top of the file
local function CountTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

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
        FLIPR.db.profile[dbKey] = value
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
    local initialValue = FLIPR.db.profile[dbKey] or 0
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
    local options = {
        type = "group",
        name = "FLIPR",
        args = {
            modeSettings = {
                type = "group",
                name = "Mode Settings",
                order = 0,
                args = {
                    useTSMMode = {
                        type = "toggle",
                        name = "Use TSM Mode",
                        desc = "Use TSM's shopping operations for maxPrice and restockQuantity",
                        get = function() return self.db.profile.useTSMMode end,
                        set = function(_, value) 
                            self.db.profile.useTSMMode = value 
                            print(string.format("|cFF00FF00FLIPR: Switched to %s mode|r", value and "TSM" or "Classic"))
                        end,
                        order = 1,
                    },
                    modeDescription = {
                        type = "description",
                        name = "TSM Mode: Uses TSM's shopping operations for maxPrice and restockQuantity.\nClassic Mode: Uses price gaps between auctions to find flips.",
                        order = 2,
                    },
                },
            },
            saleRateSettings = {
                type = "group",
                name = "Sale Rate Settings",
                order = 1,
                args = {
                    highSaleRate = {
                        type = "range",
                        name = "High Sale Rate",
                        desc = "Sale rate threshold for high volume items",
                        min = 0,
                        max = 1,
                        step = 0.01,
                        get = function() return self.db.profile.highSaleRate end,
                        set = function(_, value) self.db.profile.highSaleRate = value end,
                        order = 1,
                    },
                    mediumSaleRate = {
                        type = "range",
                        name = "Medium Sale Rate",
                        desc = "Sale rate threshold for medium volume items",
                        min = 0,
                        max = 1,
                        step = 0.01,
                        get = function() return self.db.profile.mediumSaleRate end,
                        set = function(_, value) self.db.profile.mediumSaleRate = value end,
                        order = 2,
                    },
                },
            },
            inventorySettings = {
                type = "group",
                name = "Inventory Settings",
                order = 2,
                args = {
                    highInventory = {
                        type = "range",
                        name = "High Inventory",
                        desc = "Maximum inventory for high volume items",
                        min = 0,
                        max = 200,
                        step = 1,
                        get = function() return self.db.profile.highInventory end,
                        set = function(_, value) self.db.profile.highInventory = value end,
                        order = 1,
                    },
                    mediumInventory = {
                        type = "range",
                        name = "Medium Inventory",
                        desc = "Maximum inventory for medium volume items",
                        min = 0,
                        max = 50,
                        step = 1,
                        get = function() return self.db.profile.mediumInventory end,
                        set = function(_, value) self.db.profile.mediumInventory = value end,
                        order = 2,
                    },
                    lowInventory = {
                        type = "range",
                        name = "Low Inventory",
                        desc = "Maximum inventory for low volume items",
                        min = 0,
                        max = 20,
                        step = 1,
                        get = function() return self.db.profile.lowInventory end,
                        set = function(_, value) self.db.profile.lowInventory = value end,
                        order = 3,
                    },
                },
            },
            profitabilitySettings = {
                type = "group",
                name = "Profitability Settings",
                order = 3,
                args = {
                    minProfit = {
                        type = "range",
                        name = "Minimum Profit (gold)",
                        desc = "Minimum profit required for a flip",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function() return self.db.profile.minProfit end,
                        set = function(_, value) self.db.profile.minProfit = value end,
                        order = 1,
                    },
                    highVolumeROI = {
                        type = "range",
                        name = "High Volume ROI (%)",
                        desc = "Required ROI for high volume items",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function() return self.db.profile.highVolumeROI end,
                        set = function(_, value) self.db.profile.highVolumeROI = value end,
                        order = 2,
                    },
                    mediumVolumeROI = {
                        type = "range",
                        name = "Medium Volume ROI (%)",
                        desc = "Required ROI for medium volume items",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function() return self.db.profile.mediumVolumeROI end,
                        set = function(_, value) self.db.profile.mediumVolumeROI = value end,
                        order = 3,
                    },
                    lowVolumeROI = {
                        type = "range",
                        name = "Low Volume ROI (%)",
                        desc = "Required ROI for low volume items",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function() return self.db.profile.lowVolumeROI end,
                        set = function(_, value) self.db.profile.lowVolumeROI = value end,
                        order = 4,
                    },
                    veryLowVolumeROI = {
                        type = "range",
                        name = "Very Low Volume ROI (%)",
                        desc = "Required ROI for very low volume items",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function() return self.db.profile.veryLowVolumeROI end,
                        set = function(_, value) self.db.profile.veryLowVolumeROI = value end,
                        order = 5,
                    },
                    unstableMarketMultiplier = {
                        type = "range",
                        name = "Unstable Market Multiplier",
                        desc = "Profit multiplier for unstable markets",
                        min = 1,
                        max = 2,
                        step = 0.1,
                        get = function() return self.db.profile.unstableMarketMultiplier end,
                        set = function(_, value) self.db.profile.unstableMarketMultiplier = value end,
                        order = 6,
                    },
                    historicalLowMultiplier = {
                        type = "range",
                        name = "Historical Low Multiplier",
                        desc = "Profit multiplier for historically low prices",
                        min = 0,
                        max = 1,
                        step = 0.1,
                        get = function() return self.db.profile.historicalLowMultiplier end,
                        set = function(_, value) self.db.profile.historicalLowMultiplier = value end,
                        order = 7,
                    },
                },
            },
        },
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("FLIPR", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("FLIPR", "FLIPR")
end 