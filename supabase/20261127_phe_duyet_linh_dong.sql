begin;
-- Staged, additive approval RPCs. No changes to existing records on install.
-- All functions are invoker-security and service_role-only.
create or replace function public.nk_approval_position(p public.cx_people)
returns text language sql stable set search_path=public as $$
 select case public.cx_key(coalesce(nullif(r.data->>'Chức vụ',''),r.data->>'Chức danh',''))
 when 'truong khoa' then 'Trưởng khoa' when 'pho khoa' then 'Phó khoa'
 when 'dieu duong truong' then 'Điều dưỡng trưởng' when 'dd truong' then 'Điều dưỡng trưởng'
 when 'to truong' then 'Tổ trưởng' when 'to truong bo phan' then 'Tổ trưởng'
 when 'nhan vien' then 'Nhân viên' when 'nv' then 'Nhân viên'
 when 'ho ly' then 'Nhân viên' when 'xu ly dung cu' then 'Nhân viên'
 when 'nhan vien xu ly dung cu' then 'Nhân viên' when 'nhan vien giam sat' then 'Nhân viên'
 when 'nhan vien giat la' then 'Nhân viên' when 'giam sat' then 'Nhân viên'
 when 'giat la' then 'Nhân viên' when 'dung cu' then 'Nhân viên'
 when 'nv dung cu' then 'Nhân viên' when 'nhan vien dung cu' then 'Nhân viên'
 when 'ky thuat vien' then 'Nhân viên' when 'ktv' then 'Nhân viên' end
 from public.cx_staff_catalog s join public.ksnk_legacy_rows r on r.id=s.source_id
 where p.active and p.unit='surgery' and nullif(p.staff_code,'') is not null
 and s.unit=p.unit and s.code=public.cx_key(p.staff_code) and s.copies=1
 and public.cx_key(coalesce(r.data->>'Trạng thái','')) in ('','dang lam viec','dang lam','lam viec','hoat dong')
$$;
create or replace function public.nk_approval_rank(pos text)
returns integer language sql immutable set search_path=public as $$
 select case pos when 'Trưởng khoa' then 3 when 'Phó khoa' then 2 when 'Điều dưỡng trưởng' then 2 when 'Tổ trưởng' then 1 when 'Nhân viên' then 0 else -1 end
$$;
create or replace function public.nk_approval_scope(p public.cx_people,k text)
returns text language sql stable set search_path=public as $$
 with policy as (
 select coalesce(fp.grants #>> array[k,'approve'],rp.grants #>> array[k,'approve'],
 case when k='reminders' then coalesce(fp.grants #>> array['tasks','approve'],rp.grants #>> array['tasks','approve']) end,
 case when p.admin or (p.legacy_operator and p.work_view) then 'hospital'
 when p.team_lead and p.work_role_reviewed and p.work_view then 'team' else 'none' end) as grant_scope,
 public.nk_work_feature_scope(p,k,'view') as view_scope
 from (select 1) dummy
 left join public.nk_feature_permissions fp on fp.person=p.id
 left join public.nk_role_permission_defaults rp on rp.role=case when p.legacy_operator and p.work_view then 'chief' when p.team_lead and p.work_role_reviewed and p.work_view then 'team' else 'staff' end
 )
 select case when not coalesce(p.active and p.can_approve_work and p.work_edit and (p.admin or p.legacy_operator or (p.team_lead and p.work_role_reviewed)),false) then 'none'
 when grant_scope in ('hospital','team') and view_scope in ('hospital','team')
 then case when grant_scope='team' or view_scope='team' then 'team' else 'hospital' end else 'none' end from policy
$$;
create or replace function public.nk_approval_eligible(p public.cx_people,t public.cx_threads,requester text)
returns boolean language sql stable set search_path=public as $$
 select coalesce(public.nk_approval_rank(public.nk_approval_position(p))>0
 and p.id::text<>coalesce(requester,'') and not(p.id=any(coalesce(t.performers,'{}'::uuid[])))
 and public.nk_work_scope(p,t)
 and (public.nk_approval_scope(p,case when t.kind='task' then 'tasks' else 'reminders' end)='hospital'
 or (public.nk_approval_scope(p,case when t.kind='task' then 'tasks' else 'reminders' end)='team'
 and nullif(public.cx_key(coalesce(nullif(p.team_department,''),p.department)),'') is not null
 and (nullif(public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận','')),'') is null
 or public.cx_key(coalesce(r.data->>'Bộ phận',r.data->>'Thuộc bộ phận',''))=public.cx_key(coalesce(nullif(p.team_department,''),p.department)))
 and cardinality(coalesce(t.performers,'{}'::uuid[]))>0
 and not exists(select 1 from unnest(coalesce(t.performers,'{}'::uuid[])) q(id)
 left join public.cx_people person on person.id=q.id where person.id is null or person.unit is distinct from p.unit or public.cx_key(person.department) is distinct from public.cx_key(coalesce(nullif(p.team_department,''),p.department))))),false)
 from public.ksnk_legacy_rows r where r.id=t.source_row
$$;
create or replace function public.nk_approval_context(who uuid,work_id uuid)
returns jsonb language plpgsql stable set search_path=public as $$
declare t public.cx_threads;a public.cx_people;d jsonb;h jsonb;st text;pos text;owner uuid;assigned text;requester text;
 can_review boolean:=false;can_submit boolean:=false;can_reopen boolean:=false;prev_rank integer;ver integer;opts jsonb;
begin
 select * into t from public.cx_threads where id=work_id and kind in ('task','reminder');
 select * into a from public.cx_people where id=who and active and unit='surgery';
 if t.id is null or a.id is null or not coalesce(public.nk_work_scope(a,t),false) then return null;end if;
 select data into d from public.ksnk_legacy_rows where id=t.source_row and sheet_name=case when t.kind='task' then 'GIAO VIỆC' else 'NHAC_VIEC_GHI_CHU' end;
 if d is null then return null;end if;
 h=coalesce(nullif(d->>'Lịch sử phê duyệt',''),'[]')::jsonb;
 if jsonb_typeof(h)<>'array' then return null;end if;
 ver=coalesce((d->>'Phiên bản phê duyệt')::int,1);
 st=coalesce(nullif(d->>'Trạng thái phê duyệt',''),case when t.kind='task' then 'CHƯA XIN Ý KIẾN' else 'KHÔNG YÊU CẦU' end);
 pos=public.nk_approval_position(a);owner=coalesce(t.source_creator_id,t.owner_id);
 assigned=d->>'Tài khoản duyệt';requester=d->>'Người xin duyệt ID';
 can_review=coalesce(st='CHỜ PHÊ DUYỆT' and assigned=who::text and nullif(requester,'') is not null and public.nk_approval_eligible(a,t,requester),false);
 can_reopen=coalesce(st in ('TỪ CHỐI','ĐÃ PHÊ DUYỆT') and assigned=who::text and nullif(requester,'') is not null and public.nk_approval_eligible(a,t,requester),false);
 can_submit=coalesce(pos is not null and st in ('CHƯA XIN Ý KIẾN','KHÔNG YÊU CẦU','ĐÃ PHÊ DUYỆT','YÊU CẦU BỔ SUNG') and
 public.nk_work_feature_scope(a,case when t.kind='task' then 'tasks' else 'reminders' end,'edit')<>'none'
 and (who=owner or who=any(coalesce(t.performers,'{}'::uuid[])) or
 (public.nk_approval_eligible(a,t,'') and exists(select 1 from jsonb_array_elements(h) e where e->>'actor'=who::text and lower(e->>'action') in ('approve','forward','consult') and coalesce((e->>'version')::int,1)=ver))),false);
 prev_rank=public.nk_approval_rank(pos);
 if can_review or can_submit then
 select greatest(prev_rank,coalesce(max(public.nk_approval_rank(coalesce(e->>'actorPosition',public.nk_approval_position(p)))),-1)) into prev_rank
 from jsonb_array_elements(h) e left join public.cx_people p on p.id::text=e->>'actor'
 where lower(e->>'action') in ('approve','forward','consult') and coalesce((e->>'version')::int,1)=ver;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'staffCode',p.staff_code,'position',public.nk_approval_position(p),'department',p.department,'isOwner',p.id=owner) order by (p.id=owner) desc,public.nk_approval_rank(public.nk_approval_position(p)),p.name,p.id),'[]'::jsonb) into opts
 from public.cx_people p where public.nk_approval_eligible(p,t,who::text)
 and ((st='YÊU CẦU BỔ SUNG' and p.id::text=assigned and not can_review)
 or (public.nk_approval_rank(public.nk_approval_position(p))>prev_rank and not exists(select 1 from jsonb_array_elements(h) e where e->>'actor'=p.id::text and lower(e->>'action') in ('approve','forward','consult') and coalesce((e->>'version')::int,1)=ver)));
 else opts='[]'::jsonb;end if;
 return jsonb_build_object('status',st,'revision',jsonb_array_length(h),'version',ver,'history',h,'canSubmit',can_submit,'canReview',can_review,'canReopen',can_reopen,'reviewer',assigned,'owner',owner,'ownerPosition',(select public.nk_approval_position(p) from public.cx_people p where p.id=owner),'actorPosition',pos,'candidates',opts);
end $$;
create or replace function public.nk_work_decision_v2(who uuid,work_id uuid,rid uuid,operation text,reviewer uuid,note text,expected text,expected_revision int,evaluation text default null)
returns boolean language plpgsql set search_path=public as $$
declare t public.cx_threads;a public.cx_people;m public.cx_people;r public.ksnk_legacy_rows;d jsonb;h jsonb;ctx jsonb;prior jsonb;event jsonb;
 st text;new_state text;v int;target uuid;recipients uuid[];old_reviewer uuid;old_requester uuid;assigned uuid;label text;event_kind text;message text;
begin
 if rid is null or operation not in ('request','approve','forward','consult','supplement','reject','reopen') or note is null or length(note)>2000 then return false;end if;
 note=trim(note);
 select * into t from public.cx_threads where id=work_id and kind in ('task','reminder') for update;
 if not found then return false;end if;
 select * into a from public.cx_people where id=who and active and unit='surgery';
 if not found then return false;end if;
 select * into r from public.ksnk_legacy_rows where id=t.source_row and sheet_name=case when t.kind='task' then 'GIAO VIỆC' else 'NHAC_VIEC_GHI_CHU' end for update;
 if not found then return false;end if;
 ctx=public.nk_approval_context(who,work_id);
 if ctx is null then return false;end if;
 d=r.data;h=ctx->'history';st=ctx->>'status';v=(ctx->>'version')::int;
 select e into prior from jsonb_array_elements(h) e where e->>'requestId'=rid::text limit 1;
 if found then return coalesce(prior->>'actor'=who::text and prior->>'action'=operation and prior->>'opinion'=note and prior->>'inputReviewer'=coalesce(reviewer::text,'') and prior->>'evaluation'=coalesce(evaluation,''),false);end if;
 if st is distinct from expected or (ctx->>'revision')::int is distinct from expected_revision then return false;end if;
 select p.id into old_reviewer from public.cx_people p where p.id::text=d->>'Tài khoản duyệt';
 select p.id into old_requester from public.cx_people p where p.id::text=d->>'Người xin duyệt ID';
 if operation in ('request','forward','consult') then
 if note='' or reviewer is null or not exists(select 1 from jsonb_array_elements(ctx->'candidates') c where c->>'id'=reviewer::text) then return false;end if;
 if operation='request' and not (ctx->>'canSubmit')::boolean or operation<>'request' and not (ctx->>'canReview')::boolean then return false;end if;
 select * into m from public.cx_people where id=reviewer;
 assigned=reviewer;new_state='CHỜ PHÊ DUYỆT';
 d=d||jsonb_build_object('Người xin duyệt ID',who,'Tài khoản duyệt',assigned,'Người quản lý phê duyệt',m.name,'Mã người quản lý',m.staff_code,'Chức vụ phê duyệt',public.nk_approval_position(m),'Nội dung xin phê duyệt',note,'Thời gian xin phê duyệt',now(),'Phản hồi quản lý','','Ngày phê duyệt','');
 label=case operation when 'request' then 'XIN PHÊ DUYỆT' when 'forward' then 'ĐỒNG Ý VÀ TRÌNH CẤP TRÊN' else 'ĐÃ XEM XÉT VÀ XIN Ý KIẾN' end;
 else
 assigned=old_reviewer;
 if operation='reopen' then
 if not (ctx->>'canReopen')::boolean or note='' then return false;end if;
 new_state='YÊU CẦU BỔ SUNG';label='MỞ LẠI CÓ LÝ DO';v=v+1;
 else
 if not (ctx->>'canReview')::boolean then return false;end if;
 if operation in ('reject','supplement') and note='' then return false;end if;
 new_state=case operation when 'approve' then 'ĐÃ PHÊ DUYỆT' when 'supplement' then 'YÊU CẦU BỔ SUNG' else 'TỪ CHỐI' end;
 label=case operation when 'approve' then 'ĐÃ PHÊ DUYỆT' when 'supplement' then 'YÊU CẦU BỔ SUNG' else 'TỪ CHỐI PHÊ DUYỆT' end;
 end if;
 select * into m from public.cx_people where id=assigned;
 d=d||jsonb_build_object('Phản hồi quản lý',note,'Ngày phê duyệt',now());
 end if;
 if evaluation is not null then
 if operation not in ('approve','reject','supplement','forward','consult') or evaluation not in ('CHƯA BẮT ĐẦU','XUẤT SẮC','TỐT','KHÁ','CHƯA ĐẠT_LÀM LẠI','KÉM','QUÁ HẠN') then return false;end if;
 d=d||jsonb_build_object('Đánh giá quản lý',evaluation,'Đánh giá quản lý hiện tại',evaluation,'Người đánh giá hiện tại',a.name,'Thời gian đánh giá hiện tại',now());
 end if;
 event=jsonb_build_object('action',operation,'status',new_state,'at',now(),'actor',who,'actorPosition',ctx->>'actorPosition','managerName',a.name,'reviewer',assigned,'reviewerPosition',public.nk_approval_position(m),'reviewerName',m.name,'opinion',note,'requestId',rid,'inputReviewer',coalesce(reviewer::text,''),'evaluation',coalesce(evaluation,''),'version',v);
 perform set_config('ksnk.reopening',t.id::text,true);
 update public.ksnk_legacy_rows set data=d||jsonb_build_object('Trạng thái phê duyệt',new_state,'Lịch sử phê duyệt',(h||jsonb_build_array(event))::text,'Phiên bản phê duyệt',v) where id=r.id;
 perform set_config('ksnk.reopening','',true);
 if old_reviewer is not null then
 update public.nk_work_events set handled_at=coalesce(handled_at,now()) where thread=t.id and recipient=old_reviewer and kind='CHỜ PHÊ DUYỆT' and handled_at is null;
 end if;
 recipients=case when operation='request' then array[assigned] else array_append(array_append(array_append(coalesce(t.performers,'{}'::uuid[]),coalesce(t.source_creator_id,t.owner_id)),old_requester),case when operation in ('forward','consult') then assigned else null end) end;
 for target in select distinct x from unnest(recipients) x where x is not null and x<>who loop
 if exists(select 1 from public.cx_people p where p.id=target and p.active and public.nk_work_scope(p,t)) then
 event_kind=case when new_state='CHỜ PHÊ DUYỆT' and target=assigned then 'CHỜ PHÊ DUYỆT' when operation in ('forward','consult') then label else new_state end;
 insert into public.nk_work_events(thread,sender,recipient,request_id,kind,body) values(t.id,who,target,rid,event_kind,left(note,180)) on conflict do nothing;
 end if;
 end loop;
 message=label||' · '||a.name||' — '||coalesce(ctx->>'actorPosition','')||case when operation in ('request','forward','consult') then E'\nĐến: '||m.name||' — '||coalesce(public.nk_approval_position(m),'') else '' end||E'\n'||note;
 perform public.cx_append(t.id,who,message,'[]'::jsonb,rid);
 return true;
end $$;
revoke all on function public.nk_approval_position(public.cx_people),public.nk_approval_rank(text),public.nk_approval_scope(public.cx_people,text),public.nk_approval_eligible(public.cx_people,public.cx_threads,text),public.nk_approval_context(uuid,uuid),public.nk_work_decision_v2(uuid,uuid,uuid,text,uuid,text,text,int,text) from public,anon,authenticated;
grant execute on function public.nk_approval_position(public.cx_people),public.nk_approval_rank(text),public.nk_approval_scope(public.cx_people,text),public.nk_approval_eligible(public.cx_people,public.cx_threads,text),public.nk_approval_context(uuid,uuid),public.nk_work_decision_v2(uuid,uuid,uuid,text,uuid,text,text,int,text) to service_role;
commit;
