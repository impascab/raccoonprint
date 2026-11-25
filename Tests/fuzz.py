"""Mutates sample files and checks the decoders don't crash or hang. usage: fuzz.py FUZZ_BINARY SAMPLE_DIR COUNT"""
import os,random,subprocess,sys,tempfile,resource
binp,src,N=sys.argv[1],sys.argv[2],int(sys.argv[3]);random.seed(1)
S=[os.path.join(src,f) for f in os.listdir(src) if f.lower().rsplit('.',1)[-1] in('png','jpg','gif','tif','heic','pdf')]
d=tempfile.mkdtemp();bad=0;peak=0
def mut(b):
    b=bytearray(b)
    for _ in range(random.choice((1,3,10,50))):
        k=random.randrange(5);i=random.randrange(max(1,len(b)))
        if not b: break
        if k==0:b[i]^=1<<random.randrange(8)
        elif k==1:b[i]=random.choice((0,255,127,128))
        elif k==2:b[i:i+4]=random.choice((b'\xff\xff\xff\xff',b'\x00\x00\x00\x00',b'\x7f\xff\xff\xff'))
        elif k==3:del b[i:i+random.randrange(1,64)]
        else:b[i:i]=b[:random.randrange(1,64)]
    return bytes(b[:random.randrange(len(b)+1)]) if random.random()<.1 else bytes(b)
for g in range(0,N,20):
    fs=[]
    for k in range(20):
        s=random.choice(S);p=os.path.join(d,f'{k}.{s.rsplit(".",1)[-1]}');open(p,'wb').write(mut(open(s,'rb').read()));fs.append(p)
    try:
        r=subprocess.run([binp]+fs,capture_output=True,timeout=90);out=r.stdout.decode(errors='replace')
        if r.returncode: bad+=1;last=[l for l in out.splitlines() if l.startswith('START')][-1:];print('CRASH',r.returncode,last);[os.system(f"cp '{l.split(' ',1)[1]}' '{d}/../crash{bad}.bin'") for l in last]
    except subprocess.TimeoutExpired as e: bad+=1;print('HANG',(e.stdout or b'')[-120:])
print('files',N,'problems',bad,'peak MB',resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss//1048576)
