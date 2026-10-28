import SwiftUI
import AppKit

private struct AMS149Connection:Decodable {let url:String;let token:String}
private struct AMS149Command:Decodable {let status:String;let action:String}
private struct AMS149Unit:Decodable,Identifiable {
    let id:Int
    let name:String
    let fresh:Bool
    let temperature:Double?
    let humidity:Double?
    let remaining_minutes:Int?
    let phase:Int?
    let active:Bool
    let blockers:[Int]
    let can_control:Bool
    let command:AMS149Command?
    static func placeholder(_ id:Int)->Self {
        Self(id:id,name:"HT-\([128:"A",129:"B",130:"C"][id] ?? "")",fresh:false,temperature:nil,humidity:nil,remaining_minutes:nil,phase:nil,active:false,blockers:[],can_control:false,command:nil)
    }
}
private struct AMS149Status:Decodable {
    let connected:Bool
    let last_report:Double?
    let developer_mode:Bool?
    let control_enabled:Bool
    let control_configured:Bool
    let firmware:String?
    let units:[AMS149Unit]
}
private struct AMS149Failure:Decodable {let detail:String}
private enum AMS149Error:LocalizedError {
    case message(String)
    var errorDescription:String? {if case let .message(text)=self{return text};return nil}
}
// Never forward the private bearer token to a redirected host.
private final class AMS149NoRedirect:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {completionHandler(nil)}
}
@MainActor private final class AMS149Model:ObservableObject {
    @Published var state:AMS149Status?
    @Published var reachable=false
    @Published var error:String?
    @Published var loading=false
    @Published var sending:Int?
    @Published var updated:Date?
    private let session=URLSession(configuration:.ephemeral,delegate:AMS149NoRedirect(),delegateQueue:nil)
    var units:[AMS149Unit] {state?.units ?? (128...130).map{AMS149Unit.placeholder($0)}}
    var online:Bool {reachable && state?.connected==true}
    private func request(_ path:String,body:Data?=nil) async throws->Data {
        let configURL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/149/ams-connection.json")
        guard let bytes=try? Data(contentsOf:configURL),let config=try? JSONDecoder().decode(AMS149Connection.self,from:bytes),
              let base=URL(string:config.url),base.scheme=="http",base.host=="ginger-dryer",base.port==8009,
              let url=URL(string:config.url+path) else {throw AMS149Error.message(L("未找到工作室连接配置"))}
        var req=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:8)
        req.setValue("Bearer "+config.token,forHTTPHeaderField:"Authorization")
        if let body=body {req.httpMethod="POST";req.httpBody=body;req.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:req)
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode) else {
            if let failure=try? JSONDecoder().decode(AMS149Failure.self,from:data) {throw AMS149Error.message(L(failure.detail))}
            throw AMS149Error.message(L("工作室连接未响应，请稍后重试"))
        }
        return data
    }
    func refresh() async {
        guard !loading else{return}
        loading=true;defer{loading=false}
        do {
            let data=try await request("/v1/status")
            state=try JSONDecoder().decode(AMS149Status.self,from:data)
            reachable=true;updated=Date();error=nil
        } catch is CancellationError {} catch {
            if (error as? URLError)?.code == .cancelled {return}
            reachable=false
            self.error=(error as? AMS149Error)?.localizedDescription ?? L("暂时无法连接工作室，请检查 Tailscale 和树莓派")
        }
    }
    func send(unit:AMS149Unit,action:String,temp:Int,hours:Int,filament:String) async ->String? {
        guard online,unit.can_control,sending==nil else{return L("目前仅查看，远程启停尚未启用")}
        sending=unit.id;defer{sending=nil}
        do {
            let body=try JSONSerialization.data(withJSONObject:["action":action,"temperature":temp,"hours":hours,"filament":filament])
            _ = try await request("/v1/units/\(unit.id)/drying",body:body)
            await refresh();return nil
        } catch {return (error as? AMS149Error)?.localizedDescription ?? L("未确认指令结果，请刷新状态后再操作")}
    }
}

// Orthographic three-quarter projection of the narrow AMS HT envelope.
// The spool and arched cover share the same depth/height plane.
private struct AMS149Wireframe:View {
    private func project(_ x:Double,_ y:Double,_ z:Double)->CGPoint {
        CGPoint(x:10 + 0.49*x + 0.43*y,y:266 + 0.17*x - 0.15*y - 0.72*z)
    }
    var body:some View {
        Canvas {context,_ in
            func stroke(_ points:[CGPoint],_ opacity:Double,_ width:CGFloat=0.85,closed:Bool=false) {
                var p=Path();guard let first=points.first else{return};p.move(to:first)
                for point in points.dropFirst(){p.addLine(to:point)}
                if closed{p.closeSubpath()}
                context.stroke(p,with:.color(.white.opacity(opacity)),style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round))
            }
            func circle(_ x:Double,_ radius:Double)->[CGPoint] {
                (0...120).map {i in
                    let a=Double(i)*2*Double.pi/120
                    return project(x,140+radius*cos(a),130+radius*sin(a))
                }
            }
            func arch(_ x:Double)->[CGPoint] {
                (0...90).map {i in
                    let a=Double(i)*Double.pi/90
                    return project(x,140-128*cos(a),100+128*sin(a))
                }
            }
            // Faint internal edges and far spool flange, visible through the lid.
            stroke(circle(28,100),0.22)
            stroke(circle(28,27),0.13)
            stroke(circle(82,100),0.53,1)
            stroke(circle(82,93),0.20)
            stroke(circle(82,27),0.48)
            stroke(circle(64,27),0.17)
            for a in [Double.pi/2,Double.pi*1.5] {
                stroke([project(28,140+100*cos(a),130+100*sin(a)),project(82,140+100*cos(a),130+100*sin(a))],0.24)
            }
            stroke([project(8,12,100),project(8,268,100)],0.16)
            stroke(arch(8),0.35)
            stroke(arch(106),0.62,1.05)
            for a in [0.0,Double.pi/2,Double.pi] {
                let y=140-128*cos(a),z=100+128*sin(a)
                stroke([project(8,y,z),project(106,y,z)],0.38)
            }
            // Housing: narrow front face, long side face and a restrained top lip.
            stroke([project(0,0,0),project(114,0,0),project(114,280,0),project(0,280,0)],0.18,closed:true)
            stroke([project(0,0,92),project(114,0,92),project(114,280,92),project(0,280,92)],0.50,closed:true)
            stroke([project(0,0,86),project(114,0,86),project(114,280,86)],0.22)
            stroke([project(0,0,92),project(0,0,0),project(114,0,0),project(114,280,0),project(114,280,92)],0.58,1.05)
            stroke([project(114,0,92),project(114,0,0)],0.52)
            stroke([project(0,280,0),project(0,280,92)],0.15)
            stroke([project(7,0,7),project(107,0,7),project(107,274,7)],0.20)
            // Only the front display outline remains; no decorative micro-detail.
            stroke([project(18,-0.5,58),project(91,-0.5,58),project(91,-0.5,37),project(18,-0.5,37)],0.25,0.7,closed:true)
        }.frame(width:200,height:288).accessibilityHidden(true)
    }
}

private struct AMS149Device:View {
    let unit:AMS149Unit
    let fresh:Bool
    let phase:String
    let remaining:String
    private var humidity:String {unit.humidity.map{String(format:"%.0f%%",$0)} ?? "—"}
    private var temperature:String {unit.temperature.map{String(format:"%.1f°C",$0)} ?? "—"}
    private func reading(_ title:String,_ symbol:String,_ value:String)->some View {
        VStack(spacing:6) {
            Image(systemName:symbol).font(.system(size:16,weight:.regular))
                .foregroundColor(symbol=="drop" ? Color(red:0.55,green:0.80,blue:0.84):Color.white.opacity(0.57))
                .frame(height:18)
            Text(value).interfaceFixedFont(size:18,weight:.medium).monospacedDigit()
                .foregroundColor(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(width:80,height:64).opacity(fresh ? 1:0.4)
            .accessibilityElement(children:.ignore).accessibilityLabel(L(title)).accessibilityValue(value)
    }
    var body:some View {
        GeometryReader {geo in
            ZStack(alignment:.topLeading) {
                AMS149Wireframe()
                Text(unit.name).interfaceFixedFont(size:18,weight:.medium)
                    .foregroundColor(.white.opacity(0.9)).offset(x:12,y:21)
                HStack(spacing:6) {
                    Image(systemName:unit.phase==3 ? "wind":"sun.max").font(.system(size:12,weight:.regular))
                    uiText(phase).interfaceFixedFont(size:11,weight:.regular)
                }.foregroundColor(.white.opacity(0.5)).offset(x:13,y:291)
                // All three readings share one type size, one icon size and one row rhythm.
                RoundedRectangle(cornerRadius:35)
                    .fill(LinearGradient(colors:[Color(white:0.18),Color(white:0.13)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius:35).stroke(LinearGradient(colors:[.white.opacity(0.5),.white.opacity(0.18)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1.2))
                    .frame(width:82,height:204).offset(x:207,y:59)
                VStack(spacing:0) {
                    reading("湿度","drop",humidity)
                    Rectangle().fill(.white.opacity(0.12)).frame(width:48,height:1)
                    reading("温度","thermometer.medium",temperature)
                    Rectangle().fill(.white.opacity(0.12)).frame(width:48,height:1)
                    reading("剩余时间","clock",remaining)
                }.offset(x:208,y:64)
            }.frame(width:310,height:318,alignment:.topLeading)
                .scaleEffect(min(geo.size.width/310,geo.size.height/318),anchor:.center)
                .position(x:geo.size.width/2,y:geo.size.height/2)
        }.frame(height:318)
    }
}

private struct AMS149Card:View {
    let unit:AMS149Unit
    @ObservedObject var model:AMS149Model
    @ObservedObject private var language=AppLanguage.shared
    @State private var temperature=45
    @State private var hours=4
    @State private var filament="PLA"
    @State private var confirm=false
    @State private var commandError:String?
    @State private var showSettings=false
    private var fresh:Bool {model.online && unit.fresh}
    private var enabled:Bool {fresh && unit.can_control && model.sending==nil}
    private var phase:String {
        guard fresh else{return model.state==nil ? "等待连接":"数据暂未更新"}
        switch unit.phase {
        case 0:return "待机"
        case 1:return "准备烘干"
        case 2:return "烘干中"
        case 3:return "冷却中"
        case 4:return "正在停止"
        case 5,6:return "设备异常"
        case 7:return "设备测试中"
        default:return unit.active ? "烘干中":"状态未知"
        }
    }
    private var remaining:String {
        guard let mins=unit.remaining_minutes else{return "—"}
        if unit.phase==3{return L("冷却中")}
        if !unit.active{return "—"}
        return String(format:"%d:%02d",mins/60,mins%60)
    }
    private func value(_ v:Double?,unit:String)->String {v.map{String(format:"%.0f",$0)+unit} ?? "—"}
    private var pendingText:String? {
        guard let status=unit.command?.status else{return nil}
        switch status {
        case "pending":return "指令已发送，等待设备确认…"
        case "unconfirmed":return "设备尚未确认，请核对机身状态"
        case "rejected":return "设备未接受指令，请核对机身提示"
        case "confirmed":return "设备状态已确认"
        default:return nil
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            AMS149Device(unit:unit,fresh:fresh,phase:phase,remaining:remaining)
            Divider()
            DisclosureGroup(L("下次烘干"),isExpanded:$showSettings) {
              VStack(alignment:.leading,spacing:14) {
                Picker(L("材料"),selection:$filament) {
                    ForEach(["PLA","PETG","ABS","ASA","PC","PA","PA-CF","PET-CF","TPU"],id:\.self){Text($0).tag($0)}
                }.onChange(of:filament) {material in
                    let preset:[String:(Int,Int)]=["PLA":(45,4),"PETG":(65,6),"ABS":(65,6),"ASA":(65,6),"PC":(75,8),"PA":(80,12),"PA-CF":(80,12),"PET-CF":(80,12),"TPU":(55,8)]
                    if let p=preset[material] {temperature=p.0;hours=p.1}
                }
                HStack {
                    uiText("温度")
                    Spacer()
                    Picker(L("烘干温度"),selection:$temperature) {ForEach(Array(stride(from:45,through:85,by:5)),id:\.self){Text("\($0) °C").tag($0)}}.labelsHidden().frame(width:104)
                }
                HStack {
                    uiText("时长")
                    Spacer()
                    Picker(L("烘干时长"),selection:$hours) {ForEach(1...24,id:\.self){Text(String(format:L("%d 小时"),$0)).tag($0)}}.labelsHidden().frame(width:104)
                }
              }.interfaceFont(.callout).padding(.top,12).disabled(!enabled || unit.active)
            }.interfaceFont(.caption).foregroundColor(.secondary)
            Button {confirm=true} label:{
                HStack {
                    Spacer()
                    if model.sending==unit.id {ProgressView().controlSize(.small)}
                    Image(systemName:unit.active ? "stop.fill":"play.fill").font(.system(size:10))
                    uiText(unit.active ? "停止烘干":"开始烘干")
                    Spacer()
                }.frame(height:26)
            }.buttonStyle(.bordered).disabled(!enabled)
            .confirmationDialog(L(unit.active ? "停止这台 AMS HT 的烘干？":"开始这台 AMS HT 的烘干？"),isPresented:$confirm,titleVisibility:.visible) {
                Button(L("确认")) {Task {
                    commandError=await model.send(unit:unit,action:unit.active ? "stop":"start",temp:temperature,hours:hours,filament:filament)
                }}
                Button(L("取消"),role:.cancel) {}
            } message:{Text(unit.active ? unit.name:String(format:"%@ · %@ · %d °C · "+L("%d 小时"),unit.name,filament,temperature,hours))}
            if let message=commandError ?? pendingText.map({L($0)}) {
                Text(message).interfaceFont(.caption).foregroundColor(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(24).frame(maxWidth:.infinity,alignment:.topLeading).glassCard()
    }
}

struct AMSDryingWindow:View {
    @ObservedObject private var language=AppLanguage.shared
    @StateObject private var model=AMS149Model()
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(spacing:12) {
                Image(systemName:"humidity").interfaceFixedFont(size:22,weight:.light)
                VStack(alignment:.leading,spacing:5) {
                    uiText("AMS HT").interfaceFixedFont(size:24,weight:.medium)
                    uiText("工作室 · X1 Carbon").interfaceFont(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Circle().fill(model.online ? Color.green.opacity(0.7):Color.secondary.opacity(0.5)).frame(width:6,height:6)
                uiText(model.online ? "已连接":model.loading && model.state==nil ? "连接中…":"未连接").interfaceFont(.caption).foregroundColor(.secondary)
                Button {Task{await model.refresh()}} label:{Image(systemName:"arrow.clockwise")}
                    .disabled(model.loading).help(L("刷新状态")).accessibilityLabel(L("刷新状态"))
            }.padding(.horizontal,4)
            ScrollView(.vertical) {
                HStack(alignment:.top,spacing:16) {
                    ForEach(model.units){unit in AMS149Card(unit:unit,model:model)}
                }.padding(.bottom,2)
            }
            HStack(alignment:.top,spacing:8) {
                Image(systemName:model.error==nil ? "info.circle":"wifi.slash").foregroundColor(.secondary)
                VStack(alignment:.leading,spacing:4) {
                    if let error=model.error {Text(error)}
                    else if !model.online {uiText("正在等待打印机状态；请保持打印机开机")}
                    else if model.state?.control_enabled != true {uiText("当前仅查看 · 烘干结束后再启用远程启停")}
                    else {uiText("更改下次烘干设置后，点击开始才会发送指令")}
                    if !model.online && model.state != nil {uiText("显示的是上次数据，控制已暂停").foregroundColor(.secondary)}
                }
                Spacer()
                if let date=model.updated,model.online {Text(L("更新于")+" "+date.formatted(date:.omitted,time:.standard)).foregroundColor(.secondary).monospacedDigit()}
            }.interfaceFont(.caption).foregroundColor(.secondary).padding(.horizontal,4)
        }.padding(24).frame(minWidth:970,minHeight:610).background(WindowGlass())
        .task {
            while !Task.isCancelled {
                await model.refresh()
                do {try await Task.sleep(nanoseconds:5_000_000_000)} catch {break}
            }
        }
    }
}
