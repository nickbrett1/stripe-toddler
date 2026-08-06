import SwiftUI

// MARK: - Particle State Model
struct CelebrationParticle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var color: Color
    var size: CGFloat
    var alpha: Double = 1.0
}

// MARK: - Fireworks Engine (Zero State Mutations in View Body)
final class FireworksSystem {
    private var particles: [CelebrationParticle] = []
    private var lastUpdateDate: Date? = nil
    private var lastBurstDate: Date = Date()
    
    func updateAndDraw(context: inout GraphicsContext, size: CGSize, date: Date) {
        let delta: Double
        if let lastDate = lastUpdateDate {
            delta = min(date.timeIntervalSince(lastDate), 0.05)
        } else {
            delta = 1.0 / 60.0
            spawnInitialExplosions(size: size)
        }
        lastUpdateDate = date
        
        // Continuously launch firework bursts every 0.4 seconds for toddlers
        if date.timeIntervalSince(lastBurstDate) > 0.4 {
            lastBurstDate = date
            let w = size.width > 0 ? size.width : UIScreen.main.bounds.width
            let h = size.height > 0 ? size.height : UIScreen.main.bounds.height
            let randomX = Double.random(in: (w * 0.15)...(w * 0.85))
            let randomY = Double.random(in: (h * 0.15)...(h * 0.45))
            spawnBurst(x: randomX, y: randomY)
        }
        
        // Time-delta normalized physics update (60fps baseline)
        let timeScale = delta * 60.0
        var index = 0
        while index < particles.count {
            particles[index].x += particles[index].vx * timeScale
            particles[index].y += particles[index].vy * timeScale
            particles[index].vy += 0.08 * timeScale // Gravity
            particles[index].alpha -= 0.006 * timeScale // Fade out
            
            if particles[index].alpha <= 0 {
                particles.remove(at: index)
            } else {
                let p = particles[index]
                var pContext = context
                pContext.opacity = p.alpha
                let rect = CGRect(
                    x: p.x - p.size / 2,
                    y: p.y - p.size / 2,
                    width: p.size,
                    height: p.size
                )
                pContext.fill(Path(ellipseIn: rect), with: .color(p.color))
                index += 1
            }
        }
    }
    
    private func spawnInitialExplosions(size: CGSize) {
        let w = size.width > 0 ? size.width : UIScreen.main.bounds.width
        let h = size.height > 0 ? size.height : UIScreen.main.bounds.height
        spawnBurst(x: w * 0.25, y: h * 0.3)
        spawnBurst(x: w * 0.50, y: h * 0.25)
        spawnBurst(x: w * 0.75, y: h * 0.3)
    }

    private func spawnBurst(x: Double, y: Double) {
        let colors: [Color] = [.toddlerBlue, .toddlerGreen, .toddlerRed, .toddlerYellow, .purple, .orange, .pink]
        let particleCount = Int.random(in: 35...50)

        for _ in 0..<particleCount {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 2...9)
            particles.append(
                CelebrationParticle(
                    x: x,
                    y: y,
                    vx: cos(angle) * speed,
                    vy: sin(angle) * speed,
                    color: colors.randomElement() ?? .toddlerYellow,
                    size: CGFloat.random(in: 8...22)
                )
            )
        }
    }
}

// MARK: - Continuous Fireworks Particle Effect (TimelineView + Canvas)
struct FireworksEffect: View {
    private let system = FireworksSystem()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                system.updateAndDraw(context: &context, size: size, date: timeline.date)
            }
        }
    }
}
