// Pure approval policy; callers must pass server-verified identities and grants.
// This module is not a substitute for transaction-level checks in Supabase.
export type Scope='none'|'self'|'team'|'hospital';
export type Position='Trưởng khoa'|'Phó khoa'|'Điều dưỡng trưởng'|'Tổ trưởng'|'Nhân viên';
export type Person={id:string;name:string;position:Position;active:boolean;linked:boolean;department:string;teamDepartment?:string;scope:Scope;viewScope:Scope;canApprove:boolean;canSubmit:boolean};
export type Status='idle'|'pending'|'approved'|'supplement'|'rejected';
export type Decision='request'|'approve'|'forward'|'consult'|'supplement'|'reject'|'reopen';
export type Event={id:string;actor:string;actorPosition:Position;reviewer:string;reviewerPosition:Position;action:Decision;status:Status;version:number;note:string};
export type Work={id:string;owner:string;performers:string[];departments:string[];version:number;status:Status;requester?:string;reviewer?:string;history:Event[]};
export type Config={parallelTransfers?:Array<readonly [Position,Position]>};
const rank:Record<Position,number>={'Nhân viên':0,'Tổ trưởng':1,'Điều dưỡng trưởng':2,'Phó khoa':2,'Trưởng khoa':3};
const normalized=(v:string)=>v.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[đĐ]/g,'d').trim().toLowerCase();
const valid=(p:Person|undefined):p is Person=>Boolean(p?.active&&p.linked&&p.id);
const manages=(scope:Scope,p:Person,w:Work)=>scope==='hospital'||scope==='team'&&w.departments.length>0&&w.departments.every(d=>normalized(d)===normalized(p.teamDepartment||p.department)&&normalized(d)!=='');
const prior=(w:Work)=>w.history.filter(e=>e.version===w.version);
const reviewed=(w:Work,id:string)=>prior(w).some(e=>e.actor===id&&['approve','forward','consult'].includes(e.action));
export function maySubmit(p:Person,w:Work):boolean{
 return valid(p)&&p.canSubmit&&w.status!=='pending'&&w.status!=='rejected'&&(w.owner===p.id||w.performers.includes(p.id)||reviewed(w,p.id)&&manages(p.scope,p,w)&&manages(p.viewScope,p,w));
}
export function eligibleReviewer(p:Person,w:Work,requester:string):boolean{
 return valid(p)&&p.canApprove&&rank[p.position]>0&&p.id!==requester&&!w.performers.includes(p.id)&&manages(p.scope,p,w)&&manages(p.viewScope,p,w);
}
function allowedNext(from:Position,to:Position,cfg:Config){
 return rank[to]>rank[from]||Boolean(cfg.parallelTransfers?.some(([a,b])=>a===from&&b===to));
}
export function candidates(w:Work,actor:Person,people:Person[],cfg:Config={},forward=false):Person[]{
 if(forward?!mayReview(actor,w):!maySubmit(actor,w))return [];
 const old=prior(w).filter(e=>['approve','forward','consult'].includes(e.action));
 return people.filter(p=>{
  if(!eligibleReviewer(p,w,actor.id)||reviewed(w,p.id))return false;
  const from=forward?actor.position:old.length?old[old.length-1].actorPosition:actor.position;
  if(w.status==='supplement'&&p.id===w.reviewer&&!forward)return true;
  return allowedNext(from,p.position,cfg);
 }).sort((a,b)=>(a.id===w.owner?-1:0)-(b.id===w.owner?-1:0)||rank[a.position]-rank[b.position]||a.name.localeCompare(b.name,'vi')||a.id.localeCompare(b.id));
}
export function mayReview(p:Person,w:Work):boolean{
 return w.status==='pending'&&w.reviewer===p.id&&Boolean(w.requester)&&eligibleReviewer(p,w,w.requester!);
}
export function decide(w:Work,actor:Person,people:Person[],input:{id:string;action:Decision;reviewer?:string;note:string;expected:Status;version:number},cfg:Config={}):Work{
 const previous=w.history.find(e=>e.id===input.id);
 if(previous){if(previous.actor===actor.id&&previous.action===input.action&&previous.note===input.note.trim()&&(!input.reviewer||previous.reviewer===input.reviewer))return w;throw Error('Mã yêu cầu đã được sử dụng');}
 if(!input.id||w.status!==input.expected||w.version!==input.version)throw Error('Trạng thái đã thay đổi');
 const note=input.note.trim();if(note.length>2000)throw Error('Nội dung quá dài');
 const a=input.action;const target=input.reviewer;let status:Status;let reviewer=w.reviewer||'';let requester=w.requester;
 if(a==='request'||a==='forward'||a==='consult'){
  if(!note)throw Error('Nhập nội dung trình');
  const selected=candidates(w,actor,people,cfg,a!=='request').find(p=>p.id===target);
  if(!selected)throw Error('Người duyệt không hợp lệ');
  reviewer=selected.id;requester=actor.id;status='pending';
 }else if(a==='reopen'){
  // Rejected work may only be reopened by its last assigned eligible reviewer, with a reason.
  if(w.status!=='rejected'||w.reviewer!==actor.id||!eligibleReviewer(actor,w,w.requester||'')||!note)throw Error('Không đủ quyền mở lại');
  status='supplement';
 }else{
  if(!mayReview(actor,w))throw Error('Không có quyền xử lý');
  if(a==='approve')status='approved';
  else if(a==='supplement'||a==='reject'){if(!note)throw Error('Bắt buộc nhập lý do');status=a==='reject'?'rejected':'supplement';}
  else throw Error('Thao tác không hợp lệ');
 }
 const selected=people.find(p=>p.id===reviewer);
 if(!selected)throw Error('Không tìm thấy người duyệt');
 const event:Event={id:input.id,actor:actor.id,actorPosition:actor.position,reviewer,reviewerPosition:selected.position,action:a,status,version:w.version,note};
 return {...w,status,requester,reviewer,history:[...w.history,event]};
}
