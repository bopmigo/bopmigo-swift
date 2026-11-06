import SwiftUI
import UIKit

@MainActor
enum Presenter {
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private static var top: UIViewController? {
        var vc = keyWindow?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }

    private static var showing = false

    static func present(history: Bool = false, thread: String? = nil) {
        guard !showing, let top else { return }
        guard Bopmigo.siteID != nil else {
            assertionFailure("Call Bopmigo.configure(siteID:) before Bopmigo.show().")
            return
        }
        // Taken before the sheet covers the screen.
        let shot = history || thread != nil ? nil : Redactor.screenshot()
        let close = { top.dismiss(animated: true) }
        let root: AnyView = thread.map { id in AnyView(NavigationStack { ThreadView(id: id) }.tint(accent).environment(\.closeSheet, close)) }
            ?? (history ? AnyView(NavigationStack { HistoryView() }.tint(accent).environment(\.closeSheet, close)) : AnyView(FeedbackView(screenshot: shot, close: close)))
        let host = UIHostingController(rootView: root)
        host.modalPresentationStyle = .pageSheet
        host.presentationController?.delegate = Dismissal.shared
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        showing = true
        top.present(host, animated: true)
    }

    /// If the team replied since the person last looked, offer to show it.
    static func offerReplies() async {
        guard !showing, Bopmigo.siteID != nil else { return }
        let unread = await Client.shared.unread()
        guard let first = unread.first, !showing, let top else { return }
        let alert = UIAlertController(title: "The team replied", message: unread.count == 1 ? "About “\(first.title)”." : "You have \(unread.count) new replies to your feedback.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Later", style: .cancel) { _ in Task { for r in unread { await Client.shared.markSeen(r) } } })
        alert.addAction(UIAlertAction(title: "View", style: .default) { _ in
            if unread.count == 1 { present(thread: first.id) } else { present(history: true) }
        })
        top.present(alert, animated: true)
    }

    static func offerAfterScreenshot() {
        guard !showing, let top else { return }
        let alert = UIAlertController(title: "Report a problem?", message: "Tell the team what went wrong.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Report", style: .default) { _ in present() })
        top.present(alert, animated: true)
    }

    final class Dismissal: NSObject, UIAdaptivePresentationControllerDelegate {
        static let shared = Dismissal()
        func presentationControllerDidDismiss(_ controller: UIPresentationController) { Task { @MainActor in Presenter.showing = false } }
    }
    static func closed() { showing = false }
}

private let thanks = [
    "Thanks! The team will take a look.",
    "Thanks, sending this to the team.",
    "Got it, thanks! It’s with the team now.",
    "Thanks for letting us know. The team will take a look.",
]

struct FeedbackView: View {
    let screenshot: UIImage?
    let close: () -> Void

    private enum Step { case write, asking, followUp, done }
    @State private var step = Step.write
    @State private var category = "problem"
    @State private var text = ""
    @State private var question: String?
    @State private var answer = ""
    @State private var queued = false
    @State private var requestID = UUID()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    bubble(you: true, text.isEmpty || step == .write ? nil : text)
                    if step == .write { compose }
                    if let question, step != .write { bubble(you: false, question, label: "Bopmigo asked") }
                    if step == .followUp { followUp }
                    if step == .asking { ProgressView().padding(.vertical, 8) }
                    if step == .done {
                        if !answer.isEmpty { bubble(you: true, answer) }
                        bubble(you: false, queued ? "Saved. It’ll send as soon as you’re back online." : thanks.randomElement()!, label: "Bopmigo")
                    }
                }
                .padding(18)
            }
            .navigationTitle(step == .done ? "Sent" : "What’s on your mind?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .done ? "Done" : "Cancel") { Presenter.closed(); close() }
                }
            }
        }
        .tint(accent)
        .environment(\.closeSheet, close)
        .onAppear { focused = true }
    }

    private var compose: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Type", selection: $category) {
                Text("Bug").tag("problem")
                Text("Feature").tag("change")
                Text("Idea").tag("idea")
            }
            .pickerStyle(.segmented)
            Text(kind.label).font(.subheadline.weight(.semibold))
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(kind.example).foregroundStyle(.secondary).padding(.top, 1).allowsHitTesting(false)
                }
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($focused)
                    .accessibilityLabel(kind.label)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            Button(action: next) { Text("Send").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
            NavigationLink { HistoryView(showsDone: false) } label: {
                Text("Your feedback and replies").font(.subheadline).frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
        }
    }

    private var followUp: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Your answer (optional)", text: $answer, axis: .vertical)
                .lineLimit(2...6)
                .focused($focused)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Button("Skip") { answer = ""; send() }
                Spacer()
                Button("Send", action: send).buttonStyle(.borderedProminent)
            }
        }
    }

    private func bubble(you: Bool, _ body: String?, label: String? = nil) -> some View {
        Group { if let body { Bubble(you: you, text: body, label: label) } }
    }

    private var kind: (label: String, example: String) {
        switch category {
        case "change": return ("What should change?", "It would be easier if…")
        case "idea": return ("What’s your idea?", "It would be great if…")
        default: return ("What happened?", "I tried to… but…")
        }
    }

    /// After writing: Bopmigo asks one follow-up that fits what was written, or none, then sends.
    private func next() {
        focused = false
        step = .asking
        let description = text, kind = category, id = requestID, context = DeviceContext.current()
        Task {
            // Never make someone wait long: no question after 6 seconds means send without one.
            let q = await withTaskGroup(of: String?.self) { group -> String? in
                group.addTask { await Client.shared.question(for: description, category: kind, context: context, requestID: id) }
                group.addTask { try? await Task.sleep(nanoseconds: 6_000_000_000); return nil }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            if let q { question = q; step = .followUp; focused = true } else { send() }
        }
    }

    private func send() {
        focused = false
        let draft = Draft(id: requestID, category: category, description: text.trimmingCharacters(in: .whitespacesAndNewlines),
                          question: question, answer: answer.isEmpty ? nil : answer,
                          context: DeviceContext.current().mapValues(AnyCodable.init),
                          screenshot: Redactor.encode(screenshot))
        step = .asking
        Task {
            queued = !(await Client.shared.send(draft))
            step = .done
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

let accent = Color(red: 1, green: 0.35, blue: 0.12)

private struct CloseSheetKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var closeSheet: () -> Void { get { self[CloseSheetKey.self] } set { self[CloseSheetKey.self] = newValue } }
}

/// One message in a conversation: theirs on the right, Bopmigo's and the team's on the left.
struct Bubble: View {
    let you: Bool
    let text: String
    var label: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label ?? "You").font(.caption.weight(.semibold)).foregroundStyle(you ? .white.opacity(0.7) : Color(red: 0.76, green: 0.25, blue: 0.05))
            Text(text).foregroundStyle(you ? .white : .primary)
        }
        .padding(12)
        .background(you ? Color(red: 0.09, green: 0.07, blue: 0.06) : Color(red: 1, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 16))
        .padding(you ? .leading : .trailing, 44) // keeps their messages on the right and the others on the left, even when long
        .frame(maxWidth: .infinity, alignment: you ? .trailing : .leading)
    }
}

private func statusName(_ s: String) -> String { s == "in_progress" ? "In progress" : s == "resolved" ? "Resolved" : "Open" }

/// Everything this person sent from this device, with a dot on reports that have a new reply.
struct HistoryView: View {
    /// False when opened from the feedback sheet, which already has its own Cancel.
    var showsDone = true
    @SwiftUI.Environment(\.closeSheet) private var closeSheet
    @State private var reports: [Client.Report]?
    @State private var unread: Set<String> = []

    var body: some View {
        Group {
            if let reports, reports.isEmpty {
                Text("Feedback you send shows up here, with any replies from the team.").foregroundStyle(.secondary).multilineTextAlignment(.center).padding(32)
            } else if let reports {
                List(reports) { r in
                    NavigationLink { ThreadView(id: r.id) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(unread.contains(r.id) ? accent : .clear).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.title).lineLimit(2)
                                Text(unread.contains(r.id) ? "New reply" : statusName(r.status)).font(.caption).foregroundStyle(unread.contains(r.id) ? accent : .secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Your feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if showsDone { ToolbarItem(placement: .cancellationAction) { Button("Done") { Presenter.closed(); closeSheet() } } } }
        .task {
            let list = await Client.shared.myReports()
            unread = Set(await Client.shared.unread().map(\.id))
            reports = list
        }
    }
}

/// One report and the conversation with the team. Opening it marks the replies as seen.
struct ThreadView: View {
    let id: String
    @SwiftUI.Environment(\.closeSheet) private var closeSheet
    @State private var thread: Client.Thread?
    @State private var failed = false
    @State private var reply = ""
    @State private var sending = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let t = thread {
                    HStack(alignment: .firstTextBaseline) {
                        Text(t.title).font(.headline)
                        Spacer()
                        Text(statusName(t.status)).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3).background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    Bubble(you: true, text: t.description)
                    if let q = t.question { Bubble(you: false, text: q, label: "Bopmigo asked") }
                    if let a = t.answer, !a.isEmpty { Bubble(you: true, text: a) }
                    ForEach(t.messages) { m in Bubble(you: m.author != "team", text: m.body, label: m.author == "team" ? "Team" : nil) }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Reply to the team", text: $reply, axis: .vertical)
                            .lineLimit(2...6)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        HStack { Spacer(); Button(sending ? "Sending…" : "Send reply", action: send).buttonStyle(.borderedProminent).disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending) }
                    }
                    .padding(.top, 4)
                } else if failed {
                    Text("Couldn’t load this conversation. Check your connection and try again.").foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(18)
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Presenter.closed(); closeSheet() } } }
        .task { await load() }
    }

    private func load() async {
        if let t = await Client.shared.thread(id) { thread = t; await Client.shared.markSeen(id: id) } else { failed = true }
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        Task {
            if await Client.shared.reply(id, text) { reply = ""; notice = nil; await load() } else { notice = "Couldn’t send. Check your connection and try again." }
            sending = false
        }
    }
}
