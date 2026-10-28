import SwiftUI
import Combine

// Ranges preserve G-code order, including constant-Z and non-planar paths.
final class PathTimeline:ObservableObject {
    @Published var layer=1
    @Published var progress=1.0
    @Published var playing=false
    @Published var showNozzle=true
    private(set) var data:PreviewResult?
    private(set) var layers:[PreviewResult.Layer]=[]
    private var cumulative:[[Double]]=[]
    func load(_ preview:PreviewResult) {
        playing=false;data=preview
        layers=preview.layers ?? [PreviewResult.Layer(start:0,end:preview.segments.count,z:preview.height)]
        layers=layers.filter{$0.start>=0 && $0.end<=(preview.segments.count) && $0.end>$0.start}
        cumulative=layers.map { group in
            var sums=[0.0]
            for i in group.start..<group.end {
                let s=preview.segments[i]
                sums.append(sums.last!+sqrt(pow(s[3]-s[0],2)+pow(s[4]-s[1],2)+pow(s[5]-s[2],2)))
            };return sums
        }
        layer=max(1,layers.count);progress=1
    }
    var cursor:(end:Int,fraction:Double,point:[Double]?) {
        guard let data=data,!layers.isEmpty else{return (0,1,nil)}
        let li=min(layers.count-1,max(0,layer-1)),g=layers[li],c=cumulative[li]
        let target=min(1,max(0,progress))*(c.last ?? 0)
        var lo=0,hi=c.count-1
        while lo+1<hi {let m=(lo+hi)/2;if c[m]<=target {lo=m}else{hi=m}}
        let index=min(g.end-1,g.start+lo),s=data.segments[index]
        let f=progress>=1 ? 1:min(1,max(0,(target-c[lo])/max(1e-12,c[lo+1]-c[lo])))
        var point=[Double]()
        for j in 0..<3 {point.append(s[j]+(s[j+3]-s[j])*f)}
        return (index+1,f,point)
    }
    func tick() {
        guard playing,!layers.isEmpty else{return}
        if progress>=1 {
            if layer>=layers.count {playing=false;return}
            layer+=1;progress=0
        } else {progress=min(1,progress+0.01)}
    }
    func togglePlayback() {
        if !playing && layer==layers.count && progress>=1 {layer=1;progress=0}
        playing.toggle()
    }
}
struct PlaybackControls:View {
    @ObservedObject private var appLanguage=AppLanguage.shared
    @ObservedObject var timeline:PathTimeline
    let enabled:Bool
    var body:some View {
        VStack(spacing:7) {
            HStack {
                uiText("层 \(timeline.layer) / \(max(1,timeline.layers.count))").monospacedDigit().frame(width:112,alignment:.leading)
                GlassSlider(value:Binding(get:{Double(timeline.layer)},set:{timeline.playing=false;timeline.layer=Int($0.rounded())}),range:1...Double(max(2,timeline.layers.count)),step:1,label:"观察层").frame(height:24).disabled(timeline.layers.count<2).accessibilityLabel(L("观察层"))
            }
            HStack {
                uiText(String(format:"层内 %.0f%%",timeline.progress*100)).monospacedDigit().frame(width:112,alignment:.leading)
                GlassSlider(value:Binding(get:{timeline.progress},set:{timeline.playing=false;timeline.progress=$0}),range:0...1,label:"层内路径进度").frame(height:24).accessibilityLabel(L("层内路径进度"))
            }
            HStack {
                Button {timeline.togglePlayback()} label:{Label(L(timeline.playing ? "暂停":"演示"),systemImage:timeline.playing ? "pause.fill":"play.fill")}.disabled(!enabled)
                Toggle(L("喷嘴"),isOn:$timeline.showNozzle).fixedSize()
                if let p=timeline.cursor.point {uiText(String(format:"X %.1f  Y %.1f  Z %.2f",p[0],p[1],p[2])).interfaceFont(.caption).monospacedDigit().foregroundColor(.secondary)}
                Spacer()
                uiText("每层约 10 秒").interfaceFont(.caption).foregroundColor(.secondary)
            }
        }.task(id:enabled && timeline.playing) {
            guard enabled,timeline.playing else{return}
            while !Task.isCancelled,timeline.playing {
                do {try await Task.sleep(nanoseconds:100_000_000)}catch{return}
                guard !Task.isCancelled else{return}
                timeline.tick()
            }
        }.onChange(of:enabled){value in if !value {timeline.playing=false}}
        .onDisappear{timeline.playing=false}
    }
}
