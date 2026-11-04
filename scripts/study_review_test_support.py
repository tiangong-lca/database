"""Database #906 exact owned-project proof utilities; no reset/drop on import."""
import json
from pathlib import Path
import select
import subprocess
import time
from prepare_study_runtime_project import settings

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = 'supabase_db_study906'
STUDY = '89400000-0000-4000-8000-000000000010'
REPORT = '90600000-0000-4000-8000-000000000002'


def quote(value):
    return "'" + value.replace("'", "''") + "'"


def sql_json(value):
    return quote(json.dumps(value, separators=(',', ':'))) + '::jsonb'


def command(application='study906-control'):
    return ['docker', 'exec', '-i', '-e', 'PGAPPNAME='+application, CONTAINER,
            'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']


def sql(statement, timeout=60):
    r = subprocess.run(command(), input=statement, text=True, capture_output=True, timeout=timeout)
    if r.returncode:
        raise RuntimeError('owned study906 SQL failed: '+r.stderr[-2000:])
    return r.stdout.strip()


def json_lines(output):
    return [json.loads(x) for x in output.splitlines() if x.startswith('{')]


def expand(path):
    return '\n'.join(expand(path.parent/x[4:].strip()) if x.startswith('\\ir ') else x for x in path.read_text().splitlines())


def verify_owned(workdir):
    workdir = workdir.resolve()
    receipt = json.loads((workdir/'ownership.json').read_text())
    assert receipt['project'] == 'study906' and receipt['issue'] == 'database#906'
    assert Path(receipt['destination']).resolve() == workdir and receipt['sharedProjectTouched'] is False
    config = (workdir/'supabase/config.toml').read_text()
    assert settings(config) == ('study906',56622,17) and '\n[remotes.' not in config
    info = json.loads(subprocess.check_output(['docker','inspect',CONTAINER],text=True))[0]
    assert info['Config']['Labels']['com.supabase.cli.project'] == 'study906'
    assert {x['HostPort'] for x in info['HostConfig']['PortBindings']['5432/tcp']} == {'56622'}
    assert sql("select current_setting('server_version_num')::integer/10000;") == '17'
    return receipt


def claim(actor=1,client=None,service=False):
    claims = {'role':'service_role' if service else 'authenticated'}
    if actor is not None and not service:
        claims['sub']='89400000-0000-4000-8000-'+str(actor).zfill(12)
    if client:
        claims['client_id']=client
    return "select set_config('request.jwt.claims',"+quote(json.dumps(claims))+",true) is not null;"


def request(operation,fields=None,key='request'):
    return {'schemaVersion':'lca.study-api.v4','requestId':key,'operation':operation,**(fields or {})}


def call(req,write=True):
    return 'select api.'+('cmd' if write else 'qry')+'_study_review_v1('+sql_json(req)+');'


def invoke(statement,actor=1,client=None,service=False):
    return json_lines(sql('begin;'+claim(actor,client,service)+statement+'commit;'))[0]


def wait_for(condition,description):
    deadline=time.monotonic()+12
    while time.monotonic()<deadline:
        if condition():
            return
        time.sleep(.05)
    raise AssertionError('did not observe '+description)


def race(name,first,second,first_claim=None,second_claim=None,second_wait=True):
    lock=9062180
    barrier=subprocess.Popen(command('study906-barrier'),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
    writers=[]
    try:
        barrier.stdin.write("begin;set local idle_in_transaction_session_timeout='25s';select 'held' from pg_advisory_xact_lock(%d);\n"%lock)
        barrier.stdin.flush()
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            if select.select([barrier.stdout],[],[],.2)[0] and barrier.stdout.readline().strip()=='held':
                break
        else:
            raise AssertionError('barrier unavailable')
        a=subprocess.Popen(command('study906-writer-a'),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        writers.append(a)
        a.stdin.write("begin;set local statement_timeout='20s';"+(first_claim or claim())+first+'select pg_advisory_xact_lock(%d);commit;\n'%lock)
        a.stdin.close();a.stdin=None
        wait_for(lambda:sql("select exists(select 1 from pg_stat_activity where application_name='study906-writer-a' and wait_event='advisory');")=='t','first transaction at domain-lock barrier')
        b=subprocess.Popen(command('study906-writer-b'),stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        writers.append(b)
        b.stdin.write("begin;set local statement_timeout='20s';"+(second_claim or claim())+second+'commit;\n')
        b.stdin.close();b.stdin=None
        if second_wait:
            wait_for(lambda:sql("select exists(select 1 from pg_stat_activity where application_name='study906-writer-b' and wait_event_type='Lock' and wait_event in('transactionid','tuple'));")=='t','second transaction waiting on actual row lock')
        else:
            wait_for(lambda:b.poll() is not None,'nonblocking source fence rejection')
        barrier.stdin.write('commit;\n\\q\n');barrier.stdin.flush();barrier.communicate(timeout=10)
        one,err1=a.communicate(timeout=12);two,err2=b.communicate(timeout=12)
        assert a.returncode==b.returncode==0,(err1,err2)
        return {'name':name,'first':json_lines(one)[0],'second':json_lines(two)[0],
                'observedFirstAdvisoryWait':True,'observedSecondRowWait':second_wait}
    finally:
        for p in [barrier,*writers]:
            if p.poll() is None:
                p.kill();p.communicate(timeout=5)
