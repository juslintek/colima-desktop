import SwiftUI

struct MockTerminalView: View {
    let name: String
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var command = ""
    @State private var output: [String] = ["$ "]

    private var bgColor: Color {
        colorScheme == .dark ? Color(red: 0.96, green: 0.96, blue: 0.97) : Color(red: 0.1, green: 0.1, blue: 0.12)
    }
    private var inputBg: Color {
        colorScheme == .dark ? Color(red: 0.93, green: 0.93, blue: 0.94) : Color(red: 0.08, green: 0.08, blue: 0.1)
    }
    private var promptColor: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.5, blue: 0.1) : Color(red: 0.4, green: 0.87, blue: 0.4)
    }
    private var outputColor: Color {
        colorScheme == .dark ? Color(red: 0.2, green: 0.2, blue: 0.25) : Color(red: 0.8, green: 0.8, blue: 0.8)
    }
    private var inputTextColor: Color {
        colorScheme == .dark ? .black : .white
    }
    private var borderColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.1) : Color.white.opacity(0.1)
    }

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
                    .foregroundStyle(inputTextColor)
                    .onSubmit {
                        guard !command.isEmpty else { return }
                        let cmd = command
                        output.append("$ \(cmd)")
                        command = ""
                        let parts = cmd.components(separatedBy: " ")
                        let tool = parts.first ?? "docker"
                        let args = Array(parts.dropFirst())
                        appState.executeCommand(tool: tool, args: args) { result in
                            output.append(result)
                        }
                    }
            }
            .padding(8)
            .background(inputBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor))
    }
}
