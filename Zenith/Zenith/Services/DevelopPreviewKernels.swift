//
//  DevelopPreviewKernels.swift
//  Zenith
//

import CoreImage
import Foundation

/// Kernels Core Image optionnels : magnitude Sobel (netteté), pondération tons moyens (grain), balance trois tons.
nonisolated enum DevelopPreviewKernels {

    /// Exposition scene-referred : gain EV en lumière linéaire, puis rolloff doux des hautes lumières.
    ///
    /// Le tone mapping se fait sur la luminance et ré-applique un ratio aux canaux RGB pour préserver la teinte.
    static let sceneExposureWithShoulder: CIColorKernel? = {
        let src = """
        kernel vec4 sceneExposureWithShoulder(__sample s, float ev) {
            vec3 rgb = max(s.rgb, vec3(0.0));
            float gain = pow(2.0, ev);
            float y0 = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
            float y1 = y0 * gain;

            float shoulderStart = 0.82;
            float shoulder = shoulderStart + (1.0 - shoulderStart) *
                (1.0 - exp(-max(0.0, y1 - shoulderStart) / (1.0 - shoulderStart) * 0.92));
            float yMapped = mix(y1, shoulder, smoothstep(shoulderStart, 1.8, y1));

            float ratio = y0 > 1.0e-5 ? yMapped / y0 : gain;
            return vec4(max(rgb * ratio, vec3(0.0)), s.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// Contraste en courbe S autour d'un pivot image-dépendant, appliqué en luminance pour limiter les dérives de couleur.
    static let linearLuminanceContrast: CIColorKernel? = {
        let src = """
        kernel vec4 linearLuminanceContrast(__sample s, float amount, float midpoint) {
            vec3 rgb = max(s.rgb, vec3(0.0));
            float y0 = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
            float c = clamp(amount / 100.0, -1.0, 1.0);
            float t = y0 - midpoint;
            float norm = t >= 0.0
                ? t / max(1.0e-4, 1.0 - midpoint)
                : t / max(1.0e-4, midpoint);
            float shaped = t * (1.0 + c * 0.82 * (1.0 - norm * norm));
            float y1 = clamp(midpoint + shaped, 0.0, 4.0);
            float ratio = y0 > 1.0e-5 ? y1 / y0 : 1.0;
            return vec4(max(rgb * ratio, vec3(0.0)), s.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// Magnitude √(H²+V²) à partir d’une image « packée » : **R** = gradient Sobel horizontal centré (bias 0,5), **G** = vertical.
    static let sobelMagnitudePacked: CIColorKernel? = {
        let src = """
        kernel vec4 sobelMagnitudePacked(__sample s) {
            float dh = s.r - 0.5;
            float dv = s.g - 0.5;
            float mag = sqrt(dh * dh + dv * dv);
            float o = clamp(mag * 3.85, 0.0, 1.0);
            return vec4(o, o, o, s.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// Visibilité du grain plus forte vers les tons moyens (faible vers ombres et hautes lumières).
    static let grainMidtoneVisibility: CIColorKernel? = {
        let src = """
        kernel vec4 grainMidtoneVisibility(__sample y) {
            float v = clamp(y.r, 0.0, 1.0);
            float w = 4.0 * v * (1.0 - v);
            return vec4(w, w, w, y.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    nonisolated static func applyGrainMidtoneVisibility(to luminanceGray: CIImage, extent: CGRect) -> CIImage {
        guard let kernel = grainMidtoneVisibility else {
            return CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        }
        return kernel.apply(extent: extent, roiCallback: { _, r in r }, arguments: [luminanceGray]) ?? luminanceGray
    }

    nonisolated static func applySobelMagnitudePacked(to packedHG: CIImage, extent: CGRect) -> CIImage {
        guard let kernel = sobelMagnitudePacked else { return packedHG }
        return kernel.apply(extent: extent, roiCallback: { _, r in r }, arguments: [packedHG]) ?? packedHG
    }

    /// Balance « trois tons » en Oklab : pondération par luminance perceptuelle (ombres / tons moyens / hautes lumières).
    static let colorBalanceThreeWay: CIColorKernel? = {
        let src = """
        vec3 linearToOklab(vec3 c) {
            c = max(c, vec3(0.0));
            float l = pow(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b, 1.0 / 3.0);
            float m = pow(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b, 1.0 / 3.0);
            float s = pow(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b, 1.0 / 3.0);
            return vec3(
                0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            );
        }

        vec3 oklabToLinear(vec3 lab) {
            float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
            float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
            float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
            float l = l_ * l_ * l_;
            float m = m_ * m_ * m_;
            float s = s_ * s_ * s_;
            return vec3(
                 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
            );
        }

        vec2 hueSatToOklabDelta(float hueDeg, float sat) {
            float angle = hueDeg * 0.017453292519943295;
            float chroma = clamp(sat / 100.0, -1.0, 1.0) * 0.045;
            return vec2(cos(angle) * chroma, sin(angle) * chroma);
        }

        kernel vec4 colorBalanceThreeWay(__sample s,
            float shadowHue, float midHue, float highHue,
            float shadowSat, float midSat, float highSat) {
            vec3 lab = linearToOklab(s.rgb);
            float L = clamp(lab.x, 0.0, 1.0);
            float wS = pow(max(0.0, 1.0 - smoothstep(0.08, 0.52, L)), 1.25);
            float wH = pow(max(0.0, smoothstep(0.48, 0.92, L)), 1.25);
            float wM = max(0.0, 1.0 - abs(L - 0.5) * 2.0);
            wM *= wM;
            float sum = wS + wM + wH;
            wS /= sum;
            wM /= sum;
            wH /= sum;

            vec2 shadow = hueSatToOklabDelta(shadowHue, shadowSat);
            vec2 mid = hueSatToOklabDelta(midHue, midSat);
            vec2 high = hueSatToOklabDelta(highHue, highSat);
            lab.yz += shadow * wS + mid * wM + high * wH;

            return vec4(max(oklabToLinear(lab), vec3(0.0)), s.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// Ajustements TSL (HSL Lightroom) par bande de teinte, avec transitions douces.
    ///
    /// - `targetHue01` : teinte cible ∈ [0,1] (0 = rouge, 1 = rouge).
    /// - `halfWidth01` : demi-largeur angulaire de la bande en unités [0,1] (ex. 0.08 ≈ 28,8°).
    /// - `minSat` / `maxSat` : protège les gris / quasi-gris (poids 0 en-dessous de minSat).
    /// - Shifts :
    ///   - hueShift01 : décalage de teinte en fraction de tour (ex. 0.05 = 18°)
    ///   - satScale : multiplicateur de saturation (1 = neutre)
    ///   - valScale : multiplicateur de valeur (1 = neutre)
    static let tslBandAdjust: CIColorKernel? = {
        let src = """
        vec3 rgb2hsv(vec3 c) {
            vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
            vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
            vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
            float d = q.x - min(q.w, q.y);
            float e = 1.0e-10;
            float v = q.x;
            float s = d / (q.x + e);
            float h = abs(q.z + (q.w - q.y) / (6.0 * d + e));
            return vec3(h, s, v);
        }

        vec3 hsv2rgb(vec3 hsv) {
            vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
            vec3 p = abs(fract(hsv.xxx + K.xyz) * 6.0 - K.www);
            return hsv.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), hsv.y);
        }

        float hueDistance01(float h, float target) {
            float d = abs(h - target);
            return min(d, 1.0 - d);
        }

        float smoothstep01(float e0, float e1, float x) {
            float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0);
            return t * t * (3.0 - 2.0 * t);
        }

        kernel vec4 tslBandAdjust(
            __sample s,
            float targetHue01,
            float halfWidth01,
            float minSat,
            float maxSat,
            float hueShift01,
            float satScale,
            float valScale
        ) {
            vec3 rgb = clamp(s.rgb, vec3(0.0), vec3(1.0));
            vec3 hsv = rgb2hsv(rgb);

            float d = hueDistance01(hsv.x, targetHue01);
            float sigma = max(1.0e-4, halfWidth01 * 0.72);
            float wHue = exp(-0.5 * (d / sigma) * (d / sigma));
            float wSat = smoothstep01(minSat, maxSat, hsv.y);
            float w = clamp(wHue * wSat, 0.0, 1.0);

            vec3 hsv2 = hsv;
            hsv2.x = fract(hsv2.x + hueShift01 + 1000.0);
            hsv2.y = clamp(hsv2.y * satScale, 0.0, 1.0);
            hsv2.z = clamp(hsv2.z * valScale, 0.0, 1.0);

            vec3 outRgb = mix(rgb, hsv2rgb(hsv2), w);
            return vec4(outRgb, s.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    nonisolated static func applySceneExposureWithShoulder(to image: CIImage, extent: CGRect, ev: Double) -> CIImage {
        guard let kernel = sceneExposureWithShoulder, ev != 0 else { return image }
        return kernel.apply(
            extent: extent,
            roiCallback: { _, r in r },
            arguments: [image, NSNumber(value: ev)]
        ) ?? image
    }

    nonisolated static func applyLinearLuminanceContrast(
        to image: CIImage,
        extent: CGRect,
        amount: Double,
        midpoint: Double
    ) -> CIImage {
        guard let kernel = linearLuminanceContrast, amount != 0 else { return image }
        return kernel.apply(
            extent: extent,
            roiCallback: { _, r in r },
            arguments: [image, NSNumber(value: amount), NSNumber(value: midpoint)]
        ) ?? image
    }

    nonisolated static func applyColorBalanceThreeWay(
        to image: CIImage,
        extent: CGRect,
        shadowHue: Double,
        midHue: Double,
        highHue: Double,
        shadowSat: Double,
        midSat: Double,
        highSat: Double
    ) -> CIImage {
        guard let kernel = colorBalanceThreeWay else { return image }
        if shadowHue == 0, midHue == 0, highHue == 0,
           shadowSat == 0, midSat == 0, highSat == 0 {
            return image
        }
        let args: [Any] = [
            image,
            NSNumber(value: shadowHue),
            NSNumber(value: midHue),
            NSNumber(value: highHue),
            NSNumber(value: shadowSat),
            NSNumber(value: midSat),
            NSNumber(value: highSat)
        ]
        return kernel.apply(extent: extent, roiCallback: { _, r in r }, arguments: args) ?? image
    }

    nonisolated static func applyTSLBandAdjust(
        to image: CIImage,
        extent: CGRect,
        targetHueDeg: Double,
        hueShift: Double,
        satShift: Double,
        lumShift: Double
    ) -> CIImage {
        guard let kernel = tslBandAdjust else { return image }
        if hueShift == 0, satShift == 0, lumShift == 0 { return image }

        // 8 bandes ~45° → demi-largeur ~22,5° ; on élargit un peu pour éviter des "trous".
        let halfWidth01 = 24.0 / 360.0

        // Protection des quasi-gris : en-dessous de 2 % de sat, on n'applique rien.
        let minSat = 0.02
        let maxSat = 0.10

        // Mapping sliders (−100…100) → paramètres per-pixel.
        // Hue: max ≈ 27° (calé sur l’ancienne amplitude CIHueAdjust utilisée ici).
        let hueShift01 = (hueShift / 100.0) * (27.0 / 360.0)
        // Saturation: multiplicateur doux (évite les explosions de chroma).
        let satScale = max(0.0, 1.0 + (satShift / 100.0) * 0.6)
        // Luminance (HSV value): multiplicateur modéré.
        let valScale = max(0.0, 1.0 + (lumShift / 100.0) * 0.45)

        let targetHue01 = (targetHueDeg.truncatingRemainder(dividingBy: 360.0)) / 360.0

        let args: [Any] = [
            image,
            NSNumber(value: targetHue01),
            NSNumber(value: halfWidth01),
            NSNumber(value: minSat),
            NSNumber(value: maxSat),
            NSNumber(value: hueShift01),
            NSNumber(value: satScale),
            NSNumber(value: valScale)
        ]

        return kernel.apply(extent: extent, roiCallback: { _, r in r }, arguments: args) ?? image
    }

    // MARK: - Clarté / Texture (séparation fréquentielle, espace linéaire)

    /// Contraste local sur **fréquences moyennes** : `orig + (orig − flou_large) × gain × masque(luminance)`.
    /// Masque type Lightroom : atténuation vers ombres / hautes lumières pour limiter les halos.
    static let clarityMidFrequency: CIColorKernel? = {
        let src = """
        kernel vec4 clarityMidFrequency(__sample orig, __sample blurred, float gain) {
            vec3 W = vec3(0.2126, 0.7152, 0.0722);
            vec3 mid = orig.rgb - blurred.rgb;
            float y = dot(max(orig.rgb, vec3(0.0)), W);
            float yr = y / (1.0 + max(y, 1.0e-6));
            float a = clamp(abs(yr * 2.0 - 1.0), 0.0, 1.0);
            float m = clamp(1.0 - pow(a, 2.1), 0.0, 1.0);
            return vec4(orig.rgb + mid * (gain * m), orig.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    /// **Hautes fréquences** fines : différence sur petit flou, boost sur la **luminance** du détail seulement,
    /// avec masque d’arête (gradient) pour réduire les artefacts sur les contours durs.
    static let textureHighFrequencyLuma: CIColorKernel? = {
        let src = """
        kernel vec4 textureHighFrequencyLuma(__sample base, __sample lowSmall, __sample edgeStr, float texGain) {
            vec3 W = vec3(0.2126, 0.7152, 0.0722);
            vec3 mid = base.rgb - lowSmall.rgb;
            float lh = dot(mid, W);
            float e = clamp(dot(edgeStr.rgb, vec3(0.33333)), 0.0, 1.0);
            float tMask = 1.0 - smoothstep(0.05, 0.48, e);
            vec3 delta = vec3(lh) * (texGain * tMask);
            return vec4(base.rgb + delta, base.a);
        }
        """
        return CIColorKernel(source: src)
    }()

    nonisolated static func applyClarityMidFrequency(
        orig: CIImage,
        blurred: CIImage,
        extent: CGRect,
        amountSigned100: Double
    ) -> CIImage {
        guard let kernel = clarityMidFrequency, abs(amountSigned100) > 1.0e-6 else { return orig }
        // Amplitude calibrée pour être lisible en RGBAh linéaire après `softenSigned100` (~0,65× à ±100).
        let g = Float(amountSigned100 / 100.0 * 1.72)
        return kernel.apply(
            extent: extent,
            roiCallback: { _, r in r },
            arguments: [orig, blurred, NSNumber(value: g)]
        ) ?? orig
    }

    nonisolated static func applyTextureHighFrequencyLuma(
        base: CIImage,
        lowSmall: CIImage,
        edgeStrength01: CIImage,
        extent: CGRect,
        amountSigned100: Double
    ) -> CIImage {
        guard let kernel = textureHighFrequencyLuma, abs(amountSigned100) > 1.0e-6 else { return base }
        let g = Float(amountSigned100 / 100.0 * 2.05)
        return kernel.apply(
            extent: extent,
            roiCallback: { _, r in r },
            arguments: [base, lowSmall, edgeStrength01, NSNumber(value: g)]
        ) ?? base
    }
}
