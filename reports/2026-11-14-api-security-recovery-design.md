# 분석 API 보안 및 작업 복구 설계

- 작성일: 2026-11-14
- 대상 코드 프로젝트: C:\Users\PC1\ai-trading-scanner
- 검토 코드 브랜치: master
- 문서 저장소 기준 main: 3c295c136ed7a4acdcd8169af44a070a50dd1865
- 범위: 읽기 전용 분석과 설계. 코드, SQL, 원격 DB, 환경변수, 배포, 패키지는 변경하지 않음.

## 요약 및 권고

현재 분석 API에는 인증, 세션, 사용자 식별, run 소유권 검사, rate limit이 없습니다. Supabase service role은 RLS를 우회하므로 API 앞단 인증과 run 소유권 검사가 필수입니다.

**단일 사용자 1단계 권고:** 새 인증 패키지나 IdP 없이 앱에 단일 사용자 로그인과 서명된 HttpOnly 세션 쿠키를 둡니다. start/step/status/results와 요청마다 거래소를 호출하는 markets 경로는 공통 서버 검증과 적절한 제한을 거칩니다. Vercel Deployment Protection/WAF는 계정 플랜과 scope를 확인한 뒤 보조 경계로 씁니다.

각 run은 서버가 정한 owner principal로 소유권을 기록합니다. 모든 run 접근은 owner 조건을 적용하고, step claim RPC도 owner를 원자적으로 검사해야 합니다. 서버리스 인스턴스 메모리에 의존하지 않는 제한은 Vercel WAF의 IP/경로 제한과 Supabase 원자 RPC의 principal/run 제한을 조합하는 방안이 적절합니다.

복구는 제한된 재시도, 일시/영구 오류 분류, lease 만료, lease fencing token, terminal dead-letter 처리로 설계합니다. 현재는 성공과 실패 task가 모두 정산되면 run을 completed로 표시하므로 부분 실패를 나타내는 상태도 추가해야 합니다.

아래 내용은 구현 전 설계 제안이며 코드나 DB에 반영되지 않았습니다.

## 현재 구조와 검토 근거

### 인증과 호출 흐름

| 경로 | 현재 동작 | 현재 보호 상태 |
|---|---|---|
| POST /api/analysis/start | Supabase 설정 확인 후 run, 거래소 market/ticker 수집, 후보 및 task 저장 | Supabase 설정만 확인, 사용자 인증·소유권·rate limit 없음 |
| POST /api/analysis/step | runId 형식 확인 후 run 조회, task claim, 캔들 조회·분석·저장 | 로그인 및 owner 검사 없음 |
| GET /api/analysis/status | runId 형식 확인 후 run 조회 | 로그인 및 owner 검사 없음 |
| GET /api/analysis/results | runId 형식 확인 후 결과와 후보 조회 | 로그인 및 owner 검사 없음 |
| GET /api/markets | 세 거래소 공개 market/ticker 조회 | 공개 시세지만 호출마다 거래소 요청을 일으킬 수 있음 |

코드 검색에서 인증/session, auth API, middleware, owner_id/user_id, rate-limit 구현 또는 인증 라이브러리를 찾지 못했습니다. package.json에도 인증 의존성이 없습니다. app/page.tsx는 start 이후 step/status를 반복 호출하며 서버 측 제한이나 소유권 검사는 없습니다.

Supabase helper는 서버의 SUPABASE_SERVICE_ROLE_KEY를 사용해 PostgREST 요청을 보냅니다. 현재 import는 서버 route 흐름에 있지만 명시적인 server-only guard는 없습니다. Service role은 RLS를 우회하므로 RLS만으로 API 사용자 권한을 제한할 수 없습니다. [Supabase RLS 및 service key 안내](https://supabase.com/docs/guides/database/postgres/row-level-security)

### 작업 queue 및 복구 흐름

- claim_scanner_tasks RPC는 FOR UPDATE SKIP LOCKED와 단일 UPDATE CTE로 task를 원자적으로 claim하고 attempts/locked_at을 갱신합니다.
- step route maxDuration은 60초, batch 상한은 3입니다. 같은 거래소의 task는 순차 처리하며 거래소 그룹은 병렬 처리합니다.
- CCXT 작업 오류는 개별 요청당 최대 3회 시도 후 task를 failed로 마감합니다. DB 오류에는 같은 backoff/retry가 적용되지 않습니다.
- RPC는 2분이 지난 processing task를 다시 claim하지만 attempts 상한이 없습니다. 반복 crash/lease 만료 시 무한 재claim될 수 있습니다. 현재 lease가 route maxDuration보다 길지만 실제 Vercel function 제한은 확인하지 못했습니다.
- 모든 task가 completed 또는 failed로 정산되면 run을 completed로 표시해 성공 완료와 부분 실패가 구별되지 않습니다.
- start는 run insert, 거래소 수집, 후보 batch 저장, task 저장, 상태 갱신을 여러 요청으로 수행합니다. 중간 오류 시 부분 후보/task가 남을 수 있으며 idempotency key나 원자적 생성 절차는 없습니다.
- 캔들과 결과는 unique key/upsert로 중복 row를 줄이나, stale worker의 늦은 업데이트나 run 소유권을 보장하지는 않습니다.

## 권장 설계

### 1. 단일 사용자 인증과 세션

앱 계층의 단일 사용자 비밀번호 로그인과 HMAC 서명 세션 쿠키를 구현합니다. 새 인증 패키지/IdP 없이 Node crypto/Web Crypto로 처리할 수 있습니다.

- 로그인 API는 SCANNER_LOGIN_PASSWORD를 검증하고 SCANNER_SESSION_SECRET으로 서명된 만료형 session을 발급합니다.
- 비밀번호 비교는 일정 시간 비교를 사용하고 실패 응답은 자격 증명의 유효성을 드러내지 않습니다.
- 쿠키 속성은 HttpOnly, production의 Secure, SameSite=Strict, Path=/ 및 제한된 만료를 사용합니다.
- 모든 분석 API는 route 진입 즉시 공통 server-only auth helper를 호출합니다. UI 버튼 비활성화나 난수 runId, middleware만을 인증으로 간주하지 않습니다.
- login/start/step POST는 canonical Origin 검사와 SameSite 보호를 적용하고 wildcard CORS는 허용하지 않습니다. 인증/분석 응답은 캐시하지 않습니다.
- 인증 실패는 401, 다른 owner 또는 없는 run은 존재 여부 노출을 줄이도록 404를 반환합니다.
- 로그아웃은 쿠키를 만료합니다. 무상태 세션의 전체 폐기는 SCANNER_SESSION_SECRET 회전으로 처리합니다.

제안 환경변수 이름만 나열합니다. 값은 이 문서에 포함하지 않습니다.

- SCANNER_LOGIN_PASSWORD
- SCANNER_SESSION_SECRET
- SCANNER_ALLOWED_ORIGIN
- 기존 SUPABASE_URL 및 SUPABASE_SERVICE_ROLE_KEY는 server-only로 유지

공개가 불필요한 사설 scanner이면 /api/markets에도 auth를 적용합니다. 공개로 둘 경우 WAF와 cache로 거래소 호출 남용을 제한합니다.

### 2. Vercel 보호 및 대안 비교

| 방안 | 장점 | 조건/제약 | 판단 |
|---|---|---|---|
| Vercel Deployment Protection만 | 앱 변경이 적고 배포 edge에서 차단 | 현재 플랜과 도메인 설정 미확인. Hobby의 Standard Protection은 production domain을 공개 상태로 둘 수 있으며 production 전체 보호는 Pro/Enterprise scope 조건이 있음. 로컬/대체 경로에 앱 인증을 보장하지 않음 | 설정 scope 확인 후 추가 경계로 권고 |
| 앱 단일 비밀번호 + 서명 cookie | 새 패키지/IdP 없이 로컬과 Vercel에 같은 인증 적용, single principal이 명확 | secret 환경변수, login 제한, session/CSRF 코드를 구현해야 함 | 현재 단일 사용자 단계의 권고 |
| Supabase Auth | 관리형 session/UID, 향후 다중 사용자와 RLS에 적합 | Auth 설정과 UI 필요. service-role 경로만으로 RLS가 자동 적용되지 않으며 user JWT 접근으로 전환해야 함 | 다중 사용자로 확장할 때 검토 |

Vercel은 보호 방법과 적용 scope를 별도로 설정합니다. 공식 문서에 따르면 production domain까지 보호하는 scope는 플랜에 따라 다르므로 현재 계정 및 모든 production/alias/preview URL을 확인해야 합니다. [Vercel Deployment Protection](https://vercel.com/docs/deployment-protection)

### 3. run 소유권과 IDOR 차단

- auth helper가 비밀이 아닌 안정적인 principal ID를 반환합니다. 단일 사용자 버전은 단일 owner principal, 다중 사용자 전환은 Supabase Auth UID를 사용합니다.
- 새 forward migration에서 scanner_runs.owner_id 및 owner 조회 인덱스를 추가합니다. 기존 run이 있을 경우 소유자 확인/backfill 방식을 먼저 결정하며 임의로 귀속하지 않습니다.
- start는 인증 principal을 owner_id로 저장하고 요청 body의 owner/user 값은 무시합니다.
- status/results는 runId와 owner_id를 함께 조건으로 조회합니다. results 반환 전 owner가 해당 run을 소유하는지 확인합니다.
- step은 owner 확인 후 claim RPC에도 owner를 전달합니다. RPC 내부에서 run ownership을 확인하며 다른 owner의 task는 claim할 수 없어야 합니다.
- Service role은 RLS를 우회하므로 앱 owner filter와 RPC 검사가 필수입니다. 다중 사용자 시 user JWT 요청과 RLS 정책으로 전환하고 service role은 필요한 서버 작업으로 격리합니다.
- runId는 식별자이지 권한 증명이 아닙니다.

### 4. 분산 rate limit과 중복 start 방지

인메모리 Map/전역 변수는 Vercel 서버리스 인스턴스 사이에서 공유되지 않으므로 최종 limiter로 사용하지 않습니다.

- **Vercel WAF:** login 및 start/step 경로에 edge IP 제한을 두어 무인증·burst 호출을 막습니다. 공식 WAF 문서는 custom rule의 rate limit을 지원하지만 실제 룰 수/요청량 한도는 계정에서 확인해야 합니다. [Vercel WAF custom rules](https://vercel.com/docs/vercel-firewall/vercel-waf/custom-rules)
- **Supabase RPC:** scanner_api_limits와 원자적 consume RPC를 추가해 인증 principal+route, step은 owner+run 단위로 제한합니다. 고유 키의 UPSERT로 window/count를 한 트랜잭션에서 갱신하고 allowed/retry-after를 반환합니다.
- 로그인 전에는 principal이 없으므로 IP 제한은 WAF를 우선합니다. DB limiter에서 IP를 쓸 때는 플랫폼이 제공한 신뢰 가능한 client IP만 사용하고 임의의 forwarded header는 신뢰하지 않으며 저장 키는 HMAC/hash 처리합니다.
- start limiter는 거래소 호출 전에, step limiter는 task claim 전에 적용합니다. limiter DB 장애 시 start/step은 fail closed해 거래소 요청/worker 작업을 시작하지 않습니다.
- 제한 거부는 HTTP 429 및 Retry-After를 반환합니다. 한도는 client 설정으로 노출하지 않고 서버에서 관리합니다.
- 우선 제안은 owner별 active run 1개, start 제한, owner/run별 step burst 제한, status/results 읽기 제한입니다. 횟수·기간은 staging 호출량을 보고 확정합니다.
- start에 owner별 idempotency key를 두고 DB unique constraint/RPC로 중복 실행을 막습니다. 같은 키 재전송은 기존 run을 반환합니다. active run 동시 허용 여부는 UI 동작과 함께 확정합니다.
- WAF는 IP/경로 제한, DB RPC는 사용자/run 제한을 담당하며 WAF가 user-level 권한 검사를 대체하지 않습니다.

Vercel WAF 설정은 외부 서비스 설정 승인, Supabase limiter table/RPC는 DB 변경 승인이 필요합니다.

### 5. task retry, lease, 수동 복구, run 상태

#### 제안 task 상태 전이

- queued → processing: owner 검증 후 atomic claim, attempts 증가, lease_token/lease expiry 발급
- processing → completed: 현재 lease_token이 일치하는 worker만 저장과 상태 갱신
- processing → retry_wait: timeout, 거래소 429/5xx, 일시 DB 오류 등 retry 가능한 오류. next_attempt_at과 jitter 지수 backoff 사용
- processing → failed: 잘못된 symbol/시장, 미지원 timeframe, 입력/권한 오류 등 영구 오류 또는 attempts 상한 소진
- lease expiry: attempts 미만인 task만 다시 claim 가능. 상한에 도달한 stale task는 failed/dead-letter 처리
- manual retry: 인증 owner가 terminal retryable task를 명시적으로 요청할 때만 별도 제한 경로로 허용. 재시도 수와 사유를 기록하며 영구 오류/성공 task는 허용하지 않음

초기 검토 범위로 task 총 시도 횟수 3~5회를 제안합니다. CCXT 요청별 재시도와 task 재시도를 곱해 호출이 과도하게 늘지 않도록 combined retry budget을 제한합니다. 최종 횟수/backoff는 staging 측정 후 승인합니다.

lease 만료 후 오래된 worker가 다시 살아나지 않도록 lease_token/fencing token을 저장하고 task/result 업데이트 시 token을 비교합니다. 현재 maxDuration=60초와 2분 lease 관계는 여유가 있지만 실제 Vercel 제한과 DB 지연을 측정하고 lease는 maxDuration+안전 여유보다 길게 설정합니다.

#### 제안 run 상태

- queued: 대기 또는 재시도 예정 task 존재
- processing: 실행 중 task 존재
- completed: 모든 task 성공 또는 후보 없음
- completed_with_errors: 일부 성공/실패 후 전체 terminal
- failed: 모든 task 실패 또는 run-level fatal error

현재 허용 status constraint에 partial status를 추가하는 forward migration이 필요합니다. 모든 task가 terminal이면 성공·실패 수를 구분합니다. 단일 reconciliation RPC가 aggregate와 진행률을 갱신해 동시 step의 오래된 count 덮어쓰기를 줄입니다.

start의 여러 DB 요청 사이에서 실패하면 부분 기록이 남을 수 있습니다. 시장 snapshot 후 run/candidate/task 저장을 transaction RPC로 묶거나, owner/idempotency key로 재요청 시 부분 run을 복구·실패 처리하는 정책을 선택합니다. candidate payload 크기와 Vercel 시간 제한을 작은 staging 측정으로 비교합니다.

## 예상 변경 파일과 영향

### 코드: 별도 구현 지시 후

- 신규 lib/scanner/auth.ts: 비밀번호/session 서명·검증, server-only
- 신규 lib/scanner/rate-limit.ts: limiter RPC 및 429 응답
- 신규 app/api/auth/login/route.ts, app/api/auth/logout/route.ts
- 수정 app/api/analysis/start/route.ts, step/route.ts, status/route.ts, results/route.ts
- 수정 app/page.tsx: login/logout, 세션 만료, polling backoff
- 수정 lib/scanner/supabase.ts, types.ts: owner-aware query/RPC 및 task/run 상태 타입
- 필요 시 app/api/markets/route.ts: 비공개 auth 또는 공개 WAF/cache 제한

### DB: 새 forward migration, 별도 승인

- scanner_runs.owner_id와 조회 index
- owner/idempotency unique key, 필요 시 active-run 제한
- scanner_api_limits와 원자 consume RPC
- task retry_wait/next_attempt_at/max_attempts/lease_token 등 필요한 columns/constraints
- owner·bounded attempts·lease token을 확인하는 claim RPC
- run 상태 constraint 및 atomic reconcile RPC
- SECURITY DEFINER 함수 search_path/owner/execute grants 및 service_role 최소 권한 검토

이미 적용된 migration을 수정하지 말고 새 forward migration을 준비합니다. 실제 기존 객체와 데이터는 확인되지 않아 backfill은 사전 조사 후 결정합니다.

### 환경변수 이름만

단일 사용자 권고에 필요한 신규 이름: SCANNER_LOGIN_PASSWORD, SCANNER_SESSION_SECRET, SCANNER_ALLOWED_ORIGIN. 기존 SUPABASE_URL과 SUPABASE_SERVICE_ROLE_KEY는 server-only로 유지합니다. Supabase Auth 대안을 고르면 공개 URL/anon key 및 Auth provider 설정을 별도로 검토하되 현재 1단계에서는 사용하지 않습니다.

## 단계별 구현 및 테스트 계획

1. 사용자에게 단일 사용자 인증 방식과 비밀값 provisioning 방식, Vercel protection 범위 승인받기
2. login/session/logout: 성공·오류·만료·회전·쿠키 속성·origin/CSRF 검증
3. 미인증 요청 시 네 분석 API와 markets API가 401/차단이며 DB/거래소 호출 전에 종료되는지 검증
4. 인증 사용자 본인 run 성공, 위조 owner/다른 run 조회·step은 404/차단 검증
5. 두 serverless 인스턴스의 WAF 및 DB rate limit 동시 요청에서 제한 일관성 및 Retry-After 검증
6. 같은 idempotency key 재전송, active run 동시 정책 검증
7. staging에서 두 worker 동시 claim, lease expiry/fencing, 일시·영구 오류, max attempts, manual retry, run reconciliation 검증
8. DB write 중간 오류를 주입해 partial run 복구/실패 정책 검증
9. client bundle에서 비밀값이 없고 service role 사용이 server-only인지 확인
10. Vercel preview/production/alias 접근 제한과 runtime 제한 확인 후 별도 배포 승인

이번 단계는 설계 전용입니다. 테스트/빌드는 실행하지 않았습니다. 소스·SQL·DB·환경변수·배포는 변경하지 않았습니다.

## 다음 승인 필요 사항

- 권고한 앱 단일 사용자 인증 및 run owner 구현
- owner, limiter, retry/run reconciliation schema를 위한 새 DB migration
- SCANNER_LOGIN_PASSWORD, SCANNER_SESSION_SECRET, SCANNER_ALLOWED_ORIGIN의 비밀 저장소 provisioning
- Vercel Deployment Protection/WAF 외부 설정
- staging DB 연결 및 end-to-end 테스트
- 별도 배포 승인

## 참고 자료

- [Vercel Deployment Protection](https://vercel.com/docs/deployment-protection)
- [Vercel Firewall custom rules](https://vercel.com/docs/vercel-firewall/vercel-waf/custom-rules)
- [Supabase Row Level Security 및 service role](https://supabase.com/docs/guides/database/postgres/row-level-security)
