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

    private let bgColor = Color(red: 0.1, green: 0.1, blue: 0.12)
    private let inputBg = Color(red: 0.08, green: 0.08, blue: 0.1)
    private let promptColor = Color(red: 0.4, green: 0.87, blue: 0.4)
    private let outputColor = Color(red: 0.8, green: 0.8, blue: 0.8)
    private let cmdColor = Color(red: 0.55, green: 0.82, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(output.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("$") ? promptColor : outputColor)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(bgColor)

            HStack(spacing: 4) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(promptColor)
                TextField("Enter command…", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .onSubmit {
                        guard !command.isEmpty else { return }
                        output.append("$ \(command)")
                        output.append(MockDetailData.commandOutput(tool: "docker", args: command))
                        command = ""
                    }
            }
            .padding(8)
            .background(inputBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
