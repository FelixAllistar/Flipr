# TSM Data Structure

This document explains how TradeSkillMaster (TSM) stores its data and how we access it in FLIPR.

## Database Location

TSM stores its data in the saved variables table `TradeSkillMasterDB`. The main profile data is stored under the key `p@Default@userData`.

## Data Structure

### 1. Items and Groups
```lua
TradeSkillMasterDB["p@Default@userData@items"]
```
This table maps item IDs to their group paths. Group paths use backticks (`) as separators for hierarchy levels.

Example:
```lua
["i:194792"] = "Potat0's flipping profile 11.0.3`4.Low 10+"
```

### 2. Group Operations
```lua
TradeSkillMasterDB["p@Default@userData@groups"]
```
This table maps group paths to their assigned operations for each TSM module.

Example:
```lua
["Potat0's flipping profile 11.0.3`4.Low 10+"] = {
    Shopping = {
        "shopping low quantity",  -- Operation names
        override = true          -- Whether operations are overridden at this level
    },
    Auctioning = {
        "selling"
    }
}
```

### 3. Operation Details
```lua
TradeSkillMasterDB["p@Default@userData@operations"]
```
This table contains the actual settings for each operation, organized by module.

Example:
```lua
["Shopping"] = {
    ["shopping low quantity"] = {
        maxPrice = "ifgt(maxstack,1,ifgte(max(dbregionsalerate,0.001),0.1,...))",
        restockQuantity = "min(50000,max(dbregionsoldperday*0.1,1))",
        restockSources = {
            auctions = true,
            bank = true
        }
    }
}
```

## How FLIPR Accesses This Data

1. **Building Group List**:
   - Iterate through all items in `userData@items`
   - Split each group path at backticks
   - Build a unique list of groups and their hierarchy

2. **Getting Operations**:
   - For each group, look up its operations in `userData@groups`
   - Get operation names for each TSM module (Shopping, Auctioning, etc.)
   - Check if operations are overridden at this group level

3. **Getting Operation Details**:
   - For each operation name, look up its settings in `userData@operations`
   - Access specific settings like maxPrice, minPrice, restockQuantity, etc.

## TSM Price Sources and Evaluation

### Sale Rate Handling
When working with sale rates in TSM:
1. **Individual Rate Values**:
   - When getting a single rate value (like dbregionsalerate), multiply by 1000
   - Then divide by 1000 when displaying
   - Example: `TSM_API.GetCustomPriceValue("DBRegionSaleRate*1000", itemString) / 1000`

2. **Complex Price Strings**:
   - When rates are used in price strings (like shopping operations), no multiplication needed
   - TSM handles the rate scaling internally in price string evaluation
   - Example: `ifgte(max(dbregionsalerate,0.001),0.1,...)` works without modification

### Price String Evaluation
- Use `TSM_API.GetCustomPriceValue(priceString, itemString)` for evaluation
- Returns nil when conditions aren't met (intentional "no" signal)
- Returns copper value when evaluation succeeds
- Example: `TSM_API.GetCustomPriceValue("min(dbmarket,dbregionmarketavg)", "i:2589")`

## Example Operation Types

### Shopping Operations
- maxPrice: Price calculation string
- restockQuantity: Quantity calculation string
- restockSources: Source locations for restocking
- showAboveMaxPrice: Boolean flag

### Auctioning Operations
- maxPrice: Maximum auction price
- minPrice: Minimum auction price
- normalPrice: Normal auction price
- undercut: Undercut amount
- keepQuantity: Amount to keep in bags

### Crafting Operations
- minProfit: Minimum profit threshold
- craftPriceMethod: How to calculate crafting cost
- minRestock: Minimum restock quantity
- maxRestock: Maximum restock quantity

## Notes
- All paths in group hierarchies use backticks (`) as separators
- Operations can be overridden at any level in the group hierarchy
- Price strings can use TSM's price sources (dbmarket, dbregionmarketavg, etc.)
- Some operations have module-specific settings not listed here
- Sale rates require special handling with *1000 multiplier when used individually 