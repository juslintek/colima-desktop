import SwiftUI

struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let size: String?
    let children: [FileNode]?

    var isDirectory: Bool { children != nil }
}

struct MockFileTree: View {
    private let roots: [FileNode] = [
        FileNode(name: "app", size: nil, children: [
            FileNode(name: "server.js", size: "2.1 KB", children: nil),
            FileNode(name: "package.json", size: "1.4 KB", children: nil),
            FileNode(name: "node_modules", size: "847 items", children: []),
        ]),
        FileNode(name: "etc", size: nil, children: [
            FileNode(name: "nginx", size: nil, children: [
                FileNode(name: "nginx.conf", size: "2.8 KB", children: nil),
            ]),
            FileNode(name: "hosts", size: "0.2 KB", children: nil),
        ]),
        FileNode(name: "var", size: nil, children: [
            FileNode(name: "log", size: nil, children: [
                FileNode(name: "access.log", size: "45.2 KB", children: nil),
                FileNode(name: "error.log", size: "12.1 KB", children: nil),
            ]),
        ]),
        FileNode(name: "tmp", size: "empty", children: []),
    ]

    var body: some View {
        List {
            OutlineGroup(roots, children: \.children) { node in
                HStack {
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                        .foregroundStyle(node.isDirectory ? .blue : .secondary)
                        .frame(width: 16)
                    Text(node.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    if let size = node.size {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}
