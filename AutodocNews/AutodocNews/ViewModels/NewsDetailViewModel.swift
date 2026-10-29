import Combine
import Foundation

enum DetailPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class NewsDetailViewModel {
    @Published private(set) var detail: NewsDetail?
    @Published private(set) var phase: DetailPhase = .idle

    let preview: NewsItem
    private let client: NewsAPIClient
    private var task: Task<Void, Never>?

    init(preview: NewsItem, client: NewsAPIClient) {
        self.preview = preview
        self.client = client
    }

    func load() {
        switch phase {
        case .idle, .failed:
            break
        case .loading, .loaded:
            return
        }
        phase = .loading
        let path = preview.url
        task = Task {
            do {
                let detail = try await client.detail(path: path)
                self.detail = detail
                self.phase = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(UserFacingError.message(for: error))
            }
        }
    }

    func cancel() {
        task?.cancel()
    }
}
