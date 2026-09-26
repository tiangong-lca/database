#!/usr/bin/env python3
"""Pin the composite graph and its explicitly reviewed legacy-reader revision."""
import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY_CUTOVER = ROOT / 'supabase/migrations/20260926143000_portal_catalog_bounded_v2.sql'
REVISED_READERS = {'catalog_portal_search_v2_impl', 'catalog_portal_facets_v2_impl'}


def reviewed_reader_definition(name):
    """Only these two query consumers may use the qualified V2 revision.

    Stored payloads, writers, indexes, immutable manifests and the other read
    helpers still compare against the original composite-name baseline.
    """
    text = LEGACY_CUTOVER.read_text()
    pattern = rf'^CREATE OR REPLACE FUNCTION "private"\."{name}"\(.*?\bAS (\$[a-zA-Z_0-9]*\$)[\s\S]*?\1;'
    definition = re.search(pattern, text, flags=re.M | re.S)
    assert definition, f'{name}: reviewed cutover definition missing'
    owner = re.search(rf'ALTER FUNCTION "private"\."{name}"\([^;]*\) OWNER TO "([a-z_]+)";', text)
    assert owner, f'{name}: reviewed cutover owner missing'
    return definition.group() + '\nOWNER TO "' + owner[1] + '";'

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--local-container',required=True)
parser.add_argument('--base-ref', default='0c6c00d93934c86d0059b37c3248d91449adab6b')
a=parser.parse_args()
if not re.fullmatch(r'supabase_db_database-engine(?:-[a-z0-9]+)?|supabase_db_database-engine-733-isolated',a.local_container):
    parser.error('requires a local Database container')
q="""select json_agg(json_build_object('name',p.proname,'body',p.prosrc,'owner',pg_get_userbyid(p.proowner),'config',p.proconfig,'volatility',p.provolatile,'parallel',p.proparallel,'definer',p.prosecdef)) from pg_proc p where pronamespace='private'::regnamespace and prokind='f'"""
rows=json.loads(subprocess.check_output(['docker','exec',a.local_container,'psql','-X','-qAt','-U','postgres','-d','postgres','-c',q],text=True))
functions={r['name']:r for r in rows}
# Compare to canonical Git baseline, since mutable readers now update in place.
changed = ['assert_portal_catalog_character_contract_v1', 'assert_portal_catalog_projection_contract_v1', 'assert_portal_process_keyword_rank_contract_v1', 'catalog_portal_candidate_rows_v1', 'catalog_portal_candidate_rows_v2', 'catalog_portal_facet_candidate_rows_v1', 'catalog_portal_facet_candidate_rows_v2', 'catalog_portal_facets_v1_impl', 'catalog_portal_facets_v2_impl', 'catalog_portal_flow_pattern_versions_v1', 'catalog_portal_flow_single_character_versions_v1', 'catalog_portal_hybrid_pattern_matches_v1', 'catalog_portal_process_keyword_keys_v1', 'catalog_portal_process_keyword_relevance_v1_impl', 'catalog_portal_process_pattern_versions_v1', 'catalog_portal_process_single_character_versions_v1', 'catalog_portal_projection_payload_v1', 'catalog_portal_search_v1_impl', 'catalog_portal_search_v2_impl', 'catalog_portal_single_character_search_v1_impl', 'portal_catalog_card_v1', 'portal_catalog_projection_manifest_sha256_v1', 'portal_dataset_metadata_v1', 'portal_dataset_projection_v1', 'portal_process_keyword_rank_manifest_sha256_v1', 'portal_projection_hybrid_candidates_v2', 'portal_projection_hybrid_search_v1_impl', 'portal_projection_hybrid_search_v2_impl', 'portal_projection_semantic_candidates_v1', 'portal_projection_semantic_candidates_v2', 'portal_projection_semantic_flow_exact_v1', 'portal_projection_semantic_flow_v1', 'portal_projection_semantic_flow_v2', 'portal_projection_semantic_process_exact_v1', 'portal_projection_semantic_process_v1', 'portal_projection_semantic_process_v2', 'portal_public_hybrid_card_v1', 'portal_search_v1', 'portal_search_v2', 'sync_portal_catalog_character_row_v1']
count=0
for original in changed:
    if original.startswith('assert_') or '_manifest_' in original or original=='portal_catalog_card_v1':
        continue
    generation=re.sub(r'_v(?=\d)','_cn',original)
    name=generation if generation in functions else original
    new=functions[name]
    baseline = reviewed_reader_definition(original) if original in REVISED_READERS else subprocess.check_output(['git','show',f'{a.base_ref}:supabase/workspace/schemas/private/functions/{original}/definition.sql'],cwd=ROOT,text=True)
    match=re.search(r'AS (\$[a-zA-Z_0-9]*\$)([\s\S]*?)\1',baseline)
    assert match, original
    oldbody=match[2]
    owner=re.search(r'OWNER TO "?([a-z_]+)"?;',baseline)[1]
    assert new['owner']==owner, f'{name}: owner changed'
    header=baseline[:match.start()].replace('"','').lower()
    assert new['definer']==('security definer' in header), f'{name}: executor changed'
    for word,code in [('immutable','i'),('stable','s'),('volatile','v')]:
        if re.search(r'\b'+word+r'\b',header):
            assert new['volatility']==code, f'{name}: volatility changed'
    expected_parallel='s' if 'parallel safe' in header else 'r' if 'parallel restricted' in header else 'u'
    assert new['parallel']==expected_parallel, f'{name}: parallel changed'
    configs=[]
    for key,value in re.findall(r"SET \"?([a-z_.]+)\"? TO ([^\n]+)",baseline):
        value=value.strip()
        if value=="''": value='""'
        else: value=value.strip("'\"")
        configs.append(key+'='+value)
    assert sorted(new['config'] or [])==sorted(configs), f'{name}: planner/timeout config changed'

    if original in REVISED_READERS:
        assert new['body']==oldbody, f'{name}: deployed body differs from the exact reviewed V2 cutover'
        count+=1
        continue

    body=re.sub(r'_cn(?=[12](?:_|\b))','_v',new['body'])
    for kind in ['search','character']:
        body=body.replace(f'portal_catalog_{kind}_current_v2',f'portal_catalog_{kind}_rows_v1').replace(f'portal_catalog_{kind}_rows_v2',f'portal_catalog_{kind}_rows_v1')
    body=re.sub(r"^  if p_kind = 'process' then\n  v_fingerprint := pg_catalog.encode\(extensions.digest\(pg_catalog.convert_to\('composite-names-v2:'.*\n  end if;\n",'',body,flags=re.M)
    if original=='portal_dataset_metadata_v1':
        oldbody=re.sub(r"private\.portal_localized_text_v1\(\s*v_information #> '\{dataSetInformation,name,baseName\}'\s*\)", 'private.portal_process_names_v1(p_json)',oldbody,count=1)
    assert body==oldbody, f'{name}: query body changed beyond routing/epoch/name derivation'
    count+=1
assert count==34, count
# The shadow generation must not retain duplicate mutable query readers.
assert len([n for n in functions if re.search(r'_cn[12](?:_|$)',n)])==11
print(f'PASS: {count} readers/helpers match the immutable composite baseline or the two exact reviewed V2 readers; only 11 required generation functions remain')
