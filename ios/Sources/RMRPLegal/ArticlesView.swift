import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct Article: Codable, Identifiable, Hashable {
    let id, category, document, number, title, body, penalty, url, tags: String
    var heading: String { number.isEmpty ? title : "\(number) · \(title)" }
    var copyText: String { [document, heading, body, penalty, url].filter { !$0.isEmpty }.joined(separator: "\n\n") }
    var searchable: String { [category, document, number, title, body, penalty, tags].joined(separator: " ").lowercased().replacingOccurrences(of: "ё", with: "е") }
}
struct Home: View {
    @ObservedObject var registry: Registry
    @Environment(\.scenePhase) private var phase
    @AppStorage("articleLastCheck") private var lastCheck = 0.0
    @State private var updating = false
    @State private var updateStatus = ""
    @AppStorage("favorites") private var favorites = ""
    @AppStorage("theme") private var theme = "Системная"
    @AppStorage("fontSize") private var fontSize = 17.0
    @AppStorage("history") private var history = ""
    @State private var articles: [Article] = []
    @State private var query = ""
    @State private var error = ""
    @State private var importing = false
    let categories = ["УК", "КоАП", "ПК", "УПК", "Законы", "Уставы", "Правила"]
    let icons = ["scale.3d", "book", "doc.text", "folder", "building.columns", "shield", "list.bullet.rectangle"]
    var saved: Set<String> { Set(favorites.split(separator: "|").map(String.init)) }
    func toggle(_ a: Article) { var ids = saved; if ids.contains(a.id) { ids.remove(a.id) } else { ids.insert(a.id) }; favorites = ids.sorted().joined(separator: "|") }
    func load() {
        do {
            let local = try localArticles()
            guard let bundled = Bundle.module.url(forResource: "articles", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            articles = try JSONDecoder().decode([Article].self, from: Data(contentsOf: FileManager.default.fileExists(atPath: local.path) ? local : bundled))
            error = ""
        } catch { self.error = error.localizedDescription }
    }
    private func localArticles() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("articles.json")
    }
    private func refreshArticles() async {
        guard !updating, Date().timeIntervalSince1970 - lastCheck >= 86_400 else { return }
        updating = true
        defer { updating = false }
        do {
            let url = URL(string: "https://raw.githubusercontent.com/alex1lens/rmrp-legal/main/data/articles.json")!
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == url.host,
                  data.count <= 32_000_000 else { throw URLError(.badServerResponse) }
            let downloaded = try JSONDecoder().decode([Article].self, from: data)
            let ids = Set(downloaded.map(\.id))
            let oldSources = Set(articles.filter { $0.id.hasSuffix("-full") }.map(\.id))
            guard downloaded.count >= 1_200, ids.count == downloaded.count, oldSources.isSubset(of: ids),
                  Set(categories).isSubset(of: Set(downloaded.map(\.category))) else { throw CocoaError(.fileReadCorruptFile) }
            try data.write(to: localArticles(), options: .atomic)
            articles = downloaded
            lastCheck = Date().timeIntervalSince1970
            updateStatus = "База проверена сегодня"
        } catch {
            updateStatus = "Обновление недоступно · сохранённая копия"
        }
    }
    func results(_ source: [Article], _ text: String) -> [Article] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ё", with: "е")
        let terms = q.split(whereSeparator: \.isWhitespace).map(String.init).filter { !["ст", "ст.", "статья", "пункт", "п."].contains($0) }
        if terms.isEmpty { return source }
        return source.filter { a in terms.allSatisfy { a.searchable.contains($0) } }.sorted { a,b in
            let x = terms.contains(a.number), y = terms.contains(b.number)
            return x != y ? x : false
        }
    }
    func remember(_ q: String) { let t = q.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "|", with: " "); guard !t.isEmpty else { return }; history = ([t] + history.split(separator: "|").map(String.init).filter { $0 != t }).prefix(12).joined(separator: "|") }
    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Тверской", systemImage: "shield.checkered").font(.title2.bold()).foregroundStyle(.blue)
                        Text("Правовой справочник RMRP").font(.subheadline).foregroundStyle(.secondary)
                        Text("\(articles.count) записей · офлайн").font(.caption).foregroundStyle(.secondary)
                        if !error.isEmpty { Text(error).foregroundStyle(.red) }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(categories.indices, id: \.self) { i in
                                NavigationLink { ArticleList(title: categories[i], articles: articles.filter { $0.category == categories[i] }, saved: saved, toggle: toggle, fontSize: fontSize) } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Image(systemName: icons[i]).font(.title2).foregroundStyle(.blue)
                                        Text(categories[i]).font(.headline).foregroundStyle(.primary)
                                        Text("\(articles.filter { $0.category == categories[i] }.count) записей").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                }.buttonStyle(.plain)
                            }
                        }
                        Text("Тексты и наказания доступны офлайн. В каждом разделе можно открыть полный текст документа.").font(.footnote).foregroundStyle(.secondary)
                    }.padding()
                }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("RMRP Legal")
            }.tabItem { Label("Главная", systemImage: "house") }
            NavigationStack {
                List {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !history.isEmpty {
                        Section("Недавние запросы") { ForEach(history.split(separator: "|").map(String.init), id: \.self) { h in Button(h) { query = h } } }
                    } else {
                        ForEach(results(articles, query)) { a in NavigationLink { detail(a).onAppear { remember(query) } } label: { ArticleRow(article: a) } }
                    }
                }.overlay { if !query.isEmpty && results(articles, query).isEmpty { ContentUnavailableView.search(text: query) } }.navigationTitle("Поиск").searchable(text: $query, prompt: "Номер статьи или нарушение").onSubmit(of: .search) { remember(query) }
            }.tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            NavigationStack { List(articles.filter { saved.contains($0.id) }) { a in NavigationLink { detail(a) } label: { ArticleRow(article: a) } }.overlay { if saved.isEmpty { ContentUnavailableView("Нет избранного", systemImage: "star", description: Text("Откройте статью и нажмите звезду.")) } }.navigationTitle("Избранное") }.tabItem { Label("Избранное", systemImage: "star") }
            RegistryView(registry: registry).tabItem { Label("Реестр", systemImage: "books.vertical") }
            NavigationStack {
                Form {
                    Section("Внешний вид") { Picker("Тема", selection: $theme) { ForEach(["Системная", "Светлая", "Тёмная"], id: \.self) { Text($0) } }; Slider(value: $fontSize, in: 14...25, step: 1); Text("Размер текста: \(Int(fontSize))") }
                    Section("База") { Text(updateStatus.isEmpty ? "Суточная проверка при открытии" : updateStatus); Button("Импортировать JSON") { importing = true }; Link("Форум RMRP", destination: URL(string: "https://forum.rmrp.ru/")!); Text("Импорт заменяет базу и очищает избранное. Требуется JSON в формате проекта.").font(.footnote); if !error.isEmpty { Text(error).foregroundStyle(.red) } }
                    Section { Button("Очистить историю", role: .destructive) { history = "" } }
                }.navigationTitle("Настройки")
            }.tabItem { Label("Настройки", systemImage: "gearshape") }
        }.preferredColorScheme(theme == "Тёмная" ? .dark : theme == "Светлая" ? .light : nil).onAppear { if articles.isEmpty { load() } }.task(id: phase) { if phase == .active { await refreshArticles() } }.fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); let decoded = try JSONDecoder().decode([Article].self, from: data); guard !decoded.isEmpty, Set(decoded.map(\.id)).count == decoded.count else { throw CocoaError(.fileReadCorruptFile) }; let dir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true); try data.write(to: dir.appendingPathComponent("articles.json"), options: .atomic); favorites = ""; articles = decoded; lastCheck = 0; error = "" } catch { self.error = error.localizedDescription }
        }
    }
    func detail(_ a: Article) -> some View { ArticleDetail(article: a, saved: saved.contains(a.id), toggle: { toggle(a) }, fontSize: fontSize) }
}
struct ArticleList: View {
    let title: String; let articles: [Article]; let saved: Set<String>; let toggle: (Article) -> Void; let fontSize: Double
    @State private var query = ""
    var filtered: [Article] { query.isEmpty ? articles : articles.filter { $0.searchable.contains(query.lowercased().replacingOccurrences(of: "ё", with: "е")) } }
    var body: some View {
        List { ForEach(filtered) { a in NavigationLink { ArticleDetail(article: a, saved: saved.contains(a.id), toggle: { toggle(a) }, fontSize: fontSize) } label: { ArticleRow(article: a) } } }.navigationTitle(title).searchable(text: $query, prompt: "Поиск в разделе")
    }
}
struct ArticleRow: View {
    let article: Article
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(article.document).font(.caption).foregroundStyle(.secondary); Text(article.heading).font(.headline); Text(article.body).font(.subheadline).lineLimit(2).foregroundStyle(.secondary); if !article.penalty.isEmpty { Text(article.penalty.replacingOccurrences(of: "\n", with: " · ")).font(.caption).foregroundStyle(.orange) } }.padding(.vertical, 5) }
}
struct ArticleDetail: View {
    let article: Article; let saved: Bool; let toggle: () -> Void; let fontSize: Double
    @State private var localSaved: Bool? = nil
    @State private var copied = false
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { Text(article.document).font(.subheadline).foregroundStyle(.secondary); Text(article.heading).font(.title2.bold()); Text(article.body).font(.system(size: fontSize)).textSelection(.enabled); if !article.penalty.isEmpty { VStack(alignment: .leading, spacing: 8) { Label("Наказание", systemImage: "scale.3d").font(.headline); Text(article.penalty).font(.system(size: fontSize)).textSelection(.enabled) }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)) }; Button { UIPasteboard.general.string = article.copyText; copied = true } label: { Label(copied ? "Скопировано" : "Копировать статью", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent); if let url = URL(string: article.url), url.scheme == "https" { Link("Оригинал на форуме", destination: url) } }.padding() }.navigationTitle(article.number.isEmpty ? "Документ" : "Статья \(article.number)").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button { localSaved = !(localSaved ?? saved); toggle() } label: { Image(systemName: (localSaved ?? saved) ? "star.fill" : "star") }.accessibilityLabel((localSaved ?? saved) ? "Убрать из избранного" : "В избранное") } } }
}

