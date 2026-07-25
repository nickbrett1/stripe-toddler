import XCTest
import DeviceCheck
@testable import StripeToddlerPOS

// MARK: - Mock App Attest Provider
class MockAppAttestProvider: AppAttestProvider {
    var isSupported: Bool = true
    var generateKeyResult: Result<String, Error> = .success("mock_key_id")
    var attestKeyResult: Result<Data, Error> = .success(Data("mock_attestation".utf8))
    var generateAssertionResult: Result<Data, Error> = .success(Data("mock_assertion".utf8))

    func generateKey(completionHandler: @escaping (String?, Error?) -> Void) {
        switch generateKeyResult {
        case .success(let keyId):
            completionHandler(keyId, nil)
        case .failure(let error):
            completionHandler(nil, error)
        }
    }

    func attestKey(_ keyId: String, clientDataHash: Data, completionHandler: @escaping (Data?, Error?) -> Void) {
        switch attestKeyResult {
        case .success(let data):
            completionHandler(data, nil)
        case .failure(let error):
            completionHandler(nil, error)
        }
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data, completionHandler: @escaping (Data?, Error?) -> Void) {
        switch generateAssertionResult {
        case .success(let data):
            completionHandler(data, nil)
        case .failure(let error):
            completionHandler(nil, error)
        }
    }
}

// MARK: - Mock URL Protocol
class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Received unexpected request with no handler set")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class BackendAPIClientTests: XCTestCase {
    var apiClient: BackendAPIClient!
    var mockAppAttestProvider: MockAppAttestProvider!

    override func setUp() {
        super.setUp()

        // Reset UserDefaults for isolated tests
        UserDefaults.standard.removeObject(forKey: "appAttestKeyId")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        mockAppAttestProvider = MockAppAttestProvider()

        apiClient = BackendAPIClient(
            baseURL: URL(string: "https://test.com")!,
            session: session,
            attestService: mockAppAttestProvider
        )
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        apiClient = nil
        mockAppAttestProvider = nil
        super.tearDown()
    }

    func testRegisterDeviceWithAppAttest_Success() async throws {
        // Setup mock network responses
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/attest/challenge" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = """
                {
                    "challenge": "mock_challenge_string"
                }
                """.data(using: .utf8)!
                return (response, data)
            } else if request.url?.path == "/api/attest/verify" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            XCTFail("Unexpected request: \(request.url?.path ?? "")")
            throw URLError(.badURL)
        }

        // Execute the method under test
        do {
            try await apiClient.registerDeviceWithAppAttest()
            XCTAssertEqual(apiClient.appAttestKeyId, "mock_key_id")
        } catch {
            XCTFail("Expected success, but threw error: \(error)")
        }
    }

    func testRegisterDeviceWithAppAttest_Unsupported() async throws {
        mockAppAttestProvider.isSupported = false

        do {
            try await apiClient.registerDeviceWithAppAttest()
            XCTAssertNil(apiClient.appAttestKeyId)
        } catch {
            XCTFail("Expected early return, but threw error: \(error)")
        }
    }

    func testRegisterDeviceWithAppAttest_GenerateKeyError() async throws {
        struct MockError: Error {}
        mockAppAttestProvider.generateKeyResult = .failure(MockError())

        do {
            try await apiClient.registerDeviceWithAppAttest()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertNil(apiClient.appAttestKeyId)
        }
    }

    func testRegisterDeviceWithAppAttest_ChallengeFetchError() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/attest/challenge" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            XCTFail("Unexpected request: \(request.url?.path ?? "")")
            throw URLError(.badURL)
        }

        do {
            try await apiClient.registerDeviceWithAppAttest()
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertEqual(apiClient.appAttestKeyId, "mock_key_id") // Key should be generated and saved before challenge fetch
        }
    }

    func testRegisterDeviceWithAppAttest_AttestationError() async throws {
        // Setup challenge success to reach attestation step
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/attest/challenge" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let data = """
                {
                    "challenge": "mock_challenge_string"
                }
                """.data(using: .utf8)!
                return (response, data)
            }
            XCTFail("Unexpected request: \(request.url?.path ?? "")")
            throw URLError(.badURL)
        }

        struct MockError: Error {}
        mockAppAttestProvider.attestKeyResult = .failure(MockError())

        do {
            try await apiClient.registerDeviceWithAppAttest()
            XCTFail("Expected error to be thrown")
        } catch {
            // Error should be thrown during attestation
        }
    }
}
