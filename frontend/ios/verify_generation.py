#!/usr/bin/env python3
"""
Verification script for iOS Design System generation
Checks that all expected files exist and are valid
"""

import os
import json
from pathlib import Path

# Expected structure
EXPECTED_THEMES = ["brandA.light", "brandA.dark", "brandB.light", "brandB.dark"]
EXPECTED_COLORS = [
    "bgSurface", "bgElevated", "fgPrimary", "fgSecondary",
    "brandPrimary", "brandOn", "borderSubtle", "borderStrong",
    "stateSuccess", "stateWarning", "stateDanger"
]

BASE_DIR = Path("/Users/proerror/Documents/nova/frontend/ios")
TOKENS_DIR = BASE_DIR / "DesignTokens"

def verify_colorset(colorset_path):
    """Verify a .colorset directory and its Contents.json"""
    contents_path = colorset_path / "Contents.json"

    if not contents_path.exists():
        return False, f"Missing Contents.json in {colorset_path.name}"

    try:
        with open(contents_path) as f:
            data = json.load(f)

        # Verify structure
        if "colors" not in data or "info" not in data:
            return False, f"Invalid structure in {colorset_path.name}"

        # Verify color components
        color_obj = data["colors"][0]["color"]
        components = color_obj.get("components", {})

        required_components = ["red", "green", "blue", "alpha"]
        for comp in required_components:
            if comp not in components:
                return False, f"Missing {comp} component in {colorset_path.name}"

        return True, "OK"

    except Exception as e:
        return False, f"Error reading {colorset_path.name}: {str(e)}"

def verify_theme(theme_name):
    """Verify all colors for a theme"""
    theme_dir = TOKENS_DIR / theme_name

    if not theme_dir.exists():
        return False, f"Theme directory {theme_name} not found"

    errors = []
    for color_name in EXPECTED_COLORS:
        colorset_dir = theme_dir / f"{color_name}.colorset"
        if not colorset_dir.exists():
            errors.append(f"  ❌ Missing {color_name}.colorset")
        else:
            is_valid, message = verify_colorset(colorset_dir)
            if not is_valid:
                errors.append(f"  ❌ {message}")

    if errors:
        return False, "\n".join(errors)

    return True, f"✅ All {len(EXPECTED_COLORS)} colors present"

def verify_swift_files():
    """Verify Swift implementation files"""
    required_files = {
        "Theme.swift": BASE_DIR / "Theme.swift",
        "ExamplePostCard.swift": BASE_DIR / "ExamplePostCard.swift",
        "README.md": BASE_DIR / "README.md"
    }

    results = {}
    for name, path in required_files.items():
        if path.exists():
            size = path.stat().st_size
            results[name] = (True, f"✅ Present ({size:,} bytes)")
        else:
            results[name] = (False, "❌ Missing")

    return results

def main():
    print("=" * 60)
    print("iOS Design System Verification")
    print("=" * 60)
    print()

    # Verify color assets
    print("📁 Color Assets (xcassets)")
    print("-" * 60)

    total_colors = 0
    for theme_name in EXPECTED_THEMES:
        is_valid, message = verify_theme(theme_name)
        print(f"\n{theme_name}:")
        print(f"{message}")
        if is_valid:
            total_colors += len(EXPECTED_COLORS)

    print()
    print(f"Total colorsets generated: {total_colors} / {len(EXPECTED_THEMES) * len(EXPECTED_COLORS)}")
    print()

    # Verify Swift files
    print("📄 Swift Implementation Files")
    print("-" * 60)

    swift_results = verify_swift_files()
    for filename, (is_valid, message) in swift_results.items():
        print(f"{filename:25s} {message}")

    print()

    # Summary
    print("=" * 60)
    print("Summary")
    print("=" * 60)

    all_valid = (
        total_colors == len(EXPECTED_THEMES) * len(EXPECTED_COLORS) and
        all(is_valid for is_valid, _ in swift_results.values())
    )

    if all_valid:
        print("✅ ALL CHECKS PASSED")
        print()
        print("Generated files:")
        print(f"  • {len(EXPECTED_THEMES)} theme directories")
        print(f"  • {total_colors} color asset bundles")
        print(f"  • {len(swift_results)} Swift/documentation files")
        print()
        print("Next steps:")
        print("  1. Open Xcode")
        print("  2. Add DesignTokens/ folder to your project")
        print("  3. Add Theme.swift to your target")
        print("  4. Run ExamplePostCard_Previews to test")
        return 0
    else:
        print("❌ SOME CHECKS FAILED")
        print("Review errors above and re-run generation if needed.")
        return 1

if __name__ == "__main__":
    exit(main())
