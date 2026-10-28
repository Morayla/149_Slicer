import * as THREE from 'three';
import {STLExporter} from 'three/addons/exporters/STLExporter.js';
export function printedBracketGeometry(data,flat=false){
 const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(data.position,3));g.setIndex(data.index);const result=flat?g.toNonIndexed():g;if(flat)g.dispose();result.computeVertexNormals();result.computeBoundingBox();return result;
}
export function printedBracketStl(data){const g=printedBracketGeometry(data),mesh=new THREE.Mesh(g);mesh.updateMatrixWorld(true);const stl=new STLExporter().parse(mesh,{binary:true});g.dispose();return stl.buffer;}
