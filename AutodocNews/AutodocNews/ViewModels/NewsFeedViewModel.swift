import Combine
import Foundation

enum FeedPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class NewsFeedViewModel {
    @Published private(set) var items: [NewsItem] = []
    @Published private(set) var phase: FeedPhase = .idle
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var pagingError: String?

    private let client: NewsAPIClient
    private var nextPage = 1
    private var totalCount = 0
    private var task: Task<Void, Never>?
    private var generation = 0

    var hasMore: Bool { items.count < totalCount }

    init(client: NewsAPIClient) {
        self.client = client
    }

    func loadInitial() {
        guard phase == .idle else { return }
        replaceFromStart()
    }

    func refresh() {
        replaceFromStart()
    }

    func retryPaging() {
        pagingError = nil
        guard let last = items.indices.last else {
            refresh()
            return
        }
        loadNextPageIfNeeded(at: last)
    }

    /// Догрузка, когда на экране одна из последних четырёх ячеек. Один запрос за раз.
    func loadNextPageIfNeeded(at index: Int) {
        guard pagingError == nil, !isLoadingNextPage, !isRefreshing, hasMore else { return }
        guard index >= items.count - 4 else { return }
        let page = nextPage
        let token = generation
        isLoadingNextPage = true
        task = Task { [weak self] in
            await self?.fetch(page: page, replacing: false, generation: token)
        }
    }

    private func replaceFromStart() {
        generation += 1
        let token = generation
        task?.cancel()
        isLoadingNextPage = false
        pagingError = nil
        isRefreshing = !items.isEmpty
        if items.isEmpty {
            phase = .loading
        }
        task = Task { [weak self] in
            await self?.fetch(page: 1, replacing: true, generation: token)
        }
    }

    private func fetch(page: Int, replacing: Bool, generation: Int) async {
        defer {
            if generation == self.generation {
                isLoadingNextPage = false
                isRefreshing = false
                task = nil
            }
        }

        do {
            let result = try await client.page(page)
            guard generation == self.generation, !Task.isCancelled else { return }
            if replacing {
                items = result.news
                nextPage = 2
                totalCount = result.totalCount
            } else if result.news.isEmpty {
                // Пустая страница — конец ленты, даже если totalCount ещё больше.
                totalCount = items.count
            } else {
                let known = Set(items.map(\.id))
                items.append(contentsOf: result.news.filter { !known.contains($0.id) })
                nextPage = page + 1
                totalCount = result.totalCount
            }
            phase = .loaded
            pagingError = nil
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            let message = UserFacingError.message(for: error)
            if replacing && items.isEmpty {
                phase = .failed(message)
            } else {
                pagingError = message
                if phase != .loaded {
                    phase = .loaded
                }
            }
        }
    }
}
