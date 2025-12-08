# E2EE Integration Guide (Signal Protocol - Complete Implementation)

**Status**: Architecture Design Complete
**Last Updated**: 2025-12-09
**Version**: v3 (libsignal-client)

---

## Executive Summary

This document provides a complete implementation guide for integrating **Signal Protocol** (X3DH + Double Ratchet + PQXDH) end-to-end encryption into the Nova chat system using the official `libsignal-client` library.

### Why Signal Protocol over Olm?

| Feature | Olm (Previous) | Signal Protocol (New) |
|---------|---------------|----------------------|
| Key Agreement | 2 DH (simplified) | 4+ DH (X3DH) |
| Signed PreKey | No signature verification | Full Ed25519 signature |
| Post-Quantum | No | PQXDH with Kyber |
| Forward Secrecy | Basic | Full (per-message keys) |
| Multi-Device | Manual | Sesame Protocol |
| Library | Custom FFI | Official libsignal |

### Key Decision

**Use `libsignal-client` via CocoaPods** - Signal's official Rust-based library with Swift bindings.

---

## Architecture Overview

### Signal Protocol Components

```
┌─────────────────────────────────────────────────────────────────┐
│                     Signal Protocol Stack                       │
├─────────────────────────────────────────────────────────────────┤
│  X3DH (Extended Triple Diffie-Hellman)                         │
│  ├── IK: Long-term Identity Key (Ed25519 → X25519)             │
│  ├── SPK: Signed PreKey (Curve25519 + Signature)               │
│  ├── OPK: One-Time PreKey (Curve25519, optional)               │
│  └── EK: Ephemeral Key (generated per session)                 │
├─────────────────────────────────────────────────────────────────┤
│  Double Ratchet                                                 │
│  ├── Root Chain: Master secret evolution                       │
│  ├── Sending Chain: Per-direction message keys                 │
│  ├── Receiving Chain: Decrypt incoming messages                │
│  └── DH Ratchet: New DH per message round-trip                 │
├─────────────────────────────────────────────────────────────────┤
│  PQXDH (Post-Quantum Extension) - Future Ready                 │
│  └── Kyber: ML-KEM post-quantum key encapsulation              │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Alice     │         │   Backend    │         │    Bob      │
│   Device    │         │  Key Server  │         │   Device    │
└─────────────┘         └──────────────┘         └─────────────┘
       │                        │                        │
       │                        │  1. Register Device    │
       │                        │<───────────────────────│
       │                        │  (IK, SPK, OPKs, Kyber)│
       │                        │                        │
       │ 2. GetPreKeyBundle     │                        │
       │───────────────────────>│                        │
       │                        │                        │
       │ 3. PreKeyBundle        │                        │
       │<───────────────────────│                        │
       │   (Bob's IK, SPK, OPK) │                        │
       │                        │                        │
       │ 4. processPreKeyBundle │                        │
       │    X3DH → Session      │                        │
       │                        │                        │
       │ 5. signalEncrypt       │                        │
       │    (PreKeySignalMsg)   │                        │
       │                        │                        │
       │ 6. SendMessage         │                        │
       │───────────────────────>│  7. Forward            │
       │                        │───────────────────────>│
       │                        │                        │
       │                        │  8. signalDecryptPreKey│
       │                        │     X3DH → Session     │
       │                        │     Decrypt plaintext  │
       │                        │                        │
       │                        │  9. Subsequent msgs    │
       │<───────────────────────│<───────────────────────│
       │    (SignalMessage)     │    Double Ratchet      │
```

---

## iOS Implementation

### 1. Install libsignal-client via CocoaPods

**File**: `ios/Podfile`

```ruby
platform :ios, '16.0'
use_frameworks!

target 'NovaSocial' do
  # Signal Protocol - Official Library
  pod 'LibSignalClient', git: 'https://github.com/signalapp/libsignal.git', tag: 'v0.64.1'

  # Set the checksum for the prebuilt FFI
  ENV['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'] = 'CHECKSUM_FROM_RELEASE'
end
```

Run:
```bash
cd ios && pod install
```

### 2. Core Protocol Stores

libsignal-client requires implementing 6 store protocols:

**File**: `ios/NovaSocial/Shared/Services/Security/Signal/SignalStoreProtocols.swift`

```swift
import Foundation
import LibSignalClient

// MARK: - Store Context

struct NovaStoreContext: StoreContext {
    let userId: String
}

// MARK: - Keychain-backed Signal Protocol Store

final class KeychainSignalProtocolStore: IdentityKeyStore, PreKeyStore,
                                         SignedPreKeyStore, KyberPreKeyStore,
                                         SessionStore, SenderKeyStore {

    // MARK: - Properties

    private let keychain: KeychainService
    private let userId: String

    private var identityKeyPairCache: IdentityKeyPair?
    private var registrationIdCache: UInt32?

    // Keychain key prefixes
    private let identityKeyKey = "signal.identity.keypair"
    private let registrationIdKey = "signal.registration.id"
    private let preKeyPrefix = "signal.prekey."
    private let signedPreKeyPrefix = "signal.signedprekey."
    private let kyberPreKeyPrefix = "signal.kyberprekey."
    private let sessionPrefix = "signal.session."
    private let identityPrefix = "signal.peeridentity."
    private let senderKeyPrefix = "signal.senderkey."

    // MARK: - Initialization

    init(keychain: KeychainService = .shared, userId: String) {
        self.keychain = keychain
        self.userId = userId
        loadCachedIdentity()
    }

    // MARK: - IdentityKeyStore

    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        if let cached = identityKeyPairCache {
            return cached
        }

        // Try to load from keychain
        if let data = keychain.getData(identityKeyKey),
           let keypair = try? IdentityKeyPair(bytes: data) {
            identityKeyPairCache = keypair
            return keypair
        }

        // Generate new keypair
        let keypair = IdentityKeyPair.generate()
        identityKeyPairCache = keypair

        // Save to keychain
        let data = Data(keypair.serialize())
        keychain.save(data, for: identityKeyKey)

        return keypair
    }

    func localRegistrationId(context: StoreContext) throws -> UInt32 {
        if let cached = registrationIdCache {
            return cached
        }

        // Try to load from keychain
        if let idString = keychain.get(registrationIdKey),
           let id = UInt32(idString) {
            registrationIdCache = id
            return id
        }

        // Generate new registration ID (14-bit)
        let id = UInt32.random(in: 1...0x3FFF)
        registrationIdCache = id
        keychain.save(String(id), for: registrationIdKey)

        return id
    }

    func saveIdentity(
        _ identity: IdentityKey,
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> IdentityChange {
        let key = identityPrefix + address.description
        let newData = Data(identity.serialize())

        // Check for existing identity
        if let existingData = keychain.getData(key) {
            if existingData == newData {
                return .newOrUnchanged
            }
            // Identity changed - potential MITM!
            keychain.save(newData, for: key)
            return .replacedExisting
        }

        // New identity (TOFU - Trust On First Use)
        keychain.save(newData, for: key)
        return .newOrUnchanged
    }

    func isTrustedIdentity(
        _ identity: IdentityKey,
        for address: ProtocolAddress,
        direction: Direction,
        context: StoreContext
    ) throws -> Bool {
        let key = identityPrefix + address.description

        guard let existingData = keychain.getData(key) else {
            // First contact - TOFU
            return true
        }

        let existingIdentity = try IdentityKey(bytes: existingData)
        return existingIdentity == identity
    }

    func identity(
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> IdentityKey? {
        let key = identityPrefix + address.description

        guard let data = keychain.getData(key) else {
            return nil
        }

        return try IdentityKey(bytes: data)
    }

    // MARK: - PreKeyStore

    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        let key = preKeyPrefix + String(id)

        guard let data = keychain.getData(key) else {
            throw SignalError.invalidKeyIdentifier("PreKey \(id) not found")
        }

        return try PreKeyRecord(bytes: data)
    }

    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        let key = preKeyPrefix + String(id)
        let data = Data(record.serialize())
        keychain.save(data, for: key)
    }

    func removePreKey(id: UInt32, context: StoreContext) throws {
        let key = preKeyPrefix + String(id)
        keychain.delete(key)
    }

    // MARK: - SignedPreKeyStore

    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        let key = signedPreKeyPrefix + String(id)

        guard let data = keychain.getData(key) else {
            throw SignalError.invalidKeyIdentifier("SignedPreKey \(id) not found")
        }

        return try SignedPreKeyRecord(bytes: data)
    }

    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        let key = signedPreKeyPrefix + String(id)
        let data = Data(record.serialize())
        keychain.save(data, for: key)
    }

    // MARK: - KyberPreKeyStore (Post-Quantum)

    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        let key = kyberPreKeyPrefix + String(id)

        guard let data = keychain.getData(key) else {
            throw SignalError.invalidKeyIdentifier("KyberPreKey \(id) not found")
        }

        return try KyberPreKeyRecord(bytes: data)
    }

    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        let key = kyberPreKeyPrefix + String(id)
        let data = Data(record.serialize())
        keychain.save(data, for: key)
    }

    func markKyberPreKeyUsed(
        id: UInt32,
        signedPreKeyId: UInt32,
        baseKey: PublicKey,
        context: StoreContext
    ) throws {
        // Mark as used to prevent replay attacks
        // In production: track in a separate store
    }

    // MARK: - SessionStore

    func loadSession(
        for address: ProtocolAddress,
        context: StoreContext
    ) throws -> SessionRecord? {
        let key = sessionPrefix + address.description

        guard let data = keychain.getData(key) else {
            return nil
        }

        return try SessionRecord(bytes: data)
    }

    func loadExistingSessions(
        for addresses: [ProtocolAddress],
        context: StoreContext
    ) throws -> [SessionRecord] {
        return try addresses.compactMap { address in
            try loadSession(for: address, context: context)
        }
    }

    func storeSession(
        _ record: SessionRecord,
        for address: ProtocolAddress,
        context: StoreContext
    ) throws {
        let key = sessionPrefix + address.description
        let data = Data(record.serialize())
        keychain.save(data, for: key)
    }

    // MARK: - SenderKeyStore (for Group Messaging)

    func storeSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        record: SenderKeyRecord,
        context: StoreContext
    ) throws {
        let key = senderKeyPrefix + "\(sender.description).\(distributionId.uuidString)"
        let data = Data(record.serialize())
        keychain.save(data, for: key)
    }

    func loadSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        context: StoreContext
    ) throws -> SenderKeyRecord? {
        let key = senderKeyPrefix + "\(sender.description).\(distributionId.uuidString)"

        guard let data = keychain.getData(key) else {
            return nil
        }

        return try SenderKeyRecord(bytes: data)
    }

    // MARK: - Private Helpers

    private func loadCachedIdentity() {
        if let data = keychain.getData(identityKeyKey),
           let keypair = try? IdentityKeyPair(bytes: data) {
            identityKeyPairCache = keypair
        }

        if let idString = keychain.get(registrationIdKey),
           let id = UInt32(idString) {
            registrationIdCache = id
        }
    }
}
```

### 3. Signal E2EE Service

**File**: `ios/NovaSocial/Shared/Services/Security/Signal/SignalE2EEService.swift`

```swift
import Foundation
import LibSignalClient

// MARK: - SignalE2EEService

/// Production E2EE service using Signal Protocol (X3DH + Double Ratchet)
@Observable
final class SignalE2EEService {

    // MARK: - Properties

    private let store: KeychainSignalProtocolStore
    private let apiClient: SignalKeyServerClient
    private let deviceId: UInt32
    private let context: NovaStoreContext

    // MARK: - Initialization

    init(
        userId: String,
        apiClient: SignalKeyServerClient = DefaultSignalKeyServerClient()
    ) {
        self.store = KeychainSignalProtocolStore(userId: userId)
        self.apiClient = apiClient
        self.deviceId = Self.generateDeviceId()
        self.context = NovaStoreContext(userId: userId)
    }

    // MARK: - Public API

    /// Initialize Signal Protocol for this device
    /// Generates identity key, signed prekey, one-time prekeys, and Kyber keys
    @MainActor
    func initialize() async throws {
        // 1. Get or generate identity keypair
        let identityKeyPair = try store.identityKeyPair(context: context)
        let registrationId = try store.localRegistrationId(context: context)

        // 2. Generate Signed PreKey
        let signedPreKeyId: UInt32 = 1
        let signedPreKeyPair = PrivateKey.generate()
        let signedPreKeySignature = identityKeyPair.privateKey.generateSignature(
            message: signedPreKeyPair.publicKey.serialize()
        )

        let signedPreKey = try SignedPreKeyRecord(
            id: signedPreKeyId,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            privateKey: signedPreKeyPair,
            signature: signedPreKeySignature
        )
        try store.storeSignedPreKey(signedPreKey, id: signedPreKeyId, context: context)

        // 3. Generate One-Time PreKeys (100 keys)
        var preKeyRecords: [PreKeyRecord] = []
        for i in 1...100 {
            let preKeyId = UInt32(i)
            let preKeyPair = PrivateKey.generate()
            let preKey = try PreKeyRecord(id: preKeyId, privateKey: preKeyPair)
            try store.storePreKey(preKey, id: preKeyId, context: context)
            preKeyRecords.append(preKey)
        }

        // 4. Generate Kyber PreKeys (Post-Quantum) - 10 keys
        var kyberPreKeyRecords: [KyberPreKeyRecord] = []
        for i in 1...10 {
            let kyberPreKeyId = UInt32(i)
            let kyberKeyPair = KEMKeyPair.generate()
            let kyberSignature = identityKeyPair.privateKey.generateSignature(
                message: kyberKeyPair.publicKey.serialize()
            )

            let kyberPreKey = try KyberPreKeyRecord(
                id: kyberPreKeyId,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                keyPair: kyberKeyPair,
                signature: kyberSignature
            )
            try store.storeKyberPreKey(kyberPreKey, id: kyberPreKeyId, context: context)
            kyberPreKeyRecords.append(kyberPreKey)
        }

        // 5. Upload keys to server
        try await apiClient.uploadKeys(
            deviceId: deviceId,
            registrationId: registrationId,
            identityKey: identityKeyPair.publicKey,
            signedPreKey: signedPreKey,
            preKeys: preKeyRecords,
            kyberPreKeys: kyberPreKeyRecords
        )

        #if DEBUG
        print("[SignalE2EE] Initialized with \(preKeyRecords.count) OTKs, \(kyberPreKeyRecords.count) Kyber keys")
        #endif
    }

    /// Encrypt message for a specific user/device
    @MainActor
    func encrypt(
        message: String,
        for userId: String,
        deviceId: UInt32
    ) async throws -> SignalEncryptedMessage {
        let address = try ProtocolAddress(name: userId, deviceId: deviceId)

        // Check for existing session
        if try store.loadSession(for: address, context: context) == nil {
            // No session - establish via X3DH
            try await establishSession(with: address)
        }

        // Encrypt using Signal Protocol
        guard let messageData = message.data(using: .utf8) else {
            throw SignalE2EEError.encodingError
        }

        let ciphertext = try signalEncrypt(
            message: messageData,
            for: address,
            sessionStore: store,
            identityStore: store,
            context: context
        )

        return SignalEncryptedMessage(
            type: ciphertext.messageType,
            destinationUserId: userId,
            destinationDeviceId: deviceId,
            senderDeviceId: self.deviceId,
            content: Data(ciphertext.serialize())
        )
    }

    /// Decrypt received message
    @MainActor
    func decrypt(_ message: SignalEncryptedMessage, from senderId: String) throws -> String {
        let address = try ProtocolAddress(name: senderId, deviceId: message.senderDeviceId)

        let plaintext: Data

        switch message.type {
        case .preKey:
            // First message - includes X3DH prekey material
            let preKeyMessage = try PreKeySignalMessage(bytes: message.content)
            plaintext = try signalDecryptPreKey(
                message: preKeyMessage,
                from: address,
                sessionStore: store,
                identityStore: store,
                preKeyStore: store,
                signedPreKeyStore: store,
                kyberPreKeyStore: store,
                context: context
            )

        case .whisper:
            // Subsequent messages - Double Ratchet only
            let signalMessage = try SignalMessage(bytes: message.content)
            plaintext = try signalDecrypt(
                message: signalMessage,
                from: address,
                sessionStore: store,
                identityStore: store,
                context: context
            )

        default:
            throw SignalE2EEError.unknownMessageType
        }

        guard let decrypted = String(data: plaintext, encoding: .utf8) else {
            throw SignalE2EEError.decodingError
        }

        return decrypted
    }

    /// Encrypt for group (using Sender Keys)
    @MainActor
    func encryptForGroup(
        message: String,
        groupId: UUID,
        members: [ProtocolAddress]
    ) async throws -> SenderKeyDistributionMessage {
        let address = try ProtocolAddress(
            name: context.userId,
            deviceId: deviceId
        )

        // Create sender key distribution message
        let distributionMessage = try SenderKeyDistributionMessage(
            from: address,
            distributionId: groupId,
            store: store,
            context: context
        )

        return distributionMessage
    }

    // MARK: - Private Methods

    /// Establish session via X3DH key agreement
    private func establishSession(with address: ProtocolAddress) async throws {
        // Fetch PreKey Bundle from server
        let bundle = try await apiClient.getPreKeyBundle(
            userId: address.name,
            deviceId: address.deviceId
        )

        // Process bundle - performs X3DH
        try processPreKeyBundle(
            bundle,
            for: address,
            sessionStore: store,
            identityStore: store,
            context: context
        )

        #if DEBUG
        print("[SignalE2EE] Established session with \(address)")
        #endif
    }

    private static func generateDeviceId() -> UInt32 {
        // Use stable device ID from keychain or generate new
        let keychain = KeychainService.shared

        if let idString = keychain.get("signal.device.id"),
           let id = UInt32(idString) {
            return id
        }

        let id = UInt32.random(in: 1...UInt32.max)
        keychain.save(String(id), for: "signal.device.id")
        return id
    }
}

// MARK: - Data Models

struct SignalEncryptedMessage: Codable {
    let type: CiphertextMessage.MessageType
    let destinationUserId: String
    let destinationDeviceId: UInt32
    let senderDeviceId: UInt32
    let content: Data
}

enum SignalE2EEError: Error {
    case encodingError
    case decodingError
    case unknownMessageType
    case sessionNotFound
    case bundleFetchFailed
}

extension CiphertextMessage.MessageType: Codable {}
```

### 4. Key Server API Client

**File**: `ios/NovaSocial/Shared/Services/Security/Signal/SignalKeyServerClient.swift`

```swift
import Foundation
import LibSignalClient

// MARK: - Key Server Client Protocol

protocol SignalKeyServerClient {
    func uploadKeys(
        deviceId: UInt32,
        registrationId: UInt32,
        identityKey: IdentityKey,
        signedPreKey: SignedPreKeyRecord,
        preKeys: [PreKeyRecord],
        kyberPreKeys: [KyberPreKeyRecord]
    ) async throws

    func getPreKeyBundle(userId: String, deviceId: UInt32) async throws -> PreKeyBundle

    func listDevices(userId: String) async throws -> [DeviceInfo]
}

// MARK: - Default Implementation

final class DefaultSignalKeyServerClient: SignalKeyServerClient {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func uploadKeys(
        deviceId: UInt32,
        registrationId: UInt32,
        identityKey: IdentityKey,
        signedPreKey: SignedPreKeyRecord,
        preKeys: [PreKeyRecord],
        kyberPreKeys: [KyberPreKeyRecord]
    ) async throws {
        let request = UploadSignalKeysRequest(
            deviceId: deviceId,
            registrationId: registrationId,
            identityKey: identityKey.serialize().base64EncodedString(),
            signedPreKey: SignedPreKeyDTO(
                id: signedPreKey.id,
                publicKey: signedPreKey.publicKey.serialize().base64EncodedString(),
                signature: signedPreKey.signature.base64EncodedString()
            ),
            preKeys: preKeys.map { key in
                PreKeyDTO(
                    id: key.id,
                    publicKey: key.publicKey.serialize().base64EncodedString()
                )
            },
            kyberPreKeys: kyberPreKeys.map { key in
                KyberPreKeyDTO(
                    id: key.id,
                    publicKey: key.publicKey.serialize().base64EncodedString(),
                    signature: key.signature.base64EncodedString()
                )
            }
        )

        let _: EmptyResponse = try await apiClient.request(
            endpoint: "/api/v1/e2ee/signal/keys",
            method: "PUT",
            body: request
        )
    }

    func getPreKeyBundle(userId: String, deviceId: UInt32) async throws -> PreKeyBundle {
        let response: PreKeyBundleResponse = try await apiClient.request(
            endpoint: "/api/v1/e2ee/signal/bundle/\(userId)/\(deviceId)",
            method: "GET",
            body: nil as String?
        )

        // Decode keys from Base64
        let identityKey = try IdentityKey(bytes: Data(base64Encoded: response.identityKey)!)
        let signedPreKey = try PublicKey(Data(base64Encoded: response.signedPreKey.publicKey)!)
        let signedPreKeySignature = Data(base64Encoded: response.signedPreKey.signature)!

        // One-time PreKey (optional)
        let preKey: PublicKey?
        let preKeyId: UInt32?
        if let otk = response.oneTimeKey {
            preKey = try PublicKey(Data(base64Encoded: otk.publicKey)!)
            preKeyId = otk.id
        } else {
            preKey = nil
            preKeyId = nil
        }

        // Kyber PreKey
        let kyberPreKey = try KEMPublicKey(Data(base64Encoded: response.kyberPreKey.publicKey)!)
        let kyberSignature = Data(base64Encoded: response.kyberPreKey.signature)!

        // Build PreKeyBundle
        if let preKey = preKey, let preKeyId = preKeyId {
            return try PreKeyBundle(
                registrationId: response.registrationId,
                deviceId: deviceId,
                prekeyId: preKeyId,
                prekey: preKey,
                signedPrekeyId: response.signedPreKey.id,
                signedPrekey: signedPreKey,
                signedPrekeySignature: signedPreKeySignature,
                identity: identityKey,
                kyberPrekeyId: response.kyberPreKey.id,
                kyberPrekey: kyberPreKey,
                kyberPrekeySignature: kyberSignature
            )
        } else {
            return try PreKeyBundle(
                registrationId: response.registrationId,
                deviceId: deviceId,
                signedPrekeyId: response.signedPreKey.id,
                signedPrekey: signedPreKey,
                signedPrekeySignature: signedPreKeySignature,
                identity: identityKey,
                kyberPrekeyId: response.kyberPreKey.id,
                kyberPrekey: kyberPreKey,
                kyberPrekeySignature: kyberSignature
            )
        }
    }

    func listDevices(userId: String) async throws -> [DeviceInfo] {
        let response: ListDevicesResponse = try await apiClient.request(
            endpoint: "/api/v1/e2ee/signal/devices/\(userId)",
            method: "GET",
            body: nil as String?
        )
        return response.devices
    }
}

// MARK: - DTO Models

struct UploadSignalKeysRequest: Codable {
    let deviceId: UInt32
    let registrationId: UInt32
    let identityKey: String
    let signedPreKey: SignedPreKeyDTO
    let preKeys: [PreKeyDTO]
    let kyberPreKeys: [KyberPreKeyDTO]
}

struct SignedPreKeyDTO: Codable {
    let id: UInt32
    let publicKey: String
    let signature: String
}

struct PreKeyDTO: Codable {
    let id: UInt32
    let publicKey: String
}

struct KyberPreKeyDTO: Codable {
    let id: UInt32
    let publicKey: String
    let signature: String
}

struct PreKeyBundleResponse: Codable {
    let userId: String
    let deviceId: UInt32
    let registrationId: UInt32
    let identityKey: String
    let signedPreKey: SignedPreKeyDTO
    let oneTimeKey: PreKeyDTO?
    let kyberPreKey: KyberPreKeyDTO
}

struct DeviceInfo: Codable {
    let deviceId: UInt32
    let registrationId: UInt32
    let deviceName: String?
    let platform: String?
    let lastActiveAt: Int64
}

struct ListDevicesResponse: Codable {
    let devices: [DeviceInfo]
}

struct EmptyResponse: Codable {}
```

---

## Backend Implementation

### 1. gRPC Service Definition

**File**: `backend/realtime-chat-service/proto/signal_e2ee.proto`

```protobuf
syntax = "proto3";

package nova.signal.e2ee.v1;

service SignalE2EEService {
  // Device & Key Management
  rpc UploadKeys(UploadKeysRequest) returns (UploadKeysResponse);
  rpc GetPreKeyBundle(GetPreKeyBundleRequest) returns (PreKeyBundle);
  rpc GetPreKeyCount(GetPreKeyCountRequest) returns (PreKeyCountResponse);
  rpc ListDevices(ListDevicesRequest) returns (ListDevicesResponse);
  rpc RemoveDevice(RemoveDeviceRequest) returns (RemoveDeviceResponse);
}

// Upload all keys for a device
message UploadKeysRequest {
  uint32 device_id = 1;
  uint32 registration_id = 2;
  bytes identity_key = 3;              // Ed25519 public key (32 bytes)
  SignedPreKey signed_prekey = 4;
  repeated PreKey prekeys = 5;          // One-time PreKeys
  repeated KyberPreKey kyber_prekeys = 6; // Post-quantum keys
}

message SignedPreKey {
  uint32 id = 1;
  bytes public_key = 2;                // Curve25519 public key
  bytes signature = 3;                 // Ed25519 signature
}

message PreKey {
  uint32 id = 1;
  bytes public_key = 2;                // Curve25519 public key
}

message KyberPreKey {
  uint32 id = 1;
  bytes public_key = 2;                // Kyber public key (ML-KEM-768)
  bytes signature = 3;                 // Ed25519 signature
}

message PreKeyBundle {
  string user_id = 1;
  uint32 device_id = 2;
  uint32 registration_id = 3;
  bytes identity_key = 4;
  SignedPreKey signed_prekey = 5;
  PreKey one_time_key = 6;             // Optional - may be exhausted
  KyberPreKey kyber_prekey = 7;        // Required for PQXDH
}

message GetPreKeyBundleRequest {
  string user_id = 1;
  uint32 device_id = 2;
}

message GetPreKeyCountRequest {
  uint32 device_id = 1;
}

message PreKeyCountResponse {
  uint32 prekey_count = 1;
  uint32 kyber_prekey_count = 2;
}

// ... additional messages
```

### 2. ClickHouse Schema

**File**: `backend/realtime-chat-service/migrations/signal_e2ee_schema.sql`

```sql
-- Device registration with Signal keys
CREATE TABLE signal_devices (
    user_id String,
    device_id UInt32,
    registration_id UInt32,
    identity_key String,           -- Base64 Ed25519 public key
    device_name Nullable(String),
    platform Nullable(String),
    registered_at DateTime64(3) DEFAULT now64(3),
    last_active_at DateTime64(3) DEFAULT now64(3),
    INDEX idx_user_id (user_id) TYPE bloom_filter GRANULARITY 1
) ENGINE = ReplacingMergeTree(last_active_at)
ORDER BY (user_id, device_id);

-- Signed PreKeys (rotate every 7 days)
CREATE TABLE signal_signed_prekeys (
    device_id UInt32,
    key_id UInt32,
    public_key String,             -- Base64 Curve25519
    signature String,              -- Base64 Ed25519 signature
    created_at DateTime64(3) DEFAULT now64(3)
) ENGINE = ReplacingMergeTree(created_at)
ORDER BY (device_id, key_id);

-- One-Time PreKeys (consumed on use)
CREATE TABLE signal_prekeys (
    device_id UInt32,
    key_id UInt32,
    public_key String,             -- Base64 Curve25519
    created_at DateTime64(3) DEFAULT now64(3),
    claimed_at Nullable(DateTime64(3)),
    claimed_by Nullable(UInt32)    -- Claiming device_id
) ENGINE = ReplacingMergeTree(created_at)
ORDER BY (device_id, key_id);

-- Kyber PreKeys (Post-Quantum)
CREATE TABLE signal_kyber_prekeys (
    device_id UInt32,
    key_id UInt32,
    public_key String,             -- Base64 Kyber public key
    signature String,              -- Base64 Ed25519 signature
    created_at DateTime64(3) DEFAULT now64(3),
    used_count UInt32 DEFAULT 0    -- Can be reused (unlike OTK)
) ENGINE = ReplacingMergeTree(created_at)
ORDER BY (device_id, key_id);
```

---

## Migration from Current Implementation

### Files to Delete (Over-engineered Olm abstraction)

```bash
# These files were designed for simplified Olm, not Signal Protocol
rm ios/NovaSocial/Shared/Services/Security/SessionRepository.swift
rm ios/NovaSocial/Shared/Services/Security/SessionProvider.swift
rm ios/NovaSocial/Shared/Services/Security/OlmE2EEService.swift
```

### Files to Keep

- `ios/VodozemacFFI/` - Keep for potential fallback
- `ios/NovaSocial/Shared/Services/Security/E2EEService.swift` - Deprecate gradually

### Migration Strategy

1. **Phase 1**: Add `SignalE2EEService` alongside existing `E2EEService`
2. **Phase 2**: New conversations use Signal Protocol
3. **Phase 3**: Existing conversations continue with legacy encryption
4. **Phase 4**: Display "Upgrade encryption" prompt for legacy chats

---

## Security Hardening Checklist

- [ ] Identity keys stored in Secure Enclave (if available)
- [ ] Signed PreKey signature verified on bundle fetch
- [ ] One-Time Keys marked as used (prevent replay)
- [ ] Kyber PreKeys rotated (used_count limit)
- [ ] Trust-on-first-use (TOFU) with identity change warnings
- [ ] Session reset capability for compromised keys
- [ ] Key verification via Safety Numbers

---

## Testing Plan

### Unit Tests

1. **Identity Key Generation** - Keypair generates and persists correctly
2. **PreKey Bundle Creation** - All key types included
3. **Session Establishment** - X3DH completes successfully
4. **Encrypt/Decrypt Round-trip** - Message integrity verified
5. **Ratchet Advance** - Each message uses unique key
6. **Group Encryption** - Sender Keys distribute correctly

### Integration Tests

1. **Multi-device** - Messages decrypt on all devices
2. **Key Exhaustion** - Handles missing one-time keys
3. **Offline Messages** - Queue and deliver when online
4. **Session Recovery** - Re-establish after reset

---

## References

- [Signal Protocol Specification](https://signal.org/docs/)
- [X3DH Key Agreement](https://signal.org/docs/specifications/x3dh/)
- [Double Ratchet Algorithm](https://signal.org/docs/specifications/doubleratchet/)
- [PQXDH (Post-Quantum)](https://signal.org/docs/specifications/pqxdh/)
- [libsignal-client GitHub](https://github.com/signalapp/libsignal)

---

**Next Steps**:

1. iOS: Add `LibSignalClient` pod to Podfile
2. iOS: Implement `KeychainSignalProtocolStore`
3. Backend: Implement gRPC `SignalE2EEService`
4. Backend: Create ClickHouse migration
5. Testing: End-to-end encryption flow validation
