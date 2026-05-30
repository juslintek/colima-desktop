import SwiftUI
import AppKit

struct TerminalSheetView: View {
    let command: String
    @State private var history: [String] = []
    @State private var input = ""
    @Environment(\.dismiss) private var dismiss

    private static let mockResponses: [String: String] = [
        "ls": "bin  boot  dev  etc  home  lib  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var",
        "whoami": "user",
        "pwd": "/home/user",
        "uname -a": "Linux colima 6.1.0-18-arm64 #1 SMP Debian 6.1.76-1 aarch64 GNU/Linux",
        "hostname": "colima",
        "date": "Mon Apr 27 10:42:00 UTC 2026",
        "uptime": " 10:42:00 up 2:12, 1 user, load average: 0.15, 0.10, 0.05",
        "df -h": "Filesystem      Size  Used Avail Use% Mounted on\n/dev/vda1        99G   12G   82G  13% /",
        "free -h": "              total        used        free\nMem:          7.8Gi       2.1Gi       4.2Gi\nSwap:         2.0Gi          0B       2.0Gi",
        "ps aux": "USER       PID %CPU %MEM COMMAND\nroot         1  0.0  0.1 /sbin/init\nroot       128  0.0  0.2 /usr/sbin/sshd\nuser       256  0.0  0.1 -bash",
    ]

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
                        Text("Connected.\n").font(.system(.body, design: .monospaced)).foregroundStyle(.white)
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
                .onChange(of: history.count) { _ in
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
                    .onSubmit { runCommand() }
            }
            .padding(8)
            .background(Color.black)
        }
        .frame(minWidth: 650, minHeight: 400)
        .accessibilityIdentifier("sheet_terminal")
        .accessibilityValue(command)
    }

    private func runCommand() {
        let cmd = input.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        history.append("user@colima:~$ \(cmd)")
        let response = Self.mockResponses[cmd] ?? "\(cmd.components(separatedBy: " ").first ?? cmd): command executed"
        history.append(response)
        input = ""
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
