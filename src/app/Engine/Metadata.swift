import Foundation

extension SliceGcode {
    static func replace(_ text:String,pattern:String,with replacement:String,firstOnly:Bool=false) throws -> String {
        let regex=try NSRegularExpression(pattern:pattern),range=NSRange(text.startIndex...,in:text)
        if firstOnly {guard let hit=regex.firstMatch(in:text,range:range),let r=Range(hit.range,in:text) else{return text};var result=text;result.replaceSubrange(r,with:replacement);return result}
        return regex.stringByReplacingMatches(in:text,range:range,withTemplate:NSRegularExpression.escapedTemplate(for:replacement))
    }
    static func settingsMetadata(_ input:String,key:String,values:(Bool)->String) throws -> String {
        let regex=try NSRegularExpression(pattern:"(?m)^; "+NSRegularExpression.escapedPattern(for:key)+#"([: ]+=[ ]*|:[ ]*)[^\n]*$"#)
        var text=input
        for hit in regex.matches(in:input,range:NSRange(input.startIndex...,in:input)).reversed() {
            let separator=String(input[Range(hit.range(at:1),in:input)!]),replacement="; "+key+separator+values(separator.contains("="));text.replaceSubrange(Range(hit.range,in:text)!,with:replacement)
        }
        return text
    }
    static func scalar(_ line:String,_ axis:String)->Double? {
        let code=command(line),ns=code as NSString
        for hit in words.matches(in:code,range:NSRange(location:0,length:ns.length)) where ns.substring(with:hit.range(at:1))==axis {return Double(ns.substring(with:hit.range(at:2)))}
        return nil
    }
}
