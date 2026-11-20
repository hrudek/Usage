import Foundation
import UsageKit

/// How an account card is composed (4.0): one window as its protagonist,
/// drawn large, and the rest of `WindowSlots` as compact one-line rows
/// under it, in their own order. The session slot always leads, whatever
/// its usage, also as the placeholder before the first fetch. Without a
/// session slot (Codex Free's single monthly window) the window closest
/// to its limit leads: its used percentage, a window the provider flags
/// critical or exceeded counting as full, ties keeping the slots' order.
struct AccountCardLayout {
    typealias Slot = (kind: UsageWindow.Kind, window: UsageWindow?)

    let hero: Slot
    let others: [Slot]
    /// Where the protagonist sat in `WindowSlots`, for callers that need
    /// the grouped reset rule over the original order.
    let heroIndex: Int

    init(slots: [Slot]) {
        let index = Self.heroIndex(in: slots)
        heroIndex = index
        if slots.indices.contains(index) {
            hero = slots[index]
            var rest = slots
            rest.remove(at: index)
            others = rest
        } else {
            hero = (.session, nil)
            others = []
        }
    }

    init(snapshot: UsageSnapshot?, modelSlotFallback: ModelSlotFallback) {
        self.init(slots: WindowSlots(snapshot: snapshot, modelSlotFallback: modelSlotFallback).slots)
    }

    static func heroIndex(in slots: [Slot]) -> Int {
        if let session = slots.firstIndex(where: { $0.kind == .session }) {
            return session
        }
        var best: (index: Int, urgency: Double)?
        for (index, slot) in slots.enumerated() {
            guard let window = slot.window else { continue }
            let urgency = urgency(of: window)
            if best == nil || urgency > best!.urgency {
                best = (index, urgency)
            }
        }
        return best?.index ?? 0
    }

    static func urgency(of window: UsageWindow) -> Double {
        window.severity == .critical || window.severity == .exceeded ? max(window.usedPct, 100) : window.usedPct
    }
}
