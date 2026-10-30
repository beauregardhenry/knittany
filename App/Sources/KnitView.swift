import KnitCore
import SwiftUI

/// The regraded instructions as a checklist to knit from: tick off each step,
/// keep count of rows, and the first unticked step is marked "you are here".
struct KnitView: View {
    let result: GradeResult
    @Binding var progress: KnittingProgress

    struct Step: Identifiable {
        var id: String
        var section: String
        var text: String
        var heading: Bool
    }

    var steps: [Step] {
        result.sections.flatMap { section in
            section.lines.enumerated().map { i, line in
                Step(
                    id: KnittingProgress.key(section: section.title, line: i), section: section.title,
                    text: line.hasPrefix("## ") ? String(line.dropFirst(3)) : line, heading: line.hasPrefix("## ")
                )
            }
        }
    }

    var body: some View {
        let all = steps
        let todo = all.filter { !$0.heading }
        let doneCount = todo.filter { progress.done.contains($0.id) }.count
        let next = todo.first { !progress.done.contains($0.id) }
        ScrollViewReader { scroller in
            VStack(spacing: 0) {
                counterBar(done: doneCount, of: todo.count) {
                    if let next { withAnimation { scroller.scrollTo(next.id, anchor: .center) } }
                }
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(result.sections.map(\.title).uniqued(), id: \.self) { title in
                            Text(title.uppercased())
                                .scaledFont(.headline)
                                .padding(.top, 18)
                                .padding(.bottom, 4)
                            ForEach(all.filter { $0.section == title }) { step in
                                row(step, isNext: step.id == next?.id)
                                    .id(step.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    func row(_ step: Step, isNext: Bool) -> some View {
        if step.heading {
            Text(step.text).scaledFont(.subheadline, bold: true).padding(.top, 8)
        } else {
            let done = progress.done.contains(step.id)
            Button {
                if done { progress.done.remove(step.id) } else { progress.done.insert(step.id) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(done ? Color.green : Color.secondary)
                    Text(step.text)
                        .foregroundStyle(done ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(isNext ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(done ? "Mark as not done" : "Mark as done")
        }
    }

    func counterBar(done: Int, of total: Int, jump: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(done) of \(total) steps done").scaledFont(.callout).fixedSize()
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 160)
            }
            Button("Go to Next Step", systemImage: "arrow.down.to.line", action: jump).fixedSize()
            Spacer()
            Text("Row").foregroundStyle(.secondary).fixedSize()
            Button("Back One Row", systemImage: "minus") { progress.counter = max(0, progress.counter - 1) }
                .labelStyle(.iconOnly)
                .keyboardShortcut("-", modifiers: [])
            Text("\(progress.counter)")
                .scaledFont(.counter)
                .monospacedDigit()
                .frame(minWidth: 56)
            Button("Next Row", systemImage: "plus") { progress.counter += 1 }
                .labelStyle(.iconOnly)
                .keyboardShortcut("=", modifiers: [])
            Button("Reset") { progress.counter = 0 }.fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

extension Array where Element: Hashable {
    /// The elements in order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
