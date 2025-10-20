#!/bin/bash

#
# build_and_open.sh
# NovaDesignDemo
#
# Quick script to generate Xcode project and open it
# Copyright © 2025 Nova. All rights reserved.
#

set -e  # Exit on error

echo "🎨 NovaDesignDemo - Build and Open Script"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "project.yml" ]; then
    echo "❌ Error: project.yml not found"
    echo "   Please run this script from the NovaDesignDemo directory"
    exit 1
fi

# Check if xcodegen is installed
if ! command -v xcodegen &> /dev/null; then
    echo "⚠️  XcodeGen not found"
    echo ""
    echo "Installing XcodeGen via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "❌ Homebrew not found. Please install XcodeGen manually:"
        echo "   brew install xcodegen"
        echo ""
        echo "Or install Homebrew first:"
        echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
fi

echo "✅ XcodeGen found"
echo ""

# Generate Xcode project
echo "🔨 Generating Xcode project..."
xcodegen generate

if [ $? -eq 0 ]; then
    echo "✅ Xcode project generated successfully"
    echo ""
else
    echo "❌ Failed to generate Xcode project"
    exit 1
fi

# Check if xcodeproj was created
if [ ! -d "NovaDesignDemo.xcodeproj" ]; then
    echo "❌ NovaDesignDemo.xcodeproj not found after generation"
    exit 1
fi

# Open in Xcode
echo "🚀 Opening in Xcode..."
open NovaDesignDemo.xcodeproj

echo ""
echo "=========================================="
echo "✅ Success! NovaDesignDemo is now open in Xcode"
echo ""
echo "Next steps:"
echo "  1. Select iPhone 15 Pro simulator in Xcode"
echo "  2. Press ⌘R to build and run"
echo "  3. Test theme switching"
echo "  4. Refer to VERIFICATION_CHECKLIST.md for detailed testing"
echo ""
echo "Happy theming! 🎨"
