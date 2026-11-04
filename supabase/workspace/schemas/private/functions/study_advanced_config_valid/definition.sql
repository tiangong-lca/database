CREATE OR REPLACE FUNCTION "private"."study_advanced_config_valid"("p_config" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
declare x jsonb;row jsonb;v jsonb;seen text[]:='{}'::text[];n integer;low double precision;high double precision;base double precision;kind text:=p_config->>'kind';
begin
 if octet_length(p_config::text)>262144 or p_config->>'schemaVersion' is distinct from 'lca.study-analysis-config.v2'
 or not private.study_text(p_config->'baselineRunId',36,'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
 or jsonb_typeof(p_config->'parameters') is distinct from 'array' then return false;end if;
 if kind='sensitivityOat' then
  if not private.study_keys(p_config,array['kind','schemaVersion','baselineRunId','parameters']) then return false;end if;
 elsif kind='uncertainty' then
  if not private.study_keys(p_config,array['kind','schemaVersion','baselineRunId','parameters','design','sampleCount','seedHex','generator'])
  or p_config->>'generator' is distinct from 'study.uncertainty.hmac-drbg-sha256.v1'
  or not private.study_text(p_config->'seedHex',64,'^[0-9a-f]{64}$') or jsonb_typeof(p_config->'sampleCount') is distinct from 'number'
  or (p_config->>'sampleCount')::numeric not between 2 and 4294967295 or trunc((p_config->>'sampleCount')::numeric)<>(p_config->>'sampleCount')::numeric then return false;end if;
 else return false;end if;
 if jsonb_array_length(p_config->'parameters')<1 then return false;end if;
 for x in select * from jsonb_array_elements(p_config->'parameters') loop
  if not private.study_keys(x,array['path','unit','baselineAmount','low','high'])
  or not private.study_text(x->'path',256,'^/instances/[^/]+/exchanges/[^/]+/amount$') or octet_length(x->>'path')>256
  or not private.study_text(x->'unit',256) or octet_length(x->>'unit')>256 or (x->>'path')=any(seen)
  or private.study_advanced_number(x->'low') is null or private.study_advanced_number(x->'high') is null or private.study_advanced_number(x->'baselineAmount') is null then return false;end if;
  low:=(x->>'low')::double precision;high:=(x->>'high')::double precision;base:=(x->>'baselineAmount')::double precision;
  if not (low<high and low<=base and base<=high) or (high-low)='Infinity'::double precision then return false;end if;seen:=seen||(x->>'path');
 end loop;
 if kind='uncertainty' then
  if p_config->'design'->>'kind'='independentUniform' then
   if not private.study_keys(p_config->'design',array['kind','independenceDeclared']) or p_config->'design'->'independenceDeclared' is distinct from 'true'::jsonb then return false;end if;
  elsif p_config->'design'->>'kind'='jointEmpirical' then
   if not private.study_keys(p_config->'design',array['kind','rows']) or jsonb_typeof(p_config->'design'->'rows') is distinct from 'array' then return false;end if;
   if jsonb_array_length(p_config->'design'->'rows')<1 then return false;end if;
   for row in select * from jsonb_array_elements(p_config->'design'->'rows') loop
    if jsonb_typeof(row)<>'array' then return false;end if;
    if jsonb_array_length(row)<>cardinality(seen) then return false;end if;
    n:=0;for v in select * from jsonb_array_elements(row) loop
     if private.study_advanced_number(v) is null then return false;end if;
     x:=p_config->'parameters'->n;
     if (v#>>'{}')::double precision<(x->>'low')::double precision or (v#>>'{}')::double precision>(x->>'high')::double precision then return false;end if;n:=n+1;
    end loop;
   end loop;
  else return false;end if;
 end if;return true;
exception when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value then return false;
end$_$;

ALTER FUNCTION "private"."study_advanced_config_valid"("p_config" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_config_valid"("p_config" "jsonb") FROM PUBLIC;
