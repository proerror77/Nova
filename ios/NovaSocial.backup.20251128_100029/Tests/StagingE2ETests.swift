import XCTest

/// Basic staging reachability checks against the AWS LoadBalancer.
/// We only assert that the service responds (200/401/403/404) when hit with the
/// required Host header; 5xx or network failures indicate staging is down.
final class StagingE2ETests: XCTestCase {
    private let baseURLString = "http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"
    private let hostHeader = "api.nova.local"

    func testContentServiceIsReachableOnStaging() async throws {
        try await assertReachable(path: "/api/v2/posts/author/test")
    }

    // MARK: - Helpers

    private func assertReachable(path: String) async throws {
        guard let url = URL(string: baseURLString + path) else {
            return XCTFail("Invalid URL for path: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(hostHeader, forHTTPHeaderField: "Host")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        // Bypass any local/system proxies to avoid false 502s when calling staging.
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return XCTFail("No HTTPURLResponse for \(url)")
        }

        let reachableStatuses: Set<Int> = [200, 401, 403, 404]
        let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<no-body>"

        XCTAssertTrue(
            reachableStatuses.contains(http.statusCode),
            "Staging unreachable: status=\(http.statusCode) body=\(bodyPreview)"
        )
    }
}
