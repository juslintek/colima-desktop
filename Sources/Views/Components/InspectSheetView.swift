import SwiftUI

struct InspectSheetView: View {
    let title: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspect: \(title)").font(.headline)
                Spacer()
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content, forType: .string) }
                    .accessibilityIdentifier("btn_copy_inspect")
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_inspect")
            }
            .padding()

            Divider()

            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .accessibilityIdentifier("sheet_inspect")
    }
}
