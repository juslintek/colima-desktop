import Testing
@testable import ColimaDesktopKit

@Suite("NavigationItem")
struct NavigationItemMetaTests {
    @Test("has all 13 surfaces with stable raw values")
    func allCases() {
        #expect(NavigationItem.allCases.count == 13)
        #expect(NavigationItem(rawValue: "dashboard") == .dashboard)
        #expect(NavigationItem(rawValue: "runtimeControls") == .runtimeControls)
        #expect(NavigationItem(rawValue: "nope") == nil)
    }

    @Test("every case has non-empty label, icon, id, accessibilityId")
    func metadata() {
        for item in NavigationItem.allCases {
            #expect(!item.label.isEmpty)
            #expect(!item.icon.isEmpty)
            #expect(item.id == item.rawValue)
            #expect(item.accessibilityId.hasPrefix("tab_"))
        }
    }

    @Test("special-cased accessibility ids are lowercased")
    func specialAccessibilityIds() {
        #expect(NavigationItem.runtimeControls.accessibilityId == "tab_runtimecontrols")
        #expect(NavigationItem.machines.accessibilityId == "tab_machines")
        #expect(NavigationItem.ai.accessibilityId == "tab_ai")
    }
}

@Suite("AIModelInfo.parse")
struct AIModelInfoParseTests {
    @Test("empty or header-only output yields no models")
    func emptyInputs() {
        #expect(AIModelInfo.parse("") .isEmpty)
        #expect(AIModelInfo.parse("NAME  SIZE  STATUS").isEmpty)
    }

    @Test("parses rows with name/size/status and optional port")
    func parsesRows() {
        let out = """
        NAME      SIZE     STATUS    PORT
        gemma3    2.1GB    idle
        phi4      8.2GB    serving   :8080
        """
        let models = AIModelInfo.parse(out)
        #expect(models.count == 2)
        #expect(models[0].name == "gemma3")
        #expect(models[0].size == "2.1GB")
        #expect(models[0].status == "idle")
        #expect(models[0].port == nil)
        #expect(models[1].name == "phi4")
        #expect(models[1].status == "serving")
        #expect(models[1].port == 8080)
    }

    @Test("skips malformed rows with fewer than 3 columns")
    func skipsMalformed() {
        let out = """
        NAME  SIZE  STATUS
        incomplete
        """
        #expect(AIModelInfo.parse(out).isEmpty)
    }
}
