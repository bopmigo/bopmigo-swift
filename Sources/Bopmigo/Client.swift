import Foundation
import Network

/// A report waiting to be sent. Saved on the phone so nothing is lost when sending fails.
struct Draft: Codable, Identifiable {
    var id = UUID()
    var category: String
    var description: String
    var question: String?
    var answer: String?
    var context: [String: AnyCodable]
    var screenshot: String?
}

/// Talks to Bopmigo with its own connection, independent of the app's network code and sign-in,
/// so reporting still works while the app itself is failing.
actor Client {
    static let shared = Client()
    static let version = "0.1.0"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    private var token: String? = UserDefaults.standard.string(forKey: "bopmigo.token")
    private let monitor = NWPathMonitor()
    private var watching = false

    struct Failure: Error { let message: String }

    // MARK: Requests

    func loadConfig() async {
        guard let data = try? await request("GET", "config", auth: false),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if json["hideAllText"] as? Bool == true { await MainActor.run { Bopmigo.hideAllText = true } }
    }

    /// One short follow-up question, or nil if there isn't one.
    func question(for description: String, category: String, context: [String: Any], requestID: UUID) async -> String? {
        let body: [String: Any] = ["description": description, "category": category, "context": context, "requestId": requestID.uuidString.lowercased()]
        guard let data = try? await request("POST", "question", body: body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // An empty question means Bopmigo has nothing to ask: send straight away.
        let q = (json["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return q.isEmpty ? nil : q
    }

    /// Sends a report. If it can't be sent now, it's saved and sent later.
    @discardableResult
    func send(_ draft: Draft) async -> Bool {
        do {
            try await post(draft)
            return true
        } catch {
            save(draft)
            watchConnection()
            return false
        }
    }

    /// Sends reports saved from earlier attempts.
    func sendQueued() async {
        for draft in queue() {
            do { try await post(draft); remove(draft.id) } catch { watchConnection(); return }
        }
    }

    private func post(_ draft: Draft) async throws {
        var body: [String: Any] = [
            "requestId": draft.id.uuidString.lowercased(),
            "category": draft.category,
            "description": draft.description,
            "context": draft.context.mapValues(\.value),
        ]
        if let q = draft.question { body["question"] = q }
        if let a = draft.answer { body["answer"] = a }
        // Drafts saved by older versions hold PNG; JPEG base64 starts with "/9j/".
        if let s = draft.screenshot { body["screenshot"] = "data:image/\(s.hasPrefix("/9j/") ? "jpeg" : "png");base64,\(s)" }
        _ = try await request("POST", nil, body: body)
    }

    private func request(_ method: String, _ action: String?, body: [String: Any]? = nil, auth: Bool = true, retried: Bool = false) async throws -> Data {
        let (site, host) = await MainActor.run { (Bopmigo.siteID, Bopmigo.host) }
        guard let site else { throw Failure(message: "Bopmigo isn't set up yet.") }
        if auth, token == nil { try await newToken(site: site, host: host) }
        var url = host.appendingPathComponent("api/v1/reporter/\(site)")
        if let action { url.appendPathComponent(action) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, auth, !retried {
            token = nil
            return try await request(method, action, body: body, auth: auth, retried: true)
        }
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Failure(message: message ?? "Couldn't send. Try again in a moment.")
        }
        return data
    }

    private func newToken(site: String, host: URL) async throws {
        var req = URLRequest(url: host.appendingPathComponent("api/v1/reporter/\(site)/session"))
        req.httpMethod = "POST"
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = json["token"] as? String else {
            throw Failure(message: "Couldn't reach Bopmigo.")
        }
        token = t
        UserDefaults.standard.set(t, forKey: "bopmigo.token")
    }

    // MARK: Saved drafts

    private var queueURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bopmigo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("queue.json")
    }
    private func queue() -> [Draft] { (try? JSONDecoder().decode([Draft].self, from: Data(contentsOf: queueURL))) ?? [] }
    private func write(_ drafts: [Draft]) {
        try? JSONEncoder().encode(Array(drafts.suffix(20))).write(to: queueURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func save(_ draft: Draft) { var q = queue().filter { $0.id != draft.id }; q.append(draft); write(q) }
    private func remove(_ id: UUID) { write(queue().filter { $0.id != id }) }

    /// Tries saved reports again as soon as the phone is back online.
    private func watchConnection() {
        guard !watching else { return }
        watching = true
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { await Client.shared.sendQueued() }
        }
        monitor.start(queue: DispatchQueue(label: "bopmigo.network"))
    }
}

/// Lets device details (strings, numbers, true/false) be saved with a draft.
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else { value = (try? c.decode(String.self)) ?? "" }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Int: try c.encode(v)
        default: try c.encode(String(describing: value))
        }
    }
}
