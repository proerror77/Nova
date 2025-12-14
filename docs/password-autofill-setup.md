# iOS Password AutoFill Setup Guide

This guide explains how to enable password autofill for the ICERED iOS app with both Apple iCloud Keychain and Google Password Manager.

## iOS App Changes (Already Completed)

### 1. LoginView.swift
Added `textContentType` modifiers:
- Email field: `.textContentType(.username)`
- Password field: `.textContentType(.password)`

### 2. ICERED.entitlements
Added Associated Domains:
```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>webcredentials:icered.com</string>
    <string>webcredentials:app.icered.com</string>
</array>
```

## Backend Setup Required

### Step 1: Create `.well-known` directory

On your web server (icered.com), create a `.well-known` directory at the root level.

### Step 2: Apple - apple-app-site-association

Create file: `https://icered.com/.well-known/apple-app-site-association`

**Important:** This file must be served:
- WITHOUT `.json` extension
- With `Content-Type: application/json`
- Over HTTPS (no redirects)

```json
{
  "webcredentials": {
    "apps": ["TEAM_ID.com.libruce.icered"]
  },
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAM_ID.com.libruce.icered",
        "paths": [
          "/reset-password/*",
          "/verify/*"
        ]
      }
    ]
  }
}
```

**Replace `TEAM_ID` with your Apple Developer Team ID** (found in Apple Developer Portal > Membership)

### Step 3: Google - assetlinks.json

Create file: `https://icered.com/.well-known/assetlinks.json`

```json
[
  {
    "relation": ["delegate_permission/common.get_login_creds"],
    "target": {
      "namespace": "ios_app",
      "package_name": "com.libruce.icered"
    }
  }
]
```

### Step 4: Nginx Configuration Example

```nginx
location /.well-known/apple-app-site-association {
    default_type application/json;
    add_header Content-Type application/json;
}

location /.well-known/assetlinks.json {
    default_type application/json;
    add_header Content-Type application/json;
}
```

### Step 5: Kubernetes ConfigMap (if using K8s)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: well-known-files
data:
  apple-app-site-association: |
    {
      "webcredentials": {
        "apps": ["TEAM_ID.com.libruce.icered"]
      }
    }
  assetlinks.json: |
    [
      {
        "relation": ["delegate_permission/common.get_login_creds"],
        "target": {
          "namespace": "ios_app",
          "package_name": "com.libruce.icered"
        }
      }
    ]
```

## Testing

### Apple Associated Domains
1. Use Apple's validation tool: https://search.developer.apple.com/appsearch-validation-tool/
2. Enter your domain (icered.com)
3. Verify the association is detected

### Google Digital Asset Links
1. Use Google's validation tool: https://developers.google.com/digital-asset-links/tools/generator
2. Enter your domain and app details
3. Verify the statement is valid

### On Device Testing
1. **For Apple Keychain:**
   - Go to Settings > Passwords
   - Ensure iCloud Keychain is enabled
   - Save a password for icered.com in Safari
   - Open ICERED app > Login > Tap email field
   - Password suggestion should appear above keyboard

2. **For Google Password Manager:**
   - Go to Settings > Passwords > AutoFill Passwords
   - Enable Google Password Manager
   - Ensure you have credentials saved in Google Password Manager
   - Open ICERED app > Login > Tap email field
   - Google Password Manager suggestions should appear

## Troubleshooting

### AutoFill not appearing?
1. Check that Associated Domains capability is enabled in Xcode
2. Verify the entitlements file is properly linked in Build Settings
3. Test on a real device (simulator has limited Keychain support)
4. Ensure the `.well-known` files are accessible via HTTPS without redirects

### Apple validation failing?
1. Ensure no redirects (AASA must be at exact URL)
2. Check Content-Type header is `application/json`
3. Verify TEAM_ID is correct
4. Wait up to 24 hours for Apple's CDN to refresh

## User Setup Instructions

Tell users:
1. Open iOS Settings > Passwords > Password Options
2. Enable "AutoFill Passwords"
3. Select their preferred password manager (iCloud Keychain, Google, etc.)
4. Save their ICERED credentials in their chosen password manager
5. When logging in, tap the email field to see autofill suggestions
