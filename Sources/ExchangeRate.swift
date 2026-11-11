import Foundation

/// The USD/BRL rate for showing costs in R$. Downloaded once in a while from
/// the Banco Central do Brasil's public PTAX series (no user data is sent) and
/// only while the UI is Portuguese and "Show R$" is on.
enum ExchangeRate {
    private static let defaults = UserDefaults.standard
    /// Used until the first successful download.
    static let fallback = 5.5
    /// PTAX closes once per business day; checking every few hours is plenty.
    private static let interval: TimeInterval = 6 * 3600
    /// Days to look back, so weekends and holidays still find the last close.
    private static let lookbackDays = 10
    private static var inFlight = false

    /// BRL for one USD (PTAX selling rate).
    static var usdBRL: Double {
        let saved = defaults.double(forKey: "usdBRL")
        return saved > 0 ? saved : fallback
    }

    /// The PTAX date of the saved rate ("11/11/2026"); nil while on the fallback.
    static var date: String? { defaults.string(forKey: "usdBRLDate") }

    /// Downloads a fresh rate when R$ is shown and the last try is old enough.
    /// `wait` blocks until done (for `--dump`, which exits right after).
    static func refreshIfNeeded(wait: Bool = false) {
        guard Settings.showsBRL, !inFlight, let url = requestURL(now: Date()) else { return }
        let lastTry = defaults.object(forKey: "usdBRLTried") as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastTry) > interval else { return }
        inFlight = true
        defaults.set(Date(), forKey: "usdBRLTried")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            // On failure the saved (or fallback) rate stays.
            if let data, let parsed = parse(data) {
                defaults.set(parsed.rate, forKey: "usdBRL")
                defaults.set(parsed.date, forKey: "usdBRLDate")
            } else {
                NSLog("ClaudeTouchBar: PTAX download failed: \(error?.localizedDescription ?? "unexpected response")")
            }
            inFlight = false
            done.signal()
        }.resume()
        if wait { done.wait() }
    }

    /// The BCB OData query for the last `lookbackDays` days of PTAX.
    static func requestURL(now: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd-yyyy"
        guard let start = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) else { return nil }
        var components = URLComponents(string: "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/"
            + "CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)")
        components?.queryItems = [
            URLQueryItem(name: "@dataInicial", value: "'\(formatter.string(from: start))'"),
            URLQueryItem(name: "@dataFinalCotacao", value: "'\(formatter.string(from: now))'"),
            URLQueryItem(name: "$format", value: "json"),
            URLQueryItem(name: "$select", value: "cotacaoVenda,dataHoraCotacao"),
        ]
        return components?.url
    }

    /// `{"value":[{"cotacaoVenda":5.5606,"dataHoraCotacao":"2026-11-11 13:02:30.354"}, …]}`:
    /// the newest close and its date as "11/11/2026".
    static func parse(_ data: Data) -> (rate: Double, date: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["value"] as? [[String: Any]],
              let last = rows.last,
              let rate = (last["cotacaoVenda"] as? NSNumber)?.doubleValue, rate > 0,
              let stamp = last["dataHoraCotacao"] as? String
        else { return nil }
        let day = stamp.prefix(10).split(separator: "-")
        guard day.count == 3 else { return (rate, String(stamp.prefix(10))) }
        return (rate, "\(day[2])/\(day[1])/\(day[0])")
    }
}
