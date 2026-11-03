import KnitCore
import SwiftUI

/// What the window shows when nothing is selected: the patterns on the needles
/// and the three steps to a pattern that fits.
struct WelcomeView: View {
    @Environment(LibraryModel.self) private var model
    @AppStorage(TextSize.key) private var textSize = TextSize.standard

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                StitchBand(stitchWidth: 26, rows: 2)

                VStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().frame(width: 104, height: 104)
                    Text("Knittany")
                        .font(.system(size: textSize.points(.title) * 1.9, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: Yarn.rainbow, startPoint: .leading, endPoint: .trailing))
                    Text("Knit patterns that fit the person you're knitting for.")
                        .scaledFont(.headline)
                        .foregroundStyle(.secondary)
                }

                if !model.favorites.isEmpty { onTheNeedles }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16, alignment: .top)], spacing: 16) {
                    StepCard(number: 1, colour: Yarn.pink, icon: "person.fill", title: "Who's it for?",
                             text: "Add the person you're knitting for and enter their measurements.") {
                        Button("Add Person", systemImage: "plus") { model.addPerson() }
                            .buttonStyle(YarnButtonStyle(colour: Yarn.pink))
                    }
                    StepCard(number: 2, colour: Yarn.purple, icon: "doc.richtext.fill", title: "Pick a pattern",
                             text: "Import a pattern PDF and check what was read, or design a sweater from scratch.") {
                        Button("Import Pattern…", systemImage: "square.and.arrow.down") { model.choosingImport = true }
                            .buttonStyle(YarnButtonStyle(colour: Yarn.purple))
                        Button("Design a Sweater…", systemImage: "wand.and.stars") { model.newDesign() }
                            .buttonStyle(YarnButtonStyle(colour: Yarn.green))
                    }
                    StepCard(number: 3, colour: Yarn.orange, icon: "tshirt.fill", title: "Cast on",
                             text: "Open the pattern and choose New Project. Knittany regrades it to fit, stitch by stitch.") {
                        EmptyView()
                    }
                }
                .padding(.horizontal, 32)

                StitchBand(stitchWidth: 26)
                    .rotationEffect(.degrees(180))
                    .opacity(0.9)
            }
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [Yarn.purple.opacity(0.14), Yarn.pink.opacity(0.06), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// The favourite patterns, one click away.
    var onTheNeedles: some View {
        VStack(spacing: 10) {
            Text("On the needles").scaledFont(.subheadline, bold: true).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Array(model.favorites.prefix(5).enumerated()), id: \.element.id) { i, p in
                    Button(p.name, systemImage: "star.fill") { model.selection = .favorite(p.id) }
                        .buttonStyle(YarnButtonStyle(colour: Yarn.colour(i + 1)))
                }
            }
        }
    }
}

/// One of the three steps, in its own colour.
struct StepCard<Actions: View>: View {
    let number: Int
    let colour: Color
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Yarn.ink(on: colour))
                    .frame(width: 28, height: 28)
                    .background(colour, in: Circle())
                Image(systemName: icon).foregroundStyle(colour).scaledFont(.headline)
                Spacer()
            }
            Text(title).scaledFont(.headline)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) { actions }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .background(colour.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(colour.opacity(0.4), lineWidth: 1))
    }
}
