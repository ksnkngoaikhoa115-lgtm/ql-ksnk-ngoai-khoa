BEGIN;
ALTER TABLE public.cx_people DROP CONSTRAINT cx_people_managed_departments_limit;
ALTER TABLE public.cx_people ADD CONSTRAINT cx_people_managed_departments_valid CHECK (managed_departments IS NULL OR array_position(managed_departments,NULL) IS NULL);
CREATE OR REPLACE FUNCTION public.nk_managed_department_keys(p public.cx_people) RETURNS text[] LANGUAGE sql STABLE SET search_path TO 'public' AS $$
 SELECT ARRAY(SELECT DISTINCT public.cx_key(d) FROM unnest(CASE WHEN p.position_policy='deputy' AND p.team_lead AND p.work_role_reviewed AND cardinality(p.managed_departments)>0 AND public.cx_key(p.managed_departments[1])=public.cx_key(p.team_department) THEN p.managed_departments ELSE ARRAY[coalesce(nullif(p.team_department,''),p.department)] END) d WHERE nullif(public.cx_key(d),'') IS NOT NULL)
$$;
REVOKE EXECUTE ON FUNCTION public.nk_managed_department_keys(public.cx_people) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nk_managed_department_keys(public.cx_people) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
