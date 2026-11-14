# 로컬 분석 API 요청 제한 보고서

- 작업명: 로컬 개발 분석 API 요청 제한
- 기준일: 2026-11-14
- 대상 코드 프로젝트: `C:\\Users\\PC1\\ai-trading-scanner`
- 목적: 로컬 개발에서 분석 API의 요청 제한만 프로세스 메모리 방식으로 대체하고, Supabase 기반 운영 제한과 분석 저장/작업 기능을 유지

## 조사 및 변경 파일

- `app/api/analysis/start/route.ts`: `analysis_start` scope로 공통 보호 함수를 호출
- `app/api/analysis/step/route.ts`: `analysis_step` scope와 run별 limiter subject 사용
- `app/api/analysis/status/route.ts`: `analysis_status` scope 사용
- `app/api/analysis/results/route.ts`: `analysis_results` scope 사용
- 위 4개 route는 직접 수정하지 않았습니다. 모두 기존 `protectScannerApi()` 공통 경로에 이미 등록되어 있음을 조사했습니다.
- `lib/scanner/rate-limit.ts`: 해당 분석 scope에서만, 엄격한 로컬 개발 조건일 때 메모리 limiter를 사용하도록 공통 보호 흐름을 변경했습니다. 로그인 limiter도 같은 메커니즘을 재사용합니다. 시장 API와 다른 scope는 기존 Supabase limiter를 유지합니다.
- `lib/scanner/rate-limit-policy.ts`: 기존 scope와 제한 수치를 분리해 보존하고 로컬 사용 가능 scope를 분석 네 종류로 한정합니다.
- `lib/scanner/auth-core.ts`: GET 요청에서 Origin이 없을 때 Referer의 origin을 추출하는 순수 helper를 추가했습니다. 실제 판정은 기존 canonical Origin 검증 함수가 configured origin과 loopback 조건을 확인합니다.
- `tests/scanner-security.test.mjs`: scope 격리, 모든 기존 제한 값, Origin/Referer, development/Vercel/loopback 조건의 테스트를 추가했습니다.

기존 로컬 memory limiter 구현을 재사용했습니다. 기존 사용자 변경사항은 보존했고 package, migration, 환경변수, 원격 DB 및 앱 분석 기능을 변경하지 않았습니다.

## 제한 정책 및 안전 경계

| Scope | 기존 제한 (요청 수 / 시간) | 로컬 개발 |
| --- | ---: | --- |
| analysis_start | 3 / 10분 | memory limiter |
| analysis_step | 240 / 30분 | memory limiter |
| analysis_status | 320 / 30분 | memory limiter |
| analysis_results | 60 / 10분 | memory limiter |
| markets | 4 / 1분 | Supabase 유지 |
| auth_login | 5 / 15분 | 기존 로컬 구현 유지 |

분석 scope의 로컬 분기는 모두 충족해야 합니다: `NODE_ENV=development`, Vercel deployment 표시 없음, Origin(POST) 또는 Origin이 없을 때 Referer(GET)의 출처가 `SCANNER_ALLOWED_ORIGIN`과 정확히 일치, 그리고 loopback host(localhost/127.0.0.1/::1). 일치하지 않으면 local memory 제한을 쓰지 않고 기존 Supabase 제한 경로를 탑니다. 분석 scope가 아닌 markets도 Supabase 제한을 사용합니다.

이 변경은 rate-limit gate만 대체합니다. analysis start는 limiter 통과 후에도 `isSupabaseConfigured()`, `beginRun`, candidate/task 저장 등을 계속 요구합니다. step은 task claim과 candle/result 저장, status/results는 owner 조건의 DB 조회를 계속 사용합니다. 로그인한 뒤 limiter 오류는 해결되어도 Supabase가 구성되지 않으면 실제 분석은 시작·저장되지 않습니다.

로컬 limiter는 프로세스 메모리이며 개발 서버 재시작 때 초기화됩니다. 운영 및 preview의 분산 limiter는 기존 Supabase RPC 경로를 사용합니다.

## 테스트 결과

- `node --test tests/*.test.mjs`: **9/9 통과**
- `npm.cmd run lint`: **exit 0**
- `npm.cmd run build`: **exit 0**, Turbopack compile/type check/static generation 완료
- 실제 분석 API end-to-end 요청은 수행하지 않았습니다. Supabase 설정 및 작업 저장을 우회하지 않도록 했기 때문에 DB 연동 결과를 성공으로 주장하지 않습니다.
- 테스트 runner에서 Node의 package module-type 성능 경고가 표시됐으나 테스트 실패는 없었습니다.

## 로컬 확인 및 남은 제약

기존 인증 설정과 `SCANNER_ALLOWED_ORIGIN`을 그대로 사용하고, 개발 서버 Origin과 정확히 맞춰 로컬에서 확인합니다. 같은 인증 세션으로 분석 시작 버튼을 누르면 로컬 요청 제한 오류 대신 요청 제한을 통과합니다. 그 다음 실제 분석은 기존대로 Supabase 설정 필요 응답을 내야 합니다. Supabase를 구성하지 않은 상태에서 이는 예상된 fail-closed 결과입니다. 상태/결과 GET은 Origin이 생략될 수 있어 browser Referer가 configured loopback origin과 일치할 때 로컬 limiter에 들어갑니다.

원격 Supabase query, 환경변수 변경, migration, package 변경은 수행하지 않았습니다. 운영 limiter 및 데이터 저장 검증은 전용 Supabase 환경을 별도 승인된 방식으로 구성한 후 staging에서 해야 합니다.
