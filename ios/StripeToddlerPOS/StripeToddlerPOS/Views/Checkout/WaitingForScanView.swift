import SwiftUI

struct WaitingForScanView: View {
    var showTestModeButtons: Bool = false
    var onScanBarcode: ((String) -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                // Top Headline Banner for Toddler
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.toddlerYellow)
                    
                    Text("Ready to Scan!")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.toddlerText)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.toddlerYellow)
                }
                .padding(.top, 16)
                
                // Massive Hero Tera Scanner Image
                Image("ScannerHero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height * (showTestModeButtons ? 0.68 : 0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 36))
                    .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 12)
                    .padding(.horizontal, 32)
                
                // Quick Test Barcode Tap Buttons (Only visible if Test Mode toggle is ON)
                if showTestModeButtons, let onScanBarcode = onScanBarcode {
                    HStack(spacing: 24) {
                        Button(action: { onScanBarcode("TOY001") }) {
                            HStack(spacing: 12) {
                                Image(systemName: "barcode")
                                    .font(.system(size: 26, weight: .bold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Fire Truck ($5)")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                    Text("Barcode: TOY001")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .opacity(0.85)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                            .background(Color.toddlerBlue)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                            .shadow(color: Color.toddlerBlue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        
                        Button(action: { onScanBarcode("TOY002") }) {
                            HStack(spacing: 12) {
                                Image(systemName: "barcode")
                                    .font(.system(size: 26, weight: .bold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Blocks ($12.50)")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                    Text("Barcode: TOY002")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .opacity(0.85)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                            .background(Color.toddlerGreen)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                            .shadow(color: Color.toddlerGreen.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        
                        Button(action: { onScanBarcode("TOY003") }) {
                            HStack(spacing: 12) {
                                Image(systemName: "barcode")
                                    .font(.system(size: 26, weight: .bold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Teddy Bear ($8)")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                    Text("Barcode: TOY003")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .opacity(0.85)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                            .background(Color(hex: "#8B5CF6"))
                            .foregroundColor(.white)
                            .cornerRadius(22)
                            .shadow(color: Color(hex: "#8B5CF6").opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
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
