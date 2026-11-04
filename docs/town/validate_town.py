import json, math, sys
t=json.load(open(sys.argv[1])); E=[]
B=t["boxes"]; Z={z["id"]:z for z in t["zones"]}; C=t["player_clearance"]; BK=set(t["blocking_kinds"])
ids=[b["id"] for b in B]+[m["id"] for m in t["markers"]]
if len(ids)!=len(set(ids)): E.append("duplicate ids")
for b in B:
    if any(b["min"][i]>=b["max"][i] for i in range(3)): E.append(f"bad minmax {b['id']}")
    if b["kind"]=="overhead" and b["min"][1]<2.2: E.append(f"low overhead {b['id']}")
    if b["zone"] in Z:
        z=Z[b["zone"]]
        if not(b["min"][0]>=z["min"][0] and b["max"][0]<=z["max"][0] and b["min"][2]>=z["min"][1] and b["max"][2]<=z["max"][1]): E.append(f"outside zone {b['id']}")
    elif b["zone"] not in ("ground","perimeter"): E.append(f"unknown zone {b['id']}")
# Issue #237: a round box (shape "round", a stair tower, a lookout) is its circle, not its square.
def is_round(b): return b.get("shape")=="round" or b["kind"] in ("spiral","lookout")
def round_r(b): return min(b["max"][0]-b["min"][0], b["max"][2]-b["min"][2])/2
def ctr(b): return ((b["min"][0]+b["max"][0])/2, (b["min"][2]+b["max"][2])/2)
def round_overlap(a,b):
    if not is_round(a) and not is_round(b): return True
    if is_round(a) and is_round(b): return math.dist(ctr(a),ctr(b)) < round_r(a)+round_r(b)-0.001
    c,o=(a,b) if is_round(a) else (b,a); x,z=ctr(c)
    dx=max(o["min"][0]-x,0,x-o["max"][0]); dz=max(o["min"][2]-z,0,z-o["max"][2])
    return math.hypot(dx,dz) < round_r(c)-0.001
for i in range(len(B)):
    for j in range(i+1,len(B)):
        a,b=B[i],B[j]
        if a.get("hollow") or b.get("hollow"): continue
        if all(a["min"][k]<b["max"][k] and b["min"][k]<a["max"][k] for k in range(3)) and round_overlap(a,b): E.append(f"overlap {a['id']} {b['id']}")
def seg_box_dist(p,q,b):
    # sample distance from segment to rect
    best=1e9; n=max(2,int(math.dist(p,q)/0.1))
    for s in range(n+1):
        x=p[0]+(q[0]-p[0])*s/n; z=p[1]+(q[1]-p[1])*s/n
        dx=max(b["min"][0]-x,0,x-b["max"][0]); dz=max(b["min"][2]-z,0,z-b["max"][2])
        best=min(best,math.hypot(dx,dz))
    return best
for m in t["markers"]:
    x,y,z=m["pos"]
    for b in B:
        if b["kind"] in BK and b["min"][1]<=y<b["max"][1]:
            dx=max(b["min"][0]-x,0,x-b["max"][0]); dz=max(b["min"][2]-z,0,z-b["max"][2])
            if math.hypot(dx,dz)<=C: E.append(f"marker {m['id']} blocked by {b['id']}")
    sup=[b for b in B if (b["kind"] in ("floor","solid") or b.get("standable")) and abs(b["max"][1]-y)<0.05 and b["min"][0]<=x<=b["max"][0] and b["min"][2]<=z<=b["max"][2]]
    if not sup: E.append(f"marker {m['id']} unsupported")
for r in t["routes"]:
    L=0
    for p,q in zip(r["points"],r["points"][1:]):
        L+=math.dist(p,q)
        for b in B:
            # Issue #321: a box 2.2 m or more up (on a roof) is over the walker's head.
            if b["kind"] in BK and b["min"][1]<2.2 and seg_box_dist(p,q,b)<=C: E.append(f"route {r['id']} seg {p}->{q} hits {b['id']}")
    print(f"{r['id']}: {L:.1f} m, walk {L/4:.0f}s, sprint {L/7:.0f}s")
# V9 (issue #237): a round wall (kind "ring") blocks piece by piece, open at its gaps.
# Same pieces as src/systems/world/ring_wall.gd.
def ring_pieces(b):
    r=(b["max"][0]-b["min"][0])/2; t=min(max(b.get("thickness",2.0),0.1),r); rm=r-t/2
    cx=(b["min"][0]+b["max"][0])/2; cz=(b["min"][2]+b["max"][2])/2; piece=b.get("piece",6.0)
    cuts=sorted([((math.radians(g.get("deg",0))-math.asin(min(1,g.get("half",1)/rm)))%(2*math.pi),
        math.asin(min(1,g.get("half",1)/rm))*2) for g in b.get("gaps",[])])
    spans=[(0,2*math.pi)] if not cuts else [(cuts[i][0]+cuts[i][1], cuts[(i+1)%len(cuts)][0]+(2*math.pi if i+1==len(cuts) else 0)) for i in range(len(cuts))]
    out=[]
    for a0,a1 in spans:
        n=max(1,math.ceil((a1-a0)*rm/piece))
        for i in range(n):
            p0=a0+(a1-a0)*i/n; p1=a0+(a1-a0)*(i+1)/n; m=(p0+p1)/2; h=(p1-p0)/2
            out.append((cx+math.cos(m)*rm*math.cos(h), cz+math.sin(m)*rm*math.cos(h), m, (2*rm*math.sin(h)+t*math.tan(h))/2, t/2))
    return (cx,cz,r,r-t), out
def ring_dist(info,ps,x,z):
    cx,cz,r,ri=info; d=math.hypot(x-cx,z-cz)
    if d<ri-3 or d>r+3: return 1e9
    best=1e9
    for px,pz,m,hx,hz in ps:
        ux,uz=-math.sin(m),math.cos(m); nx,nz=math.cos(m),math.sin(m)
        lx=abs((x-px)*ux+(z-pz)*uz)-hx; lz=abs((x-px)*nx+(z-pz)*nz)-hz
        best=min(best,math.hypot(max(lx,0),max(lz,0)))
    return best
for b in B:
    if b["kind"]!="ring": continue
    info,ps=ring_pieces(b)
    for m in t["markers"]:
        x,y,z=m["pos"]
        if b["min"][1]<=y<b["max"][1] and ring_dist(info,ps,x,z)<=C: E.append(f"marker {m['id']} blocked by {b['id']}")
    for r in t["routes"]:
        for p,q in zip(r["points"],r["points"][1:]):
            n=max(2,int(math.dist(p,q)/0.1))
            if any(ring_dist(info,ps,p[0]+(q[0]-p[0])*s/n,p[1]+(q[1]-p[1])*s/n)<=C for s in range(n+1)):
                E.append(f"route {r['id']} seg {p}->{q} hits {b['id']}")
print("ERRORS:" if E else "OK, 0 errors"); [print(" ",e) for e in E]
