from playwright.sync_api import sync_playwright
import re
import time

def format_gold_to_copper(gold_string):
    """Convert TSM gold string (eg: '5g91s42c') to copper value"""
    total_copper = 0
    # Find all numbers followed by g/s/c
    parts = re.findall(r'(\d+)([gsc])', gold_string)
    
    for value, unit in parts:
        if unit == 'g':
            total_copper += int(value) * 10000
        elif unit == 's':
            total_copper += int(value) * 100
        elif unit == 'c':
            total_copper += int(value)
            
    return total_copper / 10000  # Return as gold value

def scrape_tsm_data():
    with sync_playwright() as p:
        try:
            print("Launching browser...")
            browser = p.firefox.launch(headless=True)
            print("Browser launched successfully")
            
            page = browser.new_page()
            print("Page created")
            
            print("Navigating to TSM page...")
            page.goto('https://tradeskillmaster.com/retail/groups/01ja39m84ewbxe2bg7ehms868b')
            
            print("Waiting for table to load...")
            table = page.wait_for_selector('table.table-auto', timeout=30000)
            
            if not table:
                print("Table not found!")
                browser.close()
                return {}
            
            print("Finding table rows...")
            rows = page.query_selector_all('table.table-auto tr')
            print(f"Found {len(rows)} rows")
            
            items_data = {}
            
            # Skip header row
            for i, row in enumerate(rows[1:], 1):
                print(f"Processing row {i}...")
                columns = row.query_selector_all('td')
                if len(columns) >= 4:
                    # Extract item name and clean it
                    name_element = columns[0].query_selector('a')
                    if not name_element:
                        continue
                    
                    name = name_element.inner_text().strip().replace('"', '')
                    print(f"Found item: {name}")
                    
                    # Extract other data
                    subgroup = columns[1].inner_text().strip()
                    market_value = columns[2].inner_text().strip()
                    sale_rate = columns[3].inner_text().strip()
                    
                    # Extract item ID from href
                    href = name_element.get_attribute('href')
                    item_id = href.split('/')[-1] if href else None
                    
                    if item_id:
                        items_data[item_id] = {
                            'name': name,
                            'subGroup': subgroup,
                            'marketValue': format_gold_to_copper(market_value),
                            'saleRate': float(sale_rate) if sale_rate != 'n/a' else 0
                        }
            
            print("Closing browser...")
            browser.close()
            return items_data
        except Exception as e:
            print(f"Failed to launch browser: {e}")
            return {}

def generate_lua_file(items_data):
    with open('Data.lua', 'w', encoding='utf-8') as f:
        f.write('-- Auto-generated by data scraper\n')
        f.write('MyAddon_ItemDatabase = {\n')
        
        for item_id, data in items_data.items():
            f.write(f'    [{item_id}] = {{ -- {data["name"]}\n')
            f.write(f'        name = "{data["name"]}",\n')
            f.write(f'        subGroup = "{data["subGroup"]}",\n')
            f.write(f'        marketValue = {data["marketValue"]},\n')
            f.write(f'        saleRate = {data["saleRate"]}\n')
            f.write('    },\n')
        
        f.write('}\n')

def main():
    print("Starting TSM data scraping...")
    items_data = scrape_tsm_data()
    print(f"Scraped {len(items_data)} items")
    
    print("Generating Data.lua file...")
    generate_lua_file(items_data)
    print("Done! Data.lua has been created")

if __name__ == '__main__':
    main() 