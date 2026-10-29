import KnitCore
import SwiftUI

/// A text field for a length stored in cm. Accepts "94", "94 cm", "37in" or
/// "37″"; a bare number is read in the person's preferred unit.
struct LengthField: View {
    let title: String
    @Binding var cm: Double?
    let units: UnitPreference
    var prompt: String = ""

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .focused($focused)
            .multilineTextAlignment(.trailing)
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
            .onAppear(perform: load)
            .onChange(of: cm) { if !focused { load() } }
    }

    private func load() {
        text = cm.map { LengthText.format($0, units) } ?? ""
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            cm = nil
        } else if let v = Double(t) {
            cm = units == .inchFirst ? v * 2.54 : v
        } else if let v = LengthParser.cm(from: t) {
            cm = v
        }
        load()
    }
}

enum LengthText {
    static func format(_ cm: Double, _ units: UnitPreference) -> String {
        switch units {
        case .inchFirst: MeasureFormatter.trim((cm / 2.54 * 4).rounded() / 4) + " in"
        case .cmFirst: MeasureFormatter.trim((cm * 10).rounded() / 10) + " cm"
        }
    }

    /// "94 cm / 37″", in the preferred order.
    static func both(_ cm: Double, _ units: UnitPreference) -> String {
        MeasureFormatter(preference: units).length(cm)
    }
}

/// A plain number field bound to an optional Double.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var prompt: String = ""

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .focused($focused)
            .multilineTextAlignment(.trailing)
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
            .onAppear { text = value.map(MeasureFormatter.trim) ?? "" }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        value = t.isEmpty ? nil : Double(t) ?? value
        text = value.map(MeasureFormatter.trim) ?? ""
    }
}
