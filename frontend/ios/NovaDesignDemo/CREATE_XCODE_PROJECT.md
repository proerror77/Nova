# Creating the Xcode Project for NovaDesignDemo

This guide provides multiple methods to create and open the NovaDesignDemo project in Xcode.

## Method 1: Using XcodeGen (Recommended)

XcodeGen is a command-line tool that generates Xcode projects from a YAML specification file.

### Prerequisites

Install XcodeGen using Homebrew:

```bash
brew install xcodegen
```

### Generate the Project

1. Navigate to the project directory:

```bash
cd /Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo
```

2. Generate the Xcode project:

```bash
xcodegen generate
```

This will create `NovaDesignDemo.xcodeproj` based on the `project.yml` file.

3. Open the project in Xcode:

```bash
open NovaDesignDemo.xcodeproj
```

---

## Method 2: Manual Xcode Project Creation

If you prefer to create the project manually or don't have XcodeGen:

### Step 1: Create New Project

1. Open Xcode
2. Select **File → New → Project**
3. Choose **iOS → App**
4. Click **Next**

### Step 2: Project Configuration

Configure the project with these settings:

- **Product Name**: `NovaDesignDemo`
- **Team**: Select your development team (or leave blank for personal use)
- **Organization Identifier**: `com.nova`
- **Bundle Identifier**: `com.nova.NovaDesignDemo`
- **Interface**: **SwiftUI**
- **Language**: **Swift**
- **Use Core Data**: Unchecked
- **Include Tests**: Optional

### Step 3: Save Location

Save the project to:

```
/Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo
```

**Important**: When saving, ensure you're saving inside the existing `NovaDesignDemo` directory.

### Step 4: Replace Default Files

1. Delete the default files Xcode created:
   - `ContentView.swift` (we have our own)
   - `NovaDesignDemoApp.swift` (we have our own)
   - Default `Assets.xcassets` folder

2. The project structure should now match:

```
NovaDesignDemo/
├── NovaDesignDemo.xcodeproj/
└── NovaDesignDemo/
    ├── NovaDesignDemoApp.swift
    ├── ContentView.swift
    ├── ThemeShowcaseView.swift
    ├── PostCard.swift
    ├── Theme.swift
    ├── Assets.xcassets/
    ├── Preview Content/
    └── Info.plist
```

### Step 5: Add Files to Xcode

1. In Xcode's Project Navigator (left sidebar), right-click on the `NovaDesignDemo` folder
2. Select **Add Files to "NovaDesignDemo"...**
3. Navigate to `/Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo/NovaDesignDemo`
4. Select all `.swift` files:
   - `NovaDesignDemoApp.swift`
   - `ContentView.swift`
   - `ThemeShowcaseView.swift`
   - `PostCard.swift`
   - `Theme.swift`
5. Ensure **"Copy items if needed"** is **UNCHECKED** (files are already in the correct location)
6. Ensure **"Create groups"** is selected
7. Click **Add**

### Step 6: Verify Asset Catalog

1. In the Project Navigator, verify that `Assets.xcassets` contains:
   - `AccentColor`
   - `AppIcon`
   - `brandA.light/` folder with 11 color sets
   - `brandA.dark/` folder with 11 color sets
   - `brandB.light/` folder with 11 color sets
   - `brandB.dark/` folder with 11 color sets

2. If the color sets are missing, manually drag the folders from Finder:
   - Open Finder and navigate to: `/Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo/NovaDesignDemo/Assets.xcassets`
   - Drag the `brandA.light`, `brandA.dark`, `brandB.light`, and `brandB.dark` folders into Xcode's Assets.xcassets

### Step 7: Build Settings

Verify these build settings in Xcode:

1. Select the project in Project Navigator
2. Select the `NovaDesignDemo` target
3. Go to **Build Settings**
4. Search for and verify:
   - **iOS Deployment Target**: 15.0 or higher
   - **Swift Language Version**: Swift 5

---

## Method 3: Using Swift Package Manager (Alternative)

Create a Package.swift file for SPM-based development:

```bash
cd /Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo
```

Then create a `Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NovaDesignDemo",
    platforms: [.iOS(.v15)],
    products: [
        .executable(name: "NovaDesignDemo", targets: ["NovaDesignDemo"])
    ],
    targets: [
        .executableTarget(
            name: "NovaDesignDemo",
            path: "NovaDesignDemo",
            resources: [.process("Assets.xcassets")]
        )
    ]
)
```

**Note**: SwiftUI apps with Asset Catalogs work best with Xcode projects, not pure SPM.

---

## Opening the Project

Once the project is created using any method:

```bash
open /Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo/NovaDesignDemo.xcodeproj
```

Or simply double-click `NovaDesignDemo.xcodeproj` in Finder.

---

## Selecting a Simulator

1. In Xcode's top toolbar, click the device selector (next to the scheme selector)
2. Choose a simulator:
   - **iPhone 15 Pro** (recommended)
   - **iPhone 14 Pro**
   - **iPad Pro (12.9-inch)**

---

## Building and Running

1. Ensure a simulator is selected
2. Press **⌘R** or click the **Play** button
3. The app should build and launch in the simulator

---

## Troubleshooting

### Issue: "No such module 'SwiftUI'"

**Solution**: Ensure the deployment target is iOS 15.0 or higher in Build Settings.

### Issue: Color resources not found

**Solution**:
1. Clean build folder: **Product → Clean Build Folder** (⇧⌘K)
2. Verify Asset Catalog contains all theme folders
3. Rebuild the project

### Issue: "Failed to build module"

**Solution**:
1. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
2. Restart Xcode
3. Rebuild

### Issue: Simulator not showing app

**Solution**:
1. Reset simulator: **Device → Erase All Content and Settings**
2. Quit and restart Simulator
3. Rebuild and run

---

## Next Steps

After successfully opening and building the project, proceed to the [VERIFICATION_CHECKLIST.md](./VERIFICATION_CHECKLIST.md) to verify the design system implementation.
