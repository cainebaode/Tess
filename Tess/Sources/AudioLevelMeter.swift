import Foundation

/// Recent microphone amplitude, not PCM waveform or a generated animation.
struct AudioLevelMeter {
  private(set) var level: Float = 0
  private(set) var history = [Float](repeating: 0, count: 32)
  private(set) var quietDuration: TimeInterval = 0

  mutating func update(rms: Float, interval: TimeInterval) {
    let finite = rms.isFinite ? max(0, rms) : 0
    let db = 20 * log10(max(finite, 0.00001))
    let normalized = max(0, min(1, (db + 50) / 38))
    let coefficient: Float = normalized > level ? 0.7 : Float(1 - exp(-interval / 0.18))
    level += (normalized - level) * coefficient
    if level < 0.002 { level = 0 }
    history.removeFirst()
    history.append(level)
    quietDuration = finite < 0.006 ? quietDuration + interval : 0
  }
}
