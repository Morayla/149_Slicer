// One outstanding frame per view. Static and inactive workspaces stop drawing.
export function createFrameScheduler(draw,{requestFrame=requestAnimationFrame,cancelFrame=cancelAnimationFrame}={}){
 let pending=null,active=true,disposed=false;
 function request(){if(disposed||!active||pending!==null)return;pending=requestFrame(time=>{pending=null;if(!active||disposed)return;if(draw(time))request();});}
 function setActive(value){active=!!value;if(!active&&pending!==null){cancelFrame(pending);pending=null;}if(active)request();}
 function dispose(){disposed=true;if(pending!==null)cancelFrame(pending);pending=null;}
 return {request,setActive,dispose};
}
export function workspaceFrames(draw){
 const frames=createFrameScheduler(draw);
 const sync=()=>frames.setActive(!document.hidden&&document.documentElement.dataset.workbenchActive!=='false');
 document.addEventListener('visibilitychange',sync);
 document.addEventListener('149-workspace-active',sync);
 sync();
 return {...frames,dispose(){document.removeEventListener('visibilitychange',sync);document.removeEventListener('149-workspace-active',sync);frames.dispose();}};
}
