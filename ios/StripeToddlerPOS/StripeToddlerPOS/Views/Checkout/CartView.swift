import SwiftUI

struct CartView: View {
    let items: [POSInventoryItem]
    let totalCents: Int
    var showTestModeButtons: Bool = false
    var onAddTestItem: ((String) -> Void)? = nil
    let onRemoveItem: (Int) -> Void
    let onCheckout: () -> Void
    let onReset: () -> Void
    
    // YouTube Kids 2-column visual grid columns layout
    private let columns = [
        GridItem(.flexible(), spacing: ToddlerLayout.gridUnit * 4),
        GridItem(.flexible(), spacing: ToddlerLayout.gridUnit * 4)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Test Mode Quick-Add Header Bar (Only visible when Test Mode is enabled in Admin settings)
            if showTestModeButtons, let onAddTestItem = onAddTestItem {
                HStack(spacing: ToddlerLayout.gridUnit * 2) {
                    Text("TEST BAR:")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.toddlerTextSecondary)
                    
                    Button(action: { onAddTestItem("TOY001") }) {
                        Label("+ Fire Truck", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.toddlerBlue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                    
                    Button(action: { onAddTestItem("TOY002") }) {
                        Label("+ Blocks", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.toddlerGreen)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                    
                    Button(action: { onAddTestItem("TOY003") }) {
                        Label("+ Teddy Bear", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#8B5CF6"))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                    
                    Spacer()
                    
                    Button(action: {
                        onAddTestItem("TOY001")
                        onAddTestItem("TOY002")
                        onAddTestItem("TOY003")
                        onAddTestItem("TOY001")
                    }) {
                        Label("+ Add 4 Sample Toys", systemImage: "sparkles")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#F97316"))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                .padding(.vertical, ToddlerLayout.gridUnit * 2)
                .background(Color.toddlerSurfaceRaised)
            }
            
            // Keep Scanning visual banner — animated scanner + bouncing arrow
            // (see KeepScanningBanner.swift) — communicates "scan more" to
            // toddlers without relying on words.
            KeepScanningBanner()

            // YouTube Kids-style 2-column visual grid of large item tiles
            ScrollView {
                LazyVGrid(columns: columns, spacing: ToddlerLayout.gridUnit * 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        ItemCardView(item: item) {
                            onRemoveItem(index)
                        }
                    }
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                .padding(.top, ToddlerLayout.gridUnit * 4)
                .padding(.bottom, ToddlerLayout.gridUnit * 4)
            }
            
            // Bottom Action Bar: Streamlined 90pt height containing Pay and Reset CTAs
            HStack(spacing: ToddlerLayout.targetSpacing) {
                // Clear Cart / Cancel button
                Button(action: onReset) {
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("Reset")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.toddlerRed)
                    .cornerRadius(ToddlerLayout.cornerRadiusButton)
                }
                .buttonStyle(ToddlerButtonStyle())
                .frame(height: 74)
                
                // Confirm Payment button
                Button(action: onCheckout) {
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("Pay")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.toddlerGreen)
                    .cornerRadius(ToddlerLayout.cornerRadiusButton)
                }
                .buttonStyle(ToddlerButtonStyle())
                .frame(height: 74)
            }
            .padding(.horizontal, ToddlerLayout.gridUnit * 4)
            .frame(height: 90) // Bottom bar height
            .background(Color.toddlerSurface)
            .shadow(
                color: Color.black.opacity(ToddlerLayout.shadowOpacity),
                radius: ToddlerLayout.shadowRadius,
                x: 0,
                y: -ToddlerLayout.shadowY
            )
        }
        .background(Color.toddlerBackground)
    }
}

struct CartView_Previews: PreviewProvider {
    static var previews: some View {
        CartView(
            items: [
                POSInventoryItem(barcode: "1", name: "Red Fire Truck", priceCents: 500, imageUrl: URL(string: "https://placehold.co/400")!),
                POSInventoryItem(barcode: "2", name: "Yellow Rubber Duck", priceCents: 100, imageUrl: URL(string: "https://placehold.co/400")!)
            ],
            totalCents: 600,
            onRemoveItem: { _ in },
            onCheckout: {},
            onReset: {}
        )
        .previewInterfaceOrientation(.landscapeLeft)
    }
}
