export type ProgressRow={department:string;total:number;done:number;overdue:number}

export function departmentProgress(rows:Record<string,unknown>[]):ProgressRow[]{
 return rows.flatMap(row=>{
  const values=[row.taskCount,row.completedTasks,row.overdueTasks]
  if(values.some(x=>x==null||x===''||!Number.isFinite(Number(x))||Number(x)<0))return []
  const [total,done,overdue]=values.map(Number)
  return total>0?[{department:String(row.department||'Chưa ghi bộ phận'),total,done,overdue}]:[]
 }).sort((a,b)=>b.overdue-a.overdue||b.total-a.total||a.department.localeCompare(b.department,'vi'))
}

// Use counts on one axis. The total includes completed and overdue tasks.
export function addProgressChart(deck:any,slide:any,rows:ProgressRow[]){
 slide.addChart(deck.ChartType.bar,[
  {name:'Tổng giao',labels:rows.map(r=>r.department),values:rows.map(r=>r.total)},
  {name:'Hoàn thành',labels:rows.map(r=>r.department),values:rows.map(r=>r.done)},
  {name:'Quá hạn',labels:rows.map(r=>r.department),values:rows.map(r=>r.overdue)}
 ],{x:.8,y:2.35,w:11.75,h:4.4,barDir:'bar',barGrouping:'clustered',showLegend:true,legendPos:'b',
  catAxisLabelFontSize:12,valAxisLabelFontSize:10,valAxisMinVal:0,showValue:true,dataLabelPosition:'outEnd',
  dataLabelFormatCode:'0',showCatName:false,showSerName:false,chartColors:['50799C','178476','BC3949']})
}

export function briefingMetrics(s:Record<string,number>){
 return [
  {key:'tasks',label:'Giao việc',value:s.taskTotal||0},
  {key:'done',label:'CV hoàn thành',value:s.taskDone||0},
  {key:'late',label:'CV quá hạn',value:s.overdue||0},
  {key:'plans',label:'Kế hoạch tuần/tháng',value:(s.weeklyTotal||0)+'/'+(s.monthlyTotal||0)},
  {key:'checks',label:'Phiếu bảng kiểm',value:s.checklistForms||0},
  {key:'violations',label:'Vi phạm',value:s.violationCount||0},
  {key:'issues',label:'Tồn tại',value:s.issueCount||0},
 ]
}
