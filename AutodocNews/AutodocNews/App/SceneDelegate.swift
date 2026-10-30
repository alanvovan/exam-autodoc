import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        GarageTheme.apply(to: window)
        window.rootViewController = NewsSplitViewController()
        window.makeKeyAndVisible()
        self.window = window
        // Только холодный старт сцены. Выход из фона сюда не приходит.
        MetalIntroView.presentIfNeeded(on: window)
    }
}
