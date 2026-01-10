#!/bin/bash

# Script to add LiveKit SDK to Xcode project
# This script adds the LiveKit Swift SDK package dependency to the ICERED project

set -e

PROJECT_FILE="ICERED.xcodeproj/project.pbxproj"
BACKUP_FILE="ICERED.xcodeproj/project.pbxproj.backup"

echo "🔧 Adding LiveKit SDK to Xcode project..."

# Create backup
cp "$PROJECT_FILE" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"

# Generate unique IDs for the new package reference
PACKAGE_REF_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | tr '[:lower:]' '[:upper:]')
PRODUCT_DEP_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | tr '[:upper:]' '[:upper:]')

echo "📦 Package Reference ID: $PACKAGE_REF_ID"
echo "📦 Product Dependency ID: $PRODUCT_DEP_ID"

# Step 1: Add package reference to packageReferences array
echo "📝 Adding package reference..."
sed -i '' "/packageReferences = (/a\\
				$PACKAGE_REF_ID /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */,
" "$PROJECT_FILE"

# Step 2: Add XCRemoteSwiftPackageReference section entry
echo "📝 Adding XCRemoteSwiftPackageReference entry..."
sed -i '' "/\/\* End XCRemoteSwiftPackageReference section \*\//i\\
		$PACKAGE_REF_ID /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */ = {\\
			isa = XCRemoteSwiftPackageReference;\\
			repositoryURL = \"https://github.com/livekit/client-sdk-swift.git\";\\
			requirement = {\\
				kind = upToNextMajorVersion;\\
				minimumVersion = 2.0.0;\\
			};\\
		};\\

" "$PROJECT_FILE"

# Step 3: Add XCSwiftPackageProductDependency entry
echo "📝 Adding XCSwiftPackageProductDependency entry..."
sed -i '' "/\/\* End XCSwiftPackageProductDependency section \*\//i\\
		$PRODUCT_DEP_ID /* LiveKit */ = {\\
			isa = XCSwiftPackageProductDependency;\\
			package = $PACKAGE_REF_ID /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */;\\
			productName = LiveKit;\\
		};\\

" "$PROJECT_FILE"

# Step 4: Add product dependency to ICERED target's packageProductDependencies
echo "📝 Adding product dependency to ICERED target..."
# Find the ICERED target's packageProductDependencies array and add our dependency
sed -i '' "/packageProductDependencies = (/,/);/{
    /);/i\\
				$PRODUCT_DEP_ID /* LiveKit */,
}" "$PROJECT_FILE"

echo "✅ LiveKit SDK has been added to the project!"
echo ""
echo "⚠️  IMPORTANT: Next steps:"
echo "1. Open the project in Xcode"
echo "2. Xcode will automatically resolve the package"
echo "3. Build the project to verify the integration"
echo ""
echo "If something goes wrong, restore from backup:"
echo "   cp $BACKUP_FILE $PROJECT_FILE"
