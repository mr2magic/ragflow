import Foundation

struct Message: Identifiable {
    var id = UUID()
    var role: Role
    var content: String
    var timestamp = Date()

    enum Role {
        case user, assistant
    }
}
