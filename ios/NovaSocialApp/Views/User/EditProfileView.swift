import SwiftUI

struct EditProfileView: View {
    let user: User
    let onSave: (User) -> Void
    @Environment(\.dismiss) var dismiss

    @StateObject private var viewModel: EditProfileViewModel
    @State private var saveTask: Task<Void, Never>?

    init(user: User, onSave: @escaping (User) -> Void) {
        self.user = user
        self.onSave = onSave
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(user: user))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("顯示名稱")) {
                    TextField("輸入顯示名稱", text: $viewModel.displayName)
                        .textInputAutocapitalization(.words)
                }

                Section(header: Text("個人簡介")) {
                    TextEditor(text: $viewModel.bio)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("編輯個人資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveTask?.cancel()

                        saveTask = Task {
                            do {
                                if let updated = await viewModel.saveChanges() {
                                    onSave(updated)
                                    dismiss()
                                }
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                                viewModel.showError = true
                            }
                        }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("儲存")
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .alert("錯誤", isPresented: $viewModel.showError) {
                Button("好", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                if let message = viewModel.errorMessage {
                    Text(message)
                }
            }
            .onDisappear {
                saveTask?.cancel()
            }
        }
    }
}
