import Foundation
import Darwin

enum NativeSliceProcess {
    static func run(_ executable:URL,_ arguments:[String],directory:URL?=nil,timeout:Double=120) throws -> String {
        let log=FileManager.default.temporaryDirectory.appendingPathComponent("149-process-"+UUID().uuidString)
        FileManager.default.createFile(atPath:log.path,contents:nil);defer{try? FileManager.default.removeItem(at:log)}
        let handle=try FileHandle(forWritingTo:log);defer{try? handle.close()}
        let process=Process();process.executableURL=executable;process.arguments=arguments;process.currentDirectoryURL=directory;process.standardOutput=handle;process.standardError=handle
        try process.run()
        let timer=DispatchSource.makeTimerSource(queue:.global(qos:.utility));timer.schedule(deadline:.now()+timeout)
        timer.setEventHandler {if process.isRunning {process.terminate();DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+2){if process.isRunning {kill(process.processIdentifier,SIGKILL)}}}};timer.resume()
        process.waitUntilExit();timer.cancel()
        let input=try FileHandle(forReadingFrom:log);defer{try? input.close()};let size=try input.seekToEnd();try input.seek(toOffset:size>6000 ? size-6000:0)
        let text=String(decoding:try input.readToEnd() ?? Data(),as:UTF8.self)
        guard process.terminationStatus==0 else {throw SliceFailure("外部工具未完成或超过时间限制："+String(text.suffix(1500)))}
        return text
    }
}
