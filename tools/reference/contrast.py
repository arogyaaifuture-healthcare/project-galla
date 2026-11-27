def lum(h):
    h=h.lstrip('#'); c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    c=[x/12.92 if x<=0.03928 else ((x+0.055)/1.055)**2.4 for x in c]
    return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2]
def cr(a,b):
    la,lb=sorted((lum(a),lum(b)),reverse=True); return (la+0.05)/(lb+0.05)
pairs={
 "LIGHT text on bg":("#212529","#F8F9FA",4.5),"LIGHT text on surface":("#212529","#FFFFFF",4.5),
 "LIGHT muted on surface":("#5F6672","#FFFFFF",4.5),"LIGHT muted on bg":("#5F6672","#F8F9FA",4.5),
 "LIGHT muted on surface-2":("#5F6672","#F1F3F5",4.5),
 "LIGHT white on primary":("#FFFFFF","#C2410C",4.5),"LIGHT white on primary-hover":("#FFFFFF","#9A3412",4.5),
 "LIGHT primary text on primary-soft":("#C2410C","#FFEDD5",4.5),
 "LIGHT success-text on soft":("#1E7A34","#EBFBEE",4.5),"LIGHT warning-text on soft":("#A15C00","#FFF9DB",4.5),
 "LIGHT danger-text on soft":("#C92A2A","#FFF5F5",4.5),"LIGHT info-text on soft":("#1864AB","#E7F5FF",4.5),
 "LIGHT danger-text on surface":("#C92A2A","#FFFFFF",4.5),"LIGHT white on danger button":("#FFFFFF","#E03131",4.5),
 "LIGHT control border on surface (3:1)":("#7A828B","#FFFFFF",3.0),"LIGHT control border on surface-2 (3:1)":("#7A828B","#F1F3F5",3.0),
 "LIGHT primary-accent focus ring vs surface (3:1)":("#EA580C","#FFFFFF",3.0),
 "LIGHT white on platform":("#FFFFFF","#4338CA",4.5),"LIGHT platform on platform-soft":("#4338CA","#E0E7FF",4.5),
 "DARK text on bg":("#F3F4F6","#0B1220",4.5),"DARK text on surface":("#F3F4F6","#111827",4.5),
 "DARK muted on surface":("#9CA3AF","#111827",4.5),"DARK muted on surface-2":("#9CA3AF","#1F2937",4.5),
 "DARK button text on primary":("#111827","#F97316",4.5),"DARK button text on primary-hover":("#111827","#FB923C",4.5),
 "DARK control border on surface (3:1)":("#7B8494","#111827",3.0),"DARK control border on surface-2 (3:1)":("#7B8494","#1F2937",3.0),
 "DARK platform text on surface":("#A5B4FC","#111827",4.5),
}
if __name__=="__main__":
  bad=0
  for k,(f,b,t) in pairs.items():
    r=cr(f,b); ok=r>=t; bad+= (not ok); print(f"{'PASS' if ok else 'FAIL'} {r:5.2f} (need {t}) {k}  {f} on {b}")
  print("failures:",bad)
