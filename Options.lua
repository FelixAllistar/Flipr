local addonName, addon = ...
local FLIPR = addon.FLIPR

function FLIPR:CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "FLIPR"
    
    -- Main container with padding
    local container = CreateFrame("Frame", nil, panel)
    container:SetPoint("TOPLEFT", 20, -20)
    container:SetPoint("BOTTOMRIGHT", -20, 20)
    
    -- Store rows for refresh
    local rows = {}
    
    -- Add OnShow handler to refresh values when panel is displayed
    panel:SetScript("OnShow", function()
        -- Force refresh all values from saved variables
        for _, row in pairs(rows) do
            row.UpdateValue(FLIPR.db[row.dbKey])
        end
    end)
    
    -- Title
    local title = container:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, 0)
    title:SetText("FLIPR Settings")
    
    -- Create a function to make setting rows
    local function CreateSettingRow(parent, label, yOffset, dbKey, maxValue)
        local rowContainer = CreateFrame("Frame", nil, parent)
        rowContainer:SetHeight(30)
        rowContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        rowContainer:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        
        -- Label
        local labelText = rowContainer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        labelText:SetPoint("LEFT", 0, 0)
        labelText:SetText(label)
        
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
        
        -- Unified update function
        local function UpdateValue(value, source)
            -- Validate and format value
            if maxValue == 1 then
                value = math.min(math.max(value, 0), 1)
                value = math.floor(value * 1000) / 1000
            else
                value = math.min(math.max(math.floor(value), 0), maxValue)
            end
            
            -- Update database
            FLIPR.db[dbKey] = value
            
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
        
        -- Set initial value
        UpdateValue(FLIPR.db[dbKey])
        
        -- Store row info for refresh
        rowContainer.dbKey = dbKey
        table.insert(rows, {
            UpdateValue = UpdateValue,
            dbKey = dbKey
        })
        
        return rowContainer
    end
    
    -- Create settings sections
    local yOffset = -60  -- Start below title
    
    -- Sale Rate Settings Header
    local saleRateHeader = container:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    saleRateHeader:SetPoint("TOP", container, "TOP", 0, yOffset)
    saleRateHeader:SetPoint("LEFT", container, "LEFT", 0, 0)
    saleRateHeader:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    saleRateHeader:SetJustifyH("CENTER")
    saleRateHeader:SetText("Sale Rate Thresholds")
    
    yOffset = yOffset - 40  -- Space after header
    CreateSettingRow(container, "High Sale Rate", yOffset, "highSaleRate", 1)
    
    yOffset = yOffset - 40
    CreateSettingRow(container, "Medium Sale Rate", yOffset, "mediumSaleRate", 1)
    
    yOffset = yOffset - 60  -- Extra space before next header
    
    -- Inventory Settings Header
    local inventoryHeader = container:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    inventoryHeader:SetPoint("TOP", container, "TOP", 0, yOffset)
    inventoryHeader:SetPoint("LEFT", container, "LEFT", 0, 0)
    inventoryHeader:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    inventoryHeader:SetJustifyH("CENTER")
    inventoryHeader:SetText("Inventory Limits")
    
    yOffset = yOffset - 40
    CreateSettingRow(container, "High Inventory Limit", yOffset, "highInventory", 200)
    
    yOffset = yOffset - 40
    CreateSettingRow(container, "Medium Inventory Limit", yOffset, "mediumInventory", 50)
    
    yOffset = yOffset - 40
    CreateSettingRow(container, "Low Inventory Limit", yOffset, "lowInventory", 20)
    
    -- Store reference and register
    FLIPR.optionsPanel = panel
    local category = Settings.RegisterCanvasLayoutCategory(panel, "FLIPR")
    category.ID = "FLIPR"
    Settings.RegisterAddOnCategory(category)
end 