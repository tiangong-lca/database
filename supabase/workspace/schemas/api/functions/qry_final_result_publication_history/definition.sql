CREATE OR REPLACE FUNCTION "api"."qry_final_result_publication_history"("p_limit" integer DEFAULT 20, "p_before_published_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_before_id" "uuid" DEFAULT NULL::"uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare v_items jsonb; v_next jsonb;
begin
  if auth.uid() is null then
    return private.lca_release_error('auth_required',401,'Authentication required');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50
    or ((p_before_id is null) <> (p_before_published_at is null))
    or (p_before_published_at is not null and not isfinite(p_before_published_at)) then
    raise exception using errcode='22023',message='Invalid publication history page';
  end if;
  with entries as materialized (
    select p.id,p.release_version,p.published_at,p.status
    from private.lca_release_publications p
    join private.lca_release_runs r on r.id=p.release_run_id
    join private.final_result_publication_bindings b on b.publication_id=p.id
    where not p.is_current and p.status='superseded'
      and p.publication_series_key='global' and p.publication_channel='public' and p.visibility_scope='public'
      and r.publication_format='final-result-pair.v2'
      and (p_before_id is null or (p.published_at,p.id)<(p_before_published_at,p_before_id))
    order by p.published_at desc,p.id desc limit p_limit+1
  ), page as (select * from entries order by published_at desc,id desc limit p_limit)
  select coalesce((select jsonb_agg(jsonb_build_object(
    'publicationId',id,'releaseVersion',release_version,'publishedAt',published_at,'status',status,
    'formats',(select coalesce(jsonb_agg(fmt order by fmt),'[]'::jsonb) from unnest(array['tidas','ilcd']) fmt
       where api.qry_final_result_download(id,fmt)->>'ok'='true')
  ) order by published_at desc,id desc) from page),'[]'::jsonb),
  case when (select count(*) from entries)>p_limit then
    (select jsonb_build_object('publishedAt',published_at,'publicationId',id) from page order by published_at,id limit 1)
  else null end into v_items,v_next;
  return jsonb_build_object('ok',true,'data',jsonb_build_object('publications',v_items,'nextCursor',v_next));
end;
$$;

ALTER FUNCTION "api"."qry_final_result_publication_history"("p_limit" integer, "p_before_published_at" timestamp with time zone, "p_before_id" "uuid") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_final_result_publication_history"("p_limit" integer, "p_before_published_at" timestamp with time zone, "p_before_id" "uuid") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_final_result_publication_history"("p_limit" integer, "p_before_published_at" timestamp with time zone, "p_before_id" "uuid") TO "authenticated";
