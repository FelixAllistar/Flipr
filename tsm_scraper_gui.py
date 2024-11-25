import tkinter as tk
from tkinter import ttk, messagebox
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import re
import threading
import sys
import os
import argparse
from selenium.common.exceptions import WebDriverException

class BrowserDetector:
    @staticmethod
    def find_chrome():
        try:
            options = webdriver.ChromeOptions()
            options.add_argument('--headless')
            driver = webdriver.Chrome(options=options)
            driver.quit()
            return True
        except WebDriverException:
            return False

    @staticmethod
    def find_firefox():
        try:
            options = webdriver.FirefoxOptions()
            options.add_argument('--headless')
            driver = webdriver.Firefox(options=options)
            driver.quit()
            return True
        except WebDriverException:
            return False

    @staticmethod
    def find_edge():
        try:
            options = webdriver.EdgeOptions()
            options.add_argument('--headless')
            driver = webdriver.Edge(options=options)
            driver.quit()
            return True
        except WebDriverException:
            return False

    @staticmethod
    def get_available_browser():
        # Try browsers in order of preference
        if BrowserDetector.find_chrome():
            return ('chrome', webdriver.Chrome, webdriver.ChromeOptions)
        elif BrowserDetector.find_firefox():
            return ('firefox', webdriver.Firefox, webdriver.FirefoxOptions)
        elif BrowserDetector.find_edge():
            return ('edge', webdriver.Edge, webdriver.EdgeOptions)
        return None

class TSMScraper:
    @staticmethod
    def format_gold_to_copper(gold_string):
        """Convert TSM gold string (eg: '5g91s42c') to copper value"""
        total_copper = 0
        parts = re.findall(r'(\d+)([gsc])', gold_string)
        
        for value, unit in parts:
            if unit == 'g':
                total_copper += int(value) * 10000
            elif unit == 's':
                total_copper += int(value) * 100
            elif unit == 'c':
                total_copper += int(value)
                
        return total_copper / 10000

    @staticmethod
    def scrape_tsm_data(url, progress_callback=print):
        if not url or url.strip() == "":
            progress_callback("Error: URL cannot be empty")
            return {}

        progress_callback("Starting browser detection...")
        browser_info = BrowserDetector.get_available_browser()
        if not browser_info:
            progress_callback("No compatible browser found. Please install Chrome, Firefox, or Edge.")
            return {}

        browser_name, driver_class, options_class = browser_info
        progress_callback(f"Using {browser_name} browser...")

        options = options_class()
        options.add_argument('--headless')
        
        try:
            progress_callback("Launching browser...")
            driver = driver_class(options=options)
            progress_callback("Browser launched successfully")
            
            progress_callback(f"Navigating to URL: {url}")
            driver.get(url)
            progress_callback("Navigation complete")
            
            # Get master group name
            progress_callback("Looking for master group name...")
            try:
                master_group = driver.find_element(By.CSS_SELECTOR, 'h3[data-testid="group-path"]').text.strip()
                progress_callback(f"Found master group: {master_group}")
            except Exception as e:
                progress_callback(f"Warning: Could not find master group name: {str(e)}")
                progress_callback("Using default master group name")
                master_group = "Unknown"
            
            # Wait for table to load with more detailed progress
            progress_callback("Looking for data table...")
            wait = WebDriverWait(driver, 30)
            try:
                table = wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, 'table.table-auto')))
                progress_callback("Table found!")
            except Exception as e:
                progress_callback(f"Failed to find table: {str(e)}")
                progress_callback("Make sure this is a valid TSM group URL")
                driver.quit()
                return {}
            
            if not table:
                progress_callback("Table element is empty! Make sure this is a valid TSM group URL.")
                driver.quit()
                return {}
            
            progress_callback("Finding table rows...")
            try:
                rows = driver.find_elements(By.CSS_SELECTOR, 'table.table-auto tr')
                progress_callback("Successfully found table rows")
            except Exception as e:
                progress_callback(f"Error finding table rows: {str(e)}")
                driver.quit()
                return {}
            
            if not rows or len(rows) <= 1:  # Only header row or no rows
                progress_callback("No data found in table! Make sure this is a valid TSM group URL.")
                driver.quit()
                return {}
                
            progress_callback(f"Found {len(rows)-1} items")  # Subtract header row
            
            items_data = {}
            
            # Skip header row
            for i, row in enumerate(rows[1:], 1):
                progress_callback(f"Processing row {i}/{len(rows)-1}")
                try:
                    columns = row.find_elements(By.TAG_NAME, 'td')
                    if len(columns) >= 4:
                        try:
                            name_element = columns[0].find_element(By.TAG_NAME, 'a')
                        except:
                            progress_callback(f"Skipping row {i} - no item link found")
                            continue
                        
                        name = name_element.text.strip().replace('"', '')
                        # Prefix master group to subgroup
                        subgroup = f"{master_group}/{columns[1].text.strip()}"
                        market_value = columns[2].text.strip()
                        sale_rate = columns[3].text.strip()
                        
                        if not all([name, subgroup, market_value, sale_rate]):
                            progress_callback(f"Skipping row {i} - missing required data")
                            continue
                        
                        href = name_element.get_attribute('href')
                        item_id = href.split('/')[-1] if href else None
                        
                        if item_id:
                            try:
                                items_data[item_id] = {
                                    'name': name,
                                    'subGroup': subgroup,
                                    'marketValue': TSMScraper.format_gold_to_copper(market_value),
                                    'saleRate': float(sale_rate) if sale_rate != 'n/a' else 0
                                }
                            except ValueError as e:
                                progress_callback(f"Error processing row {i}: {str(e)}")
                                continue
                except Exception as e:
                    progress_callback(f"Error processing row {i}: {str(e)}")
                    continue
            
            driver.quit()
            
            if not items_data:
                progress_callback("No valid items found in the group!")
                return {}
                
            return items_data
        except Exception as e:
            progress_callback(f"Error: {str(e)}")
            try:
                driver.quit()
            except:
                pass
            return {}

    @staticmethod
    def split_and_save_data(items_data, progress_callback=print):
        # Initialize dictionary to organize items by their full path
        organized_data = {}
        master_group = None
        
        # First pass: organize items and detect master group
        for item_id, data in items_data.items():
            subGroup = data['subGroup']
            # Extract master group from first item's subGroup
            if master_group is None:
                master_group = subGroup.split('/')[0]
            
            if subGroup not in organized_data:
                organized_data[subGroup] = []
            organized_data[subGroup].append({
                'id': item_id,
                'comment': data['name'],
                'name': data['name'],
                'subGroup': subGroup,
                'marketValue': data['marketValue'],
                'saleRate': data['saleRate']
            })

        # Get output directory (same as executable location)
        output_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
        filepath = os.path.join(output_dir, "DataTables.lua")
        
        # Read existing file content if it exists
        existing_content = ""
        existing_groups = set()
        if os.path.exists(filepath):
            with open(filepath, 'r', encoding='utf-8') as file:
                existing_content = file.read()
                # Find existing group names using regex
                for match in re.finditer(r'FLIPR_(\w+)\s*=\s*{', existing_content):
                    existing_groups.add(match.group(1))
        
        # Remove old version of this group if it exists
        safe_master = master_group.replace(' ', '')
        if safe_master in existing_groups:
            progress_callback(f"Removing existing group: {master_group}")
            # Use regex to remove the entire group definition
            pattern = f"FLIPR_{safe_master}\\s*=\\s*{{[^}}]*}}\\s*\n"
            existing_content = re.sub(pattern, '', existing_content)
        
        progress_callback(f"Writing {filepath}...")
        
        with open(filepath, 'w', encoding='utf-8') as file:
            # If file was empty or didn't exist, write the initial comment
            if not existing_content:
                file.write("-- Auto-generated by TSM Scraper\n\n")
            else:
                file.write(existing_content)
                if not existing_content.endswith('\n\n'):
                    file.write('\n\n')
            
            # Create the master table
            master_var = f"FLIPR_{master_group.replace(' ', '')}"
            file.write(f"{master_var} = {{\n")
            file.write("    -- Master group information\n")
            file.write(f"    name = \"{master_group}\",\n")
            file.write("    groups = {},\n")
            file.write("    items = {},\n")
            
            # Write helper function
            file.write(f"    GetItemsByGroup = function(self, group)\n")
            file.write("        if group == nil then\n")
            file.write("            return self.items\n")
            file.write("        end\n")
            file.write("        local items = {}\n")
            file.write("        for id, item in pairs(self.items) do\n")
            file.write("            if item.subGroup:find(group, 1, true) then\n")
            file.write("                items[id] = item\n")
            file.write("            end\n")
            file.write("        end\n")
            file.write("        return items\n")
            file.write("    end,\n")
            
            # Write groups table
            file.write("    groups = {\n")
            for group in sorted(organized_data.keys()):
                # Remove master group from display name but keep in key for uniqueness
                display_name = group.replace(f"{master_group}/", "")
                safe_group = group.replace(' ', '_').replace('/', '_').replace('+', 'plus')
                file.write(f"        [\"{safe_group}\"] = \"{display_name}\",\n")
            file.write("    },\n")
            
            # Write items table
            file.write("    items = {\n")
            for group, items in organized_data.items():
                file.write(f"        -- {group}\n")
                for item in sorted(items, key=lambda x: int(x['id'])):
                    file.write(f"        [{item['id']}] = {{ -- {item['comment']}\n")
                    file.write(f"            name = \"{item['name']}\",\n")
                    file.write(f"            subGroup = \"{item['subGroup']}\",\n")
                    file.write(f"            marketValue = {item['marketValue']},\n")
                    file.write(f"            saleRate = {item['saleRate']}\n")
                    file.write("        },\n")
            file.write("    }\n")
            file.write("}\n")

class TSMScraperGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("TSM Data Scraper")
        self.root.geometry("800x600")
        
        # Configure style
        style = ttk.Style()
        style.configure('TButton', padding=5)
        style.configure('TFrame', padding=10)
        
        # Create main frame
        main_frame = ttk.Frame(root)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # URL frame
        url_frame = ttk.Frame(main_frame)
        url_frame.pack(fill=tk.X, pady=(0, 10))
        
        # URL input with label
        ttk.Label(url_frame, text="TSM URL:", font=('Segoe UI', 10)).pack(side=tk.LEFT)
        self.url_var = tk.StringVar()
        self.url_entry = ttk.Entry(url_frame, textvariable=self.url_var, width=70)
        self.url_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(10, 0))
        
        # Progress frame
        progress_frame = ttk.Frame(main_frame)
        progress_frame.pack(fill=tk.BOTH, expand=True)
        
        # Progress text with scrollbar
        self.progress_text = tk.Text(progress_frame, height=20, width=80, font=('Consolas', 10))
        scrollbar = ttk.Scrollbar(progress_frame, orient=tk.VERTICAL, command=self.progress_text.yview)
        self.progress_text.configure(yscrollcommand=scrollbar.set)
        
        self.progress_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        # Button frame
        button_frame = ttk.Frame(main_frame)
        button_frame.pack(fill=tk.X, pady=(10, 0))
        
        # Start button
        self.start_button = ttk.Button(
            button_frame,
            text="Start Scraping",
            command=self.start_scraping,
            style='TButton'
        )
        self.start_button.pack(pady=5)
        
        # Status label
        self.status_var = tk.StringVar(value="Ready")
        self.status_label = ttk.Label(
            button_frame,
            textvariable=self.status_var,
            font=('Segoe UI', 9)
        )
        self.status_label.pack(pady=5)
        
        # Check for available browsers
        browser_info = BrowserDetector.get_available_browser()
        if browser_info:
            self.log(f"Found {browser_info[0]} browser!")
        else:
            self.log("WARNING: No compatible browser found!")
            self.log("Please install Chrome, Firefox, or Edge to use this application.")
        
        # Add initial instructions
        self.log("\nWelcome to TSM Data Scraper!")
        self.log("1. Paste your TSM URL in the input field above")
        self.log("2. Click 'Start Scraping' to begin")
        self.log("3. Wait for the process to complete")
        self.log("\nThe program will create separate .lua files for different item groups.")

    def log(self, message):
        self.progress_text.insert(tk.END, message + "\n")
        self.progress_text.see(tk.END)
        self.root.update_idletasks()

    def start_scraping(self):
        url = self.url_var.get().strip()
        if not url:
            messagebox.showerror("Error", "Please enter a TSM URL")
            return
        
        self.start_button.state(['disabled'])
        self.progress_text.delete(1.0, tk.END)
        self.status_var.set("Scraping in progress...")
        
        def scrape_thread():
            try:
                items_data = TSMScraper.scrape_tsm_data(url, self.log)
                if items_data:
                    self.log("Splitting and saving data...")
                    TSMScraper.split_and_save_data(items_data, self.log)
                    self.log("Done! All files have been created.")
                    self.status_var.set("Completed successfully!")
                else:
                    self.log("No data was scraped. Please check the URL and try again.")
                    self.status_var.set("Failed to scrape data")
            except Exception as e:
                self.log(f"Error: {str(e)}")
                self.status_var.set("Error occurred")
            finally:
                self.start_button.state(['!disabled'])
        
        thread = threading.Thread(target=scrape_thread)
        thread.daemon = True
        thread.start()

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='TSM Data Scraper')
    parser.add_argument('-url', '--url', help='TSM URL to scrape')
    args = parser.parse_args()

    # If URL is provided, run in CLI mode
    if args.url:
        print(f"Scraping URL: {args.url}")
        items_data = TSMScraper.scrape_tsm_data(args.url)
        if items_data:
            TSMScraper.split_and_save_data(items_data)
            print("Done! All files have been created.")
        else:
            print("No data was scraped. Please check the URL and try again.")
        return

    # Otherwise, launch GUI
    root = tk.Tk()
    root.iconbitmap(default=None)
    app = TSMScraperGUI(root)
    root.mainloop()

if __name__ == '__main__':
    main() 