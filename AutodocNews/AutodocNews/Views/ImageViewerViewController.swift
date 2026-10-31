import UIKit

final class ImageViewerViewController: UIViewController {
    private let url: URL
    private let preview: UIImage?
    private let imageLoader: ImageLoader
    private var loadTask: Task<Void, Never>?

    let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    var isZoomedIn: Bool {
        scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    init(url: URL, preview: UIImage?, imageLoader: ImageLoader) {
        self.url = url
        self.preview = preview
        self.imageLoader = imageLoader
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("Просмотр фото создаётся в коде")
    }

    deinit {
        loadTask?.cancel()
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        configureHierarchy()
        setImage(preview)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isZoomedIn {
            layoutImage()
        }
        loadFullImageIfNeeded()
    }

    private func configureHierarchy() {
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityLabel = "Фото из новости"
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // У зум-перехода свой интерактивный свайп вниз.
        if preferredTransition == nil {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipeDown))
            swipe.direction = .down
            swipe.delegate = self
            scrollView.addGestureRecognizer(swipe)
        }

        var close = UIButton.Configuration.glass()
        close.image = UIImage(systemName: "xmark")
        close.cornerStyle = .capsule
        closeButton.configuration = close
        closeButton.accessibilityLabel = "Закрыть"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        view.addSubview(closeButton)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadFullImageIfNeeded() {
        let size = view.bounds.size
        guard size.width > 1, loadTask == nil else { return }
        if preview == nil {
            spinner.startAnimating()
        }
        // Запас под зум: при 1× фото занимает экран, детали видны до ~2×.
        let scale = traitCollection.displayScale * 2
        loadTask = Task { [weak self, url, imageLoader] in
            let image = await imageLoader.image(for: url, pointSize: size, scale: scale)
            guard !Task.isCancelled, let self else { return }
            spinner.stopAnimating()
            if let image {
                setImage(image)
            } else if preview == nil {
                statusLabel.text = "Не удалось загрузить фото"
                statusLabel.isHidden = false
            }
        }
    }

    private func setImage(_ image: UIImage?) {
        imageView.image = image
        guard image != nil else { return }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        layoutImage()
    }

    private func layoutImage() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }
        let bounds = scrollView.bounds.size
        let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let fitted = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        centerImage()
    }

    private func centerImage() {
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        scrollView.contentInset = UIEdgeInsets(
            top: max((bounds.height - content.height) / 2, 0),
            left: max((bounds.width - content.width) / 2, 0),
            bottom: 0,
            right: 0
        )
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if isZoomedIn {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let scale = min(scrollView.maximumZoomScale, 2.5)
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        let target = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        scrollView.zoom(to: target, animated: true)
    }

    @objc private func swipeDown() {
        dismiss(animated: true)
    }
}

extension ImageViewerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UISwipeGestureRecognizer else { return true }
        return !isZoomedIn
    }
}

extension ImageViewerViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}
