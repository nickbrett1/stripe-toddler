import SwiftUI
import UIKit

// MARK: - Keyboard Wedge Barcode Interceptor View
struct BarcodeInterceptorRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> BarcodeInterceptorUIView {
        let view = BarcodeInterceptorUIView()
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: BarcodeInterceptorUIView, context: Context) {}

    final class BarcodeInterceptorUIView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        override var canBecomeFirstResponder: Bool { true }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                BarcodeScannerService.shared.handlePress(press)
            }
            super.pressesBegan(presses, with: event)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            becomeFirstResponder()
        }
    }
}

// MARK: - App Entry Point
@main
struct StripeToddlerPOSApp: App {
    @StateObject private var viewModel: POSViewModel

    init() {
        let backendURL = URL(string: "https://stripe-toddler.nick-brett1.workers.dev")!
        let api = BackendAPIClient(baseURL: backendURL)
        let terminal = StripeTerminalManager(apiClient: api)
        _viewModel = StateObject(wrappedValue: POSViewModel(apiClient: api, terminalManager: terminal))
    }

    var body: some Scene {
        WindowGroup {
            CheckoutView(viewModel: viewModel)
                .overlay(BarcodeInterceptorRepresentable().frame(width: 0, height: 0).allowsHitTesting(false))
        }
    }
}
