import SwiftUI

/// Profile-scoped template read/edit/save surface over `GetTemplate` /
/// `SetTemplate`. Reads the active profile's colima VM template, lets the user
/// edit it as YAML with validation, and saves it back. Template edits are the
/// base config for newly created VMs — they do not modify a running VM.
struct TemplateEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var validationIssues: [String] {
        ColimaTemplate.validationIssues(appState.templateYAML)
    }

    private var isValid: Bool { validationIssues.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            restartNoteBanner
            editor
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 520)
        .accessibilityIdentifier("sheet_template_editor")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.gearshape").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Edit VM Template").font(.headline)
                Text("Profile: \(appState.templateProfile)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("label_template_profile")
            }
            Spacer()
            if appState.isTemplateLoading {
                ProgressView().controlSize(.small)
                    .accessibilityIdentifier("progress_template_loading")
            }
            Button("Close") { dismiss() }
                .accessibilityIdentifier("btn_template_close")
        }
        .padding()
    }

    // MARK: - Restart-implications note

    private var restartNoteBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(ColimaTemplate.restartNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
        .accessibilityIdentifier("note_template_restart")
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Template YAML").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextEditor(text: $appState.templateYAML)
                .font(.system(.body, design: .monospaced))
                .disableAutocorrection(true)
                .scrollContentBackground(.hidden)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                .frame(minHeight: 300)
                .accessibilityIdentifier("field_template_yaml")
            validationSummary
        }
        .padding()
    }

    // Live validation feedback — recomputed from the current editor text on
    // every change, so it is never stale.
    @ViewBuilder
    private var validationSummary: some View {
        if isValid {
            Label("Valid colima YAML", systemImage: "checkmark.seal")
                .font(.caption).foregroundStyle(.green)
                .accessibilityIdentifier("label_template_validation")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(validationIssues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("label_template_validation")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Reload") { appState.reloadTemplateFromDisk() }
                .disabled(appState.isTemplateLoading)
                .accessibilityIdentifier("btn_template_reload")
            Spacer()
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("btn_template_cancel")
            Button("Save Template") { appState.saveTemplateEdits() }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isTemplateLoading || !isValid)
                .accessibilityIdentifier("btn_template_save")
        }
        .padding()
    }
}
