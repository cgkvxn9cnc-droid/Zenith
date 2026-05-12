//
//  DevelopPipelineQuality.swift
//  Zenith
//
//  Qualité du pipeline développement : preview proxy / vignette contre rendu plein ou export.

import Foundation

/// `.fast` : LUT courbes réduites, rayons netteté amortis pour les très petites cibles GPU.
nonisolated enum DevelopPipelineQuality: Sendable {
    case fast
    case high

    var curveLUTSampleCount: Int {
        switch self {
        case .fast: return 128
        case .high: return 256
        }
    }
}
