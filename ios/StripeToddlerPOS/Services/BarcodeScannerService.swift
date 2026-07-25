import UIKit

// MARK: - Barcode Scanner Protocols
public protocol BarcodeScannerDelegate: AnyObject {
    func didScanBarcode(_ barcode: ScannedBarcode)
    func didEncounterScannerError(_ error: Error)
}

public protocol BarcodeScannerServiceProtocol: AnyObject {
    var delegate: BarcodeScannerDelegate? { get set }
    func startListening()
    func stopListening()
}

// MARK: - Barcode Scanner Service Implementation
public final class BarcodeScannerService: BarcodeScannerServiceProtocol {
    public weak var delegate: BarcodeScannerDelegate?
    
    private var buffer = ""
    private var lastKeyTime = Date()
    private var isListening = false
    private let timeoutInterval: TimeInterval = 0.5 // 500ms timeout between keystrokes
    
    // Shared singleton instance for global window interceptor access
    public static let shared = BarcodeScannerService()
    
    private init() {}
    
    public func startListening() {
        isListening = true
        buffer = ""
        lastKeyTime = Date()
    }
    
    public func stopListening() {
        isListening = false
        buffer = ""
    }
    
    /// Entry point to process keyboard press events from the UIWindow layer
    public func handlePress(_ press: UIPress) {
        guard isListening, let key = press.key else { return }
        
        let now = Date()
        if now.timeIntervalSince(lastKeyTime) > timeoutInterval {
            buffer = ""
        }
        lastKeyTime = now
        
        let characters = key.characters
        let keyCode = key.keyCode
        
        // Carriage return or enter keys denote complete scan
        if keyCode == .keyboardReturnOrEnter || characters == "\r" || characters == "\n" {
            let barcodeValue = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !barcodeValue.isEmpty {
                let scannedBarcode = ScannedBarcode(value: barcodeValue, timestamp: now)
                DispatchQueue.main.async {
                    self.delegate?.didScanBarcode(scannedBarcode)
                }
            }
            buffer = ""
        } else {
            // Strip control characters, only record alphanumeric scanner sweeps
            let filteredCharacters = characters.filteringForBarcode()
            if !filteredCharacters.isEmpty {
                buffer.append(filteredCharacters)
            }
        }
    }
}

// MARK: - String Filter Helper
private extension String {
    func filteringForBarcode() -> String {
        // Barcode HID wedges output letters and numbers
        let allowedCharacters = CharacterSet.alphanumerics
        return String(self.unicodeScalars.filter { allowedCharacters.contains($0) })
    }
}
