import SwiftUI

struct MockTerminalView: View {
    let name: String
    @State private var command = ""
    @State private var output: [String] = [
        "$ whoami",
        "root",
        "$ ls /",
        "app  bin  dev  etc  home  lib  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var",
        "$ "
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(output.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.9))

            HStack(spacing: 4) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.green)
                TextField("Enter command…", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        guard !command.isEmpty else { return }
                        output.append("$ \(command)")
                        output.append(MockDetailData.commandOutput(tool: "docker", args: command))
                        command = ""
                    }
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .foregroundStyle(.green)
    }
}
