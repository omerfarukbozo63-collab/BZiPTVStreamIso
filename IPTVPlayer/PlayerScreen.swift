import SwiftUI
import AVKit

struct PlayerVC: UIViewControllerRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.videoGravity = gravity
    }
}

final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    let profile: Profile
    let zapList: [Item]
    @Published var cur: Playable
    @Published var epg = ""
    @Published var past: [PastProgram] = []
    private var timer: Any?
    private var epgTask: Task<Void, Never>?
    private var stopped = false

    init(start: Playable, profile: Profile, zap: [Item]) {
        self.cur = start
        self.profile = profile
        self.zapList = zap
        timer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1),
                                               queue: .main) { [weak self] _ in self?.savePos() }
        play(start)
    }

    func play(_ p: Playable) {
        savePos()
        cur = p
        guard let u = URL(string: p.url) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: u))
        // Kaldığın yerden devam (sadece film/dizi)
        if p.streamId == nil {
            let t = UserDefaults.standard.double(forKey: "pos_\(p.url)")
            if t > 0 { player.seek(to: CMTime(seconds: t, preferredTimescale: 600)) }
        }
        player.play()
        startEPG()
    }

    func savePos() {
        guard cur.streamId == nil, let item = player.currentItem else { return }
        let t = player.currentTime().seconds
        let d = item.duration.seconds
        let key = "pos_\(cur.url)"
        if d.isFinite, d > 0, t > 10, t < d - 30 {
            UserDefaults.standard.set(t, forKey: key)
        } else if d.isFinite, d > 0 {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func startEPG() {
        epgTask?.cancel()
        epg = ""
        guard let sid = cur.streamId, profile.isXtream else { return }
        let p = profile
        epgTask = Task { [weak self] in
            while !Task.isCancelled {
                let e = await API.epg(p, streamId: sid)
                await MainActor.run { self?.epg = e }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    func zap(_ d: Int) {
        guard !zapList.isEmpty,
              let i = zapList.firstIndex(where: { $0.streamId == cur.streamId }) else { return }
        let n = zapList[(i + d + zapList.count) % zapList.count]
        play(Playable(url: n.url, title: n.name, streamId: n.streamId.isEmpty ? nil : n.streamId, archive: n.archive))
    }

    func loadPast() async {
        guard let sid = cur.streamId else { return }
        let r = await API.past(profile, streamId: sid)
        await MainActor.run { self.past = r }
    }

    func playPast(_ pp: PastProgram) {
        guard let sid = cur.streamId else { return }
        let url = "\(profile.base)/timeshift/\(profile.user)/\(profile.pass)/\(pp.minutes)/\(pp.start)/\(sid).m3u8"
        play(Playable(url: url, title: pp.title, streamId: sid, archive: true))
    }

    func stop() {
        if stopped { return }
        stopped = true
        savePos()
        epgTask?.cancel()
        if let t = timer { player.removeTimeObserver(t); timer = nil }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

struct PlayerScreen: View {
    @StateObject private var m: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var gravity: AVLayerVideoGravity = .resizeAspect
    @State private var showPast = false

    init(start: Playable, profile: Profile, zap: [Item]) {
        _m = StateObject(wrappedValue: PlayerModel(start: start, profile: profile, zap: zap))
    }

    var isLive: Bool { m.cur.streamId != nil }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            PlayerVC(player: m.player, gravity: gravity).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Button { m.stop(); dismiss() } label: { icon("xmark") }
                    Spacer()
                    if isLive && !m.zapList.isEmpty {
                        Button { m.zap(-1) } label: { icon("chevron.down") }
                        Button { m.zap(1) } label: { icon("chevron.up") }
                    }
                    if isLive && m.cur.archive {
                        Button { showPast = true } label: { icon("clock.arrow.circlepath") }
                    }
                    Button {
                        gravity = (gravity == .resizeAspect) ? .resizeAspectFill : .resizeAspect
                    } label: { icon("aspectratio") }
                }
                Text(m.cur.title + (m.epg.isEmpty ? "" : "\n" + m.epg))
                    .font(.caption).foregroundColor(.white).shadow(radius: 2)
            }
            .padding()
        }
        .sheet(isPresented: $showPast) { PastView(m: m, isPresented: $showPast) }
        .onDisappear { m.stop() }
    }

    func icon(_ name: String) -> some View {
        Image(systemName: name).font(.title3).foregroundColor(.white)
            .padding(10).background(Color.black.opacity(0.5)).clipShape(Circle())
    }
}

struct PastView: View {
    @ObservedObject var m: PlayerModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(m.past) { pp in
                Button(pp.title) { m.playPast(pp); isPresented = false }
            }
            .overlay { if m.past.isEmpty { Text("Yükleniyor / kayıt yok").foregroundColor(.secondary) } }
            .navigationTitle("Geçmiş yayınlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { isPresented = false } } }
        }
        .task { await m.loadPast() }
    }
}
