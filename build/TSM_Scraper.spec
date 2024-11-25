# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['..\\tsm_scraper_gui.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['selenium', 'selenium.webdriver', 'selenium.webdriver.chrome.service', 'selenium.webdriver.chrome.webdriver', 'selenium.webdriver.firefox.service', 'selenium.webdriver.firefox.webdriver', 'selenium.webdriver.edge.service', 'selenium.webdriver.edge.webdriver', 'selenium.webdriver.common.by', 'selenium.webdriver.support.wait', 'selenium.webdriver.support.expected_conditions', 'tkinter', 'tkinter.ttk'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='TSM_Scraper',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
