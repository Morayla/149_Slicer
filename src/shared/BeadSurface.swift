import SceneKit

// UV.x traverses a bead section; UV.y is the flat half-span in units of half a layer height.
// The stadium's semicircular sides are evaluated per pixel, without subdividing the mesh.
enum BeadSurface {
    private static let white: CGImage = CGImage(
        width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data([255, 255, 255, 255]) as CFData)!, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent)!
    static func material(geometricProfile: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.multiply.contents = NSColor(white: 0.78, alpha: 1)
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.72
        material.metalness.contents = 0
        material.isDoubleSided = true
        attach(to: material)
        if geometricProfile { material.shaderModifiers?.removeValue(forKey: .surface) }
        material.multiply.contents = NSColor(white: 0.78, alpha: 1)
        return material
    }
    static func attach(to material: SCNMaterial) {
        if let color = material.diffuse.contents as? NSColor { material.multiply.contents = color }
        material.diffuse.contents = white
        var modifiers = material.shaderModifiers ?? [:]
        modifiers[.surface] = surface
        material.shaderModifiers = modifiers
    }
    static let surface = """
        #pragma body
        float2 beadUV = _surface.diffuseTexcoord;
        float3 beadN = normalize(_surface.normal);
        float3 beadDX = dfdx(_surface.position);
        float3 beadDY = dfdy(_surface.position);
        float3 beadR1 = cross(beadDY, beadN);
        float3 beadR2 = cross(beadN, beadDX);
        float beadDet = dot(beadDX, beadR1);
        float3 beadGradient = (dfdx(beadUV.x) * beadR1 + dfdy(beadUV.x) * beadR2) * sign(beadDet);
        float beadLength = length(beadGradient);
        if (beadLength > 1e-10) {
            float beadCurve = clamp(abs(beadUV.x) - beadUV.y, 0.0, 0.97) * sign(beadUV.x);
            float beadFade = 1.0 - smoothstep(0.35, 1.2, fwidth(beadUV.x));
            float3 beadNormal = beadN * sqrt(1.0 - beadCurve * beadCurve) + beadGradient / beadLength * beadCurve;
            _surface.normal = normalize(mix(beadN, beadNormal, beadFade));
        }
        """
}
