import {SETUP_ID,setupCompatible} from './hardware-setup.mjs';
import {validatedTravelSpeed} from './travel-speed.mjs';
import {createAutoScan} from './needle-ui.mjs';
import {currentLanguage} from './text.mjs';
const strings={
 homeSave:['将当前位置设为 Home（置零）','Set current position as Home (zero)'],homeReset:['恢复默认 Home','Restore default Home'],homeDestination:['Home 原点','Home origin'],homeReference:['重新校准下限位','Re-reference lower limit'],homeStored:['已保存','Saved'],homeDefault:['默认','Default'],homeUnset:['等待设备连接','Waiting for device'],homeTeaching:['这里设为 0 mm，向上为正。位置已知时 Home 直接回到这里；重启或位置丢失后，先校准下限位再回到这里。置零不会移动设备。','This is 0 mm; upward is positive. Home returns here directly when position is known. After restart or lost position, it references the lower switch first. Setting zero does not move the stage.'],homeParking:['正在返回 Home 原点…','Returning to Home origin…'],homeSavedMessage:['当前位置已设为 Home（0 mm）；设备未移动。','Current position set to Home (0 mm); no movement.'],homeResetMessage:['已恢复默认 Home 10 mm；设备未移动。','Default Home restored; no movement.'],
 speed:['统一移动速度','All travel speed'],speedHelp:['≥ 0.10 · 无固定速度上限；归零、退离、手动移动和扫描共用。实际速度受加减速与设备能力影响，距离按暂定参数估算。','≥ 0.10 · No fixed speed cap; shared by home, retreat, jog and scan. Actual speed depends on ramps and hardware; distance is provisional.'],speedInvalid:['请输入不小于 0.10 的有效速度（mm/s）','Enter a finite speed of at least 0.10 mm/s'],task:['Task · 实机','Task · Device'],specimen:['样件参数','Specimen'],camera:['相机','Camera'],dial:['表盘放大','Dial'],full:['完整画面','Full view'],expand:['放大 ↗','Expand ↗'],close:['关闭','Close'],home:['Home · 回原点','Home · Return'],stop:['■ 停止','■ Stop'],distance:['移动距离','Jog distance'],toward:['↓ 靠近下限位','↓ Toward lower limit'],away:['↑ 远离下限位','↑ Away from lower limit'],position:['相对 Home 位置','Position from Home'],unknown:['待归零','Home required'],limit:['下限位','Upper limit'],pressed:['已触发','Pressed'],released:['已松开','Released'],connecting:['正在连接树莓派…','Connecting to Pi…'],connected:['树莓派已连接','Pi connected'],offline:['树莓派未连接','Pi disconnected'],waiting:['正在获取画面…','Waiting for camera…'],stale:['相机画面已中断','Camera unavailable'],note:['位置按暂定丝杆参数估算。Home 为 0 mm，向上远离下限位为正，向下为负；需要重新找限位时点“重新校准下限位”。','Estimated position: Home is 0 mm, upward away from the lower limit is positive, downward is negative. Use Re-reference lower limit when needed.'],manual:['相机实时画面 · 扫描停稳后多帧读数','Live camera · scan readings use settled frames'],browser:['请在 149 软件中使用实机控制','Open 149 to use device controls'],idle:['就绪','Ready'],homing:['正在归零…','Homing…'],retreat:['正在退离限位…','Moving away from limit…'],moving:['正在移动…','Moving…'],settling:['停稳中…','Settling…'],reading:['读取数值…','Reading gauge…'],complete:['完成','Complete'],stopped:['已停止 · 请重新归零','Stopped · Home again'],mm:['估算 mm','estimated mm']};
const t=k=>strings[k]?.[currentLanguage()==='en'?1:0]??k;
export function createHardware({getSpecimen,onHardwareState=()=>{}}) {
 const panel=document.getElementById('parameter-panel');
 const original=document.createElement('div');original.id='specimen-settings';
 while(panel.firstChild)original.append(panel.firstChild);
 const header=document.createElement('div');header.className='task-tabs';
 header.innerHTML='<button id="task-tab" aria-selected="true">Task</button><button id="specimen-tab" aria-selected="false">Specimen</button>';
 const section=document.createElement('section');section.id='hardware-task';
 section.innerHTML=`<div class="hardware-heading"><span data-h="camera"></span><button id="camera-expand" data-h="expand"></button></div>
 <div class="camera-frame dial-crop"><img id="camera-image" alt="Live dial indicator camera" hidden><span id="camera-message"></span></div>
 <div class="camera-modes"><button id="camera-dial" class="selected" data-h="dial"></button><button id="camera-full" data-h="full"></button></div>
 <div id="hardware-speed-control"><label for="hardware-speed" data-h="speed"></label><div class="field"><input id="hardware-speed" type="number" min="0.1" step="0.05" value="0.8" aria-describedby="hardware-speed-help"><span>mm/s</span></div><p id="hardware-speed-help" class="hardware-note" data-h="speedHelp"></p></div>
 <p id="hardware-connection" role="status"></p>
 <div class="hardware-actions"><button id="hardware-home" data-h="home"></button><button id="hardware-stop" data-h="stop"></button></div>
 <label for="hardware-distance" data-h="distance"></label><div class="field"><input id="hardware-distance" type="number" min="0.1" max="10" step="0.1" value="1"><span>mm</span></div>
 <div class="jog-presets">${[.1,1,5,10].map(v=>`<button data-distance="${v}">${v}</button>`).join('')}</div>
 <div class="jog-buttons"><button id="hardware-toward" data-h="toward"></button><button id="hardware-away" data-h="away"></button></div>
 <div class="home-destination">
 <p id="hardware-home-target" class="hardware-note"></p>
 <button id="hardware-home-save" data-h="homeSave"></button>
 <button id="hardware-home-reset" data-h="homeReset"></button>
 <button id="hardware-reference" data-h="homeReference"></button>
 <p class="hardware-note" data-h="homeTeaching"></p>
 <p id="hardware-home-feedback" class="hardware-note" role="status"></p>
 </div>
 <div class="hardware-progress"><div id="hardware-progress-fill"></div></div>
 <p id="hardware-phase" role="status"></p><div class="hardware-position"><span data-h="position"></span><strong id="hardware-position">—</strong><small data-h="mm"></small></div>
 <div class="hardware-limit"><span data-h="limit"></span><span id="hardware-limit">—</span></div>
 <p id="hardware-error" role="alert"></p><p class="hardware-note" data-h="note"></p><p class="hardware-note" data-h="manual"></p>`;
 panel.append(header,section,original);original.hidden=true;
 const dialog=document.createElement('dialog');dialog.id='camera-dialog';dialog.innerHTML='<div class="dialog-heading"><h2 data-h="camera"></h2><div><button id="camera-stop" data-h="stop"></button> <button id="camera-close" data-h="close"></button></div></div><div class="camera-large"><img id="camera-large-image" alt="Live camera"></div><p id="camera-large-state"></p>';
 document.body.append(dialog);
 const $=id=>document.getElementById(id), pending=new Map();let serial=0,state=null,connected=false,tab=true,crop=true,active=true,cameraAt=0,statusPending=false,cameraPending=false,lastError='',networkError='',sending=false;
 const host=window.webkit?.messageHandlers?.calibration;
 function request(method,params={}) {
  return new Promise((resolve,reject)=>{
   if(!host){reject(Error(t('browser')));return;}
   if(['home','reference','jog','scan','home-position'].includes(method)){if(!setupCompatible(state)){reject(Error('设备配置不匹配，请连接新版下限位控制器'));return;}params={...params,setupId:SETUP_ID};}
   const id=String(++serial),timer=setTimeout(()=>{pending.delete(id);reject(Error('Scanner request timed out'));},6000);
   pending.set(id,{resolve,reject,timer});host.postMessage({action:'hardware',id,method,params});
  });
 }
 function response(value){const p=pending.get(value.id);if(!p)return;pending.delete(value.id);clearTimeout(p.timer);if(value.error)p.reject(Error(value.error));else p.resolve(value.data);}
 function getSpeed(){try{return validatedTravelSpeed($('hardware-speed').value);}catch{throw Error(t('speedInvalid'));}}
 try{const saved=validatedTravelSpeed(localStorage.getItem('149-travel-speed'));$('hardware-speed').value=saved;}catch{}
 $('hardware-speed').onchange=()=>{try{const v=getSpeed();localStorage.setItem('149-travel-speed',String(v));lastError='';}catch(e){lastError=e.message;}render();};
 const autoScan=createAutoScan({request,section,getSpecimen,getSpeed});
 function language(){autoScan.language();for(const el of document.querySelectorAll('[data-h]'))el.textContent=t(el.dataset.h);$('task-tab').textContent=t('task');$('specimen-tab').textContent=t('specimen');render();}
 function render(){
  const busy=!!state?.busy||sending;autoScan.update(state,connected);onHardwareState(connected?state:null,tab);
  const compatible=setupCompatible(state);
  const target=state?.homePositionMm;
  $('hardware-home-save').disabled=!connected||!compatible||busy||!state?.homed||state?.limitPressed||!Number.isFinite(state?.position)||state.position<10||!Number.isFinite(target);
  $('hardware-home-reset').disabled=!connected||!compatible||busy||!state?.homePositionSaved;
  $('hardware-home-target').textContent=connected&&Number.isFinite(target)?`${t('homeDestination')} · 0.00 ${t('mm')} · ${t(state.homePositionSaved?'homeStored':'homeDefault')} · 下限位退离 ${target.toFixed(1)} mm · 软件行程至 ${state.maxPositionMm} mm（估算）`:t('homeUnset');
  $('hardware-connection').textContent=host?(connected?t('connected'):t(statusPending?'connecting':'offline')):t('browser');
  $('hardware-home').disabled=!connected||!compatible||busy||state?.limitPressed;
  $('hardware-reference').disabled=!connected||!compatible||busy||state?.limitPressed;
  $('hardware-stop').disabled=!host;$('camera-stop').disabled=!host;
  for(const id of ['hardware-toward','hardware-away'])$(id).disabled=!connected||!compatible||busy||!state?.homed||state?.limitPressed;
  $('hardware-distance').disabled=busy;$('hardware-speed').disabled=busy;
  for(const b of section.querySelectorAll('[data-distance]'))b.disabled=busy;
  // Keep controls accessible throughout a move rather than hiding Stop behind another tab.
  $('specimen-tab').disabled=busy;
  $('hardware-position').textContent=Number.isFinite(state?.positionFromHomeMm)?(Math.abs(state.positionFromHomeMm)<.005?'0.00':state.positionFromHomeMm.toFixed(2)):'—';
  $('hardware-limit').textContent=connected?t(state?.limitPressed?'pressed':'released'):'—';
  const phases={settling:'settling',reading:'reading','scan-moving':'moving',home:'homeParking',reference:'homing',retreat:'retreat','home-position':'homeParking',jog:'moving',complete:'complete',stopped:'stopped',idle:'idle'};
  $('hardware-phase').textContent=state?t(state.phase==='idle'&&!state.homed?'unknown':phases[state.phase]??'idle'):t('unknown');
  $('hardware-progress-fill').style.width=`${Math.max(0,Math.min(1,state?.progress||0))*100}%`;
  $('hardware-error').textContent=lastError||networkError||(connected&&!compatible?'设备尚未更新为下限位配置；运动按钮已停用。':state?.error)||'';
  const live=Date.now()-cameraAt<3500;
  $('camera-image').hidden=!live;$('camera-message').hidden=live;
  $('camera-message').textContent=t(cameraAt?'stale':'waiting');
  $('camera-large-image').hidden=!live;$('camera-large-state').textContent=live?t('manual'):t('stale');
 }
 async function pollStatus(){if(statusPending||!host)return;statusPending=true;try{state=await request('status');connected=true;networkError='';}catch(e){connected=false;networkError=e.message;}finally{statusPending=false;render();}}
 async function pollCamera(){if(cameraPending||!host||!active||(!tab&&!dialog.open)||document.hidden)return;cameraPending=true;try{const data=await request('camera');let source=data.image;if(state?.calibration?.profile==='katsu-lcd-mm-v1'){const im=new Image();await new Promise((ok,fail)=>{im.onload=ok;im.onerror=fail;im.src=source;});const c=document.createElement('canvas'),a=state.calibration.rotation??180,side=a%180!==0;c.width=side?im.height:im.width;c.height=side?im.width:im.height;const ctx=c.getContext('2d');ctx.translate(c.width/2,c.height/2);ctx.rotate(-a*Math.PI/180);ctx.drawImage(im,-im.width/2,-im.height/2);source=c.toDataURL('image/jpeg',.9);}$('camera-image').src=source;$('camera-large-image').src=source;cameraAt=Date.now();}catch{}finally{cameraPending=false;render();}}
 async function motion(method,params){if(sending||state?.busy)return;sending=true;lastError='';render();try{await request(method,params);await pollStatus();}catch(e){lastError=e.message;await request('stop').catch(()=>{});}finally{sending=false;render();}}
 async function saveHome(mode){
  if(sending||state?.busy)return;
  sending=true;lastError='';$('hardware-home-feedback').textContent='';render();
  try{await request('home-position',{mode});await pollStatus();$('hardware-home-feedback').textContent=t(mode==='current'?'homeSavedMessage':'homeResetMessage');}
  catch(e){lastError=e.message;}
  finally{sending=false;render();}
 }
 $('hardware-home-save').onclick=()=>saveHome('current');
 $('hardware-home-reset').onclick=()=>saveHome('reset');
 $('hardware-reference').onclick=()=>{try{motion('reference',{speedMmS:getSpeed()});}catch(e){lastError=e.message;render();}};
 $('hardware-home').onclick=()=>{try{motion('home',{speedMmS:getSpeed()});}catch(e){lastError=e.message;render();}};
 $('hardware-stop').onclick=async()=>{try{await request('stop');lastError='';await pollStatus();}catch(e){lastError=e.message;render();}};
 $('camera-stop').onclick=()=>$('hardware-stop').click();
 for(const direction of ['toward','away'])$(`hardware-${direction}`).onclick=()=>{const mm=Number($('hardware-distance').value);if(!Number.isFinite(mm)||mm<.1||mm>10){lastError=currentLanguage()==='en'?'Enter 0.1–10 mm':'请输入 0.1–10 mm';render();return;}try{motion('jog',{mm,direction,speedMmS:getSpeed()});}catch(e){lastError=e.message;render();}};
 for(const b of section.querySelectorAll('[data-distance]'))b.onclick=()=>{$('hardware-distance').value=b.dataset.distance;};
 function select(value){tab=value;onHardwareState(connected?state:null,tab);autoScan.select(value);section.hidden=!value;original.hidden=value;$('task-tab').setAttribute('aria-selected',String(value));$('specimen-tab').setAttribute('aria-selected',String(!value));if(value)pollCamera();}
 $('task-tab').onclick=()=>select(true);$('specimen-tab').onclick=()=>select(false);
 function setCrop(value){crop=value;section.querySelector('.camera-frame').classList.toggle('dial-crop',crop);dialog.querySelector('.camera-large').classList.toggle('dial-crop',crop);$('camera-dial').classList.toggle('selected',crop);$('camera-full').classList.toggle('selected',!crop);}
 $('camera-dial').onclick=()=>setCrop(true);$('camera-full').onclick=()=>setCrop(false);
 $('camera-expand').onclick=()=>{setCrop(crop);dialog.showModal();pollCamera();};$('camera-close').onclick=()=>dialog.close();
 setInterval(pollStatus,1000);setInterval(pollCamera,500);setInterval(render,1000);
 autoScan.select(true);language();pollStatus();pollCamera();
 return {response,language,setActive(value){active=value;if(!value)request('stop').catch(()=>{});if(value)pollCamera();}};
}
