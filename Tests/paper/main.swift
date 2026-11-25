// Out-of-paper probe. Only asks questions unless --go is given; then it sends one tiny, almost white strip.
import Foundation
setbuf(stdout,nil)
DispatchQueue.global().asyncAfter(deadline:.now()+110){print("TIMEOUT");exit(9)}
let go=CommandLine.arguments.contains("--go")
func hx(_ d:Data)->String{d.isEmpty ? "-" : d.map{String(format:"%02x",$0)}.joined()}
Task{@MainActor in let p=Printer();p.log={s,e in print("  ",s)};do{_=try await p.connect()
 @MainActor func ask(_ n:String,_ c:[UInt8],_ t:Double=1.2)async throws{p.rx=Data();try await p.send(Data(c));try await Task.sleep(nanoseconds:UInt64(t*1e9));print(n,hx(p.rx))}
 p.rx=Data();try await Task.sleep(nanoseconds:5_000_000_000);print("unsolicited 5s",hx(p.rx))
 for _ in 1...5{try await ask("10ff40",[0x10,0xff,0x40],0.6);try await ask("battery",[0x10,0xff,0x50,0xf1],0.5)}
 if go{var b=Bitmap(width:384,height:60,px:[UInt8](repeating:255,count:384*60));for y in 0..<60{for x in [10,373]{b.px[y*384+x]=0}}
  print("black %",Double(b.px.filter{$0==0}.count)*100/Double(b.px.count));p.rx=Data();try await p.send(Data([0x10,0xff,0x10,0,1]));try await Task.sleep(nanoseconds:400_000_000);print("dark ack",hx(p.rx))
  p.rx=Data();try await p.send(Encoder.strips(b)[0]);try await p.send(Sender.feed);print("strip sent")
  for k in 1...4{try await Task.sleep(nanoseconds:3_000_000_000);print("unsolicited",k*3,"s",hx(p.rx));p.rx=Data();try await ask(" 10ff40",[0x10,0xff,0x40],0.8);try await ask(" battery",[0x10,0xff,0x50,0xf1],0.8);p.rx=Data()}}
 }catch{print("ERROR",error.localizedDescription)};await p.close();exit(0)}
RunLoop.main.run()
