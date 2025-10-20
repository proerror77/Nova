#!/bin/bash

#
# validate_project.sh
# NovaDesignDemo
#
# Validates the project structure before opening in Xcode
# Copyright © 2025 Nova. All rights reserved.
#

echo "🔍 NovaDesignDemo - Project Validation"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

errors=0
warnings=0

# Function to check file exists
check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✅${NC} $1"
    else
        echo -e "${RED}❌${NC} Missing: $1"
        ((errors++))
    fi
}

# Function to check directory exists
check_dir() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✅${NC} $1"
    else
        echo -e "${RED}❌${NC} Missing: $1"
        ((errors++))
    fi
}

# Function to count files in directory
count_files() {
    count=$(ls -1 "$1" 2>/dev/null | wc -l | tr -d ' ')
    echo "$count"
}

echo "1. Checking Swift Source Files"
echo "-------------------------------"
check_file "NovaDesignDemo/NovaDesignDemoApp.swift"
check_file "NovaDesignDemo/ContentView.swift"
check_file "NovaDesignDemo/ThemeShowcaseView.swift"
check_file "NovaDesignDemo/PostCard.swift"
check_file "NovaDesignDemo/Theme.swift"
echo ""

echo "2. Checking Configuration Files"
echo "--------------------------------"
check_file "NovaDesignDemo/Info.plist"
check_file "project.yml"
echo ""

echo "3. Checking Asset Catalog"
echo "-------------------------"
check_dir "NovaDesignDemo/Assets.xcassets"
check_file "NovaDesignDemo/Assets.xcassets/Contents.json"
check_dir "NovaDesignDemo/Assets.xcassets/AccentColor.colorset"
check_dir "NovaDesignDemo/Assets.xcassets/AppIcon.appiconset"
echo ""

echo "4. Checking Theme Color Sets"
echo "-----------------------------"

# Brand A Light
check_dir "NovaDesignDemo/Assets.xcassets/brandA.light"
brandA_light_count=$(count_files "NovaDesignDemo/Assets.xcassets/brandA.light")
if [ "$brandA_light_count" -eq 11 ]; then
    echo -e "${GREEN}✅${NC} Brand A Light: $brandA_light_count color sets"
else
    echo -e "${YELLOW}⚠️${NC}  Brand A Light: Expected 11, found $brandA_light_count"
    ((warnings++))
fi

# Brand A Dark
check_dir "NovaDesignDemo/Assets.xcassets/brandA.dark"
brandA_dark_count=$(count_files "NovaDesignDemo/Assets.xcassets/brandA.dark")
if [ "$brandA_dark_count" -eq 11 ]; then
    echo -e "${GREEN}✅${NC} Brand A Dark: $brandA_dark_count color sets"
else
    echo -e "${YELLOW}⚠️${NC}  Brand A Dark: Expected 11, found $brandA_dark_count"
    ((warnings++))
fi

# Brand B Light
check_dir "NovaDesignDemo/Assets.xcassets/brandB.light"
brandB_light_count=$(count_files "NovaDesignDemo/Assets.xcassets/brandB.light")
if [ "$brandB_light_count" -eq 11 ]; then
    echo -e "${GREEN}✅${NC} Brand B Light: $brandB_light_count color sets"
else
    echo -e "${YELLOW}⚠️${NC}  Brand B Light: Expected 11, found $brandB_light_count"
    ((warnings++))
fi

# Brand B Dark
check_dir "NovaDesignDemo/Assets.xcassets/brandB.dark"
brandB_dark_count=$(count_files "NovaDesignDemo/Assets.xcassets/brandB.dark")
if [ "$brandB_dark_count" -eq 11 ]; then
    echo -e "${GREEN}✅${NC} Brand B Dark: $brandB_dark_count color sets"
else
    echo -e "${YELLOW}⚠️${NC}  Brand B Dark: Expected 11, found $brandB_dark_count"
    ((warnings++))
fi

echo ""
echo "5. Checking Required Color Sets (Brand A Light)"
echo "------------------------------------------------"
colors=("bgSurface" "bgElevated" "fgPrimary" "fgSecondary" "brandPrimary" "brandOn" "borderSubtle" "borderStrong" "stateSuccess" "stateWarning" "stateDanger")
for color in "${colors[@]}"; do
    check_dir "NovaDesignDemo/Assets.xcassets/brandA.light/${color}.colorset"
done

echo ""
echo "6. Checking Documentation Files"
echo "--------------------------------"
check_file "README.md"
check_file "CREATE_XCODE_PROJECT.md"
check_file "VERIFICATION_CHECKLIST.md"
check_file "QUICK_REFERENCE.md"
check_file "DELIVERY_SUMMARY.md"
check_file "PROJECT_STRUCTURE.txt"
echo ""

echo "7. Checking Build Scripts"
echo "--------------------------"
check_file "build_and_open.sh"
if [ -f "build_and_open.sh" ]; then
    if [ -x "build_and_open.sh" ]; then
        echo -e "${GREEN}✅${NC} build_and_open.sh is executable"
    else
        echo -e "${YELLOW}⚠️${NC}  build_and_open.sh is not executable (run: chmod +x build_and_open.sh)"
        ((warnings++))
    fi
fi
echo ""

echo "8. Checking Preview Content"
echo "----------------------------"
check_dir "NovaDesignDemo/Preview Content"
check_dir "NovaDesignDemo/Preview Content/Preview Assets.xcassets"
echo ""

# Summary
echo "======================================"
echo "Validation Summary"
echo "======================================"
total_color_sets=$((brandA_light_count + brandA_dark_count + brandB_light_count + brandB_dark_count))
echo "Total color sets: $total_color_sets / 44"

if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo ""
    echo "Project is ready to open in Xcode."
    echo "Run: ./build_and_open.sh"
    exit 0
elif [ $errors -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Validation completed with $warnings warning(s)${NC}"
    echo ""
    echo "Project should work, but check warnings above."
    echo "Run: ./build_and_open.sh"
    exit 0
else
    echo -e "${RED}❌ Validation failed with $errors error(s) and $warnings warning(s)${NC}"
    echo ""
    echo "Please fix the errors above before opening in Xcode."
    exit 1
fi
