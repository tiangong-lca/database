"""Database #912 exact owned-project utilities; no reset/creation on import."""
import json
from pathlib import Path
import subprocess
from prepare_study_runtime_project import settings

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = 'supabase_db_study912'
STUDY = '89400000-0000-4000-8000-000000000010'


def quote(value):
    return "'"+value.replace("'", "''")+"'"


def sql_json(value):
    return quote(json.dumps(value, separators=(',', ':'), ensure_ascii=False))+'::jsonb'


def command(application='study912-control'):
    return ['docker', 'exec', '-i', '-e', 'PGAPPNAME='+application, CONTAINER,
            'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']


def sql(statement, timeout=60):
    result = subprocess.run(command(), input=statement, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError('owned study912 SQL failed: '+result.stderr[-2000:])
    return result.stdout.strip()


def json_lines(output):
    return [json.loads(line) for line in output.splitlines() if line.startswith('{')]


def expand(path):
    return '\n'.join(expand(path.parent/line[4:].strip()) if line.startswith('\\ir ') else line for line in path.read_text().splitlines())


def verify_owned(workdir):
    workdir = workdir.resolve()
    receipt = json.loads((workdir/'ownership.json').read_text())
    assert receipt['project']=='study912' and receipt['issue']=='database#912'
    assert Path(receipt['destination']).resolve()==workdir and receipt['sharedProjectTouched'] is False
    config = (workdir/'supabase/config.toml').read_text()
    assert settings(config)==('study912',56922,17) and '\n[remotes.' not in config
    info = json.loads(subprocess.check_output(['docker','inspect',CONTAINER],text=True))[0]
    assert info['Config']['Labels']['com.supabase.cli.project']=='study912'
    assert {x['HostPort'] for x in info['HostConfig']['PortBindings']['5432/tcp']}=={'56922'}
    assert sql("select current_setting('server_version_num')::integer/10000;")=='17'
    return receipt


def claim(actor=1, client=None, service=False):
    claims = {'role':'service_role' if service else 'authenticated'}
    if actor is not None and not service:
        claims['sub']='89400000-0000-4000-8000-'+str(actor).zfill(12)
    if client:
        claims['client_id']=client
    return "select set_config('request.jwt.claims',"+quote(json.dumps(claims))+",true) is not null;"


def request(operation, fields=None, key='request'):
    return {'schemaVersion':'lca.study-api.v6','requestId':key,'operation':operation,**(fields or {})}
