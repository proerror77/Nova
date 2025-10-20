import SwiftUI
import Combine

// MARK: - Base ViewModel Protocol

/// Base protocol for all ViewModels
protocol BaseViewModel: ObservableObject {
    associatedtype DataType

    var state: ViewState<DataType> { get set }
    var errorMessage: String? { get set }

    func loadData() async
    func refresh() async
}

// MARK: - Paginated ViewModel Protocol

/// Protocol for ViewModels that support pagination
protocol PaginatedViewModel: BaseViewModel where DataType: Collection {
    var isLoadingMore: Bool { get set }
    var hasMorePages: Bool { get set }
    var currentPage: Int { get set }

    func loadMore() async
    func resetPagination()
}

// MARK: - Example: Generic List ViewModel

/// Generic ViewModel for list-based data with pagination
@MainActor
class GenericListViewModel<Item: Identifiable>: ObservableObject, PaginatedViewModel {
    typealias DataType = [Item]

    // MARK: - Published Properties

    @Published private(set) var state: ViewState<[Item]> = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String? = nil

    // MARK: - Pagination Properties

    @Published private(set) var hasMorePages = true
    @Published private(set) var currentPage = 0

    // MARK: - Private Properties

    private var items: [Item] = []
    private let pageSize: Int
    private let fetchItems: (Int, Int) async throws -> [Item]

    // MARK: - Initialization

    /// Initialize with custom fetch function
    /// - Parameters:
    ///   - pageSize: Number of items per page
    ///   - fetchItems: Async function to fetch items (page, pageSize) -> [Item]
    init(
        pageSize: Int = 20,
        fetchItems: @escaping (Int, Int) async throws -> [Item]
    ) {
        self.pageSize = pageSize
        self.fetchItems = fetchItems
    }

    // MARK: - Public Methods

    func loadData() async {
        guard !state.isLoading else { return }

        state = .loading
        currentPage = 0
        hasMorePages = true
        errorMessage = nil

        do {
            let newItems = try await fetchItems(currentPage, pageSize)
            items = newItems

            if newItems.isEmpty {
                state = .empty
            } else {
                state = .loaded(newItems)
                hasMorePages = newItems.count >= pageSize
            }
        } catch {
            state = .error(error)
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        currentPage = 0
        hasMorePages = true
        errorMessage = nil

        do {
            let newItems = try await fetchItems(currentPage, pageSize)
            items = newItems

            if newItems.isEmpty {
                state = .empty
            } else {
                state = .loaded(newItems)
                hasMorePages = newItems.count >= pageSize
            }
        } catch {
            state = .error(error)
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    func loadMore() async {
        guard !isLoadingMore && !isRefreshing && hasMorePages else { return }

        isLoadingMore = true

        do {
            currentPage += 1
            let newItems = try await fetchItems(currentPage, pageSize)

            if newItems.isEmpty {
                hasMorePages = false
            } else {
                items.append(contentsOf: newItems)
                state = .loaded(items)
                hasMorePages = newItems.count >= pageSize
            }
        } catch {
            // Silently fail for pagination - don't change main state
            print("Failed to load more: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }

    func resetPagination() {
        currentPage = 0
        hasMorePages = true
        items = []
    }

    // MARK: - Item Operations

    func updateItem(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        state = .loaded(items)
    }

    func removeItem(_ item: Item) {
        items.removeAll { $0.id == item.id }
        state = items.isEmpty ? .empty : .loaded(items)
    }

    func addItem(_ item: Item, at position: Int = 0) {
        items.insert(item, at: position)
        state = .loaded(items)
    }
}

// MARK: - Example: Simple Data ViewModel

/// Simple ViewModel for single data object
@MainActor
class SimpleDataViewModel<Data>: ObservableObject, BaseViewModel {
    typealias DataType = Data

    // MARK: - Published Properties

    @Published private(set) var state: ViewState<Data> = .idle
    @Published var errorMessage: String? = nil

    // MARK: - Private Properties

    private let fetchData: () async throws -> Data

    // MARK: - Initialization

    init(fetchData: @escaping () async throws -> Data) {
        self.fetchData = fetchData
    }

    // MARK: - Public Methods

    func loadData() async {
        guard !state.isLoading else { return }

        state = .loading
        errorMessage = nil

        do {
            let data = try await fetchData()
            state = .loaded(data)
        } catch {
            state = .error(error)
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await loadData()
    }
}

// MARK: - Example: Form ViewModel

/// ViewModel for form handling with validation
@MainActor
class FormViewModel: ObservableObject {
    // MARK: - Form State

    enum FormState {
        case idle
        case validating
        case submitting
        case success
        case error(String)

        var isSubmitting: Bool {
            if case .submitting = self { return true }
            return false
        }
    }

    // MARK: - Published Properties

    @Published var formState: FormState = .idle
    @Published var validationErrors: [String: String] = [:]

    // MARK: - Validation

    func validate(field: String, value: String, rules: [(String) -> Bool]) -> Bool {
        for rule in rules {
            if !rule(value) {
                return false
            }
        }
        validationErrors.removeValue(forKey: field)
        return true
    }

    func setError(field: String, message: String) {
        validationErrors[field] = message
    }

    func clearError(field: String) {
        validationErrors.removeValue(forKey: field)
    }

    var hasErrors: Bool {
        !validationErrors.isEmpty
    }

    // MARK: - Submission

    func submit(action: () async throws -> Void) async {
        guard !formState.isSubmitting else { return }
        guard !hasErrors else {
            formState = .error("请修正表单错误")
            return
        }

        formState = .submitting

        do {
            try await action()
            formState = .success
        } catch {
            formState = .error(error.localizedDescription)
        }
    }

    func reset() {
        formState = .idle
        validationErrors = [:]
    }
}

// MARK: - Common Validation Rules

struct ValidationRules {
    static func required(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func email(_ value: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: value)
    }

    static func minLength(_ length: Int) -> (String) -> Bool {
        return { value in
            value.count >= length
        }
    }

    static func maxLength(_ length: Int) -> (String) -> Bool {
        return { value in
            value.count <= length
        }
    }

    static func numeric(_ value: String) -> Bool {
        CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: value))
    }

    static func alphanumeric(_ value: String) -> Bool {
        CharacterSet.alphanumerics.isSuperset(of: CharacterSet(charactersIn: value))
    }

    static func matches(_ pattern: String) -> (String) -> Bool {
        return { value in
            let predicate = NSPredicate(format: "SELF MATCHES %@", pattern)
            return predicate.evaluate(with: value)
        }
    }
}

// MARK: - Example Usage

#if DEBUG
// Example: User List ViewModel
struct User: Identifiable {
    let id: String
    let name: String
    let email: String
    let avatar: String
}

@MainActor
class UserListViewModel: GenericListViewModel<User> {
    init() {
        super.init(pageSize: 20) { page, pageSize in
            // Simulate API delay
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // Simulate no more data after page 2
            guard page <= 2 else {
                return []
            }

            // Generate mock users
            let startIndex = page * pageSize
            return (0..<pageSize).map { index in
                let globalIndex = startIndex + index
                let avatars = ["👤", "😊", "🎨", "📱", "🌅", "☕️", "🎬", "📚"]
                return User(
                    id: "user_\(globalIndex)",
                    name: "用户 \(globalIndex)",
                    email: "user\(globalIndex)@example.com",
                    avatar: avatars[globalIndex % avatars.count]
                )
            }
        }
    }
}

// Example: Profile ViewModel
struct Profile {
    let name: String
    let bio: String
    let followers: Int
    let following: Int
}

@MainActor
class ProfileViewModel: SimpleDataViewModel<Profile> {
    init() {
        super.init {
            // Simulate API delay
            try await Task.sleep(nanoseconds: 1_000_000_000)

            return Profile(
                name: "John Doe",
                bio: "iOS Developer & Designer",
                followers: 1234,
                following: 567
            )
        }
    }
}

// Example: Login Form ViewModel
@MainActor
class LoginFormViewModel: FormViewModel {
    @Published var email = ""
    @Published var password = ""

    func validateEmail() -> Bool {
        guard ValidationRules.required(email) else {
            setError(field: "email", message: "邮箱不能为空")
            return false
        }

        guard ValidationRules.email(email) else {
            setError(field: "email", message: "请输入有效的邮箱地址")
            return false
        }

        clearError(field: "email")
        return true
    }

    func validatePassword() -> Bool {
        guard ValidationRules.required(password) else {
            setError(field: "password", message: "密码不能为空")
            return false
        }

        guard ValidationRules.minLength(6)(password) else {
            setError(field: "password", message: "密码至少需要6个字符")
            return false
        }

        clearError(field: "password")
        return true
    }

    func login() async {
        // Validate all fields
        let emailValid = validateEmail()
        let passwordValid = validatePassword()

        guard emailValid && passwordValid else {
            formState = .error("请修正表单错误")
            return
        }

        // Submit
        await submit {
            // Simulate API call
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // Simulate random failure
            if Bool.random() {
                throw NSError(domain: "", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "登录失败，请检查邮箱和密码"
                ])
            }
        }
    }
}
#endif
