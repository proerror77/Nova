import Foundation

// MARK: - Matrix Integration Status
//
// This file previously contained stub implementations for MatrixBridgeService.
// The full Matrix integration is now enabled via:
//
// - MatrixService.swift: Core Matrix Rust SDK wrapper
// - MatrixBridgeService.swift: Nova-Matrix bridge service
// - MatrixSSOManager.swift: SSO authentication flow
//
// Configuration:
// - Staging homeserver: https://matrix.staging.gcp.icered.com
// - Matrix server name: staging.gcp.icered.com
// - SSO callback URLs configured in Info.plist:
//   - nova-staging://matrix-sso-callback (staging)
//   - nova://matrix-sso-callback (production)
//
// To use Matrix E2EE in the app:
// 1. Initialize MatrixBridgeService after user login
// 2. Check MatrixBridgeService.shared.isE2EEAvailable
// 3. Use MatrixBridgeService.shared to send/receive encrypted messages
//
// Note: The MatrixRustSDK package must be added to the Xcode project
// via Swift Package Manager for full functionality.
// Package URL: https://github.com/matrix-org/matrix-rust-components-swift

// No stub types needed - all implementations are in their respective files:
// - MatrixService.swift
// - MatrixBridgeService.swift
// - MatrixSSOManager.swift
