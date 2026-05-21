#!/usr/bin/env python3
import json, copy, os
LIBS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".msft-icons", "libraries", "azure-public-service-icons")
OUT  = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs")
_n = 0
def nid():
    global _n; _n += 1; return f"e{_n:04d}"
def load_icon(lib, name):
    with open(os.path.join(LIBS, lib)) as f: data = json.load(f)
    for it in data.get("libraryItems", []):
        if it.get("name") == name: return it["elements"]
    raise ValueError(f"{name} not in {lib}")
def icon_bbox(elems):
    xs=[e.get("x",0) for e in elems]; ys=[e.get("y",0) for e in elems]
    xe=[e.get("x",0)+e.get("width",0) for e in elems]; ye=[e.get("y",0)+e.get("height",0) for e in elems]
    return min(xs),min(ys),max(xe)-min(xs),max(ye)-min(ys)
def place(elems, x, y, sc=1.0, pfx=""):
    out, idm = [], {}
    mx = min(e.get("x",0) for e in elems); my = min(e.get("y",0) for e in elems)
    for e in elems:
        n = copy.deepcopy(e); oid = n.get("id",""); ni = pfx+nid()
        idm[oid] = ni; n["id"] = ni
        n["x"] = x + (n.get("x",0)-mx)*sc; n["y"] = y + (n.get("y",0)-my)*sc
        if "width" in n: n["width"] *= sc
        if "height" in n: n["height"] *= sc
        out.append(n)
    for n in out:
        if n.get("containerId") in idm: n["containerId"] = idm[n["containerId"]]
        if n.get("frameId") in idm: n["frameId"] = idm[n["frameId"]]
        if n.get("boundElements"):
            for b in n["boundElements"]:
                if b.get("id") in idm: b["id"] = idm[b["id"]]
        if n.get("groupIds"): n["groupIds"] = [pfx+g for g in n["groupIds"]]
    return out
def centered_icon(icon, cx, top_y, width, pfx):
    _,_,iw,ih = icon_bbox(icon)
    scale = width / iw
    return place(icon, cx - width/2, top_y, scale, pfx), width * (ih/iw)
def R(x,y,w,h,bg="transparent",st="#1e1e1e",sw=2,op=100,rnd=True,dash=False):
    e={"type":"rectangle","id":nid(),"x":x,"y":y,"width":w,"height":h,"strokeColor":st,"backgroundColor":bg,"fillStyle":"solid","strokeWidth":sw,"roughness":0,"opacity":op,"angle":0,"seed":1,"version":1,"isDeleted":False,"boundElements":[],"locked":False}
    if rnd: e["roundness"]={"type":3}
    if dash: e["strokeStyle"]="dashed"
    return e
def T(x,y,s,fs=16,c="#1e1e1e",align="left"):
    lines=s.split("\n")
    w=int(max(len(l) for l in lines)*fs*0.72)+10
    return{"type":"text","id":nid(),"x":x,"y":y,"width":w,"height":fs*1.3*len(lines),"text":s,"fontSize":fs,"fontFamily":1,"strokeColor":c,"backgroundColor":"transparent","fillStyle":"solid","strokeWidth":1,"roughness":0,"opacity":100,"angle":0,"textAlign":align,"verticalAlign":"top","seed":1,"version":1,"isDeleted":False,"boundElements":[],"locked":False}
def AR(x1,y1,x2,y2,st="#1e1e1e",sw=2,dash=False,label=None,wp=None):
    pts=[[0,0]]+[[wx-x1,wy-y1] for wx,wy in (wp or [])]+[[x2-x1,y2-y1]]
    e={"type":"arrow","id":nid(),"x":x1,"y":y1,"width":abs(x2-x1),"height":abs(y2-y1),"points":pts,"strokeColor":st,"backgroundColor":"transparent","fillStyle":"solid","strokeWidth":sw,"roughness":0,"opacity":100,"angle":0,"endArrowhead":"arrow","startArrowhead":None,"seed":1,"version":1,"isDeleted":False,"boundElements":[],"locked":False}
    if dash: e["strokeStyle"]="dashed"
    if label: e["label"]={"text":label,"fontSize":13}
    return e
def ctxt(bx,by,bw,bh,txt,fs=14,c="#3b0764"):
    els=[]; lines=txt.split("\n"); lh=fs*1.35; total=lh*len(lines); ty=by+(bh-total)/2
    for line in lines:
        tw=len(line)*fs*0.6; tx=bx+(bw-tw)/2; els.append(T(tx,ty,line,fs=fs,c=c)); ty+=lh
    return els
def paas_row(y, region_x, region_w, icons_labels_pfxs):
    els = []
    n = len(icons_labels_pfxs)
    tile_w = 150
    total = tile_w * n
    start_x = region_x + (region_w - total) / 2
    icon_size = 48
    centers = []
    for i, (ic_elems, lbl, pfx) in enumerate(icons_labels_pfxs):
        cx = start_x + tile_w*i + tile_w/2
        iel, _ = centered_icon(ic_elems, cx, y, icon_size, pfx)
        els += iel
        for li, line in enumerate(lbl.split("\n")):
            tw = len(line)*11*0.6
            els.append(T(cx - tw/2, y + icon_size + 8 + li*14, line, fs=11, c="#333"))
        centers.append(cx)
    return els, y + icon_size/2, centers
def main():
    print("Loading icons...")
    ic={"vnet":load_icon("networking.excalidrawlib","Virtual Networks"),
        "vm":load_icon("compute.excalidrawlib","Virtual Machine"),
        "appsvc":load_icon("app-services.excalidrawlib","App Services"),
        "appplan":load_icon("app-services.excalidrawlib","App Service Plans"),
        "sql":load_icon("databases.excalidrawlib","Azure SQL"),
        "rsv":load_icon("management-governance.excalidrawlib","Recovery Services Vaults")}
    E=[]
    PX,PY,PW,PH = 40, 80, 620, 640
    SX,SY,SW,SH = 740, 80, 620, 640
    CX,CY,CW,CH = 120, 770, 1160, 130
    E.append(T(540, 20, "Azure DR Sandbox \u2014 Architecture", fs=26, align="center"))

    # PRIMARY REGION
    E.append(R(PX,PY,PW,PH, bg="#dbe4ff", st="#4a9eed", sw=2, op=30))
    E.append(T(PX+15, PY+12, "Primary Region (AZURE_LOCATION)", fs=17, c="#2563eb"))

    # VNet (IaaS) top band
    vx, vy, vw, vh = PX+20, PY+50, PW-40, 210
    E.append(R(vx, vy, vw, vh, bg="#a5d8ff", st="#4a9eed", sw=1, op=22))
    vn_el, _ = centered_icon(ic["vnet"], vx+30, vy+14, 36, "pvn_")
    E += vn_el
    E.append(T(vx+60, vy+18, "Primary VNet", fs=15, c="#1e3a5f"))
    E.append(T(vx+60, vy+44, "iaas-subnet  \u2022  test-failover-subnet", fs=10, c="#555"))
    vm_y = vy + 90
    vm_tile_w = 140
    vm_start = vx + (vw - vm_tile_w*3)/2
    vm_centers = []
    for i,lbl in enumerate(["Linux VM 1","Linux VM 2","Win VM"]):
        cx = vm_start + vm_tile_w*i + vm_tile_w/2
        iel, _ = centered_icon(ic["vm"], cx, vm_y, 42, f"pvm{i}_")
        E += iel
        tw = len(lbl)*10*0.6
        E.append(T(cx - tw/2, vm_y + 50, lbl, fs=10, c="#333"))
        vm_centers.append(cx)

    # PaaS row below VNet
    paas_y = PY + 290
    pe, p_center_y, p_centers = paas_row(paas_y, PX, PW, [
        (ic["appplan"], "App Service Plan", "pasp_"),
        (ic["appsvc"],  "Web App",          "pwa_"),
        (ic["sql"],     "Azure SQL\n(Primary)", "psql_"),
    ])
    E += pe

    # RSV bottom-left
    rsv_y = PY + 440
    E.append(R(PX+20, rsv_y, 240, 140, bg="#fff3bf", st="#f59e0b", sw=1, op=28))
    rsv_el, _ = centered_icon(ic["rsv"], PX+140, rsv_y+18, 52, "rsv_")
    E += rsv_el
    E.append(T(PX+65, rsv_y+82, "Recovery Services Vault", fs=12, c="#92400e"))
    E.append(T(PX+70, rsv_y+102, "(ASR orchestration)", fs=10, c="#b45309"))

    # SECONDARY REGION
    E.append(R(SX,SY,SW,SH, bg="#d3f9d8", st="#22c55e", sw=2, op=30))
    E.append(T(SX+15, SY+12, "Secondary Region (DR_SECONDARY_LOCATION)", fs=17, c="#15803d"))
    svx, svy, svw, svh = SX+20, SY+50, SW-40, 210
    E.append(R(svx, svy, svw, svh, bg="#b2f2bb", st="#22c55e", sw=1, op=22))
    sv_el, _ = centered_icon(ic["vnet"], svx+30, svy+14, 36, "svn_")
    E += sv_el
    E.append(T(svx+60, svy+18, "Secondary VNet", fs=15, c="#14532d"))
    E.append(T(svx+60, svy+44, "iaas-subnet  \u2022  test-failover-subnet", fs=10, c="#555"))
    E.append(T(svx+(svw-430)/2, svy+105, "(Standby \u2014 VM replicas materialize on failover)",
               fs=13, c="#15803d"))

    spaas_y = SY + 290
    se, s_center_y, s_centers = paas_row(spaas_y, SX, SW, [
        (ic["appplan"], "App Service Plan", "sasp_"),
        (ic["appsvc"],  "Web App",          "swa_"),
        (ic["sql"],     "Azure SQL\n(Geo-secondary)", "ssql_"),
    ])
    E += se

    # CROSS-REGION ARROWS
    # IaaS VNet -> VNet at VM row
    E.append(AR(vx+vw, vm_y+20, svx, vm_y+20, st="#8b5cf6", sw=2, dash=True))
    E.append(T((vx+vw+svx)/2 - 55, vm_y + 0, "ASR replication", fs=12, c="#8b5cf6"))
    # PaaS: App Service Plan -> App Service Plan (at icon center y)
    E.append(AR(p_centers[0]+30, p_center_y, s_centers[0]-30, s_center_y,
                st="#06b6d4", sw=2, dash=True))
    E.append(T((p_centers[0]+s_centers[0])/2 - 48, p_center_y - 18, "Traffic reroute", fs=12, c="#06b6d4"))
    # PaaS: SQL -> SQL
    E.append(AR(p_centers[2]+30, p_center_y, s_centers[2]-30, s_center_y,
                st="#ef4444", sw=2, dash=True))
    E.append(T((p_centers[2]+s_centers[2])/2 - 48, p_center_y - 18, "Failover group", fs=12, c="#ef4444"))

    # RSV management: route out right, up through gutter BETWEEN regions, into secondary VNet left edge
    rsv_right_x = PX + 260
    rsv_mid_y   = rsv_y + 70
    gutter_x    = (PX + PW + SX) / 2           # midpoint between regions
    vnet_mid_y  = vy + vh/2
    E.append(AR(rsv_right_x, rsv_mid_y, svx, vnet_mid_y + 40,
                st="#f59e0b", sw=2, dash=True,
                wp=[(gutter_x, rsv_mid_y),
                    (gutter_x, vnet_mid_y + 40)]))
    E.append(T(gutter_x - 48, rsv_mid_y - 20, "ASR mgmt", fs=12, c="#f59e0b"))

    # CONTROL BAR
    E.append(R(CX,CY,CW,CH, bg="#e5dbff", st="#8b5cf6", sw=2, op=30))
    E.append(T(CX+15, CY+10, "Control & Automation", fs=17, c="#5b21b6"))
    by2 = CY + 48; bh2 = 62
    boxes=[(CX+30,220,"Azure Continuity\nCenter"),
           (CX+290,220,"azd CLI + hooks"),
           (CX+550,220,"scripts/asr +\nscripts/scenarios")]
    for bx,bw,bt in boxes:
        E.append(R(bx,by2,bw,bh2, bg="#d0bfff", st="#8b5cf6", sw=1, op=65))
        E.extend(ctxt(bx,by2,bw,bh2,bt, fs=13))

    lx, ly = CX + 820, CY + 18
    E.append(R(lx-12, ly-10, 330, 105, bg="#ffffff", st="#bbb", sw=1, op=90))
    E.append(T(lx, ly, "Legend", fs=13, c="#333"))
    E.append(T(lx, ly+22, "\u2500\u2500  ASR replication",  fs=11, c="#8b5cf6"))
    E.append(T(lx, ly+40, "\u2500\u2500  Failover group",   fs=11, c="#ef4444"))
    E.append(T(lx, ly+58, "\u2500\u2500  Traffic reroute",  fs=11, c="#06b6d4"))
    E.append(T(lx, ly+76, "\u2500\u2500  RSV management",   fs=11, c="#f59e0b"))

    doc = {"type":"excalidraw","version":2,"source":"azure-bcdr-lab",
           "elements":E,"appState":{"gridSize":None,"viewBackgroundColor":"#ffffff"},"files":{}}
    p = os.path.join(OUT, "architecture.excalidraw")
    with open(p,"w") as f: json.dump(doc,f,indent=2)
    print(f"Wrote {len(E)} elements -> {p}")
if __name__=="__main__": main()
