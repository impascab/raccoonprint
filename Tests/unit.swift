import Foundation
import CoreGraphics
@MainActor final class Fake: Transport {
    var rx=Data(); var sends:[Data]=[]; var answer:(Int)->Bool={_ in true}; var okLate=false; var failAt = -1; var status:(Int)->[UInt8]={_ in [0]}; var asked=0
    func send(_ x:Data) async throws { if x==Sender.statusQuery {asked+=1;rx.append(contentsOf:status(asked));return}; if sends.count==failAt{throw PrintError(msg:"The printer disconnected.")}
        sends.append(x)
        if x.count==5 && x[2]==0x10 && !okLate {rx.append(Data("OK".utf8))}
        if x.count>100 && okLate {rx.append(Data("OK".utf8))}
        if x==Sender.query && answer(sends.count) && !okLate {rx.append(Data([0,0x56]))} }
}
var fails=0
@MainActor func check(_ n:String,_ c:Bool){print(c ? "ok  ":"FAIL",n);if !c{fails+=1}}
func flat(_ v:UInt8,_ w:Int,_ h:Int,_ dark:CGRect?=nil)->CGImage{let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpace(name:CGColorSpace.genericGrayGamma2_2)!,bitmapInfo:0)!
 c.setFillColor(gray:CGFloat(v)/255,alpha:1);c.fill(CGRect(x:0,y:0,width:w,height:h));if let d=dark{c.setFillColor(gray:0,alpha:1);c.fill(d)};return c.makeImage()!}
func black(_ b:Bitmap)->Int{b.px.filter{$0==0}.count*100/b.px.count}
@main struct T{ @MainActor static func main() async {
 func strip(_ rows:Int)->Data{Data(repeating:1,count:24+48*rows)}
 let j=Job(name:"a",strips:[strip(120)],rows:120), long=Job(name:"l",strips:[strip(1000),strip(200)],rows:1200)
 func s(_ c:@escaping()->Bool={false})->Sender{Sender(timeScale:0.05,cancelled:c)}
 func bytes(_ f:Fake)->Int{f.sends.filter{$0.count>100}.reduce(0){$0+$1.count}}
 // j = darkness, 3 slices, feed, query
 var f=Fake();check("prints 2 jobs",(try? await s().run([j,j],darkness:1,on:f)) == .printed && bytes(f)==2*j.strips[0].count && f.sends.count==11)
 f=Fake();check("strip is continuous",(try? await s().run([j],darkness:1,on:f)) == .printed && f.sends[1...3].allSatisfy{$0.count>100} && f.sends[4]==Sender.feed)
 f=Fake();check("long job pauses once",(try? await s().run([long],darkness:1,on:f)) == .printed && f.sends.filter{$0==Sender.query}.count==2 && bytes(f)==long.strips.reduce(0){$0+$1.count})
 f=Fake();f.answer={_ in false};check("silent printer stops after strip 1",(try? await s().run([long,j],darkness:1,on:f)) == .unconfirmed(finished:0) && bytes(f)==strip(1000).count)
 f=Fake();f.answer={$0<8};check("silent at end stops job 2",(try? await s().run([j,j],darkness:1,on:f)) == .unconfirmed(finished:1))
 f=Fake();f.okLate=true;check("late OK not counted",(try? await s().run([j],darkness:1,on:f)) == .unconfirmed(finished:0))
 for at in 0...5 {f=Fake();f.failAt=at;var e="";var o:Outcome?;do{o=try await s().run([j],darkness:1,on:f)}catch{e=error.localizedDescription};check("failure at send \(at): \(e)",o != .printed && (!e.isEmpty || o == .unconfirmed(finished:0)))}
 f=Fake();check("cancel before start",(try? await s({true}).run([j],darkness:1,on:f)) == .cancelled(finished:0) && f.sends.isEmpty)
 f=Fake();let f1=f;check("cancel mid-strip pads white, exact bytes",(try? await s({f1.sends.count>=2}).run([j,j],darkness:1,on:f)) == .cancelled(finished:0) && bytes(f)==j.strips[0].count && f.sends[2].allSatisfy{$0==0} && f.sends[3].allSatisfy{$0==0} && f.sends[4]==Sender.feed)
 f=Fake();let f2=f;check("cancel after last send = alreadySent",(try? await s({f2.sends.count>=5}).run([j],darkness:1,on:f)) == .alreadySent)
 f=Fake();let f3=f;check("cancel between copies",(try? await s({f3.sends.count>=6}).run([j,j],darkness:1,on:f)) == .cancelled(finished:1))
 // paper
 f=Fake();f.status={_ in [4]};check("no paper: stops before sending any row",(try? await s().run([j,j],darkness:1,on:f)) == .noPaper(finished:0,started:false) && bytes(f)==0)
 f=Fake();f.status={$0==2 ? [4]:[0]};check("paper ran out during print 1",(try? await s().run([j,j],darkness:1,on:f)) == .noPaper(finished:0,started:true) && bytes(f)==j.strips[0].count)
 f=Fake();f.status={$0==3 ? [4]:[0]};check("no paper before copy 2",(try? await s().run([j,j],darkness:1,on:f)) == .noPaper(finished:1,started:false) && bytes(f)==j.strips[0].count)
 for (n,r) in [("none",[]),("unknown 01",[1]),("unknown 02",[2]),("unknown ff",[0xff]),("OK",[0x4f,0x4b])] as [(String,[UInt8])]{f=Fake();f.status={_ in r};check("status \(n) never blocks",(try? await s().run([j],darkness:1,on:f)) == .printed)}
 check("no-paper flag",Sender.noPaper(Data([6])) && Sender.noPaper(Data([4])) && !Sender.noPaper(Data([2])) && !Sender.noPaper(Data([0])) && !Sender.noPaper(Data([0xff])));check("status after late OK",Sender.noPaper(Data([0x4f,0x4b,4])) && !Sender.noPaper(Data([4,0])) && !Sender.noPaper(Data()))
 // review findings
 do{let bad=Data([0x10,0xff,0x70,0xf1]);f=Fake();_=try? await s().run([long,j],darkness:0,on:f)
  let all=[Sender.reset,Sender.firmwareQuery,Sender.query]+f.sends.filter{$0.count<=16};check("never sends 70f1",all.allSatisfy{$0.range(of:bad)==nil} && !((try? String(contentsOfFile:"Sources/Printer.swift",encoding:.utf8)) ?? "0x70, 0xf1").contains("0x70, 0xf1"))
  check("handshake bytes",[UInt8](Sender.firmwareQuery)==[0x10,0xff,0x20,0xf1] && Sender.reset.count==16)
  check("battery replies",batteryLevel(Data([0,0x44]))==68 && batteryLevel(Data([0x4f,0x4b,0,100]))==100 && batteryLevel(Data([0,101]))==nil && batteryLevel(Data([0x4f,0x4b]))==nil && batteryLevel(Data())==nil)}
 final class Odd:Transport{var rx=Data();var reply=Data();func send(_ x:Data) async throws{if x==Sender.query{rx.append(reply)}}}
 var od=Odd();od.reply=Data([0x4f,0x4b]);check("stray OK is not an answer",(try? await s().run([j],darkness:1,on:od)) == .unconfirmed(finished:0))
 od=Odd();od.reply=Data([0x01,0x04]);check("odd 2-byte reply is not an answer",(try? await s().run([j],darkness:1,on:od)) == .unconfirmed(finished:0))
 od=Odd();od.reply=Data([0x4f,0x4b,0,0x56]);check("late OK then battery is an answer",(try? await s().run([j],darkness:1,on:od)) == .printed)
 let n1=1+20 // darkness + slices of a 1000-row strip
 f=Fake();let g1=f;check("cancel between strips: feed, answer, cancelled",(try? await s({g1.sends.count>=n1}).run([long],darkness:1,on:f)) == .cancelled(finished:0) && f.sends.suffix(2)==[Sender.feed,Sender.query] && bytes(f)==strip(1000).count)
 f=Fake();f.answer={_ in false};let g2=f;check("cancel between strips, silent printer = unconfirmed",(try? await s({g2.sends.count>=n1}).run([long],darkness:1,on:f)) == .unconfirmed(finished:0))
 f=Fake();f.answer={_ in false};let g3=f;check("padded cancel, silent printer = unconfirmed",(try? await s({g3.sends.count>=2}).run([j],darkness:1,on:f)) == .unconfirmed(finished:0))
 for at in [3,4,5]{f=Fake();f.failAt=at;let g=f;var e="";do{_=try await s({g.sends.count>=2}).run([j],darkness:1,on:f)}catch{e=error.localizedDescription};check("drop during cancel at \(at) is reported: \(e.suffix(40))",e.contains("off and on"))}
 // encoder
 for h in [321,1000,1001,2500]{let b=try! Encoder.render(flat(100,384,h),mode:.photo,turns:0);let bk=Encoder.strips(b);var ok=true,rows=0
  for d in bk{let x=[UInt8](d);let n=Int(x[22])+Int(x[23])*256;ok=ok&&x[16]==0x1d&&x[20]==48&&x.count==24+n*48
   for r in 0..<n{for c in 0..<384{let bit=(x[24+r*48+c/8]>>UInt8(7-c%8))&1;if (bit==1) != (b.px[(rows+r)*384+c]==0){ok=false}}};rows+=n}
  check("strip bytes equal preview, \(rows) rows in \(bk.count)",ok&&rows==h&&bk.count==(h+999)/1000)}
 let mid=flat(128,200,200);let b0=try! Encoder.render(mid,mode:.photo,turns:0)
 let hi=try! Encoder.render(mid,mode:.photo,turns:0,brightness:0.6),lo=try! Encoder.render(mid,mode:.photo,turns:0,brightness:-0.6)
 check("brightness \(black(lo)) > \(black(b0)) > \(black(hi))",black(lo)>black(b0)&&black(b0)>black(hi))
 let t=Encoder.trimmed(flat(255,300,300,CGRect(x:50,y:100,width:20,height:40)));check("trim \(t.width)x\(t.height)",t.width==20&&t.height==40)
 let pale=Encoder.trimmed(flat(255,300,300,CGRect(x:50,y:100,width:20,height:40)));check("trim keeps content",pale.width==20)
 do{let c=CGContext(data:nil,width:100,height:100,bitsPerComponent:8,bytesPerRow:400,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.setFillColor(red:1,green:1,blue:1,alpha:1);c.fill(CGRect(x:10,y:20,width:60,height:50));let t=Encoder.trimmed(c.makeImage()!);check("white on transparent kept \(t.width)x\(t.height)",t.width==60&&t.height==50)}
 do{let t=try Encoder.render(flat(0,100,50),mode:.photo,turns:0,trim:true);let m=Encoder.trimMargin;check("margin \(t.width)x\(t.height)",t.width==384&&(0..<384).allSatisfy{t.px[$0]==255}&&(0..<t.height).allSatisfy{t.px[$0*384]==255&&t.px[$0*384+383]==255}&&t.px[m*384+m]==0)
  let s0=try Encoder.render(flat(0,100,50),mode:.photo,turns:1,trim:true);check("margin sideways",(0..<s0.height).allSatisfy{s0.px[$0*384]==255&&s0.px[$0*384+383]==255})}catch{check("margin",false)}
 do{let b=try Encoder.render(flat(120,100,50),mode:.photo,turns:0);func mean(_ k:Int)->Int{let d=[UInt8](Encoder.preview(b,strength:k)!.dataProvider!.data! as Data);return d.reduce(0){$0+Int($1)}/d.count};check("preview darker with strength \(mean(0))>\(mean(1))>\(mean(2))",mean(0)>mean(1)&&mean(1)>mean(2))}catch{check("preview",false)}
 do{ // calibrated preview: 10...100 % patches against a photo of a printed strip
  let cov=[10,20,30,40,50,65,80,100];let want:[[Double]]=[[0.96,0.96,0.93,0.85,0.77,0.63,0.49],[0.97,0.93,0.87,0.79,0.66,0.49,0.36,0.29],[0.97,0.94,0.88,0.78,0.61,0.43,0.35,0.31]]
  func lin(_ v:UInt8)->Double{let x=Double(v)/255;return x<=0.04045 ? x/12.92:pow((x+0.055)/1.055,2.4)}
  var prev=[Double](repeating:2,count:8)
  for k in 0..<3{var got:[Double]=[]
   for c in cov{let g=UnsafeMutablePointer<UInt8>.allocate(capacity:384*94);g.initialize(repeating:UInt8(255-255*c/100),count:384*94);let b=Encoder.toBits(g,384,94,.photo);g.deallocate()
    let d=[UInt8](Encoder.preview(b,strength:k)!.dataProvider!.data! as Data);var t=0.0,n=0;for y in 4..<90{for x in 4..<380{t+=lin(d[y*384+x]);n+=1}};let l=t/Double(n);got.append(l<=0.0031308 ? 12.92*l:1.055*pow(l,1/2.4)-0.055)}
   let worst=zip(got,want[k]).map{abs($0-$1)}.max()!
   check("calibrated \(k): worst \((worst*1000).rounded()/1000)",worst<0.06);check("monotonic \(k)",zip(got,got.dropFirst()).allSatisfy{$0>$1} && zip(got,prev).allSatisfy{$0<=$1+0.005});prev=got}}
 check("printer text cleaned",cleanReply("A\u{1b}[31m\n\u{202e}B"+String(repeating:"x",count:100)).count==40 && cleanReply("a\nb\u{0}")=="ab")
 check("trim blank",Encoder.trimmed(flat(255,30,40)).height==40);check("trim black",Encoder.trimmed(flat(0,30,40)).width==30)
 // text
 for (n,z) in TextRender.sizes{for a in TextAlign.allCases{let b=try? TextRender.render("Bonjour, été déjà",size:z,bold:true,align:a)
   check("text \(n) \(a) \(b?.height ?? 0) rows, \(b.map(black) ?? 0)% black",b != nil && black(b!)>1)}}
 for (n,x) in [("empty",""),("spaces","  \n ")]{check(n,(try? TextRender.render(x,size:32,bold:false,align:.left))==nil)}
 for (n,x) in [("long word",String(repeating:"W",count:300)),("emoji","Hi 😀🎉"),("arabic","مرحبا بالعالم"),("blank lines","a\n\n\nb"),("200 lines",(1...200).map{"Line \($0)"}.joined(separator:"\n"))]{
   let b=try? TextRender.render(x,size:32,bold:false,align:.left);check("\(n) \(b?.height ?? 0)",b != nil && b!.px.contains(0))}
 check("too long",(try? TextRender.render((1...2000).map{"\($0)"}.joined(separator:"\n"),size:76,bold:false,align:.left))==nil)
 // rotated text
 func rt(_ x:String,_ n:Int,_ z:CGFloat=32)->Bitmap?{try? TextRender.render(x,size:z,bold:true,align:.left,turns:n)}
 for n in 0..<4{let b=rt("Hello déjà",n);check("rotated \(n): \(b?.width ?? 0)x\(b?.height ?? 0)",b?.width==384 && b!.px.contains(0))}
 check("180 = flipped 0",rt("Hi",2)!.px==Array(rt("Hi",0)!.px.reversed()));check("270 = flipped 90",rt("Hi",3)!.px==Array(rt("Hi",1)!.px.reversed()))
 let rr=rt("Ab",1)!;check("4 turns = same",TextRender.rotated(rr,4).px==rr.px && TextRender.rotated(TextRender.rotated(rr,1),3).px==rr.px)
 check("longer text = longer paper",rt("Hello Hello Hello",1)!.height>rt("Hello",1)!.height)
 check("many lines shrink",rt((1...12).map{"Line \($0)"}.joined(separator:"\n"),1,76)?.width==384);check("too many lines refused",rt((1...300).map{"\($0)"}.joined(separator:"\n"),1)==nil)
 check("sideways emoji",rt("Hi 😀",1) != nil);check("sideways empty refused",rt(" \n ",1)==nil);check("sideways too long refused",rt(String(repeating:"W",count:2000),1,76)==nil)
 check("no clipping at ends",{let b=rt("WWWWjgy",1)!;return (0..<384).allSatisfy{b.px[$0]==255}&&(0..<384).allSatisfy{b.px[(b.height-1)*384+$0]==255}}())
 // left/right actually differ
 func side(_ a:TextAlign)->Int{let b=try! TextRender.render("Hi",size:32,bold:false,align:a);var l=0,r=0;for y in 0..<b.height{for x in 0..<384 where b.px[y*384+x]==0{if x<192{l+=1}else{r+=1}}};return l-r}
 check("alignment",side(.left)>0&&side(.right)<0)
 // log
 let u=URL(fileURLWithPath:NSTemporaryDirectory()+"pp-test.log");try? FileManager.default.removeItem(at:u)
 let l=Log(file:u);for i in 0..<620{l.add("line \(i)\nx",error:i%10==0)}
 check("log private",(try? FileManager.default.attributesOfItem(atPath:u.path)[.posixPermissions] as? Int)==0o600);check("log cap",l.lines.count==500&&Log(file:u).lines.count==500&&Log(file:u).lines.contains{$0.error})
 l.clear();check("log clear",l.lines.isEmpty && !FileManager.default.fileExists(atPath:u.path))
 print("failures",fails)
 for p in CommandLine.arguments.dropFirst(){let t0=Date();do{let i=try Encoder.load(URL(fileURLWithPath:p));let b=try Encoder.render(i,mode:.photo,turns:0);print(p.split(separator:"/").last!,"loaded",i.width,i.height,"rows",b.height,String(format:"%.1fs",Date().timeIntervalSince(t0)))}catch{print(p.split(separator:"/").last!,"ERR",error.localizedDescription)}}
}}
