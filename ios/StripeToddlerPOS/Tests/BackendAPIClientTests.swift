import XCTest
@testable import StripeToddlerPOS

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler is unavailable.")
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

final class BackendAPIClientTests: XCTestCase {
    var apiClient: BackendAPIClient!
    var session: URLSession!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        apiClient = BackendAPIClient(baseURL: URL(string: "https://example.com")!, session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        apiClient = nil
        session = nil
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testFetchItem_invalidResponse() async {
        MockURLProtocol.requestHandler = { request in
            let response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            return (response, Data())
        }

        do {
            _ = try await apiClient.fetchItem(barcode: "123")
            XCTFail("Expected invalidResponse error")
        } catch let error as BackendAPIError {
            if case .invalidResponse = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Expected BackendAPIError, got \(error)")
        }
    }

    func testFetchItem_notFound() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await apiClient.fetchItem(barcode: "404")
            XCTFail("Expected itemNotFound error")
        } catch let error as BackendAPIError {
            if case .itemNotFound = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected itemNotFound, got \(error)")
            }
        } catch {
            XCTFail("Expected BackendAPIError, got \(error)")
        }
    }

    func testFetchItem_serverError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await apiClient.fetchItem(barcode: "500")
            XCTFail("Expected badResponse(500) error")
        } catch let error as BackendAPIError {
            if case .badResponse(let statusCode) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected badResponse(500), got \(error)")
            }
        } catch {
            XCTFail("Expected BackendAPIError, got \(error)")
        }
    }
}
