// Connects repeatedly at random gaps: first attempts only, no reuse. Never prints. usage: conn [count]
import Foundation
setbuf(stdout,nil)
let count=CommandLine.arguments.count>1 ? Int(CommandLine.arguments[1])! : 4
DispatchQueue.global().asyncAfter(deadline:.now()+Double(count)*25+30){print("TIMEOUT");exit(9)}
Task{@MainActor in var bad=0,slow=0.0
 for k in 1...count{let g=[0,0,0.05,0.2,0.5,1,1.5,1.8,2,2,2.2,2.5,3,4].randomElement()!;try? await Task.sleep(nanoseconds:UInt64(g*1e9))
  let p=Printer();p.maxAttempts=1;let t=uptime();p.log={s,e in if e{print("   ",s)}}
  do{_=try await p.connect();let c=uptime()-t;slow=max(slow,c);let t2=uptime();await p.close();print("run",k,String(format:"gap %.2f connect+identify %.1fs close %.2fs",g,c,uptime()-t2))}catch{bad+=1;print("run",k,"gap",g,"FAILED",error.localizedDescription.prefix(40));await p.close()}}
 print("runs",count,"failed first attempts",bad,String(format:"slowest %.1fs",slow));exit(0)}
RunLoop.main.run()
