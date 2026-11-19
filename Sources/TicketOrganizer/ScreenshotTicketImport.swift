import SwiftUI
import AppKit
import Vision
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotImportError: LocalizedError {
    case image, tooLarge, duplicateOrInvalid
    var errorDescription: String? {
        switch self {
        case .image: "The image could not be read. Choose a PNG, JPEG, or other supported image."
        case .tooLarge: "The image is too large to process (maximum 40 MB and 40 megapixels)."
        case .duplicateOrInvalid: "A selected RITM is invalid or already exists. Review the list and try again."
        }
    }
}

struct ScreenshotTextBox {
    let text: String
    let rect: CGRect
}
struct ScreenshotTicketRow: Identifiable {
    let id = UUID()
    var number: String
    var created: String
    var selected = true
}
enum ScreenshotTicketParser {
    static func validNumber(_ text: String) -> Bool {
        text.range(of: "^RITM[0-9]+$", options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
    static func parse(_ boxes: [ScreenshotTextBox]) -> [ScreenshotTicketRow] {
        let numberPattern = "(?<![A-Za-z0-9])RITM[0-9]+(?![A-Za-z0-9])"
        let datePattern = "(?<![0-9])[0-9]{4}-[0-9]{2}-[0-9]{2}\\s+[0-9]{2}:[0-9]{2}:[0-9]{2}(?![0-9])"
        let numbers = boxes.flatMap { box in matches(numberPattern, in: box.text).map { (number: $0.uppercased(), box: box) } }
            .sorted { $0.box.rect.midY > $1.box.rect.midY }
        let dates = boxes.flatMap { box in matches(datePattern, in: box.text).map { (date: $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression), box: box) } }
        return numbers.map { item in
            let candidates = dates.filter { date in
                abs(date.box.rect.midY - item.box.rect.midY) <= max(date.box.rect.height, item.box.rect.height) * 0.65
            }
            let nearbyNumbers = numbers.filter { other in
                abs(other.box.rect.midY - item.box.rect.midY) <= max(other.box.rect.height, item.box.rect.height) * 0.65
            }
            // Ambiguous OCR geometry must be reviewed and entered manually.
            let date = candidates.count == 1 && nearbyNumbers.count == 1 ? candidates[0].date : ""
            return ScreenshotTicketRow(number: item.number, created: date)
        }
    }
    static func recognize(_ data: Data) throws -> [ScreenshotTicketRow] {
        guard data.count <= 40 * 1024 * 1024 else { throw ScreenshotImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ScreenshotImportError.image }
        guard width > 0, height > 0, Double(width) * Double(height) <= 40_000_000 else { throw ScreenshotImportError.tooLarge }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ScreenshotImportError.image }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let boxes = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ScreenshotTextBox(text: $0.string, rect: observation.boundingBox) }
        }
        return parse(boxes)
    }
}

struct ScreenshotTicketImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: TicketStore
    var onImported: () -> Void
    @State private var rows: [ScreenshotTicketRow] = []
    @State private var sourceName = ""
    @State private var isReading = false
    @State private var error: String?
    private var existing: Set<String> { Set(store.notes.map { $0.ritm.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }) }
    private func number(_ row: ScreenshotTicketRow) -> String { row.number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private func status(_ row: ScreenshotTicketRow, index: Int) -> String {
        let value = number(row)
        guard ScreenshotTicketParser.validNumber(value) else { return "Check RITM" }
        if existing.contains(value) { return "Already exists" }
        if rows.prefix(index).contains(where: { number($0) == value }) { return "Repeated in image" }
        guard CreatedTimeInput.parse(row.created) != nil else { return "Enter valid Created time" }
        return "New draft"
    }
    private var ready: [(ScreenshotTicketRow, Date)] {
        rows.enumerated().compactMap { index, row in
            guard row.selected, status(row, index: index) == "New draft", let date = CreatedTimeInput.parse(row.created) else { return nil }
            return (row, date)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Compare Screenshot").font(.title2.bold())
                Spacer()
                Button("Add Row") { rows.append(ScreenshotTicketRow(number: "", created: "")) }.disabled(isReading)
                Button("Choose Screenshot…") { chooseImage() }.disabled(isReading)
            }
            Text("Review every RITM and Created time before importing. Existing tickets, including Closed, are not duplicated. Times use this Mac's local time.")
                .foregroundStyle(.secondary)
            Text(sourceName.isEmpty ? "Choose a screenshot containing RITM numbers and Created times." : sourceName).foregroundStyle(.secondary)
            if isReading { ProgressView("Reading screenshot on this Mac…") }
            else if !sourceName.isEmpty && rows.isEmpty { Text("No RITM numbers found. Try a clearer screenshot.").foregroundStyle(.secondary) }
            else if !rows.isEmpty {
                HStack {
                    Text("Import").frame(width: 50)
                    Text("RITM").frame(width: 160, alignment: .leading)
                    Text("Created (yyyy-MM-dd HH:mm:ss)").frame(width: 220, alignment: .leading)
                    Text("Status")
                }.fontWeight(.semibold)
                List {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack {
                            Toggle("Import", isOn: $rows[index].selected).labelsHidden().frame(width: 50)
                                .disabled(status(rows[index], index: index) != "New draft")
                            TextField("RITM", text: $rows[index].number).frame(width: 160)
                            TextField("yyyy-MM-dd HH:mm:ss", text: $rows[index].created).frame(width: 220)
                            Text(status(rows[index], index: index)).foregroundStyle(status(rows[index], index: index) == "New draft" ? Color.primary : Color.secondary)
                        }
                    }
                }
                Text("\(ready.count) selected new drafts ready · \(rows.count) recognized rows").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create \(ready.count) Drafts") { importSelected() }.buttonStyle(.borderedProminent).disabled(ready.isEmpty || isReading)
            }
        }
        .padding(20).frame(minWidth: 800, minHeight: 480)
        .alert("Unable to Compare Screenshot", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= 40 * 1024 * 1024 else { throw ScreenshotImportError.tooLarge }
            sourceName = url.lastPathComponent; rows = []; isReading = true
            Task {
                do { rows = try await Task.detached(priority: .userInitiated) { try ScreenshotTicketParser.recognize(data) }.value }
                catch { self.error = error.localizedDescription }
                isReading = false
            }
        } catch { self.error = error.localizedDescription }
    }
    private func importSelected() {
        do {
            let drafts = ready.map { row, date in
                TicketNote(ritm: number(row), chg: "", title: "", body: "", stage: .draft, priority: .low, owner: "", createdAt: date)
            }
            try store.importDrafts(drafts)
            onImported(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
