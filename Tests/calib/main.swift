// Prints grey patches at the three print strengths, with edge lines. --dry writes a picture instead.
import AppKit
setbuf(stdout,nil)
DispatchQueue.global().asyncAfter(deadline:.now()+150){print("TIMEOUT");exit(9)}
let imageArg=CommandLine.arguments.dropFirst().first{!$0.hasPrefix("--")}
let go=CommandLine.arguments.contains("--go") // nothing prints without it
let names=["Light","Normal","Dark"], levels=[10,20,30,40,50,65,80,100], H=176
func strip(_ k:Int)->Bitmap{
 let g=UnsafeMutablePointer<UInt8>.allocate(capacity:384*H);g.initialize(repeating:255,count:384*H)
 for (i,l) in levels.enumerated(){for y in 72..<166{for x in 0..<44{g[y*384+10+i*46+x]=UInt8(255-255*l/100)}}}
 var b=Encoder.toBits(g,384,H,.photo);g.deallocate()
 func stamp(_ s:String,_ z:CGFloat,_ x0:Int,_ y0:Int){let t=try! TextRender.render(s,size:z,bold:true,align:.left);for y in 0..<t.height{for x in 0..<(384-x0) where t.px[y*384+x]==0 && y0+y<H{b.px[(y0+y)*384+x0+x]=0}}}
 stamp(names[k],26,10,2);for i in levels.indices{stamp("\(i+1)",20,20+i*46,40)}
 for y in 0..<H{for x in [0,383]{b.px[y*384+x]=0};if y%4<2{for x in [6,377]{b.px[y*384+x]=0}}}
 return b}
if !go && !CommandLine.arguments.contains("--light"){for k in 0..<3{try! NSBitmapImageRep(cgImage:Encoder.preview(strip(k),strength:k)!).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"build/cal\(k).png"))};print("rows",3*H,"bytes",(0..<3).map{Encoder.strips(strip($0)).reduce(0){$0+$1.count}});exit(0)}
func tiny(_ t:String)->Bitmap{var b=Bitmap(width:384,height:60,px:[UInt8](repeating:255,count:384*60));let l=try! TextRender.render(t,size:30,bold:true,align:.left)
 for y in 0..<60{for x in 0..<384{if x<3||x>380||y<2||y>57||(x%48<2&&y>44){b.px[y*384+x]=0}}};for y in 0..<min(l.height,44){for x in 0..<300 where l.px[y*384+x]==0{b.px[(y+4)*384+x+20]=0}};return b}
if CommandLine.arguments.contains("--light"){
 if !go{print("tiny rows",60,"bytes",Encoder.strips(tiny("L1"))[0].count);exit(0)}
 Task{@MainActor in let p=Printer();@MainActor func hx()->String{p.rx.map{String(format:"%02x",$0)}.joined()}
  do{print(try await p.connect())
  for (n,k) in [("L1 light first",0),("N normal",1),("L2 light",0),("L3 light+wait",0)]{
   p.rx=Data();try await p.send(Data([0x10,0xff,0x10,0,UInt8(k)]));try await Task.sleep(nanoseconds:500_000_000);let r=hx()
   if n.hasPrefix("L3"){try await Task.sleep(nanoseconds:3_000_000_000);try await p.send(Data([0x10,0xff,0xfe,1]+[UInt8](repeating:0,count:12)));try await Task.sleep(nanoseconds:500_000_000)}
   try await p.send(Encoder.strips(tiny(n))[0]);try await p.send(Sender.feed);p.rx=Data();try await p.send(Sender.query);let e=uptime()+15;while p.rx.count<2&&uptime()<e{try await Task.sleep(nanoseconds:50_000_000)}
   print(n,"darkness reply",r,"end reply",hx());try await Task.sleep(nanoseconds:5_000_000_000)}
  }catch{print(error.localizedDescription)};await p.close();exit(0)}
 RunLoop.main.run()}
Task{@MainActor in let p=Printer();p.log={s,e in print(s)};do{_=try await p.connect()
 for k in 0..<3{let s=Encoder.strips(strip(k));let o=try await Sender(log:{t,_ in print(t)}).run([Job(name:names[k],strips:s,rows:H)],darkness:k,on:p);print(names[k],o);try await Task.sleep(nanoseconds:6_000_000_000)}
  if let f=imageArg{let b=try Encoder.render(try Encoder.load(URL(fileURLWithPath:f)),mode:.photo,turns:0,trim:true);let o=try await Sender(log:{t,_ in print(t)}).run([Job(name:"image",strips:Encoder.strips(b),rows:b.height)],darkness:1,on:p);print("image",b.height,"rows",o);try await Task.sleep(nanoseconds:8_000_000_000)}
 }catch{print(error.localizedDescription)};await p.close();exit(0)}
RunLoop.main.run()
