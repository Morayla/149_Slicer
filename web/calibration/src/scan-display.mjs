export function displayDelta(value,threshold=.01){
 if(!Number.isFinite(value))return '—';
 if(Math.abs(value)<=threshold)return '≈ 0.00';
 return `${value>=0?'+':'−'} ${Math.abs(value).toFixed(2)}`;
}
export function scanErrorText(error,language='zh'){
 if(!error)return '';
 if(language==='en')return error;
 if(/Digital display is blank|Digital mm unit is not visible/.test(error))return '数显屏幕未亮或数字不清楚，请打开电子表、切到 mm 并检查反光。';
 if(/Digital.*decimal|Digital unit|Digital mm unit changed/.test(error))return '小数点或 mm 标识无法确认，请检查单位、遮挡和数字框选区域。';
 if(/Digital.*still changing/.test(error))return '数显读数仍在变化，请等探针停稳。';
 if(/Digital|digital/.test(error))return '数显读数未通过核对，请检查数字区域、对焦和反光，必要时重新校准。';
 if(/Dial outline|Dial moved/.test(error))return '表盘已偏出可跟踪范围或外圈被遮挡，请检查相机画面。';
 if(/Unclear frames|Needle tip|counterweight|Ambiguous|Needle is not clear|Needle shaft|short pointer/.test(error))return '暂未取得足够清晰的指针方向；请检查画面是否晃动或遮挡。';
 if(/did not stabilise|still moving|Not enough fresh/.test(error))return '等待后仍未取得足够稳定的清晰画面；请检查晃动、光线和对焦。';
 if(/Connection lost/.test(error))return '连接中断，已停止。';
 if(/Counter|counter readings|Black needle/.test(error))return '小计圈盘或黑色指针无法可靠识别；检查反光、遮挡及双表盘校准。若接近 0/10 mm，先让探针适当预压。';
 if(/Hardware setup changed/.test(error))return '限位配置已改变，请重新打开新版 149。';
 if(/Upper limit|Limit switch/.test(error))return '触发限位，已停止。';
 if(/Stopped by operator/.test(error))return '已收到停止指令。';
 if(/Service restarted/.test(error))return '服务已重启；保留记录，请重新归零。';
 if(/stale|Camera/.test(error))return '相机画面中断，已停止。';
 return error;
}
