import UIKit

final class NewsPlaceholderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = GarageTheme.background
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "newspaper")
        configuration.text = "Новости"
        configuration.secondaryText = "Выберите новость"
        configuration.imageProperties.tintColor = GarageTheme.accent
        configuration.textProperties.color = .label
        configuration.secondaryTextProperties.color = GarageTheme.accent
        let placeholder = UIContentUnavailableView(configuration: configuration)
        placeholder.backgroundColor = .clear
        placeholder.tintColor = GarageTheme.accent
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholder.topAnchor.constraint(equalTo: view.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
