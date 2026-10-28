// Independent, persisted scene display controls. These never alter mechanical parts.
export function electronicsFlags(name){
 const external=/^ELEC_(Wire_(MotorOutside|EndstopOutside|DCSupplyOutside|CSI_External)|DCPlugEnvelope|MotorPlug|EndstopPlug|EndstopCrimp_)/.test(name);
 const cable=/^ELEC_(Wire_|CableTie_|PowerCableTie|PiSocket_|USBPowerPlug|TMCSocket_|DCPlugEnvelope|MotorPlug|EndstopPlug|EndstopCrimp_)/.test(name);
 return {electronicsCable:cable,electronicsPart:name.startsWith('ELEC_')&&!name.startsWith('ELEC_MotorUser')&&!name.startsWith('ELEC_Camera_')&&!external};
}
export function applyElectronicsView(group,s){
 for(const mesh of group.children){
  const d=mesh.userData;
  if(d.electronicsPart||d.electronicsCable)mesh.visible=(!d.electronicsPart||s.electronicsVisible!==false)&&(!d.electronicsCable||s.wiresVisible!==false);
  if(d.electronicsCover)mesh.position.set(s.electronicsOpen?.085:0,0,s.electronicsOpen?-.020:0);
 }
}
