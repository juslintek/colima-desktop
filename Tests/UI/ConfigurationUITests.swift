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

    func testAutoActivateToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_autoactivate"].waitForExistence(timeout: 3))
    }

    func testModelRunnerPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_modelrunner"].waitForExistence(timeout: 3))
    }

    func testDockerJSONEditorExists() {
        XCTAssertTrue(app.textViews["field_config_dockerjson"].waitForExistence(timeout: 3))
    }

    // MARK: - Kubernetes

    func testK8sEnabledToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_k8s"].waitForExistence(timeout: 3))
    }

    func testK8sVersionFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_k8sversion"].waitForExistence(timeout: 3))
    }

    func testK3sArgsEditorExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_k3sargs"].waitForExistence(timeout: 3))
    }

    func testK8sPortFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_k8sport"].waitForExistence(timeout: 3))
    }

    // MARK: - Network

    func testNetworkAddressToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_networkaddress"].waitForExistence(timeout: 3))
    }

    func testNetworkModePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_networkmode"].waitForExistence(timeout: 3))
    }

    func testNetworkInterfaceFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_interface"].waitForExistence(timeout: 3))
    }

    func testDNSFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_dns"].waitForExistence(timeout: 3))
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

    // MARK: - Volume Mounts

    func testMountTypePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_mounttype"].waitForExistence(timeout: 3))
    }

    func testInotifyToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_inotify"].waitForExistence(timeout: 3))
    }

    func testDisableMountsToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_disablemounts"].waitForExistence(timeout: 3))
    }

    func testMountsAddButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_add_mount"].waitForExistence(timeout: 3))
    }

    func testMountsRemoveButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_remove_mount_0"].waitForExistence(timeout: 3))
    }

    // MARK: - SSH

    func testSSHPortFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_config_sshport"].waitForExistence(timeout: 3))
    }

    func testForwardAgentToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_forwardagent"].waitForExistence(timeout: 3))
    }

    func testSSHConfigToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_config_sshconfig"].waitForExistence(timeout: 3))
    }

    // MARK: - Provisioning

    func testProvisioningAddButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_add_provision"].waitForExistence(timeout: 3))
    }

    func testProvisioningRemoveButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_remove_provision_0"].waitForExistence(timeout: 3))
    }

    // MARK: - Environment

    func testEnvironmentAddButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_add_env"].waitForExistence(timeout: 3))
    }

    func testEnvironmentRemoveButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_remove_env_0"].waitForExistence(timeout: 3))
    }

    // MARK: - Template

    func testTemplateLoadButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_load_template"].waitForExistence(timeout: 3))
    }

    func testTemplateSaveButton() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_save_template"].waitForExistence(timeout: 3))
    }

    // MARK: - Lock icons

    func testLockIconsExist() {
        XCTAssertTrue(app.descendants(matching: .any)["lock_config_arch"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["lock_config_vmtype"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["lock_config_runtime"].exists)
    }

    // MARK: - Actions

    func testSaveButtonExists() {
        let btn = app.descendants(matching: .any)["btn_save_config_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testResetButtonExists() {
        let btn = app.descendants(matching: .any)["btn_reset_config_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testEditYAMLButtonExists() {
        let btn = app.descendants(matching: .any)["btn_edit_config_yaml"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }
}
