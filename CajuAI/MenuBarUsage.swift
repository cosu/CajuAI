import Foundation

struct MenuBarUsage {
    let text: String
    let systemImage: String
    let changedAt: Date?

    /// Prefers the provider whose usage number moved most recently.
    /// Before any value has changed, falls back to the first non-empty label (Claude).
    static func pick(_ items: [MenuBarUsage]) -> MenuBarUsage? {
        let changed = items.filter { $0.changedAt != nil && !$0.text.isEmpty }
        if let latest = changed.max(by: { $0.changedAt! < $1.changedAt! }) {
            return latest
        }
        return items.first(where: { !$0.text.isEmpty })
    }
}
