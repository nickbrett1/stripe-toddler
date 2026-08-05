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

// MARK: - Continuous Fireworks Particle Effect (TimelineView + Canvas)
struct FireworksEffect: View {
    @State private var particles: [CelebrationParticle] = []
    @State private var frameCounter = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    var pContext = context
                    pContext.opacity = particle.alpha
                    let rect = CGRect(
                        x: particle.x - particle.size / 2,
                        y: particle.y - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )
                    pContext.fill(Path(ellipseIn: rect), with: .color(particle.color))
                }
            }
            .onAppear {
                spawnInitialExplosions()
            }
            .onChange(of: timeline.date) { _ in
                updateParticles()
            }
        }
    }

    private func spawnInitialExplosions() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        spawnBurst(x: screenWidth * 0.25, y: screenHeight * 0.3)
        spawnBurst(x: screenWidth * 0.50, y: screenHeight * 0.25)
        spawnBurst(x: screenWidth * 0.75, y: screenHeight * 0.3)
    }

    private func spawnBurst(x: CGFloat, y: CGFloat) {
        let colors: [Color] = [.toddlerBlue, .toddlerGreen, .toddlerRed, .toddlerYellow, .purple, .orange, .pink]
        let particleCount = Int.random(in: 35...50)

        for _ in 0..<particleCount {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 2...9)
            particles.append(
                CelebrationParticle(
                    x: Double(x),
                    y: Double(y),
                    vx: cos(angle) * speed,
                    vy: sin(angle) * speed,
                    color: colors.randomElement() ?? .toddlerYellow,
                    size: CGFloat.random(in: 8...22)
                )
            )
        }
    }

    private func updateParticles() {
        frameCounter += 1

        // Continuously launch new firework bursts every 25 frames (~0.4s) for endless toddler fun!
        if frameCounter % 25 == 0 {
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            let randomX = CGFloat.random(in: (screenWidth * 0.15)...(screenWidth * 0.85))
            let randomY = CGFloat.random(in: (screenHeight * 0.15)...(screenHeight * 0.45))
            spawnBurst(x: randomX, y: randomY)
        }

        for i in 0..<particles.count {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vy += 0.08 // Gentle gravity
            particles[i].alpha -= 0.006 // Slow fade so fireworks linger much longer
        }

        // Prune faded particles
        particles.removeAll { $0.alpha <= 0 }
    }
}
