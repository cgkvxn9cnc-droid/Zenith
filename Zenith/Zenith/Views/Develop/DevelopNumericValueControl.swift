//
//  DevelopNumericValueControl.swift
//  Zenith
//

import SwiftUI

/// Champ numérique aligné à droite : édition directe, flèches haut / bas (pas 5 pour les réglages en %, pas plus fins pour les plages décimales courtes).
struct DevelopNumericValueControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var displayPercent: Bool = true

    @FocusState private var focused: Bool
    @State private var text: String = ""

    private var keyboardStep: Double {
        if displayPercent {
            return 5
        }
        let span = range.upperBound - range.lowerBound
        if span <= 10 { return 0.25 }
        if span <= 25 { return 0.5 }
        return 1
    }

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .font(.caption.monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 40, maxWidth: 52)
            .textFieldStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(focused ? 0.12 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(focused ? 0.35 : 0.12), lineWidth: 1)
            }
            .onSubmit { commitText() }
            .onChange(of: value) { _, new in
                if !focused {
                    text = stringForValue(new)
                }
            }
            .onAppear {
                text = stringForValue(value)
            }
            .onKeyPress(.upArrow) {
                adjustByKeyboardStep(direction: 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                adjustByKeyboardStep(direction: -1)
                return .handled
            }
            .accessibilityLabel(String(localized: "develop.value.accessibility"))
            .help(String(localized: "develop.value.help"))
    }

    private func stringForValue(_ v: Double) -> String {
        if displayPercent {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }

    private func commitText() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(normalized) {
            value = min(range.upperBound, max(range.lowerBound, v))
        }
        text = stringForValue(value)
        focused = false
    }

    private func adjustByKeyboardStep(direction: Int) {
        let delta = Double(direction) * keyboardStep
        value = min(range.upperBound, max(range.lowerBound, value + delta))
        text = stringForValue(value)
    }
}
