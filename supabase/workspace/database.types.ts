export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  api: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      worker_job_domain_refs: {
        Row: {
          created_at: string | null
          domain_id: string | null
          domain_role: string | null
          domain_source: string | null
          legacy_job_id: string | null
          status: string | null
          updated_at: string | null
          worker_job_id: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      _search_simple_dataset_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          p_table: unknown
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      assert_lca_release_manager: { Args: never; Returns: Json }
      cmd_dataset_alias_execution_admit_guarded: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_dataset_alias_execution_admit_v2_guarded: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_dataset_alias_execution_execute_v2: {
        Args: { p_nonce: string; p_request_id: string }
        Returns: Json
      }
      cmd_dataset_alias_execution_gate_guarded: {
        Args: {
          p_gate_name: string
          p_preflight_token: string
          p_request_id: string
        }
        Returns: Json
      }
      cmd_dataset_alias_execution_gate_v2_guarded: {
        Args: {
          p_gate_name: string
          p_preflight_token: string
          p_request_id: string
        }
        Returns: Json
      }
      cmd_dataset_alias_execution_preflight_guarded: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_dataset_alias_execution_preflight_v2_guarded: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_dataset_alias_execution_read: {
        Args: { p_request_id: string }
        Returns: Json
      }
      cmd_dataset_alias_execution_read_v2: {
        Args: { p_request_id: string }
        Returns: Json
      }
      cmd_dataset_assign_team: {
        Args: {
          p_audit?: Json
          p_id: string
          p_table: string
          p_team_id: string
          p_version: string
        }
        Returns: Json
      }
      cmd_dataset_create: {
        Args: {
          p_audit?: Json
          p_id: string
          p_json_ordered: Json
          p_model_id?: string
          p_model_version?: string
          p_rule_verification?: boolean
          p_table: string
        }
        Returns: Json
      }
      cmd_dataset_create_version: {
        Args: {
          p_audit?: Json
          p_id: string
          p_json_ordered: Json
          p_model_id?: string
          p_model_version?: string
          p_rule_verification?: boolean
          p_source_version: string
          p_table: string
        }
        Returns: Json
      }
      cmd_dataset_delete: {
        Args: {
          p_audit?: Json
          p_id: string
          p_table: string
          p_version: string
        }
        Returns: Json
      }
      cmd_dataset_derivative_rebuild_plan_guarded: {
        Args: { p_plan: Json }
        Returns: Json
      }
      cmd_dataset_derivative_rebuild_read: {
        Args: { p_request_id: string }
        Returns: Json
      }
      cmd_dataset_derivative_rebuild_snapshot: {
        Args: { p_id: string; p_table: string; p_version: string }
        Returns: Json
      }
      cmd_dataset_extraction_ack: {
        Args: { p_msg_ids: number[] }
        Returns: Json
      }
      cmd_dataset_extraction_claim: {
        Args: {
          p_max_read_count?: number
          p_qty?: number
          p_vt_seconds?: number
        }
        Returns: Json
      }
      cmd_dataset_extraction_record_failure: {
        Args: {
          p_delete?: boolean
          p_last_error?: string
          p_message: Json
          p_msg_id: number
          p_read_count: number
          p_reason: string
        }
        Returns: Json
      }
      cmd_dataset_flow_identity_capture_attest_guarded: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_dataset_flow_identity_process_rewrite_guarded: {
        Args: { p_authorization: Json; p_request: Json; p_scope_id: string }
        Returns: Json
      }
      cmd_dataset_flow_identity_scope_cancel_guarded: {
        Args: { p_request: Json; p_scope_id: string }
        Returns: Json
      }
      cmd_dataset_flow_identity_scope_finalize_guarded: {
        Args: { p_authorization: Json; p_request: Json; p_scope_id: string }
        Returns: Json
      }
      cmd_dataset_flow_identity_scope_lookup: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_dataset_flow_identity_scope_preflight_guarded: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_dataset_flow_identity_scope_read: {
        Args: { p_scope_id: string }
        Returns: Json
      }
      cmd_dataset_flow_identity_scope_recover_guarded: {
        Args: { p_request: Json; p_scope_id: string }
        Returns: Json
      }
      cmd_dataset_publish: {
        Args: {
          p_audit?: Json
          p_id: string
          p_table: string
          p_version: string
        }
        Returns: Json
      }
      cmd_dataset_save_draft: {
        Args: {
          p_audit?: Json
          p_id: string
          p_json_ordered: Json
          p_model_id?: string
          p_model_version?: string
          p_rule_verification?: boolean
          p_table: string
          p_version: string
        }
        Returns: Json
      }
      cmd_dataset_save_draft_guarded: {
        Args: {
          p_audit?: Json
          p_expected_json_ordered: Json
          p_id: string
          p_json_ordered: Json
          p_model_id?: string
          p_model_version?: string
          p_rule_verification?: boolean
          p_table: string
          p_version: string
        }
        Returns: Json
      }
      cmd_dataset_withdraw: {
        Args: {
          p_audit?: Json
          p_id: string
          p_reason: string
          p_table: string
          p_version: string
        }
        Returns: Json
      }
      cmd_lca_release_approve: {
        Args: {
          p_audit?: Json
          p_expires_at?: string
          p_publish_plan_hash: string
          p_reason?: string
          p_release_run_id: string
        }
        Returns: Json
      }
      cmd_lca_release_prepare: {
        Args: {
          p_audit?: Json
          p_calculation_bundle_hash: string
          p_calculation_bundle_ref: Json
          p_idempotency_key: string
          p_input_manifest_hash: string
          p_profile_lock_hash: string
          p_publish_plan: Json
          p_publish_plan_hash: string
          p_release_run_id: string
          p_release_version: string
          p_selection_manifest_hash: string
        }
        Returns: Json
      }
      cmd_lca_release_publish: {
        Args: {
          p_approval_hash: string
          p_approval_id: string
          p_audit?: Json
          p_credential_fingerprint: string
          p_idempotency_key: string
          p_publish_plan_hash: string
          p_reason?: string
          p_release_run_id: string
        }
        Returns: Json
      }
      cmd_lca_release_readback_verify: {
        Args: {
          p_artifact_hashes: Json
          p_audit?: Json
          p_release_manifest_hash: string
          p_release_run_id: string
        }
        Returns: Json
      }
      cmd_lca_release_unpublish: {
        Args: { p_audit?: Json; p_publication_id: string; p_reason: string }
        Returns: Json
      }
      cmd_lcia_result_build_request: {
        Args: {
          p_audit?: Json
          p_coverage_mode?: string
          p_default_impact_category?: string
          p_idempotency_key?: string
          p_lcia_method_set?: Json
          p_name: string
          p_processes?: Json
        }
        Returns: Json
      }
      cmd_lcia_result_build_request_v2: {
        Args: {
          p_audit?: Json
          p_closure_check_id: string
          p_coverage_mode: string
          p_default_impact_category: string
          p_idempotency_key: string
          p_lcia_method_set: Json
          p_name: string
          p_policy_fingerprint: string
          p_processes: Json
          p_requested_scope_hash: string
        }
        Returns: Json
      }
      cmd_lcia_result_build_request_v3: {
        Args: {
          p_audit?: Json
          p_closure_check_id: string
          p_coverage_mode: string
          p_default_impact_category: string
          p_idempotency_key: string
          p_lcia_method_set: Json
          p_name: string
          p_policy_fingerprint: string
          p_processes: Json
          p_requested_scope_hash: string
        }
        Returns: Json
      }
      cmd_lcia_result_package_publish: {
        Args: {
          p_audit?: Json
          p_display_default_impact_category?: string
          p_package_id: string
          p_reason?: string
        }
        Returns: Json
      }
      cmd_lcia_result_publication_unpublish: {
        Args: { p_audit?: Json; p_publication_id: string; p_reason?: string }
        Returns: Json
      }
      cmd_lcia_result_set_create: { Args: { p_name: string }; Returns: Json }
      cmd_lcia_scope_closure_check_request_v2: {
        Args: {
          p_audit?: Json
          p_request_idempotency_token: string
          p_requested_scope: Json
        }
        Returns: Json
      }
      cmd_lcia_scope_closure_check_request_v3: {
        Args: {
          p_audit?: Json
          p_request_idempotency_token: string
          p_requested_scope: Json
          p_result_set_id: string
        }
        Returns: Json
      }
      cmd_lifecycle_model_bundle_delete: {
        Args: { p_model_id: string; p_version: string }
        Returns: Json
      }
      cmd_lifecycle_model_bundle_save: { Args: { p_plan: Json }; Returns: Json }
      cmd_membership_is_review_admin: {
        Args: { p_actor?: string }
        Returns: boolean
      }
      cmd_membership_is_system_manager: {
        Args: { p_actor?: string }
        Returns: boolean
      }
      cmd_membership_is_system_owner: {
        Args: { p_actor?: string }
        Returns: boolean
      }
      cmd_membership_is_team_manager: {
        Args: { p_actor: string; p_team_id: string }
        Returns: boolean
      }
      cmd_membership_is_team_owner: {
        Args: { p_actor: string; p_team_id: string }
        Returns: boolean
      }
      cmd_membership_resolve_member_order_by: {
        Args: { p_allow_workload?: boolean; p_sort_by: string }
        Returns: string
      }
      cmd_membership_resolve_sort_direction: {
        Args: { p_sort_order: string }
        Returns: string
      }
      cmd_notification_normalize_text_array: {
        Args: { p_values: string[] }
        Returns: string[]
      }
      cmd_notification_send_validation_issue: {
        Args: {
          p_audit?: Json
          p_dataset_id: string
          p_dataset_type: string
          p_dataset_version: string
          p_issue_codes?: string[]
          p_issue_count?: number
          p_link?: string
          p_recipient_user_id: string
          p_tab_names?: string[]
        }
        Returns: Json
      }
      cmd_open_data_process_publish_batch: {
        Args: { p_items: Json }
        Returns: Json
      }
      cmd_portal_lcia_projection_finalize_publication_v1: {
        Args: {
          p_audit?: Json
          p_idempotency_key: string
          p_lcia_result_publication_id: string
          p_package_result_hash: string
          p_package_version: string
          p_projection_content_hash: string
          p_projection_id: string
        }
        Returns: Json
      }
      cmd_portal_lcia_projection_revoke_publication_v1: {
        Args: {
          p_audit?: Json
          p_lcia_result_publication_id: string
          p_projection_content_hash: string
          p_reason: string
        }
        Returns: Json
      }
      cmd_portal_lcia_result_package_publish_v1: {
        Args: {
          p_audit?: Json
          p_display_default_impact_category: string
          p_expected_publish_plan_hash: string
          p_package_id: string
          p_reason?: string
        }
        Returns: Json
      }
      cmd_result_process_publish_v1: {
        Args: { p_request: Json }
        Returns: Json
      }
      cmd_review_append_log: {
        Args: {
          p_action: string
          p_actor: string
          p_extra?: Json
          p_review_json: Json
        }
        Returns: Json
      }
      cmd_review_append_review_ref: {
        Args: { p_existing_reviews: Json; p_review_id: string }
        Returns: Json
      }
      cmd_review_apply_model_validation_to_process_json: {
        Args: {
          p_comment_compliance?: Json
          p_comment_review?: Json
          p_model_json: Json
          p_process_json: Json
        }
        Returns: Json
      }
      cmd_review_apply_mv_payload: {
        Args: {
          p_compliance_items?: Json
          p_id: string
          p_review_items?: Json
          p_table: string
          p_version: string
        }
        Returns: Json
      }
      cmd_review_approve: {
        Args: { p_audit?: Json; p_review_id: string; p_table: string }
        Returns: Json
      }
      cmd_review_assign_reviewers: {
        Args: {
          p_audit?: Json
          p_deadline?: string
          p_review_id: string
          p_reviewer_ids: Json
        }
        Returns: Json
      }
      cmd_review_change_member_role: {
        Args: {
          p_action?: string
          p_audit?: Json
          p_role?: string
          p_user_id: string
        }
        Returns: Json
      }
      cmd_review_collect_dataset_targets: {
        Args: { p_lock?: boolean; p_roots: Json }
        Returns: {
          dataset_id: string
          dataset_row: Json
          dataset_version: string
          is_root: boolean
          reviews: Json
          state_code: number
          table_name: string
        }[]
      }
      cmd_review_contact_activate: {
        Args: {
          p_audit?: Json
          p_bind?: boolean
          p_expected_contact?: Json
          p_id: string
          p_json_ordered: Json
          p_mode: string
          p_operation_id: string
          p_source_version?: string
        }
        Returns: Json
      }
      cmd_review_extract_refs: {
        Args: { p_json: Json }
        Returns: {
          ref_object_id: string
          ref_type: string
          ref_version: string
        }[]
      }
      cmd_review_finalize_approve: {
        Args: { p_audit?: Json; p_review_id: string }
        Returns: Json
      }
      cmd_review_finalize_reject: {
        Args: { p_audit?: Json; p_reason: string; p_review_id: string }
        Returns: Json
      }
      cmd_review_get_actor_meta: { Args: { p_actor: string }; Returns: Json }
      cmd_review_get_dataset_name: {
        Args: { p_row: Json; p_table: string }
        Returns: Json
      }
      cmd_review_get_dataset_row: {
        Args: {
          p_id: string
          p_lock?: boolean
          p_table: string
          p_version: string
        }
        Returns: Json
      }
      cmd_review_get_root_table: {
        Args: { p_data_id: string; p_data_version: string; p_review_json: Json }
        Returns: string
      }
      cmd_review_is_review_admin: {
        Args: { p_actor?: string }
        Returns: boolean
      }
      cmd_review_is_review_member: {
        Args: { p_actor?: string }
        Returns: boolean
      }
      cmd_review_json_array: { Args: { p_value: Json }; Returns: Json }
      cmd_review_merge_compliance_declarations: {
        Args: { p_additions: Json; p_existing: Json }
        Returns: Json
      }
      cmd_review_merge_json_collection: {
        Args: { p_additions: Json; p_existing: Json }
        Returns: Json
      }
      cmd_review_merge_validation: {
        Args: { p_additions: Json; p_existing: Json }
        Returns: Json
      }
      cmd_review_normalize_reviewer_ids: {
        Args: { p_reviewer_ids: Json }
        Returns: Json
      }
      cmd_review_quality_diagnostic_start: { Args: never; Returns: Json }
      cmd_review_ref_type_to_table: {
        Args: { p_ref_type: string }
        Returns: string
      }
      cmd_review_reject: {
        Args: {
          p_audit?: Json
          p_reason: string
          p_review_id: string
          p_table: string
        }
        Returns: Json
      }
      cmd_review_resolve_queue_order_by: {
        Args: { p_allow_comment_modified?: boolean; p_sort_by: string }
        Returns: string
      }
      cmd_review_revoke_reviewer: {
        Args: { p_audit?: Json; p_review_id: string; p_reviewer_id: string }
        Returns: Json
      }
      cmd_review_save_assignment_draft: {
        Args: { p_audit?: Json; p_review_id: string; p_reviewer_ids: Json }
        Returns: Json
      }
      cmd_review_save_comment_draft: {
        Args: { p_audit?: Json; p_json: Json; p_review_id: string }
        Returns: Json
      }
      cmd_review_submit: {
        Args: {
          p_audit?: Json
          p_target_id: string
          p_target_table: string
          p_target_version: string
        }
        Returns: Json
      }
      cmd_review_submit_comment:
        | {
            Args: { p_audit?: Json; p_json: Json; p_review_id: string }
            Returns: Json
          }
        | {
            Args: {
              p_audit?: Json
              p_comment_state?: number
              p_json: Json
              p_review_id: string
            }
            Returns: Json
          }
      cmd_reviewer_submit_decision: {
        Args: {
          p_audit?: Json
          p_decision: string
          p_reason?: string
          p_review_id: string
        }
        Returns: Json
      }
      cmd_simple_review_submit_decision: {
        Args: {
          p_audit?: Json
          p_decision: string
          p_reason?: string
          p_review_id: string
        }
        Returns: Json
      }
      cmd_system_change_member_role: {
        Args: {
          p_action?: string
          p_audit?: Json
          p_role?: string
          p_user_id: string
        }
        Returns: Json
      }
      cmd_team_accept_invitation: {
        Args: { p_audit?: Json; p_team_id: string }
        Returns: Json
      }
      cmd_team_change_member_role: {
        Args: {
          p_action?: string
          p_audit?: Json
          p_role?: string
          p_team_id: string
          p_user_id: string
        }
        Returns: Json
      }
      cmd_team_create: {
        Args: {
          p_audit?: Json
          p_is_public: boolean
          p_json: Json
          p_rank: number
          p_team_id: string
        }
        Returns: Json
      }
      cmd_team_reinvite_member: {
        Args: { p_audit?: Json; p_team_id: string; p_user_id: string }
        Returns: Json
      }
      cmd_team_reject_invitation: {
        Args: { p_audit?: Json; p_team_id: string }
        Returns: Json
      }
      cmd_team_set_rank: {
        Args: { p_audit?: Json; p_rank: number; p_team_id: string }
        Returns: Json
      }
      cmd_team_update_profile: {
        Args: {
          p_audit?: Json
          p_is_public: boolean
          p_json: Json
          p_team_id: string
        }
        Returns: Json
      }
      cmd_user_update_contact: {
        Args: { p_audit?: Json; p_contact: Json; p_user_id: string }
        Returns: Json
      }
      contacts_embedding_ft_input: {
        Args: { proc: Database["public"]["Tables"]["contacts"]["Row"] }
        Returns: string
      }
      flowproperties_embedding_ft_input: {
        Args: { proc: Database["public"]["Tables"]["flowproperties"]["Row"] }
        Returns: string
      }
      flows_embedding_ft_input: {
        Args: { proc: Database["public"]["Tables"]["flows"]["Row"] }
        Returns: string
      }
      get_current_lca_release: { Args: never; Returns: Json }
      get_current_lca_release_process: {
        Args: { p_process_uuid: string; p_process_version: string }
        Returns: Json
      }
      get_latest_contact_versions: {
        Args: {
          data_source?: string
          page_current?: number
          page_size?: number
          sort_by?: string
          sort_direction?: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      get_latest_flow_versions: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          sort_by?: string
          sort_direction?: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      get_latest_flowproperty_versions: {
        Args: {
          data_source?: string
          page_current?: number
          page_size?: number
          sort_by?: string
          sort_direction?: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      get_latest_lifecyclemodel_versions: {
        Args: {
          data_source?: string
          page_current?: number
          page_size?: number
          sort_by?: string
          sort_direction?: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      get_latest_process_versions: {
        Args: {
          data_source?: string
          page_current?: number
          page_size?: number
          sort_by?: string
          sort_direction?: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
          type_of_data_set_filter?: string
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      get_latest_source_versions: {
        Args: {
          data_source?: string
          page_current?: number
          page_size?: number
          sort_by?: string
          sort_direction?: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      get_latest_unitgroup_versions: {
        Args: {
          data_source?: string
          page_current?: number
          page_size?: number
          sort_by?: string
          sort_direction?: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      get_lca_release_artifact_download: {
        Args: { p_artifact_id: string }
        Returns: Json
      }
      get_lca_release_run: { Args: { p_release_run_id: string }; Returns: Json }
      get_lcia_result_calculation_bundle: {
        Args: { p_package_id: string }
        Returns: Json
      }
      get_lcia_result_package_preview: {
        Args: { p_package_id: string }
        Returns: Json
      }
      get_lcia_result_set: { Args: { p_result_set_id: string }; Returns: Json }
      get_lcia_scope_closure_check: {
        Args: { p_closure_check_id: string }
        Returns: Json
      }
      get_lcia_scope_closure_report_download:
        | { Args: { p_closure_check_id: string }; Returns: Json }
        | {
            Args: { p_artifact_role: string; p_closure_check_id: string }
            Returns: Json
          }
      get_published_lcia_result_package: {
        Args: {
          p_impact_category_id?: string
          p_process_id: string
          p_process_version: string
        }
        Returns: Json
      }
      get_task_summary_v2_feed: {
        Args: {
          p_category?: string
          p_cursor_job_id?: string
          p_cursor_updated_at?: string
          p_job_kinds?: string[]
          p_limit?: number
          p_root_only?: boolean
          p_statuses?: string[]
          p_updated_since?: string
        }
        Returns: Json
      }
      hybrid_search_contacts: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_contacts_v2: {
        Args: {
          data_source?: string
          filter_condition?: string
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_flow_versions_v1: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_flow_versions_v2: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          semantic_candidate_population: number
          semantic_fallback_used: boolean
          semantic_route: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_flowproperties: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_flowproperties_v2: {
        Args: {
          data_source?: string
          filter_condition?: string
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_flows: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_flows_v2: {
        Args: {
          data_source?: string
          filter_condition?: string
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_lifecyclemodels: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_lifecyclemodels_v2: {
        Args: {
          data_source?: string
          filter_condition?: string
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_open_data_catalog: {
        Args: {
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          p_dataset_kind: string
          page_current?: number
          page_size?: number
          publication_filter?: string
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          source_filter?: string
        }
        Returns: {
          id: string
          is_published: boolean
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_process_versions_v1: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_process_versions_v2: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
          type_of_data_set_filter?: string
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          semantic_candidate_population: number
          semantic_fallback_used: boolean
          semantic_route: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_processes: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_processes_v2: {
        Args: {
          data_source?: string
          filter_condition?: string
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_sources: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_sources_v2: {
        Args: {
          data_source?: string
          filter_condition?: string
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_unitgroups: {
        Args: {
          data_source?: string
          filter_condition?: Json
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      hybrid_search_unitgroups_v2: {
        Args: {
          data_source?: string
          filter_condition?: string
          lexical_weight?: number
          match_count?: number
          match_threshold?: number
          page_current?: number
          page_size?: number
          query_embedding: string
          query_terms?: string[]
          query_text: string
          rrf_k?: number
          semantic_weight?: number
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      ilcd_classification_get: {
        Args: {
          category_type: string
          get_values: string[]
          this_file_name: string
        }
        Returns: Json[]
      }
      ilcd_flow_categorization_get: {
        Args: { get_values: string[]; this_file_name: string }
        Returns: Json[]
      }
      ilcd_location_get: {
        Args: { get_values: string[]; this_file_name: string }
        Returns: Json[]
      }
      lcia_result_current_eligible_manifest: { Args: never; Returns: Json }
      lcia_result_error: {
        Args: { p_code: string; p_message: string; p_status: number }
        Returns: Json
      }
      lcia_result_is_manager: { Args: never; Returns: boolean }
      lcia_result_is_service_request: { Args: never; Returns: boolean }
      lcia_scope_closure_error: {
        Args: { p_code: string; p_message: string; p_status: number }
        Returns: Json
      }
      lcia_scope_closure_is_manager: { Args: never; Returns: boolean }
      lifecyclemodels_embedding_ft_input: {
        Args: { proc: Database["public"]["Tables"]["lifecyclemodels"]["Row"] }
        Returns: string
      }
      list_lcia_result_sets: { Args: { p_limit?: number }; Returns: Json }
      list_lcia_scope_closure_issues: {
        Args: {
          p_after_issue_id?: string
          p_closure_check_id: string
          p_limit?: number
        }
        Returns: Json
      }
      oauth_client_pre_request: { Args: never; Returns: undefined }
      pgroonga_search_contacts: {
        Args: {
          data_source?: string
          filter_condition?: string
          page_current?: number
          page_size?: number
          query_text: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_contacts_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_flowproperties: {
        Args: {
          data_source?: string
          filter_condition?: string
          page_current?: number
          page_size?: number
          query_text: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_flowproperties_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_flows_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          order_by?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_flows_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          order_by?: string
          page_current?: number
          page_size?: number
          query_text: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_lifecyclemodels_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          order_by?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_lifecyclemodels_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          order_by?: string
          page_current?: number
          page_size?: number
          query_text: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_processes_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          order_by?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
          type_of_data_set_filter?: string
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_processes_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          order_by?: string
          page_current?: number
          page_size?: number
          query_text: string
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_sources: {
        Args: {
          data_source?: string
          filter_condition?: string
          page_current?: number
          page_size?: number
          query_text: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_sources_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_unitgroups: {
        Args: {
          data_source?: string
          filter_condition?: string
          page_current?: number
          page_size?: number
          query_text: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      pgroonga_search_unitgroups_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      policy_is_current_user_in_roles: {
        Args: { p_roles_to_check: string[]; p_team_id: string }
        Returns: boolean
      }
      policy_is_team_id_used: { Args: { _team_id: string }; Returns: boolean }
      policy_is_team_public: { Args: { _team_id: string }; Returns: boolean }
      policy_review_can_read: {
        Args: { p_actor?: string; p_review_id: string }
        Returns: boolean
      }
      policy_roles_delete: {
        Args: { _role: string; _team_id: string; _user_id: string }
        Returns: boolean
      }
      policy_roles_insert: {
        Args: { _role: string; _team_id: string; _user_id: string }
        Returns: boolean
      }
      policy_roles_select: {
        Args: { _role: string; _team_id: string }
        Returns: boolean
      }
      policy_roles_update: {
        Args: { _role: string; _team_id: string; _user_id: string }
        Returns: boolean
      }
      policy_user_has_team: { Args: { _user_id: string }; Returns: boolean }
      portal_catalog_summary_v1: { Args: never; Returns: Json }
      portal_facets_v1: {
        Args: { p_filters?: Json; p_kind: string; p_query: string }
        Returns: Json
      }
      portal_facets_v2: {
        Args: { p_filters?: Json; p_kind: string; p_query: string }
        Returns: Json
      }
      portal_facets_v3: {
        Args: { p_filters?: Json; p_kind: string; p_query: string }
        Returns: Json
      }
      portal_get_dataset_v1: {
        Args: { p_id: string; p_kind: string; p_version: string }
        Returns: Json
      }
      portal_get_published_lcia_values_v1: {
        Args: {
          p_cursor: string
          p_impact_ref: string
          p_limit: number
          p_mode: string
          p_process_refs: Json
        }
        Returns: Json
      }
      portal_hybrid_search_v1: {
        Args: {
          p_filters: Json
          p_kind: string
          p_limit: number
          p_query_embedding: string
          p_query_terms: string[]
        }
        Returns: Json
      }
      portal_hybrid_search_v2: {
        Args: {
          p_cursor?: string
          p_filters: Json
          p_kind: string
          p_limit: number
          p_query_embedding: string
          p_query_terms: string[]
        }
        Returns: Json
      }
      portal_list_process_exchanges_v1: {
        Args: {
          p_cursor?: string
          p_exchange_kind?: string
          p_limit?: number
          p_process_id: string
          p_process_version: string
        }
        Returns: Json
      }
      portal_list_versions_v1: {
        Args: {
          p_cursor?: string
          p_id: string
          p_kind: string
          p_limit?: number
        }
        Returns: Json
      }
      portal_navigation_v1: {
        Args: {
          p_cursor?: string
          p_dimension?: string
          p_filters?: Json
          p_kind: string
          p_limit?: number
          p_parent_node_id?: string
          p_query?: string
        }
        Returns: Json
      }
      portal_search_flows_v1: {
        Args: {
          p_cursor?: string
          p_filters?: Json
          p_limit?: number
          p_query: string
          p_sort?: string
        }
        Returns: Json
      }
      portal_search_flows_v2: {
        Args: {
          p_cursor?: string
          p_filters?: Json
          p_limit?: number
          p_query: string
          p_sort?: string
        }
        Returns: Json
      }
      portal_search_flows_v3: {
        Args: {
          p_cursor?: string
          p_filters?: Json
          p_limit?: number
          p_query: string
          p_sort?: string
        }
        Returns: Json
      }
      portal_search_processes_v1: {
        Args: {
          p_cursor?: string
          p_filters?: Json
          p_limit?: number
          p_query: string
          p_sort?: string
        }
        Returns: Json
      }
      portal_search_processes_v2: {
        Args: {
          p_cursor?: string
          p_filters?: Json
          p_limit?: number
          p_query: string
          p_sort?: string
        }
        Returns: Json
      }
      portal_search_processes_v3: {
        Args: {
          p_cursor?: string
          p_filters?: Json
          p_limit?: number
          p_query: string
          p_sort?: string
        }
        Returns: Json
      }
      portal_sitemap_entries_v1: {
        Args: { p_cursor?: string; p_kind: string; p_limit?: number }
        Returns: Json
      }
      portal_sitemap_manifest_v1: { Args: never; Returns: Json }
      portal_sitemap_shard_v1: {
        Args: { p_shard_cursor: string }
        Returns: Json
      }
      processes_embedding_ft_input: {
        Args: { proc: Database["public"]["Tables"]["processes"]["Row"] }
        Returns: string
      }
      qry_identity_get_mine: {
        Args: never
        Returns: {
          contact: Json
          display_name: string
          email: string
          id: string
        }[]
      }
      qry_identity_get_visible_users: {
        Args: { p_user_ids: string[] }
        Returns: {
          display_name: string
          email: string
          id: string
        }[]
      }
      qry_membership_get_mine: {
        Args: never
        Returns: {
          created_at: string
          modified_at: string
          role: string
          team_id: string
          user_id: string
        }[]
      }
      qry_national_carbon_organization_contributions: {
        Args: { p_limit?: number }
        Returns: Json
      }
      qry_notification_get_my_data_count: {
        Args: { p_days?: number; p_last_view_at?: string }
        Returns: number
      }
      qry_notification_get_my_data_items: {
        Args: { p_days?: number; p_page?: number; p_page_size?: number }
        Returns: {
          id: string
          json: Json
          modified_at: string
          state_code: number
          total_count: number
        }[]
      }
      qry_notification_get_my_issue_count: {
        Args: { p_days?: number; p_last_view_at?: string }
        Returns: number
      }
      qry_notification_get_my_issue_items: {
        Args: { p_days?: number; p_page?: number; p_page_size?: number }
        Returns: {
          dataset_id: string
          dataset_type: string
          dataset_version: string
          id: string
          json: Json
          modified_at: string
          total_count: number
          type: string
        }[]
      }
      qry_notification_get_my_team_count: {
        Args: { p_days?: number; p_last_view_at?: string }
        Returns: number
      }
      qry_notification_get_my_team_items: {
        Args: { p_days?: number }
        Returns: {
          modified_at: string
          role: string
          team_id: string
          team_title: Json
          user_id: string
        }[]
      }
      qry_portal_lcia_projection_prepare_v1: {
        Args: { p_lcia_result_publication_id: string; p_package_id: string }
        Returns: Json
      }
      qry_portal_lcia_projection_publication_readback_v1: {
        Args: {
          p_lcia_result_publication_id: string
          p_projection_content_hash: string
        }
        Returns: Json
      }
      qry_portal_lcia_result_package_publish_prepare_v1: {
        Args: {
          p_display_default_impact_category?: string
          p_package_id: string
        }
        Returns: Json
      }
      qry_reference_review_impacted_roots: {
        Args: { p_include_history?: boolean; p_reference_review_id: string }
        Returns: {
          data_id: string
          data_version: string
          is_current: boolean
          root_review_id: string
          state_code: number
          target_table: string
        }[]
      }
      qry_result_process_publication_readback_v1: {
        Args: { p_request: Json }
        Returns: Json
      }
      qry_result_process_publish_prepare_v1: {
        Args: { p_request: Json }
        Returns: Json
      }
      qry_review_admin_queue_items_v2: {
        Args: { p_page?: number; p_page_size?: number; p_status?: string }
        Returns: {
          completed_reviewer_count: number
          data_id: string
          data_version: string
          deadline: string
          id: string
          modified_at: string
          reference_count: number
          review_kind: string
          reviewer_id: Json
          state_code: number
          submitted_revision_checksum: string
          target_owner_id: string
          target_table: string
          target_team_id: string
          total_count: number
        }[]
      }
      qry_review_batch_eligibility_v1: {
        Args: { p_operation: string; p_review_ids: string[] }
        Returns: {
          approve_opinion_count: number
          data_version: string
          eligible: boolean
          ordinal: number
          reason_code: string
          reject_opinion_count: number
          review_id: string
          reviewer_count: number
          state_code: number
          submitted_opinion_count: number
          target_table: string
        }[]
      }
      qry_review_find_member_candidate_by_email: {
        Args: { p_email: string }
        Returns: {
          contact: Json
          display_name: string
          email: string
          id: string
        }[]
      }
      qry_review_get_admin_queue_items: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
        }
        Returns: {
          comment_state_codes: Json
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          reviewer_id: Json
          state_code: number
          total_count: number
        }[]
      }
      qry_review_get_admin_queue_items_v3: {
        Args: {
          p_display_mode?: string
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
          p_target_table?: string
        }
        Returns: {
          comment_state_codes: Json
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          review_kind: string
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          state_code: number
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_admin_queue_items_v4: {
        Args: {
          p_display_mode?: string
          p_page?: number
          p_page_size?: number
          p_query?: string
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
          p_target_table?: string
        }
        Returns: {
          comment_state_codes: Json
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          review_kind: string
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          state_code: number
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_admin_queue_items_v5: {
        Args: {
          p_display_mode?: string
          p_page?: number
          p_page_size?: number
          p_query?: string
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
          p_target_table?: string
        }
        Returns: {
          approve_opinion_count: number
          comment_state_codes: Json
          completed_reviewer_count: number
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          reject_opinion_count: number
          review_kind: string
          reviewer_count: number
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          state_code: number
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_admin_root_queue_items_v2: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
        }
        Returns: {
          comment_state_codes: Json
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          review_kind: string
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          state_code: number
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_comment_items: {
        Args: { p_review_id: string; p_scope?: string }
        Returns: {
          created_at: string
          json: Json
          modified_at: string
          review_id: string
          reviewer_id: string
          state_code: number
        }[]
      }
      qry_review_get_items: {
        Args: {
          p_data_id?: string
          p_data_version?: string
          p_review_ids?: string[]
          p_state_codes?: number[]
        }
        Returns: {
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          reviewer_id: Json
          state_code: number
        }[]
      }
      qry_review_get_member_list: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_role?: string
          p_sort_by?: string
          p_sort_order?: string
        }
        Returns: {
          created_at: string
          display_name: string
          email: string
          modified_at: string
          role: string
          team_id: string
          total_count: number
          user_id: string
        }[]
      }
      qry_review_get_member_queue_items: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
        }
        Returns: {
          comment_created_at: string
          comment_json: Json
          comment_modified_at: string
          comment_state_code: number
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          review_state_code: number
          reviewer_id: Json
          total_count: number
        }[]
      }
      qry_review_get_member_queue_items_v3: {
        Args: {
          p_display_mode?: string
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
          p_target_table?: string
        }
        Returns: {
          comment_created_at: string
          comment_json: Json
          comment_modified_at: string
          comment_state_code: number
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          review_kind: string
          review_state_code: number
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_member_queue_items_v4: {
        Args: {
          p_display_mode?: string
          p_page?: number
          p_page_size?: number
          p_query?: string
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
          p_target_table?: string
        }
        Returns: {
          comment_created_at: string
          comment_json: Json
          comment_modified_at: string
          comment_state_code: number
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          review_kind: string
          review_state_code: number
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_member_queue_items_v5: {
        Args: {
          p_display_mode?: string
          p_page?: number
          p_page_size?: number
          p_query?: string
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
          p_target_table?: string
        }
        Returns: {
          approve_opinion_count: number
          comment_created_at: string
          comment_json: Json
          comment_modified_at: string
          comment_state_code: number
          completed_reviewer_count: number
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          reject_opinion_count: number
          review_kind: string
          review_state_code: number
          reviewer_count: number
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_member_root_queue_items_v2: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
          p_status?: string
        }
        Returns: {
          comment_created_at: string
          comment_json: Json
          comment_modified_at: string
          comment_state_code: number
          created_at: string
          data_id: string
          data_version: string
          deadline: string
          id: string
          json: Json
          modified_at: string
          review_kind: string
          review_state_code: number
          reviewer_id: Json
          root_can_read: boolean
          root_matches_status: boolean
          target_table: string
          total_count: number
        }[]
      }
      qry_review_get_member_workload: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_role?: string
          p_sort_by?: string
          p_sort_order?: string
        }
        Returns: {
          created_at: string
          display_name: string
          email: string
          modified_at: string
          pending_count: number
          reviewed_count: number
          role: string
          team_id: string
          total_count: number
          user_id: string
        }[]
      }
      qry_review_get_my_contact_status: { Args: never; Returns: Json }
      qry_review_member_queue_items_v2: {
        Args: { p_page?: number; p_page_size?: number; p_status?: string }
        Returns: {
          data_id: string
          data_version: string
          deadline: string
          id: string
          modified_at: string
          my_comment_state_code: number
          review_kind: string
          state_code: number
          submitted_revision_checksum: string
          target_table: string
          total_count: number
        }[]
      }
      qry_review_quality_diagnostic: {
        Args: { p_run_id?: string }
        Returns: Json
      }
      qry_root_review_reference_progress: {
        Args: { p_root_review_id: string }
        Returns: {
          completed_reviewer_count: number
          data_id: string
          data_version: string
          reference_review_id: string
          relation_paths: Json
          reviewer_count: number
          state_code: number
          submitted_revision_checksum: string
          target_table: string
        }[]
      }
      qry_root_review_reference_progress_v2: {
        Args: { p_root_review_id: string }
        Returns: {
          actor_comment_modified_at: string
          actor_comment_state_code: number
          completed_reviewer_count: number
          data_id: string
          data_name: Json
          data_version: string
          reference_review_id: string
          reviewer_count: number
          state_code: number
          submitted_revision_checksum: string
          target_table: string
        }[]
      }
      qry_system_find_member_candidate_by_email: {
        Args: { p_email: string }
        Returns: {
          display_name: string
          email: string
          id: string
        }[]
      }
      qry_system_get_member_list: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
        }
        Returns: {
          created_at: string
          display_name: string
          email: string
          modified_at: string
          role: string
          team_id: string
          total_count: number
          user_id: string
        }[]
      }
      qry_system_status: { Args: never; Returns: Json }
      qry_team_find_invitable_user_by_email: {
        Args: { p_email: string; p_team_id: string }
        Returns: Json
      }
      qry_team_get: {
        Args: { p_team_id: string }
        Returns: {
          created_at: string
          id: string
          is_public: boolean
          json: Json
          modified_at: string
          rank: number
        }[]
      }
      qry_team_get_member_list: {
        Args: {
          p_page?: number
          p_page_size?: number
          p_sort_by?: string
          p_sort_order?: string
          p_team_id: string
        }
        Returns: {
          created_at: string
          display_name: string
          email: string
          modified_at: string
          role: string
          team_id: string
          total_count: number
          user_id: string
        }[]
      }
      qry_team_list: {
        Args: {
          p_keyword?: string
          p_mode: string
          p_page?: number
          p_page_size?: number
        }
        Returns: {
          created_at: string
          id: string
          is_public: boolean
          json: Json
          modified_at: string
          owner_email: string
          owner_user_id: string
          rank: number
          total_count: number
        }[]
      }
      search_contacts: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_contacts_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_dataset_json_uuid_mentions: {
        Args: {
          p_data_source?: string
          p_limit?: number
          p_source_entity_kinds?: string[]
          p_state_code_filter?: number
          p_team_id_filter?: string
          p_this_user_id?: string
          p_uuid: string
        }
        Returns: {
          matched_by: string
          matched_entity_table: string
          rank: number
          source_entity_kind: string
          source_id: string
          source_json: Json
          source_modified_at: string
          source_name: string
          source_team_id: string
          source_version: string
        }[]
      }
      search_flowproperties: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_flowproperties_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_flows: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_terms?: string[]
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_flows_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          order_by?: Json
          page_current?: number
          page_size?: number
          query_terms?: string[]
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_lifecyclemodels: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_terms?: string[]
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_lifecyclemodels_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          order_by?: Json
          page_current?: number
          page_size?: number
          query_terms?: string[]
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_open_data_catalog: {
        Args: {
          p_dataset_kind: string
          p_filter_condition?: Json
          p_page_current?: number
          p_page_size?: number
          p_publication_filter?: string
          p_query_terms?: string[]
          p_query_text?: string
          p_search_mode?: string
          p_sort_by?: string
          p_sort_direction?: string
          p_source_filter?: string
        }
        Returns: {
          id: string
          is_published: boolean
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_processes: {
        Args: {
          data_source?: string
          filter_condition?: Json
          owner_draft_only?: boolean
          page_current?: number
          page_size?: number
          query_terms?: string[]
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
          type_of_data_set_filter?: string
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_processes_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          order_by?: Json
          page_current?: number
          page_size?: number
          query_terms?: string[]
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
          type_of_data_set_filter?: string
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_processes_latest_v2: {
        Args: {
          data_source?: string
          filter_condition?: Json
          order_by?: Json
          owner_draft_only?: boolean
          page_current?: number
          page_size?: number
          query_terms?: string[]
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
          type_of_data_set_filter?: string
        }
        Returns: {
          id: string
          json: Json
          model_id: string
          model_version: string
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_sources: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_sources_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_unitgroups: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      search_unitgroups_latest: {
        Args: {
          data_source?: string
          filter_condition?: Json
          page_current?: number
          page_size?: number
          query_text: string
          state_code_filter?: number
          team_id_filter?: string
          this_user_id?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          team_id: string
          total_count: number
          version: string
        }[]
      }
      semantic_search: {
        Args: {
          match_count?: number
          match_threshold?: number
          query_embedding: string
        }
        Returns: {
          id: string
          json: Json
          rank: number
        }[]
      }
      semantic_search_contacts_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_flowproperties_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_flows: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_flows_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_lifecyclemodels: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_lifecyclemodels_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_processes: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_processes_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_sources_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      semantic_search_unitgroups_v1: {
        Args: {
          data_source?: string
          filter_condition?: string
          match_count?: number
          match_threshold?: number
          query_embedding: string
          state_code_filter?: number
          team_id_filter?: string
        }
        Returns: {
          id: string
          json: Json
          modified_at: string
          rank: number
          total_count: number
          version: string
        }[]
      }
      sources_embedding_ft_input: {
        Args: { proc: Database["public"]["Tables"]["sources"]["Row"] }
        Returns: string
      }
      svc_ai_tidas_suggestion_enqueue: {
        Args: { p_data: Json; p_data_type: string; p_requested_by: string }
        Returns: Json
      }
      svc_ai_tidas_suggestion_read: {
        Args: { p_job_id: string; p_requested_by: string }
        Returns: Json
      }
      svc_data_product_current_public_package: { Args: never; Returns: Json }
      svc_data_product_publication_list: {
        Args: { p_limit?: number }
        Returns: Json
      }
      svc_data_product_worker_metadata: {
        Args: { p_worker_job_ids: string[] }
        Returns: Json
      }
      svc_dataset_search_text_backfill_enqueue: {
        Args: {
          p_after_id?: string
          p_after_version?: string
          p_entity_kind: string
          p_limit?: number
        }
        Returns: Json
      }
      svc_identity_desired_state_read: {
        Args: { p_keycloak_sub: string }
        Returns: Json
      }
      svc_identity_desired_state_upsert: {
        Args: {
          p_keycloak_sub: string
          p_metadata?: Json
          p_role_code?: string
          p_role_operation?: string
          p_status?: string
        }
        Returns: Json
      }
      svc_identity_event_claim: {
        Args: { p_event_id: string; p_event_type: string }
        Returns: boolean
      }
      svc_identity_event_release: {
        Args: { p_event_id: string }
        Returns: boolean
      }
      svc_identity_login_bind: {
        Args: { p_keycloak_sub: string; p_user_id: string }
        Returns: Json
      }
      svc_identity_managed_role_materialize: {
        Args: { p_keycloak_sub: string; p_user_id: string }
        Returns: Json
      }
      svc_lca_cached_job_enqueue: {
        Args: {
          p_idempotency_key: string
          p_job_id: string
          p_job_kind: string
          p_payload: Json
          p_payload_schema_version: string
          p_queue_key?: string
          p_request_key: string
          p_request_payload: Json
          p_requested_by: string
          p_scope: string
          p_snapshot_id: string
        }
        Returns: Json
      }
      svc_lca_latest_all_unit_result: {
        Args: { p_requested_by: string; p_snapshot_id: string }
        Returns: Json
      }
      svc_lca_read_job_projection: {
        Args: {
          p_include_internal?: boolean
          p_legacy_job_id?: string
          p_requested_by: string
          p_worker_job_id?: string
        }
        Returns: Json
      }
      svc_lca_read_latest_single_solve_result: {
        Args: {
          p_process_index: number
          p_requested_by: string
          p_snapshot_id: string
        }
        Returns: Json
      }
      svc_lca_read_result_projection: {
        Args: {
          p_include_internal?: boolean
          p_requested_by: string
          p_required_artifact_format?: string
          p_result_id: string
        }
        Returns: Json
      }
      svc_lca_snapshot_build_enqueue: {
        Args: {
          p_job_id: string
          p_payload: Json
          p_payload_schema_version?: string
          p_process_filter: Json
          p_request_key: string
          p_requested_by: string
          p_scope: string
          p_snapshot_id: string
        }
        Returns: Json
      }
      svc_lca_snapshot_candidates: {
        Args: {
          p_limit?: number
          p_process_filter_contains?: Json
          p_scope: string
          p_snapshot_id?: string
        }
        Returns: Json
      }
      svc_membership_is_review_admin: {
        Args: { p_user_id: string }
        Returns: Json
      }
      svc_oauth_client_configure: {
        Args: {
          p_capability_ids?: string[]
          p_client_id: string
          p_client_kind: string
          p_enabled: boolean
        }
        Returns: Json
      }
      svc_schema_contract_status: { Args: never; Returns: Json }
      svc_tidas_package_export_enqueue: {
        Args: {
          p_idempotency_key: string
          p_job_id: string
          p_request_key: string
          p_request_payload: Json
          p_requested_by: string
          p_roots: Json
          p_scope: string
        }
        Returns: Json
      }
      svc_tidas_package_import_enqueue: {
        Args: {
          p_artifact_byte_size: number
          p_artifact_sha256: string
          p_content_type?: string
          p_filename: string
          p_job_id: string
          p_requested_by: string
          p_source_artifact_id: string
        }
        Returns: Json
      }
      svc_tidas_package_import_enqueue_v2: {
        Args: {
          p_artifact_byte_size: number
          p_artifact_sha256: string
          p_content_type?: string
          p_filename: string
          p_job_id: string
          p_requested_by: string
          p_source_artifact_id: string
        }
        Returns: Json
      }
      svc_tidas_package_import_prepare: {
        Args: {
          p_artifact_url: string
          p_content_type: string
          p_filename: string
          p_idempotency_key?: string
          p_job_id: string
          p_requested_by: string
          p_source_artifact_id: string
        }
        Returns: Json
      }
      svc_tidas_package_read: {
        Args: { p_lookup_id: string; p_requested_by: string }
        Returns: Json
      }
      svc_tidas_package_read_v2: {
        Args: { p_lookup_id: string; p_requested_by: string }
        Returns: Json
      }
      svc_worker_cancel_job: {
        Args: { p_cancelled_by?: string; p_job_id: string; p_reason?: string }
        Returns: Json
      }
      svc_worker_enqueue_job: {
        Args: {
          p_concurrency_key?: string
          p_idempotency_key?: string
          p_job_kind: string
          p_max_attempts?: number
          p_parent_job_id?: string
          p_payload_json?: Json
          p_payload_ref?: Json
          p_payload_schema_version?: string
          p_priority?: number
          p_queue_key?: string
          p_request_hash?: string
          p_requested_by?: string
          p_requester_type?: string
          p_root_job_id?: string
          p_run_after?: string
          p_subject_id?: string
          p_subject_type?: string
          p_subject_version?: string
          p_team_id?: string
          p_timeout_at?: string
          p_visibility?: string
        }
        Returns: Json
      }
      svc_worker_list_jobs: {
        Args: {
          p_include_internal?: boolean
          p_limit?: number
          p_requested_by?: string
          p_statuses?: string[]
          p_subject_id?: string
          p_subject_type?: string
          p_visibility?: string
        }
        Returns: Json
      }
      svc_worker_read_job: {
        Args: { p_include_internal?: boolean; p_job_id: string }
        Returns: Json
      }
      unitgroups_embedding_ft_input: {
        Args: { proc: Database["public"]["Tables"]["unitgroups"]["Row"] }
        Returns: string
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      filtered_row: {
        id: string | null
        embedding: string | null
      }
    }
  }
  public: {
    Tables: {
      contacts: {
        Row: {
          created_at: string | null
          embedding_ft: string | null
          embedding_ft_at: string | null
          extracted_md: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          modified_at: string | null
          review_id: string | null
          reviews: Json | null
          rule_verification: boolean | null
          search_text: string[] | null
          state_code: number | null
          team_id: string | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
      flowproperties: {
        Row: {
          created_at: string | null
          embedding_ft: string | null
          embedding_ft_at: string | null
          extracted_md: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          modified_at: string | null
          review_id: string | null
          reviews: Json | null
          rule_verification: boolean | null
          search_text: string[] | null
          state_code: number | null
          team_id: string | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
      flows: {
        Row: {
          created_at: string | null
          embedding_ft: string | null
          embedding_ft_at: string | null
          extracted_md: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          modified_at: string | null
          review_id: string | null
          reviews: Json | null
          rule_verification: boolean | null
          search_text: string[] | null
          state_code: number | null
          team_id: string | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
      ilcd: {
        Row: {
          created_at: string | null
          file_name: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          modified_at: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          file_name?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          file_name?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      lciamethods: {
        Row: {
          created_at: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          modified_at: string | null
          state_code: number | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          state_code?: number | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          state_code?: number | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
      lifecyclemodels: {
        Row: {
          created_at: string | null
          embedding_ft: string | null
          embedding_ft_at: string | null
          extracted_md: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          json_tg: Json | null
          modified_at: string | null
          reviews: Json | null
          rule_verification: boolean | null
          search_text: string[] | null
          state_code: number | null
          team_id: string | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          json_tg?: Json | null
          modified_at?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          json_tg?: Json | null
          modified_at?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
      processes: {
        Row: {
          created_at: string | null
          embedding_ft: string | null
          embedding_ft_at: string | null
          extracted_md: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          model_id: string | null
          model_version: string | null
          modified_at: string | null
          review_id: string | null
          reviews: Json | null
          rule_verification: boolean | null
          search_text: string[] | null
          state_code: number | null
          team_id: string | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          model_id?: string | null
          model_version?: string | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          model_id?: string | null
          model_version?: string | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
      sources: {
        Row: {
          created_at: string | null
          embedding_ft: string | null
          embedding_ft_at: string | null
          extracted_md: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          modified_at: string | null
          review_id: string | null
          reviews: Json | null
          rule_verification: boolean | null
          search_text: string[] | null
          state_code: number | null
          team_id: string | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
      unitgroups: {
        Row: {
          created_at: string | null
          embedding_ft: string | null
          embedding_ft_at: string | null
          extracted_md: string | null
          id: string
          json: Json | null
          json_ordered: Json | null
          modified_at: string | null
          review_id: string | null
          reviews: Json | null
          rule_verification: boolean | null
          search_text: string[] | null
          state_code: number | null
          team_id: string | null
          user_id: string | null
          version: string
        }
        Insert: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version: string
        }
        Update: {
          created_at?: string | null
          embedding_ft?: string | null
          embedding_ft_at?: string | null
          extracted_md?: string | null
          id?: string
          json?: Json | null
          json_ordered?: Json | null
          modified_at?: string | null
          review_id?: string | null
          reviews?: Json | null
          rule_verification?: boolean | null
          search_text?: string[] | null
          state_code?: number | null
          team_id?: string | null
          user_id?: string | null
          version?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  api: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
