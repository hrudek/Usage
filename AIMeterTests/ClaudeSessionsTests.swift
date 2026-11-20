import XCTest
import UsageKit
@testable import AIMeter

/// Claude Code's sessions in the island: the preferences, what the mark,
/// the count and the rows say, and on the Mac the hooks' edits to Claude
/// Code's settings, the log paths and the hook requests. Pure: nothing
/// here reads a real log, opens the socket or touches ~/.claude.
final class ClaudeSessionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, _ state: ClaudeCodeSessionActivity.State, title: String? = nil, project: String? = "aimeter") -> ClaudeCodeSessionActivity {
        ClaudeCodeSessionActivity(id: id, customTitle: title, project: project, state: state, lastActivity: now)
    }

    func testPreferences() {
        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        let fresh = Preferences.load(from: scratch.defaults)
        XCTAssertTrue(fresh.claudeSessionsEnabled, "on by default, so presence-checked")
        XCTAssertFalse(fresh.claudeSessionsNotify)
        XCTAssertFalse(fresh.claudeSessionsHooksDismissed)
        XCTAssertTrue(fresh.claudeSessionsPets, "pets on by default, presence-checked")
        XCTAssertFalse(fresh.claudeSessionsShowsName, "off by default: a short island")
        XCTAssertFalse(fresh.claudeSessionsAnswers, "answering from the island is opt-in")

        let model = PreferencesModel(defaults: scratch.defaults)
        model.claudeSessionsEnabled = false
        model.claudeSessionsNotify = true
        model.claudeSessionsHooksDismissed = true
        model.claudeSessionsPets = false
        model.claudeSessionsShowsName = true
        model.claudeSessionsAnswers = true
        let reloaded = Preferences.load(from: scratch.defaults)
        XCTAssertFalse(reloaded.claudeSessionsEnabled, "a written false is honored")
        XCTAssertTrue(reloaded.claudeSessionsNotify)
        XCTAssertTrue(reloaded.claudeSessionsHooksDismissed)
        XCTAssertFalse(reloaded.claudeSessionsPets)
        XCTAssertTrue(reloaded.claudeSessionsShowsName)
        XCTAssertTrue(reloaded.claudeSessionsAnswers)
    }

    /// "Avoid covering the menu bar": macOS's prompt only while the
    /// permission never worked, and a copy that lost it to another
    /// signature told how to mend it rather than asked again.
    func testAccessibilityAsksOnlyWhenItNeverWorked() {
        XCTAssertEqual(AccessibilityState(trusted: true, confirmedBefore: false), .granted)
        XCTAssertEqual(AccessibilityState(trusted: true, confirmedBefore: true), .granted)
        XCTAssertEqual(AccessibilityState(trusted: false, confirmedBefore: false), .notGranted)
        XCTAssertEqual(AccessibilityState(trusted: false, confirmedBefore: true), .lostForThisCopy)
        XCTAssertTrue(AccessibilityState.notGranted.mayPrompt)
        XCTAssertFalse(AccessibilityState.lostForThisCopy.mayPrompt, "System Settings may show it on: no prompt")
        XCTAssertFalse(AccessibilityState.granted.mayPrompt)

        let scratch = ScratchDefaults()
        defer { scratch.wipe() }
        XCTAssertFalse(Preferences.load(from: scratch.defaults).claudeSessionsAccessibilityConfirmed)
        PreferencesModel(defaults: scratch.defaults).claudeSessionsAccessibilityConfirmed = true
        XCTAssertTrue(Preferences.load(from: scratch.defaults).claudeSessionsAccessibilityConfirmed)
    }

    func testTheMarkGoesByUrgency() {
        typealias Sessions = NotchIslandModel.Sessions
        XCTAssertNil(Sessions(sessions: [], justFinished: nil, now: now).mark, "nothing at work: the bare notch")
        let working = session("w", .working(since: now))
        let waiting = session("p", .needsPermission(since: now))
        let done = session("d", .finished(at: now))
        XCTAssertNil(Sessions(sessions: [done], justFinished: nil, now: now).mark, "finished a while ago is no news")
        XCTAssertEqual(Sessions(sessions: [working], justFinished: nil, now: now).mark, .working)
        XCTAssertEqual(Sessions(sessions: [working, done], justFinished: done, now: now).mark, .finished)
        XCTAssertEqual(Sessions(sessions: [working, waiting, done], justFinished: done, now: now).mark, .waiting)
        XCTAssertEqual(Sessions(sessions: [working, waiting, done], justFinished: nil, now: now).activeCount, 2)
    }

    func testRows() {
        let sessions = NotchIslandModel.Sessions(
            sessions: [
                session("a", .working(since: now.addingTimeInterval(-30)), title: "Fix the build"),
                session("b", .working(since: now.addingTimeInterval(-185))),
                session("c", .needsPermission(since: now.addingTimeInterval(-600))),
                session("d", .finished(at: now.addingTimeInterval(-20))),
                session("e", .finished(at: now.addingTimeInterval(-125))),
                session("f", .finished(at: now.addingTimeInterval(-300))),
            ],
            justFinished: nil,
            now: now
        )
        XCTAssertEqual(sessions.rows.map(\.detail), ["Working", "Working for 3m", "Needs permission", "Done just now", "Done 2m ago"])
        XCTAssertEqual(sessions.rows.map(\.status), [.working, .working, .waiting, .finished, .finished])
        XCTAssertEqual(sessions.moreCount, 1, "five rows at most")
        XCTAssertEqual(sessions.rows[0].name, "Fix the build")
        XCTAssertEqual(sessions.rows[0].project, "aimeter", "the folder after a title")
        XCTAssertEqual(sessions.rows[1].name, "aimeter")
        XCTAssertNil(sessions.rows[1].project, "a session named by its folder doesn't repeat it")
        XCTAssertEqual(sessions.rows[0].accessibilityLabel, "Fix the build, Working")
    }

    func testPets() {
        let sessions = NotchIslandModel.Sessions(
            sessions: [
                session("a", .working(since: now)),
                session("c", .working(since: now)),
                session("d", .working(since: now)),
                session("b", .needsPermission(since: now)),
                session("e", .finished(at: now)),
            ],
            justFinished: session("e", .finished(at: now)),
            now: now
        )
        XCTAssertTrue(sessions.showsPets, "on by default")
        XCTAssertEqual(sessions.pets.map(\.id), ["b", "a", "c"], "three beside the notch, the one waiting first even from fourth place")
        XCTAssertEqual(sessions.pets.map(\.pose), [.waiting, .working, .working])
        XCTAssertEqual(sessions.morePets, 2, "d at work, and e asleep")
        XCTAssertEqual(sessions.count, 5, "the count says every one")
        XCTAssertEqual(sessions.lead?.id, "b", "the lead: the one that needs you")
        XCTAssertEqual(sessions.lead?.detail, "Needs permission", "what the peek says it is doing")
        XCTAssertEqual(sessions.leftPets.map(\.id), ["b", "a"], "by default two of three on the notch's left")
        XCTAssertEqual(sessions.rightPets.map(\.id), ["c"], "and the third on its right, before the count")
        let named = NotchIslandModel.Sessions(
            sessions: [session("a", .working(since: now)), session("c", .working(since: now)), session("d", .working(since: now))],
            justFinished: nil, showsName: true, now: now
        )
        XCTAssertEqual(named.leftPets.map(\.id), ["a"], "with its name, the lead alone on the left")
        XCTAssertEqual(named.rightPets.map(\.id), ["c", "d"], "the others before the count")
        let two = NotchIslandModel.Sessions(sessions: [session("x", .working(since: now)), session("y", .working(since: now))], justFinished: nil, now: now)
        XCTAssertEqual(two.leftPets.map(\.id), ["x"], "one a side with two")
        XCTAssertEqual(two.rightPets.map(\.id), ["y"])
        for slot in sessions.pets {
            XCTAssertEqual(sessions.rows.first { $0.id == slot.id }?.pet, slot.pet, "the same pet beside the notch and in its row")
        }
        XCTAssertEqual(Set(sessions.rows.map(\.pet)).count, sessions.rows.count, "no two alike")
        XCTAssertEqual(sessions.rows.last?.pose, .asleep)

        let calm = NotchIslandModel.Sessions(sessions: [session("e", .finished(at: now))], justFinished: session("e", .finished(at: now)), now: now)
        XCTAssertEqual(calm.pets.map(\.pose), [.asleep], "the one that just finished, asleep for its few seconds")
        XCTAssertEqual(calm.count, 1)
        XCTAssertEqual(calm.leftPets.map(\.id), ["e"], "alone, on the left, the count on the right")
        XCTAssertTrue(calm.rightPets.isEmpty)
        XCTAssertTrue(NotchIslandModel.Sessions(sessions: [session("e", .finished(at: now))], justFinished: nil, now: now).pets.isEmpty)
        XCTAssertFalse(NotchIslandModel.Sessions(sessions: [], justFinished: nil, showsPets: false, now: now).showsPets)
    }

    func testTheIslandCarriesThem() {
        let island = NotchIslandModel(
            accounts: [], primaryID: nil, displayMode: .used, resetStyle: .relative, modelSlotFallback: .auto,
            showCreditsAmount: false, usageColors: true, metrics: [.session], glanceMetric: .session,
            layout: .bothSides, incident: nil, sessions: [session("a", .working(since: now))], now: now
        )
        XCTAssertEqual(island.sessions.mark, .working)
        XCTAssertEqual(island.sessions.activeCount, 1)
        XCTAssertEqual(island.sessions.markLabel, "Claude Code sessions working: 1")
    }

}
