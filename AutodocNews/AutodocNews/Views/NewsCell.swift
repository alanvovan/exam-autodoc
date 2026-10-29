import UIKit

final class NewsCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let captionLabel = UILabel()
    private var imageTask: Task<Void, Never>?
    private var itemID: Int?
    private var imageURL: URL?
    private var requestedURL: URL?
    private var requestedWidth: CGFloat = 0
    private var loader: ImageLoader?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("Ячейка создаётся в коде")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        itemID = nil
        imageURL = nil
        requestedURL = nil
        requestedWidth = 0
        imageView.image = nil
        titleLabel.text = nil
        captionLabel.text = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        loadImageIfNeeded()
    }

    func configure(item: NewsItem, loader: ImageLoader) {
        itemID = item.id
        imageURL = item.titleImageURL
        self.loader = loader
        titleLabel.text = item.title
        captionLabel.text = NewsDateFormatting.caption(category: item.categoryType, date: item.publishedDate)
        accessibilityLabel = "\(item.title), \(captionLabel.text ?? "")"
        if imageURL == nil {
            imageView.image = nil
        }
        loadImageIfNeeded()
    }

    private func loadImageIfNeeded() {
        guard let url = imageURL, let loader else { return }
        let width = imageView.bounds.width > 1 ? imageView.bounds.width : contentView.bounds.width
        guard width > 1 else { return }
        // layoutSubviews приходит пачками. Повторный старт отменяет ещё не скачанную картинку.
        let sameRequest = requestedURL == url && abs(width - requestedWidth) <= 8
        if sameRequest, imageView.image != nil || imageTask != nil {
            return
        }
        requestedURL = url
        requestedWidth = width
        let pointSize = CGSize(width: width, height: width * 9 / 16)
        let scale = max(traitCollection.displayScale, 1)
        let token = itemID
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let image = await loader.image(for: url, pointSize: pointSize, scale: scale)
            guard !Task.isCancelled, let self, self.itemID == token else { return }
            self.imageTask = nil
            self.imageView.image = image
        }
    }

    private func configureHierarchy() {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = .secondarySystemGroupedBackground
        background.cornerRadius = 12
        backgroundConfiguration = background

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemFill
        imageView.layer.cornerCurve = .continuous

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        captionLabel.font = .preferredFont(forTextStyle: .caption1)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = .secondaryLabel
        captionLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, captionLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        let column = UIStackView(arrangedSubviews: [imageView, textStack])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)

        let aspect = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 9.0 / 16.0)
        aspect.priority = .required - 1

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            column.topAnchor.constraint(equalTo: contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            aspect
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }
}
