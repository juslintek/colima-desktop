# Fresh Session Prompt

Paste this into a new kiro-cli session:

---

ralph: Continue Colima Desktop real backend integration. Use the colima skill.

Read Sources/docs/IMPLEMENTATION_STATUS.md first for full context.

Current state: AppState refactored (no useMocks), Docker API works, 58 tests pass.

Remaining work (in priority order):
1. ConfigurationView — read/write ~/.colima/default/colima.yaml (NEVER use colima template — it opens editor). Add readConfig/writeConfig to DaemonClient. Load on .onAppear, save writes YAML + restarts.
2. RuntimeControlsView — replace MockDetailData.commandOutput with real Process() execution
3. MonitoringView — replace MockDetailData.containerStats with real Docker API stats
4. Sheet views (Stats, Changes, History, Search) — wire to real ServiceProvider data
5. KubernetesView — add kubectl JSON integration (only when k8s enabled)

Rules:
- Run on HOST machine (not host machine — no nested virt)
- NEVER run interactive colima commands (template, ssh without --, start --edit)
- Read/write YAML files directly for config changes
- Build: xcodegen generate && xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet
- Test: xcodebuild test -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:ColimaDesktopUnitTests
