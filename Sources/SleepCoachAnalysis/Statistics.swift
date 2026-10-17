import Foundation

enum Statistics {
    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func stddev(_ values: [Double]) -> Double? {
        guard values.count >= 2, let mu = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mu) * ($1 - mu) } / Double(values.count)
        return variance.squareRoot()
    }

    static func coefficientOfVariation(_ values: [Double]) -> Double? {
        guard let mu = mean(values), mu != 0, let sd = stddev(values) else { return nil }
        return sd / mu
    }

    static func clamp(_ value: Double, min minV: Double = 0, max maxV: Double = 100) -> Double {
        Swift.min(maxV, Swift.max(minV, value))
    }

    /// Linear interpolation: `value` at `start` → 100, at `end` → `endScore`.
    static func lerpScore(value: Double, fullUntil: Double, zeroAt: Double) -> Double {
        if value <= fullUntil { return 100 }
        if value >= zeroAt { return 0 }
        let t = (value - fullUntil) / (zeroAt - fullUntil)
        return clamp(100 * (1 - t))
    }

    /// Peak at `ideal`, full score between `lowFull` and `highFull`, 0 at `lowZero`/`highZero`.
    static func bandScore(
        _ value: Double,
        lowZero: Double,
        lowFull: Double,
        highFull: Double,
        highZero: Double
    ) -> Double {
        if value < lowZero { return 0 }
        if value < lowFull {
            return 100 * (value - lowZero) / (lowFull - lowZero)
        }
        if value <= highFull { return 100 }
        if value < highZero {
            return 100 * (highZero - value) / (highZero - highFull)
        }
        return 0
    }
}
