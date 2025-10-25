# CryptoCore.xcframework (iOS)

Client-side E2E crypto wrapper for iOS, bridging to the existing Rust crate `backend/libs/crypto-core`.

This folder contains build notes and scripts to generate `CryptoCore.xcframework` for iOS devices/simulators.

## Prerequisites

- Rust toolchain (stable)
- Xcode command line tools
- cbindgen (`cargo install cbindgen`)

## Build Targets

We build static libraries for:
- aarch64-apple-ios (device)
- aarch64-apple-ios-sim (simulator on Apple Silicon)
- x86_64-apple-ios (simulator on Intel)

Then we create an XCFramework from the three slices.

## Steps

```
cd ios/CryptoCore
./build.sh
```

This will:
- Generate `include/cryptocore.h` via cbindgen
- Build staticlibs for the three targets
- Create `CryptoCore.xcframework`

## Swift Usage

Add `CryptoCore.xcframework` to your Xcode project (Embed & Sign not required for static).

Swift wrapper lives at `ios/NovaSocial/Network/Security/CryptoCore.swift`.
Use `CryptoCoreProvider.shared.encrypt/decrypt/generateNonce` from Swift.

## Notes

- In development, if the XCFramework is missing, the Swift wrapper falls back to a no-op/Base64 scheme so app flows aren't blocked.
- Replace the fallback with the real framework when shipping strict E2E.

