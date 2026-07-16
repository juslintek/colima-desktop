import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - MockK8sData

@Suite("MockK8sData")
struct MockK8sDataTests {

    @Test("pods array is non-empty and has correct structure")
    func pods() {
        #expect(!MockK8sData.pods.isEmpty)
        let first = MockK8sData.pods[0]
        #expect(!first.name.isEmpty)
        #expect(!first.status.isEmpty)
        #expect(!first.ip.isEmpty)
        #expect(!first.age.isEmpty)
    }

    @Test("systemPods array is non-empty and all Running")
    func systemPods() {
        #expect(!MockK8sData.systemPods.isEmpty)
        for pod in MockK8sData.systemPods {
            #expect(pod.status == "Running")
        }
    }

    @Test("services array has correct types")
    func services() {
        #expect(!MockK8sData.services.isEmpty)
        let svc = MockK8sData.services[0]
        #expect(!svc.name.isEmpty)
        #expect(!svc.type.isEmpty)
        #expect(!svc.clusterIP.isEmpty)
        #expect(!svc.ports.isEmpty)
    }

    @Test("deployments array has valid replica counts")
    func deployments() {
        #expect(!MockK8sData.deployments.isEmpty)
        for dep in MockK8sData.deployments {
            #expect(dep.replicas >= 0)
            #expect(dep.ready >= 0)
            #expect(dep.available >= 0)
        }
    }

    @Test("nodes array has one entry: colima")
    func nodes() {
        #expect(MockK8sData.nodes.count == 1)
        let node = MockK8sData.nodes[0]
        #expect(node.name == "colima")
        #expect(node.status == "Ready")
        #expect(node.cpuCapacity > 0)
        #expect(!node.memCapacity.isEmpty)
    }

    @Test("events array has both Normal and Warning types")
    func events() {
        #expect(!MockK8sData.events.isEmpty)
        let types = Set(MockK8sData.events.map { $0.type })
        #expect(types.contains("Normal"))
        #expect(types.contains("Warning"))
    }

    @Test("podYAML generates valid YAML string with pod name")
    func podYAML() {
        let yaml = MockK8sData.podYAML("my-test-pod")
        #expect(yaml.contains("my-test-pod"))
        #expect(yaml.contains("apiVersion: v1"))
        #expect(yaml.contains("kind: Pod"))
        #expect(yaml.contains("namespace: default"))
        #expect(yaml.contains("phase: Running"))
    }

    @Test("aiModels array has expected models")
    func aiModels() {
        #expect(!MockK8sData.aiModels.isEmpty)
        let names = MockK8sData.aiModels.map { $0.name }
        #expect(names.contains("gemma3"))
        #expect(names.contains("phi4"))
    }

    @Test("aiModels have non-negative requiredRAM")
    func aiModelsRAM() {
        for model in MockK8sData.aiModels {
            #expect(model.requiredRAM >= 0)
            #expect(!model.name.isEmpty)
            #expect(!model.size.isEmpty)
        }
    }

    @Test("dockerAIModels array is non-empty")
    func dockerAIModels() {
        #expect(!MockK8sData.dockerAIModels.isEmpty)
        for entry in MockK8sData.dockerAIModels {
            #expect(!entry.name.isEmpty)
            #expect(!entry.desc.isEmpty)
        }
    }

    @Test("discussions array has non-empty entries with valid categories")
    func discussions() {
        #expect(!MockK8sData.discussions.isEmpty)
        let validCategories = ["Q&A", "General", "Show and Tell"]
        for d in MockK8sData.discussions {
            #expect(!d.title.isEmpty)
            #expect(!d.author.isEmpty)
            #expect(validCategories.contains(d.category))
            #expect(d.reactions >= 0)
            #expect(d.url.hasPrefix("https://"))
        }
    }
}

// MARK: - MockK8sResource struct

@Suite("MockK8s structs")
struct MockK8sStructTests {

    @Test("MockK8sResource stores all fields")
    func resource() {
        let r = MockK8sResource(name: "nginx-pod", status: "Running", restarts: 2, age: "1h", ip: "10.42.0.5")
        #expect(r.name == "nginx-pod")
        #expect(r.status == "Running")
        #expect(r.restarts == 2)
        #expect(r.age == "1h")
        #expect(r.ip == "10.42.0.5")
    }

    @Test("MockK8sService stores all fields")
    func service() {
        let s = MockK8sService(name: "kubernetes", type: "ClusterIP", clusterIP: "10.43.0.1", ports: "443/TCP", age: "3h")
        #expect(s.name == "kubernetes")
        #expect(s.type == "ClusterIP")
        #expect(s.clusterIP == "10.43.0.1")
        #expect(s.ports == "443/TCP")
        #expect(s.age == "3h")
    }

    @Test("MockK8sDeployment stores all fields")
    func deployment() {
        let d = MockK8sDeployment(name: "coredns", replicas: 2, ready: 2, upToDate: 2, available: 2, age: "3h")
        #expect(d.name == "coredns")
        #expect(d.replicas == 2)
        #expect(d.ready == 2)
        #expect(d.upToDate == 2)
        #expect(d.available == 2)
    }

    @Test("MockK8sNode stores all fields including capacity")
    func node() {
        let n = MockK8sNode(name: "colima", status: "Ready", roles: "control-plane", age: "3h", version: "v1.28.3+k3s1", cpuCapacity: 4, cpuAllocatable: 4, memCapacity: "8Gi", memAllocatable: "7.5Gi")
        #expect(n.name == "colima")
        #expect(n.cpuCapacity == 4)
        #expect(n.memCapacity == "8Gi")
        #expect(n.roles.contains("control-plane"))
    }

    @Test("MockK8sEvent stores all fields")
    func event() {
        let e = MockK8sEvent(lastSeen: "2m", type: "Warning", reason: "BackOff", object: "pod/nginx", message: "Back-off restarting failed container")
        #expect(e.type == "Warning")
        #expect(e.reason == "BackOff")
        #expect(e.object == "pod/nginx")
        #expect(!e.message.isEmpty)
    }

    @Test("MockModel with nil port stores correctly")
    func mockModelNilPort() {
        let m = MockModel(name: "gemma3", registry: "docker", size: "2.1GB", status: "idle", port: nil, requiredRAM: 8)
        #expect(m.name == "gemma3")
        #expect(m.port == nil)
        #expect(m.requiredRAM == 8)
    }

    @Test("MockModel with non-nil port stores correctly")
    func mockModelWithPort() {
        let m = MockModel(name: "phi4", registry: "docker", size: "8.2GB", status: "serving", port: 8080, requiredRAM: 12)
        #expect(m.port == 8080)
        #expect(m.status == "serving")
    }

    @Test("MockDiscussion stores all fields")
    func mockDiscussion() {
        let d = MockDiscussion(title: "Test Discussion", author: "testuser", date: "1d ago", reactions: 5, category: "Q&A", url: "https://github.com/test")
        #expect(d.title == "Test Discussion")
        #expect(d.author == "testuser")
        #expect(d.reactions == 5)
        #expect(d.url.hasPrefix("https://"))
    }
}

// MARK: - FileNode

@Suite("FileNode")
struct FileNodeTests {

    @Test("isDirectory returns true when children are present")
    func isDirectoryTrue() {
        let node = FileNode(name: "app", size: nil, children: [])
        #expect(node.isDirectory == true)
    }

    @Test("isDirectory returns false when children is nil")
    func isDirectoryFalse() {
        let node = FileNode(name: "server.js", size: "2.1 KB", children: nil)
        #expect(node.isDirectory == false)
    }

    @Test("id is unique per instance")
    func uniqueId() {
        let a = FileNode(name: "a", size: nil, children: nil)
        let b = FileNode(name: "b", size: nil, children: nil)
        #expect(a.id != b.id)
    }

    @Test("nested children are accessible")
    func nestedChildren() {
        let child = FileNode(name: "child.js", size: "1KB", children: nil)
        let parent = FileNode(name: "src", size: nil, children: [child])
        #expect(parent.children?.count == 1)
        #expect(parent.children?[0].name == "child.js")
    }

    @Test("size is stored correctly")
    func sizeField() {
        let node = FileNode(name: "package.json", size: "1.4 KB", children: nil)
        #expect(node.size == "1.4 KB")
    }
}
