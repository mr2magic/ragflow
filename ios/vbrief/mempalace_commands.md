# MemPalace Commands

| Command | What it does |
|---|---|
| `mempalace init <dir>` | Detect rooms from folder structure |
| `mempalace mine <dir>` | Index project files (code, docs, notes) into the palace |
| `mempalace mine <dir> --mode convos` | Index conversation exports (Claude, ChatGPT, Slack) |
| `mempalace split <dir>` | Split concatenated transcript mega-files into per-session files (run before mine) |
| `mempalace search "query"` | Semantic search across all indexed content |
| `mempalace search "query" --wing w --room r` | Search filtered to a specific wing/room |
| `mempalace compress` | Compress drawers using AAAK dialect (~30x token reduction) |
| `mempalace wake-up` | Show L0 + L1 wake-up context (~600–900 tokens) |
| `mempalace wake-up --wing <name>` | Wake-up context for a specific project |
| `mempalace status` | Show what's been filed (drawer counts by room) |
| `mempalace mcp` | Show MCP setup command to connect palace to your AI client |
| `mempalace repair` | Rebuild vector index from stored data (fixes corruption/segfaults) |
| `mempalace hook` | Run hook logic (reads JSON from stdin, outputs JSON to stdout) |
| `mempalace instructions` | Output skill instructions to stdout |
| `mempalace migrate` | Migrate palace after ChromaDB version upgrade |
