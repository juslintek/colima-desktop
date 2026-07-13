import ColimaDesktopKit

// Thin executable entry: all app logic lives in the ColimaDesktopKit framework
// so tests can @testable-import it without hosting the app (fixes Xcode-26 hang).
ColimaDesktopApp.main()
