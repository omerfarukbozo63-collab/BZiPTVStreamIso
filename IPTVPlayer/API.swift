import Foundation

func str(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

func decode64(_ s: String) -> String {
    if let d = Data(base64Encoded: s), let t = String(data: d, encoding: .utf8) { return t }
    return s
}

enum API {
    static func fetch(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 90
        req.setValue("Mozilla/5.0 (iPhone)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    static func json(_ s: String) async throws -> Any {
        let d = try await fetch(s)
        return try JSONSerialization.jsonObject(with: d)
    }

    static func apiBase(_ p: Profile) -> String {
        "\(p.base)/player_api.php?username=\(p.user)&password=\(p.pass)"
    }

    // MARK: Xtream Codes
    static func list(_ p: Profile, _ action: String) async throws -> [[String: Any]] {
        (try await json("\(apiBase(p))&action=\(action)") as? [[String: Any]]) ?? []
    }

    static func cats(_ p: Profile, _ action: String) async throws -> [String: String] {
        var d: [String: String] = [:]
        for o in try await list(p, action) { d[str(o["category_id"])] = str(o["category_name"]) }
        return d
    }

    static func loadXtream(_ p: Profile) async throws -> [Item] {
        async let lc = cats(p, "get_live_categories")
        async let ls = list(p, "get_live_streams")
        async let vc = cats(p, "get_vod_categories")
        async let vs = list(p, "get_vod_streams")
        async let sc = cats(p, "get_series_categories")
        async let ss = list(p, "get_series")
        let (liveCats, live) = try await (lc, ls)
        let (vodCats, vod) = try await (vc, vs)
        let (serCats, ser) = try await (sc, ss)

        var items: [Item] = []
        for o in live {
            let id = str(o["stream_id"])
            items.append(Item(key: "l\(id)", name: str(o["name"]),
                              group: liveCats[str(o["category_id"])] ?? "Diğer",
                              url: "\(p.base)/live/\(p.user)/\(p.pass)/\(id).m3u8",
                              type: .live, logo: str(o["stream_icon"]), streamId: id,
                              archive: str(o["tv_archive"]) == "1"))
        }
        for o in vod {
            let id = str(o["stream_id"])
            var ext = str(o["container_extension"]); if ext.isEmpty { ext = "mp4" }
            items.append(Item(key: "v\(id)", name: str(o["name"]),
                              group: vodCats[str(o["category_id"])] ?? "Diğer",
                              url: "\(p.base)/movie/\(p.user)/\(p.pass)/\(id).\(ext)",
                              type: .movie, logo: str(o["stream_icon"]), vodId: id))
        }
        for o in ser {
            let id = str(o["series_id"])
            items.append(Item(key: "s\(id)", name: str(o["name"]),
                              group: serCats[str(o["category_id"])] ?? "Diğer",
                              url: "", type: .series, logo: str(o["cover"]), seriesId: id))
        }
        return items
    }

    static func episodes(_ p: Profile, seriesId: String) async throws -> [Episode] {
        guard let root = try await json("\(apiBase(p))&action=get_series_info&series_id=\(seriesId)") as? [String: Any],
              let eps = root["episodes"] as? [String: Any] else { return [] }
        var out: [Episode] = []
        for (s, v) in eps {
            guard let list = v as? [[String: Any]] else { continue }
            for e in list {
                var ext = str(e["container_extension"]); if ext.isEmpty { ext = "mp4" }
                out.append(Episode(season: Int(s) ?? 1, num: Int(str(e["episode_num"])) ?? 0,
                                   title: str(e["title"]),
                                   url: "\(p.base)/series/\(p.user)/\(p.pass)/\(str(e["id"])).\(ext)"))
            }
        }
        return out.sorted { ($0.season, $0.num) < ($1.season, $1.num) }
    }

    static func epg(_ p: Profile, streamId: String) async -> String {
        guard let root = (try? await json("\(apiBase(p))&action=get_short_epg&stream_id=\(streamId)&limit=3")) as? [String: Any],
              let list = root["epg_listings"] as? [[String: Any]] else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        var lines: [String] = []
        for (i, o) in list.enumerated() {
            let t = decode64(str(o["title"]))
            let s = f.string(from: Date(timeIntervalSince1970: Double(str(o["start_timestamp"])) ?? 0))
            lines.append((i == 0 ? "Şimdi" : "Sonra") + ": \(s)  \(t)")
        }
        return lines.joined(separator: "\n")
    }

    static func past(_ p: Profile, streamId: String) async -> [PastProgram] {
        guard let root = (try? await json("\(apiBase(p))&action=get_simple_data_table&stream_id=\(streamId)")) as? [String: Any],
              let list = root["epg_listings"] as? [[String: Any]] else { return [] }
        let now = Date().timeIntervalSince1970
        let arch = list.filter { str($0["has_archive"]) == "1" && (Double(str($0["stop_timestamp"])) ?? 0) < now }
        var out: [PastProgram] = []
        for o in arch.suffix(30).reversed() {
            let s = str(o["start"])
            let date = String(s.prefix(10))
            let time = String(s.dropFirst(11).prefix(5)).replacingOccurrences(of: ":", with: "-")
            let st = Double(str(o["start_timestamp"])) ?? 0
            let en = Double(str(o["stop_timestamp"])) ?? 0
            out.append(PastProgram(title: decode64(str(o["title"])), minutes: Int((en - st) / 60), start: "\(date):\(time)"))
        }
        return out
    }

    static func account(_ p: Profile) async -> String {
        guard let root = (try? await json(apiBase(p))) as? [String: Any],
              let u = root["user_info"] as? [String: Any] else { return "Bilgi alınamadı" }
        var exp = "Süresiz"
        if let t = Double(str(u["exp_date"])) {
            let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy"
            exp = f.string(from: Date(timeIntervalSince1970: t))
        }
        return "Durum: \(str(u["status"]))\nBitiş: \(exp)\nAktif bağlantı: \(str(u["active_cons"])) / \(str(u["max_connections"]))\nDeneme hesabı: \(str(u["is_trial"]) == "1" ? "Evet" : "Hayır")"
    }

    static func vodInfo(_ p: Profile, id: String) async -> String {
        guard let root = (try? await json("\(apiBase(p))&action=get_vod_info&vod_id=\(id)")) as? [String: Any],
              let i = root["info"] as? [String: Any] else { return "Bilgi yok" }
        let pairs = [("Puan", "rating"), ("Yıl", "releasedate"), ("Tür", "genre"), ("Süre", "duration"),
                     ("Yönetmen", "director"), ("Oyuncular", "cast"), ("Konu", "plot")]
        let lines = pairs.compactMap { (label, key) -> String? in
            let v = str(i[key])
            return v.isEmpty || v == "null" ? nil : "\(label): \(v)"
        }
        return lines.isEmpty ? "Bilgi yok" : lines.joined(separator: "\n")
    }

    // MARK: M3U
    static func captures(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        var out: [String] = []
        for i in 1..<max(m.numberOfRanges, 1) {
            if let r = Range(m.range(at: i), in: s) { out.append(String(s[r])) } else { out.append("") }
        }
        return out
    }

    static func classify(_ url: String, _ group: String) -> Kind {
        let u = url.lowercased(), g = group.lowercased()
        if u.contains("/movie/") { return .movie }
        if u.contains("/series/") { return .series }
        if ["vod", "film", "movie", "sinema"].contains(where: { g.contains($0) }) { return .movie }
        if ["dizi", "series"].contains(where: { g.contains($0) }) { return .series }
        return .live
    }

    static func parseM3U(_ text: String) -> [Item] {
        var out: [Item] = []
        var order: [String] = []
        var series: [String: (group: String, logo: String, eps: [Episode])] = [:]
        var name = "", group = "Diğer", logo = ""
        let se = #"(.*?)[\s._-]*[Ss](\d{1,2})[\s._-]*[Ee](\d{1,3})"#

        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("#EXTINF") {
                let g = captures(#"group-title="(.*?)""#, l)?.first ?? ""
                group = g.isEmpty ? "Diğer" : g
                logo = captures(#"tvg-logo="(.*?)""#, l)?.first ?? ""
                name = (l.components(separatedBy: ",").last ?? "").trimmingCharacters(in: .whitespaces)
            } else if !l.isEmpty && !l.hasPrefix("#") {
                let t = classify(l, group)
                let n = name.isEmpty ? l : name
                if t == .series, let c = captures(se, n), c.count == 3 {
                    let title = c[0].trimmingCharacters(in: .whitespaces)
                    if series[title] == nil { series[title] = (group, logo, []); order.append(title) }
                    series[title]?.eps.append(Episode(season: Int(c[1]) ?? 1, num: Int(c[2]) ?? 0, title: n, url: l))
                } else {
                    out.append(Item(key: l, name: n, group: group, url: l, type: t, logo: logo))
                }
                name = ""; group = "Diğer"; logo = ""
            }
        }
        for t in order {
            guard let v = series[t] else { continue }
            let eps = v.eps.sorted { ($0.season, $0.num) < ($1.season, $1.num) }
            out.append(Item(key: "s:\(t)", name: t, group: v.group, url: "", type: .series, logo: v.logo, episodes: eps))
        }
        return out
    }
}
