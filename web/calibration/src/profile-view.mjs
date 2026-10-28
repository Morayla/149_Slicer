import {workspaceFrames} from './frame-scheduler.mjs';
import * as T from 'three';
import {radialError} from './scan.mjs';
import {createSpecimenGeometry,specimenLayerBounds} from './specimen-geometry.mjs';
// The same physical specimen as the assembly; only measured layers brighten.
export function layerProfile(config,row,count){
 const bounds=specimenLayerBounds(config,row.layer);
 return {y:bounds.center-config.height/2,rx:config.diameter/2+row.radialErrorMm,pitch:bounds.thickness};
}
export function profileCursor(config,height,error=radialError(height,config)){return {y:height-config.height/2,rx:config.diameter/2+error};}
export function createProfile(host){
 const scene=new T.Scene(),camera=new T.OrthographicCamera(-115,115,122,-122,.1,1000);
 camera.position.set(210,150,340);camera.lookAt(0,0,0);
 const renderer=new T.WebGLRenderer({alpha:true,antialias:true});renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.setClearColor(0,0);host.append(renderer.domElement);renderer.domElement.setAttribute('aria-hidden','true');
 let lastWidth=0,lastHeight=0;let signature='',bands=new Map(),current=1,lastConfig,lastCount=15,lastWhite;
 const ink={value:new T.Color('#eeeeee')};
 const material=new T.ShaderMaterial({transparent:true,depthWrite:false,side:T.DoubleSide,uniforms:{ink,revealCutoff:{value:-1e6}},vertexShader:`varying vec3 n;varying vec3 v;varying float localY;void main(){localY=position.y;vec4 p=modelViewMatrix*vec4(position,1.);n=normalize(normalMatrix*normal);v=normalize(-p.xyz);gl_Position=projectionMatrix*p;}`,fragmentShader:`uniform vec3 ink;uniform float revealCutoff;varying vec3 n;varying vec3 v;varying float localY;void main(){if(localY<revealCutoff)discard;float rim=pow(1.-abs(dot(normalize(n),normalize(v))),2.);gl_FragColor=vec4(ink,.018+.15*rim);}`});
 const contourMaterial=new T.LineBasicMaterial({color:0xdddddd,transparent:true,opacity:.18,depthWrite:false});
 const ghostMaterial=new T.LineBasicMaterial({color:0xcccccc,transparent:true,opacity:.06,depthWrite:false});
 function circle(radius,y,mat){return new T.Line(new T.BufferGeometry().setFromPoints(Array.from({length:129},(_,i)=>{const a=i/128*Math.PI*2;return new T.Vector3(radius*Math.cos(a),y,radius*Math.sin(a));})),mat);}
 const ghost=new T.Group();scene.add(ghost);const ghostShell=new T.MeshBasicMaterial({color:0xdddddd,transparent:true,opacity:.018,depthWrite:false,side:T.DoubleSide});
 const focusMaterial=new T.MeshBasicMaterial({color:0xffffff,transparent:true,opacity:.86,depthWrite:false});const focus=new T.Mesh(new T.TorusGeometry(1,.006,6,128),focusMaterial);focus.rotation.x=Math.PI/2;scene.add(focus);
 function resize(){const r=host.getBoundingClientRect();if(r.width<=0||r.height<=0)return;if(r.width!==lastWidth||r.height!==lastHeight){renderer.setSize(r.width,r.height,false);lastWidth=r.width;lastHeight=r.height;}const a=r.width/r.height,c=lastConfig;const span=c?Math.max(c.height*.62+c.diameter*.18,c.diameter*.64/a):122;camera.left=-span*a;camera.right=span*a;camera.top=span;camera.bottom=-span;camera.updateProjectionMatrix();}
 new ResizeObserver(()=>{resize();frames.request();}).observe(host);
 function clear(){for(const {group}of bands.values()){scene.remove(group);group.traverse(o=>{o.geometry?.dispose();if(o.isMesh)o.material.dispose();});}bands.clear();}
 const render=(config,rows,count,currentLayer,position)=>{
  const next=JSON.stringify([config.diameter,config.height,config.step,config.lineWidth,config.foot,count]);if(next!==signature||rows.length<bands.size){clear();signature=next;ghost.traverse(o=>o.geometry?.dispose());ghost.clear();const shell=new T.Mesh(createSpecimenGeometry(config),ghostShell);shell.position.y=-config.height/2;ghost.add(shell);const r=config.diameter/2;for(let i=0;i<=Math.ceil(config.height/config.step);i++){const y=Math.max(0,config.height-i*config.step);ghost.add(circle(r,y-config.height/2,ghostMaterial));}}lastConfig=config;lastCount=count;current=currentLayer;resize();
  for(const row of rows){if(bands.has(row.layer))continue;const {y,rx,pitch}=layerProfile(config,row,count),g=new T.Group();g.position.y=y;
   const geom=createSpecimenGeometry(config,{firstLayer:row.layer,lastLayer:row.layer,errorAtHeight:()=>row.radialErrorMm});geom.translate(0,-(y+config.height/2),0);
   const bandMaterial=material.clone();bandMaterial.uniforms.ink=ink;g.add(new T.Mesh(geom,bandMaterial));const bead=.28*pitch,inner=config.diameter/2-config.lineWidth+bead;
   g.add(circle(rx-bead,pitch/2,contourMaterial),circle(rx-bead,-pitch/2,contourMaterial),circle(inner,pitch/2,contourMaterial));scene.add(g);bands.set(row.layer,{group:g,row,pitch,bandMaterial,born:performance.now()});
  }
  const selected=bands.get(current)?.row;const height=Number.isFinite(position)?position:specimenLayerBounds(config,current).center;const {y,rx}=profileCursor(config,height,selected?.radialErrorMm);focus.position.y=y;focus.scale.setScalar(rx);host.dataset.recorded=String(rows.length);host.dataset.layer=String(current);frames.request();
 };
 function frame(){if(!lastConfig||!host.clientWidth||!host.clientHeight)return;const white=document.body.classList.contains('light-results');if(white!==lastWhite){lastWhite=white;ink.value.set(white?'#151515':'#eeeeee');contourMaterial.color.set(white?'#222222':'#dddddd');ghostMaterial.color.copy(contourMaterial.color);ghostShell.color.copy(contourMaterial.color);focusMaterial.color.copy(contourMaterial.color);}
  const now=performance.now();let animating=false;for(const {group,born,pitch,bandMaterial}of bands.values()){const t=Math.min(1,(now-born)/500);animating ||= t<1;bandMaterial.uniforms.revealCutoff.value=pitch/2-pitch*t-.001;for(const child of group.children)if(child.isLine)child.visible=t>=1;}renderer.render(scene,camera);return animating;
 }
 const frames=workspaceFrames(frame);new MutationObserver(frames.request).observe(document.body,{attributes:true,attributeFilter:['class']});render.frame=frames.request;resize();return render;
}
