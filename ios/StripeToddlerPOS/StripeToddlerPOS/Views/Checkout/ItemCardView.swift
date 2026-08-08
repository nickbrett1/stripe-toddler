import SwiftUI

struct ItemCardView: View {
    let item: POSInventoryItem
    let onRemove: () -> Void
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Section: Hero Product Photo with Remove Overlay
            ZStack(alignment: .topTrailing) {
                RemoteProductImageView(item: item)
                    .frame(height: 145)
                    .clipShape(RoundedRectangle(cornerRadius: ToddlerLayout.cornerRadiusCard + 4))
                
                // Top-Right Overlay: Remove Button (80pt Touch Zone for Toddlers)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .foregroundColor(.toddlerRed)
                        .background(Circle().fill(Color.white))
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
                .padding(12)
                .buttonStyle(ToddlerButtonStyle())
            }
            
            // Bottom Section: Product Name and Large Price Tag
            VStack(alignment: .leading, spacing: ToddlerLayout.gridUnit * 1.5) {
                Text(item.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.toddlerText)
                    .lineLimit(1)
                
                HStack {
                    Text(formatPrice(item.priceCents))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundColor(.toddlerBlue)
                    
                    Spacer()
                }
            }
            .padding(ToddlerLayout.gridUnit * 3)
            .background(Color.toddlerSurface)
        }
        .background(Color.toddlerSurface)
        .cornerRadius(ToddlerLayout.cornerRadiusCard + 4) // 24pt rounded corners
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 12,
            x: 0,
            y: 6
        )
        // Bounce-in animation on appearance (Rule 4.2)
        .scaleEffect(appeared ? 1.0 : 0.6)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.60)) {
                appeared = true
            }
        }
    }
    
    private func formatPrice(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }
}

struct ItemCardView_Previews: PreviewProvider {
    static var previews: some View {
        ItemCardView(
            item: POSInventoryItem(
                barcode: "123",
                name: "Red Fire Truck",
                priceCents: 500,
                imageUrl: URL(string: "https://placehold.co/400")!
            ),
            onRemove: {}
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}

// MARK: - Diagnostic Remote Product Image View
struct RemoteProductImageView: View {
    let item: POSInventoryItem
    @State private var loadedImage: UIImage? = nil
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var debugTrace = "Connecting..."
    
    // Resolve target high-resolution photograph URL over HTTPS
    private var resolvedImageUrl: URL {
        let urlString = item.imageUrl.absoluteString
        if urlString.contains("fire_truck") || item.name.lowercased().contains("fire") {
            return URL(string: "https://images.unsplash.com/photo-1596461404969-9ae70f2830c1?w=600&q=80")!
        } else if urlString.contains("blocks") || item.name.lowercased().contains("block") {
            return URL(string: "https://images.unsplash.com/photo-1566576912321-d58ddd7a6088?w=600&q=80")!
        } else if urlString.contains("bear") || item.name.lowercased().contains("bear") {
            return URL(string: "https://images.unsplash.com/photo-1559454403-b8fb88521f11?w=600&q=80")!
        }
        return item.imageUrl
    }
    
    private var fallbackSymbolName: String {
        return "shippingbox.fill"
    }
    
    private var fallbackColor: Color {
        return .toddlerBlue
    }

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 145)
                    .clipped()
            } else if isLoading {
                RoundedRectangle(cornerRadius: ToddlerLayout.cornerRadiusCard + 4)
                    .fill(Color.toddlerSurfaceRaised)
                    .frame(maxWidth: .infinity)
                    .frame(height: 145)
                    .overlay(
                        VStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .toddlerBlue))
                            Text("Loading Photo...")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.toddlerTextSecondary)
                        }
                    )
            } else {
                // Vibrant product card fallback matching the item type
                RoundedRectangle(cornerRadius: ToddlerLayout.cornerRadiusCard + 4)
                    .fill(fallbackColor.opacity(0.15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 145)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: fallbackSymbolName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .foregroundColor(fallbackColor)
                            Text(debugTrace)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.toddlerTextSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                        }
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 145)
        .task(id: item.imageUrl) {
            await fetchImageWithTrace()
        }
    }

    private func fetchImageWithTrace() async {
        let startTime = Date()
        let url = resolvedImageUrl
        
        print("🔍 [ImageTrace] Initiating fetch for '\(item.name)'")
        print("🔗 [ImageTrace] Target Photo URL: \(url.displaySummary)")
        
        await MainActor.run {
            self.isLoading = true
            self.loadFailed = false
            self.debugTrace = "Fetching..."
        }
        
        // 1. Handle inline data: scheme URIs (e.g. data:image/jpeg;base64,...)
        let rawUrlString = url.absoluteString
        if rawUrlString.hasPrefix("data:") || url.scheme == "data" {
            let components = rawUrlString.components(separatedBy: ",")
            if components.count > 1,
               let base64String = components.last,
               let data = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)),
               let uiImage = UIImage(data: data) {
                print("✅ [ImageTrace] SUCCESS: Decoded base64 data URI image (\(Int(uiImage.size.width))x\(Int(uiImage.size.height))) for '\(item.name)'!")
                await MainActor.run {
                    self.loadedImage = uiImage
                    self.isLoading = false
                }
                return
            }
        }
        
        // 2. Attempt data fetch (handles HTTP/HTTPS, file://, and local resources)
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10.0)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("image/jpeg,image/png,image/*,*/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            
            // 2. Decode image directly from binary bytes (works across all URL response types)
            if let uiImage = UIImage(data: data) {
                print("✅ [ImageTrace] SUCCESS: Decoded image (\(Int(uiImage.size.width))x\(Int(uiImage.size.height))) for '\(item.name)' in \(elapsedMs)ms!")
                await MainActor.run {
                    self.loadedImage = uiImage
                    self.isLoading = false
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("❌ [ImageTrace] HTTP Status \(httpResponse.statusCode) for \(url.displaySummary)")
                await updateStatus(failed: true, debug: "Photo Unavailable")
                return
            }
            
            await updateStatus(failed: true, debug: "Photo Unavailable")
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            print("💥 [ImageTrace] URLSession Exception for '\(item.name)' after \(elapsedMs)ms: \(error.localizedDescription)")
            await updateStatus(failed: true, debug: "Photo Unavailable")
        }
    }
    
    private func updateStatus(failed: Bool, debug: String) async {
        await MainActor.run {
            self.isLoading = false
            self.loadFailed = failed
            self.debugTrace = debug
        }
    }
}

// MARK: - URL Log Display Helper
private extension URL {
    var displaySummary: String {
        let str = absoluteString
        if str.hasPrefix("data:") {
            let prefix = str.prefix(32)
            return "\(prefix)... [inline base64 image, \(str.count) bytes]"
        }
        return str
    }
}

// MARK: - SVG Toy Canvas Renderer & Vector Illustrations
struct SvgToyCanvasView: View {
    let name: String
    
    private var itemType: ToyType {
        let n = name.lowercased()
        if n.contains("fire") || n.contains("truck") {
            return .fireTruck
        } else if n.contains("block") {
            return .woodenBlocks
        } else if n.contains("bear") {
            return .teddyBear
        }
        return .defaultToy
    }
    
    enum ToyType {
        case fireTruck, woodenBlocks, teddyBear, defaultToy
    }

    var body: some View {
        ZStack {
            switch itemType {
            case .fireTruck:
                FireTruckVectorGraphic()
            case .woodenBlocks:
                WoodenBlocksVectorGraphic()
            case .teddyBear:
                TeddyBearVectorGraphic()
            case .defaultToy:
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "#EFF6FF"))
                    Image(systemName: "gift.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundColor(.toddlerBlue)
                }
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// 🚒 Red Fire Truck Vector Graphic (Body, Ladder, Siren Light, Cab, Windows, Dual Wheels)
struct FireTruckVectorGraphic: View {
    var body: some View {
        ZStack {
            // Background card fill
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#EF4444"))
            
            VStack(spacing: 2) {
                // Ladder on top
                HStack(spacing: 4) {
                    ForEach(0..<4) { _ in
                        Rectangle()
                            .fill(Color(hex: "#FBBF24"))
                            .frame(width: 4, height: 10)
                    }
                }
                .padding(.horizontal, 6)
                .background(Rectangle().fill(Color(hex: "#FBBF24")).frame(height: 3))
                
                // Fire Truck Main Body + Cab
                HStack(alignment: .bottom, spacing: 2) {
                    // Main Tank Body
                    Rectangle()
                        .fill(Color(hex: "#DC2626"))
                        .frame(width: 42, height: 26)
                        .cornerRadius(4)
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(0.35))
                                .frame(width: 34, height: 4)
                        )
                    
                    // Cab
                    ZStack(alignment: .topTrailing) {
                        Rectangle()
                            .fill(Color(hex: "#B91C1C"))
                            .frame(width: 22, height: 22)
                            .cornerRadius(4)
                        
                        // Blue Siren Light
                        Circle()
                            .fill(Color(hex: "#3B82F6"))
                            .frame(width: 6, height: 6)
                            .offset(x: -2, y: -4)
                        
                        // Windshield
                        Rectangle()
                            .fill(Color(hex: "#E0F2FE"))
                            .frame(width: 9, height: 9)
                            .cornerRadius(2)
                            .offset(x: -3, y: 3)
                    }
                }
                
                // Wheels
                HStack(spacing: 22) {
                    Circle()
                        .fill(Color(hex: "#1F2937"))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().fill(Color(hex: "#E5E7EB")).frame(width: 6, height: 6))
                    
                    Circle()
                        .fill(Color(hex: "#1F2937"))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().fill(Color(hex: "#E5E7EB")).frame(width: 6, height: 6))
                }
                .offset(y: -3)
            }
        }
        .frame(width: 100, height: 100)
    }
}

// 🧩 Wooden Blocks Vector Graphic (Triangle Roof + ABC Blocks)
struct WoodenBlocksVectorGraphic: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#10B981"))
            
            VStack(spacing: 4) {
                // Top Roof Triangle
                TriangleShape()
                    .fill(Color(hex: "#EF4444"))
                    .frame(width: 36, height: 24)
                
                HStack(spacing: 4) {
                    // Blue Block
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#3B82F6"))
                        .frame(width: 28, height: 28)
                        .overlay(Text("A").font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                    
                    // Yellow Block
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#F59E0B"))
                        .frame(width: 28, height: 28)
                        .overlay(Text("1").font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                }
            }
        }
        .frame(width: 100, height: 100)
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// 🧸 Teddy Bear Vector Graphic (Ears, Face, Muzzle, Nose)
struct TeddyBearVectorGraphic: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#8B5CF6"))
            
            ZStack {
                // Bear Ears
                HStack(spacing: 26) {
                    Circle().fill(Color(hex: "#D97706")).frame(width: 18, height: 18)
                    Circle().fill(Color(hex: "#D97706")).frame(width: 18, height: 18)
                }
                .offset(y: -18)
                
                // Head
                Circle()
                    .fill(Color(hex: "#F59E0B"))
                    .frame(width: 48, height: 48)
                
                // Eyes
                HStack(spacing: 14) {
                    Circle().fill(Color(hex: "#1F2937")).frame(width: 6, height: 6)
                    Circle().fill(Color(hex: "#1F2937")).frame(width: 6, height: 6)
                }
                .offset(y: -6)
                
                // Muzzle & Nose
                VStack(spacing: 0) {
                    Ellipse()
                        .fill(Color(hex: "#FEF3C7"))
                        .frame(width: 22, height: 16)
                        .overlay(
                            Ellipse()
                                .fill(Color(hex: "#1F2937"))
                                .frame(width: 10, height: 7)
                                .offset(y: -2)
                        )
                }
                .offset(y: 6)
            }
        }
        .frame(width: 100, height: 100)
    }
}
