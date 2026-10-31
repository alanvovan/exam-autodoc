import UIKit

enum GarageTheme {
    /// Холодный металл заставки, #0E1216. Не зависит от темы.
    static let metal = UIColor(red: 14.0 / 255, green: 18.0 / 255, blue: 22.0 / 255, alpha: 1)

    /// Красный логотипа autodoc.ru, #FE0000.
    static let brandRed = UIColor(red: 254.0 / 255, green: 0, blue: 0, alpha: 1)

    /// Текст и иконки. Чистый #FE0000 на белом даёт 4.0:1 — мало для мелкого текста.
    /// На светлом фоне #E20000 (4.5:1 на #F4F4F6). На #0E1216 сам бренд даёт 4.7:1.
    static let accent = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return brandRed
        }
        return UIColor(red: 226.0 / 255, green: 0, blue: 0, alpha: 1)
    }

    static let background = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return metal
        }
        return UIColor(red: 244.0 / 255, green: 244.0 / 255, blue: 246.0 / 255, alpha: 1)
    }

    static let stroke = UIColor { traits in
        let strong = traits.accessibilityContrast == .high
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: strong ? 0.45 : 0.22)
        }
        return UIColor(white: 0, alpha: strong ? 0.28 : 0.12)
    }

    static let imageWell = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: 0.08)
        }
        return UIColor(white: 0, alpha: 0.05)
    }

    /// Логотип на тёмном поле, если у новости нет обложки.
    static let newsPlaceholder = UIImage(named: "NewsPlaceholder")

    static let cardCornerRadius: CGFloat = 16

    static let cardBlurStyle = UIBlurEffect.Style.systemThinMaterial

    static func accentCSS(matching traits: UITraitCollection) -> String {
        let color = accent.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#E20000"
        }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    static func apply(to window: UIWindow) {
        window.backgroundColor = background
        window.tintColor = accent
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
        bar.tintColor = accent
        bar.isTranslucent = true
    }

    private static func navigationBarAppearance(frosted: Bool) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        if frosted {
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        let title: UIColor = .label
        appearance.titleTextAttributes = [.foregroundColor: title]
        appearance.largeTitleTextAttributes = [.foregroundColor: title]
        return appearance
    }
}
