# Supabase 연결 사전 점검 보고서

- 작업명: Supabase 신규 프로젝트 연결 사전 점검
- 기준일: 2026-11-14
- 코드 프로젝트: `C:\\Users\\PC1\\ai-trading-scanner`
- 검토 범위: Supabase 사용 경로, 신규 프로젝트 schema/migration, project isolation, secret handling, current pricing
- 결론: 전용 Supabase 프로젝트로 분리하는 구성이 적합합니다. 이번 단계에서는 프로젝트 생성/연결, 원격 접속/query, migration 적용, 환경변수 변경을 하지 않았습니다.

## 수행 범위 및 한계

최신 `instructions/WORKFLOW.md`, `handover/STATUS.md`, `reports/README.md`를 읽었습니다. 로컬 코드는 정적 검색과 migration 파일 읽기로만 확인했습니다. 환경변수 값, 비밀번호, API 키, Supabase Service Role Key는 읽거나 기록하지 않았습니다. 기존 가족 학습관리 또는 WORD MASTER 프로젝트에 접근하지 않았습니다.

현재 작업 트리는 이미 변경된 app/package/API/lib/migration/test 파일을 포함하고 있었습니다. 이번 점검 중 코드 프로젝트 파일은 수정하지 않았습니다. SQL을 실행하거나 Supabase에 연결하지 않았습니다.

## Supabase 사용 위치

현재 앱은 `@supabase/supabase-js` SDK가 아니라 서버 측 REST/RPC용 `fetch` wrapper를 사용합니다.

- `lib/scanner/supabase.ts`: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` 설정 여부 확인, `/rest/v1` CRUD 요청 및 `/rpc` 호출, helper 함수가 위치합니다. 파일은 `server-only`를 import합니다.
- `lib/scanner/rate-limit.ts`: `consume_scanner_rate_limit` RPC 호출. 운영 및 비로컬 요청 제한에 필요합니다.
- `lib/scanner/candles.ts`: 캔들 캐시 조회 및 upsert.
- `app/api/analysis/start/route.ts`: run 생성, 기존 run 복구 조회, 후보·task 저장, run 상태 갱신. Supabase 미설정이면 분석 시작을 거부합니다.
- `app/api/analysis/step/route.ts`: run/candidate 조회, task claim, candle/result 원자 저장, 실패 처리, 상태 정산 RPC.
- `app/api/analysis/status/route.ts`: 소유자 조건을 붙여 run 상태 조회.
- `app/api/analysis/results/route.ts`: run 소유권 확인, scanner_results와 scanner_candidates 조회.
- `app/api/auth/login/route.ts`: 로그인 요청 limiter가 운영/비로컬 경로에서 Supabase RPC에 의존합니다.
- `app/api/markets/route.ts`: Supabase 저장소를 직접 쓰지 않지만 API limiter 때문에 운영/비로컬에서는 RPC가 필요합니다. 시세 자체는 거래소 공개 API에서 가져옵니다.

브라우저 초기 화면이나 클라이언트 코드에서 Supabase DB를 직접 호출하는 경로는 검색되지 않았습니다.

## 필요한 database 구조

### Migration 적용 순서

신규 빈 프로젝트에서 다음 migration 두 개가 필요합니다.

1. `supabase/migrations/20261114000100_scanner.sql`
2. `supabase/migrations/20261114000200_auth_owner_recovery.sql`

00200은 00100의 테이블을 전제로 `owner_id`, task retry/lease 필드, API limiter와 신규 RPC를 추가합니다. 적용 전에 dedicated project와 대상 ref를 확인하고, 빈 신규 project인지 확인해야 합니다. 두 migration 모두 `IF NOT EXISTS`만으로 기존 객체의 잘못된 구조를 수리하지 않으므로, 기존 schema가 있는 DB에 무심코 재사용하면 안 됩니다.

### Tables 및 주요 columns

| Table | 용도 및 columns |
| --- | --- |
| `scanner_runs` | 실행 이력·진행상태: `id, status, settings, exchange_status, total_markets, qualified_count, candidate_count, total_tasks, completed_tasks, failed_tasks, progress_percent, error_message, created_at, started_at, completed_at, updated_at`; 00200 추가: nullable `owner_id, idempotency_key` |
| `scanner_candidates` | 시장 선별 결과: `id, run_id, exchange, symbol, base, is_qualified, is_selected, rank, trend_score, turning_score, reasons, deferred_checks, market_snapshot, analysis_status, created_at` |
| `scanner_tasks` | 분할된 분석 task/재시도: `id, run_id, candidate_id, exchange, symbol, status, attempts, locked_at, error_message, created_at, finished_at`; 00200 추가: `max_attempts, next_attempt_at, lease_token` |
| `scanner_candles` | OHLCV 원본: `exchange, symbol, timeframe, timestamp_ms, open, high, low, close, volume, is_closed, fetched_at` |
| `scanner_results` | 방향별 분석 결과: `id, run_id, candidate_id, exchange, symbol, base, side, score, is_qualified, reasons, features, algorithm_version, created_at` |
| `scanner_api_limits` | 원자 요청 제한: `scope, subject_hash, window_started_at, hit_count` |

중요 key/constraint:

- PK: runs/candidates/tasks/results의 `id`; candle의 `(exchange,symbol,timeframe,timestamp_ms)`; limiter의 `(scope,subject_hash)`.
- Unique: candidates `(run_id,exchange,symbol)`; tasks의 `candidate_id`; results `(run_id,candidate_id,side,algorithm_version)`; runs의 non-null `(owner_id,idempotency_key)` partial unique index.
- FK: candidates/tasks/results가 run에 연결되고, tasks/results가 candidate에 연결됩니다. run/candidate 삭제에는 일부 cascade가 선언돼 있습니다.
- CHECK: exchange는 Binance/OKX/Bybit, candle timeframe은 1h/4h/1d, result side는 long/short, run/task/analysis status와 task max_attempts 및 limiter scope/hash/hit_count 값이 제한됩니다.

### Indexes

- 00100: `scanner_tasks_run_status_idx`, `scanner_candidates_run_selected_idx`, `scanner_candles_recent_idx`, `scanner_results_run_side_idx`; 각 테이블의 PK 및 위에 적은 unique index/constraint.
- 00200: `scanner_runs_owner_created_idx`, partial unique `scanner_runs_owner_idempotency_uidx`, `scanner_tasks_due_idx`.

### RPCs

- 기존/교체 대상: `claim_scanner_tasks(uuid, integer)` legacy overload (00200에서 execute 권한을 service_role 포함 전부 회수하고 앱 사용을 중단)
- `begin_scanner_run(text, uuid, jsonb)`
- `consume_scanner_rate_limit(text, text, integer, integer)`
- `claim_scanner_tasks(uuid, text, integer)`
- `complete_scanner_task(uuid, uuid, jsonb, jsonb)`
- `finish_scanner_task_failure(uuid, uuid, text, boolean, integer)`
- `reconcile_scanner_run(uuid, text)`

00200은 신규 RPC에서 PUBLIC/anon/authenticated execute를 회수하고 service_role만 execute하도록 설정합니다.

### RLS 및 grants

두 migration을 모두 적용한 뒤 여섯 테이블 모두 RLS enabled 상태가 됩니다. migration에는 RLS policy 생성문이 없습니다. 이는 브라우저에서 직접 접근하지 않고 backend에서 service_role로 요청하는 구조입니다. 00100은 다섯 scanner tables에, 00200은 limiter table에 service_role의 SELECT/INSERT/UPDATE/DELETE를 grant합니다. Supabase service_role은 RLS를 우회하므로 이 키의 서버 전용 보관과 route-level session/owner 검증이 보안 경계입니다. 이 schema에 anon/authenticated용 직접 접근 정책을 임의로 추가하지 않습니다.

## 가족 학습관리 및 WORD MASTER 데이터 격리

별도 신규 Supabase project를 생성하면 각 project가 자체 Postgres instance/database를 갖기 때문에 다른 프로젝트의 `public` schema나 데이터와 구조적으로 분리됩니다. 이 프로그램이 사용하는 `scanner_*` 이름도 별도 DB에서는 가족 학습관리/WORD MASTER의 동명 객체와 충돌하지 않습니다. 기존 프로젝트의 URL/key 재사용이나 그 DB 안에 migration 적용은 피해야 합니다.

이 보고서는 두 프로젝트를 열거나 조회하지 않았으므로 현재 어느 조직/프로젝트에 속해 있는지, 새 free project quota가 남아 있는지는 확인하지 않았습니다. Supabase의 Free project quota는 Owner/Admin인 모든 조직에 걸쳐 계산되므로, project 생성 전 Dashboard에서 잔여 quota를 확인해야 합니다.

## 환경변수 및 secret 관리

### 현재 코드가 요구하는 변수

- Supabase 연결: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- 앱 자체 인증: `SCANNER_LOGIN_PASSWORD`, `SCANNER_SESSION_SECRET`, `SCANNER_ALLOWED_ORIGIN`

값들은 이 보고서에 기록하지 않았습니다. .gitignore는 `.env*`를 무시하며 `.env.local`은 현재 Git 추적 파일이 아닙니다. `next.config.ts`에 환경변수 expose 설정은 없고, 검색상 Supabase 변수는 server-only helper에만 참조되며 `NEXT_PUBLIC_SUPABASE_*` 참조는 발견되지 않았습니다. 문서 저장소에도 secret 값을 올리지 않습니다.

향후 연결 시 로컬 값은 `.env.local`에만 저장하고, 운영값은 승인 후 Vercel의 server-only environment variables에 등록합니다. `NEXT_PUBLIC_` prefix를 쓰지 않고 터미널 출력, 화면 캡처, 오류 로그, 보고서, Git에 값을 남기지 않습니다. service-role/secret key는 전체 DB 권한 및 RLS 우회 권한이므로 브라우저 번들에 넣을 수 없습니다. 현재 helper의 `server-only` 경계가 유지되어야 합니다.

### API key 호환성 주의 (연결 전 확인 필요)

현재 helper는 legacy `SUPABASE_SERVICE_ROLE_KEY` 변수와 JWT형 service_role key를 전제로 하며 이를 `apikey`와 `Authorization: Bearer` 헤더에 함께 넣습니다. Supabase 공식 문서는 legacy `service_role`/anon key를 2026년 말까지 폐기할 예정이며 서버에는 새 `sb_secret_...` key 사용을 권고합니다. 새 secret key는 브라우저에 노출할 수 없고 RLS를 우회합니다. 현재 helper는 `SUPABASE_SECRET_KEY` 변수를 처리하지 않습니다. 따라서 장기 연결 전에는 새로운 secret key 형식 및 REST 인증 헤더와 helper의 호환성을 별도 승인된 코드 변경으로 검토해야 합니다. Supabase 공식 [API keys guide](https://supabase.com/docs/guides/getting-started/api-keys)를 참조합니다.

## 비용 및 Free plan 전제 (공식 페이지 확인: 2026-11-14)

- Free는 $0이며 project당 database size 500 MB, shared Nano compute(최대 0.5 GB RAM), API requests 무제한, 5 GB egress가 안내되어 있습니다. pricing 표에는 storage cached egress 5 GB도 별도로 표시됩니다.
- Free는 Owner/Admin 권한이 있는 여러 조직 전체에서 2개의 active projects로 제한됩니다. 다른 project가 같은 계정/조직에 있는지는 이번 검토에서 확인하지 않았습니다.
- Free project는 7일 동안 database activity가 낮으면 자동 pause 대상이 될 수 있습니다. 복구 가능 기간이 문서화돼 있지만 24/7 서비스에는 가용성 위험이 됩니다.
- Free에는 자동 백업이 포함되지 않고 Supabase Production Checklist는 Free project backup을 다운로드할 수 없다고 안내합니다. migration 전 별도 backup/restore 방안이 필요합니다.
- Pro는 현재 $25/월부터입니다. project마다 별도 Postgres compute가 청구되며 기본 Micro compute는 약 $10/월 수준입니다. Pro의 compute credits와 organization/project 조건을 반영한 실제 예상액은 Dashboard의 현재 견적을 다시 확인해야 합니다.
- 프로젝트는 candle/result/run/API limiter 데이터를 쌓습니다. 특히 candle은 심볼/timeframe/timestamp key로 upsert되지만 오래된 run/results 및 candles의 retention/cleanup 정책은 이 두 migration에 없습니다. DB 500 MB 및 egress 사용량을 운영 중 관찰해야 합니다.

공식 요금은 변할 수 있습니다. 생성 직전에 pricing, billing FAQ 및 compute 가격을 재확인하십시오: [Supabase Pricing](https://supabase.com/pricing), [Billing](https://supabase.com/docs/guides/platform/billing-on-supabase), [Compute and Disk](https://supabase.com/docs/guides/platform/compute-and-disk).

## 연결 진행 checklist 및 순서

1. **코드 key compatibility 결정**: 기존 service_role key 지원을 임시 사용 가능한지 확인하거나, 새 secret key 형식 지원을 별도 승인된 코드 작업으로 먼저 설계합니다. Supabase key deprecation 시한을 고려합니다.
2. **독립성/비용 승인**: scanner 전용 새 Supabase project 및 조직/region을 정하고 Free slot 또는 유료 비용을 확인합니다. 기존 학습관리 및 WORD MASTER project 자격증명은 사용하지 않습니다.
3. **프로젝트 생성**: 승인된 사용자가 새 project를 만들고 강력한 DB password를 안전한 password manager에 보관합니다. 이 단계는 이번 점검에서 하지 않았습니다.
4. **Migration 정적 확인**: 프로젝트 ref와 빈 DB를 확인하고 두 migration 파일을 재검토합니다. 00100부터 적용한 뒤 필요한 base schema를 확인합니다.
5. **Preflight**: read-only `supabase/preflight/20261114000200_auth_owner_recovery_preflight.sql`로 00100 schema의 tables/columns/indexes/functions/grants/RLS를 확인합니다. 실제 DB 실행은 별도 승인 후입니다.
6. **Migration 00200 적용 승인**: blocker와 backup 방식, 복구 책임을 검토한 후 명시적 승인과 계획된 migration 절차로 적용합니다.
7. **Environment setup**: 코드가 지원하는 key 방식을 확인한 후 로컬 `.env.local`에 서버 전용 variables, 운영 시 Vercel server-side secrets에 각각 구성합니다. 값은 대화/로그/Git으로 전달하지 않습니다.
8. **작은 범위 smoke test**: login → limiter → `maxCandidates=1` start → step → status → results, candle upsert 반복, 소유권 거부 및 task retry/recovery를 확인합니다. no-key browser bundle과 Git ignore 상태도 검토합니다.
9. **운영 readiness**: quota/storage, backups, Free auto-pause, monitoring, retention/cleanup 및 key rotation plan을 결정하고 staging 확인 후 배포는 별도 승인받습니다.

## 이번 단계 완료 및 미실행

- 작성: 이 보고서 및 문서 저장소 `handover/STATUS.md` 갱신
- 코드, migration 파일, package, environment variables는 수정하지 않았습니다.
- Supabase project 생성/연결, remote DB query, SQL/migration 실행, backup/export는 하지 않았습니다.
- 기존 가족 학습관리와 WORD MASTER 프로젝트를 열거나 조회하지 않았습니다.
- build/test는 실행하지 않았습니다. 이번 단계는 승인된 read-only 정적 점검과 문서 작성입니다.

## 공식 참고자료

- [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase pricing](https://supabase.com/pricing)
- [About billing](https://supabase.com/docs/guides/platform/billing-on-supabase)
- [Free project pausing](https://supabase.com/docs/guides/platform/free-project-pausing)
- [Production checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
- [Compute and disk](https://supabase.com/docs/guides/platform/compute-and-disk)
