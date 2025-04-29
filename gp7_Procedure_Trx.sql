
--Greenplum 6에서는 프로시저 함수지원, 
--Greenplum 7에서는 프로시저 함수지원와 프로시저 둘다 지원 

--Greenplum 6 & 7에서 함수 형태의 프로시저 지원 예시

--1.테스트를 위한 테이블 생성 
DROP TABLE IF EXISTS public.test_trx;

CREATE TABLE public.test_trx (id int) 
DISTRIBUTED BY (id);

--Unique 에러 발생을 위하여 Unique Index 생
CREATE UNIQUE INDEX ixu_test_trx ON public.test_trx(id);

DROP TABLE IF EXISTS public.test_job_log;
CREATE TABLE public.test_job_log (id int, job_flag TEXT, err_msg text)
DISTRIBUTED BY (id);

  
--2.1 테스트용 프로시저 함수 - (All or Nothing)
--프로시저 수행시 에러 발생시 전체 롤백 케이스  

DELETE FROM public.test_trx;
DELETE FROM public.test_job_log;

CREATE OR REPLACE FUNCTION control_trasaction()
RETURNS TEXT 
AS 
$$
DECLARE 
    v_err_msg  text;
    v_err_cd   TEXT;
    v_err_context TEXT;
BEGIN 
     DELETE FROM public.test_trx;
     DELETE FROM public.test_job_log;             
     INSERT INTO public.test_trx values(1);
     INSERT INTO public.test_trx values(1); --에러 강제 발생  
     INSERT INTO public.test_job_log VALUES (1, 'S', NULL);
     RETURN 'OK';

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
          INSERT INTO public.test_job_log VALUES (1, 'F', v_err_msg);
          RETURN 'ERROR';
END
$$
LANGUAGE plpgsql ;

--프로시저 함수 호출 
SELECT control_trasaction();

--Output 메시지 
PL/pgSQL function control_trasaction() line 12 at SQL statement
Got exception: 
    err_cd  : 23505
    err_msg : duplicate key value violates unique constraint "ixu_test_trx"  
              (seg1 172.16.65.90:6001 pid=21436)
    err_context: SQL statement "INSERT INTO public.test_trx values(1)"
PL/pgSQL function control_trasaction() line 10 at SQL statement

--데이터 중복 건으로 Unique 에러로 인하여, 전체 롤백 됨.
--에러로 인하여 트랜잭션이 롤백되고, 0건 입력  
SELECT * FROM public.test_trx ORDER BY id;
id|
--+

--예외 처리로 에러 원인 적재 
SELECT * FROM public.test_job_log;
id|job_flag|err_msg                                                       |
--+--------+--------------------------------------------------------------+
 1|F       |duplicate key value violates unique constraint "ixu_test_trx"  
            (seg1 172.16.65.90:6001 pid=21436)|

--2.2. 트랜잭션 부분 처리 
--여러 단계의 작업 처리시, 에러 발생하더라도 특정 구간까지 수행한 작업이 완료되어야 할 경우
--서브 트랜잭션으로 단위 작업까지 완료가 필요한 경우, 트랜잭션 Block(Begin/END)으로 묶음.
 
DELETE FROM public.test_trx;
DELETE FROM public.test_job_log;
 
CREATE OR REPLACE function control_trasaction()
RETURNS TEXT 
AS 
$$
DECLARE 
    v_err_msg  text;
    v_err_cd   TEXT;
    v_err_context TEXT;
BEGIN 

    BEGIN
        DELETE FROM public.test_trx;
        DELETE FROM public.test_job_log;             
        INSERT INTO public.test_trx values(1);
    END;
    
    BEGIN
        INSERT INTO public.test_trx values(1);
        INSERT INTO public.test_job_log VALUES (1, 'S', NULL);
        
        RETURN 'OK';
  
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

          INSERT INTO public.test_job_log VALUES (1, 'F', v_err_msg);
          RETURN 'ERROR';
    END;
    

END
$$
LANGUAGE plpgsql ;

--프로시저 함수 호출 
SELECT control_trasaction();
--Output 메시지 
Got exception: 
    err_cd  : 23505
    err_msg : duplicate key value violates unique constraint "ixu_test_trx"  
              (seg1 172.16.65.90:6001 pid=21436)
    err_context: SQL statement "INSERT INTO public.test_trx values(1)"
PL/pgSQL function control_trasaction() line 15 at SQL STATEMENT
--SELECT control_trasaction(); 수행 결과 
control_trasaction|
------------------+
ERROR             |

--서브 트랜잭션 Block까지 처리되고, 이후에 에러 발생
--첫번째 트랜잭션 Block까지 처리 됨.
SELECT * FROM public.test_trx ORDER BY id;
id|
--+
 1|

--2번째 트랜잭션 Block에서 Unique 에러 발생하여 예외 처리 적용 됨.
SELECT * FROM public.test_job_log;
id|job_flag|err_msg                                                       |
--+--------+--------------------------------------------------------------+
 1|F       |duplicate key value violates unique constraint "ixu_test_trx"  
            (seg4 172.16.65.133:6000 pid=1937134)|


--2.3. 트랜잭션 부분 처리를 이용한 정상적인 처리  
--각 트랜잭션 블락을 처리하고, 예외 처리없이 정상 수
 
DELETE FROM public.test_trx;
DELETE FROM public.test_job_log;
 
CREATE OR REPLACE FUNCTION control_trasaction()
RETURNS TEXT 
AS 
$$
DECLARE 
    v_err_msg  text;
    v_err_cd   TEXT;
    v_err_context TEXT;
BEGIN 

    BEGIN 
        DELETE FROM public.test_trx;
        DELETE FROM public.test_job_log;          
        INSERT INTO public.test_trx values(1);
    END;
    
    BEGIN
        INSERT INTO public.test_trx values(2);
        INSERT INTO public.test_job_log VALUES (2, 'S', NULL);
  
        RETURN 'OK';
       
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

            INSERT INTO public.test_job_log VALUES (2, 'F', v_err_msg);
            RETURN 'ERROR';
    END;
END
$$
LANGUAGE plpgsql;

--프로시저 함수 호출 -> 정상 처리 
SELECT control_trasaction();
control_trasaction|
------------------+
OK                |

--정상으로 처리 됨. 
SELECT * FROM public.test_trx ORDER BY id;
id|
--+
 1|
 2|

--Job 로그도 정상처리 
SELECT * FROM public.test_job_log;
id|job_flag|err_msg|
--+--------+-------+
 2|S       |       |
 
--3.Greenplum 7에서의 프로시저 테스트
--프로시저 수행시 리턴값이 없음.  

DELETE FROM public.test_trx;
DELETE FROM public.test_job_log;
 
CREATE OR REPLACE PROCEDURE control_trasaction()
LANGUAGE plpgsql
AS 
$$
DECLARE 
    v_err_msg  text;
    v_err_cd   TEXT;
    v_err_context TEXT;
BEGIN 

    BEGIN 
        DELETE FROM public.test_trx;
        DELETE FROM public.test_job_log;          
        INSERT INTO public.test_trx values(1);
    END;
    
    BEGIN
        INSERT INTO public.test_trx values(2);
        INSERT INTO public.test_job_log VALUES (2, 'S', NULL);
       
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

          INSERT INTO public.test_job_log VALUES (2, 'F', v_err_msg);
    END;
END
$$;

--프로시저 수행시 select 프로시저가 아닌, call 프로시저로 수행 
SELECT control_trasaction();
SQL Error [42809]: ERROR: control_trasaction() is a procedure
  Hint: To call a procedure, use CALL.
  Position: 8

CALL control_trasaction();
  
-- 정상 처리 
SELECT * FROM public.test_trx ORDER BY id;
id|
--+
 1|
 2|

-- job 로그 정상 처리 
SELECT * FROM public.test_job_log;
id|job_flag|err_msg|
--+--------+-------+
 2|S       |       |
  