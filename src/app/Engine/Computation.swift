import Foundation

// A cancellation scope belongs to one worker thread; exported slices never
// inherit the preview's token. Long loops check at bounded intervals.
final class SliceComputation {
    private let lock=NSLock()
    private var stopped=false
    func cancel() {lock.lock();stopped=true;lock.unlock()}
    var isCancelled:Bool {lock.lock();defer{lock.unlock()};return stopped}
    func check() throws {if isCancelled {throw CancellationError()}}
    static var current:SliceComputation? {Thread.current.threadDictionary["149.preview.computation"] as? SliceComputation}
    static func check() throws {try current?.check()}
    func run<T>(_ work:() throws -> T) throws -> T {
        let thread=Thread.current,previous=thread.threadDictionary["149.preview.computation"]
        thread.threadDictionary["149.preview.computation"]=self
        defer {if let previous=previous {thread.threadDictionary["149.preview.computation"]=previous} else {thread.threadDictionary.removeObject(forKey:"149.preview.computation")}}
        try check();let value=try work();try check();return value
    }
}
