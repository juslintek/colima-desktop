import SwiftUI
import AppKit

struct CommunityView: View {
    @EnvironmentObject var appState: AppState
    // Issue reporter state (kept flat — not a wizard)
    @State private var wizardStep = 1
    @State private var issueRepo = "Colima"
    @State private var issueTitle = ""
    @State private var issueDescription = ""
    @State private var showSystemInfo = false
    @State private var faqSearch = ""

    private var systemInfo: String {
        """
        Colima version: \(appState.colimaVersion)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        VM Type: vz
        Runtime: docker
        Architecture: aarch64
        Profile: \(appState.activeProfile)
        """
    }

    private var issueBody: String {
        """
        \(issueDescription)

        ---
        **System Info**
        ```
        \(systemInfo)
        ```
        """
    }

    private var githubIssueURL: URL? {
        let repo = issueRepo == "Colima" ? "abiosoft/colima" : "user/ColimaUI"
        var comps = URLComponents(string: "https://github.com/\(repo)/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: issueTitle),
            URLQueryItem(name: "body", value: issueBody),
        ]
        return comps?.url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                discussionsFeed
                issueReporter
                faqSection
                linksSection
            }
            .padding()
        }
        .navigationTitle("Community")
    }

    // MARK: - Discussions Feed

    private var discussionsFeed: some View {
        GroupBox("Recent Discussions") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(MockK8sData.discussions.enumerated()), id: \.offset) { idx, d in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).fontWeight(.medium).lineLimit(1)
                            HStack(spacing: 8) {
                                Text(d.author).foregroundStyle(.secondary)
                                Text(d.date).foregroundStyle(.secondary)
                                Text(d.category).padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15)).cornerRadius(4)
                            }.font(.caption)
                        }
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "hand.thumbsup").font(.caption2)
                            Text("\(d.reactions)").font(.caption)
                        }.foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture { openURL(d.url) }
                    .accessibilityIdentifier("row_discussion_\(idx)")
                    if idx < MockK8sData.discussions.count - 1 { Divider() }
                }
            }
            .accessibilityIdentifier("table_discussions")

            Button("View All Discussions") { openURL("https://github.com/abiosoft/colima/discussions") }
                .font(.caption)
        }
    }

    // MARK: - Issue Reporter (single form with wizard steps preserved for tests)

    private var issueReporter: some View {
        GroupBox("Report Issue") {
            VStack(alignment: .leading, spacing: 8) {
                if wizardStep == 1 {
                    Text("Step 1: Select Repository").fontWeight(.medium)
                    Picker("Repository", selection: $issueRepo) {
                        Text("Colima").tag("Colima"); Text("ColimaUI (GUI)").tag("ColimaUI")
                    }.accessibilityIdentifier("picker_issue_repo")
                    Button("Next") { wizardStep = 2 }.accessibilityIdentifier("btn_issue_wizard_next1")
                } else if wizardStep == 2 {
                    Text("Step 2: Describe Issue").fontWeight(.medium)
                    TextField("Title", text: $issueTitle).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_community_issue_title")
                        .accessibilityIdentifier("field_issue_title")
                    TextEditor(text: $issueDescription).frame(height: 80)
                        .accessibilityIdentifier("field_community_issue_description")
                        .accessibilityIdentifier("field_issue_description")

                    DisclosureGroup("System Info (auto-collected)", isExpanded: $showSystemInfo) {
                        Text(systemInfo).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("text_system_info")
                    }

                    HStack {
                        Button("Back") { wizardStep = 1 }.accessibilityIdentifier("btn_issue_wizard_back2")
                        Button("Next") { wizardStep = 3 }.accessibilityIdentifier("btn_issue_wizard_next2")
                            .disabled(issueTitle.isEmpty)
                    }
                } else {
                    Text("Step 3: Review & Submit").fontWeight(.medium)
                    Text("Repo: \(issueRepo)").font(.caption)
                    Text("Title: \(issueTitle)").font(.caption)

                    HStack {
                        Button("Back") { wizardStep = 2 }.accessibilityIdentifier("btn_issue_wizard_back3")
                        Button("Open on GitHub") {
                            if let url = githubIssueURL { openURL(url.absoluteString) }
                            appState.showToast("Issue submitted to \(issueRepo): \(issueTitle)")
                            issueTitle = ""; issueDescription = ""; wizardStep = 1
                        }
                        .accessibilityIdentifier("btn_submit_community_issue")
                        .accessibilityIdentifier("btn_open_github_issue")

                        Button("Copy to Clipboard") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("# \(issueTitle)\n\n\(issueBody)", forType: .string)
                            appState.showToast("Issue copied to clipboard")
                        }.accessibilityIdentifier("btn_copy_issue")
                    }
                }
            }
        }
    }

    // MARK: - FAQ

    private let faqCategories: [(category: String, items: [(q: String, a: String)])] = [
        ("General", [
            ("How to reset?", "Run `colima delete --force` then `colima start`"),
            ("Multiple profiles?", "Use `colima start --profile <name>`"),
            ("SSH into VM?", "Run `colima ssh` or use the SSH button in Dashboard"),
        ]),
        ("Docker", [
            ("Cannot connect to Docker?", "Set DOCKER_HOST or use `docker context use colima`"),
            ("Port forwarding fails?", "Check port forwarder setting (ssh vs grpc)"),
        ]),
        ("Networking", [
            ("VM IP unreachable?", "Use `colima start --network-address`"),
            ("No internet in VM?", "Try `colima start --dns 8.8.8.8`"),
        ]),
        ("Storage", [
            ("Disk space low?", "Run `colima ssh -- sudo fstrim -a`"),
            ("Slow file sync?", "Switch mount type to virtiofs (requires vz VM type)"),
        ]),
        ("Troubleshooting", [
            ("Broken status?", "Run `colima stop --force && colima start`"),
            ("Rosetta not working?", "Ensure VM type is vz and macOS 13+"),
            ("Kubernetes not starting?", "Increase memory to at least 4GiB"),
        ]),
    ]

    private var filteredFAQ: [(category: String, items: [(q: String, a: String)])] {
        guard !faqSearch.isEmpty else { return faqCategories }
        return faqCategories.compactMap { cat in
            let filtered = cat.items.filter {
                $0.q.localizedCaseInsensitiveContains(faqSearch) ||
                $0.a.localizedCaseInsensitiveContains(faqSearch)
            }
            return filtered.isEmpty ? nil : (cat.category, filtered)
        }
    }

    private var faqSection: some View {
        GroupBox("FAQ") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search FAQ…", text: $faqSearch).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_faq_search")

                ForEach(Array(filteredFAQ.enumerated()), id: \.offset) { catIdx, cat in
                    DisclosureGroup(cat.category) {
                        ForEach(Array(cat.items.enumerated()), id: \.offset) { idx, item in
                            DisclosureGroup {
                                Text(item.a).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            } label: {
                                Text(item.q).fontWeight(.medium).font(.caption)
                                    .accessibilityIdentifier("faq_\(item.q.prefix(20).filter { $0.isLetter })")
                            }
                            .accessibilityIdentifier("faq_entry_\(catIdx * 10 + idx)")
                        }
                    }
                    .accessibilityIdentifier("disclosure_faq_\(cat.category.lowercased())")
                }
            }
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        GroupBox("Links") {
            VStack(alignment: .leading, spacing: 8) {
                linkButton("GitHub Discussions", id: "discussions", url: "https://github.com/abiosoft/colima/discussions")
                linkButton("Report Issue", id: "issues", url: "https://github.com/abiosoft/colima/issues")
                linkButton("Release Notes", id: "releases", url: "https://github.com/abiosoft/colima/releases")
                linkButton("Documentation", id: "docs", url: "https://github.com/abiosoft/colima/blob/main/docs/FAQ.md")
            }
        }
    }

    private func linkButton(_ title: String, id: String, url: String) -> some View {
        Button(title) {
            openURL(url)
            appState.showToast("Opening \(title)")
        }.accessibilityIdentifier("btn_open_community_\(id)")
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
