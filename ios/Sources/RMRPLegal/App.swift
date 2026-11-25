import SwiftUI
import Foundation

struct Law: Codable, Identifiable {
    let id: String
    var title: String
    var url: URL
    var amendment: URL?
    var effective: String?
    var attachments: [URL]
}

struct Snapshot: Codable {
    let checked: Date
    let laws: [Law]
}

@MainActor final class Registry: ObservableObject {
    @Published private(set) var laws: [Law] = []
    @Published private(set) var status = "Реестр от 25 ноября 2026"
    private var checked: Date?
    private var refreshing = false
    private let cacheKey = "registry.snapshot.v1"

    init() {
        let decoder = JSONDecoder()
        if let data = Bundle.module.url(forResource: "Registry", withExtension: "json").flatMap({ try? Data(contentsOf: $0) }),
           let bundled = try? decoder.decode([Law].self, from: data) {
            laws = bundled
        }
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let saved = try? decoder.decode(Snapshot.self, from: data), !saved.laws.isEmpty {
            laws = saved.laws
            checked = saved.checked
            status = "Проверено " + saved.checked.formatted(date: .abbreviated, time: .shortened)
        }
    }

    func refresh(force: Bool = false) async {
        guard !refreshing, force || (checked.map({ Date().timeIntervalSince($0) >= 86_400 }) ?? true) else { return }
        refreshing = true
        defer { refreshing = false }
        status = "Проверяю официальный каталог…"
        do {
            let url = URL(string: "https://forum.rmrp.ru/forums/laws/")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.host == url.host, let html = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            let updated = try mergeCatalog(html)
            let now = Date()
            let snapshot = Snapshot(checked: now, laws: updated)
            UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: cacheKey)
            laws = updated
            checked = now
            status = "Проверено " + now.formatted(date: .abbreviated, time: .shortened)
        } catch {
            status = "Форум недоступен · сохранённая копия"
        }
    }

    private func mergeCatalog(_ html: String) throws -> [Law] {
        let pattern = #"<a\b[^>]*href="(/threads/([a-z0-9-]+)\.(\d+)/(?:unread)?)"[^>]*data-tp-primary="on"[^>]*>([^<]+)</a>"#
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let source = html as NSString
        var updated: [Law] = []
        var seen = Set<String>()
        let existing = Dictionary(uniqueKeysWithValues: laws.map { ($0.id, $0) })
        for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let id = source.substring(with: match.range(at: 3))
            guard seen.insert(id).inserted,
                  let url = URL(string: "https://forum.rmrp.ru/threads/" + source.substring(with: match.range(at: 2)) + "." + id + "/") else { continue }
            let title = source.substring(with: match.range(at: 4))
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#039;", with: "'")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var law = existing[id] ?? Law(id: id, title: title, url: url, attachments: [])
            law.title = title
            law.url = url
            updated.append(law)
        }
        guard updated.count >= 25 else { throw URLError(.cannotParseResponse) }
        return updated + laws.filter { !seen.contains($0.id) }
    }
}

@main struct LegalApp: App {
    @StateObject private var registry = Registry()
    var body: some Scene { WindowGroup { Home(registry: registry) } }
}

struct RegistryView: View {
    @ObservedObject var registry: Registry
    @Environment(\.scenePhase) private var phase
    @State private var query = ""

    var body: some View {
            NavigationStack {
                List {
                    Section {
                        ForEach(registry.laws.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { law in
                            NavigationLink {
                                List {
                                    Link("Текст на официальном форуме", destination: law.url)
                                    if let amendment = law.amendment {
                                        Link("Проверенная поправка", destination: amendment)
                                    }
                                    if let effective = law.effective {
                                        LabeledContent("Дата действия поправки", value: effective)
                                    }
                                    ForEach(Array(law.attachments.enumerated()), id: \.offset) { item in
                                        Link("Приложение или поправка \(item.offset + 1)", destination: item.element)
                                    }
                                }
                                .navigationTitle(law.title)
                                .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                Text(law.title)
                            }
                        }
                    } header: {
                        Text("Тверской · \(registry.laws.count) актов")
                    } footer: {
                        Text(registry.status)
                    }
                }
                .navigationTitle("RMRP Legal")
                .searchable(text: $query, prompt: "Поиск по названию закона")
                .refreshable { await registry.refresh(force: true) }
                .task(id: phase) {
                    if phase == .active { await registry.refresh() }
                }
            }
            .tint(.blue)
    }
}

