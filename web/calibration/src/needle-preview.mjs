// Preview only. Scan acquisition and saved measurements never use this filter.
export class NeedlePreview {
 constructor(){this.reset();}
 reset(){this.samples=[];}
 push(reading,now=Date.now()){
  const digital=reading?.method==='lcd-seven-segment';
  if(this.samples.length&&this.samples[0].digital!==digital)this.reset();
  if(!Number.isFinite(reading?.readingMm)||!(reading.confidence>=(digital?.65:.35))){this.reset();return;}
  this.samples=this.samples.filter(s=>now-s.time<=4000);
  this.samples.push({value:reading.readingMm,time:now,digital});this.samples=this.samples.slice(-5);
 }
 snapshot(now=Date.now()){
  const samples=this.samples.filter(s=>now-s.time<=4000);
  if(!samples.length||now-samples.at(-1).time>1800)return {status:'missing'};
  if(samples.length<3)return {status:'warming'};
  const values=samples.map(s=>s.value).sort((a,b)=>a-b),range=values.at(-1)-values[0];
  if(range>(samples[0].digital?.010001:.003))return {status:'unstable',range};
  const mid=Math.floor(values.length/2),value=samples[0].digital||values.length%2?values[mid]:(values[mid-1]+values[mid])/2;
  return {status:'stable',value,range};
 }
}
