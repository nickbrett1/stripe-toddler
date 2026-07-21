import SwiftUI

struct WaitingForScanView: View {
    @State private var pulse = false
    
    var body: some View {
        VStack(spacing: ToddlerLayout.gridUnit * 4) {
            Spacer()
            
            // Empty basket state: display cart.badge.plus SF Symbol (Rule 9.2)
            Image(systemName: "cart.badge.plus")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .foregroundColor(.toddlerBlue)
                .scaleEffect(pulse ? 1.08 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear {
                    pulse = true
                }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.toddlerBackground)
    }
}

struct WaitingForScanView_Previews: PreviewProvider {
    static var previews: some View {
        WaitingForScanView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
