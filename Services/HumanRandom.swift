import Foundation

/// Random timing jitter using a log-normal distribution.
/// Produces right-skewed values: most near the median, occasional longer outliers —
/// matching real human reaction time distributions.
func humanRandom(median: Double, spread: Double = 0.3) -> Double {
    // Box-Muller transform for normal distribution
    let u1 = Double.random(in: 0.0001...0.9999)
    let u2 = Double.random(in: 0.0001...0.9999)
    let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)

    // Log-normal: median is exp(mu), spread controls variance
    let mu = log(median)
    let value = exp(mu + spread * z)

    // Clamp to reasonable bounds (0.5x to 3x median)
    return max(median * 0.5, min(median * 3.0, value))
}

/// Clamped random timing convenience for callers that need hard bounds.
func humanRandom(median: Double, spread: Double = 0.3, min minVal: Double, max maxVal: Double) -> Double {
    let value = humanRandom(median: median, spread: spread)
    return max(minVal, min(maxVal, value))
}
