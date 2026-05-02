# ColimaUI Coding Standards

## Swift
- SwiftUI views: max 200 lines per file, extract subviews
- All interactive elements: `.accessibilityIdentifier("category_name_context")`
- State: `@EnvironmentObject var appState: AppState` (single source of truth)
- Mock mode: `CommandLine.arguments.contains("--ui-testing")` → use MockData
- No force unwraps in production code
- Prefer `@ViewBuilder` computed properties over complex body expressions

## Naming
- Views: `ContainersView.swift`, `ContainerDetailView.swift`
- Models: `MockData.swift`, `MockContainer`, `MockImage`
- IDs: `tab_containers`, `btn_start_vm_dashboard`, `field_config_cpus`
- Shared components: `ColimaUI/Views/Shared/`

## Testing
- XCUITest pattern: `app.descendants(matching: .any)["id"].waitForExistence(timeout: 5)`
- Test existence and state, NOT toast messages
- setUp: launch with `["--ui-testing"]`, activate, navigate to target view
- Timeouts: 5s for element existence, 10s for navigation

## Git
- Commit after each logical change
- Always push to main (trunk-based)
- Format: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`
