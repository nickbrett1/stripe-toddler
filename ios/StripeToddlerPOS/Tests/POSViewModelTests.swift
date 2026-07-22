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
}
