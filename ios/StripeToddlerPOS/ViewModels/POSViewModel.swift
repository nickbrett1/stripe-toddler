import Foundation
import Combine

// MARK: - Payment Simulation Outcome
public enum PaymentSimulationOutcome: String, CaseIterable, Identifiable {
    case approved = "Approved"
    case declined = "Declined"
    case networkError = "Network Error"
    case none = "None"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .approved: return "Simulate: Approved ✓"
        case .declined: return "Simulate: Declined ✗"
        case .networkError: return "Simulate: Network Error ⚡"
        case .none: return "Simulate: None (Stay on Tap Modal)"
        }
    }
}

// MARK: - POS Flow State
public enum POSFlowState: Equatable {
    case waitingForScan
    case cartActive(items: [POSInventoryItem], totalCents: Int)
    case readerSyncing
    case awaitingCardTap
    case processingPayment
    case celebrating(itemsSold: [POSInventoryItem])
    case error(message: String)
    /// A barcode was scanned but isn't in inventory. This is an expected,
    /// recoverable moment (e.g. a random barcode), NOT a system error.
    case itemNotFound(barcode: String)
}

// MARK: - POS View Model Implementation
@MainActor
public final class POSViewModel: ObservableObject, BarcodeScannerDelegate, StripeTerminalManagerDelegate {
    @Published public private(set) var state: POSFlowState = .waitingForScan
    @Published public var scannerConnected: Bool = true
    @Published public private(set) var readerConnected: Bool = false
    @Published public var isTestModeEnabled: Bool = false
    @Published public var showQuickAddButtons: Bool = true
    @Published public var simulatedPaymentOutcome: PaymentSimulationOutcome = .approved
    /// Progress (0.0–1.0) while the reader installs a required software update.
    @Published public var readerUpdateProgress: Float?
    
    private let apiClient: BackendAPIClientProtocol
    private let terminalManager: StripeTerminalManagerProtocol
    private let scannerService: BarcodeScannerServiceProtocol
    
    // Cache the cart items and total to finalize the transaction after terminal authorization
    private var cachedCartItems: [POSInventoryItem] = []
    private var cachedCartTotal: Int = 0
    /// Watchdog that converts a stuck payment phase into a clear error instead
    /// of leaving the app hanging with frozen UI.
    private var checkoutWatchdogTask: Task<Void, Never>?
    
    public init(
        apiClient: BackendAPIClientProtocol,
        terminalManager: StripeTerminalManagerProtocol,
        scannerService: BarcodeScannerServiceProtocol = BarcodeScannerService.shared
    ) {
        self.apiClient = apiClient
        self.terminalManager = terminalManager
        self.scannerService = scannerService
        
        // Setup delegates
        self.scannerService.delegate = self
        self.terminalManager.delegate = self
        
        // Start barcode listening
        self.scannerService.startListening()
        
        // Auto connect to Stripe Terminal reader
        self.terminalManager.connectToReader()
    }
    
    // MARK: - POS Operations
    public func handleBarcodeScanned(_ barcode: String) {
        // Trigger haptic feedback for physical feedback loop (Rule 8)
        ToddlerHaptic.play(ToddlerHapticStyle.rigid)
        
        Task {
            do {
                let newItem = try await apiClient.fetchItem(barcode: barcode)
                
                // Add scanned item to active cart
                cachedCartItems.append(newItem)
                cachedCartTotal += newItem.priceCents
                
                // Cheerful confirmation chime when an item lands in the cart
                ToddlerSound.playScan()
                
                state = .cartActive(items: cachedCartItems, totalCents: cachedCartTotal)
            } catch {
                if isItemNotFoundError(error) {
                    // A random/unrecognized barcode was scanned — expected and recoverable,
                    // so show the friendly "not in our shop" state instead of a scary error.
                    state = .itemNotFound(barcode: barcode)
                    ToddlerHaptic.playNotification(ToddlerHapticType.warning)
                } else {
                    state = .error(message: "Couldn't look up item: \(barcode)")
                    ToddlerHaptic.playNotification(ToddlerHapticType.error)
                }
            }
        }
    }
    
    // MARK: - Error Classification
    /// Returns true when the failure simply means "this barcode isn't in inventory"
    /// (e.g. a random barcode was scanned), as opposed to a real system error.
    private func isItemNotFoundError(_ error: Error) -> Bool {
        if case BackendAPIError.badResponse(let statusCode) = error {
            return statusCode == 404
        }
        return false
    }

    public func removeItem(at index: Int) {
        guard index >= 0 && index < cachedCartItems.count else { return }
        
        // Trigger soft haptic feedback on removal (Rule 8)
        ToddlerHaptic.play(ToddlerHapticStyle.soft)
        
        let removedItem = cachedCartItems.remove(at: index)
        cachedCartTotal -= removedItem.priceCents
        
        if cachedCartItems.isEmpty {
            state = .waitingForScan
        } else {
            state = .cartActive(items: cachedCartItems, totalCents: cachedCartTotal)
        }
    }
    
    public func startCheckout() {
        guard case .cartActive(let items, let totalCents) = state else { return }
        
        // Trigger heavy haptic on checkout start (Rule 8)
        ToddlerHaptic.play(ToddlerHapticStyle.heavy)

        if isTestModeEnabled {
            // Test mode is a pure offline simulation: no Stripe/worker calls.
            // A simulated sale is intentionally NOT persisted to the database
            // (no card was ever collected or captured), so it must not be
            // masqueraded as a real transaction.
            state = .awaitingCardTap

            Task {
                // Show "Tap Card on Reader!" modal realistically for 1.2s before
                // auto-processing the simulation outcome.
                try? await Task.sleep(nanoseconds: 1_200_000_000)

                switch simulatedPaymentOutcome {
                case .approved:
                    completeTestModeSale()
                case .declined:
                    state = .error(message: "Card Declined. Please Try Again.")
                    ToddlerHaptic.playNotification(ToddlerHapticType.error)
                case .networkError:
                    state = .error(message: "Network Connection Lost")
                    ToddlerHaptic.playNotification(ToddlerHapticType.error)
                case .none:
                    // Remain on .awaitingCardTap screen so user can easily preview the modal
                    break
                }
            }
            return
        }

        state = .readerSyncing
        startReaderSyncWatchdog()
        
        Task {
            do {
                let barcodes = items.map { $0.barcode }
                let response = try await apiClient.createPaymentIntent(amountCents: totalCents, barcodes: barcodes)

                // Real reader: stay on .readerSyncing until the terminal
                // manager confirms the SDK is actively collecting (see
                // terminalManagerDidBeginCollectingPayment), so "Tap Card on
                // Reader" never appears before the reader is actually ready.
                terminalManager.collectPayment(amount: totalCents, clientSecret: response.clientSecret)
            } catch {
                // This failure is about syncing the checkout with the backend
                // (creating the PaymentIntent), NOT the reader — so surface the
                // real cause instead of blaming the reader.
                cancelCheckoutWatchdog()
                state = .error(message: "Checkout failed: \(error.localizedDescription)")
                ToddlerHaptic.playNotification(ToddlerHapticType.error)
            }
        }
    }

    /// Simulated sale success for test mode: celebrates like a real payment
    /// (haptic + sound) but never touches Stripe or the database.
    private func completeTestModeSale() {
        cancelCheckoutWatchdog()
        state = .celebrating(itemsSold: cachedCartItems)
        ToddlerHaptic.playNotification(ToddlerHapticType.success)
        ToddlerSound.playSuccess()
    }
    
    public func resetPOS() {
        cancelCheckoutWatchdog()
        cachedCartItems.removeAll()
        cachedCartTotal = 0
        readerUpdateProgress = nil
        state = .waitingForScan
        ToddlerHaptic.play(ToddlerHapticStyle.medium)
    }
    
    /// Cancel an in-progress checkout (reader sync / card tap) and return to the
    /// basket with items intact — NOT the landing page. Aborts any in-flight
    /// terminal work so the payment can't complete afterwards.
    public func cancelCheckout() {
        cancelCheckoutWatchdog()
        readerUpdateProgress = nil
        switch state {
        case .readerSyncing, .awaitingCardTap, .processingPayment:
            // Update the UI FIRST so Cancel responds instantly; then abort the
            // terminal work in the background. A slow SDK cancel must never
            // make the screen feel frozen.
            if cachedCartItems.isEmpty {
                state = .waitingForScan
            } else {
                state = .cartActive(items: cachedCartItems, totalCents: cachedCartTotal)
            }
            terminalManager.cancelPayment()
        default:
            break
        }
    }
    
    /// If the checkout sits on "Syncing Reader..." too long — the reader never
    /// becomes ready, or an SDK payment call (retrieve/collect/confirm) stalls
    /// without calling back — surface an error instead of hanging forever.
    /// Also aborts any in-flight terminal work so a late SDK completion can't
    /// complete the sale after the error screen appears.
    private func startReaderSyncWatchdog() {
        checkoutWatchdogTask?.cancel()
        checkoutWatchdogTask = Task { [weak self] in
            // 150s: comfortably covers the SDK's own timeouts (20s discovery,
            // 45s connect) plus its documented up-to-2-minute wait for the
            // location permission prompt on first launch, so the watchdog only
            // fires when something is genuinely stuck.
            try? await Task.sleep(nanoseconds: 150_000_000_000) // 150 seconds
            guard let self = self, !Task.isCancelled else { return }
            guard case .readerSyncing = self.state else { return }
            self.checkoutWatchdogTask = nil
            self.state = .error(message: "Couldn't sync the card reader. Make sure the Reader M2 is powered on and close to the iPad, then try again.")
            ToddlerHaptic.playNotification(ToddlerHapticType.error)
            // Abort in-flight terminal work so a late completion can't complete
            // the sale behind the error screen (same mechanism as cancelCheckout).
            self.terminalManager.cancelPayment()
        }
    }
    
    /// If the reader is waiting for a card but no tap registers, surface a
    /// friendly error instead of hanging on the tap prompt forever.
    private func startCardTapWatchdog() {
        checkoutWatchdogTask?.cancel()
        checkoutWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes
            guard let self = self, !Task.isCancelled else { return }
            guard case .awaitingCardTap = self.state else { return }
            self.checkoutWatchdogTask = nil
            self.state = .error(message: "Card wasn't detected on the reader. Tap a contactless card (or Apple Pay), then try again.")
            ToddlerHaptic.playNotification(ToddlerHapticType.error)
        }
    }
    
    /// If the backend capture (or Stripe confirm) stalls, surface an error
    /// instead of sitting on "Paying..." forever.
    private func startCaptureWatchdog() {
        checkoutWatchdogTask?.cancel()
        checkoutWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000) // 45 seconds
            guard let self = self, !Task.isCancelled else { return }
            guard case .processingPayment = self.state else { return }
            self.checkoutWatchdogTask = nil
            self.state = .error(message: "Payment is taking too long. Check the connection and try again.")
            ToddlerHaptic.playNotification(ToddlerHapticType.error)
        }
    }
    
    private func cancelCheckoutWatchdog() {
        checkoutWatchdogTask?.cancel()
        checkoutWatchdogTask = nil
    }


    
    /// Dismiss the current error overlay and return to the cart (if items are
    /// still cached) instead of wiping the session and bouncing back to the
    /// landing screen. E.g. a reader sync failure at checkout should drop the
    /// shopper back into their basket, not erase it.
    public func dismissError() {
        cancelCheckoutWatchdog()
        if cachedCartItems.isEmpty {
            state = .waitingForScan
        } else {
            state = .cartActive(items: cachedCartItems, totalCents: cachedCartTotal)
        }
    }
    
    // MARK: - BarcodeScannerDelegate
    public func didScanBarcode(_ barcode: ScannedBarcode) {
        handleBarcodeScanned(barcode.value)
    }
    
    public func didEncounterScannerError(_ error: Error) {
        state = .error(message: "Scanner Error: \(error.localizedDescription)")
        ToddlerHaptic.playNotification(ToddlerHapticType.error)
    }
    
    // MARK: - StripeTerminalManagerDelegate
    public func terminalManager(_ manager: StripeTerminalManagerProtocol, didChangeState state: ReaderConnectionState) {
        switch state {
        case .connected:
            readerConnected = true
        default:
            readerConnected = false
        }
    }
    
    public func terminalManager(_ manager: StripeTerminalManagerProtocol, didEncounterError error: Error) {
        // Log the raw SDK error so the real cause is visible in the Xcode console
        // even when the friendly error screen condenses it.
        print("[POS] Terminal error: \(error.localizedDescription)")
        state = .error(message: "Terminal Error: \(error.localizedDescription)")
        ToddlerHaptic.playNotification(ToddlerHapticType.error)
    }
    
    public func terminalManagerDidCompletePayment(_ manager: StripeTerminalManagerProtocol, paymentIntentId: String) {
        cancelCheckoutWatchdog()
        state = .processingPayment
        startCaptureWatchdog()
        
        Task {
            do {
                _ = try await apiClient.captureTransaction(
                    paymentIntentId: paymentIntentId,
                    totalCents: cachedCartTotal,
                    items: cachedCartItems
                )
                
                // Show celebration overlay! (Rule 4.3)
                cancelCheckoutWatchdog()
                state = .celebrating(itemsSold: cachedCartItems)
                ToddlerHaptic.playNotification(ToddlerHapticType.success)
                // Victory arpeggio to celebrate the successful payment
                ToddlerSound.playSuccess()
            } catch {
                cancelCheckoutWatchdog()
                state = .error(message: "Capture failed: \(error.localizedDescription)")
                ToddlerHaptic.playNotification(ToddlerHapticType.error)
            }
        }
    }
    
    /// The reader is connected and the SDK is actively collecting a card —
    /// only now show the "Tap Card on Reader" prompt (previously it appeared
    /// before the reader was ready, so early taps did nothing).
    public func terminalManagerDidBeginCollectingPayment(_ manager: StripeTerminalManagerProtocol) {
        readerUpdateProgress = nil
        guard case .readerSyncing = state else { return }
        state = .awaitingCardTap
        startCardTapWatchdog()
    }
    
    /// Required reader software updates install during connect; surface the
    /// progress so the screen says "Updating Reader…" instead of looking stuck.
    public func terminalManager(_ manager: StripeTerminalManagerProtocol, didReportReaderUpdateProgress progress: Float) {
        readerUpdateProgress = progress
    }
}
