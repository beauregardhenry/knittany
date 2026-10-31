import AppKit
import ImageIO
import KnitCore
import SwiftUI
import UniformTypeIdentifiers

struct PatternView: View {
    @Environment(LibraryModel.self) private var model
    let entry: PatternEntry
    @State private var attachingPDF = false
    @State private var addingPhotos = false
    @State private var confirmingDelete = false
    private let inches = Locale.current.measurementSystem == .us

    var body: some View {
        if let pattern = model.pattern(entry.id) {
            Form {
                Section {
                    if let designer = pattern.designer { LabeledContent("Designer", value: designer) }
                    if let c = pattern.construction { LabeledContent("Construction") { Text(c).multilineTextAlignment(.trailing) } }
                    LabeledContent("Sizes", value: pattern.sizes.joined(separator: ", "))
                    LabeledContent("Gauge", value: MeasureFormatter().gauge(pattern.gauge))
                    if let ease = pattern.statedEase?[pattern.primaryDimension] {
                        LabeledContent("Designer's ease", value: "\(MeasureFormatter().length(ease)) at the \(pattern.primaryDimension.label.lowercased())")
                    }
                }

                Section {
                    HStack {
                        Button("New Project", systemImage: "plus") { model.addProject(patternID: entry.id) }
                            .buttonStyle(.borderedProminent)
                        if pattern.design != nil {
                            Button("Edit Design…", systemImage: "wand.and.stars") { model.editDesign(entry.id) }
                        }
                        Spacer()
                    }
                }

                photosSection

                if pattern.design == nil { Section("Original PDF") {
                    if entry.hasSourcePDF {
                        LabeledContent("Attached") {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.sourcePDFURL(entry.id)]) }
                        }
                    } else {
                        Text(
                            (pattern.sourcePages ?? []).isEmpty
                                ? "No PDF attached."
                                : "Attach the original PDF so its chart pages (\((pattern.sourcePages ?? []).map(\.title).joined(separator: ", "))) can be included in exports."
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button(entry.hasSourcePDF ? "Replace PDF…" : "Attach PDF…") { attachingPDF = true }
                } }

                Section("Published measurements") {
                    Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("").gridColumnAlignment(.leading)
                            ForEach(pattern.sizes, id: \.self) { Text($0).bold() }
                        }
                        ForEach(pattern.schematic, id: \.id) { s in
                            GridRow {
                                Text("\(s.id.prefix(1))  \(s.label)").gridColumnAlignment(.leading)
                                ForEach(Array(s.values.enumerated()), id: \.offset) { _, v in
                                    Text(MeasureFormatter.trim(inches ? (v / 2.54 * 4).rounded() / 4 : v)).monospacedDigit()
                                }
                            }
                        }
                    }
                    .scaledFont(.callout)
                    Text(inches ? "inches" : "cm").scaledFont(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Button("Delete Pattern…", role: .destructive) { confirmingDelete = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pattern.name)
            .fileImporter(isPresented: $attachingPDF, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result { model.attachSourcePDF(url, to: entry.id) }
            }
            .fileImporter(isPresented: $addingPhotos, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { model.addPhotos(urls, to: entry.id) }
            }
            .confirmationDialog("Delete \(pattern.name)?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) { model.deletePattern(entry.id) }
            } message: {
                Text("Its projects are deleted too. The pattern's files go to the Trash.")
            }
        } else {
            Text("This pattern couldn't be read.").foregroundStyle(.secondary)
        }
    }

    /// Photos of the finished piece: the designer's samples, or your own.
    var photosSection: some View {
        let photos = model.photos(entry.id)
        return Section {
            if photos.isEmpty {
                Text("Add photos of the finished piece: the designer's samples or your own. You can also drag them here.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(photos, id: \.self) { url in
                        PhotoThumbnail(url: url)
                            .onTapGesture { NSWorkspace.shared.open(url) }
                            .help("Click to open")
                            .contextMenu {
                                Button("Open") { NSWorkspace.shared.open(url) }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Divider()
                                Button("Remove Photo", role: .destructive) { model.removePhoto(url) }
                            }
                    }
                }
                .padding(.vertical, 4)
            }
            Button("Add Photos…", systemImage: "photo.badge.plus") { addingPhotos = true }
        } header: {
            Text("Photos")
        }
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
            guard !images.isEmpty else { return false }
            model.addPhotos(images, to: entry.id)
            return true
        }
    }
}

/// A photo cropped to a square, loaded at thumbnail size so large camera photos stay quick.
struct PhotoThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Color.secondary.opacity(0.1)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .task(id: url) { image = await Self.thumbnail(url) }
    }

    nonisolated static func thumbnail(_ url: URL) async -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 600,
              ] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
