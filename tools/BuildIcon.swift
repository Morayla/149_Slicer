import AppKit
import Foundation
// Rebuild the Dock icon from the vector mark, with a standard inset tile.
let args=CommandLine.arguments
 guard args.count==3,let mark=NSImage(contentsOfFile:args[1]) else {fatalError("Usage: swift BuildIcon.swift Logo149VectorWhite.pdf output.icns")}
let work=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".iconset")
try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:work)}
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale,n=CGFloat(pixels)
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        let tile=NSRect(x:n*0.094,y:n*0.094,width:n*0.812,height:n*0.812)
        NSColor.white.setFill();NSBezierPath(roundedRect:tile,xRadius:n*0.18,yRadius:n*0.18).fill()
        let logo=NSImage(size:NSSize(width:700,height:450));logo.lockFocus()
        mark.draw(in:NSRect(x:0,y:0,width:700,height:450),from:.zero,operation:.sourceOver,fraction:1)
        NSColor.black.setFill();NSRect(x:0,y:0,width:700,height:450).fill(using:.sourceIn);logo.unlockFocus()
        logo.draw(in:NSRect(x:n*0.19,y:n*0.30,width:n*0.62,height:n*0.40),from:.zero,operation:.sourceOver,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix=scale==2 ? "@2x":""
        try bitmap.representation(using:.png,properties:[:])!.write(to:work.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");process.arguments=["-c","icns",work.path,"-o",args[2]]
try process.run();process.waitUntilExit();guard process.terminationStatus==0 else {fatalError("Icon assembly failed")}
