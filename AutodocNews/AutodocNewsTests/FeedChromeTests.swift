import Testing
import UIKit
@testable import AutodocNews

struct HeaderMetrics: Equatable {
    var topGap: CGFloat
    var leading: CGFloat
    var trailing: CGFloat
    var join: CGFloat
}

nonisolated final class RegularFailStub: NewsStub {
    nonisolated(unsafe) static var gateOpen = false

    nonisolated override class func reply(for request: URLRequest) -> NewsReply {
        NewsReply(status: 500, body: Data())
    }

    nonisolated override func startLoading() {
        DispatchQueue.global().async {
            while !Self.gateOpen {
                Thread.sleep(forTimeInterval: 0.01)
            }
            self.deliver(Self.reply(for: self.request))
        }
    }
}

nonisolated final class CompactFailStub: NewsStub {
    nonisolated(unsafe) static var gateOpen = false

    nonisolated override class func reply(for request: URLRequest) -> NewsReply {
        NewsReply(status: 500, body: Data())
    }

    nonisolated override func startLoading() {
        DispatchQueue.global().async {
            while !Self.gateOpen {
                Thread.sleep(forTimeInterval: 0.01)
            }
            self.deliver(Self.reply(for: self.request))
        }
    }
}

nonisolated final class EmptyPageStub: NewsStub {
    nonisolated override class func reply(for request: URLRequest) -> NewsReply {
        NewsReply(body: newsPageJSON(items: []))
    }
}

nonisolated final class OneItemStub: NewsStub {
    nonisolated override class func reply(for request: URLRequest) -> NewsReply {
        NewsReply(body: newsPageJSON())
    }
}

struct FeedChromeTests {
    @Test func regularHeightKeepsTheHeaderWhenLoadingFails() async {
        RegularFailStub.gateOpen = false
        let feed = makeFeed(using: RegularFailStub.self)
        let window = show(feed)
        let loading = visibleStrings(in: feed.view)
        #expect(loading.contains("Загрузка"), "Видно: \(loading)")
        expectTitle(feed)
        let before = headerMetrics(feed)
        expectHeader(before, top: 4)

        RegularFailStub.gateOpen = true
        let failed = await waitUntil {
            visibleStrings(in: feed.view).contains("Не удалось загрузить")
        }
        let after = visibleStrings(in: feed.view)
        #expect(failed, "Видно: \(after)")
        #expect(after.contains("Сервер вернул ошибку 500."))
        #expect(after.contains("Повторить"))
        expectHeader(headerMetrics(feed), top: 4)
        #expect(headerMetrics(feed) == before)
        _ = window
    }

    @Test func compactHeightPinsTheSegmentToTheSafeArea() async {
        CompactFailStub.gateOpen = false
        let feed = makeFeed(using: CompactFailStub.self)
        feed.traitOverrides.verticalSizeClass = .compact
        let window = show(feed)
        window.traitOverrides.verticalSizeClass = .compact
        feed.view.layoutIfNeeded()

        let loading = visibleStrings(in: feed.view)
        #expect(loading.contains("Загрузка"), "Видно: \(loading)")
        expectTitle(feed)
        expectHeader(headerMetrics(feed), top: 0)

        CompactFailStub.gateOpen = true
        let failed = await waitUntil {
            visibleStrings(in: feed.view).contains("Не удалось загрузить")
        }
        #expect(failed)
        expectHeader(headerMetrics(feed), top: 0)
        _ = window
    }

    @Test func emptyFeedShowsTheEmptyState() async {
        let feed = makeFeed(using: EmptyPageStub.self)
        let window = show(feed)
        let appeared = await waitUntil {
            visibleStrings(in: feed.view).contains("Новостей нет")
        }
        let texts = visibleStrings(in: feed.view)
        #expect(appeared, "Видно: \(texts)")
        #expect(texts.contains("Повторить"))
        _ = window
    }

    @Test func aNewsItemClearsTheBackground() async {
        let feed = makeFeed(using: OneItemStub.self)
        let window = show(feed)
        let cleared = await waitUntil {
            collectionView(in: feed.view)?.backgroundView == nil
                && !visibleStrings(in: feed.view).contains("Загрузка")
        }
        #expect(cleared, "Видно: \(visibleStrings(in: feed.view))")
        _ = window
    }
}

private func makeFeed<P: NewsStub>(using type: P.Type) -> NewsFeedViewController {
    NewsFeedViewController(
        client: NewsAPIClient(session: session(using: type)),
        imageLoader: ImageLoader()
    )
}

private func show(_ feed: NewsFeedViewController) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = feed
    window.makeKeyAndVisible()
    feed.view.layoutIfNeeded()
    return window
}

private func expectTitle(_ feed: NewsFeedViewController) {
    #expect(feed.navigationItem.title == "Новости")
    let title = feed.navigationItem.titleView as? UILabel
    #expect(title?.text == "Новости" || title?.attributedText?.string == "Новости")
    let control = segment(in: feed.view)
    #expect(control?.titleForSegment(at: 0) == "Все")
    #expect(control?.titleForSegment(at: 1) == "Авто")
    #expect(control?.titleForSegment(at: 2) == "Компания")
    #expect(control?.selectedSegmentIndex == 0)
}

private func expectHeader(_ metrics: HeaderMetrics, top: CGFloat) {
    #expect(abs(metrics.topGap - top) <= 1)
    #expect(abs(metrics.leading - 16) <= 1)
    #expect(abs(metrics.trailing - 16) <= 1)
    #expect(abs(metrics.join) <= 1)
}

private func headerMetrics(_ feed: NewsFeedViewController) -> HeaderMetrics {
    feed.view.layoutIfNeeded()
    let segmentFrame = segment(in: feed.view)!.convert(segment(in: feed.view)!.bounds, to: feed.view)
    let collection = collectionView(in: feed.view)!
    let collectionFrame = collection.convert(collection.bounds, to: feed.view)
    let safeTop = feed.view.safeAreaLayoutGuide.layoutFrame.minY
    return HeaderMetrics(
        topGap: segmentFrame.minY - safeTop,
        leading: segmentFrame.minX - feed.view.bounds.minX,
        trailing: feed.view.bounds.maxX - segmentFrame.maxX,
        join: collectionFrame.minY - segmentFrame.maxY
    )
}

private func visibleStrings(in root: UIView) -> [String] {
    var strings: [String] = []
    func walk(_ view: UIView) {
        if view.isHidden || view.alpha < 0.01 { return }
        if let label = view as? UILabel {
            let text = label.text ?? label.attributedText?.string
            if let text, !text.isEmpty { strings.append(text) }
        }
        if let button = view as? UIButton {
            let title = button.configuration?.title ?? button.title(for: .normal)
            if let title, !title.isEmpty { strings.append(title) }
        }
        if let label = view.accessibilityLabel, !label.isEmpty {
            strings.append(label)
        }
        for child in view.subviews {
            walk(child)
        }
    }
    walk(root)
    return strings
}

private func segment(in view: UIView) -> UISegmentedControl? {
    if let control = view as? UISegmentedControl { return control }
    for child in view.subviews {
        if let found = segment(in: child) { return found }
    }
    return nil
}

private func collectionView(in view: UIView) -> UICollectionView? {
    if let collection = view as? UICollectionView { return collection }
    for child in view.subviews {
        if let found = collectionView(in: child) { return found }
    }
    return nil
}
