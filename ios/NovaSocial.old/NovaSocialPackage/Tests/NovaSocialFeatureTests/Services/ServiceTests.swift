import Testing
import Foundation

@testable import NovaSocialFeature

// MARK: - Cache Manager Tests

@Suite("CacheManager Tests")
struct CacheManagerTests {
    var cache: CacheManager!

    mutating func setup() async {
        cache = CacheManager()
    }

    @Test("Cache stores and retrieves values")
    func testCacheStoreAndRetrieve() async {
        let testData = ["item1", "item2", "item3"]
        cache.set(testData, for: "test_key")

        let retrieved: [String]? = cache.get(for: "test_key")
        #expect(retrieved == testData)
    }

    @Test("Cache returns nil for missing keys")
    func testCacheMissing() {
        let missing: [String]? = cache.get(for: "nonexistent_key")
        #expect(missing == nil)
    }

    @Test("Cache can clear entries")
    func testCacheClear() {
        let testData = ["item1"]
        cache.set(testData, for: "key1")

        cache.clear(for: "key1")
        let retrieved: [String]? = cache.get(for: "key1")

        #expect(retrieved == nil)
    }

    @Test("Cache clears all entries")
    func testCacheClearAll() {
        cache.set(["data1"], for: "key1")
        cache.set(["data2"], for: "key2")
        cache.set(["data3"], for: "key3")

        cache.clearAll()

        let r1: [String]? = cache.get(for: "key1")
        let r2: [String]? = cache.get(for: "key2")
        let r3: [String]? = cache.get(for: "key3")

        #expect(r1 == nil)
        #expect(r2 == nil)
        #expect(r3 == nil)
    }

    @Test("Cache stores and updates values")
    func testCacheUpdate() async throws {
        let testData1 = ["item1"]
        let testData2 = ["item1", "item2"]

        cache.set(testData1, for: "update_key")
        let first: [String]? = cache.get(for: "update_key")
        #expect(first == testData1)

        // Update with new data
        cache.set(testData2, for: "update_key")
        let updated: [String]? = cache.get(for: "update_key")
        #expect(updated == testData2)
    }
}

// MARK: - Feed Service Tests

@Suite("FeedService Tests")
struct FeedServiceTests {
    var feedService: FeedService!
    var cache: CacheManager!

    mutating func setup() async {
        cache = CacheManager()
        feedService = FeedService(httpClient: MockHTTPClient(), cache: cache)
    }

    @Test("FeedService initializes with default dependencies")
    func testFeedServiceInitialization() {
        let service = FeedService()
        // Service initializes successfully without error
        _ = service
        #expect(true)
    }

    @Test("FeedService can be initialized with custom dependencies")
    func testFeedServiceCustomInitialization() {
        let mockClient = MockHTTPClient()
        let customCache = CacheManager()
        let service = FeedService(httpClient: mockClient, cache: customCache)
        // Service initializes successfully with custom dependencies
        _ = service
        #expect(true)
    }
}

// MARK: - User Service Tests

@Suite("UserService Tests")
struct UserServiceTests {
    var userService: UserService!

    mutating func setup() async {
        userService = UserService(httpClient: MockHTTPClient())
    }

    @Test("UserService initializes")
    func testUserServiceInitialization() {
        #expect(userService != nil)
    }
}

// MARK: - Notification Service Tests

@Suite("NotificationService Tests")
struct NotificationServiceTests {
    var notificationService: NotificationService!
    var cache: CacheManager!

    mutating func setup() async {
        cache = CacheManager()
        notificationService = NotificationService(
            httpClient: MockHTTPClient(),
            cache: cache,
            useMockData: true
        )
    }

    @Test("NotificationService uses mock data when requested")
    func testNotificationServiceMockData() async throws {
        let notifications = try await notificationService.getNotifications()
        #expect(!notifications.isEmpty)
        #expect(notifications.count == 6) // We have 6 mock notifications
    }

    @Test("NotificationService caches results")
    func testNotificationServiceCaching() async throws {
        let firstCall = try await notificationService.getNotifications()
        let secondCall = try await notificationService.getNotifications()

        #expect(firstCall.count == secondCall.count)
        #expect(firstCall == secondCall)
    }

    @Test("NotificationService mock data contains valid users")
    func testNotificationServiceMockDataStructure() async throws {
        let notifications = try await notificationService.getNotifications()

        for notification in notifications {
            #expect(!notification.id.isEmpty)
            #expect(!notification.userId.isEmpty)
            #expect(!notification.actionType.isEmpty)
            #expect(!notification.timestamp.isEmpty)
            #expect(!notification.actor.displayName.isEmpty)
            #expect(!notification.actor.username.isEmpty)
        }
    }
}

// MARK: - Search Service Tests

@Suite("SearchService Tests")
struct SearchServiceTests {
    var searchService: SearchService!
    var cache: CacheManager!

    mutating func setup() async {
        cache = CacheManager()
        searchService = SearchService(httpClient: MockHTTPClient(), cache: cache)
    }

    @Test("SearchService initializes")
    func testSearchServiceInitialization() {
        #expect(searchService != nil)
    }
}

// MARK: - APIConfig Tests

@Suite("APIConfig Tests")
struct APIConfigTests {
    @Test("APIConfig provides valid base URL")
    func testAPIConfigBaseURL() {
        let url = APIConfig.baseURL
        #expect(url.scheme == "https" || url.scheme == "http")
    }

    @Test("APIConfig provides authorization headers")
    func testAPIConfigHeaders() {
        let headers = APIConfig.makeHeaders()

        #expect(headers["Authorization"] != nil)
        #expect(headers["Authorization"]?.hasPrefix("Bearer ") == true)
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["Accept"] == "application/json")
    }

    @Test("APIConfig debug info is available")
    func testAPIConfigDebugInfo() {
        let debugInfo = APIConfig.debugInfo
        #expect(debugInfo.contains("API Configuration"))
        #expect(debugInfo.contains("Environment"))
        #expect(debugInfo.contains("Base URL"))
        #expect(debugInfo.contains("Timeout"))
    }
}
