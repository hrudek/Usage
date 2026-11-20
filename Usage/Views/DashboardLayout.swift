import CoreGraphics

enum DashboardLayout: Equatable {
    case stack
    case sideBySide
    case aboveAndBelow(top: CGFloat, gap: CGFloat)

    init(isRegularWidth: Bool, size: CGSize, activeFold fold: CGRect?, hasAccounts: Bool) {
        guard hasAccounts else {
            self = .stack
            return
        }
        if let fold, fold.height > fold.width {
            self = .sideBySide
        } else if let fold, fold.minY > 0, fold.maxY < size.height {
            self = .aboveAndBelow(top: fold.minY, gap: fold.height)
        } else if isRegularWidth, size.width > size.height {
            self = .sideBySide
        } else {
            self = .stack
        }
    }

    var selectsAccounts: Bool {
        self != .stack
    }

    static func sidebarWidth(in size: CGSize) -> CGFloat {
        size.width / 2
    }

    static func shownAccount(selected: String?, in accountIDs: [String]) -> String? {
        if let selected, accountIDs.contains(selected) {
            return selected
        }
        return accountIDs.first
    }
}
