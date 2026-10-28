import SwiftUI
import SceneKit
import simd

struct ModelGeometry {
    let id=UUID()
    let geometry:SCNGeometry
    let dimensions:[Double]
    init(_ prepared:NativePreparedModel) throws {
        let model=prepared.shape,parsed=try SliceGcode.records(model.gcode,includeHeights:true)
        let records=parsed.0,heights=parsed.2,computation=SliceComputation.current
        struct Deposit {let a:SlicePoint;let b:SlicePoint;let normal:SlicePoint;let width:Double;let height:Double}
        func deposit(_ index:Int)->Deposit? {
            guard records.indices.contains(index) else{return nil}
            let r=records[index],h=heights[index] ?? model.parameters["H0"]
            guard let e=r.extrusion,e>0,r.distance>1e-9,h>0,let a=r.before.point,let b=r.after.point else{return nil}
            let xy=hypot(b.x-a.x,b.y-a.y),area=e/r.distance
            let width=area>=Double.pi*h*h/4 ? area/h+h*SliceGeometry.edge:4*area/(Double.pi*h)
            guard xy>1e-9,width.isFinite,width>0 else{return nil}
            return Deposit(a:a,b:b,normal:SlicePoint(-(b.y-a.y)/xy,(b.x-a.x)/xy,0),width:width,height:h)
        }
        // Adjacent extrusion segments share a cross-section and a normal. This removes
        // the overlapping end faces and gaps produced by independent boxes.
        func join(_ a:Deposit?,_ b:Deposit?)->(SlicePoint,SlicePoint,Double)? {
            guard let a=a,let b=b,simd_distance_squared(a.b,b.a)<1e-12,
                  abs(a.width-b.width)<0.05*max(a.width,b.width),
                  abs(a.height-b.height)<0.05*max(a.height,b.height) else{return nil}
            let sum=a.normal+b.normal
            guard simd_length_squared(sum)>1e-8 else{return nil}
            let normal=simd_normalize(sum),cosine=simd_dot(normal,b.normal)
            guard cosine>=0.5 else{return nil}
            let half=(a.width+b.width)/4
            let da=a.b-a.a,db=b.b-b.a
            let available2=min(da.x*da.x+da.y*da.y,db.x*db.x+db.y*db.y)/4
            guard half*half*(1/(cosine*cosine)-1)<=available2 else{return nil}
            return (normal*(half/cosine),normal,(a.height+b.height)/2)
        }
        var vertices=[SCNVector3](),normals=[SCNVector3](),indices=[Int32]()
        var low=SlicePoint(repeating:.infinity),high=SlicePoint(repeating:-.infinity)
        vertices.reserveCapacity(records.count*8);normals.reserveCapacity(records.count*8);indices.reserveCapacity(records.count*24)
        func vertex(_ p:SlicePoint,_ normal:SlicePoint) {
            low=simd_min(low,p);high=simd_max(high,p)
            vertices.append(SCNVector3(Float(p.x),Float(p.z),Float(-p.y)))
            let n=simd_normalize(normal)
            normals.append(SCNVector3(Float(n.x),Float(n.z),Float(-n.y)))
        }
        // Open strokes have a rounded footprint, including the short infill strokes
        // meeting the perimeter. Flat box caps falsely displayed holes there.
        func cap(_ point:SlicePoint,_ normal:SlicePoint,_ width:Double,_ height:Double,_ start:Bool) {
            let offset=Int32(vertices.count),down=SlicePoint(0,0,-height)
            vertex(point,SlicePoint(0,0,1));vertex(point+down,SlicePoint(0,0,-1))
            let tangent=SlicePoint(normal.y,-normal.x,0)*(start ? -1.0:1.0)
            for i in 0...8 {
                let angle=Double(i)*Double.pi/8,radial=normal*cos(angle)+tangent*sin(angle)
                vertex(point+radial*width/2,radial+SlicePoint(0,0,0.25))
                vertex(point+radial*width/2+down,radial+SlicePoint(0,0,-0.25))
            }
            for i in 0..<8 {
                let a=offset+2+Int32(i)*2,b=a+2
                let triangles:[Int32]=[offset,a,b,offset+1,b+1,a+1,a,a+1,b,b,a+1,b+1]
                for j in stride(from:0,to:triangles.count,by:3) {
                    indices += start ? [triangles[j],triangles[j+1],triangles[j+2]]:[triangles[j],triangles[j+2],triangles[j+1]]
                }
            }
        }
        // The exposed first layer uses the same elliptical display section as
        // the sliced-path preview. Real cross-section geometry preserves bead
        // grooves instead of flattening the underside's lighting normals.
        let section=(0..<16).map {i -> (Double,Double) in
            let angle=Double(i)*2*Double.pi/16
            return (cos(angle),sin(angle))
        }
        func firstLayer(_ d:Deposit)->Bool {abs(d.a.z-d.height)<1e-6 && abs(d.b.z-d.height)<1e-6}
        func roundedBead(_ d:Deposit,_ start:(SlicePoint,SlicePoint,Double)?,_ end:(SlicePoint,SlicePoint,Double)?) {
            let count=Int32(section.count),offset=Int32(vertices.count)
            for (point,joint) in [(d.a,start),(d.b,end)] {
                let side=joint?.0 ?? d.normal*d.width/2,normal=joint?.1 ?? d.normal,h=joint?.2 ?? d.height
                for (c,s) in section {
                    vertex(point+side*c+SlicePoint(0,0,h*(s-1)/2),normal*(c/d.width)+SlicePoint(0,0,s/h))
                }
            }
            for i in 0..<count {
                let a=offset+i,b=offset+(i+1)%count
                indices += [a,b,a+count,b,b+count,a+count]
            }
            // A rounded end closes each independent infill stroke without a
            // coplanar bottom disk overlapping the perimeter.
            func close(_ point:SlicePoint,_ isStart:Bool) {
                let tangent=SlicePoint(d.normal.y,-d.normal.x,0)*(isStart ? -1.0:1.0)
                var ring=offset+(isStart ? 0:count)
                for step in 1...3 {
                    let angle=Double(step)*Double.pi/8,c=cos(angle),s=sin(angle),next=Int32(vertices.count)
                    for (x,z) in section {
                        vertex(point+d.normal*(d.width/2*x*c)+tangent*(d.width/2*s)+SlicePoint(0,0,d.height/2*(z*c-1)),
                               d.normal*(x*c/d.width)+tangent*(s/d.width)+SlicePoint(0,0,z*c/d.height))
                    }
                    for i in 0..<count {
                        let a=ring+i,b=ring+(i+1)%count,u=next+i,v=next+(i+1)%count
                        indices += isStart ? [a,u,b,b,u,v]:[a,b,u,b,v,u]
                    }
                    ring=next
                }
                let tip=Int32(vertices.count)
                vertex(point+tangent*d.width/2+SlicePoint(0,0,-d.height/2),tangent)
                for i in 0..<count {
                    let a=ring+i,b=ring+(i+1)%count
                    indices += isStart ? [a,tip,b]:[a,b,tip]
                }
            }
            if start==nil {close(d.a,true)}
            if end==nil {close(d.b,false)}
        }
        let faces:[Int32]=[0,1,2,1,3,2,4,6,5,5,6,7,0,2,4,2,6,4,1,5,3,3,5,7]
        var previous:Deposit?,current=deposit(0)
        for index in records.indices {
            if index & 1023 == 0 {try computation?.check()}
            let next=deposit(index+1)
            defer {previous=current;current=next}
            guard let segment=current else{continue}
            let rounded=firstLayer(segment)
            // Different display sections must close independently at a boundary.
            let start=previous.flatMap {firstLayer($0)==rounded ? join($0,segment):nil}
            let end=next.flatMap {firstLayer($0)==rounded ? join(segment,$0):nil}
            if rounded {roundedBead(segment,start,end);continue}
            let sa=start?.0 ?? segment.normal*segment.width/2,sb=end?.0 ?? segment.normal*segment.width/2
            let na=start?.1 ?? segment.normal,nb=end?.1 ?? segment.normal
            let da=SlicePoint(0,0,-(start?.2 ?? segment.height)),db=SlicePoint(0,0,-(end?.2 ?? segment.height))
            let a=segment.a,b=segment.b,offset=Int32(vertices.count)
            let points=[a+sa,a-sa,b+sb,b-sb,a+sa+da,a-sa+da,b+sb+db,b-sb+db]
            for (i,p) in points.enumerated() {
                let normal=(i%4<2 ? na:nb)*(i%2==0 ? 1.0:-1.0)+SlicePoint(0,0,i<4 ? 0.25:-0.25)
                vertex(p,normal)
            }
            indices.append(contentsOf:faces.map{$0+offset})
            if start==nil {cap(a,segment.normal,segment.width,segment.height,true)}
            if end==nil {cap(b,segment.normal,segment.width,segment.height,false)}
        }
        guard !vertices.isEmpty else {throw SliceFailure("没有可显示的模型轮廓，请检查造型参数。")}
        let center=(low+high)/2
        for i in vertices.indices {vertices[i].x-=CGFloat(center.x);vertices[i].y-=CGFloat(center.z);vertices[i].z+=CGFloat(center.y)}
        dimensions=(0..<3).map{high[$0]-low[$0]}
        try computation?.check()
        geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        let material=SCNMaterial();material.diffuse.contents=NSColor(white:0.85,alpha:1);material.roughness.contents=0.72;material.metalness.contents=0.0;material.lightingModel = .physicallyBased;material.isDoubleSided=true
        geometry.materials=[material]
    }
}

struct ModelPreview:NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let model:ModelGeometry
    let viewAction:Int
    @Binding var zoom:Double
    let panMode:Bool
    let source:String
    final class Coordinator {var id:UUID?;var action = -1;var object:SCNNode?;var source=""}
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->ZoomSceneView {
        let view=ZoomSceneView();view.scene=SCNScene();view.backgroundColor=NSColor(white:0.063,alpha:1);view.autoenablesDefaultLighting=false;view.rendersContinuously=false;view.antialiasingMode = .multisampling4X
        view.setContentHuggingPriority(.defaultLow,for:.horizontal);view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        StudioLighting.install(in:view.scene!)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.zNear=0.01;camera.camera?.zFar=10000;camera.camera?.projectionDirection = .vertical
        view.scene!.rootNode.addChildNode(camera);view.pointOfView=camera;return view
    }
    func updateNSView(_ view:ZoomSceneView,context:Context) {
        let coordinator=context.coordinator,newModel=coordinator.id != model.id
        view.backgroundColor=NSColor(white:colorScheme == .dark ? 0.063:0.94,alpha:1)
        let material=model.geometry.firstMaterial!
        material.diffuse.contents=NSColor(white:colorScheme == .dark ? 0.78:0.64,alpha:1)
        view.panMode=panMode;view.zoomChanged={zoom=$0};view.synchronizeZoom(zoom)
        if newModel {coordinator.object?.removeFromParentNode();let object=SCNNode(geometry:model.geometry);view.scene!.rootNode.addChildNode(object);coordinator.object=object;coordinator.id=model.id}
        if newModel || coordinator.action != viewAction {
            coordinator.action=viewAction;let preserve=newModel && coordinator.source==source,command=newModel ? 0:viewAction%10,d=model.dimensions
            view.frameTarget(SCNVector3Zero,extent:SIMD3(Float(d[0]),Float(d[2]),Float(d[1])),orientation:preserve || command==2 ? nil:command)
            coordinator.source=source
        }
        view.applyScale();view.needsDisplay=true
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:ZoomSceneView,context:Context)->CGSize? {CGSize(width:max(1,proposal.width ?? 520),height:max(1,proposal.height ?? 360))}
    static func dismantleNSView(_ view:ZoomSceneView,coordinator:Coordinator) {view.stopInteraction();view.scene=nil}
}
