import AppIntents

// MARK: - KBEntity

struct KBEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Knowledge Base"
    static var defaultQuery = KBEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct KBEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [KBEntity] {
        let set = Set(identifiers)
        return ((try? DatabaseService.shared.allKBs()) ?? [])
            .filter { set.contains($0.id) }
            .map { KBEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [KBEntity] {
        ((try? DatabaseService.shared.allKBs()) ?? [])
            .map { KBEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - WorkflowEntity

struct WorkflowEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workflow"
    static var defaultQuery = WorkflowEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WorkflowEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [WorkflowEntity] {
        let set = Set(identifiers)
        return ((try? DatabaseService.shared.allWorkflows()) ?? [])
            .filter { set.contains($0.id) }
            .map { WorkflowEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [WorkflowEntity] {
        ((try? DatabaseService.shared.allWorkflows()) ?? [])
            .map { WorkflowEntity(id: $0.id, name: $0.name) }
    }
}
