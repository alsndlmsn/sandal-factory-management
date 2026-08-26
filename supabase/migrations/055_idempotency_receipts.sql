create table if not exists public.idempotency_receipts(
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete cascade,
  idempotency_key text not null,
  operation_name text not null,
  request_hash text not null,
  status text not null default 'claimed' check (status in ('claimed','succeeded','failed','conflict')),
  response_payload jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(actor_id,idempotency_key)
);

create index if not exists idempotency_receipts_created_at_idx on public.idempotency_receipts(created_at desc);
alter table public.idempotency_receipts enable row level security;
revoke all on public.idempotency_receipts from anon, authenticated;

create or replace function public.claim_idempotency_key(
  p_idempotency_key text,
  p_operation_name text,
  p_request_hash text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor uuid := auth.uid();
  v_existing public.idempotency_receipts%rowtype;
  v_inserted public.idempotency_receipts%rowtype;
begin
  if v_actor is null then
    raise exception 'authentication_required' using errcode='42501';
  end if;
  if coalesce(length(trim(p_idempotency_key)),0) < 20 or length(p_idempotency_key) > 255 then
    raise exception 'invalid_idempotency_key' using errcode='22023';
  end if;
  if coalesce(length(trim(p_operation_name)),0) < 2 or length(p_operation_name) > 120 then
    raise exception 'invalid_operation_name' using errcode='22023';
  end if;
  if coalesce(length(trim(p_request_hash)),0) < 16 or length(p_request_hash) > 128 then
    raise exception 'invalid_request_hash' using errcode='22023';
  end if;

  select * into v_existing
  from public.idempotency_receipts
  where actor_id=v_actor and idempotency_key=p_idempotency_key
  for update;

  if found then
    if v_existing.operation_name <> p_operation_name or v_existing.request_hash <> p_request_hash then
      update public.idempotency_receipts
      set status='conflict',completed_at=coalesce(completed_at,now())
      where id=v_existing.id;
      raise exception 'idempotency_conflict' using errcode='P0001';
    end if;
    return jsonb_build_object('claimed',false,'receipt_id',v_existing.id,'status',v_existing.status,'response_payload',v_existing.response_payload);
  end if;

  insert into public.idempotency_receipts(actor_id,idempotency_key,operation_name,request_hash,status)
  values(v_actor,p_idempotency_key,p_operation_name,p_request_hash,'claimed')
  returning * into v_inserted;
  return jsonb_build_object('claimed',true,'receipt_id',v_inserted.id,'status',v_inserted.status);
exception when unique_violation then
  select * into v_existing from public.idempotency_receipts where actor_id=v_actor and idempotency_key=p_idempotency_key;
  if v_existing.operation_name <> p_operation_name or v_existing.request_hash <> p_request_hash then
    raise exception 'idempotency_conflict' using errcode='P0001';
  end if;
  return jsonb_build_object('claimed',false,'receipt_id',v_existing.id,'status',v_existing.status,'response_payload',v_existing.response_payload);
end;
$$;

create or replace function public.complete_idempotency_key(
  p_idempotency_key text,
  p_status text,
  p_response_payload jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_status text := lower(trim(p_status));
  v_response jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode='42501';
  end if;
  if v_status not in ('succeeded','failed','conflict') then
    raise exception 'invalid_idempotency_status' using errcode='22023';
  end if;
  update public.idempotency_receipts
  set status=v_status,response_payload=p_response_payload,completed_at=now()
  where actor_id=auth.uid() and idempotency_key=p_idempotency_key
  returning id,response_payload into v_id,v_response;
  if v_id is null then
    raise exception 'idempotency_receipt_not_found' using errcode='P0002';
  end if;
  return jsonb_build_object('receipt_id',v_id,'status',v_status,'response_payload',v_response);
end;
$$;

grant execute on function public.claim_idempotency_key(text,text,text) to authenticated;
grant execute on function public.complete_idempotency_key(text,text,jsonb) to authenticated;
revoke execute on function public.claim_idempotency_key(text,text,text) from anon, public;
revoke execute on function public.complete_idempotency_key(text,text,jsonb) from anon, public;
