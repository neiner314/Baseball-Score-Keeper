import Foundation

/// Minimal JSON GET client. Deliberately small — there is exactly one kind of
/// request this app makes.
struct HTTPClient: @unchecked Sendable {
    let session: URLSession
    let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 20) {
        self.session = session
        self.timeout = timeout
    }

    func get<Value: Decodable>(_ url: URL, as type: Value.Type) async throws -> Value {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RosterProviderError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RosterProviderError.badResponse(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw RosterProviderError.malformedData(String(describing: error))
        }
    }

    /// Fetches a plain-text body — used for the CSV feeds that some leagues
    /// publish instead of JSON. Redirects (a GitHub release download hops to a
    /// storage host) are followed by URLSession automatically.
    func getText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RosterProviderError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RosterProviderError.badResponse(http.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw RosterProviderError.malformedData("response was not UTF-8 text")
        }
        return text
    }
}
