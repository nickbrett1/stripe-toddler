import SwiftUI

struct CheckoutView: View {
    @ObservedObject var viewModel: POSViewModel
    @State private var showAdminSettings = false
    
    var body: some View {
        ZStack {
            // Main Content Layout
            VStack(spacing: 0) {
                // Top Bar (Rule 5.2: 88pt height bar)
                HStack(spacing: ToddlerLayout.gridUnit * 3) {
                    // Total display in large title style (Rule 6.1: 34pt black)
                    Text(formatPrice(getCartTotal()))
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(.toddlerText)
                    
                    Spacer()
                    
                    // Hardware Status Indicators (Rule 1.3: 120pt target)
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        // Scanner status
                        Image(systemName: viewModel.scannerConnected ? "barcode.viewfinder" : "barcode.viewfinder")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .foregroundColor(viewModel.scannerConnected ? .toddlerGreen : .toddlerDisabledText)
                            .frame(width: 80, height: 80)
                        
                        // Reader status
                        Image(systemName: viewModel.readerConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .foregroundColor(viewModel.readerConnected ? .toddlerGreen : .toddlerDisabledText)
                            .frame(width: 80, height: 80)
                    }
                    
                    // Admin settings button (Rule 2.2 gearshape.fill, 120pt target)
                    Button(action: { showAdminSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .foregroundColor(.toddlerTextSecondary)
                            .frame(width: ToddlerLayout.minTouchTarget, height: ToddlerLayout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ToddlerButtonStyle())
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                .frame(height: 88)
                .background(Color.toddlerSurface)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                
                // Active workspace layout
                switch viewModel.state {
                case .waitingForScan:
                    WaitingForScanView()
                    
                case .cartActive(let items, let totalCents):
                    CartView(
                        items: items,
                        totalCents: totalCents,
                        onRemoveItem: { index in
                            viewModel.removeItem(at: index)
                        },
                        onCheckout: {
                            viewModel.startCheckout()
                        },
                        onReset: {
                            viewModel.resetPOS()
                        }
                    )
                    
                case .readerSyncing, .awaitingCardTap, .processingPayment:
                    // Render the cart background under the payment overlay
                    CartView(
                        items: getCartItems(),
                        totalCents: getCartTotal(),
                        onRemoveItem: { _ in },
                        onCheckout: {},
                        onReset: {}
                    )
                    .disabled(true)
                    
                case .celebrating(let itemsSold):
                    WaitingForScanView()
                        .disabled(true)
                    
                case .error:
                    WaitingForScanView()
                        .disabled(true)
                }
            }
            .background(Color.toddlerBackground)
            
            // Payment Overlay
            if isCheckoutState(viewModel.state) {
                PaymentPromptView(state: viewModel.state) {
                    viewModel.resetPOS()
                }
                .transition(.opacity)
            }
            
            // Celebration Overlay (Rule 4.3 / Phase 3 Step 3.9)
            if case .celebrating(let itemsSold) = viewModel.state {
                CelebrationView(itemsSold: itemsSold) {
                    viewModel.resetPOS()
                }
                .transition(.opacity)
            }
            
            // Error Overlay (Rule 9.1 / Phase 3 Step 3.10)
            if case .error(let message) = viewModel.state {
                ErrorView(message: message) {
                    viewModel.resetPOS()
                }
                .transition(.opacity)
            }
        }
        .fontDesign(.rounded) // Rule 6.2 Rounded family locking
        .sheet(isPresented: $showAdminSettings) {
            AdminSettingsView(viewModel: viewModel)
        }
    }
    
    // MARK: - Helpers
    private func getCartTotal() -> Int {
        if case .cartActive(_, let total) = viewModel.state {
            return total
        }
        return 0
    }
    
    private func getCartItems() -> [POSInventoryItem] {
        if case .cartActive(let items, _) = viewModel.state {
            return items
        }
        return []
    }
    
    private func isCheckoutState(_ state: POSFlowState) -> Bool {
        switch state {
        case .readerSyncing, .awaitingCardTap, .processingPayment:
            return true
        default:
            return false
        }
    }
    
    private func formatPrice(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }
}

// Dummy Admin settings panel for simulation / testing barcode injection
struct AdminSettingsView: View {
    @ObservedObject var viewModel: POSViewModel
    @Environment(\.dismiss) var dismiss
    @State private var barcodeInput = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Simulated Scan Input")) {
                    TextField("Enter Barcode (e.g. TOY001)", text: $barcodeInput)
                        .keyboardType(.asciiCapable)
                    
                    Button("Trigger Scan") {
                        if !barcodeInput.isEmpty {
                            viewModel.handleBarcodeScanned(barcodeInput)
                            dismiss()
                        }
                    }
                    .disabled(barcodeInput.isEmpty)
                }
            }
            .navigationTitle("Admin Terminal Control")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
}
