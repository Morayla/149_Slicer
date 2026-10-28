import * as T from 'three';
import {radialError} from './scan.mjs';
// Millimetres in both views. Layer 1 is the original print base, at the top
// of the inverted specimen. The short final layer belongs at the bottom.
export function specimenLayerBounds(c,layer){
 const top=c.height-(layer-1)*c.step,bottom=Math.max(0,c.height-layer*c.step);
 return {top,bottom,center:(top+bottom)/2,thickness:top-bottom};
}
export function createSpecimenGeometry(c,{firstLayer=1,lastLayer=Math.ceil(c.height/c.step),errorAtHeight=y=>radialError(y,c)}={}){
 const radius=c.diameter/2,outer=[],inner=[];
 for(let layer=lastLayer;layer>=firstLayer;layer--){const {bottom,thickness:h}=specimenLayerBounds(c,layer);if(h<=0)continue;
  for(let j=0;j<=10;j++){const a=j*Math.PI/10,y=bottom+h/2-h/2*Math.cos(a),bead=.28*h*(Math.sin(a)-1);
   outer.push(new T.Vector2(radius+errorAtHeight(y)+bead,y));inner.push(new T.Vector2(radius-c.lineWidth-bead,y));
  }
 }
 const points=[...outer,...inner.reverse()];points.push(points[0].clone());return new T.LatheGeometry(points,160);
}
