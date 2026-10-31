import Foundation

struct NewsReply: Sendable {
    var status: Int = 200
    var body: Data = Data()
    var failure: (any Error)?
}

nonisolated class NewsStub: URLProtocol, @unchecked Sendable {
    nonisolated class func reply(for request: URLRequest) -> NewsReply {
        NewsReply()
    }

    nonisolated override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    nonisolated func deliver(_ reply: NewsReply) {
        guard let client else { return }
        if let failure = reply.failure {
            client.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              )
        else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: reply.body)
        client.urlProtocolDidFinishLoading(self)
    }

    nonisolated override func startLoading() {
        deliver(Self.reply(for: request))
    }

    nonisolated override func stopLoading() {}
}

func session<P: NewsStub>(using type: P.Type) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [type]
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
}

nonisolated func newsItemJSON(text: String? = nil) -> String {
    let textField = text.map { ",\"text\":\"\($0)\"" } ?? ""
    return """
    {"id":1,"title":"Заголовок","description":"Кратко","publishedDate":"2024-05-01T12:00:00","url":"news/1","fullUrl":"https://www.autodoc.ru/news/1","titleImageUrl":"","categoryType":"Автомобильные новости"\(textField)}
    """
}

nonisolated func newsPageJSON(items: [String] = [newsItemJSON()]) -> Data {
    let body = items.joined(separator: ",")
    return Data("{\"news\":[\(body)],\"totalCount\":\(items.count)}".utf8)
}

func waitUntil(
    timeout: TimeInterval = 2,
    _ condition: () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
