import Testing
import Foundation

@Suite("Typing auto-clear behavior (spec)")
struct TypingStateTests {
    final class TypingState {
        private(set) var users = Set<UUID>()
        func add(_ u: UUID) { users.insert(u); scheduleClear(u) }
        private func scheduleClear(_ u: UUID) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                self.users.remove(u)
            }
        }
    }

    @Test("user removed after timeout")
    func testAutoClear() async throws {
        let s = TypingState()
        let u = UUID()
        s.add(u)
        #expect(s.users.contains(u))
        try await Task.sleep(for: .milliseconds(150))
        #expect(!s.users.contains(u))
    }
}

