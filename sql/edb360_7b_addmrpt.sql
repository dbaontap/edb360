SET VER OFF FEED OFF SERVEROUT ON HEAD OFF PAGES 50000 LIN 32767 LONG 320000 LONGC 2000 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100;
DEF section_name = 'ADDM Reports';
SPO &&main_report_name..html APP;
PRO <h2 title="For largest 'DB time' or 'background elapsed time' for past 4 hours, 1 and 7 days (for each instance)">&&section_name.</h2>
SPO OFF;

COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;
SPO 9993_&&common_prefix._addm_driver.sql;
PRO VAR inst_num VARCHAR2(1023);;
DECLARE
  l_standard_filename VARCHAR2(32767);
  l_spool_filename VARCHAR2(32767);
  l_one_spool_filename VARCHAR2(32767);
  l_instances NUMBER;
  l_begin_date VARCHAR2(14);
  l_end_date VARCHAR2(14);
  PROCEDURE put_line(p_line IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_line);
  END put_line;
  PROCEDURE update_log(p_module IN VARCHAR2) IS
  BEGIN
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
		put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
		put_line('-- update log');
		put_line('SPO &&edb360_log..txt APP;');
        put_line('SET TERM ON;');
		put_line('PRO '||CHR(38)||chr(38)||'hh_mm_ss. col:&&column_number.of&&max_col_number. '||p_module);
        put_line('SET TERM OFF;');
		put_line('SPO OFF;');
  END update_log;
BEGIN
  SELECT COUNT(*) INTO l_instances FROM gv$instance;
  -- three report per instance
  FOR i IN (SELECT instance_number
              FROM gv$instance
             WHERE '&&diagnostics_pack.' = 'Y'
               AND '&&text_reports.' IS NULL
             ORDER BY
                   instance_number)
  LOOP
    -- find the one with largest 'DB time' or 'background elapsed time' for past 4 hours, 1 and 7 days (for each instance)
    FOR j IN (WITH
              expensive AS (
              SELECT h1.dbid, h1.snap_id bid, h2.snap_id eid,
                     CAST(s2.begin_interval_time AS DATE) begin_date,
                     CAST(s2.end_interval_time AS DATE) end_date,
                     (h2.value - h1.value) value
                FROM dba_hist_sys_time_model h1,
                     dba_hist_sys_time_model h2,
                     dba_hist_snapshot s1,
                     dba_hist_snapshot s2
               WHERE h1.instance_number = i.instance_number
                 AND h1.stat_name IN ('DB time', 'background elapsed time')
                 AND h1.snap_id BETWEEN &&minimum_snap_id. AND &&maximum_snap_id.
                 AND h2.snap_id = h1.snap_id + 1
                 AND h2.dbid = h1.dbid
                 AND h2.instance_number = h1.instance_number
                 AND h2.stat_id = h1.stat_id
                 AND h2.stat_name = h1.stat_name
                 AND s1.snap_id = h1.snap_id
                 AND s1.dbid = h1.dbid
                 AND s1.instance_number = h1.instance_number
                 AND CAST(s1.end_interval_time AS DATE) > TO_DATE('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - 7 -- includes all options
                 AND s2.snap_id = s1.snap_id + 1
                 AND s2.dbid = s1.dbid
                 AND s2.instance_number = s1.instance_number
                 AND s2.startup_time = s1.startup_time
              ),
              max_7d AS (
              SELECT MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - 7 AND TO_DATE('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - 1 -- avoids selecting same twice
              ),
              max_1d AS (
              SELECT MAX(value) value
                FROM expensive
               WHERE end_date BETWEEN TO_DATE('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - 1 AND TO_DATE('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - (4 / 24) -- avoids selecting same twice
              ),
              max_4h AS (
              SELECT MAX(value) value
                FROM expensive
               WHERE end_date > TO_DATE('&&tool_sysdate.', 'YYYYMMDDHH24MISS') - (4 / 24)
              )
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date
                FROM expensive e,
                     max_7d m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date
                FROM expensive e,
                     max_1d m
               WHERE m.value = e.value
               UNION
              SELECT e.dbid, e.bid, e.eid, e.begin_date, e.end_date
                FROM expensive e,
                     max_4h m
               WHERE m.value = e.value
               ORDER BY
                     1, 2 DESC)
    LOOP
      l_begin_date := TO_CHAR(j.begin_date, 'YYYYMMDDHH24MISS');
      l_end_date := TO_CHAR(j.end_date, 'YYYYMMDDHH24MISS');
      -- one node
      put_line('VAR l_task_name VARCHAR2(30);');
      put_line('BEGIN');
      put_line('  :l_task_name := ''ADDM_''||TO_CHAR(SYSDATE, ''YYYYMMDD_HH24MISS'');');
      put_line('  DBMS_ADVISOR.CREATE_TASK(advisor_name => ''ADDM'', task_name =>  :l_task_name);');
      put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''START_SNAPSHOT'', value => '||j.bid||');');
      put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''END_SNAPSHOT'', value => '||j.eid||');');
      put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''DB_ID'', value => '||j.dbid||');');
      put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''INSTANCE'', value => '||i.instance_number||');');
      put_line('  DBMS_ADVISOR.EXECUTE_TASK(task_name => :l_task_name);');
      put_line('END;');
      put_line('/');
      put_line('PRINT l_task_name;');
      l_standard_filename := 'addmrpt_'||i.instance_number||'_'||j.bid||'_'||j.eid;
      l_spool_filename := '&&common_prefix._'||l_standard_filename;
      put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
      put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
      put_line('-- update log');
      put_line('SPO &&edb360_log..txt APP;');
      put_line('PRO');
      put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
      put_line('PRO');
      put_line('PRO '||CHR(38)||chr(38)||'hh_mm_ss. '||l_spool_filename);
      put_line('SPO OFF;');
      put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&edb360_log..txt');
      put_line('-- update main report');
      put_line('SPO &&main_report_name..html APP;');
      put_line('PRO <li title="DBMS_ADDM">'||l_standard_filename||' <small><em>('||TO_CHAR(j.end_date,'DD-Mon-YY HH24:MI:SS')||')</em></small>');
      put_line('SPO OFF;');
      put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&main_report_name..html');
      IF '&&text_reports.' IS NULL THEN
        :file_seq := :file_seq + 1;
        l_one_spool_filename := LPAD(:file_seq, 4, '0')||'_'||l_spool_filename;
        update_log(l_one_spool_filename||'.txt');
        put_line('SPO '||l_one_spool_filename||'.txt;');
        put_line('SELECT DBMS_ADVISOR.get_task_report(:l_task_name) FROM DUAL;');
        put_line('SPO OFF;');
        put_line('-- update main report');
        put_line('SPO &&main_report_name..html APP;');
        put_line('PRO <a href="'||l_one_spool_filename||'.txt">text</a>');
        put_line('SPO OFF;');
        put_line('-- zip');
        put_line('HOS zip -mq &&main_compressed_filename._&&file_creation_time. '||l_one_spool_filename||'.txt');
        put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&main_report_name..html');
      END IF;
      put_line('-- update main report');
      put_line('SPO &&main_report_name..html APP;');
      put_line('PRO </li>');
      put_line('SPO OFF;');
      put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&main_report_name..html');
      put_line('EXEC DBMS_ADVISOR.DELETE_TASK(task_name => :l_task_name);');

      -- all nodes
      IF l_instances > 1 THEN
        put_line('VAR l_task_name VARCHAR2(30);');
        put_line('BEGIN');
        put_line('  :l_task_name := ''ADDM_''||TO_CHAR(SYSDATE, ''YYYYMMDD_HH24MISS'');');
        put_line('  DBMS_ADVISOR.CREATE_TASK(advisor_name => ''ADDM'', task_name =>  :l_task_name);');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''START_SNAPSHOT'', value => '||j.bid||');');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''END_SNAPSHOT'', value => '||j.eid||');');
        put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''DB_ID'', value => '||j.dbid||');');
        --put_line('  DBMS_ADVISOR.SET_TASK_PARAMETER(task_name => :l_task_name, parameter => ''INSTANCE'', value => '||i.instance_number||');');
        put_line('  DBMS_ADVISOR.EXECUTE_TASK(task_name => :l_task_name);');
        put_line('END;');
        put_line('/');
        put_line('PRINT l_task_name;');
        l_standard_filename := 'addmrpt_rac_'||j.bid||'_'||j.eid;
        l_spool_filename := '&&common_prefix._'||l_standard_filename;
        put_line('COL hh_mm_ss NEW_V hh_mm_ss NOPRI FOR A8;');
        put_line('SELECT TO_CHAR(SYSDATE, ''HH24:MI:SS'') hh_mm_ss FROM DUAL;');
        put_line('-- update log');
        put_line('SPO &&edb360_log..txt APP;');
        put_line('PRO');
        put_line('PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
        put_line('PRO');
        put_line('PRO '||CHR(38)||chr(38)||'hh_mm_ss. '||l_spool_filename);
        put_line('SPO OFF;');
        put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&edb360_log..txt');
        put_line('-- update main report');
        put_line('SPO &&main_report_name..html APP;');
        put_line('PRO <li title="DBMS_ADDM">'||l_standard_filename||' <small><em>('||TO_CHAR(j.end_date,'DD-Mon-YY HH24:MI:SS')||')</em></small>');
        put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&main_report_name..html');
        IF '&&text_reports.' IS NULL THEN
          :file_seq := :file_seq + 1;
          l_one_spool_filename := LPAD(:file_seq, 4, '0')||'_'||l_spool_filename;
          update_log(l_one_spool_filename||'.txt');
          put_line('SPO '||l_one_spool_filename||'.txt;');
          put_line('SELECT DBMS_ADVISOR.get_task_report(:l_task_name) FROM DUAL;');
          put_line('SPO OFF;');
          put_line('-- update main report');
          put_line('SPO &&main_report_name..html APP;');
          put_line('PRO <a href="'||l_one_spool_filename||'.txt">text</a>');
          put_line('SPO OFF;');
          put_line('-- zip');
          put_line('HOS zip -mq &&main_compressed_filename._&&file_creation_time. '||l_one_spool_filename||'.txt');
          put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&main_report_name..html');
        END IF;
        put_line('-- update main report');
        put_line('SPO &&main_report_name..html APP;');
        put_line('PRO </li>');
        put_line('SPO OFF;');
        put_line('HOS zip -q &&main_compressed_filename._&&file_creation_time. &&main_report_name..html');
        put_line('EXEC DBMS_ADVISOR.DELETE_TASK(task_name => :l_task_name);');
      END IF;
    END LOOP;
  END LOOP;
END;
/
SPO OFF;
@9993_&&common_prefix._addm_driver.sql;
SET SERVEROUT OFF HEAD ON PAGES 50;
HOS zip -mq &&main_compressed_filename._&&file_creation_time. 9993_&&common_prefix._addm_driver.sql