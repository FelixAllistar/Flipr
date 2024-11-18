local function GetItemData(itemID)
    return MyAddon_ItemDatabase[itemID]
end

-- Usage example
local itemData = GetItemData(12345)
if itemData then
    print(itemData.name, itemData.marketValue)
end 