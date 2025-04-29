Greenplum 7에서 추가된 BRIN INDEX  

1.BRIN (Block Range Index)
  - 블럭 범위의 인덱스로 스캔에 불필요한 block를 skip하기 위한 인덱스 
  - 블럭의 Min, Max 값을 이용하기 때문에, 인덱스 사이즈가 작은 장점이 있음.
  - 다만, 블럭에 여러개의 값이 들어갈 경우 효과가 떨어짐. 
  - BRIN INDEX 설명: https://www.youtube.com/watch?v=--KCYkWbY6M
  
2.BRIN INDEX 적용 유형 
  - 같은 데이터가 같은 블럭에 많이 분포될 경우 유리 -> 시계열 데이터
  - 일련 번호가 올라가는 구성 유리 

3.예제 설명 
  - 프로젝트 중 2개의 시계열 컬럼이 있었는데, 2개 컬럼 모두 사용하는 경우  
    . 이중 하나는 Greenplum에서 분석용도로 파티션 컬럼으로 활용, --order_dt
    . 다른 하나 컬럼은 원소스 시스템의 파티션 컬럼, ETL/마이그레이션시 검증용 컬럼 --sys_dt 
  - TABLE 구성 
    . 1일 1만건 데이터 적재
    . 월 파티션 + zstd7 압 
    . 파티션 키:  order_dt 
    . BRIN INDEX: sys_dt 
    
4. 테스트 결과 
  - 파티션 테이블에 인덱스 사용시 optimizer=OFF 할 때 인덱스 스캔 수행 
  - 테이블은 압축되지만, 인덱스는 압축되지 않음.
  - Btree index는 90MB 이지만, Brin index는 1.5MB 정도. 60배 정도 사이즈가 줄어 듬.
  - 인덱스 스캔시 btree아 brin간에는 차이가 없음.

4.1 SET optimizer = OFF;
  - 인덱스 스캔 수행으로 성능 개선 
---------------------------------------------------------------------------------------------------
                            |FULL scan | 파티션 스캔 | 인덱스 스캔 | 인덱스  | 파티션 사이즈 | 파티션 인덱스 사이즈| 
                            |(sys_dt)  | order_dt | sys_dt   | 생성시간 | zstd 7 압축 |     (비압축)    |
----------------------------|----------|---------|-----------|-------|------------|----------------|
NO INDEX                    |  6.71sec | 0.59sec |           |       |    6.6MB   |                |
btree idx                   |          |         |  0.10sec  |19.7sec|    6.6MB   |      90.0MB    |
brin idx(default)           |          |         |  0.09sec  | 7.9sec|    6.6MB   |       1.5MB    |
brin idx(pages_per_range=4) |          |         |  0.08sec  | 8.2sec|    6.6MB   |       1.5MB    |
----------------------------------------------------------------------------------------------------

4.2 SET optimizer = ON;     
  - 인덱스를 사용하더라도 사용하지 않음.
---------------------------------------------------------------------------------------------------
                            |FULL scan | 파티션 스캔 | 인덱스 스캔 | 인덱스  | 파티션 사이즈 | 파티션 인덱스 사이즈| 
                            |(sys_dt)  | order_dt | sys_dt   | 생성시간 | zstd 7 압축 |     (비압축)    |
----------------------------|----------|---------|-----------|-------|------------|----------------|
NO INDEX                    |  6.71sec | 0.59sec |           |       |    6.6MB   |                |
btree idx                   |          |         |미사용(6.8s) |20.0sec|    6.6MB   |      90.0MB    |
brin idx(default)           |          |         |미사용(6.7s) | 8.3sec|    6.6MB   |       1.5MB    |
brin idx(pages_per_range=4) |          |         |미사용(6.9s) | 8.2sec|    6.6MB   |       1.5MB    |
----------------------------------------------------------------------------------------------------


5. 테스트 스크립트   
5.1 테이블 생성 및 적재   

DROP TABLE IF EXISTS public.order_log;
CREATE TABLE public.order_log
(
    order_no      int, 
    cust_no       int,
    prod_nm       varchar(20),
    order_dt      varchar(8),
    sys_dt        varchar(8)
)
WITH (appendonly=TRUE, compresstype=zstd, compresslevel=7)
DISTRIBUTED BY (order_no)
PARTITION BY RANGE (order_dt)
(
   PARTITION p200101 start('20010101') END ('20010201'), 
   PARTITION p200102 start('20010201') END ('20010301'), 
   PARTITION p200103 start('20010301') END ('20010401'), 
   PARTITION p200104 start('20010401') END ('20010501'), 
   PARTITION p200105 start('20010501') END ('20010601'), 
   PARTITION p200106 start('20010601') END ('20010701'), 
   PARTITION p200107 start('20010701') END ('20010801'), 
   PARTITION p200108 start('20010801') END ('20010901'), 
   PARTITION p200109 start('20010901') END ('20011001'), 
   PARTITION p200110 start('20011001') END ('20011101'), 
   PARTITION p200111 start('20011101') END ('20011201'), 
   PARTITION p200112 start('20011201') END ('20020101')
)
;

--데이터 적재 
--1년 데이터 일괄 적재 
INSERT INTO public.order_log
SELECT i order_no
     , i%100 cust_no
     , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
     , to_char('2001-01-01'::date + i, 'yyyymmdd') order_dt
     , to_char('2001-01-01'::date + i + 1, 'yyyymmdd') sys_dt
  FROM generate_series(1, 364) i
     , generate_series(1, 100000) j
      
;
Inserted ROWS: 36400000

/*
--1년 데이터를 1일씩 데이터 적재
--카티션 조인한 것과 조회실행 시간과는 차이가 없었음. 
TRUNCATE TABLE public.order_log ;
DO $$
BEGIN
    FOR i in 1..364 LOOP
      INSERT INTO public.order_log
      SELECT i order_no
           , i%100 cust_no
           , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
           , to_char('2001-01-01'::date + i, 'yyyymmdd') order_dt
           , to_char('2001-01-01'::date + i + 1, 'yyyymmdd') sys_dt
        FROM generate_series(1, 100000) j;
    END LOOP;
END $$;
 */

ANALYZE public.order_log;



--######################################################################################
6. 인덱스 종류별 사이트 확인 및 조회 시간 추출 (Optimizer=off)
SET optimizer=off;

--------##########  Full 스캔, 파티션 스캔 
gpadmin=# SELECT count(*) FROM public.order_log;
  count
----------
 36400000
(1 row)

Time: 6711.915 ms (00:06.712)

--Full Scan + GPORCA off
SELECT count(*) 
FROM   public.order_log
WHERE  sys_dt >= '20010103'
AND    sys_dt <= '20010105';

 count
--------
 300000
(1 row)

Time: 6824.244 ms (00:06.824)
gpadmin=#

--파티션 Scan + GPORCA off
SELECT count(*) 
FROM   public.order_log
WHERE  order_dt >= '20010103'
AND    order_dt <= '20010105';

 count
--------
 300000
(1 row)

Time: 594.700 ms
gpadmin=#

--------##########  Btree Index 스캔  + GPORCA off
CREATE INDEX ixb_order_log_sys_dt ON public.order_log USING btree(sys_dt);
CREATE INDEX
Time: 19695.137 ms (00:19.695)
gpadmin=# \dt+ public.order_log*
                                            List of relations
 Schema |              Name               |       Type        |  Owner  | Storage |  Size   | Description
--------+---------------------------------+-------------------+---------+---------+---------+-------------
 public | order_log                       | partitioned table | gpadmin | ao_row  | 0 bytes |
 public | order_log_1_prt_p200101         | table             | gpadmin | ao_row  | 6692 kB |
 public | order_log_1_prt_p200102         | table             | gpadmin | ao_row  | 6328 kB |
 public | order_log_1_prt_p200103         | table             | gpadmin | ao_row  | 6878 kB |
 public | order_log_1_prt_p200104         | table             | gpadmin | ao_row  | 6611 kB |
 public | order_log_1_prt_p200105         | table             | gpadmin | ao_row  | 6896 kB |
 public | order_log_1_prt_p200106         | table             | gpadmin | ao_row  | 6616 kB |
 public | order_log_1_prt_p200107         | table             | gpadmin | ao_row  | 6896 kB |
 public | order_log_1_prt_p200108         | table             | gpadmin | ao_row  | 6897 kB |
 public | order_log_1_prt_p200109         | table             | gpadmin | ao_row  | 6715 kB |
 public | order_log_1_prt_p200110         | table             | gpadmin | ao_row  | 6896 kB |
 public | order_log_1_prt_p200111         | table             | gpadmin | ao_row  | 6711 kB |
 public | order_log_1_prt_p200112         | table             | gpadmin | ao_row  | 6896 kB |

gpadmin=# \di+ order_log_1_prt_p2001*
                                               List of relations
 Schema |                Name                | Type  |  Owner  |          Table          | Size  | Description
--------+------------------------------------+-------+---------+-------------------------+-------+-------------
 public | order_log_1_prt_p200101_sys_dt_idx | index | gpadmin | order_log_1_prt_p200101 | 90 MB |
 public | order_log_1_prt_p200102_sys_dt_idx | index | gpadmin | order_log_1_prt_p200102 | 84 MB |
 public | order_log_1_prt_p200103_sys_dt_idx | index | gpadmin | order_log_1_prt_p200103 | 93 MB |
 public | order_log_1_prt_p200104_sys_dt_idx | index | gpadmin | order_log_1_prt_p200104 | 90 MB |
 public | order_log_1_prt_p200105_sys_dt_idx | index | gpadmin | order_log_1_prt_p200105 | 93 MB |
 public | order_log_1_prt_p200106_sys_dt_idx | index | gpadmin | order_log_1_prt_p200106 | 90 MB |
 public | order_log_1_prt_p200107_sys_dt_idx | index | gpadmin | order_log_1_prt_p200107 | 93 MB |
 public | order_log_1_prt_p200108_sys_dt_idx | index | gpadmin | order_log_1_prt_p200108 | 93 MB |
 public | order_log_1_prt_p200109_sys_dt_idx | index | gpadmin | order_log_1_prt_p200109 | 90 MB |
 public | order_log_1_prt_p200110_sys_dt_idx | index | gpadmin | order_log_1_prt_p200110 | 93 MB |
 public | order_log_1_prt_p200111_sys_dt_idx | index | gpadmin | order_log_1_prt_p200111 | 90 MB |
 public | order_log_1_prt_p200112_sys_dt_idx | index | gpadmin | order_log_1_prt_p200112 | 93 MB |
(12 rows)

--EXPLAIN ANALYZE 
SELECT count(*) 
FROM   public.order_log
WHERE  sys_dt >= '20010103'
AND    sys_dt <= '20010105';
 count
--------
 300000
(1 row)

Time: 104.626 ms

DROP INDEX ixb_order_log_sys_dt;

--------########## BRIN Index 스캔 - Default   + GPORCA off
CREATE INDEX ixbrin_order_log_sys_dt ON public.order_log USING brin(sys_dt);
CREATE INDEX
Time: 7936.710 ms (00:07.937)
gpadmin=# \di+ order_log_1_prt_p2001*_sys_dt_idx
                                                List of relations
 Schema |                Name                | Type  |  Owner  |          Table          |  Size   | Description
--------+------------------------------------+-------+---------+-------------------------+---------+-------------
 public | order_log_1_prt_p200101_sys_dt_idx | index | gpadmin | order_log_1_prt_p200101 | 1568 kB |
 public | order_log_1_prt_p200102_sys_dt_idx | index | gpadmin | order_log_1_prt_p200102 | 1568 kB |
 public | order_log_1_prt_p200103_sys_dt_idx | index | gpadmin | order_log_1_prt_p200103 | 1568 kB |
 public | order_log_1_prt_p200104_sys_dt_idx | index | gpadmin | order_log_1_prt_p200104 | 1408 kB |
 public | order_log_1_prt_p200105_sys_dt_idx | index | gpadmin | order_log_1_prt_p200105 | 1568 kB |
 public | order_log_1_prt_p200106_sys_dt_idx | index | gpadmin | order_log_1_prt_p200106 | 1408 kB |
 public | order_log_1_prt_p200107_sys_dt_idx | index | gpadmin | order_log_1_prt_p200107 | 1568 kB |
 public | order_log_1_prt_p200108_sys_dt_idx | index | gpadmin | order_log_1_prt_p200108 | 1568 kB |
 public | order_log_1_prt_p200109_sys_dt_idx | index | gpadmin | order_log_1_prt_p200109 | 1568 kB |
 public | order_log_1_prt_p200110_sys_dt_idx | index | gpadmin | order_log_1_prt_p200110 | 1568 kB |
 public | order_log_1_prt_p200111_sys_dt_idx | index | gpadmin | order_log_1_prt_p200111 | 1568 kB |
 public | order_log_1_prt_p200112_sys_dt_idx | index | gpadmin | order_log_1_prt_p200112 | 1568 kB |
(12 rows)


--EXPLAIN ANALYZE 
SELECT count(*) 
FROM   public.order_log
WHERE  sys_dt >= '20010103'
AND    sys_dt <= '20010105';
 count
--------
 300000
(1 row)

Time: 90.161 ms
gpadmin=#
DROP INDEX ixbrin_order_log_sys_dt;

--------########## BRIN Index 스캔 - pages_per_range=4   + GPORCA off
CREATE INDEX ixbrin_order_log_sys_dt ON public.order_log USING brin(sys_dt) WITH (pages_per_range=4);
CREATE INDEX
Time: 8209.303 ms (00:08.209)
gpadmin=# \di+ order_log_1_prt_p2001*_sys_dt_idx
                                                List of relations
 Schema |                Name                | Type  |  Owner  |          Table          |  Size   | Description
--------+------------------------------------+-------+---------+-------------------------+---------+-------------
 public | order_log_1_prt_p200101_sys_dt_idx | index | gpadmin | order_log_1_prt_p200101 | 1568 kB |
 public | order_log_1_prt_p200102_sys_dt_idx | index | gpadmin | order_log_1_prt_p200102 | 1568 kB |
 public | order_log_1_prt_p200103_sys_dt_idx | index | gpadmin | order_log_1_prt_p200103 | 1568 kB |
 public | order_log_1_prt_p200104_sys_dt_idx | index | gpadmin | order_log_1_prt_p200104 | 1408 kB |
 public | order_log_1_prt_p200105_sys_dt_idx | index | gpadmin | order_log_1_prt_p200105 | 1568 kB |
 public | order_log_1_prt_p200106_sys_dt_idx | index | gpadmin | order_log_1_prt_p200106 | 1408 kB |
 public | order_log_1_prt_p200107_sys_dt_idx | index | gpadmin | order_log_1_prt_p200107 | 1568 kB |
 public | order_log_1_prt_p200108_sys_dt_idx | index | gpadmin | order_log_1_prt_p200108 | 1568 kB |
 public | order_log_1_prt_p200109_sys_dt_idx | index | gpadmin | order_log_1_prt_p200109 | 1568 kB |
 public | order_log_1_prt_p200110_sys_dt_idx | index | gpadmin | order_log_1_prt_p200110 | 1568 kB |
 public | order_log_1_prt_p200111_sys_dt_idx | index | gpadmin | order_log_1_prt_p200111 | 1568 kB |
 public | order_log_1_prt_p200112_sys_dt_idx | index | gpadmin | order_log_1_prt_p200112 | 1568 kB |

--EXPLAIN ANALYZE 
SELECT count(*) 
FROM   public.order_log
WHERE  sys_dt >= '20010103'
AND    sys_dt <= '20010105';

 count
--------
 300000
(1 row)

Time: 82.105 ms
gpadmin=#

drop index ixbrin_order_log_sys_dt;



--######################################################################################
7. 인덱스 종류별 사이트 확인 및 조회 시간 추출 (Optimizer=on)
SET optimizer=on;
--------##########  Btree Index 스캔  + GPORCA on
CREATE INDEX ixb_order_log_sys_dt ON public.order_log USING btree(sys_dt);
CREATE INDEX
Time: 19992.654 ms (00:19.993)
gpadmin=# \di+ order_log_1_prt_p2001*
                                               List of relations
 Schema |                Name                | Type  |  Owner  |          Table          | Size  | Description
--------+------------------------------------+-------+---------+-------------------------+-------+-------------
 public | order_log_1_prt_p200101_sys_dt_idx | index | gpadmin | order_log_1_prt_p200101 | 90 MB |
 public | order_log_1_prt_p200102_sys_dt_idx | index | gpadmin | order_log_1_prt_p200102 | 84 MB |
 public | order_log_1_prt_p200103_sys_dt_idx | index | gpadmin | order_log_1_prt_p200103 | 93 MB |
 public | order_log_1_prt_p200104_sys_dt_idx | index | gpadmin | order_log_1_prt_p200104 | 90 MB |
 public | order_log_1_prt_p200105_sys_dt_idx | index | gpadmin | order_log_1_prt_p200105 | 93 MB |
 public | order_log_1_prt_p200106_sys_dt_idx | index | gpadmin | order_log_1_prt_p200106 | 90 MB |
 public | order_log_1_prt_p200107_sys_dt_idx | index | gpadmin | order_log_1_prt_p200107 | 93 MB |
 public | order_log_1_prt_p200108_sys_dt_idx | index | gpadmin | order_log_1_prt_p200108 | 93 MB |
 public | order_log_1_prt_p200109_sys_dt_idx | index | gpadmin | order_log_1_prt_p200109 | 90 MB |
 public | order_log_1_prt_p200110_sys_dt_idx | index | gpadmin | order_log_1_prt_p200110 | 93 MB |
 public | order_log_1_prt_p200111_sys_dt_idx | index | gpadmin | order_log_1_prt_p200111 | 90 MB |
 public | order_log_1_prt_p200112_sys_dt_idx | index | gpadmin | order_log_1_prt_p200112 | 93 MB |
(12 rows)

--EXPLAIN ANALYZE 
SELECT count(*) 
FROM   public.order_log
WHERE  sys_dt >= '20010103'
AND    sys_dt <= '20010105';

 count
--------
 300000
(1 row)

Time: 6832.338 ms (00:06.832)

drop index ixb_order_log_sys_dt;

--------########## BRIN Index 스캔 - Default   + GPORCA on
CREATE INDEX ixbrin_order_log_sys_dt ON public.order_log USING brin(sys_dt);
CREATE INDEX
Time: 8308.608 ms (00:08.309)
gpadmin=# \di+ order_log_1_prt_p2001*_sys_dt_idx
                                                List of relations
 Schema |                Name                | Type  |  Owner  |          Table          |  Size   | Description
--------+------------------------------------+-------+---------+-------------------------+---------+-------------
 public | order_log_1_prt_p200101_sys_dt_idx | index | gpadmin | order_log_1_prt_p200101 | 1568 kB |
 public | order_log_1_prt_p200102_sys_dt_idx | index | gpadmin | order_log_1_prt_p200102 | 1568 kB |
 public | order_log_1_prt_p200103_sys_dt_idx | index | gpadmin | order_log_1_prt_p200103 | 1568 kB |
 public | order_log_1_prt_p200104_sys_dt_idx | index | gpadmin | order_log_1_prt_p200104 | 1408 kB |
 public | order_log_1_prt_p200105_sys_dt_idx | index | gpadmin | order_log_1_prt_p200105 | 1568 kB |
 public | order_log_1_prt_p200106_sys_dt_idx | index | gpadmin | order_log_1_prt_p200106 | 1408 kB |
 public | order_log_1_prt_p200107_sys_dt_idx | index | gpadmin | order_log_1_prt_p200107 | 1568 kB |
 public | order_log_1_prt_p200108_sys_dt_idx | index | gpadmin | order_log_1_prt_p200108 | 1568 kB |
 public | order_log_1_prt_p200109_sys_dt_idx | index | gpadmin | order_log_1_prt_p200109 | 1568 kB |
 public | order_log_1_prt_p200110_sys_dt_idx | index | gpadmin | order_log_1_prt_p200110 | 1568 kB |
 public | order_log_1_prt_p200111_sys_dt_idx | index | gpadmin | order_log_1_prt_p200111 | 1568 kB |
 public | order_log_1_prt_p200112_sys_dt_idx | index | gpadmin | order_log_1_prt_p200112 | 1568 kB |
(12 rows)


--EXPLAIN ANALYZE 
SELECT count(*) 
FROM   public.order_log
WHERE  sys_dt >= '20010103'
AND    sys_dt <= '20010105';

 count
--------
 300000
(1 row)

Time: 6715.830 ms (00:06.716)
gpadmin=#
DROP INDEX ixbrin_order_log_sys_dt;

--------########## BRIN Index 스캔 - pages_per_range=4   + GPORCA on
CREATE INDEX ixbrin_order_log_sys_dt ON public.order_log USING brin(sys_dt) WITH (pages_per_range=4);
CREATE INDEX
Time: 8191.656 ms (00:08.192)
gpadmin=# \di+ order_log_1_prt_p2001*_sys_dt_idx
                                                List of relations
 Schema |                Name                | Type  |  Owner  |          Table          |  Size   | Description
--------+------------------------------------+-------+---------+-------------------------+---------+-------------
 public | order_log_1_prt_p200101_sys_dt_idx | index | gpadmin | order_log_1_prt_p200101 | 1568 kB |
 public | order_log_1_prt_p200102_sys_dt_idx | index | gpadmin | order_log_1_prt_p200102 | 1568 kB |
 public | order_log_1_prt_p200103_sys_dt_idx | index | gpadmin | order_log_1_prt_p200103 | 1568 kB |
 public | order_log_1_prt_p200104_sys_dt_idx | index | gpadmin | order_log_1_prt_p200104 | 1408 kB |
 public | order_log_1_prt_p200105_sys_dt_idx | index | gpadmin | order_log_1_prt_p200105 | 1568 kB |
 public | order_log_1_prt_p200106_sys_dt_idx | index | gpadmin | order_log_1_prt_p200106 | 1408 kB |
 public | order_log_1_prt_p200107_sys_dt_idx | index | gpadmin | order_log_1_prt_p200107 | 1568 kB |
 public | order_log_1_prt_p200108_sys_dt_idx | index | gpadmin | order_log_1_prt_p200108 | 1568 kB |
 public | order_log_1_prt_p200109_sys_dt_idx | index | gpadmin | order_log_1_prt_p200109 | 1568 kB |
 public | order_log_1_prt_p200110_sys_dt_idx | index | gpadmin | order_log_1_prt_p200110 | 1568 kB |
 public | order_log_1_prt_p200111_sys_dt_idx | index | gpadmin | order_log_1_prt_p200111 | 1568 kB |
 public | order_log_1_prt_p200112_sys_dt_idx | index | gpadmin | order_log_1_prt_p200112 | 1568 kB |
(12 rows)

--EXPLAIN ANALYZE 
SELECT count(*) 
FROM   public.order_log
WHERE  sys_dt >= '20010103'
AND    sys_dt <= '20010105';

 count
--------
 300000
(1 row)

Time: 6913.908 ms (00:06.914)

drop index ixbrin_order_log_sys_dt;


