// Measures reconnects at different gaps. Single attempt each, no retries. Only a battery query is sent; never prints.
import Foundation
import IOBluetooth
setbuf(stdout,nil)
let arg=CommandLine.arguments, per=Int(arg.dropFirst().first ?? "8")!, waitClosed=arg.contains("--wait-closed"), acl=arg.contains("--acl")
DispatchQueue.global().asyncAfter(deadline:.now()+560){print("TIMEOUT");exit(9)}
func now()->Double{Double(DispatchTime.now().uptimeNanoseconds)/1e9}
func spin(_ s:Double,_ f:()->Bool={false}){let e=now()+s;while now()<e && !f(){RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.01))}}
final class N:NSObject{var down=false;@objc func gone(_ n:IOBluetoothUserNotification,device:IOBluetoothDevice){down=true;n.unregister()}}
final class D:NSObject,IOBluetoothRFCOMMChannelDelegate{var opened:IOReturn?;var closed=false;var rx=0
 func rfcommChannelOpenComplete(_ c:IOBluetoothRFCOMMChannel!,status:IOReturn){opened=status}
 func rfcommChannelClosed(_ c:IOBluetoothRFCOMMChannel!){closed=true}
 func rfcommChannelData(_ c:IOBluetoothRFCOMMChannel!,data p:UnsafeMutableRawPointer!,length n:Int){rx+=n}}
guard let dev=(IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where:{($0.name ?? "").hasPrefix("PeriPage")}) else{print("no printer");exit(1)}
let gaps:[Double]=[0,0.2,0.5,1,2,4];var plan=gaps.flatMap{g in Array(repeating:g,count:per)}.shuffled()
var stat=[Double:(ok:Int,fail:Int,max:Double)]();var keep:[Any]=[]
var aclT:(Double,Double,Bool,Bool)=(0,0,false,false);var worstACL=0.0,noNote=0
var lastClose="first";var n=0
for g in [5.0]+plan {
 spin(g);let d=D();keep.append(d);var ch:IOBluetoothRFCOMMChannel?;let acl0=dev.isConnected(),t=now()
 let r=dev.openRFCOMMChannelAsync(&ch,withChannelID:1,delegate:d);spin(6){d.opened != nil};let dt=now()-t
 let ok=d.opened==kIOReturnSuccess
 var info="";var closeT = -1.0
 if ok,let c=ch{var q:[UInt8]=[0x10,0xff,0x50,0xf1];_ = c.writeSync(&q,length:4);spin(1){d.rx>=2};info="rx\(d.rx)"}
 if let c=ch{let t2=now();if !waitClosed{c.setDelegate(nil)};c.close();if waitClosed{spin(3){d.closed};closeT=now()-t2};if acl{let w=N();keep.append(w);let reg=dev.register(forDisconnectNotification:w,selector:#selector(N.gone(_:device:)));let t3=now();dev.closeConnection();let t4=now();spin(6){w.down || !dev.isConnected()};let note=w.down;if !note{spin(0.3){w.down}};aclT=(t4-t3,now()-t3,w.down,dev.isConnected());_ = reg};info+=String(format:" close %.2f%@",closeT,d.closed ? " cb":"")}
 if n>0{var s=stat[g] ?? (0,0,0);if ok{s.ok+=1}else{s.fail+=1};s.max=max(s.max,dt);stat[g]=s}
 if !ok || dt>1.5{print(String(format:"#%d gap %.1f start-acl %@ %@ %.1fs r=%08x st=%@",n,g,acl0 ? "up":"down",ok ? "slow":"FAIL",dt,r,d.opened.map{String(format:"%08x",$0)} ?? "none"),info,"prev:",lastClose)}
if acl{worstACL=max(worstACL,aclT.1);if !aclT.2{noNote+=1}}
 lastClose=info+(ok ? " ok":" fail");n+=1
}
if acl{print("closeConnection: longest wait until down",String(format:"%.2fs",worstACL),"missing notifications",noNote)}
for g in gaps{let s=stat[g] ?? (0,0,0);print(String(format:"gap %.1f: ok %d fail %d slowest %.1fs",g,s.ok,s.fail,s.max))}
