CREATE OR REPLACE FUNCTION "private"."portal_display_contract_identity_v1"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
 select md5(jsonb_build_object(
 'routines',(select jsonb_agg(jsonb_build_array(p.oid::regprocedure::text,pg_get_functiondef(p.oid),p.proowner::regrole::text,p.proacl::text) order by p.oid::regprocedure::text)
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where (n.nspname='private' and (p.proname like 'display_%' or p.proname like 'portal_display_%')) or (n.nspname='api' and p.proname like 'portal_%')),
 'relations',(select jsonb_agg(jsonb_build_array(c.relname,c.relrowsecurity,c.relforcerowsecurity,c.reloptions,c.relowner::regrole::text,c.relacl::text,case when c.relkind='v' then pg_get_viewdef(c.oid) else null end,
 (select jsonb_agg(jsonb_build_array(a.attname,format_type(a.atttypid,a.atttypmod),a.attnotnull,a.attacl::text) order by a.attnum) from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
 (select jsonb_agg(pg_get_constraintdef(x.oid) order by x.conname) from pg_constraint x where x.conrelid=c.oid),
 (select jsonb_agg(jsonb_build_array(pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisready) order by i.indexrelid::regclass::text) from pg_index i where i.indrelid=c.oid),
 (select jsonb_agg(jsonb_build_array(p.polname,p.polcmd,p.polpermissive,p.polroles::text,pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname) from pg_policy p where p.polrelid=c.oid)) order by c.relname)
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind in ('r','v') and (c.relname like 'display_%' or c.relname='portal_display_derivation_contract')),
 'writers',(select jsonb_agg(jsonb_build_array(t.tgrelid::regclass::text,pg_get_triggerdef(t.oid),t.tgenabled) order by t.tgrelid::regclass::text,t.tgname) from pg_trigger t where t.tgname like 'portal_display_%' or t.tgrelid in (select c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname like 'display_%'))
 )::text)
$$;

ALTER FUNCTION "private"."portal_display_contract_identity_v1"() OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."portal_display_contract_identity_v1"() FROM PUBLIC;
