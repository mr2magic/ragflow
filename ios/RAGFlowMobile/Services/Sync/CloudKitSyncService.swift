import CloudKit
import Foundation

/// Syncs Knowledge Base metadata and chat history to iCloud via CloudKit.
///
/// ## What is synced
/// - `KnowledgeBase` records: id, name, settings (topK, topN, threshold, chunk config)
/// - `Book` records: id, kbId, title, author, fileType, wordCount, pageCount, chunkCount
/// - `ChatSession` records: id, kbId, name, createdAt
/// - `Message` records: id, sessionId, kbId, role, content, timestamp
/// - `Workflow` records: id, name, templateId, kbId, stepsJSON, createdAt
///
/// ## What is NOT synced
/// - API keys (stored in Keychain, never leave the device)
/// - Chunk embeddings (too large; rebuilt by re-indexing on each device)
/// - File paths (device-specific)
/// - Actual document files (user imports documents on each device)
///
/// ## Conflict resolution
/// - KBs, books, and sessions: last-write-wins (CloudKit `changedKeys` save policy)
/// - Messages: append-only; remote messages not present locally are inserted
///
/// ## Container
/// Uses `iCloud.com.dhorn.ragflowmobile` (private database only).
@MainActor
final class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date? = nil
    @Published var syncError: String? = nil
    @Published var isAvailable = false

    private let db = DatabaseService.shared

    /// Container is created on first use so the initializer never crashes in
    /// environments where the CloudKit entitlement is not validated at launch
    /// (e.g. simulator builds, unit tests, unsigned Debug builds).
    private var _container: CKContainer?
    private var container: CKContainer {
        if let c = _container { return c }
        let c = CKContainer(identifier: "iCloud.com.dhorn.ragflowmobile")
        _container = c
        return c
    }
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    private init() {
        // Restore last sync date from UserDefaults across sessions.
        lastSyncDate = UserDefaults.standard.object(forKey: "ck_last_sync_date") as? Date
    }

    // MARK: - Availability

    func checkAvailability() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = (status == .available)
        } catch {
            isAvailable = false
        }
    }

    // MARK: - Full Sync

    func sync() async {
        guard AuthService.shared.isAuthenticated else {
            syncError = "Sign in to enable sync."
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil

        do {
            try await pushKnowledgeBases()
            try await pullKnowledgeBases()
            try await pushBooks()
            try await pullBooks()
            try await pushSessions()
            try await pullSessions()
            try await pushMessages()
            try await pullMessages()
            try await pushWorkflows()
            try await pullWorkflows()

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: "ck_last_sync_date")
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Knowledge Bases

    private func pushKnowledgeBases() async throws {
        let kbs = (try? db.allKBs()) ?? []
        guard !kbs.isEmpty else { return }

        let records: [CKRecord] = kbs.map { kb in
            let record = CKRecord(recordType: "KnowledgeBase",
                                  recordID: CKRecord.ID(recordName: "KB-\(kb.id)"))
            record["id"]                  = kb.id
            record["name"]                = kb.name
            record["createdAt"]           = kb.createdAt
            record["topK"]                = kb.topK
            record["topN"]                = kb.topN
            record["similarityThreshold"] = kb.similarityThreshold
            record["chunkMethod"]         = kb.chunkMethod.rawValue
            record["chunkSize"]           = kb.chunkSize
            record["chunkOverlap"]        = kb.chunkOverlap
            return record
        }
        try await saveRecords(records)
    }

    private func pullKnowledgeBases() async throws {
        let results = try await fetchAll(recordType: "KnowledgeBase")
        for record in results {
            guard let id      = record["id"]        as? String,
                  let name    = record["name"]      as? String,
                  let created = record["createdAt"] as? Date else { continue }

            // Skip the default KB — it is seeded locally on first launch.
            if id == KnowledgeBase.defaultID { continue }

            if var existing = try? db.kb(id: id) {
                // Update settings (last-write-wins).
                existing.name = name
                existing.topK               = record["topK"]               as? Int    ?? existing.topK
                existing.topN               = record["topN"]               as? Int    ?? existing.topN
                existing.similarityThreshold = record["similarityThreshold"] as? Double ?? existing.similarityThreshold
                if let m = record["chunkMethod"] as? String { existing.chunkMethod = ChunkMethod(rawValue: m) ?? existing.chunkMethod }
                existing.chunkSize          = record["chunkSize"]          as? Int    ?? existing.chunkSize
                existing.chunkOverlap       = record["chunkOverlap"]       as? Int    ?? existing.chunkOverlap
                try? db.saveKB(existing)
            } else {
                // Insert new KB from cloud.
                var kb = KnowledgeBase(id: id, name: name, createdAt: created)
                kb.topK               = record["topK"]               as? Int    ?? 10
                kb.topN               = record["topN"]               as? Int    ?? 50
                kb.similarityThreshold = record["similarityThreshold"] as? Double ?? 0.2
                if let m = record["chunkMethod"] as? String { kb.chunkMethod = ChunkMethod(rawValue: m) ?? .general }
                kb.chunkSize          = record["chunkSize"]          as? Int    ?? 512
                kb.chunkOverlap       = record["chunkOverlap"]       as? Int    ?? 64
                try? db.saveKB(kb)
            }
        }
    }

    // MARK: - Books

    private func pushBooks() async throws {
        let kbs = (try? db.allKBs()) ?? []
        let books = kbs.flatMap { (try? db.allBooks(kbId: $0.id)) ?? [] }
        guard !books.isEmpty else { return }

        let records: [CKRecord] = books.map { book in
            let record = CKRecord(recordType: "Book",
                                  recordID: CKRecord.ID(recordName: "Book-\(book.id)"))
            record["id"]         = book.id
            record["kbId"]       = book.kbId
            record["title"]      = book.title
            record["author"]     = book.author
            record["fileType"]   = book.fileType
            record["addedAt"]    = book.addedAt
            record["chunkCount"] = book.chunkCount
            record["pageCount"]  = book.pageCount
            record["wordCount"]  = book.wordCount
            // filePath intentionally omitted — it is device-specific.
            return record
        }
        try await saveRecords(records)
    }

    private func pullBooks() async throws {
        let results = try await fetchAll(recordType: "Book")
        for record in results {
            guard let id    = record["id"]      as? String,
                  let kbId  = record["kbId"]    as? String,
                  let title = record["title"]   as? String,
                  let added = record["addedAt"] as? Date else { continue }

            // Only create the metadata stub if not already present locally.
            guard (try? db.book(id: id)) == nil else { continue }

            var book = Book(id: id, kbId: kbId, title: title,
                            author: record["author"] as? String ?? "",
                            filePath: "",   // No file on this device yet.
                            addedAt: added,
                            chunkCount: record["chunkCount"] as? Int ?? 0)
            book.fileType  = record["fileType"]  as? String ?? ""
            book.pageCount = record["pageCount"] as? Int    ?? 0
            book.wordCount = record["wordCount"] as? Int    ?? 0
            try? db.save(book)
        }
    }

    // MARK: - Chat Sessions

    private func pushSessions() async throws {
        let kbs = (try? db.allKBs()) ?? []
        let sessions = kbs.flatMap { (try? db.allSessions(kbId: $0.id)) ?? [] }
        guard !sessions.isEmpty else { return }

        let records: [CKRecord] = sessions.map { s in
            let record = CKRecord(recordType: "ChatSession",
                                  recordID: CKRecord.ID(recordName: "Session-\(s.id)"))
            record["id"]        = s.id
            record["kbId"]      = s.kbId
            record["name"]      = s.name
            record["createdAt"] = s.createdAt
            return record
        }
        try await saveRecords(records)
    }

    private func pullSessions() async throws {
        let results = try await fetchAll(recordType: "ChatSession")
        for record in results {
            guard let id      = record["id"]        as? String,
                  let kbId    = record["kbId"]      as? String,
                  let name    = record["name"]      as? String,
                  let created = record["createdAt"] as? Date else { continue }

            guard (try? db.session(id: id)) == nil else { continue }
            let session = ChatSession(id: id, kbId: kbId, name: name, createdAt: created)
            try? db.saveSession(session)
        }
    }

    // MARK: - Messages

    private func pushMessages() async throws {
        let kbs = (try? db.allKBs()) ?? []
        let sessions = kbs.flatMap { (try? db.allSessions(kbId: $0.id)) ?? [] }
        var records: [CKRecord] = []

        for session in sessions {
            let msgs = (try? db.loadMessages(sessionId: session.id)) ?? []
            for msg in msgs {
                let record = CKRecord(recordType: "Message",
                                      recordID: CKRecord.ID(recordName: "Msg-\(msg.id.uuidString)"))
                record["id"]        = msg.id.uuidString
                record["sessionId"] = session.id
                record["kbId"]      = session.kbId
                record["role"]      = msg.role == .user ? "user" : "assistant"
                record["content"]   = msg.content
                record["timestamp"] = msg.timestamp
                records.append(record)
            }
        }
        guard !records.isEmpty else { return }
        try await saveRecords(records)
    }

    private func pullMessages() async throws {
        let results = try await fetchAll(recordType: "Message")
        for record in results {
            guard let idStr     = record["id"]        as? String,
                  let id        = UUID(uuidString: idStr),
                  let sessionId = record["sessionId"] as? String,
                  let kbId      = record["kbId"]      as? String,
                  let roleStr   = record["role"]      as? String,
                  let content   = record["content"]   as? String,
                  let ts        = record["timestamp"] as? Date else { continue }

            // Append-only: skip messages already in the local DB.
            guard !(db.messageExists(id: idStr)) else { continue }

            let role: Message.Role = roleStr == "user" ? .user : .assistant
            var msg = Message(role: role, content: content)
            msg.id = id
            msg.timestamp = ts
            try? db.saveMessages([msg], sessionId: sessionId, kbId: kbId)
        }
    }

    // MARK: - Workflows

    private func pushWorkflows() async throws {
        let workflows = (try? db.allWorkflows()) ?? []
        guard !workflows.isEmpty else { return }

        let records: [CKRecord] = workflows.map { wf in
            let record = CKRecord(recordType: "Workflow",
                                  recordID: CKRecord.ID(recordName: "WF-\(wf.id)"))
            record["id"]         = wf.id
            record["name"]       = wf.name
            record["templateId"] = wf.templateId
            record["kbId"]       = wf.kbId
            record["stepsJSON"]  = wf.stepsJSON
            record["createdAt"]  = wf.createdAt
            return record
        }
        try await saveRecords(records)
    }

    private func pullWorkflows() async throws {
        let results = try await fetchAll(recordType: "Workflow")
        for record in results {
            guard let id         = record["id"]         as? String,
                  let name       = record["name"]       as? String,
                  let templateId = record["templateId"] as? String,
                  let kbId       = record["kbId"]       as? String,
                  let stepsJSON  = record["stepsJSON"]  as? String,
                  let createdAt  = record["createdAt"]  as? Date else { continue }

            let wf = Workflow(id: id, name: name, templateId: templateId,
                              kbId: kbId, stepsJSON: stepsJSON, createdAt: createdAt)
            try? db.saveWorkflow(wf)
        }
    }

    // MARK: - CloudKit Helpers

    private func saveRecords(_ records: [CKRecord]) async throws {
        guard !records.isEmpty else { return }
        // CloudKit batch limit: 400 records per operation.
        let batches = stride(from: 0, to: records.count, by: 400).map {
            Array(records[$0..<min($0 + 400, records.count)])
        }
        for batch in batches {
            let op = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.isAtomic = false
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:        cont.resume()
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
                self.privateDB.add(op)
            }
        }
    }

    private func fetchAll(recordType: String) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        repeat {
            let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
            let nextCursor: CKQueryOperation.Cursor?
            if let c = cursor {
                let response = try await privateDB.records(continuingMatchFrom: c)
                matchResults = response.matchResults
                nextCursor = response.queryCursor
            } else {
                let response = try await privateDB.records(matching: query)
                matchResults = response.matchResults
                nextCursor = response.queryCursor
            }
            for (_, result) in matchResults {
                if let record = try? result.get() { records.append(record) }
            }
            cursor = nextCursor
        } while cursor != nil

        return records
    }
}
