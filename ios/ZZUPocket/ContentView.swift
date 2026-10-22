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
                    FocusScreen().tabItem { Label("专注", systemImage: "timer") }
                    LibraryScreen().tabItem { Label("图书馆", systemImage: "books.vertical") }
                    settings.tabItem { Label("我的", systemImage: "person.crop.circle") }
                }
                .tint(PocketStyle.accent)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                if !model.semesters.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("当前学期", systemImage: "sparkles")
                            .font(.caption.weight(.semibold)).foregroundStyle(PocketStyle.accent)
                        Picker("学期", selection: $model.selectedSemester) {
                            ForEach(model.semesters) { semester in Text(semester.name).tag(Optional(semester.id)) }
                        }
                        .pickerStyle(.menu)
                        .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onChange(of: model.selectedSemester) { _, _ in
                        if !model.busy { Task { await model.perform { try await model.loadSemester() } } }
                    }
                    HStack(spacing: 16) {
                        weekButton("chevron.left", disabled: model.week <= (model.semesters.first(where: { $0.id == model.selectedSemester })?.weeks.first ?? 1)) { model.week -= 1 }
                        VStack(spacing: 3) {
                            Text("第 \(model.week) 周").font(.title2.bold()).contentTransition(.numericText())
                            Text("按周查看课程安排").font(.caption).foregroundStyle(.white.opacity(0.8))
                        }.frame(maxWidth: .infinity)
                        weekButton("chevron.right", disabled: model.week >= (model.semesters.first(where: { $0.id == model.selectedSemester })?.weeks.last ?? 20)) { model.week += 1 }
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(LinearGradient(colors: [PocketStyle.accent, PocketStyle.deepAccent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    let selected = model.lessons.filter { $0.week == model.week }.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }
                    if selected.isEmpty {
                        ContentUnavailableView("本周暂无课程", systemImage: "sun.max", description: Text("可以切换周次，查看其他课程安排。"))
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    ForEach(1...7, id: \.self) { day in
                        let rows = selected.filter { $0.weekday == day }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1])
                                        .font(.headline)
                                    Text("\(rows.count) 门课程")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(rows) { lesson in
                                    LessonCard(lesson: lesson)
                                }
                            }
                        }
                    }
                } else if !model.busy {
                    ContentUnavailableView("准备好查看课表了吗？", systemImage: "calendar.badge.clock", description: Text("同步本科教务课表后，课程安排会显示在这里。"))
                }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("课表")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { Button { Task { await model.perform { try await model.refreshSchedule() } } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy).accessibilityLabel("同步课表") }
            .overlay { if model.busy { ProgressView() } }
            .task { if model.semesters.isEmpty { await model.perform { try await model.refreshSchedule() } } }
        }
    }

    private var campus: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("校园卡余额", systemImage: "creditcard.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        Text(model.balance.map { String(format: "¥%.2f", $0) } ?? "¥ --")
                            .font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(.white).contentTransition(.numericText())
                        Button { Task { await model.perform { try await model.refreshBalance() } } } label: {
                            Label("刷新余额", systemImage: "arrow.clockwise").font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(.white.opacity(0.18), in: Capsule())
                        }.foregroundStyle(.white).disabled(model.busy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(LinearGradient(colors: [PocketStyle.accent, PocketStyle.deepAccent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("最近消费", systemImage: "list.bullet.rectangle.portrait")
                                .font(.headline)
                            Spacer()
                            Button("近 30 天") { Task { await model.perform { try await model.refreshTrades() } } }.font(.subheadline.weight(.semibold))
                        }
                    ForEach(model.trades) { trade in
                        HStack(spacing: 12) {
                            Image(systemName: trade.amount < 0 ? "arrow.up.right" : "arrow.down.left")
                                .font(.caption.bold()).foregroundStyle(trade.amount < 0 ? PocketStyle.accent : .green)
                                .frame(width: 38, height: 38).background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(trade.merchant.isEmpty ? trade.summary : trade.merchant).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(trade.date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(String(format: "%@¥%.2f", trade.amount < 0 ? "−" : "+", abs(trade.amount)))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                        if model.trades.isEmpty {
                            Text("点击“近 30 天”加载校园卡交易记录。")
                                .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Label("宿舍电量", systemImage: "bolt.fill").font(.headline).foregroundStyle(PocketStyle.deepAccent)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(model.electricity.map { String(format: "%.2f", $0) } ?? "--")
                                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            Text("度").foregroundStyle(.secondary)
                        }
                        TextField("房间编号，例如 99-16--32-8101", text: $model.roomId)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit { model.saveRoom() }
                            .padding(13).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        HStack(spacing: 10) {
                            Button { showingRooms = true; Task { await model.perform { try await model.startRoomPicker() } } } label: {
                                Label("选择房间", systemImage: "location.magnifyingglass").frame(maxWidth: .infinity).padding(12)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }.disabled(model.busy)
                            Button { model.saveRoom(); Task { await model.perform { try await model.refreshElectricity() } } } label: {
                                Label("查电量", systemImage: "bolt.fill").frame(maxWidth: .infinity).padding(12)
                                    .foregroundStyle(.white).background(PocketStyle.accent, in: RoundedRectangle(cornerRadius: 12))
                            }.disabled(model.busy || model.roomId.isEmpty)
                        }.font(.subheadline.weight(.semibold))
                    }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "graduationcap.fill").font(.title2).foregroundStyle(.white)
                            .frame(width: 54, height: 54).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("研究生教务").font(.title3.bold()).foregroundStyle(.white)
                            Text("独立网页认证 · 与本科课表分开同步").font(.caption).foregroundStyle(.white.opacity(0.82))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .background(LinearGradient(colors: [PocketStyle.accent, PocketStyle.deepAccent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Section {
                    Button { showingLogin = true } label: { Label("登录研究生系统", systemImage: "person.badge.key.fill") }
                    Button { Task { await grad.refresh() } } label: { Label("同步研究生课表", systemImage: "arrow.clockwise") }.disabled(grad.busy)
                } footer: {
                    Text("研究生教务使用学校网页会话，需要在学校页面单独登录；CAS 令牌不能直接查询研究生课表。")
                }
                if !grad.terms.isEmpty {
                    Picker("学期", selection: $grad.selectedTerm) {
                        ForEach(grad.terms) { term in Text(term.name).tag(term.code) }
                    }.onChange(of: grad.selectedTerm) { _, code in
                        if !grad.busy { Task { await grad.selectTerm(code) } }
                    }
                    HStack { weekButton("chevron.left", disabled: grad.week <= 1) { grad.week -= 1 }; Text("第 \(grad.week) 周").font(.headline).frame(maxWidth: .infinity); weekButton("chevron.right", disabled: grad.week >= 30) { grad.week += 1 } }
                    let selected = grad.lessons.filter { $0.week == grad.week }.sorted { ($0.weekday, $0.start) < ($1.weekday, $1.start) }
                    if selected.isEmpty { ContentUnavailableView("本周暂无课程", systemImage: "calendar") }
                    ForEach(1...7, id: \.self) { day in
                        let rows = selected.filter { $0.weekday == day }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][day - 1]).font(.headline)
                                ForEach(rows) { LessonCard(lesson: $0) }
                            }
                        }
                    }
                }
            }
            .padding(18)
            .background(Color(uiColor: .systemGroupedBackground))
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
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 76, height: 76).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            Text("ZZUPocket").font(.largeTitle.bold()).foregroundStyle(.white)
                            Text("郑州大学校园助手").font(.subheadline).foregroundStyle(.white.opacity(0.86))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                        .background(LinearGradient(colors: [PocketStyle.accent, PocketStyle.deepAccent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                        VStack(alignment: .leading, spacing: 16) {
                            Text("欢迎回来").font(.title2.bold())
                            Text("使用学校统一身份认证登录").font(.subheadline).foregroundStyle(.secondary)
                            credentialField("学号", icon: "person", content: {
                                TextField("请输入学号", text: $account).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            })
                            credentialField("密码", icon: "lock", content: {
                                SecureField("请输入密码", text: $password).textContentType(.password)
                            })
                            if let challenge {
                                credentialField("短信验证码", icon: "message", content: {
                                    TextField("请输入验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                                })
                                Button("重新发送验证码") { Task { await model.perform { try await CAS.send(challenge) } } }
                                    .font(.subheadline.weight(.medium)).disabled(model.busy)
                            }
                            Button {
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
                            } label: {
                                HStack { Spacer(); Text(challenge == nil ? "安全登录" : "验证并登录"); Spacer(); Image(systemName: "arrow.right") }
                                    .font(.headline).foregroundStyle(.white).padding(16)
                                    .background(PocketStyle.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }.disabled(model.busy || account.isEmpty || password.isEmpty || (challenge != nil && code.isEmpty))
                        }
                        .padding(20).background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        Text("密码不会保存 · 登录令牌仅安全保存在本机 Keychain")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(20)
                }
            }
            .overlay { if model.busy { ProgressView() } }
        }
    }

    private func credentialField<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(PocketStyle.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                content().font(.body)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private enum PocketStyle {
    static let accent = Color(red: 0.16, green: 0.39, blue: 0.82)
    static let deepAccent = Color(red: 0.10, green: 0.25, blue: 0.59)
    static let softAccent = Color(red: 0.91, green: 0.94, blue: 1.0)
}

private struct LessonCard: View {
    let lesson: Lesson

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3).fill(PocketStyle.accent).frame(width: 4)
            VStack(alignment: .leading, spacing: 9) {
                Text(lesson.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 12) {
                    Label("第 \(lesson.start)-\(lesson.end) 节", systemImage: "clock")
                    if !lesson.room.isEmpty { Label(lesson.room, systemImage: "location") }
                }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !lesson.teacher.isEmpty { Label(lesson.teacher, systemImage: "person") .font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.padding(.vertical, 13).padding(.horizontal, 14)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private func weekButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.subheadline.bold()).frame(width: 40, height: 40).background(.white.opacity(0.17), in: Circle()) }
        .disabled(disabled).opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(symbol == "chevron.left" ? "上一周" : "下一周")
}
