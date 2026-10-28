import Foundation
import CryptoKit

@main struct BundleCAD {
    static func main() throws {
        guard CommandLine.arguments.count==4 else {fatalError("BundleCAD <helper> <OCCT-library-directory> <new-output-directory>")}
        let fm=FileManager.default,input=URL(fileURLWithPath:CommandLine.arguments[1]),libraries=URL(fileURLWithPath:CommandLine.arguments[2]),output=URL(fileURLWithPath:CommandLine.arguments[3])
        guard !fm.fileExists(atPath:output.path) else {throw NSError(domain:"149",code:1,userInfo:[NSLocalizedDescriptionKey:"Output already exists"])}
        try fm.createDirectory(at:output.appendingPathComponent("bin"),withIntermediateDirectories:true);try fm.createDirectory(at:output.appendingPathComponent("lib"),withIntermediateDirectories:true)
        func run(_ path:String,_ args:[String]) throws -> String {
            let p=Process(),pipe=Pipe();p.executableURL=URL(fileURLWithPath:path);p.arguments=args;p.standardOutput=pipe;p.standardError=pipe;try p.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
            let text=String(decoding:data,as:UTF8.self);guard p.terminationStatus==0 else {throw NSError(domain:"149",code:Int(p.terminationStatus),userInfo:[NSLocalizedDescriptionKey:text])};return text
        }
        let helper=output.appendingPathComponent("bin/149-step");try fm.copyItem(at:input,to:helper)
        var pending=[helper],seen=Set<String>(),files=[helper]
        while !pending.isEmpty {
            let file=pending.removeFirst(),dependencies=try run("/usr/bin/otool",["-L",file.path]).split(separator:"\n").dropFirst().compactMap{$0.split(whereSeparator:{$0.isWhitespace}).first.map(String.init)}
            for dependency in dependencies where !dependency.hasPrefix("/usr/lib/") && !dependency.hasPrefix("/System/") {
                let name=(dependency as NSString).lastPathComponent
                guard name.hasPrefix("libTK"),name.hasSuffix(".dylib") else {throw NSError(domain:"149",code:2,userInfo:[NSLocalizedDescriptionKey:"Unexpected dependency: "+dependency])}
                if !dependency.hasPrefix("@rpath/") {_=try run("/usr/bin/install_name_tool",["-change",dependency,"@rpath/"+name,file.path])}
                if seen.insert(name).inserted {let destination=output.appendingPathComponent("lib/"+name);try fm.copyItem(at:libraries.appendingPathComponent(name).resolvingSymlinksInPath(),to:destination);pending.append(destination);files.append(destination)}
            }
        }
        for file in files {
            let lines=try run("/usr/bin/otool",["-l",file.path]).components(separatedBy:"\n");var paths=[String]()
            for i in lines.indices where lines[i].trimmingCharacters(in:.whitespaces)=="cmd LC_RPATH" {let line=lines[i+2].trimmingCharacters(in:.whitespaces);paths.append(String(line.dropFirst(5).components(separatedBy:" (offset")[0]))}
            let desired=file==helper ? ["@executable_path/../Frameworks","@executable_path/../lib"]:["@loader_path"]
            for path in paths where !desired.contains(path) {_=try run("/usr/bin/install_name_tool",["-delete_rpath",path,file.path])}
            for path in desired where !paths.contains(path) {_=try run("/usr/bin/install_name_tool",["-add_rpath",path,file.path])}
            if file != helper {_=try run("/usr/bin/install_name_tool",["-id","@rpath/"+file.lastPathComponent,file.path])}
            _=try run("/usr/bin/codesign",["--force","--sign","-",file.path]);_=try run("/usr/bin/codesign",["--verify","--strict",file.path])
        }
        let hashes=try Dictionary(uniqueKeysWithValues:files.map{file in (String(file.path.dropFirst(output.path.count+1)),SHA256.hash(data:try Data(contentsOf:file)).map{String(format:"%02x",$0)}.joined())})
        let provenance:[String:Any]=["name":"Open CASCADE Technology","version":"7.9.3","source":"https://github.com/Open-Cascade-SAS/OCCT/tree/V7_9_3","source_archive_sha256":"5ecf094ec6b12d5413dfb851d8c3590c354058aee556e32e408bdfbf8c357d57","architecture":"arm64","minimum_macos":"13.0","linkage":"dynamic","use_tbb":false,"use_freetype":false,"libraries":seen.sorted(),"sha256":hashes]
        try JSONSerialization.data(withJSONObject:provenance,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:output.appendingPathComponent("provenance.json"))
        print("Bundled \(seen.count) native CAD libraries")
    }
}
