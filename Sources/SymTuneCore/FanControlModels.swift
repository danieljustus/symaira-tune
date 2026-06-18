import Foundation

/// Preset fan profiles that map to specific fan behavior.
public enum FanPreset: String, Codable, Sendable, CaseIterable {
    /// Quiet: minimum fan speed, prioritizing silence.
    case quiet
    /// Auto: let the firmware curve decide (default).
    case auto
    /// Cool: aggressive fan speed for maximum cooling.
    case cool

    public var displayName: String {
        switch self {
        case .quiet: return "Quiet"
        case .auto: return "Auto"
        case .cool: return "Cool"
        }
    }

    /// The fan fraction this preset targets.
    public var fanFraction: Double {
        switch self {
        case .quiet: return 0.15
        case .auto: return 0.5
        case .cool: return 0.85
        }
    }
}

/// A temperature→speed curve point: at `temperatureC`°C, the fan should be
/// at `fraction` (0.0–1.0). Interpolated linearly between points.
public struct FanCurvePoint: Codable, Sendable {
    public let temperatureC: Double
    public let fraction: Double

    public init(temperatureC: Double, fraction: Double) {
        self.temperatureC = temperatureC
        self.fraction = fraction
    }
}

/// Temperature→speed curve for automatic fan control. Defines a set of
/// temperature thresholds with corresponding fan fractions. Between points,
/// the fan fraction is linearly interpolated.
public struct FanCurve: Codable, Sendable {
    public let name: String
    public let points: [FanCurvePoint]

    public init(name: String, points: [FanCurvePoint]) {
        self.name = name
        self.points = points.sorted { $0.temperatureC < $1.temperatureC }
    }

    /// Compute the target fan fraction at the given temperature.
    /// Returns 0.0 if no points exist.
    public func fraction(at temperatureC: Double) -> Double {
        guard !points.isEmpty else { return 0.0 }
        if let first = points.first, temperatureC <= first.temperatureC {
            return first.fraction
        }
        if let last = points.last, temperatureC >= last.temperatureC {
            return last.fraction
        }
        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            if temperatureC >= a.temperatureC && temperatureC <= b.temperatureC {
                let range = b.temperatureC - a.temperatureC
                guard range > 0 else { return a.fraction }
                let t = (temperatureC - a.temperatureC) / range
                return a.fraction + t * (b.fraction - a.fraction)
            }
        }
        return points.last?.fraction ?? 0.0
    }
}

/// Built-in fan curves for common use cases.
extension FanCurve {
    public static let quietCurve = FanCurve(name: "Quiet", points: [
        FanCurvePoint(temperatureC: 40, fraction: 0.10),
        FanCurvePoint(temperatureC: 60, fraction: 0.25),
        FanCurvePoint(temperatureC: 80, fraction: 0.50),
        FanCurvePoint(temperatureC: 95, fraction: 0.75),
    ])

    public static let balancedCurve = FanCurve(name: "Balanced", points: [
        FanCurvePoint(temperatureC: 35, fraction: 0.15),
        FanCurvePoint(temperatureC: 55, fraction: 0.35),
        FanCurvePoint(temperatureC: 75, fraction: 0.65),
        FanCurvePoint(temperatureC: 90, fraction: 0.90),
    ])

    public static let aggressiveCurve = FanCurve(name: "Aggressive", points: [
        FanCurvePoint(temperatureC: 30, fraction: 0.25),
        FanCurvePoint(temperatureC: 50, fraction: 0.50),
        FanCurvePoint(temperatureC: 70, fraction: 0.80),
        FanCurvePoint(temperatureC: 85, fraction: 1.00),
    ])
}
