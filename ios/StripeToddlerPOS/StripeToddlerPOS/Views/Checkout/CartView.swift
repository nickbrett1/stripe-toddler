import SwiftUI

struct CartView: View {
    let items: [POSInventoryItem]
    let totalCents: Int
    var showTestModeButtons: Bool = false
    var onAddTestItem: ((String) -> Void)? = nil
    let onRemoveItem: (Int) -> Void
    let onCheckout: () -> Void
    let onReset: () -> Void
    
    /// Item count from the previous render — used to detect that a new item was
    /// scanned so we can auto-scroll it into view.
    @State private var previousItemCount = 0
    
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
                    
                    Button(action: { onAddTestItem("TOY-TUNA-FISH-001") }) {
                        Label("+ Tuna Fish", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.toddlerBlue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                    
                    Button(action: { onAddTestItem("TOY-ALPHABET-SOUP-001") }) {
                        Label("+ Alphabet Soup", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.toddlerGreen)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .buttonStyle(ToddlerButtonStyle())
                    
                    Button(action: { onAddTestItem("TOY-SLICED-PEACHES-001") }) {
                        Label("+ Sliced Peaches", systemImage: "plus.circle.fill")
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
                        onAddTestItem("TOY-TUNA-FISH-001")
                        onAddTestItem("TOY-ALPHABET-SOUP-001")
                        onAddTestItem("TOY-CORN-001")
                        onAddTestItem("TOY-GREEN-BEANS-001")
                    }) {
                        Label("+ Add 4 Sample Items", systemImage: "sparkles")
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

            // YouTube Kids-style 2-column visual grid of large item tiles.
            // ScrollViewReader enables auto-scrolling so the most recently
            // scanned item is always brought into view.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: ToddlerLayout.gridUnit * 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            ItemCardView(item: item) {
                                onRemoveItem(index)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                    .padding(.top, ToddlerLayout.gridUnit * 4)
                    .padding(.bottom, ToddlerLayout.gridUnit * 4)
                }
                .onChange(of: items.count) { newCount in
                    // Scanning appends the new item to the end of the grid —
                    // scroll it into view instead of leaving it below the fold.
                    // (Single-parameter onChange keeps iOS 16 compatibility.)
                    if newCount > previousItemCount {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                    previousItemCount = newCount
                }
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
