import SceneKit

// Shader formulas retain the clay grain and rim-weighted transparency of the original view.
enum CalibrationMaterials {
    static func clay(grain: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(white: 223.0 / 255, alpha: 1)
        material.roughness.contents = 0.94
        material.metalness.contents = 0
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float grainAmount;
            #pragma body
            float grain = fract(sin(dot(_surface.position.xy, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
            _output.color.rgb = clamp(_output.color.rgb + grain * grainAmount, 0.0, 1.0);
            """
        ]
        material.setValue(NSNumber(value: grain), forKey: "grainAmount")
        return material
    }

    static func ink() -> SCNMaterial {
        let material = constant(NSColor(white: 0.04, alpha: 1))
        material.shaderModifiers = [
            .fragment: """
            float grain = fract(sin(dot(_surface.position.xy, float2(12.9898, 78.233))) * 43758.5453);
            _output.color = float4(float3(0.028 + grain * 0.025), 1.0);
            """
        ]
        return material
    }

    static func xray(white: Bool, strength: Double, surface: Double = 1, exponent: Double = 2.4) -> SCNMaterial {
        let material = constant(NSColor(white: white ? 23.0 / 255 : 238.0 / 255, alpha: 1))
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.transparencyMode = .singleLayer
        material.shaderModifiers = [
            .fragment: """
            #pragma arguments
            float rimExponent;
            float surfaceStrength;
            float inkLevel;
            #pragma transparent
            #pragma body
            float rim = pow(1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view))), rimExponent);
            float alpha = (0.016 + rim * 0.16) * surfaceStrength;
            _output.color = float4(float3(inkLevel) * alpha, alpha);
            """
        ]
        material.setValue(NSNumber(value: exponent), forKey: "rimExponent")
        material.setValue(NSNumber(value: strength * surface), forKey: "surfaceStrength")
        material.setValue(NSNumber(value: white ? 23.0 / 255 : 238.0 / 255), forKey: "inkLevel")
        return material
    }

    static func constant(_ color: NSColor, opacity: Double = 1, depth: Bool = true) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.transparency = opacity
        material.readsFromDepthBuffer = depth
        material.writesToDepthBuffer = opacity == 1 && depth
        return material
    }
}
