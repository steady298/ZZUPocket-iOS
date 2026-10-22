import Foundation
import SwiftUI
import WebKit

struct GraduateTerm: Identifiable {
    let code: String
    let name: String
    var id: String { code }
}

// Graduate EAS uses a web CAS session; the undergraduate JWT is not accepted here.
@MainActor
final class GraduateSchedule: ObservableObject {
    @Published var terms: [GraduateTerm] = []
    @Published var selectedTerm = ""
    @Published var lessons: [Lesson] = []
    @Published var week = 1
    @Published var error: String?
    @Published var busy = false

    private let home = URL(string: "https://gmsstu.zzu.edu.cn/stu/")!

    func refresh() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await importCookies()
            let result = try await fetch("pygl/xskbcx/kbcx_drop")
            guard let entries = result["termcode"] as? [[String: Any]] else { throw PocketError.message("研究生学期列表格式有误") }
            terms = entries.compactMap { item in
                guard let code = item["value"] as? String else { return nil }
                return GraduateTerm(code: code, name: item["text"] as? String ?? code)
            }
            if !terms.contains(where: { $0.code == selectedTerm }) {
                selectedTerm = entries.first(where: { $0["selected"] as? Bool == true })?["value"] as? String ?? terms.first?.code ?? ""
            }
            try await loadTerm()
        } catch { self.error = error.localizedDescription }
    }

    func loadTerm() async throws {
        guard !selectedTerm.isEmpty else { throw PocketError.message("请选择研究生学期") }
        let result = try await fetch("pygl/xskbcx/loadKb", form: ["kblx": "xs", "termcode": selectedTerm])
        guard let rows = result["rows"] as? [[String: Any]] else { throw PocketError.message("研究生课表格式有误") }
        var output: [Lesson] = []
        for (rowIndex, row) in rows.enumerated() {
            guard let period = Int("\(row["jcid"] ?? "")"), (1...11).contains(period) else { continue }
            for day in 1...7 {
                guard let cell = row["z\(day)"] as? String,
                      let parsed = Self.parseCell(cell) else { continue }
                for range in parsed.weeks {
                    for week in range {
                        output.append(Lesson(id: "gms-\(rowIndex)-\(day)-\(week)", name: parsed.name, week: week, weekday: day, start: period, end: period, date: nil, time: "", room: parsed.room, teacher: parsed.teacher))
                    }
                }
            }
        }
        lessons = output
        if !output.contains(where: { $0.week == week }) { week = output.map(\.week).min() ?? 1 }
    }

    func selectTerm(_ code: String) async {
        selectedTerm = code
        busy = true
        error = nil
        defer { busy = false }
        do { try await loadTerm() } catch { self.error = error.localizedDescription }
    }

    private func importCookies() async throws {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let gms = cookies.filter { $0.domain == "gmsstu.zzu.edu.cn" || $0.domain == ".gmsstu.zzu.edu.cn" }
        guard gms.contains(where: { $0.name == "cn_com_southsoft_gmis_stu" }) else {
            throw PocketError.message("请先在「登录研究生系统」页面完成学校网页认证")
        }
        for cookie in cookies where cookie.domain.hasSuffix("zzu.edu.cn") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func fetch(_ module: String, form: [String: String]? = nil) async throws -> [String: Any] {
        let (page, pageResponse) = try await API.request(home)
        guard pageResponse.url?.host == home.host else { throw PocketError.message("研究生网页会话已过期，请重新登录") }
        let text = String(data: page, encoding: .utf8) ?? ""
        let cookie = HTTPCookieStorage.shared.cookies(for: home)?.first(where: { $0.name == "cn_com_southsoft_gmis_stu" })?.value
        let guid = text.range(of: "#[0-9a-fA-F-]{36}", options: .regularExpression).map { String(text[$0].dropFirst()) } ?? cookie
        guard let guid, !guid.isEmpty else { throw PocketError.message("研究生系统会话标识缺失，请重新登录") }
        let route = Data("MyHeartWillGoOn\(module)#\(guid)".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "_")
        let url = try API.url("https://gmsstu.zzu.edu.cn", "/stu/\(route)")
        var body: Data?
        if let form {
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            body = components.percentEncodedQuery?.data(using: .utf8) ?? Data()
        }
        let (data, response) = try await API.request(url, method: form == nil ? "GET" : "POST", headers: ["X-Requested-With": "XMLHttpRequest", "Accept": "application/json, text/javascript, */*; q=0.01", "Content-Type": "application/x-www-form-urlencoded"], body: body)
        guard response.url?.host == home.host else { throw PocketError.message("研究生系统会话已过期，请重新登录") }
        return try API.json(data, response)
    }

    private static func parseCell(_ raw: String) -> (name: String, room: String, teacher: String, weeks: [ClosedRange<Int>])? {
        let text = raw.replacingOccurrences(of: "##", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let weekMatch = text.range(of: "\\[[^\\[\\]]*周[^\\[\\]]*\\]", options: .regularExpression) else { return nil }
        let head = String(text[..<weekMatch.lowerBound])
        let name = head.replacingOccurrences(of: "[0-9]{6,10}_[0-9]{1,3}$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let tail = String(text[weekMatch.upperBound...])
        let room = tail.range(of: "\\[[^\\[\\]]+\\]", options: .regularExpression).map { String(tail[$0].dropFirst().dropLast()) } ?? ""
        let teacher = tail.components(separatedBy: "[").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let weekText = String(text[weekMatch])
        let pattern = try? NSRegularExpression(pattern: "([0-9]+)(?:-([0-9]+))?周")
        let ns = weekText as NSString
        let weeks = pattern?.matches(in: weekText, range: NSRange(location: 0, length: ns.length)).compactMap { match -> ClosedRange<Int>? in
            guard let start = Int(ns.substring(with: match.range(at: 1))) else { return nil }
            let end = match.range(at: 2).location == NSNotFound ? start : Int(ns.substring(with: match.range(at: 2))) ?? start
            return start <= end && end <= 30 ? start...end : nil
        } ?? []
        guard !weeks.isEmpty else { return nil }
        return (name, room, teacher, weeks)
    }
}

struct GraduateLoginView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: URL(string: "https://gmsstu.zzu.edu.cn/stu/")!))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
