# 04. 인증·소유권·작업 복구 구현

- 승인일: 2026-11-14
- 대상 코드 프로젝트: `C:\Users\PC1\ai-trading-scanner`
- 코드 저장소: 대상 프로젝트의 기존 저장소와 브랜치 정책을 따를 것
- 문서 저장소: `jaewanlim00/ai-trading-scanner-docs`
- 승인 범위: 앱 단일 사용자 인증, 분석 run 소유권 검사, 호출 제한 코드, task 재시도·lease 복구·run 상태 정산 코드, 신규 forward migration SQL 파일 작성, 빌드/테스트, 보고서 및 handover 갱신
- 이번 승인에 포함되지 않는 작업: 실제 Supabase DB에 SQL 적용, 원격 DB/데이터 변경, 비밀값 생성·등록, .env 파일 수정, Vercel/WAF/Deployment Protection 설정, 외부 서비스 설정, 배포, 패키지 설치·제거·버전 변경, 자동주문·자동 감시

## 시작 전 필수 확인

1. `instructions/WORKFLOW.md`, 이 지시서, `handover/STATUS.md`, `reports/2026-11-14-api-security-recovery-design.md`를 읽는다.
2. 코드 저장소/브랜치와 Git working tree를 확인한다. 기존 사용자 변경은 절대 덮어쓰거나 초기화하지 않는다.
3. 실제 코드의 현재 구조를 확인하고 설계 보고서와 다른 점이 있으면 보고서의 가정을 그대로 강제하지 말고 현재 코드에 맞게 안전한 구현안을 정리한다.
4. 기존 migration `supabase/migrations/20261114000100_scanner.sql`은 수정하지 않는다. 새 migration 파일만 추가한다.
5. 패키지 변경이 필요해 보이면 설치하지 말고 이유와 대안을 보고한다. 이번 승인에는 의존성 변경이 포함되지 않는다.

## 구현 목표

### A. 단일 사용자 로그인과 세션

- 새 패키지 없이 기존 런타임의 안전한 암호학 API(Node crypto 또는 호환되는 Web Crypto)를 사용한다.
- 서버 전용 공통 모듈을 만들고 client bundle에 비밀값이나 service-role 접근 코드가 포함되지 않도록 한다.
- 신규 환경변수 이름은 다음 세 가지로 제한한다.
  - `SCANNER_LOGIN_PASSWORD`
  - `SCANNER_SESSION_SECRET`
  - `SCANNER_ALLOWED_ORIGIN`
- 환경변수의 실제 값은 생성하거나 설정하지 않는다. `.env`, `.env.local`, 문서, 로그, Git에 값을 쓰지 않는다.
- 필요한 환경변수가 없으면 안전하게 fail closed하고, 사용자에게 어떤 이름이 누락됐는지만 표시한다.
- 로그인 성공 시 만료형 HMAC 서명 HttpOnly 세션 쿠키를 발급한다. production에서 Secure, SameSite=Strict, Path=/, 합리적인 만료 시간을 설정한다.
- 서명 검증은 timing-safe 비교를 사용하고, 만료·잘못된 서명·잘못된 형식을 거부한다. 세션에는 비밀값이나 원 비밀번호를 넣지 않는다.
- 로그인 실패 메시지는 계정/비밀번호 유효성을 구분해 노출하지 않는다. 로그인 API는 Origin 검사와 가능한 범위의 안전한 실패 제한을 적용한다.
- 로그아웃은 쿠키를 만료한다. 무상태 세션의 전체 폐기는 session secret 회전으로 처리됨을 문서화한다.
- 로그인/로그아웃 API와 화면을 구현한다. 기존 분석 화면의 기능과 스타일은 가능한 한 보존하고, 세션이 없으면 로그인 화면을 보여준다.
- 세션 만료 시 polling을 중지하고 로그인 상태로 복귀한다. 민감한 응답은 캐시하지 않는다.
- `SCANNER_ALLOWED_ORIGIN`이 설정된 경우 canonical Origin을 엄격히 비교한다. 환경변수가 없는 상태에서 POST 요청을 허용하는 식으로 우회하지 않는다. 로컬 개발/production 모두 동작 가능한 명확한 origin 정책을 구현하고 README/보고서에 설정 방법(값 없이) 설명한다.

### B. 분석 API 및 run 소유권 보호

- `/api/analysis/start`, `step`, `status`, `results`의 모든 요청에서 DB 또는 거래소 작업 전에 세션 인증을 확인한다.
- 비인증은 401, 소유자가 다른 run 또는 없는 run은 존재 여부 노출을 최소화하도록 404를 반환한다.
- start는 서버가 계산한 고정 principal ID를 owner로 저장한다. 요청 body의 owner/user 필드를 권한 근거로 신뢰하지 않는다.
- status/results는 run ID와 owner를 함께 조건으로 조회한다.
- step은 run owner를 확인하고, task claim RPC에도 owner를 전달해 DB 내부에서 원자적으로 검증한다. 단순히 route에서만 확인하고 RPC에 owner 검증을 생략하지 않는다.
- ID는 권한 증명이 아니다. 다른 사용자의 runId를 넣어도 상태/결과 조회나 task 실행이 불가능해야 한다.
- `/api/markets`는 공개 market/ticker API 호출 비용을 고려해 인증으로 보호하는 방향을 우선 적용한다. 기존 UI가 인증된 상태에서 정상 조회하는지 확인한다.
- Supabase service role은 RLS를 우회하므로 route와 RPC에서 명시적 owner 검사를 유지한다. service-role 키는 server-only로 유지한다.

### C. 호출 제한 및 중복 start 안전성

- Vercel WAF 설정은 하지 않는다. 이번 단계에서는 앱/DB 코드와 migration 파일만 준비한다.
- 서버리스 인스턴스 메모리 Map을 분산 rate limit으로 사용하지 않는다.
- 신규 migration에 원자적 DB limiter 테이블/RPC를 설계하고, 인증 principal+route 및 step의 principal+run 단위로 제한한다.
- limiter RPC 장애 시 비용이 큰 start/step은 fail closed해 거래소 호출 또는 task claim 전에 중단한다. 429와 Retry-After를 반환한다.
- 한도는 합리적인 보수적 서버 상수로 설정하고 보고서에 선택 근거를 기록한다. 사용자 body/query가 한도를 올릴 수 없어야 한다.
- start 중복 요청에 대한 owner별 idempotency key를 구현할 수 있는 경우 DB unique constraint/RPC와 함께 적용한다. 동일 키 재전송 시 중복 run을 만들지 않는다. 구현 복잡성 때문에 안전한 원자성을 보장할 수 없다면 추측성 구현 대신 미해결 사유를 보고한다.
- 실제 DB 동시성 검증은 이번 단계에서 할 수 없으므로 코드/SQL 정적 검토와 가능한 mock/unit 테스트만 실행하고, 원격 검증 미실행을 명확히 기록한다.

### D. task 재시도·lease fencing·run 상태 정산

- task의 최대 시도 횟수를 제한한다(초기 제안 4회). CCXT 내부 재시도와 합산 호출량이 과도해지지 않게 조정하고 근거를 보고한다.
- 일시적 오류(예: 거래소 429/5xx, timeout, 일시 DB 오류)와 영구적 오류(예: 잘못된 symbol/지원하지 않는 입력)를 분리한다.
- 일시 오류는 `retry_wait`와 `next_attempt_at`을 사용하고 jitter가 포함된 bounded exponential backoff를 적용한다.
- attempts 상한에 도달한 task 및 만료된 lease의 최종 시도 task는 terminal failed/dead-letter 상태로 정산한다. 무한 재claim을 허용하지 않는다.
- claim 시 lease token/fencing token을 발급하고, 완료/실패/저장 갱신 시 현재 token이 일치하는 worker만 상태를 바꿀 수 있게 한다. 오래된 worker가 늦게 돌아와 새 worker 결과를 덮어쓰지 못해야 한다.
- task claim RPC는 owner, run, attempts 상한, retry 시각, lease 상태를 원자적으로 확인한다.
- run 상태는 최소한 queued, processing, completed, completed_with_errors, failed를 구분한다. 모든 task terminal 이후 성공/실패 집계를 통해 상태를 결정한다. 후보가 0개인 정상 run 처리도 기존 의미를 확인해 보존한다.
- 동시 step이 진행률/상태를 오래된 값으로 덮어쓰지 않도록 DB reconciliation RPC 또는 동등하게 원자적인 정산 방법을 구현한다.
- 수동 retry API/UI는 이번 단계에서 반드시 만들 필요는 없다. 구현이 기존 구조에 자연스럽고 권한·횟수 제한을 안전하게 보장할 수 있을 때만 추가한다. 그렇지 않으면 설계만 보고하고 다음 단계로 남긴다.
- start의 부분 생성 문제를 해결할 때 transaction RPC 또는 안전한 owner/idempotency 복구 정책을 검토한다. 기존 데이터 의미를 추정해 삭제·초기화하지 않는다.

### E. 신규 forward migration

- 기존 migration은 절대 수정하지 않는다.
- 새 migration은 현재 schema를 기준으로 필요한 owner, idempotency, limiter, retry/lease, run status, RPC 변경을 추가한다.
- `IF NOT EXISTS`만으로 기존 객체가 올바른 schema라고 가정하지 않는다. 함수 signature, owner, grants, policies, constraints, indexes의 충돌 가능성을 고려한다.
- SECURITY DEFINER 함수는 고정된 최소 `search_path`, 명시적 권한 검사, 최소 execute grants를 사용한다.
- 기존 run/task 데이터가 있을 수 있으므로 owner backfill을 임의로 모든 행에 부여하지 않는다. 안전한 backfill이 불가능하면 migration은 명확히 중단하고 preflight/수동 backfill 필요 조건을 보고한다.
- 실제 DB 상태는 미확인이다. migration SQL을 작성하고 정적 검토할 뿐 실행하지 않는다.
- migration 상단 또는 별도 문서에 적용 전 read-only preflight 목록과 적용 조건을 기록한다. 전용 빈 DB인지, 기존 객체/정책/grants/function owner, 기존 row 수, 기존 status 값 등을 확인하도록 한다.
- migration이 빈 DB 또는 기존 DB 모두에서 안전하다고 검증되지 않았다면 지원 대상을 명시하고 실행 금지 조건을 분명히 한다.

## 테스트 및 검증

1. `npm.cmd run build`를 실행한다.
2. 저장소에 이미 존재하는 테스트 명령을 확인해 관련 테스트를 실행한다. 새 테스트 프레임워크/패키지를 설치하지 않는다.
3. 세션 서명/검증, 만료, 변조, cookie 속성, Origin 검사 테스트를 가능한 범위에서 추가/실행한다.
4. 미인증 요청이 Supabase/거래소 호출 전에 차단되는지 확인한다.
5. owner mismatch/위조 owner/run ID 접근이 차단되는지 테스트한다.
6. attempts 상한, backoff, lease token stale worker 방지, run 상태 집계의 테스트를 추가/실행한다.
7. migration은 실행하지 않는다. SQL 정적 검토와 preflight 체크리스트만 제공한다.
8. Supabase 환경변수가 현재 없을 수 있으므로 실제 DB 통합 테스트를 했다고 표현하지 않는다. 외부 서비스가 필요한 테스트는 skipped/not run으로 분리한다.
9. 기존 변경 파일을 보존하고, 본 지시 범위 파일만 커밋한다. 기존 사용자 변경이 섞여 있으면 임의로 stage/commit하지 말고 보고한다.

## 완료 보고

완료 후 문서 저장소에 다음을 작성/갱신한다.

- `reports/2026-11-14-auth-owner-retry-implementation.md`
- `handover/STATUS.md`

보고서에는 변경 파일, 주요 구현, 보안 결정, 신규 migration 경로, 빌드/테스트 명령과 실제 결과, 실행하지 않은 검증, 기존 변경사항 보존 여부, 미해결 위험, 다음 단계(실제 DB preflight/적용 승인, 비밀값 provisioning, staging E2E, Vercel 보호 설정 및 배포 별도 승인)를 기록한다.

## 완료 기준

- 비인증 상태에서 분석 및 market API가 보호된다.
- 본인 소유 run만 조회/실행 가능하며 runId만으로 접근할 수 없다.
- task 재시도와 lease 복구에 상한이 있고 stale worker가 결과를 덮어쓰지 못한다.
- run의 부분 실패가 성공 완료와 구분된다.
- 신규 migration이 작성되고 preflight/적용 금지 조건이 명확하다.
- 빌드가 성공하거나 실패 원인이 정확히 보고된다.
- DB 적용, 비밀값 설정, Vercel 설정, 배포는 전혀 수행하지 않는다.
