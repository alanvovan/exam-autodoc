import Foundation

nonisolated struct NewsAPIClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func page(_ page: Int, count: Int = NewsEndpoint.pageSize) async throws -> NewsPage {
        try await fetch(NewsEndpoint.page(page, count: count))
    }

    func detail(path: String) async throws -> NewsDetail {
        try await fetch(NewsEndpoint.item(path: path))
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            throw APIError.transport(error)
        } catch {
            throw APIError.transport(URLError(.unknown))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode)
        }

        let decoder = JSONDecoder()
        // Сервер отдаёт «yyyy-MM-dd'T'HH:mm:ss» без часового пояса.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        decoder.dateDecodingStrategy = .formatted(formatter)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}
