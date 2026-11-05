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

/// Bug 1: check-out was moved to Nov 18, but the nights and total still say 3 nights.
/// Photos on Unsplash (Unsplash License): Evan Leith (cabin), Clay Banks (interiors), Sibel Kusdemir (host).
struct StaysView: View {
    private let pine = Color(red: 0.11, green: 0.23, blue: 0.17)
    private let photos = [
        "photo-1542213598-8fbf6282334b",
        "photo-1777895868494-4e01af8487b6",
        "photo-1774927475366-7c4d31588d98",
    ]
    @State private var page = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Swipeable gallery, full bleed, with floating controls.
                ZStack(alignment: .top) {
                    TabView(selection: $page) {
                        ForEach(photos.indices, id: \.self) { i in
                            photo(photos[i], width: 1200).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 340)

                    HStack {
                        circle("chevron.left")
                        Spacer()
                        circle("square.and.arrow.up")
                        circle("heart")
                    }
                    .padding(.horizontal, 16).padding(.top, 60)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(page + 1) / \(photos.count)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.trailing, 16).padding(.bottom, 36)
                }

                // Details sheet over the photo.
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        Text("Forest Cabin in Hemsedal").font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
                        Text("Entire cabin · 4 guests · 2 bedrooms · 1 bath").font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").font(.caption)
                            Text("4.96").fontWeight(.semibold)
                            Text("·").foregroundStyle(.secondary)
                            Text("212 reviews").underline()
                        }.font(.subheadline).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 20)

                    Divider()

                    HStack(spacing: 14) {
                        photo("photo-1757348665310-0b68ed0ebc30", width: 160)
                            .frame(width: 44, height: 44).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hosted by Ingrid").font(.subheadline.weight(.semibold))
                            Text("Superhost · 6 years hosting").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("What this place offers").font(.headline)
                        HStack(spacing: 0) {
                            amenity("flame", "Sauna"); amenity("fireplace", "Fireplace")
                            amenity("wifi", "Wi-Fi"); amenity("car", "Parking")
                        }
                    }
                    .padding(.vertical, 20)

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your trip").font(.headline)
                        HStack(spacing: 0) {
                            date("Check-in", "Thu, Nov 14")
                            Rectangle().fill(Color(.separator)).frame(width: 1, height: 36)
                            date("Check-out", "Mon, Nov 18")
                        }
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator)))

                        VStack(spacing: 10) {
                            row("€204 × 3 nights", "€612")   // planted bug: not updated for 4 nights
                            row("Cleaning fee", "€0")
                            Divider()
                            row("Total", "€612", bold: true)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 20)
                }
                .padding(.horizontal, 22)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24))
                .offset(y: -24)
                .padding(.bottom, -24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemBackground))
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("€612").font(.headline)
                    Text("Nov 14 – 18 · 3 nights").font(.footnote).underline().foregroundStyle(.secondary)
                }
                Spacer()
                Text("Reserve").font(.headline).foregroundStyle(.white)
                    .frame(width: 150, height: 50)
                    .background(pine, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
        .bopmigoScreen("Checkout")
    }

    private func photo(_ id: String, width: Int) -> some View {
        AsyncImage(url: URL(string: "https://images.unsplash.com/\(id)?w=\(width)&q=80&auto=format&fit=crop")) { image in
            image.resizable().scaledToFill()
        } placeholder: { Color(white: 0.9) }
        .clipped()
    }
    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
            .frame(width: 38, height: 38).background(.regularMaterial, in: Circle())
    }
    private func amenity(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20)).frame(height: 24)
            Text(label).font(.caption)
        }
        .frame(maxWidth: .infinity)
    }
    private func date(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
    private func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack { Text(label); Spacer(); Text(value) }
            .font(bold ? .headline : .subheadline)
            .foregroundStyle(bold ? .primary : .secondary)
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

/// Account screen with a "Send feedback" row (the button route, no screenshot needed).
/// The email, card and address are marked private, so they come out covered in screenshots.
struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AsyncImage(url: URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&q=80&auto=format&fit=crop")) { $0.resizable().scaledToFill() } placeholder: { Color(white: 0.9) }
                            .frame(width: 60, height: 60).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Maria Lopez").font(.title3.weight(.semibold))
                            Text("maria.lopez@icloud.com").font(.subheadline).foregroundStyle(.secondary).bopmigoPrivate()
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Account") {
                    row("person.crop.circle", "Personal information")
                    HStack { row("creditcard", "Payments"); Spacer(); Text("Visa •••• 8317").foregroundStyle(.secondary).bopmigoPrivate() }
                    HStack { row("house", "Home address"); Spacer(); Text("Calle Mayor 12, Madrid").foregroundStyle(.secondary).bopmigoPrivate() }
                    row("bell", "Notifications")
                }
                Section("Support") {
                    Button { Bopmigo.show() } label: { row("bubble.left.and.text.bubble.right", "Send feedback") }
                    row("questionmark.circle", "Help Center")
                    row("doc.text", "Terms and privacy")
                }
                Section { Text("Log out").foregroundStyle(.red) }
            }
            .navigationTitle("Profile")
            .bopmigoScreen("Profile")
        }
    }
    private func row(_ symbol: String, _ title: String) -> some View {
        Label { Text(title).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(.primary) }
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
