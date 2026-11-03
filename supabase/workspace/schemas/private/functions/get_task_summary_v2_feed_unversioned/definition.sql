CREATE OR REPLACE FUNCTION "private"."get_task_summary_v2_feed_unversioned"("p_category" "text" DEFAULT NULL::"text", "p_job_kinds" "text"[] DEFAULT NULL::"text"[], "p_statuses" "text"[] DEFAULT NULL::"text"[], "p_updated_since" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_cursor_updated_at" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_cursor_job_id" "uuid" DEFAULT NULL::"uuid", "p_limit" integer DEFAULT 50, "p_root_only" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'private', 'api', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  a uuid := auth.uid();
  lim integer := greatest(1, least(coalesce(p_limit, 50), 200));
  mgr boolean;
begin
  if a is null then
    return api.lcia_scope_closure_error(
      'auth_required', 401, 'Authentication required'
    );
  end if;
  if (p_cursor_updated_at is null) <> (p_cursor_job_id is null) then
    return api.lcia_scope_closure_error(
      'invalid_task_cursor', 400,
      'Task cursor fields must be supplied together'
    );
  end if;
  mgr := api.lcia_scope_closure_is_manager();

  return jsonb_build_object(
    'ok', true,
    'serverTime', now(),
    'data', coalesce((
      with x as (
        select
          j.*,
          k.task_center_category,
          p.id as package_id,
          coalesce(cd.id, cp.id, ck.id) as closure_id,
          coalesce(cd.status, cp.status, ck.status) as closure_status,
          coalesce(
            cd.certificate_status,
            cp.certificate_status,
            ck.certificate_status
          ) as certificate_status,
          result_set.id as result_set_id,
          result_set.name as result_set_name,
          greatest(
            j.updated_at,
            coalesce(cd.updated_at, '-infinity'::timestamptz),
            coalesce(cp.updated_at, '-infinity'::timestamptz),
            coalesce(ck.updated_at, '-infinity'::timestamptz),
            coalesce(p.updated_at, '-infinity'::timestamptz)
          ) as pu
        from private.worker_jobs j
        join private.worker_job_kinds k on k.job_kind = j.job_kind
        left join private.lcia_scope_closure_checks cd
          on cd.worker_job_id = j.id
        left join private.lcia_result_packages p
          on p.build_worker_job_id = j.id
        left join private.lcia_scope_closure_checks cp
          on cp.id = case
            when (j.payload_json->>'closure_check_id')
              ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
              then (j.payload_json->>'closure_check_id')::uuid
            else null
          end
        left join private.lcia_scope_closure_checks ck
          on ck.id = p.closure_check_id
        left join private.lcia_result_sets result_set
          on result_set.id = coalesce(
            cd.result_set_id,
            cp.result_set_id,
            ck.result_set_id
          )
        where j.job_kind not like 'study.%' and j.requested_by = a
          and (
            j.visibility = 'user'
            or (
              mgr
              and j.visibility = 'operator'
              and j.job_kind = any(array[
                'lcia.scope_closure_check',
                'lcia_result.package_build'
              ])
            )
          )
          and (p_category is null or k.task_center_category = p_category)
          and (p_job_kinds is null or j.job_kind = any(p_job_kinds))
          and (p_statuses is null or j.status = any(p_statuses))
          and (
            p_updated_since is null
            or greatest(
              j.updated_at,
              coalesce(cd.updated_at, '-infinity'::timestamptz),
              coalesce(cp.updated_at, '-infinity'::timestamptz),
              coalesce(ck.updated_at, '-infinity'::timestamptz),
              coalesce(p.updated_at, '-infinity'::timestamptz)
            ) >= p_updated_since
          )
          and (
            not p_root_only
            or j.root_job_id is null
            or j.root_job_id = j.id
          )
      ), pg as (
        select *
        from x
        where p_cursor_updated_at is null
          or (pu, id) < (p_cursor_updated_at, p_cursor_job_id)
        order by pu desc, id desc
        limit lim + 1
      ), sh as (
        select * from pg order by pu desc, id desc limit lim
      )
      select jsonb_build_object(
        'items', coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'jobId', id,
          'jobKind', job_kind,
          'category', task_center_category,
          'requestedBy', requested_by,
          'workerStatus', status,
          'phase', phase,
          'progressFraction', case
            when progress is null then null
            else greatest(0::numeric, least(progress, 1::numeric))
          end,
          'progressCounters', diagnostics->'progressCounters',
          'domainStatus', coalesce(closure_status, result_json->>'status'),
          'domainValidity', certificate_status,
          'projectionUpdatedAt', pu,
          'title', coalesce(result_set_name, payload_json->>'name', job_kind),
          'blockerCodes', blocker_codes,
          'errorSummary', error_code,
          'capabilities', jsonb_build_object(
            'canCancel', status in ('queued', 'running', 'waiting'),
            'canDownloadReport', closure_id is not null
              and closure_status in ('passed', 'blocked'),
            'canOpenWorkbench', task_center_category = 'data_product',
            'canPreviewResult', package_id is not null
          ),
          'deepLink', case
            when package_id is not null then jsonb_build_object(
              'routeKey', 'data_product.package',
              'params', jsonb_strip_nulls(jsonb_build_object(
                'packageId', package_id,
                'closureCheckId', closure_id,
                'resultSetId', result_set_id
              ))
            )
            when closure_id is not null then jsonb_build_object(
              'routeKey', 'data_product.closure_check',
              'params', jsonb_strip_nulls(jsonb_build_object(
                'closureCheckId', closure_id,
                'resultSetId', result_set_id
              ))
            )
          end,
          'closureCheckId', closure_id,
          'resultPackageId', package_id,
          'resultSetId', result_set_id,
          'resultSetName', result_set_name
        )) order by pu desc, id desc), '[]'::jsonb),
        'nextCursor', case
          when exists(select 1 from pg offset lim) then (
            select jsonb_build_object('updatedAt', pu, 'jobId', id)
            from sh
            order by pu asc, id asc
            limit 1
          )
          else null
        end
      )
      from sh
    ), jsonb_build_object('items', '[]'::jsonb, 'nextCursor', null))
  );
end;
$_$;

ALTER FUNCTION "private"."get_task_summary_v2_feed_unversioned"("p_category" "text", "p_job_kinds" "text"[], "p_statuses" "text"[], "p_updated_since" timestamp with time zone, "p_cursor_updated_at" timestamp with time zone, "p_cursor_job_id" "uuid", "p_limit" integer, "p_root_only" boolean) OWNER TO "postgres";

REVOKE ALL ON FUNCTION "private"."get_task_summary_v2_feed_unversioned"("p_category" "text", "p_job_kinds" "text"[], "p_statuses" "text"[], "p_updated_since" timestamp with time zone, "p_cursor_updated_at" timestamp with time zone, "p_cursor_job_id" "uuid", "p_limit" integer, "p_root_only" boolean) FROM PUBLIC;

GRANT ALL ON FUNCTION "private"."get_task_summary_v2_feed_unversioned"("p_category" "text", "p_job_kinds" "text"[], "p_statuses" "text"[], "p_updated_since" timestamp with time zone, "p_cursor_updated_at" timestamp with time zone, "p_cursor_job_id" "uuid", "p_limit" integer, "p_root_only" boolean) TO "api_internal_executor";
