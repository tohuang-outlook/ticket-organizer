import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let organizerTicket = UTType(exportedAs: "com.tohuang.ticket-organizer.ticket", conformingTo: .data)
}

// Drag only the identifier; resolve the latest ticket from the shared store on drop.
struct TicketDragItem: Codable, Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .organizerTicket)
    }
}

struct WorkflowDropRow: View {
    @ObservedObject var store: TicketStore
    let stage: TicketStage
    let selected: Bool
    let onSelect: () -> Void
    let onMoved: (UUID) -> Void
    @State private var isTargeted = false

    private var icon: String {
        switch stage {
        case .draft: "note.text"
        case .working: "hammer"
        case .approval: "paperplane"
        case .approved: "checkmark.circle"
        case .example: "star"
        case .closed: "archivebox"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: icon).foregroundStyle(stage.color)
                Text(stage.shortTitle).font(.system(size: 18))
                Spacer()
                Text("\(store.notes.filter { $0.stage == stage }.count)").font(.system(size: 18)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .primary : .secondary)
        .background(isTargeted ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            if isTargeted { RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2) }
        }
        .help("Drag a ticket here to move it to \(stage.shortTitle).")
        .dropDestination(for: TicketDragItem.self) { items, _ in
            guard items.count == 1, let item = items.first else { return false }
            do {
                try store.moveTicket(id: item.id, to: stage)
                onSelect()
                onMoved(item.id)
                return true
            } catch {
                store.errorMessage = error.localizedDescription
                return false
            }
        } isTargeted: { isTargeted = $0 }
    }
}
