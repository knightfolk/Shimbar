import SwiftUI

struct ZenflowWorkflowEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State var workflow: ZenflowWorkflow
    let existingFileNames: [String]
    var onSave: (ZenflowWorkflow) -> Void
    
    private var isDuplicateFileName: Bool {
        workflow.fileName.hasSuffix(".md")
            ? existingFileNames.contains(workflow.fileName)
            : existingFileNames.contains(workflow.fileName + ".md")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Workflow Details") {
                    TextField("File Name (e.g. custom-flow.md)", text: $workflow.fileName)
                        .autocorrectionDisabled()
                    
                    if isDuplicateFileName {
                        Label("A workflow with this file name already exists. It will be overwritten on save.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                
                Section("Markdown Definition") {
                    TextEditor(text: $workflow.content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 300)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(workflow.title.isEmpty ? "New Workflow" : workflow.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !workflow.fileName.hasSuffix(".md") {
                            workflow.fileName += ".md"
                        }
                        
                        if let extractedTitle = ZenflowWorkflow.extractTitle(from: workflow.content) {
                            workflow.title = extractedTitle
                        } else {
                            workflow.title = workflow.fileName.replacingOccurrences(of: ".md", with: "").capitalized
                        }
                        
                        onSave(workflow)
                        dismiss()
                    }
                    .disabled(workflow.fileName.isEmpty || workflow.content.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 500)
    }
}
