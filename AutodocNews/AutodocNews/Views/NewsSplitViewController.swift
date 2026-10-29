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

    required init?(coder: NSCoder) {
        fatalError("Разделение создаётся в коде")
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
