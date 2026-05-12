//
//  ZenithTests.swift
//  ZenithTests
//
//  Created by Romain Cobigo on 02/05/2026.
//

import Foundation
import Testing
@testable import Zenith

struct ZenithTests {

    @Test func developSettingsRoundtrip() throws {
        var s = DevelopSettings.neutral
        s.exposureEV = 0.5
        s.saturation = 12
        s.brightness = 4
        s.tslHue = -7
        s.tslSaturation = 3
        s.tslLuminance = -2
        s.maskRadialBlend = 18
        s.toneCurveMaster = ToneCurve(points: [
            ToneCurvePoint(x: 0, y: 0),
            ToneCurvePoint(x: 0.5, y: 0.62),
            ToneCurvePoint(x: 1, y: 1)
        ])
        let data = try s.encoded()
        let decoded = DevelopSettings.decode(from: data)
        #expect(decoded.exposureEV == 0.5)
        #expect(decoded.saturation == 12)
        #expect(decoded.brightness == 4)
        #expect(decoded.tslHue == -7)
        #expect(decoded.tslSaturation == 3)
        #expect(decoded.tslLuminance == -2)
        #expect(decoded.maskRadialBlend == 18)
        #expect(decoded.toneCurveMaster.normalized().points.count == 3)
        #expect(abs(decoded.toneCurveMaster.normalized().points[1].y - 0.62) < 0.001)
    }

    @Test func developSettingsMigratesLegacyCurveIntensities() throws {
        let json = #"{"curvesMasterIntensity":40,"curvesRedIntensity":-30}"#
        let data = Data(json.utf8)
        let decoded = DevelopSettings.decode(from: data)
        #expect(decoded.toneCurveMaster.isEffectivelyIdentity(epsilon: 0.08) == false)
        #expect(decoded.toneCurveRed.isEffectivelyIdentity(epsilon: 0.08) == false)
        #expect(decoded.toneCurveGreen.isEffectivelyIdentity())
        #expect(decoded.toneCurveBlue.isEffectivelyIdentity())
    }

    @Test func toneCurveInterpolationIsMonotonicOnIncreasingControlPoints() {
        let c = ToneCurve(points: [
            ToneCurvePoint(x: 0, y: 0),
            ToneCurvePoint(x: 0.35, y: 0.15),
            ToneCurvePoint(x: 0.65, y: 0.85),
            ToneCurvePoint(x: 1, y: 1)
        ]).normalized()
        let lut = ToneCurveInterpolation.sampleMonotoneYC(c, sampleCount: 64)
        #expect(lut.count == 64)
        for v in lut {
            #expect(v >= 0 && v <= 1)
        }
        for i in 1 ..< lut.count {
            #expect(lut[i] >= lut[i - 1] - 1e-6)
        }
    }

    @Test func blackWhiteChannelWeightsSumToOneAndMatchRec709WhenNeutral() {
        let w0 = DevelopPipelineColorMath.blackWhiteChannelWeights(bwRed: 0, bwGreen: 0, bwBlue: 0)
        let sum = w0.wr + w0.wg + w0.wb
        #expect(abs(sum - 1.0) < 1e-9)
        #expect(abs(w0.wr - 0.2126) < 1e-9)
        #expect(abs(w0.wg - 0.7152) < 1e-9)
        #expect(abs(w0.wb - 0.0722) < 1e-9)

        let w1 = DevelopPipelineColorMath.blackWhiteChannelWeights(bwRed: 100, bwGreen: 0, bwBlue: 0)
        #expect(w1.wr > w0.wr)
        #expect(abs(w1.wr + w1.wg + w1.wb - 1.0) < 1e-9)
    }

    @Test func rgbLevelsPerceptualLUTIsMonotoneAndBracketed() {
        let lut = DevelopPipelineColorMath.rgbLevelsPerceptualLUT(
            inputBlackPct: 0,
            inputWhitePct: 100,
            midtonePct: 50,
            sampleCount: 64
        )
        #expect(lut.count == 64)
        #expect(lut.first! >= 0 && lut.last! <= 1)
        for i in 1 ..< lut.count {
            #expect(lut[i] >= lut[i - 1] - 1e-6)
        }
    }

    @Test func toneCurveStableLUTCacheHashIsDeterministic() {
        let c = ToneCurve(points: [
            ToneCurvePoint(x: 0, y: 0),
            ToneCurvePoint(x: 0.4, y: 0.25),
            ToneCurvePoint(x: 1, y: 1)
        ])
        #expect(c.stableLUTCacheHash() == c.stableLUTCacheHash())
    }

    @Test func toneCurveLUTCacheReturnsConsistentBundle() {
        ToneCurveLUTCache.clearForTesting()
        let m = ToneCurve.identity
        let r = ToneCurve(points: [ToneCurvePoint(x: 0, y: 0), ToneCurvePoint(x: 0.5, y: 0.4), ToneCurvePoint(x: 1, y: 1)])
        let b1 = ToneCurveLUTCache.lutBundle(master: m, red: r, green: m, blue: m, sampleCount: 128)
        let b2 = ToneCurveLUTCache.lutBundle(master: m, red: r, green: m, blue: m, sampleCount: 128)
        #expect(b1.master == nil)
        #expect(b1.red != nil)
        #expect(b1.red == b2.red)
        ToneCurveLUTCache.clearForTesting()
    }
}
