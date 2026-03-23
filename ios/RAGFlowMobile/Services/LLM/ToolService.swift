import Foundation

// MARK: - Tool Definitions

struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    var asDict: [String: Any] {
        ["name": name, "description": description, "input_schema": inputSchema]
    }
}

enum AgentTools {
    static let braveSearch = ToolDefinition(
        name: "brave_search",
        description: "Search the web using Brave Search. Use for current events, facts, or topics not in the book.",
        inputSchema: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Search query"]
            ],
            "required": ["query"]
        ]
    )

    static let jinaReader = ToolDefinition(
        name: "jina_reader",
        description: "Extract clean text content from a web URL.",
        inputSchema: [
            "type": "object",
            "properties": [
                "url": ["type": "string", "description": "URL to read"]
            ],
            "required": ["url"]
        ]
    )

    static let all: [ToolDefinition] = [braveSearch, jinaReader]
}

// MARK: - Tool Executor

struct ToolExecutor {
    var braveApiKey: String = ""

    func execute(name: String, input: [String: Any]) async -> String {
        switch name {
        case "brave_search":
            guard let query = input["query"] as? String else { return "Missing query" }
            return await braveSearch(query: query)
        case "jina_reader":
            guard let urlString = input["url"] as? String,
                  let url = URL(string: "https://r.jina.ai/\(urlString)") else { return "Invalid URL" }
            return await jinaFetch(url: url)
        default:
            return "Unknown tool: \(name)"
        }
    }

    private func braveSearch(query: String) async -> String {
        guard !braveApiKey.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=3") else {
            return "Brave Search not configured (no API key)."
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(braveApiKey, forHTTPHeaderField: "X-Subscription-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["web"] as? [String: Any],
              let items = results["results"] as? [[String: Any]] else {
            return "No results found."
        }
        return items.prefix(3).compactMap { item -> String? in
            guard let title = item["title"] as? String,
                  let desc = item["description"] as? String else { return nil }
            return "**\(title)**: \(desc)"
        }.joined(separator: "\n\n")
    }

    private func jinaFetch(url: URL) async -> String {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("text/plain", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let text = String(data: data, encoding: .utf8) else {
            return "Could not fetch URL."
        }
        return String(text.prefix(2000))
    }
}
