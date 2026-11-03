#!/usr/bin/env python3
"""Check the bounded review schema projection and migration embedding offline.

Optionally verify against an installed SDK 0.5.0 runtime-assets/tidas/schemas
folder. No dependency installation or remote/database operation is performed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'contracts/review/metadata.v1.json'
MIGRATION = ROOT / 'supabase/migrations/20261103110000_review_metadata_guard.sql'


def project(assets):
    source = {'package': '@tiangong-lca/tidas-sdk', 'version': '0.5.0', 'sha256': {}}
    result = {'source': source, 'schemas': {}}
    for table, filename, root in [
        ('processes', 'tidas_processes.json', 'processDataSet'),
        ('lifecyclemodels', 'tidas_lifecyclemodels.json', 'lifeCycleModelDataSet'),
    ]:
        documents, definitions = {}, {}

        def document(name):
            if name not in documents:
                assert Path(name).name == name, 'only local schema assets are allowed'
                raw = (assets / name).read_bytes()
                source['sha256'][name] = hashlib.sha256(raw).hexdigest()
                documents[name] = json.loads(raw)
            return documents[name]

        def convert(value, current):
            if isinstance(value, list):
                return [convert(item, current) for item in value]
            if not isinstance(value, dict):
                return value
            output = {}
            for key, item in value.items():
                if key in ('description', 'title', '$id', '$schema'):
                    continue
                if key == '$ref':
                    target, pointer = item.split('#')
                    target = target or current
                    assert pointer.startswith('/$defs/')
                    name = target.removesuffix('.json') + '_' + pointer.split('/')[-1]
                    if name not in definitions:
                        definitions[name] = {}
                        referred = document(target)
                        for part in pointer.lstrip('/').split('/'):
                            referred = referred[part]
                        definitions[name] = convert(referred, target)
                    output[key] = '#/$defs/' + name
                else:
                    output[key] = convert(item, current)
            return output

        metadata = document(filename)['properties'][root]['properties']['modellingAndValidation']['properties']
        properties = {key: convert(metadata[key], filename)
                      for key in ('validation', 'complianceDeclarations')}
        result['schemas'][table] = {
            '$schema': 'http://json-schema.org/draft-07/schema#',
            'type': 'object', 'properties': properties, '$defs': definitions,
        }
    return result


def check():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-assets', type=Path)
    args = parser.parse_args()
    contract = json.loads(CONTRACT.read_text())
    embedded = re.findall(r'\$contract\$(.*?)\$contract\$', MIGRATION.read_text(), re.S)
    assert len(embedded) == 1
    assert json.loads(embedded[0]) == contract['schemas'], 'migration schema drift'
    for schema in contract['schemas'].values():
        def references(value):
            if isinstance(value, dict):
                if '$ref' in value:
                    reference = value['$ref']
                    assert reference.startswith('#/$defs/')
                    assert reference.removeprefix('#/$defs/') in schema['$defs']
                for item in value.values():
                    references(item)
            elif isinstance(value, list):
                for item in value:
                    references(item)
        references(schema)
    if args.sdk_assets:
        assert project(args.sdk_assets) == contract, 'SDK source/projection drift'
    print('Review metadata schemas: local references and migration parity verified.')


if __name__ == '__main__':
    check()
