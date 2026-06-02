import Foundation

struct ZenflowWorkflow: Identifiable, Hashable {
    let id: UUID
    var fileName: String
    var title: String
    var content: String
    var projectPath: String
    var lastModified: Date?
    
    var absolutePath: URL {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".zenflow")
            .appendingPathComponent("workflows")
            .appendingPathComponent(fileName)
    }
    
    init(id: UUID = UUID(), fileName: String, title: String, content: String, projectPath: String, lastModified: Date? = nil) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.content = content
        self.projectPath = projectPath
        self.lastModified = lastModified
    }
    
    static func extractTitle(from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
