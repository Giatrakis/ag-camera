import CoreGraphics
import Testing
#if canImport(AGCamera)
@testable import AGCamera
#else
@testable import ag_camera
#endif

struct AGZoomStopsTests {
    @Test
    func oneXCyclesThroughSupportedFocalLengthSteps() {
        let steps = [CGFloat(1), 1.2, 1.5].map {
            AGZoomStops.nextOneXZoom(current: $0, maximum: 2)
        }

        #expect(steps.map(\.factor) == [1.2, 1.5, 1])
        #expect(steps.map(\.focalLength) == [28, 35, 24])
    }

    @Test
    func oneXSkipsUnavailableOnePointFiveZoom() {
        let first = AGZoomStops.nextOneXZoom(current: 1, maximum: 1.3)
        let second = AGZoomStops.nextOneXZoom(current: first.factor, maximum: 1.3)

        #expect(first.factor == 1.2)
        #expect(second.factor == 1)
    }

    @Test
    func nativeStopsUseDeviceMultiplierAndRespectConfiguredLimit() {
        let levels = AGZoomStops.make(
            minimum: 0.5,
            maximum: 3,
            displayMultiplier: 0.5,
            switchOvers: [2, 4, 10],
            nativeResolutionStops: [4]
        )

        #expect(levels == [0.5, 1, 2])
    }

    @Test
    func oneXIsNotOfferedWhenHardwareMinimumIsHigher() {
        let levels = AGZoomStops.make(
            minimum: 1.2,
            maximum: 3,
            displayMultiplier: 1.2,
            switchOvers: [],
            nativeResolutionStops: []
        )

        #expect(levels == [1.2])
    }

    @Test
    func zoomDisplayUsesOneDecimalAndPeriod() {
        #expect(AGZoomDisplay.number(0.5) == "0.5")
        #expect(AGZoomDisplay.number(1.24) == "1.2")
        #expect(AGZoomDisplay.number(2) == "2")
    }

    @Test
    func zoomSelectionReturnsToPreviousStopBelowNextStop() {
        let levels: [CGFloat] = [0.5, 1, 2, 4]

        #expect(AGZoomDisplay.containingStop(for: 1.99, in: levels) == 1)
        #expect(AGZoomDisplay.containingStop(for: 2, in: levels) == 2)
        #expect(AGZoomDisplay.containingStop(for: 0.5, in: levels) == 0.5)
    }

    @Test
    func dialDragDirectionAndLimitsMatchNativeControl() {
        let increased = AGZoomDialScale.zoom(from: 1, translation: -13, minimum: 0.5, maximum: 40)
        let decreased = AGZoomDialScale.zoom(from: 1, translation: 13, minimum: 0.5, maximum: 40)

        #expect(abs(increased - 2) < 0.001)
        #expect(abs(decreased - 0.5) < 0.001)
        #expect(AGZoomDialScale.zoom(from: 1, translation: -100, minimum: 0.5, maximum: 40) == 40)
        #expect(AGZoomDialScale.zoom(from: 1, translation: 100, minimum: 0.5, maximum: 40) == 0.5)
    }

    @Test
    func dialFeedbackFollowsLandmarkCrossingsWithinDeviceRange() {
        #expect(AGZoomDialScale.crossesLandmark(from: 1.1, to: 1.3, minimum: 0.5, maximum: 40))
        #expect(AGZoomDialScale.crossesLandmark(from: 1.3, to: 1.1, minimum: 0.5, maximum: 40))
        #expect(!AGZoomDialScale.crossesLandmark(from: 1.21, to: 1.29, minimum: 0.5, maximum: 40))
        #expect(!AGZoomDialScale.crossesLandmark(from: 8.5, to: 10.5, minimum: 0.5, maximum: 8))
    }
}
