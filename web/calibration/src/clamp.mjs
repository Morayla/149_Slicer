import * as THREE from 'three';
import sculptedJaw from '../assets/sculpted-clamp.mjs';
import flangeScrew from '../assets/clamp-button-screw.mjs';
import {STLExporter} from 'three/addons/exporters/STLExporter.js';
export const clampSpec={width:110,height:25,back:45,pad:1,slotX:45,slotRadius:3.5,slotStart:15,slotEnd:30,rib:5,innerRadius:3,chamfer:.7,webHeight:18,seatHeight:8,recessRadius:6.75,screwLength:16,washerDiameter:12.5,washerThickness:1.6,washerThicknessConfirmed:false};
// Print coordinates: XY on the bed, Z upwards. One jaw is mirrored by a rigid 180° turn.
function front(x,r){return Math.sqrt(r*r-x*x)-r;}
function capsule(x,y0,y1,r){const p=new THREE.Path();p.moveTo(x-r,y0);p.lineTo(x-r,y1);p.absarc(x,y1,r,Math.PI,0,true);p.lineTo(x+r,y0);p.absarc(x,y0,r,0,-Math.PI,true);p.closePath();return p;}
// Inset adjacent triangular cells by half the rib width. Shared ribs are exactly 5 mm.
// Fillets remove aperture corners (adding material), retaining planar outer faces.
export function reliefTriangles(){
 const corners=[[-36,2.5],[36,2.5],[36,42.5],[-36,42.5]],center=[0,22.5];
 return corners.map((p,i)=>{
  const tri=[p,corners[(i+1)%4],center];
  const lengths=tri.map((_,j)=>Math.hypot(tri[(j+1)%3][0]-tri[(j+2)%3][0],tri[(j+1)%3][1]-tri[(j+2)%3][1]));
  const perimeter=lengths.reduce((a,b)=>a+b),ic=[0,1].map(k=>tri.reduce((a,v,j)=>a+v[k]*lengths[j],0)/perimeter);
  const area=Math.abs((tri[1][0]-tri[0][0])*(tri[2][1]-tri[0][1])-(tri[1][1]-tri[0][1])*(tri[2][0]-tri[0][0]))/2;
  const factor=1-(clampSpec.rib/2)/(2*area/perimeter);
  return tri.map(v=>v.map((n,k)=>ic[k]+(n-ic[k])*factor));
 });
}
function roundedTriangle(points,r){
 const path=new THREE.Path(),corners=points.map((p,i)=>{
  const a=new THREE.Vector2(...points[(i+2)%3]).sub(new THREE.Vector2(...p)).normalize();
  const b=new THREE.Vector2(...points[(i+1)%3]).sub(new THREE.Vector2(...p)).normalize();
  const half=Math.acos(a.dot(b))/2,t=r/Math.tan(half),c=new THREE.Vector2(...p).add(a.clone().add(b).normalize().multiplyScalar(r/Math.sin(half)));
  return {entry:new THREE.Vector2(...p).add(a.multiplyScalar(t)),exit:new THREE.Vector2(...p).add(b.multiplyScalar(t)),c};
 });
 path.moveTo(corners[0].entry.x,corners[0].entry.y);
 for(const {entry,exit,c} of corners){path.lineTo(entry.x,entry.y);path.absarc(c.x,c.y,r,Math.atan2(entry.y-c.y,entry.x-c.x),Math.atan2(exit.y-c.y,exit.x-c.x),false);}
 path.closePath();return path;
}
function createLegacyJawGeometry(diameter,{relief=true}={}){
 const c=clampSpec,r=diameter/2+c.pad,w=c.width/2,shape=new THREE.Shape();
 shape.moveTo(-w,front(-w,r));for(let i=1;i<=96;i++){const x=-w+2*w*i/96;shape.lineTo(x,front(x,r));}
 shape.lineTo(w,c.back);shape.lineTo(-w,c.back);shape.closePath();
 for(const x of [-c.slotX,c.slotX])shape.holes.push(capsule(x,c.slotStart,c.slotEnd,c.slotRadius));
 if(relief)for(const tri of reliefTriangles())shape.holes.push(roundedTriangle(tri,c.innerRadius));
 const g=new THREE.ExtrudeGeometry(shape,{depth:c.height,bevelEnabled:false,steps:1,curveSegments:24});g.computeBoundingBox();return g;
}
export function createPadGeometry(diameter){
 const c=clampSpec,r=diameter/2,w=c.width/2,shape=new THREE.Shape();
 shape.moveTo(-w,front(-w,r));for(let i=1;i<=96;i++){const x=-w+2*w*i/96;shape.lineTo(x,front(x,r));}
 for(let i=96;i>=0;i--){const x=-w+2*w*i/96;shape.lineTo(x,front(x,r+c.pad)+c.pad);}
 shape.closePath();return new THREE.ExtrudeGeometry(shape,{depth:c.height,bevelEnabled:false,steps:1});
}
export function jawPlacements(s){const r=s.workpieceDiameter/2;return [-1,1].map(sign=>({sign,x:s.width/2,d:s.depth/2+(s.workpieceOffset||0)+sign*(r+clampSpec.pad+s.clampOpening/2),z:s.height,rotation:sign===1?0:Math.PI}));}
export function jawStl(diameter){const g=createJawGeometry(diameter),m=new THREE.Mesh(g);m.updateMatrixWorld(true);const data=new STLExporter().parse(m);g.dispose();return data;}

export function createJawGeometry(diameter,{relief=true}={}){
 if(!relief)return createLegacyJawGeometry(diameter,{relief:false});
 const pos=sculptedJaw.position.slice(),radius=diameter/2+clampSpec.pad;
 for(let i=0;i<pos.length;i+=3){const x=pos[i],y=pos[i+1],f=front(x,101),weight=Math.max(0,Math.min(1,(5-y)/(5-f)));pos[i+1]+=weight*(front(x,radius)-f);}
 const indexed=new THREE.BufferGeometry();indexed.setAttribute('position',new THREE.Float32BufferAttribute(pos,3));indexed.setIndex(sculptedJaw.index);
 const g=indexed.toNonIndexed();indexed.dispose();g.computeVertexNormals();g.computeBoundingBox();return g;
}
export function createClampScrewGeometry(){
 const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(flangeScrew.position,3));g.setIndex(flangeScrew.index);g.computeVertexNormals();return g;
}

// 1.6 mm is a display reference pending measurement; STL seat does not depend on this thickness.
export function createClampWasherGeometry(){
 const s=new THREE.Shape();s.absarc(0,0,clampSpec.washerDiameter/2,0,Math.PI*2,false);
 const h=new THREE.Path();h.absarc(0,0,3.2,0,Math.PI*2,true);s.holes.push(h);
 return new THREE.ExtrudeGeometry(s,{depth:clampSpec.washerThickness,bevelEnabled:false,curveSegments:64});
}
