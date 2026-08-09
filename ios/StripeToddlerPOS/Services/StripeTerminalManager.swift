import Foundation
import StripeTerminal

// MARK: - Reader Connection State
public enum ReaderConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected(readerName: String, batteryLevel: Float)
}

// MARK: - Stripe Terminal Manager Protocols
public protocol StripeTerminalManagerDelegate: AnyObject {
    func terminalManager(_ manager: StripeTerminalManagerProtocol, didChangeState state: ReaderConnectionState)
    func terminalManager(_ manager: StripeTerminalManagerProtocol, didEncounterError error: Error)
    func terminalManagerDidCompletePayment(_ manager: StripeTerminalManagerProtocol, paymentIntentId: String)
    /// Fired when the SDK has connected to the reader, retrieved the payment
    /// intent, and is actively collecting a card — the moment the UI should
    /// prompt the shopper to tap.
    func terminalManagerDidBeginCollectingPayment(_ manager: StripeTerminalManagerProtocol)
    /// Fired while a required reader software update is installing (during
    /// connect). Lets the UI show progress instead of a stuck-looking spinner.
    func terminalManager(_ manager: StripeTerminalManagerProtocol, didReportReaderUpdateProgress progress: Float)
}

public protocol StripeTerminalManagerProtocol: AnyObject {
    var delegate: StripeTerminalManagerDelegate? { get set }
    var connectionState: ReaderConnectionState { get }
    func connectToReader()
    func disconnectReader()
    func collectPayment(amount: Int, clientSecret: String)
    /// Aborts any in-flight discovery, connection, or card collection so a
    /// canceled checkout can't complete the payment afterwards.
    func cancelPayment()
}

// MARK: - Stripe Terminal Connection Token Provider
final class StripeConnectionTokenProvider: NSObject, ConnectionTokenProvider {
    private let apiClient: BackendAPIClientProtocol
    
    init(apiClient: BackendAPIClientProtocol) {
        self.apiClient = apiClient
        super.init()
    }
    
    func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        Task {
            do {
                let secret = try await apiClient.fetchTerminalConnectionToken()
                completion(secret, nil)
            } catch {
                completion(nil, error)
            }
        }
    }
}

// MARK: - Stripe Terminal Manager Implementation

/// Fired when reader discovery runs too long without finding/connecting the M2,
/// so checkout never hangs on "Syncing Reader..." forever.
private struct ReaderDiscoveryTimeoutError: LocalizedError {
    var errorDescription: String? {
        "Couldn't reach the card reader in time. Make sure the M2 is powered on and close to the iPad, then try again."
    }
}

/// Fired when the SDK found the reader but couldn't finish connecting (e.g. the
/// iOS pairing prompt stalled or the reader dropped mid-connect).
private struct ReaderConnectTimeoutError: LocalizedError {
    var errorDescription: String? {
        "Couldn't finish connecting to the card reader. Check the M2 is awake and close by, then try again."
    }
}

/// IMPORTANT: the Stripe Terminal SDK requires ALL of its API calls (discover,
/// connect, cancel, collect, confirm…) on the main thread and aborts otherwise.
/// Being @MainActor guarantees every call — including from our internal Tasks —
/// runs on the main thread.
@MainActor
public final class StripeTerminalManager: NSObject, StripeTerminalManagerProtocol, DiscoveryDelegate, TerminalDelegate, ReaderDelegate, MobileReaderDelegate, OfflineDelegate {
    public weak var delegate: StripeTerminalManagerDelegate?
    
    public private(set) var connectionState: ReaderConnectionState = .disconnected {
        didSet {
            delegate?.terminalManager(self, didChangeState: connectionState)
        }
    }
    
    private let apiClient: BackendAPIClientProtocol
    private let tokenProvider: ConnectionTokenProvider
    /// Stripe Dashboard → Terminal → Locations. The Reader M2 must be registered
    /// to this location or the SDK refuses to connect it.
    private let locationId: String
    /// When true, discovery uses Stripe's virtual simulated reader (dev/testing
    /// without hardware). Must be false to connect the physical Reader M2.
    private let usesSimulatedReader: Bool
    private var discoveryCancelable: Cancelable?
    /// Guards discovery so it can't hang forever (e.g. reader asleep/out of range):
    /// after a timeout we stop scanning and surface a clear error.
    private var discoveryTimeoutTask: Task<Void, Never>?
    /// Guards the connect phase (incl. first-time iOS pairing), which can stall.
    private var connectTimeoutTask: Task<Void, Never>?
    /// The in-flight collectPaymentMethod/confirmPaymentIntent cancelable (the
    /// SDK v5.7 API returns a Cancelable for those; connectReader does not), so
    /// a canceled checkout can abort card collection/confirmation.
    private var paymentCancelable: Cancelable?
    /// A payment that arrived while no reader was connected; it is processed
    /// automatically once a reader connects.
    private var pendingPayment: (amount: Int, clientSecret: String)?
    /// Set when the cashier cancels checkout, so any in-flight terminal work
    /// (retrieve/collect/confirm) doesn't complete the sale afterwards.
    private var isPaymentCancelled = false
    
    /// How long discovery may run before we give up and tell the user.
    private let discoveryTimeoutNanoseconds: UInt64 = 20_000_000_000
    /// How long a connect (incl. iOS pairing) may take before we give up.
    private let connectTimeoutNanoseconds: UInt64 = 45_000_000_000
    
    public init(
        apiClient: BackendAPIClientProtocol,
        locationId: String,
        usesSimulatedReader: Bool = false
    ) {
        self.apiClient = apiClient
        self.locationId = locationId
        self.usesSimulatedReader = usesSimulatedReader
        self.tokenProvider = StripeConnectionTokenProvider(apiClient: apiClient)
        super.init()
        
        // Register token provider if not already set
        if !Terminal.isInitialized() {
            Terminal.initWithTokenProvider(
                self.tokenProvider,
                delegate: self,
                offlineDelegate: self,
                logLevel: .none
            )
        }
    }
    
    public func connectToReader() {
        guard connectionState == .disconnected else { return }
        
        connectionState = .scanning
        startDiscoveryTimeout()
        
        // Continuous Bluetooth scan is more reliable for the M2 than
        // proximity-only discovery, which can miss a reader that's awake but
        // not extremely close. Simulated mode is only for dev without hardware.
        let config = try! BluetoothScanDiscoveryConfigurationBuilder()
            .setSimulated(usesSimulatedReader)
            .build()
        
        discoveryCancelable = Terminal.shared.discoverReaders(config, delegate: self) { [weak self] error in
            guard let self = self else { return }
            self.discoveryTimeoutTask?.cancel()
            self.discoveryTimeoutTask = nil
            if let error = error {
                // Startup reader discovery failure should NOT block the POS landing screen.
                // The top-bar reader icon reflects the disconnected state, and scanning +
                // cart remain fully usable. Payment-time failures still surface via
                // didEncounterError inside collectPayment().
                self.connectionState = .disconnected

                // A canceled discovery is EXPECTED when we restart discovery at
                // checkout ("discoverReaders was canceled.") — it's the old scan
                // shutting down, not a real failure. Ignore it; the new discovery
                // attempt continues with the pending payment intact.
                if error.localizedDescription.localizedCaseInsensitiveContains("cancel") {
                    return
                }

                // ...but if the cashier is mid-checkout waiting for this reader,
                // surface the real failure instead of hanging silently.
                if self.pendingPayment != nil {
                    self.pendingPayment = nil
                    self.reportError(error, context: "Reader discovery failed")
                }
            }
        }
    }
    
    /// Cancels discovery after a grace period if no reader connected, so the
    /// checkout UI never hangs on "Syncing Reader..." indefinitely.
    private func startDiscoveryTimeout() {
        discoveryTimeoutTask?.cancel()
        discoveryTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.discoveryTimeoutNanoseconds ?? 15_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            
            // A reader connected, or a connect attempt is already in flight —
            // don't yank the rug out from under it.
            if case .connected = self.connectionState { return }
            if case .connecting = self.connectionState { return }
            
            print("[StripeTerminal] Reader discovery timed out after 20s")
            try? await self.discoveryCancelable?.cancel()
            self.discoveryCancelable = nil
            self.connectionState = .disconnected
            
            // Only surface an error if the cashier is waiting on a payment;
            // background/startup discovery timeouts stay silent.
            guard self.pendingPayment != nil else { return }
            self.pendingPayment = nil
            self.reportError(ReaderDiscoveryTimeoutError(), context: "Reader discovery timed out")
        }
    }
    
    /// Cancels a stuck connect (e.g. iOS pairing prompt accepted but the SDK
    /// never finishes) so checkout can't hang on "Syncing Reader..." forever.
    private func startConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.connectTimeoutNanoseconds ?? 45_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            guard case .connecting = self.connectionState else { return }
            
            print("[StripeTerminal] Reader connect timed out — resetting connection state")
            // Note: SDK v5.7's connectReader returns no cancelable, so the SDK
            // connect attempt can't be aborted directly. We reset our state and
            // surface an error; a late connect completion is harmless because
            // pendingPayment is cleared below (and isPaymentCancelled guards
            // the payment flow).
            self.connectionState = .disconnected
            
            guard self.pendingPayment != nil else { return }
            self.pendingPayment = nil
            self.reportError(ReaderConnectTimeoutError(), context: "Reader connect timed out")
        }
    }
    
    public func disconnectReader() {
        Terminal.shared.disconnectReader { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.reportError(error, context: "Reader disconnect failed")
            } else {
                self.connectionState = .disconnected
            }
        }
    }
    
    public func cancelPayment() {
        print("[StripeTerminal] Canceling payment flow")
        isPaymentCancelled = true
        pendingPayment = nil
        
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        discoveryTimeoutTask?.cancel()
        discoveryTimeoutTask = nil
        
        // Abort in-flight discovery and any active card collection/confirmation.
        // SDK v5.7's connectReader returns no cancelable, so a mid-connect
        // attempt can't be aborted directly — but any late completion is
        // harmless: pendingPayment was cleared above and the isPaymentCancelled
        // guards in processPayment() suppress late payment completions, so a
        // canceled checkout can never complete the sale or capture a charge.
        Task {
            try? await self.discoveryCancelable?.cancel()
            try? await self.paymentCancelable?.cancel()
            self.discoveryCancelable = nil
            self.paymentCancelable = nil
        }
    }
    
    public func collectPayment(amount: Int, clientSecret: String) {
        isPaymentCancelled = false
        guard case .connected = connectionState else {
            // No reader connected yet. Remember the payment — it will be
            // processed automatically once a reader connects.
            pendingPayment = (amount, clientSecret)
            
            // If a discovery/connect attempt is already running (e.g. the
            // launch-time connect is mid-pairing), let it finish instead of
            // racing it with a second attempt. Only start fresh when idle.
            switch connectionState {
            case .disconnected:
                restartDiscovery()
            case .scanning, .connecting, .connected:
                break
            }
            return
        }
        processPayment(amount: amount, clientSecret: clientSecret)
    }
    
    /// Cancels any in-flight discovery and starts a fresh attempt. This matters
    /// because startup discovery can be left stuck scanning (e.g. the reader was
    /// off at launch) — tapping Pay must force a new attempt rather than
    /// silently waiting forever.
    private func restartDiscovery() {
        // Cancelable.cancel() is async-throwing in the Stripe Terminal SDK v5.
        // Await it so the old discovery can't fire callbacks after we restart.
        discoveryTimeoutTask?.cancel()
        discoveryTimeoutTask = nil
        Task {
            if let discoveryCancelable {
                try? await discoveryCancelable.cancel()
            }
            self.discoveryCancelable = nil
            self.connectionState = .disconnected
            self.connectToReader()
        }
    }
    
    /// Logs the underlying failure (so the real cause is visible in the Xcode
    /// console) and forwards it to the delegate.
    private func reportError(_ error: Error, context: String) {
        print("[StripeTerminal] \(context): \(error.localizedDescription)")
        delegate?.terminalManager(self, didEncounterError: error)
    }
    
    private func processPayment(amount: Int, clientSecret: String) {
        Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret) { [weak self] paymentIntent, error in
            guard let self = self else { return }
            
            // Cashier canceled while we were fetching the intent.
            guard !self.isPaymentCancelled else { return }
            
            if let error = error {
                self.reportError(error, context: "Retrieving payment intent failed")
                return
            }
            
            guard let paymentIntent = paymentIntent else {
                self.reportError(BackendAPIError.missingData, context: "Payment intent missing")
                return
            }
            
            // Reader is connected and the intent is ready — tell the UI it's safe
            // to prompt "Tap Card on Reader".
            self.delegate?.terminalManagerDidBeginCollectingPayment(self)
            
            let collectCancelable = Terminal.shared.collectPaymentMethod(paymentIntent) { [weak self] collectedIntent, collectError in
                guard let self = self else { return }
                self.paymentCancelable = nil
                
                if let error = collectError {
                    // Canceling on purpose is not a failure — stay silent.
                    guard !self.isPaymentCancelled else { return }
                    self.reportError(error, context: "Collecting payment method failed")
                    return
                }
                
                guard let collectedIntent = collectedIntent else {
                    guard !self.isPaymentCancelled else { return }
                    self.reportError(BackendAPIError.missingData, context: "Collected payment missing")
                    return
                }
                
                let confirmCancelable = Terminal.shared.confirmPaymentIntent(collectedIntent) { [weak self] confirmedIntent, confirmError in
                    guard let self = self else { return }
                    self.paymentCancelable = nil
                    
                    if let error = confirmError {
                        guard !self.isPaymentCancelled else { return }
                        self.reportError(error, context: "Confirming payment failed")
                    } else if let confirmedIntent = confirmedIntent {
                        // Contactless transaction authorized by physical reader.
                        // Delegate triggers backend payment capture to finalize transaction in D1.
                        guard !self.isPaymentCancelled else { return }
                        self.delegate?.terminalManagerDidCompletePayment(self, paymentIntentId: confirmedIntent.stripeId ?? "")
                    }
                }
                self.paymentCancelable = confirmCancelable
            }
            self.paymentCancelable = collectCancelable
        }
    }
    
    // MARK: - DiscoveryDelegate
    public func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        print("[StripeTerminal] Discovery update: \(readers.count) reader(s) seen")
        guard connectionState == .scanning, let firstReader = readers.first else { return }
        
        connectionState = .connecting
        startConnectTimeout()
        print("[StripeTerminal] Connecting to reader: \(firstReader.label ?? "Stripe Reader M2")")
        
        // Location ID must match the Stripe Terminal dashboard location that the
        // Reader M2 is registered to.
        let connectionConfig = try! BluetoothConnectionConfigurationBuilder(delegate: self, locationId: locationId).build()
        
        Terminal.shared.connectReader(firstReader, connectionConfig: connectionConfig) { [weak self] connectedReader, error in
            guard let self = self else { return }
            
            // Discovery succeeded in finding a reader — the guards are done.
            self.discoveryTimeoutTask?.cancel()
            self.discoveryTimeoutTask = nil
            self.connectTimeoutTask?.cancel()
            self.connectTimeoutTask = nil
            
            if let error = error {
                print("[StripeTerminal] Reader connection failed: \(error.localizedDescription)")
                // Same non-blocking treatment as startup discovery: a reader that fails to
                // connect just leaves the top-bar icon gray instead of blocking the UI.
                self.connectionState = .disconnected
                // ...but if the cashier is mid-checkout waiting for this reader,
                // surface the real failure instead of hanging silently.
                if self.pendingPayment != nil {
                    self.pendingPayment = nil
                    self.reportError(error, context: "Reader connection failed")
                }
            } else if let reader = connectedReader {
                print("[StripeTerminal] Reader connected: \(reader.label ?? "Stripe Reader M2")")
                self.connectionState = .connected(
                    readerName: reader.label ?? "Stripe Reader M2",
                    batteryLevel: reader.batteryLevel?.floatValue ?? 100.0
                )
                
                // Process any payment that was deferred while waiting for a reader.
                if let pending = self.pendingPayment {
                    self.pendingPayment = nil
                    self.processPayment(amount: pending.amount, clientSecret: pending.clientSecret)
                }
            }
        }
    }
    
    // MARK: - MobileReaderDelegate — software updates
    /// A required reader update installs automatically DURING connect; the
    /// connectReader completion only fires after it finishes (minutes, with the
    /// reader's 4 LEDs flashing). We must NOT let our connect timeout cancel it.
    public func reader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        print("[StripeTerminal] Reader software update STARTED (required during connect) — waiting for it to finish")
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        
        // Safety net: updates can take several minutes, but if one truly hangs,
        // surface an error instead of waiting forever.
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000_000) // 10 minutes
            guard let self = self, !Task.isCancelled else { return }
            guard case .connecting = self.connectionState else { return }
            print("[StripeTerminal] Reader update took too long — resetting connection state")
            self.connectionState = .disconnected
            guard self.pendingPayment != nil else { return }
            self.pendingPayment = nil
            self.reportError(ReaderConnectTimeoutError(), context: "Reader update timed out")
        }
    }
    
    public func reader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        // Guard against non-finite values — Int() traps on NaN/infinity.
        let percent = progress.isFinite ? Int(progress * 100) : 0
        print("[StripeTerminal] Reader update progress: \(percent)%")
        delegate?.terminalManager(self, didReportReaderUpdateProgress: progress)
    }
    
    public func reader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {
        if let error = error {
            print("[StripeTerminal] Reader update FAILED: \(error.localizedDescription)")
        } else {
            print("[StripeTerminal] Reader update finished: \(update?.deviceSoftwareVersion ?? "?")")
        }
    }
    
    public func reader(_ reader: Reader, didReportAvailableUpdate update: ReaderSoftwareUpdate) {
        print("[StripeTerminal] Reader software update available (optional): \(update.deviceSoftwareVersion ?? "?")")
    }
    
    public func reader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {}
    public func reader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {}
    public func reader(_ reader: Reader, didReportReaderEvent event: ReaderEvent, info: [AnyHashable: Any]?) {}
    public func reader(_ reader: Reader, didReportBatteryLevel batteryLevel: Float, status: BatteryStatus, isCharging: Bool) {}
    public func readerDidReportLowBatteryWarning(_ reader: Reader) {}
    
    public func reader(
        _ reader: Reader,
        didRequestPaymentMethodSelection paymentIntent: PaymentIntent,
        availablePaymentOptions: [PaymentOption],
        completion: @escaping PaymentMethodSelectionCompletionBlock
    ) {
        completion(availablePaymentOptions.first, nil)
    }
    
    public func reader(
        _ reader: Reader,
        didRequestQrCodeDisplay paymentIntent: PaymentIntent,
        qrData: QrCodeDisplayData,
        completion: @escaping QrCodeDisplayCompletionBlock
    ) {
        completion(nil)
    }
    
    // MARK: - ReaderDelegate placeholders
    public func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {}
    public func reader(_ reader: Reader, didStartReconnect cancelable: Cancelable, disconnectReason: DisconnectReason) {}
    public func readerDidFailReconnect(_ reader: Reader) {}
    public func readerDidSucceedReconnect(_ reader: Reader) {}
    
    // MARK: - TerminalDelegate placeholders
    public func terminal(_ terminal: Terminal, didChangePaymentStatus status: PaymentStatus) {}
    public func terminal(_ terminal: Terminal, didChangeConnectionStatus status: ConnectionStatus) {}
    public func terminal(_ terminal: Terminal, didReportUnexpectedReaderDisconnect reader: Reader) {}
    
    // MARK: - OfflineDelegate placeholders
    public func terminal(_ terminal: Terminal, didChange offlineStatus: OfflineStatus) {}
    public func terminal(_ terminal: Terminal, didForwardPaymentIntent intent: PaymentIntent, error: Error?) {}
    public func terminal(_ terminal: Terminal, didReportForwardingError error: Error) {}
}
