#!/usr/bin/env python3
import json
import os

def hex_to_rgb(hex_color):
    """Convert hex color to normalized RGB values"""
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16) / 255.0
    g = int(hex_color[2:4], 16) / 255.0
    b = int(hex_color[4:6], 16) / 255.0
    return f"{r:.3f}", f"{g:.3f}", f"{b:.3f}"

def create_colorset(directory, color_name, hex_value):
    """Create a .colorset directory with Contents.json"""
    colorset_dir = os.path.join(directory, f"{color_name}.colorset")
    os.makedirs(colorset_dir, exist_ok=True)

    r, g, b = hex_to_rgb(hex_value)

    contents = {
        "colors": [
            {
                "idiom": "universal",
                "color": {
                    "color-space": "srgb",
                    "components": {
                        "red": r,
                        "green": g,
                        "blue": b,
                        "alpha": "1.000"
                    }
                }
            }
        ],
        "info": {
            "version": 1,
            "author": "xcode"
        }
    }

    contents_path = os.path.join(colorset_dir, "Contents.json")
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)

# Define all theme colors
themes = {
    "brandA.light": {
        "bgSurface": "#FFFFFF",
        "bgElevated": "#F9FAFB",
        "fgPrimary": "#101828",
        "fgSecondary": "#475467",
        "brandPrimary": "#0086C9",
        "brandOn": "#FFFFFF",
        "borderSubtle": "#E4E7EC",
        "borderStrong": "#D0D5DD",
        "stateSuccess": "#12B76A",
        "stateWarning": "#F79009",
        "stateDanger": "#F04438"
    },
    "brandA.dark": {
        "bgSurface": "#101828",
        "bgElevated": "#1D2939",
        "fgPrimary": "#FFFFFF",
        "fgSecondary": "#98A2B3",
        "brandPrimary": "#0BA5EC",
        "brandOn": "#001119",
        "borderSubtle": "#1D2939",
        "borderStrong": "#344054",
        "stateSuccess": "#12B76A",
        "stateWarning": "#F79009",
        "stateDanger": "#F97066"
    },
    "brandB.light": {
        "bgSurface": "#FFFFFF",
        "bgElevated": "#F9FAFB",
        "fgPrimary": "#101828",
        "fgSecondary": "#475467",
        "brandPrimary": "#F04438",
        "brandOn": "#FFFFFF",
        "borderSubtle": "#E4E7EC",
        "borderStrong": "#D0D5DD",
        "stateSuccess": "#12B76A",
        "stateWarning": "#F79009",
        "stateDanger": "#D92D20"
    },
    "brandB.dark": {
        "bgSurface": "#101828",
        "bgElevated": "#1D2939",
        "fgPrimary": "#FFFFFF",
        "fgSecondary": "#98A2B3",
        "brandPrimary": "#F97066",
        "brandOn": "#2A0A08",
        "borderSubtle": "#1D2939",
        "borderStrong": "#344054",
        "stateSuccess": "#12B76A",
        "stateWarning": "#F79009",
        "stateDanger": "#F04438"
    }
}

# Base directory
base_dir = "/Users/proerror/Documents/nova/frontend/ios/DesignTokens"

# Generate all colorsets
for theme_name, colors in themes.items():
    theme_dir = os.path.join(base_dir, theme_name)
    print(f"Generating {theme_name}...")
    for color_name, hex_value in colors.items():
        create_colorset(theme_dir, color_name, hex_value)
        print(f"  Created {color_name}")

print("\nAll colorsets generated successfully!")
