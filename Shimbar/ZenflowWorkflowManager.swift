import Foundation

@Observable
final class ZenflowWorkflowManager {
    static let shared = ZenflowWorkflowManager()
    
    private let fileManager = FileManager.default
    private let defaults: UserDefaults
    
    var recentProjects: [String] {
        get {
            defaults.stringArray(forKey: "shimbar.recentZenflowProjects") ?? []
        }
        set {
            defaults.set(newValue, forKey: "shimbar.recentZenflowProjects")
        }
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func addRecentProject(_ path: String) {
        var projects = recentProjects
        if let index = projects.firstIndex(of: path) {
            projects.remove(at: index)
        }
        projects.insert(path, at: 0)
        // Keep max 10
        if projects.count > 10 {
            projects = Array(projects.prefix(10))
        }
        recentProjects = projects
    }
    
    func loadWorkflows(from projectPath: String) -> [ZenflowWorkflow] {
        let workflowsURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".zenflow")
            .appendingPathComponent("workflows")
            
        guard fileManager.fileExists(atPath: workflowsURL.path) else {
            return []
        }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: workflowsURL, includingPropertiesForKeys: [.contentModificationDateKey])
            var workflows: [ZenflowWorkflow] = []
            
            for fileURL in files where fileURL.pathExtension == "md" {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let title = ZenflowWorkflow.extractTitle(from: content) ?? fileURL.deletingPathExtension().lastPathComponent
                    let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                    let lastModified = attrs?[.modificationDate] as? Date
                    
                    let workflow = ZenflowWorkflow(
                        fileName: fileURL.lastPathComponent,
                        title: title,
                        content: content,
                        projectPath: projectPath,
                        lastModified: lastModified
                    )
                    workflows.append(workflow)
                }
            }
            
            return workflows.sorted(by: { $0.title < $1.title })
        } catch {
            print("Failed to load workflows: \(error)")
            return []
        }
    }
    
    @discardableResult
    func saveWorkflow(_ workflow: ZenflowWorkflow) throws -> Date? {
        let workflowsURL = URL(fileURLWithPath: workflow.projectPath)
            .appendingPathComponent(".zenflow")
            .appendingPathComponent("workflows")
            
        if !fileManager.fileExists(atPath: workflowsURL.path) {
            try fileManager.createDirectory(at: workflowsURL, withIntermediateDirectories: true)
        }
        
        try workflow.content.write(to: workflow.absolutePath, atomically: true, encoding: .utf8)
        
        addRecentProject(workflow.projectPath)
        
        let attrs = try? fileManager.attributesOfItem(atPath: workflow.absolutePath.path)
        return attrs?[.modificationDate] as? Date
    }
    
    func deleteWorkflow(_ workflow: ZenflowWorkflow) throws {
        try fileManager.removeItem(at: workflow.absolutePath)
    }
}

struct WorkflowTemplate: Identifiable {
    let id: String
    let title: String
    let description: String
    let content: String
    
    var defaultFileName: String {
        "\(id).md"
    }
    
    init(id: String, title: String, description: String, content: String) {
        self.id = id
        self.title = title
        self.description = description
        self.content = WorkflowTemplate.dedent(content)
    }
    
    static func dedent(_ string: String) -> String {
        let lines = string.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let minIndent = nonEmpty.reduce(Int.max) { min($0, $1.prefix(while: { $0 == " " || $0 == "\t" }).count) }
        guard minIndent > 0, minIndent != Int.max else { return string }
        return lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
            return String(line.dropFirst(min(minIndent, line.count)))
        }.joined(separator: "\n")
    }
    
    static let templates: [WorkflowTemplate] = [
        WorkflowTemplate(
            id: "code-review",
            title: "Code Review",
            description: "Multi-step review process: architecture, logic, and style.",
            content: """
            # Code Review
            
            ## Configuration
            - **Artifacts Path**: {@artifacts_path}
            
            ---
            
            ## Workflow Steps
            
            ### [ ] Step 1: Architecture Review
            <!-- agent: senior-developer -->
            Review the architecture and design of the proposed changes.
            Ensure they align with project patterns.
            
            ### [ ] Step 2: Logic & Security Check
            <!-- agent: security-auditor -->
            Check for logic flaws, edge cases, and potential security issues.
            
            ### [ ] Step 3: Style & Formatting
            <!-- agent: linter-bot -->
            Ensure code style matches the repository guidelines.
            """
        ),
        WorkflowTemplate(
            id: "security-audit",
            title: "Security Audit",
            description: "Dependency scan and vulnerability analysis.",
            content: """
            # Security Audit
            
            ## Configuration
            - **Artifacts Path**: {@artifacts_path}
            
            ---
            
            ## Workflow Steps
            
            ### [ ] Step 1: Dependency Scan
            <!-- agent: security-auditor -->
            Scan current dependencies for known vulnerabilities and CVEs.
            
            ### [ ] Step 2: Source Code Analysis
            <!-- agent: security-auditor -->
            Perform static analysis on the core modules looking for common OWASP vulnerabilities.
            
            ### [ ] Step 3: Audit Report
            <!-- agent: tech-writer -->
            Compile the findings into a comprehensive markdown report.
            """
        ),
        WorkflowTemplate(
            id: "refactor-plan",
            title: "Refactor Plan",
            description: "Identify targets, plan changes, implement, and verify.",
            content: """
            # Refactor Plan
            
            ## Configuration
            - **Artifacts Path**: {@artifacts_path}
            
            ---
            
            ## Workflow Steps
            
            ### [ ] Step 1: Identify Refactoring Targets
            <!-- agent: architect -->
            Analyze the codebase to find modules with high complexity or code smell.
            
            ### [ ] Step 2: Propose Architecture
            <!-- agent: architect -->
            Draft a plan on how to restructure the identified modules.
            
            ### [ ] Step 3: Implementation
            <!-- agent: developer -->
            Execute the refactoring plan carefully.
            
            ### [ ] Step 4: Verification
            <!-- agent: qa-bot -->
            Run test suites and verify no regressions were introduced.
            """
        )
    ]
}
