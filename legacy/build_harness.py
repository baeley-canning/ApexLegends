#!/usr/bin/env python3
"""Builds the harness package files."""
import pathlib

ROOT = pathlib.Path(r"c:/Users/New User/OneDrive/Desktop/cheating/harness")
ROOT.mkdir(parents=True, exist_ok=True)

# __init__.py
(ROOT / "__init__.py").write_text(
    'from .harness import CheaterAPIHarness, GameSpec, EntityStruct\n'
    '__all__ = ["CheaterAPIHarness", "GameSpec", "EntityStruct"]\n'
)

print("Created __init__.py")
