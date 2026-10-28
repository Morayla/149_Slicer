import {specimenDistance} from './printed-specimen-spec.mjs';
// Millimetres. Ball position is extracted from the positioned CAD probe, not the view camera.
const specs={"side": {"ballX": -8.526512829121202e-14, "ballY": 123.6102732702422, "ballZ": 100.0, "ballRadius": 1, "referencePosition": 20, "travel": 107.8, "postFrontInset": 30}, "up": {"ballX": -2.2737367544323206e-13, "ballY": 123.61027327024232, "ballZ": 124.62640710699995, "ballRadius": 1, "referencePosition": 20, "travel": 107.8, "postFrontInset": 30}};
export const measurementSpec=Object.freeze(specs.side);
export function measurementSpecFor(s){return specs[s.indicatorFacing]||specs.side;}
export function fixtureOffsetLimit(s){return Math.max(0,(s.depth-60-(s.workpieceDiameter+2+90+s.clampOpening))/2);}
export function measurementClearance(s){
 const a=measurementSpecFor(s),R=s.workpieceDiameter/2,H=s.workpieceHeight;
 const ballDepth=s.depth-a.postFrontInset-a.ballY,centerDepth=s.depth/2+s.workpieceOffset;
 const dy=ballDepth-centerDepth,rho=Math.hypot(a.ballX,dy),height=a.ballZ+s.measurementPosition-a.referencePosition+s.measurementElevation;
 const outsideHeight=Math.max(-height,height-H,0),sideGap=rho-R-a.ballRadius;
 const gap=specimenDistance(s,rho,height)-a.ballRadius;
 return {gap,sideGap,height,sideValid:height>=0&&height<=H,ballDepth,centerDepth,postGap:s.depth-30-(centerDepth+R),side:'模型几何间隙'};
}
export function offsetNearProbe(s,gap=1){
 const a=measurementSpecFor(s),r=s.workpieceDiameter/2+a.ballRadius+gap;
 if(r<=Math.abs(a.ballX))return null;
 const height=a.ballZ+s.measurementPosition-a.referencePosition+s.measurementElevation;
 if(height<0||height>s.workpieceHeight)return null;
 let lo=s.workpieceDiameter/2,hi=lo+a.ballRadius+gap+2;
 for(let i=0;i<45;i++){const mid=(lo+hi)/2;if(specimenDistance(s,mid,height)-a.ballRadius>gap)hi=mid;else lo=mid;}
 const offset=s.depth-30-a.ballY-Math.sqrt(((lo+hi)/2)**2-a.ballX*a.ballX)-s.depth/2;
 const limit=fixtureOffsetLimit(s);return Math.max(-limit,Math.min(limit,offset));
}
