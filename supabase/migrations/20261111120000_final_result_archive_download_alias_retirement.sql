begin;

-- Edge uses the stable download RPC. Remove the transition name and its grant.
delete from private.api_capability_grants
where routine_identity = 'api.qry_final_result_download_v2(uuid, text)';
drop function api.qry_final_result_download_v2(uuid, text);

notify pgrst, 'reload schema';
commit;
