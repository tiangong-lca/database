begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth;
set local statement_timeout = '90s';

select extensions.no_plan();

create temporary table portal_sitemap_capacity_ids (
  ordinal integer primary key,
  id uuid not null unique
) on commit drop;

with candidates as materialized (
  select
    series.ordinal,
    (
      pg_catalog.substr(candidate.hash, 1, 8) || '-' ||
      pg_catalog.substr(candidate.hash, 9, 4) || '-' ||
      pg_catalog.substr(candidate.hash, 13, 4) || '-' ||
      pg_catalog.substr(candidate.hash, 17, 4) || '-' ||
      pg_catalog.substr(candidate.hash, 21, 12)
    )::uuid as id
  from pg_catalog.generate_series(1, 400000) as series(ordinal)
  cross join lateral (
    select pg_catalog.md5(
      'portal-sitemap-capacity-v1:' || series.ordinal::text
    ) as hash
  ) as candidate
), bucket_zero as (
  select candidate.id
  from candidates as candidate
  where (
    pg_catalog.get_byte(
      pg_catalog.decode(
        pg_catalog.md5('process:' || candidate.id::text),
        'hex'
      ),
      0
    ) / 4
  ) = 0
  order by candidate.id
  limit 4097
)
insert into portal_sitemap_capacity_ids (ordinal, id)
select pg_catalog.row_number() over (order by bucket_zero.id)::integer,
  bucket_zero.id
from bucket_zero;

select extensions.is(
  (select pg_catalog.count(*) from portal_sitemap_capacity_ids),
  4097::bigint,
  'the deterministic capacity fixture contains 4097 unique bucket-zero identities'
);

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_sitemap_manifest_v1() -> 'shards'
  ),
  64,
  'the manifest remains fixed at 64 descriptors on an empty projection'
);

grant select on portal_sitemap_capacity_ids to api_internal_executor;
grant api_internal_executor to postgres;
set local role api_internal_executor;

insert into private.portal_catalog_search_rows_v2 (
  dataset_kind,
  id,
  version,
  state_code,
  modified_at,
  card,
  document,
  projection_contract_version
)
select
  'process',
  fixture.id,
  '01.00.000',
  100,
  '2026-08-27 13:50:00+00'::timestamptz +
    fixture.ordinal * interval '1 millisecond',
  pg_catalog.jsonb_build_object(
    'document', 'sitemap capacity fixture',
    'accessLevel', 'metadata_only',
    'geography', pg_catalog.jsonb_build_object('code', null),
    'classifications', '[]'::jsonb
  ),
  'sitemap capacity fixture',
  2
from portal_sitemap_capacity_ids as fixture
where fixture.ordinal <= 4096;

reset role;
revoke api_internal_executor from postgres;

select extensions.is(
  (
    select pg_catalog.count(*)
    from private.portal_catalog_facet_rows_v1
    where (
      pg_catalog.get_byte(
        pg_catalog.decode(
          pg_catalog.md5(dataset_kind || ':' || id::text),
          'hex'
        ),
        0
      ) / 4
    ) = 0
  ),
  4096::bigint,
  'existing projection writers synchronously populate a full 4096-item shard'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from private.portal_sitemap_rows_v1
    where shard_no = 0
      and contract_version = 1
  ),
  4096::bigint,
  'the exact-version sitemap projection contains one row per visible version'
);

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_sitemap_shard_v1(
      api.portal_sitemap_manifest_v1() #>>
        '{shards,0,shardCursor}'
    ) -> 'items'
  ),
  4096,
  'the hard-cap shard returns every latest visible identity without truncation'
);

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_sitemap_shard_v1(
      api.portal_sitemap_manifest_v1() #>>
        '{shards,1,shardCursor}'
    ) -> 'items'
  ),
  0,
  'an unrelated fixed shard remains independently readable and empty'
);

grant api_internal_executor to postgres;
set local role api_internal_executor;

insert into private.portal_catalog_search_rows_v2 (
  dataset_kind,
  id,
  version,
  state_code,
  modified_at,
  card,
  document,
  projection_contract_version
)
select
  'process',
  fixture.id,
  '02.00.000',
  200,
  '2026-08-27 14:00:00+00',
  pg_catalog.jsonb_build_object(
    'document', 'sitemap capacity newer visible version',
    'accessLevel', 'metadata_only',
    'geography', pg_catalog.jsonb_build_object('code', null),
    'classifications', '[]'::jsonb
  ),
  'sitemap capacity newer visible version',
  2
from portal_sitemap_capacity_ids as fixture
where fixture.ordinal = 1;

reset role;
revoke api_internal_executor from postgres;

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_sitemap_shard_v1(
      api.portal_sitemap_manifest_v1() #>>
        '{shards,0,shardCursor}'
    ) -> 'items'
  ),
  4096,
  'an additional visible version does not consume another latest-identity slot'
);

select extensions.is(
  (
    select item.value #>> '{key,version}'
    from pg_catalog.jsonb_array_elements(
      api.portal_sitemap_shard_v1(
        api.portal_sitemap_manifest_v1() #>>
          '{shards,0,shardCursor}'
      ) -> 'items'
    ) as item(value)
    where item.value #>> '{key,id}' = (
      select id::text
      from portal_sitemap_capacity_ids
      where ordinal = 1
    )
  ),
  '02.00.000',
  'the shard returns only the latest visible exact version for an identity'
);

grant api_internal_executor to postgres;
set local role api_internal_executor;

insert into private.portal_catalog_search_rows_v2 (
  dataset_kind,
  id,
  version,
  state_code,
  modified_at,
  card,
  document,
  projection_contract_version
)
select
  'process',
  fixture.id,
  '01.00.000',
  100,
  '2026-08-27 14:10:00+00',
  pg_catalog.jsonb_build_object(
    'document', 'sitemap capacity overflow identity',
    'accessLevel', 'metadata_only',
    'geography', pg_catalog.jsonb_build_object('code', null),
    'classifications', '[]'::jsonb
  ),
  'sitemap capacity overflow identity',
  2
from portal_sitemap_capacity_ids as fixture
where fixture.ordinal = 4097;

reset role;
revoke api_internal_executor from postgres;

select extensions.is(
  (
    select pg_catalog.count(*)
    from private.portal_catalog_facet_rows_v1
    where (
      pg_catalog.get_byte(
        pg_catalog.decode(
          pg_catalog.md5(dataset_kind || ':' || id::text),
          'hex'
        ),
        0
      ) / 4
    ) = 0
  ),
  4098::bigint,
  'the 4097th latest identity is accepted and an existing second version is retained'
);

select extensions.is(
  (
    select pg_catalog.count(*)
    from private.portal_sitemap_rows_v1
    where shard_no = 0
      and contract_version = 1
  ),
  4098::bigint,
  'capacity overflow and retained history are recorded without blocking writers'
);

select extensions.throws_ok(
  pg_catalog.format(
    'select api.portal_sitemap_shard_v1(%L)',
    api.portal_sitemap_manifest_v1() #>>
      '{shards,0,shardCursor}'
  ),
  'P0001',
  'portal sitemap unavailable',
  'capacity overflow fails only the public shard read instead of truncating it'
);

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_sitemap_shard_v1(
      api.portal_sitemap_manifest_v1() #>>
        '{shards,1,shardCursor}'
    ) -> 'items'
  ),
  0,
  'capacity overflow in one shard does not disable unrelated shards'
);

grant api_internal_executor to postgres;
set local role api_internal_executor;

delete from private.portal_catalog_search_rows_v2
where dataset_kind = 'process'
  and id = (
    select id
    from portal_sitemap_capacity_ids
    where ordinal = 4097
  )
  and version = '01.00.000';

reset role;
revoke api_internal_executor from postgres;

select extensions.is(
  pg_catalog.jsonb_array_length(
    api.portal_sitemap_shard_v1(
      api.portal_sitemap_manifest_v1() #>>
        '{shards,0,shardCursor}'
    ) -> 'items'
  ),
  4096,
  'removing the overflow identity immediately restores the exact bounded shard'
);

grant api_internal_executor to postgres;
set local role api_internal_executor;

delete from private.portal_catalog_search_rows_v2
where dataset_kind = 'process'
  and id = (
    select id
    from portal_sitemap_capacity_ids
    where ordinal = 1
  )
  and version = '02.00.000';

reset role;
revoke api_internal_executor from postgres;

select extensions.is(
  (
    select item.value #>> '{key,version}'
    from pg_catalog.jsonb_array_elements(
      api.portal_sitemap_shard_v1(
        api.portal_sitemap_manifest_v1() #>>
          '{shards,0,shardCursor}'
      ) -> 'items'
    ) as item(value)
    where item.value #>> '{key,id}' = (
      select id::text
      from portal_sitemap_capacity_ids
      where ordinal = 1
    )
  ),
  '01.00.000',
  'deleting the latest visible version exposes its retained exact predecessor'
);

select extensions.ok(
  pg_catalog.octet_length(
    api.portal_sitemap_shard_v1(
      api.portal_sitemap_manifest_v1() #>>
        '{shards,0,shardCursor}'
    )::text
  ) < 2 * 1024 * 1024,
  'the maximum JSON shard remains below its explicit 2 MiB database budget'
);

select extensions.ok(
  api.portal_sitemap_shard_v1(
    api.portal_sitemap_manifest_v1() #>>
      '{shards,0,shardCursor}'
  )::text !~
    'json|document|card|actor|team|review|embedding|credential|locator|bucket',
  'a maximum shard exposes only locator-free sitemap identities and timestamps'
);

select * from extensions.finish();
rollback;
