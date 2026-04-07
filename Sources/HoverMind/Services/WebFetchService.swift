import Foundation

/// Available web search backends.
enum WebSearchProvider: String, CaseIterable, Codable {
    case duckduckgo = "DuckDuckGo"
    case brave = "Brave Search"
    case google = "Google"
}

/// Fetches web pages and extracts text content for AI context.
final class WebFetchService {

    var provider: WebSearchProvider = .duckduckgo
    var braveApiKey: String?
    var googleApiKey: String?
    var googleSearchEngineId: String?

    func search(query: String) async -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch provider {
        case .duckduckgo:
            return await fetchText(from: "https://html.duckduckgo.com/html/?q=\(encoded)", maxLength: 3000)
        case .brave:
            return await braveSearch(query: encoded)
        case .google:
            return await googleSearch(query: encoded)
        }
    }

    func fetchPage(url: String) async -> String {
        return await fetchText(from: url, maxLength: 4000)
    }

    // MARK: - Brave Search API

    private func braveSearch(query: String) async -> String {
        guard let key = braveApiKey, !key.isEmpty else {
            return "Brave Search API key not configured"
        }
        guard let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(query)&count=3") else {
            return "Invalid query"
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let web = json["web"] as? [String: Any],
                  let results = web["results"] as? [[String: Any]]
            else { return "No results" }
            return results.prefix(3).compactMap { r in
                let title = r["title"] as? String ?? ""
                let desc = r["description"] as? String ?? ""
                return "\(title): \(desc)"
            }.joined(separator: "\n\n")
        } catch {
            return "Brave search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Google Custom Search API

    private func googleSearch(query: String) async -> String {
        guard let key = googleApiKey, !key.isEmpty,
              let cx = googleSearchEngineId, !cx.isEmpty else {
            return "Google API key or Search Engine ID not configured"
        }
        guard let url = URL(string: "https://www.googleapis.com/customsearch/v1?key=\(key)&cx=\(cx)&q=\(query)&num=3") else {
            return "Invalid query"
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]]
            else { return "No results" }
            return items.prefix(3).compactMap { item in
                let title = item["title"] as? String ?? ""
                let snippet = item["snippet"] as? String ?? ""
                return "\(title): \(snippet)"
            }.joined(separator: "\n\n")
        } catch {
            return "Google search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Shared

    private func fetchText(from urlString: String, maxLength: Int) async -> String {
        guard let url = URL(string: urlString) else { return "Invalid URL" }
        do {
            var request = URLRequest(url: url, timeoutInterval: 3)
            request.setValue("HoverMind/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return "Could not decode response" }
            let text = Self.stripHTML(html)
            return text.count > maxLength ? String(text.prefix(maxLength)) : text
        } catch {
            return "Fetch failed: \(error.localizedDescription)"
        }
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#[0-9]+;", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
