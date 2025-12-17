import Foundation

/// Shared state for editing alias accounts
/// Used to pass the editing account ID between SettingsView and AliasNameView
@MainActor
final class AliasEditState: ObservableObject {
    static let shared = AliasEditState()

    /// The ID of the alias account being edited (nil for creating new)
    @Published var editingAccountId: String?

    private init() {}

    /// Set the account ID for editing
    func setEditingAccount(_ accountId: String?) {
        editingAccountId = accountId
    }

    /// Clear the editing state
    func clear() {
        editingAccountId = nil
    }
}
