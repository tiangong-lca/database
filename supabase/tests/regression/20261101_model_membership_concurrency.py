#!/usr/bin/env python3
"""Database #880. Real two-writer membership races in a disposable local clone.

The source database is read only. A uniquely named database is restored from a
logical dump, excluding pg_cron, then removed with its sessions after testing.
No service is stopped and no hosted endpoint is accepted. All writes use
synthetic identities and the existing authenticated dataset/bundle commands.

Example on the ordinary local CI stack, after migrations have been applied:
  python3 supabase/tests/regression/20261101_model_membership_concurrency.py \
    --container supabase_db_database-engine --project-id database-engine \
    --receipt /tmp/model-membership-concurrency.json

For a development-only candidate, --migration may name SQL applied exclusively
inside the disposable clone. CI must omit that option. --expect-red runs only
one bounded predecessor reproduction and requires an actual orphaned member.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import secrets
import subprocess
import tempfile
import threading
import time
import uuid


TIMEOUT = 20


def literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


class Session:
    """Persistent psql connection, with a bounded completion marker per query."""

    def __init__(self, docker: list[str], container: str, database: str, name: str):
        self.lines: queue.Queue[str | None] = queue.Queue()
        self.diagnostics: list[str] = []
        self.process = subprocess.Popen(
            docker + ['exec', '-i', container, 'psql', '-XqAt', '-U', 'supabase_admin',
                      '-d', database, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()
        self.query(f"set application_name={literal(name)};set statement_timeout='15s';"
                   "set lock_timeout=0;set idle_in_transaction_session_timeout='60s';"
                   "set client_min_messages=warning;")
        self.pid = int(self.scalar('select pg_backend_pid();'))
        self.query("""
          create function pg_temp.model880_try(p_sql text) returns jsonb
          language plpgsql as $$
          declare result jsonb;
          begin
            execute p_sql into result;
            return result;
          exception when others then
            return jsonb_build_object('ok',false,'sqlstate',sqlstate,'code',sqlerrm);
          end;
          $$;
          grant execute on function pg_temp.model880_try(text) to authenticated;
        """)

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.lines.put(line.rstrip('\r\n'))
        self.lines.put(None)

    def _read_stderr(self) -> None:
        assert self.process.stderr is not None
        for line in self.process.stderr:
            match = re.search(r'ERROR:\s+([0-9A-Z]{5})', line)
            if match:
                self.diagnostics.append(match[1])

    def query(self, sql: str) -> list[str]:
        marker = 'MODEL880_END_' + secrets.token_hex(12)
        assert self.process.stdin is not None
        self.process.stdin.write(sql.rstrip() + '\n\\echo ' + marker + '\n')
        self.process.stdin.flush()
        end = time.monotonic() + TIMEOUT
        lines = []
        while True:
            try:
                line = self.lines.get(timeout=max(0.01, end-time.monotonic()))
            except queue.Empty as exc:
                raise RuntimeError('Bounded local SQL response timed out') from exc
            require(line is not None, 'Local SQL session exited, SQLSTATE '+','.join(self.diagnostics))
            if line == marker:
                return lines
            if line:
                lines.append(line)
            require(time.monotonic() < end and len(lines) < 100, 'SQL output bound exceeded')

    def scalar(self, sql: str) -> str:
        lines = self.query(sql)
        require(len(lines) == 1, 'Expected one scalar from local SQL')
        return lines[0]

    def json(self, sql: str):
        return json.loads(self.scalar(sql))

    def begin(self, actor: str, isolation: str = 'read committed') -> None:
        self.query(f"begin isolation level {isolation};"
                   f"select set_config('request.jwt.claim.sub',{literal(actor)},true);"
                   "select set_config('request.jwt.claim.role','authenticated',true);"
                   "set local role authenticated;")

    def command(self, sql: str) -> dict:
        return self.json('select pg_temp.model880_try('+literal(sql)+');')

    def close(self) -> None:
        if self.process.poll() is None:
            assert self.process.stdin is not None
            try:
                self.process.stdin.write('rollback;\n\\q\n')
                self.process.stdin.flush()
                self.process.wait(timeout=3)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.process.kill()
                self.process.wait(timeout=3)


def document(kind: str, version: str) -> dict:
    return {kind: {'administrativeInformation': {'publicationAndOwnership':
                  {'common:dataSetVersion': version}}, 'syntheticMarker': 'database880'}}


def process_create(child: str, model: str | None, version: str = '01.00.000',
                   model_version: str | None = '01.00.000') -> str:
    return ("select api.cmd_dataset_create('processes',"+literal(child)+"::uuid,"
            +literal(json.dumps(document('processDataSet', version)))+"::jsonb,"
            +(literal(model)+"::uuid" if model else 'null')+",true,'{}'::jsonb,"
            +(literal(model_version) if model and model_version is not None else 'null')+")")


def model_create(model: str, version: str = '01.00.000') -> str:
    plan = {'mode': 'create', 'modelId': model, 'version': version,
            'parent': {'jsonOrdered': document('lifeCycleModelDataSet', version)},
            'processMutations': []}
    return 'select api.cmd_lifecycle_model_bundle_save('+literal(json.dumps(plan))+'::jsonb)'


def model_delete(model: str, version: str = '01.00.000') -> str:
    return 'select api.cmd_lifecycle_model_bundle_delete('+literal(model)+'::uuid,'+literal(version)+')'


def saved(result: dict) -> bool:
    return result.get('ok') is not False and 'sqlstate' not in result


def busy(result: dict) -> bool:
    return result.get('sqlstate') == '55P03' or result.get('code') == 'DATASET_CREATE_LOCK_TIMEOUT'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--project-id', required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--migration', action='append', type=Path, default=[])
    parser.add_argument('--expect-red', action='store_true')
    args = parser.parse_args()
    require(not (os.environ.get('CI') and args.migration), 'CI must test already applied migrations')
    require(not args.receipt.exists(), 'Receipt must be a new file')
    require(re.fullmatch(r'[A-Za-z0-9_-]+', args.project_id) is not None, 'Invalid local project ID')
    require(args.container == 'supabase_db_'+args.project_id, 'Exact Supabase DB container required')
    endpoint = os.environ.get('DOCKER_HOST', '').strip()
    if not endpoint:
        endpoint = subprocess.check_output(
            ['docker', 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], text=True,timeout=5).strip()
    require(endpoint.startswith('unix:///'), 'Only a local Unix Docker endpoint is admitted')
    require(os.environ.get('DOCKER_HOST') in (None, '', endpoint), 'Conflicting Docker endpoint')
    docker = ['docker', '--host', endpoint]
    labels = json.loads(subprocess.check_output(
        docker+['inspect', args.container, '--format', '{{json .Config.Labels}}'], text=True,timeout=5))
    require(labels.get('com.supabase.cli.project') == args.project_id, 'Wrong local project label')
    database = 'db880_concurrency_'+secrets.token_hex(8)
    actor = str(uuid.uuid4())
    other_actor = str(uuid.uuid4())
    receipt = {'syntheticOnly': True, 'database': database, 'container': args.container,
               'cases': [], 'passed': False, 'cleanup': False, 'migrations': [],
               'harnessSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    sessions: list[Session] = []
    created = False

    def psql(sql: str, target: str = database) -> str:
        result = subprocess.run(docker+['exec', '-i', args.container, 'psql', '-XqAt',
                                '-U', 'supabase_admin', '-d', target, '-v', 'ON_ERROR_STOP=1'],
                                input=sql, text=True, capture_output=True, timeout=60)
        require(result.returncode == 0, 'Local clone SQL failed')
        return result.stdout.strip()

    try:
        psql('create database '+database+' template template0;', 'template1')
        created = True
        with tempfile.TemporaryFile() as dump:
            result = subprocess.run(docker+['exec', args.container, 'pg_dump', '-U', 'supabase_admin',
                                    '-d', 'postgres', '--exclude-extension=pg_cron', '--exclude-schema=cron'],
                                    stdout=dump, stderr=subprocess.PIPE, timeout=60)
            require(result.returncode == 0, 'Read-only source dump failed')
            dump.seek(0)
            receipt['logicalCloneSha256'] = hashlib.file_digest(dump, 'sha256').hexdigest()
            dump.seek(0)
            result = subprocess.run(docker+['exec', '-i', args.container, 'psql', '-Xq',
                                    '-U', 'supabase_admin', '-d', database, '-v', 'ON_ERROR_STOP=1'],
                                    stdin=dump, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=90)
            require(result.returncode == 0, 'Disposable clone restore failed')
        receipt['serverVersion'] = psql("select current_setting('server_version');")
        receipt['sourceMigrationHead'] = psql('select max(version) from supabase_migrations.schema_migrations;')
        receipt['sourceRoutines'] = json.loads(psql("""
          select jsonb_object_agg(n.nspname||'.'||p.proname,
            encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex'))
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='private' and p.proname in
            ('delete_lifecycle_model_bundle','fence_process_model_membership_v1',
             'dataset_flow_identity_active_fence');
        """))
        for migration in args.migration:
            sql = migration.read_text()
            psql(sql)
            receipt['migrations'].append({'path': str(migration),
                                          'sha256': hashlib.sha256(sql.encode()).hexdigest()})
        # The clone alone contains egress. The source function is untouched.
        psql("""create or replace function util.invoke_edge_function(
          name text,body jsonb,timeout_milliseconds integer default 300000)
          returns void language plpgsql security definer set search_path='' as $$begin return;end$$;
        """
        +"insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) values("
        +literal(actor)+",'authenticated','authenticated','race880@example.invalid','{}','{}'),("
        +literal(other_actor)+",'authenticated','authenticated','race880-other@example.invalid','{}','{}');")
        for name in ('control', 'first', 'second'):
            sessions.append(Session(docker,args.container,database,'model880-'+database+'-'+name))
        c, a, b = sessions
        require(a.pid != b.pid, 'Independent writer backends are required')

        def setup_model(model: str, version: str = '01.00.000') -> None:
            c.begin(actor)
            require(saved(c.command(model_create(model, version))), 'Synthetic Model setup failed')
            c.query('commit;')

        def counts(model: str, version: str = '01.00.000') -> dict:
            return c.json("select jsonb_build_object('models',(select count(*) from public.lifecyclemodels where id="
                          +literal(model)+" and version="+literal(version)+"),'children',"
                          "(select count(*) from public.processes where model_id="+literal(model)
                          +" and coalesce(model_version,version)="+literal(version)+"));")

        def compete(label: str, first: str, second: str, *, isolation: str = 'read committed', retry: bool = True, first_actor: str = actor, second_actor: str = actor) -> tuple[dict,dict]:
            a.begin(first_actor)
            one = a.command(first)
            require(saved(one), 'First authenticated command failed in '+label)
            b.begin(second_actor, isolation)
            # Fix a stale snapshot before release for the stronger isolation case.
            if isolation != 'read committed':
                b.scalar('select count(*) from public.lifecyclemodels;')
            holder_before = c.scalar(f"select state='idle in transaction' from pg_stat_activity where pid={a.pid};") == 't'
            started = time.monotonic()
            two = b.command(second)
            elapsed = time.monotonic()-started
            holder_after = c.scalar(f"select state='idle in transaction' from pg_stat_activity where pid={a.pid};") == 't'
            holder_open = holder_before and holder_after
            require(holder_open, 'First writer transaction must remain open during the competing command')
            contention = busy(two)
            a.query('commit;')
            b.query('commit;')
            # A bounded try-lock loser retries through the same normal endpoint.
            initial = two
            if retry and busy(two):
                b.begin(second_actor, isolation)
                two = b.command(second)
                b.query('commit;')
            receipt['cases'].append({'case': label, 'distinctBackends': True,
                                      'holderTransactionObserved': holder_open,
                                      'competingCommandSeconds': round(elapsed,4),
                                      'nonblockingProtocol': True,
                                      'contentionObserved': contention,
                                      'initialSecondSucceeded': saved(initial),
                                      'initialSecondSqlstate': initial.get('sqlstate'),
                                      'initialSecondCode': initial.get('code'),
                                      'firstSucceeded': saved(one), 'secondSucceeded': saved(two),
                                      'secondSqlstate': two.get('sqlstate'), 'secondCode': two.get('code')})
            return receipt['cases'][-1], two

        model, child = str(uuid.uuid4()), str(uuid.uuid4())
        setup_model(model)
        case, result = compete('insert-first-delete', process_create(child, model), model_delete(model),
                               first_actor=other_actor if args.expect_red else actor)
        case['foreignWriter'] = args.expect_red
        state = counts(model)
        case['after'] = state
        if args.expect_red:
            require(state == {'models': 0, 'children': 1}, 'Predecessor did not reproduce the orphan race')
            require(case['holderTransactionObserved'], 'Predecessor reproduction lacked overlapping transactions')
            receipt['passed'] = True
            return 0
        require(case['contentionObserved'] and saved(result) and state == {'models': 0, 'children': 0},
                'Writer-first delete must serialize and remove the committed child')

        model, child = str(uuid.uuid4()), str(uuid.uuid4())
        setup_model(model)
        case, result = compete('delete-first-insert', model_delete(model), process_create(child, model),retry=False)
        case['after'] = counts(model)
        require(case['contentionObserved'] and not saved(result) and case['after'] == {'models': 0, 'children': 0},
                'Delete-first insert must reject without orphaning a member')

        # Existing actor fences run before the new membership trigger. Cover
        # nonempty deletion and same-key reinsertion through both actor paths.
        for label, reuse_key, writer in (
            ('nonempty-delete-first-distinct-own-insert',False,actor),
            ('nonempty-delete-first-same-own-key',True,actor),
            ('nonempty-delete-first-same-foreign-key',True,other_actor),
        ):
            model, child = str(uuid.uuid4()), str(uuid.uuid4())
            setup_model(model)
            c.begin(actor)
            require(saved(c.command(process_create(child,model))), 'Nonempty bundle setup failed')
            c.query('commit;')
            destination = child if reuse_key else str(uuid.uuid4())
            case, result = compete(label,model_delete(model),process_create(destination,model),
                                   retry=False,second_actor=writer)
            case['after'] = counts(model)
            require(case['contentionObserved'] and busy(result) and case['after']=={'models':0,'children':0},
                    'Nonempty deletion must reject overlapping insertion without an orphan')

        # Joining an existing standalone Process uses the normal draft-save API.
        model, child = str(uuid.uuid4()), str(uuid.uuid4())
        setup_model(model)
        c.begin(actor)
        require(saved(c.command(process_create(child, None))), 'Standalone Process setup failed')
        c.query('commit;')
        attach = ("select api.cmd_dataset_save_draft('processes',"+literal(child)
                  +"::uuid,'01.00.000',"+literal(json.dumps(document('processDataSet','01.00.000')))
                  +"::jsonb,"+literal(model)+"::uuid,true,'{}'::jsonb,'01.00.000')")
        case, result = compete('relink-first-delete', attach, model_delete(model))
        case['after'] = counts(model)
        require(case['contentionObserved'] and saved(result) and case['after'] == {'models': 0, 'children': 0},
                'Relinked member must enter the post-wait deletion set')

        model = str(uuid.uuid4())
        setup_model(model)
        setup_model(model, '02.00.000')
        case, result = compete('different-version-progress', model_delete(model),
                               process_create(str(uuid.uuid4()), model, '02.00.000','02.00.000'))
        require(not case['contentionObserved'] and saved(result) and counts(model,'02.00.000') == {'models':1,'children':1},
                'Different Model versions must progress independently')

        model = str(uuid.uuid4())
        setup_model(model)
        case, result = compete('compatible-writers', process_create(str(uuid.uuid4()),model),
                               process_create(str(uuid.uuid4()),model),second_actor=other_actor)
        require(not case['contentionObserved'] and saved(result) and counts(model) == {'models':1,'children':2},
                'Compatible same-key Process insertions must progress together')

        # An admitted child may precede a genuine legacy parent. Creating that
        # parent is supported, while deletion must respect the in-flight child.
        model = str(uuid.uuid4())
        a.begin(actor)
        require(saved(a.command(process_create(str(uuid.uuid4()),model))), 'Legacy child setup failed')
        b.begin(actor)
        require(saved(b.command(model_create(model))), 'Concurrent legacy parent creation failed')
        b.query('commit;')
        c.begin(actor)
        collision = c.command(model_delete(model))
        c.query('rollback;')
        holder_open = c.scalar(f"select state='idle in transaction' from pg_stat_activity where pid={a.pid};") == 't'
        require(holder_open and busy(collision) and counts(model)=={'models':1,'children':0},
                'New parent deletion must reject the uncommitted legacy membership window')
        a.query('commit;')
        c.begin(actor)
        result = c.command(model_delete(model))
        c.query('commit;')
        require(saved(result) and counts(model)=={'models':0,'children':0},
                'Legacy membership deletion retry must use the fresh committed set')
        receipt['cases'].append({'case':'missing-parent-created-during-member-write',
                                  'distinctBackends':True,'holderTransactionObserved':holder_open,
                                  'initialDeleteSqlstate':collision.get('sqlstate'),
                                  'retryDeletedParentAndChild':True})

        model = str(uuid.uuid4())
        case, result = compete('missing-parent-model-first', model_create(model), process_create(str(uuid.uuid4()),model))
        require(not case['contentionObserved'] and saved(result) and counts(model)=={'models':1,'children':1},
                'Legacy child may commit while a new parent is being created')

        model, child = str(uuid.uuid4()), str(uuid.uuid4())
        setup_model(model)
        parent_before = c.scalar('select to_jsonb(m)::text from public.lifecyclemodels m where id='+literal(model)+';')
        case, result = compete('foreign-member-first-delete', process_create(child,model),model_delete(model),first_actor=other_actor)
        require(case['contentionObserved'] and not saved(result) and result.get('code')=='PROCESS_NOT_FOUND'
                and counts(model)=={'models':1,'children':1}, 'Foreign member must reject the complete deletion retry')
        require(parent_before==c.scalar('select to_jsonb(m)::text from public.lifecyclemodels m where id='+literal(model)+';'),
                'Rejected foreign-member deletion must preserve the parent timestamp and content')

        # JSON synchronization changes the effective fallback key when the
        # Process version changes while model_version remains NULL.
        model, child = str(uuid.uuid4()), str(uuid.uuid4())
        setup_model(model,'02.00.000')
        c.begin(actor)
        require(saved(c.command(process_create(child,model,model_version=None))), 'Fallback Process setup failed')
        c.query('commit;')
        rekey = ("select api.cmd_dataset_save_draft('processes',"+literal(child)
                 +"::uuid,'01.00.000',"+literal(json.dumps(document('processDataSet','02.00.000')))
                 +"::jsonb,null,true,'{}'::jsonb,null)")
        case, result = compete('fallback-version-rekey-first-delete',rekey,model_delete(model,'02.00.000'))
        require(case['contentionObserved'] and saved(result) and counts(model,'02.00.000')=={'models':0,'children':0},
                'The final JSON-derived fallback key must fence a concurrent deletion')

        for isolation in ('repeatable read', 'serializable'):
            model = str(uuid.uuid4())
            setup_model(model)
            case, result = compete(isolation.replace(' ', '-') + '-fails-closed',
                                   process_create(str(uuid.uuid4()), model),
                                   model_delete(model), isolation=isolation)
            require(result.get('sqlstate') == '0A000'
                    and counts(model) == {'models': 1, 'children': 1},
                    f'{isolation} deletion must reject before changing the Model or its members')
        receipt['passed'] = True
        return 0
    finally:
        for session in reversed(sessions):
            session.close()
        if created:
            psql('drop database '+database+' with (force);', 'template1')
            receipt['cleanup'] = psql('select count(*) from pg_database where datname='+literal(database)+';', 'template1') == '0'
        args.receipt.write_text(json.dumps(receipt,indent=2)+'\n')
        print(json.dumps({'passed':receipt['passed'],'cases':len(receipt['cases']),'cleanup':receipt['cleanup']}))


if __name__ == '__main__':
    raise SystemExit(main())
