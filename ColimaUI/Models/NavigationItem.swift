import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case dashboard, containers, images, volumes, networks
    case configuration, profiles, kubernetes, ai, monitoring
    case runtimeControls, community

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .containers: return "Containers"
        case .images: return "Images"
        case .volumes: return "Volumes"
        case .networks: return "Networks"
        case .configuration: return "Configuration"
        case .profiles: return "Profiles"
        case .kubernetes: return "Kubernetes"
        case .ai: return "AI Workloads"
        case .monitoring: return "Monitoring"
        case .runtimeControls: return "Runtime Controls"
        case .community: return "Community"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge"
        case .containers: return "shippingbox"
        case .images: return "photo.stack"
        case .volumes: return "externaldrive"
        case .networks: return "network"
        case .configuration: return "gearshape"
        case .profiles: return "person.2"
        case .kubernetes: return "helm"
        case .ai: return "brain"
        case .monitoring: return "chart.bar"
        case .runtimeControls: return "gearshape.2"
        case .community: return "bubble.left.and.bubble.right"
        }
    }

    var accessibilityId: String {
        switch self {
        case .runtimeControls: return "tab_runtimecontrols"
        default: return "tab_\(rawValue)"
        }
    }
}
