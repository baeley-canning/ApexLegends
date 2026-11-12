r"""h399 -- find CURRENT DTB, not talk about endless transport alternatives.

Vendor gdrv3 dynamic `Read MSR`/`Map Locked Pages` families are already installed.
MmGetPhysicalAddress has a driver-side handler; its original API had a suspected
bad shape. By reading actual jump-table dispatch we can recover the shape and
translate only proper kernel-context addresses. Search the proc name only if
pinned from the native row. No game modifications, no injected hooks.
"""
import os
import sys
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
# Read documentation of installed bridge so this stays an existing-driver path.
import gio, dumplive as dl, qk_va, qk_gdrv_mapread