import Foundation
import Combine

// MARK: - POS Flow State
public enum POSFlowState: Equatable {
    case waitingForScan
    case cartActive(items: [POSInventoryItem], totalCents: Int)
    case readerSyncing
    case awaitingCardTap
    case processingPayment
    case celebrating(itemsSold: [POSInventoryItem])
    case error(message: String)
}

// MARK: - POS View Model Implementation
@MainActor
public final class POSViewModel: ObservableObject, BarcodeScannerDelegate, StripeTerminalManagerDelegate {
    @Published public private(set) var state: POSFlowState = .waitingForScan
    @Published public var scannerConnected: Bool = true
    @Published public private(set) var readerConnected: Bool = false
    
    private let apiClient: BackendAPIClientProtocol
    private let terminalManager: StripeTerminalManagerProtocol
    private let scannerService: BarcodeScannerServiceProtocol
    
    // Cache the cart items and total to finalize the transaction after terminal authorization
    private var cachedCartItems: [POSInventoryItem] = []
    private var cachedCartTotal: Int = 0
    
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
                
                state = .cartActive(items: cachedCartItems, totalCents: cachedCartTotal)
            } catch {
                state = .error(message: "Item not found: \(barcode)")
                ToddlerHaptic.playNotification(ToddlerHapticType.error)
            }
        }
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
        state = .readerSyncing
        
        Task {
            do {
                let barcodes = items.map { $0.barcode }
                let response = try await apiClient.createPaymentIntent(amountCents: totalCents, barcodes: barcodes)
                
                state = .awaitingCardTap
                terminalManager.collectPayment(amount: totalCents, clientSecret: response.clientSecret)
            } catch {
                state = .error(message: "Failed to sync payment reader: \(error.localizedDescription)")
                ToddlerHaptic.playNotification(ToddlerHapticType.error)
            }
        }
    }
    
    public func resetPOS() {
        cachedCartItems.removeAll()
        cachedCartTotal = 0
        state = .waitingForScan
        ToddlerHaptic.play(ToddlerHapticStyle.medium)
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
        state = .error(message: "Terminal Error: \(error.localizedDescription)")
        ToddlerHaptic.playNotification(ToddlerHapticType.error)
    }
    
    public func terminalManagerDidCompletePayment(_ manager: StripeTerminalManagerProtocol, paymentIntentId: String) {
        state = .processingPayment
        
        Task {
            do {
                _ = try await apiClient.captureTransaction(
                    paymentIntentId: paymentIntentId,
                    totalCents: cachedCartTotal,
                    items: cachedCartItems
                )
                
                // Show celebration overlay! (Rule 4.3)
                state = .celebrating(itemsSold: cachedCartItems)
                ToddlerHaptic.playNotification(ToddlerHapticType.success)
            } catch {
                state = .error(message: "Capture failed: \(error.localizedDescription)")
                ToddlerHaptic.playNotification(ToddlerHapticType.error)
            }
        }
    }
}
