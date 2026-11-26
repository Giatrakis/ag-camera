import SwiftUI

struct AGZoomDialView: View {
    let zoom: CGFloat
    let minimum: CGFloat
    let maximum: CGFloat
    let focalLength: (CGFloat) -> Int?
    let physicalLensFocalLength: (CGFloat) -> Int?

    var body: some View {
        GeometryReader { geometry in
            let radius = geometry.size.width * 0.55
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height + radius * 0.435)
            let edgeAngle = asin((center.y - geometry.size.height) / radius) * 180 / .pi
            let startAngle = 180 + edgeAngle
            let endAngle = 360 - edgeAngle

            ZStack {
                Path { path in
                    path.move(to: point(at: startAngle, radius: radius, center: center))
                    for degree in stride(from: startAngle, through: endAngle, by: 2) {
                        path.addLine(to: point(at: degree, radius: radius, center: center))
                    }
                    path.addLine(to: point(at: endAngle, radius: radius, center: center))
                    path.closeSubpath()
                }
                .fill(.black.opacity(0.6))

                Canvas { context, _ in
                    guard minimum > 0, maximum >= minimum else { return }
                    for value in AGZoomDialScale.ticks {
                        guard value >= minimum, value <= maximum else { continue }
                        let degree = angle(for: value)
                        guard (210...330).contains(degree) else { continue }

                        let major = AGZoomDialScale.majorLandmarks.contains(value)
                        var path = Path()
                        path.move(to: point(at: degree, radius: radius - 2, center: center))
                        path.addLine(to: point(at: degree, radius: radius - (major ? 18 : 10), center: center))
                        context.stroke(path, with: .color(.white.opacity(major ? 0.85 : 0.45)), lineWidth: 1)
                    }
                }

                ForEach(AGZoomDialScale.labelLandmarks.filter { $0 >= minimum && $0 <= maximum }, id: \.self) { stop in
                    let degree = angle(for: stop)
                    if (210...332).contains(degree), abs(degree - 270) >= 12.5 {
                        let labelPoint = point(at: degree, radius: radius - 38, center: center)
                        VStack(spacing: 0) {
                            Text(AGZoomDisplay.number(stop))
                                .font(.caption2)
                            if let millimeters = physicalLensFocalLength(stop) {
                                Text("\(millimeters)MM")
                                    .font(.caption2)
                                    .scaleEffect(0.7)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                            .foregroundStyle(.white.opacity(0.8))
                            .position(x: labelPoint.x, y: min(labelPoint.y, geometry.size.height - 13))
                    }
                }

                ForEach([CGFloat(1.2), 1.5].filter { $0 >= minimum && $0 <= maximum }, id: \.self) { stop in
                    let degree = angle(for: stop)
                    if (215...325).contains(degree) {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 4, height: 4)
                            .position(point(at: degree, radius: radius - 38, center: center))
                    }
                }

                Capsule()
                    .fill(.yellow)
                    .frame(width: 2, height: 9)
                    .position(x: center.x, y: center.y - radius + 5)

                VStack(spacing: 0) {
                    Text("\(AGZoomDisplay.number(zoom))×")
                        .font(.caption)
                        .fontWeight(.semibold)
                    if zoom < 10, let millimeters = focalLength(zoom) {
                        Text("\(millimeters)MM")
                            .font(.caption2)
                    }
                }
                    .foregroundStyle(.yellow)
                    .monospacedDigit()
                    .position(x: center.x, y: center.y - radius + 39)
            }
        }
        .accessibilityLabel("Zoom dial, \(AGZoomDisplay.number(zoom)) times")
    }

    private func angle(for value: CGFloat) -> Double {
        guard zoom > 0, value > 0 else { return 270 }
        return 270 + (log2(Double(value)) - log2(Double(zoom))) * 15
    }

    private func point(at degree: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = degree * .pi / 180
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )
    }
}

enum AGZoomDialScale {
    static let majorLandmarks: [CGFloat] = [0.5, 1, 2, 4, 8, 10, 20, 30, 40]
    static let labelLandmarks: [CGFloat] = [0.5, 1, 2, 4, 8]
    static let hapticLandmarks: [CGFloat] = [0.5, 1, 1.2, 1.5, 2, 4, 8, 10, 20, 30, 40]
    static let ticks: [CGFloat] =
        (5...20).map { CGFloat($0) / 10 }
        + (9...16).map { CGFloat($0) / 4 }
        + (9...16).map { CGFloat($0) / 2 }
        + (9...40).map { CGFloat($0) }

    static func zoom(from start: CGFloat, translation: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard start > 0, minimum > 0, maximum >= minimum else { return start }
        let scaled = start * pow(2, -translation / 13)
        return min(max(scaled, minimum), maximum)
    }

    static func crossesLandmark(from old: CGFloat, to new: CGFloat, minimum: CGFloat, maximum: CGFloat) -> Bool {
        guard old != new else { return false }
        return hapticLandmarks.contains { landmark in
            guard landmark >= minimum, landmark <= maximum else { return false }
            return old < landmark && new >= landmark || old > landmark && new <= landmark
        }
    }
}
