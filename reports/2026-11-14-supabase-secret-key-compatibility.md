# Supabase Secret Key 호환성 검토 (2026-11-14)

## 요청 및 범위

기존 Supabase helper가 legacy `service_role` 키와 신규 Secret Key를 안전하게 지원하는지, REST API 인증 헤더 호환성, 변경 범위와 보안 테스트를 읽기 전용으로 검토했습니다.

이번 작업은 코드·SQL·패키지·환경변수·원격 Supabase·DB·migration·배포를 변경하지 않았습니다. 로컬 helper만 읽었으며 비밀값이나 환경변수 값을 읽거나 기록하지 않았습니다.

## 확인한 현재 구현

대상 파일: 코드 프로젝트 `lib/scanner/supabase.ts`.

- `server-only`를 import하므로 helper는 서버 전용 경계를 표시합니다.
- `missingSupabaseEnvironment()`와 `getConfig()`는 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`만 요구/읽습니다.
- 공통 request 함수는 REST 경로 `/rest/v1/...`를 사용하며 테이블 CRUD와 `/rpc/{name}` RPC 모두에 동일한 인증 헤더를 넣습니다.
- 현재는 `apikey: serviceKey`와 `Authorization: Bearer serviceKey`를 함께 설정합니다.
- 요청 오류는 상태 코드만 노출하고 응답 body를 취소합니다. 키 원문은 오류 메시지에 포함되지 않습니다.
- 따라서 legacy JWT 기반 `service_role` 키는 현재 흐름을 전제로 작성됐지만, 신규 `sb_secret_...` 키는 변수명과 인증 헤더 처리 모두 지원하지 않습니다.

## 키 종류별 REST 호환성

Supabase 공식 키 이전 문서는 신규 publishable/secret 키를 `apikey` 헤더에만 보내고 `Authorization: Bearer`에는 보내지 말라고 명시합니다. 신규 키는 JWT가 아니므로 Bearer에 넣으면 플랫폼이 JWT로 파싱해 `Invalid JWT`를 반환할 수 있습니다. 이 안내는 Edge Function 전용이 아니라 신규 키의 헤더 형식에 대한 설명입니다.

| 서버 키 모드 | 현재 변수명 | 필요한 REST 헤더 | 현재 helper |
|---|---|---|---|
| Legacy `service_role` JWT | `SUPABASE_SERVICE_ROLE_KEY` | `apikey`와 `Authorization: Bearer <legacy JWT>` | 호환되도록 작성됨 |
| 신규 Secret Key | 현재 미지원 | `apikey: <sb_secret_...>`만 전송. 해당 키를 Authorization Bearer로 전송하지 않음 | 미호환. 변수명 미인식 및 Bearer JWT 파싱 위험 |

신규 Secret Key는 서버 전용이며 service-role 권한으로 RLS를 우회할 수 있으므로 기존 키와 같은 강한 비밀값으로 취급해야 합니다. 브라우저 노출, `NEXT_PUBLIC_` 접두 변수, 저장소 기록, 로그 출력을 금지해야 합니다.

### 공식 근거

- [Supabase: Migrating to publishable and secret API keys](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys) — 신규 키는 `apikey` 전용이며 Bearer 사용 시 Invalid JWT 가능성을 설명합니다. legacy `service_role`에서 Secret Key로의 대응 및 두 키를 동시에 유지할 수 있는 이전 단계도 설명합니다.
- [Supabase: API keys](https://supabase.com/docs/guides/getting-started/api-keys) — secret key를 서버 측에서 사용하고 RLS 우회 권한이 있으므로 비밀로 관리해야 함을 설명합니다.
- [Supabase: Creating API routes](https://supabase.com/docs/guides/api/creating-routes) — Data API의 `/rest/v1` 경로와 API key 요청 방식을 설명합니다.

## 코드 변경 제안 (이번에는 미적용)

필요한 변경은 `lib/scanner/supabase.ts` 한 파일에 한정할 수 있습니다. package 변경은 필요하지 않습니다. 직접 REST 호출을 유지하면서 다음을 제안합니다.

1. 설정 해석을 legacy 전용에서 키 모드 해석으로 확장: `SUPABASE_URL`과 `SUPABASE_SECRET_KEY` 또는 기존 `SUPABASE_SERVICE_ROLE_KEY` 중 하나를 요구합니다.
2. 키를 하나만 명시하도록 하고 두 키 변수가 동시에 설정된 경우 모호한 선택/조용한 fallback을 피하도록 설정 오류로 fail closed 합니다. 오류에는 변수명만 포함하고 값은 포함하지 않습니다.
3. legacy 모드에서는 현재처럼 `apikey` + `Authorization: Bearer <legacy key>`를 사용합니다.
4. Secret Key 모드에서는 `apikey`만 설정하고 기존 `init.headers`에 Authorization이 전달되더라도 제거합니다. 신규 키를 Bearer로 자동 복사하지 않습니다.
5. 공통 REST 경로, RPC, Content-Type/Accept, no-store, 요청/응답 및 오류 비노출 동작은 유지합니다.
6. `missingSupabaseEnvironment()`와 `isSupabaseConfigured()`가 두 키 중 하나의 유효한 단일 설정을 반영하도록 함께 조정합니다.

이 변경은 legacy 변수 호환성을 보존하면서 신규 키를 명시적으로 선택할 수 있게 합니다. 두 변수 동시 설정을 허용하고 신규 키를 우선하는 정책도 가능하지만, 운영 설정에서 예기치 않은 키 모드 전환을 막기 위해 이 검토에서는 동시 설정 거부를 권고합니다. 구현 전에 별도 코드 변경 지시가 필요합니다.

## 보안 테스트 계획

코드 변경 승인 후 mock fetch 기반 단위 테스트를 추가합니다. 실제 키/DB 접근 없이 헤더와 요청 생성만 검증합니다.

- legacy-only 환경: 설정 성공, `apikey` 및 legacy Bearer 헤더가 정확히 설정됨.
- secret-only 환경: 설정 성공, `apikey`가 설정되고 Authorization 헤더가 없음을 확인. 호출자가 전달한 Authorization도 제거되는지 확인.
- 두 키 동시 설정: 선택된 키에 대한 묵시적 우선순위 없이 설정 오류. 오류에 키 원문이 없고 변수명만 존재.
- 두 키 모두 없음 또는 URL 누락: fail-closed와 누락 변수명 확인; 실제 값이나 유사 토큰 문자열은 출력되지 않음.
- CRUD와 `/rpc/{name}`: 두 모드에서 URL, method, body, Content-Type, Accept, `cache: no-store` 보존.
- HTTP 실패 및 악성/민감 response body: 오류는 상태 코드만 포함하고 키나 응답 body를 노출하지 않음.
- 모듈 경계 검사: `server-only` 유지, 클라이언트 import와 `NEXT_PUBLIC_*` 키 참조 없음.
- 이후 별도 승인된 전용 staging DB에서만 최소 smoke test를 수행. 이번 검토에서는 네트워크/DB 검증을 수행하지 않음.

## Migration 순서 및 조건

기존 순서를 그대로 유지합니다.

1. `20261114000100_scanner.sql`: 전용 신규 프로젝트의 기본 scanner schema migration.
2. `20261114000200_auth_owner_recovery.sql`: 첫 migration이 적용된 상태를 전제로 한 owner, limiter, retry/recovery 확장. 적용 전에 승인된 read-only preflight와 blocker 검토를 마쳐야 합니다.

이번 키 호환성 검토는 migration 내용을 변경하거나 순서를 바꾸지 않습니다. 프로젝트 생성, 연결, SQL 실행, migration 적용은 하지 않았습니다.

## 검증 결과 및 미해결 항목

- helper 파일과 문서 저장소의 현재 handover를 읽어 키 변수 및 헤더 사용을 확인했습니다.
- 공식 Supabase 문서에서 신규 키의 헤더 지침을 대조했습니다.
- 코드 수정, package 설치, 환경변수 확인/수정, 원격 호출, DB 연결, migration 실행, build/test는 수행하지 않았습니다.
- 실행 검증은 하지 않았으므로 실제 Supabase 프로젝트/환경에서의 성공을 주장하지 않습니다.
- 다음 작업은 사용자의 별도 코드 수정 지시 후 helper 및 단위 테스트를 수정·실행하고, 실제 DB smoke test는 별도 승인과 전용 프로젝트 준비 후 수행하는 것입니다.

관련 handover: `handover/STATUS.md`.
