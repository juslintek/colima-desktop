import Foundation

struct MockK8sResource {
    let name: String
    let status: String
    let restarts: Int
    let age: String
    let ip: String
}

struct MockK8sService {
    let name: String
    let type: String
    let clusterIP: String
    let ports: String
    let age: String
}

struct MockK8sDeployment {
    let name: String
    let replicas: Int
    let ready: Int
    let upToDate: Int
    let available: Int
    let age: String
}

struct MockK8sNode {
    let name: String
    let status: String
    let roles: String
    let age: String
    let version: String
    let cpuCapacity: Int
    let cpuAllocatable: Int
    let memCapacity: String
    let memAllocatable: String
}

struct MockK8sEvent {
    let lastSeen: String
    let type: String
    let reason: String
    let object: String
    let message: String
}

struct MockModel {
    let name: String
    let registry: String
    let size: String
    let status: String // idle, running, serving
    let port: Int?
    let requiredRAM: Int // GiB
}

struct MockDiscussion {
    let title: String
    let author: String
    let date: String
    let reactions: Int
    let category: String
    let url: String
}

struct MockK8sData {
    // MARK: - Kubernetes Resources

    static let pods: [MockK8sResource] = [
        MockK8sResource(name: "nginx-7c5b4f", status: "Running", restarts: 0, age: "2h", ip: "10.42.0.5"),
        MockK8sResource(name: "coredns-5c98db", status: "Running", restarts: 0, age: "3h", ip: "10.42.0.3"),
        MockK8sResource(name: "traefik-8b7d2a", status: "Running", restarts: 1, age: "3h", ip: "10.42.0.4"),
        MockK8sResource(name: "metrics-server-6d4c", status: "Running", restarts: 0, age: "3h", ip: "10.42.0.6"),
        MockK8sResource(name: "local-path-provisioner-7f", status: "Running", restarts: 0, age: "3h", ip: "10.42.0.2"),
        MockK8sResource(name: "svclb-traefik-9e3f", status: "Running", restarts: 0, age: "3h", ip: "10.42.0.7"),
    ]

    static let services: [MockK8sService] = [
        MockK8sService(name: "kubernetes", type: "ClusterIP", clusterIP: "10.43.0.1", ports: "443/TCP", age: "3h"),
        MockK8sService(name: "kube-dns", type: "ClusterIP", clusterIP: "10.43.0.10", ports: "53/UDP,53/TCP,9153/TCP", age: "3h"),
        MockK8sService(name: "traefik", type: "LoadBalancer", clusterIP: "10.43.128.5", ports: "80:31080/TCP,443:31443/TCP", age: "3h"),
        MockK8sService(name: "metrics-server", type: "ClusterIP", clusterIP: "10.43.0.100", ports: "443/TCP", age: "3h"),
    ]

    static let deployments: [MockK8sDeployment] = [
        MockK8sDeployment(name: "coredns", replicas: 1, ready: 1, upToDate: 1, available: 1, age: "3h"),
        MockK8sDeployment(name: "traefik", replicas: 1, ready: 1, upToDate: 1, available: 1, age: "3h"),
        MockK8sDeployment(name: "metrics-server", replicas: 1, ready: 1, upToDate: 1, available: 1, age: "3h"),
    ]

    static let nodes: [MockK8sNode] = [
        MockK8sNode(name: "colima", status: "Ready", roles: "control-plane,master", age: "3h", version: "v1.28.3+k3s1", cpuCapacity: 4, cpuAllocatable: 4, memCapacity: "8Gi", memAllocatable: "7.5Gi"),
    ]

    static let events: [MockK8sEvent] = [
        MockK8sEvent(lastSeen: "2m", type: "Normal", reason: "Scheduled", object: "pod/nginx-7c5b4f", message: "Successfully assigned default/nginx-7c5b4f to colima"),
        MockK8sEvent(lastSeen: "2m", type: "Normal", reason: "Pulled", object: "pod/nginx-7c5b4f", message: "Container image \"nginx:latest\" already present on machine"),
        MockK8sEvent(lastSeen: "2m", type: "Normal", reason: "Created", object: "pod/nginx-7c5b4f", message: "Created container nginx"),
        MockK8sEvent(lastSeen: "2m", type: "Normal", reason: "Started", object: "pod/nginx-7c5b4f", message: "Started container nginx"),
        MockK8sEvent(lastSeen: "5m", type: "Normal", reason: "ScalingReplicaSet", object: "deployment/coredns", message: "Scaled up replica set coredns-5c98db to 1"),
        MockK8sEvent(lastSeen: "10m", type: "Warning", reason: "BackOff", object: "pod/traefik-8b7d2a", message: "Back-off restarting failed container"),
        MockK8sEvent(lastSeen: "15m", type: "Normal", reason: "NodeReady", object: "node/colima", message: "Node colima status is now: NodeReady"),
        MockK8sEvent(lastSeen: "20m", type: "Normal", reason: "RegisteredNode", object: "node/colima", message: "Node colima event: Registered Node colima in Controller"),
    ]

    static func podYAML(_ name: String) -> String {
        """
        apiVersion: v1
        kind: Pod
        metadata:
          name: \(name)
          namespace: default
        spec:
          containers:
          - name: \(name.components(separatedBy: "-").first ?? name)
            image: nginx:latest
            ports:
            - containerPort: 80
          nodeName: colima
        status:
          phase: Running
          podIP: 10.42.0.5
        """
    }

    // MARK: - AI Models

    static let aiModels: [MockModel] = [
        MockModel(name: "gemma3", registry: "docker", size: "2.1GB", status: "idle", port: nil, requiredRAM: 8),
        MockModel(name: "phi4", registry: "docker", size: "8.2GB", status: "serving", port: 8080, requiredRAM: 12),
        MockModel(name: "tinyllama", registry: "ollama", size: "637MB", status: "idle", port: nil, requiredRAM: 4),
    ]

    static let dockerAIModels: [(name: String, desc: String, size: String)] = [
        ("ai/gemma3", "Google Gemma 3 — lightweight open model", "~2.1GB"),
        ("ai/llama3", "Meta Llama 3 — high-quality open model", "~4.7GB"),
        ("ai/phi4", "Microsoft Phi-4 — efficient reasoning model", "~8.2GB"),
        ("ai/mistral", "Mistral AI — fast inference model", "~4.1GB"),
    ]

    static let huggingFaceModels: [(name: String, desc: String, size: String)] = [
        ("google/gemma-3-2b", "Gemma 3 2B parameters", "~2.1GB"),
        ("meta-llama/Llama-3-8B", "Llama 3 8B parameters", "~4.7GB"),
        ("microsoft/phi-4", "Phi-4 14B parameters", "~8.2GB"),
    ]

    static let ollamaModels: [(name: String, desc: String, size: String)] = [
        ("tinyllama", "TinyLlama 1.1B — ultra lightweight", "~637MB"),
        ("gemma3", "Google Gemma 3", "~2.1GB"),
        ("llama3", "Meta Llama 3", "~4.7GB"),
        ("codellama", "Code Llama — code generation", "~3.8GB"),
    ]

    // MARK: - Discussions

    static let discussions: [MockDiscussion] = [
        MockDiscussion(title: "How to use localhost to access Docker containers", author: "devuser42", date: "2d ago", reactions: 45, category: "Q&A", url: "https://github.com/abiosoft/colima/discussions/1"),
        MockDiscussion(title: "Colima vs Docker Desktop performance comparison", author: "benchmarker", date: "3d ago", reactions: 32, category: "General", url: "https://github.com/abiosoft/colima/discussions/2"),
        MockDiscussion(title: "Running GPU workloads with krunkit", author: "mldev", date: "5d ago", reactions: 28, category: "Show and Tell", url: "https://github.com/abiosoft/colima/discussions/3"),
        MockDiscussion(title: "Best practices for multi-profile setups", author: "k8suser", date: "1w ago", reactions: 19, category: "Q&A", url: "https://github.com/abiosoft/colima/discussions/4"),
        MockDiscussion(title: "Colima 0.10 release notes discussion", author: "abiosoft", date: "2w ago", reactions: 67, category: "General", url: "https://github.com/abiosoft/colima/discussions/5"),
    ]
}
