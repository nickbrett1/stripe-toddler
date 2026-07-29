import SwiftUI

struct WaitingForScanView: View {
    var onScanBarcode: ((String) -> Void)?
    @State private var pulse = false
    
    var body: some View {
        VStack(spacing: ToddlerLayout.gridUnit * 4) {
            Spacer()
            
            VStack(spacing: 24) {
                // Pulsing Cart Icon in glowing card
                ZStack {
                    Circle()
                        .fill(Color.toddlerBlue.opacity(0.12))
                        .frame(width: 180, height: 180)
                        .scaleEffect(pulse ? 1.10 : 0.95)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: pulse
                        )
                    
                    Image(systemName: "cart.badge.plus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .foregroundColor(.toddlerBlue)
                }
                
                VStack(spacing: 8) {
                    Text("Ready to Scan!")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundColor(.toddlerText)
                    
                    Text("Scan a barcode with your scanner or tap a test item below:")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.toddlerTextSecondary)
                }
                
                // Quick Test Barcode Buttons
                if let onScanBarcode = onScanBarcode {
                    HStack(spacing: 16) {
                        Button(action: { onScanBarcode("TOY001") }) {
                            HStack {
                                Image(systemName: "barcode")
                                Text("TOY001 ($5.00)")
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.toddlerBlue)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        
                        Button(action: { onScanBarcode("TOY002") }) {
                            HStack {
                                Image(systemName: "barcode")
                                Text("TOY002 ($12.50)")
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.toddlerGreen)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        
                        Button(action: { onScanBarcode("TOY003") }) {
                            HStack {
                                Image(systemName: "barcode")
                                Text("TOY003 ($8.00)")
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color(hex: "#8B5CF6"))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
            )
            .padding(.horizontal, 40)
            .onAppear {
                pulse = true
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "#EEF2FF"), Color(hex: "#E0E7FF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct WaitingForScanView_Previews: PreviewProvider {
    static var previews: some View {
        WaitingForScanView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
