-- Greenplum 7에서 테이블 스토리지 옵션 변경 
-- Greenplum 6에서는 스토리지 옵션 변경시 새로운 테이블 생성 후 적재를 해야 하지만, Greenplum 7에서는 ALTER 구문으로 스토리지 옵션 변경 지원 

--테이블 생성 
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


--스토리지 옵션 확인 
SELECT t1.nspname, t2.relname
      , pg_get_expr(relpartbound, t2.oid)
      , relispartition
      , t3.amname 
      , t2.reloptions
  FROM pg_namespace t1
  JOIN pg_class t2
    ON t1.oid = t2.relnamespace
  JOIN pg_am t3
    ON t2.relam = t3.oid
 WHERE 1=1
   AND t2.relispartition = TRUE 
   AND t1.nspname     = 'public'
   AND t2.relname LIKE 'order_log%' ;
   
nspname|relname              |pg_get_expr                                     |relispartition|amname|reloptions                                                       |
-------+---------------------+------------------------------------------------+--------------+------+-----------------------------------------------------------------+
public |order_log_1_prt_p2001|FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|true          |ao_row|{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2002|FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|true          |ao_row|{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2003|FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|true          |ao_row|{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2004|FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|true          |ao_row|{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2005|FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|true          |ao_row|{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|

--각 파티션에 데이터 적재 
INSERT INTO public.order_log 
SELECT i order_no
     , i%100 cust_no
     , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
     , '2001-01-01'::date + i order_date
FROM   generate_series(1, 1825) i 
;

--각각의 파티션에 압축 옵션 변경 
--일반 Heap 테이블로 변경 
ALTER TABLE public.order_log_1_prt_p2001 SET ACCESS METHOD heap;
--압축 레벨 변경 (row 압축일 때에는 옵션만 적용해도 스토리지 옵션변경 
ALTER TABLE public.order_log_1_prt_p2002 SET (compresstype=zstd,compresslevel=1) ;
--접근 방식이 row에서 row 일때 압축 옵션 적용 (위의 커멘드와 동일 )
ALTER TABLE public.order_log_1_prt_p2003 SET ACCESS METHOD ao_row WITH (compresstype=zstd,compresslevel=1);
--row 압축에서 컬럼 압축일 때 옵션, 
ALTER TABLE public.order_log_1_prt_p2004 SET ACCESS METHOD ao_column WITH (compresstype=zstd,compresslevel=1);



SELECT t1.nspname, t2.relname
      , pg_get_expr(relpartbound, t2.oid)
      , relispartition
      , t3.amname 
      , t2.reloptions
  FROM pg_namespace t1
  JOIN pg_class t2
    ON t1.oid = t2.relnamespace
  JOIN pg_am t3
    ON t2.relam = t3.oid
 WHERE 1=1
   AND t2.relispartition = TRUE 
   AND t1.nspname     = 'public'
   AND t2.relname LIKE 'order_log%' ;
   
 --기존 row 압축에서 compresstype=zstd, compresslevel=7에서 
 --각각의 스토리지 옵션 적용시 변경 후 현황   

nspname|relname              |pg_get_expr                                     |relispartition|amname   |reloptions                                                       |
-------+---------------------+------------------------------------------------+--------------+---------+-----------------------------------------------------------------+
public |order_log_1_prt_p2001|FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|true          |heap     |NULL                                                             |
public |order_log_1_prt_p2002|FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|true          |ao_row   |{blocksize=32768,checksum=true,compresstype=zstd,compresslevel=1}|
public |order_log_1_prt_p2003|FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|true          |ao_row   |{blocksize=32768,checksum=true,compresstype=zstd,compresslevel=1}|
public |order_log_1_prt_p2004|FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|true          |ao_column|{compresstype=zstd,compresslevel=1,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2005|FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|true          |ao_row   |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|




   
