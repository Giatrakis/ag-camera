# AGENTS

<skills_system priority="1">

## Available Skills

<!-- SKILLS_TABLE_START -->
<usage>
When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.

How to use skills:
- Invoke: `npx openskills read <skill-name>` (run in your shell)
  - For multiple: `npx openskills read skill-one,skill-two`
- The skill content will load with detailed instructions on how to complete the task
- Base directory provided in output for resolving bundled resources (references/, scripts/, assets/)

Usage notes:
- Only use skills listed in <available_skills> below
- Do not invoke a skill that is already loaded in your context
- Each skill invocation is stateless
</usage>

<available_skills>

<skill>
<name>apple-project-structure</name>
<description>Define and apply folder/module structure conventions for Apple-platform app projects (iOS and macOS), including placement of App, Screens, Models, Managers, Networking, Extensions, and reusable UI components. Use when scaffolding a new project, reorganizing an existing codebase, reviewing repo layout, or deciding where new files/folders should live in SwiftUI-based Apple apps.</description>
<location>global</location>
</skill>

<skill>
<name>find-skills</name>
<description>Helps users discover and install agent skills when they ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express interest in extending capabilities. This skill should be used when the user is looking for functionality that might exist as an installable skill.</description>
<location>global</location>
</skill>

<skill>
<name>swift-concurrency</name>
<description>Expert guidance on Swift Concurrency best practices, patterns, and implementation. Use when developers mention: (1) Swift Concurrency, async/await, actors, or tasks, (2) "use Swift Concurrency" or "modern concurrency patterns", (3) migrating to Swift 6, (4) data races or thread safety issues, (5) refactoring closures to async/await, (6) @MainActor, Sendable, or actor isolation, (7) concurrent code architecture or performance optimization, (8) concurrency-related linter warnings (SwiftLint or similar; e.g. async_without_await, Sendable/actor isolation/MainActor lint).</description>
<location>global</location>
</skill>

<skill>
<name>swift-testing-expert</name>
<description>Expert guidance for Swift Testing: test structure, #expect/#require macros, traits and tags, parameterized tests, test plans, parallel execution, async waiting patterns, and XCTest migration. Use when writing new Swift tests, modernizing XCTest suites, debugging flaky tests, or improving test quality and maintainability in Apple-platform or Swift server projects.</description>
<location>global</location>
</skill>

<skill>
<name>swiftui-expert-skill</name>
<description>Write, review, or improve SwiftUI code following best practices for state management, view composition, performance, modern APIs, Swift concurrency, and iOS 26+ Liquid Glass adoption. Use when building new SwiftUI features, refactoring existing views, reviewing code quality, or adopting modern SwiftUI patterns.</description>
<location>global</location>
</skill>

<skill>
<name>swiftui-view-structure</name>
<description>Enforce a consistent SwiftUI View file/member organization convention (property ordering, non-view computed properties, init placement, body placement, view subcomponents, and private action extensions). Use when creating, refactoring, reviewing, or formatting SwiftUI View files and the team wants a specific structural layout/style beyond generic SwiftUI best practices.</description>
<location>global</location>
</skill>

<skill>
<name>skill-creator</name>
<description>Guide for creating effective skills. This skill should be used when users want to create a new skill (or update an existing skill) that extends Codex's capabilities with specialized knowledge, workflows, or tool integrations.</description>
<location>system</location>
</skill>

<skill>
<name>skill-installer</name>
<description>Install Codex skills into $CODEX_HOME/skills from a curated list or a GitHub repo path. Use when a user asks to list installable skills, install a curated skill, or install a skill from another repo (including private repos).</description>
<location>system</location>
</skill>

</available_skills>
<!-- SKILLS_TABLE_END -->

</skills_system>


## Project Skill Routing
- Use `swiftui-expert-skill` for SwiftUI API correctness, state management, performance, and modern SwiftUI patterns.
- Use `swiftui-view-structure` for SwiftUI `View` file/member ordering and layout conventions.
- Use `apple-project-structure` for file placement, folder structure, and repo organization decisions.
- Use `swift-concurrency` for Swift concurrency guidance, actor isolation issues, Sendable warnings, and migration-related questions.
- Use `swift-testing-expert` when writing tests, debugging test failures, or improving test structure.
- Keep this file focused on project-specific rules and agent workflow expectations; avoid duplicating reusable guidance that already exists in skills.

---

## Project Guidelines

## Platform & Frameworks
1. **Target Platform:** iOS 26 and later — always use the latest iOS SDK and APIs available.
2. **Frameworks:** Prefer modern, native Apple frameworks (e.g., SwiftUI, SwiftData, WidgetKit, AppIntents, etc.).
3. **Language Version:** Target **Swift 5**, but prepare the codebase for **Swift 6** adoption by using modern syntax and concurrency features where compatible.
4. **Availability Checks:** Do **not** add OS availability checks (e.g., `if #available(...)`) when the app's minimum deployment target is already higher than the checked OS version.
5. **Avoid:** Do **not** use `NotificationCenter` for communication or event handling — prefer structured approaches such as `@Observable`, `.onChange` SwiftUI modifier, dependency injection, or Swift Concurrency (`async` streams, `AsyncSequence`).

---

## UI Guidelines
1. Build UIs using **SwiftUI** exclusively.
2. **Typography:** Use system-provided font styles (e.g., `.title`, `.body`, `.caption`) instead of hardcoded font sizes or weights.
3. **Icons:** Always use **SF Symbols** for iconography and visual consistency.

---

## Code Quality & Conventions
1. **Never use force unwrapping (`!`)** — use safe optional binding (`if let`, `guard`) or provide sensible defaults.
2. **Avoid unnecessary comments** — code should be self-documenting through meaningful naming and structure. Don't add comments on SwiftUI views.
3. **Use modern Swift features** where appropriate:
   - `if let`, `guard`, `defer`, `Result`, `Codable`, `Task`, `actor`, `macro`
   - Avoid outdated Objective-C patterns or deprecated APIs.
4. **Bindings:** Use the shorthand `$` syntax for bindings instead of manually creating `Binding(get:set:)`.
   ```swift
   // Correct
   $viewModel.item.reminderDate

   // Wrong - avoid this pattern
   Binding(
       get: { viewModel.item.reminderDate },
       set: { viewModel.item.reminderDate = $0 }
   )
   ```

---

## Agent Workflow & Delivery
1. **Plan First (Non-Trivial Work):** For non-trivial tasks (multi-step work, architectural decisions, or risky changes), start with a short plan before implementation. Use plan mode when available.
2. **Re-Plan on Surprises:** If implementation reveals new constraints or a chosen approach fails, stop and re-plan instead of continuing to push a broken direction.
3. **Parallelize Research:** Use subagents when available (or parallel tool calls / isolated analysis passes) to keep the main working context focused.
4. **One Focus Per Worker:** When delegating analysis, give each subagent/parallel effort a single purpose (research, repro, diff review, etc.).
5. **Autonomous Execution:** For actionable bug reports, move directly into reproduction, diagnosis, and fix. Minimize back-and-forth unless requirements are truly unclear.
6. **Explain Approach Early:** Before non-trivial code changes, summarize the intended approach and assumptions. Ask clarifying questions only when ambiguity blocks safe implementation.

---

## Task Tracking
1. **Track Non-Trivial Work:** For larger tasks, create a checkable plan in the tool or format being used for the task.
2. **Keep Progress Current:** Update progress as work advances so the current status is visible.
3. **Verification Notes:** Document what was verified and what remains unverified before marking work complete.
4. **Break Down Large Changes:** If a task requires changes across many files, split it into smaller reviewable steps before editing.


---

## Verification & Quality Bar
1. **Prove It Works:** Do not mark work complete without verification appropriate to the change (tests, logs, manual validation, or behavior checks).
2. **Prefer Reproducible Bug Fixes:** When practical, start bug fixes with a failing test or a clear reproduction path, then verify the fix.
3. **Review Blast Radius:** After changes, identify likely regression risks and suggest tests to cover them.
4. **Compare Behavior When Relevant:** For refactors or risky fixes, compare pre/post behavior to confirm no accidental regressions.
5. **Engineer Review Standard:** Before finalizing, challenge the solution quality and ask whether the implementation is clear, minimal, and reviewable.

---

## Engineering Principles
1. **Simplicity First:** Prefer the simplest solution that correctly solves the problem.
2. **Root Cause Over Patches:** Avoid temporary fixes when a reasonable root-cause fix is available.
3. **Minimal Impact:** Change only what is necessary to reduce regression risk.
4. **Balanced Elegance:** For non-trivial changes, check whether a cleaner approach exists. Do not over-engineer simple fixes.

---

## Lessons & Corrections
1. **Capture Corrections:** After user corrections, record the mistake pattern and a prevention rule in your preferred notes or project workflow system.
2. **Make Lessons Actionable:** Write lessons as concrete rules that can be applied on future tasks.
3. **Use Lessons Proactively:** Review relevant lessons at the start of similar work when available.
4. **Iterate Ruthlessly:** Refine lessons when repeated mistakes show the rule is too vague or incomplete.
