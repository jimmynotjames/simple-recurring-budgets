"""Repo paths shared by the localization pipelines, from i18n/app.json. Import; never restate."""

from app_config import REPO_ROOT, repo_path

# The app target's String Catalog.
CATALOG_PATH = repo_path("catalog")

# Production Swift sources scanned for unkeyed copy.
SOURCE_DIR = repo_path("source")

# Per-locale screenshot seed catalogs (UI-test target only; never ships).
SEEDS_DIR = repo_path("seeds")

__all__ = ["REPO_ROOT", "CATALOG_PATH", "SOURCE_DIR", "SEEDS_DIR"]
