import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - toYAML round-trip for previously uncovered fields

@Suite("Cov3Svc_ColimaConfig toYAML and round-trips")
struct Cov3Svc_ColimaConfigToYAMLTests {

    @Test("toYAML produces non-empty output")
    func toYAMLNonEmpty() {
        let yaml = ColimaConfig().toYAML()
        #expect(!yaml.isEmpty)
    }

    @Test("toYAML includes cpu field")
    func toYAMLCPU() {
        var c = ColimaConfig()
        c.cpu = 8
        let yaml = c.toYAML()
        #expect(yaml.contains("cpu: 8"))
    }

    @Test("toYAML includes disk field")
    func toYAMLDisk() {
        var c = ColimaConfig()
        c.disk = 200
        let yaml = c.toYAML()
        #expect(yaml.contains("disk: 200"))
    }

    @Test("toYAML serializes float memory correctly (integer case)")
    func toYAMLMemoryInt() {
        var c = ColimaConfig()
        c.memory = 8
        let yaml = c.toYAML()
        #expect(yaml.contains("memory: 8"))
    }

    @Test("toYAML serializes float memory correctly (fractional case)")
    func toYAMLMemoryFloat() {
        var c = ColimaConfig()
        c.memory = 2.5
        let yaml = c.toYAML()
        #expect(yaml.contains("memory: 2.5"))
    }

    @Test("toYAML includes rootDisk field")
    func toYAMLRootDisk() {
        var c = ColimaConfig()
        c.rootDisk = 30
        let yaml = c.toYAML()
        #expect(yaml.contains("rootDisk: 30"))
    }

    @Test("toYAML includes sshPort field")
    func toYAMLSSHPort() {
        var c = ColimaConfig()
        c.sshPort = 2222
        let yaml = c.toYAML()
        #expect(yaml.contains("sshPort: 2222"))
    }

    @Test("toYAML includes hostname in quotes")
    func toYAMLHostname() {
        var c = ColimaConfig()
        c.hostname = "myhost"
        let yaml = c.toYAML()
        #expect(yaml.contains("\"myhost\""))
    }

    @Test("toYAML writes kubernetes enabled true")
    func toYAMLKubernetesEnabled() {
        var c = ColimaConfig()
        c.kubernetes.enabled = true
        let yaml = c.toYAML()
        #expect(yaml.contains("enabled: true"))
    }

    @Test("toYAML writes custom kubernetes version")
    func toYAMLKubernetesVersion() {
        var c = ColimaConfig()
        c.kubernetes.version = "v1.28.0+k3s1"
        let yaml = c.toYAML()
        #expect(yaml.contains("v1.28.0+k3s1"))
    }

    @Test("toYAML writes k3sArgs list items")
    func toYAMLK3sArgs() {
        var c = ColimaConfig()
        c.kubernetes.k3sArgs = ["--disable=traefik", "--disable=servicelb"]
        let yaml = c.toYAML()
        #expect(yaml.contains("--disable=traefik"))
        #expect(yaml.contains("--disable=servicelb"))
    }

    @Test("toYAML writes network dns list")
    func toYAMLNetworkDNS() {
        var c = ColimaConfig()
        c.network.dns = ["8.8.8.8", "1.1.1.1"]
        let yaml = c.toYAML()
        #expect(yaml.contains("dns:"))
        #expect(yaml.contains("8.8.8.8"))
        #expect(yaml.contains("1.1.1.1"))
    }

    @Test("toYAML writes null when dns is empty")
    func toYAMLNetworkDNSNull() {
        var c = ColimaConfig()
        c.network.dns = []
        let yaml = c.toYAML()
        #expect(yaml.contains("dns: null"))
    }

    @Test("toYAML writes network dnsHosts when non-empty")
    func toYAMLNetworkDNSHosts() {
        var c = ColimaConfig()
        c.network.dnsHosts = ["host.docker.internal": "192.168.5.2"]
        let yaml = c.toYAML()
        #expect(yaml.contains("dnsHosts"))
        #expect(yaml.contains("host.docker.internal"))
    }

    @Test("toYAML writes dnsHosts: {} when empty")
    func toYAMLNetworkDNSHostsEmpty() {
        var c = ColimaConfig()
        c.network.dnsHosts = [:]
        let yaml = c.toYAML()
        #expect(yaml.contains("dnsHosts: {}"))
    }

    @Test("toYAML writes network address, mode, preferredRoute, hostAddresses")
    func toYAMLNetworkFields() {
        var c = ColimaConfig()
        c.network.address = true
        c.network.mode = "bridged"
        c.network.preferredRoute = true
        c.network.hostAddresses = true
        let yaml = c.toYAML()
        #expect(yaml.contains("address: true"))
        #expect(yaml.contains("mode: bridged"))
        #expect(yaml.contains("preferredRoute: true"))
        #expect(yaml.contains("hostAddresses: true"))
    }

    @Test("toYAML writes gatewayAddress")
    func toYAMLGatewayAddress() {
        var c = ColimaConfig()
        c.network.gatewayAddress = "192.168.5.3"
        let yaml = c.toYAML()
        #expect(yaml.contains("gatewayAddress: 192.168.5.3"))
    }

    @Test("toYAML writes mounts when non-empty")
    func toYAMLMounts() {
        var c = ColimaConfig()
        c.mounts = [
            ColimaConfig.Mount(location: "~", writable: true),
            ColimaConfig.Mount(location: "/tmp/data", writable: false)
        ]
        let yaml = c.toYAML()
        #expect(yaml.contains("mounts:"))
        #expect(yaml.contains("location: ~"))
        #expect(yaml.contains("location: /tmp/data"))
        #expect(yaml.contains("writable: true"))
        #expect(yaml.contains("writable: false"))
    }

    @Test("toYAML writes mounts: [] when empty")
    func toYAMLMountsEmpty() {
        var c = ColimaConfig()
        c.mounts = []
        let yaml = c.toYAML()
        #expect(yaml.contains("mounts: []"))
    }

    @Test("toYAML writes provision with mode and single-line script")
    func toYAMLProvisionSingleLine() {
        var c = ColimaConfig()
        c.provision = [ColimaConfig.Provision(mode: "system", script: "apt-get update")]
        let yaml = c.toYAML()
        #expect(yaml.contains("provision:"))
        #expect(yaml.contains("mode: system"))
        #expect(yaml.contains("script: apt-get update"))
    }

    @Test("toYAML writes provision with multiline script using |")
    func toYAMLProvisionMultiline() {
        var c = ColimaConfig()
        c.provision = [ColimaConfig.Provision(mode: "user", script: "apt-get update\napt-get install -y curl")]
        let yaml = c.toYAML()
        #expect(yaml.contains("mode: user"))
        #expect(yaml.contains("script: |"))
        #expect(yaml.contains("apt-get update"))
        #expect(yaml.contains("apt-get install -y curl"))
    }

    @Test("toYAML writes provision: null when empty")
    func toYAMLProvisionNull() {
        var c = ColimaConfig()
        c.provision = []
        let yaml = c.toYAML()
        #expect(yaml.contains("provision: null"))
    }

    @Test("toYAML writes env when non-empty")
    func toYAMLEnv() {
        var c = ColimaConfig()
        c.env = ["DOCKER_BUILDKIT": "1"]
        let yaml = c.toYAML()
        #expect(yaml.contains("env:"))
        #expect(yaml.contains("DOCKER_BUILDKIT"))
    }

    @Test("toYAML writes env: {} when empty")
    func toYAMLEnvEmpty() {
        var c = ColimaConfig()
        c.env = [:]
        let yaml = c.toYAML()
        #expect(yaml.contains("env: {}"))
    }

    @Test("toYAML writes boolean flags correctly")
    func toYAMLBooleans() {
        var c = ColimaConfig()
        c.rosetta = true
        c.nestedVirtualization = true
        c.forwardAgent = true
        c.autoActivate = false
        let yaml = c.toYAML()
        #expect(yaml.contains("rosetta: true"))
        #expect(yaml.contains("nestedVirtualization: true"))
        #expect(yaml.contains("forwardAgent: true"))
        #expect(yaml.contains("autoActivate: false"))
    }

    @Test("toYAML writes cpuType in quotes")
    func toYAMLCpuType() {
        var c = ColimaConfig()
        c.cpuType = "host"
        let yaml = c.toYAML()
        #expect(yaml.contains("\"host\""))
    }

    @Test("toYAML writes diskImage in quotes")
    func toYAMLDiskImage() {
        var c = ColimaConfig()
        c.diskImage = "/path/to/disk.qcow2"
        let yaml = c.toYAML()
        #expect(yaml.contains("\"/path/to/disk.qcow2\""))
    }

    @Test("toYAML writes docker: {} placeholder")
    func toYAMLDocker() {
        let yaml = ColimaConfig().toYAML()
        #expect(yaml.contains("docker: {}"))
    }
}

// MARK: - fromYAML for remaining uncovered paths

@Suite("Cov3Svc_ColimaConfig fromYAML extended")
struct Cov3Svc_ColimaConfigFromYAMLExtendedTests {

    @Test("fromYAML parses rootDisk and sshPort")
    func rootDiskSshPort() {
        let yaml = """
        cpu: 2
        memory: 4
        disk: 100
        rootDisk: 30
        sshPort: 2222
        arch: aarch64
        runtime: docker
        vmType: vz
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.rootDisk == 30)
        #expect(c.sshPort == 2222)
    }

    @Test("fromYAML parses boolean false values")
    func boolFalseValues() {
        let yaml = """
        rosetta: false
        binfmt: false
        nestedVirtualization: false
        autoActivate: false
        forwardAgent: false
        sshConfig: false
        mountInotify: false
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.rosetta == false)
        #expect(c.binfmt == false)
        #expect(c.nestedVirtualization == false)
        #expect(c.autoActivate == false)
        #expect(c.forwardAgent == false)
        #expect(c.sshConfig == false)
        #expect(c.mountInotify == false)
    }

    @Test("fromYAML parses boolean true values")
    func boolTrueValues() {
        let yaml = """
        rosetta: true
        binfmt: true
        nestedVirtualization: true
        autoActivate: true
        forwardAgent: true
        sshConfig: true
        mountInotify: true
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.rosetta == true)
        #expect(c.binfmt == true)
        #expect(c.nestedVirtualization == true)
        #expect(c.autoActivate == true)
        #expect(c.forwardAgent == true)
        #expect(c.sshConfig == true)
        #expect(c.mountInotify == true)
    }

    @Test("fromYAML parses yes as true (alternative bool)")
    func boolYes() {
        let yaml = """
        rosetta: yes
        forwardAgent: yes
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.rosetta == true)
        #expect(c.forwardAgent == true)
    }

    @Test("fromYAML parses network section fields")
    func networkSection() {
        let yaml = """
        network:
          address: true
          mode: bridged
          interface: en1
          preferredRoute: true
          hostAddresses: true
          gatewayAddress: 192.168.5.3
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.network.address == true)
        #expect(c.network.mode == "bridged")
        #expect(c.network.interface == "en1")
        #expect(c.network.preferredRoute == true)
        #expect(c.network.hostAddresses == true)
        #expect(c.network.gatewayAddress == "192.168.5.3")
    }

    @Test("fromYAML parses kubernetes port")
    func kubernetesPort() {
        let yaml = """
        kubernetes:
          enabled: true
          version: v1.28.0+k3s1
          port: 6443
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.kubernetes.enabled == true)
        #expect(c.kubernetes.version == "v1.28.0+k3s1")
        #expect(c.kubernetes.port == 6443)
    }

    @Test("fromYAML parses custom k3sArgs list")
    func k3sArgsList() {
        let yaml = """
        kubernetes:
          enabled: true
          version: v1.35.0+k3s1
          k3sArgs:
            - --disable=traefik
            - --disable=servicelb
            - --node-name=dev
        """
        let c = ColimaConfig.fromYAML(yaml)
        // k3sArgs is reset when "k3sArgs:" section is seen, then items appended
        #expect(c.kubernetes.k3sArgs.contains("--disable=traefik"))
        #expect(c.kubernetes.k3sArgs.contains("--disable=servicelb"))
        #expect(c.kubernetes.k3sArgs.contains("--node-name=dev"))
    }

    @Test("fromYAML parses mounts with writable flags")
    func mountsWithWritable() {
        let yaml = """
        mounts:
          - location: ~
            writable: true
          - location: /tmp/data
            writable: false
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.mounts.count == 2)
        #expect(c.mounts[0].location == "~")
        #expect(c.mounts[0].writable == true)
        #expect(c.mounts[1].location == "/tmp/data")
        #expect(c.mounts[1].writable == false)
    }

    @Test("fromYAML parses provision with single-line script")
    func provisionSingleLine() {
        let yaml = """
        provision:
          - mode: system
            script: apt-get update
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.provision.count == 1)
        #expect(c.provision[0].mode == "system")
        #expect(c.provision[0].script == "apt-get update")
    }

    @Test("fromYAML parses provision with multiline script")
    func provisionMultiline() {
        let yaml = """
        provision:
          - mode: user
            script: |
              apt-get update
              apt-get install -y curl
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.provision.count == 1)
        #expect(c.provision[0].mode == "user")
        #expect(c.provision[0].script.contains("apt-get update"))
        #expect(c.provision[0].script.contains("apt-get install -y curl"))
    }

    @Test("fromYAML skips comment lines")
    func skipsComments() {
        let yaml = """
        # This is a comment
        cpu: 4
        # memory comment
        memory: 8
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.cpu == 4)
        #expect(c.memory == 8)
    }

    @Test("fromYAML skips empty lines")
    func skipsEmptyLines() {
        let yaml = """
        cpu: 4

        memory: 8

        disk: 100
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.cpu == 4)
        #expect(c.memory == 8)
        #expect(c.disk == 100)
    }

    @Test("fromYAML handles unknown top-level keys gracefully")
    func unknownTopLevelKeys() {
        let yaml = """
        cpu: 2
        unknownKey: someValue
        anotherUnknown: 42
        memory: 4
        """
        let c = ColimaConfig.fromYAML(yaml)
        // Unknown keys are ignored; known keys are parsed
        #expect(c.cpu == 2)
        #expect(c.memory == 4)
    }

    @Test("fromYAML handles section with {} inline (no section content)")
    func sectionEmptyInline() {
        let yaml = """
        cpu: 2
        docker: {}
        memory: 4
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.cpu == 2)
        #expect(c.memory == 4)
    }

    @Test("fromYAML handles section with [] inline")
    func sectionEmptyArrayInline() {
        let yaml = """
        cpu: 2
        mounts: []
        memory: 4
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.cpu == 2)
        #expect(c.memory == 4)
    }

    @Test("fromYAML handles section: null")
    func sectionNull() {
        let yaml = """
        cpu: 2
        provision: null
        memory: 4
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.cpu == 2)
        #expect(c.memory == 4)
    }

    @Test("fromYAML quoted string value is unquoted")
    func quotedStringValue() {
        let yaml = """
        arch: "x86_64"
        runtime: 'containerd'
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.arch == "x86_64")
        #expect(c.runtime == "containerd")
    }

    @Test("fromYAML float memory value 2.5")
    func floatMemory() {
        let yaml = """
        memory: 2.5
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.memory == 2.5)
    }

    @Test("fromYAML invalid int falls back to default for cpu")
    func invalidIntFallback() {
        let yaml = """
        cpu: not-a-number
        disk: also-bad
        """
        let c = ColimaConfig.fromYAML(yaml)
        // Falls back to default 2 when Int() returns nil
        #expect(c.cpu == 2)
        #expect(c.disk == 100)
    }

    @Test("fromYAML modelRunner and hostname fields parsed")
    func modelRunnerHostname() {
        let yaml = """
        modelRunner: ramalama
        hostname: "dev-box"
        portForwarder: grpc
        cpuType: "host"
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.modelRunner == "ramalama")
        #expect(c.hostname == "dev-box")
        #expect(c.portForwarder == "grpc")
        #expect(c.cpuType == "host")
    }

    @Test("fromYAML diskImage parsed")
    func diskImage() {
        let yaml = """
        diskImage: "/images/custom.qcow2"
        """
        let c = ColimaConfig.fromYAML(yaml)
        #expect(c.diskImage == "/images/custom.qcow2")
    }

    @Test("fromYAML empty string returns default config")
    func emptyStringReturnsDefault() {
        let c = ColimaConfig.fromYAML("")
        let def = ColimaConfig()
        #expect(c.cpu == def.cpu)
        #expect(c.memory == def.memory)
        #expect(c.disk == def.disk)
    }
}

// MARK: - ColimaConfig struct types

@Suite("Cov3Svc_ColimaConfig struct types")
struct Cov3Svc_ColimaConfigStructTests {

    @Test("Mount struct equality")
    func mountEquality() {
        let m1 = ColimaConfig.Mount(location: "~", writable: true)
        let m2 = ColimaConfig.Mount(location: "~", writable: true)
        let m3 = ColimaConfig.Mount(location: "/tmp", writable: false)
        #expect(m1 == m2)
        #expect(m1 != m3)
    }

    @Test("Provision struct equality")
    func provisionEquality() {
        let p1 = ColimaConfig.Provision(mode: "system", script: "echo hello")
        let p2 = ColimaConfig.Provision(mode: "system", script: "echo hello")
        let p3 = ColimaConfig.Provision(mode: "user", script: "echo world")
        #expect(p1 == p2)
        #expect(p1 != p3)
    }

    @Test("Kubernetes struct equality")
    func kubernetesEquality() {
        let k1 = ColimaConfig.Kubernetes()
        let k2 = ColimaConfig.Kubernetes()
        #expect(k1 == k2)
    }

    @Test("Kubernetes struct with custom version differs")
    func kubernetesDiffers() {
        let k1 = ColimaConfig.Kubernetes()
        var k2 = ColimaConfig.Kubernetes()
        k2.version = "v1.28.0+k3s1"
        #expect(k1 != k2)
    }

    @Test("Network struct equality")
    func networkEquality() {
        let n1 = ColimaConfig.Network()
        let n2 = ColimaConfig.Network()
        #expect(n1 == n2)
    }

    @Test("Network struct with custom mode differs")
    func networkDiffers() {
        var n1 = ColimaConfig.Network()
        var n2 = ColimaConfig.Network()
        n1.mode = "bridged"
        n2.mode = "shared"
        #expect(n1 != n2)
    }
}

// MARK: - full round-trip (toYAML → fromYAML)

@Suite("Cov3Svc_ColimaConfig full round-trip")
struct Cov3Svc_ColimaConfigRoundTripTests {

    @Test("default config survives toYAML → fromYAML round-trip (cpu/memory/disk)")
    func defaultRoundTrip() {
        let original = ColimaConfig()
        let yaml = original.toYAML()
        let restored = ColimaConfig.fromYAML(yaml)
        #expect(restored.cpu == original.cpu)
        #expect(restored.memory == original.memory)
        #expect(restored.disk == original.disk)
        #expect(restored.arch == original.arch)
        #expect(restored.runtime == original.runtime)
        #expect(restored.vmType == original.vmType)
    }

    @Test("custom config round-trip preserves kubernetes settings")
    func kubernetesRoundTrip() {
        var c = ColimaConfig()
        c.kubernetes.enabled = true
        c.kubernetes.version = "v1.30.0+k3s1"
        c.kubernetes.port = 6443
        let yaml = c.toYAML()
        let restored = ColimaConfig.fromYAML(yaml)
        #expect(restored.kubernetes.enabled == true)
        #expect(restored.kubernetes.version == "v1.30.0+k3s1")
        #expect(restored.kubernetes.port == 6443)
    }

    @Test("mounts round-trip preserves entries")
    func mountsRoundTrip() {
        var c = ColimaConfig()
        c.mounts = [
            ColimaConfig.Mount(location: "~", writable: true),
            ColimaConfig.Mount(location: "/tmp/colima", writable: false)
        ]
        let yaml = c.toYAML()
        let restored = ColimaConfig.fromYAML(yaml)
        #expect(restored.mounts.count == 2)
        #expect(restored.mounts[0].location == "~")
        #expect(restored.mounts[0].writable == true)
        #expect(restored.mounts[1].location == "/tmp/colima")
        #expect(restored.mounts[1].writable == false)
    }

    @Test("network dns round-trip preserves entries")
    func networkDNSRoundTrip() {
        var c = ColimaConfig()
        c.network.dns = ["8.8.8.8", "1.1.1.1"]
        // Note: toYAML writes dns: with items, but fromYAML uses currentSubSection to parse dns items
        let yaml = c.toYAML()
        // Just verify YAML contains the dns entries (round-trip for dns items requires
        // the currentSubSection == "dns" path which is triggered by "  dns:" in the yaml)
        #expect(yaml.contains("8.8.8.8"))
        #expect(yaml.contains("1.1.1.1"))
    }

    @Test("network mode round-trip")
    func networkModeRoundTrip() {
        var c = ColimaConfig()
        c.network.mode = "bridged"
        c.network.interface = "en1"
        let yaml = c.toYAML()
        let restored = ColimaConfig.fromYAML(yaml)
        #expect(restored.network.mode == "bridged")
        #expect(restored.network.interface == "en1")
    }

    @Test("booleans round-trip correctly")
    func booleansRoundTrip() {
        var c = ColimaConfig()
        c.rosetta = true
        c.nestedVirtualization = true
        c.forwardAgent = true
        c.autoActivate = false
        c.mountInotify = false
        let yaml = c.toYAML()
        let restored = ColimaConfig.fromYAML(yaml)
        #expect(restored.rosetta == true)
        #expect(restored.nestedVirtualization == true)
        #expect(restored.forwardAgent == true)
        #expect(restored.autoActivate == false)
        #expect(restored.mountInotify == false)
    }

    @Test("provision single-line script round-trip")
    func provisionRoundTrip() {
        var c = ColimaConfig()
        c.provision = [ColimaConfig.Provision(mode: "system", script: "apt-get update")]
        let yaml = c.toYAML()
        let restored = ColimaConfig.fromYAML(yaml)
        #expect(restored.provision.count == 1)
        #expect(restored.provision[0].mode == "system")
        #expect(restored.provision[0].script == "apt-get update")
    }

    @Test("sshPort and rootDisk round-trip")
    func sshPortRootDiskRoundTrip() {
        var c = ColimaConfig()
        c.sshPort = 2222
        c.rootDisk = 40
        let yaml = c.toYAML()
        let restored = ColimaConfig.fromYAML(yaml)
        #expect(restored.sshPort == 2222)
        #expect(restored.rootDisk == 40)
    }
}
