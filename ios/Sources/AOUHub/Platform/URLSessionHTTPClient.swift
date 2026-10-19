import AOUHubCore
import Foundation

/// Plain GET with no cookies and no redirects off the allowed host: the update
/// check never shares a session with anything else.
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func get(_ url: URL, headers: [String: String]) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
