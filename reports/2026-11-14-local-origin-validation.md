# 로컬 출처 검증 불일치 수정 보고서

- 작업명: 로컬 분석 API Origin 검증 보정
- 기준일: 2026-11-14
- 대상: `C:\\Users\\PC1\\ai-trading-scanner`
- 범위: 개발 환경의 strict loopback origin 별칭 정규화, 테스트, 보고서 및 handover 갱신

## 조사 결과와 원인

- 로그인 POST는 `app/api/auth/login/route.ts`에서 `requireAllowedOrigin(request)`를 직접 호출합니다.
- 분석 시작 POST는 `app/api/analysis/start/route.ts`에서 `protectScannerApi(request, "analysis_start", true)`를 거칩니다. 공통 함수는 세션 검증 다음 `requireAllowedOrigin`을 실행하고, 그 뒤 limiter를 평가합니다.
- 분석 step POST도 `protectScannerApi(request, "analysis_step", true, runId)`를 사용하므로 동일한 순서로 Origin을 검사합니다.
- status/results는 GET이므로 `protectScannerApi`의 `requireOrigin` 옵션을 켜지 않습니다. 세션/요청 제한은 계속 적용하며, 로컬 limiter가 필요한 경우 Origin이 없으면 Referer의 origin을 가져와 loopback/configured-origin 조건을 확인합니다.
- Origin 검사 오류 문구는 `requireAllowedOrigin`에서만 반환됩니다. 따라서 분석 시작의 오류는 rate limiter가 아니라 Origin 비교에서 발생합니다. 로그인과 분석 POST는 같은 검증 함수를 씁니다.
- 비교 전 `SCANNER_ALLOWED_ORIGIN`은 URL `origin`으로 정규화됩니다(끝의 slash/default port/case 등 URL canonicalization). 기존 요청 비교는 그 정규값과 요청 origin의 완전 일치만 허용해, 개발 브라우저가 localhost, 127.0.0.1, IPv6 loopback 별칭으로 같은 서버에 접속하는 경우를 거부할 수 있었습니다.
- 현재 Chrome 자동화에서 확인된 탭은 ChatGPT 페이지였고 scanner localhost 탭이 아니었습니다. 따라서 사용자의 실제 POST Origin 및 GET Referer 값을 직접 캡처하지는 못했습니다. root cause는 코드 경로와 비교 방식으로 좁혔으며, 실제 요청 헤더가 host/port mismatch인지 별도로 관찰하지 않았습니다.

## 변경 파일

- `lib/scanner/auth-core.ts`: 요청 origin과 configured origin의 exact 비교를 유지하면서, 별도 허용 플래그가 켜진 경우에만 개발 loopback alias를 같은 scheme/effective port 범위로 정규화합니다. 이 별칭 허용은 nodeEnv=development 및 Vercel 미배포인 strict local-dev helper에서만 활성화됩니다.
- `lib/scanner/auth.ts`: shared origin guard가 loopback alias 허용 플래그를 개발 환경이고 Vercel이 아닐 때만 전달합니다. 로그인과 analysis POST는 기존 shared guard를 계속 씁니다.
- `tests/scanner-security.test.mjs`: exact origin, localhost↔127.0.0.1/IPv6 alias, port/scheme mismatch, 비-loopback, production 거부 및 Referer 파싱 사례를 보강했습니다.

분석 route, limiter policy, Supabase 호출/저장 로직, package, 환경변수, migration은 변경하지 않았습니다.

## 보안 경계

- alias 허용은 configured/request Origin 양쪽이 loopback일 때만 적용되고 scheme과 유효 port가 같아야 합니다.
- 다른 port, scheme mismatch, non-loopback host는 계속 거부합니다.
- production에서는 alias 허용 플래그가 false이고 HTTPS exact-origin 정책이 유지됩니다.
- Origin 검증을 제거하거나 임의 출처를 허용하지 않았습니다. Supabase limiter/data/task/owner 작업도 우회하지 않았습니다.
- GET의 Referer fallback은 로컬 개발 limiter의 origin 판정용입니다. 기존 status/results API를 state-changing 요청으로 바꾸지 않았고, 세션과 Supabase owner 확인도 유지했습니다.

## 검증

- `node --test tests/*.test.mjs`: **9/9 통과**
- `npm.cmd run lint`: **exit 0**
- `npm.cmd run build`: **exit 0**, Turbopack compile/type-check/static generation 완료
- 실제 브라우저 요청 header와 Supabase-backed 분석 E2E는 실행하지 않았습니다. 열린 Chrome 탭이 scanner 앱이 아니었으며 DB 설정을 우회하지 않았습니다.

## 로컬 재확인 및 남은 제한

Scanner를 연 주소와 `SCANNER_ALLOWED_ORIGIN`이 같은 scheme/port의 loopback 주소인지 확인합니다. 예: 브라우저 `http://localhost:3000`, 설정 `http://127.0.0.1:3000`은 development에서 허용됩니다. 서버 재기동 후 로그인하여 분석 시작을 재확인합니다. 다른 port인 localhost:3001 ↔ 127.0.0.1:3000은 계속 거부됩니다. limiter gate를 통과한 다음에도 Supabase가 미설정이면 분석 기능은 기존 fail-closed 응답을 반환해야 합니다.
