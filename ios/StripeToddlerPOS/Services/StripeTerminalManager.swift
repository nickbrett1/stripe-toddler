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
private final class StripeConnectionTokenProvider: ConnectionTokenProvider {
    private let apiClient: BackendAPIClientProtocol
    
    init(apiClient: BackendAPIClientProtocol) {
        self.apiClient = apiClient
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
public final class StripeTerminalManager: NSObject, StripeTerminalManagerProtocol, DiscoveryDelegate, TerminalDelegate {
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
        if !Terminal.isInitialized {
            Terminal.setSharedInstance(tokenProvider: StripeConnectionTokenProvider(apiClient: apiClient))
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
        let connectionConfig = try! BluetoothConnectionConfigurationBuilder(locationId: "tml_placeholder").build()
        
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
}
