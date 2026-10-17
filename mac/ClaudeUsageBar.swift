// ClaudeUsageBar — MIGATRONIX
// Menu-bar view of Claude plan usage, read from ~/.claude/usage-cache.json
// (written by statusline-usage.sh whenever Claude Code refreshes its status line).

import SwiftUI
import AppKit

private extension Color {
    static let ttMagenta = Color(red: 0xB7 / 255, green: 0x00 / 255, blue: 0x6A / 255)
    static let ttAmber = Color(red: 0xE0 / 255, green: 0x9A / 255, blue: 0x00 / 255)
}

struct CacheFile: Decodable {
    struct Window: Decodable {
        let usedPercentage: Double
        let resetsAt: Double
    }
    let updatedAt: Double
    let fiveHour: Window?
    let sevenDay: Window?
    let contextPct: Double?
}

struct UsageWindow {
    let usedPct: Double
    let resetsAt: Date
}

struct UsageSnapshot {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let contextPct: Double?
    let updatedAt: Date
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var now = Date()

    static let staleAfter: TimeInterval = 15 * 60
    private let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/usage-cache.json")
    private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        now = Date()
        guard let data = try? Data(contentsOf: fileURL) else { snapshot = nil; return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let file = try? decoder.decode(CacheFile.self, from: data) else { snapshot = nil; return }
        func map(_ w: CacheFile.Window?) -> UsageWindow? {
            w.map { UsageWindow(usedPct: $0.usedPercentage, resetsAt: Date(timeIntervalSince1970: $0.resetsAt)) }
        }
        snapshot = UsageSnapshot(
            fiveHour: map(file.fiveHour),
            sevenDay: map(file.sevenDay),
            contextPct: file.contextPct,
            updatedAt: Date(timeIntervalSince1970: file.updatedAt)
        )
    }

    var isStale: Bool {
        guard let s = snapshot else { return true }
        return now.timeIntervalSince(s.updatedAt) > Self.staleAfter
    }

    var menuTitle: String {
        guard let w = snapshot?.fiveHour else { return "—" }
        if w.resetsAt <= now { return "reset" }
        return "\(Int(w.usedPct.rounded()))% · \(Format.left(w.resetsAt.timeIntervalSince(now)))"
    }
}

enum Format {
    static func left(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        return "\(m)m"
    }

    static func clock(_ date: Date, withDay: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = withDay ? "EEE HH:mm" : "HH:mm"
        return f.string(from: date)
    }

    static func ago(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        if m < 1 { return "just now" }
        if m < 60 { return "\(m) min ago" }
        return "\(m / 60)h \(m % 60)m ago"
    }
}

func levelColor(_ pct: Double) -> Color {
    if pct >= 90 { return .ttMagenta }
    if pct >= 70 { return .ttAmber }
    return .accentColor
}

struct RingView: View {
    let title: String
    let window: UsageWindow?
    let now: Date
    let showDay: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 9)
                if let w = window, w.resetsAt > now {
                    Circle()
                        .trim(from: 0, to: min(1, w.usedPct / 100))
                        .stroke(levelColor(w.usedPct), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: w.usedPct)
                    VStack(spacing: 0) {
                        Text("\(Int(w.usedPct.rounded()))%").font(.title2.bold().monospacedDigit())
                        Text("used").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(window == nil ? "—" : "reset").font(.title3).foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)

            Text(title).font(.headline)
            if let w = window {
                if w.resetsAt > now {
                    Text("\(100 - Int(w.usedPct.rounded()))% left").font(.caption.monospacedDigit())
                    Text("resets in \(Format.left(w.resetsAt.timeIntervalSince(now)))")
                        .font(.caption.monospacedDigit())
                    Text(Format.clock(w.resetsAt, withDay: showDay))
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("reset at \(Format.clock(w.resetsAt, withDay: showDay))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("awaiting new data").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("no data").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Claude usage").font(.title3.bold())
                Spacer()
                Button {
                    store.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload")
            }

            if let s = store.snapshot {
                HStack(alignment: .top) {
                    RingView(title: "5-hour", window: s.fiveHour, now: store.now, showDay: false)
                    RingView(title: "Weekly", window: s.sevenDay, now: store.now, showDay: true)
                }
                if let c = s.contextPct {
                    Text("Last session context: \(Int(c.rounded()))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if store.isStale {
                        Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Color.ttAmber)
                    }
                    Text("Updated \(Format.ago(store.now.timeIntervalSince(s.updatedAt)))")
                }
                .font(.caption).foregroundStyle(.secondary)
                if store.isStale {
                    Text("Values refresh while a Claude Code session is open.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No usage data yet.\nOpen Claude Code (claude) and send one message.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Text("MIGATRONIX").font(.caption2.bold()).foregroundStyle(Color.ttMagenta)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(store.menuTitle).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
