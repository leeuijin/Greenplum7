Gㄴeenplum 7 쿼리 힌트

1. Greenplum 7 쿼리 힌트
   - Greenplum 7.2+ 에서 쿼리 힌트 지원
   - 쿼리 플랜 힌트 지원: Scan, Row Estimation, Join Order and Join Types.
   - Greenplum 7.2 Release note
     https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-greenplum/7/greenplum-database/relnotes-release-notes.html
   - Greenplum 쿼리 플랜 힌트
     https://techdocs.broadcom.com/us/en/vmware-tanzu/data-solutions/tanzu-greenplum/7/greenplum-database/admin_guide-query-topics-optimizer-hints.html


2. 쿼리 플랜 힌트 사용하기 위한 설정
--session level
LOAD 'pg_hint_plan';

--database level
ALTER DATABASE gpadmin SET session_preload_libraries='pg_hint_plan';

--user level
ALTER USER gpadmin SET session_preload_libraries='pg_hint_plan';

--check to enable pg_hint plan option
SHOW pg_hint_plan.enable_hint;
on

3. 쿼리 힌트 적용 예제
   1) pg_hint_plan 적용 
      ## Cardinality Hints
        - 특정 테이블에 대한 조인의 결과의 행 번호를 수정하도록 적용
        - 옵티마이저가 조인에서 출력되는 행 수를 부정확하게 추정하는 경우, 재분사 대신 브로드 캐스트 선택하거나, 
          HashJoin 대신 MergeJoin, NestLoop 조인등으로 최적화되지 않은 쿼리 플랜이 생성될 수 있음.
        - 특히, 통계 누락이나 오래된 데이터로 인하여 옵티마이저의 추정값이 부정확할 때 유용
        - 절대(#), 더하기(+), 빼기(-), 곱하기(*)를 이용하여 특정 테이블에 대한 조인 결과 행수를 수정하도록 적용(플랜 작성시 이용)
      /*+ Rows(t1 t2 t3 #42) */ SELECT * FROM t1, t2, t3; -- sets row estimate to 42
      /*+ Rows(t1 t2 t3 +42) */ SELECT * FROM t1, t2, t3; -- adds 42 to original row estimate
      /*+ Rows(t1 t2 t3 -42) */ SELECT * FROM t1, t2, t3; -- subtracts 42 from original row estimate
      /*+ Rows(t1 t2 t3 *42) */ SELECT * FROM t1, t2, t3; -- multiplies 42 with original row estimate


      ## Table Access Hints
        - 쿼리할 테이블의 스캔 유형과 인덱스를 지정하여, 데이터 스캔 적랼 최적화시 적용
        - 오래된 통계나 Cost/카니널리티의 잘못된 추정으로 인하여 옵티마이저가 비효율적인 스캔 방지를 위한 힌트  
      /*+ SeqScan(t1) */ SELECT * FROM t1 WHERE t1.a > 42; -- force sequential scan
      /*+ IndexScan(t1 my_index) */ SELECT * FROM t1 WHERE t1.a > 42; -- force index scan
      /*+ IndexOnlyScan(t1) */ SELECT * FROM t1 WHERE t1.a > 42; -- force index-only scan
      /*+ BitmapScan(t1 my_bitmap_index) */ SELECT * FROM t1 WHERE t1.a > 42; -- force bitmap index scan

      ## Join Type Hints
        - 조인 형태를 재정의 
        - 예상치 못한 계산 왜곡으로 인해 hash join으로 플랜을 짤 경우, 디스크로에 임시로 파일을 많이 사용하는 경우 발생되는데, 
          이를 인덱스를 이용하여 nestloop으로 변경이 가능 함.
        - nestloop 조인을 hash Join으로 변경도 가능.
      /*+ HashJoin(t1 t2) */ SELECT * FROM t1, t2;
      /*+ NestLoop(t1 t2) */ SELECT * FROM t1, t2;
      /*+ MergeJoin(t1 t2) */ SELECT * FROM t1 FULL JOIN t2 ON t1.a=t2.a;

      ## Join Order Hints
        - 조인 순서를 지정하여, 옵티마이저가 비효율적인 조인 전략을 피하도록 플랜 작성
      /*+ Leading(t1 t2 t3) */ SELECT * FROM t1, t2, t3;
      /*+ Leading(t1 (t3 t2)) */ SELECT * FROM t1, t2, t3;


   2) Greenplum GUC 세션 파라미터를 플랜에 적용
        - GUC 매개변수 값을 hist에 정의된 값으로 적용
        - 다른 hint와 충돌하는 경우 적용되지 않음.
      /*+ Set(enable_indexscan off)*/ SELECT * FROM t1, t2 WHERE t1.id = t2.id;

   3) Plan Hints Logging
       set pg_hint_plan.debug_print = on;
       set client_min_messages = 'log';
       /*+SeqScan(t1)IndexScan(t2)*/
       EXPLAIN (COSTS false) SELECT * FROM t1, t2 WHERE t1.id = t2.id;
       LOG:  pg_hint_plan:
       used hint:
       SeqScan(t1)
       IndexScan(t2)
       not used hint:
       duplication hint:
       error hint:
       
                        QUERY PLAN                 
       --------------------------------------------
        Hash Join
          Hash Cond: (t1.id = t2.id)
          ->  Seq Scan on t1
          ->  Hash
                ->  Index Scan using t2_pkey on t2
       (5 rows)    

4. 참고 사항
   1) pg_hint_plan는 GPORCA 및 Postgres 쿼리 플랜을 2개 모두 지원.
   2) GUC 쿼리 세션 파라미터로는 쿼리 플랜이 변경되지 않는 경우에도 힌트로 사용할 경우 쿼리 플랜을 변경할 수 있음.  
   3) 쿼리 플랜을 변경하는 경우에는 특정 패턴에 대해서만 적용하는 것을 추천 
       - 더 나은 플랜이 있더라도 사용자에 의해서 쿼리 플랜이 고정되기 때문에 주의가 필요 함.





