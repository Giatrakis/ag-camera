---
name: iOS Development Core Guidelines
description: Core development principles and conventions for building iOS 26+ apps using SwiftUI, @Observable view models, and clean architecture aligned with Apple's frameworks and SOLID principles.
---

# iOS Development Core Guidelines

## Overview
This Skill defines the foundational rules, conventions, and patterns for all iOS development work within our projects.  
It ensures that all generated or reviewed code aligns with the latest iOS SDKs, Swift language features, and Apple’s official documentation.

---

## Platform & Frameworks
1. **Target Platform:** iOS 26 and later — always use the latest iOS SDK and APIs available.
2. **Frameworks:** Prefer modern, native Apple frameworks (e.g., SwiftUI, SwiftData, WidgetKit, AppIntents, etc.).
3. **Language Version:** Target **Swift 5**, but prepare the codebase for **Swift 6** adoption by using modern syntax and concurrency features where compatible.
4. **Concurrency:** Use `async/await` and structured concurrency primitives (e.g., `Task`, `actors`) instead of Combine or legacy patterns.
5. **Avoid:** Do **not** use `NotificationCenter` for communication or event handling — prefer structured approaches such as `@Observable`, `.onChange` SwiftUI modifier, dependency injection, or Swift Concurrency (`async` streams, `AsyncSequence`).

---

## Architecture & Design Principles
1. Follow **Clean Architecture** and **SOLID** principles.
2. Maintain **separation of concerns**:
   - **UI** → SwiftUI `View` structs  
   - **ViewModels / Managers** → business logic and state management using `@Observable`
3. Each `ViewModel` or `Manager` should have **a single, clear responsibility**.
4. Organize large files using **private extensions** with `// MARK:` notes to logically separate functionality.
5. Keep **ViewModels/Managers** lightweight and focused. Avoid bloated or overly complex state logic.

---

## UI Guidelines
1. Build UIs using **SwiftUI** exclusively.
2. Follow **Apple’s Human Interface Guidelines (HIG)** — design interfaces that feel native and idiomatic to iOS.
3. Break down complex UIs into **small, reusable `View` structs** for clarity and maintainability.
4. **Typography:** Use system-provided font styles (e.g., `.title`, `.body`, `.caption`) instead of hardcoded font sizes or weights.
5. **Layout:** Avoid hardcoded values for padding, sizes, images, or fonts. Use system adaptive APIs and constants where possible.
6. **Icons:** Always use **SF Symbols** for iconography and visual consistency.
7. Always follow **Apple’s official documentation** — prioritize Apple-endorsed patterns and APIs before third-party or legacy approaches.

---

## Code Quality & Conventions
1. **Never use force unwrapping (`!`)** — use safe optional binding (`if let`, `guard`) or provide sensible defaults.
2. **Avoid unnecessary comments** — code should be self-documenting through meaningful naming and structure.
3. **Swift Warnings:** Be aware of and resolve concurrency-related warnings, such as  
   > “Call to main actor-isolated instance method in a synchronous nonisolated context.”
4. **Use modern Swift features** where appropriate:
   - `if let`, `guard`, `defer`, `Result`, `Codable`, `Task`, `actor`, `macro`
   - Avoid outdated Objective-C patterns or deprecated APIs.

---

## Logging
### Preferred Logging Pattern
Do **not** use `print` statements.  
Use a structured logging system built on `OSLog` that conforms to a common `LoggerProtocol`.  

```swift
import Foundation
import OSLog

protocol LoggerProtocol {
    func debug(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

extension Logger: LoggerProtocol {
    func debug(_ message: String) { self.debug("\(message, privacy: .public)") }
    func info(_ message: String) { self.info("\(message, privacy: .public)") }
    func warning(_ message: String) { self.warning("\(message, privacy: .public)") }
    func error(_ message: String) { self.error("\(message, privacy: .public)") }
}

struct SilentLogger: LoggerProtocol {
    func debug(_ message: String) { }
    func info(_ message: String) { }
    func warning(_ message: String) { }
    func error(_ message: String) { }
}

enum SyncLogger {
    private static let subsystem = "...."

    private static let isEnabled = true

    static let error: LoggerProtocol = isEnabled ? Logger(subsystem: subsystem, category: "sync-error") : SilentLogger()
    static let network: LoggerProtocol = isEnabled ? Logger(subsystem: subsystem, category: "network") : SilentLogger()
}
