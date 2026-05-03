//
//  DevelopPanel.swift
//  Zenith
//

import SwiftData
import SwiftUI

struct DevelopPanel: View {
    @Bindable var photo: PhotoRecord
    @Environment(\.modelContext) private var modelContext
    @Binding var compareOriginal: Bool

    @State private var selectedSelectiveSwatch = 0
    @State private var colorBalanceMode = 0
    @State private var levelsChannel = 0
    @State private var curvesChannel = 0

    private let swatchColors: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("develop.pixelmator.panel_title")
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DevelopAdjustmentCard(
                        titleKey: "develop.card.white_balance",
                        isOn: boolBinding(\.enableWhiteBalance)
                    ) {
                        DevelopGradientSliderRow(
                            titleKey: "develop.slider.temperature",
                            value: binding(\.temperature),
                            range: -100 ... 100,
                            gradientColors: [.blue, .cyan, .white, .yellow, .orange]
                        )
                        DevelopGradientSliderRow(
                            titleKey: "develop.slider.tint",
                            value: binding(\.tint),
                            range: -100 ... 100,
                            gradientColors: [.green, .gray, .purple]
                        )
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.basic",
                        isOn: boolBinding(\.enableBasicAdjustments)
                    ) {
                        DevelopSliderRow(
                            titleKey: "develop.exposure",
                            value: binding(\.exposureEV),
                            range: -4 ... 4,
                            displayPercent: false
                        )
                        DevelopSliderRow(titleKey: "develop.basic.highlights", value: binding(\.highlights), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.basic.shadows", value: binding(\.shadows), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.brightness", value: binding(\.brightness), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.contrast", value: binding(\.contrast), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.basic.black_point", value: binding(\.blackPoint), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.basic.texture", value: binding(\.texture), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.clarity", value: binding(\.clarity), range: -100 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.hue_sat",
                        isOn: boolBinding(\.enableHueSaturation),
                        showMagicWand: true,
                        magicWandAction: { }
                    ) {
                        DevelopGradientSliderRow(
                            titleKey: "develop.hue",
                            value: binding(\.tslHue),
                            range: -100 ... 100,
                            gradientColors: [
                                .red, .orange, .yellow, .green, .cyan, .blue, .purple, .red
                            ]
                        )
                        DevelopGradientSliderRow(
                            titleKey: "develop.saturation",
                            value: binding(\.tslSaturation),
                            range: -100 ... 100,
                            gradientColors: [.gray, .red]
                        )
                        DevelopGradientSliderRow(
                            titleKey: "develop.slider.brilliance",
                            value: binding(\.tslLuminance),
                            range: -100 ... 100,
                            gradientColors: [.black, .white]
                        )
                        DevelopSliderRow(titleKey: "develop.global_saturation", value: binding(\.saturation), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.vibrance", value: binding(\.vibrance), range: -100 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.selective_clarity",
                        isOn: boolBinding(\.enableSelectiveClarity)
                    ) {
                        Picker("", selection: intBinding(\.selectiveClarityTone)) {
                            Text("develop.tone.shadow").tag(0)
                            Text("develop.tone.mid").tag(1)
                            Text("develop.tone.highlight").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text("develop.selective_clarity.hint")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.selective_color",
                        isOn: boolBinding(\.enableSelectiveColor),
                        showMagicWand: true,
                        magicWandAction: { }
                    ) {
                        DevelopHistogramPlaceholder()
                            .padding(.bottom, 6)
                        HStack(spacing: 8) {
                            ForEach(0 ..< 8, id: \.self) { i in
                                Button {
                                    selectedSelectiveSwatch = i
                                } label: {
                                    Circle()
                                        .fill(swatchColors[i])
                                        .frame(width: 22, height: 22)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    selectedSelectiveSwatch == i
                                                        ? ZenithTheme.adjustmentOrange
                                                        : Color.clear,
                                                    lineWidth: 3
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        selectiveSlidersForSwatch
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.color_balance",
                        isOn: boolBinding(\.enableColorBalance),
                        showMagicWand: true,
                        magicWandAction: { }
                    ) {
                        Picker("", selection: $colorBalanceMode) {
                            Text("develop.cb.mode_3way").tag(0)
                        }
                        .labelsHidden()

                        HStack(alignment: .top, spacing: 8) {
                            wheelColumn(title: "develop.cb.highlight", hue: \.cbHighlightHue, sat: \.cbHighlightSaturation)
                            wheelColumn(title: "develop.cb.midtone", hue: \.cbMidtoneHue, sat: \.cbMidtoneSaturation)
                            wheelColumn(title: "develop.cb.shadow", hue: \.cbShadowHue, sat: \.cbShadowSaturation)
                        }
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.levels",
                        isOn: boolBinding(\.enableLevels)
                    ) {
                        HStack {
                            Picker("", selection: $levelsChannel) {
                                Text("develop.channel.rgb").tag(0)
                            }
                            .pickerStyle(.menu)
                            Spacer()
                            Image(systemName: "eyedropper")
                                .foregroundStyle(.secondary)
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        DevelopHistogramPlaceholder()
                            .frame(height: 56)
                        DevelopSliderRow(titleKey: "develop.levels.black", value: binding(\.levelsInputBlack), range: 0 ... 100)
                        DevelopSliderRow(titleKey: "develop.levels.white", value: binding(\.levelsInputWhite), range: 0 ... 100)
                        DevelopSliderRow(titleKey: "develop.levels.midtone", value: binding(\.levelsMidtone), range: 0 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.curves",
                        isOn: boolBinding(\.enableCurves)
                    ) {
                        HStack {
                            Picker("", selection: $curvesChannel) {
                                Text("develop.channel.rgb").tag(0)
                            }
                            .pickerStyle(.menu)
                            Spacer()
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        DevelopCurvesPreview(intensity: photo.developSettings.curvesMasterIntensity)
                        DevelopSliderRow(
                            titleKey: "develop.curves.master",
                            value: binding(\.curvesMasterIntensity),
                            range: -100 ... 100
                        )
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.remove_color",
                        isOn: boolBinding(\.enableRemoveColor)
                    ) {
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green)
                                .frame(width: 44, height: 28)
                            Image(systemName: "eyedropper")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        DevelopSliderRow(titleKey: "develop.remove.range", value: binding(\.removeColorRange), range: 0 ... 100)
                        DevelopSliderRow(titleKey: "develop.remove.luma", value: binding(\.removeColorLumaRange), range: 0 ... 100)
                        DevelopSliderRow(titleKey: "develop.remove.intensity", value: binding(\.removeColorIntensity), range: 0 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.black_white",
                        isOn: boolBinding(\.enableBlackWhite)
                    ) {
                        DevelopSliderRow(titleKey: "develop.bw.red", value: binding(\.bwRed), range: -100 ... 100, accent: .red)
                        DevelopSliderRow(titleKey: "develop.bw.green", value: binding(\.bwGreen), range: -100 ... 100, accent: .green)
                        DevelopSliderRow(titleKey: "develop.bw.blue", value: binding(\.bwBlue), range: -100 ... 100, accent: .blue)
                        DevelopSliderRow(titleKey: "develop.bw.tone", value: binding(\.bwTone), range: -100 ... 100, accent: .gray)
                        DevelopSliderRow(titleKey: "develop.bw.intensity", value: binding(\.bwIntensity), range: 0 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.lut",
                        isOn: boolBinding(\.enableLUT)
                    ) {
                        HStack {
                            Picker("", selection: intBinding(\.lutPresetIndex)) {
                                Text("develop.lut.none").tag(0)
                                Text("develop.lut.cinematic").tag(1)
                                Text("develop.lut.warm").tag(2)
                                Text("develop.lut.cool").tag(3)
                            }
                            .pickerStyle(.menu)
                            Spacer()
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        DevelopSliderRow(titleKey: "develop.lut.intensity", value: binding(\.lutMix), range: 0 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.vignette",
                        isOn: boolBinding(\.enableVignetting)
                    ) {
                        DevelopSliderRow(
                            titleKey: "develop.vignette.exposure",
                            value: binding(\.vignetteExposureAmount),
                            range: 0 ... 100
                        )
                        DevelopSliderRow(
                            titleKey: "develop.vignette.black_point",
                            value: binding(\.vignetteBlackPointAmount),
                            range: -100 ... 100
                        )
                        DevelopSliderRow(
                            titleKey: "develop.vignette.softness",
                            value: binding(\.vignetteSoftnessAmount),
                            range: 0 ... 100
                        )
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.sharpness",
                        isOn: boolBinding(\.enableSharpness)
                    ) {
                        DevelopSliderRow(
                            titleKey: "develop.sharpness.radius",
                            value: binding(\.sharpnessRadiusPx),
                            range: 0.1 ... 20,
                            displayPercent: false
                        )
                        DevelopSliderRow(titleKey: "develop.sharpness.amount", value: binding(\.sharpnessAmountPct), range: 0 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.grain",
                        isOn: boolBinding(\.enableGrain)
                    ) {
                        DevelopSliderRow(titleKey: "develop.grain.size", value: binding(\.grainSizePct), range: 0 ... 100)
                        DevelopSliderRow(titleKey: "develop.grain.intensity", value: binding(\.grainIntensityPct), range: 0 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.lens",
                        isOn: boolBinding(\.enableLensCorrection)
                    ) {
                        DevelopSliderRow(titleKey: "develop.lens", value: binding(\.lensCorrection), range: -100 ... 100)
                        DevelopSliderRow(titleKey: "develop.ca", value: binding(\.chromaticAberration), range: -100 ... 100)
                    }

                    DevelopAdjustmentCard(
                        titleKey: "develop.card.masks",
                        isOn: boolBinding(\.enableMasks)
                    ) {
                        DevelopSliderRow(titleKey: "develop.mask_radial", value: binding(\.maskRadialBlend), range: -100 ... 100)
                    }

                    DevelopPanelFooter(compareOriginal: $compareOriginal) {
                        photo.resetDevelopToNeutral()
                        try? modelContext.save()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.vertical, 10)
        .background(Color.clear)
    }

    private func wheelColumn(
        title: LocalizedStringKey,
        hue: WritableKeyPath<DevelopSettings, Double>,
        sat: WritableKeyPath<DevelopSettings, Double>
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            DevelopColorWheelPair(hue: binding(hue), saturation: binding(sat))
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var selectiveSlidersForSwatch: some View {
        let i = selectedSelectiveSwatch
        VStack(alignment: .leading, spacing: 10) {
            DevelopGradientSliderRow(
                titleKey: "develop.selective.hue",
                value: selectiveHueBinding(i),
                range: -100 ... 100,
                gradientColors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple]
            )
            DevelopGradientSliderRow(
                titleKey: "develop.selective.sat",
                value: selectiveSatBinding(i),
                range: -100 ... 100,
                gradientColors: [.gray, swatchColors[i]]
            )
            DevelopGradientSliderRow(
                titleKey: "develop.selective.lum",
                value: selectiveLumBinding(i),
                range: -100 ... 100,
                gradientColors: [.black, .white]
            )
        }
    }

    private func selectiveHueBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { photo.developSettings.selectivePalette.channels[index].hue },
            set: { newValue in
                var s = photo.developSettings
                var pal = s.selectivePalette
                var ch = pal.channels[index]
                ch.hue = newValue
                pal.channels[index] = ch
                s.selectivePalette = pal
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func selectiveSatBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { photo.developSettings.selectivePalette.channels[index].saturation },
            set: { newValue in
                var s = photo.developSettings
                var pal = s.selectivePalette
                var ch = pal.channels[index]
                ch.saturation = newValue
                pal.channels[index] = ch
                s.selectivePalette = pal
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func selectiveLumBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { photo.developSettings.selectivePalette.channels[index].luminance },
            set: { newValue in
                var s = photo.developSettings
                var pal = s.selectivePalette
                var ch = pal.channels[index]
                ch.luminance = newValue
                pal.channels[index] = ch
                s.selectivePalette = pal
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<DevelopSettings, Double>) -> Binding<Double> {
        Binding(
            get: { photo.developSettings[keyPath: keyPath] },
            set: { newValue in
                var s = photo.developSettings
                s[keyPath: keyPath] = newValue
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DevelopSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { photo.developSettings[keyPath: keyPath] },
            set: { newValue in
                var s = photo.developSettings
                s[keyPath: keyPath] = newValue
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<DevelopSettings, Int>) -> Binding<Int> {
        Binding(
            get: { photo.developSettings[keyPath: keyPath] },
            set: { newValue in
                var s = photo.developSettings
                s[keyPath: keyPath] = newValue
                photo.applyDevelopSettings(s)
                try? modelContext.save()
            }
        )
    }
}
