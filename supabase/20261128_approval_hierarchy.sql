-- Professional hierarchy only; existing grants and history stay unchanged.
CREATE OR REPLACE FUNCTION public.nk_approval_rank(pos text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
 select case pos when 'Trưởng khoa' then 4 when 'Phó khoa' then 3 when 'Điều dưỡng trưởng' then 2 when 'Tổ trưởng' then 1 when 'Nhân viên' then 0 else -1 end
$function$;
