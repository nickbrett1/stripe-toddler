import AVFoundation

// MARK: - Synthesized Toddler Sound Effects
//
// Tiny AVFoundation-based sound generator — no audio assets required.
//   - playScan():    cheerful two-note "ding-dong" when an item lands in the cart
//   - playSuccess(): a few seconds of Karplus-Strong "guitar" celebration solo
//
// Sounds are synthesized so they never fail to load and are consistent
// across devices. The celebration solo uses plucked-string synthesis
// (Karplus-Strong, 1979): a burst of noise plus a resonant feedback loop
// that decays like a real vibrating string — a convincing guitar voice
// from pure math, no sample files.
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
    /// A ~4-second Karplus-Strong guitar solo in G major: an opening strum,
    /// a rising melodic phrase, a half-step slide, resolving strums, and a
    /// ringing high G to finish.
    public static func playSuccess() {
        playGuitarSolo()
    }

    // MARK: - Sine Chimes (scan)

    private static func play(notes: [(freq: Double, duration: Double)], gap: Double) {
        guard !isRunningTests else { return }
        guard configureEngine() else { return }
        play(buffer: makeBuffer(notes: notes, gap: gap))
    }

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

    // MARK: - Guitar Solo (Karplus-Strong)

    /// One plucked string in the solo mix.
    private struct GuitarString {
        var frequency: Double        // Hz at pluck time
        var startTime: Double        // seconds from the start of the buffer
        var duration: Double         // seconds the string rings
        var velocity: Double = 1.0   // pluck strength 0...1
        var slideTo: Double? = nil   // optional smooth pitch bend target (Hz)
        var vibrato: Bool = false    // gentle 6 Hz wobble on held notes
    }

    private static func playGuitarSolo() {
        guard !isRunningTests else { return }
        guard configureEngine() else { return }

        // The composition: strums plus a few seconds of happy melody in G major.
        let strings: [GuitarString] = [
            // --- Opening strum: G major, low to high ---
            GuitarString(frequency: 196.00, startTime: 0.00, duration: 1.00, velocity: 0.90),  // G3
            GuitarString(frequency: 246.94, startTime: 0.02, duration: 1.00, velocity: 0.90),  // B3
            GuitarString(frequency: 293.66, startTime: 0.04, duration: 1.00, velocity: 0.90),  // D4
            GuitarString(frequency: 392.00, startTime: 0.06, duration: 1.00, velocity: 0.85),  // G4

            // --- Rising phrase: B4, D5, then a long ringing G5 ---
            GuitarString(frequency: 493.88, startTime: 0.40, duration: 0.28, velocity: 0.85),  // B4
            GuitarString(frequency: 587.33, startTime: 0.62, duration: 0.28, velocity: 0.85),  // D5
            GuitarString(frequency: 783.99, startTime: 0.84, duration: 0.95, velocity: 0.80, vibrato: true), // G5 held

            // --- Descending turn with a half-step slide up (F#5 -> G5) ---
            GuitarString(frequency: 739.99, startTime: 1.82, duration: 0.30, velocity: 0.85, slideTo: 783.99), // F#5 -> G5
            GuitarString(frequency: 659.26, startTime: 2.10, duration: 0.22, velocity: 0.80),  // E5
            GuitarString(frequency: 523.25, startTime: 2.28, duration: 0.22, velocity: 0.80),  // C5
            GuitarString(frequency: 587.33, startTime: 2.46, duration: 0.26, velocity: 0.85),  // D5
            GuitarString(frequency: 493.88, startTime: 2.70, duration: 0.30, velocity: 0.85),  // B4

            // --- Resolution: quick C major, then G major strum ---
            GuitarString(frequency: 261.63, startTime: 3.00, duration: 0.50, velocity: 0.85),  // C4
            GuitarString(frequency: 329.63, startTime: 3.02, duration: 0.50, velocity: 0.85),  // E4
            GuitarString(frequency: 392.00, startTime: 3.04, duration: 0.50, velocity: 0.80),  // G4
            GuitarString(frequency: 196.00, startTime: 3.42, duration: 0.80, velocity: 0.90),  // G3
            GuitarString(frequency: 246.94, startTime: 3.44, duration: 0.80, velocity: 0.90),  // B3
            GuitarString(frequency: 293.66, startTime: 3.46, duration: 0.80, velocity: 0.90),  // D4
            GuitarString(frequency: 392.00, startTime: 3.48, duration: 0.80, velocity: 0.85),  // G4

            // --- Final ringing high G over the chord ---
            GuitarString(frequency: 783.99, startTime: 3.60, duration: 0.75, velocity: 0.85, vibrato: true), // G5
        ]

        play(buffer: makeGuitarSoloBuffer(strings: strings))
    }

    /// Renders every plucked string into one normalized PCM buffer.
    private static func makeGuitarSoloBuffer(strings: [GuitarString]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let totalDuration = strings.map { $0.startTime + $0.duration }.max() ?? 1.0
        let totalFrames = Int(totalDuration * sampleRate) + 1
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = buffer.frameCapacity

        var samples = [Float](repeating: 0, count: totalFrames)
        for string in strings {
            renderPluckedString(into: &samples, string: string)
        }

        // Normalize so several ringing strings never clip the mix.
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 0.8 {
            let gain = 0.8 / peak
            for i in 0..<samples.count { samples[i] *= gain }
        }

        samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
        }
        return buffer
    }

    /// Karplus-Strong plucked string, mixed into `samples` at its start time.
    ///
    /// A string is a circular delay line seeded with one period of noise (the
    /// pluck). Each new sample is the average of two samples one period back,
    /// scaled by a decay factor — the string vibrates and loses energy exactly
    /// like a real plucked string. Slides and vibrato are just smooth changes
    /// to the delay length (pitch).
    private static func renderPluckedString(into samples: inout [Float], string: GuitarString) {
        let startFrame = Int(string.startTime * sampleRate)
        let totalFrames = Int(string.duration * sampleRate)
        guard startFrame < samples.count, totalFrames > 0 else { return }

        // String length in samples = one period at the pluck frequency.
        var basePeriod = sampleRate / string.frequency
        let targetPeriod = string.slideTo.map { sampleRate / $0 }
        let maxPeriod = Int(max(basePeriod, targetPeriod ?? basePeriod)) + 4

        // Decay per round-trip (one period): 0.996 keeps a note ringing for
        // roughly a second, like real string friction.
        let decayPerPeriod = 0.996
        let vibratoRate = 6.0
        let vibratoDepth = 0.006  // ±0.6% pitch wobble

        var delay = [Float](repeating: 0, count: maxPeriod)
        var idx = 0

        // Excitation: one period of noise = the "pluck".
        for _ in 0..<Int(basePeriod) {
            delay[idx] = Float.random(in: -1...1) * Float(string.velocity)
            idx = (idx + 1) % delay.count
        }

        for i in 0..<totalFrames {
            // Smooth slide: ease the base period toward the target.
            if let target = targetPeriod {
                basePeriod += (target - basePeriod) * 0.0008
            }

            // Gentle vibrato on held notes (modulates around the base period,
            // so the pitch never drifts over time).
            var period = basePeriod
            if string.vibrato {
                let t = Double(i) / sampleRate
                period *= 1.0 + vibratoDepth * sin(2.0 * .pi * vibratoRate * t)
            }

            let p = max(2, Int(period.rounded()))
            let perSampleDecay = pow(decayPerPeriod, 1.0 / Double(p))

            let a = (idx - p + delay.count) % delay.count
            let b = (a - 1 + delay.count) % delay.count
            let value = Float(perSampleDecay) * 0.5 * (delay[a] + delay[b])

            delay[idx] = value
            let out = startFrame + i
            if out < samples.count {
                samples[out] += value * 0.25
            }
            idx = (idx + 1) % delay.count
        }
    }

    // MARK: - Engine Setup

    private static func play(buffer: AVAudioPCMBuffer) {
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
}
