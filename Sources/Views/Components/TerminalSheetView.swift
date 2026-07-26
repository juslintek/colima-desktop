import SwiftUI
import AppKit

struct TerminalSheetView: View {
    let command: String
    @State private var history: [String] = []
    @State private var input = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(command).font(.system(.headline, design: .monospaced))
                Spacer()
                Button("Open in Terminal.app") { openInTerminal() }
                    .accessibilityIdentifier("btn_open_terminal_external")
                    .accessibilityValue(command)
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_terminal")
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("$ \(command)").font(.system(.body, design: .monospaced)).foregroundStyle(.green)
                        Text("Interactive execution is delegated to Terminal.app. No output is simulated here.\n")
                            .font(.system(.body, design: .monospaced)).foregroundStyle(.white)
                        ForEach(Array(history.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("user@colima") ? .green : .white)
                                .id(idx)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .onChange(of: history.count) {
                    if let last = history.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .background(Color.black)

            HStack {
                Text("user@colima:~$").font(.system(.body, design: .monospaced)).foregroundStyle(.green)
                TextField("", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("field_terminal_input")
                    .disabled(true)
            }
            .padding(8)
            .background(Color.black)
        }
        .frame(minWidth: 650, minHeight: 400)
        .accessibilityIdentifier("sheet_terminal")
        .accessibilityValue(command)
    }

    private func openInTerminal() {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
