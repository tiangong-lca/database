CREATE OR REPLACE FUNCTION "private"."study_advanced_number"("p_value" "jsonb") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    SET "extra_float_digits" TO '3'
    AS $_$
declare v double precision;t text;negative boolean;digits text;point integer;zero_count integer;exponent integer;result text;
 raw bytea;fraction bigint;binary_exponent integer;i integer;power_value numeric:=1;factor numeric;remaining integer;exact_value numeric;rounded numeric;quantum numeric;scale integer;candidate numeric;best numeric;best_distance numeric;distance numeric;
begin
 if not private.study_text(p_value,64,'^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?(e-?[1-9][0-9]{0,2})?$') then return null;end if;
 v:=(p_value#>>'{}')::double precision;
 if v in ('Infinity'::double precision,'-Infinity'::double precision,'NaN'::double precision) then return null;end if;
 if v=0 then return case when p_value#>>'{}'='0' then '0' end;end if;
 negative:=v<0;raw:=float8send(abs(v));binary_exponent:=((get_byte(raw,0)&127)*16+(get_byte(raw,1)>>4));fraction:=(get_byte(raw,1)&15)::bigint;
 for byte_index in 2..7 loop fraction:=fraction*256+get_byte(raw,byte_index);end loop;
 if binary_exponent=0 then binary_exponent:=-1074;else fraction:=fraction+4503599627370496;binary_exponent:=binary_exponent-1075;end if;
 -- Construct the exact finite binary value as decimal integer/scale. PostgreSQL's
 -- own float8 text chooses different shortest spellings at some boundaries.
 remaining:=abs(binary_exponent);factor:=case when binary_exponent<0 then 5 else 2 end;
 while remaining>0 loop
  if remaining%2=1 then power_value:=power_value*factor;end if;
  remaining:=remaining/2;if remaining>0 then factor:=factor*factor;end if;
 end loop;
 t:=(fraction::numeric*power_value)::text;
 if binary_exponent<0 then
  i:=-binary_exponent;
  if length(t)<=i then t:='0.'||repeat('0',i-length(t))||t;else t:=left(t,length(t)-i)||'.'||right(t,i);end if;
 end if;exact_value:=t::numeric;
 point:=position('.' in t);if point=0 then point:=length(t)+1;end if;
 digits:=replace(t,'.','');zero_count:=length(digits)-length(ltrim(digits,'0'));exponent:=point-zero_count-2;
 -- Binary powers have asymmetric neighboring intervals. At the shortest
 -- decimal precision inspect the nearest coefficient and both adjacent ones;
 -- select only roundtripping candidates by exact distance, then even ties.
 for precision in 1..17 loop
  scale:=precision-1-exponent;rounded:=round(exact_value,scale);quantum:=('1e'||(-scale)::text)::numeric;best:=null;best_distance:=null;
  foreach candidate in array array[rounded,rounded-quantum,rounded+quantum] loop
   if candidate<=0 then continue;end if;
   begin
    if candidate::double precision=abs(v) then
     distance:=abs(candidate-exact_value);
     if best is null or distance<best_distance or (distance=best_distance and mod(candidate*(('1e'||scale::text)::numeric),2)=0 and mod(best*(('1e'||scale::text)::numeric),2)<>0) then
      best:=candidate;best_distance:=distance;
     end if;
    end if;
   exception when numeric_value_out_of_range then null;end;
  end loop;
  if best is not null then rounded:=best;exit;end if;
 end loop;
 if best is null then return null;end if;
 t:=rounded::text;point:=position('.' in t);if point=0 then point:=length(t)+1;end if;
 digits:=replace(t,'.','');zero_count:=length(digits)-length(ltrim(digits,'0'));digits:=rtrim(ltrim(digits,'0'),'0');exponent:=point-zero_count-2;
 if exponent between -5 and 15 then result:=case when position('.' in t)>0 then rtrim(rtrim(t,'0'),'.') else t end;
 else result:=left(digits,1)||case when length(digits)>1 then '.'||substr(digits,2) else '' end||'e'||exponent::text;end if;
 if negative then result:='-'||result;end if;return case when result=p_value#>>'{}' then result end;
exception when invalid_text_representation or numeric_value_out_of_range then return null;
end$_$;

ALTER FUNCTION "private"."study_advanced_number"("p_value" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."study_advanced_number"("p_value" "jsonb") FROM PUBLIC;
