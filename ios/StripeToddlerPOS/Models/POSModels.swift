import Foundation

// MARK: - POS Inventory Item
public struct POSInventoryItem: Codable, Identifiable, Equatable {
    public var id: String { barcode }
    public let barcode: String
    public let name: String
    public let priceCents: Int
    public let imageUrl: URL
    
    enum CodingKeys: String, CodingKey {
        case barcode
        case name
        case priceCents
        case imageUrl
    }
    
    public init(barcode: String, name: String, priceCents: Int, imageUrl: URL) {
        self.barcode = barcode
        self.name = name
        self.priceCents = priceCents
        self.imageUrl = imageUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.barcode = try container.decode(String.self, forKey: .barcode)
        self.name = try container.decode(String.self, forKey: .name)
        self.priceCents = try container.decode(Int.self, forKey: .priceCents)

        // Robust URL parsing supporting web URLs, data URIs, and raw base64 strings
        if let url = try? container.decode(URL.self, forKey: .imageUrl) {
            self.imageUrl = url
        } else if let rawString = try? container.decode(String.self, forKey: .imageUrl) {
            if let url = URL(string: rawString) {
                self.imageUrl = url
            } else if let encoded = rawString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: encoded) {
                self.imageUrl = url
            } else {
                self.imageUrl = URL(string: "https://placehold.co/400")!
            }
        } else {
            self.imageUrl = URL(string: "https://placehold.co/400")!
        }
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
