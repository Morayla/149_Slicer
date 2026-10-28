import * as T from 'three';
import data from '../assets/bottom-white-stage.json';
import electronics from '../assets/electronics-stage.json';
import {electronicsFlags} from './electronics-view.mjs';
export function createBottomStage(){
 const group=new T.Group();group.name='V24 bottom switch and white dial';
 for(const p of [...data.parts,...electronics.parts]){
  const geometry=new T.BufferGeometry(),pos=new Float32Array(p.position.length),norm=new Float32Array(p.normal.length),idx=p.index.slice();
  for(let i=0;i<pos.length;i+=3){pos[i]=p.position[i]/1000;pos[i+1]=p.position[i+2]/1000;pos[i+2]=p.position[i+1]/1000;norm[i]=p.normal[i];norm[i+1]=p.normal[i+2];norm[i+2]=p.normal[i+1];}
  for(let i=0;i<idx.length;i+=3)[idx[i+1],idx[i+2]]=[idx[i+2],idx[i+1]];
  geometry.setAttribute('position',new T.BufferAttribute(pos,3));geometry.setAttribute('normal',new T.BufferAttribute(norm,3));geometry.setIndex(idx);
  const mesh=new T.Mesh(geometry,new T.MeshStandardMaterial({color:0xdddddd}));mesh.userData={size:p.name,stageMoving:p.moving,source:'V24 CAD; estimated pose, not measured clearance',...electronicsFlags(p.name)};group.add(mesh);
 }
 return group;
}
export function updateBottomStage(group,state){
 // Display only: this CAD contact offset must never be sent to the controller.
 const known=state?.homed&&Number.isFinite(state.position);
 const position=known?data.limits.pressedPosition+state.position:20;
 for(const mesh of group.children)if(mesh.userData.stageMoving)mesh.position.y=(position-20)/1000;
 group.userData.positionKnown=!!known;
}
