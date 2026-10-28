import {electronicsFlags,applyElectronicsView} from './electronics-view.mjs';
import * as THREE from 'three';
import data from '../assets/measurement-stage.json';
import electronics from '../assets/electronics-stage.json';
import {endstopPose,endstopSpec} from './endstop.mjs';
import {measurementSpecFor} from './measurement-spec.mjs';
const labels={B28:'V12 下端支座 · 恢复无开关平台',B54:'V12 电机座 · 圆角上座与表夹 · 保留夹紧缝 · 单侧限位孔',B12:'V12 一体滑块表夹 · 表夹外侧 R3 圆角',B60:'居中水平表夹底座',B61:'独立表夹压盖'};
function nameOf(p){if(p.label)return p.label;if(p.name.startsWith('REF_Endstop'))return ({Body:'限位开关 · 本体',Lever:'限位开关 · 金属弹片',PCB:'限位开关 · 20 mm孔距电路板',Connector:'限位开关 · 接线端子'}[p.name.slice(12)]||(/Screw/.test(p.name)?'限位开关 · M3×8螺丝 · 下方装入':'限位开关 · 普通M3螺母'));if(p.name.startsWith('REF_Lateral_Screw_Upper'))return '上座导杆夹紧 · M3×12 · 侧向调节';if(p.name.startsWith('REF_Lateral_Nut_Upper'))return '上座导杆夹紧 · 内藏M3螺母';if(p.name.startsWith('REF_Lateral_Screw'))return '原位侧孔 · M3×12螺丝';if(p.name.startsWith('REF_Lateral_Nut'))return '原位侧孔 · 普通M3六角螺母';if(p.name.startsWith('REF_Motor_Mount_Screw'))return '电机安装螺丝 · M3×16 · 下方安装';if(p.name.startsWith('REF_Clamp_Screw'))return '一体表夹螺丝 · M3×20';if(p.name.startsWith('REF_Clamp_Nut'))return '一体表夹 · M3六角螺母';if(p.name.startsWith('REF_TNut_3060'))return '3060 槽用 M3 T型螺母 · 配合示意';if(p.name.startsWith('Original_Frame_Fastener'))return /_(91|92)$/.test(p.name)?'下端固定螺丝 · M3×35':'上端侧槽固定螺丝 · M3×10 · 沉孔';if(p.name.startsWith('B'))return labels[p.name.slice(0,3)]||p.name;if(p.name.startsWith('REF_Indicator'))return '杠杆百分表 · '+p.name.slice(-2);if(p.name.startsWith('Original_NEMA'))return '原步进电机';if(p.name.includes('Lead_Screw'))return '原丝杆';if(p.name.includes('Guide'))return '原 6 mm 导杆';if(p.name.includes('Linear_Bearing'))return '原直线轴承';if(p.name.includes('625'))return '原625丝杆支撑轴承';if(p.name.includes('Coupling'))return '原联轴器';if(p.name.includes('Unchanged_Motor_Bracket'))return '原电机座 · 未改形状';if(p.name.includes('Separate_Plate'))return '原下端独立夹片 · 未合并';return p.name;}
const templates=[...data.parts.filter(p=>!p.name.startsWith('Original_NEMA')), ...electronics.parts].filter(p=>!p.name.startsWith('REF_3060')).map(p=>{
 const g=new THREE.BufferGeometry(),pos=new Float32Array(p.position.length),norm=new Float32Array(p.normal.length),idx=p.index.slice();
 for(let i=0;i<pos.length;i+=3){pos[i]=p.position[i]/1000;pos[i+1]=p.position[i+2]/1000;pos[i+2]=p.position[i+1]/1000;norm[i]=p.normal[i];norm[i+1]=p.normal[i+2];norm[i+2]=p.normal[i+1];}
 for(let i=0;i<idx.length;i+=3)[idx[i+1],idx[i+2]]=[idx[i+2],idx[i+1]];
 g.setAttribute('position',new THREE.BufferAttribute(pos,3));g.setAttribute('normal',new THREE.BufferAttribute(norm,3));g.setIndex(idx);g.computeBoundingBox();
 const color=new THREE.Color(...p.color.map(x=>x/255));const m=new THREE.MeshStandardMaterial({color,roughness:p.name.startsWith('B')?.62:.4,metalness:p.name.startsWith('B')?.05:.48});if(p.reserved){m.transparent=true;m.opacity=.12;m.depthWrite=false;}return {p,g,m};
});
export function createMeasurementStage(s){
 const group=new THREE.Group();group.name='Measurement Stage 3060';group.userData={name:'百分表测量架',size:'3060 · 电机置顶 · Ø6 导杆 · Ø8 表夹',source:'V12三件打印版：连续一体上座：恢复光轴夹紧缝与侧向螺丝，外边缘圆角；仅左侧限位孔，侧槽固定螺丝头下沉；表夹底面延展齐平；Pi Zero 2 WH + TMC2209；官方 Camera Module 3 标准版；顶部可调支架和CSI排线'};
 group.position.set(0,(s.height+s.measurementElevation)/1000,(-s.depth/2+30)/1000);
 for(const {p,g,m} of templates){if(p.variant&&p.variant!==s.indicatorFacing)continue;const mesh=new THREE.Mesh(p.cameraRibbon?g.clone():g,m.clone());mesh.castShadow=mesh.receiveShadow=true;mesh.userData={name:nameOf(p),size:p.name,source:p.note||'修改版 CAD 实体',stageMoving:p.moving,cameraMount:!!p.cameraMount,cameraRibbon:!!p.cameraRibbon,electronicsLid:!!p.lid,electronicsCover:!!p.cover,exportExclude:!!p.reserved,...electronicsFlags(p.name)};if(p.cameraRibbon)mesh.userData.ribbonBase=Array.from(g.attributes.position.array);applyCameraPose(mesh,s);if(p.moving)mesh.position.y=(s.measurementPosition-measurementSpecFor(s).referencePosition)/1000;if(p.name==='REF_Endstop_Lever')applyEndstopLever(mesh,s);group.add(mesh);}
 applyElectronicsView(group,s);return group;
}
export function updateMeasurementStage(group,s){if(!group)return;group.position.y=(s.height+s.measurementElevation)/1000;for(const o of group.children){applyCameraPose(o,s);if(o.userData.stageMoving)o.position.y=(s.measurementPosition-measurementSpecFor(s).referencePosition)/1000;if(o.userData.size==='REF_Endstop_Lever')applyEndstopLever(o,s);}}

function applyEndstopLever(mesh,s){
 const [x,y,z]=endstopSpec.pivot,pivot=new THREE.Vector3(x/1000,z/1000,y/1000);
 // CAD-to-THREE axis swap is a reflection: X rotation changes sign.
 mesh.rotation.set(-endstopSpec.axisSign*endstopPose(s.measurementPosition).angle,0,0);
 mesh.position.copy(pivot).sub(pivot.clone().applyEuler(mesh.rotation));
}

// Camera mount stays on the extrusion top even when stage elevation changes.
function applyCameraPose(mesh,s){
 const delta=(s.uprightLength-400-s.measurementElevation)/1000;
 if(mesh.userData.cameraMount)mesh.position.y=delta;
 if(mesh.userData.cameraRibbon){const p=mesh.geometry.attributes.position,a=mesh.userData.ribbonBase;for(let i=0;i<p.count;i++){const y=a[i*3+1];p.setY(i,y+delta*Math.max(0,Math.min(1,(y-.263)/.137)));}p.needsUpdate=true;mesh.geometry.computeVertexNormals();mesh.geometry.computeBoundingBox();mesh.geometry.computeBoundingSphere();}
}
