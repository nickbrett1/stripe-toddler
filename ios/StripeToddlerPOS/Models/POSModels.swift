import Foundation

// MARK: - POS Inventory Item
public struct POSInventoryItem: Codable, Identifiable, Equatable {
    public var id: String { barcode }
    public let barcode: String
    public let name: String
    public let priceCents: Int
    public let imageUrl: URL
    
    public init(barcode: String, name: String, priceCents: Int, imageUrl: URL) {
        self.barcode = barcode
        self.name = name
        self.priceCents = priceCents
        self.imageUrl = imageUrl
    }
}

// MARK: - Payment Intent Response
public struct PaymentIntentResponse: Codable {
    public let paymentIntentId: String
    public let clientSecret: String
    
    public init(paymentIntentId: String, clientSecret: String) {
        self.paymentIntentId = paymentIntentId
        self.clientSecret = clientSecret
    }
}

// MARK: - Capture Response
public struct CaptureResponse: Codable {
    public let status: String
    public let transactionId: String
    
    public init(status: String, transactionId: String) {
        self.status = status
        self.transactionId = transactionId
    }
}

// MARK: - Scanned Barcode Helper
public struct ScannedBarcode {
    public let value: String
    public let timestamp: Date
    
    public init(value: String, timestamp: Date = Date()) {
        self.value = value
        self.timestamp = timestamp
    }
}
