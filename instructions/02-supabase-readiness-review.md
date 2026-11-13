# 2단계: Supabase 준비 상태 및 마이그레이션 안전성 검토

## 목적
AI Trading Scanner의 Supabase 연결 및 end-to-end 검증에 앞서, 기존 코드와 SQL migration을 읽기 전용으로 점검한다.

## 대상
- 코드 프로젝트: `C:\Users\PC1\ai-trading-scanner`
- 문서 저장소: `jaewanlim00/ai-trading-scanner-docs`
- 기준 상태: `handover/STATUS.md`
- 기존 migration: `supabase/migrations/20261114000100_scanner.sql`

## 이번 작업에서 허용되는 범위
1. 코드 프로젝트의 현재 Git 상태와 브랜치를 확인한다.
2. migration SQL 전체와 관련 Supabase 호출 코드를 읽고 구조를 설명한다.
3. 테이블, 인덱스, 제약조건, RPC 함수, RLS 정책 및 권한을 점검한다.
4. 서버 측 service role 사용 위치와 클라이언트 노출 가능성을 점검한다.
5. 작업 claim/lease, 중복 실행 방지, 동시성, 재시도, 실패 복구 흐름을 점검한다.
6. 필요한 경우 읽기 전용 명령과 로컬 빌드·테스트만 실행한다.
7. 문제를 심각도별로 분류하고, migration 적용 전 확인해야 할 사항과 안전한 적용 순서를 제안한다.

## 금지 사항
- Supabase 대시보드 또는 원격 DB에 접속해 SQL을 적용하지 않는다.
- migration을 실행하거나 원격 DB 데이터를 변경·삭제하지 않는다.
- 환경변수, API 키, service role key를 생성·변경·출력·커밋하지 않는다.
- 패키지 설치/제거, DB 스키마 수정, 코드 수정, 배포를 하지 않는다.
- 기존 사용자 변경사항이나 Git 작업물을 덮어쓰지 않는다.

## 반드시 확인할 내용
- migration이 신규 전용 DB를 전제로 하는지, 기존 데이터가 있을 때 충돌·손실 위험이 있는지
- RLS 활성화 여부와 정책의 실제 접근 범위
- service role 키가 서버 전용으로 제한되는지
- RPC 함수의 SECURITY DEFINER 여부, search_path 고정, 실행 권한 제한
- task claim이 원자적인지, 중복 worker가 같은 작업을 처리할 수 있는지
- lease 만료·재시도·실패 상태 전이가 일관적인지
- 결과·캔들 upsert의 conflict key와 중복 데이터 방지 조건
- Vercel 서버리스에서 step 실행 시간, 동시 요청, 재호출 시 안전성
- 인증 없는 API 호출이 데이터베이스 쓰기나 비용 소모를 유발할 수 있는지

## 결과물
다음 파일을 문서 저장소에 새로 작성한다.
- `reports/2026-11-14-supabase-readiness-review.md`

보고서에는 다음을 포함한다.
1. 검토한 코드 및 SQL 파일 목록
2. DB 구조와 데이터 흐름 요약
3. 정상 / 문제 / 실환경 검증 불가 항목 구분
4. 심각도(Critical / High / Medium / Low)와 근거
5. migration 적용 전 필수 수정·확인 사항
6. Supabase 적용 및 검증을 위한 단계별 실행 계획
7. 빌드·테스트 명령과 실제 결과
8. 변경 사항이 없음을 확인한 Git 상태

마지막으로 `handover/STATUS.md`를 갱신해 이번 검토 결과와 다음 단계를 반영한다. 단, 검토 결과를 사실대로 기록하고 미검증 항목을 완료로 표시하지 않는다.

## 완료 기준
- 코드 프로젝트에는 어떠한 파일 변경도 없어야 한다.
- 원격 Supabase에는 어떠한 변경도 없어야 한다.
- 문서 저장소에는 보고서와 최신 handover만 반영한다.
- 완료 후 커밋 SHA, 변경 문서, 미해결 위험, 다음 승인 필요 사항을 보고한다.
