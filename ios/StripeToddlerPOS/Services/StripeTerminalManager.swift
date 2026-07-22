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
}

public protocol StripeTerminalManagerProtocol: AnyObject {
    var delegate: StripeTerminalManagerDelegate? { get set }
    var connectionState: ReaderConnectionState { get }
    func connectToReader()
    func disconnectReader()
    func collectPayment(amount: Int, clientSecret: String)
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
public final class StripeTerminalManager: NSObject, StripeTerminalManagerProtocol, DiscoveryDelegate, TerminalDelegate, ReaderDelegate, MobileReaderDelegate, OfflineDelegate {
    public weak var delegate: StripeTerminalManagerDelegate?
    
    public private(set) var connectionState: ReaderConnectionState = .disconnected {
        didSet {
            delegate?.terminalManager(self, didChangeState: connectionState)
        }
    }
    
    private let apiClient: BackendAPIClientProtocol
    private var discoveryCancelable: Cancelable?
    
    public init(apiClient: BackendAPIClientProtocol) {
        self.apiClient = apiClient
        super.init()
        
        // Register token provider if not already set
        if !Terminal.isInitialized() {
            let tokenProvider: ConnectionTokenProvider = StripeConnectionTokenProvider(apiClient: apiClient)
            Terminal.initWithTokenProvider(
                tokenProvider,
                delegate: self,
                offlineDelegate: self,
                logLevel: .none
            )
        }
    }
    
    public func connectToReader() {
        guard connectionState == .disconnected else { return }
        
        connectionState = .scanning
        
        // Scan for Reader M2 using simulated mode for local development
        let config = try! BluetoothProximityDiscoveryConfigurationBuilder()
            .setSimulated(true)
            .build()
        
        discoveryCancelable = Terminal.shared.discoverReaders(config, delegate: self) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.connectionState = .disconnected
                self.delegate?.terminalManager(self, didEncounterError: error)
            }
        }
    }
    
    public func disconnectReader() {
        Terminal.shared.disconnectReader { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.delegate?.terminalManager(self, didEncounterError: error)
            } else {
                self.connectionState = .disconnected
            }
        }
    }
    
    public func collectPayment(amount: Int, clientSecret: String) {
        Terminal.shared.retrievePaymentIntent(clientSecret: clientSecret) { [weak self] paymentIntent, error in
            guard let self = self else { return }
            
            if let error = error {
                self.delegate?.terminalManager(self, didEncounterError: error)
                return
            }
            
            guard let paymentIntent = paymentIntent else {
                self.delegate?.terminalManager(self, didEncounterError: BackendAPIError.missingData)
                return
            }
            
            Terminal.shared.collectPaymentMethod(paymentIntent) { [weak self] collectedIntent, collectError in
                guard let self = self else { return }
                
                if let error = collectError {
                    self.delegate?.terminalManager(self, didEncounterError: error)
                    return
                }
                
                guard let collectedIntent = collectedIntent else {
                    self.delegate?.terminalManager(self, didEncounterError: BackendAPIError.missingData)
                    return
                }
                
                Terminal.shared.confirmPaymentIntent(collectedIntent) { [weak self] confirmedIntent, confirmError in
                    guard let self = self else { return }
                    
                    if let error = confirmError {
                        self.delegate?.terminalManager(self, didEncounterError: error)
                    } else if let confirmedIntent = confirmedIntent {
                        // Contactless transaction authorized by physical reader.
                        // Delegate triggers backend payment capture to finalize transaction in D1.
                        self.delegate?.terminalManagerDidCompletePayment(self, paymentIntentId: confirmedIntent.stripeId ?? "")
                    }
                }
            }
        }
    }
    
    // MARK: - DiscoveryDelegate
    public func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        guard connectionState == .scanning, let firstReader = readers.first else { return }
        
        connectionState = .connecting
        
        // Location ID is configured to match Stripe Terminal dashboard location ID
        let connectionConfig = try! BluetoothConnectionConfigurationBuilder(delegate: self, locationId: "tml_placeholder").build()
        
        Terminal.shared.connectReader(firstReader, connectionConfig: connectionConfig) { [weak self] connectedReader, error in
            guard let self = self else { return }
            
            if let error = error {
                self.connectionState = .disconnected
                self.delegate?.terminalManager(self, didEncounterError: error)
            } else if let reader = connectedReader {
                self.connectionState = .connected(
                    readerName: reader.label ?? "Stripe Reader M2",
                    batteryLevel: reader.batteryLevel?.floatValue ?? 100.0
                )
            }
        }
    }
    
    // MARK: - MobileReaderDelegate placeholders
    public func reader(_ reader: Reader, didReportAvailableUpdate update: ReaderSoftwareUpdate) {}
    public func reader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {}
    public func reader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {}
    public func reader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {}
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
