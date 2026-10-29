import UIKit

final class NewsFooterView: UICollectionReusableView {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.hidesWhenStopped = true
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [spinner, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Футер создаётся в коде")
    }

    func configure(isLoading: Bool, message: String?, onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        if isLoading {
            spinner.startAnimating()
            retryButton.isHidden = true
        } else {
            spinner.stopAnimating()
            retryButton.isHidden = message == nil
            retryButton.setTitle(message.map { "\($0) Повторить" }, for: .normal)
        }
    }
}
