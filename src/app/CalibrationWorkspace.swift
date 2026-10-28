import SwiftUI
import WebKit
import UniformTypeIdentifiers

extension Workbench {
    var calibrationContext:[String:Any] {
        func n(_ k:String,_ fallback:Double)->Double {Double(fields[k] ?? "") ?? fallback}
        let shape=fields["SourceMode"] ?? "Cylinder"
        let height=shape == "Cone" ? n("ConeHeight",150):shape == "Ellipse" ? n("EllipseHeight",150):n("CH",150)
        let base=n("H0",2.5)+(toggle("HasBottom").wrappedValue ? max(0,n("B",1)-1)*n("BH",4):0)
        return ["height":height,"layerHeight":n("H",4),"lineWidth":n("W",9),"baseHeight":base,"diameter":n("Dout",200),"eligible":["Cylinder","Ellipse","Cone"].contains(shape)]
    }
}
// Blocks clicks into the softened workspace while the presentation is in front.
final class CalibrationBackdrop:NSVisualEffectView {
    override func hitTest(_ point:NSPoint)->NSView? {bounds.contains(point) ? self:nil}
    override func mouseDown(with event:NSEvent) {}
}
struct CalibrationWorkspace:NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model:Workbench
    @ObservedObject private var language=AppLanguage.shared
    @ObservedObject private var typography=AppTypography.shared
    var active:Bool
    func makeCoordinator()->Coordinator {Coordinator(model:model)}
    func makeNSView(context:Context)->NSView {
        let host=NSView(frame:.zero)
        host.setContentHuggingPriority(.defaultLow,for:.horizontal)
        host.setContentHuggingPriority(.defaultLow,for:.vertical)
        context.coordinator.host=host
        let cfg=WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator,name:"calibration")
        let web=WKWebView(frame:.zero,configuration:cfg);web.navigationDelegate=context.coordinator
        web.setValue(false,forKey:"drawsBackground")
        context.coordinator.web=web
        context.coordinator.mount(web,in:host)
        if let url=Bundle.main.url(forResource:"calibration",withExtension:"html") {web.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())}
        else {DispatchQueue.main.async {model.calibrationLoading=false;model.calibrationLoadError="找不到校准工作区资源。"}}
        return host
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSView,context:Context)->CGSize? {
        let width=proposal.width ?? 980,height=proposal.height ?? 600
        return CGSize(width:width.isFinite ? max(1,width):980,height:height.isFinite ? max(1,height):600)
    }
    func updateNSView(_ host:NSView,context:Context) {context.coordinator.model=model;context.coordinator.active=active;context.coordinator.appearance=colorScheme == .dark ? "dark":"light";context.coordinator.sync()}
    static func dismantleNSView(_ host:NSView,coordinator:Coordinator){
        coordinator.presentationCard?.removeFromSuperview()
        coordinator.backdrop?.removeFromSuperview()
        coordinator.frozenWorkspace?.removeFromSuperview()
        coordinator.web?.configuration.userContentController.removeScriptMessageHandler(forName:"calibration")
    }
    final class Coordinator:NSObject,WKScriptMessageHandler,WKNavigationDelegate {
        let hardware=ScannerHardware()
        var sessionURL:URL?
        var forceSaveAs=false
        var model:Workbench;weak var web:WKWebView?;weak var host:NSView?;weak var presentationWindow:NSWindow?;var presentationCard:NSView?;var backdrop:CalibrationBackdrop?;var frozenWorkspace:NSImageView?;var preparingPresentation=false;var ready=false;var active=false;var lastSync="";var lastRequest="";var appearance="dark"
        init(model:Workbench){self.model=model}
        func mount(_ view:NSView,in parent:NSView){
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints=true
            view.autoresizingMask=[.width,.height]
            view.frame=parent.bounds
            parent.addSubview(view)
        }
        func presentIndependently(){
            if let window=presentationWindow {window.makeKeyAndOrderFront(nil);return}
            guard !preparingPresentation,let web=web,let host=host,let parent=host.window else{return}
            preparingPresentation=true
            // Keep an image of the original workspace behind the live presentation.
            web.takeSnapshot(with:nil){[weak self] image,_ in
                guard let self=self else{return}
                self.preparingPresentation=false
                guard self.model.calibrationPresentation,self.presentationWindow==nil else{return}
                if let image=image {
                    let frozen=NSImageView(frame:host.bounds)
                    frozen.image=image;frozen.imageScaling = .scaleAxesIndependently
                    frozen.autoresizingMask=[.width,.height]
                    host.addSubview(frozen);self.frozenWorkspace=frozen
                }
                guard let content=parent.contentView?.superview ?? parent.contentView else{return}
                self.presentationWindow=parent
                let glass=CalibrationBackdrop(frame:content.bounds)
                glass.autoresizingMask=[.width,.height]
                glass.blendingMode = .withinWindow;glass.material = .hudWindow;glass.state = .active
                glass.wantsLayer=true;glass.layer?.backgroundColor=NSColor(white:0.35,alpha:0.16).cgColor
                content.addSubview(glass);self.backdrop=glass
                let card=NSView(frame:content.bounds.insetBy(dx:48,dy:60))
                card.autoresizingMask=[.width,.height]
                card.wantsLayer=true
                card.shadow=NSShadow()
                card.shadow?.shadowColor=NSColor.black.withAlphaComponent(0.45)
                card.shadow?.shadowBlurRadius=32
                card.shadow?.shadowOffset=NSSize(width:0,height:-12)
                let clipped=NSView(frame:card.bounds)
                clipped.autoresizingMask=[.width,.height];clipped.wantsLayer=true
                clipped.layer?.cornerRadius=22;clipped.layer?.masksToBounds=true
                card.addSubview(clipped);content.addSubview(card);self.presentationCard=card
                self.mount(web,in:clipped)
                self.js("enterPresentation",true)
                self.js("setDetached",true)
                self.lastSync="";self.sync()
                parent.makeKeyAndOrderFront(nil);parent.makeFirstResponder(web);NSApp.activate(ignoringOtherApps:true)
            }
        }
        func restoreWorkspace(){
            guard presentationCard != nil,let web=web,let host=host else{return}
            mount(web,in:host)
            js("setDetached",false)
            frozenWorkspace?.removeFromSuperview();frozenWorkspace=nil
            backdrop?.removeFromSuperview();backdrop=nil
            presentationCard?.removeFromSuperview();presentationCard=nil;presentationWindow=nil
            lastSync="";sync()
            host.window?.makeKeyAndOrderFront(nil)
        }
        func js(_ method:String,_ value:Any) {guard let data=try? JSONSerialization.data(withJSONObject:[value]),let arg=String(data:data,encoding:.utf8) else{return};web?.evaluateJavaScript("window.Calibration.\(method)(\(arg)[0])",completionHandler:nil)}
        func sync(){guard ready else{return}
            if model.calibrationRequest.count==2,model.calibrationRequest[0] != lastRequest {lastRequest=model.calibrationRequest[0];forceSaveAs=model.calibrationRequest[1]=="saveAs";js("command",forceSaveAs ? "save":model.calibrationRequest[1])}
            let state:[String:Any]=["context":model.calibrationContext,"active":(active || presentationWindow != nil),"language":AppLanguage.shared.english ? "en":"zh","typography":AppTypography.shared.preset,"appearance":appearance]
            guard let d=try? JSONSerialization.data(withJSONObject:state,options:.sortedKeys),let text=String(data:d,encoding:.utf8),text != lastSync else{return};lastSync=text
            web?.evaluateJavaScript("window.set149Appearance?.(\"\(appearance)\")",completionHandler:nil)
            js("setTypography",AppTypography.shared.preset);js("setLanguage",AppLanguage.shared.english ? "en":"zh");js("setContext",model.calibrationContext);js("setActive",active || presentationWindow != nil)
        }
        func notify(_ zh:String,_ en:String){js("notify",AppLanguage.shared.english ? en:zh)}
        func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage){
            guard message.frameInfo.isMainFrame,message.frameInfo.request.url?.isFileURL==true,message.frameInfo.request.url?.lastPathComponent=="calibration.html",let b=message.body as? [String:Any],let action=b["action"] as? String else{return}
            switch action {
            case "hardware":hardware.request(b){[weak self] result in self?.js("hardwareResponse",result)}
            case "ready":ready=true;model.calibrationLoading=false;model.calibrationLoadError=nil;js("setHostCapabilities",["presentationOverlay":true]);sync()
            case "present":model.calibrationPresentation=true;presentIndependently()
            case "layout":
                model.calibrationSidebarCollapsed=(b["sidebarCollapsed"] as? Bool) ?? false
                let wantsPresentation=(b["presentation"] as? Bool) ?? false
                model.calibrationPresentation=wantsPresentation
                if wantsPresentation {presentIndependently()} else {restoreWorkspace()}
            case "save":
                guard let encoded=b["base64"] as? String,encoded.count<15_000_000,let data=Data(base64Encoded:encoded),let filename=b["filename"] as? String,let window=web?.window else{return}
                let csv=URL(fileURLWithPath:filename).pathExtension=="csv"
                let saveAs=forceSaveAs;forceSaveAs=false
                if !csv,!saveAs,let url=sessionURL {saveRecord(data,to:url,remember:true);return}
                let p=NSSavePanel();p.allowedContentTypes=csv ? [.commaSeparatedText]:[.json]
                p.nameFieldStringValue=csv ? URL(fileURLWithPath:filename).lastPathComponent:(sessionURL?.lastPathComponent ?? URL(fileURLWithPath:filename).lastPathComponent)
                p.beginSheetModal(for:window){[weak self] r in
                    guard r == .OK,let url=p.url else{return}
                    self?.saveRecord(data,to:url,remember:!csv)
                }
            case "open":
                guard let window=web?.window else{return};let p=NSOpenPanel();p.allowedContentTypes=[.json];p.allowsMultipleSelection=false
                p.beginSheetModal(for:window){[weak self] r in
                    guard r == .OK,let url=p.url else{return}
                    do {
                        let data=try Data(contentsOf:url);guard data.count<5_000_000 else{return}
                        let obj=try JSONSerialization.jsonObject(with:data)
                        let args=try JSONSerialization.data(withJSONObject:[obj])
                        guard let text=String(data:args,encoding:.utf8) else{return}
                        self?.web?.evaluateJavaScript("window.Calibration.loadSession(\(text)[0])"){[weak self] result,_ in
                            if result as? Bool == true {self?.sessionURL=url}
                        }
                    }catch{self?.notify("无法打开记录","Cannot open record")}
                }
            case "applyDraft":applyDraft(b)
            default:break
            }
        }
        func saveRecord(_ data:Data,to url:URL,remember:Bool) {
            do {try data.write(to:url,options:.atomic);if remember {sessionURL=url};notify("记录已保存","Record saved")}
            catch {notify("保存失败：\(error.localizedDescription)","Save failed: \(error.localizedDescription)")}
        }
        func applyDraft(_ body:[String:Any]) {
            guard !model.busy,let d=body["draft"] as? [String:Any],let amount=d["amount"] as? Double,amount.isFinite,amount>0,
                  let turns=d["turns"] as? Int,(1...200).contains(turns),let table=d["table"] as? String,
                  let sourceTarget=d["target"] as? NSDictionary,sourceTarget.isEqual(to:model.calibrationContext),
                  model.calibrationContext["eligible"] as? Bool == true,let width=model.calibrationContext["lineWidth"] as? Double,amount<=width/2,
                  let samples=body["samples"] as? [[String:Any]],samples.count>=5 else{notify("当前切片参数已变化或方案无效，请重新检查方案。","The slicer setup changed or the draft is invalid. Review it again.");return}
            let rows=table.split(separator:"\n");guard rows.count==turns+1 else{return};var previous=100.0
            for (i,row) in rows.enumerated(){let pair=row.split(separator:":");guard pair.count==2,Int(pair[0])==i,let p=Double(pair[1]),p.isFinite,p>=0,p<=previous,(i != 0 || p==100),(i != turns || p==0) else{notify("逐圈表无效","Invalid per-turn table");return};previous=p}
            let simulation=samples.contains{($0["source"] as? String) != "device"}
                let store=EFPresetStore(),stamp=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
                do {
                    _=try store.save(name:"补偿备份 "+stamp+" "+String(UUID().uuidString.prefix(4)),fields:model.fields)
                    model.fields["EF"]=String(amount);model.fields["EFLayers"]=String(turns);model.fields["EFTable"]=table;model.fields["EFEnabled"]="0";model.dirty=true
                    model.selectedEFPresetID=try store.save(name:(simulation ? "模拟测量 — ":"实测补偿 — ")+stamp+" "+String(UUID().uuidString.prefix(4)),fields:model.fields)
                    model.parameterTab=2;model.compensationReviewPending=true
                    model.calibrationRevision+=1;model.status=AppLanguage.shared.english ? "Calibration draft saved; EF is off. Review before slicing.":"校准草稿已写入，EF 未启用。请检查后重新切片。"
                    self.web?.evaluateJavaScript("window.Calibration.draftApplied()",completionHandler:nil)
                }catch{self.notify("无法保存补偿预设：\(error.localizedDescription)","Cannot save preset: \(error.localizedDescription)")}
        }
        func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
            webView.evaluateJavaScript("typeof window.Calibration === 'object'") { [weak self] result,error in
                guard let self=self,!self.ready else{return}
                if error != nil || result as? Bool != true {
                    self.model.calibrationLoading=false
                    self.model.calibrationLoadError="校准工作区初始化失败，请重新加载。"
                }
            }
        }
        func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {loadFailed(error)}
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {loadFailed(error)}
        func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {
            ready=false;model.calibrationLoading=false;model.calibrationLoadError="校准工作区已停止，请重新加载。"
        }
        private func loadFailed(_ error:Error) {
            guard (error as NSError).code != NSURLErrorCancelled else{return}
            ready=false;model.calibrationLoading=false;model.calibrationLoadError="校准工作区加载失败："+error.localizedDescription
        }
        func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){decisionHandler(navigationAction.request.url?.isFileURL==true ? .allow:.cancel)}
    }
}

// Reuse 149's actual glass material, radius and border, rather than approximating colours in HTML.
struct CalibrationGlassBackground:View {
    var sidebarCollapsed=false
    var presentation=false
    var body:some View {
        GeometryReader {g in
            let left:CGFloat = g.size.width>=1600 ? 270 : g.size.width<=1150 ? 210 : 235
            let right:CGFloat = g.size.width>=1600 ? 340 : g.size.width<=1150 ? 280 : 310
            HStack(spacing:10) {
                    if !sidebarCollapsed && !presentation {Color.clear.frame(width:left).glassCard()}
                    Color.clear.frame(maxWidth:.infinity).glassCard()
                    if !presentation {Color.clear.frame(width:right).glassCard()}
            }.padding(.horizontal,10).padding(.top,44).padding(.bottom,10)
        }.allowsHitTesting(false)
    }
}
