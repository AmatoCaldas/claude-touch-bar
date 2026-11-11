import AppKit
import Charts
import SwiftUI

final class DetailModel: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var approvals: [ApprovalRequest] = []
    @Published var selectedSession: URL?
    @Published var layout = Settings.layout
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    @Published var hooksInstalled = HookInstaller.isInstalled
    @Published var accessibilityTrusted = KeySender.isTrusted
    @Published var hookError: String?
    @Published var section: Section = .overview

    enum Section: String, CaseIterable, Identifiable {
        case overview, touchBar, integration, git, general
        var id: String { rawValue }

        /// Tabs shown in the sidebar; Git and Push is hidden along with the ↑ button.
        static let visible = allCases.filter { $0 != .git }

        var title: String {
            switch self {
            case .overview: return L("Visão geral", "Overview")
            case .touchBar: return "Touch Bar"
            case .integration: return L("Integração com o Claude", "Claude integration")
            case .git: return L("Git e Push", "Git and Push")
            case .general: return L("Geral", "General")
            }
        }

        var symbol: String {
            switch self {
            case .overview: return "chart.bar"
            case .touchBar: return "rectangle.3.group"
            case .integration: return "link"
            case .git: return "arrow.up.circle"
            case .general: return "gearshape"
            }
        }
    }

    var onLayoutPicked: ((Layout) -> Void)?
    var onSelectSession: ((URL?) -> Void)?
    var onApproval: ((UUID, ApprovalDecision) -> Void)?
    var onSettingsChanged: (() -> Void)?

    func reloadStatus() {
        launchAtLogin = LaunchAtLogin.isEnabled
        hooksInstalled = HookInstaller.isInstalled
        accessibilityTrusted = KeySender.isTrusted
    }

    /// Settings changed from the window: refresh both the window and the bar.
    func changed() {
        objectWillChange.send()
        onSettingsChanged?()
    }
}

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        NavigationSplitView {
            List(DetailModel.Section.visible, selection: Binding(
                get: { model.section },
                set: { if let section = $0 { model.section = section } }
            )) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.section {
                    case .overview: OverviewSection(model: model)
                    case .touchBar: TouchBarSection(model: model)
                    case .integration: IntegrationSection(model: model)
                    case .git: GitSection(model: model)
                    case .general: GeneralSection(model: model)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(model.section.title)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

/// A thin progress bar used across the sections.
struct Meter: View {
    let fraction: Double
    let color: NSColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color(nsColor: color))
                    .frame(width: max(6, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}

private func toggle(_ model: DetailModel, _ title: String, _ get: @escaping () -> Bool,
                    _ set: @escaping (Bool) -> Void) -> some View {
    Toggle(title, isOn: Binding(get: get, set: { set($0); model.changed() }))
}

// MARK: - Přehled

struct OverviewSection: View {
    @ObservedObject var model: DetailModel
    private var s: Snapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let request = model.approvals.first { approvalBox(request) }
            context
            if let plan = s.plan { planBox(plan) }
            sessionPicker
            Divider()
            tokenTable
            HStack(spacing: 24) {
                stat(L("Ritmo", "Rate"), Format.cost(s.hourlyRate) + "/h" + (Settings.showsBRL ? " (≈\u{00A0}" + Format.brl(s.hourlyRate) + ")" : ""))
                stat(L("Ativo hoje", "Active today"), Format.minutes(s.activeMinutes))
                stat(L("Arquivos alterados", "Changed files"), "\(s.changedFiles.count)")
            }
            charts
            budget
            if !s.changedFiles.isEmpty { filesList }
            Text(L("O custo é uma estimativa pelo preço da API; assinaturas Pro/Max não são cobradas por token.", "Cost is a rough estimate from API pricing; Pro/Max subscriptions aren't billed per token."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stateText: String {
        switch s.activity {
        case .working: return L("trabalhando", "working")
        case .waiting: return L("esperando você", "waiting for you")
        case .done: return L("pronto", "done")
        case .idle: return L("parado", "idle")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.title ?? (s.hasSession ? L("Sessão do Code", "Code session") : L("Nenhuma sessão do Code", "No Code session"))).font(.title3.bold())
            Text([s.project, s.hasSession ? s.modelName : nil, s.mode.map { L("modo ", "mode ") + $0 }, stateText, s.tool]
                .compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
        }
    }

    private func approvalBox(_ request: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Esperando aprovação", "Waiting for approval") + (model.approvals.count > 1 ? " (\(model.approvals.count))" : "")).bold()
            Text(request.toolName + (request.summary.isEmpty ? "" : ": " + request.summary))
                .font(.system(.body, design: .monospaced))
                .lineLimit(3)
            HStack {
                Button(L("Permitir", "Allow")) { model.onApproval?(request.id, .allow) }
                if request.canAlwaysAllow { Button(L("Sempre permitir", "Always allow")) { model.onApproval?(request.id, .always) } }
                Button(L("Negar", "Deny"), role: .destructive) { model.onApproval?(request.id, .deny) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Contexto", "Context"))
                Spacer()
                Text("\(Format.tokens(s.contextUsed)) " + L("de", "of") + " \(Format.tokens(s.contextWindow)) · \(Format.percent(s.contextFraction))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Meter(fraction: s.contextFraction,
                  color: s.contextFraction >= 0.7 ? Palette.context(s.contextFraction) : Palette.claude)
        }
    }

    // Intel build: split out of the view bodies so swiftc type-checks them in time.
    private func planLabel(_ plan: PlanProgress) -> String {
        var text: String = "\(plan.done) " + L("de", "of")
        text += " \(plan.total) " + L("etapas", "steps")
        if let eta = plan.eta {
            text += L(" · faltam ~", " · ~") + Format.duration(eta) + L("", " left")
        }
        return text
    }

    private func budgetLabel(_ fraction: Double) -> String {
        var text: String = L("Hoje", "Today") + " \(Format.price(s.today.cost)) "
        text += L("de", "of") + " \(Format.price(Settings.dailyBudget)) · \(Format.percent(fraction))"
        if let runway = s.budgetRunway(Settings.dailyBudget) {
            text += L(" · no ritmo atual dura ", " · at the current pace lasts ") + Format.runway(runway)
        }
        return text
    }

    private func planBox(_ plan: PlanProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Progresso", "Progress"))
                Spacer()
                Text(planLabel(plan))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Meter(fraction: plan.fraction, color: (plan.done == plan.total ? Palette.done : Palette.claude) as NSColor)
            if let current = plan.current {
                Text(L("Agora: ", "Now: ") + current).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var sessionPicker: some View {
        if s.sessions.count > 1 {
            Picker(L("Sessão", "Session"), selection: Binding(get: { model.selectedSession }, set: { model.onSelectSession?($0) })) {
                Text(L("Automático (a que precisa de você)", "Automatic (the one that needs you)")).tag(URL?.none)
                ForEach(s.sessions) { session in
                    Text(session.title).tag(URL?.some(session.url))
                }
            }
        }
    }

    private var tokenTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 5) {
            GridRow {
                Text("").frame(maxWidth: .infinity).gridColumnAlignment(.leading)
                ForEach([L("Sessão", "Session"), "5 h", L("Hoje", "Today"), L("Semana", "Week"), L("Mês", "Month")], id: \.self) { Text($0).bold() }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(L("Total", "All time")).bold()
                    if let since = s.allTimeSince {
                        Text(L("desde ", "since ") + Format.day(since)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            row(L("Entrada", "Input"), \.input)
            row(L("Leitura de cache", "Cache read"), \.cacheRead)
            row(L("Escrita de cache", "Cache write"), \.cacheWrite)
            row(L("Saída", "Output"), \.output)
            Divider().gridCellUnsizedAxes(.horizontal)
            row(L("Total", "Total"), \.total)
            GridRow {
                Text(L("Custo estimado", "Estimated cost"))
                ForEach(columns.indices, id: \.self) { Text(Format.cost(columns[$0].cost)) }
            }
            .bold()
            // The columns have no room for "$27 (≈ R$ 150)", so R$ gets its own row.
            if Settings.showsBRL {
                GridRow {
                    Text("≈ em R$").foregroundStyle(.secondary)
                    ForEach(columns.indices, id: \.self) { Text(Format.brl(columns[$0].cost)).foregroundStyle(.secondary) }
                }
            }
        }
        .monospacedDigit()
    }

    private var columns: [Tokens] { [s.session, s.fiveHours, s.today, s.week, s.month, s.allTime] }

    private func row(_ label: String, _ key: KeyPath<Tokens, Int>) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            ForEach(columns.indices, id: \.self) { Text(Format.tokens(columns[$0][keyPath: key])) }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }

    private struct Bar: Identifiable {
        let date: Date
        let cost: Double
        var id: Date { date }
    }

    private var charts: some View {
        let now = Date()
        let hours = s.hourly.enumerated().map {
            Bar(date: now.addingTimeInterval(-Double(s.hourly.count - 1 - $0.offset) * 3600), cost: $0.element)
        }
        let today = Calendar.current.startOfDay(for: now)
        let days = s.daily.enumerated().map {
            Bar(date: Calendar.current.date(byAdding: .day, value: -(s.daily.count - 1 - $0.offset), to: today) ?? today,
                cost: $0.element)
        }
        return HStack(alignment: .top, spacing: 20) {
            chart(L("Últimas 24 h", "Last 24 h"), hours, unit: .hour, stride: 6, format: .dateTime.hour())
            chart(L("Últimos 30 dias", "Last 30 days"), days, unit: .day, stride: 7, format: .dateTime.day().month())
        }
    }

    private func chart(_ title: String, _ bars: [Bar], unit: Calendar.Component, stride: Int,
                       format: Date.FormatStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            Chart(bars) { bar in
                BarMark(x: .value(L("Tempo", "Time"), bar.date, unit: unit), y: .value("USD", bar.cost))
                    .foregroundStyle(Color(nsColor: Palette.claude))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: unit, count: stride)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: format)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text(Format.cost(value.as(Double.self) ?? 0)) }
                }
            }
            .frame(height: 120)
        }
    }

    private var budget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Orçamento diário", "Daily budget"))
                Spacer()
                TextField(L("desligado", "off"), value: Binding(
                    get: { Settings.dailyBudget > 0 ? Settings.dailyBudget : nil },
                    set: { Settings.dailyBudget = $0 ?? 0; model.changed() }
                ), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                Text("$")
            }
            if Settings.dailyBudget > 0 {
                let fraction = s.today.cost / Settings.dailyBudget
                Meter(fraction: fraction, color: (fraction >= 1 ? Palette.danger : (fraction >= 0.8 ? Palette.warning : Palette.claude)) as NSColor)
                Text(budgetLabel(fraction))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var filesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Arquivos alterados na sessão", "Files changed in the session")).font(.subheadline)
            ForEach(s.changedFiles, id: \.self) { path in
                Text(path.replacingOccurrences(of: s.cwd.map { $0 + "/" } ?? "\u{0}", with: ""))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - Touch Bar

struct TouchBarSection: View {
    @ObservedObject var model: DetailModel
    @State private var editing: Layout = Settings.layout
    @State private var items: [BarItem] = LayoutItems.items(Settings.layout)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Escolha um layout, ligue itens e arraste para reordenar. As mudanças aparecem na Touch Bar na hora. O ⇄ na Touch Bar troca de layout.", "Pick a layout, turn items on and drag to reorder them. Changes show on the Touch Bar right away. ⇄ on the Touch Bar switches layouts."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(L("Layout", "Layout"), selection: $editing) {
                ForEach(Layout.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: editing) { _, layout in items = LayoutItems.items(layout) }

            preview

            List {
                ForEach(items) { item in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Text(item.title)
                        if let condition = item.condition {
                            Text(condition).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            items.removeAll { $0 == item }
                            save()
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(L("Tirar da Touch Bar", "Remove from the Touch Bar"))
                    }
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                    save()
                }
            }
            .frame(minHeight: 300)

            HStack {
                Menu(L("Adicionar item", "Add item")) {
                    ForEach(BarItem.offered.filter { !items.contains($0) }) { item in
                        Button(item.title + (item.condition.map { " (\($0))" } ?? "")) {
                            items.append(item)
                            save()
                        }
                    }
                }
                .frame(width: 180)
                Spacer()
                Button(L("Restaurar padrão", "Restore defaults")) {
                    LayoutItems.reset(editing)
                    items = LayoutItems.items(editing)
                    model.changed()
                }
                Button(L("Usar na Touch Bar", "Use on the Touch Bar")) {
                    model.layout = editing
                    model.onLayoutPicked?(editing)
                }
            }

            Divider()
            toggle(model, L("Mostrar sozinho quando o Claude estiver na frente", "Show automatically when Claude is in front"), { Settings.autoShow }, { Settings.autoShow = $0 })
            toggle(model, L("Touch Bar inteira no Claude (⤓ recolhe)", "Full Touch Bar width in Claude (⤓ shrinks it)"), { Settings.fullWidth }, { Settings.fullWidth = $0 })
            Text(L("Fora do Claude a barra fica compacta, ao lado do brilho e do volume, com os itens do layout Compacto.", "Outside Claude the bar shows compact, next to brightness and volume, with the Compact layout's items."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Rough look of the bar: the chosen items as capsules.
    private var preview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items) { item in
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.25), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(.white)
                }
            }
            .padding(6)
        }
        .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
    }

    private func save() {
        LayoutItems.set(items, for: editing)
        model.changed()
    }
}

// MARK: - Napojení

struct IntegrationSection: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Hooks do Claude Code", "Claude Code hooks")).bold()
                    Text(model.hooksInstalled
                         ? L("Ligados: status exato, ferramenta atual, plano, aprovações e cartões na Touch Bar (em sessões novas).", "On: exact states, current tool, plan, approvals and cards on the Touch Bar (in new sessions).")
                         : L("Desligados. O status é deduzido dos transcripts; aprovações e cartões não funcionam.", "Off. State is guessed from transcripts; approvals and cards don't work."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(model.hooksInstalled ? L("Desligar", "Turn off") : L("Ligar", "Turn on")) {
                    do {
                        if model.hooksInstalled { try HookInstaller.uninstall() } else { try HookInstaller.install() }
                        model.hookError = nil
                    } catch {
                        model.hookError = error.localizedDescription
                    }
                    model.reloadStatus()
                }
            }
            if let error = model.hookError { Text(error).font(.caption).foregroundStyle(.red) }

            Group {
                toggle(model, L("Aprovar pela Touch Bar quando você estiver fora do Claude", "Approve from the Touch Bar when you're outside Claude"), { Settings.approvals }, { Settings.approvals = $0 })
                toggle(model, L("Aprovar pela Touch Bar também dentro do app do Claude", "Approve from the Touch Bar inside the Claude app too"), { Settings.approvalsInClaude }, { Settings.approvalsInClaude = $0 })
                toggle(model, L("Mostrar os cartões do Claude (perguntas, próximo passo, nova sessão)", "Show Claude's cards (questions, next step, new session)"), { Settings.cards }, { Settings.cards = $0 })
                toggle(model, L("Aparecer quando o Claude terminar", "Pop up when Claude finishes"), { Settings.popOnDone }, { Settings.popOnDone = $0 })
                toggle(model, L("Som ao terminar e em aprovações", "Sound on finish and approvals"), { Settings.sound }, { Settings.sound = $0 })
            }
            .disabled(!model.hooksInstalled)

            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Acessibilidade", "Accessibility")).bold()
                    Text(model.accessibilityTrusted
                         ? L("Liberada: Parar, Novo, chats, modo, modelo e cartões funcionam.", "Allowed: Stop, New, Push, mode, model and cards work.")
                         : L("Necessária para Parar, Novo, chats, modo, modelo e cartões.", "Needed for Stop, New, Push, mode, model and cards."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.accessibilityTrusted {
                    Button(L("Permitir", "Allow")) {
                        KeySender.requestTrust()
                        model.reloadStatus()
                    }
                }
            }
        }
    }
}

// MARK: - Git a Push

struct GitSection: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("O botão ↑ mostra o estado deste repositório; um toque manda “Faça commit e push das mudanças” para o chat aberto.", "The ↑ button shows this repository's state; a tap sends “Commit and push the changes” to the open chat."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent(L("Nome na Touch Bar", "Name on the Touch Bar")) {
                TextField(L("Meu projeto", "My project"), text: Binding(
                    get: { Settings.pushName }, set: { Settings.pushName = $0; model.changed() }))
            }
            LabeledContent(L("Pasta do repositório", "Repository folder")) {
                HStack {
                    TextField(L("~/Documents/meu-projeto", "~/Documents/my-project"), text: Binding(
                        get: { Settings.pushRepo },
                        set: { Settings.pushRepo = ($0 as NSString).expandingTildeInPath; model.changed() }))
                    Button(L("Escolher…", "Choose…")) { chooseFolder() }
                }
            }
            if let git = model.snapshot.git {
                Text(L("Branch", "Branch") + " \(git.branch) · "
                     + (git.changes == 0 ? L("sem mudanças", "no changes") : "\(git.changes) " + L("sem commit", "uncommitted"))
                     + (git.ahead > 0 ? " · \(git.ahead) " + L("para enviar", "to push") : ""))
                    .foregroundStyle(.secondary)
            } else if !Settings.pushRepo.isEmpty {
                Text(L("A pasta não é um repositório git, ou ainda está carregando.", "The folder isn't a git repository, or it's still loading.")).foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            Settings.pushRepo = url.path
            if Settings.pushName.isEmpty { Settings.pushName = url.lastPathComponent }
            model.changed()
        }
    }
}

// MARK: - General

struct GeneralSection: View {
    @ObservedObject var model: DetailModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("Idioma", "Language"), selection: Binding(
                get: { Settings.language }, set: { Settings.language = $0; model.changed() })) {
                ForEach(Lang.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .frame(width: 280)
            if Settings.portuguese {
                toggle(model, "Mostrar em R$", { Settings.showBRL }, {
                    Settings.showBRL = $0
                    ExchangeRate.refreshIfNeeded()
                })
                Text("Dólar PTAX R$ \(String(format: "%.4f", ExchangeRate.usdBRL).replacingOccurrences(of: ".", with: ","))"
                     + (ExchangeRate.date.map { " (BCB, \($0))" } ?? " (padrão, PTAX ainda não baixada)")
                     + ". A cada poucas horas o app baixa a cotação pública do Banco Central (olinda.bcb.gov.br), sem enviar nada sobre você. Desligue para parar o download.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            toggle(model, L("Abrir ao iniciar sessão", "Start at login"), { model.launchAtLogin }, {
                LaunchAtLogin.setEnabled($0)
                model.launchAtLogin = LaunchAtLogin.isEnabled
            })
            Text(L("Abra esta janela de novo pelo Launchpad ou tocando num número na Touch Bar. Fechar a janela mantém o app rodando em segundo plano.", "Open this window again anytime from Launchpad or by tapping a number on the Touch Bar. Closing it keeps the app running in the background."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Tokens e custos são lidos dos transcripts da aba Code (~/.claude/projects). O Chat não guarda tokens localmente.", "Tokens and costs are read from the Code tab's transcripts (~/.claude/projects). Chat doesn't store tokens locally."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(L("Abrir o Claude", "Open Claude")) { ClaudeApp.activate() }
                Spacer()
                Button(L("Sair do Claude Touch Bar", "Quit Claude Touch Bar")) { NSApp.terminate(nil) }
            }
        }
    }
}

// MARK: - Controller

/// The app's window. While it's open the app shows in the Dock like any
/// other; closing it sends the app back to the background.
final class DetailWindowController: NSObject, NSWindowDelegate {
    let model = DetailModel()
    private var window: NSWindow?

    func show(section: DetailModel.Section? = nil) {
        if let section { model.section = section }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Claude Touch Bar"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.setFrameAutosaveName("ClaudeTouchBarWindow")
            if !window.setFrameUsingName("ClaudeTouchBarWindow") { window.center() }
            self.window = window
        }
        model.reloadStatus()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
