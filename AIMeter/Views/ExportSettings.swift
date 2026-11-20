import SwiftUI
import UniformTypeIdentifiers
import UsageKit

/// Settings' "Export": every account's usage history as a CSV or a JSON
/// file (`UsageExport`). iOS hands the file to the share sheet (Files,
/// AirDrop, Mail), the Mac to a save panel. Shown only with an account to
/// export, and never in demo mode, whose history is fabricated.
struct ExportSettings: View {
    @Environment(UsageModel.self) private var model

    var body: some View {
        SectionHeader(title: String(localized: "Export"))
        Card {
            row(.csv, title: String(localized: "Export as CSV"))
            Divider().overlay(Theme.track)
            row(.json, title: String(localized: "Export as JSON"))
        }
        SectionFootnote(text: String(localized: "Up to 90 days of usage per window for every account, as a file you can open in Numbers or Excel (CSV) or feed to a script (JSON). Nothing is uploaded: the file goes only where you send it."))
    }

    /// Whether the section has anything to offer here.
    static func isOffered(_ model: UsageModel) -> Bool {
        !model.isDemoMode && !model.needsConnection
    }

    @ViewBuilder
    private func row(_ format: UsageExport.Format, title: String) -> some View {
        // One item type per format, each with exactly one file
        // representation: the share sheet then never has to pick.
        let preview = SharePreview(String(localized: "Usage history"), image: Image(systemName: "chart.xyaxis.line"))
        switch format {
        case .csv:
            ShareLink(item: UsageExportCSV(export: model.usageExport), preview: preview) { rowLabel(title) }
                .buttonStyle(.plain)
        case .json:
            ShareLink(item: UsageExportJSON(export: model.usageExport), preview: preview) { rowLabel(title) }
                .buttonStyle(.plain)
        }
    }

    private func rowLabel(_ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .contentShape(Rectangle())
    }
}

extension UsageExport.Format {
    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .json: .json
        }
    }
}

extension UsageModel {
    /// Every connected account's history and last snapshot, in the
    /// Dashboard's order, as the export reads them.
    var usageExport: UsageExport {
        UsageExport(
            accounts: accounts.map { usage in
                UsageExport.Account(
                    name: usage.account.displayName,
                    providerID: usage.account.providerID,
                    history: timelines[usage.account.accountID] ?? [:],
                    latest: usage.snapshot
                )
            },
            exportedAt: Date()
        )
    }
}

/// The share sheet's items: the file is written only once something is
/// picked to receive it.
nonisolated struct UsageExportCSV: Transferable {
    let export: UsageExport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { try $0.export.written(.csv) }
    }
}

nonisolated struct UsageExportJSON: Transferable {
    let export: UsageExport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { try $0.export.written(.json) }
    }
}

extension UsageExport {
    /// Off the main actor: the share sheet calls it from its own.
    fileprivate nonisolated func written(_ format: Format) throws -> SentTransferredFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(format))
        try data(format).write(to: url, options: .atomic)
        return SentTransferredFile(url)
    }
}
