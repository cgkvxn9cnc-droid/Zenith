//
//  PhotoEXIFFormatter.swift
//  Zenith
//

import Foundation
import ImageIO

/// Lecture minimale des propriétés EXIF pour la ligne « ISO · focale · ouverture · vitesse » (style Lightroom).
enum PhotoEXIFFormatter {
    struct Line {
        let iso: String?
        let focalLengthMM: String?
        let aperture: String?
        let shutter: String?
    }

    static func line(from url: URL) -> Line? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]

        let iso = isoString(from: exif)
        let focal = focalLengthString(from: exif)
        let fNumber = apertureString(from: exif)
        let shutter = shutterString(from: exif)

        if iso == nil, focal == nil, fNumber == nil, shutter == nil { return nil }
        return Line(iso: iso, focalLengthMM: focal, aperture: fNumber, shutter: shutter)
    }

    private static func isoString(from exif: [CFString: Any]?) -> String? {
        if let arr = exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let first = arr.first {
            return first.stringValue
        }
        if let arr = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = arr.first {
            return "\(first)"
        }
        if let n = exif?[kCGImagePropertyExifISOSpeedRatings] as? NSNumber {
            return n.stringValue
        }
        return nil
    }

    private static func focalLengthString(from exif: [CFString: Any]?) -> String? {
        guard let exif else { return nil }
        if let n = exif[kCGImagePropertyExifFocalLength] as? NSNumber {
            return formatNumber(n.doubleValue, maxDecimals: 0)
        }
        if let n = exif[kCGImagePropertyExifFocalLength] as? Double {
            return formatNumber(n, maxDecimals: 0)
        }
        return nil
    }

    private static func apertureString(from exif: [CFString: Any]?) -> String? {
        guard let exif else { return nil }
        if let n = exif[kCGImagePropertyExifFNumber] as? NSNumber {
            return formatNumber(n.doubleValue, maxDecimals: 1)
        }
        if let n = exif[kCGImagePropertyExifFNumber] as? Double {
            return formatNumber(n, maxDecimals: 1)
        }
        return nil
    }

    private static func shutterString(from exif: [CFString: Any]?) -> String? {
        guard let exif else { return nil }
        let sec: Double? = {
            if let n = exif[kCGImagePropertyExifExposureTime] as? NSNumber { return n.doubleValue }
            if let n = exif[kCGImagePropertyExifExposureTime] as? Double { return n }
            return nil
        }()
        guard let sec, sec > 0 else { return nil }
        if sec >= 1 {
            let s = formatNumber(sec, maxDecimals: 1)
            return "\(s) s"
        }
        let inv = 1.0 / sec
        let denom = max(1, Int(inv.rounded()))
        return "1/\(denom) s"
    }

    private static func formatNumber(_ value: Double, maxDecimals: Int) -> String {
        if maxDecimals == 0 { return "\(Int(value.rounded()))" }
        let t = pow(10.0, Double(maxDecimals))
        let r = (value * t).rounded() / t
        if abs(r - Double(Int(r))) < 0.000_1 { return "\(Int(r))" }
        return String(format: "%.\(maxDecimals)f", r)
    }
}
