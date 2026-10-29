import UIKit

final class NewsSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    init(client: NewsAPIClient = NewsAPIClient(), imageLoader: ImageLoader = .shared) {
        super.init(style: .doubleColumn)
        delegate = self
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        presentsWithGesture = true

        let feed = UINavigationController(
            rootViewController: NewsFeedViewController(client: client, imageLoader: imageLoader)
        )
        let detail = UINavigationController(rootViewController: NewsPlaceholderViewController())
        setViewController(feed, for: .primary)
        setViewController(detail, for: .secondary)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = GarageTheme.background
        if let primary = viewController(for: .primary) as? UINavigationController {
            GarageTheme.apply(to: primary)
        }
        if let secondary = viewController(for: .secondary) as? UINavigationController {
            GarageTheme.apply(to: secondary)
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        revealFeedIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("Разделение создаётся в коде")
    }

    /// На iPhone колоночный split по умолчанию открывает вторичную колонку.
    /// Без выбранной статьи там только заглушка, поэтому сверху должна быть лента.
    func splitViewController(
        _ splitViewController: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        showsArticle(in: splitViewController) ? .secondary : .primary
    }

    func splitViewController(
        _ splitViewController: UISplitViewController,
        collapseSecondary secondaryViewController: UIViewController,
        onto primaryViewController: UIViewController
    ) -> Bool {
        guard let navigation = secondaryViewController as? UINavigationController else { return false }
        let showsArticle = navigation.viewControllers.contains { $0 is NewsDetailViewController }
        return !showsArticle
    }

    private func revealFeedIfNeeded() {
        guard isCollapsed, !showsArticle(in: self) else { return }
        show(.primary)
    }

    private func showsArticle(in splitViewController: UISplitViewController) -> Bool {
        if columnShowsArticle(.secondary, in: splitViewController) { return true }
        if splitViewController.isCollapsed, columnShowsArticle(.primary, in: splitViewController) { return true }
        return false
    }

    private func columnShowsArticle(
        _ column: UISplitViewController.Column,
        in splitViewController: UISplitViewController
    ) -> Bool {
        let controller = splitViewController.viewController(for: column)
        let controllers = (controller as? UINavigationController)?.viewControllers ?? (controller.map { [$0] } ?? [])
        return controllers.contains { $0 is NewsDetailViewController }
    }

    func splitViewController(
        _ splitViewController: UISplitViewController,
        separateSecondaryFrom primaryViewController: UIViewController
    ) -> UIViewController? {
        guard let navigation = primaryViewController as? UINavigationController else { return nil }
        let showsArticle = navigation.viewControllers.contains { $0 is NewsDetailViewController }
        if showsArticle {
            return nil
        }
        return splitViewController.viewController(for: .secondary)
    }
}
