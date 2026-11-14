# 05. 신규 migration 정적 검토 및 read-only preflight 보고서

- 기준일: 2026-11-14
- 지시서: `instructions/05-migration-static-review.md`
- 대상: `C:\\Users\\PC1\\ai-trading-scanner`
- 검토 대상 migration: `supabase/migrations/20261114000200_auth_owner_recovery.sql`
- 기존 migration: `supabase/migrations/20261114000100_scanner.sql`
- preflight 자료: `supabase/preflight/20261114000200_auth_owner_recovery_preflight.sql`
- 결론: **원격 DB 적용 보류 (BLOCKER: 대상 DB 상태와 기존 행을 아직 확인하지 않음)**

## 범위와 확인 방법

최신 WORKFLOW, STATUS, 05번 지시서, 04번 구현 보고서를 확인했습니다. 작업 전 코드 프로젝트에는 기존 사용자 변경이 있었습니다. 코드, migration, 환경변수, package, 기존 파일은 수정하지 않았고, 승인된 새 read-only preflight SQL 파일만 만들었습니다.

검토는 두 migration, Supabase 호출 helper, analysis/auth API route, rate limiter와 TypeScript 타입을 정적으로 대조했습니다. 원격 Supabase 접속, SQL 실행/파서 검증, migration 적용, DB 쿼리, 환경변수 접근은 하지 않았습니다. 따라서 아래는 코드 구조에 대한 정적 평가이며 실제 schema 상태의 확인 결과가 아닙니다.

## 검토 결과

| 항목 | 판정 | 근거와 적용 조건 |
| --- | --- | --- |
| 기존 schema 및 status 제약 | **BLOCKER — 조건부 적용 차단** | 00100의 테이블·기본 column과 00200의 변경은 구조상 이어집니다. 다만 새 status constraint가 허용하지 않는 기존 값이 있으면 constraint 추가가 실패합니다. 이름이 같은 추가 사용자 제약은 drop/re-add 과정에서 사라질 수 있으므로 definition 비교가 필요합니다. |
| owner-less 기존 run | **WARNING** | `owner_id`는 nullable로 추가되고 기존 행은 자동 backfill되지 않습니다. 기존 run은 새 owner 조건 API에서 조회/실행되지 않습니다. 이를 허용할지, 별도 승인된 owner 할당 절차가 필요한지 결정해야 합니다. |
| idempotency unique index | **PASS — schema 확인 조건** | partial unique index와 `begin_scanner_run`의 conflict predicate가 일치합니다. 둘 다 non-null일 때만 owner/key 중복을 막고, 신규 RPC는 null key를 거부합니다. 같은 이름의 다른 index, 기존 column type drift, 이미 존재하는 중복 값이 있으면 `IF NOT EXISTS`가 이를 고치지 않거나 index 생성이 실패할 수 있습니다. |
| TypeScript ↔ RPC 인자/반환 | **PASS** | `begin_scanner_run`, `consume_scanner_rate_limit`, owner 인자형 `claim_scanner_tasks`, `complete_scanner_task`, `finish_scanner_task_failure`, `reconcile_scanner_run`의 이름/인자형/사용 반환 필드가 `lib/scanner/supabase.ts`와 대조됩니다. `ClaimedTask`의 `max_attempts`와 `lease_token`, run의 `completed_with_errors`도 대응합니다. |
| SECURITY DEFINER 및 search_path | **PASS — function owner 확인 조건** | 새 함수는 `search_path = pg_catalog`으로 고정하고 대상 테이블을 `public.`으로 schema-qualified 참조합니다. `CREATE OR REPLACE`는 기존 함수 owner를 바꾸지 않으므로, 예상한 migration owner가 아닌 기존 함수는 적용 blocker입니다. |
| EXECUTE 권한 회수/부여 | **PASS — 잔여 ACL 확인 조건** | 신규 RPC에서 PUBLIC/anon/authenticated 권한을 회수하고 service_role에 실행 권한을 줍니다. 기존 owner-less `claim_scanner_tasks(uuid, integer)`는 service_role 권한도 회수합니다. 기존 함수의 예상 밖 role ACL은 자동 제거하지 않으며 preflight에서 검토해야 합니다. |
| RLS/table ACL | **WARNING — 기존 객체 조건** | 새 limiter table은 RLS를 켜고 service_role에 table 권한을 줍니다. 기존 동명 table이 있으면 `CREATE TABLE IF NOT EXISTS`가 schema를 교정하지 않고 기존 policy와 ACL도 자동 제거되지 않습니다. PUBLIC/anon/authenticated 접근이나 예상 밖 policy/grant가 있으면 blocker입니다. |
| limiter 원자성 및 성장 | **PASS / WARNING** | `(scope, subject_hash)` PK와 단일 UPSERT가 window 경계의 동시 요청을 직렬화합니다. scope/key/한도 입력을 검증하고 오래된 limiter 행을 호출당 최대 100개 삭제합니다. cleanup은 요청 때만 실행되므로 유입이 cleanup보다 빠르면 오래된 bucket이 누적될 수 있습니다. |
| task claim 및 stale 상태 | **BLOCKER — 기존 task 조건** | owner/run 검증, `FOR UPDATE SKIP LOCKED`, retry due time, 최대 attempt와 lease 조건은 존재합니다. 그러나 4회 이상 시도한 기존 `queued` 행은 claim 조건에 걸리지 않고 terminal 처리도 되지 않아 stuck될 수 있습니다. `processing`인데 `locked_at IS NULL`인 행은 만료 처리/재claim이 되지 않습니다. `retry_wait`에서 `next_attempt_at`이 null인 행도 영구 대기합니다. 해당 집계가 0인지 확인해야 합니다. |
| lease fencing | **PASS / WARNING** | complete와 failure RPC 모두 current `lease_token`을 확인하고 task 행을 잠근 뒤 변경합니다. 오래된 token은 재claim 뒤 거부됩니다. 단, complete RPC는 JSON의 candle/result 행이 현재 task의 run/candidate/exchange/symbol과 일치하는지 검증하지 않습니다. service_role 전용이고 현재 TypeScript 호출부는 같은 task에서 만든 행을 전달하지만, DB 단의 payload-task 일치 검증을 보강하는 편이 안전합니다. |
| run reconciliation | **PASS** | run 행을 잠근 뒤 task 상태를 집계합니다. retry_wait는 queued 진행 중으로 취급하고, 빈 task run은 completed, 혼합 성공/실패는 completed_with_errors, 전부 실패는 failed로 반환합니다. 여러 reconciliation은 run row lock으로 직렬화됩니다. |
| 재실행/부분 실패 | **WARNING** | add column/index/table의 `IF NOT EXISTS`와 `CREATE OR REPLACE`는 존재만 확인하며 같은 이름의 잘못된 정의를 고치지 않습니다. status constraint는 drop/re-add합니다. 파일은 명시적 transaction block을 선언하지 않으므로 migration 실행 도구가 파일 단위 원자성/실패 rollback을 보장하는지 사전에 확인해야 합니다. |

### 적용 판단

현재 **실제 대상 DB와 기존 데이터가 미확인**이므로 migration 적용은 BLOCKED입니다. 다음 조건을 전부 만족하기 전에는 실행하지 마십시오.

1. Dashboard에서 전용 AI Trading Scanner Supabase project임을 직접 확인하고, preflight를 읽기 전용 권한으로 실행합니다.
2. 기본 scanner table/column type, constraint, unique key, 함수 signature/owner/search_path/ACL 및 RLS/policy가 00100과 예상 상태에 부합해야 합니다.
3. idempotency 중복 group은 0이어야 합니다. 기존 status 외 값, 4회 이상 시도한 queued task, locked_at 없는 processing task, due time 없는 retry_wait task가 있으면 적용 전에 별도 복구 계획이 필요합니다.
4. 이전 application worker를 중지하고 active task 처리가 끝나도록 drain/wait합니다. 기존 processing task에는 migration 전 lease token이 없을 수 있습니다.
5. migration tool의 transaction 처리와 backup/restore 방안을 확인합니다. SQL Editor에 조각별로 수동 실행하지 않습니다.
6. 기존 owner-less run을 접근 불가로 남길지 별도 승인된 보존/owner 부여 절차가 필요한지 결정합니다.
7. preflight report와 blocker 해결을 검토한 뒤, migration 적용은 별도 승인과 실행 단계에서만 수행합니다.

## Read-only preflight SQL

파일: `supabase/preflight/20261114000200_auth_owner_recovery_preflight.sql`

실행 순서는 파일의 section 1–11입니다: 연결 identity/role → relation/RLS/column → constraints/index/history → policy → function ACL → table ACL → 민감값 없는 aggregate → approximate row estimate.

스크립트는 catalog 조회와 SELECT/WITH만 포함합니다. relation은 `to_regclass`로, optional column은 `pg_attribute`로 확인하고, data aggregate는 존재할 때만 고정된 SELECT 문자열을 `query_to_xml`에 전달합니다. 전체 row/payload, symbol, subject hash, key는 반환하지 않습니다. 정확한 데이터 분포는 aggregate XML 결과에서 status별 건수만 확인합니다.

자체 정적 점검:

- 금지된 변경 statement 시작: **0**
- SELECT/WITH query 시작: **43** (고정 query_to_xml 내부 SELECT 포함)
- catalog-guarded query_to_xml: **8**
- `to_regclass` guard: **27**
- trailing whitespace: **0**, 파일 끝 newline 있음
- 이 점검은 텍스트 audit이며 SQL parser 또는 DB 실행 검증이 아닙니다.

해석 시 `HISTORY_TABLE_ABSENT`는 migration ledger를 확인할 수 없다는 뜻이지 자동으로 미적용을 증명하지 않습니다. relation/required column absent, 예상 밖 function owner/ACL, invalid index, custom status constraint, 제한되지 않은 PUBLIC/anon/authenticated ACL, duplicate key group 또는 stuck task count가 있으면 보류합니다. `estimated_live_rows`는 통계치이므로 exact aggregate XML과 혼동하지 않습니다.

## Rollback 및 운영 영향

migration은 기존 run을 삭제하거나 owner를 추측해 채우지 않습니다. 대신 새 run/task 열·상태·함수·권한을 추가하고, legacy claim 함수 권한을 회수합니다. 적용 후 새 데이터가 생긴 상태에서 columns/table/status를 되돌리면 소유 정보, retry/lease 상태, limiter rows 및 `completed_with_errors` 상태가 손실되거나 구 앱이 동작하지 않을 수 있습니다. 단순한 down SQL을 가정하지 말고 적용 전 backup/restore 계획을 마련하고, 실패는 forward correction으로 복구하는 것을 우선 검토하십시오.

## 완료 확인

- 생성 파일: `supabase/preflight/20261114000200_auth_owner_recovery_preflight.sql`
- 문서 파일: 이 보고서와 `handover/STATUS.md`
- 기존 코드/migration 및 사용자의 working tree는 수정하지 않았습니다. stage/commit하지 않았습니다.
- 원격 Supabase 접속/쿼리, migration 적용, 환경변수 변경은 하지 않았습니다.
- 코드 전용 build/test는 실행하지 않았습니다. 이번 단계는 정적 검토와 SQL artifact 작성이며, DB SQL 역시 실행하지 않았습니다.
