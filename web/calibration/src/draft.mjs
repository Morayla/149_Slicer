// A measurement layer center is not an EF wall-turn boundary. Convert via print Z.
export function compensationDraft(config,samples,target,excluded=[]){
 const rows=samples.filter(r=>!excluded.includes(r.layer)).map(r=>({...r,z:config.height-r.heightMm})).sort((a,b)=>a.z-b.z);
 if(rows.length<5)throw Error('至少需要五层有效记录');
 if(!target||!target.eligible)throw Error('当前造型不支持这项补偿');
 if(![target.layerHeight,target.baseHeight,target.height].every(Number.isFinite)||target.layerHeight<=0)throw Error('切片参数无效');
 const tail=rows.slice(-3).map(r=>r.radialErrorMm).sort((a,b)=>a-b),baseline=tail[1];
 if(tail[2]-tail[0]>config.tolerance)throw Error('尾部读数尚未稳定，请增加测量范围');
 // Pool adjacent violators; preserve raw measurements, fit a non-increasing profile.
 const blocks=[];for(const row of rows){blocks.push({sum:Math.max(0,row.radialErrorMm-baseline),n:1});while(blocks.length>1&&blocks.at(-2).sum/blocks.at(-2).n<blocks.at(-1).sum/blocks.at(-1).n){const b=blocks.pop(),a=blocks.pop();blocks.push({sum:a.sum+b.sum,n:a.n+b.n});}}
 const fit=blocks.flatMap(b=>Array(b.n).fill(b.sum/b.n));
 const at=z=>{if(z<=rows[0].z)return fit[0];for(let i=1;i<rows.length;i++)if(z<=rows[i].z){const t=(z-rows[i-1].z)/(rows[i].z-rows[i-1].z);return fit[i-1]*(1-t)+fit[i]*t;}return fit.at(-1);};
 const turns=Math.floor((rows.at(-1).z-target.baseHeight)/target.layerHeight);
 if(turns<1||turns>200||target.baseHeight+turns*target.layerHeight>target.height)throw Error('有效记录不足以覆盖当前切片的墙体圈数');
 const amount=at(target.baseHeight);if(amount<.001)throw Error('当前记录没有足够的外扩量生成补偿');
 if(amount>config.lineWidth/2)throw Error('补偿量超过半个线宽，请复核读数');
 const percentages=Array.from({length:turns+1},(_,i)=>i===0?100:i===turns?0:Number((100*at(target.baseHeight+i*target.layerHeight)/amount).toFixed(5)));
 return {amount:Number(amount.toFixed(4)),turns,table:percentages.map((v,i)=>`${i}:${v}`).join('\n'),baseline,simulated:rows.some(r=>r.source!=='device'),usedLayers:rows.length,method:'tail median baseline; monotone fit; print-Z interpolation; zero at final wall turn',target:{...target}};
}
