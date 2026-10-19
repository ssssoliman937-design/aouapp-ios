import AOUHubCore
import Foundation

/// HTTPS transport for SIS/LMS. Cookies are handled by hand (as Android's
/// SisAuthInterceptor does): no shared cookie store, so the `_spaoutkn` cookie
/// only ever goes back to the SIS in the explicit `cookie` header.
struct URLSessionTransport: HTTPTransport {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard request.url.scheme == "https" else { throw URLError(.secureConnectionFailed) }
        var r = URLRequest(url: request.url)
        r.httpMethod = request.method
        r.httpBody = request.body
        request.headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: r)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        http?.allHeaderFields.forEach { key, value in headers["\(key)"] = "\(value)" }
        return HTTPResponse(status: http?.statusCode ?? 0, headers: headers, body: data)
    }
}
