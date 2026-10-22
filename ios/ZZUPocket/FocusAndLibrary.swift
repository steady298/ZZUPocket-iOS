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
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 18) {
                        HStack {
                            Label("专注时光", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.86))
                            Spacer()
                            Text(focus.endDate == nil ? "准备开始" : "专注中")
                                .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.17), in: Capsule())
                        }.foregroundStyle(.white)

                        ZStack {
                            Circle().stroke(.white.opacity(0.18), lineWidth: 10)
                            Circle().trim(from: 0, to: focus.endDate == nil ? 1 : CGFloat(focus.remaining) / CGFloat(max(1, focus.minutes * 60)))
                                .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90)).animation(.easeInOut(duration: 0.35), value: focus.remaining)
                            VStack(spacing: 3) {
                                Text(String(format: "%02d:%02d", focus.remaining / 60, focus.remaining % 60))
                                    .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                                Text(focus.label.isEmpty ? "专注" : focus.label).font(.subheadline).foregroundStyle(.white.opacity(0.82))
                            }.foregroundStyle(.white)
                        }.frame(width: 210, height: 210).padding(.vertical, 4)

                        if focus.endDate == nil {
                            TextField("给这次专注起个名称", text: $focus.label)
                                .multilineTextAlignment(.center).padding(12)
                                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                            HStack {
                                Text("时长").foregroundStyle(.white.opacity(0.82))
                                Spacer()
                                Stepper("\(focus.minutes) 分钟", value: $focus.minutes, in: 1...180)
                                    .fixedSize().labelsHidden()
                                Text("\(focus.minutes) 分钟").font(.subheadline.weight(.semibold).monospacedDigit())
                            }.foregroundStyle(.white)
                            Button { focus.start() } label: {
                                Label("开始专注", systemImage: "play.fill").font(.headline)
                                    .frame(maxWidth: .infinity).padding(15)
                                    .foregroundStyle(PocketStyle.deepAccent).background(.white, in: RoundedRectangle(cornerRadius: 15))
                            }
                        } else {
                            Button { focus.stop() } label: {
                                Label("结束并保存记录", systemImage: "stop.fill").font(.headline)
                                    .frame(maxWidth: .infinity).padding(15)
                                    .foregroundStyle(PocketStyle.deepAccent).background(.white, in: RoundedRectangle(cornerRadius: 15))
                            }
                        }
                    }
                    .padding(20)
                    .background(LinearGradient(colors: [PocketStyle.accent, PocketStyle.deepAccent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("專注記錄").font(.headline)
                            Spacer()
                            Text("累计 \(focus.totalMinutes) 分钟").font(.caption).foregroundStyle(.secondary)
                        }
                        if focus.records.isEmpty {
                            ContentUnavailableView("还没有专注记录", systemImage: "chart.bar.xaxis", description: Text("完成一次专注后，记录会显示在这里。"))
                                .padding(.vertical, 8).background(.background, in: RoundedRectangle(cornerRadius: 18))
                        }
                        ForEach(focus.records.prefix(50)) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold()).foregroundStyle(.green)
                                    .frame(width: 38, height: 38).background(.green.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.label).font(.subheadline.weight(.semibold))
                                    Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(max(1, item.seconds / 60)) 分钟").font(.subheadline.weight(.semibold).monospacedDigit())
                            }.padding(13).background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
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
                .toolbarBackground(.visible, for: .navigationBar)
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
