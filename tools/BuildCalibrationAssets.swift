import Foundation
import SceneKit
import simd

// Compile CAD triangles once. Runtime uses SceneKit's binary archive, with no JSON parsing or web engine.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
func read(_ name: String) throws -> [String: Any] {
    guard
        let value = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent(name + ".json"))) as? [String: Any]
    else { throw NSError(domain: "CalibrationAssets", code: 1) }
    return value
}
func mesh(_ raw: [String: Any], swap: Bool = true, origin: SIMD3<Float> = .zero) throws -> SCNGeometry {
    guard let p = raw["position"] as? [NSNumber], let indices = raw["index"] as? [NSNumber], p.count % 3 == 0,
        indices.count % 3 == 0
    else { throw NSError(domain: "CalibrationAssets", code: 2) }
    var vertices = [SIMD3<Float>]()
    vertices.reserveCapacity(p.count / 3)
    for i in stride(from: 0, to: p.count, by: 3) {
        let a = SIMD3<Float>(p[i].floatValue, p[i + 1].floatValue, p[i + 2].floatValue) - origin
        vertices.append(swap ? SIMD3(a.x, a.z, a.y) : a)
    }
    var ix = indices.map { $0.uint32Value }
    if swap { for i in stride(from: 0, to: ix.count, by: 3) { ix.swapAt(i + 1, i + 2) } }
    guard ix.allSatisfy({ Int($0) < vertices.count }) else { throw NSError(domain: "CalibrationAssets", code: 3) }
    var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)
    if let n = raw["normal"] as? [NSNumber], n.count == p.count {
        for i in vertices.indices {
            let j = i * 3
            normals[i] =
                swap
                ? SIMD3(n[j].floatValue, n[j + 2].floatValue, n[j + 1].floatValue)
                : SIMD3(n[j].floatValue, n[j + 1].floatValue, n[j + 2].floatValue)
        }
    } else {
        for i in stride(from: 0, to: ix.count, by: 3) {
            let a = Int(ix[i])
            let b = Int(ix[i + 1])
            let c = Int(ix[i + 2])
            let n = simd_cross(vertices[b] - vertices[a], vertices[c] - vertices[a])
            normals[a] += n
            normals[b] += n
            normals[c] += n
        }
        normals = normals.map { simd_length_squared($0) > 1e-12 ? simd_normalize($0) : SIMD3(0, 1, 0) }
    }
    func source(_ values: [SIMD3<Float>], _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        let packed = values.flatMap { [$0.x, $0.y, $0.z] }
        let data = packed.withUnsafeBytes { Data($0) }
        return SCNGeometrySource(
            data: data, semantic: semantic, vectorCount: values.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
    }
    let element = SCNGeometryElement(
        data: ix.withUnsafeBytes { Data($0) }, primitiveType: .triangles, primitiveCount: ix.count / 3, bytesPerIndex: 4
    )
    return SCNGeometry(sources: [source(vertices, .vertex), source(normals, .normal)], elements: [element])
}
var metadata: [String: Any] = ["endstop": try read("endstop")]
func part(_ p: [String: Any]) throws -> SCNNode {
    let node = SCNNode(geometry: try mesh(p))
    let name = p["name"] as? String ?? "part"
    node.name = name
    var info: [String: Any] = [:]
    for key in ["moving", "variant", "cameraMount", "cameraRibbon", "lid", "cover", "reserved", "label"] {
        if let v = p[key] { info[key] = v }
    }
    let external =
        name.range(
            of:
                "^ELEC_(Wire_(MotorOutside|EndstopOutside|DCSupplyOutside|CSI_External)|DCPlugEnvelope|MotorPlug|EndstopPlug|EndstopCrimp_)",
            options: .regularExpression) != nil
    info["electronicsCable"] =
        name.range(
            of:
                "^ELEC_(Wire_|CableTie_|PowerCableTie|PiSocket_|USBPowerPlug|TMCSocket_|DCPlugEnvelope|MotorPlug|EndstopPlug|EndstopCrimp_)",
            options: .regularExpression) != nil
    info["electronicsPart"] =
        name.hasPrefix("ELEC_") && !name.hasPrefix("ELEC_MotorUser") && !name.hasPrefix("ELEC_Camera_") && !external
    metadata[name] = info
    return node
}
let scene = SCNScene()
func group(_ name: String) -> SCNNode {
    let n = SCNNode()
    n.name = name
    scene.rootNode.addChildNode(n)
    return n
}
let electronics = try read("electronics-stage")["parts"] as! [[String: Any]]
for (name, file) in [("measurement", "measurement-stage"), ("bottom", "bottom-white-stage")] {
    let g = group(name)
    let data = try read(file)
    if let limits = data["limits"] as? [String: Any] {
        metadata["limits"] = ["pressedPosition": limits["pressedPosition"]!]
    }
    for p in (data["parts"] as! [[String: Any]]) + electronics {
        let n = p["name"] as? String ?? ""
        if name == "measurement" && (n.hasPrefix("Original_NEMA") || n.hasPrefix("REF_3060")) { continue }
        if let variant = p["variant"] as? String, variant != "up" { continue }
        g.addChildNode(try part(p))
    }
    if name == "measurement" { g.position = SCNVector3(0, 0, 0) }
}
let base = group("base")
let profiles = try read("profiles")
let layout: [(String, SIMD3<Float>, SIMD3<Float>, Float)] = [
    ("3060", [0, 0, -15], [0, 400, -15], .pi / 2), ("3030", [-208, -15, -15], [208, -15, -15], 0),
    ("30120", [0, -15, 0], [0, -15, 560], 0),
]
for (type, a, b, rotation) in layout {
    let raw = profiles[type] as! [String: Any]
    let bounds = raw["bounds"] as! [String: [NSNumber]]
    let lo = bounds["min"]!
    let hi = bounds["max"]!
    let origin = SIMD3<Float>(
        (lo[0].floatValue + hi[0].floatValue) / 2, lo[1].floatValue, (lo[2].floatValue + hi[2].floatValue) / 2)
    let node = SCNNode()
    node.name = "profile-" + type
    node.simdPosition = a
    node.simdOrientation =
        simd_quatf(from: SIMD3(0, 0, 1), to: simd_normalize(b - a)) * simd_quatf(angle: rotation, axis: [0, 0, 1])
    node.simdScale = [1, 1, simd_length(b - a) / 100]
    for rawMesh in raw["meshes"] as! [[String: Any]] {
        node.addChildNode(SCNNode(geometry: try mesh(rawMesh, origin: origin)))
    }
    base.addChildNode(node)
}
for name in ["printed-bracket", "printed-bracket-screw", "sculpted-clamp", "clamp-button-screw"] {
    let n = SCNNode(geometry: try mesh(read(name), swap: false))
    n.name = name
    scene.rootNode.addChildNode(n)
}
var meshes: [SCNNode] = []
scene.rootNode.enumerateChildNodes { node, _ in if node.geometry != nil { meshes.append(node) } }
for node in meshes {
    let edge = SCNNode(geometry: CalibrationEdges.geometry(node.geometry!))
    edge.name = "cad-outline"
    edge.isHidden = true
    node.addChildNode(edge)
}
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
guard scene.write(to: output, options: nil, delegate: nil, progressHandler: nil) else {
    fatalError("Could not write calibration scene")
}
print("Compiled calibration CAD: \(output.path)")

try JSONSerialization.data(withJSONObject: metadata, options: .sortedKeys).write(
    to: output.deletingPathExtension().appendingPathExtension("metadata.json"), options: .atomic)

let compressed = try NSData(contentsOf: output).compressed(using: .lzfse)
try compressed.write(to: output.appendingPathExtension("lzfse"), options: .atomic)
try FileManager.default.removeItem(at: output)
print("Compressed scene: \(compressed.length) bytes")
