import AppKit

let arguments = CommandLine.arguments

// Run by Claude Code for every hook event; must stay quick and never fail.
if arguments.contains("--hook") { HookClient.run() }

if arguments.contains("--ax-dump") {
    let index = arguments.firstIndex(of: "--ax-dump")!
    ClaudeUI.dump(matching: index + 1 < arguments.count ? arguments[index + 1] : nil)
    exit(0)
}

if arguments.contains("--ax-modes") {
    let text = "current=\(ClaudeUI.currentMode() ?? "-")\noptions=\(ClaudeUI.availableModes())\n"
    try? text.write(to: HookPaths.directory.appendingPathComponent("ax-modes.txt"), atomically: true, encoding: .utf8)
    exit(0)
}

if arguments.contains("--ax-cancel") {
    ClaudeUI.cancelMenus()
    exit(0)
}

if let index = arguments.firstIndex(of: "--ax-menu"), index + 1 < arguments.count {
    let prefix = arguments[index + 1]
    var text = "popup=\(ClaudeUI.popUp(prefix)?.label ?? "-")\nitems=\(ClaudeUI.menuItems(of: prefix))\n"
    if index + 2 < arguments.count {
        Thread.sleep(forTimeInterval: 0.5)
        text += "submenu=\(ClaudeUI.submenuItems(of: prefix, submenu: arguments[index + 2]))\n"
    }
    try? text.write(to: HookPaths.directory.appendingPathComponent("ax-menu.txt"), atomically: true, encoding: .utf8)
    exit(0)
}

if let index = arguments.firstIndex(of: "--answer"), index + 1 < arguments.count {
    HookClient.answer(arguments[index + 1])
}

if arguments.contains("--install-hooks") || arguments.contains("--uninstall-hooks") {
    do {
        if arguments.contains("--install-hooks") {
            try HookInstaller.install()
            print(L("Hooks ligados no ~/.claude/settings.json (backup: settings.json.bak-claudetouchbar).",
                    "Hooks on in ~/.claude/settings.json (backup: settings.json.bak-claudetouchbar)."))
        } else {
            try HookInstaller.uninstall()
            print(L("Hooks removidos do ~/.claude/settings.json.", "Hooks removed from ~/.claude/settings.json."))
        }
        exit(0)
    } catch {
        print(L("Erro: ", "Error: ") + "\(error.localizedDescription)")
        exit(1)
    }
}

// `--dump` prints what the Touch Bar would show and exits; handy for checking
// the numbers without a Touch Bar.
if arguments.contains("--dump") {
    let s = UsageStore().scanNow()
    ExchangeRate.refreshIfNeeded(wait: true)
    func line(_ label: String, _ t: Tokens) {
        print("\(label): " + L("entrada", "input") + " \(Format.tokens(t.input)), "
            + L("leitura de cache", "cache read") + " \(Format.tokens(t.cacheRead)), "
            + L("escrita de cache", "cache write") + " \(Format.tokens(t.cacheWrite)), "
            + L("saída", "output") + " \(Format.tokens(t.output)), "
            + L("total", "total") + " \(Format.tokens(t.total)), \(Format.price(t.cost))")
    }
    print("Touch Bar API: \(SystemTouchBar.isSupported ? L("disponível", "available") : L("indisponível", "unavailable"))")
    print(L("Sessão", "Session") + ": \(s.title ?? "-") · \(s.project ?? "-") · \(s.modelName) · \(s.activity)")
    print(L("Contexto", "Context") + ": \(Format.tokens(s.contextUsed)) / \(Format.tokens(s.contextWindow)) (\(Format.percent(s.contextFraction)))")
    line(L("Sessão", "Session"), s.session)
    line("5 h", s.fiveHours)
    line(L("Hoje", "Today"), s.today)
    line(L("Semana", "Week"), s.week)
    line(L("Mês", "Month"), s.month)
    line(L("Total", "All time") + (s.allTimeSince.map { " (" + L("desde", "since") + " " + Format.day($0) + ")" } ?? ""), s.allTime)
    print(L("Sessões nas últimas 3 h", "Sessions in the last 3 h") + ": \(s.sessions.map { "\($0.title) (\($0.activity))" }.joined(separator: ", "))")
    print(L("Últimos 60 min em passos de 5 min", "Last 60 min in 5 min steps") + ": \(s.burn.map { Format.cost($0) }.joined(separator: " "))")
    if Settings.showsBRL {
        print("Dólar PTAX: R$ " + String(format: "%.4f", ExchangeRate.usdBRL).replacingOccurrences(of: ".", with: ",") + (ExchangeRate.date.map { " (BCB \($0))" } ?? " (padrão)"))
    }
    print(L("Hooks", "Hooks") + ": " + (HookInstaller.isInstalled ? L("ligados", "on") : L("desligado", "off")))
    if let cwd = s.cwd {
        if let git = Git.status(at: cwd) {
            print("Git (\(cwd)): " + L("branch", "branch") + " \(git.branch), " + L("mudanças", "changes") + " \(git.changes), "
                + L("para enviar", "to push") + " \(git.ahead)")
        } else {
            print("Git (\(cwd)): " + L("não é repositório", "not a repository"))
        }
    }
    if let runway = s.budgetRunway(50) { print(L("Um orçamento de $50 dura", "A $50 budget lasts") + ": \(Format.runway(runway))") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
