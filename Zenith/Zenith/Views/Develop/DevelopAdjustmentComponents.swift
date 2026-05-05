//
//  DevelopAdjustmentComponents.swift
//  Zenith
//

import SwiftUI

// MARK: - Carte type Pixelmator

struct DevelopAdjustmentCard<Content: View>: View {
    let titleKey: LocalizedStringKey
    @Binding var isOn: Bool
    var showMagicWand: Bool = false
    var magicWandAction: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if showMagicWand {
                    Button {
                        magicWandAction?()
                    } label: {
                        Image(systemName: "wand.and.rays")
                            .font(.body.weight(.medium))
                            .foregroundStyle(ZenithTheme.adjustmentOrange.opacity(isOn ? 1 : 0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOn)
                    .help(String(localized: "develop.auto_adjust_hint"))
                }
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(ZenithTheme.adjustmentOrange)
                    .controlSize(.small)
            }

            if isOn {
                content()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ZenithTheme.developCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Ligne curseur + valeur %

struct DevelopSliderRow: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>
    var displayPercent: Bool = true
    var accent: Color = ZenithTheme.sliderThumbNeutral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .tint(accent)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    private var formattedValue: String {
        if displayPercent {
            return String(format: "%.0f %%", value)
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Curseur avec dégradé sous la piste (température, teinte, teinte arc-en-ciel)

struct DevelopGradientSliderRow: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>
    var gradientColors: [Color]
    var displayPercent: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(titleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displayPercent ? String(format: "%.0f %%", value) : String(format: "%.1f", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 5)
                    .opacity(0.85)
                Slider(value: $value, in: range)
                    .tint(ZenithTheme.sliderThumbNeutral)
                    .controlSize(.small)
            }
            .frame(height: 18)
        }
    }
}

// MARK: - Histogramme (placeholder)

struct DevelopHistogramPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.black.opacity(0.35))
            .frame(height: 72)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("develop.histogram.placeholder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
    }
}

// MARK: - Courbe maître (aperçu visuel)

struct DevelopCurvesPreview: View {
    var intensity: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 1)

                let bend = intensity / 100.0 * 0.25
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addQuadCurve(
                        to: CGPoint(x: w, y: 0),
                        control: CGPoint(x: w * (0.5 + bend), y: h * (0.5 - bend))
                    )
                }
                .stroke(Color.white.opacity(0.75), lineWidth: 2)
            }
        }
        .frame(height: 120)
    }
}

// MARK: - Mini disque teinte / saturation (−100…100 teinte, 0…100 saturation)

struct DevelopColorWheelPair: View {
    @Binding var hue: Double
    @Binding var saturation: Double

    private let size: CGFloat = 104

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            .red, .yellow, .green, .cyan, .blue, .purple, .red
                        ],
                        center: .center
                    ),
                    lineWidth: 12
                )
                .background(Circle().fill(ZenithTheme.developCardFill))

            Circle()
                .stroke(Color.white.opacity(0.95), lineWidth: 2)
                .frame(width: 10, height: 10)
                .offset(offsetForKnob)
        }
        .frame(width: size, height: size)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let center = CGPoint(x: size / 2, y: size / 2)
                    let p = CGPoint(x: g.location.x - center.x, y: g.location.y - center.y)
                    let ang = atan2(p.y, p.x)
                    hue = ang / .pi * 100
                    let maxR = size / 2 - 16
                    let dist = min(hypot(p.x, p.y) / maxR, 1)
                    saturation = dist * 100
                }
        )
    }

    private var offsetForKnob: CGSize {
        let rad = (hue / 100) * .pi
        let r = (saturation / 100) * (size / 2 - 18)
        return CGSize(width: CGFloat(cos(rad)) * r, height: CGFloat(sin(rad)) * r)
    }
}

// MARK: - Pied de panneau Avant/Après + Réinitialiser

struct DevelopPanelFooter: View {
    @Binding var compareOriginal: Bool
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                compareOriginal.toggle()
            } label: {
                Image(systemName: "square.split.1x2")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(compareOriginal ? ZenithTheme.adjustmentOrange : .secondary)
            .help(String(localized: "develop.footer.compare_hint"))

            Button(String(localized: "develop.footer.reset")) {
                onReset()
            }
            .buttonStyle(.borderedProminent)
            .tint(ZenithTheme.adjustmentOrange)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }
}
