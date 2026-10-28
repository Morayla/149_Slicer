import {workspaceFrames} from './frame-scheduler.mjs';
import {createBottomStage,updateBottomStage} from './bottom-stage.mjs';
import * as T from 'three';
import {createSpecimenGeometry} from './specimen-geometry.mjs';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {createMeasurementStage,updateMeasurementStage} from './measurement.mjs';
import {applyElectronicsView} from './electronics-view.mjs';
import {createJawGeometry,createPadGeometry,createClampScrewGeometry,createClampWasherGeometry,clampSpec} from './clamp.mjs';
import profiles from '../assets/profiles.json';
import {profileGeometry,placeProfile,layout} from './profile.mjs';
import printedBracket from '../assets/printed-bracket.json';
import printedScrew from '../assets/printed-bracket-screw.json';
import {printedBracketGeometry} from './printed-bracket.mjs';
import {radialError,planFor,TRAVEL} from './scan.mjs';
export function createView(host){
 const scene=new T.Scene();scene.background=null;
 const renderer=new T.WebGLRenderer({antialias:true,alpha:true});renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.04;host.append(renderer.domElement);renderer.domElement.setAttribute('aria-label','三维测量装置，可拖动旋转与缩放');
 let aspect=1,viewSpan=.4,cameraView='iso';const camera=new T.OrthographicCamera(-.4,.4,.4,-.4,.001,10);const controls=new OrbitControls(camera,renderer.domElement);controls.enableDamping=true;controls.minDistance=.12;controls.maxDistance=2;controls.minZoom=.6;controls.maxZoom=5;
 // Matte white clay with stable monochrome grain, confined to model surfaces.
 let xrayBackground='white';let lineStrength=.55;const grainAmount={value:.085};
 renderer.shadowMap.enabled=true;renderer.shadowMap.needsUpdate=true;renderer.shadowMap.type=T.PCFSoftShadowMap;
 scene.add(new T.HemisphereLight(0xffffff,0x454545,.8));
 const key=new T.DirectionalLight(0xffffff,3.1);key.position.set(-.45,.85,.6);key.target.position.set(0,.14,.2);key.castShadow=true;key.shadow.mapSize.set(2048,2048);Object.assign(key.shadow.camera,{left:-.45,right:.45,top:.45,bottom:-.45,near:.05,far:2});key.shadow.bias=-.00008;key.shadow.normalBias=.00025;scene.add(key,key.target);
 const fill=new T.DirectionalLight(0xffffff,.35);fill.position.set(.7,.3,-.3);scene.add(fill);
 function materialFor(o){const mat=new T.MeshStandardMaterial({color:0xdfdfdf,metalness:0,roughness:.94});
 mat.onBeforeCompile=shader=>{shader.uniforms.grainAmount=grainAmount;shader.fragmentShader='uniform float grainAmount;\n'+shader.fragmentShader;shader.fragmentShader=shader.fragmentShader.replace('#include <dithering_fragment>',`#include <dithering_fragment>
 float grain=fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233)))*43758.5453)-.5;
 gl_FragColor.rgb=clamp(gl_FragColor.rgb+grain*grainAmount,0.,1.);`);};
 mat.customProgramCacheKey=()=> '149-clay-grain-v1';return mat;}
 function xrayMaterial(o){return new T.ShaderMaterial({transparent:true,depthWrite:false,side:T.DoubleSide,uniforms:{ink:{value:new T.Color(0xeeeeee)},strength:{value:lineStrength},surface:{value:o.geometry.type==='LatheGeometry'?2.1:1}},
 vertexShader:`varying vec3 n;varying vec3 eye;void main(){vec4 p=modelViewMatrix*vec4(position,1.);n=normalize(normalMatrix*normal);eye=normalize(-p.xyz);gl_Position=projectionMatrix*p;}`,
 fragmentShader:`varying vec3 n;varying vec3 eye;uniform vec3 ink;uniform float strength;uniform float surface;void main(){float rim=pow(1.-abs(dot(normalize(n),normalize(eye))),2.4);gl_FragColor=vec4(ink,(.016+rim*.16)*strength*surface);}`});}
 function inkMaterial(o){o.userData.inkDark=true;
 // Flat printed ink: no diffuse gradient or specular reflection in drawing mode.
 return new T.ShaderMaterial({polygonOffset:true,polygonOffsetFactor:1,polygonOffsetUnits:1,
 vertexShader:`void main(){gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}`,
 fragmentShader:`void main(){float grain=fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233)))*43758.5453);float ink=.028+grain*.025;gl_FragColor=vec4(vec3(ink),1.);}`});}
 function ringColor(r){if(viewMode==='xray'&&xrayBackground==='white')return 0x404040;return r.userData.band==='bad'?(lineMode?0xbdbdbd:0xbdbdbd):r.userData.band==='done'?(lineMode?0xbdbdbd:0xbdbdbd):(lineMode?0xe2dfd8:0xbdbdbd);}
 const silver=new T.MeshStandardMaterial({color:0x9aa8af,metalness:.7,roughness:.43}),plastic=new T.MeshStandardMaterial({color:0x798d98,roughness:.7});
 const floor=new T.Mesh(new T.PlaneGeometry(4,4),new T.MeshStandardMaterial({color:0x353a39,roughness:1}));floor.rotation.x=-Math.PI/2;floor.position.y=-.032;floor.visible=false;scene.add(floor);
 const steel=new T.MeshStandardMaterial({color:0x777f83,metalness:.75,roughness:.4}),dark=new T.MeshStandardMaterial({color:0x444a47,roughness:.6});

 const root=new T.Group();scene.add(root);let config,stage,sample,highlight,datumGroup,jaws,base=0,minimum=0,layerRings=[],lineMode=false,viewMode='clay';
 const s={height:0,depth:60,measurementElevation:0,measurementPosition:20,uprightLength:400,indicatorFacing:'up',electronicsVisible:true,electronicsOpen:false,wiresVisible:true};
 function add(g,mat,parent=root){const m=new T.Mesh(g,mat);parent.add(m);return m;}
 for(const spec of Object.values(layout)){const group=new T.Group();for(const q of profiles[spec.type].meshes)add(profileGeometry(profiles[spec.type],q),silver,group);placeProfile(group,spec);root.add(group);}
 for(const sign of [-1,1]){const g=printedBracketGeometry(printedBracket,true);g.translate(0,0,-15);g.rotateY(Math.PI);g.scale(.001,.001,.001);const bracket=add(g,plastic);bracket.position.set(sign*.03,0,-.015);if(sign===1)bracket.rotation.y=Math.PI;
  for(const h of [.015,.045]){const bottom=add(printedBracketGeometry(printedScrew,true).scale(.001,.001,.001),steel);bottom.rotation.x=-Math.PI/2;bottom.position.set(sign*(.03+h),.00485,-.015);const bottomNut=add(new T.BoxGeometry(.016,.004,.012),dark);bottomNut.position.set(sign*(.03+h),-.005,-.015);const side=add(printedBracketGeometry(printedScrew,true).scale(.001,.001,.001),steel);side.rotation.y=sign*Math.PI/2;side.position.set(sign*.03485,h,-.015);const sideNut=add(new T.BoxGeometry(.004,.016,.012),dark);sideNut.position.set(sign*.025,h,-.015);}
 }
 stage=createMeasurementStage(s);root.add(stage);
 const bottomStage=createBottomStage();root.add(bottomStage);bottomStage.visible=false;let hardwareMode=false;
 function outline(group){group.traverse(o=>{if(!o.isMesh||o.userData.lineStyled||o.userData.cadSilhouette)return;o.userData.lineStyled=true;o.castShadow=true;o.receiveShadow=true;o.userData.solidMaterial=materialFor(o);o.userData.xrayMaterial=xrayMaterial(o);o.userData.lineMaterial=inkMaterial(o);o.material=lineMode?o.userData.lineMaterial:o.userData.solidMaterial;
 // Smooth specimen surfaces keep their real shape; layer contours provide its line detail.
 const edge=new T.LineSegments(new T.EdgesGeometry(o.geometry,12),new T.LineBasicMaterial({color:0xb6b8b7,transparent:true,opacity:.7,depthTest:true,depthWrite:false}));edge.userData.cadOutline=true;edge.visible=lineMode&&o.geometry.type!=='LatheGeometry';edge.renderOrder=2;o.add(edge);
 const silhouetteMaterial=new T.MeshBasicMaterial({color:0x151515,side:T.BackSide,depthWrite:false});silhouetteMaterial.onBeforeCompile=shader=>{shader.vertexShader=shader.vertexShader.replace('#include <begin_vertex>','#include <begin_vertex>\ntransformed += normal * 0.00024;');};const silhouette=new T.Mesh(o.geometry,silhouetteMaterial);silhouette.userData.cadSilhouette=true;silhouette.renderOrder=1;silhouette.visible=lineMode&&o.geometry.type!=='LatheGeometry';o.add(silhouette);});}
 function xrayDetailWeight(o,white){const d=o.userData;if(d.electronicsCable||d.cameraRibbon)return white?.10:.18;if(d.electronicsPart||/Motor|NEMA/.test(d.size||''))return white?.24:.35;return 1;}
 function style(mode){viewMode=['clay','lines','xray'].includes(mode)?mode:'clay';lineMode=viewMode==='lines';const lines=lineMode,xray=viewMode==='xray',white=xray&&xrayBackground==='white',sheet=host.closest('.stage');sheet.classList.add('line-preview');sheet.classList.toggle('clay-preview',viewMode==='clay');sheet.classList.toggle('paper-preview',lines);sheet.classList.toggle('xray-preview',xray);sheet.classList.toggle('xray-white',white);renderer.shadowMap.enabled=viewMode==='clay';renderer.shadowMap.needsUpdate=true;root.traverse(o=>{
  if(o.isMesh&&o.userData.lineStyled){o.material=lines?o.userData.lineMaterial:xray?o.userData.xrayMaterial:o.userData.solidMaterial;o.userData.xrayMaterial.uniforms.strength.value=lineStrength*xrayDetailWeight(o,white);o.userData.xrayMaterial.uniforms.ink.value.set(white?0x171717:0xeeeeee);}
  if(o.userData.cadOutline){o.visible=(lines||xray)&&o.parent.geometry.type!=='LatheGeometry';o.material.color.set(lines?0xe4e1dc:white?0x171717:0xeeeeee);o.material.opacity=lines?.55+.45*lineStrength:.25*lineStrength*xrayDetailWeight(o.parent,white);o.material.depthTest=!xray;}
  if(o.userData.cadSilhouette)o.visible=lines;
  if(o.userData.specimenContour){o.material.color.set(white?0x171717:0xe4e1dc);o.visible=lines||xray;o.material.opacity=lines?.9:.35*lineStrength;o.material.depthTest=!xray;}
 });for(const ring of layerRings){ring.material.opacity=lines?.55+.4*lineStrength:xray?1.15*lineStrength:.22;ring.material.depthTest=!xray;ring.material.color.set(ringColor(ring));}if(highlight){highlight.material.color.set(white?0x171717:0xeeeeee);for(const halo of highlight.children){halo.visible=!lines;halo.material.color.set(white?0x171717:0xeeeeee);}}}




 outline(root);
 const originalNeedle=stage.children.find(o=>o.userData.size==='REF_Indicator_06');
 function disposeGroup(group){if(!group)return;root.remove(group);group.traverse(o=>{if(o.isMesh||o.isLine){o.geometry.dispose();if(o.userData.lineStyled){for(const mat of new Set([o.userData.solidMaterial,o.userData.lineMaterial,o.userData.xrayMaterial]))mat?.dispose();}else if(![plastic,steel,dark,silver].includes(o.material))o.material.dispose();}});}
 function rebuild(c){const firstBuild=!sample;config=c;minimum=planFor(c).at(-1).heightMm;base=0;disposeGroup(sample);disposeGroup(datumGroup);disposeGroup(jaws);for(const ring of layerRings){root.remove(ring);ring.geometry.dispose();ring.material.dispose();}layerRings=[];if(highlight){root.remove(highlight);highlight.traverse(o=>{if(o.isMesh){o.geometry.dispose();o.material.dispose();}});}
  sample=new T.Group();root.add(sample);const radius=c.diameter/2,center=.1241+radius/1000;sample.position.set(0,base/1000,center);
  // Each bead follows the same radial error field used by the simulated sensor.
  const count=Math.ceil(c.height/c.step),geom=createSpecimenGeometry(c).scale(.001,.001,.001),colors=[];const pos=geom.attributes.position;const cool=new T.Color('#aaaaaa'),warm=new T.Color('#aaaaaa');for(let i=0;i<pos.count;i++){const color=cool.clone().lerp(warm,c.foot?Math.exp(-(c.height-pos.getY(i)*1000)/c.decay):0);colors.push(color.r,color.g,color.b);}geom.setAttribute('color',new T.Float32BufferAttribute(colors,3));add(geom,new T.MeshStandardMaterial({vertexColors:true,roughness:.68,metalness:.03}),sample);
  jaws=new T.Group();root.add(jaws);for(const sign of [-1,1]){const jaw=add(createJawGeometry(c.diameter).scale(.001,.001,.001),plastic,jaws);jaw.rotation.x=-Math.PI/2;if(sign===1)jaw.rotateZ(Math.PI);jaw.position.set(0,base/1000,center+sign*(radius+1)/1000);const pad=add(createPadGeometry(c.diameter).scale(.001,.001,.001),new T.MeshStandardMaterial({color:0x595e5c,roughness:.95}),jaws);pad.rotation.copy(jaw.rotation);pad.position.set(0,0,center+sign*radius/1000);
   for(const x of [-.045,.045]){const z=center+sign*(radius+1+22.5)/1000;const screw=add(createClampScrewGeometry().scale(.001,.001,.001),steel,jaws);screw.rotation.x=-Math.PI/2;screw.position.set(x,(clampSpec.seatHeight+clampSpec.washerThickness)/1000,z);const washer=add(createClampWasherGeometry().scale(.001,.001,.001),steel,jaws);washer.rotation.x=-Math.PI/2;washer.position.set(x,clampSpec.seatHeight/1000,z);const nut=add(new T.BoxGeometry(.012,.004,.016),dark,jaws);nut.position.set(x,-.005,z);}
  }
  outline(sample);outline(jaws);
  // Explicit top/bottom rim and inner-wall layer contours follow the actual specimen.
  function specimenCircle(y,r){const points=Array.from({length:161},(_,i)=>{const a=i/160*Math.PI*2;return new T.Vector3(r*Math.cos(a),y,r*Math.sin(a));});const line=new T.Line(new T.BufferGeometry().setFromPoints(points),new T.LineBasicMaterial({color:0xe4e1dc,toneMapped:false,transparent:true,opacity:.9,depthWrite:false}));line.userData.specimenContour=true;line.renderOrder=3;sample.add(line);return line;}
  for(const y of [0,c.height]){specimenCircle(y/1000+.000025,(radius+radialError(y,c)-.28*c.step)/1000);specimenCircle(y/1000+.000025,(radius-c.lineWidth+.28*c.step)/1000);}
  for(let j=0;j<count;j++){const y=Math.min(c.height,(j+.5)*c.step);specimenCircle(y/1000,(radius-c.lineWidth)/1000-.00006);}

  for(let j=0;j<count;j++){const y=c.height-(j+.5)*c.step;if(y<0)continue;const rad=(radius+radialError(y,c))/1000+.00006;const pts=Array.from({length:161},(_,i)=>{const a=i/160*Math.PI*2;return new T.Vector3(rad*Math.cos(a),y/1000,center+rad*Math.sin(a));});const ring=new T.Line(new T.BufferGeometry().setFromPoints(pts),new T.LineBasicMaterial({color:0xbdbdbd,transparent:true,opacity:.8,depthTest:true,depthWrite:false}));ring.userData.layer=j+1;ring.renderOrder=3;root.add(ring);layerRings.push(ring);}
  highlight=add(new T.TorusGeometry((radius+c.foot+.6)/1000,.00085,8,160),new T.MeshBasicMaterial({color:0xeeeeee,toneMapped:false,depthTest:false,transparent:true}));highlight.rotation.x=Math.PI/2;highlight.position.z=center;highlight.renderOrder=6;
  for(const [thickness,opacity]of [[.0016,.2],[.0032,.065]]){const halo=new T.Mesh(new T.TorusGeometry((radius+c.foot+.6)/1000,thickness,8,160),new T.MeshBasicMaterial({color:0xeeeeee,transparent:true,opacity,depthTest:false,depthWrite:false}));halo.renderOrder=5;highlight.add(halo);}
  style(viewMode);if(firstBuild)fit();return base;
 }
 function pose(height,error=0,rows=[],layer=1,phase='ready'){if(!config)return;const p=Math.max(0,Math.min(TRAVEL,height-104.626407107));s.measurementPosition=p;updateMeasurementStage(stage,s);renderer.shadowMap.needsUpdate=true;highlight.position.y=(base+height)/1000;const radius=config.diameter/2;const radiusScale=(radius+radialError(height,config)+.25)/(radius+config.foot+.6);highlight.scale.set(radiusScale,radiusScale,1);for(const r of layerRings){const row=rows.find(v=>v.layer===r.userData.layer);r.visible=r.userData.layer!==layer;r.userData.band=row?(Math.abs(row.radialErrorMm)>(config.tolerance??.1)?'bad':'done'):'pending';r.material.color.set(ringColor(r));}
 if(originalNeedle){const pivot=new T.Vector3(0,.1384,.060);originalNeedle.rotation.y=error*Math.PI*2;originalNeedle.position.copy(pivot).sub(pivot.clone().applyEuler(originalNeedle.rotation));originalNeedle.position.y+=(p-20)/1000;}}
 function display(key,value){s[key]=value;applyElectronicsView(stage,s);applyElectronicsView(bottomStage,s);}
 function fit(mode=cameraView){
  if(['iso','front','side','top'].includes(mode))cameraView=mode;
  const previousDirection=camera.position.clone().sub(controls.target).normalize();
  root.updateMatrixWorld(true);const box=new T.Box3();root.traverseVisible(o=>{if(!o.isMesh||o===highlight||o.parent===highlight||o.userData.cadSilhouette)return;o.geometry.computeBoundingBox();box.union(o.geometry.boundingBox.clone().applyMatrix4(o.matrixWorld));});const center=box.getCenter(new T.Vector3());controls.target.copy(center);
  const dir=(mode==='keep'&&previousDirection.lengthSq()>.1?previousDirection:mode==='front'?new T.Vector3(0,0,1):mode==='side'?new T.Vector3(-1,0,0):mode==='top'?new T.Vector3(0,1,.0001):new T.Vector3(-1,.75,.65)).normalize();
  if(mode==='bay'){center.set(0,.2,-.04);controls.target.copy(center);dir.set(-1,.3,-1).normalize();display('electronicsOpen',true);viewSpan=.16;}else{camera.position.copy(center).addScaledVector(dir,1);camera.lookAt(center);camera.updateMatrixWorld();const v=[];for(const x of [box.min.x,box.max.x])for(const y of [box.min.y,box.max.y])for(const z of [box.min.z,box.max.z])v.push(new T.Vector3(x,y,z).applyMatrix4(camera.matrixWorldInverse));viewSpan=Math.max(...v.map(p=>Math.max(Math.abs(p.y),Math.abs(p.x)/aspect)))*1.05;}
  camera.zoom=1;camera.left=-viewSpan*aspect;camera.right=viewSpan*aspect;camera.top=viewSpan;camera.bottom=-viewSpan;camera.position.copy(center).addScaledVector(dir,1);camera.lookAt(center);camera.updateProjectionMatrix();controls.update();
 }
 function resize(){const r=host.getBoundingClientRect();if(r.width<=0||r.height<=0)return;renderer.setSize(r.width,r.height,false);aspect=r.width/r.height;camera.left=-viewSpan*aspect;camera.right=viewSpan*aspect;camera.top=viewSpan;camera.bottom=-viewSpan;camera.updateProjectionMatrix();}
 new ResizeObserver(()=>{resize();frames.request();}).observe(host);resize();fit();
 let firstFrame=true;function frame(){if(firstFrame){resize();fit();firstFrame=false;}controls.update();renderer.render(scene,camera);}
 const frames=workspaceFrames(frame);controls.addEventListener('change',frames.request);
 const change=fn=>(...args)=>{const result=fn(...args);frames.request();return result;};
 return {rebuild:change(rebuild),pose:change(pose),display:change(display),style:change(style),fit:change(fit),frame:frames.request,renderer,hardwareState(state,active){hardwareMode=active;stage.visible=!active;bottomStage.visible=active;updateBottomStage(bottomStage,state);applyElectronicsView(bottomStage,s);renderer.shadowMap.needsUpdate=true;frames.request();},background(value){xrayBackground=value;style(viewMode);frames.request();},intensity(v){lineStrength=v;style(viewMode);frames.request();},grain(v){grainAmount.value=v;frames.request();},zoomBy(factor){camera.zoom=Math.max(controls.minZoom,Math.min(controls.maxZoom,camera.zoom*factor));camera.updateProjectionMatrix();frames.request();}};
}
