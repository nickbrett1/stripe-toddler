import Foundation
import DeviceCheck
import CryptoKit
import UIKit

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
    private let attestService = DCAppAttestService.shared
    
    // Store keyId in UserDefaults (Keychain is preferred in production, UserDefaults for simplicity)
    private var appAttestKeyId: String? {
        get { UserDefaults.standard.string(forKey: "appAttestKeyId") }
        set { UserDefaults.standard.set(newValue, forKey: "appAttestKeyId") }
    }
    
    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
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
    
    // MARK: - Apple App Attest Integration (Step 4.6)
    public func registerDeviceWithAppAttest() async throws {
        guard attestService.isSupported else {
            // App Attest is not supported on Simulators. Fall back to placeholder mode.
            return
        }
        
        let keyId: String
        if let existingKey = appAttestKeyId {
            keyId = existingKey
        } else {
            keyId = try await withCheckedThrowingContinuation { continuation in
                attestService.generateKey { keyId, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let keyId = keyId {
                        continuation.resume(returning: keyId)
                    } else {
                        continuation.resume(throwing: BackendAPIError.missingData)
                    }
                }
            }
            appAttestKeyId = keyId
        }
        
        // 1. Fetch challenge from backend
        let challenge = try await fetchChallenge()
        
        // 2. Hash the challenge clientDataHash
        let challengeData = challenge.data(using: .utf8)!
        let hash = Data(SHA256.hash(data: challengeData))
        
        // 3. Attest the generated keyId
        let attestation = try await withCheckedThrowingContinuation { continuation in
            attestService.attestKey(keyId, clientDataHash: hash) { attestation, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let attestation = attestation {
                    continuation.resume(returning: attestation)
                } else {
                    continuation.resume(throwing: BackendAPIError.missingData)
                }
            }
        }
        
        // 4. Send attestation verification request to backend
        try await verifyAttestation(keyId: keyId, attestation: attestation, challenge: challenge)
    }
    
    private func fetchChallenge() async throws -> String {
        let url = baseURL.appendingPathComponent("api/attest/challenge")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BackendAPIError.badResponse(statusCode: 200)
        }
        
        struct ChallengeResponse: Decodable {
            let challenge: String
        }
        let result = try JSONDecoder().decode(ChallengeResponse.self, from: data)
        return result.challenge
    }
    
    private func verifyAttestation(keyId: String, attestation: Data, challenge: String) async throws {
        let url = baseURL.appendingPathComponent("api/attest/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct VerifyPayload: Encodable {
            let deviceId: String
            let keyId: String
            let attestationObject: String
            let challenge: String
        }
        
        let payload = VerifyPayload(
            deviceId: deviceId,
            keyId: keyId,
            attestationObject: attestation.base64EncodedString(),
            challenge: challenge
        )
        request.httpBody = try jsonEncoder.encode(payload)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BackendAPIError.badResponse(statusCode: 200)
        }
    }
    
    // Generates a base64 encoded client assertion payload (Step 4.6.6)
    private func generateAssertionHeader(for clientData: Data) async -> String {
        guard attestService.isSupported, let keyId = appAttestKeyId else {
            return "placeholder-attest-token"
        }
        
        let clientDataHash = Data(SHA256.hash(data: clientData))
        do {
            let assertion = try await withCheckedThrowingContinuation { continuation in
                attestService.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let assertion = assertion {
                        continuation.resume(returning: assertion)
                    } else {
                        continuation.resume(throwing: BackendAPIError.missingData)
                    }
                }
            }
            return assertion.base64EncodedString()
        } catch {
            return "placeholder-attest-token"
        }
    }
    
    // MARK: - POS Operations
    public func fetchItem(barcode: String) async throws -> POSInventoryItem {
        let url = baseURL.appendingPathComponent("api/pos/inventory/\(barcode)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let barcodeData = barcode.data(using: .utf8)!
        let assertion = await generateAssertionHeader(for: barcodeData)
        request.setValue(assertion, forHTTPHeaderField: "X-App-Attest-Assertion")
        
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
        
        // Empty payload hash for connection token requests
        let assertion = await generateAssertionHeader(for: Data())
        request.setValue(assertion, forHTTPHeaderField: "X-App-Attest-Assertion")
        
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
        
        struct RequestBody: Encodable {
            let amountCents: Int
            let barcodes: [String]
        }
        
        let body = RequestBody(amountCents: amountCents, barcodes: barcodes)
        let bodyData = try jsonEncoder.encode(body)
        request.httpBody = bodyData
        
        let assertion = await generateAssertionHeader(for: bodyData)
        request.setValue(assertion, forHTTPHeaderField: "X-App-Attest-Assertion")
        
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
        
        struct RequestBody: Encodable {
            let paymentIntentId: String
            let totalCents: Int
            let items: [POSInventoryItem]
        }
        
        let body = RequestBody(paymentIntentId: paymentIntentId, totalCents: totalCents, items: items)
        let bodyData = try jsonEncoder.encode(body)
        request.httpBody = bodyData
        
        let assertion = await generateAssertionHeader(for: bodyData)
        request.setValue(assertion, forHTTPHeaderField: "X-App-Attest-Assertion")
        
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
