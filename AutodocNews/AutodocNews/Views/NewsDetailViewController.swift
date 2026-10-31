import Combine
import UIKit
import WebKit

final class NewsDetailViewController: UIViewController {
    private let viewModel: NewsDetailViewModel
    private let imageLoader: ImageLoader
    private var cancellables: Set<AnyCancellable> = []
    private var imageTask: Task<Void, Never>?
    private var contentSizeObservation: NSKeyValueObservation?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let captionLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let descriptionMark = UIView()
    private let descriptionRow = UIStackView()
    private let webView: WKWebView = {
        // Щипок не должен масштабировать статью: она уже внутри общей прокрутки.
        let source = """
        document.addEventListener('gesturestart', function (event) {
          event.preventDefault();
        }, { passive: false });
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(script)
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var webHeight: NSLayoutConstraint!
    private var textLeading: NSLayoutConstraint!
    private var textTrailing: NSLayoutConstraint!
    private var imageLeading: NSLayoutConstraint!
    private var imageTrailing: NSLayoutConstraint!

    init(item: NewsItem, client: NewsAPIClient, imageLoader: ImageLoader) {
        viewModel = NewsDetailViewModel(preview: item, client: client)
        self.imageLoader = imageLoader
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Экран новости создаётся в коде")
    }

    deinit {
        imageTask?.cancel()
        contentSizeObservation?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = GarageTheme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.title = viewModel.preview.title
        configureHierarchy()
        bind()
        showPreview()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: Self, _) in
            guard let text = controller.viewModel.detail?.text else { return }
            controller.renderHTML(text)
        }
        viewModel.load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyReadableAndFoldInsets()
        loadHeroIfNeeded()
    }

    private func configureHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = GarageTheme.background
        scrollView.indicatorStyle = .default
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = GarageTheme.imageWell
        if viewModel.preview.titleImageURL != nil {
            imageView.isUserInteractionEnabled = true
            imageView.isAccessibilityElement = true
            imageView.accessibilityTraits = [.image, .button]
            imageView.accessibilityLabel = "Открыть фото"
            imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openHero)))
        }

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        captionLabel.font = .preferredFont(forTextStyle: .subheadline)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = GarageTheme.accent
        captionLabel.numberOfLines = 0

        // На шаг крупнее тела и плотнее по насыщенности: лид стоит прямо перед фото в тексте.
        let lead = UIFont.systemFont(ofSize: 19, weight: .semibold)
        descriptionLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: lead)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.textColor = .label
        descriptionLabel.numberOfLines = 0

        descriptionMark.translatesAutoresizingMaskIntoConstraints = false
        descriptionMark.backgroundColor = GarageTheme.accent
        descriptionMark.layer.cornerRadius = 1.5
        descriptionMark.isAccessibilityElement = false
        descriptionMark.widthAnchor.constraint(equalToConstant: 3).isActive = true

        descriptionRow.axis = .horizontal
        descriptionRow.alignment = .fill
        descriptionRow.spacing = 10
        descriptionRow.addArrangedSubview(descriptionMark)
        descriptionRow.addArrangedSubview(descriptionLabel)

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(
            WeakScriptHandler(target: self),
            name: Self.imageTapMessage
        )
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        lockArticleZoom()

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true

        retryButton.tintColor = GarageTheme.accent
        retryButton.setTitle("Повторить", for: .normal)
        retryButton.isHidden = true
        retryButton.addAction(UIAction { [weak self] _ in
            self?.viewModel.load()
        }, for: .touchUpInside)

        let textColumn = UIStackView(arrangedSubviews: [
            titleLabel, captionLabel, descriptionRow, webView, statusLabel, retryButton
        ])
        textColumn.axis = .vertical
        textColumn.spacing = 12
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        textColumn.setCustomSpacing(20, after: descriptionRow)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        scrollView.addSubview(textColumn)

        webHeight = webView.heightAnchor.constraint(equalToConstant: 44)
        let aspect = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 9.0 / 16.0)
        aspect.priority = .required - 1
        textLeading = textColumn.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor)
        textTrailing = textColumn.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor)
        imageLeading = imageView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor)
        imageTrailing = imageView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor)
        imageLeading.isActive = true
        imageTrailing.isActive = true

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            aspect,

            textLeading,
            textTrailing,
            textColumn.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            textColumn.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            webHeight
        ])

        contentSizeObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.setWebHeight(self.webView.scrollView.contentSize.height)
            }
        }
    }

    private func bind() {
        viewModel.$phase
            .combineLatest(viewModel.$detail)
            .sink { [weak self] phase, detail in
                // @Published шлёт значение в willSet, само свойство ещё старое.
                self?.render(phase: phase, detail: detail)
            }
            .store(in: &cancellables)
    }

    private func showPreview() {
        let item = viewModel.preview
        titleLabel.text = item.title
        captionLabel.text = NewsDateFormatting.caption(category: item.categoryType, date: item.publishedDate)
        applyDescription(item.description)
        imageView.isHidden = false
        if item.titleImageURL == nil {
            imageView.image = GarageTheme.newsPlaceholder
        }
    }

    private func render(phase: DetailPhase, detail: NewsDetail?) {
        switch phase {
        case .idle, .loading:
            statusLabel.isHidden = false
            statusLabel.text = "Загрузка"
            retryButton.isHidden = true
        case .failed(let message):
            statusLabel.isHidden = false
            statusLabel.text = message
            retryButton.isHidden = false
        case .loaded:
            statusLabel.isHidden = true
            retryButton.isHidden = true
            if let detail {
                titleLabel.text = detail.item.title
                navigationItem.title = detail.item.title
                applyDescription(detail.item.description)
                renderHTML(detail.text)
            }
        }
    }

    private func applyDescription(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionLabel.text = trimmed
        descriptionRow.isHidden = trimmed.isEmpty
    }

    private func renderHTML(_ html: String) {
        guard !html.isEmpty else {
            webView.isHidden = true
            return
        }
        webView.isHidden = false
        statusLabel.isHidden = true
        let dark = traitCollection.userInterfaceStyle == .dark
        let scheme = dark ? "dark" : "light"
        let link = GarageTheme.accentCSS(matching: traitCollection)
        let document = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta name="color-scheme" content="\(scheme)">
        <style>
          :root { color-scheme: \(scheme); }
          html, body { margin: 0; padding: 0; background: transparent; color: CanvasText; }
          body { font: -apple-system-body; font-family: -apple-system, system-ui, sans-serif; }
          img, video { max-width: 100%; height: auto; }
          a { color: \(link); }
        </style>
        </head>
        <body>\(html)
        <script>
          document.addEventListener('click', function (event) {
            var img = event.target.closest('img');
            if (!img) { return; }
            event.preventDefault();
            window.webkit.messageHandlers.\(Self.imageTapMessage).postMessage(img.currentSrc || img.src);
          }, true);
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(document, baseURL: URL(string: "https://www.autodoc.ru"))
    }

    private func lockArticleZoom() {
        let article = webView.scrollView
        if article.zoomScale != 1 {
            article.setZoomScale(1, animated: false)
        }
        article.minimumZoomScale = 1
        article.maximumZoomScale = 1
        article.bouncesZoom = false
        disableMagnification(on: article)
    }

    private func disableMagnification(on view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] {
            if recognizer is UIPinchGestureRecognizer {
                recognizer.isEnabled = false
            } else if let tap = recognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 {
                tap.isEnabled = false
            }
        }
        for subview in view.subviews {
            disableMagnification(on: subview)
        }
    }

    private func setWebHeight(_ height: CGFloat) {
        let next = max(height, 1)
        guard abs(webHeight.constant - next) > 1 else { return }
        webHeight.constant = next
    }

    private func applyReadableAndFoldInsets() {
        let readable = view.readableContentGuide.layoutFrame
        let bounds = view.bounds
        var leading = max(readable.minX - bounds.minX, 16)
        var trailing = max(bounds.maxX - readable.maxX, 16)
        var imageInset = UIEdgeInsets.zero
        if let fold = DuoLayout.activeDivisionFrame(in: scrollView) {
            let hinge = DuoLayout.hingeContentInsets(fold: fold, bounds: scrollView.bounds)
            leading = max(leading, hinge.left)
            trailing = max(trailing, hinge.right)
            imageInset = hinge
        }
        textLeading.constant = leading
        textTrailing.constant = -trailing
        // Вторичный экран на iPad шире видимой колонки: список лежит поверх него.
        // Та же safe area уводит героя со сгиба Duo.
        let obscuredLeading = max(imageInset.left, scrollView.safeAreaInsets.left)
        let obscuredTrailing = max(imageInset.right, scrollView.safeAreaInsets.right)
        imageLeading.constant = obscuredLeading
        imageTrailing.constant = -obscuredTrailing
    }

    private func loadHeroIfNeeded() {
        guard let url = viewModel.preview.titleImageURL else { return }
        let width = imageView.bounds.width
        guard width > 1, imageTask == nil, imageView.image == nil else { return }
        let scale = traitCollection.displayScale
        imageTask = Task { [weak self] in
            let image = await self?.imageLoader.image(
                for: url,
                pointSize: CGSize(width: width, height: width * 9 / 16),
                scale: scale
            )
            guard !Task.isCancelled else { return }
            self?.imageView.image = image ?? GarageTheme.newsPlaceholder
        }
    }

    @objc private func openHero() {
        guard let url = viewModel.preview.titleImageURL else { return }
        let viewer = ImageViewerViewController(url: url, preview: imageView.image, imageLoader: imageLoader)
        let options = UIViewController.Transition.ZoomOptions()
        options.interactiveDismissShouldBegin = { [weak viewer] _ in
            !(viewer?.isZoomedIn ?? false)
        }
        viewer.preferredTransition = .zoom(options: options) { [weak self] _ in
            self?.imageView
        }
        present(viewer, animated: true)
    }

    fileprivate func openInlineImage(_ source: String) {
        guard let url = URL(string: source), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }
        present(ImageViewerViewController(url: url, preview: nil, imageLoader: imageLoader), animated: true)
    }

    fileprivate static let imageTapMessage = "imageTap"
}

/// WKUserContentController держит обработчик сильно, поэтому экран статьи нельзя отдавать ему напрямую.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: NewsDetailViewController?

    init(target: NewsDetailViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let source = message.body as? String else { return }
        target?.openInlineImage(source)
    }
}

extension NewsDetailViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // Ссылка не должна подменять текст статьи внутри страницы.
        if navigationAction.navigationType == .linkActivated {
            openInBrowser(navigationAction.request.url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        openInBrowser(navigationAction.request.url)
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lockArticleZoom()
        Task { @MainActor in
            // При выключенной прокрутке contentSize не растёт. Высоту берём из документа.
            let raw = try? await webView.evaluateJavaScript("document.documentElement.scrollHeight")
            let height = (raw as? NSNumber).map { CGFloat(truncating: $0) } ?? (raw as? Double).map { CGFloat($0) }
            setWebHeight(height ?? webView.scrollView.contentSize.height)
        }
    }

    private func openInBrowser(_ url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return
        }
        UIApplication.shared.open(url)
    }
}
