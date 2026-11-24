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
}
