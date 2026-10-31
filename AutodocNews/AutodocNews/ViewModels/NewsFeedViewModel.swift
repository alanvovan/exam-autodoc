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
    @Published private(set) var category: NewsCategory = .all
    @Published private(set) var phase: FeedPhase = .idle
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var pagingError: String?

    private let client: NewsAPIClient
    private var fetched: [NewsItem] = []
    private var nextPage = 1
    private var totalCount = 0
    private var task: Task<Void, Never>?
    private var generation = 0
    private var autoFillPages = 0

    /// Сколько карточек выбранного раздела держим заранее, чтобы экран не пустел на редкой категории.
    private let filteredTarget = 10
    private let autoFillLimit = 40

    /// Сервер отдаёт общую ленту без фильтра. `hasMore` считает сырые страницы, не отфильтрованные карточки.
    var hasMore: Bool { fetched.count < totalCount }

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

    func select(_ category: NewsCategory) {
        guard category != self.category else { return }
        self.category = category
        pagingError = nil
        autoFillPages = 0
        publishFilter()
        fillIfSparse()
    }

    func retryPaging() {
        pagingError = nil
        guard let last = items.indices.last else {
            if fetched.isEmpty {
                refresh()
            } else {
                fetchNextPage(countsAsAutoFill: false)
            }
            return
        }
        loadNextPageIfNeeded(at: last)
    }

    /// Догрузка, когда на экране одна из последних четырёх карточек выбранного раздела.
    func loadNextPageIfNeeded(at index: Int) {
        guard !items.isEmpty, index >= items.count - 4 else { return }
        fetchNextPage(countsAsAutoFill: false)
    }

    private func replaceFromStart() {
        generation += 1
        let token = generation
        task?.cancel()
        isLoadingNextPage = false
        pagingError = nil
        autoFillPages = 0
        isRefreshing = !items.isEmpty
        if items.isEmpty {
            phase = .loading
        }
        task = Task { [weak self] in
            await self?.fetch(page: 1, replacing: true, generation: token)
        }
    }

    private func fetchNextPage(countsAsAutoFill: Bool) {
        guard pagingError == nil, !isLoadingNextPage, !isRefreshing, hasMore else { return }
        if countsAsAutoFill {
            autoFillPages += 1
        }
        let page = nextPage
        let token = generation
        isLoadingNextPage = true
        task = Task { [weak self] in
            await self?.fetch(page: page, replacing: false, generation: token)
        }
    }

    /// Редкая категория на общей странице почти не встречается, поэтому добираем страницы, пока раздел не заполнится.
    private func fillIfSparse() {
        guard phase == .loaded, items.count < filteredTarget, autoFillPages < autoFillLimit else { return }
        fetchNextPage(countsAsAutoFill: true)
    }

    private func publishFilter() {
        let filtered: [NewsItem]
        if category == .all {
            filtered = fetched
        } else {
            let selected = category.rawValue
            filtered = fetched.filter { $0.categoryType == selected }
        }
        if filtered != items {
            items = filtered
        }
    }

    private func fetch(page: Int, replacing: Bool, generation: Int) async {
        do {
            let result = try await client.page(page)
            guard generation == self.generation, !Task.isCancelled else { return }
            if replacing {
                fetched = result.news
                nextPage = 2
                totalCount = result.totalCount
            } else if result.news.isEmpty {
                // Пустая страница — конец ленты, даже если totalCount ещё больше.
                totalCount = fetched.count
            } else {
                let known = Set(fetched.map(\.id))
                fetched.append(contentsOf: result.news.filter { !known.contains($0.id) })
                nextPage = page + 1
                totalCount = result.totalCount
            }
            publishFilter()
            phase = .loaded
            pagingError = nil
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            let message = UserFacingError.message(for: error)
            if replacing && fetched.isEmpty {
                phase = .failed(message)
            } else {
                pagingError = message
                if phase != .loaded {
                    phase = .loaded
                }
            }
        }

        guard generation == self.generation, !Task.isCancelled else { return }
        isLoadingNextPage = false
        isRefreshing = false
        task = nil
        if pagingError == nil, phase == .loaded {
            fillIfSparse()
        }
    }
}
