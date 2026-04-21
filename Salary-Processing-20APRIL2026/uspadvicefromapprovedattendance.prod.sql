-- FUNCTION: public.uspadvicefromapprovedattendance(bigint, bigint, character varying, integer, integer, numeric, numeric, character varying)

-- DROP FUNCTION IF EXISTS public.uspadvicefromapprovedattendance(bigint, bigint, character varying, integer, integer, numeric, numeric, character varying);

CREATE OR REPLACE FUNCTION public.uspadvicefromapprovedattendance(
	p_emp_code bigint,
	p_createdby bigint,
	p_createdbyip character varying,
	p_month integer,
	p_year integer,
	p_paiddays numeric DEFAULT 0.0,
	p_leavetaken numeric DEFAULT 0.0,
	p_advance_or_current character varying DEFAULT 'Current'::character varying)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
	v_monthdays double precision;
	v_paiddays double precision;
	v_leavetaken double precision;
	v_rfc refcursor;
	v_currentmonthstartdate varchar(12);
	v_currentmonthenddate varchar(12);
	v_rec_payrolldates record;
--	v_customeraccountid bigint;
--	v_rec_attendance record;
	v_advice_attendancerecord text;
--	v_advance_or_current text:='Current';
--	v_rfcadvice refcursor;
--	v_empsalaryregister empsalaryregister%rowtype;
--	v_recadvice record;
--	v_rfcadvice_2 refcursor;
	v_openappointments openappointments%rowtype;
--	v_regime varchar(30);
	v_financial_year varchar(30);
	projectioncursors refcursor;
	v_working_minutes numeric:=0;
	v_shift_minutes numeric:=0;
	v_cmsdownloadedwages cmsdownloadedwages%rowtype;
	v_rec record;
	
-- 	v_currentpf numeric(18,2);
-- 	v_currentvpf numeric(18,2);
-- 	v_currentinsurance numeric(18,2);
-- 	v_currentprofessionaltax numeric(18,2);
-- 	v_grossearning numeric(18,2);
-- 	v_vpf numeric(18,2);
	v_result int;
BEGIN
/*************************************************************************
Version Date			Done_by					Change							
1.0		31-May-2025		Shiv Kumar				Initial Version						
*************************************************************************/
if not EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array((select COALESCE(COALESCE(NULLIF(op.assigned_ou_ids, ''),'0')) from openappointments op where op.emp_code=p_emp_code), ',')) AS input_ou_ids
		WHERE input_ou_ids::bigint in (select id from tbl_org_unit_geofencing where is_attendance_leave_only='Y')
		) then
		v_monthdays:=date_part('day',DATE_TRUNC('MONTH', (p_year||'-'||p_month||'-01')::DATE + INTERVAL '1 MONTH') - INTERVAL '1 DAY');

		v_currentmonthstartdate:=(p_year::text||'-'||lpad(p_month::text,2,'0')||'-01');
		v_currentmonthenddate:=to_char((v_currentmonthstartdate::date+interval '1 month'-interval '1 day'),'yyyy-mm-dd');

		v_paiddays:=coalesce(p_paiddays,0);
		v_leavetaken:=coalesce(p_leavetaken,0);
		
		
-- if p_month in (1,2,3) then
-- 	v_financial_year:=(p_year-1)::text||'-'||p_year::text;
-- else
-- 	v_financial_year:=(p_year)::text||'-'||(p_year+1)::text;
-- end if;
	select * from openappointments where emp_code=p_emp_code into v_openappointments;
--	select regime_tye into v_regime from employee_regime where emp_code=p_emp_code and financial_year=v_financial_year and isactive='1';
--	v_regime:=coalesce(v_regime,'New');
/**********************change 1.35 starts***************************************************/
	if not exists(select * from paymentadvice where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and advicelockstatus='Locked'  and attendancemode<>'Ledger')
	then

	drop table if exists pg_temp.cmsdownloadedwages_pregenerate;						
	create /*GLOBAL*/ temporary table pg_temp.cmsdownloadedwages_pregenerate
	as
	select * from cmsdownloadedwages where 1=2;
					INSERT INTO pg_temp.cmsdownloadedwages_pregenerate(
				mprmonth, mpryear, empcode, employeename, pancardno, dateofjoining, deputeddate, projectname, contractno, 
						agencyname, contractcategory, contracttype, dateofleaving, 
						lossofpay, totalpaiddays, totalleavetaken, 
						hrgeneratedon, mpruploadeddate, ismultilocated, remark, 
						companycode, bunit, isactive, createdon, createdbyip,
						batch_no, bunitname, agencyid, customeraccountid, customeraccountname,
						jobrole, relieveddate, multi_performerwagesflag, 
						cms_contractid, cms_salremark, cms_trackingid, cms_jobid, cms_posting_department, 
						cms_posting_location, transactionid, attendancemode, manualmodereason, cjcode
						,working_minutes,shift_minutes)

				select p_month,p_year,openappointments.emp_code,emp_name,pancard,dateofjoining,dateofjoining,contract_name,crm_order_number,
						agencyname,contract_category,type_of_contract,dateofrelieveing,
						v_monthdays-(coalesce(v_paiddays,0)+coalesce(v_leavetaken,0)) lossofpay, 
						coalesce(v_paiddays,0)paiddays,coalesce(v_leavetaken,0) leavetaken, 
						to_char(current_timestamp,'dd Mon yyyy hh24:mi'),current_timestamp,'N','TP Attendance Moved',
						'A0001',1,'1',current_timestamp,p_createdbyip,
						(current_timestamp::text),'TP',null,customeraccountid,tbl_account.accountname,
						post_offered,dateofrelieveing,'Y',
						contractid,'',trackingid,jobid,posting_department,
						posting_location, EXTRACT(EPOCH FROM current_timestamp)::bigint,'MPR','TP',cjcode
						,v_working_minutes,v_shift_minutes
				from openappointments inner join tbl_account
				on openappointments.customeraccountid=tbl_account.id	  
				where openappointments.emp_code=p_emp_code
				returning * into v_cmsdownloadedwages;

SELECT json_agg(row_to_json(t))::text into v_advice_attendancerecord
FROM (
    SELECT *
    FROM cmsdownloadedwages_pregenerate
) t;

			select public.uspupdatetaxonpaiddays(
				p_emp_code =>p_emp_code,
				p_createdby =>p_createdby,
				p_createdbyip =>p_createdbyip,
				p_month =>p_month,
				p_year =>p_year,
				p_paiddays=>p_paiddays,
				p_leavetaken =>p_leavetaken,
				p_advance_or_current =>p_advance_or_current)
				into v_result;
	
				select  public.uspgetorderwisewages_pregenerate(
							p_mprmonth =>p_month,
							p_mpryear =>p_year,
							p_ordernumber =>''::character varying,
							p_emp_code =>p_emp_code,
							p_batch_no =>''::character varying,
							p_action =>'Retrieve_Salary'::character varying,
							p_createdby =>p_createdby::bigint,
							createdbyip =>p_createdbyip::character varying,
							p_criteria =>'Employee'::character varying,
							p_process_status =>'NotProcessed'::character varying,
							p_issalaryorliability =>'L'::character varying,
							p_tptype =>'TP'::character varying,
							p_advice_attendancerecord=>v_advice_attendancerecord,
							p_advance_or_current=>p_advance_or_current
							)
				into v_rfc;						
	return '{"Status":"true","Message":"Advice generated"}';				
				
end if;				
		return '{"Status":"true","Message":"Advice not generated"}';	

-- 	exception when others then
-- 	return 0;
end if;
		return v_rfc;
	end;

$BODY$;

ALTER FUNCTION public.uspadvicefromapprovedattendance(bigint, bigint, character varying, integer, integer, numeric, numeric, character varying)
    OWNER TO payrollingdb;

