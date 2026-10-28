// Millimetres. One continuous hollow wall made from fused, rounded bead profiles.
// Diameter denotes the maximum outer envelope; width is the full radial bead width.
let cachedKey='',cachedProfile;
export function specimenSpec(s){const diameter=s.workpieceDiameter,height=s.workpieceHeight,layerHeight=s.printLayerHeight??4,lineWidth=s.printLineWidth??9;return {diameter,height,layerHeight,lineWidth,layers:Math.ceil(height/layerHeight-1e-9),innerDiameter:diameter-2*lineWidth};}
export function specimenProfile(s){
 const a=specimenSpec(s),key=[a.diameter,a.height,a.layerHeight,a.lineWidth].join(':');if(key===cachedKey)return cachedProfile;
 const R=a.diameter/2,outer=[],inner=[],steps=6;
 for(let k=0;k<a.layers;k++){
  const z=k*a.layerHeight,h=Math.min(a.layerHeight,a.height-z),r=h/2;
  for(let j=0;j<=steps;j++){const t=Math.PI*j/steps,y=z+r-r*Math.cos(t);outer.push([R-r+r*Math.sin(t),y]);inner.push([R-a.lineWidth+r-r*Math.sin(t),y]);}
 }
 const points=[...outer,...inner.reverse(),outer[0]].filter((p,i,a)=>i===0||Math.hypot(p[0]-a[i-1][0],p[1]-a[i-1][1])>1e-9);
 cachedKey=key;cachedProfile={...a,points};return cachedProfile;
}
export function specimenDistance(s,rho,height){
 const {points}=specimenProfile(s);let distance2=Infinity,inside=false;
 for(let i=0;i<points.length-1;i++){
  const [x,y]=points[i],[xx,yy]=points[i+1],dx=xx-x,dy=yy-y,l=dx*dx+dy*dy;
  const t=l?Math.max(0,Math.min(1,((rho-x)*dx+(height-y)*dy)/l)):0;
  distance2=Math.min(distance2,(rho-x-t*dx)**2+(height-y-t*dy)**2);
  if((y>height)!==(yy>height)&&rho<(xx-x)*(height-y)/(yy-y)+x)inside=!inside;
 }
 return Math.sqrt(distance2)*(inside?-1:1);
}
