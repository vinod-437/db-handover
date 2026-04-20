-- PROCEDURE: public.uspcreatepayoutfromadvice(character varying, bigint, bigint, character varying, integer, integer, bigint, record, bigint)

-- DROP PROCEDURE IF EXISTS public.uspcreatepayoutfromadvice(character varying, bigint, bigint, character varying, integer, integer, bigint, record, bigint);

CREATE OR REPLACE PROCEDURE public.uspcreatepayoutfromadvice(
	IN p_action character varying,
	IN p_emp_code bigint,
	IN p_createdby bigint,
	IN p_createdbyip character varying,
	IN p_month integer,
	IN p_year integer,
	IN p_payment_record_id bigint DEFAULT (- (9999)::bigint),
	IN p_paymentadvice record DEFAULT NULL::record,
	IN p_multipayoutrequestid bigint DEFAULT (0)::bigint)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	v_monthdays double precision;
	v_currentmonthstartdate varchar(12);
	v_currentmonthenddate varchar(12);
	v_cmsdownloadedwages cmsdownloadedwages%rowtype;
	v_rfcpayout refcursor;
 	v_openappointments openappointments%rowtype;
 	v_tbl_account tbl_account%rowtype;
BEGIN
/*************************************************************************
Version Date			Change								Done_by
1.0		06-Jun-2025		Initial Version						Shiv Kumar
1.1		08-Jul-2025		hrgenerated as per Salary Month		Shiv Kumar
*************************************************************************/
-- STEP 1: Fetch employee appointment and customer account details
select * from  openappointments into v_openappointments where emp_code=p_emp_code;
select * from tbl_account where id=v_openappointments.customeraccountid into v_tbl_account;
-- STEP 2: Verify the employee is eligible for salary processing (Skip if configured for attendance/leave only)
if not EXISTS
		(
		SELECT 1
		FROM unnest(string_to_array((select COALESCE(COALESCE(NULLIF(op.assigned_ou_ids, ''),'0')) from openappointments op where op.emp_code=p_emp_code), ',')) AS input_ou_ids
		WHERE input_ou_ids::bigint in (select id from tbl_org_unit_geofencing where is_attendance_leave_only='Y')
		) then
	if p_action='MoveAttendanceToWages' then
		-- STEP 3: Exit early if standard (non-multipayout) salary is already successfully processed for the month
		if exists(select * from tbl_monthlysalary where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and is_rejected='0' and attendancemode='MPR' and multipayoutrequestid=0) then
			return;		
		end if;

			-- STEP 4: Calculate the bounds of the current payroll month
			v_currentmonthstartdate:=(p_year::text||'-'||lpad(p_month::text,2,'0')||'-01');
			v_currentmonthenddate:=to_char((v_currentmonthstartdate::date+interval '1 month'-interval '1 day'),'yyyy-mm-dd');
			v_monthdays:=date_part('day',DATE_TRUNC('MONTH',make_date (p_year,p_month,1) + INTERVAL '1 MONTH') - INTERVAL '1 DAY');
				/*****************************************************************/
		-- STEP 5: Check if a valid wage staging record exists in 'cmsdownloadedwages'; if not, create one
		if not exists(select * from cmsdownloadedwages where empcode=p_emp_code::text and mprmonth=p_month and mpryear=p_year and isactive='1' 
					  			and attendancemode=p_paymentadvice.attendancemode 
					  			and (coalesce(totalpaiddays,0)+coalesce(totalleavetaken,0))>0
								 and multipayoutrequestid=0
					 )
				or
					(p_paymentadvice.attendancemode='Manual'
					and not exists(select * from tbl_monthlysalary 
								   where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and is_rejected='0' 
					  			and batch_no=p_paymentadvice.batch_no
					 )	
					 )
					 then	
					if p_paymentadvice.attendancemode<>'Manual' then
					-- 5a: Insert a fresh staging record mapping payment advice data and employee attributes
					INSERT INTO public.cmsdownloadedwages(
				mprmonth, mpryear, empcode, employeename, pancardno, dateofjoining, deputeddate, projectname, contractno, 
						agencyname, contractcategory, contracttype, dateofleaving, 
						lossofpay, totalpaiddays, totalleavetaken, 
						hrgeneratedon,
						mpruploadeddate, ismultilocated, remark, 
						companycode, bunit, isactive, createdon, createdbyip,
						batch_no, bunitname, agencyid, customeraccountid, customeraccountname,
						jobrole, relieveddate, multi_performerwagesflag, 
						cms_contractid, cms_salremark, cms_trackingid, cms_jobid, cms_posting_department, 
						cms_posting_location, transactionid, attendancemode, manualmodereason, cjcode,attendance_head
						/*,working_minutes,shift_minutes*/,multipayoutrequestid)

				select p_month,p_year,p_emp_code,v_openappointments.emp_name,v_openappointments.pancard,v_openappointments.dateofjoining,v_openappointments.dateofjoining,v_openappointments.contract_name,v_openappointments.crm_order_number,
						v_openappointments.agencyname,v_openappointments.contract_category,v_openappointments.type_of_contract,v_openappointments.dateofrelieveing,
						p_paymentadvice.lossofpay , 
						p_paymentadvice.paiddays-coalesce(p_paymentadvice.totalleavetaken,0),p_paymentadvice.totalleavetaken, 
						to_char(case when make_date(p_year,p_month,1)=date_trunc('month',current_timestamp) then current_timestamp else make_date(p_year,p_month,1) +interval '1 month' end ,'dd Mon yyyy hh24:mi'),
						current_timestamp,'N','TP Attendance Moved',
						'A0001',1,'1',current_timestamp,p_createdbyip,
						p_paymentadvice.batch_no,'TP',null,v_openappointments.customeraccountid,v_tbl_account.accountname,
						v_openappointments.post_offered,v_openappointments.dateofrelieveing,'Y',
						v_openappointments.contractid,'',v_openappointments.trackingid,v_openappointments.jobid,v_openappointments.posting_department,
						v_openappointments.posting_location, EXTRACT(EPOCH FROM current_timestamp)::bigint,p_paymentadvice.attendancemode,'TP',v_openappointments.cjcode,'TP'
						/*,v_working_minutes,v_shift_minutes*/,p_multipayoutrequestid
						returning * into v_cmsdownloadedwages;
					else
						-- 5b: For 'Manual' mode, just fetch the existing staging record based on the batch number
						select * from cmsdownloadedwages where empcode::bigint=p_emp_code 
											and mprmonth=p_month and mpryear=p_year and isactive='1' 
											and batch_no=p_paymentadvice.batch_no
						into v_cmsdownloadedwages;
					end if;
					
					-- STEP 6: Execute core wage processing by invoking 'uspgetorderwisewages'
					-- This calculates all final salary components, taxes, and deductions
					select public.uspgetorderwisewages(
										p_mprmonth =>p_month,
										p_mpryear =>p_year,
										p_ordernumber =>''::character varying,
										p_emp_code =>p_emp_code,
										p_batch_no =>v_cmsdownloadedwages.batch_no::character varying,
										p_action =>'Save_Salary'::character varying,
										p_createdby =>p_createdby::bigint,
										createdbyip =>p_createdbyip::character varying,
										p_criteria =>'Employee'::character varying,
										p_process_status =>'NotProcessed'::character varying,
										p_issalaryorliability =>'L'::character varying,
										p_tptype =>'TP'::character varying,
										p_payment_recordid=>p_payment_record_id,
										p_paymentadvice=>p_paymentadvice,
										p_multipayoutrequestid=>p_multipayoutrequestid)
					into v_rfcpayout;
/*************change 1.2 starts************************************/				
			-- STEP 7: Rollback / Cleanup Phase
			-- If 'uspgetorderwisewages' did not successfully generate a 'tbl_monthlysalary' record (e.g. due to rejection or internal errors),
			-- deactivate the 'cmsdownloadedwages' staging record to keep state clean.
			if not exists (select * from tbl_monthlysalary ts
							where ts.emp_code=p_emp_code
								and is_rejected='0'
								and ts.mprmonth=p_month
								and ts.mpryear=p_year
								and ts.batchid=v_cmsdownloadedwages.batch_no
						   ) then
								
								update cmsdownloadedwages
								set isactive='0'
								where "tblAutoId"=v_cmsdownloadedwages."tblAutoId";
			end if;	
	end if;
/*************change 1.2 ends************************************/				
	end if;
end if;	
--commit;
end;

$BODY$;
ALTER PROCEDURE public.uspcreatepayoutfromadvice(character varying, bigint, bigint, character varying, integer, integer, bigint, record, bigint)
    OWNER TO payrollingdb;

