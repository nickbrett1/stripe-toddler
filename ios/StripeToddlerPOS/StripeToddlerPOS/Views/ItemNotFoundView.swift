import SwiftUI

/// Friendly "we don't carry that barcode" overlay.
///
/// Deliberately separate from `ErrorView`: scanning a barcode that isn't in
/// inventory (e.g. a random barcode) is an expected, recoverable moment — not a
/// hardware/system failure. The scanned value is shown in full, never clipped
/// by surrounding text, and is selectable so the cashier can read or copy it.
struct ItemNotFoundView: View {
    let barcode: String
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Same semi-opaque dark overlay as ErrorView
            Color.black.opacity(0.90)
                .ignoresSafeArea()
            
            VStack(spacing: ToddlerLayout.gridUnit * 4) {
                Spacer()
                
                // Friendly "searching" icon (amber, not red — this isn't a failure)
                Image(systemName: "magnifyingglass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .foregroundColor(.toddlerYellow)
                
                // Friendly title and guidance
                VStack(spacing: ToddlerLayout.gridUnit * 2) {
                    Text("Hmm, we don't sell that!")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("That barcode isn't in our toy shop. Try scanning the tag on a toy again.")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 6)
                
                // The scanned value — shown in full (scales to fit, never truncates),
                // and selectable so it can be copied for troubleshooting.
                VStack(spacing: ToddlerLayout.gridUnit) {
                    Text("You scanned")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.6))
                    
                    Text(barcode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .allowsTightening(true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, ToddlerLayout.gridUnit * 4)
                        .padding(.vertical, ToddlerLayout.gridUnit * 2)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(ToddlerLayout.cornerRadiusCard)
                }
                .padding(.horizontal, ToddlerLayout.gridUnit * 6)
                
                Spacer()
                
                // Dismiss button
                Button(action: onDismiss) {
                    HStack(spacing: ToddlerLayout.gridUnit * 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                        Text("Okay")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, ToddlerLayout.gridUnit * 8)
                    .frame(height: 90)
                    .background(Color.toddlerGreen)
                    .cornerRadius(ToddlerLayout.cornerRadiusButton)
                }
                .buttonStyle(ToddlerButtonStyle())
            }
            .padding(.bottom, ToddlerLayout.gridUnit * 6)
        }
    }
}

struct ItemNotFoundView_Previews: PreviewProvider {
    static var previews: some View {
        ItemNotFoundView(barcode: "036000291452") {}
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
