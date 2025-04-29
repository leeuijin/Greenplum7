Greenplum 7에서는 Convering 인덱스를 제공
Covering 인덱스는 인덱스 컬럼 이외에 자주 Access되는 컬럼을 추가하여 INDEX ONLY Scan 되도록 수행

테스트 결과, 
조회 조건이 INDEX 컬럼과 조회 컬럼을 같이 있을 경우 INDEX ONLY scan으로 플랜이 만들어지나, 
필터링 조건이 추가될때 INDEX ONLY scan이 아닌 INDEX scan으로 플랜 생성 

성능적인 측면에서는 테스트 데이터 사이즈가 작기 때문에 효과는 미지수이나, 
대용량 데이터 처리시에는 추가 테스트가 필요 함.

1. 세션 파라미터 확인 - DEFAULT 설정일 경우 
SHOW optimizer; --ON 
SHOW enable_indexonlyscan; --ON 
SHOW optimizer_enable_dynamicindexonlyscan; --ON 
SHOW optimizer_enable_indexonlyscan; --ON 


2. 마스터성 테이블일 경우 커버링 인덱스 테스트 
DROP TABLE IF EXISTS public.customer;
CREATE TABLE public.customer
(
    cust_no int, 
    cust_nm TEXT,
    gender  varchar(1),
    status_yn varchar(1)
)
WITH (appendonly=TRUE, compresstype=zstd, compresslevel=7)
DISTRIBUTED BY (cust_no)
;

INSERT INTO public.customer 
SELECT i, 'cust_nm_'||trim(to_char(i, '000'))
     , CASE WHEN (i % 2) = 0 THEN 'M' ELSE 'F' END gender
     , CASE WHEN (i % 50) = 0 THEN 'N' ELSE 'Y' END status_yn
FROM   generate_series(1, 10000) i 
;

--일반 인덱스 테스트 
DROP INDEX IF EXISTS public.ixu_customer_cust_no;
CREATE UNIQUE INDEX ixu_customer_cust_no ON public.customer(cust_no);

EXPLAIN ANALYZE 
SELECT cust_no, cust_nm
  FROM public.customer
 WHERE cust_no = 100;
 
 QUERY PLAN                                                                                                                       |
---------------------------------------------------------------------------------------------------------------------------------+
Gather Motion 1:1  (slice1; segments: 1)  (cost=0.00..387.96 rows=1 width=16) (actual time=0.857..0.858 rows=1 loops=1)          |
  ->  Bitmap Heap Scan on customer  (cost=0.00..387.96 rows=1 width=16) (actual time=0.292..0.294 rows=1 loops=1)                |
        Recheck Cond: (cust_no = 100)                                                                                            |
        Heap Blocks: exact=1                                                                                                     |
        ->  Bitmap Index Scan on ixu_customer_cust_no  (cost=0.00..0.00 rows=0 width=0) (actual time=0.081..0.082 rows=1 loops=1)|
              Index Cond: (cust_no = 100)                                                                                        |
Optimizer: GPORCA                                                                                                                |
Planning Time: 2.613 ms                                                                                                          |
  (slice0)    Executor memory: 52K bytes.                                                                                        |
  (slice1)    Executor memory: 368K bytes (seg7).                                                                                |
Memory used:  128000kB                                                                                                           |
Execution Time: 1.585 ms                                                                                                         |



--Covering 인덱스 테스트 
DROP INDEX IF EXISTS public.ixu_customer_cust_no;
DROP INDEX IF EXISTS public.ixu_customer_cust_no_covering;
CREATE UNIQUE INDEX ixu_customer_cust_no_covering ON public.customer(cust_no) INCLUDE (cust_nm);

--필 조건에 인덱스 컬럼과 조회 컬럼에 including 컬럼이 추가될 때 index only scan 수행 
EXPLAIN ANALYZE  
SELECT cust_no, cust_nm
  FROM public.customer
 WHERE cust_no = 100;

 QUERY PLAN                                                                                                                                        |
--------------------------------------------------------------------------------------------------------------------------------------------------+
Gather Motion 1:1  (slice1; segments: 1)  (cost=0.00..6.00 rows=1 width=16) (actual time=0.794..0.796 rows=1 loops=1)                             |
  ->  Index Only Scan using ixu_customer_cust_no_covering on customer  (cost=0.00..6.00 rows=1 width=16) (actual time=0.159..0.160 rows=1 loops=1)|
        Index Cond: (cust_no = 100)                                                                                                               |
        Heap Fetches: 0                                                                                                                           |
Optimizer: GPORCA                                                                                                                                 |
Planning Time: 2.410 ms                                                                                                                           |
  (slice0)    Executor memory: 14K bytes.                                                                                                         |
  (slice1)    Executor memory: 147K bytes (seg7).                                                                                                 |
Memory used:  128000kB                                                                                                                            |
Execution Time: 1.447 ms    |

--필터 조건에 커버링 인덱스이외의 컬럼이 있을 경우 index only scan이 수행되지 않음. - 일반 index 스캔 수행  
EXPLAIN ANALYZE  
SELECT cust_no, cust_nm
  FROM public.customer
 WHERE cust_no = 100
   AND status_yn = 'Y' ;
 
QUERY PLAN                                                                                                                                      |
------------------------------------------------------------------------------------------------------------------------------------------------+
Result  (cost=0.00..387.96 rows=1 width=16) (actual time=0.738..0.739 rows=0 loops=1)                                                           |
  ->  Gather Motion 1:1  (slice1; segments: 1)  (cost=0.00..387.96 rows=1 width=16) (actual time=0.738..0.738 rows=0 loops=1)                   |
        ->  Bitmap Heap Scan on customer  (cost=0.00..387.96 rows=1 width=16) (actual time=0.000..0.157 rows=0 loops=1)                         |
              Recheck Cond: (cust_no = 100)                                                                                                     |
              Filter: ((status_yn)::text = 'Y'::text)                                                                                           |
              ->  Bitmap Index Scan on ixu_customer_cust_no_covering  (cost=0.00..0.00 rows=0 width=0) (actual time=0.009..0.009 rows=1 loops=1)|
                    Index Cond: (cust_no = 100)                                                                                                 |
Optimizer: GPORCA                                                                                                                               |
Planning Time: 3.510 ms                                                                                                                         |
  (slice0)    Executor memory: 57K bytes.                                                                                                       |
  (slice1)    Executor memory: 370K bytes (seg7).                                                                                               |
Memory used:  128000kB                                                                                                                          |
Execution Time: 1.367 ms    


3. 이력성 파티션 테이블에서의 커버링 인덱스 테스트 
--커버링 인덱스 컬럼 이외의 조건 추가시 일반 index 스캔 수행 (index only scan 수행되지 않음.)
DROP TABLE IF EXISTS public.order_log;
CREATE TABLE public.order_log
(
    order_no      int, 
    cust_no       int,
    prod_nm       TEXT,
    order_date    varchar(8), 
    order_amt     int
)
WITH (appendonly=TRUE, compresstype=zstd, compresslevel=7)
DISTRIBUTED BY (order_no)
PARTITION BY RANGE (order_date)
(
   PARTITION p2001 start('20010101') END ('20020101'), 
   PARTITION p2002 start('20020101') END ('20030101'), 
   PARTITION p2003 start('20030101') END ('20040101'), 
   PARTITION p2004 start('20040101') END ('20050101'), 
   PARTITION p2005 start('20050101') END ('20060101'), 
   PARTITION p2006 start('20060101') END ('20070101'), 
   PARTITION p2007 start('20070101') END ('20080101'), 
   PARTITION p2008 start('20080101') END ('20090101'), 
   PARTITION p2009 start('20090101') END ('20100101'),
   PARTITION p2010 start('20100101') END ('20110101')
)
;

INSERT INTO public.order_log
SELECT i*j order_no
     , j%100 cust_no
     , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
     , to_char('2001-01-01'::date + i, 'yyyymmdd') order_dt
     , round(random()*100)::int * 100  sys_dt
  FROM generate_series(1, 364) i
     , generate_series(1, 10000) j   
;

DROP INDEX IF EXISTS public.ixu_order_log_cust_no;
DROP INDEX IF EXISTS public.ixu_order_log_cust_no_convering;


CREATE INDEX ixu_order_log_cust_no ON public.order_log(cust_no);
ANALYZE public.order_log;

SET optimizer =ON;

EXPLAIN ANALYZE 
SELECT sum(order_amt)
  FROM public.order_log
WHERE  cust_no = 1
AND    order_date >= '20010101'
AND    order_date <  '20020101'
;

QUERY PLAN                                                                                                                                               |
---------------------------------------------------------------------------------------------------------------------------------------------------------+
Finalize Aggregate  (cost=0.00..418.62 rows=1 width=8) (actual time=35.349..35.351 rows=1 loops=1)                                                       |
  ->  Gather Motion 8:1  (slice1; segments: 8)  (cost=0.00..418.62 rows=1 width=8) (actual time=29.441..35.328 rows=8 loops=1)                           |
        ->  Partial Aggregate  (cost=0.00..418.62 rows=1 width=8) (actual time=35.095..35.096 rows=1 loops=1)                                            |
              ->  Dynamic Bitmap Heap Scan on order_log  (cost=0.00..418.62 rows=1273 width=4) (actual time=1.889..28.300 rows=4680 loops=1)             |
                    Number of partitions to scan: 1 (out of 10)                                                                                          |
                    Recheck Cond: (cust_no = 1)                                                                                                          |
                    Filter: ((cust_no = 1) AND ((order_date)::text >= '20010101'::text) AND ((order_date)::text < '20020101'::text))                     |
                    Heap Blocks: exact=1                                                                                                                 |
                    Partitions scanned:  Avg 1.0 x 8 workers.  Max 1 parts (seg0).                                                                       |
                    ->  Dynamic Bitmap Index Scan on ixu_order_log_cust_no  (cost=0.00..0.00 rows=0 width=0) (actual time=1.274..1.275 rows=4680 loops=1)|
                          Index Cond: (cust_no = 1)                                                                                                      |
Optimizer: GPORCA                                                                                                                                        |
Planning Time: 20.110 ms                                                                                                                                 |
  (slice0)    Executor memory: 34K bytes.                                                                                                                |
  (slice1)    Executor memory: 2434K bytes avg x 8 workers, 2434K bytes max (seg0).                                                                      |
Memory used:  128000kB                                                                                                                                   |
Execution Time: 36.671 ms                                                                                                                                |

SET optimizer =OFF;
EXPLAIN ANALYZE 
SELECT sum(order_amt)
  FROM public.order_log
WHERE  cust_no = 1
AND    order_date >= '20010101'
AND    order_date <  '20020101'
;

QUERY PLAN                                                                                                                                                        |
------------------------------------------------------------------------------------------------------------------------------------------------------------------+
Finalize Aggregate  (cost=590.62..590.63 rows=1 width=8) (actual time=33.021..33.023 rows=1 loops=1)                                                              |
  ->  Gather Motion 8:1  (slice1; segments: 8)  (cost=590.50..590.60 rows=8 width=8) (actual time=25.173..32.979 rows=8 loops=1)                                  |
        ->  Partial Aggregate  (cost=590.50..590.51 rows=1 width=8) (actual time=31.201..31.202 rows=1 loops=1)                                                   |
              ->  Bitmap Heap Scan on order_log_1_prt_p2001  (cost=371.02..579.31 rows=4474 width=4) (actual time=0.858..28.146 rows=4680 loops=1)                |
                    Recheck Cond: (cust_no = 1)                                                                                                                   |
                    Filter: (((order_date)::text >= '20010101'::text) AND ((order_date)::text < '20020101'::text))                                                |
                    Heap Blocks: exact=14                                                                                                                         |
                    ->  Bitmap Index Scan on order_log_1_prt_p2001_cust_no_idx  (cost=0.00..369.90 rows=4474 width=0) (actual time=0.439..0.439 rows=4680 loops=1)|
                          Index Cond: (cust_no = 1)                                                                                                               |
Optimizer: Postgres-based planner                                                                                                                                 |
Planning Time: 0.295 ms                                                                                                                                           |
  (slice0)    Executor memory: 69K bytes.                                                                                                                         |
  (slice1)    Executor memory: 2430K bytes avg x 8 workers, 2430K bytes max (seg0).                                                                               |
Memory used:  128000kB                                                                                                                                            |
Execution Time: 34.320 ms   

--------###################
DROP INDEX IF EXISTS public.ixu_order_log_cust_no;
DROP INDEX IF EXISTS public.ixu_order_log_cust_no_convering;

CREATE INDEX ixu_order_log_cust_no_convering ON public.order_log(cust_no) INCLUDE(order_amt);
ANALYZE public.order_log;

SET optimizer =ON;
EXPLAIN ANALYZE 
SELECT sum(order_amt)
  FROM public.order_log
WHERE  cust_no = 1
AND    order_date >= '20010101'
AND    order_date <  '20020101'
;
QUERY PLAN                                                                                                                                                         |
-------------------------------------------------------------------------------------------------------------------------------------------------------------------+
Finalize Aggregate  (cost=0.00..415.71 rows=1 width=8) (actual time=48.383..48.386 rows=1 loops=1)                                                                 |
  ->  Gather Motion 8:1  (slice1; segments: 8)  (cost=0.00..415.71 rows=1 width=8) (actual time=43.469..48.363 rows=8 loops=1)                                     |
        ->  Partial Aggregate  (cost=0.00..415.71 rows=1 width=8) (actual time=47.047..47.049 rows=1 loops=1)                                                      |
              ->  Dynamic Bitmap Heap Scan on order_log  (cost=0.00..415.71 rows=1152 width=4) (actual time=2.796..47.208 rows=4680 loops=1)                       |
                    Number of partitions to scan: 1 (out of 10)                                                                                                    |
                    Recheck Cond: (cust_no = 1)                                                                                                                    |
                    Filter: ((cust_no = 1) AND ((order_date)::text >= '20010101'::text) AND ((order_date)::text < '20020101'::text))                               |
                    Heap Blocks: exact=1                                                                                                                           |
                    Partitions scanned:  Avg 1.0 x 8 workers.  Max 1 parts (seg0).                                                                                 |
                    ->  Dynamic Bitmap Index Scan on ixu_order_log_cust_no_convering  (cost=0.00..0.00 rows=0 width=0) (actual time=2.265..2.266 rows=4680 loops=1)|
                          Index Cond: (cust_no = 1)                                                                                                                |
Optimizer: GPORCA                                                                                                                                                  |
Planning Time: 30.877 ms                                                                                                                                           |
  (slice0)    Executor memory: 34K bytes.                                                                                                                          |
  (slice1)    Executor memory: 2434K bytes avg x 8 workers, 2434K bytes max (seg0).                                                                                |
Memory used:  128000kB                                                                                                                                             |
Execution Time: 49.816 ms   

SET optimizer =off;
EXPLAIN ANALYZE 
SELECT sum(order_amt)
  FROM public.order_log
WHERE  cust_no = 1
AND    order_date >= '20010101'
AND    order_date <  '20020101'
;

QUERY PLAN                                                                                                                                                                  |
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
Finalize Aggregate  (cost=547.54..547.55 rows=1 width=8) (actual time=46.434..46.435 rows=1 loops=1)                                                                        |
  ->  Gather Motion 8:1  (slice1; segments: 8)  (cost=547.42..547.52 rows=8 width=8) (actual time=31.647..46.368 rows=8 loops=1)                                            |
        ->  Partial Aggregate  (cost=547.42..547.43 rows=1 width=8) (actual time=34.170..34.171 rows=1 loops=1)                                                             |
              ->  Bitmap Heap Scan on order_log_1_prt_p2001  (cost=337.43..537.30 rows=4049 width=4) (actual time=0.875..39.432 rows=4680 loops=1)                          |
                    Recheck Cond: (cust_no = 1)                                                                                                                             |
                    Filter: (((order_date)::text >= '20010101'::text) AND ((order_date)::text < '20020101'::text))                                                          |
                    Heap Blocks: exact=14                                                                                                                                   |
                    ->  Bitmap Index Scan on order_log_1_prt_p2001_cust_no_order_amt_idx  (cost=0.00..336.42 rows=4049 width=0) (actual time=0.526..0.526 rows=4680 loops=1)|
                          Index Cond: (cust_no = 1)                                                                                                                         |
Optimizer: Postgres-based planner                                                                                                                                           |
Planning Time: 0.201 ms                                                                                                                                                     |
  (slice0)    Executor memory: 69K bytes.                                                                                                                                   |
  (slice1)    Executor memory: 2430K bytes avg x 8 workers, 2430K bytes max (seg0).                                                                                         |
Memory used:  128000kB                                                                                                                                                      |
Execution Time: 48.352 ms                                                                                                                                                   |

