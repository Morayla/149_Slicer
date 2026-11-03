import Metal
import SceneKit

// Accumulate optical depth before resolving color, so triangle order cannot create seams.
enum ModelTransparency {
    static func make() -> SCNTechnique {
        let technique = SCNTechnique(dictionary: [
            "sequence": ["platform", "accumulate", "resolve", "handles"],
            "targets": ["accumulation": ["type": "color", "format": "rgba16f"],
                        "platformColor": ["type": "color", "format": "rgba16f"]],
            "symbols": ["viewportBackground": ["type": "vec3"]],
            "passes": [
                "platform": [
                    "draw": "DRAW_SCENE", "includeCategoryMask": 2,
                    "outputs": ["color": "platformColor"],
                    "colorStates": ["clear": true, "clearColor": "0 0 0 0"],
                    "depthStates": ["enableRead": false, "enableWrite": false],
                    "blendStates": ["enable": true, "colorSrc": "srcAlpha", "colorDst": "oneMinusSrcAlpha",
                                    "alphaSrc": "one", "alphaDst": "oneMinusSrcAlpha"],
                ],
                "accumulate": [
                    "draw": "DRAW_SCENE",
                    "outputs": ["color": "accumulation"], "includeCategoryMask": 1,
                    "colorStates": ["clear": true, "clearColor": "0 0 0 0"],
                    "depthStates": ["enableRead": false, "enableWrite": false],
                    "blendStates": [
                        "enable": true, "colorSrc": "one", "colorDst": "one", "alphaSrc": "one", "alphaDst": "one",
                    ],
                    "samples": 4,
                ],
                "handles": [
                    "draw": "DRAW_SCENE", "includeCategoryMask": 4,
                    "outputs": ["color": "COLOR"], "colorStates": ["clear": false],
                    "depthStates": ["enableRead": false, "enableWrite": false],
                ],
                "resolve": [
                    "draw": "DRAW_QUAD",
                    "metalVertexShader": "transparencyVertex",
                    "metalFragmentShader": "transparencyResolve",
                    "inputs": ["accumulation": "accumulation", "platformColor": "platformColor", "viewportBackground": "viewportBackground"],
                    "outputs": ["color": "COLOR"],
                    "depthStates": ["enableRead": false, "enableWrite": false],
                    "blendStates": ["enable": false],
                ],
            ],
        ])!
        technique.library = library
        return technique
    }
    static func setBackground(_ white: Bool, on technique: SCNTechnique) {
        setBackgroundLevel(white ? 0.94 : 0.063, on: technique)
    }
    static func setBackgroundLevel(_ level: Double, on technique: SCNTechnique) {
        let srgb = Float(level)
        let value = pow((srgb + 0.055) / 1.055, 2.4)
        technique.setValue(NSValue(scnVector3: SCNVector3(value, value, value)), forKey: "viewportBackground")
    }
    private static let library = try! MTLCreateSystemDefaultDevice()!.makeLibrary(source: shader, options: nil)
    private static let shader = """
        #include <metal_stdlib>
        using namespace metal;

        struct QuadInput { float3 position [[attribute(0)]]; };
        struct QuadOutput { float4 position [[position]]; float2 uv; };
        vertex QuadOutput transparencyVertex(QuadInput in [[stage_in]]) {
            return {float4(in.position.xy, 0.0, 1.0), float2(in.position.x * 0.5 + 0.5, 0.5 - in.position.y * 0.5)};
        }
        struct ResolveParameters { float3 viewportBackground; };
        fragment float4 transparencyResolve(QuadOutput in [[stage_in]],
                                           texture2d<float> accumulation [[texture(0)]],
                                           texture2d<float> platformColor [[texture(1)]],
                                           constant ResolveParameters &parameters [[buffer(0)]]) {
            constexpr sampler pixelSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
            float4 sum = accumulation.sample(pixelSampler, in.uv);
            float transmission = exp(-sum.a);
            float3 color = sum.rgb / max(sum.a, 1e-6);
            float4 grid = platformColor.sample(pixelSampler, in.uv);
            float3 background = grid.rgb + parameters.viewportBackground * (1.0 - grid.a);
            return float4(mix(color, background, transmission), 1.0);
        }
        """
}
