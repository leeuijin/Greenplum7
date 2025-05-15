# Greenplum 7 개선 
- Greenplum 7은 기존 core PostgreSQL엔진을 9.6에서 12로 업그레이드
- Greenplum 6 core 엔진 : PostgreSQL 9.6
- Greenplum 7 core 엔진 : PostgreSQL 12
- Greenplum 8 core 엔진 : 현재까지 계획은 PostgreSQL 15+


## 성능 개선
- JIT 컴파일 지원: 쿼리 플랜을 기계어로 컴파일 후 쿼리 수행
- 정렬 속도 개선: varchar, text, numeric 컬럼 정렬 속도 개선
- Index only scan : heap 테이블에 인덱스 온리 스캔 지원, Covering index 지원
- BRIN/Hash 인덱스 지원 
- 워크로드 관리 : Resource Group v2 지원, Disk IO 컨트롤
- pg_hint_plan: 쿼리 힌트 플랜 지원(테이블 스캔, Row Estimation, Join 순서 및 유형)

## 개발 생산성 
- 프로시저 트랜잭션 지원: 프로시저 지원, 프로시저 내에 Commit 지원
- upsert 지원: Insert 구문 수행시 키 값 충돌시 update 수행
- 제너레이티드 컬럼: 컬럼을 활용해서 자동 생성되는 컬럼

## 관리 개선
- 효율적인 스키마 변경: Alter Table 구문으로 스토리지 옵션 변경 및 컬럼 추가
- 압축 테이블에 PK/UK 지원 
- 파티션 관리 개선: 파티션 Attach, Detach 기능 추가 
- 운영 명령어 모니터링 지원: pg_stat_progress_xxxx view 제공

## 통계 수집 개선
- 멀티컬럼 통계(MCV): 멀티 컬럼의 통계 수집 지원
- 압축 테이블에 Analyze 성능 개선
- 카탈로그 테이블 통계 자동 수집(auto vacuum/auto analyze 수행)

## 보안 강화
- row 레벨 보안
- 감사 기능 제공(pgaudit)
