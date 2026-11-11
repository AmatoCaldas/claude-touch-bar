import Foundation

/// Everything that can sit on the Touch Bar. The raw value is also the item's
/// Touch Bar identifier suffix, so it must stay stable.
enum BarItem: String, CaseIterable, Identifiable {
    case state, plan, context, session, fiveHours, today, week, month, allTime
    case tokens, cost, rate, active, graph, model, files, waiting, compact
    case push, modelPicker, wide, switcher, more, collapse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .state: return L("Status e tempo", "State and time")
        case .plan: return L("Progresso do plano", "Plan progress")
        case .context: return L("Contexto", "Context")
        case .session: return L("Gasto da sessão", "Session spend")
        case .fiveHours: return L("Gasto 5 h", "5 h spend")
        case .today: return L("Gasto hoje", "Today's spend")
        case .week: return L("Gasto na semana", "Week's spend")
        case .month: return L("Gasto no mês", "Month's spend")
        case .allTime: return L("Gasto total (desde o início)", "All-time spend")
        case .tokens: return L("Tokens ▲▼", "Tokens ▲▼")
        case .cost: return L("Custo da sessão", "Session cost")
        case .rate: return L("Ritmo $/h", "Rate $/h")
        case .active: return L("Tempo ativo hoje", "Active time today")
        case .graph: return L("Gráfico da última hora", "Last hour graph")
        case .model: return L("Nome do modelo", "Model name")
        case .files: return L("Arquivos alterados", "Changed files")
        case .waiting: return L("Sessões esperando", "Waiting sessions")
        case .compact: return L("Compactar contexto", "Compact context")
        case .push: return L("Commit e push", "Commit and push")
        case .modelPicker: return L("Seletor de modelo", "Model picker")
        case .wide: return L("Contexto grande (Mínimo)", "Large context (Minimal)")
        case .switcher: return L("Trocar layout ⇄", "Switch layout ⇄")
        case .more: return L("Ações ⋯", "Actions ⋯")
        case .collapse: return L("Recolher ⤓", "Shrink ⤓")
        }
    }

    /// When the item only shows up while it has something to say.
    var condition: String? {
        switch self {
        case .plan: return L("só quando o Claude tem um plano", "only when Claude has a plan")
        case .push: return L("só com um repositório para o Push", "only with a Push repository")
        case .compact: return L("só acima de 80% do contexto", "only above 80% context")
        case .waiting: return L("só quando algo espera", "only when something waits")
        case .files: return L("só quando o Claude alterou algo", "only when Claude changed something")
        case .collapse: return L("só na largura total", "only at full width")
        default: return nil
        }
    }
}

enum LayoutItems {
    static func defaults(_ layout: Layout) -> [BarItem] {
        switch layout {
        case .compact:
            return [.state, .plan, .context, .session, .today, .waiting, .compact, .graph, .model, .push,
                    .switcher, .more, .collapse]
        case .overview:
            return [.context, .plan, .session, .fiveHours, .today, .week, .allTime, .waiting, .push, .switcher, .more,
                    .collapse]
        case .minimal:
            return [.graph, .plan, .wide, .push, .switcher, .more, .collapse]
        }
    }

    private static func key(_ layout: Layout) -> String { "items.\(layout.rawValue)" }

    static func items(_ layout: Layout) -> [BarItem] {
        guard let saved = UserDefaults.standard.stringArray(forKey: key(layout)) else { return defaults(layout) }
        return saved.compactMap(BarItem.init(rawValue:))
    }

    static func set(_ items: [BarItem], for layout: Layout) {
        UserDefaults.standard.set(items.map(\.rawValue), forKey: key(layout))
    }

    static func reset(_ layout: Layout) {
        UserDefaults.standard.removeObject(forKey: key(layout))
    }
}
