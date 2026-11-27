import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
const pg=new PGlite();
await pg.exec(`
create role anon;create role authenticated;create role service_role;
create table cx_people(id uuid primary key,name text,active boolean,admin boolean,unit text,work_edit boolean,team_lead boolean,work_role_reviewed boolean,legacy_operator boolean,staff_code text,work_view boolean,team_department text,department text);
create table cx_threads(id uuid primary key,source_row int,kind text,owner_id uuid,source_creator_id uuid,performers uuid[],title text);
create table ksnk_legacy_rows(id int primary key,sheet_name text,data jsonb);
create table nk_feature_permissions(person uuid,grants jsonb);
create table nk_role_permission_defaults(role text,grants jsonb);
create function cx_key(v text) returns text language sql immutable as $$select lower(translate(trim(coalesce(v,'')),'ăâđêôơưàáảãạầấẩẫậằắẳẵặèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ','aadeoouaaaaaaaaaaaaaaaeeeeeeeeeeiiiiiooooooooooooooouuuuuuuuuuyyyyy'))$$;
create view cx_staff_catalog as select id as source_id,'surgery'::text as unit,cx_key(data->>'Mã NV') code,count(*) over(partition by data->>'Mã NV') copies from ksnk_legacy_rows where sheet_name='DM_NHANVIEN';
create function nk_work_scope(cx_people,cx_threads) returns boolean language sql stable as $$select $1.active and $1.unit='surgery'$$;
create function nk_work_feature_scope(p cx_people,k text,a text) returns text language sql stable as $$select case when p.legacy_operator or p.admin then 'hospital' when p.team_lead then 'team' else 'self' end$$;
create table fake_messages(thread uuid,sender uuid,body text,request_id uuid,unique(thread,sender,request_id));
create function cx_append(t uuid,who uuid,txt text,attachments jsonb,rid uuid) returns void language sql as $$insert into fake_messages values(t,who,txt,rid) on conflict do nothing$$;
`);
await pg.exec(fs.readFileSync('supabase/20261121_phe_duyet_tac_vu.sql','utf8'));
await pg.exec(fs.readFileSync('supabase/20261127_phe_duyet_linh_dong.sql','utf8'));
const ids=Array.from({length:7},(_,i)=>'00000000-0000-0000-0000-'+String(i+1).padStart(12,'0'));
const [nv,tt,tk,dd,out,work,rem]=ids;
const positions=['nhan vien','to truong','truong khoa','dieu duong truong','to truong'];
for(let i=0;i<5;i++){
 const code='nv'+i,dept=i===4?'Giặt là':'CSSD';
 await pg.query("insert into cx_people values($1,$2,true,false,'surgery',$3,$4,true,$5,$2,true,$6,$6,$3)",[ids[i],code,i>0,i===1||i===4,i===2||i===3,dept]);
 await pg.query("insert into ksnk_legacy_rows values($1,'DM_NHANVIEN',$2)",[i+1,JSON.stringify({'Mã NV':code,'Chức vụ':positions[i],'Trạng thái':'dang lam viec'})]);
}
for(const [id,kind,row,sheet] of [[work,'task',10,'GIAO VIỆC'],[rem,'reminder',11,'NHAC_VIEC_GHI_CHU']]){
 await pg.query("insert into cx_threads values($1,$2,$3,$4,$4,array[$5]::uuid[],'Thử')",[id,row,kind,tk,nv]);
 await pg.query("insert into ksnk_legacy_rows values($1,$2,$3)",[row,sheet,JSON.stringify({'Bộ phận':'CSSD'})]);
}
const ctx=async(who,id=work)=>(await pg.query('select nk_approval_context($1,$2) x',[who,id])).rows[0].x;
const act=async(who,operation,reviewer=null,note='Nội dung',id=work,rid=crypto.randomUUID(),old=null)=>{const c=old||await ctx(who,id);return (await pg.query('select nk_work_decision_v2($1,$2,$3,$4,$5,$6,$7,$8) ok',[who,id,rid,operation,reviewer,note,c.status,c.revision])).rows[0].ok};
const start=await ctx(nv);assert.deepEqual(start.candidates.map(p=>p.id),[tk,tt,dd]);assert.equal(start.canSubmit,true);
const rid=crypto.randomUUID();assert.equal(await act(nv,'request',tt,'Nội dung',work,rid,start),true);assert.equal(await act(nv,'request',tt,'Nội dung',work,rid,start),true);
assert.equal(await act(tk,'approve'),false);assert.equal(await act(tt,'reject',null,''),false);
assert.equal(await act(tt,'approve'),true);assert.equal((await ctx(nv)).canSubmit,true);assert.equal((await ctx(tt)).canSubmit,true);
assert.equal(await act(tt,'request',tk),true);assert.equal(await act(tk,'reject'),true);assert.equal(await act(nv,'request',dd),false);
assert.equal(await act(tk,'reopen'),true);assert.equal(await act(nv,'request',tk),true);assert.equal(await act(tk,'approve'),true);
assert.equal((await ctx(nv)).history.length,7);assert.equal((await pg.query('select count(*)::int n from fake_messages')).rows[0].n,7);
assert.equal(await act(nv,'request',dd,'Nội dung',rem),true);assert.equal(await act(dd,'forward',tk,'Trình tiếp',rem),true);assert.equal(await act(dd,'approve',null,'',rem),false);assert.equal(await act(tk,'approve',null,'',rem),true);
assert.equal((await ctx(nv,rem)).status,'ĐÃ PHÊ DUYỆT');
await pg.close();console.log('PASS approval SQL v2: scope, assigned reviewer, repeat, rejection, reopen, transfer, message, reminder');
