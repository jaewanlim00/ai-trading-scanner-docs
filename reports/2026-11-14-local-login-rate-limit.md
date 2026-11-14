# 로컬 개발 로그인 제한 보완 보고서

- 작업명: 로컬 개발 로그인 제한 보완
- 기준일: 2026-11-14
- 대상 코드 프로젝트: `C:\\Users\\PC1\\ai-trading-scanner`
- 범위: Supabase가 구성되지 않은 로컬 개발에서 로그인 요청에 한해 동일한 5회/15분 제한을 적용. 운영 환경과 분석/시장 API 제한은 기존 Supabase 경로 유지.

## 변경 파일

- `lib/scanner/auth-core.ts`: 정확히 일치하는 configured Origin과 localhost/127.0.0.1/::1, NODE_ENV=development, Vercel 미배포 조건을 모두 확인하는 local-origin 판별 함수를 추가했습니다.
- `lib/scanner/local-login-limiter.ts`: 프로세스 메모리의 fixed-window limiter를 추가했습니다.
- `lib/scanner/rate-limit.ts`: 로그인에만 local-development 조건부 limiter를 선택합니다. Vercel 환경, production, non-loopback 또는 Origin 불일치에서는 기존 Supabase RPC limiter를 사용합니다. limiter 한도는 기존 5회/15분입니다. 분석 관련 호출은 기존 Supabase limiter를 계속 사용합니다.
- `app/api/auth/login/route.ts`: 로그인 제한 분기 함수를 사용하도록 변경했습니다. 기존 Origin 검증, 비밀번호 검증, 세션 쿠키 처리는 유지했습니다.
- `tests/scanner-security.test.mjs`: loopback 및 production/Vercel/Origin 불일치 거부와 5회/15분 fixed-window 동작 테스트를 추가했습니다.

기존 작업 tree의 변경사항은 보존했습니다. package, 환경변수, migration, Supabase 설정 및 DB는 변경하지 않았습니다.

## 보안 조건과 동작

로컬 limiter는 다음 조건을 전부 만족할 때만 로그인 요청에 사용됩니다.

1. `NODE_ENV === "development"`
2. `VERCEL` 배포 표시가 없음
3. 요청 Origin이 설정된 `SCANNER_ALLOWED_ORIGIN`과 정확히 일치
4. Origin hostname이 localhost, 127.0.0.1 또는 ::1

조건 중 하나라도 불일치하면 메모리 limiter를 사용하지 않고 기존 Supabase limiter 경로로 진행합니다. Origin 검증은 login route에서 limiter 선택 전에 계속 실행됩니다. 비밀번호 비교, 세션 서명 및 만료 검증도 변경하지 않았습니다. 분석 start/step/status/results, markets의 Supabase 제한과 데이터 접근은 우회하지 않습니다.

로컬 제한 상태는 개발 서버 프로세스 메모리에 저장되므로 서버 재시작 시 초기화됩니다. 이는 개발 환경 전용이며 운영 환경에서 분산 제한을 대체하지 않습니다.

## 검증 결과

- `npm.cmd run lint`: exit 0
- `node --test tests/scanner-security.test.mjs`: 7/7 통과
- `npm.cmd run build`: exit 0, Turbopack compile, type check 및 static page generation 완료
- 로그인 API 실요청은 수행하지 않았습니다. 환경변수 값과 비밀정보를 확인하거나 수정하지 않았기 때문입니다. 실제 Supabase 로그인 제한과 영속 저장도 검증하지 않았습니다.

## 로컬 확인 방법

기존 인증 환경변수 설정을 사용하고, `SCANNER_ALLOWED_ORIGIN`이 브라우저 접속 origin과 정확히 같도록 구성합니다. 예를 들어 개발 서버를 localhost:3000으로 열면 허용 origin도 `http://localhost:3000`이어야 합니다. `NODE_ENV=development`로 로컬 서버를 실행하고 Vercel 배포 환경이 아닌 것을 확인한 뒤 로그인 화면에서 틀린 비밀번호를 반복 제출하면 다섯 번째 시도까지 기존 정책대로 허용되고, 이후 15분 동안 429 제한을 받습니다. 서버 재시작은 로컬 limiter 상태를 초기화합니다. 올바른 비밀번호의 성공 여부는 기존 password/session 설정에 달려 있습니다.

## 미해결 사항 및 다음 단계

- 로컬 limiter는 단일 개발 서버 프로세스 기준이며 재시작 후 카운터는 유지되지 않습니다. 로컬 전용 제약입니다.
- 운영 및 preview에서는 Supabase 설정과 DB migration이 필요합니다. 이 작업은 이를 설정하거나 적용하지 않았습니다.
- 별도 DB 설정 이후 staging에서 운영 Supabase limiter, 로그인 성공/실패, 분석 저장 흐름을 검증해야 합니다.
