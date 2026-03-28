-- FUNCTION: public.uspsavecustomsalarystructure(integer, character varying, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, character varying, integer, character varying, character varying, integer, numeric, numeric, character varying, integer, character varying, integer, character varying, character varying, character varying, integer, character varying, numeric, text, integer, character varying, numeric, numeric, integer, text, character varying, text, text, numeric, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, bigint, bigint, bigint, bigint, numeric, text, numeric, character varying, double precision, double precision, character varying, numeric, character varying, character varying, character varying, character varying, text, numeric, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.uspsavecustomsalarystructure(integer, character varying, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, character varying, integer, character varying, character varying, integer, numeric, numeric, character varying, integer, character varying, integer, character varying, character varying, character varying, integer, character varying, numeric, text, integer, character varying, numeric, numeric, integer, text, character varying, text, text, numeric, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, bigint, bigint, bigint, bigint, numeric, text, numeric, character varying, double precision, double precision, character varying, numeric, character varying, character varying, character varying, character varying, text, numeric, character varying, character varying);

CREATE OR REPLACE FUNCTION public.uspsavecustomsalarystructure(
	personalinfoid integer,
	salarycategoryname character varying,
	monthlyofferedpackage numeric,
	basic numeric,
	hra numeric,
	allowances numeric,
	gross numeric,
	epf_employer numeric,
	epf_employee numeric,
	esi_employer numeric,
	esi_employee numeric,
	salary_in_hand numeric,
	ctc numeric,
	esiexceptionalcase character varying,
	salarydays integer,
	pfcapapplied character varying,
	islwfstate character varying,
	lwfstatecode integer,
	employeelwf numeric,
	employerlwf numeric,
	lwfdeductionmonths character varying,
	ptid integer,
	location_type character varying,
	basicoption integer,
	salarydaysopted character varying,
	operation character varying,
	minwagestatename character varying,
	minwagescategoryid integer,
	minwagescategoryname character varying,
	minimumwagessalary numeric,
	effectivedate text,
	status integer,
	msg character varying,
	conveyance_allowance numeric,
	medical_allowance numeric,
	createdby integer,
	createdbyip text,
	p_dateofjoining character varying,
	p_jobrole text,
	p_tp_leave_template_txt text,
	p_gratuity numeric,
	p_employergratuityopted text,
	p_employergratuity numeric,
	p_commission numeric,
	p_salarybonus numeric,
	p_transport_allowance numeric,
	p_travelling_allowance numeric,
	p_leave_encashment numeric,
	p_overtime_allowance numeric,
	p_notice_pay numeric,
	p_hold_salary_non_taxable numeric,
	p_children_education_allowance numeric,
	p_gratuityinhand numeric,
	p_dailyallowance_rate numeric DEFAULT 0.0,
	p_customeraccountid bigint DEFAULT 0,
	p_unitid bigint DEFAULT 0,
	p_designationid bigint DEFAULT 0,
	p_departmentid bigint DEFAULT 0,
	p_pfapplicablecomponents numeric DEFAULT 0.0,
	p_edli_adminchargesincludeinctc text DEFAULT 'Y'::text,
	p_esiappliedcomponents numeric DEFAULT 0,
	p_isgroupinsurance character varying DEFAULT 'N'::character varying,
	p_employeeinsuranceamount double precision DEFAULT 0.0,
	p_employerinsuranceamount double precision DEFAULT 0.0,
	p_ishourlysetup character varying DEFAULT 'N'::character varying,
	p_customtaxpercent numeric DEFAULT 1,
	p_charity_contribution character varying DEFAULT 'N'::character varying,
	p_is_exemptedfromtds character varying DEFAULT 'N'::character varying,
	p_tds_exempted_docpath character varying DEFAULT ''::character varying,
	p_ispiecerate character varying DEFAULT 'N'::character varying,
	p_salarymasterjson text DEFAULT ''::text,
	p_grossearningcomponents numeric DEFAULT 0.0,
	p_fullmonthincentiveapplicable character varying DEFAULT 'N'::character varying,
	p_flexiblemonthdays character varying DEFAULT 'N'::character varying)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$

/*************************************************************************
Version 	Date			Change								Done_by
1.0			24-Apr-2024		Initial Version						Shiv Kumar
1.1			22-Jun-2024		Add Annual Variables				Shiv Kumar
1.2         24-July-2024    Add parameters unit					Chandra Mohan
1.3			19-Sep-2024		PF on other than basic components	Shiv Kumar
1.4		 	09-Dec-2024		Update pfoped/esic opted in 		Shiv Kumar
							openapp. as per PF and ESIC
1.5 	 	23-Sept-2025	V_Jobrole changes for designation id update 	Parveen Kumar													
1.6 	 	24-Sept-2025	Add Grossearning components			Shiv Kumar
1.7         30-Sep-2025     Add workflow			            Shiv Kumar
1.8         15-Nov-2025     Full Month Incentive		        Shiv Kumar
1.9         02-Dec-2025     Add flexiblemonthdays		            Shiv Kumar
1.10         13-Oct-2025     Smart Payrolling		            Shiv Kumar
*************************************************************************/
DECLARE
	v_rfcsal text;
	v_empsalaryregister empsalaryregister%rowtype;

	-- START - New Variables Define
	v_doj date;
	v_leave_type json;
	v_clgranted int;
	v_mlgranted int;
    v_iscl_carry_forward character varying(1);
    v_isml_carry_forward character varying(1);
	v_totalleaves int;
	v_carryforwardedleaves int;
	v_leaverecord json;
	v_empcode bigint;
	v_userid bigint;
	v_jsid bigint;
	v_pid bigint;
	-- v_rec record;
	-- v_epfemployee numeric(18,2);
	-- v_esiemployee numeric(18,2);
	-- v_monthlysalary double precision;
	-- v_annualsalary double precision;
	-- v_result int;
	-- v_statecode int:=0;
	-- v_lwf_statecode int:=0;
	-- v_employeelwf numeric(18,2):=0;
	-- v_employerlwf numeric(18,2):=0;
	-- v_lwfdeductionmonths character varying(50):=NULL;
	-- v_salaryid bigint;
    v_lwf_applied character varying(1):=islwfstate;

	v_customeraccount_id bigint;
	v_epf_total bigint;
	v_esi_total bigint;
	v_islwfstate text;
	v_lwfstatecode integer:=lwfstatecode;
	v_personalinfoid int:=personalinfoid;
	v_createdby int:=createdby;
	v_createdbyip text:=createdbyip;
	v_monthlyofferedpackage numeric:=monthlyofferedpackage;
    v_joining_status TEXT:='NEW';
	-- END - New Variables Define
	v_designation_id bigint;
	v_jobrole text;
	v_grossearningcomponents numeric;
	v_workflowapprovalstatus int:=1;
BEGIN

/*************change 1.6 starts**************************/
	if exists(select 'x' 
			from tbl_application ta inner join openappointments op
			on ta.apptpcode=op.cjcode and op.emp_id=v_personalinfoid
			and ta.standardappmoduleid=34
			and ta.status='1'
			and ta.approved_status=0
			and ta.status='1'
			inner join mst_scheme_component msc
			on msc.id=ta.component_id and msc.form_build_status='1'
			inner join tbl_approval_workflow taw
			on msc.workflowid=taw.row_id and taw.status='1'
			)
	then
		v_workflowapprovalstatus:=0;
	end if;
/*************change 1.6 ends**************************/
if 	(monthlyofferedpackage	<0
or	basic	<0
or	hra	<0
or	allowances	<0
or	gross	<0
or	epf_employer	<0
or	epf_employee	<0
or	esi_employer	<0
or	esi_employee	<0
or	salary_in_hand	<0
or	ctc	<0
or	salarydays	<0
or	employeelwf	<0
or	employerlwf	<0
or	conveyance_allowance	<0
or	medical_allowance	<0
or	p_gratuity	<0
or	p_employergratuity	<0
or	p_commission	<0
or	p_salarybonus	<0
or	p_transport_allowance	<0
or	p_travelling_allowance	<0
or	p_leave_encashment	<0
or	p_overtime_allowance	<0
or	p_notice_pay	<0
or	p_hold_salary_non_taxable	<0
or	p_children_education_allowance	<0
or	p_gratuityinhand	<0
or	p_dailyallowance_rate	<0
) then
v_rfcsal:='Salary components must not be negative.';
return v_rfcsal;
end if;
if nullif(p_salarymasterjson,'') is null then
v_grossearningcomponents:=basic+hra+allowances+conveyance_allowance+medical_allowance+
				p_commission+p_salarybonus+p_transport_allowance+p_travelling_allowance+
				p_leave_encashment+p_overtime_allowance+p_notice_pay+p_hold_salary_non_taxable+
				p_children_education_allowance+p_gratuityinhand;
else
WITH data AS (SELECT p_salarymasterjson::jsonb AS js)
SELECT 
    --t.key AS component_name,
    sum(t.value::numeric) into v_grossearningcomponents
FROM data,
     jsonb_array_elements(js) elem,
     jsonb_each_text(elem) t;
end if;
/*****************change 1.2 starts*****************************/
update openappointments set pfopted=case when coalesce(epf_employee,0)>0 then 'Y' else 'N' end,
		esiopted =case when coalesce(esi_employee,0)>0 then 'Y' else 'N' end
where emp_id=v_personalinfoid;
/*****************change 1.2 ends*****************************/
	v_doj:=to_date(p_dateofjoining, 'dd/mm/yyyy');

	-- update effectiveto also
	IF EXISTS(SELECT * FROM empsalaryregister WHERE appointment_id = v_personalinfoid and isactive = '1') THEN
		v_joining_status := 'RESTRUCTURE';
		UPDATE empsalaryregister set isactive='0', effectiveto = to_date(effectivedate, 'dd/mm/yyyy') + interval '-1 day' WHERE appointment_id = v_personalinfoid AND isactive = '1';
	END IF;

	INSERT INTO public.empsalaryregister(
	appointment_id, designation, locationtype, salminwagesctgid, salctgid, minimumwagesalary, monthlyofferedpackage, basic, hra, allowances, gross, 
	employerepfrate, employeresirate,  employeeepfrate, employeeesirate, verificationstatus, salaryinhand, ctc, 
	/*verifiedby, verifiedon, */
	isactive, 
	createdby, createddate, createdbyip, /*modifiedby, modifiedon, modifiedbyip, optedinsurance, insuranceamount, familymemberscovered, familyinsuranceamount, ews, gratuity, */
	basicoption, salarydays, salaryindaysopted,
	/*bonus, special_allowance,* vpfemployee, taxes, govt_bonus_opted, govt_bonus_amt, revised, is_special_category, ct2, */
	minwagesctgname, revisiondate, remarks, pfcapapplied,
	effectivefrom, effectiveto, 
	/*incrementlettertext, annexure, incrementtemplateid, taxupdatedon, taxupdatedby, taxupdatedbyip,*/
	islwfstate, lwfstatecode, employeelwf, employerlwf, lwfdeductionmonths,
	/*isesiexceptionalcase, esiapplicabletilldate, esicexceptionmessage, isattendancerequired, salarygenerationbase, generatedbycustomeraccountid, modifiedbycustomeraccountid, leavetemplateid, leavetemplatetext, employergratuity, professionaltax,*/
	ptid, timecriteria, salaryhours, salarysetupcriteria,conveyance_allowance,medical_allowance,/*dynamiccomponent,*/gratuity,employergratuityopted,employergratuity,
	salarysetupmode,
	commission,
	salarybonus,
	transport_allowance,
	travelling_allowance,
	leave_encashment,
	overtime_allowance,
	notice_pay,
	hold_salary_non_taxable,
	children_education_allowance,
	gratuityinhand,
	dailyallowance_rate,
	e_customeraccountid,
	e_unitid,
	e_departmentid,
	e_designationid,
	pfapplicablecomponents,
	edli_adminchargesincludeinctc,
	esiapplicablecomponents,
	isgroupinsurance,
	insuranceamount,
	employerinsuranceamount,
	ishourlysetup,
	customtaxpercent,
	charity_contribution,
	is_exemptedfromtds,
	tds_exempted_docpath,
	grossearningcomponents,
	salarymasterjson,
	fullmonthincentiveapplicable,
	flexiblemonthdays
	)
	select
		v_personalinfoid, null, location_type, minwagescategoryid, case when epf_employee>0 then 1 else 2 end,
		minimumwagessalary, v_monthlyofferedpackage, basic, hra, allowances, gross,
		epf_employer,
		esi_employer,
		epf_employee,
		esi_employee,
		'V',
		salary_in_hand,
		ctc,
		--esiexceptionalcase,
		'1',
		createdby,
		current_timestamp,
		createdbyip,
		basicoption,
		salarydays,
		salarydaysopted,
		minwagescategoryname,	
		current_date,
		null,
		pfcapapplied,
		to_date(effectivedate,'dd/mm/yyyy'),
		null,
		v_lwf_applied,
		v_lwfstatecode,
		employeelwf,
		employerlwf,
		lwfdeductionmonths,
		ptid,
		'Full Time',
		8.00,
		case when p_ispiecerate='Y' then 'PieceRate'  when salarydays='1' then 'Daily' else 'Monthly' end,
		conveyance_allowance,
		medical_allowance,
		--dynamiccomponents,
		coalesce(p_gratuity,0),
		p_employergratuityopted,
		coalesce(p_employergratuity,0),
		'Custom',
		p_commission,
		p_salarybonus,
		p_transport_allowance,
		p_travelling_allowance,
		p_leave_encashment,
		p_overtime_allowance,
		p_notice_pay,
		p_hold_salary_non_taxable,
		p_children_education_allowance,
		p_gratuityinhand,
		p_dailyallowance_rate,
		coalesce(p_customeraccountid,0),
	    coalesce(p_unitid,0),
	    coalesce(p_departmentid,0),
	    coalesce(p_designationid,0),
		p_pfapplicablecomponents,
		p_edli_adminchargesincludeinctc,
		p_esiappliedcomponents,
		p_isgroupinsurance,
		case when coalesce(p_isgroupinsurance,'N')='Y' then p_employeeinsuranceamount else 0 end,
		case when coalesce(p_isgroupinsurance,'N')='Y' then p_employerinsuranceamount else 0 end,
		p_ishourlysetup,
		p_customtaxpercent,
		p_charity_contribution,
		p_is_exemptedfromtds,
		p_tds_exempted_docpath,
		v_grossearningcomponents,
		p_salarymasterjson,
		p_fullmonthincentiveapplicable,
		coalesce(p_flexiblemonthdays,'N')
	returning * into v_empsalaryregister;

/**************change 1.1 starts**************************************/
	update public.trn_candidate_otherduction
	set salaryid=v_empsalaryregister.id
	where candidate_id=v_personalinfoid and active='Y' and salaryid is null;

	SELECT customeraccountid INTO v_customeraccount_id FROM openappointments WHERE emp_id=v_personalinfoid;
/***************change 1.1 ends*************************************/	
	-- START :- Save Leave Template Details.
		BEGIN
			UPDATE tbl_tpemp_leavetemplates SET isactive='0', modifiedby=v_createdby, modifieddate=CURRENT_TIMESTAMP, modifiedip=v_createdbyip WHERE emp_id=v_personalinfoid AND isactive='1';

			v_leave_type:=((p_tp_leave_template_txt::json->0->>'leave_details')::json ->>'leave_type')::json;
			v_totalleaves:=0;
			v_carryforwardedleaves:=0;

			FOR v_leaverecord IN SELECT * FROM json_array_elements(v_leave_type)
			LOOP
				v_totalleaves:=v_totalleaves+(v_leaverecord->>'days')::int;
				IF (v_leaverecord->>'is_carry_forward')='Y' THEN
					v_carryforwardedleaves:=v_carryforwardedleaves+(v_leaverecord->>'days')::int;
				END IF;
			END LOOP;

			IF (v_leave_type->0->>'typecode')='CL' THEN
				v_clgranted:=v_leave_type->0->>'days';
				v_iscl_carry_forward:=v_leave_type->0->>'is_carry_forward';
				v_mlgranted:=v_leave_type->1->>'days';
				v_isml_carry_forward:=v_leave_type->1->>'is_carry_forward';
			ELSE
				v_clgranted:=v_leave_type->1->>'days';
				v_iscl_carry_forward:=v_leave_type->1->>'is_carry_forward';
				v_mlgranted:=v_leave_type->0->>'days';
				v_isml_carry_forward:=v_leave_type->0->>'is_carry_forward';
			END IF;

			INSERT INTO public.tbl_tpemp_leavetemplates
			(
				emp_id, 
				customeracountid, 
				calendartype, 
				weekly_off_days, 
				weekly_off_days_name, 
				clgranted, 
				mlgranted, 
				iscl_carry_forward, 
				isml_carry_forward, 
				attendance_approval_required_for_payout, 
				absent_is_equal_to_loss_of_pay, 
				template_id, 
				template_name, 
				appsource, 
				status, 
				createdby, 
				createddate, 
				createdip,
				totalleaves,
				carryforwardedleaves
			)
			VALUES
			(
				v_personalinfoid,
				v_customeraccount_id,
				(p_tp_leave_template_txt::json->0->>'leave_details')::json ->>'leaves_calender',
				(p_tp_leave_template_txt::json->0->>'leave_details')::json ->>'weekly_off_days',
				(p_tp_leave_template_txt::json->0->>'leave_details')::json ->>'weekly_off_days_name',
				v_clgranted, 
				v_mlgranted, 
				v_iscl_carry_forward, 
				v_isml_carry_forward, 
				(p_tp_leave_template_txt::json->0->>'leave_details')::json ->>'attendance_approval_required_for_payout',
				(p_tp_leave_template_txt::json->0->>'leave_details')::json ->>'absent_is_equal_to_loss_of_pay',
				(p_tp_leave_template_txt::json->0->>'templateid')::int, 
				(p_tp_leave_template_txt::json->0->>'templatedesc'), 
				'TP', 
				'1', 
				v_createdby,
				CURRENT_TIMESTAMP,
				v_createdbyip, 
				v_totalleaves,
				v_carryforwardedleaves
			);

			EXCEPTION WHEN OTHERS THEN NULL;
		END;
	-- END :- Save Leave Template Details.

	-- START :- Code Added for Convert Employee startes here.
		SELECT emp_code, NULLIF(designation_id, 0) INTO v_empcode, v_designation_id FROM openappointments WHERE emp_id=v_personalinfoid /*AND isactive='1'*/ AND appointment_status_Id<>13 /*AND COALESCE(left_flag,'N')<>'Y'*/;

		SELECT COALESCE(employerepfrate, 0) + COALESCE(employeeepfrate, 0), COALESCE(employeresirate, 0) + COALESCE(employeeesirate, 0)
		INTO v_epf_total, v_esi_total
		FROM empsalaryregister
		WHERE appointment_id=v_personalinfoid AND isactive='1';

		v_jobrole := p_jobrole;
		IF NULLIF(p_jobrole, '') IS NULL AND v_designation_id IS NOT NULL THEN
			SELECT designationname
			INTO v_jobrole
			FROM mst_tp_designations
			WHERE dsignationid = v_designation_id AND account_id = v_customeraccount_id;
		END IF;

		IF /*v_joining_status<>'RESTRUCTURE' and*/ v_empcode IS NULL THEN
			IF v_empcode IS NULL THEN
				SELECT nextval('openappointments_seq_empcode') INTO v_empcode;
			END IF;

			UPDATE openappointments 
			SET 
				dateofjoining=case when appointment_status_id in (11,14) then dateofjoining else v_doj end,
				emp_code=case when v_workflowapprovalstatus=1 then v_empcode else emp_code end,
				job_state=minwagestatename,
				appointment_status_id=case when v_workflowapprovalstatus=1 then 11 else appointment_status_id end,
				converted=case when v_workflowapprovalstatus=1 then 'Y' else converted end,
				esncode=case when v_workflowapprovalstatus=1 then  'TP'||EMP_CODE else esncode end,
				recordsource=case when v_workflowapprovalstatus=1 then 'HUBTPCRM' else recordsource end,
				cjcode='TP'||emp_id::text,
				pfopted=CASE WHEN v_epf_total>0 THEN 'Y' ELSE pfopted END,
				uannumber=CASE WHEN v_epf_total>0 AND nullif(trim(uannumber),'') IS NULL THEN 'Request For UAN' ELSE uannumber END,
				esiopted=CASE WHEN v_esi_total > 0 THEN 'Y' ELSE 'N' END,
				esinumber=CASE WHEN v_esi_total > 0 AND nullif(trim(esinumber),'') IS NULL THEN 'Request For ESIC' ELSE esinumber END,
				offered_salary = COALESCE(v_monthlyofferedpackage, 0),
				annualsalaryoffered = COALESCE(v_monthlyofferedpackage*12, 0),
				--post_offered=v_jobrole,
				minwagesstate=minwagestatename,
				islwfstate=v_lwf_applied,
				lwfstatecode=v_lwfstatecode
			WHERE emp_id=v_personalinfoid;

		if v_workflowapprovalstatus=1  then
			SELECT js_id INTO v_jsid FROM openappointments WHERE emp_id=v_personalinfoid;
			UPDATE tblemployeepin SET emp_code=v_empcode WHERE js_id=v_jsid AND emp_code IS NULL;

			SELECT nextval('users_seq') INTO v_userid;
			INSERT INTO users (userid, username, Emailid, Active, emp_code)
			SELECT v_userid, email, email, '1', emp_code FROM openappointments WHERE emp_id=v_personalinfoid;

			SELECT nextval('PersonalInformation_seq') INTO v_pid;
			INSERT INTO PersonalInformation
			(
				id,
				Name,
				FatherName,
				Gender,
				DOB_Christian,
				PanCard,
				UserId,
				CreatedBy,
				CreatedOn,
				AppointmentType,
				dateofjoininggovservice,
				aadharcardno
			)
			SELECT v_pid, emp_name, null, gender, dateofbirth, pancard, v_userid, null userby, CURRENT_TIMESTAMP, 'CJ', dateofjoining, aadharcard FROM openappointments WHERE emp_id=v_personalinfoid;

			UPDATE openappointments SET personalinfoid=v_pid WHERE emp_id=v_personalinfoid;

	end if;
	ELSE
			UPDATE openappointments 
			SET 
				dateofjoining=v_doj,
				appointment_status_id=11,
				job_state=minwagestatename,
				pfopted=CASE WHEN v_epf_total>0 THEN 'Y' ELSE pfopted END,
				uannumber=CASE WHEN v_epf_total>0 AND nullif(trim(uannumber),'') IS NULL THEN 'Request For UAN' ELSE uannumber END,
				esiopted=CASE WHEN v_esi_total > 0 THEN 'Y' ELSE 'N' END,
				esinumber=CASE WHEN v_esi_total > 0 AND nullif(trim(esinumber),'') IS NULL THEN 'Request For ESIC' ELSE esinumber END,
				offered_salary = COALESCE(v_monthlyofferedpackage, 0),
				annualsalaryoffered = COALESCE(v_monthlyofferedpackage*12, 0),
				--post_offered=v_jobrole,
				minwagesstate=minwagestatename,
				islwfstate=v_lwf_applied,
				lwfstatecode=v_lwfstatecode
			WHERE emp_id=v_personalinfoid;
		END IF;
	-- END :- Code Added for Convert Employee startes here.

	-- START :- Update Salary ID for null. -- Added on 29/04/2024
-- 	UPDATE trn_candidate_otherduction SET salaryid=(SELECT MAX(ID) FROM empsalaryregister WHERE appointment_id=v_personalinfoid AND isactive='1') WHERE candidate_id=v_personalinfoid AND active='Y' AND salaryid IS NULL;
	-- END :- Update Salary ID for null.

	select array_to_json(array_agg(row_to_json(X)))::text FROM (
		select * from empsalaryregister where appointment_id=v_personalinfoid and isactive='1'
		) as X
		into v_rfcsal;
		
	return v_rfcsal;
END;
$BODY$;

ALTER FUNCTION public.uspsavecustomsalarystructure(integer, character varying, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, character varying, integer, character varying, character varying, integer, numeric, numeric, character varying, integer, character varying, integer, character varying, character varying, character varying, integer, character varying, numeric, text, integer, character varying, numeric, numeric, integer, text, character varying, text, text, numeric, text, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, bigint, bigint, bigint, bigint, numeric, text, numeric, character varying, double precision, double precision, character varying, numeric, character varying, character varying, character varying, character varying, text, numeric, character varying, character varying)
    OWNER TO payrollingdb;

