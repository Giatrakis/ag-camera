import OSLog
import Synchronization

final class AGCameraLog: Sendable {
    private let enabled: Mutex<Bool>

    init(enabled: Bool) {
        self.enabled = Mutex(enabled)
    }

    var isEnabled: Bool {
        enabled.withLock { $0 }
    }

    func setEnabled(_ value: Bool) {
        enabled.withLock { $0 = value }
    }

    func debug(_ message: @autoclosure () -> String, category: String) {
        guard isEnabled else { return }
        let value = message()
        Logger(subsystem: "com.agcamera", category: category).debug("\(value, privacy: .private)")
    }

    func info(_ message: @autoclosure () -> String, category: String) {
        guard isEnabled else { return }
        let value = message()
        Logger(subsystem: "com.agcamera", category: category).info("\(value, privacy: .private)")
    }

    func warning(_ message: @autoclosure () -> String, category: String) {
        guard isEnabled else { return }
        let value = message()
        Logger(subsystem: "com.agcamera", category: category).warning("\(value, privacy: .private)")
    }

    func error(_ message: @autoclosure () -> String, category: String) {
        guard isEnabled else { return }
        let value = message()
        Logger(subsystem: "com.agcamera", category: category).error("\(value, privacy: .private)")
    }

    func timing(_ operation: String, elapsed: TimeInterval, category: String) {
        guard isEnabled else { return }
        Logger(subsystem: "com.agcamera", category: category)
            .info("\(operation, privacy: .public) completed in \(elapsed, privacy: .public) seconds")
    }
}
