// No arbitrary travel-speed ceiling; reject values that cannot form a finite pulse rate.
export function validatedTravelSpeed(raw) {
 const value=typeof raw==='string' ? Number(raw) : raw;
 if(typeof value!=='number'||!Number.isFinite(value)||value<.1||!Number.isFinite(value*2000)) throw new RangeError('Invalid travel speed');
 return value;
}
