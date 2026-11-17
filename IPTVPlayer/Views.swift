import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        NavigationStack {
            if store.active == nil { ProfilesView() } else { BrowserView() }
        }
    }
}

// MARK: Profiller
struct ProfilesView: View {
    @EnvironmentObject var store: Store
    @State private var showAdd = false

    var body: some View {
        List {
            if !store.status.isEmpty {
                HStack { if store.loading { ProgressView() }; Text(store.status) }
            }
            ForEach(store.profiles) { p in
                Button { Task { await store.open(p) } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.headline)
                        Text(p.isXtream ? "Xtream · \(p.user)" : "M3U")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { store.delete(at: $0) }
        }
        .navigationTitle("Profiller")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddProfileView() }
        .overlay {
            if store.profiles.isEmpty {
                Text("Sağ üstteki + ile profil ekle").foregroundColor(.secondary)
            }
        }
    }
}

struct AddProfileView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var user = ""
    @State private var pass = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Profil adı", text: $name)
                    TextField("Sunucu (http://host:port) veya M3U linki", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Xtream giriş (M3U ise boş bırak)") {
                    TextField("Kullanıcı adı", text: $user)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Şifre", text: $pass)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .navigationTitle("Yeni Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("İptal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        let u = url.trimmingCharacters(in: .whitespaces)
                        guard !u.isEmpty else { return }
                        store.add(Profile(name: name.isEmpty ? "Profil" : name, url: u,
                                          user: user.trimmingCharacters(in: .whitespaces),
                                          pass: pass.trimmingCharacters(in: .whitespaces)))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: Liste
struct ItemRow: View {
    let item: Item
    let fav: Bool
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: item.logo)) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                Color.gray.opacity(0.15)
            }
            .frame(width: 44, height: 44)
            .cornerRadius(6)
            Text(item.name).lineLimit(2)
            Spacer()
            if fav { Image(systemName: "star.fill").foregroundColor(.yellow) }
        }
    }
}

struct BrowserView: View {
    @EnvironmentObject var store: Store
    @State private var tab: Kind = .live
    @State private var group: String? = nil
    @State private var query = ""
    @State private var adult = false
    @State private var pinAsk = false
    @State private var pinText = ""
    @State private var pinChg = false
    @State private var newPin = ""
    @State private var accountText: String?
    @State private var vodItem: Item?
    @State private var playing: Playable?
    @State private var zapList: [Item] = []

    static let favGroup = "★ Favoriler"
    static let recGroup = "🕘 Son İzlenenler"

    var inTab: [Item] {
        store.items.filter { $0.type == tab && (adult || !isAdult($0.group)) }
    }
    var groups: [String] { Array(Set(inTab.map { $0.group })).sorted() }
    var shown: [Item] {
        var base: [Item]
        switch group {
        case nil: base = inTab
        case Self.favGroup?: base = inTab.filter { store.favs.contains($0.key) }
        case Self.recGroup?:
            base = store.recents.compactMap { k in inTab.first { $0.key == k } }
        case let g?: base = inTab.filter { $0.group == g }
        }
        if !query.isEmpty { base = base.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        return base
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            HStack {
                Menu {
                    Button("Tümü") { group = nil }
                    Button(Self.favGroup) { group = Self.favGroup }
                    Button(Self.recGroup) { group = Self.recGroup }
                    ForEach(groups, id: \.self) { g in Button(g) { group = g } }
                } label: {
                    Label(group ?? "Tümü", systemImage: "line.3.horizontal.decrease.circle")
                }
                Spacer()
                Text("\(shown.count) içerik").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 8)

            List(shown) { it in row(it) }
                .listStyle(.plain)
                .navigationDestination(for: Item.self) { SeriesView(item: $0) }
        }
        .navigationTitle(store.active?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
        .onChange(of: tab) { _ in group = nil }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.close() } label: { Image(systemName: "person.2") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if store.active?.isXtream == true {
                        Button {
                            accountText = "Yükleniyor..."
                            if let p = store.active { Task { accountText = await API.account(p) } }
                        } label: { Image(systemName: "person.crop.circle") }
                    }
                    Button { if adult { adult = false } else { pinAsk = true } } label: {
                        Image(systemName: adult ? "lock.open" : "lock")
                    }
                    if adult {
                        Button { pinChg = true } label: { Image(systemName: "key") }
                    }
                }
            }
        }
        .alert("Hesap Bilgisi", isPresented: Binding(get: { accountText != nil },
                                                    set: { if !$0 { accountText = nil } })) {
            Button("Kapat", role: .cancel) {}
        } message: { Text(accountText ?? "") }
        .alert("Ebeveyn PIN", isPresented: $pinAsk) {
            SecureField("PIN (varsayılan 1234)", text: $pinText)
            Button("Aç") { if pinText == store.pin { adult = true }; pinText = "" }
            Button("İptal", role: .cancel) { pinText = "" }
        }
        .alert("Yeni PIN", isPresented: $pinChg) {
            SecureField("En az 4 hane", text: $newPin)
            Button("Kaydet") { if newPin.count >= 4 { store.pin = newPin }; newPin = "" }
            Button("İptal", role: .cancel) { newPin = "" }
        }
        .sheet(item: $vodItem) { v in
            VodDetail(item: v, profile: store.active!) {
                vodItem = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { play(v) }
            }
        }
        .fullScreenCover(item: $playing) { p in
            PlayerScreen(start: p, profile: store.active!, zap: zapList)
        }
    }

    @ViewBuilder
    func row(_ it: Item) -> some View {
        let fav = store.favs.contains(it.key)
        Group {
            if it.isSeriesFolder {
                NavigationLink(value: it) { ItemRow(item: it, fav: fav) }
            } else {
                Button { tap(it) } label: { ItemRow(item: it, fav: fav) }
                    .buttonStyle(.plain)
            }
        }
        .swipeActions {
            Button { store.toggleFav(it.key) } label: { Label("Favori", systemImage: "star") }
                .tint(.yellow)
        }
    }

    func tap(_ it: Item) {
        store.addRecent(it.key)
        if it.type == .movie && !it.vodId.isEmpty { vodItem = it } else { play(it) }
    }

    func play(_ it: Item) {
        zapList = it.type == .live ? store.items.filter { $0.type == .live && $0.group == it.group } : []
        playing = Playable(url: it.url, title: it.name,
                           streamId: it.streamId.isEmpty ? nil : it.streamId, archive: it.archive)
    }
}

// MARK: Film detayı
struct VodDetail: View {
    let item: Item
    let profile: Profile
    let onPlay: () -> Void
    @State private var info = "Yükleniyor..."
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AsyncImage(url: URL(string: item.logo)) { img in
                        img.resizable().scaledToFit()
                    } placeholder: { Color.gray.opacity(0.15) }
                    .frame(maxHeight: 260).frame(maxWidth: .infinity).cornerRadius(10)
                    Text(info)
                    Button(action: onPlay) {
                        Label("Oynat", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
        .task { info = await API.vodInfo(profile, id: item.vodId) }
    }
}

// MARK: Dizi
struct SeriesView: View {
    @EnvironmentObject var store: Store
    let item: Item
    @State private var eps: [Episode] = []
    @State private var season = 1
    @State private var err = ""
    @State private var playing: Playable?

    var seasons: [Int] { Array(Set(eps.map { $0.season })).sorted() }

    var body: some View {
        List {
            if eps.isEmpty {
                Text(err.isEmpty ? "Yükleniyor..." : err)
            } else {
                Picker("Sezon", selection: $season) {
                    ForEach(seasons, id: \.self) { Text("Sezon \($0)").tag($0) }
                }
                .pickerStyle(.menu)
                ForEach(eps.filter { $0.season == season }) { e in
                    Button("\(e.num). \(e.title)") {
                        playing = Playable(url: e.url, title: "\(item.name) S\(e.season)E\(e.num)",
                                           streamId: nil, archive: false)
                    }
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            eps = item.episodes
            if eps.isEmpty, !item.seriesId.isEmpty, let p = store.active {
                do { eps = try await API.episodes(p, seriesId: item.seriesId) }
                catch { err = error.localizedDescription }
            }
            season = seasons.first ?? 1
            store.addRecent(item.key)
        }
        .fullScreenCover(item: $playing) { p in
            PlayerScreen(start: p, profile: store.active!, zap: [])
        }
    }
}
