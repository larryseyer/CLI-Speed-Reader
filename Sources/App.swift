import AppKit
import SwiftUI

final class Reader: ObservableObject {
    @Published var agent: Agent = .claude
    @Published var assistantOnly = true
    @Published var wpm = UserDefaults.standard.double(forKey: "wpm") == 0 ? 300 : UserDefaults.standard.double(forKey: "wpm")
    @Published var text = ""
    @Published var position = 0
    @Published var playing = false
    @Published var watching = false
    @Published var status = "Choose an agent, then connect to a conversation."
    @Published var source = ""
    var words: [String] = []
    var reading = Reading("")
    var selection = 0
    private var file: URL?
    private var tty: String?
    private var lastReply: Reply?
    private var replyStart = 0
    private var baseline = ""
    private var pending = ""
    private var changed = Date()
    private var watchTimer: Timer?
    private var playbackTimer: Timer?

    func stopWatching() {
        watching = false
        watchTimer?.invalidate()
        file = nil; tty = nil; lastReply = nil
        status = "Disconnected. Reading position retained."
    }

    func connect(file chosen: URL? = nil) {
        stopWatching()
        pause()
        text = ""; words = []; reading = Reading(""); position = 0; selection = 0
        do {
            if agent == .terminal {
                guard !assistantOnly else {
                    status = "Assistant-only needs an agent conversation log. Choose Claude Code, Codex, or Grok Build."
                    return
                }
                let (device, current) = try Terminal.bind()
                tty = device; baseline = Reading.normalized(current); pending = baseline
                source = device
                status = "Watching new screen text; prompts and your input may be included."
            } else {
                guard let url = chosen ?? agent.latestFile() else {
                    status = "No conversation found. Start an agent session, or choose a log file."
                    return
                }
                file = url; source = url.path
                let reply = try Conversation.read(url, agent: agent, assistantOnly: assistantOnly)
                lastReply = reply
                replyStart = 0
                if let reply { append(reply.text, autoPlay: false) }
                status = "Connected. Latest reply loaded; new replies play automatically."
            }
            watching = true
            watchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        } catch { status = error.localizedDescription }
    }

    func chooseFile() {
        guard agent != .terminal else { connect(); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.directoryURL = agent.directory
        panel.message = "Choose this agent's conversation JSONL file."
        if panel.runModal() == .OK, let url = panel.url { connect(file: url) }
    }

    func poll() {
        do {
            if let file {
                guard let reply = try Conversation.read(file, agent: agent, assistantOnly: assistantOnly), reply != lastReply else { return }
                if reply.id == lastReply?.id {
                    let wasAtEnd = position >= words.count
                    text = String(text.prefix(replyStart)) + reply.text
                    reading = Reading(text); words = reading.words
                    if wasAtEnd, position < words.count { play() }
                } else {
                    replyStart = text.count + (text.isEmpty ? 0 : 2)
                    append(reply.text, autoPlay: true)
                }
                lastReply = reply
            } else if let tty {
                let current = Reading.normalized(try Terminal.contents(tty: tty))
                if current != pending { pending = current; changed = Date(); return }
                guard current != baseline, Date().timeIntervalSince(changed) >= 1.2 else { return }
                let addition = Reading.newText(after: baseline, in: current)
                baseline = current
                append(addition, autoPlay: true)
            }
        } catch {
            stopWatching()
            status = error.localizedDescription
        }
    }

    func append(_ addition: String, autoPlay: Bool) {
        guard !addition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let wasAtEnd = position >= words.count
        let oldCount = words.count
        text += (text.isEmpty ? "" : "\n\n") + addition
        reading = Reading(text); words = reading.words
        if wasAtEnd { position = oldCount }
        if autoPlay && wasAtEnd { play() }
    }

    func paste() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            status = "Copy a reply in Terminal first."; return
        }
        stopWatching(); pause()
        text = ""; words = []; position = 0
        append(value, autoPlay: false)
        source = "Clipboard (manually chosen text)"
        status = "Clipboard loaded. Select a starting place, then play."
    }

    func pause() { playing = false; playbackTimer?.invalidate() }
    func play() {
        guard !words.isEmpty else { return }
        if position >= words.count { position = 0 }
        playing = true; schedule()
    }
    func schedule() {
        playbackTimer?.invalidate()
        guard playing, position < words.count else { pause(); return }
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 60 / wpm, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.position += 1
            if self.position >= self.words.count { self.pause() } else { self.schedule() }
        }
    }
    func seek(_ index: Int) { pause(); position = min(max(0, index), max(0, words.count - 1)) }
    func startAtSelection() { seek(reading.word(atUTF16Offset: selection)); play() }
}

struct Transcript: NSViewRepresentable {
    @ObservedObject var reader: Reader
    func makeCoordinator() -> Coordinator { Coordinator(reader) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let view = NSTextView()
        view.isEditable = false; view.isSelectable = true
        view.font = .systemFont(ofSize: 14)
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != reader.text else { return }
        let range = view.selectedRange()
        view.string = reader.text
        view.setSelectedRange(NSRange(location: min(range.location, (reader.text as NSString).length), length: 0))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        let reader: Reader
        init(_ reader: Reader) { self.reader = reader }
        func textViewDidChangeSelection(_ notification: Notification) {
            if let view = notification.object as? NSTextView { reader.selection = view.selectedRange().location }
        }
    }
}

struct FocalWord: NSViewRepresentable {
    let word: String
    func makeNSView(context: Context) -> WordView { WordView() }
    func updateNSView(_ view: WordView, context: Context) { view.word = word; view.needsDisplay = true }
}

final class WordView: NSView {
    var word = ""
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.065, alpha: 1).setFill(); bounds.fill()
        let letters = Array(word)
        guard !letters.isEmpty else { return }
        let index = Reading.focalIndex(word)
        var size: CGFloat = 54
        func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
            [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium), .foregroundColor: color]
        }
        var attrs = attributes(.white)
        // Keep the focal letter fixed even when long paths require a smaller font.
        let left = String(letters.prefix(index)), focal = String(letters[index])
        let right = String(letters.dropFirst(index + 1))
        let maxSide = max((left as NSString).size(withAttributes: attrs).width,
                          (right as NSString).size(withAttributes: attrs).width) + (focal as NSString).size(withAttributes: attrs).width / 2
        if maxSide > bounds.width / 2 - 12 { size *= (bounds.width / 2 - 12) / maxSide; attrs = attributes(.white) }
        let focalWidth = (focal as NSString).size(withAttributes: attrs).width
        let x = bounds.midX - focalWidth / 2 - (left as NSString).size(withAttributes: attrs).width
        let value = NSMutableAttributedString(string: word, attributes: attrs)
        let range = NSRange(word.index(word.startIndex, offsetBy: index)..<word.index(word.startIndex, offsetBy: index + 1), in: word)
        value.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
        value.draw(at: NSPoint(x: x, y: bounds.midY - value.size().height / 2))
        NSColor.systemRed.withAlphaComponent(0.7).setFill()
        NSRect(x: bounds.midX - 1, y: bounds.maxY - 18, width: 2, height: 9).fill()
        NSRect(x: bounds.midX - 1, y: 9, width: 2, height: 9).fill()
    }
}

struct ReaderView: View {
    @ObservedObject var reader: Reader
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Source", selection: $reader.agent) {
                    ForEach(Agent.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.frame(width: 215).disabled(reader.watching)
                Toggle("Assistant replies only", isOn: $reader.assistantOnly).disabled(reader.watching)
                Spacer()
            }
            HStack {
                Button(reader.agent == .terminal ? "Watch front Terminal tab" : "Connect latest session") { reader.connect() }
                if reader.agent != .terminal { Button("Choose session…") { reader.chooseFile() } }
                Button("Disconnect") { reader.stopWatching() }.disabled(!reader.watching)
                Button("Read Clipboard") { reader.paste() }
            }
            Text(reader.source).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(reader.source)
            FocalWord(word: reader.words.indices.contains(reader.position) ? reader.words[reader.position] : (reader.words.isEmpty ? "Ready" : ""))
                .frame(minHeight: 130, maxHeight: 180).accessibilityLabel("Current word")
            HStack {
                Button(reader.playing ? "Pause" : "Play") { reader.playing ? reader.pause() : reader.play() }
                    .disabled(reader.words.isEmpty)
                Button("Restart") { reader.seek(0); reader.play() }.disabled(reader.words.isEmpty)
                Text("\(Int(reader.wpm)) WPM").monospacedDigit().frame(width: 90)
                Slider(value: $reader.wpm, in: 60...1000, step: 10).accessibilityLabel("Words per minute")
                    .onChange(of: reader.wpm) { value in UserDefaults.standard.set(value, forKey: "wpm"); reader.schedule() }
            }
            HStack {
                Text("Start / position")
                Slider(value: Binding(get: { Double(min(reader.position, max(0, reader.words.count - 1))) },
                                      set: { reader.seek(Int($0)) }),
                       in: 0...Double(max(1, reader.words.count - 1)), step: 1)
                    .disabled(reader.words.isEmpty).accessibilityLabel("Starting word")
                Text("\(min(reader.position + 1, reader.words.count)) / \(reader.words.count)").monospacedDigit().frame(minWidth: 90)
            }
            HStack {
                Text("Select a word below to choose where to start.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Start at selection") { reader.startAtSelection() }.disabled(reader.words.isEmpty)
            }
            Transcript(reader: reader).frame(minHeight: 110)
            Text(reader.status).font(.caption).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(minWidth: 650, minHeight: 480)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let reader = Reader()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit CLI Speed Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "CLI Speed Reader"
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ReaderView(reader: reader))
        panel.minSize = NSSize(width: 680, height: 520)
        panel.setFrameAutosaveName("ReaderPanel")
        panel.center(); panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main enum RSVPApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
