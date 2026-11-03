CREATE OR REPLACE FUNCTION "private"."study_reporting_snapshot_rights"("p_snapshot" "uuid", "p_actor" "uuid", "p_client" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    SET "lock_timeout" TO '2s'
    AS $_$
declare scope jsonb;d record;t text;seen_row integer;deadline timestamptz:=clock_timestamp()+interval '10 seconds';begin
 select source_authorization->'sourceScope' into scope from private.study_source_snapshots where id=p_snapshot;
 perform private.study_require(jsonb_typeof(scope)='array' and jsonb_array_length(scope) between 1 and 512,'DISCLOSURE_DENIED');
 for d in select distinct x->>'kind' kind,coalesce(x->>'id',x->'identity'->>'id') id,coalesce(x->>'version',x->'identity'->>'version') version
  from jsonb_array_elements(scope)e(x) order by kind,id,version loop
  perform private.study_require(clock_timestamp()<deadline,'CAPABILITY_UNAVAILABLE');
  t:=case d.kind when 'lifecyclemodel' then 'lifecyclemodels' when 'process' then 'processes' when 'flow' then 'flows' when 'flowproperty' then 'flowproperties' when 'unitgroup' then 'unitgroups' end;
  perform private.study_require(t is not null,'REFERENCE_MISMATCH');
  execute format('select 1 from public.%I where id=$1 and version=$2 for share nowait',t) into seen_row using d.id::uuid,d.version;
  perform private.study_require(seen_row=1,'DISCLOSURE_DENIED');
 end loop;
 perform private.study_snapshot_rights(p_snapshot,p_actor,p_client);
exception when lock_not_available or deadlock_detected then raise exception using errcode='P0001',message='CAPABILITY_UNAVAILABLE';
end $_$;

ALTER FUNCTION "private"."study_reporting_snapshot_rights"("p_snapshot" "uuid", "p_actor" "uuid", "p_client" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_reporting_snapshot_rights"("p_snapshot" "uuid", "p_actor" "uuid", "p_client" "text") FROM PUBLIC;
