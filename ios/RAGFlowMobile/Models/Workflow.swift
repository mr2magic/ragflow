import Foundation
import GRDB

struct Workflow: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    var templateId: String
    var kbId: String
    var stepsJSON: String       // JSON-encoded [WorkflowStep]
    var createdAt: Date

    static let databaseTableName = "workflows"

    var steps: [WorkflowStep] {
        (try? JSONDecoder().decode([WorkflowStep].self, from: Data(stepsJSON.utf8))) ?? []
    }
}

struct WorkflowRun: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var workflowId: String
    var input: String
    var output: String
    var status: String          // "completed" | "failed"
    var stepLogJSON: String     // JSON-encoded [String]
    var createdAt: Date

    static let databaseTableName = "workflow_runs"

    var stepLog: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(stepLogJSON.utf8))) ?? []
    }
}
