import Foundation
import Combine

@MainActor
final class TicketStore: ObservableObject {
    @Published private(set) var notes: [TicketNote] = []
    @Published var errorMessage: String?
    let url: URL
    private var canWrite = true

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TicketOrganizer/tickets.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                notes = try JSONDecoder().decode([TicketNote].self, from: Data(contentsOf: self.url))
            }
        } catch {
            canWrite = false
            errorMessage = "Your saved notes could not be opened. The file has not been changed. Check \(self.url.path) and its .backup file before restarting.\n\n\(error.localizedDescription)"
        }
    }

    private func commit(_ next: [TicketNote]) throws {
        guard canWrite else {
            throw StoreError.unreadableFile
        }
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url)
            // Never overwrite a file that has become unreadable since launch.
            _ = try JSONDecoder().decode([TicketNote].self, from: previous)
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        notes = next
    }

    func add(_ note: TicketNote) throws {
        var next = notes
        next.insert(note, at: 0)
        try commit(next)
    }

    func update(_ note: TicketNote, originalStage: TicketStage? = nil) throws {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { throw StoreError.missingTicket }
        var next = notes
        next[index] = note
        // An open editor must not undo a drag if its Status field was untouched.
        if let originalStage, note.stage == originalStage {
            next[index].stage = notes[index].stage
        }
        next[index].createdAt = notes[index].createdAt
        next[index].updatedAt = Date()
        try commit(next)
    }

    func moveTicket(id: UUID, to stage: TicketStage) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { throw StoreError.missingTicket }
        guard notes[index].stage != stage else { return }
        var next = notes
        next[index].stage = stage
        next[index].updatedAt = Date()
        try commit(next)
    }

    func delete(_ note: TicketNote) throws {
        guard notes.contains(where: { $0.id == note.id }) else { throw StoreError.missingTicket }
        try commit(notes.filter { $0.id != note.id })
    }

    enum StoreError: LocalizedError {
        case unreadableFile, missingTicket
        var errorDescription: String? {
            switch self {
            case .unreadableFile: "Notes cannot be saved because the existing data file could not be opened. Restore your data file, then restart the app."
            case .missingTicket: "This ticket no longer exists. Close the editor and select another ticket."
            }
        }
    }
}
