--Greenplum 7에서 파티션 관리

--##### 1.1 Greenplum 6 OR Greenplum 7 파티션 테이블 생성
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

SELECT t1.nspname, t2.relname
      , pg_get_expr(relpartbound, t2.oid)
      , relispartition 
      , t2.reloptions
  FROM pg_namespace t1
  JOIN pg_class t2
    ON t1.oid = t2.relnamespace
 WHERE 1=1
   AND t2.relispartition = TRUE 
   AND t1.nspname     = 'public'
   AND t2.relname LIKE 'order_log%' ;
   
nspname|relname              |pg_get_expr                                     |relispartition|reloptions                                                       |
-------+---------------------+------------------------------------------------+--------------+-----------------------------------------------------------------+
public |order_log_1_prt_p2001|FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|true          |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2002|FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|true          |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2003|FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|true          |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2004|FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|true          |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2005|FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|true          |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|

   
--##### 1.2 Greenplum 7 파티션 테이블 생성 (GP7만 지원) 
--테이블 생성시 테이블 압축 옵션 적용할 경우, 개별적 파티션을 만들때 압축 옵션이 자동 적용 됨.
--단,개별적 파티션에 저장 옵션을 적용할 경우,파티션 저장 옵션이 우선 함.
--Greenplum 6의 파티션 생성 명명법에 따라 파티션 명을 정하는 것이 좋음. _1_prt_일 경우 파티션 인지가 빠름.
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
;

SELECT t1.nspname, t2.relname
      , pg_get_expr(relpartbound, t2.oid)
      , relispartition 
      , t2.reloptions
  FROM pg_namespace t1
  JOIN pg_class t2
    ON t1.oid = t2.relnamespace
 WHERE 1=1
   AND t2.relispartition = TRUE 
   AND t1.nspname     = 'public'
   AND t2.relname LIKE 'order_log%' ;

--파티션이 생성되어 있지 않음.   
nspname|relname|pg_get_expr|relispartition|reloptions|
-------+-------+-----------+--------------+----------+   

-- 파티션 명을 테이블+파티션명으로 했을 경우 
CREATE TABLE public.order_log_p2001 PARTITION OF public.order_log FOR VALUES FROM ('2001-01-01'::date) TO ('2002-01-01'::date) WITH (appendonly=FALSE);
CREATE TABLE public.order_log_p2002 PARTITION OF public.order_log FOR VALUES FROM ('2002-01-01'::date) TO ('2003-01-01'::date) WITH (appendonly=TRUE, compresstype=zstd, compresslevel=1);
CREATE TABLE public.order_log_p2003 PARTITION OF public.order_log FOR VALUES FROM ('2003-01-01'::date) TO ('2004-01-01'::date) WITH (appendonly=TRUE, compresstype=zstd, compresslevel=2);
CREATE TABLE public.order_log_p2004 PARTITION OF public.order_log FOR VALUES FROM ('2004-01-01'::date) TO ('2005-01-01'::date) WITH (appendonly=TRUE, compresstype=zstd, compresslevel=3);
CREATE TABLE public.order_log_p2005 PARTITION OF public.order_log FOR VALUES FROM ('2005-01-01'::date) TO ('2006-01-01'::date);


SELECT t1.nspname, t2.relname
      , pg_get_expr(relpartbound, t2.oid)
      , relispartition 
      , t2.reloptions
  FROM pg_namespace t1
  JOIN pg_class t2
    ON t1.oid = t2.relnamespace
 WHERE 1=1
   AND t2.relispartition = TRUE 
   AND t1.nspname     = 'public'
   AND t2.relname LIKE 'order_log%' ;

nspname|relname        |pg_get_expr                                     |relispartition|reloptions                                                       |
-------+---------------+------------------------------------------------+--------------+-----------------------------------------------------------------+
public |order_log_p2001|FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|true          |NULL                                                             |
public |order_log_p2002|FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|true          |{compresstype=zstd,compresslevel=1,blocksize=32768,checksum=true}|
public |order_log_p2003|FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|true          |{compresstype=zstd,compresslevel=2,blocksize=32768,checksum=true}|
public |order_log_p2004|FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|true          |{compresstype=zstd,compresslevel=3,blocksize=32768,checksum=true}|
public |order_log_p2005|FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|true          |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|


-- Greenplum 7에서만 지원되는 형태, 파티션 테이블임을 선언만 하고, 개별적으로 파티션 만듬. 
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
;

-- 파티션 명을 [테이블명][_1_prt_][파티션명]으로 할 경우, 파티션 테이블 한번에 생성할 때의 파티션명과 동일
-- _1_prt_ ==> 첫번째 파티션
CREATE TABLE public.order_log_1_prt_p2001 PARTITION OF public.order_log FOR VALUES FROM ('2001-01-01'::date) TO ('2002-01-01'::date) WITH (appendonly=FALSE);
CREATE TABLE public.order_log_1_prt_p2002 PARTITION OF public.order_log FOR VALUES FROM ('2002-01-01'::date) TO ('2003-01-01'::date) WITH (appendonly=TRUE, compresstype=zstd, compresslevel=1);
CREATE TABLE public.order_log_1_prt_p2003 PARTITION OF public.order_log FOR VALUES FROM ('2003-01-01'::date) TO ('2004-01-01'::date) WITH (appendonly=TRUE, compresstype=zstd, compresslevel=2);
CREATE TABLE public.order_log_1_prt_p2004 PARTITION OF public.order_log FOR VALUES FROM ('2004-01-01'::date) TO ('2005-01-01'::date) WITH (appendonly=TRUE, compresstype=zstd, compresslevel=3);
CREATE TABLE public.order_log_1_prt_p2005 PARTITION OF public.order_log FOR VALUES FROM ('2005-01-01'::date) TO ('2006-01-01'::date);


SELECT t1.nspname, t2.relname
      , pg_get_expr(relpartbound, t2.oid)
      , relispartition 
      , t2.reloptions
  FROM pg_namespace t1
  JOIN pg_class t2
    ON t1.oid = t2.relnamespace
 WHERE 1=1
   AND t2.relispartition = TRUE 
   AND t1.nspname     = 'public'
   AND t2.relname LIKE 'order_log%' ;
--
nspname|relname              |pg_get_expr                                     |relispartition|reloptions                                                       |
-------+---------------------+------------------------------------------------+--------------+-----------------------------------------------------------------+
public |order_log_1_prt_p2001|FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|true          |NULL                                                             |
public |order_log_1_prt_p2002|FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|true          |{compresstype=zstd,compresslevel=1,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2003|FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|true          |{compresstype=zstd,compresslevel=2,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2004|FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|true          |{compresstype=zstd,compresslevel=3,blocksize=32768,checksum=true}|
public |order_log_1_prt_p2005|FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|true          |{compresstype=zstd,compresslevel=7,blocksize=32768,checksum=true}|


--##### 2.1 파티션 테이블의 Root 파티션에 데이터 적재 
--Root 파티션에 데이터 적재 
INSERT INTO public.order_log 
SELECT i order_no
     , i%100 cust_no
     , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
     , '2001-01-01'::date + i order_date
FROM   generate_series(1, 1825) i 
;

SELECT count(*) FROM public.order_log ;
--1,825 rows

--##### 2.2 특정 파티션에 DML 수행 
--해당 파티션에 데이터 적재 
SELECT count(*) FROM public.order_log_1_prt_p2001;
--364

TRUNCATE TABLE public.order_log;

--###################### 특정 파티션에  INSERT ######################
INSERT INTO public.order_log_1_prt_p2001 
SELECT i order_no
     , i%100 cust_no
     , 'prod_'||trim(to_char(i%50, '00000')) prod_nm  
     , '2001-01-01'::date + i order_date
FROM   generate_series(1, 364) i 
;
--364 rows 

--###################### 특정 파티션에  UPDATE ######################
UPDATE public.order_log_1_prt_p2001 
  SET  prod_nm = 'prod_name'
WHERE  order_date >= '2001-01-01'
AND    order_date <= '2001-12-31'
;
--364 rows

--###################### 특정 파티션에  DELETE ######################
DELETE FROM public.order_log_1_prt_p2001
WHERE  order_date >= '2001-01-01'
AND    order_date <= '2001-12-31'
;
--364 rows

--##### 3. 파티션 관리 
--파티션 생성, 추가, Detach & Attach, 파티션명 변경, 파티션 삭제, Default 파티션 추가 
--3.1 Greenplum 7 파티션 추가
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
   PARTITION p2003 start('2003-01-01'::date) END ('2004-01-01'::date)
)
;

--### Greenplum 7에서는 2가지 커멘드로 파티션을 추가 할 수 있음.
--1) Add Partition 방법 
ALTER TABLE public.order_log ADD PARTITION p2004 start('2004-01-01'::date) END ('2005-01-01'::date);


--2) 테이블을 생성하면서 Root 파티션의 일부로 인식하는 방식
--단이방식으로는 테이블명을  "_1_prt_" 까지 넣으면, 테이블 생성시의 파티션명 룰 또는 Add Partitoin과 동일한 네이밍룰을 따라 갈 수 있음.  
CREATE TABLE public.order_log_1_prt_p2005 PARTITION OF public.order_log FOR VALUES FROM ('2005-01-01'::date) TO ('2006-01-01'::date);

--3) Default 파티션 추가 
ALTER TABLE public.order_log ADD DEFAULT PARTITION pother;


SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;

--
schemaname|tablename|partitiontablename    |partitiontype|partitionboundary                               |
----------+---------+----------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2001 |range        |FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|
public    |order_log|order_log_1_prt_p2002 |range        |FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|
public    |order_log|order_log_1_prt_p2003 |range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004 |range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|
public    |order_log|order_log_1_prt_p2005 |range        |FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|
public    |order_log|order_log_1_prt_pother|range        |DEFAULT                                         |


--##### 3.2 파티션 Detach & Attach, 파티션명 변경, 파티션 삭제, Default 파티션 추가 
--특정 파티션을 일반 테이블로 생성함. 
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


SELECT t1.nspname, relname, relkind, relhassubclass, relispartition
  FROM pg_namespace t1
  JOIN pg_class t2 
    ON t1.oid = t2.relnamespace 
 WHERE 1=1
   AND t1.nspname = 'public'
   AND t2.relname LIKE 'order_log%';

--output
nspname|relname              |relkind|relhassubclass|relispartition|
-------+---------------------+-------+--------------+--------------+
public |order_log            |p      |true          |false         | ==> Root 파티
public |order_log_1_prt_p2001|r      |false         |true          | ==> 아래로 파티
public |order_log_1_prt_p2002|r      |false         |true          |
public |order_log_1_prt_p2003|r      |false         |true          |
public |order_log_1_prt_p2004|r      |false         |true          |
public |order_log_1_prt_p2005|r      |false         |true          | ==>DETACH 할 예정 


--파티션 Detach, order_log_1_prt_p2005 파티션이 파티션 분리 => 즉 특정 파티션을 테이블로 치환 
ALTER TABLE public.order_log DETACH PARTITION order_log_1_prt_p2005;


SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;
-- output 
schemaname|tablename|partitiontablename   |partitiontype|partitionboundary                               |
----------+---------+---------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2001|range        |FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|
public    |order_log|order_log_1_prt_p2002|range        |FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|
public    |order_log|order_log_1_prt_p2003|range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004|range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|

-- output   
SELECT t1.nspname, relname, relkind, relhassubclass, relispartition
  FROM pg_namespace t1
  JOIN pg_class t2 
    ON t1.oid = t2.relnamespace 
 WHERE 1=1
   AND t1.nspname = 'public'
   AND t2.relname LIKE 'order_log%';
nspname|relname              |relkind|relhassubclass|relispartition|
-------+---------------------+-------+--------------+--------------+
public |order_log            |p      |true          |false         |
public |order_log_1_prt_p2001|r      |false         |true          |
public |order_log_1_prt_p2002|r      |false         |true          |
public |order_log_1_prt_p2003|r      |false         |true          |
public |order_log_1_prt_p2004|r      |false         |true          |
public |order_log_1_prt_p2005|r      |false         |false         | ==> 기존 파티션이 일반 테이블로 분리. relispartition 필드가 FALSE 변경


--테이블과 파티션 이름이 혼동될 수 있어서 detach된 테이블명 이름 변경하는 것이 좋을 것 같음.
ALTER TABLE public.order_log_1_prt_p2005 RENAME TO order_log_p2005;

SELECT t1.nspname, relname, relkind, relhassubclass, relispartition
  FROM pg_namespace t1
  JOIN pg_class t2 
    ON t1.oid = t2.relnamespace 
 WHERE 1=1
   AND t1.nspname = 'public'
   AND t2.relname LIKE 'order_log%';

nspname|relname              |relkind|relhassubclass|relispartition|
-------+---------------------+-------+--------------+--------------+
public |order_log            |p      |true          |false         |
public |order_log_1_prt_p2001|r      |false         |true          |
public |order_log_1_prt_p2002|r      |false         |true          |
public |order_log_1_prt_p2003|r      |false         |true          |
public |order_log_1_prt_p2004|r      |false         |true          |
public |order_log_p2005      |r      |false         |false         |


--기존 테이블 Attach    
ALTER TABLE public.order_log ATTACH PARTITION order_log_p2005
FOR VALUES FROM ('2005-01-01'::date) TO ('2006-01-01'::date) --파티션 구간 
;

--
SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;
--output
schemaname|tablename|partitiontablename   |partitiontype|partitionboundary                               |
----------+---------+---------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2001|range        |FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|
public    |order_log|order_log_1_prt_p2002|range        |FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|
public    |order_log|order_log_1_prt_p2003|range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004|range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|
public    |order_log|order_log_p2005      |range        |FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')| --> Attach


--Greenplum 7에서의 파티션명 변경. 
ALTER TABLE  public.order_log_p2005 RENAME TO order_log_1_prt_p2005;

SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;

schemaname|tablename|partitiontablename   |partitiontype|partitionboundary                               |
----------+---------+---------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2001|range        |FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|
public    |order_log|order_log_1_prt_p2002|range        |FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|
public    |order_log|order_log_1_prt_p2003|range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004|range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|
public    |order_log|order_log_1_prt_p2005|range        |FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')| --> 파티션명 변경 

--Greenplum 7에서 Greenplum 6의 파티션명 변경 명령어는 수행되지 않음. => 에러 발
ALTER TABLE  public.order_log RENAME PARTITION p2005  TO _1_prt_p2005;

--##### 3.3 Greenplum 7 파티션 Drop 
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
   PARTITION p2003 start('2003-01-01'::date) END ('2004-01-01'::date)
)
;
CREATE TABLE public.order_log_1_prt_p2004 PARTITION OF public.order_log FOR VALUES FROM ('2004-01-01'::date) TO ('2005-01-01'::date);
CREATE TABLE public.order_log_1_prt_p2005 PARTITION OF public.order_log FOR VALUES FROM ('2005-01-01'::date) TO ('2006-01-01'::date);

SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;

 --output
schemaname|tablename|partitiontablename   |partitiontype|partitionboundary                               |
----------+---------+---------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2001|range        |FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|
public    |order_log|order_log_1_prt_p2002|range        |FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|
public    |order_log|order_log_1_prt_p2003|range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004|range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|
public    |order_log|order_log_1_prt_p2005|range        |FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|

--Greenplum 7에서 파티션 Drop  (파티션명으로 삭제)
ALTER TABLE public.order_log DROP PARTITION p2001;

--Greenplum 7에서 파티션 Drop  (파티션 구간으로 삭제 - 삭제시 FROM의 값을 지정 )
ALTER TABLE public.order_log DROP PARTITION FOR ('2002-01-01');


SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;

--output 
schemaname|tablename|partitiontablename   |partitiontype|partitionboundary                               |
----------+---------+---------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2003|range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004|range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|
public    |order_log|order_log_1_prt_p2005|range        |FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|



--##### 4. Default 파티션 Split 작업 
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
   PARTITION p2005 start('2005-01-01'::date) END ('2006-01-01'::date),
   DEFAULT PARTITION pother
)
;

SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;

schemaname|tablename|partitiontablename    |partitiontype|partitionboundary                               |
----------+---------+----------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2001 |range        |FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|
public    |order_log|order_log_1_prt_p2002 |range        |FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|
public    |order_log|order_log_1_prt_p2003 |range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004 |range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|
public    |order_log|order_log_1_prt_p2005 |range        |FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|
public    |order_log|order_log_1_prt_pother|range        |DEFAULT                                         |

ALTER TABLE public.order_log SPLIT DEFAULT PARTITION 
 START ('2006-01-01') INCLUSIVE END ('2007-01-01') EXCLUSIVE 
 INTO (PARTITION P2006, PARTITION POTHER)
;

SELECT schemaname, tablename, partitiontablename, partitiontype, partitionboundary
FROM  gp_toolkit.gp_partitions
WHERE schemaname = 'public'
AND   tablename  = 'order_log'
;

schemaname|tablename|partitiontablename    |partitiontype|partitionboundary                               |
----------+---------+----------------------+-------------+------------------------------------------------+
public    |order_log|order_log_1_prt_p2001 |range        |FOR VALUES FROM ('2001-01-01') TO ('2002-01-01')|
public    |order_log|order_log_1_prt_p2002 |range        |FOR VALUES FROM ('2002-01-01') TO ('2003-01-01')|
public    |order_log|order_log_1_prt_p2003 |range        |FOR VALUES FROM ('2003-01-01') TO ('2004-01-01')|
public    |order_log|order_log_1_prt_p2004 |range        |FOR VALUES FROM ('2004-01-01') TO ('2005-01-01')|
public    |order_log|order_log_1_prt_p2005 |range        |FOR VALUES FROM ('2005-01-01') TO ('2006-01-01')|
public    |order_log|order_log_1_prt_p2006 |range        |FOR VALUES FROM ('2006-01-01') TO ('2007-01-01')|
public    |order_log|order_log_1_prt_pother|range        |DEFAULT                                         |





   
