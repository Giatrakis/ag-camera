---
name: iOS New Feature Planner
description: Guide for carefully planning and implementing new iOS features step by step, following core conventions and modern SwiftUI + Clean Architecture principles.
---

# iOS New Feature Planner

## Instructions
1. Always **start by understanding the feature requirements** before writing any code.
2. **Break the feature into small, incremental steps**. Each step should be implementable and testable individually.
3. For each step:
   - Identify **what needs to be done**, **what files/classes/views are involved**, and **any dependencies**.
   - Suggest the **minimum code or skeleton needed**; do not generate full implementation at once.
   - Include **progression notes** so the next step can follow logically.
4. Always reference **core conventions** from `ios-dev-core/SKILL.md`:
   - Target iOS 26+ and use the latest Apple frameworks.
   - Use SwiftUI for UI and `@Observable` for view models/managers.
   - Apply Clean Architecture and SOLID principles.
   - Avoid NotificationCenter; prefer structured communication.
   - Use OSLog-based Logger instead of `print`.
5. Provide **short, actionable guidance** for each step; avoid long explanations.
6. Include **key reminders** as needed:
   - Split Views into small `View` structs.
   - Keep view models/managers focused with single responsibility.
   - Use async/await for concurrency.
   - Avoid hardcoded values for fonts, sizes, or images.
   - Use SF Symbols for icons.

---

## Examples
**Input**
Add a new "Profile Screen" feature with editable user info, avatar upload, and settings toggles.

**Step 1 Output**
Step 1: Define the data model and ViewModel
Create ProfileViewModel: Observable with properties for user info and settings.
Set up initial state using dummy/mock data.
Logger: Use SyncLogger.coordinator for logging ViewModel actions.
Notes: Avoid NotificationCenter, follow SOLID principles.

**Step 2 Output**
Step 2: Create the basic SwiftUI view
Create ProfileView: View struct.
Use small subviews for sections (e.g., AvatarView, SettingsRow).
Bind to ProfileViewModel using @Observable properties.
Use SF Symbols for icons.
Avoid hardcoded sizes and fonts; use system styles.

---

## Key Notes (from Core Guidelines)
- Target **iOS 26+**, prefer latest frameworks.
- Use **SwiftUI + @Observable** for UI and state.
- Follow **Clean Architecture / SOLID**.
- Prefer **async/await** over Combine.
- Avoid **NotificationCenter**.
- Use **OSLog-based Logger**, not `print`.
- Break views into **small reusable structs**.
- Keep **ViewModels / Managers clean and focused**.
- Avoid **hardcoded sizes, fonts, images**; use system styles.

---

## Notes
- Always plan features step by step; do not generate all code at once.
- Keep instructions clear, concise, and actionable.
- Reference `ios-dev-core/SKILL.md` when unsure about architectural or code conventions.