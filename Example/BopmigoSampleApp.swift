import SwiftUI
import Bopmigo

/* A small booking app with a few planted problems, so each kind of report can be tried:
   - Stays: the total doesn't update when you change check-out (a clear bug).
   - Search: Reserve does nothing, and one search shows no results (vague bugs).
   - Profile: private details that must be hidden in the screenshot.
   - Settings: no dark mode yet (feature requests), and a long scrolling list. */

@main
struct BopmigoSampleApp: App {
    init() {
        // Your app ID from Bopmigo. `.always` so you can try the screenshot offer in the Simulator.
        Bopmigo.configure(siteID: "YOUR-APP-ID", screenshotPrompt: .always)
        Bopmigo.setUser(id: "guest-42", email: "maria@example.com", name: "Maria Lopez")
    }
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    var body: some View {
        TabView {
            StaysView().tabItem { Label("Stays", systemImage: "house") }
            SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            ProfileView().tabItem { Label("Profile", systemImage: "person") }
            SettingsView().tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

/// Bug 1: changing check-out never updates the nights or the total.
struct StaysView: View {
    @State private var checkOut = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17))!
    var body: some View {
        NavigationStack {
            Form {
                Section("Forest House") {
                    LabeledContent("Check in", value: "Nov 14")
                    DatePicker("Check out", selection: $checkOut, displayedComponents: .date)
                    LabeledContent("Total", value: "3 nights · €612") // planted bug: never recalculated
                }
                Button("Send feedback") { Bopmigo.show() }
            }
            .navigationTitle("Checkout")
            .bopmigoScreen("Checkout")
        }
    }
}

/// Bug 2: Reserve does nothing; searching "Lisbon" shows nothing at all.
struct SearchView: View {
    @State private var query = ""
    private let all = ["Forest House, Oslo", "Harbour Loft, Porto", "Dune Cabin, Sylt", "Old Town Flat, Prague"]
    var results: [String] { query.isEmpty ? all : (query.lowercased() == "lisbon" ? [] : all.filter { $0.localizedCaseInsensitiveContains(query) }) }
    var body: some View {
        NavigationStack {
            List {
                ForEach(results, id: \.self) { stay in
                    HStack { Text(stay); Spacer(); Button("Reserve") { /* planted bug: does nothing */ }.buttonStyle(.bordered) }
                }
            }
            .overlay { if results.isEmpty { Text(" ") } } // planted bug: blank, no "no results" message
            .searchable(text: $query, prompt: "Try Lisbon")
            .navigationTitle("Search")
            .bopmigoScreen("Search")
        }
    }
}

/// Private details: these must come out covered in the screenshot.
struct ProfileView: View {
    @State private var password = "hunter2hunter2"
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Name", value: "Maria Lopez")
                    Text("maria@example.com").bopmigoPrivate()
                    SecureField("Password", text: $password)
                }
                Section("Payment") {
                    Text("Visa •••• 4242  exp 08/29").bopmigoPrivate()
                    Text("Calle Mayor 12, 28013 Madrid").bopmigoPrivate()
                }
                Button("Send feedback") { Bopmigo.show() }
            }
            .navigationTitle("Profile")
            .bopmigoScreen("Profile")
        }
    }
}

/// Feature requests (no dark mode, no currency choice) and a long list to scroll.
struct SettingsView: View {
    @State private var hideText = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    LabeledContent("Theme", value: "Light only")
                    LabeledContent("Currency", value: "EUR")
                }
                Section("Testing") {
                    Toggle("Hide all text in screenshots", isOn: $hideText)
                        .onChange(of: hideText) { on in Bopmigo.setHideAllText(on) }
                }
                Section("Notifications") {
                    ForEach(1...25, id: \.self) { i in Toggle("Alert \(i)", isOn: .constant(i % 3 == 0)) }
                }
                Button("Send feedback") { Bopmigo.show() }
            }
            .navigationTitle("Settings")
            .bopmigoScreen("Settings")
        }
    }
}
