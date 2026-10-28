import * as T from 'three';

// An invisible broad light source below the assembly. No platform or light panel.
export function createLightTable(scene) {
 const group=new T.Group();group.name='Soft underlighting';scene.add(group);
 const level={value:1};let enabled=true,target=1,current=1;
 const haze=new T.Mesh(new T.PlaneGeometry(1,1),new T.ShaderMaterial({
  uniforms:{level},transparent:true,depthWrite:false,depthTest:true,
  vertexShader:`varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}`,
  fragmentShader:`uniform float level;varying vec2 vUv;void main(){vec2 p=vUv-.5;float g=exp(-p.x*p.x*25.-p.y*p.y*38.);float feather=(1.-smoothstep(.32,.5,abs(p.x)))*(1.-smoothstep(.3,.5,abs(p.y)));gl_FragColor=vec4(vec3(.95,.975,1.),g*feather*.25*level);}`
 }));haze.position.set(0,.005,.245);haze.scale.set(.78,.26,1);haze.renderOrder=-2;group.add(haze);
 function illuminate(root){root.traverse(o=>{
  if(!o.isMesh||!o.userData.lineStyled||o.userData.uplightApplied||o.userData.cadSilhouette)return;
  o.userData.uplightApplied=true;
  const mat=new T.ShaderMaterial({uniforms:{level,materialMode:{value:.45}},transparent:true,depthWrite:false,polygonOffset:true,polygonOffsetFactor:-1,polygonOffsetUnits:-1,
   vertexShader:`varying float height;varying vec3 n;varying vec3 down;void main(){vec4 world=modelMatrix*vec4(position,1.);height=world.y+.028;n=normalize(normalMatrix*normal);down=normalize(mat3(viewMatrix)*vec3(0.,-1.,0.));gl_Position=projectionMatrix*viewMatrix*world;}`,
   fragmentShader:`uniform float level;uniform float materialMode;varying float height;varying vec3 n;varying vec3 down;void main(){float facing=.38+.62*max(0.,dot(normalize(n),normalize(down)));float falloff=exp(-max(0.,height)*14.);float a=materialMode*level*falloff*facing*.85;gl_FragColor=vec4(vec3(.95,.975,1.),a);}`});
  const glow=new T.Mesh(o.geometry,mat);glow.userData.uplightSurface=true;glow.renderOrder=1;o.add(glow);
 });}
 return {illuminate,setEnabled(v){enabled=!!v;group.visible=enabled;level.value=enabled?current:0;},phase(phase){target=phase==='settling'?1.10:1;},frame(camera){current+=(target-current)*.045;level.value=enabled?current:0;if(camera)haze.quaternion.copy(camera.quaternion);}};
}
