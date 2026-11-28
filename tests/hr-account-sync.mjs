import assert from 'node:assert/strict';
import fs from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {roleAllowedByPosition} from '../lib/staff-roles.ts';
const pg=new PGlite();
await pg.exec(`
 create role anon; create role authenticated;
 create table cx_people(id int primary key,staff_code text,unit text,active boolean,admin boolean,department text,team_lead boolean,legacy_operator boolean,team_department text,managed_departments text[],position_policy text,work_role_reviewed boolean,can_approve_work boolean,version uuid);
 create table ksnk_legacy_rows(id int primary key,sheet_name text,data jsonb);
 create function cx_key(text) returns text language sql immutable as $$select lower(trim($1))$$;
 create function cx_source_unit(jsonb) returns text language sql immutable as $$select $1->>'unitId'$$;
 create view cx_staff_catalog as select id source_id,data->>'Mã NV' code,data->>'unitId' unit,1 copies from ksnk_legacy_rows;
 create function nk_approval_position(p cx_people) returns text language sql stable as $$select data->>'Chức vụ' from ksnk_legacy_rows where data->>'Mã NV'=p.staff_code$$;
 insert into ksnk_legacy_rows values(1,'DM_NHANVIEN','{"unitId":"surgery","Mã NV":"nv1","Chức vụ":"Trưởng khoa"}');
 insert into cx_people values(1,'nv1','surgery',true,false,'CSSD',false,true,null,'{}',null,true,true,gen_random_uuid());
`);
await pg.exec(fs.readFileSync('supabase/20261128_hr_account_role_sync.sql','utf8'));
const person=async()=>(await pg.query('select * from cx_people where id=1')).rows[0];
await pg.exec(`update ksnk_legacy_rows set data=data||'{"Chức vụ":"Nhân viên"}'`);
assert.equal((await person()).legacy_operator,false);
assert.equal((await person()).can_approve_work,false);
await pg.exec(`update ksnk_legacy_rows set data=data||'{"Chức vụ":"Phó khoa"}'`);
assert.equal((await person()).team_lead,false);
assert.equal((await person()).active,true);
for(const [position,role] of [['Phó khoa','deputy'],['Điều dưỡng trưởng','head_nurse'],['Tổ trưởng','team'],['Trưởng khoa','chief'],['Nhân viên','staff']]){
 for(const candidate of ['deputy','head_nurse','team','chief','staff'])
  assert.equal(roleAllowedByPosition(candidate,position),candidate===role);
}
await pg.close();
console.log('PASS role mapping, demotion, approval revocation, promotion pending admin, account identity');
