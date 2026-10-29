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
    private let cardView = UIView()
    private let glassView = UIVisualEffectView(effect: UIBlurEffect(style: GarageTheme.cardBlurStyle))
    private let strokeView = UIView()

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

    override var isHighlighted: Bool {
        didSet { updateStroke() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateStroke()
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
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        backgroundConfiguration = .clear()

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.clipsToBounds = true
        cardView.backgroundColor = .clear
        cardView.layer.cornerCurve = .continuous
        cardView.layer.cornerRadius = GarageTheme.cardCornerRadius

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isUserInteractionEnabled = false

        strokeView.translatesAutoresizingMaskIntoConstraints = false
        strokeView.isUserInteractionEnabled = false
        strokeView.backgroundColor = .clear
        strokeView.layer.cornerCurve = .continuous
        strokeView.layer.cornerRadius = GarageTheme.cardCornerRadius
        strokeView.layer.borderColor = GarageTheme.stroke.cgColor

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = GarageTheme.imageWell

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        captionLabel.font = .preferredFont(forTextStyle: .caption1)
        captionLabel.adjustsFontForContentSizeCategory = true
        captionLabel.textColor = GarageTheme.brass
        captionLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, captionLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        let column = UIStackView(arrangedSubviews: [imageView, textStack])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(glassView)
        cardView.addSubview(column)
        contentView.addSubview(cardView)
        contentView.addSubview(strokeView)

        let aspect = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 9.0 / 16.0)
        aspect.priority = .required - 1

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            glassView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: cardView.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            column.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            column.topAnchor.constraint(equalTo: cardView.topAnchor),
            column.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            strokeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            strokeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            strokeView.topAnchor.constraint(equalTo: contentView.topAnchor),
            strokeView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            aspect
        ])

        let selection = UIView()
        selection.backgroundColor = .clear
        selectedBackgroundView = selection

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private func updateStroke() {
        let scale = max(traitCollection.displayScale, 1)
        strokeView.layer.borderWidth = 1 / scale
        strokeView.layer.borderColor = isHighlighted ? GarageTheme.brass.cgColor : GarageTheme.stroke.cgColor
    }
}
