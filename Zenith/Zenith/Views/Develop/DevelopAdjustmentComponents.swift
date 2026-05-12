//
//  DevelopAdjustmentComponents.swift
//  Zenith
//

import AppKit
import SwiftUI

/// Identité des sections pour l’accordéon du panneau Développement (jusqu’à trois sections ouvertes à la fois).
enum DevelopAdjustmentAccordionSection: Hashable {
    /// Groupe 1 — Basiques (balance des blancs, tons, teinte / saturation).
    case basics
    case tslPerColor
    case colorBalance
    case curves
    case blackWhite
    case sharpness
    /// Groupe 7 — Grain et réduction de bruit (une carte).
    case grainAndNoise
}

// MARK: - Carte type Pixelmator

struct DevelopAdjustmentCard<Content: View>: View {
    let accordionID: DevelopAdjustmentAccordionSection
    @Binding var expandedSectionIDs: [DevelopAdjustmentAccordionSection]
    @Binding var hoveredGroupResetSection: DevelopAdjustmentAccordionSection?
    let titleKey: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    private var isExpanded: Bool { expandedSectionIDs.contains(accordionID) }

    private func toggleExpanded() {
        var arr = expandedSectionIDs
        if let idx = arr.firstIndex(of: accordionID) {
            arr.remove(at: idx)
        } else {
            arr.append(accordionID)
            while arr.count > 3 {
                arr.removeFirst()
            }
        }
        expandedSectionIDs = arr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        toggleExpanded()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text(titleKey)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        hoveredGroupResetSection = accordionID
                    } else if hoveredGroupResetSection == accordionID {
                        hoveredGroupResetSection = nil
                    }
                }
                Spacer(minLength: 8)
            }

            if isExpanded {
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
    var accent: Color = ZenithTheme.adjustmentOrange
    var defaultValue: Double = 0
    /// Affiche « Réinitialiser » à côté du titre tant que ⌘ est maintenu.
    var commandKeyShowsReset: Bool = false
    var onReset: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(titleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if commandKeyShowsReset, let onReset {
                    Button(String(localized: "develop.footer.reset")) {
                        onReset()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(ZenithTheme.adjustmentOrange)
                    .fixedSize()
                }
                HStack(spacing: 2) {
                    DevelopNumericValueControl(value: $value, range: range, displayPercent: displayPercent)
                    if displayPercent {
                        Text("%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Slider(value: $value, in: range)
                .tint(accent)
                .controlSize(.small)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        let clamped = min(max(defaultValue, range.lowerBound), range.upperBound)
                        value = clamped
                    }
                )
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Curseur avec dégradé sous la piste (température, teinte, teinte arc-en-ciel)

struct DevelopGradientSliderRow: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double>
    var gradientColors: [Color]
    var displayPercent: Bool = true
    var defaultValue: Double = 0
    var commandKeyShowsReset: Bool = false
    var onReset: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(titleKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if commandKeyShowsReset, let onReset {
                    Button(String(localized: "develop.footer.reset")) {
                        onReset()
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(ZenithTheme.adjustmentOrange)
                    .fixedSize()
                }
                HStack(spacing: 2) {
                    DevelopNumericValueControl(value: $value, range: range, displayPercent: displayPercent)
                    if displayPercent {
                        Text("%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
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
                    .tint(.clear)
                    .controlSize(.small)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            let clamped = min(max(defaultValue, range.lowerBound), range.upperBound)
                            value = clamped
                        }
                    )
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

// MARK: - Mini disque teinte / saturation (−100…100 teinte, 0…100 saturation)

struct DevelopColorWheelPair: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    var defaultHue: Double = 0
    var defaultSaturation: Double = 0

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
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture(count: 2).onEnded {
                hue = defaultHue
                saturation = defaultSaturation
            }
        )
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

// MARK: - Pied de panneau Avant / Après + tout réinitialiser

struct DevelopPanelFooter: View {
    @Binding var compareOriginal: Bool
    var onResetAll: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Label(String(localized: "develop.footer.compare"), systemImage: "square.split.2x1")
                .font(.callout.weight(.medium))
                .foregroundStyle(compareOriginal ? ZenithTheme.adjustmentOrange : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(compareOriginal ? 0.38 : 0.2), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            compareOriginal = true
                        }
                        .onEnded { _ in
                            compareOriginal = false
                        }
                )
                .help(String(localized: "develop.footer.compare_hint"))
                .accessibilityLabel(Text("develop.footer.compare"))
                .accessibilityHint(Text("develop.footer.compare_hint"))

            Button(action: onResetAll) {
                Label(String(localized: "develop.footer.reset_all"), systemImage: "arrow.counterclockwise.circle")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(String(localized: "develop.footer.reset_all_hint"))
            .accessibilityLabel(Text("develop.footer.reset_all"))
        }
        .padding(.top, 8)
        .onDisappear {
            compareOriginal = false
        }
    }
}

// MARK: - Suivi du curseur pour ⌘ = sur l’outil survolé

extension View {
    /// Associe la vue au nom d’outil pour la réinitialisation au clavier (voir `DevelopPanel`).
    func developResetHoverTracking(id: String, hoveredId: Binding<String?>) -> some View {
        onHover { inside in
            if inside {
                hoveredId.wrappedValue = id
            } else if hoveredId.wrappedValue == id {
                hoveredId.wrappedValue = nil
            }
        }
    }
}
