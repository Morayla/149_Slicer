import SwiftUI
import SceneKit
import AppKit

final class ZoomSceneView:SCNView {
    var zoomChanged:((Double)->Void)?
    var panMode=false
    var target=SIMD3<Float>(repeating:0)
    var yaw:Float=0.59,pitch:Float=0.53,distance:Float=1000
    private var pointer=NSPoint.zero
    var fitExtent=SIMD3<Float>(100,100,100)
    var magnification=1.0
    private(set) var fittedScale=100.0
    private var fittedSize=NSSize.zero
    private var idleRender:DispatchWorkItem?
    private var zoomNotification:DispatchWorkItem?
    func beginInteraction() {
        idleRender?.cancel()
        rendersContinuously=true
        let stop=DispatchWorkItem { [weak self] in self?.rendersContinuously=false }
        idleRender=stop
        DispatchQueue.main.asyncAfter(deadline:.now()+0.20,execute:stop)
    }
    func synchronizeZoom(_ value:Double) {
        if zoomNotification == nil {magnification=value}
    }
    func zoomBy(_ factor:Double) {
        beginInteraction()
        magnification=min(30,max(0.25,magnification*factor))
        // Move the camera in the input event, before SwiftUI recomputes panels.
        applyScale()
        guard zoomNotification == nil else{return}
        let notification=DispatchWorkItem { [weak self] in
            guard let self=self else{return}
            self.zoomNotification=nil
            self.zoomChanged?(self.magnification)
        }
        zoomNotification=notification
        DispatchQueue.main.asyncAfter(deadline:.now()+1.0/60,execute:notification)
    }
    func stopInteraction() {
        idleRender?.cancel();zoomNotification?.cancel();zoomNotification=nil
        rendersContinuously=false
    }
    override func layout() {
        super.layout()
        if bounds.size != fittedSize {fittedSize=bounds.size;fitScale()}
    }
    func fitScale() {
        guard let node=pointOfView else{return}
        let m=node.simdWorldTransform
        let right=SIMD3(m.columns.0.x,m.columns.0.y,m.columns.0.z)
        let up=SIMD3(m.columns.1.x,m.columns.1.y,m.columns.1.z)
        let width=Double(simd_dot(simd_abs(right),fitExtent))
        let height=Double(simd_dot(simd_abs(up),fitExtent))
        let aspect=max(0.1,Double(bounds.width/max(1,bounds.height)))
        fittedScale=max(height,width/aspect,1)*0.60
        applyScale()
    }
    func applyScale() {
        pointOfView?.camera?.orthographicScale=fittedScale/max(0.25,magnification)
        needsDisplay=true
    }
    func frameTarget(_ center:SCNVector3,extent:SIMD3<Float>,orientation:Int?) {
        target=SIMD3(Float(center.x),Float(center.y),Float(center.z));fitExtent=extent
        distance=max(extent.x,extent.y,extent.z)*3+100
        if let orientation=orientation {
            switch orientation {
            case 1:yaw=0;pitch=Float.pi/2
            case 3:yaw=0;pitch=0
            case 4:yaw = -Float.pi/2;pitch=0
            default:yaw=0.59;pitch=0.53
            }
        }
        positionCamera();fitScale()
    }
    func resetCamera(target:SCNVector3,span:Double,top:Bool) {
        self.target=SIMD3(Float(target.x),Float(target.y),Float(target.z))
        distance=Float(span*2);yaw=top ? 0:0.59;pitch=top ? 1.5706:0.53
        positionCamera()
    }
    func positionCamera() {
        beginInteraction()
        guard let camera=pointOfView else{return}
        camera.simdPosition=target+distance*SIMD3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
        let up:SCNVector3=abs(cos(pitch))<0.001 ? SCNVector3(-sin(yaw),0,-cos(yaw)):SCNVector3(0,1,0)
        camera.look(at:SCNVector3(target.x,target.y,target.z),up:up,localFront:SCNVector3(0,0,-1));needsDisplay=true
    }
    func pan(dx:Double,dy:Double) {
        guard let camera=pointOfView,let lens=camera.camera else{return}
        let m=camera.simdWorldTransform,k=Float(2*lens.orthographicScale/max(1,bounds.height))
        let right=SIMD3(m.columns.0.x,m.columns.0.y,m.columns.0.z)
        let up=SIMD3(m.columns.1.x,m.columns.1.y,m.columns.1.z)
        target -= right*Float(dx)*k+up*Float(dy)*k
        positionCamera()
    }
    override func mouseDown(with event:NSEvent){beginInteraction();pointer=convert(event.locationInWindow,from:nil)}
    override func mouseDragged(with event:NSEvent) {
        let p=convert(event.locationInWindow,from:nil),dx=Double(p.x-pointer.x),dy=Double(p.y-pointer.y);pointer=p
        if panMode || event.modifierFlags.contains(.shift) {pan(dx:dx,dy:dy)}
        else {yaw-=Float(dx)*0.008;pitch=min(1.5706,max(-1.50,pitch-Float(dy)*0.008));positionCamera()}
    }
    override func rightMouseDown(with event:NSEvent){mouseDown(with:event)}
    override func rightMouseDragged(with event:NSEvent){let p=convert(event.locationInWindow,from:nil);pan(dx:p.x-pointer.x,dy:p.y-pointer.y);pointer=p}
    override func otherMouseDown(with event:NSEvent){mouseDown(with:event)}
    override func otherMouseDragged(with event:NSEvent){rightMouseDragged(with:event)}
    static func scrollZoomFactor(delta:Double,precise:Bool)->Double {
        exp(min(0.25,max(-0.25,delta*(precise ? 0.012:0.08))))
    }
    override func scrollWheel(with event:NSEvent) {
        guard event.momentumPhase.isEmpty else{return}
        // Magic Mouse also reports precise deltas; never infer pan from that flag.
        zoomBy(Self.scrollZoomFactor(delta:Double(event.scrollingDeltaY),precise:event.hasPreciseScrollingDeltas))
    }
    override func magnify(with event:NSEvent){zoomBy(exp(min(0.3,max(-0.3,Double(event.magnification)))))}
}

// Cache completed mesh batches; playback only rebuilds its last partial batch.
// GPU rendering and background mesh construction remain independent.
struct BeadPreview:NSViewRepresentable {
    let data:PreviewResult
    let zLimit:Double
    let showTravel:Bool
    let showBed:Bool
    let mode:PreviewMode
    let viewAction:Int
    @Binding var zoom:Double
    var visibleCount:Int?=nil
    var segmentFraction:Double=1
    var nozzlePoint:[Double]?=nil
    var asLines=false
    var panMode=false
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeNSView(context:Context)->SCNView {
        _ = GlassEnvironment.image
        let view=ZoomSceneView();view.scene=SCNScene();view.backgroundColor=NSColor.clear
        view.setContentHuggingPriority(.defaultLow,for:.horizontal)
        view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        view.allowsCameraControl=false;view.autoenablesDefaultLighting=false
        StudioLighting.install(in:view.scene!)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond=60;view.rendersContinuously=false
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true
        camera.camera?.zNear=0.01;camera.camera?.zFar=10000;camera.camera?.projectionDirection = .vertical
        view.scene!.rootNode.addChildNode(camera);view.pointOfView=camera
        context.coordinator.camera=camera
        return view
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:SCNView,context:Context)->CGSize? {
        let width=proposal.width ?? 520,height=proposal.height ?? 300
        return CGSize(width:width.isFinite ? max(1,width):520,height:height.isFinite ? max(1,height):300)
    }
    func updateNSView(_ view:SCNView,context:Context) {context.coordinator.update(view,self)}
    static func dismantleNSView(_ view:SCNView,coordinator:Coordinator) {coordinator.pending?.cancel();coordinator.cancellation.cancel();coordinator.revision+=1;(view as? ZoomSceneView)?.stopInteraction();view.scene=nil}
    final class Coordinator {
        var camera:SCNNode?
        var pending:DispatchWorkItem?
        var key="",cameraKey=""
        var action = -1
        var nozzle:SCNNode?
        var cachedFrames:(sha:String,bed:BeadMesh.Frame,model:BeadMesh.Frame)?
        var revision=0
        var cancellation=MeshCancellation()
        let meshCache=BeadMeshCache() // Accessed only by the serial mesh queue.
        let queue=DispatchQueue(label:"G1Mini.bead.mesh",qos:.userInitiated)
        func update(_ view:SCNView,_ config:BeadPreview) {
            if cachedFrames?.sha != config.data.sha256 {
                cachedFrames=(config.data.sha256,BeadMesh.frame(config.data,true),BeadMesh.frame(config.data,false))
            }
            let frame=cachedFrames!.model
            (view as? ZoomSceneView)?.panMode=config.panMode
            (view as? ZoomSceneView)?.zoomChanged={value in config.zoom=value}
            let mf=cachedFrames!.model
            let nextCameraKey=config.data.sha256
            if let viewport=view as? ZoomSceneView {
                viewport.synchronizeZoom(config.zoom)
                if cameraKey != nextCameraKey || action != config.viewAction {
                    let newModel=cameraKey != nextCameraKey
                    cameraKey=nextCameraKey;action=config.viewAction
                    let command=newModel ? 0:action%10
                    if command==6 {
                        let center=SCNVector3(Float(config.data.bedSize[0]/2-mf.cx),Float(-mf.cz),Float(-(config.data.bedSize[1]/2-mf.cy)))
                        viewport.frameTarget(center,extent:SIMD3(Float(config.data.bedSize[0]*1.04),Float(max(1,config.data.height)),Float(config.data.bedSize[1]*1.04)),orientation:5)
                    } else {
                        viewport.frameTarget(SCNVector3Zero,extent:SIMD3(Float(mf.sx),Float(mf.sz),Float(mf.sy)),orientation:command==2 ? nil:command)
                    }
                }
                viewport.applyScale()
            }
            if nozzle==nil {
                let marker=SCNNode();marker.name="nozzle-marker"
                let nozzleScale:CGFloat=config.data.machine_name=="G1" || config.data.machine_name==nil ? 1:0.35
                let cone=SCNCone(topRadius:4,bottomRadius:0,height:10)
                marker.scale=SCNVector3(Float(nozzleScale),Float(nozzleScale),Float(nozzleScale))
                let material=SCNMaterial();material.diffuse.contents=NSColor(white:0.88,alpha:1);material.specular.contents=NSColor.white;material.shininess=75
                cone.materials=[material]
                let tip=SCNNode(geometry:cone);tip.position.y=5;marker.addChildNode(tip)
                let body=SCNNode(geometry:SCNCylinder(radius:4,height:5));body.geometry?.materials=[material];body.position.y=12.5;marker.addChildNode(body)
                nozzle=marker;view.scene?.rootNode.addChildNode(marker)
            }
            nozzle?.isHidden=config.nozzlePoint==nil
            if let p=config.nozzlePoint {nozzle?.position=SCNVector3(Float(p[0]-frame.cx),Float(p[2]-frame.cz),Float(-(p[1]-frame.cy)))}
            view.needsDisplay=true
            let next=config.data.sha256+config.mode.rawValue+String(config.showTravel)+String(config.showBed)+String(config.asLines)+String(config.zLimit)+String(config.visibleCount ?? -1)+String(format:"%.5f",config.segmentFraction)
            if key==next{return};key=next;revision+=1
            let ticket=revision;pending?.cancel();cancellation.cancel()
            let token=MeshCancellation();cancellation=token
            let work=DispatchWorkItem { [weak self,weak view] in
                guard let self=self else{return}
                guard let nodes=self.meshCache.nodes(config.data,config.zLimit,config.showTravel,config.showBed,config.mode,end:config.visibleCount,fraction:config.segmentFraction,asLines:config.asLines,cancelled:{token.isCancelled}) else{return}
                DispatchQueue.main.async {
                    guard self.revision==ticket,let view=view else{return}
                    view.scene?.rootNode.childNode(withName:"beads",recursively:false)?.removeFromParentNode()
                    let node=SCNNode();node.name="beads"
                    for child in nodes {node.addChildNode(child)}
                    view.scene?.rootNode.addChildNode(node);view.needsDisplay=true
                }
            }
            pending=work;queue.asyncAfter(deadline:.now()+0.035,execute:work)
        }
    }
}

enum BeadMesh {
    struct Frame {let cx:Double;let cy:Double;let cz:Double;let span:Double;var sx:Double=1;var sy:Double=1;var sz:Double=1}
    static func frame(_ data:PreviewResult,_ bed:Bool)->Frame {
        let rows=data.segments.filter{Int($0[6]) != 4}
        let xs=rows.flatMap{[$0[0],$0[3]]},ys=rows.flatMap{[$0[1],$0[4]]}
        let minx=xs.min() ?? 0,maxx=xs.max() ?? 1,miny=ys.min() ?? 0,maxy=ys.max() ?? 1
        let w=data.beads.map{$0[0]}.max() ?? 1
        return Frame(cx:bed ? data.bedSize[0]/2:(minx+maxx)/2,cy:bed ? data.bedSize[1]/2:(miny+maxy)/2,cz:bed ? 0:data.height/2,
                     span:bed ? max(data.bedSize[0],data.bedSize[1])*1.15:max(maxx-minx+w,maxy-miny+w,data.height,1),sx:maxx-minx+w,sy:maxy-miny+w,sz:max(1,data.height))
    }
    static func color(_ s:[Double],_ mode:PreviewMode,_ limits:[Double],_ heightColors:LayerHeightColors,_ layerHeight:Double)->[Float] {
        if mode == .xray {return [0.92,0.92,0.92,1]}
        if mode == .role {
            return previewRoleRGB[Int(s[6])].map{Float($0)}+[1]
        }
        if Int(s[6])==4 && mode != .speed{return [0.48,0.52,0.57,1]}
        if mode == .height {return heightColors.color(layerHeight).map{Float($0)}+[1]}
        let span=limits[1]-limits[0]
        let f=span>1e-7 ? min(1,max(0,(s[mode.index]-limits[0])/span)):0.5
        return previewMetricRGB(f).map{Float($0)}+[1]
    }
    static func build(_ data:PreviewResult,_ z:Double,_ travel:Bool,_ bed:Bool,_ mode:PreviewMode,end:Int?=nil,fraction:Double=1,asLines:Bool=false,start:Int=0,continues:Bool=false,decorations:Bool=true,preparedFrame:Frame?=nil,preparedColors:LayerHeightColors?=nil)->SCNNode {
        let f=preparedFrame ?? frame(data,false),limits=data.limits(mode,travel)
        let heightColors=preparedColors ?? LayerHeightColors(heights:mode == .height ? (data.layer_heights ?? []):[])
        var vertices=[SCNVector3](),normals=[SCNVector3](),colors=[Float](),indices=[UInt32]()
        var linePoints=[SCNVector3](),lineColors=[Float]()
        let sides=16
        // Join only real, visible extrusion neighbours. Travel, cuts and sharp
        // reversals remain exposed ends; continuous paths have no internal caps.
        let count=max(0,min(end ?? data.segments.count,data.segments.count))
        let connectionLimit=continues ? data.segments.count:count
        func connected(_ left:Int,_ right:Int)->Bool {
            guard left>=0,right<connectionLimit,right==left+1 else{return false}
            let a=data.segments[left],b=data.segments[right]
            guard Int(a[6]) != 4,Int(b[6]) != 4,
                  data.beads[left][0]>0,data.beads[right][0]>0,
                  data.beads[left][1]>0,data.beads[right][1]>0,
                  max(a[2],a[5],b[2],b[5])<=z+1e-7 else{return false}
            let gap=(0..<3).reduce(0.0){$0+pow(a[$1+3]-b[$1],2)}
            let ax=a[3]-a[0],ay=a[4]-a[1],bx=b[3]-b[0],by=b[4]-b[1]
            let lengths=hypot(ax,ay)*hypot(bx,by)
            return gap<1e-10 && lengths>1e-12 && (ax*bx+ay*by)/lengths > -0.5
        }
        func jointNormal(_ index:Int,_ nx:Double,_ ny:Double)->(Double,Double) {
            let row=data.segments[index],dx=row[3]-row[0],dy=row[4]-row[1],length=hypot(dx,dy)
            let x=nx-dy/length,y=ny+dx/length,k=hypot(x,y)
            return (x/k,y/k)
        }
        func xyz(_ x:Double,_ y:Double,_ z:Double)->SCNVector3 {SCNVector3(Float(x-f.cx),Float(z-f.cz),Float(-(y-f.cy)))}
        for i in min(max(0,start),count)..<count {
            let s=data.segments[i]
            if min(s[2],s[5])>z+1e-7 {continue}
            var a=Array(s[0...2]),b=Array(s[3...5])
            if i == (end ?? data.segments.count)-1 {for j in 0..<3 {b[j]=a[j]+(b[j]-a[j])*min(1,max(0,fraction))}}
            if s[5]>z && s[5]>s[2] {
                let t=(z-s[2])/(s[5]-s[2]);for j in 0..<3 {b[j]=s[j]+t*(s[j+3]-s[j])}
            } else if s[2]>z && s[2]>s[5] {
                let t=(z-s[5])/(s[2]-s[5]);for j in 0..<3 {a[j]=s[j+3]+t*(s[j]-s[j+3])}
            }
            let d=hypot(b[0]-a[0],b[1]-a[1])
            if Int(s[6])==4 || asLines {
                if Int(s[6]) != 4 || travel {
                    linePoints += [xyz(a[0],a[1],a[2]),xyz(b[0],b[1],b[2])]
                    let rgba=color(s,mode,limits,heightColors,data.displayLayerHeight(i));lineColors += rgba+rgba
                };continue
            }
            let w=data.beads[i][0],h=data.beads[i][1]
            if w<=0 || h<=0 || d<1e-9 {continue}
            let nx = -(b[1]-a[1])/d,ny=(b[0]-a[0])/d
            let base=UInt32(vertices.count);let rgba=color(s,mode,limits,heightColors,data.displayLayerHeight(i))
            let joinStart=connected(i-1,i)
            let joinEnd=connected(i,i+1) && !(i==count-1 && fraction<1)
            let startNormal=joinStart ? jointNormal(i-1,nx,ny):(nx,ny)
            let endNormal=joinEnd ? jointNormal(i+1,nx,ny):(nx,ny)
            // Elliptical display section has the calculated width and height.
            // Nozzle Z is the top of the bead, not its vertical centre.
            for (endpoint,point) in [a,b].enumerated() {
                let joined=endpoint==0 ? joinStart:joinEnd
                let neighbour=endpoint==0 ? i-1:i+1
                let width=joined ? (w+data.beads[neighbour][0])/2:w
                let height=joined ? (h+data.beads[neighbour][1])/2:h
                let (normalX2,normalY2)=endpoint==0 ? startNormal:endNormal
                for j in 0..<sides {
                    let angle=Double(j)*2*Double.pi/Double(sides)
                    let offset=width/2*cos(angle),vertical=height/2*sin(angle)
                    vertices.append(xyz(point[0]+normalX2*offset,point[1]+normalY2*offset,point[2]-height/2+vertical))
                    let normalX=normalX2*cos(angle)/width,normalY=normalY2*cos(angle)/width,normalZ=sin(angle)/height
                    let length=sqrt(normalX*normalX+normalY*normalY+normalZ*normalZ)
                    normals.append(SCNVector3(Float(normalX/length),Float(normalZ/length),Float(-normalY/length)))
                    colors+=rgba
                }
            }
            for j in 0..<sides {
                let u=base+UInt32(j),v=base+UInt32((j+1)%sides),offset=UInt32(sides)
                indices += [u,v,u+offset,v,v+offset,u+offset]
            }
            // End caps make exposed wave tips and section cuts visible.
            for j in 1..<(sides-1) {
                if !joinStart {indices += [base,base+UInt32(j+1),base+UInt32(j)]}
                if !joinEnd {let q=base+UInt32(sides);indices += [q,q+UInt32(j),q+UInt32(j+1)]}
            }
        }
        let parent=SCNNode()
        if let lamp=data.lamp_reference, lamp.center.count==3 {
            var marks=[SCNVector3]()
            for i in 0..<48 where i%2==0 {
                for j in [i,i+1] {
                    let a=Double(j)*2*Double.pi/48
                    marks.append(xyz(lamp.center[0]+lamp.diameter/2*cos(a),lamp.center[1]+lamp.diameter/2*sin(a),lamp.center[2]))
                }
            }
            let g=SCNGeometry(sources:[SCNGeometrySource(vertices:marks)],elements:[SCNGeometryElement(indices:Array(0..<Int32(marks.count)),primitiveType:.line)])
            let m=SCNMaterial();m.lightingModel = .constant;m.diffuse.contents=NSColor(white:0.85,alpha:0.9);g.materials=[m]
            let reference=SCNNode(geometry:g);reference.name="lamp-reference-no-extrusion";parent.addChildNode(reference)
        }
        if !vertices.isEmpty {
            let cdata=colors.withUnsafeBufferPointer{Data(buffer:$0)}
            let source=SCNGeometrySource(data:cdata,semantic:.color,vectorCount:vertices.count,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
            let element=SCNGeometryElement(indices:indices,primitiveType:.triangles)
            let mesh=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals),source],elements:[element])
            let material=SCNMaterial();material.diffuse.contents=NSColor.white;material.lightingModel = .lambert
            material.isDoubleSided=true;material.specular.contents=NSColor(white:0.13,alpha:1);mesh.materials=[material]
            if mode == .xray {
                material.lightingModel = .constant
                material.diffuse.contents=NSColor.white
                material.specular.contents=NSColor.black
                material.transparencyMode = .singleLayer
                // Match calibration's neutral, rim-weighted X-ray material.
                // Interior faces remain faint; bead silhouettes reveal layer shape.
                material.shaderModifiers=[.fragment:"""
                #pragma transparent
                #pragma body
                float3 normal = normalize(_surface.normal);
                float3 view = normalize(_surface.view);
                float rim = pow(1.0 - clamp(abs(dot(normal, view)), 0.0, 1.0), 2.4);
                float alpha = (0.016 + 0.16 * rim) * 0.35;
                _output.color = float4(float3(0.933) * alpha, alpha);
                """]
                material.readsFromDepthBuffer=false;material.writesToDepthBuffer=false
            }

            let body=SCNNode(geometry:mesh);body.name="material-body";parent.addChildNode(body)
        }
        if decorations && bed {
            let bw=data.bedSize[0],bh=data.bedSize[1],step=bw>500 ? 50.0:20.0
            for v in stride(from:0.0,through:bw,by:step) {
                linePoints += [xyz(v,0,-0.30),xyz(v,bh,-0.30)]
                for _ in 0..<2 {lineColors += [1,1,1,v.truncatingRemainder(dividingBy:step*2)==0 ? 0.32:0.15]}
            }
            for v in stride(from:0.0,through:bh,by:step) {
                linePoints += [xyz(0,v,-0.30),xyz(bw,v,-0.30)]
                for _ in 0..<2 {lineColors += [1,1,1,v.truncatingRemainder(dividingBy:step*2)==0 ? 0.32:0.15]}
            }
            let edgePoints=[xyz(0,0,-0.25),xyz(bw,0,-0.25),xyz(bw,bh,-0.25),xyz(0,bh,-0.25)]
            for j in 0..<4 {linePoints += [edgePoints[j],edgePoints[(j+1)%4]];lineColors += [1,1,1,0.65,1,1,1,0.65]}
            func label(_ text:String,_ x:Double,_ y:Double) {
                let shape=SCNText(string:text,extrusionDepth:0);shape.font=NSFont.systemFont(ofSize:CGFloat(min(16,max(4,bw/62.5))),weight:.medium);shape.flatness=0.5
                let ink=SCNMaterial();ink.lightingModel = .constant;ink.diffuse.contents=NSColor(white:1,alpha:0.65);shape.materials=[ink]
                let node=SCNNode(geometry:shape);node.name="bed-label";node.castsShadow=false;node.eulerAngles.x = -.pi/2;node.position=xyz(x,y,-0.20);parent.addChildNode(node)
            }
            label("0",8,25);label("X · \(Int(bw)) mm",max(20,bw-180),25);label("Y",8,max(30,bh-40))
        }
        if !linePoints.isEmpty {
            let ids=(0..<linePoints.count).map{UInt32($0)}
            let cdata=lineColors.withUnsafeBufferPointer{Data(buffer:$0)}
            let source=SCNGeometrySource(data:cdata,semantic:.color,vectorCount:linePoints.count,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
            let geom=SCNGeometry(sources:[SCNGeometrySource(vertices:linePoints),source],elements:[SCNGeometryElement(indices:ids,primitiveType:.line)])
            let mat=SCNMaterial();mat.lightingModel = .constant;mat.diffuse.contents=NSColor.white;geom.materials=[mat]
            let node=SCNNode(geometry:geom);node.name="travel-and-grid";node.castsShadow=false;node.renderingOrder = -1;parent.addChildNode(node)
        }
        return parent
    }
}


// Fixed studio lights: no animation, no downloaded environment maps.
enum StudioLighting {
    static func install(in scene:SCNScene) {
        let ambient=SCNNode();ambient.name="studio-ambient";ambient.light=SCNLight();ambient.light!.type = .ambient
        ambient.light!.color=NSColor.white;ambient.light!.intensity=170;scene.rootNode.addChildNode(ambient)
        func directional(_ name:String,_ position:SCNVector3,_ intensity:CGFloat,_ shadow:Bool) {
            let node=SCNNode();node.name=name;node.light=SCNLight();let light=node.light!
            light.type = .directional;light.color=NSColor.white;light.intensity=intensity
            light.castsShadow=shadow
            if shadow {
                light.shadowMode = .deferred;light.shadowColor=NSColor(white:0,alpha:0.22)
                light.shadowRadius=5;light.shadowSampleCount=8;light.shadowMapSize=CGSize(width:2048,height:2048)
                light.orthographicScale=1800;light.zNear=1;light.zFar=5000;light.shadowBias=0.2
            }
            node.position=position;node.look(at:SCNVector3Zero);scene.rootNode.addChildNode(node)
        }
        directional("studio-key",SCNVector3(-700,1100,650),850,false)
        directional("studio-fill",SCNVector3(700,400,200),240,false)
        directional("studio-rim",SCNVector3(100,700,-900),500,false)
        // A soft lower fill makes bead contours visible when inspecting the base.
        directional("studio-underside",SCNVector3(-700,-500,650),550,false)
    }
}


// Small procedural studio reflection map, drawn once and cached. No bitmap source.
enum GlassEnvironment {
    static let image:NSImage = {
        let result=NSImage(size:NSSize(width:512,height:256))
        result.lockFocus()
        NSColor(white:0.10,alpha:1).setFill()
        NSRect(x:0,y:0,width:512,height:256).fill()
        NSGradient(colors:[NSColor(white:0.32,alpha:1),NSColor(white:0.72,alpha:1),NSColor(white:0.26,alpha:1)])!.draw(in:NSRect(x:0,y:0,width:512,height:256),angle:90)
        NSGradient(colors:[NSColor(white:0.18,alpha:1),NSColor(white:0.95,alpha:1),NSColor(white:0.92,alpha:1)])!.draw(in:NSBezierPath(roundedRect:NSRect(x:45,y:8,width:105,height:240),xRadius:18,yRadius:18),angle:0)
        NSGradient(colors:[NSColor(white:0.14,alpha:1),NSColor(white:0.75,alpha:1),NSColor(white:0.20,alpha:1)])!.draw(in:NSBezierPath(roundedRect:NSRect(x:300,y:15,width:135,height:225),xRadius:25,yRadius:25),angle:0)
        result.unlockFocus();return result
    }()
}

// Cancellation is checked between batches so superseded requests do not queue
// a full model rebuild. Never mutate mounted SceneKit nodes on the worker queue.
final class MeshCancellation {
    private let lock=NSLock()
    private var cancelled=false
    func cancel(){lock.lock();cancelled=true;lock.unlock()}
    var isCancelled:Bool {lock.lock();defer{lock.unlock()};return cancelled}
}

final class BeadMeshCache {
    static let batchSize=512
    private var key=""
    private var complete=[Int:SCNNode]()
    private var decoration:SCNNode?
    private var frame:BeadMesh.Frame?
    private var colors:LayerHeightColors?
    func nodes(_ data:PreviewResult,_ z:Double,_ travel:Bool,_ bed:Bool,_ mode:PreviewMode,
               end:Int?=nil,fraction:Double=1,asLines:Bool=false,cancelled:()->Bool={false})->[SCNNode]? {
        let next=[data.sha256,String(z),String(travel),String(bed),mode.rawValue,String(asLines)].joined(separator:"|")
        if next != key {
            key=next;complete.removeAll();frame=BeadMesh.frame(data,false)
            colors=LayerHeightColors(heights:mode == .height ? (data.layer_heights ?? []):[])
            decoration=BeadMesh.build(data,z,travel,bed,mode,end:0,asLines:asLines,preparedFrame:frame,preparedColors:colors)
        }
        let count=max(0,min(end ?? data.segments.count,data.segments.count))
        // Keep the last segment in the changing tail, even at a batch boundary:
        // its end normal/cap depends on whether the next segment is visible.
        let tailStart=max(0,(count-1)/Self.batchSize)*Self.batchSize
        var result=[SCNNode]()
        if let decoration=decoration {result.append(decoration)}
        for start in stride(from:0,to:tailStart,by:Self.batchSize) {
            if cancelled(){return nil}
            if complete[start]==nil {
                complete[start]=BeadMesh.build(data,z,travel,false,mode,end:start+Self.batchSize,asLines:asLines,
                    start:start,continues:true,decorations:false,preparedFrame:frame,preparedColors:colors)
            }
            result.append(complete[start]!)
        }
        if cancelled(){return nil}
        result.append(BeadMesh.build(data,z,travel,false,mode,end:count,fraction:fraction,asLines:asLines,
            start:tailStart,decorations:false,preparedFrame:frame,preparedColors:colors))
        return result
    }
}
