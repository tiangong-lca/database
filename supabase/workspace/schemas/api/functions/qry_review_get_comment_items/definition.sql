CREATE OR REPLACE FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text" DEFAULT 'auto'::"text") RETURNS TABLE("review_id" "uuid", "reviewer_id" "uuid", "state_code" integer, "json" "jsonb", "created_at" timestamp with time zone, "modified_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $$
  with visible as materialized (
    select r.*, lower(coalesce(p_scope, 'auto')) as requested_scope,
      private.oauth_client_has_capability('NX-REV-01') as participant_access
    from api.qry_review_get_items(array[p_review_id]) as r
  ), scoped as (
    select r.*, case
      when requested_scope = 'returned' then 'returned'
      when requested_scope = 'opinions' then opinion_scope
      -- Existing participant scopes retain their established projection.
      when participant_access and requested_scope in ('all', 'auto', 'mine', 'self') then 'legacy'
    end as view_scope
    from visible as r
  )
  select c.review_id,
    case when r.view_scope <> 'returned' then c.reviewer_id end,
    c.state_code,
    case when r.view_scope = 'returned' then
      jsonb_build_object('modellingAndValidation', coalesce((
        select jsonb_object_agg(field.key, field.value)
        from jsonb_each(case when jsonb_typeof(c.json::jsonb->'modellingAndValidation') = 'object'
          then c.json::jsonb->'modellingAndValidation' else '{}'::jsonb end) as field
        where field.key in ('validation', 'complianceDeclarations')
      ), '{}'::jsonb))
    else coalesce(c.json::jsonb, '{}'::jsonb) end,
    c.created_at, c.modified_at
  from scoped as r
  join private.comments as c on c.review_id = r.id
  where case r.view_scope
    when 'returned' then r.target_table = 'processes' and r.state_code = -1 and c.state_code = -1
      and (r.json->'user'->>'id' = auth.uid()::text or r.opinion_scope = 'admin'
           or (r.opinion_scope = 'reviewer' and c.reviewer_id = auth.uid()))
    when 'admin' then true
    when 'reviewer' then c.reviewer_id = auth.uid()
    when 'legacy' then (r.opinion_scope = 'admin' or r.json->'user'->>'id' = auth.uid()::text
                        or c.reviewer_id = auth.uid())
      and (r.requested_scope not in ('mine', 'self') or c.reviewer_id = auth.uid())
    else false
  end
  order by c.created_at, c.reviewer_id
$$;

ALTER FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") TO "api_internal_executor";

GRANT ALL ON FUNCTION "api"."qry_review_get_comment_items"("p_review_id" "uuid", "p_scope" "text") TO "authenticated";
