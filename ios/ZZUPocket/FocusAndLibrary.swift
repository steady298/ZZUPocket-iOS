import Foundation
import SwiftUI
import WebKit

struct FocusRecord: Codable, Identifiable {
    var id: UUID
    var startedAt: Date
    var seconds: Int
    var label: String
}

@MainActor
final class FocusTimer: ObservableObject {
    @Published var minutes = 25
    @Published var label = "学习"
    @Published private(set) var records: [FocusRecord] = []
    @Published private(set) var endDate: Date?
    @Published private(set) var remaining = 25 * 60

    private var startDate: Date?
    private var timer: Timer?
    private let recordsKey = "focusRecordsV1"

    init() {
        if let data = UserDefaults.standard.data(forKey: recordsKey), let saved = try? JSONDecoder().decode([FocusRecord].self, from: data) {
            records = saved
        }
    }

    func start() {
        guard endDate == nil else { return }
        let now = Date()
        startDate = now
        endDate = now.addingTimeInterval(TimeInterval(minutes * 60))
        remaining = minutes * 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        if let startDate {
            let elapsed = max(0, min(minutes * 60, Int(Date().timeIntervalSince(startDate))))
            if elapsed > 0 {
                records.insert(FocusRecord(id: UUID(), startedAt: startDate, seconds: elapsed, label: label), at: 0)
                UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: recordsKey)
            }
        }
        timer?.invalidate()
        timer = nil
        startDate = nil
        endDate = nil
        remaining = minutes * 60
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remaining == 0 { stop() }
    }

    var totalMinutes: Int { records.reduce(0) { $0 + $1.seconds } / 60 }
}

struct FocusScreen: View {
    @StateObject private var focus = FocusTimer()

    var body: some View {
        NavigationStack {
            Form {
                Section("专注计时") {
                    TextField("标签", text: $focus.label)
                    Stepper("时长 \(focus.minutes) 分钟", value: $focus.minutes, in: 1...180).disabled(focus.endDate != nil)
                    Text(String(format: "%02d:%02d", focus.remaining / 60, focus.remaining % 60))
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                    if focus.endDate == nil {
                        Button("开始专注") { focus.start() }
                    } else {
                        Button("结束并记录") { focus.stop() }
                    }
                }
                Section("记录 · 共 \(focus.totalMinutes) 分钟") {
                    ForEach(focus.records.prefix(50)) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.label)
                                Text(item.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(max(1, item.seconds / 60)) 分钟")
                        }
                    }
                }
            }
            .navigationTitle("专注")
        }
    }
}

struct LibraryScreen: View {
    var body: some View {
        NavigationStack {
            LibraryWebView()
                .navigationTitle("图书馆座位")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LibraryWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        // Library's public website only serves the booking page over HTTP.
        web.load(URLRequest(url: URL(string: "http://order.lib.zzu.edu.cn/h5/")!))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
