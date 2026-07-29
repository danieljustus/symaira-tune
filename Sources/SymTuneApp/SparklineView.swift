import SwiftUI
import SymTuneCore

/// A mini sparkline view that renders a ``MetricSample`` array as a polyline.
///
/// - Value samples are connected by a continuous line.
/// - Gap markers (``MetricSample/isValue == false``) break the line — no
///   fabricated straight line across sleep/wake or unavailable windows.
/// - The Y-axis is auto-scaled to the value range, with optional `min`/`max`
///   annotations.
struct SparklineView: View {
    let samples: [MetricSample]
    let lineColor: Color
    let showAnnotations: Bool

    /// Optional explicit range. When `nil`, the range is computed from the
    /// value samples in `samples`.
    let valueRange: ClosedRange<Double>?

    init(
        samples: [MetricSample],
        lineColor: Color = SymairaColors.goldPrimary,
        showAnnotations: Bool = true,
        valueRange: ClosedRange<Double>? = nil
    ) {
        self.samples = samples
        self.lineColor = lineColor
        self.showAnnotations = showAnnotations
        self.valueRange = valueRange
    }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let valueSamples = samples.enumerated().filter { $0.element.isValue }
            guard !valueSamples.isEmpty else { return }

            let range = valueRange ?? computeRange(from: valueSamples.map(\.element))
            let yRange = range.upperBound - range.lowerBound

            // Ensure we don't divide by zero
            let scale = yRange > 0 ? yRange : 1.0
            let pad: Double = 2 // padding from top/bottom edges

            // Build segments: each contiguous run of value samples is one path segment
            var segments: [[(x: Double, y: Double)]] = []
            var current: [(x: Double, y: Double)] = []

            for (globalIdx, sample) in samples.enumerated() {
                guard let value = sample.value else {
                    // Gap: finish current segment
                    if !current.isEmpty {
                        segments.append(current)
                        current = []
                    }
                    continue
                }

                let x = size.width * Double(globalIdx) / Double(max(1, samples.count - 1))
                let normalizedY = (value - range.lowerBound) / scale
                let y = size.height - pad - (normalizedY * (size.height - 2 * pad))
                current.append((x: x, y: y))
            }
            if !current.isEmpty {
                segments.append(current)
            }

            // Draw each segment as a polyline
            for segment in segments where segment.count >= 2 {
                var path = Path()
                path.move(to: CGPoint(x: segment[0].x, y: segment[0].y))
                for pt in segment.dropFirst() {
                    path.addLine(to: CGPoint(x: pt.x, y: pt.y))
                }
                context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }

            // Optionally draw min/max dots
            if showAnnotations, let globalMin = valueSamples.map({ $0.element.value! }).min(),
               let globalMax = valueSamples.map({ $0.element.value! }).max() {
                for (globalIdx, sample) in samples.enumerated() {
                    guard let value = sample.value else { continue }
                    let x = size.width * Double(globalIdx) / Double(max(1, samples.count - 1))
                    let normalizedY = (value - range.lowerBound) / scale
                    let y = size.height - pad - (normalizedY * (size.height - 2 * pad))

                    if value == globalMin || value == globalMax {
                        let dot = Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3))
                        let color: Color = value == globalMax ? SymairaColors.success : SymairaColors.warning
                        context.fill(dot, with: .color(color))
                    }
                }
            }
        }
        .frame(height: 22)
    }

    private func computeRange(from samples: [MetricSample]) -> ClosedRange<Double> {
        let values = samples.compactMap(\.value)
        guard let mn = values.min(), let mx = values.max() else { return 0...1 }
        if mn == mx { return mn...(mn + 1) }
        // Add 10% padding above/below for visual breathing room
        let pad = (mx - mn) * 0.1
        return (mn - pad)...(mx + pad)
    }
}
