"""Repo paths shared by the localization pipelines. Import; never restate."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# The app target's String Catalog.
CATALOG_PATH = REPO_ROOT / "simple-recurring-budgets" / "Resources" / "Localizable.xcstrings"

# Production Swift sources scanned for unkeyed copy.
SOURCE_DIR = REPO_ROOT / "simple-recurring-budgets"
