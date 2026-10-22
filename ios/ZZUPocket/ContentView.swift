import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: PocketModel
    @State private var showingRooms = false

    var body: some View {
        Group {
            if model.loggedIn {
                TabView {
                    schedule.tabItem { Label("课表", systemImage: "calendar") }
                    GraduateScheduleView().tabItem { Label("研究生", systemImage: "graduationcap") }
                    campus.tabItem { Label("校园", systemImage: "building.2") }
                    settings.tabItem { Label("我的", systemImage: "person.crop.circle") }
                }
            } else {
                LoginView()
            }
        }
        .alert("提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("确定", role: .cancel) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var schedule: some View {
        NavigationStack {
            List {
                if !model.semesters.isEmpty {
                    Picker("学期", selection: $model.selectedSemester) {
                        ForEach(model.semesters) { semester in Text(semester.name).tag(Optional(semester.id)) }
                    }
                    .onChange(of: model.selectedSemester) { _, _ in
                        if !model.busy { Task { await model.perform { try await model.loadSemester() } } }
                    }
                    HStack {
                        Button { model.week -= 1 } label: { Image(systemName: "chevron.left") }.disabled(model.week <= (model.semesters.first(where: { $0.id == model.selectedSemester })?.weeks.first ?? 1))
                        Spacer()
                        Text("第 \(model.week) 周").font(.headline)
                        Spacer()
                        Button { model.week += 1 } label: { Image(systemName: "chevron.right") }.disabled(model.week >= (model.semesters.first(where: { $0.id == model.selectedSemester })?.weeks.last ?? 20))
                    }
                    let selected = model.lessons.filter { $0.week == model.week }.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }
                    if selected.isEmpty { ContentUnavailableView("本周暂无课程", systemImage: "calendar") }
                    ForEach(1...7, id: \.self) { day in
                        let rows = selected.filter { $0.weekday == day }
                        if !rows.isEmpty {
                            Section(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1]) {
                                ForEach(rows) { lesson in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(lesson.name).font(.headline)
                                        Text("第 \(lesson.start)-\(lesson.end) 节  \(lesson.time)")
                                        if !lesson.room.isEmpty { Text(lesson.room) }
                                        if !lesson.teacher.isEmpty { Text(lesson.teacher) }
                                    }.font(.subheadline)
                                }
                            }
                        }
                    }
                } else if !model.busy {
                    ContentUnavailableView("尚无课表", systemImage: "calendar", description: Text("点击右上角同步本科教务课表"))
                }
            }
            .navigationTitle("课表")
            .toolbar { Button { Task { await model.perform { try await model.refreshSchedule() } } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy).accessibilityLabel("同步课表") }
            .overlay { if model.busy { ProgressView() } }
            .task { if model.semesters.isEmpty { await model.perform { try await model.refreshSchedule() } } }
        }
    }

    private var campus: some View {
        NavigationStack {
            Form {
                Section("校园卡") {
                    LabeledContent("余额", value: model.balance.map { String(format: "¥%.2f", $0) } ?? "--")
                    Button("查询余额") { Task { await model.perform { try await model.refreshBalance() } } }.disabled(model.busy)
                    Button("近 30 天流水") { Task { await model.perform { try await model.refreshTrades() } } }.disabled(model.busy)
                    ForEach(model.trades) { trade in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(trade.merchant.isEmpty ? trade.summary : trade.merchant)
                                Spacer()
                                Text(String(format: "¥%.2f", trade.amount))
                            }
                            Text(trade.date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("宿舍电量") {
                    TextField("房间 ID，如 99-16--32-8101", text: $model.roomId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { model.saveRoom() }
                    Button("在线选择房间") {
                        showingRooms = true
                        Task { await model.perform { try await model.startRoomPicker() } }
                    }.disabled(model.busy)
                    LabeledContent("剩余电量", value: model.electricity.map { String(format: "%.2f 度", $0) } ?? "--")
                    Button("查询电量") { model.saveRoom(); Task { await model.perform { try await model.refreshElectricity() } } }.disabled(model.busy || model.roomId.isEmpty)
                }
            }
            .navigationTitle("校园")
            .overlay { if model.busy { ProgressView() } }
            .sheet(isPresented: $showingRooms) {
                NavigationStack {
                    List(model.roomNodes) { node in
                        Button(node.name) {
                            if model.roomIsLastLevel {
                                Task { await model.perform { try await model.pickRoomNode(node) }; if model.error == nil { showingRooms = false } }
                            } else {
                                Task { await model.perform { try await model.pickRoomNode(node) } }
                            }
                        }
                    }
                    .navigationTitle("选择\(model.roomLevel)")
                    .toolbar { Button("关闭") { showingRooms = false } }
                    .overlay { if model.busy { ProgressView() } }
                }
            }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section {
                    Button("退出登录", role: .destructive) { model.signOut() }
                }
                Section { Text("ZZUPocket 是非官方校园助手。数据直接与学校系统交互，登录令牌仅保存在本机。") }
            }
            .navigationTitle("我的")
        }
    }
}

private struct GraduateScheduleView: View {
    @StateObject private var grad = GraduateSchedule()
    @State private var showingLogin = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("登录研究生系统") { showingLogin = true }
                    Button("同步研究生课表") { Task { await grad.refresh() } }.disabled(grad.busy)
                } footer: {
                    Text("研究生教务使用学校网页会话，需要在学校页面单独登录；CAS 令牌不能直接查询研究生课表。")
                }
                if !grad.terms.isEmpty {
                    Picker("学期", selection: $grad.selectedTerm) {
                        ForEach(grad.terms) { term in Text(term.name).tag(term.code) }
                    }.onChange(of: grad.selectedTerm) { _, code in
                        if !grad.busy { Task { await grad.selectTerm(code) } }
                    }
                    HStack {
                        Button { grad.week -= 1 } label: { Image(systemName: "chevron.left") }.disabled(grad.week <= 1)
                        Spacer()
                        Text("第 \(grad.week) 周").font(.headline)
                        Spacer()
                        Button { grad.week += 1 } label: { Image(systemName: "chevron.right") }.disabled(grad.week >= 30)
                    }
                    let selected = grad.lessons.filter { $0.week == grad.week }.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }
                    if selected.isEmpty { ContentUnavailableView("本周暂无课程", systemImage: "calendar") }
                    ForEach(1...7, id: \.self) { day in
                        let rows = selected.filter { $0.weekday == day }
                        if !rows.isEmpty {
                            Section(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1]) {
                                ForEach(rows) { lesson in
                                    VStack(alignment: .leading) {
                                        Text(lesson.name).font(.headline)
                                        Text("第 \(lesson.start) 节")
                                        if !lesson.room.isEmpty { Text(lesson.room) }
                                        if !lesson.teacher.isEmpty { Text(lesson.teacher) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("研究生课表")
            .overlay { if grad.busy { ProgressView() } }
            .sheet(isPresented: $showingLogin, onDismiss: { Task { await grad.refresh() } }) {
                NavigationStack {
                    GraduateLoginView().ignoresSafeArea(edges: .bottom)
                        .navigationTitle("学校认证")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("完成") { showingLogin = false } }
                }
            }
            .alert("研究生教务", isPresented: Binding(get: { grad.error != nil }, set: { if !$0 { grad.error = nil } })) {
                Button("确定", role: .cancel) { grad.error = nil }
            } message: { Text(grad.error ?? "") }
        }
    }
}

private struct LoginView: View {
    @EnvironmentObject private var model: PocketModel
    @State private var account = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challenge: CAS.Challenge?

    var body: some View {
        NavigationStack {
            Form {
                Section("郑州大学统一身份认证") {
                    TextField("学号", text: $account).textContentType(.username).textInputAutocapitalization(.never)
                    SecureField("密码", text: $password).textContentType(.password)
                    if let challenge {
                        TextField("短信验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        Button("重新发送验证码") { Task { await model.perform { try await CAS.send(challenge) } } }.disabled(model.busy)
                    }
                    Button(challenge == nil ? "登录" : "验证并登录") {
                        Task {
                            await model.perform {
                                if let challenge {
                                    try await CAS.verify(challenge, code: code)
                                    try await finish(state: challenge.state)
                                } else {
                                    let (state, next) = try await CAS.detect(account: account, password: password)
                                    if let next {
                                        challenge = next
                                        try await CAS.send(next)
                                    } else {
                                        try await finish(state: state)
                                    }
                                }
                            }
                        }
                    }.disabled(model.busy || account.isEmpty || password.isEmpty || (challenge != nil && code.isEmpty))
                }
                Section { Text("密码不会保存。登录令牌保存在本机 Keychain，过期后需重新登录。") }
            }
            .navigationTitle("登录")
            .overlay { if model.busy { ProgressView() } }
        }
    }

    private func finish(state: String) async throws {
        let token = try await CAS.login(account: account, password: password, state: state)
        TokenStore.save(token)
        password = ""
        code = ""
        challenge = nil
        model.token = token
    }
}
