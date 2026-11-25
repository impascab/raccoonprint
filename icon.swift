import AppKit
// Original artwork: a raccoon ("trash panda") with code eyes printing a receipt.
let r=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:r)
func c(_ h:Int)->NSColor{NSColor(red:CGFloat(h>>16&255)/255,green:CGFloat(h>>8&255)/255,blue:CGFloat(h&255)/255,alpha:1)}
let ink=c(0x1b1d22)
func P(_ f:(NSBezierPath)->Void)->NSBezierPath{let p=NSBezierPath();f(p);return p}
func pt(_ x:CGFloat,_ y:CGFloat)->NSPoint{NSPoint(x:x,y:y)}
func draw(_ p:NSBezierPath,_ f:NSColor,_ w:CGFloat=14){f.setFill();p.fill();if w>0{ink.setStroke();p.lineWidth=w;p.lineJoinStyle = .round;p.lineCapStyle = .round;p.stroke()}}
func oval(_ cx:CGFloat,_ cy:CGFloat,_ rx:CGFloat,_ ry:CGFloat)->NSBezierPath{NSBezierPath(ovalIn:NSRect(x:cx-rx,y:cy-ry,width:2*rx,height:2*ry))}
func mono(_ s:String,_ size:CGFloat,_ col:NSColor,_ x:CGFloat,_ y:CGFloat){let a=NSAttributedString(string:s,attributes:[.font:NSFont.monospacedSystemFont(ofSize:size,weight:.heavy),.foregroundColor:col]);let z=a.size();a.draw(at:pt(x-z.width/2,y-z.height/2))}
let tile=NSBezierPath(roundedRect:NSRect(x:100,y:100,width:824,height:824),xRadius:185,yRadius:185)
NSGradient(starting:c(0x2c3a5a),ending:c(0x141a2b))!.draw(in:tile,angle:-90)
NSGraphicsContext.saveGraphicsState();tile.addClip()
// hoodie body
draw(P{$0.move(to:pt(250,60));$0.curve(to:pt(390,400),controlPoint1:pt(250,260),controlPoint2:pt(300,380));$0.line(to:pt(634,400));$0.curve(to:pt(774,60),controlPoint1:pt(724,380),controlPoint2:pt(774,260));$0.close()},c(0xf08a24))
// hood behind head
draw(oval(512,570,345,330),c(0xd97412))
// ears
for s in [-1.0,1.0] as [CGFloat]{draw(P{$0.move(to:pt(512+s*130,745));$0.curve(to:pt(512+s*275,860),controlPoint1:pt(512+s*160,850),controlPoint2:pt(512+s*230,890));$0.curve(to:pt(512+s*290,650),controlPoint1:pt(512+s*320,820),controlPoint2:pt(512+s*320,730));$0.close()},c(0x6d7480))
 draw(oval(512+s*232,770,34,46),c(0x2b2f37),0)}
// face
draw(oval(512,560,300,245),c(0x9aa2ae))
draw(P{$0.move(to:pt(512,800));$0.curve(to:pt(470,600),controlPoint1:pt(475,760),controlPoint2:pt(470,680));$0.line(to:pt(554,600));$0.curve(to:pt(512,800),controlPoint1:pt(554,680),controlPoint2:pt(549,760));$0.close()},c(0x6d7480),0)
// cheeks and muzzle
draw(oval(512,450,190,125),c(0xf4f5f7),0)
// mask
for s in [-1.0,1.0] as [CGFloat]{draw(P{$0.move(to:pt(512+s*45,620));$0.curve(to:pt(512+s*200,690),controlPoint1:pt(512+s*80,690),controlPoint2:pt(512+s*140,705));$0.curve(to:pt(512+s*285,520),controlPoint1:pt(512+s*265,670),controlPoint2:pt(512+s*300,590));$0.curve(to:pt(512+s*45,620),controlPoint1:pt(512+s*200,450),controlPoint2:pt(512+s*75,480));$0.close()},c(0x2b2f37),0)
 let e=P{$0.move(to:pt(512+s*118,632));$0.line(to:pt(512+s*190,582));$0.line(to:pt(512+s*118,532))}
 // "<" on the left, ">" on the right
 c(0x5dff9b).setStroke();e.lineWidth=30;e.lineCapStyle = .round;e.lineJoinStyle = .round;e.stroke()}
// nose
draw(P{$0.move(to:pt(460,535));$0.curve(to:pt(564,535),controlPoint1:pt(480,560),controlPoint2:pt(544,560));$0.curve(to:pt(512,478),controlPoint1:pt(566,505),controlPoint2:pt(536,480));$0.curve(to:pt(460,535),controlPoint1:pt(488,480),controlPoint2:pt(458,505));$0.close()},ink,0)
// paper from mouth slot
draw(NSBezierPath(roundedRect:NSRect(x:372,y:396,width:280,height:34),xRadius:17,yRadius:17),ink,0)
draw(P{$0.move(to:pt(400,414));$0.line(to:pt(400,170));for k in 0..<7{let x=400+CGFloat(k)*32;$0.line(to:pt(x+16,146));$0.line(to:pt(x+32,170))};$0.line(to:pt(624,414));$0.close()},.white,12)
mono("{}",124,c(0x141a2b),512,300)
NSGraphicsContext.restoreGraphicsState()
try r.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
