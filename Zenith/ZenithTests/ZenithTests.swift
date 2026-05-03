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
        let data = try s.encoded()
        let decoded = DevelopSettings.decode(from: data)
        #expect(decoded.exposureEV == 0.5)
        #expect(decoded.saturation == 12)
        #expect(decoded.brightness == 4)
        #expect(decoded.tslHue == -7)
        #expect(decoded.tslSaturation == 3)
        #expect(decoded.tslLuminance == -2)
        #expect(decoded.maskRadialBlend == 18)
    }
}
