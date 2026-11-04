#!/usr/bin/env python3
"""Verify contained Worker schemas and actual study912 DTOs with bundled pg_jsonschema.

No new dependency, sibling import, remote schema resolution or business mutation.
The installed0.3.3 validator needs an absolute root base URI; only that annotation
is adapted in memory after verifying every producer reference is fragment-local.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from study_method_test_support import ROOT,quote,sql,sql_json,verify_owned

SCHEMA_DIR=ROOT/'supabase/tests/fixtures/study912-worker'
SOURCE='13a749e619d7ef348e9298bb049e8c01c60e9086'
SCHEMAS={
    'assessment':'study-method-assessment-record.v1.schema.json',
    'inputContext':'study-method-job-context.v1.schema.json',
    'completion':'study-method-completion.v1.schema.json',
    'evidenceBody':'study-method-evidence.v1.schema.json',
    'evidenceRecord':'study-method-evidence-record.v1.schema.json',
}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--workdir',type=Path,required=True);p.add_argument('--vectors',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();verify_owned(a.workdir);assert not a.report.exists()
    manifest=json.loads((SCHEMA_DIR/'source-manifest.json').read_text());assert manifest['sourceCommit']==SOURCE and manifest['producerRepository']=='tiangong-lca/worker';files={x['path']:x for x in manifest['files']}
    for name,item in files.items():
        assert Path(name).name==name;f=SCHEMA_DIR/name;assert f.is_file()and not f.is_symlink();b=f.read_bytes();assert len(b)==item['byteSize']and hashlib.sha256(b).hexdigest()==item['sha256']
    vectors=json.loads(a.vectors.read_text());assert vectors['project']=='study912';migration=ROOT/'supabase/migrations/20261104191012_study_method_assessment_v1.sql';assert vectors['migrationSha256']==hashlib.sha256(migration.read_bytes()).hexdigest();data=vectors['serviceDtos'];schemas={}
    def inspect(value,root=False):
        if isinstance(value,dict):
            if'$schema'in value:assert value['$schema']=='https://json-schema.org/draft/2020-12/schema'
            if not root:assert'$id'not in value,'new nested schema scope requires independent review'
            for key,item in value.items():
                if key in('$ref','$dynamicRef','$recursiveRef'):assert isinstance(item,str)and item.startswith('#/'),'external references are forbidden'
                inspect(item)
        elif isinstance(value,list):
            for item in value:inspect(item)
    for name in SCHEMAS.values():
        value=json.loads((SCHEMA_DIR/name).read_text());inspect(value,True);value['$id']='https://study912.invalid/validation/'+name
        assert sql('select extensions.jsonschema_is_valid('+quote(json.dumps(value,ensure_ascii=False))+'::json);')=='t';schemas[name]=value
    cases=[]
    def check(name,schema_key,value,expected=True):
        found=sql('select extensions.jsonb_matches_schema('+quote(json.dumps(schemas[SCHEMAS[schema_key]],ensure_ascii=False))+'::json,'+sql_json(value)+');')=='t';cases.append({'name':name,'expectedValid':expected,'actualValid':found});assert found is expected,name
    for key in SCHEMAS:check('actualSQL-'+key,key,data[key])
    for key in SCHEMAS:
        value=copy.deepcopy(data[key]);value['unexpectedAuthority']=True;check('unknown-field-'+key,key,value,False)
    value=copy.deepcopy(data['completion']);value['factsRef']['type']='analysisFacts';check('wrong-facts-family','completion',value,False)
    value=copy.deepcopy(data['inputContext']);value['budget']['maxSelectedFactorRecords']=8193;check('excess-selected-factor-budget','inputContext',value,False)
    value=copy.deepcopy(data['evidenceRecord']);value['status']='verified';check('cannot-mint-professional-status','evidenceRecord',value,False)
    for text in['研'*256,'😀'*256]:
        value=copy.deepcopy(data['evidenceBody']);value['title']=text;check('unicode-title-'+str(len(text.encode()))+'-bytes','evidenceBody',value)
    value=copy.deepcopy(data['evidenceBody']);value['statement']='研'*8192;check('unicode-statement-boundary','evidenceBody',value)
    for text in['研'*257,'😀'*257,'C1\u0085control']:
        value=copy.deepcopy(data['evidenceBody']);value['title']=text;check('unicode-invalid-title-'+str(len(text.encode()))+'-bytes','evidenceBody',value,False)
    golden=json.loads((SCHEMA_DIR/'config-identity.json').read_text());canonical=json.dumps(golden['config'],sort_keys=True,ensure_ascii=False,separators=(',',':'));assert canonical==golden['canonicalUtf8'];digest=hashlib.sha256(b'study.method-assessment-config.v1\0'+canonical.encode()).hexdigest();assert digest==golden['sha256']==sql('select private.study_method_config_hash('+sql_json(golden['config'])+');')
    version=sql("select extversion from pg_extension where extname='pg_jsonschema';");a.report.write_text(json.dumps({'schemaVersion':'lca.study-method-schema-parity.v1','passed':True,'project':'study912','workerSourceCommit':SOURCE,'containedFilesVerified':len(files),'actualProducerDtos':len(SCHEMAS),'cases':cases,'independentConfigGolden':digest,'validator':'installed pg_jsonschema','validatorVersion':version,'compilerBaseUriOnlyAdapter':True,'allReferencesLocalNoFetch':True,'originalSchemaBytesUnchanged':True,'vectorsSha256':hashlib.sha256(a.vectors.read_bytes()).hexdigest(),'classification':'actualSQLDTOstructure_and_softwareConfigIdentity_noNativeBytesOrScientificQualification'},indent=2)+'\n');print(json.dumps({'passed':True,'actualDtos':len(SCHEMAS),'adversarialCases':len(cases)-len(SCHEMAS),'validatorVersion':version}))


if __name__=='__main__':main()
