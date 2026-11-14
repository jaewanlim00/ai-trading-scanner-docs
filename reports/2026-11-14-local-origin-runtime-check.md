# 로컬 Origin 런타임 확인 보충

- 기준일: 2026-11-14
- 관련 보고서: `reports/2026-11-14-local-origin-validation.md`
- 현재 환경에서 `SCANNER_ALLOWED_ORIGIN` 값만 선택적으로 확인한 결과: `http://localhost:3000`
- 비밀번호 및 Supabase 키를 포함한 다른 환경변수는 읽거나 기록하지 않았습니다.
- 현재 점검 시점에 로컬 포트 3000/3001 listener는 없었습니다.
- 사용 가능한 Chrome automation 대상은 scanner localhost 탭이 아니라 ChatGPT 페이지였습니다. 따라서 문제 발생 당시 브라우저의 POST Origin과 GET Referer 실제 값은 관측할 수 없었습니다.

## 해석

로그인 POST와 analysis start/step POST는 같은 `requireAllowedOrigin()` 구현을 공유합니다. 두 요청이 같은 페이지 origin, 같은 서버 프로세스, 같은 환경설정을 사용했다면 출처 판정 결과도 같아야 합니다. 따라서 최근 limiter 분기 자체가 두 POST 사이의 Origin 결과 차이를 만들지는 않습니다.

코드에서 확인된 거부 조건은 설정 origin과 요청 origin의 scheme/host/effective port 불일치입니다. 흔한 localhost 별칭 차이는 이번 수정으로 같은 scheme/port loopback 범위 안에서만 처리합니다. 예를 들어 configured origin이 localhost:3000이고 실제 요청 Origin이 127.0.0.1:3000이면 개발 환경에서 허용됩니다. 포트나 scheme이 다르면 계속 차단됩니다.

실제 로컬 오류의 개별 원인은 브라우저 주소와 네트워크 탭의 실패 POST Origin 값을 함께 확인해야 확정할 수 있습니다. `SCANNER_ALLOWED_ORIGIN`은 현재 localhost:3000으로 설정되어 있으므로, 개발 서버가 다른 포트에 뜬 경우 설정을 그 포트로 맞추는 절차가 필요합니다. 이번 작업에서는 환경설정을 변경하지 않았습니다.
