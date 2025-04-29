--Greenplum 7.2에서 테스트 결과
--Greenplum 7 버전에서는  ANALYZE, COPY, VACUUM, 인덱스 생성에 대해서 
--pg_stat_progress_xxxx 와 같은 View로 상태 확인
--테스트 결과 상태 코드 변경은 있지만, select 구문으로 copy로 사용할 때 진행율 확인 가능 

--모니터링을 위한 view 
pg_catalog.gp_stat_progress_analyze
pg_catalog.gp_stat_progress_copy
pg_catalog.gp_stat_progress_create_index
pg_catalog.gp_stat_progress_vacuum

-------------------
--테이블 생성 
------------------
DROP TABLE IF EXISTS public.order_log;
CREATE TABLE public.order_log
(
    order_no      int, 
    cust_no       int,
    prod_nm       TEXT,
    order_date    date
)
WITH (appendonly=TRUE, compresstype=zstd, compresslevel=7)
DISTRIBUTED BY (order_no)
PARTITION BY RANGE (order_date)
(
   PARTITION p2001 start('2001-01-01'::date) END ('2002-01-01'::date), 
   PARTITION p2002 start('2002-01-01'::date) END ('2003-01-01'::date), 
   PARTITION p2003 start('2003-01-01'::date) END ('2004-01-01'::date), 
   PARTITION p2004 start('2004-01-01'::date) END ('2005-01-01'::date), 
   PARTITION p2005 start('2005-01-01'::date) END ('2006-01-01'::date)
)
;

--테스트를 위한 테이블 적재 
TRUNCATE TABLE public.order_log_1_prt_p2001 ;
INSERT INTO public.order_log_1_prt_p2001
SELECT i order_no
     , i%100 cust_no
     , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
     , '2001-01-01'::date + i order_date
  FROM generate_series(1, 364) i
     , generate_series(1, 100000) j
      
;

--사이즈 확인 
gpadmin=# \dt+ public.order_log_1_prt_p2001
                                List of relations
 Schema |         Name          | Type  |  Owner  | Storage | Size  | Description
--------+-----------------------+-------+---------+---------+-------+-------------
 public | order_log_1_prt_p2001 | table | gpadmin | ao_row  | 57 MB |
(1 row)

gpadmin=#

-----------------------
--Analyze 
-----------------------
--별도의 터미널 창에서 수행 
ANALYZE public.order_log_1_prt_p2001;

--Analyze 진행 확인용 쿼리 
SELECT t01.nspname, t02.relname, t03.phase 
  FROM pg_namespace t01, pg_class t02, pg_catalog.pg_stat_progress_analyze t03 
 WHERE t01.oid = t02.relnamespace 
   AND t02.oid = t03.relid ;
   
---Analyze 수행시 진행상황 output
Wed Aug 14 09:54:38 KST 2024
 nspname | relname | phase
---------+---------+-------
(0 rows)

Wed Aug 14 09:54:38 KST 2024
 nspname |        relname        |         phase
---------+-----------------------+-----------------------
 public  | order_log_1_prt_p2001 | acquiring sample rows
(1 row)

Wed Aug 14 09:54:38 KST 2024
 nspname |        relname        |         phase
---------+-----------------------+-----------------------
 public  | order_log_1_prt_p2001 | acquiring sample rows
(1 row)

Wed Aug 14 09:54:38 KST 2024
 nspname |        relname        |         phase
---------+-----------------------+-----------------------
 public  | order_log_1_prt_p2001 | acquiring sample rows
(1 row)

Wed Aug 14 09:54:38 KST 2024
 nspname |        relname        |         phase
---------+-----------------------+-----------------------
 public  | order_log_1_prt_p2001 | acquiring sample rows
(1 row)

Wed Aug 14 09:54:39 KST 2024
 nspname |        relname        |        phase
---------+-----------------------+----------------------
 public  | order_log_1_prt_p2001 | computing statistics
(1 row)

Wed Aug 14 09:54:39 KST 2024
 nspname | relname | phase
---------+---------+-------
(0 rows)

-----------------------
--Copy  
-----------------------
--진행상황 확인 쿼리 
SELECT t02.query
     , t01.command, t01.TYPE, t01.bytes_processed, t01.bytes_total, t01.tuples_processed, t01.tuples_excluded
  FROM pg_catalog.pg_stat_progress_copy t01
  JOIN pg_stat_activity t02
    ON t01.pid = t02.pid
;  

-- select를 인자로 이용하는 copy에서는 진행상황 확인 가능 
gpadmin=# copy (select * from public.order_log_1_prt_p2001) to '/home/gpadmin/public.order_log';
COPY 36400000
Time: 321715.246 ms (05:21.715)


--진행상황 output
query                                                                                   |command|type|bytes_processed|bytes_total|tuples_processed|tuples_excluded|
----------------------------------------------------------------------------------------+-------+----+---------------+-----------+----------------+---------------+
copy (select * from public.order_log_1_prt_p2001) to '/home/gpadmin/public.order_log' ¶;|COPY TO|FILE|      470446126|          0|        16662990|              0|

query                                                                                   |command|type|bytes_processed|bytes_total|tuples_processed|tuples_excluded|
----------------------------------------------------------------------------------------+-------+--------+---------------+-----------+----------------+---------------+
copy (select * from public.order_log_1_prt_p2001) to '/home/gpadmin/public.order_log' ¶;|COPY TO|FILE|      583004040|          0|        20558760|              0|

--테이블을 인자로 이용하는 copy에서는 진행율 체크가 안됨.
gpadmin=# copy public.order_log_1_prt_p2001 to '/home/gpadmin/public.order_log'
;

--진행상황 output
query                                                                   |command|type|bytes_processed|bytes_total|tuples_processed|tuples_excluded|
------------------------------------------------------------------------+-------+----+---------------+-----------+----------------+---------------+
copy public.order_log_1_prt_p2001 to '/home/gpadmin/public.order_log' ¶;|COPY TO|FILE|              0|          0|               0|              0|

query                                                                   |command|type|bytes_processed|bytes_total|tuples_processed|tuples_excluded|
------------------------------------------------------------------------+-------+----+---------------+-----------+----------------+---------------+
copy public.order_log_1_prt_p2001 to '/home/gpadmin/public.order_log' ¶;|COPY TO|FILE|              0|          0|               0|              0|


VACUUM order_log_1_prt_p2001;

-----------------------
--Create Index   
-----------------------
--파티션 테이블에 인덱스를 생성하였을때, partitions_total 컬럼에 파티션 개수가 나옴.
--파티션에 인덱스를 생성하였을때 현재 진행상황에 대해서만 확인 가능 

--파티션 테이블에 인덱스 생성 
DROP INDEX IF EXISTS public.idx_order_no;
CREATE INDEX idx_order_no ON public.order_log (order_no);


select * from pg_catalog.pg_stat_progress_create_index;

pid    |datid|datname|relid |index_relid|command     |phase                                 |lockers_total|lockers_done|current_locker_pid|blocks_total|blocks_done|tuples_total|tuples_done|partitions_total|partitions_done|
-------+-----+-------+------+-----------+------------+--------------------------------------+-------------+------------+------------------+------------+-----------+------------+-----------+----------------+---------------+
3534938|19576|gpadmin|559288|          0|CREATE INDEX|building index: loading tuples in tree|            0|           0|                 0|           0|          0|           0|          0|               5|              5|

pid    |datid|datname|relid |index_relid|command     |phase                                 |lockers_total|lockers_done|current_locker_pid|blocks_total|blocks_done|tuples_total|tuples_done|partitions_total|partitions_done|
-------+-----+-------+------+-----------+------------+--------------------------------------+-------------+------------+------------------+------------+-----------+------------+-----------+----------------+---------------+
3534938|19576|gpadmin|559288|          0|CREATE INDEX|building index: loading tuples in tree|            0|           0|                 0|           0|          0|           0|          0|               5|              5|

--파티션 테이블에 인덱스 생성 
DROP INDEX IF EXISTS public.idx_order_no_1_p2001;
CREATE INDEX idx_order_no_1_p2001 ON public.order_log_1_prt_p2001(order_no);
select * from pg_catalog.pg_stat_progress_create_index;

pid    |datid|datname|relid |index_relid|command     |phase                                 |lockers_total|lockers_done|current_locker_pid|blocks_total|blocks_done|tuples_total|tuples_done|partitions_total|partitions_done|
-------+-----+-------+------+-----------+------------+--------------------------------------+-------------+------------+------------------+------------+-----------+------------+-----------+----------------+---------------+
3534938|19576|gpadmin|559290|          0|CREATE INDEX|building index: loading tuples in tree|            0|           0|                 0|           0|          0|           0|          0|               0|              0|

pid    |datid|datname|relid |index_relid|command     |phase                                 |lockers_total|lockers_done|current_locker_pid|blocks_total|blocks_done|tuples_total|tuples_done|partitions_total|partitions_done|
-------+-----+-------+------+-----------+------------+--------------------------------------+-------------+------------+------------------+------------+-----------+------------+-----------+----------------+---------------+
3534938|19576|gpadmin|559290|          0|CREATE INDEX|building index: loading tuples in tree|            0|           0|                 0|           0|          0|           0|          0|               0|              0|

-----------------------
--VACUUM  
-----------------------
TRUNCATE TABLE public.order_log_1_prt_p2001 ;
INSERT INTO public.order_log_1_prt_p2001
SELECT i order_no
     , i%100 cust_no
     , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
     , '2001-01-01'::date + i order_date
  FROM generate_series(1, 364) i
     , generate_series(1, 100000) j

DELETE FROM public.order_log_1_prt_p2001
WHERE order_no % 2 = 0;

INSERT INTO public.order_log_1_prt_p2001
SELECT *
  FROM (
        SELECT i order_no
             , i%100 cust_no
             , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
             , '2001-01-01'::date + i order_date
          FROM generate_series(1, 364) i
             , generate_series(1, 100000) j
) tmp01 
WHERE tmp01.order_no % 2 = 0;

--다른 창에서 수행 
VACUUM public.order_log_1_prt_p2001;

--VACUUM 상태 확인 
select * from pg_catalog.pg_stat_progress_vacuum  ;

pid    |datid|datname|relid |phase                   |heap_blks_total|heap_blks_scanned|heap_blks_vacuumed|index_vacuum_count|max_dead_tuples|num_dead_tuples|
-------+-----+-------+------+------------------------+---------------+-----------------+------------------+------------------+---------------+---------------+
3534938|19576|gpadmin|559290|append-optimized compact|              0|                0|                 0|                 0|              0|              0|

pid    |datid|datname|relid |phase                   |heap_blks_total|heap_blks_scanned|heap_blks_vacuumed|index_vacuum_count|max_dead_tuples|num_dead_tuples|
-------+-----+-------+------+------------------------+---------------+-----------------+------------------+------------------+---------------+---------------+
3534938|19576|gpadmin|559290|append-optimized compact|              0|                0|                 0|                 0|              0|              0|

pid    |datid|datname|relid |phase                   |heap_blks_total|heap_blks_scanned|heap_blks_vacuumed|index_vacuum_count|max_dead_tuples|num_dead_tuples|
-------+-----+-------+------+------------------------+---------------+-----------------+------------------+------------------+---------------+---------------+
3534938|19576|gpadmin|559290|append-optimized compact|              0|                0|                 0|                 0|              0|              0|


