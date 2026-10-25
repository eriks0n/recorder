import SwiftUI

struct RenameRecordingPopover: View {
    let entry: RecordingEntry
    @Environment(RecorderModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meeting umbenennen").font(.headline)
            TextField("Meetingname", text: $draft).textFieldStyle(.roundedBorder).onSubmit(save)
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Abbrechen") { dismiss() }
                Spacer()
                Button("Speichern", action: save)
                    .disabled(MeetingNaming.clean(draft) == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 300)
        .onAppear { draft = entry.title ?? "" }
    }
    private func save() {
        if model.renameRecording(entry, to: draft) { dismiss() }
        else { error = model.statusMessage }
    }
}
