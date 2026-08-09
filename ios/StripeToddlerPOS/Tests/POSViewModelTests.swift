import XCTest
import SwiftUI
@testable import StripeToddlerPOS

// MARK: - API Client Mock
final class MockBackendAPIClient: BackendAPIClientProtocol {
    var registerCalled = false
    var fetchItemResult: Result<POSInventoryItem, Error> = .success(
        POSInventoryItem(
            barcode: "TOY001",
            name: "Fire Truck",
            priceCents: 500,
            imageUrl: URL(string: "https://example.com/photo.jpg")!
        )
    )
    var fetchTokenResult: Result<String, Error> = .success("pst_test_connection_token_secret")
    var createPIResult: Result<PaymentIntentResponse, Error> = .success(
        PaymentIntentResponse(paymentIntentId: "pi_123", clientSecret: "secret_123")
    )
    var captureResult: Result<CaptureResponse, Error> = .success(
        CaptureResponse(status: "succeeded", transactionId: "tx_999")
    )
    
    func registerDeviceWithAppAttest() async throws {
        registerCalled = true
    }
    
    func fetchItem(barcode: String) async throws -> POSInventoryItem {
        try fetchItemResult.get()
    }
    
    func fetchTerminalConnectionToken() async throws -> String {
        try fetchTokenResult.get()
    }
    
    func createPaymentIntent(amountCents: Int, barcodes: [String]) async throws -> PaymentIntentResponse {
        try createPIResult.get()
    }
    
    func captureTransaction(
        paymentIntentId: String,
        totalCents: Int,
        items: [POSInventoryItem]
    ) async throws -> CaptureResponse {
        try captureResult.get()
    }
}

// MARK: - Stripe Terminal Manager Mock
final class MockStripeTerminalManager: StripeTerminalManagerProtocol {
    weak var delegate: StripeTerminalManagerDelegate?
    var connectionState: ReaderConnectionState = .disconnected
    var connectCalled = false
    var disconnectCalled = false
    var collectPaymentCalled = false
    var cancelPaymentCalled = false
    
    func connectToReader() {
        connectCalled = true
        connectionState = .connected(readerName: "Simulated Reader", batteryLevel: 99.0)
        delegate?.terminalManager(self, didChangeState: connectionState)
    }
    
    func disconnectReader() {
        disconnectCalled = true
        connectionState = .disconnected
        delegate?.terminalManager(self, didChangeState: connectionState)
    }
    
    func collectPayment(amount: Int, clientSecret: String) {
        collectPaymentCalled = true
        delegate?.terminalManagerDidBeginCollectingPayment(self)
    }
    
    func cancelPayment() {
        cancelPaymentCalled = true
    }
    
    func simulatePaymentSuccess(paymentIntentId: String) {
        delegate?.terminalManagerDidCompletePayment(self, paymentIntentId: paymentIntentId)
    }
}

// MARK: - Barcode Scanner Mock
final class MockBarcodeScannerService: BarcodeScannerServiceProtocol {
    weak var delegate: BarcodeScannerDelegate?
    var startCalled = false
    var stopCalled = false
    
    func startListening() {
        startCalled = true
    }
    
    func stopListening() {
        stopCalled = true
    }
}

// MARK: - POS View Model Tests
@MainActor
final class POSViewModelTests: XCTestCase {
    private var apiClient: MockBackendAPIClient!
    private var terminalManager: MockStripeTerminalManager!
    private var scannerService: MockBarcodeScannerService!
    private var viewModel: POSViewModel!
    
    override func setUp() {
        super.setUp()
        apiClient = MockBackendAPIClient()
        terminalManager = MockStripeTerminalManager()
        scannerService = MockBarcodeScannerService()
        
        viewModel = POSViewModel(
            apiClient: apiClient,
            terminalManager: terminalManager,
            scannerService: scannerService
        )
    }
    
    override func tearDown() {
        viewModel = nil
        apiClient = nil
        terminalManager = nil
        scannerService = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(viewModel.state, .waitingForScan)
        XCTAssertTrue(terminalManager.connectCalled)
        XCTAssertTrue(scannerService.startCalled)
        XCTAssertTrue(viewModel.readerConnected)
    }
    
    func testBarcodeScannedAddsItemToCart() async {
        let expectation = XCTestExpectation(description: "Fetch item from worker")
        
        // Scan item
        viewModel.handleBarcodeScanned("TOY001")
        
        // Wait briefly for Task to execute
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(
                self.viewModel.state,
                .cartActive(
                    items: [
                        POSInventoryItem(
                            barcode: "TOY001",
                            name: "Fire Truck",
                            priceCents: 500,
                            imageUrl: URL(string: "https://example.com/photo.jpg")!
                        )
                    ],
                    totalCents: 500
                )
            )
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testRemoveItemFromCart() async {
        let expectation = XCTestExpectation(description: "Remove item from cart")
        
        viewModel.handleBarcodeScanned("TOY001")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Remove the added item
            self.viewModel.removeItem(at: 0)
            XCTAssertEqual(self.viewModel.state, .waitingForScan)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testCheckoutFlowSuccess() async {
        let expectation = XCTestExpectation(description: "E2E Checkout flow completes successfully")
        
        viewModel.handleBarcodeScanned("TOY001")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Trigger pay button tap
            self.viewModel.startCheckout()
            XCTAssertEqual(self.viewModel.state, .readerSyncing)
            
            // Wait for PaymentIntent generation on backend
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertEqual(self.viewModel.state, .awaitingCardTap)
                XCTAssertTrue(self.terminalManager.collectPaymentCalled)
                
                // Simulate card tap and authorization on terminal
                self.terminalManager.simulatePaymentSuccess(paymentIntentId: "pi_123")
                XCTAssertEqual(self.viewModel.state, .processingPayment)
                
                // Wait for backend capture completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard case .celebrating(let items) = self.viewModel.state else {
                        XCTFail("State is not celebrating")
                        return
                    }
                    XCTAssertEqual(items.count, 1)
                    XCTAssertEqual(items.first?.barcode, "TOY001")
                    
                    // Reset POS back to waiting for scan
                    self.viewModel.resetPOS()
                    XCTAssertEqual(self.viewModel.state, .waitingForScan)
                    
                    expectation.fulfill()
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testUnknownBarcodeShowsFriendlyItemNotFound() async {
        let expectation = XCTestExpectation(description: "Unknown barcode shows item not found state")
        
        // A random/unrecognized barcode should surface the friendly item-not-found
        // state, NOT the scary generic error state.
        apiClient.fetchItemResult = .failure(BackendAPIError.badResponse(statusCode: 404))
        viewModel.handleBarcodeScanned("RANDOM123")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.state, .itemNotFound(barcode: "RANDOM123"))
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testRealFailureStillShowsErrorState() async {
        let expectation = XCTestExpectation(description: "Non-404 failures still show error state")
        
        // A genuine backend failure (e.g. 500) must remain a real error,
        // not be disguised as "item not found".
        apiClient.fetchItemResult = .failure(BackendAPIError.badResponse(statusCode: 500))
        viewModel.handleBarcodeScanned("TOY001")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard case .error = self.viewModel.state else {
                XCTFail("State is not error")
                expectation.fulfill()
                return
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testDismissErrorReturnsToCart() async {
        let expectation = XCTestExpectation(description: "Error dismissal returns to cart")
        
        viewModel.handleBarcodeScanned("TOY001")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Force the reader-sync (PaymentIntent) step to fail
            self.apiClient.createPIResult = .failure(BackendAPIError.badResponse(statusCode: 500))
            self.viewModel.startCheckout()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard case .error = self.viewModel.state else {
                XCTFail("State is not error")
                expectation.fulfill()
                return
            }
            
            // Dismissing the error should return to the cart, not the landing page
            self.viewModel.dismissError()
            guard case .cartActive(let items, let totalCents) = self.viewModel.state else {
                XCTFail("State is not cartActive after dismiss")
                expectation.fulfill()
                return
            }
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.barcode, "TOY001")
            XCTAssertEqual(totalCents, 500)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testScannerPreservesHyphenatedBarcode() {
        // Regression: generated barcodes contain hyphens (e.g.
        // "TOY-ALPHABET-SOUP-001"). The scanner sanitization must NOT strip
        // them, or the app looks up "TOYALPHABETSOUP001" and surfaces
        // "Item not found" even though the item exists in inventory.
        XCTAssertEqual(
            BarcodeScannerService.sanitizedBarcode("TOY-ALPHABET-SOUP-001"),
            "TOY-ALPHABET-SOUP-001"
        )
        
        // Plain alphanumeric codes are unaffected.
        XCTAssertEqual(BarcodeScannerService.sanitizedBarcode("TOY001"), "TOY001")
        XCTAssertEqual(BarcodeScannerService.sanitizedBarcode("036000291452"), "036000291452")
        
        // Control characters and whitespace are still stripped.
        XCTAssertEqual(BarcodeScannerService.sanitizedBarcode("TOY\u{0}001 "), "TOY001")
    }
    
    func testCancelCheckoutReturnsToCart() async {
        let expectation = XCTestExpectation(description: "Cancel returns to basket")
        
        viewModel.handleBarcodeScanned("TOY001")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.viewModel.startCheckout()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Cancel the sync — should return to the basket, not the landing page.
            self.viewModel.cancelCheckout()
            
            XCTAssertTrue(self.terminalManager.cancelPaymentCalled)
            guard case .cartActive(let items, let totalCents) = self.viewModel.state else {
                XCTFail("State is not cartActive after cancel")
                expectation.fulfill()
                return
            }
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?.barcode, "TOY001")
            XCTAssertEqual(totalCents, 500)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
