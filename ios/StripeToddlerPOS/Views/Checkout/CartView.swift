import SwiftUI

struct CartView: View {
    let items: [POSInventoryItem]
    let totalCents: Int
    let onRemoveItem: (Int) -> Void
    let onCheckout: () -> Void
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable grid of items in the cart
            ScrollView {
                VStack(spacing: ToddlerLayout.targetSpacing) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        ItemCardView(item: item) {
                            onRemoveItem(index)
                        }
                    }
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                .padding(.top, ToddlerLayout.gridUnit * 3)
                .padding(.bottom, ToddlerLayout.gridUnit * 3)
            }
            
            // Bottom Action Bar: 160pt height containing Pay and Reset CTAs (Rule 5.2)
            HStack(spacing: ToddlerLayout.targetSpacing) {
                // Clear Cart / Cancel button (Rule 2.2 destructive, Rule 3.3)
                Button(action: onReset) {
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                        Text("Reset")
                            .font(.system(size: 18, weight: .bold)) // Rule 2.4 supplement
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.toddlerRed)
                    .cornerRadius(ToddlerLayout.cornerRadiusButton)
                }
                .buttonStyle(ToddlerButtonStyle())
                .frame(height: 120) // Touch target minimum height
                
                // Confirm Payment button (Rule 2.2 confirm, Rule 3.3)
                Button(action: onCheckout) {
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                        Text("Pay")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.toddlerGreen)
                    .cornerRadius(ToddlerLayout.cornerRadiusButton)
                }
                .buttonStyle(ToddlerButtonStyle())
                .frame(height: 120)
            }
            .padding(.horizontal, ToddlerLayout.gridUnit * 4)
            .frame(height: 160) // Bottom bar height
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
