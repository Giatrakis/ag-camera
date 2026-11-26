import SwiftUI

struct AGAspectRatioIcon: View {
    let ratio: AGPhotoAspectRatio

    private var outlineSize: CGSize {
        switch ratio {
        case .fourThree: CGSize(width: 31, height: 25)
        case .sixteenNine: CGSize(width: 36, height: 20)
        case .square: CGSize(width: 27, height: 27)
        }
    }

    var body: some View {
        ZStack {
            cornerBrackets
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

            Text(ratio.title)
                .font(.caption2)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
        .frame(width: 36, height: 30)
        .accessibilityHidden(true)
    }

    private var cornerBrackets: Path {
        let width = outlineSize.width
        let height = outlineSize.height
        let left = (36 - width) / 2
        let top = (30 - height) / 2
        let right = left + width
        let bottom = top + height
        let length: CGFloat = 5

        return Path { path in
            path.move(to: CGPoint(x: left + length, y: top))
            path.addLine(to: CGPoint(x: left + 2, y: top))
            path.addQuadCurve(to: CGPoint(x: left, y: top + 2), control: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: left, y: top + length))

            path.move(to: CGPoint(x: right - length, y: top))
            path.addLine(to: CGPoint(x: right - 2, y: top))
            path.addQuadCurve(to: CGPoint(x: right, y: top + 2), control: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: top + length))

            path.move(to: CGPoint(x: left, y: bottom - length))
            path.addLine(to: CGPoint(x: left, y: bottom - 2))
            path.addQuadCurve(to: CGPoint(x: left + 2, y: bottom), control: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left + length, y: bottom))

            path.move(to: CGPoint(x: right, y: bottom - length))
            path.addLine(to: CGPoint(x: right, y: bottom - 2))
            path.addQuadCurve(to: CGPoint(x: right - 2, y: bottom), control: CGPoint(x: right, y: bottom))
            path.addLine(to: CGPoint(x: right - length, y: bottom))
        }
    }
}
