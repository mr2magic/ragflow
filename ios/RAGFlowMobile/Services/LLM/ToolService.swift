import Foundation

// MARK: - Tool Definitions (for LLM tool-use / chat mode)

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

// MARK: - Search Tool Protocol

/// A pluggable web-search tool used by the Web Search workflow step.
protocol SearchTool {
    var toolId: String { get }
    var displayName: String { get }
    var requiresApiKey: Bool { get }
    func search(query: String, apiKey: String) async -> String
}

// MARK: - Search Tool Registry

final class SearchToolRegistry {
    static let shared = SearchToolRegistry()

    private var tools: [String: any SearchTool] = [:]

    private init() {
        register(BraveSearchTool())
        register(DuckDuckGoTool())
        register(WikipediaTool())
    }

    func register(_ tool: some SearchTool) { tools[tool.toolId] = tool }
    func tool(id: String) -> (any SearchTool)? { tools[id] }

    /// All registered tools, sorted alphabetically by display name.
    var all: [any SearchTool] { tools.values.sorted { $0.displayName < $1.displayName } }
}

// MARK: - Brave Search

struct BraveSearchTool: SearchTool {
    let toolId = "brave_search"
    let displayName = "Brave Search"
    let requiresApiKey = true

    func search(query: String, apiKey: String) async -> String {
        guard !apiKey.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=3") else {
            return "Brave Search not configured — add an API key in Settings → Agent Tools."
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
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
}

// MARK: - DuckDuckGo Search (free, no API key)

struct DuckDuckGoTool: SearchTool {
    let toolId = "duckduckgo"
    let displayName = "DuckDuckGo"
    let requiresApiKey = false

    func search(query: String, apiKey: String) async -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1")
        else { return "Invalid query." }

        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("RAGFlowMobile/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "No results." }

        var results: [String] = []
        if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
            results.append(abstract)
        }
        if let topics = json["RelatedTopics"] as? [[String: Any]] {
            results += topics.prefix(3).compactMap { $0["Text"] as? String }
        }
        return results.isEmpty ? "No results found." : results.joined(separator: "\n\n")
    }
}

// MARK: - Wikipedia Search (free, no API key)

struct WikipediaTool: SearchTool {
    let toolId = "wikipedia"
    let displayName = "Wikipedia"
    let requiresApiKey = false

    func search(query: String, apiKey: String) async -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&srlimit=3")
        else { return "Invalid query." }

        guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryResult = json["query"] as? [String: Any],
              let items = queryResult["search"] as? [[String: Any]]
        else { return "No results." }

        return items.prefix(3).compactMap { item -> String? in
            guard let title = item["title"] as? String,
                  let snippet = item["snippet"] as? String else { return nil }
            let clean = snippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return "**\(title)**: \(clean)"
        }.joined(separator: "\n\n")
    }
}

// MARK: - Tool Executor (legacy — used by chat LLM tool-use)

struct ToolExecutor {
    var braveApiKey: String = ""

    func execute(name: String, input: [String: Any]) async -> String {
        switch name {
        case "brave_search":
            guard let query = input["query"] as? String else { return "Missing query" }
            return await BraveSearchTool().search(query: query, apiKey: braveApiKey)
        case "jina_reader":
            guard let urlString = input["url"] as? String,
                  let url = URL(string: "https://r.jina.ai/\(urlString)") else { return "Invalid URL" }
            return await jinaFetch(url: url)
        default:
            return "Unknown tool: \(name)"
        }
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
