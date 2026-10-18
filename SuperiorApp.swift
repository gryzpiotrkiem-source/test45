// Superior - aplikacja na iPhone'a (SwiftUI, iOS 16+)
import SwiftUI
import PhotosUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

@main
struct SuperiorApp: App {
    var body: some Scene { WindowGroup { HomeView() } }
}

// MARK: - Narzędzia
enum Tool: String, CaseIterable, Identifiable {
    case pixel, effect, blur, robot, bit, mixer
    var id: String { rawValue }
    var isImage: Bool { return self == .pixel || self == .effect || self == .blur }
    var name: String {
        switch self {
        case .pixel: return "Pixel art photo"
        case .effect: return "Effect photo"
        case .blur: return "Blur photo"
        case .robot: return "Robot sound"
        case .bit: return "Bit sound"
        case .mixer: return "Audio mixer"
        }
    }
    var desc: String {
        switch self {
        case .pixel: return "Zamień zdjęcie w pikselową grafikę"
        case .effect: return "Filtry, glitch, szum, korekta barw"
        case .blur: return "Rozmycie całości lub z ostrym środkiem"
        case .robot: return "Metaliczny głos robota"
        case .bit: return "Bitcrusher: głębia bitowa i próbkowanie"
        case .mixer: return "Połącz dwa utwory"
        }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Obraz") {
                    ForEach(Tool.allCases.filter { $0.isImage }) { t in
                        NavigationLink(value: t) { row(t) }
                    }
                }
                Section("Dźwięk") {
                    ForEach(Tool.allCases.filter { !$0.isImage }) { t in
                        NavigationLink(value: t) { row(t) }
                    }
                }
            }
            .navigationTitle("Superior")
            .navigationDestination(for: Tool.self) { t in
                if t.isImage { ImageToolView(tool: t) } else { AudioToolView(tool: t) }
            }
        }
    }
    func row(_ t: Tool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.name).font(.headline)
            Text(t.desc).font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text(title); Spacer(); Text(String(format: step < 1 ? "%.1f" : "%.0f", value)).foregroundStyle(.secondary) }
            Slider(value: $value, in: range, step: step)
        }
    }
}

// MARK: - Obraz
struct ImgParams: Equatable {
    var size = 10.0, levels = 8.0
    var fx = 1, amt = 80.0, br = 100.0, co = 100.0, sa = 100.0
    var radius = 8.0, centerSharp = false
}

struct ImageToolView: View {
    let tool: Tool
    @State private var pick: PhotosPickerItem?
    @State private var original: UIImage?
    @State private var result: UIImage?
    @State private var p = ImgParams()
    @State private var showFull = false
    private let ctx = CIContext()

    var body: some View {
        Form {
            Section {
                if let r = result {
                    Image(uiImage: r).resizable().scaledToFit().frame(maxWidth: .infinity)
                        .onTapGesture { showFull = true }
                } else {
                    Text("Wybierz zdjęcie, aby zacząć.").foregroundStyle(.secondary)
                }
                PhotosPicker(selection: $pick, matching: .images) { Label("Wybierz zdjęcie", systemImage: "photo") }
            }
            Section("Ustawienia") { controls }
            if let r = result {
                Section {
                    Button("Podgląd") { showFull = true }
                    ShareLink(item: Image(uiImage: r), preview: SharePreview("Superior", image: Image(uiImage: r))) {
                        Label("Zapisz / udostępnij", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pick) { item in
            Task {
                if let d = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: d) {
                    original = normalize(ui); render()
                }
            }
        }
        .onChange(of: p) { _ in render() }
        .fullScreenCover(isPresented: $showFull) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let r = result { Image(uiImage: r).resizable().scaledToFit() }
            }.onTapGesture { showFull = false }
        }
    }

    @ViewBuilder var controls: some View {
        switch tool {
        case .pixel:
            SliderRow(title: "Wielkość piksela", value: $p.size, range: 2...64)
            SliderRow(title: "Poziomy kolorów (32 = bez redukcji)", value: $p.levels, range: 2...32)
        case .effect:
            Picker("Efekt", selection: $p.fx) {
                Text("Brak").tag(0); Text("Czarno-biały").tag(1); Text("Sepia").tag(2)
                Text("Negatyw").tag(3); Text("Glitch RGB").tag(4); Text("Szum").tag(5)
            }
            SliderRow(title: "Siła efektu", value: $p.amt, range: 0...100)
            SliderRow(title: "Jasność", value: $p.br, range: 50...150)
            SliderRow(title: "Kontrast", value: $p.co, range: 50...150)
            SliderRow(title: "Nasycenie", value: $p.sa, range: 0...200)
        default:
            SliderRow(title: "Promień rozmycia", value: $p.radius, range: 0...40)
            Toggle("Ostry środek", isOn: $p.centerSharp)
        }
    }

    func normalize(_ img: UIImage, maxSide: CGFloat = 1800) -> UIImage {
        let s = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func channel(_ img: CIImage, r: CGFloat, g: CGFloat, b: CGFloat, dx: CGFloat) -> CIImage {
        return img.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]).transformed(by: CGAffineTransform(translationX: dx, y: 0))
    }

    func add(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.additionCompositing(); f.inputImage = a; f.backgroundImage = b
        return f.outputImage ?? a
    }

    func render() {
        guard let base = original, let input = CIImage(image: base) else { return }
        let ext = input.extent
        var out = input
        switch tool {
        case .pixel:
            let f = CIFilter.pixellate(); f.inputImage = input; f.center = .zero; f.scale = Float(p.size)
            out = (f.outputImage ?? input).cropped(to: ext)
            if p.levels < 32 {
                let po = CIFilter.colorPosterize(); po.inputImage = out; po.levels = Float(p.levels)
                out = po.outputImage ?? out
            }
        case .effect:
            let cc = CIFilter.colorControls(); cc.inputImage = input
            cc.brightness = Float((p.br - 100) / 100 * 0.5); cc.contrast = Float(p.co / 100); cc.saturation = Float(p.sa / 100)
            let b = cc.outputImage ?? input
            let a = p.amt / 100
            var fxImg: CIImage? = nil
            switch p.fx {
            case 1: fxImg = b.applyingFilter("CIPhotoEffectMono")
            case 2: let s = CIFilter.sepiaTone(); s.inputImage = b; s.intensity = 1; fxImg = s.outputImage
            case 3: let s = CIFilter.colorInvert(); s.inputImage = b; fxImg = s.outputImage
            case 4:
                let sh = CGFloat(a) * ext.width * 0.03
                let r = channel(b, r: 1, g: 0, b: 0, dx: sh)
                let g = channel(b, r: 0, g: 1, b: 0, dx: 0)
                let bl = channel(b, r: 0, g: 0, b: 1, dx: -sh)
                fxImg = add(add(r, g), bl).cropped(to: ext)
            default: break
            }
            if p.fx == 5, let n = CIFilter.randomGenerator().outputImage?.cropped(to: ext) {
                let grain = n.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(a * 0.7))
                ])
                out = grain.composited(over: b)
            } else if let fx = fxImg {
                let d = CIFilter.dissolveTransition()
                d.inputImage = b; d.targetImage = fx; d.time = Float(a)
                out = d.outputImage ?? fx
            } else { out = b }
        case .blur:
            if p.radius < 0.5 { out = input } else {
                let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: p.radius).cropped(to: ext)
                if p.centerSharp {
                    let g = CIFilter.radialGradient()
                    g.center = CGPoint(x: ext.midX, y: ext.midY)
                    g.radius0 = Float(min(ext.width, ext.height) * 0.15)
                    g.radius1 = Float(min(ext.width, ext.height) * 0.6)
                    g.color0 = CIColor.white; g.color1 = CIColor.black
                    let m = CIFilter.blendWithMask()
                    m.inputImage = input; m.backgroundImage = blurred; m.maskImage = g.outputImage
                    out = m.outputImage ?? blurred
                } else { out = blurred }
            }
        default: break
        }
        if let cg = ctx.createCGImage(out, from: ext) { result = UIImage(cgImage: cg) }
    }
}

// MARK: - Dźwięk
struct Track {
    var ch: [[Float]]
    var sr: Double
    var frames: Int { return ch.first?.count ?? 0 }
}

enum AudioFX {
    static func load(_ url: URL) throws -> Track {
        let f = try AVAudioFile(forReading: url)
        let fmt = f.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(f.length)) else {
            throw NSError(domain: "Superior", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pusty plik"])
        }
        try f.read(into: buf)
        let n = Int(buf.frameLength)
        var ch: [[Float]] = []
        for c in 0..<Int(fmt.channelCount) {
            ch.append(Array(UnsafeBufferPointer(start: buf.floatChannelData![c], count: n)))
        }
        return Track(ch: ch, sr: fmt.sampleRate)
    }

    static func write(_ t: Track, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: t.sr, channels: AVAudioChannelCount(t.ch.count))!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(t.frames))!
        buf.frameLength = AVAudioFrameCount(t.frames)
        for c in 0..<t.ch.count {
            t.ch[c].withUnsafeBufferPointer { buf.floatChannelData![c].update(from: $0.baseAddress!, count: t.frames) }
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: t.sr,
            AVNumberOfChannelsKey: t.ch.count, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buf)
    }

    static func clamp(_ x: Float) -> Float { return max(-1, min(1, x)) }

    static func robot(_ t: Track, f: Double, m: Double, c: Double) -> Track {
        let mm = Float(m / 100), fb = Float(c / 100 * 0.6), d = Int(t.sr * 0.012)
        var outCh: [[Float]] = []
        for x in t.ch {
            var y = [Float](repeating: 0, count: x.count)
            for i in 0..<x.count {
                let mod = Float(sin(2 * Double.pi * f * Double(i) / t.sr))
                y[i] = x[i] * (1 - mm) + x[i] * mod * mm
            }
            var o = y
            for k in 1...4 {
                let sh = d * k
                if sh < y.count {
                    let g = powf(fb, Float(k))
                    for i in sh..<y.count { o[i] += y[i - sh] * g }
                }
            }
            outCh.append(o.map { clamp($0) })
        }
        return Track(ch: outCh, sr: t.sr)
    }

    static func bit(_ t: Track, bits: Int, div: Int) -> Track {
        let q = Float(pow(2.0, Double(bits - 1)))
        var outCh: [[Float]] = []
        for x in t.ch {
            var o = x; var h: Float = 0
            for i in 0..<x.count {
                if i % div == 0 { h = (x[i] * q).rounded() / q }
                o[i] = clamp(h)
            }
            outCh.append(o)
        }
        return Track(ch: outCh, sr: t.sr)
    }

    static func stereo(_ t: Track) -> [[Float]] {
        return t.ch.count == 1 ? [t.ch[0], t.ch[0]] : Array(t.ch.prefix(2))
    }

    static func resample(_ x: [Float], ratio: Double) -> [Float] {
        let n = Int(Double(x.count) / ratio)
        var o = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let pos = Double(i) * ratio; let j = Int(pos); let fr = Float(pos - Double(j))
            let s0 = x[min(j, x.count - 1)], s1 = x[min(j + 1, x.count - 1)]
            o[i] = s0 + (s1 - s0) * fr
        }
        return o
    }

    static func mix(_ A: Track, _ B: Track, ga: Double, gb: Double, off: Double) -> Track {
        let a = stereo(A)
        var b = stereo(B)
        if B.sr != A.sr { b = b.map { resample($0, ratio: B.sr / A.sr) } }
        let o = Int(off * A.sr)
        let n = max(a[0].count, o + b[0].count)
        var out = [[Float]](repeating: [Float](repeating: 0, count: n), count: 2)
        for c in 0..<2 {
            for i in 0..<a[c].count { out[c][i] += a[c][i] * Float(ga / 100) }
            for i in 0..<b[c].count { out[c][o + i] += b[c][i] * Float(gb / 100) }
            for i in 0..<n { out[c][i] = clamp(out[c][i]) }
        }
        return Track(ch: out, sr: A.sr)
    }
}

struct WaveformView: View {
    let track: Track
    var body: some View {
        Canvas { g, size in
            let d = track.ch[0]
            guard !d.isEmpty else { return }
            let w = Int(size.width), step = max(1, d.count / max(w, 1))
            var path = Path()
            for x in 0..<w {
                let lo = x * step, hi = min(d.count, lo + step)
                if lo >= hi { break }
                var mn: Float = 1, mx: Float = -1
                var i = lo; let st = max(1, step / 50)
                while i < hi { mn = min(mn, d[i]); mx = max(mx, d[i]); i += st }
                let mid = size.height / 2
                path.move(to: CGPoint(x: CGFloat(x), y: mid - CGFloat(mx) * mid))
                path.addLine(to: CGPoint(x: CGFloat(x), y: mid - CGFloat(mn) * mid + 1))
            }
            g.stroke(path, with: .color(.orange), lineWidth: 1)
        }
    }
}

struct AudioToolView: View {
    let tool: Tool
    @State private var a: Track?
    @State private var b: Track?
    @State private var result: Track?
    @State private var resultURL: URL?
    @State private var picking = 0
    @State private var importing = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var player: AVAudioPlayer?
    @State private var f = 70.0, m = 85.0, c = 35.0
    @State private var bits = 6.0, div = 4.0
    @State private var ga = 100.0, gb = 100.0, off = 0.0

    var canProcess: Bool { return tool == .mixer ? (a != nil && b != nil) : a != nil }

    var body: some View {
        Form {
            Section("Pliki") {
                Button(tool == .mixer ? "Wczytaj utwór A" : "Wczytaj plik audio") { picking = 0; importing = true }
                if tool == .mixer { Button("Wczytaj utwór B") { picking = 1; importing = true } }
                Text(status).foregroundStyle(.secondary)
                if let e = errorText { Text(e).foregroundStyle(.red) }
            }
            Section("Ustawienia") {
                switch tool {
                case .robot:
                    SliderRow(title: "Częstotliwość modulacji (Hz)", value: $f, range: 20...300)
                    SliderRow(title: "Moc efektu (%)", value: $m, range: 0...100)
                    SliderRow(title: "Metaliczny pogłos (%)", value: $c, range: 0...80)
                case .bit:
                    SliderRow(title: "Głębia bitowa", value: $bits, range: 1...16)
                    SliderRow(title: "Redukcja próbkowania (×)", value: $div, range: 1...50)
                default:
                    SliderRow(title: "Głośność A (%)", value: $ga, range: 0...150)
                    SliderRow(title: "Głośność B (%)", value: $gb, range: 0...150)
                    SliderRow(title: "Przesunięcie B (s)", value: $off, range: 0...30, step: 0.1)
                }
            }
            Section {
                Button(busy ? "Przetwarzanie…" : "Przetwórz") { process() }.disabled(!canProcess || busy)
                if let r = result {
                    WaveformView(track: r).frame(height: 90)
                    Button("Odtwórz oryginał") { play(a) }
                    Button("Odtwórz efekt") { play(r) }
                    Button("Stop") { player?.stop() }
                    if let u = resultURL { ShareLink(item: u) { Label("Zapisz WAV", systemImage: "square.and.arrow.up") } }
                }
            }
        }
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { res in
            if case .success(let url) = res {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do {
                    let t = try AudioFX.load(url)
                    if picking == 0 { a = t } else { b = t }
                    result = nil; errorText = nil
                } catch { errorText = "Nie udało się odczytać pliku: \(error.localizedDescription)" }
            }
        }
    }

    var status: String {
        let sa = a == nil ? "nie wczytano" : "wczytano"
        if tool == .mixer { return "A: \(sa), B: \(b == nil ? "nie wczytano" : "wczytano")" }
        return "Plik: \(sa)"
    }

    func process() {
        guard let a = a else { return }
        busy = true
        let tool = self.tool, b = self.b
        let f = self.f, m = self.m, c = self.c, bits = Int(self.bits), div = Int(self.div)
        let ga = self.ga, gb = self.gb, off = self.off
        Task.detached {
            var out: Track
            switch tool {
            case .robot: out = AudioFX.robot(a, f: f, m: m, c: c)
            case .bit: out = AudioFX.bit(a, bits: bits, div: div)
            default:
                guard let b = b else { return }
                out = AudioFX.mix(a, b, ga: ga, gb: gb, off: off)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("superior-\(tool.rawValue).wav")
            try? AudioFX.write(out, to: url)
            await MainActor.run { self.result = out; self.resultURL = url; self.busy = false }
        }
    }

    func play(_ t: Track?) {
        guard let t = t else { return }
        player?.stop()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("superior-play.wav")
        try? AudioFX.write(t, to: url)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
