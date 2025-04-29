1. Greenplum 7 프로시저 
Greenplum 7에서는 프로시저를 지원, Greenplum 6까지는 Function으로 프로시저를 지원하였음.
배치 업무를 위한 함수와 프로시저의 차이점
 1) 함수로 프로시저를 만들 경우
    - 함수내에서 COMMIT; Rollback을 사용할 수 없음.
    - 즉, 함수로 프로시저를 수행하는 동안 어디까지 진행되는지를 job 이력 테이블로는 확인이 불가능
 2) 프로시저를 이용하는 경우 - ONLY Greenplum 7
    - 프로시저 중간에 COMMIT;을 이용하여 현재 진행상황을 Job 이력 테이블에 UPDATE 하여, 진행상황을 알 수 있음.
 3) Greenplum 6에서 배치 함수의 진행상황 확인하는 방법 
    - 함수내에서 NOTICE를 이용하여, 메시지로 확인이 가능하였음.

2. Greenplum 7의 Upsert 
Greenplum 7에서는 INSERT시 키 중복이 될 경우 update를 지원 
아래 예제에서는 job 이력 로그에 job이름과 job 실행일자가 유니크하고, 
재수행할 경우 업데이트로 수행 함.
   INSERT INTO TABLE xxxx 
   VALUES ()
   ON CONFLICT (키값) DO UPDATE
   SET 


--테스트 테이블 
DROP TABLE IF EXISTS public.order_log;
CREATE TABLE public.order_log
(
    order_no      int, 
    cust_no       int,
    prod_nm       varchar(20),
    order_dt    varchar(8)
)
WITH (appendonly=TRUE, compresstype=zstd, compresslevel=7)
DISTRIBUTED BY (order_no)
PARTITION BY RANGE (order_dt)
(
   PARTITION p2001 start('20010101') END ('20020101'), 
   PARTITION p2002 start('20020101') END ('20030101'), 
   PARTITION p2003 start('20030101') END ('20040101'), 
   PARTITION p2004 start('20040101') END ('20050101'), 
   PARTITION p2005 start('20050101') END ('20060101')
)
;

--Job 수행 이력 로깅 테이블 
DROP TABLE IF EXISTS public.tb_sp_job_log;
CREATE TABLE public.tb_sp_job_log (
  job_nm       varchar(63),
  job_base_dt  varchar(8),
  job_start_ts timestamp,
  job_end_ts   timestamp,
  rows         bigint,
  job_status   char(1),  --R:Running, S:Success, F:Failure
  query        text,
  err_msg      text
) 
DISTRIBUTED BY (job_nm, job_base_dt);

CREATE UNIQUE INDEX ixu_tb_sp_job_log ON public.tb_sp_job_log(job_nm, job_base_dt);

-- Job 수행 프로시저 
DROP PROCEDURE public.sp_test_upsert(v_date IN varchar(8)) ;
CREATE OR REPLACE PROCEDURE public.sp_test_upsert(v_date IN varchar(8)) 
LANGUAGE plpgsql
AS 
$$
DECLARE 
  
  v_tmp     text;
  v_job_nm  text;
  v_rows    integer;   
  v_sql     text;

  v_err_msg  text;
  v_err_cd   TEXT;
  v_err_context TEXT;
   
BEGIN
     
      --현재 프로시져 명을 추출  
      GET DIAGNOSTICS v_tmp = PG_CONTEXT;
      v_job_nm := split_part((substring(v_tmp from 'function (.*?) line'))::regprocedure::text, '(', 1);
      --select usename, sess_id into v_usr, v_ssid from pg_stat_activity where pid = pg_backend_pid(); 
    
      -- 처음 작업할때에는 insert
      -- 키 값이 중복될 경우 update 수행 (키 값은 job_nm, job_base_dt)
      INSERT INTO public.tb_sp_job_log AS t 
             (job_nm, job_base_dt, job_start_ts, job_end_ts, "rows", job_status, query, err_msg)
      VALUES (v_job_nm, v_date, clock_timestamp(), NULL, NULL, 'R', NULL, NULL)
      ON CONFLICT (job_nm, job_base_dt) DO UPDATE 
      SET  job_start_ts = clock_timestamp()
         , job_end_ts   = NULL 
         , ROWS         = NULL
         , job_status   = 'R'
         , query        = NULL
         , err_msg      = NULL 
      ;
      COMMIT; -- Job이 수행되는 동안 'R', Running으로 변경 - 다른 세션에서 public.tb_sp_job_log 상태 확인 

      BEGIN
           ---------------- Job Logic Start -------------------
           DELETE FROM public.order_log
           WHERE  order_dt = v_date; 
           
           v_sql = '
                 INSERT INTO public.order_log
                      (order_no, cust_no, prod_nm, order_dt)
                 VALUES(0, 0, ''prod_01'', '''||v_date||''' ) ';
           
           EXECUTE v_sql;
           GET DIAGNOSTICS v_rows := row_count; -- 처리 건수 
           
           SELECT pg_sleep(5) INTO v_tmp; --상태 확인을 위하여 5초 sleep 적용
           ---------------- Job Logic End -------------------
           
           UPDATE public.tb_sp_job_log
              SET job_end_ts=clock_timestamp(), ROWS=v_rows
                , job_status = 'S', query = v_sql, err_msg=NULL
            WHERE job_nm      = v_job_nm
              AND job_base_dt = v_date;  
              
           
           EXCEPTION  
              WHEN OTHERS THEN 
                  GET stacked DIAGNOSTICS 
                      v_err_cd          = returned_sqlstate,
                      v_err_msg         = message_text,
                      v_err_context     = pg_exception_context;
           
                  RAISE NOTICE E'Got exception: 
                      err_cd  : %
                      err_msg : %
                      err_context: %', v_err_cd, v_err_msg, v_err_context;
            
                  UPDATE public.tb_sp_job_log
                     SET job_end_ts=clock_timestamp(), ROWS=NULL, job_status = 'F'
                       , query = v_sql, err_msg=v_err_msg
                   WHERE job_nm      = v_job_nm
                     AND job_base_dt = v_date;  
           END;    

END
$$
;
------ 초기 수행 시 ------
--수행전 로그 삭제 
TRUNCATE TABLE public.order_log;
TRUNCATE TABLE public.tb_sp_job_log;

-- 프로시저 Job 수행  
CALL public.sp_test_upsert('20010101');

-- 수행되는 동안 Job 실행 확인(현재 소스상에는 5초로 설정되어 있어서 5초 안에 다른 창에서 확인 가능) 
SELECT * FROM public.tb_sp_job_log;
job_nm        |job_base_dt|job_start_ts           |job_end_ts|rows|job_status|query|err_msg|
--------------+-----------+-----------------------+----------+----+----------+-----+-------+
sp_test_upsert|20010101   |2024-08-15 05:47:08.489|          |    |R         |     |       |

-- Job 수행 완료시 실행결과 확인 
SELECT * FROM public.tb_sp_job_log;
job_nm        |job_base_dt|job_start_ts           |job_end_ts             |rows|job_status|query                            |err_msg|
--------------+-----------+-----------------------+-----------------------+----+----------+---------------------------------+-------+
sp_test_upsert|20010101   |2024-08-15 05:47:08.489|2024-08-15 05:48:05.169|   1|S         |¶INSERT INTO public.order_log... |       |

--적재 작업 확인 
SELECT * FROM public.order_log;
order_no|cust_no|prod_nm|order_dt|
--------+-------+-------+--------+
       0|      0|prod_01|20010101|

------ 재작 수행 시 ------    
-- 프로시저 Job 수행  
CALL public.sp_test_upsert('20010101');

-- Job 수행 완료시 실행결과 확인 -- 기존 데이터에서 update 됨.
SELECT * FROM public.tb_sp_job_log;
job_nm        |job_base_dt|job_start_ts           |job_end_ts             |rows|job_status|query                            |err_msg|
--------------+-----------+-----------------------+-----------------------+----+----------+---------------------------------+-------+
sp_test_upsert|20010101   |2024-08-15 06:06:31.139|2024-08-15 06:06:36.170|   1|S         |¶INSERT INTO public.order_log... |       |

