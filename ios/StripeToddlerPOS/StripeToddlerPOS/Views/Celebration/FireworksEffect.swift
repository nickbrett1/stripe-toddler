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

// MARK: - Fireworks Particle Effect (TimelineView + Canvas)
struct FireworksEffect: View {
    @State private var particles: [CelebrationParticle] = []
    @State private var timerActive = true
    
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
                guard timerActive else { return }
                updateParticles()
            }
        }
    }
    
    private func spawnInitialExplosions() {
        // Spawn multiple firework bursts across the screen width
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        spawnBurst(x: screenWidth / 4, y: screenHeight / 3)
        spawnBurst(x: screenWidth / 2, y: screenHeight / 4)
        spawnBurst(x: (screenWidth / 4) * 3, y: screenHeight / 3)
    }
    
    private func spawnBurst(x: CGFloat, y: CGFloat) {
        let colors: [Color] = [.toddlerBlue, .toddlerGreen, .toddlerRed, .toddlerYellow]
        for _ in 0..<40 {
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 3...12)
            particles.append(
                CelebrationParticle(
                    x: Double(x),
                    y: Double(y),
                    vx: cos(angle) * speed,
                    vy: sin(angle) * speed,
                    color: colors.randomElement() ?? .toddlerBlue,
                    size: CGFloat.random(in: 8...16)
                )
            )
        }
    }
    
    private func updateParticles() {
        for i in 0..<particles.count {
            particles[i].x += particles[i].vx
            particles[i].y += particles[i].vy
            particles[i].vy += 0.15 // Gravity force pulling down
            particles[i].alpha -= 0.012 // Fade out over time
        }
        
        // Prune faded particles to conserve rendering cycles
        particles.removeAll { $0.alpha <= 0 }
        
        if particles.isEmpty {
            timerActive = false
        }
    }
}
