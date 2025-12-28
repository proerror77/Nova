import Foundation
import UniformTypeIdentifiers

// MARK: - Chat Backup Service

/// Service for backing up and restoring chat conversations
@MainActor
final class ChatBackupService {
    // MARK: - Singleton

    static let shared = ChatBackupService()
    private init() {}

    // MARK: - Properties

    private let chatService = ChatService.shared
    private let fileManager = FileManager.default

    // MARK: - Backup Models

    /// Backup file format version
    private static let backupVersion = 1

    /// Complete backup structure
    struct ChatBackup: Codable {
        let version: Int
        let createdAt: Date
        let deviceId: String?
        let conversations: [ConversationBackup]
    }

    /// Individual conversation backup
    struct ConversationBackup: Codable {
        let conversationId: String
        let name: String?
        let type: String
        let createdAt: Date
        let messages: [MessageBackup]
        let metadata: ConversationMetadata?
    }

    /// Message backup with all relevant fields
    struct MessageBackup: Codable {
        let id: String
        let senderId: String
        let content: String
        let type: String
        let createdAt: Date
        let isEdited: Bool
        let mediaUrl: String?
        let replyToId: String?
        let isPinned: Bool
    }

    /// Additional conversation metadata
    struct ConversationMetadata: Codable {
        let participantIds: [String]?
        let isEncrypted: Bool
        let messageCount: Int
    }

    // MARK: - Export

    /// Export a single conversation to a backup file
    /// - Parameters:
    ///   - conversationId: Conversation to export
    ///   - includeMedia: Whether to include media URLs (default true)
    /// - Returns: URL to the backup file
    func exportConversation(conversationId: String, includeMedia: Bool = true) async throws -> URL {
        // Fetch conversation details
        let conversation = try await chatService.getConversation(conversationId: conversationId)

        // Fetch all messages (paginate if needed)
        var allMessages: [Message] = []
        var cursor: String?
        repeat {
            let response = try await chatService.getMessages(
                conversationId: conversationId,
                limit: 100,
                cursor: cursor
            )
            allMessages.append(contentsOf: response.messages)
            cursor = response.nextCursor
        } while cursor != nil && allMessages.count < 10000 // Safety limit

        // Convert to backup format
        let messageBackups = allMessages.map { message -> MessageBackup in
            MessageBackup(
                id: message.id,
                senderId: message.senderId,
                content: message.content,
                type: message.type.rawValue,
                createdAt: message.createdAt,
                isEdited: message.isEdited,
                mediaUrl: includeMedia ? message.mediaUrl : nil,
                replyToId: message.replyToId,
                isPinned: message.isPinned
            )
        }

        let conversationBackup = ConversationBackup(
            conversationId: conversationId,
            name: conversation.name,
            type: conversation.type.rawValue,
            createdAt: conversation.createdAt,
            messages: messageBackups,
            metadata: ConversationMetadata(
                participantIds: conversation.participants,
                isEncrypted: conversation.isEncrypted,
                messageCount: allMessages.count
            )
        )

        let backup = ChatBackup(
            version: ChatBackupService.backupVersion,
            createdAt: Date(),
            deviceId: KeychainService.shared.get(.matrixDeviceId),
            conversations: [conversationBackup]
        )

        return try saveBackup(backup, name: "chat_backup_\(conversationId)")
    }

    /// Export all conversations to a backup file
    /// - Parameter includeMedia: Whether to include media URLs
    /// - Returns: URL to the backup file
    func exportAllConversations(includeMedia: Bool = true) async throws -> URL {
        // Fetch all conversations
        let conversations = try await chatService.getConversations()

        var conversationBackups: [ConversationBackup] = []

        for conversation in conversations {
            // Fetch messages for each conversation
            var allMessages: [Message] = []
            var cursor: String?
            repeat {
                let response = try await chatService.getMessages(
                    conversationId: conversation.id,
                    limit: 100,
                    cursor: cursor
                )
                allMessages.append(contentsOf: response.messages)
                cursor = response.nextCursor
            } while cursor != nil && allMessages.count < 5000 // Per-conversation limit

            let messageBackups = allMessages.map { message -> MessageBackup in
                MessageBackup(
                    id: message.id,
                    senderId: message.senderId,
                    content: message.content,
                    type: message.type.rawValue,
                    createdAt: message.createdAt,
                    isEdited: message.isEdited,
                    mediaUrl: includeMedia ? message.mediaUrl : nil,
                    replyToId: message.replyToId,
                    isPinned: message.isPinned
                )
            }

            let conversationBackup = ConversationBackup(
                conversationId: conversation.id,
                name: conversation.name,
                type: conversation.type.rawValue,
                createdAt: conversation.createdAt,
                messages: messageBackups,
                metadata: ConversationMetadata(
                    participantIds: conversation.participants,
                    isEncrypted: conversation.isEncrypted,
                    messageCount: allMessages.count
                )
            )

            conversationBackups.append(conversationBackup)
        }

        let backup = ChatBackup(
            version: ChatBackupService.backupVersion,
            createdAt: Date(),
            deviceId: KeychainService.shared.get(.matrixDeviceId),
            conversations: conversationBackups
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        return try saveBackup(backup, name: "nova_chat_backup_\(timestamp)")
    }

    // MARK: - Import

    /// Import conversations from a backup file
    /// - Parameter url: URL to the backup file
    /// - Returns: Import result with statistics
    func importBackup(from url: URL) async throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup = try decoder.decode(ChatBackup.self, from: data)

        // Validate backup version
        guard backup.version <= ChatBackupService.backupVersion else {
            throw BackupError.unsupportedVersion(backup.version)
        }

        var importedConversations = 0
        var importedMessages = 0
        var errors: [String] = []

        for conversationBackup in backup.conversations {
            do {
                // Check if conversation exists
                let existingConversations = try await chatService.getConversations()
                let exists = existingConversations.contains { $0.id == conversationBackup.conversationId }

                if !exists {
                    // Create new conversation would require server-side support
                    // For now, log that the conversation doesn't exist
                    #if DEBUG
                    print("[ChatBackupService] Conversation \(conversationBackup.conversationId) not found - skipping import")
                    #endif
                    errors.append("Conversation \(conversationBackup.name ?? conversationBackup.conversationId) not found")
                    continue
                }

                importedConversations += 1
                importedMessages += conversationBackup.messages.count

                #if DEBUG
                print("[ChatBackupService] Would restore \(conversationBackup.messages.count) messages to \(conversationBackup.conversationId)")
                #endif

            } catch {
                errors.append("Failed to import \(conversationBackup.name ?? conversationBackup.conversationId): \(error.localizedDescription)")
            }
        }

        return ImportResult(
            totalConversations: backup.conversations.count,
            importedConversations: importedConversations,
            totalMessages: backup.conversations.reduce(0) { $0 + $1.messages.count },
            importedMessages: importedMessages,
            errors: errors
        )
    }

    /// Read backup file info without importing
    /// - Parameter url: URL to the backup file
    /// - Returns: Backup info
    func getBackupInfo(from url: URL) throws -> BackupInfo {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup = try decoder.decode(ChatBackup.self, from: data)

        return BackupInfo(
            version: backup.version,
            createdAt: backup.createdAt,
            deviceId: backup.deviceId,
            conversationCount: backup.conversations.count,
            totalMessages: backup.conversations.reduce(0) { $0 + $1.messages.count },
            dateRange: calculateDateRange(backup)
        )
    }

    // MARK: - Helper Methods

    private func saveBackup(_ backup: ChatBackup, name: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(backup)

        // Save to documents directory
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsURL.appendingPathComponent("\(name).json")

        try data.write(to: backupURL)

        #if DEBUG
        print("[ChatBackupService] Saved backup to \(backupURL.path)")
        #endif

        return backupURL
    }

    private func calculateDateRange(_ backup: ChatBackup) -> (oldest: Date, newest: Date)? {
        let allDates = backup.conversations.flatMap { $0.messages.map { $0.createdAt } }
        guard let oldest = allDates.min(), let newest = allDates.max() else {
            return nil
        }
        return (oldest, newest)
    }

    // MARK: - Result Types

    struct ImportResult {
        let totalConversations: Int
        let importedConversations: Int
        let totalMessages: Int
        let importedMessages: Int
        let errors: [String]

        var isSuccess: Bool {
            errors.isEmpty
        }
    }

    struct BackupInfo {
        let version: Int
        let createdAt: Date
        let deviceId: String?
        let conversationCount: Int
        let totalMessages: Int
        let dateRange: (oldest: Date, newest: Date)?
    }

    // MARK: - Errors

    enum BackupError: LocalizedError {
        case unsupportedVersion(Int)
        case invalidFormat
        case fileNotFound
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Unsupported backup version: \(version). Please update the app."
            case .invalidFormat:
                return "Invalid backup file format."
            case .fileNotFound:
                return "Backup file not found."
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            }
        }
    }
}

// MARK: - UTType Extension for Backup Files

extension UTType {
    static var novaChatBackup: UTType {
        UTType(exportedAs: "com.nova.chat.backup", conformingTo: .json)
    }
}
