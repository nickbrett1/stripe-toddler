import Foundation

// MARK: - Backend API Client Protocol
public protocol BackendAPIClientProtocol: AnyObject {
    func registerDeviceWithAppAttest() async throws
    func fetchItem(barcode: String) async throws -> POSInventoryItem
    func fetchTerminalConnectionToken() async throws -> String
    func createPaymentIntent(amountCents: Int, barcodes: [String]) async throws -> PaymentIntentResponse
    func captureTransaction(paymentIntentId: String, totalCents: Int, items: [POSInventoryItem]) async throws -> CaptureResponse
}

// MARK: - Backend API Client Error
public enum BackendAPIError: LocalizedError {
    case invalidURL
    case badResponse(statusCode: Int)
    case missingData
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .badResponse(let code):
            return "Server returned an error status code: \(code)."
        case .missingData:
            return "The server did not send any data."
        }
    }
}

// MARK: - Backend API Client Implementation
public final class BackendAPIClient: BackendAPIClientProtocol {
    private let baseURL: URL
    private let session: URLSession
    
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    // Helper to configure decoders with snake_case conversion support
    private var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    
    private var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
    
    public func registerDeviceWithAppAttest() async throws {
        // App Attest registration stub for development / simulation
        // In physical builds, Apple App Attest challenge-response verification is run here
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    public func fetchItem(barcode: String) async throws -> POSInventoryItem {
        let url = baseURL.appendingPathComponent("api/pos/inventory/\(barcode)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("placeholder-attest-token", forHTTPHeaderField: "X-App-Attest-Assertion")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.badResponse(statusCode: 0)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BackendAPIError.badResponse(statusCode: httpResponse.statusCode)
        }
        
        return try jsonDecoder.decode(POSInventoryItem.self, from: data)
    }
    
    public func fetchTerminalConnectionToken() async throws -> String {
        let url = baseURL.appendingPathComponent("api/terminal/connection-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("placeholder-attest-token", forHTTPHeaderField: "X-App-Attest-Assertion")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.badResponse(statusCode: 0)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BackendAPIError.badResponse(statusCode: httpResponse.statusCode)
        }
        
        struct TokenResponse: Decodable {
            let secret: String
        }
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.secret
    }
    
    public func createPaymentIntent(amountCents: Int, barcodes: [String]) async throws -> PaymentIntentResponse {
        let url = baseURL.appendingPathComponent("api/terminal/payment-intent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("placeholder-attest-token", forHTTPHeaderField: "X-App-Attest-Assertion")
        
        struct RequestBody: Encodable {
            let amountCents: Int
            let barcodes: [String]
        }
        
        let body = RequestBody(amountCents: amountCents, barcodes: barcodes)
        request.httpBody = try jsonEncoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.badResponse(statusCode: 0)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BackendAPIError.badResponse(statusCode: httpResponse.statusCode)
        }
        
        return try jsonDecoder.decode(PaymentIntentResponse.self, from: data)
    }
    
    public func captureTransaction(paymentIntentId: String, totalCents: Int, items: [POSInventoryItem]) async throws -> CaptureResponse {
        let url = baseURL.appendingPathComponent("api/terminal/capture")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("placeholder-attest-token", forHTTPHeaderField: "X-App-Attest-Assertion")
        
        struct RequestBody: Encodable {
            let paymentIntentId: String
            let totalCents: Int
            let items: [POSInventoryItem]
        }
        
        let body = RequestBody(paymentIntentId: paymentIntentId, totalCents: totalCents, items: items)
        request.httpBody = try jsonEncoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.badResponse(statusCode: 0)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw BackendAPIError.badResponse(statusCode: httpResponse.statusCode)
        }
        
        return try jsonDecoder.decode(CaptureResponse.self, from: data)
    }
}
