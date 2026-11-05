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

    static func present() {
        guard !showing, let top else { return }
        guard Bopmigo.siteID != nil else {
            assertionFailure("Call Bopmigo.configure(siteID:) before Bopmigo.show().")
            return
        }
        // Taken before the sheet covers the screen.
        let shot = Redactor.screenshot()
        let host = UIHostingController(rootView: FeedbackView(screenshot: shot) { top.dismiss(animated: true) })
        host.modalPresentationStyle = .pageSheet
        host.presentationController?.delegate = Dismissal.shared
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        showing = true
        top.present(host, animated: true)
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
        .tint(Color(red: 1, green: 0.35, blue: 0.12))
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
        Group {
            if let body {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label ?? "You").font(.caption.weight(.semibold)).foregroundStyle(you ? .white.opacity(0.7) : Color(red: 0.76, green: 0.25, blue: 0.05))
                    Text(body).foregroundStyle(you ? .white : .primary)
                }
                .padding(12)
                .background(you ? Color(red: 0.09, green: 0.07, blue: 0.06) : Color(red: 1, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: you ? .trailing : .leading)
            }
        }
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
