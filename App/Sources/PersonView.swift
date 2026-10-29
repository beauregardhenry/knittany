import KnitCore
import SwiftUI

struct PersonView: View {
    @Environment(LibraryModel.self) private var model
    @State var person: Person
    @State private var confirmingDelete = false

    /// The order a knitter would measure in.
    static let order: [BodyMeasure] = [
        .chest, .waist, .hip, .upperArm, .wrist, .armLength, .crossBack,
        .neck, .backWaistLength, .armholeDepth, .neckToWrist, .height,
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $person.name)
                Picker("Show first", selection: $person.units) {
                    Text("Centimetres").tag(UnitPreference.cmFirst)
                    Text("Inches").tag(UnitPreference.inchFirst)
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(Self.order, id: \.self) { m in
                    measurementRow(m)
                }
            } header: {
                Text("Body measurements")
            } footer: {
                Text(
                    "Measure the body, not a garment. Leave out anything you haven't measured: grey values are estimates "
                        + "from the Craft Yarn Council standard charts, based on the chest. Regrading uses only what you measure; "
                        + "anything else follows the designer's grading. Height is kept for reference only, because it "
                        + "doesn't reliably predict body or arm lengths."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextEditor(text: $person.notes).frame(minHeight: 60)
            }

            Section {
                Button("Delete \(person.name)…", role: .destructive) { confirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(person.name)
        .onChange(of: person) { model.update(person) }
        .confirmationDialog("Delete \(person.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { model.deletePerson(person.id) }
        } message: {
            Text("Their measurements are removed. Projects for them stay, without a person.")
        }
    }

    @ViewBuilder
    func measurementRow(_ m: BodyMeasure) -> some View {
        let binding = Binding<Double?>(
            get: { person.measurements[m] },
            set: { person.measurements[m] = $0 }
        )
        let estimate = person.estimate(m)
        HStack {
            Text(m.label)
            Spacer()
            if person.measurements[m] == nil, let e = estimate {
                Text("≈ \(LengthText.both(e, person.units)) (estimate)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let v = person.measurements[m] {
                Text(LengthText.both(v, person.units)).font(.callout).foregroundStyle(.secondary)
            }
            LengthField(title: m.label, cm: binding, units: person.units, prompt: person.units == .inchFirst ? "in" : "cm")
                .labelsHidden()
                .frame(width: 90)
        }
    }
}
