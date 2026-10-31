import Foundation
import Testing
@testable import AutodocNews

nonisolated final class LoadedDetailStub: NewsStub {
    nonisolated override class func reply(for request: URLRequest) -> NewsReply {
        if request.url?.path.contains("/item/") == true {
            return NewsReply(body: Data(newsItemJSON(text: "<p>Текст</p>").utf8))
        }
        return NewsReply(body: newsPageJSON())
    }
}

nonisolated final class OfflineDetailStub: NewsStub {
    nonisolated override class func reply(for request: URLRequest) -> NewsReply {
        if request.url?.path.contains("/item/") == true {
            return NewsReply(failure: URLError(.notConnectedToInternet))
        }
        return NewsReply(body: newsPageJSON())
    }
}

nonisolated final class MissingDetailStub: NewsStub {
    nonisolated override class func reply(for request: URLRequest) -> NewsReply {
        if request.url?.path.contains("/item/") == true {
            return NewsReply(status: 404, body: Data())
        }
        return NewsReply(body: newsPageJSON())
    }
}

struct NewsDetailLoadTests {
    @Test func loadedDetailKeepsTheArticleText() async throws {
        let client = NewsAPIClient(session: session(using: LoadedDetailStub.self))
        let preview = try await client.page(1).news[0]
        let model = NewsDetailViewModel(preview: preview, client: client)
        model.load()
        let finished = await waitUntil {
            if case .loaded = model.phase { return true }
            if case .failed = model.phase { return true }
            return false
        }
        #expect(finished)
        #expect(model.phase == .loaded)
        #expect(model.detail?.text == "<p>Текст</p>")
    }

    @Test func offlineFailureUsesTheConnectionMessage() async throws {
        let client = NewsAPIClient(session: session(using: OfflineDetailStub.self))
        let preview = try await client.page(1).news[0]
        let model = NewsDetailViewModel(preview: preview, client: client)
        model.load()
        let finished = await waitUntil {
            if case .failed = model.phase { return true }
            if case .loaded = model.phase { return true }
            return false
        }
        #expect(finished)
        #expect(model.phase == .failed("Нет соединения с интернетом."))
    }

    @Test func httpFailureIncludesTheStatusCode() async throws {
        let client = NewsAPIClient(session: session(using: MissingDetailStub.self))
        let preview = try await client.page(1).news[0]
        let model = NewsDetailViewModel(preview: preview, client: client)
        model.load()
        let finished = await waitUntil {
            if case .failed = model.phase { return true }
            if case .loaded = model.phase { return true }
            return false
        }
        #expect(finished)
        #expect(model.phase == .failed("Сервер вернул ошибку 404."))
    }

    @Test func timeoutMessage() {
        #expect(UserFacingError.message(for: URLError(.timedOut)) == "Сервер не ответил вовремя.")
    }

    @Test func unknownErrorMessage() {
        let error = NSError(domain: "test", code: 1)
        #expect(UserFacingError.message(for: error) == "Не удалось загрузить данные.")
    }
}
