import SwiftUI

struct AGCameraGridOverlay: View {
    let grid: AGCameraGrid

    var body: some View {
        Canvas { context, size in
            let divisions: Int
            switch grid {
            case .none:
                return
            case .rule3x3:
                divisions = 3
            case .square4x4:
                divisions = 4
            }

            var lines = Path()
            for index in 1..<divisions {
                let fraction = CGFloat(index) / CGFloat(divisions)
                let x = size.width * fraction
                let y = size.height * fraction
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(.white.opacity(0.65)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
