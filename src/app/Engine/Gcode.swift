import Foundation

// A typed modal-state parser shared by the exporter and the preview. Coordinates
// and feeds are resolved once per line without allocating per-axis dictionaries.
enum SliceGcode {
    struct State {
        var x:Double?,y:Double?,z:Double?,feed:Double?
        var point:SlicePoint? {guard let x=x,let y=y,let z=z else{return nil};return SlicePoint(x,y,z)}
        subscript(_ axis:String)->Double? {
            get {switch axis {case "X":return x;case "Y":return y;case "Z":return z;case "F":return feed;default:return nil}}
            set {switch axis {case "X":x=newValue;case "Y":y=newValue;case "Z":z=newValue;case "F":feed=newValue;default:break}}
        }
    }
    struct Record {
        let line:Int,before:State,after:State,extrusion:Double?,distance:Double,section:String,command:String
        var deposits:Bool {(extrusion ?? 0)>0 && distance>1e-8}
    }
    static let words=try! NSRegularExpression(pattern:#"\b([XYZFE])([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)"#)
    private static let sectionPattern=try! NSRegularExpression(pattern:#"^;\s*=+\s*(SKIRT|BRIM|BOTTOM|WALL|PATH|TRAVEL)\b"#)
    static func lines(_ text:String)->[String] {
        var input=text
        return input.withUTF8 {bytes in
            var result=[String]();result.reserveCapacity(bytes.count/55);var start=0
            func append(_ end:Int) {let end=end>start && bytes[end-1]==13 ? end-1:end;result.append(String(decoding:bytes[start..<end],as:UTF8.self))}
            for i in bytes.indices where bytes[i]==10 {append(i);start=i+1}
            if start<bytes.count {append(bytes.count)}
            return result
        }
    }
    static func fmt(_ value:Double)->String {SliceGeometry.fmt(value,places:5)}
    private static func asciiUpper(_ c:UInt8)->UInt8 {c>=97 && c<=122 ? c-32:c}
    private static func whitespace(_ c:UInt8)->Bool {c==32 || (c>=9 && c<=13)}
    private static func wordCharacter(_ c:UInt8)->Bool {(c>=48 && c<=57) || (c>=65 && c<=90) || (c>=97 && c<=122) || c==95}
    private static func digit(_ c:UInt8)->Bool {c>=48 && c<=57}
    private static func scanWords(_ bytes:UnsafeBufferPointer<UInt8>,from:Int,to:Int,_ accept:(UInt8,Double)->Void) {
        var i=from
        while i<to {
            let axis=asciiUpper(bytes[i])
            guard [UInt8(88),89,90,70,69].contains(axis),i==0 || !wordCharacter(bytes[i-1]) else {i+=1;continue}
            let start=i+1;var end=start
            if end<to && (bytes[end]==43 || bytes[end]==45) {end+=1}
            let integer=end;while end<to && digit(bytes[end]) {end+=1};let hasInteger=end>integer
            if end<to && bytes[end]==46 {end+=1;let fraction=end;while end<to && digit(bytes[end]) {end+=1};if !hasInteger && end==fraction {i+=1;continue}}
            else if !hasInteger {i+=1;continue}
            if end<to && asciiUpper(bytes[end])==69 {
                var exponent=end+1;if exponent<to && (bytes[exponent]==43 || bytes[exponent]==45) {exponent+=1}
                let digits=exponent;while exponent<to && digit(bytes[exponent]) {exponent+=1};if exponent>digits {end=exponent}
            }
            if let value=Double(String(decoding:bytes[start..<end],as:UTF8.self)) {accept(axis,value)}
            i=end
        }
    }
    static func command(_ line:String)->String {
        var input=line
        return input.withUTF8 {bytes in
            var start=0,end=0;while end<bytes.count && bytes[end] != 59 {end+=1}
            while start<end && whitespace(bytes[start]) {start+=1};while end>start && whitespace(bytes[end-1]) {end-=1}
            if !bytes[start..<end].contains(where:{$0>=97 && $0<=122}) {return String(decoding:bytes[start..<end],as:UTF8.self)}
            return String(decoding:bytes[start..<end].map(asciiUpper),as:UTF8.self)
        }
    }
    static func records(_ text:String,includeHeights:Bool=false) throws -> ([Record],Int?,[Double?]) {
        var result=[Record](),state=State(),section="",wallMarker:Int?,gapHeight:Double?
        var heights=[Double?]()
        let computation=SliceComputation.current
        let input=lines(text);result.reserveCapacity(input.count/2)
        if includeHeights {heights.reserveCapacity(input.count/2)}
        for (i,source) in input.enumerated() {
            if i & 1023 == 0 {try computation?.check()}
            if includeHeights {
                if source.hasPrefix(";HEIGHT:"),let h=Double(source.dropFirst(8)) {gapHeight=h}
                if source.hasPrefix("; GH_GAP_HEIGHT="),let h=Double(source.dropFirst(16)) {gapHeight=h}
            }
            var line=source
            try line.withUTF8 {bytes in
                var start=0;while start<bytes.count && whitespace(bytes[start]) {start+=1}
                if start==bytes.count {return}
                if bytes[start]==59 {
                    if bytes.count-start>=7 && bytes[start+1]==32 && bytes[start+2]==61 && bytes[start+3]==61 && bytes[start+4]==61 && bytes[start+5]==61 && bytes[start+6]==61 {
                        let upper=String(decoding:bytes[start...].map(asciiUpper),as:UTF8.self),ns=upper as NSString
                        if let match=sectionPattern.firstMatch(in:upper,range:NSRange(location:0,length:ns.length)) {
                            section=ns.substring(with:match.range(at:1));if section=="WALL" && wallMarker==nil {wallMarker=i}
                        }else if upper.contains("END") {section=""}
                    }
                    return
                }
                var end=start;while end<bytes.count && bytes[end] != 59 {end+=1}
                var commandEnd=start;while commandEnd<end && !whitespace(bytes[commandEnd]) {commandEnd+=1}
                let cmd=String(decoding:bytes[start..<commandEnd].map(asciiUpper),as:UTF8.self)
                switch cmd {
                case "G91","G20","M82","G2","G3","G02","G03","G28","START_PRINT","END_PRINT":throw SliceFailure("G1 input body contains unsupported "+cmd+"; use GH PRINT START body, G90/G21/M83, linear G0/G1")
                case "G0","G1","G00","G01","G92":break
                default:return
                }
                let before=state;var x:Double?,y:Double?,z:Double?,f:Double?,e:Double?
                scanWords(bytes,from:commandEnd,to:end) {axis,value in
                    switch axis {case 88:if x==nil{x=value};case 89:if y==nil{y=value};case 90:if z==nil{z=value};case 70:if f==nil{f=value};case 69:if e==nil{e=value};default:break}
                }
                if cmd=="G92" {if x != nil || y != nil || z != nil {throw SliceFailure("G1 body must not reset XYZ with G92")};return}
                for value in [x,y,z,f].compactMap({$0}) where !value.isFinite {throw SliceFailure("Non-finite coordinate")}
                if let x=x {state.x=x};if let y=y {state.y=y};if let z=z {state.z=z};if let f=f {state.feed=f}
                let xy=x != nil || y != nil
                var distance=0.0
                if xy,let ax=before.x,let ay=before.y,let bx=state.x,let by=state.y {distance=hypot(bx-ax,by-ay)}
                if (e ?? 0)>0 && xy && (before.point==nil || state.point==nil) {throw SliceFailure("Establish XYZ before first XY extrusion")}
                result.append(Record(line:i,before:before,after:state,extrusion:e,distance:distance,section:section,command:cmd))
                if includeHeights {heights.append(gapHeight)}
            }
        }
        return (result,wallMarker,heights)
    }
    static func word(_ line:String,_ axis:String,_ value:Double)->String {
        var input=line;let replacement=Array((axis+fmt(value)).utf8),letter=axis.utf8.first!
        return input.withUTF8 {bytes in
            let comment=bytes.firstIndex(of:59) ?? bytes.count
            var begin=0,end=comment
            while begin<end && (bytes[begin]==32 || bytes[begin]==9) {begin+=1}
            while end>begin && (bytes[end-1]==32 || bytes[end-1]==9) {end-=1}
            var output=[UInt8]();output.reserveCapacity(bytes.count+replacement.count+2)
            var i=begin,last=begin,found=false
            while i<end {
                guard bytes[i]==letter,i==0 || !wordCharacter(bytes[i-1]) else {i+=1;continue}
                var tail=i+1
                if tail<end && (bytes[tail]==43 || bytes[tail]==45) {tail+=1}
                let integer=tail;while tail<end && digit(bytes[tail]) {tail+=1};let hasInteger=tail>integer
                if tail<end && bytes[tail]==46 {tail+=1;let fraction=tail;while tail<end && digit(bytes[tail]) {tail+=1};if !hasInteger && tail==fraction {i+=1;continue}}
                else if !hasInteger {i+=1;continue}
                output.append(contentsOf:bytes[last..<i]);output.append(contentsOf:replacement);last=tail;i=tail;found=true
            }
            output.append(contentsOf:bytes[last..<end])
            if !found {if !output.isEmpty {output.append(32)};output.append(contentsOf:replacement)}
            if comment<bytes.count {output.append(contentsOf:[32,59]);output.append(contentsOf:bytes[(comment+1)..<bytes.count])}
            return String(decoding:output,as:UTF8.self)
        }
    }
    static func meta(_ text:String,_ key:String)->String? {
        let prefix=Array(("; "+key+"=").utf8)
        var input=text
        return input.withUTF8 {bytes in
            guard bytes.count>=prefix.count else{return nil}
            for i in 0...(bytes.count-prefix.count) where bytes[i]==59 && (i==0 || bytes[i-1]==10) {
                guard bytes[i..<(i+prefix.count)].elementsEqual(prefix) else{continue}
                let start=i+prefix.count
                var end=start;while end<bytes.count && bytes[end] != 10 {end+=1}
                return String(decoding:bytes[start..<end],as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            }
            return nil
        }
    }
    static func setMeta(_ text:String,_ key:String,_ value:String)->String {
        let prefix="; "+key+"="
        return prefix+value+"\n"+lines(text).filter{!$0.hasPrefix(prefix)}.joined(separator:"\n")
    }
    static func metadata(_ text:String,_ name:String,_ fallback:Double) throws -> Double {
        let regex=try NSRegularExpression(pattern:#"(?m)^\s*;[^\r\n]*?\b"#+NSRegularExpression.escapedPattern(for:name)+#"=([-+0-9.eE]+)"#)
        let ns=text as NSString
        if let match=regex.firstMatch(in:text,range:NSRange(location:0,length:ns.length)) {
            guard let value=Double(ns.substring(with:match.range(at:1))) else {throw SliceFailure("Invalid metadata: "+name)}
            return value
        }
        return fallback
    }
    static func hull(_ input:[SlicePoint])->[SlicePoint] {
        let planar:[SlicePoint]=input.map{SlicePoint($0.x,$0.y,0)}
        let unique=Set<SlicePoint>(planar)
        let points:[SlicePoint]=unique.sorted{a,b in a.x==b.x ? a.y<b.y:a.x<b.x}
        func cross(_ o:SlicePoint,_ a:SlicePoint,_ b:SlicePoint)->Double {(a.x-o.x)*(b.y-o.y)-(a.y-o.y)*(b.x-o.x)}
        var lower=[SlicePoint](),upper=[SlicePoint]()
        for p in points {while lower.count>=2 && cross(lower[lower.count-2],lower.last!,p)<=0 {lower.removeLast()};lower.append(p)}
        for p in points.reversed() {while upper.count>=2 && cross(upper[upper.count-2],upper.last!,p)<=0 {upper.removeLast()};upper.append(p)}
        return Array(lower.dropLast())+Array(upper.dropLast())
    }
    static func openSkirt(_ path:[SlicePoint],_ separation:Double) throws -> [SlicePoint] {
        guard let start=path.first else {throw SliceFailure("Empty skirt")}
        let closed=path+[start]
        for i in stride(from:closed.count-2,through:1,by:-1) {
            let a=closed[i],b=closed[i+1]
            if SliceGeometry.xyLength(a,start)<separation {continue}
            let dx=b.x-a.x,dy=b.y-a.y,ax=a.x-start.x,ay=a.y-start.y,aa=dx*dx+dy*dy
            if aa<=1e-16 {continue}
            let bb=2*(ax*dx+ay*dy),cc=ax*ax+ay*ay-separation*separation
            var t=(-bb-sqrt(max(0,bb*bb-4*aa*cc)))/(2*aa)
            guard t>=(-1e-8),t<=1+1e-8 else {throw SliceFailure("Cannot locate skirt end clearance")}
            t=min(1,max(0,t));let end=SlicePoint(a.x+t*dx,a.y+t*dy,0)
            return Array(closed[...i])+(SliceGeometry.xyLength(a,end)>1e-8 ? [end]:[])
        }
        throw SliceFailure("Skirt too small for separated ends; enlarge skirt gap")
    }
}
