import Foundation

/// Represents a real AI model from `colima model list` output.
struct AIModelInfo: Identifiable {
    let id: String
    let name: String
    let size: String
    let status: String // "idle", "running", "serving"
    let port: Int?

    /// Parse `colima model list` output (table format) into model structs.
    static func parse(_ output: String) -> [AIModelInfo] {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        // Skip header line, parse each row
        return lines.dropFirst().compactMap { line in
            let cols = line.split(separator: /\s{2,}/).map(String.init)
            guard cols.count >= 3 else { return nil }
            let name = cols[0]
            let size = cols.count > 1 ? cols[1] : ""
            let status = cols.count > 2 ? cols[2].lowercased() : "idle"
            let port = cols.count > 3 ? Int(cols[3].replacingOccurrences(of: ":", with: "")) : nil
            return AIModelInfo(id: name, name: name, size: size, status: status, port: port)
        }
    }
}
