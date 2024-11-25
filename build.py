import PyInstaller.__main__
import sys
import os
import shutil

def cleanup():
    """Clean up build artifacts"""
    print("Cleaning up old build files...")
    paths_to_remove = ['build', 'dist', '__pycache__']
    files_to_remove = [f for f in os.listdir('.') if f.endswith('.spec')]
    
    for path in paths_to_remove:
        if os.path.exists(path):
            try:
                shutil.rmtree(path)
                print(f"Removed {path}/")
            except Exception as e:
                print(f"Error removing {path}: {e}")
    
    for file in files_to_remove:
        try:
            os.remove(file)
            print(f"Removed {file}")
        except Exception as e:
            print(f"Error removing {file}: {e}")

# Clean up before building
cleanup()

# Get the directory of this script
script_dir = os.path.dirname(os.path.abspath(__file__))

print("\nStarting build process...")
# Define the spec
PyInstaller.__main__.run([
    'tsm_scraper_gui.py',
    '--onefile',
    '--windowed',
    '--name=TSM_Scraper',
    '--clean',
    '--distpath=./dist',
    '--workpath=./build',
    '--specpath=./build',
    # Add hidden imports for selenium
    '--hidden-import=selenium',
    '--hidden-import=selenium.webdriver',
    '--hidden-import=selenium.webdriver.chrome.service',
    '--hidden-import=selenium.webdriver.chrome.webdriver',
    '--hidden-import=selenium.webdriver.firefox.service',
    '--hidden-import=selenium.webdriver.firefox.webdriver',
    '--hidden-import=selenium.webdriver.edge.service',
    '--hidden-import=selenium.webdriver.edge.webdriver',
    '--hidden-import=selenium.webdriver.common.by',
    '--hidden-import=selenium.webdriver.support.wait',
    '--hidden-import=selenium.webdriver.support.expected_conditions',
    # Add tkinter imports
    '--hidden-import=tkinter',
    '--hidden-import=tkinter.ttk',
    # Clean up the spec
    '--noconfirm',
]) 