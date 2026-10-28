export const SETUP_ID='bottom-white-v1';
export function setupCompatible(state){return state?.setupId===SETUP_ID&&state?.limitEnd==='bottom'&&state?.towardDir===1;}
export function scanArrow(direction){return direction==='toward'?'↓':'↑';}
// Model layers count down from the top. Records retain their original limit orientation.
export function scanLayer(offset,config,direction,limitEnd='bottom'){
 const count=Math.ceil(config.height/config.step),index=Math.floor(offset/config.step);
 const upward=limitEnd==='bottom'?direction==='away':direction==='toward';
 return Math.max(1,Math.min(count,upward?count-index:index+1));
}
