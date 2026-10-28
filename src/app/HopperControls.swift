import SwiftUI

// Shared with hopper.py; piecewise quadrature exactly integrates r² on each span.
enum HopperCapacity {
    static let lowerHeight=194.7
    static func radius(_ t:Double)->Double {
        if t>=180.7 {return 32+4*(t-180.7)/14}
        let q=min(160,max(0,t))
        let s=q<10 ? q*q/20 : (q>150 ? 150-pow(160-q,2)/20 : q-5)
        return 105-73*s/150
    }
    static func litres(height:Double,width:Double)->Double? {
        guard height.isFinite,width.isFinite,(220...990).contains(height),width>0,width<32 else{return nil}
        var v=Double.pi*pow(105-width,2)*(height-lowerHeight)
        let spans:[Double]=[0,10,150,160,180.7,194.7]
        let samples:[(Double,Double)]=[(-sqrt(3.0/5),5.0/9),(0,8.0/9),(sqrt(3.0/5),5.0/9)]
        for i in 0..<5 {
            let mid=(spans[i]+spans[i+1])/2, half=(spans[i+1]-spans[i])/2
            for (x,w) in samples {v += half*w*Double.pi*pow(radius(mid+half*x)-width,2)}
        }
        return v/1e6
    }
}

struct HopperControls:View {
    @ObservedObject var model:Workbench
    private func value(_ key:String)->Double {Double(model.fields[key] ?? "") ?? .nan}
    private var measured:Bool {value("HopperDensityMode")==1}
    private var volume:Double? {HopperCapacity.litres(height:value("HopperHeight"),width:value("W"))}
    private var bulk:Double {measured ? value("HopperBulkDensity") : value("Density")*value("HopperPackingPercent")/100}
    private var validMass:Bool {
        let fill=value("HopperFillPercent"),packing=value("HopperPackingPercent"),density=value("Density")
        return bulk.isFinite && bulk>0 && bulk<=30 && fill.isFinite && fill>0 && fill<=100 &&
          (measured || (packing.isFinite && packing>0 && packing<=100 && density.isFinite && density>=0.01 && density<=30))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            NumberRow(model:model,label:"料桶总高",key:"HopperHeight",unit:"mm")
            HStack {
                Button("−0.1 mm"){adjust(-0.1)}
                Button("+0.1 mm"){adjust(0.1)}
                Spacer()
                Button("恢复 800 mm"){model.binding("HopperHeight").wrappedValue="800"}
            }
            ContextHelp("仅上方直筒随总高改变。外径 Ø210、下端锥体 160 mm 和嘴部 34.7 mm 固定。")
            if let litres=volume {
                Text(String(format:"直筒 %.2f mm + 固定下端 194.70 mm",value("HopperHeight")-194.7)).interfaceFont(.caption)
                Divider()
                Text(String(format:"内部容积  %.4f L",litres)).interfaceFont(.headline)
                Text(String(format:"内径 Ø%.2f mm · 按当前线宽 %.2f mm 内缩计算",210-2*value("W"),value("W"))).interfaceFont(.caption).foregroundColor(.secondary)
                NumberRow(model:model,label:"装满比例",key:"HopperFillPercent",unit:"%")
                Picker(L("装料重量依据"),selection:model.binding("HopperDensityMode")) {
                    uiText("本体密度 × 颗粒占比（估算）").tag("0")
                    uiText("实测堆积密度").tag("1")
                }
                if measured {
                    NumberRow(model:model,label:"实测堆积密度",key:"HopperBulkDensity",unit:"kg/L")
                    uiText("量取 1 L 颗粒，净重多少 kg 就填多少。使用装入桶内的物料密度。").interfaceFont(.caption).foregroundColor(.secondary)
                } else {
                    Text(String(format:"材料本体密度 %.3f g/cm³（沿用 GI 材料参数）",value("Density"))).interfaceFont(.caption)
                    NumberRow(model:model,label:"颗粒占比",key:"HopperPackingPercent",unit:"%")
                    uiText("60% 为可调整的估算假设，其余为空隙，不是该材料的实测值。1.3 g/cm³ 不能直接当作每升颗粒的重量。").interfaceFont(.caption).foregroundColor(.secondary)
                }
                if validMass {
                    Text(String(format:"预计装料  %.3f kg",litres*value("HopperFillPercent")/100*bulk)).interfaceFont(.headline)
                    Text(String(format:"使用容积 %.4f L × %@ %.4f kg/L",litres*value("HopperFillPercent")/100,measured ? "实测堆积密度":"估算堆积密度",bulk)).interfaceFont(.caption).foregroundColor(.secondary)
                } else {
                    uiText("请填写有效密度及 0–100% 范围内的比例（不含 0）。").interfaceFont(.caption).foregroundColor(.orange)
                }
            } else {
                uiText("总高范围 220–990 mm；线宽需大于 0 且小于 32 mm。").interfaceFont(.caption).foregroundColor(.orange)
            }
            ContextHelp("容量和装料重量随输入即时更新；路径预览需重新切片。容积按名义光滑内壁计算，显示小数位不代表实物精度。")
            uiText("大口朝平台，连续螺旋向上打印；上下贯通，不含盖和封底。装料重量不等于下方的打印用料重量。").interfaceFont(.caption).foregroundColor(.secondary)
        }
    }
    private func adjust(_ delta:Double) {
        let h=value("HopperHeight");guard h.isFinite else{return}
        model.binding("HopperHeight").wrappedValue=String(format:"%.2f",min(990,max(220,h+delta)))
    }
}
