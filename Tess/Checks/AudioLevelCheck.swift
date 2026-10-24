import Foundation

@main struct AudioLevelCheck {
    static func main() {
        var meter = AudioLevelMeter()
        for _ in 0..<20 { meter.update(rms: 0, interval: 0.08) }
        precondition(meter.level == 0 && meter.history.allSatisfy { $0 == 0 })
        precondition(abs(meter.quietDuration - 1.6) < 0.0001)

        meter.update(rms: 0.1, interval: 0.08)
        let peak = meter.level
        precondition(peak > 0.5 && peak <= 1 && meter.quietDuration == 0)
        meter.update(rms: 0, interval: 0.08)
        precondition(meter.level > 0 && meter.level < peak)
        precondition(meter.history.suffix(2).first == peak)

        var previous = meter.level
        for _ in 0..<32 {
            meter.update(rms: 0, interval: 0.08)
            precondition(meter.level <= previous && meter.history.count == 32)
            previous = meter.level
        }
        precondition(meter.level == 0 && meter.history.last == 0)
        for input in [Float.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude] {
            meter.update(rms: input, interval: 0.08)
            precondition(meter.level.isFinite && (0...1).contains(meter.level))
            precondition(meter.history.count == 32 && meter.history.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
        // A new recording begins without residual amplitude from its predecessor.
        meter = AudioLevelMeter()
        precondition(meter.level == 0 && meter.quietDuration == 0 && meter.history.allSatisfy { $0 == 0 })
        print("Audio level checks passed: real-signal mapping, silence, bounded history, attack/decay, non-finite input and session reset. No microphone used.")
    }
}
