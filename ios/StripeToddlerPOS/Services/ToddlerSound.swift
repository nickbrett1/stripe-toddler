import AVFoundation

// MARK: - Synthesized Toddler Sound Effects
//
// Tiny AVFoundation-based chime generator — no audio assets required.
//   - playScan():    cheerful two-note "ding-dong" when an item lands in the cart
//   - playSuccess(): rising 4-note victory arpeggio when payment completes
//
// Sounds are synthesized (sine tones with soft attack/release envelopes) so
// they never fail to load and are consistent across devices.
public enum ToddlerSound {
    private static let sampleRate: Double = 44_100

    private static var engine: AVAudioEngine?
    private static var player = AVAudioPlayerNode()
    private static var isConfigured = false

    // MARK: - Public API

    /// True when running under the unit test runner (XCTest). Audio engine
    /// setup can hang or spew noise in tests, so sounds are skipped entirely.
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// Played when a barcode scan successfully adds an item to the cart.
    public static func playScan() {
        play(notes: [(587.33, 0.12), (880.00, 0.22)], gap: 0.04)
    }

    /// Played when a payment completes and the celebration screen appears.
    public static func playSuccess() {
        play(
            notes: [(523.25, 0.14), (659.25, 0.14), (783.99, 0.14), (1046.50, 0.40)],
            gap: 0.02
        )
    }

    // MARK: - Engine Setup

    private static func play(notes: [(freq: Double, duration: Double)], gap: Double) {
        guard !isRunningTests else { return } // never spin up audio in unit tests
        guard configureEngine() else { return }
        let buffer = makeBuffer(notes: notes, gap: gap)
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    @discardableResult
    private static func configureEngine() -> Bool {
        if isConfigured { return true }

        #if os(iOS)
        // .playback so the chimes ring even when the silent switch is on
        // (toddlers + kiosk iPad); .mixWithOthers so we don't kill background audio.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return false
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[ToddlerSound] Failed to start audio engine: \(error.localizedDescription)")
            return false
        }

        self.engine = engine
        self.player = player
        isConfigured = true
        return true
    }

    // MARK: - Buffer Synthesis

    /// Builds a single PCM buffer containing the given notes (with gaps),
    /// each shaped with a quick attack + soft release envelope to avoid clicks.
    private static func makeBuffer(notes: [(freq: Double, duration: Double)], gap: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let totalFrames = notes.reduce(0) { $0 + Int(($1.duration + gap) * sampleRate) }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = buffer.frameCapacity

        let samples = buffer.floatChannelData![0]
        var frame = 0

        for note in notes {
            let noteFrames = Int(note.duration * sampleRate)
            let gapFrames = Int(gap * sampleRate)
            let attackFrames = Int(0.01 * sampleRate)   // 10ms attack
            let releaseFrames = Int(0.06 * sampleRate)  // 60ms release

            for i in 0..<noteFrames {
                let t = Double(i) / sampleRate
                let attack = min(1.0, Double(i) / Double(attackFrames))
                let release = min(1.0, Double(noteFrames - i) / Double(releaseFrames))
                let envelope = attack * release
                let value = sin(2.0 * .pi * note.freq * t) * 0.45 * envelope
                samples[frame] = Float(value)
                frame += 1
            }

            for _ in 0..<gapFrames {
                samples[frame] = 0
                frame += 1
            }
        }

        return buffer
    }
}
