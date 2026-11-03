import SceneKit

enum ViewportSurfaceShader {
    static let outline = """
    #pragma arguments
    float outlineStrength;
    float xrayInk;
    #pragma body
    float edge = pow(1.0 - clamp(abs(dot(normalize(_surface.normal), normalize(_surface.view))), 0.0, 1.0), 5.0);
    _output.color.rgb = mix(_output.color.rgb, float3(xrayInk), edge * outlineStrength);
    """
    static let xray = """
    #pragma arguments
    float xrayInk;
    float outlineStrength;
    float xrayColor;
    float xrayStrength;
    #pragma transparent
    #pragma body
    float edge = pow(1.0 - clamp(abs(dot(normalize(_surface.normal), normalize(_surface.view))), 0.0, 1.0), 2.4);
    float alpha = 0.04 + edge * (0.09 + 0.18 * xrayStrength + 0.18 * outlineStrength);
    float3 ink = mix(float3(xrayInk), _surface.diffuse.rgb * (xrayInk < 0.5 ? 0.55 : 1.0), xrayColor * 0.65);
    _output.color = float4(ink * alpha, alpha);
    """
}
