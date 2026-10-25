import SwiftUI

/// Sandy's own pixel mascot. Native drawing keeps it crisp at notch sizes.
struct AgentPixelAvatar: View {
    var state: AgentSessionState
    var source: AgentSource
    var body: some View {
        TimelineView(.periodic(from:.now,by:0.8)) { tick in
            Canvas { context,size in
                let cell=min(size.width/16,size.height/16)
                let body=source == .claude ? Color(red:0.95,green:0.58,blue:0.36) : Color(red:0.55,green:0.63,blue:1)
                func pixel(_ x:Int,_ y:Int,_ w:Int=1,_ h:Int=1,_ color:Color) {
                    context.fill(Path(CGRect(x:CGFloat(x)*cell,y:CGFloat(y)*cell,width:CGFloat(w)*cell,height:CGFloat(h)*cell)),with:.color(color))
                }
                pixel(3,4,10,7,body);pixel(2,6,1,4,body);pixel(13,6,1,4,body)
                pixel(5,2,1,2,body.opacity(0.7));pixel(10,2,1,2,body.opacity(0.7))
                let blink=Int(tick.date.timeIntervalSince1970)%7==0
                pixel(5,6,2,blink ? 1:3,Color.black.opacity(0.85));pixel(9,6,2,blink ? 1:3,Color.black.opacity(0.85))
                pixel(6,10,4,1,Color.black.opacity(0.5))
                if state == .working {
                    pixel(2,12,12,3,Color.gray.opacity(0.45))
                    let offset=Int(tick.date.timeIntervalSince1970*2)%3
                    for x in stride(from:3,to:13,by:2) { pixel(x,13,1,1,Color.white.opacity((x+offset)%3==0 ? 0.9:0.4)) }
                } else if state == .waiting {
                    pixel(13,1,1,3,.yellow);pixel(13,5,1,1,.yellow)
                } else if [.idle,.ended,.disconnected].contains(state) {
                    pixel(4,12,2,1,body.opacity(0.6));pixel(10,12,2,1,body.opacity(0.6))
                } else { pixel(4,12,2,2,body);pixel(10,12,2,2,body) }
            }
        }.frame(width:42,height:42).accessibilityLabel(Text(source.title+": "+state.displayTitle))
    }
}
