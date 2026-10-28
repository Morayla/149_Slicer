export const TRAVEL=107.8;
export const defaults=Object.freeze({height:150,step:3,scanLayers:15,diameter:200,foot:1.2,decay:9,speed:12,dwell:.65,noise:.015,lineWidth:9,tolerance:.1});
export function configOf(input={}){
 const c={...defaults};const limits={lineWidth:[.5,30],tolerance:[.01,5],scanLayers:[1,100],height:[3,300],step:[.5,20],diameter:[120,300],foot:[0,5],decay:[1,60],speed:[1,60],dwell:[.2,5],noise:[0,.1]};
 for(const [k,[lo,hi]] of Object.entries(limits)){if(input[k]!==undefined){const n=Number(input[k]);if(!Number.isFinite(n)||n<lo||n>hi)throw Error(`${k} 参数超出范围 ${lo}–${hi}`);c[k]=n;}}
 if(!Number.isInteger(c.scanLayers))throw Error('测量层数必须为整数');
 if(c.decay>c.height)c.decay=c.height;
 return c;
}
// Layer-center samples, descending. The short last layer is measured at its own center.
export function planFor(c){const n=Math.min(c.scanLayers,Math.ceil(c.height/c.step-1e-9));return Array.from({length:n},(_,j)=>{const layer=j+1,lo=j*c.step,hi=Math.min(c.height,(j+1)*c.step);return {layer,heightMm:c.height-(lo+hi)/2,printHeightMm:(lo+hi)/2,thicknessMm:hi-lo};});}
// Workpiece is inverted: its ORIGINAL print base / elephant foot is at the physical top.
export function radialError(height,c){return c.foot*Math.exp(-(c.height-height)/c.decay);}
export function reachability(c){const p=planFor(c);return p.every(v=>v.heightMm>=104.626407107&&v.heightMm<=212.426407107);}
export function simulatedReading(point,c){const noise=c.noise*(.65*Math.sin(point.layer*2.137)+.35*Math.sin(point.layer*.831));return Number((radialError(point.heightMm,c)+noise).toFixed(4));}
export function validateSample(raw){
 if(!raw||typeof raw!=='object')throw Error('数据必须是JSON对象');
 const {layer,heightMm,radialErrorMm,timestamp}=raw;
 if(!Number.isInteger(layer)||layer<1||layer>10000)throw Error('layer必须为正整数');
 if(typeof heightMm!=='number'||!Number.isFinite(heightMm)||heightMm<0||heightMm>10000)throw Error('heightMm无效');
 if(typeof radialErrorMm!=='number'||!Number.isFinite(radialErrorMm)||Math.abs(radialErrorMm)>100)throw Error('radialErrorMm无效');
 if(typeof timestamp!=='string'||!Number.isFinite(Date.parse(timestamp)))throw Error('timestamp必须为有效ISO时间');
 const source=raw.source;if(!['simulation','device','replay'].includes(source))throw Error('source必须是simulation、device或replay');
 if(raw.printHeightMm!==undefined&&(typeof raw.printHeightMm!=='number'||!Number.isFinite(raw.printHeightMm)||raw.printHeightMm<0))throw Error('printHeightMm无效');
 return {layer,heightMm,...(raw.printHeightMm!==undefined?{printHeightMm:raw.printHeightMm}:{}),radialErrorMm,compensationMm:Number((-radialErrorMm).toFixed(4)),timestamp:new Date(timestamp).toISOString(),source};
}
export class Scan{
 constructor(config=defaults){this.reset(config);}
 reset(config=this.config){this.config=configOf(config);this.plan=planFor(this.config);this.rows=[];this.index=0;this.position=this.plan[0].heightMm;this.phase='ready';this.paused=false;this.elapsed=0;this.clock=0;}
 get running(){return ['moving','settling'].includes(this.phase)&&!this.paused;}
 start(){if(this.phase==='done')this.reset();if(this.phase==='ready')this.phase='settling';this.paused=false;}
 pause(){if(this.running)this.paused=true;}
 tick(dt){if(!this.running||!Number.isFinite(dt)||dt<=0)return [];
  const added=[];let remaining=Math.min(dt,1); // large browser gaps never generate a burst of fake samples
  while(remaining>1e-8&&this.running){const target=this.plan[this.index];
   if(this.phase==='moving'){const dist=Math.abs(this.position-target.heightMm),t=dist/this.config.speed,used=Math.min(remaining,t);this.position+=Math.sign(target.heightMm-this.position)*used*this.config.speed;remaining-=used;this.clock+=used;if(t<=used+1e-8){this.position=target.heightMm;this.phase='settling';this.elapsed=0;}else break;}
   else {const used=Math.min(remaining,this.config.dwell-this.elapsed);this.elapsed+=used;this.clock+=used;remaining-=used;
    if(this.elapsed>=this.config.dwell-1e-8){const row=validateSample({...target,radialErrorMm:simulatedReading(target,this.config),timestamp:new Date().toISOString(),source:'simulation'});this.rows.push(row);added.push(row);this.index++;this.elapsed=0;if(this.index===this.plan.length)this.phase='done';else this.phase='moving';}else break;}
  }return added;
 }
}
export function parseSession(text){const data=JSON.parse(text);if(data.schema!=='elephant-foot.measurement.v1'||!Array.isArray(data.samples)||data.samples.length>10000)throw Error('不是支持的测量记录文件');const config=configOf(data.config);const samples=data.samples.map(validateSample);const ids=new Set();for(const s of samples){if(ids.has(s.layer))throw Error('层号重复');ids.add(s.layer);if(s.heightMm>config.height+.001)throw Error('测量高度超出样件');}return {config,samples};}
export function toCsv(rows){const head='layer,height_mm,original_print_height_mm,radial_error_mm,radial_compensation_mm,timestamp,source';return '\uFEFF'+[head,...rows.map(r=>[r.layer,r.heightMm.toFixed(3),r.printHeightMm===undefined?'':r.printHeightMm.toFixed(3),r.radialErrorMm.toFixed(4),r.compensationMm.toFixed(4),r.timestamp,r.source].join(','))].join('\r\n');}
