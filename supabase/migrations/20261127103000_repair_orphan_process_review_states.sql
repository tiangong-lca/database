-- #1024. One-time correction for the fixed, audited production cohort.
-- Only the dataset state changes. No approval, rejection or user identity is synthesized.
do $repair$
declare
  -- SHA-256 of UUID/version -> SHA-256 of the audited before image (UTC).
  expected constant jsonb := $manifest$
{
  "1577326bbedcd4703319eb4338abfb56881c9369f3c86b06148ba65adf06acd1": "c29d3663980a80f3a40cd391d07f32628039b5fe24bf4de2bccd61f34d52fb1d",
  "2aea426b00fe9d945ceb2bcf8ee4fe3dbec8c86716df89bd8ad13b902a50c10c": "6ee6c38a62df11f110342b5f35a39827a1a1ea11bf371694d75b7b8c1f4c9929",
  "3d37a79f57a9a28483fa098b52b8a291e01851436136bcbe8b48b40a0e218ade": "a57ada7d1aa807565c7e1a2891cdc284a282ff0c18a11b743b2f1f815c3d5c64",
  "3dbc97b43a552db274a68fffde53f7756e435b324ef179c66a2773d7e19530c4": "abd751aa527036563545b0b938ed288e5a585f5e59880fe64d1e67b31ec006cf",
  "3f37e51af81ce576b3d4b14682cb8a26311331d2a7be91ce777122ceb939554e": "1219fb880e0a141aca0ba83bddf5f6ac48938c841a839b13f4997b800fc78c75",
  "51fb4c9a0a3fce4ad23f9dd269f7a118bff96993b71be40b130ba063513d3ecb": "31d798cc43f7290e71cad802e5c07488a1c0d55ce9b72ce9c8e0393f77a6c2a5",
  "59d756556dab01981c40299a5b5e45f5686e283598227a49822654a377f91199": "9408cf2a6f57b8b33b9976fcfd1169a63d4eb14155c79831e9da65ea371d1506",
  "71614a9d69b80817042247acc37ba72612010fe56946be4bfa7cbbe6912d4274": "dca45e71f3da80202d58d44947a923cf732a0aecb455a962f361b466a7b19b64",
  "727e040f8d88afeae8fcebc67db5922a232b527d59253205f4c5a16064b1b76c": "44fd7aa1b7aa20833e7cef8b377cf77be6abc41c6a94e797b563461c407a7a7f",
  "76a66dd2946cd1de04a568569c86be90da27cf89374f8feb8b4b2317df55eff9": "31b0770968df318d55a4cd3344ea42bd3638d2790616469b4ca9b7657e46c268",
  "7c3a3b30774874fd88a603e104fb9f36b493f701d3e3ebdfb0f90e53cdb2b29f": "a7c79b372ddfdcc4ae946cd8f6ea26ef5f63588bda62d64f6356e8b8085fd801",
  "9cecc8d0bfae135d818c5cd6c1a1fb2d08aa199d9b654da8a7d8d85e47129894": "fa7bff55f5af8aa08b8abf2ddd93158a8f87788b1c95ece4c9bb58f00879123b",
  "b1eb68303cb21eec668c2cb388a30e01ba5a5f7bec494d731b604a71c17678c5": "e9fdc376d398ed8b1aaceab4cabeeb82766ff3e75ddedb113ea652b6aa4b6519",
  "bda60ad08e6eeed5254cd7b639a9cbbca44f1a76b62a189317ec239266e47765": "122916bf078ed23dd082bc597e69c36071e681e71f359dc85217c560d64bcff0",
  "d3567b1f67a856280c4ea8a346c5ed520ec8597c8525d40a7ae99550f692b984": "d98de7da73ac67da8ac6360e6913e4f74a78b26c9794306fe190a3762b7124a8",
  "f7e3e2379071b71b4ae2eab0b5b382c4666062c3be783cf0c7ccf0cc294d4fa5": "84ae75eea7e759391b0cc7d1ae662799b7b6464959ea63f86d95dd3efb25e66a",
  "fbe080b213c529e901f74e217b3b5a553701b3671b40ff4ed62d17f8f70ba825": "893ff31cd73c7a9ff7a20f4d641b180f00327979adbc390686d14b75b1901de2"
}
$manifest$::jsonb;
  item record;
  evidence text;
  selected_ids uuid[] := '{}';
  selected_versions character(9)[] := '{}';
  changed integer;
begin
  if not exists (select 1 from vault.secrets where name = 'project_url') then
    -- Clean local databases have no branch binding. Fail closed on a populated
    -- copy of the cohort without a binding instead of assuming it is local.
    if exists (select 1 from public.processes p where p.state_code = 20 and expected ? encode(sha256(convert_to(p.id::text || '/' || btrim(p.version::text), 'UTF8')), 'hex')) then
      raise exception 'Review repair: target records present without an environment binding';
    end if;
    return;
  end if;
  if (util.dataset_alias_execution_v2_server_context()->>'environment') is distinct from 'production' then
    return;
  end if;

  perform set_config('TimeZone', 'UTC', true);
  perform set_config('lock_timeout', '3s', true);
  -- Hold exact dataset rows in a stable order. Normal submissions also lock
  -- the target version. Check its current reviews after obtaining the lock.
  for item in
    select p.id, p.version, encode(sha256(convert_to(p.id::text || '/' || btrim(p.version::text), 'UTF8')), 'hex') as audit_key
    from public.processes p
    where p.state_code = 20 and expected ? encode(sha256(convert_to(p.id::text || '/' || btrim(p.version::text), 'UTF8')), 'hex')
    order by p.id, p.version
    for update of p
  loop
    if exists (
      select 1 from private.reviews r
      where r.target_table = 'processes' and r.data_id = item.id
        and r.data_version = item.version and r.state_code in (0, 1)
        and r.review_kind in ('root', 'reference')
    ) then
      raise exception 'Review repair: target acquired an active review';
    end if;

    select encode(sha256(convert_to(jsonb_build_array(
      p.id, p.version, p.modified_at, p.review_id, p.reviews, p.model_id, p.model_version,
      p.rule_verification, p.user_id, p.team_id, md5(p.json::text), md5(p.json_ordered::text),
      history.review_digests
    )::text, 'UTF8')), 'hex')
    into strict evidence
    from public.processes p
    cross join lateral (
      select coalesce(jsonb_agg(
        jsonb_build_array(r.id, md5(to_jsonb(r)::text), comments.digest) order by r.id
      ), '[]'::jsonb) as review_digests
      from private.reviews r
      cross join lateral (
        select md5(coalesce(jsonb_agg(to_jsonb(c) order by to_jsonb(c)::text)::text, '[]')) as digest
        from private.comments c where c.review_id = r.id
      ) comments
      where r.review_kind is null and (
        (r.data_id = p.id and r.data_version = p.version and (r.target_table is null or r.target_table = 'processes'))
        or r.id = p.review_id
        or p.reviews @> jsonb_build_array(jsonb_build_object('id', r.id))
        or p.reviews @> jsonb_build_array(jsonb_build_object('review_id', r.id))
        or p.reviews @> jsonb_build_array(r.id::text)
      )
    ) history
    where (p.id, p.version) = (item.id, item.version);
    if evidence is distinct from (expected ->> item.audit_key) then
      raise exception 'Review repair: audited content, metadata or review history changed';
    end if;

    selected_ids := array_append(selected_ids, item.id);
    selected_versions := array_append(selected_versions, item.version);
  end loop;
  if cardinality(selected_ids) <> 17 then
    raise exception 'Review repair: expected all 17 audited versions, found %', cardinality(selected_ids);
  end if;

  -- Enter the same transaction-local review write context as the normal
  -- rejection command, only after the whole fixed cohort has been verified.
  perform set_config('app.review_controlled_write', 'on', true);
  update public.processes p set state_code = 0
  from unnest(selected_ids, selected_versions) as target(id, version)
  where (p.id, p.version) = (target.id, target.version) and p.state_code = 20;
  get diagnostics changed = row_count;
  perform set_config('app.review_controlled_write', 'off', true);

  if changed <> 17 or exists (
    select 1 from unnest(selected_ids, selected_versions) as target(id, version)
    left join public.processes p on (p.id, p.version)=(target.id, target.version)
    where p.state_code is distinct from 0 or exists (
      select 1 from private.reviews r
      where r.target_table = 'processes' and r.data_id = target.id and r.data_version = target.version
        and r.review_kind in ('root', 'reference') and r.state_code in (0,1)
    )
  ) then
    raise exception 'Review repair: failed postcondition for the fixed cohort';
  end if;
end;
$repair$;
