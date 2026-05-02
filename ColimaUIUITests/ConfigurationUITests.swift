import XCTest

final class ConfigurationUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_configuration"].click()
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cpus"].waitForExistence(timeout: 3))
    }

    // MARK: - VM Resources

    func testConfigTitle() {
        XCTAssertTrue(app.navigationBars["Configuration"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["Configuration"].waitForExistence(timeout: 3))
    }

    func testCPUStepperExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cpus"].exists)
    }

    func testMemoryStepperExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_memory"].exists)
    }

    func testDiskStepperExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_disk"].exists)
    }

    func testRootDiskStepperExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_rootdisk"].exists)
    }

    // MARK: - VM Settings

    func testArchPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_arch"].waitForExistence(timeout: 3))
    }

    func testVMTypePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_vmtype"].waitForExistence(timeout: 3))
    }

    func testCPUTypeFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cputype"].waitForExistence(timeout: 3))
    }

    func testRosettaToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_rosetta"].waitForExistence(timeout: 3))
    }

    func testNestedVirtToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_nestedvirt"].waitForExistence(timeout: 3))
    }

    func testHostnameFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_hostname"].waitForExistence(timeout: 3))
    }

    func testDiskImageFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_diskimage"].waitForExistence(timeout: 3))
    }

    func testBinfmtToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_binfmt"].waitForExistence(timeout: 3))
    }

    func testForegroundToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_foreground"].waitForExistence(timeout: 3))
    }

    func testPortForwarderPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_portforwarder"].waitForExistence(timeout: 3))
    }

    // MARK: - Runtime

    func testRuntimePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_runtime"].waitForExistence(timeout: 3))
    }

    func testDockerJSONEditorExists() {
        XCTAssertTrue(app.textViews["field_config_dockerjson"].waitForExistence(timeout: 3))
    }

    func testK3sArgsEditorExists() {
        XCTAssertTrue(app.textViews["field_config_k3sargs"].waitForExistence(timeout: 3))
    }

    // MARK: - Network

    func testNetworkInterfaceFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_interface"].waitForExistence(timeout: 3))
    }

    func testDNSHostsEditorExists() {
        XCTAssertTrue(app.textViews["field_config_dnshosts"].waitForExistence(timeout: 3))
    }

    func testGatewayFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_gateway"].waitForExistence(timeout: 3))
    }

    func testHostAddressesToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_hostaddresses"].waitForExistence(timeout: 3))
    }

    func testPreferredRouteToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_preferredroute"].waitForExistence(timeout: 3))
    }

    // MARK: - Mounts / Provisioning / Environment

    func testMountsAddRemoveButtons() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_add_mount"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["btn_remove_mount_0"].exists)
    }

    func testProvisioningAddRemoveButtons() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_add_provision"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["btn_remove_provision_0"].exists)
    }

    func testEnvironmentAddRemoveButtons() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_add_env"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["btn_remove_env_0"].exists)
    }

    // MARK: - Template

    func testTemplateLoadSaveButtons() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_load_template"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["btn_save_template"].exists)
    }

    // MARK: - Lock icons

    func testLockIconsExist() {
        XCTAssertTrue(app.descendants(matching: .any)["lock_config_arch"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["lock_config_vmtype"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["lock_config_runtime"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["lock_config_mounttype"].exists)
    }

    // MARK: - Actions

    func testSaveButtonShowsToast() {
        app.descendants(matching: .any)["btn_save_config_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("saved"))
    }

    func testResetButtonShowsToast() {
        app.descendants(matching: .any)["btn_reset_config_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("reset"))
    }

    // MARK: - Toggles (untested IDs)

    func testAutoActivateToggleExists() {
        let toggle = app.descendants(matching: .any)["toggle_config_autoactivate"]
        if !toggle.waitForExistence(timeout: 3) {
            let sw = app.descendants(matching: .any)["toggle_config_autoactivate"]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), "Auto Activate toggle should exist")
            return
        }
        XCTAssertTrue(toggle.exists)
    }

    func testDisableMountsToggleExists() {
        let toggle = app.descendants(matching: .any)["toggle_config_disablemounts"]
        if !toggle.waitForExistence(timeout: 3) {
            let sw = app.descendants(matching: .any)["toggle_config_disablemounts"]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), "Disable Mounts toggle should exist")
            return
        }
        XCTAssertTrue(toggle.exists)
    }

    func testForwardAgentToggleExists() {
        let toggle = app.descendants(matching: .any)["toggle_config_forwardagent"]
        if !toggle.waitForExistence(timeout: 3) {
            let sw = app.descendants(matching: .any)["toggle_config_forwardagent"]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), "Forward Agent toggle should exist")
            return
        }
        XCTAssertTrue(toggle.exists)
    }

    func testInotifyToggleExists() {
        let toggle = app.descendants(matching: .any)["toggle_config_inotify"]
        if !toggle.waitForExistence(timeout: 3) {
            let sw = app.descendants(matching: .any)["toggle_config_inotify"]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), "Inotify toggle should exist")
            return
        }
        XCTAssertTrue(toggle.exists)
    }

    func testK8sEnabledToggleExists() {
        let toggle = app.descendants(matching: .any)["toggle_config_k8s"]
        if !toggle.waitForExistence(timeout: 3) {
            let sw = app.descendants(matching: .any)["toggle_config_k8s"]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), "K8s Enabled toggle should exist")
            return
        }
        XCTAssertTrue(toggle.exists)
    }

    func testNetworkAddressToggleExists() {
        let toggle = app.descendants(matching: .any)["toggle_config_networkaddress"]
        if !toggle.waitForExistence(timeout: 3) {
            let sw = app.descendants(matching: .any)["toggle_config_networkaddress"]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), "Network Address toggle should exist")
            return
        }
        XCTAssertTrue(toggle.exists)
    }

    func testSSHConfigToggleExists() {
        let toggle = app.descendants(matching: .any)["toggle_config_sshconfig"]
        if !toggle.waitForExistence(timeout: 3) {
            let sw = app.descendants(matching: .any)["toggle_config_sshconfig"]
            XCTAssertTrue(sw.waitForExistence(timeout: 3), "SSH Config toggle should exist")
            return
        }
        XCTAssertTrue(toggle.exists)
    }

    // MARK: - Fields (untested IDs)

    func testK8sPortFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_k8sport"].waitForExistence(timeout: 3))
    }

    func testK8sVersionFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_k8sversion"].waitForExistence(timeout: 3))
    }

    func testModelRunnerPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_modelrunner"].waitForExistence(timeout: 3))
    }

    func testMountTypePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_mounttype"].waitForExistence(timeout: 3))
    }

    func testNetworkModePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_networkmode"].waitForExistence(timeout: 3))
    }

    func testSSHPortFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_sshport"].waitForExistence(timeout: 3))
    }

    func testEditYAMLButtonShowsToast() {
        app.descendants(matching: .any)["btn_edit_config_yaml"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
    }
}
