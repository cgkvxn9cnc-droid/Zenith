//
//  DevelopPanel.swift
//  Zenith
//

import AppKit
import SwiftData
import SwiftUI

struct DevelopPanel: View {
    @Bindable var photo: PhotoRecord
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTSLSwatch = 0
    @State private var colorBalanceMode = 0
    @State private var curvesChannel = 0
    @State private var commandKeyHeld = false
    @State private var hoveredResetToolID: String?
    @State private var hoveredGroupResetSection: DevelopAdjustmentAccordionSection?
    @State private var expandedSectionIDs: [DevelopAdjustmentAccordionSection] = [.basics]
    @State private var lastModifierResetChord: ModifierResetChord = .none

    private let swatchColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink
    ]

    /// Plages adoucies pour rendre les ajustements plus progressifs et éviter des rendus trop extrêmes.
    private enum SoftRange {
        static let temperature = -80.0 ... 80.0
        static let tint = -80.0 ... 80.0
        static let tones = -70.0 ... 70.0
        static let saturation = -75.0 ... 75.0
        static let exposureEV = -3.0 ... 3.0
        static let sharpAmount = 0.0 ... 75.0
        static let sharpRadius = 0.2 ... 8.0
        static let sharpDetail = 0.0 ... 80.0
        static let sharpMasking = 0.0 ... 90.0
        static let noiseReduction = 0.0 ... 80.0
        static let grainSize = 0.0 ... 70.0
        static let grainIntensity = 0.0 ... 70.0
        static let grainRoughness = 0.0 ... 80.0
        static let blackWhite = -80.0 ... 80.0
        static let blackWhiteIntensity = 0.0 ... 80.0
        static let tslPerColor = -80.0 ... 80.0
    }

    private enum ModifierResetChord {
        case none
        case tool
        case group
    }

    /// Identifiants pour ⌘ = (curseur sous le pointeur) et panneaux pour ⌘⌥ = (réinitialisation de groupe).
    private enum HoverResetID: String {
        case temperature, tint, exposure, contrast, highlights, shadows, blackPoint, texture, clarity
        case tslHue, tslSaturation
        case tslPCHue, tslPCSat, tslPCLum
        case cbHighlight, cbMidtone, cbShadow
        case curvesChannel
        case bwRed, bwGreen, bwBlue, bwTone, bwIntensity
        case sharpAmount, sharpRadius, sharpDetail, sharpMasking
        case noiseLuma, noiseChroma
        case grainSize, grainIntensity, grainRoughness

        /// Groupe réinitialisé par ⌘⌥= lorsque le curseur survole cet outil (sans passer par le titre du panneau).
        var groupAccordionSection: DevelopAdjustmentAccordionSection {
            switch self {
            case .temperature, .tint, .exposure, .contrast, .highlights, .shadows, .blackPoint, .texture, .clarity,
                 .tslHue, .tslSaturation:
                return .basics
            case .tslPCHue, .tslPCSat, .tslPCLum:
                return .tslPerColor
            case .cbHighlight, .cbMidtone, .cbShadow:
                return .colorBalance
            case .curvesChannel:
                return .curves
            case .bwRed, .bwGreen, .bwBlue, .bwTone, .bwIntensity:
                return .blackWhite
            case .sharpAmount, .sharpRadius, .sharpDetail, .sharpMasking:
                return .sharpness
            case .noiseLuma, .noiseChroma, .grainSize, .grainIntensity, .grainRoughness:
                return .grainAndNoise
            }
        }
    }

    var body: some View {
        developAdjustmentSections
            .padding(.bottom, 8)
            .background(alignment: .topLeading) {
                CommandKeyHeldMonitor(isHeld: $commandKeyHeld) { flags in
                    handleModifierReset(flags: flags)
                }
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
            .onChange(of: photo.id) { _, _ in
                expandedSectionIDs = [.basics]
                hoveredResetToolID = nil
                hoveredGroupResetSection = nil
                lastModifierResetChord = .none
            }
    }

    private func handleModifierReset(flags: NSEvent.ModifierFlags) {
        guard !PhotoTriageKeyMonitor.isTextEditingActive() else { return }
        let normalized = flags.intersection(.deviceIndependentFlagsMask)
        let command = normalized.contains(.command)
        let option = normalized.contains(.option)
        let chord: ModifierResetChord = {
            if !command { return .none }
            return option ? .group : .tool
        }()
        guard chord != lastModifierResetChord else { return }
        defer { lastModifierResetChord = chord }
        switch chord {
        case .none:
            break
        case .tool:
            _ = performResetShortcut(group: false)
        case .group:
            _ = performResetShortcut(group: true)
        }
    }

    @discardableResult
    private func performResetShortcut(group: Bool) -> Bool {
        if group {
            if let section = hoveredGroupResetSection {
                resetGroup(section)
                return true
            }
            if let raw = hoveredResetToolID, let hid = HoverResetID(rawValue: raw) {
                resetGroup(hid.groupAccordionSection)
                return true
            }
            return false
        }
        guard let id = hoveredResetToolID else { return false }
        resetTool(id: id)
        return true
    }

    private func commit(_ s: DevelopSettings) {
        photo.applyDevelopSettings(s)
        try? modelContext.save()
    }

    private func resetField(_ keyPath: WritableKeyPath<DevelopSettings, Double>) {
        var s = photo.developSettings
        let n = DevelopSettings.neutral
        s[keyPath: keyPath] = n[keyPath: keyPath]
        commit(s)
    }

    private func resetFieldPair(
        hue: WritableKeyPath<DevelopSettings, Double>,
        sat: WritableKeyPath<DevelopSettings, Double>
    ) {
        var s = photo.developSettings
        let n = DevelopSettings.neutral
        s[keyPath: hue] = n[keyPath: hue]
        s[keyPath: sat] = n[keyPath: sat]
        commit(s)
    }

    private func resetGroup(_ section: DevelopAdjustmentAccordionSection) {
        var s = photo.developSettings
        switch section {
        case .basics:
            s.resetBasicsPanelGroup()
        case .tslPerColor:
            s.resetTSLPerColorGroup()
        case .colorBalance:
            s.resetColorBalanceGroup()
        case .curves:
            s.resetCurvesGroup()
        case .blackWhite:
            s.resetBlackWhiteGroup()
        case .sharpness:
            s.resetSharpnessGroup()
        case .grainAndNoise:
            s.resetGrainAndNoiseGroup()
        }
        commit(s)
    }

    private func resetTool(id: String) {
        guard let hid = HoverResetID(rawValue: id) else { return }
        switch hid {
        case .temperature:
            resetField(\.temperature)
        case .tint:
            resetField(\.tint)
        case .exposure:
            resetField(\.exposureEV)
        case .contrast:
            resetField(\.contrast)
        case .highlights:
            resetField(\.highlights)
        case .shadows:
            resetField(\.shadows)
        case .blackPoint:
            resetField(\.blackPoint)
        case .texture:
            resetField(\.texture)
        case .clarity:
            resetField(\.clarity)
        case .tslHue:
            resetField(\.tslHue)
        case .tslSaturation:
            resetField(\.tslSaturation)
        case .tslPCHue:
            resetTSLChannel(index: selectedTSLSwatch) { ch, nz in ch.hue = nz.hue }
        case .tslPCSat:
            resetTSLChannel(index: selectedTSLSwatch) { ch, nz in ch.saturation = nz.saturation }
        case .tslPCLum:
            resetTSLChannel(index: selectedTSLSwatch) { ch, nz in ch.luminance = nz.luminance }
        case .cbHighlight:
            resetFieldPair(hue: \.cbHighlightHue, sat: \.cbHighlightSaturation)
        case .cbMidtone:
            resetFieldPair(hue: \.cbMidtoneHue, sat: \.cbMidtoneSaturation)
        case .cbShadow:
            resetFieldPair(hue: \.cbShadowHue, sat: \.cbShadowSaturation)
        case .curvesChannel:
            resetActiveCurveChannel()
        case .bwRed:
            resetField(\.bwRed)
        case .bwGreen:
            resetField(\.bwGreen)
        case .bwBlue:
            resetField(\.bwBlue)
        case .bwTone:
            resetField(\.bwTone)
        case .bwIntensity:
            resetField(\.bwIntensity)
        case .sharpAmount:
            resetField(\.sharpnessAmountPct)
        case .sharpRadius:
            resetField(\.sharpnessRadiusPx)
        case .sharpDetail:
            resetField(\.sharpnessDetailPct)
        case .sharpMasking:
            resetField(\.sharpnessMaskingPct)
        case .noiseLuma:
            resetField(\.noiseReductionLuminance)
        case .noiseChroma:
            resetField(\.noiseReductionChrominance)
        case .grainSize:
            resetField(\.grainSizePct)
        case .grainIntensity:
            resetField(\.grainIntensityPct)
        case .grainRoughness:
            resetField(\.grainRoughnessPct)
        }
    }

    private func resetTSLChannel(
        index: Int,
        apply: (inout SelectiveColorChannel, SelectiveColorChannel) -> Void
    ) {
        var s = photo.developSettings
        var pal = s.tslPerColorPalette
        var ch = pal.channels[index]
        let nz = DevelopSettings.neutral.tslPerColorPalette.channels[index]
        apply(&ch, nz)
        pal.channels[index] = ch
        s.tslPerColorPalette = pal
        commit(s)
    }

    private func resetActiveCurveChannel() {
        var s = photo.developSettings
        switch curvesChannel {
        case 0: s.toneCurveMaster = .identity
        case 1: s.toneCurveRed = .identity
        case 2: s.toneCurveGreen = .identity
        default: s.toneCurveBlue = .identity
        }
        commit(s)
    }

    @ViewBuilder
    private var developAdjustmentSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            DevelopAdjustmentCard(
                accordionID: .basics,
                expandedSectionIDs: $expandedSectionIDs,
                hoveredGroupResetSection: $hoveredGroupResetSection,
                titleKey: "develop.card.basics_group"
            ) {
                Text("develop.card.white_balance")
                    .font(.subheadline.weight(.medium))
                DevelopGradientSliderRow(
                    titleKey: "develop.slider.temperature",
                    value: binding(\.temperature, autoEnable: \.enableWhiteBalance),
                    range: SoftRange.temperature,
                    gradientColors: [.blue, .cyan, .white, .yellow, .orange],
                    commandKeyShowsReset: commandKeyHeld,
                    onReset: { resetTool(id: HoverResetID.temperature.rawValue) }
                )
                .developResetHoverTracking(id: HoverResetID.temperature.rawValue, hoveredId: $hoveredResetToolID)

                DevelopGradientSliderRow(
                    titleKey: "develop.slider.tint",
                    value: binding(\.tint, autoEnable: \.enableWhiteBalance),
                    range: SoftRange.tint,
                    gradientColors: [.green, .gray, .purple],
                    commandKeyShowsReset: commandKeyHeld,
                    onReset: { resetTool(id: HoverResetID.tint.rawValue) }
                )
                .developResetHoverTracking(id: HoverResetID.tint.rawValue, hoveredId: $hoveredResetToolID)

                Divider().opacity(0.2).padding(.vertical, 4)

                Text("develop.basics.tones_section")
                    .font(.subheadline.weight(.medium))
                sliderReset(.exposure, binding(\.exposureEV, autoEnable: \.enableBasicAdjustments), SoftRange.exposureEV, displayPercent: false, defaultValue: 0)
                sliderReset(.contrast, binding(\.contrast, autoEnable: \.enableBasicAdjustments), SoftRange.tones)
                sliderReset(.highlights, binding(\.highlights, autoEnable: \.enableBasicAdjustments), SoftRange.tones)
                sliderReset(.shadows, binding(\.shadows, autoEnable: \.enableBasicAdjustments), SoftRange.tones)
                sliderReset(.blackPoint, binding(\.blackPoint, autoEnable: \.enableBasicAdjustments), SoftRange.tones)
                sliderReset(.texture, binding(\.texture, autoEnable: \.enableBasicAdjustments), SoftRange.tones)
                sliderReset(.clarity, binding(\.clarity, autoEnable: \.enableBasicAdjustments), SoftRange.tones)

                Divider().opacity(0.2).padding(.vertical, 4)

                Text("develop.basics.hue_sat_section")
                    .font(.subheadline.weight(.medium))
                DevelopGradientSliderRow(
                    titleKey: "develop.hue",
                    value: binding(\.tslHue, autoEnable: \.enableHueSaturation),
                    range: SoftRange.saturation,
                    gradientColors: [
                        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .red
                    ],
                    commandKeyShowsReset: commandKeyHeld,
                    onReset: { resetTool(id: HoverResetID.tslHue.rawValue) }
                )
                .developResetHoverTracking(id: HoverResetID.tslHue.rawValue, hoveredId: $hoveredResetToolID)

                DevelopSliderRow(
                    titleKey: "develop.saturation",
                    value: binding(\.tslSaturation, autoEnable: \.enableHueSaturation),
                    range: SoftRange.saturation,
                    commandKeyShowsReset: commandKeyHeld,
                    onReset: { resetTool(id: HoverResetID.tslSaturation.rawValue) }
                )
                .developResetHoverTracking(id: HoverResetID.tslSaturation.rawValue, hoveredId: $hoveredResetToolID)
            }

            DevelopAdjustmentCard(
                accordionID: .tslPerColor,
                expandedSectionIDs: $expandedSectionIDs,
                hoveredGroupResetSection: $hoveredGroupResetSection,
                titleKey: "develop.card.tsl_per_color"
            ) {
                HStack(spacing: 8) {
                    ForEach(0 ..< 8, id: \.self) { i in
                        Button {
                            selectedTSLSwatch = i
                        } label: {
                            Circle()
                                .fill(swatchColors[i])
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            selectedTSLSwatch == i
                                                ? ZenithTheme.adjustmentOrange
                                                : Color.clear,
                                            lineWidth: 3
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                tslPerColorSlidersForSwatch
            }

            DevelopAdjustmentCard(
                accordionID: .colorBalance,
                expandedSectionIDs: $expandedSectionIDs,
                hoveredGroupResetSection: $hoveredGroupResetSection,
                titleKey: "develop.card.color_balance"
            ) {
                Picker("", selection: $colorBalanceMode) {
                    Text("develop.cb.mode_3way").tag(0)
                }
                .labelsHidden()

                HStack(alignment: .top, spacing: 8) {
                    wheelColumn(title: "develop.cb.highlight", hue: \.cbHighlightHue, sat: \.cbHighlightSaturation, resetHoverId: HoverResetID.cbHighlight.rawValue)
                    wheelColumn(title: "develop.cb.midtone", hue: \.cbMidtoneHue, sat: \.cbMidtoneSaturation, resetHoverId: HoverResetID.cbMidtone.rawValue)
                    wheelColumn(title: "develop.cb.shadow", hue: \.cbShadowHue, sat: \.cbShadowSaturation, resetHoverId: HoverResetID.cbShadow.rawValue)
                }
            }

            DevelopAdjustmentCard(
                accordionID: .curves,
                expandedSectionIDs: $expandedSectionIDs,
                hoveredGroupResetSection: $hoveredGroupResetSection,
                titleKey: "develop.card.curves"
            ) {
                HStack {
                    Picker("", selection: $curvesChannel) {
                        Text("develop.channel.rgb").tag(0)
                        Text("develop.channel.red").tag(1)
                        Text("develop.channel.green").tag(2)
                        Text("develop.channel.blue").tag(3)
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                DevelopCurveEditor(curve: toneCurveBinding(forChannelTag: curvesChannel))
                    .padding(.top, 2)
                    .developResetHoverTracking(id: HoverResetID.curvesChannel.rawValue, hoveredId: $hoveredResetToolID)
            }

            DevelopAdjustmentCard(
                accordionID: .blackWhite,
                expandedSectionIDs: $expandedSectionIDs,
                hoveredGroupResetSection: $hoveredGroupResetSection,
                titleKey: "develop.card.black_white"
            ) {
                sliderReset(.bwRed, binding(\.bwRed, autoEnable: \.enableBlackWhite), SoftRange.blackWhite, accent: .red)
                sliderReset(.bwGreen, binding(\.bwGreen, autoEnable: \.enableBlackWhite), SoftRange.blackWhite, accent: .green)
                sliderReset(.bwBlue, binding(\.bwBlue, autoEnable: \.enableBlackWhite), SoftRange.blackWhite, accent: .blue)
                sliderReset(.bwTone, binding(\.bwTone, autoEnable: \.enableBlackWhite), SoftRange.blackWhite, accent: .gray)
                sliderReset(.bwIntensity, binding(\.bwIntensity, autoEnable: \.enableBlackWhite), SoftRange.blackWhiteIntensity, defaultValue: 0)
            }

            DevelopAdjustmentCard(
                accordionID: .sharpness,
                expandedSectionIDs: $expandedSectionIDs,
                hoveredGroupResetSection: $hoveredGroupResetSection,
                titleKey: "develop.card.sharpness"
            ) {
                if photo.developSettings.sharpnessAmountPct < 0.5 {
                    Text("develop.sharpness.amount_zero_hint")
                        .font(.caption2)
                        .foregroundStyle(ZenithTheme.adjustmentOrange.opacity(0.9))
                }
                sliderReset(.sharpAmount, binding(\.sharpnessAmountPct, autoEnable: \.enableSharpness), SoftRange.sharpAmount, defaultValue: 0)
                sliderReset(.sharpRadius, binding(\.sharpnessRadiusPx, autoEnable: \.enableSharpness), SoftRange.sharpRadius, displayPercent: false, defaultValue: 2.0)
                sliderReset(.sharpDetail, binding(\.sharpnessDetailPct, autoEnable: \.enableSharpness), SoftRange.sharpDetail, defaultValue: 50)
                sliderReset(.sharpMasking, binding(\.sharpnessMaskingPct, autoEnable: \.enableSharpness), SoftRange.sharpMasking, defaultValue: 0)
            }

            DevelopAdjustmentCard(
                accordionID: .grainAndNoise,
                expandedSectionIDs: $expandedSectionIDs,
                hoveredGroupResetSection: $hoveredGroupResetSection,
                titleKey: "develop.card.grain_and_noise"
            ) {
                Text("develop.card.noise_reduction")
                    .font(.subheadline.weight(.medium))
                sliderReset(.noiseLuma, binding(\.noiseReductionLuminance, autoEnable: \.enableNoiseReduction), SoftRange.noiseReduction)
                sliderReset(.noiseChroma, binding(\.noiseReductionChrominance, autoEnable: \.enableNoiseReduction), SoftRange.noiseReduction)

                Divider().opacity(0.2).padding(.vertical, 4)

                Text("develop.card.grain")
                    .font(.subheadline.weight(.medium))
                if photo.developSettings.grainIntensityPct < 0.5 {
                    Text("develop.grain.intensity_zero_hint")
                        .font(.caption2)
                        .foregroundStyle(ZenithTheme.adjustmentOrange.opacity(0.9))
                }
                sliderReset(.grainSize, binding(\.grainSizePct, autoEnable: \.enableGrain), SoftRange.grainSize, defaultValue: 25)
                sliderReset(.grainIntensity, binding(\.grainIntensityPct, autoEnable: \.enableGrain), SoftRange.grainIntensity, defaultValue: 0)
                sliderReset(.grainRoughness, binding(\.grainRoughnessPct, autoEnable: \.enableGrain), SoftRange.grainRoughness, defaultValue: 45)
            }
            .id("grainNoiseCard")
        }
    }

    private func wheelColumn(
        title: LocalizedStringKey,
        hue: WritableKeyPath<DevelopSettings, Double>,
        sat: WritableKeyPath<DevelopSettings, Double>,
        resetHoverId: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if commandKeyHeld {
                    Button(String(localized: "develop.footer.reset")) {
                        resetFieldPair(hue: hue, sat: sat)
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(ZenithTheme.adjustmentOrange)
                }
            }
            DevelopColorWheelPair(hue: binding(hue, autoEnable: \.enableColorBalance), saturation: binding(sat, autoEnable: \.enableColorBalance))
                .frame(maxWidth: .infinity)
        }
        .developResetHoverTracking(id: resetHoverId, hoveredId: $hoveredResetToolID)
    }

    @ViewBuilder
    private var tslPerColorSlidersForSwatch: some View {
        let i = selectedTSLSwatch
        let tslColorNames: [LocalizedStringKey] = [
            "develop.tsl.red", "develop.tsl.orange", "develop.tsl.yellow", "develop.tsl.green",
            "develop.tsl.cyan", "develop.tsl.blue", "develop.tsl.violet", "develop.tsl.magenta"
        ]
        VStack(alignment: .leading, spacing: 10) {
            Text(tslColorNames[i])
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            DevelopGradientSliderRow(
                titleKey: "develop.tsl.hue",
                value: tslPerColorHueBinding(i),
                range: SoftRange.tslPerColor,
                gradientColors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple],
                commandKeyShowsReset: commandKeyHeld,
                onReset: { resetTool(id: HoverResetID.tslPCHue.rawValue) }
            )
            .developResetHoverTracking(id: HoverResetID.tslPCHue.rawValue, hoveredId: $hoveredResetToolID)

            DevelopGradientSliderRow(
                titleKey: "develop.tsl.saturation",
                value: tslPerColorSatBinding(i),
                range: SoftRange.tslPerColor,
                gradientColors: [.gray, swatchColors[i]],
                commandKeyShowsReset: commandKeyHeld,
                onReset: { resetTool(id: HoverResetID.tslPCSat.rawValue) }
            )
            .developResetHoverTracking(id: HoverResetID.tslPCSat.rawValue, hoveredId: $hoveredResetToolID)

            DevelopGradientSliderRow(
                titleKey: "develop.tsl.luminance",
                value: tslPerColorLumBinding(i),
                range: SoftRange.tslPerColor,
                gradientColors: [.black, .white],
                commandKeyShowsReset: commandKeyHeld,
                onReset: { resetTool(id: HoverResetID.tslPCLum.rawValue) }
            )
            .developResetHoverTracking(id: HoverResetID.tslPCLum.rawValue, hoveredId: $hoveredResetToolID)
        }
    }

    private func tslPerColorHueBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { photo.developSettings.tslPerColorPalette.channels[index].hue },
            set: { newValue in
                var s = photo.developSettings
                s.enableTSLPerColor = true
                var pal = s.tslPerColorPalette
                var ch = pal.channels[index]
                ch.hue = newValue
                pal.channels[index] = ch
                s.tslPerColorPalette = pal
                commit(s)
            }
        )
    }

    private func tslPerColorSatBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { photo.developSettings.tslPerColorPalette.channels[index].saturation },
            set: { newValue in
                var s = photo.developSettings
                s.enableTSLPerColor = true
                var pal = s.tslPerColorPalette
                var ch = pal.channels[index]
                ch.saturation = newValue
                pal.channels[index] = ch
                s.tslPerColorPalette = pal
                commit(s)
            }
        )
    }

    private func tslPerColorLumBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { photo.developSettings.tslPerColorPalette.channels[index].luminance },
            set: { newValue in
                var s = photo.developSettings
                s.enableTSLPerColor = true
                var pal = s.tslPerColorPalette
                var ch = pal.channels[index]
                ch.luminance = newValue
                pal.channels[index] = ch
                s.tslPerColorPalette = pal
                commit(s)
            }
        )
    }

    private func toneCurveBinding(forChannelTag tag: Int) -> Binding<ToneCurve> {
        Binding(
            get: {
                switch tag {
                case 0: return photo.developSettings.toneCurveMaster
                case 1: return photo.developSettings.toneCurveRed
                case 2: return photo.developSettings.toneCurveGreen
                default: return photo.developSettings.toneCurveBlue
                }
            },
            set: { newValue in
                var s = photo.developSettings
                s.enableCurves = true
                switch tag {
                case 0: s.toneCurveMaster = newValue
                case 1: s.toneCurveRed = newValue
                case 2: s.toneCurveGreen = newValue
                default: s.toneCurveBlue = newValue
                }
                commit(s)
            }
        )
    }

    private func binding(
        _ keyPath: WritableKeyPath<DevelopSettings, Double>,
        autoEnable: WritableKeyPath<DevelopSettings, Bool>? = nil
    ) -> Binding<Double> {
        Binding(
            get: { photo.developSettings[keyPath: keyPath] },
            set: { newValue in
                var s = photo.developSettings
                if let en = autoEnable {
                    s[keyPath: en] = true
                }
                s[keyPath: keyPath] = newValue
                commit(s)
            }
        )
    }

    private func localizedTitle(for id: HoverResetID) -> LocalizedStringKey {
        switch id {
        case .exposure: return "develop.exposure"
        case .contrast: return "develop.contrast"
        case .highlights: return "develop.basic.highlights"
        case .shadows: return "develop.basic.shadows"
        case .blackPoint: return "develop.basic.black_point"
        case .texture: return "develop.basic.texture"
        case .clarity: return "develop.clarity"
        case .bwRed: return "develop.bw.red"
        case .bwGreen: return "develop.bw.green"
        case .bwBlue: return "develop.bw.blue"
        case .bwTone: return "develop.bw.tone"
        case .bwIntensity: return "develop.bw.intensity"
        case .sharpAmount: return "develop.sharpness.amount"
        case .sharpRadius: return "develop.sharpness.radius"
        case .sharpDetail: return "develop.sharpness.detail"
        case .sharpMasking: return "develop.sharpness.masking"
        case .noiseLuma: return "develop.noise.luminance"
        case .noiseChroma: return "develop.noise.chrominance"
        case .grainSize: return "develop.grain.size"
        case .grainIntensity: return "develop.grain.intensity"
        case .grainRoughness: return "develop.grain.roughness"
        case .temperature, .tint, .tslHue, .tslSaturation, .tslPCHue, .tslPCSat, .tslPCLum,
             .cbHighlight, .cbMidtone, .cbShadow, .curvesChannel:
            return ""
        }
    }

    /// Curseur avec titre, réinitialisation (⌘ ou bouton si ⌘ maintenu) et survol pour ⌘ = .
    private func sliderReset(
        _ id: HoverResetID,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        displayPercent: Bool = true,
        defaultValue: Double = 0,
        accent: Color = ZenithTheme.adjustmentOrange
    ) -> some View {
        DevelopSliderRow(
            titleKey: localizedTitle(for: id),
            value: value,
            range: range,
            displayPercent: displayPercent,
            accent: accent,
            defaultValue: defaultValue,
            commandKeyShowsReset: commandKeyHeld,
            onReset: { resetTool(id: id.rawValue) }
        )
        .developResetHoverTracking(id: id.rawValue, hoveredId: $hoveredResetToolID)
    }
}
