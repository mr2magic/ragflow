# RAGFlow Backend API Reference

All endpoints are prefixed with the configured base URL (default: `http://localhost:9380`).

Authentication uses Bearer tokens: `Authorization: Bearer <token>`

---

## Dialog (Chat Configuration) API

A **Dialog** is a chatbot configuration: which knowledge bases to search, which LLM to use, and how to prompt it.

### List Dialogs

```http
POST /v1/dialog/next
Content-Type: application/json

{
  "keywords": "",     // optional search filter
  "page": 1,
  "page_size": 30
}
```

### Create / Update Dialog

```http
POST /v1/dialog/set
Content-Type: application/json

{
  "dialog_id": "",              // empty = create, filled = update
  "name": "My Chatbot",
  "description": "...",
  "kb_ids": ["kb-id-1"],
  "llm_id": "gpt-4o@OpenAI",
  "llm_setting": {
    "temperature": 0.1,
    "top_p": 0.3,
    "max_tokens": 512
  },
  "prompt_config": {
    "system": "You are a helpful assistant.",
    "prologue": "Hi! How can I help?",
    "empty_response": "I don't know."
  },
  "top_n": 6,
  "similarity_threshold": 0.2,
  "vector_similarity_weight": 0.3
}
```

### Get Dialog

```http
GET /v1/dialog/get?dialog_id=<id>
```

### Delete Dialog

```http
POST /v1/dialog/rm
Content-Type: application/json

{ "dialog_ids": ["id1", "id2"] }
```

---

## Conversation API

A **Conversation** is an individual chat session within a Dialog.

### List Conversations

```http
GET /v1/conversation/list?dialog_id=<dialog_id>
```

### Get Conversation (with messages)

```http
GET /v1/conversation/get?conversation_id=<id>
```

### Create / Update Conversation

```http
POST /v1/conversation/set
Content-Type: application/json

{
  "conversation_id": "",   // empty = create
  "dialog_id": "...",
  "name": "Chat 1"
}
```

### Delete Conversations

```http
POST /v1/conversation/rm
Content-Type: application/json

{ "conversation_ids": ["id1"] }
```

### Send Message (Streaming)

Returns an **SSE stream** of tokens.

```http
POST /v1/conversation/completion
Content-Type: application/json

{
  "conversation_id": "...",
  "messages": [
    { "role": "user", "content": "What is RAGFlow?" }
  ]
}
```

**SSE Response format:**
```
data: {"answer": "RAG", "reference": {}, "running_status": true}
data: {"answer": "RAGFlow is", "reference": {}, "running_status": true}
data: {"answer": "RAGFlow is a ...", "reference": {...}, "running_status": false}
```

---

## Knowledge Base API

### List Knowledge Bases

```http
GET /v1/kb/list
```

### Create Knowledge Base

```http
POST /v1/kb/create
Content-Type: application/json

{
  "name": "My KB",
  "description": "...",
  "embedding_model": "text-embedding-ada-002@OpenAI",
  "permission": "me"
}
```

### Delete Knowledge Base

```http
POST /v1/kb/rm
Content-Type: application/json

{ "kb_id": "..." }
```

---

## Document API

### Upload Document

```http
POST /v1/document/upload
Content-Type: multipart/form-data

kb_id=<kb_id>
file=<binary>
```

### List Documents

```http
GET /v1/document/list?kb_id=<kb_id>&page=1&page_size=30
```

### Delete Document

```http
POST /v1/document/rm
Content-Type: application/json

{ "doc_ids": ["id1"] }
```

### Run Chunking

```http
POST /v1/document/run
Content-Type: application/json

{ "doc_ids": ["id1"], "run": 1 }
```

---

## LLM Provider API

### Set API Key

Validates and stores an API key for a provider:

```http
POST /v1/llm/set_api_key
Content-Type: application/json

{
  "llm_factory": "Anthropic",
  "api_key": "sk-ant-...",
  "base_url": "https://api.anthropic.com/v1"  // optional
}
```

### List Available Models

```http
GET /v1/llm/list?model_type=chat
```

### List My Configured Models

```http
GET /v1/llm/my_llms
```

### Add Custom Model

```http
POST /v1/llm/add_llm
Content-Type: application/json

{
  "llm_factory": "Ollama",
  "llm_name": "llama3.2",
  "model_type": "chat",
  "max_tokens": 8192,
  "api_base": "http://localhost:11434"
}
```

---

## Error Responses

All errors return:

```json
{
  "retcode": 101,
  "retmsg": "Description of the error",
  "data": false
}
```

Common error codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 100 | Authentication failed |
| 101 | Invalid parameter |
| 102 | Permission denied |
| 109 | Not found |

---

## SDK

A Python SDK is available in `sdk/python/`:

```python
from ragflow_sdk import RAGFlow

client = RAGFlow(api_key="your-key", base_url="http://localhost:9380")

# Create a knowledge base
kb = client.create_dataset(name="My KB")

# Upload a document
kb.upload_documents([{"name": "doc.pdf", "blob": open("doc.pdf", "rb").read()}])

# Create a chat
chat = client.create_chat("My Bot", knowledgebases=[kb])

# Start a conversation
session = chat.create_session()
for chunk in session.ask("What is RAGFlow?"):
    print(chunk.content, end="")
```

Full SDK documentation: `sdk/python/README.md`
