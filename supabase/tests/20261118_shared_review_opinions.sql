begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select no_plan();

do $$
begin
  perform api.svc_oauth_client_configure('review992-author', 'cli', true, array['CLI-REVIEW-AUTHOR-01']);
  perform api.svc_oauth_client_configure('review992-participant', 'cli', true, array['NX-REV-01']);
end;
$$;
-- Synthetic actors and rows scoped to this rolled-back transaction.
set local session_replication_role = replica;
insert into private.roles (user_id, team_id, role) values
 ('99200000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','review-member'),
 ('99200000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','review-admin');
insert into private.reviews(id, data_id, data_version, target_table, target_owner_id, json, reviewer_id, state_code, submitted_revision_checksum)
select ('99200000-0000-4000-8000-' || seq)::uuid,
 '99200000-0000-4000-8000-000000000010', '01.00.000', target,
 '99200000-0000-4000-8000-000000000001', '{"user":{"id":"99200000-0000-4000-8000-000000000001"}}',
 '["99200000-0000-4000-8000-000000000002"]', state, repeat(checksum,64)
from (values ('000000000021','processes',-1,'a'),('000000000022','processes',1,'b'),('000000000023','flows',-1,'c')) as samples(seq,target,state,checksum);
insert into private.comments(review_id, reviewer_id, state_code, json)
select r.id, ('99200000-0000-4000-8000-' || c.actor)::uuid, c.state,
 '{"internal":"fixture","modellingAndValidation":{"private":"fixture","validation":{"review":[{"note":"visible"}]}}}'::json
from private.reviews r cross join (values ('000000000002',-1),('000000000004',0),('000000000005',-3),('000000000006',1)) c(actor,state)
where r.data_id='99200000-0000-4000-8000-000000000010';
set local session_replication_role = origin;
create temporary view fixture_contents as
  select to_jsonb(r) as content from private.reviews r where r.data_id='99200000-0000-4000-8000-000000000010'
  union all
  select to_jsonb(c) from private.comments c join private.reviews r on c.review_id=r.id
  where r.data_id='99200000-0000-4000-8000-000000000010';
create temporary table before_reads as select * from fixture_contents;
set local role authenticated;
set local request.path = '/rpc/qry_review_get_comment_items';
set local request.jwt.claims = '{"role":"authenticated","sub":"99200000-0000-4000-8000-000000000001","client_id":"review992-author"}';
select lives_ok('select api.oauth_client_pre_request()', 'author client can reach the bounded read');
select is((select count(*) from api.qry_review_get_items(null,'99200000-0000-4000-8000-000000000010','01.00.000')
 where target_table='processes'), 2::bigint, 'exact target retains both Process submissions and excludes the Flow');
select is((select submitted_revision_checksum from api.qry_review_get_items(array['99200000-0000-4000-8000-000000000021'::uuid])),
 repeat('a',64), 'stored submission fingerprint returned for author');
select results_eq($$select reviewer_id, state_code, json from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000021','opinions')$$,
 $$select null::uuid,-1,'{"modellingAndValidation":{"validation":{"review":[{"note":"visible"}]}}}'::jsonb$$, 'author sees exactly the returned feedback');
select is_empty($$select * from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000022','returned')$$,'active reviews have no author feedback');
select is_empty($$select * from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000023','returned')$$,'no author Process feedback on other types');
select is_empty($$select * from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000021','all')$$,'broad legacy scope requires participant capability');
set local request.jwt.claims = '{"role":"authenticated","sub":"99200000-0000-4000-8000-000000000001"}';
select results_eq($$select * from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000021','returned')$$,
 $$select * from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000021','opinions')$$,'first-party author sees the same returned projection through both new scopes');
set local request.jwt.claims = '{"role":"authenticated","sub":"99200000-0000-4000-8000-000000000002","client_id":"review992-participant"}';
select results_eq($$select reviewer_id from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000021','opinions')$$,
 $$select '99200000-0000-4000-8000-000000000002'::uuid$$,'assigned member reads own row');
set local request.jwt.claims = '{"role":"authenticated","sub":"99200000-0000-4000-8000-000000000003","client_id":"review992-participant"}';
select is((select array_agg(state_code order by state_code) from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000021','opinions')),
 array[-3,-1,0,1], 'admin reads all opinion rows');
select is((select opinion_scope from api.qry_review_get_items(array['99200000-0000-4000-8000-000000000022'::uuid])), 'admin', 'server verifies admin view');
set local request.jwt.claims = '{"role":"authenticated","sub":"99200000-0000-4000-8000-000000000003","client_id":"review992-author"}';
select is_empty($$select * from api.qry_review_get_comment_items('99200000-0000-4000-8000-000000000021','opinions')$$,'the author-only client cannot use the actor admin role on a foreign review');
reset role;
select bag_eq('select content from fixture_contents', 'select content from before_reads',
  'review and comment records are identical after all role-scoped reads');
select * from finish();
rollback;
