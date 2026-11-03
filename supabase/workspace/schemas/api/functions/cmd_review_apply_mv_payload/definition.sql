CREATE OR REPLACE FUNCTION "api"."cmd_review_apply_mv_payload"("p_table" "text", "p_id" "uuid", "p_version" "text", "p_review_items" "jsonb" DEFAULT '[]'::"jsonb", "p_compliance_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'api', 'private', 'public', 'util', 'extensions', 'pg_temp'
    AS $_$
declare
  v_row jsonb;
  v_doc jsonb;
  v_dataset_path text[];
  v_mv_path text[];
  v_validation_object_path text[];
  v_compliance_object_path text[];
  v_review_path text[];
  v_compliance_path text[];
  v_review_items jsonb := coalesce(p_review_items, '[]'::jsonb);
  v_compliance_items jsonb := coalesce(p_compliance_items, '[]'::jsonb);
begin
  if p_table not in ('processes', 'lifecyclemodels') then
    return api.cmd_review_get_dataset_row(p_table, p_id, p_version, false);
  end if;

  v_review_items := coalesce(private.review_clean_metadata_v1(v_review_items), '[]'::jsonb);
  v_compliance_items := coalesce(private.review_clean_metadata_v1(v_compliance_items), '[]'::jsonb);
  perform private.review_assert_metadata_v1(
    private.review_clean_metadata_v1(jsonb_build_object(
      'validation', jsonb_build_object('review', v_review_items),
      'complianceDeclarations', jsonb_build_object('compliance', v_compliance_items)
    )), p_table
  );
  v_row := api.cmd_review_get_dataset_row(p_table, p_id, p_version, true);

  if v_row is null then
    return null;
  end if;

  if p_table = 'processes' then
    v_dataset_path := array['processDataSet'];
    v_mv_path := array['processDataSet', 'modellingAndValidation'];
    v_validation_object_path := array[
      'processDataSet',
      'modellingAndValidation',
      'validation'
    ];
    v_compliance_object_path := array[
      'processDataSet',
      'modellingAndValidation',
      'complianceDeclarations'
    ];
    v_review_path := array['processDataSet', 'modellingAndValidation', 'validation', 'review'];
    v_compliance_path := array[
      'processDataSet',
      'modellingAndValidation',
      'complianceDeclarations',
      'compliance'
    ];
  else
    v_dataset_path := array['lifeCycleModelDataSet'];
    v_mv_path := array['lifeCycleModelDataSet', 'modellingAndValidation'];
    v_validation_object_path := array[
      'lifeCycleModelDataSet',
      'modellingAndValidation',
      'validation'
    ];
    v_compliance_object_path := array[
      'lifeCycleModelDataSet',
      'modellingAndValidation',
      'complianceDeclarations'
    ];
    v_review_path := array[
      'lifeCycleModelDataSet',
      'modellingAndValidation',
      'validation',
      'review'
    ];
    v_compliance_path := array[
      'lifeCycleModelDataSet',
      'modellingAndValidation',
      'complianceDeclarations',
      'compliance'
    ];
  end if;

  v_doc := coalesce(v_row->'json_ordered', v_row->'json', '{}'::jsonb);
  v_doc := jsonb_set(
    v_doc,
    v_dataset_path,
    case
      when jsonb_typeof(v_doc #> v_dataset_path) = 'object'
        then v_doc #> v_dataset_path
      else '{}'::jsonb
    end,
    true
  );
  v_doc := jsonb_set(
    v_doc,
    v_mv_path,
    case
      when jsonb_typeof(v_doc #> v_mv_path) = 'object'
        then v_doc #> v_mv_path
      else '{}'::jsonb
    end,
    true
  );
  v_doc := jsonb_set(
    v_doc,
    v_validation_object_path,
    case
      when jsonb_typeof(v_doc #> v_validation_object_path) = 'object'
        then v_doc #> v_validation_object_path
      else '{}'::jsonb
    end,
    true
  );
  v_doc := jsonb_set(
    v_doc,
    v_compliance_object_path,
    case
      when jsonb_typeof(v_doc #> v_compliance_object_path) = 'object'
        then v_doc #> v_compliance_object_path
      else '{}'::jsonb
    end,
    true
  );

  if jsonb_array_length(v_review_items) > 0 then
    v_doc := jsonb_set(
      v_doc,
      v_review_path,
      api.cmd_review_json_array(v_doc #> v_review_path) || v_review_items,
      true
    );
  end if;

  if jsonb_array_length(v_compliance_items) > 0 then
    v_doc := jsonb_set(
      v_doc,
      v_compliance_path,
      api.cmd_review_json_array(v_doc #> v_compliance_path) || v_compliance_items,
      true
    );
  end if;

  execute format(
    'update public.%I
        set json_ordered = $1::json,
            json = $1::jsonb,
            modified_at = now()
      where id = $2
        and version = $3',
    p_table
  )
    using v_doc, p_id, p_version;

  return api.cmd_review_get_dataset_row(p_table, p_id, p_version, false);
end;
$_$;

ALTER FUNCTION "api"."cmd_review_apply_mv_payload"("p_table" "text", "p_id" "uuid", "p_version" "text", "p_review_items" "jsonb", "p_compliance_items" "jsonb") OWNER TO "postgres";

REVOKE ALL ON FUNCTION "api"."cmd_review_apply_mv_payload"("p_table" "text", "p_id" "uuid", "p_version" "text", "p_review_items" "jsonb", "p_compliance_items" "jsonb") FROM PUBLIC;

GRANT ALL ON FUNCTION "api"."cmd_review_apply_mv_payload"("p_table" "text", "p_id" "uuid", "p_version" "text", "p_review_items" "jsonb", "p_compliance_items" "jsonb") TO "api_internal_executor";
