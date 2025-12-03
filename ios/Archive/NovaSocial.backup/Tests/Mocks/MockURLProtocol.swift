import Foundation

/// MockURLProtocol - 用于拦截和模拟网络请求
/// TDD: 让测试可以完全控制网络响应，无需真实后端
final class MockURLProtocol: URLProtocol {

    // MARK: - Static Configuration

    /// 请求处理器类型
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data?)

    /// 全局请求处理器
    static var requestHandler: RequestHandler?

    /// 模拟响应延迟（秒）
    static var responseDelay: TimeInterval = 0

    /// 重置所有配置
    static func reset() {
        requestHandler = nil
        responseDelay = 0
    }

    // MARK: - URLProtocol Override

    override class func canInit(with request: URLRequest) -> Bool {
        // 拦截所有请求
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("MockURLProtocol: requestHandler not set")
        }

        // 模拟网络延迟
        if MockURLProtocol.responseDelay > 0 {
            Thread.sleep(forTimeInterval: MockURLProtocol.responseDelay)
        }

        do {
            let (response, data) = try handler(request)

            // 发送响应
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            // 发送数据
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }

            // 完成
            client?.urlProtocolDidFinishLoading(self)

        } catch {
            // 发送错误
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // 清理资源
    }
}

// MARK: - Convenience Helpers

extension MockURLProtocol {

    /// 配置成功响应
    static func mockSuccess(statusCode: Int = 200, data: Data? = nil) {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
    }

    /// 配置 JSON 响应
    static func mockJSON<T: Encodable>(_ object: T, statusCode: Int = 200) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(object)

        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
    }

    /// 配置错误响应
    static func mockError(statusCode: Int, errorData: Data? = nil) {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, errorData)
        }
    }

    /// 配置网络超时
    static func mockTimeout() {
        requestHandler = { _ in
            throw URLError(.timedOut)
        }
    }

    /// 配置无网络连接
    static func mockNoConnection() {
        requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
    }
}
