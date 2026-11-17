import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var active: Profile?
    @Published var items: [Item] = []
    @Published var favs: [String] = []
    @Published var recents: [String] = []
    @Published var status = ""
    @Published var loading = false
    private let ud = UserDefaults.standard

    init() {
        if let d = ud.data(forKey: "profiles"),
           let p = try? JSONDecoder().decode([Profile].self, from: d) { profiles = p }
    }

    var pin: String {
        get { ud.string(forKey: "pin") ?? "1234" }
        set { ud.set(newValue, forKey: "pin") }
    }

    func saveProfiles() {
        if let d = try? JSONEncoder().encode(profiles) { ud.set(d, forKey: "profiles") }
    }
    func add(_ p: Profile) { profiles.append(p); saveProfiles() }
    func delete(at offsets: IndexSet) { profiles.remove(atOffsets: offsets); saveProfiles() }

    func open(_ p: Profile) async {
        loading = true; status = "Yükleniyor..."
        do {
            var list: [Item]
            if p.isXtream {
                do { list = try await API.loadXtream(p) }
                catch {
                    let d = try await API.fetch(p.m3uURL)
                    list = API.parseM3U(String(decoding: d, as: UTF8.self))
                }
            } else {
                let d = try await API.fetch(p.m3uURL)
                list = API.parseM3U(String(decoding: d, as: UTF8.self))
            }
            if list.isEmpty {
                status = "Kanal bulunamadı"
            } else {
                items = list
                favs = ud.stringArray(forKey: "fav_\(p.id)") ?? []
                recents = ud.stringArray(forKey: "rec_\(p.id)") ?? []
                active = p
                status = ""
            }
        } catch {
            status = "Hata: \(error.localizedDescription)"
        }
        loading = false
    }

    func close() { active = nil; items = [] }

    func toggleFav(_ key: String) {
        guard let p = active else { return }
        if let i = favs.firstIndex(of: key) { favs.remove(at: i) } else { favs.append(key) }
        ud.set(favs, forKey: "fav_\(p.id)")
    }

    func addRecent(_ key: String) {
        guard let p = active else { return }
        recents = Array(([key] + recents.filter { $0 != key }).prefix(30))
        ud.set(recents, forKey: "rec_\(p.id)")
    }
}
