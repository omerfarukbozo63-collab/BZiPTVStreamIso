import Foundation

enum Kind: String, CaseIterable, Identifiable {
    case live, movie, series
    var id: String { rawValue }
    var label: String {
        switch self {
        case .live: return "Canlı TV"
        case .movie: return "Filmler"
        case .series: return "Diziler"
        }
    }
}

struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var user: String
    var pass: String

    var isXtream: Bool { !user.isEmpty }
    var base: String {
        var s = url.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
    var m3uURL: String {
        isXtream ? "\(base)/get.php?username=\(user)&password=\(pass)&type=m3u_plus&output=m3u8" : url
    }
}

struct Episode: Identifiable, Hashable {
    let id = UUID()
    let season: Int
    let num: Int
    let title: String
    let url: String
}

struct Item: Identifiable, Hashable {
    let key: String
    let name: String
    let group: String
    let url: String
    let type: Kind
    var logo = ""
    var streamId = ""
    var seriesId = ""
    var episodes: [Episode] = []
    var vodId = ""
    var archive = false

    var id: String { key }
    var isSeriesFolder: Bool { type == .series && (!seriesId.isEmpty || !episodes.isEmpty) }
}

struct Playable: Identifiable, Hashable {
    let url: String
    let title: String
    let streamId: String?
    let archive: Bool
    var id: String { url }
}

struct PastProgram: Identifiable {
    let id = UUID()
    let title: String
    let minutes: Int
    let start: String
}

func isAdult(_ g: String) -> Bool {
    let l = g.lowercased()
    return ["adult", "xxx", "+18", "18+", "erotik", "porn"].contains { l.contains($0) }
}
