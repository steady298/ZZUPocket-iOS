import Foundation
import Security

enum PocketError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

enum API {
    static let cas = "https://cas.s.zzu.edu.cn"
    static let jwxt = "https://jwxt.zzu.edu.cn"
    static let ecard = "https://ecard.v.zzu.edu.cn"

    static func request(_ url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, redirects: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let session = redirects ? URLSession.shared : URLSession(configuration: .ephemeral, delegate: NoRedirects.shared, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 25
        request.setValue("okhttp/3.12.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: request)
        if !redirects { session.invalidateAndCancel() }
        guard let http = response as? HTTPURLResponse else { throw PocketError.message("无效的服务器响应") }
        return (data, http)
    }

    static func json(_ data: Data, _ response: HTTPURLResponse) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PocketError.message("服务器返回 HTTP \(response.statusCode)，响应不是 JSON。请稍后重试")
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = value["message"] as? String ?? value["msg"] as? String ?? value["error"] as? String
            throw PocketError.message("服务器返回 HTTP \(response.statusCode)\(message.map { "：\($0)" } ?? "")")
        }
        return value
    }

    static func url(_ base: String, _ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var parts = URLComponents(string: base + path) else { throw PocketError.message("无效的服务地址") }
        parts.queryItems = query.isEmpty ? nil : query
        // Foundation leaves '+' untouched in query items. CAS interprets query as form data,
        // where '+' becomes a space. RSA Base64 must therefore send '+' as '%2B'.
        if let encoded = parts.percentEncodedQuery {
            parts.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let result = parts.url else { throw PocketError.message("无效的请求地址") }
        return result
    }

    static func postJSON(_ url: URL, token: String, payload: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await request(url, method: "POST", headers: ["Authorization": token, "Content-Type": "application/json"], body: body)
        return try json(data, response)
    }

    static func eas(_ path: String, token: String, step: String) async throws -> [String: Any] {
        let url = try self.url(jwxt, path)
        let (data, response) = try await request(url, headers: ["Authorization": token], redirects: false)
        if response.statusCode == 401 || response.statusCode == 403 {
            let identityURL = try self.url(jwxt, "/eams-door/api/v1/portal/home/user-info")
            let identityStatus: Int?
            do {
                let (_, probeResponse) = try await request(identityURL, headers: ["Authorization": token], redirects: false)
                identityStatus = probeResponse.statusCode
            } catch {
                identityStatus = nil
            }
            if identityStatus == 401 || identityStatus == 403 {
                throw PocketError.message("本科教务未接受此账号（\(step) · HTTP \(response.statusCode)）。若你是研究生，课表在研究生系统，当前 iOS 版尚未接入；若你是本科生，请重新登录后再试。")
            }
            if identityStatus == 200 {
                throw PocketError.message("本科教务拒绝\(step)（HTTP \(response.statusCode)），但用户信息接口可访问。请稍后重试或联系学校教务系统。")
            }
            throw PocketError.message("本科教务未通过鉴权（\(step) · HTTP \(response.statusCode)）。请退出并重新登录；若仍失败，需检查该账号的教务权限。")
        }
        do { return try json(data, response) }
        catch { throw PocketError.message("本科教务\(step)：\(error.localizedDescription)") }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirects()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

enum TokenStore {
    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ZZUPocket.CAS", kSecAttrAccount as String: "idToken", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ZZUPocket.CAS", kSecAttrAccount as String: "idToken"]
        SecItemDelete(query as CFDictionary)
        if let token {
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

enum CAS {
    struct Challenge {
        let state: String
        let gid: String
        let attest: String
    }

    private static let appHeaders = ["User-Agent": "SWSuperApp/1.1.1()"]

    static func detect(account: String, password: String) async throws -> (String, Challenge?) {
        let key = try await publicKey()
        let url = try API.url(API.cas, "/token/mfa/detect", query: [
            .init(name: "username", value: try encrypt(account, key)),
            .init(name: "password", value: try encrypt(password, key)),
            .init(name: "deviceId", value: deviceId)
        ])
        let (data, response) = try await API.request(url, method: "POST", headers: appHeaders, body: Data())
        let value = try envelope(data, response, step: "检测是否需要短信验证")
        guard let result = value["data"] as? [String: Any], let state = result["state"] as? String else { throw PocketError.message("登录状态缺失") }
        guard result["need"] as? Bool == true else { return (state, nil) }
        guard result["mfaTypeSecurePhone"] as? Bool == true else { throw PocketError.message("该账号不支持手机号验证") }
        let initURL = try API.url(API.cas, "/token/mfa/initByType/securephone", query: [.init(name: "state", value: state)])
        let (initData, initResponse) = try await API.request(initURL, headers: appHeaders)
        let initValue = try envelope(initData, initResponse, step: "初始化短信验证")
        guard let info = initValue["data"] as? [String: Any], let gid = info["gid"] as? String, !gid.isEmpty else { throw PocketError.message("短信验证初始化失败") }
        return (state, Challenge(state: state, gid: gid, attest: (info["attestServerUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(API.cas)/attest/api/guard"))
    }

    static func send(_ challenge: Challenge) async throws {
        _ = try await sms(challenge, path: "send", data: ["gid": challenge.gid])
    }

    static func verify(_ challenge: Challenge, code: String) async throws {
        let result = try await sms(challenge, path: "valid", data: ["gid": challenge.gid, "code": code])
        guard (result["data"] as? [String: Any])?["status"] as? Int == 2 else { throw PocketError.message("验证码错误或已过期") }
    }

    private static func sms(_ challenge: Challenge, path: String, data: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: challenge.attest.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/guard/securephone/" + path), url.scheme == "https", url.host == URL(string: API.cas)?.host else { throw PocketError.message("短信服务地址无效") }
        let (body, response) = try await API.request(url, method: "POST", headers: appHeaders.merging(["Content-Type": "application/json"]) { _, new in new }, body: try JSONSerialization.data(withJSONObject: data))
        return try envelope(body, response, step: path == "send" ? "发送验证码" : "校验验证码")
    }

    static func login(account: String, password: String, state: String) async throws -> String {
        let key = try await publicKey()
        let values = ["username": try encrypt(account, key), "password": try encrypt(password, key), "appId": "com.supwisdom.zzu", "osType": "android", "geo": "", "deviceId": deviceId, "clientId": "", "mfaState": state]
        let url = try API.url(API.cas, "/token/password/passwordLogin", query: values.map { URLQueryItem(name: $0.key, value: $0.value) })
        let (body, response) = try await API.request(url, method: "POST", headers: appHeaders, body: Data())
        let value = try envelope(body, response, step: "获取登录令牌")
        guard let token = (value["data"] as? [String: Any])?["idToken"] as? String, !token.isEmpty else { throw PocketError.message("服务器未返回令牌") }
        return token
    }

    private static func envelope(_ data: Data, _ response: HTTPURLResponse, step: String) throws -> [String: Any] {
        let value: [String: Any]
        do { value = try API.json(data, response) }
        catch { throw PocketError.message("\(step)：\(safeMessage(error.localizedDescription))") }
        guard value["code"] as? Int == 0 else { throw PocketError.message("\(step)：\(safeMessage(value["message"] as? String ?? "认证失败"))") }
        return value
    }

    private static func safeMessage(_ text: String) -> String {
        // A CAS decrypt error may echo the entire encrypted username/password; don't display it.
        if text.contains("解密字符串") { return "认证服务无法解密请求参数，请更新客户端后重试" }
        return String(text.prefix(200))
    }

    private static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: "casDeviceId") { return existing }
        let id = "zzupocket-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "casDeviceId")
        return id
    }

    private static func publicKey() async throws -> SecKey {
        let url = try API.url(API.cas, "/token/jwt/publicKey")
        let (data, response) = try await API.request(url, headers: ["User-Agent": "okhttp/3.12.1"])
        guard (200..<300).contains(response.statusCode), let pem = String(data: data, encoding: .utf8) else { throw PocketError.message("获取认证公钥失败") }
        let stripped = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined().filter { !$0.isWhitespace }
        guard let der = Data(base64Encoded: stripped), let keyData = rsaKeyData(der) else { throw PocketError.message("认证公钥格式无效") }
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic] as CFDictionary, &error) else { throw PocketError.message("无法导入认证公钥") }
        return key
    }

    // SecKey expects PKCS#1 RSA bytes; the CAS PEM uses X.509 SubjectPublicKeyInfo.
    private static func rsaKeyData(_ der: Data) -> Data? {
        let bytes = [UInt8](der)
        func element(_ offset: Int) -> (tag: UInt8, start: Int, end: Int)? {
            guard offset + 2 <= bytes.count else { return nil }
            let first = Int(bytes[offset + 1])
            var start = offset + 2
            var length = first
            if first & 0x80 != 0 {
                let count = first & 0x7f
                guard count > 0, count <= 4, start + count <= bytes.count else { return nil }
                length = 0
                for index in start..<(start + count) { length = length * 256 + Int(bytes[index]) }
                start += count
            }
            guard length <= bytes.count - start else { return nil }
            return (bytes[offset], start, start + length)
        }
        guard let root = element(0), root.tag == 0x30, root.end == bytes.count,
              let algorithm = element(root.start), algorithm.tag == 0x30,
              let bitString = element(algorithm.end), bitString.tag == 0x03,
              bitString.end == root.end, bitString.start < bitString.end,
              bytes[bitString.start] == 0,
              let rsa = element(bitString.start + 1), rsa.tag == 0x30, rsa.end == bitString.end else { return nil }
        return Data(bytes[(bitString.start + 1)..<bitString.end])
    }

    private static func encrypt(_ text: String, _ key: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, Data(text.utf8) as CFData, &error) as Data? else { throw PocketError.message("账号加密失败") }
        return "__RSA__" + data.base64EncodedString()
    }
}
