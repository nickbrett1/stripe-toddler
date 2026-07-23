import SwiftUI
import UIKit

// MARK: - Barcode Interceptor UIWindow (Rule 10 Keyboard Wedge Interceptor)
final class BarcodeInterceptorWindow: UIWindow {
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            BarcodeScannerService.shared.handlePress(press)
        }
        super.pressesBegan(presses, with: event)
    }
}

// MARK: - Scene Delegate for Custom Window Setup
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        // Instantiate the window with global keyboard presses interceptor
        let interceptorWindow = BarcodeInterceptorWindow(windowScene: windowScene)
        
        // Configure endpoint matching the live workers route (Phase 4 Step 4.2)
        let backendURL = URL(string: "https://stripe-toddler.fintechnick.workers.dev")!
        let api = BackendAPIClient(baseURL: backendURL)
        let terminal = StripeTerminalManager(apiClient: api)
        let viewModel = POSViewModel(apiClient: api, terminalManager: terminal)
        
        // Inject dependencies into root view
        let rootViewController = UIHostingController(
            rootView: CheckoutView(viewModel: viewModel)
        )
        
        interceptorWindow.rootViewController = rootViewController
        self.window = interceptorWindow
        interceptorWindow.makeKeyAndVisible()
    }
}

// MARK: - Application Delegate
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

// MARK: - App Entry Point
@main
struct StripeToddlerPOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            Color.clear
        }
    }
}
