-- READ-ONLY PREFLIGHT for migration 20261114000200_auth_owner_recovery.sql.
--
-- This file is inspection material only. It is not a migration and must not be
-- pasted into a write session. Confirm in the Supabase dashboard that the
-- selected project is the dedicated AI Trading Scanner project before running
-- these SELECT statements. Review every result before separately approving any
-- migration. No secrets, candle values, symbols, or result payloads are emitted.
--
-- Every statement below is SELECT-only. The query_to_xml calls contain fixed,
-- read-only aggregate SELECT strings and are guarded by to_regclass so missing
-- tables do not abort the script.

-- 1. Connection identity. Confirm this database against the approved project
-- dashboard; this query cannot independently establish project ownership.
select current_database() as database_name,
       current_user as executing_role,
       current_schema() as current_schema,
       current_setting('server_version') as server_version,
       inet_server_addr()::text as server_address;

-- 2. Required Supabase roles. Missing roles block this Supabase-specific SQL.
select expected.role_name,
       roles.oid is not null as role_exists,
       roles.rolsuper as is_superuser,
       roles.rolbypassrls as bypasses_rls
from (values ('anon'), ('authenticated'), ('service_role')) as expected(role_name)
left join pg_catalog.pg_roles as roles on roles.rolname = expected.role_name
order by expected.role_name;

-- 3. Table existence, owner and RLS state. A missing base table means the
-- expected 20261114000100 migration/schema has not been established.
with expected(table_name) as (
  values ('scanner_runs'), ('scanner_candidates'), ('scanner_tasks'),
         ('scanner_candles'), ('scanner_results'), ('scanner_api_limits')
)
select expected.table_name,
       relation.oid is not null as table_exists,
       case when relation.oid is not null then pg_catalog.pg_get_userbyid(relation.relowner) end as table_owner,
       relation.relrowsecurity as rls_enabled,
       relation.relforcerowsecurity as rls_forced,
       case relation.relkind
         when 'r' then 'TABLE'
         when 'p' then 'PARTITIONED_TABLE'
         when 'v' then 'VIEW'
         when 'm' then 'MATERIALIZED_VIEW'
         when 'f' then 'FOREIGN_TABLE'
         when 'S' then 'SEQUENCE'
         when 'i' then 'INDEX'
         when 'I' then 'PARTITIONED_INDEX'
         else case when relation.oid is null then 'ABSENT' else 'OTHER' end
       end as relation_kind,
       relation.relkind as relation_kind_code
from expected
left join pg_catalog.pg_namespace as namespace on namespace.nspname = 'public'
left join pg_catalog.pg_class as relation
  on relation.relnamespace = namespace.oid and relation.relname = expected.table_name
order by expected.table_name;

-- 4. Expected base and migration columns. Each expected column is reported as
-- present/absent, including columns introduced only by migration 002.
with expected(table_name, column_name) as (
  values
    ('scanner_runs','id'), ('scanner_runs','status'), ('scanner_runs','settings'),
    ('scanner_runs','exchange_status'), ('scanner_runs','created_at'), ('scanner_runs','updated_at'),
    ('scanner_runs','owner_id'), ('scanner_runs','idempotency_key'),
    ('scanner_candidates','id'), ('scanner_candidates','run_id'), ('scanner_candidates','exchange'),
    ('scanner_candidates','symbol'), ('scanner_candidates','is_selected'), ('scanner_candidates','analysis_status'),
    ('scanner_tasks','id'), ('scanner_tasks','run_id'), ('scanner_tasks','candidate_id'),
    ('scanner_tasks','status'), ('scanner_tasks','attempts'), ('scanner_tasks','locked_at'),
    ('scanner_tasks','max_attempts'), ('scanner_tasks','next_attempt_at'), ('scanner_tasks','lease_token'),
    ('scanner_candles','exchange'), ('scanner_candles','symbol'), ('scanner_candles','timeframe'),
    ('scanner_candles','timestamp_ms'), ('scanner_candles','fetched_at'),
    ('scanner_results','run_id'), ('scanner_results','candidate_id'), ('scanner_results','side'),
    ('scanner_results','algorithm_version'),
    ('scanner_api_limits','scope'), ('scanner_api_limits','subject_hash'),
    ('scanner_api_limits','window_started_at'), ('scanner_api_limits','hit_count')
)
select expected.table_name,
       expected.column_name,
       attribute.attnum is not null as column_exists,
       case when attribute.attnum is not null then pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) end as data_type,
       attribute.attnotnull as not_null
from expected
left join pg_catalog.pg_namespace as namespace on namespace.nspname = 'public'
left join pg_catalog.pg_class as relation
  on relation.relnamespace = namespace.oid and relation.relname = expected.table_name
left join pg_catalog.pg_attribute as attribute
  on attribute.attrelid = relation.oid
 and attribute.attname = expected.column_name
 and attribute.attnum > 0
 and not attribute.attisdropped
order by expected.table_name, expected.column_name;

-- 5. All constraints on the six affected tables, including every CHECK
-- constraint. Definitions and validation state reveal drift without reading
-- table payloads.
select relation.relname as table_name,
       constraint_row.conname as constraint_name,
       constraint_row.contype as constraint_type,
       constraint_row.convalidated as validated,
       pg_catalog.pg_get_constraintdef(constraint_row.oid, true) as definition
from pg_catalog.pg_constraint as constraint_row
join pg_catalog.pg_class as relation on relation.oid = constraint_row.conrelid
join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
where namespace.nspname = 'public'
  and relation.relname in ('scanner_runs','scanner_candidates','scanner_tasks',
                           'scanner_candles','scanner_results','scanner_api_limits')
  and constraint_row.contype in ('c','p','u','f','x')
order by relation.relname, constraint_row.conname;

-- 6. Expected migration indexes, including their exact definitions when present.
with expected(index_name) as (
  values ('scanner_runs_owner_created_idx'), ('scanner_runs_owner_idempotency_uidx'),
         ('scanner_tasks_due_idx')
)
select expected.index_name,
       index_relation.oid is not null as index_exists,
       index_row.indisunique as is_unique,
       index_row.indisvalid as is_valid,
       index_row.indisready as is_ready,
       pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) as predicate,
       pg_catalog.pg_get_indexdef(index_relation.oid) as definition
from expected
left join pg_catalog.pg_namespace as namespace on namespace.nspname = 'public'
left join pg_catalog.pg_class as index_relation
  on index_relation.relnamespace = namespace.oid and index_relation.relname = expected.index_name
left join pg_catalog.pg_index as index_row on index_row.indexrelid = index_relation.oid
order by expected.index_name;

-- 6b. Every index currently defined on the six target tables. The full index
-- definition includes UNIQUE key/column details; is_unique is also explicit.
select table_relation.relname as table_name,
       index_relation.relname as index_name,
       index_row.indisunique as is_unique,
       index_row.indisprimary as is_primary,
       index_row.indisvalid as is_valid,
       index_row.indisready as is_ready,
       pg_catalog.pg_get_expr(index_row.indpred, index_row.indrelid) as predicate,
       pg_catalog.pg_get_indexdef(index_relation.oid) as definition
from pg_catalog.pg_index as index_row
join pg_catalog.pg_class as table_relation on table_relation.oid = index_row.indrelid
join pg_catalog.pg_namespace as table_namespace on table_namespace.oid = table_relation.relnamespace
join pg_catalog.pg_class as index_relation on index_relation.oid = index_row.indexrelid
where table_namespace.nspname = 'public'
  and table_relation.relname in ('scanner_runs','scanner_candidates','scanner_tasks',
                                 'scanner_candles','scanner_results','scanner_api_limits')
order by table_relation.relname, index_relation.relname;

-- 6a. Migration history, when the Supabase CLI history relation exists. An
-- absent history table is reported rather than referenced directly.
select case when pg_catalog.to_regclass('supabase_migrations.schema_migrations') is null
            then 'HISTORY_TABLE_ABSENT'
            when not exists (
              select 1 from pg_catalog.pg_attribute
              where attrelid = pg_catalog.to_regclass('supabase_migrations.schema_migrations')
                and attname = 'version' and attnum > 0 and not attisdropped
            ) then 'HISTORY_TABLE_VERSION_COLUMN_ABSENT'
            else 'HISTORY_TABLE_PRESENT' end as migration_history_state,
       case when pg_catalog.to_regclass('supabase_migrations.schema_migrations') is null
                  or not exists (
                    select 1 from pg_catalog.pg_attribute
                    where attrelid = pg_catalog.to_regclass('supabase_migrations.schema_migrations')
                      and attname = 'version' and attnum > 0 and not attisdropped
                  ) then null
            else pg_catalog.query_to_xml($q$
              select version from supabase_migrations.schema_migrations
              where version = '20261114000200'
            $q$, false, true, '') end as target_migration_record;

-- 7. RLS policies on affected tables. Existing permissive policies or policies
-- on scanner_api_limits must be reviewed before relying on the migration.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_catalog.pg_policies
where schemaname = 'public'
  and tablename in ('scanner_runs','scanner_candidates','scanner_tasks',
                    'scanner_candles','scanner_results','scanner_api_limits')
order by tablename, policyname;

-- 8. RPC signatures, owner, SECURITY DEFINER flag, pinned search_path and ACL.
-- Rows missing from this catalog result are reported as missing; ACL expansion
-- also shows PUBLIC (grantee OID 0) and any unexpected role grants.
with expected(signature) as (
  values
    ('public.begin_scanner_run(text,uuid,jsonb)'),
    ('public.consume_scanner_rate_limit(text,text,integer,integer)'),
    ('public.claim_scanner_tasks(uuid,text,integer)'),
    ('public.claim_scanner_tasks(uuid,integer)'),
    ('public.complete_scanner_task(uuid,uuid,jsonb,jsonb)'),
    ('public.finish_scanner_task_failure(uuid,uuid,text,boolean,integer)'),
    ('public.reconcile_scanner_run(uuid,text)')
), resolved as (
  select expected.signature, pg_catalog.to_regprocedure(expected.signature) as function_oid
  from expected
)
select resolved.signature,
       procedure.oid is not null as function_exists,
       case when procedure.oid is not null then pg_catalog.pg_get_userbyid(procedure.proowner) end as function_owner,
       procedure.prosecdef as security_definer,
       procedure.proconfig as function_settings,
       procedure.prokind as function_kind,
       case when procedure.oid is not null then pg_catalog.pg_get_function_identity_arguments(procedure.oid) end as identity_arguments,
       case when procedure.oid is not null then pg_catalog.pg_get_function_result(procedure.oid) end as return_type,
       array_agg(distinct
         case when acl_item.grantee = 0 then 'PUBLIC'
              else coalesce(grantee.rolname, acl_item.grantee::text) end
         || ':' || acl_item.privilege_type
       ) filter (where acl_item.grantee is not null) as execute_acl
from resolved
left join pg_catalog.pg_proc as procedure on procedure.oid = resolved.function_oid
left join lateral (
  select expanded.grantee, expanded.privilege_type
  from pg_catalog.aclexplode(
    case when procedure.oid is not null
         then coalesce(procedure.proacl, pg_catalog.acldefault('f', procedure.proowner))
         else null::aclitem[] end
  ) as expanded
) as acl_item on true
left join pg_catalog.pg_roles as grantee on grantee.oid = acl_item.grantee
group by resolved.signature, procedure.oid, procedure.proowner, procedure.prosecdef,
         procedure.proconfig, procedure.prokind
order by resolved.signature;

-- 9. Table ACLs, including implicit/default grants. Service-role access is
-- expected; any anon/authenticated/PUBLIC DML must be investigated.
select relation.relname as table_name,
       case when acl_item.grantee = 0 then 'PUBLIC'
            else coalesce(grantee.rolname, acl_item.grantee::text) end as grantee,
       acl_item.privilege_type,
       acl_item.is_grantable
from pg_catalog.pg_class as relation
join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
cross join lateral pg_catalog.aclexplode(
  coalesce(relation.relacl, pg_catalog.acldefault('r', relation.relowner))
) as acl_item
left join pg_catalog.pg_roles as grantee on grantee.oid = acl_item.grantee
where namespace.nspname = 'public'
  and relation.relname in ('scanner_runs','scanner_candidates','scanner_tasks',
                           'scanner_candles','scanner_results','scanner_api_limits')
order by relation.relname, grantee, acl_item.privilege_type;

-- 10. Aggregate row-state checks. query_to_xml executes only fixed, read-only
-- aggregate SELECT strings and only when the relation exists. Candle/result
-- table sizes are reported below from catalog statistics, not full scans.
select 'scanner_runs' as target,
       case when pg_catalog.to_regclass('public.scanner_runs') is null then 'ABSENT'
            when not exists (
              select 1 from pg_catalog.pg_attribute
              where attrelid = pg_catalog.to_regclass('public.scanner_runs')
                and attname = 'status' and attnum > 0 and not attisdropped
            ) then 'PRESENT_BUT_STATUS_COLUMN_ABSENT'
            else 'PRESENT' end as relation_state,
       case when pg_catalog.to_regclass('public.scanner_runs') is null
                  or not exists (
                    select 1 from pg_catalog.pg_attribute
                    where attrelid = pg_catalog.to_regclass('public.scanner_runs')
                      and attname = 'status' and attnum > 0 and not attisdropped
                  ) then null
            else pg_catalog.query_to_xml($q$
              select status, count(*)::bigint as row_count,
                     count(*) filter (where to_jsonb(run_row)->>'owner_id' is null) as owner_id_missing_or_null,
                     count(*) filter (where to_jsonb(run_row)->>'idempotency_key' is null) as idempotency_key_missing_or_null
              from public.scanner_runs as run_row
              group by status order by status
            $q$, false, true, '') end as grouped_counts;

select 'scanner_runs_nonnull_idempotency_duplicates' as check_name,
       case when pg_catalog.to_regclass('public.scanner_runs') is null then 'NOT_CHECKED_TABLE_ABSENT'
            when not exists (
              select 1 from pg_catalog.pg_attribute
              where attrelid = pg_catalog.to_regclass('public.scanner_runs')
                and attname in ('owner_id','idempotency_key')
                and attnum > 0 and not attisdropped
              group by attrelid having count(distinct attname) = 2
            ) then 'NOT_CHECKED_IDEMPOTENCY_COLUMNS_ABSENT'
            else pg_catalog.query_to_xml($q$
              select count(*)::bigint as duplicate_key_groups
              from (
                select to_jsonb(run_row)->>'owner_id' as owner_value,
                       to_jsonb(run_row)->>'idempotency_key' as key_value
                from public.scanner_runs as run_row
                where to_jsonb(run_row)->>'owner_id' is not null
                  and to_jsonb(run_row)->>'idempotency_key' is not null
                group by to_jsonb(run_row)->>'owner_id', to_jsonb(run_row)->>'idempotency_key'
                having count(*) > 1
              ) as duplicate_keys
            $q$, false, true, '')::text end as aggregate_result;

select 'scanner_tasks' as target,
       case when pg_catalog.to_regclass('public.scanner_tasks') is null then 'ABSENT'
            when not exists (
              select 1 from pg_catalog.pg_attribute
              where attrelid = pg_catalog.to_regclass('public.scanner_tasks')
                and attname in ('status','attempts','locked_at')
                and attnum > 0 and not attisdropped
              group by attrelid having count(distinct attname) = 3
            ) then 'PRESENT_BUT_REQUIRED_COLUMN_ABSENT'
            else 'PRESENT' end as relation_state,
       case when pg_catalog.to_regclass('public.scanner_tasks') is null
                  or not exists (
                    select 1 from pg_catalog.pg_attribute
                    where attrelid = pg_catalog.to_regclass('public.scanner_tasks')
                      and attname in ('status','attempts','locked_at')
                      and attnum > 0 and not attisdropped
                    group by attrelid having count(distinct attname) = 3
                  ) then null
            else pg_catalog.query_to_xml($q$
              select status, count(*)::bigint as row_count,
                     count(*) filter (where status = 'processing' and locked_at is null) as processing_missing_lock_time,
                     count(*) filter (
                       where status = 'processing'
                         and locked_at < statement_timestamp() - interval '2 minutes'
                     ) as lease_older_than_two_minutes,
                     count(*) filter (
                       where status = 'queued' and case
                         when coalesce(to_jsonb(task_row)->>'max_attempts','4') ~ '^[0-9]{1,9}$'
                           then attempts >= coalesce(to_jsonb(task_row)->>'max_attempts','4')::integer
                         else attempts >= 4
                       end
                     ) as queued_attempts_at_or_over_limit,
                     count(*) filter (
                       where status = 'processing' and case
                         when coalesce(to_jsonb(task_row)->>'max_attempts','4') ~ '^[0-9]{1,9}$'
                           then attempts >= coalesce(to_jsonb(task_row)->>'max_attempts','4')::integer
                         else attempts >= 4
                       end
                     ) as processing_attempts_at_or_over_limit,
                     count(*) filter (
                       where status = 'retry_wait' and case
                         when coalesce(to_jsonb(task_row)->>'max_attempts','4') ~ '^[0-9]{1,9}$'
                           then attempts >= coalesce(to_jsonb(task_row)->>'max_attempts','4')::integer
                         else attempts >= 4
                       end
                     ) as retry_wait_attempts_at_or_over_limit,
                     count(*) filter (
                       where status = 'retry_wait'
                         and to_jsonb(task_row)->>'next_attempt_at' is null
                     ) as retry_wait_missing_due_time,
                     count(*) filter (
                       where status = 'processing'
                         and to_jsonb(task_row)->>'lease_token' is null
                     ) as processing_missing_lease_token
              from public.scanner_tasks as task_row
              group by status order by status
            $q$, false, true, '') end as grouped_counts;

select 'scanner_candidates' as target,
       case when pg_catalog.to_regclass('public.scanner_candidates') is null then 'ABSENT'
            when not exists (
              select 1 from pg_catalog.pg_attribute
              where attrelid = pg_catalog.to_regclass('public.scanner_candidates')
                and attname in ('analysis_status','is_selected')
                and attnum > 0 and not attisdropped
              group by attrelid having count(distinct attname) = 2
            ) then 'PRESENT_BUT_REQUIRED_COLUMN_ABSENT'
            else 'PRESENT' end as relation_state,
       case when pg_catalog.to_regclass('public.scanner_candidates') is null
                  or not exists (
                    select 1 from pg_catalog.pg_attribute
                    where attrelid = pg_catalog.to_regclass('public.scanner_candidates')
                      and attname in ('analysis_status','is_selected')
                      and attnum > 0 and not attisdropped
                    group by attrelid having count(distinct attname) = 2
                  ) then null
            else pg_catalog.query_to_xml($q$
              select analysis_status, count(*)::bigint as row_count,
                     count(*) filter (where is_selected) as selected_rows
              from public.scanner_candidates
              group by analysis_status order by analysis_status
            $q$, false, true, '') end as grouped_counts;

select 'scanner_api_limits' as target,
       case when pg_catalog.to_regclass('public.scanner_api_limits') is null then 'ABSENT'
            when not exists (
              select 1 from pg_catalog.pg_attribute
              where attrelid = pg_catalog.to_regclass('public.scanner_api_limits')
                and attname in ('scope','window_started_at')
                and attnum > 0 and not attisdropped
              group by attrelid having count(distinct attname) = 2
            ) then 'PRESENT_BUT_REQUIRED_COLUMN_ABSENT'
            else 'PRESENT' end as relation_state,
       case when pg_catalog.to_regclass('public.scanner_api_limits') is null
                  or not exists (
                    select 1 from pg_catalog.pg_attribute
                    where attrelid = pg_catalog.to_regclass('public.scanner_api_limits')
                      and attname in ('scope','window_started_at')
                      and attnum > 0 and not attisdropped
                    group by attrelid having count(distinct attname) = 2
                  ) then null
            else pg_catalog.query_to_xml($q$
              select scope, count(*)::bigint as row_count,
                     count(*) filter (where window_started_at < statement_timestamp() - interval '1 day') as older_than_cleanup_window
              from public.scanner_api_limits
              group by scope order by scope
            $q$, false, true, '') end as grouped_counts;

-- 11. Approximate catalog row estimates for all expected tables, including
-- scanner_candles and scanner_results. n_live_tup/n_dead_tup are statistics
-- estimates (potentially stale), not exact counts and do not scan table rows.
with expected(table_name) as (
  values ('scanner_runs'), ('scanner_candidates'), ('scanner_tasks'),
         ('scanner_candles'), ('scanner_results'), ('scanner_api_limits')
)
select expected.table_name,
       coalesce(statistics.n_live_tup, 0)::bigint as estimated_live_rows,
       coalesce(statistics.n_dead_tup, 0)::bigint as estimated_dead_rows,
       statistics.last_analyze,
       statistics.last_autoanalyze
from expected
left join pg_catalog.pg_stat_user_tables as statistics
  on statistics.schemaname = 'public' and statistics.relname = expected.table_name
order by expected.table_name;

