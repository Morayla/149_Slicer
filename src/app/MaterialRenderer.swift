import SceneKit

// PBR reflection and environment refraction share the studio map. Transmission
// is a real-time approximation; it does not trace rays through other objects.
enum MaterialRenderer {
    private static let linearColorSpace = NSColorSpace(
        cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!
    static func make(geometricProfile: Bool = true) -> SCNMaterial {
        let material = BeadSurface.material(geometricProfile: geometricProfile)
        material.transparencyMode = .singleLayer
        material.shaderModifiers?[.fragment] = transmissionShader
        let environment = SCNMaterialProperty(contents: GlassEnvironment.image)
        environment.wrapS = .repeat
        environment.wrapT = .clamp
        environment.minificationFilter = .linear
        environment.magnificationFilter = .linear
        environment.mipFilter = .linear
        material.setValue(environment, forKey: "transmissionEnvironment")
        material.setValue(NSNumber(value: 0.0), forKey: "outlineStrength")
        material.setValue(NSNumber(value: 0.9), forKey: "xrayInk")
        material.setValue(NSNumber(value: 0.0), forKey: "xrayColor")
        material.setValue(NSNumber(value: 0.5), forKey: "xrayStrength")
        apply(MaterialAppearance(), to: material)
        return material
    }
    static func apply(
        _ appearance: MaterialAppearance, to material: SCNMaterial, solid: Bool = false,
        accumulatesTransparency: Bool = false
    ) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        let transmitting = !solid && appearance.transmission > 0 && appearance.metallic < 1
        // Render entry surfaces once instead of blending both sides of every bead shell.
        material.isDoubleSided = false
        material.blendMode = accumulatesTransparency ? .add : .alpha
        material.setValue(NSNumber(value: accumulatesTransparency ? 1 : 0), forKey: "accumulateTransparency")
        material.multiply.contents = solid ? NSColor(white: 0.78, alpha: 1) : appearance.color
        material.lightingModel = solid ? .lambert : .physicallyBased
        material.roughness.contents = max(0.025, appearance.roughness)
        material.metalness.contents = solid ? 0 : appearance.metallic
        material.writesToDepthBuffer = !transmitting
        material.setValue(
            NSNumber(value: solid ? 0 : appearance.transmission * (1 - appearance.metallic)),
            forKey: "transmissionAmount")
        material.setValue(NSNumber(value: appearance.ior), forKey: "opticalIOR")
        material.setValue(NSNumber(value: appearance.roughness), forKey: "surfaceRoughness")
        let tint = appearance.color.usingColorSpace(linearColorSpace)!
        material.setValue(
            NSValue(scnVector3: SCNVector3(tint.redComponent, tint.greenComponent, tint.blueComponent)),
            forKey: "transmissionTint")
    }
    static let transmissionShader = """
        #pragma arguments
        float outlineStrength;
        float xrayInk;
        float transmissionAmount;
        float accumulateTransparency;
        float opticalIOR;
        float surfaceRoughness;
        float3 transmissionTint;
        texture2d<float> transmissionEnvironment;
        #pragma transparent
        #pragma body
        float outlineEdge = pow(1.0 - clamp(abs(dot(normalize(_surface.normal), normalize(_surface.view))), 0.0, 1.0), 5.0);
        _output.color.rgb = mix(_output.color.rgb, float3(xrayInk), outlineEdge * outlineStrength);
        if (transmissionAmount > 0.0) {
            float3 normal = normalize(_surface.normal);
            float3 viewDirection = normalize(_surface.view);
            normal *= dot(normal, viewDirection) < 0.0 ? -1.0 : 1.0;
            float3 ray = refract(-viewDirection, normal, 1.0 / opticalIOR);
            float3 direction = normalize((scn_frame.inverseViewTransform * float4(ray, 0.0)).xyz);
            float2 uv = float2(atan2(direction.z, direction.x) / (2.0 * M_PI_F) + 0.5,
                               acos(clamp(direction.y, -1.0, 1.0)) / M_PI_F);
            constexpr sampler environmentSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);
            float3 transmitted = transmissionEnvironment.sample(environmentSampler, uv, level(surfaceRoughness * 6.0)).rgb;
            float f0 = (opticalIOR - 1.0) / (opticalIOR + 1.0);
            f0 *= f0;
            float fresnel = f0 + (1.0 - f0) * pow(1.0 - saturate(dot(normal, viewDirection)), 5.0);
            float amount = transmissionAmount * (1.0 - fresnel);
            float alpha = 1.0 - amount * 0.65;
            _output.color.rgb = mix(_output.color.rgb, transmitted * transmissionTint, amount);
            _output.color.a = alpha;
            if (accumulateTransparency > 0.5) {
                float opticalDepth = -log(1.0 - min(alpha, 0.999));
                _output.color = float4(_output.color.rgb * opticalDepth, opticalDepth);
            }
        }
        """
}
