# RAGFlow Web Frontend

The web frontend is a React/TypeScript single-page application built with UmiJS, Ant Design, and shadcn/ui.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | UmiJS (React 18) |
| Language | TypeScript |
| UI Components | Ant Design + shadcn/ui |
| Styling | Tailwind CSS |
| State Management | Zustand |
| Data Fetching | React Query (TanStack Query) |
| Build Tool | Webpack (via UmiJS) |
| Testing | Jest + React Testing Library |

---

## Project Structure

```
web/src/
├── pages/
│   ├── next-chats/                    # Chat interface
│   │   ├── index.tsx                  # Chat list (dialogs)
│   │   ├── chat/
│   │   │   └── sessions.tsx           # Conversation list within a chat
│   │   ├── hooks/
│   │   │   ├── use-send-chat-message.ts
│   │   │   └── use-rename-chat.ts
│   │   └── chat-dropdown.tsx          # Rename/delete chat menu
│   │
│   ├── user-setting/                  # Settings pages
│   │   ├── sidebar/index.tsx          # Settings navigation sidebar
│   │   ├── setting-model/             # LLM provider configuration
│   │   │   ├── index.tsx              # Model providers overview
│   │   │   ├── components/
│   │   │   │   ├── modal-card.tsx     # Provider card (enabled models)
│   │   │   │   ├── un-add-model.tsx   # Available providers to add
│   │   │   │   └── system-setting.tsx # Default model selectors
│   │   │   ├── modal/
│   │   │   │   └── api-key-modal/     # Generic API key entry modal
│   │   │   └── hooks.tsx              # useSubmitApiKey, useSubmitSystemModelSetting
│   │   ├── setting-profile/           # User profile
│   │   └── setting-team/             # Team management
│   │
│   ├── knowledge-base/                # KB management
│   ├── agent/                         # Agent workflow canvas
│   └── document/                      # Document processing
│
├── hooks/
│   ├── use-chat-request.ts            # Chat CRUD hooks (React Query)
│   └── use-llm-request.tsx            # LLM provider hooks
│
├── services/
│   └── next-chat-service.ts           # Chat API method definitions
│
├── interfaces/
│   └── database/
│       └── chat.ts                    # IDialog, IConversation, IMessage types
│
└── constants/
    └── llm.ts                         # LLMFactory enum, IconMap, APIMapUrl
```

---

## Chat System

### Concepts

- **Dialog** (`IDialog`) — A chat configuration: which KB(s) to search, which LLM to use, prompt settings, similarity thresholds. Like a chatbot definition.
- **Conversation** (`IConversation`) — An individual chat session within a dialog. Contains the message history.
- **Message** (`IMessage`) — A single user or assistant message.

### Chat CRUD Operations

All operations use React Query hooks defined in `hooks/use-chat-request.ts`:

| Operation | Hook | API Endpoint |
|-----------|------|-------------|
| List dialogs | `useFetchDialogList()` | `POST /dialog/next` (paginated) |
| Create dialog | `useSetDialog()` | `POST /dialog/set` |
| Update dialog | `useSetDialog()` | `POST /dialog/set` (with `dialog_id`) |
| Delete dialog | `useRemoveDialog()` | `POST /dialog/rm` |
| List conversations | `useFetchConversationList()` | `GET /conversation/list` |
| Create conversation | `addTemporaryConversation()` | client-side + `POST /conversation/set` |
| Rename conversation | `useUpdateConversation()` | `POST /conversation/set` |
| Delete conversation | `useRemoveConversation()` | `POST /conversation/rm` |
| Send message | `useSendMessage()` | `POST /conversation/completion` (SSE) |

### Message Streaming

Chat responses use **Server-Sent Events (SSE)** via `useSendMessageWithSse()`. The stream is consumed token-by-token and appended to the assistant message in real-time.

---

## LLM Provider Configuration

### Settings Page

Navigate to **Settings → Model** (`/setting/model`) to configure LLM providers.

The page has two sections:
- **Left (3/5)**: System default models + configured providers
- **Right (2/5)**: Available providers to add

### Adding a Provider

1. Find the provider in the right panel (searchable, filterable by capability tag)
2. Click "Add" — opens the API key modal
3. Enter your API key (and optional base URL for providers like Anthropic)
4. Click "Verify" to test the key, then "Save"

### Supported Providers

Defined in `constants/llm.ts` (`LLMFactory` enum) and `conf/llm_factories.json`:

| Provider | Factory Name | Requires |
|----------|-------------|---------|
| Anthropic (Claude) | `Anthropic` | API key, optional base URL |
| OpenAI (ChatGPT) | `OpenAI` | API key |
| Azure OpenAI | `Azure-OpenAI` | Endpoint, API key, deployment |
| Google Gemini | `Gemini` | API key |
| DeepSeek | `DeepSeek` | API key |
| Ollama | `Ollama` | Host URL |
| AWS Bedrock | `Bedrock` | AWS credentials |
| ...30+ more | | |

### API Key Storage

API keys are stored encrypted in the database (`TenantLLM.api_key`) and never exposed to the frontend after saving.

### Default Models

Set system-wide defaults for each model type under **Settings → Model → System**:

- **LLM** — Default chat model for all dialogs
- **Embedding** — Model used to vectorize documents
- **Image to Text** — For image understanding
- **ASR** — Speech-to-text transcription

---

## Routing

Routes are defined in `config/routes.ts` (UmiJS). Key routes:

| Path | Page | Description |
|------|------|-------------|
| `/` | Home | Dashboard |
| `/chat` | next-chats | Chat interface |
| `/knowledge-base` | knowledge-base | KB management |
| `/agent` | agent | Workflow canvas |
| `/setting/model` | user-setting/setting-model | LLM configuration |
| `/setting/profile` | user-setting/setting-profile | User profile |
| `/setting/team` | user-setting/setting-team | Team management |

---

## Development

```bash
cd web
npm install
npm run dev       # Start dev server (hot reload)
npm run build     # Production build
npm run lint      # ESLint
npm run test      # Jest unit tests
```

### Environment Variables

Set in `web/.umirc.ts` or via `.env` files:
- `API_URL` — Backend API base URL (proxied in dev)
