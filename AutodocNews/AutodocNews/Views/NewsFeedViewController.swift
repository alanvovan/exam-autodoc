import Combine
import UIKit

private nonisolated enum NewsSection: Hashable, Sendable {
    case main
}

final class NewsFeedViewController: UIViewController {

    private let viewModel: NewsFeedViewModel
    private let client: NewsAPIClient
    private let imageLoader: ImageLoader
    private let layoutMetrics = NewsLayoutMetrics()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<NewsSection, NewsItem>!
    private var cancellables: Set<AnyCancellable> = []
    private var appliedIDs: [Int] = []
    private var lastDivision: CGRect = .null
    private let refreshControl = UIRefreshControl()

    init(client: NewsAPIClient, imageLoader: ImageLoader) {
        self.client = client
        self.imageLoader = imageLoader
        viewModel = NewsFeedViewModel(client: client)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Лента создаётся в коде")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureCollectionView()
        configureDataSource()
        view.backgroundColor = GarageTheme.background
        navigationItem.title = "Новости"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        bind()
        registerForTraitChanges([
            UITraitHorizontalSizeClass.self,
            UITraitVerticalSizeClass.self,
            UITraitDisplayScale.self
        ]) { (controller: Self, _) in
            controller.collectionView.collectionViewLayout.invalidateLayout()
            controller.reloadVisibleCells()
        }
        viewModel.loadInitial()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard collectionView != nil else { return }
        let frame = DuoLayout.activeDivisionFrame(in: collectionView) ?? .null
        guard frame != lastDivision else { return }
        lastDivision = frame
        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard isViewLoaded, let collectionView else { return }
        coordinator.animate(alongsideTransition: { _ in
            collectionView.collectionViewLayout.invalidateLayout()
        })
    }

    private func configureCollectionView() {
        let layout = NewsLayout.make(metrics: layoutMetrics)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        layoutMetrics.host = collectionView
        collectionView.backgroundColor = GarageTheme.background
        collectionView.indicatorStyle = .white
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.selfSizingInvalidation = .enabledIncludingConstraints
        collectionView.refreshControl = refreshControl
        refreshControl.tintColor = GarageTheme.brass
        refreshControl.addAction(UIAction { [weak self] _ in
            self?.viewModel.refresh()
        }, for: .valueChanged)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<NewsCell, NewsItem> { [weak self] cell, _, item in
            guard self != nil else { return }
            cell.configure(item: item, loader: ImageLoader.shared)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<NewsFooterView>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footer, _, _ in
            guard let self else { return }
            footer.configure(
                isLoading: self.viewModel.isLoadingNextPage,
                message: self.viewModel.pagingError
            ) { [weak self] in
                self?.viewModel.retryPaging()
            }
        }
        dataSource.supplementaryViewProvider = { (collectionView: UICollectionView, _: String, indexPath: IndexPath) in
            collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
        }
    }

    private func bind() {
        viewModel.$items
            .sink { [weak self] items in
                self?.apply(items)
            }
            .store(in: &cancellables)

        viewModel.$phase
            .combineLatest(viewModel.$isRefreshing, viewModel.$isLoadingNextPage, viewModel.$pagingError)
            .sink { [weak self] phase, isRefreshing, isLoadingNextPage, pagingError in
                self?.renderChrome(
                    phase: phase,
                    isRefreshing: isRefreshing,
                    isLoadingNextPage: isLoadingNextPage,
                    pagingError: pagingError
                )
            }
            .store(in: &cancellables)
    }

    private func apply(_ items: [NewsItem]) {
        let ids = items.map(\.id)
        if !appliedIDs.isEmpty, ids.count > appliedIDs.count, ids.starts(with: appliedIDs) {
            var snapshot = dataSource.snapshot()
            let existing = Set(snapshot.itemIdentifiers.map { item in item.id })
            let fresh = items.filter { !existing.contains($0.id) }
            if !fresh.isEmpty {
                snapshot.appendItems(fresh)
                dataSource.apply(snapshot, animatingDifferences: true)
            }
        } else {
            var snapshot = NSDiffableDataSourceSnapshot<NewsSection, NewsItem>()
            snapshot.appendSections([.main])
            snapshot.appendItems(items)
            dataSource.apply(snapshot, animatingDifferences: !appliedIDs.isEmpty)
        }
        appliedIDs = ids
        renderChrome(
            phase: viewModel.phase,
            isRefreshing: viewModel.isRefreshing,
            isLoadingNextPage: viewModel.isLoadingNextPage,
            pagingError: viewModel.pagingError
        )
    }

    private func renderChrome(
        phase: FeedPhase,
        isRefreshing: Bool,
        isLoadingNextPage: Bool,
        pagingError: String?
    ) {
        if !isRefreshing {
            refreshControl.endRefreshing()
        }
        layoutMetrics.showsFooter = isLoadingNextPage || pagingError != nil
        collectionView.collectionViewLayout.invalidateLayout()
        updateFooter(isLoading: isLoadingNextPage, message: pagingError)
        updateBackground(phase: phase)
    }

    private func updateFooter(isLoading: Bool, message: String?) {
        let footers = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionFooter)
        for case let footer as NewsFooterView in footers {
            footer.configure(isLoading: isLoading, message: message) { [weak self] in
                self?.viewModel.retryPaging()
            }
        }
    }

    private func updateBackground(phase: FeedPhase) {
        guard viewModel.items.isEmpty, !viewModel.isRefreshing else {
            collectionView.backgroundView = nil
            return
        }
        switch phase {
        case .idle, .loading:
            var configuration = UIContentUnavailableConfiguration.loading()
            configuration.text = "Загрузка"
            configuration.textProperties.color = .secondaryLabel
            collectionView.backgroundView = unavailableView(configuration)
        case .failed(let message):
            collectionView.backgroundView = unavailable(
                symbol: "wifi.slash",
                title: "Не удалось загрузить",
                message: message,
                retry: true
            )
        case .loaded:
            collectionView.backgroundView = unavailable(
                symbol: "newspaper",
                title: "Новостей нет",
                message: nil,
                retry: true
            )
        }
    }

    private func unavailable(symbol: String, title: String, message: String?, retry: Bool) -> UIView {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: symbol)
        configuration.text = title
        configuration.secondaryText = message
        configuration.imageProperties.tintColor = GarageTheme.brass
        configuration.textProperties.color = .label
        configuration.secondaryTextProperties.color = .secondaryLabel
        if retry {
            var button = UIButton.Configuration.bordered()
            button.title = "Повторить"
            button.baseForegroundColor = GarageTheme.brass
            button.baseBackgroundColor = GarageTheme.brass.withAlphaComponent(0.14)
            button.background.strokeColor = GarageTheme.brass.withAlphaComponent(0.45)
            button.background.strokeWidth = 1
            configuration.button = button
            configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
                self?.viewModel.refresh()
            }
        }
        return unavailableView(configuration)
    }

    private func unavailableView(_ configuration: UIContentUnavailableConfiguration) -> UIContentUnavailableView {
        let unavailable = UIContentUnavailableView(configuration: configuration)
        unavailable.backgroundColor = .clear
        unavailable.tintColor = GarageTheme.brass
        return unavailable
    }

    private func reloadVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let item = dataSource.itemIdentifier(for: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath) as? NewsCell else { continue }
            cell.configure(item: item, loader: imageLoader)
        }
    }

    private func open(_ item: NewsItem) {
        let detail = NewsDetailViewController(item: item, client: client, imageLoader: imageLoader)
        if let split = splitViewController, !split.isCollapsed,
           let secondary = split.viewController(for: .secondary) as? UINavigationController {
            secondary.setViewControllers([detail], animated: false)
        } else if let split = splitViewController {
            split.showDetailViewController(detail, sender: self)
        } else {
            navigationController?.pushViewController(detail, animated: true)
        }
    }
}

extension NewsFeedViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        open(item)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        viewModel.loadNextPageIfNeeded(at: indexPath.item)
    }
}

extension NewsFeedViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let scale = traitCollection.displayScale
        let width = max(collectionView.bounds.width, 1)
        for indexPath in indexPaths {
            viewModel.loadNextPageIfNeeded(at: indexPath.item)
            guard let url = dataSource.itemIdentifier(for: indexPath)?.titleImageURL else { continue }
            Task {
                await imageLoader.image(
                    for: url,
                    pointSize: CGSize(width: width, height: width * 9 / 16),
                    scale: scale
                )
            }
        }
    }
}
