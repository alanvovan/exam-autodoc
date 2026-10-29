import UIKit

enum GarageTheme {
    /// Холодный почти чёрный металл, #0E1216. Последний кадр заставки совпадает с ним.
    static let background = UIColor(red: 14.0 / 255, green: 18.0 / 255, blue: 22.0 / 255, alpha: 1)

    /// Тёплая латунь для меток и кнопок, #D2B07A.
    static let brass = UIColor(red: 210.0 / 255, green: 176.0 / 255, blue: 122.0 / 255, alpha: 1)

    static let brassHTML = "#D2B07A"

    /// Тонкая светлая обводка стеклянной карточки.
    static let stroke = UIColor(white: 1, alpha: 0.22)

    static let imageWell = UIColor(white: 1, alpha: 0.08)

    static let cardCornerRadius: CGFloat = 16

    static let cardBlurStyle = UIBlurEffect.Style.systemThinMaterialDark

    static func apply(to window: UIWindow) {
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = background
        window.tintColor = brass
        apply(to: UINavigationBar.appearance())
    }

    static func apply(to navigationController: UINavigationController) {
        apply(to: navigationController.navigationBar)
        navigationController.view.backgroundColor = background
    }

    static func apply(to bar: UINavigationBar) {
        let expanded = navigationBarAppearance(frosted: false)
        let collapsed = navigationBarAppearance(frosted: true)
        bar.standardAppearance = collapsed
        bar.compactAppearance = collapsed
        bar.scrollEdgeAppearance = expanded
        bar.compactScrollEdgeAppearance = expanded
        bar.tintColor = brass
        bar.isTranslucent = true
        bar.overrideUserInterfaceStyle = .dark
    }

    private static func navigationBarAppearance(frosted: Bool) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        if frosted {
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        }
        let title: UIColor = .label
        appearance.titleTextAttributes = [.foregroundColor: title]
        appearance.largeTitleTextAttributes = [.foregroundColor: title]
        return appearance
    }
}
