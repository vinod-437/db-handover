-- FUNCTION: public.uspcreatecustomsalarystructure(integer, character varying, integer, character varying, double precision, integer, integer, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, character varying, double precision, double precision, character varying, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.uspcreatecustomsalarystructure(integer, character varying, integer, character varying, double precision, integer, integer, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, character varying, double precision, double precision, character varying, character varying, character varying);

CREATE OR REPLACE FUNCTION public.uspcreatecustomsalarystructure(
	p_appointment_id integer,
	p_minwagesstatename character varying,
	p_minwagescategoryid integer,
	p_locationtype character varying DEFAULT 'Metro'::character varying,
	p_monthlyofferedpackage double precision DEFAULT 0,
	p_basicoption integer DEFAULT 6,
	p_salarydays integer DEFAULT 30,
	p_salarydaysopted character varying DEFAULT 'N'::character varying,
	p_pfcapapplied character varying DEFAULT 'Y'::character varying,
	p_effectivefrom character varying DEFAULT NULL::character varying,
	p_pt_applicable character varying DEFAULT 'N'::character varying,
	p_lwf_applicable character varying DEFAULT 'N'::character varying,
	p_pf_opted character varying DEFAULT 'N'::character varying,
	p_esiopted character varying DEFAULT 'N'::character varying,
	p_salarystructure character varying DEFAULT ''::character varying,
	p_gratuityopted character varying DEFAULT 'N'::character varying,
	p_employergratuityopted character varying DEFAULT 'N'::character varying,
	p_employerpartexcludedfromctc character varying DEFAULT 'Y'::character varying,
	p_customeraccountid integer DEFAULT '-9999'::integer,
	p_isgroupinsurance character varying DEFAULT 'N'::character varying,
	p_employeeinsuranceamount double precision DEFAULT 0.0,
	p_employerinsuranceamount double precision DEFAULT 0.0,
	p_ishourlysetup character varying DEFAULT 'N'::character varying,
	p_charity_contribution character varying DEFAULT 'N'::character varying,
	p_ispiecerate character varying DEFAULT 'N'::character varying)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$

/*************************************************************************
Version 	Date			Change								Done_by
1.0			22-Apr-2024		Initial Version						Shiv Kumar
1.1			20-May-2024		Gratuity							Shiv Kumar
1.2			31-May-2024		Static 10 heads						Shiv Kumar
1.3			17-Jun-2024		AC21 Max 75							Shiv Kumar
1.4			22-Jun-2024		Add Annual Variables				Shiv Kumar
1.5			17-Jul-2024		PF/ESI Enable Condition				Shiv Kumar
1.6			28-Aug-2024		Revert AC21 Max 75					Shiv Kumar
							As per Mail Dated 28-Aug-2024 Roll Back the PF ( as per Pankaj Priti )
1.7			18-Sep-2024		PF on other than Basic				Shiv Kumar
1.8			26-Nov-2024		ESIC Exception Handling				Shiv Kumar
1.9			06-Feb-2025		Employee ESIC on 176 Rs/day			Shiv Kumar
2.0			04-Jun-2025		Adding Monthly Components			Shiv Kumar
2.1			27-Jun-2025		Deducting VPF from Net Pay			Shiv Kumar
2.2			01-Jul-2025		Meal Voucher						Shiv Kumar
2.5			23-Jul-2025		Deduct Annually, Half yearly,		Shiv Kumar
							 quarterly LWF from gross
2.8			24-Sep-2025		Adding Gross and grossearningcomponents	Shiv Kumar
2.9			04-Sep-2025		Gratuity on multiple heads			Shiv Kumar
2.10			20-Dec-2025		Apprentices Salary Setup			Shiv Kumar
2.11          09-March-2026   v_ESI_Employee:=ceil(v_ESI_Employee); As per ESI rule given by Satish Ji line No 550 Shiv Kumar
*************************************************************************/
DECLARE
	sal refcursor;
	v_salarycategoryname varchar(30);
	v_hra double precision:=0;
	v_allowances double precision:=0;
	v_gross double precision:=0;
	v_EPF_Employer double precision:=0;
	v_ESI_Employer double precision:=0;
	v_NPS_EMPLOYER double precision:=0;
	v_NPS_EMPLOYEE double precision:=0;
	v_EPF_Employee double precision:=0;
	v_ESI_Employee double precision:=0;
	v_salary_in_hand double precision:=0;
	v_CTC double precision:=0;
	v_Difference double precision:=0;
	v_insuranceamount double precision:=0;
	v_familyinsuranceamount double precision:=0;
	v_ews double precision:=0;
	v_gratuity double precision:=0.0;
	v_basic double precision:=0;
	v_monthlyofferedpackage double precision:=0.0;
	v_pfopted varchar(1);
	v_esiopted varchar(1);
	v_medicalinsuranceopted varchar(1);
	v_gratuityopted varchar(1);
	v_performancebonus_opted varchar(1);
	v_npsopted varchar(1);
	v_minwagescategoryid int;
	v_gross2 double precision:=0;
	v_deductions double precision:=0.0;
	v_hratemp double precision:=0.0;
	v_hratemp2 double precision:=0.0;
	v_govt_bonus_opted varchar(1);
	v_govt_bonus_amt double precision:=0.0;
	v_govt_bonus_rate double precision:=0.0;
	v_otherdeductions double precision:=0.0;
	v_familymemberscovered double precision:=0.0;
	v_monthlyvaraible_excluded double precision:=0.0;
	v_esiapplieddeductions numeric(18,5):=0.0;
	v_variableamount numeric(18,2):=0.0;
	v_lwfstatecode int;
	v_ptid int;
	v_statecode int;
	v_employerlwf numeric(18,2):=0.0;
	v_employeelwf numeric(18,2):=0.0; 
	v_lwfdeductionmonths varchar(150):=NULL;
	v_isesiambit varchar(1);
	v_frequency varchar(30);
	v_customeraccountid bigint;
	v_number_of_employees int;
	v_operation varchar(30);
	v_effectivedate date;
	v_emp_code bigint;
	v_doj text;
	v_effective_from text;
	v_minimumwagessalary text;
	v_minwagescategoryname text;
	v_appointment_status_id int;
	v_uannumber text;
	v_timecriteria text:='Full Time';
	v_salarysetupcriteria text:=case when p_ispiecerate='Y' then 'PieceRate' else 'Monthly' end;
	v_salaryhours double precision:=8.00;
	v_is_valid int:=0;
	v_compliancemodeltype varchar(10);
	
	v_esiappliedvariables numeric(18,5):=0.0;
	v_esinotappliedvariables numeric(18,5):=0.0;

	v_conveyance_allowance numeric(18,5):=0.0;
	v_medical_allowance numeric(18,5):=0.0;
	v_employergratuity numeric(18,5):=0.0;
	v_dynamiccomponents text;
	
	
	v_commission NUMERIC(18,2);
	v_salarybonus NUMERIC(18,2);
	v_transport_allowance NUMERIC(18,2);
	v_travelling_allowance NUMERIC(18,2);
	v_leave_encashment NUMERIC(18,2);
	v_overtime_allowance NUMERIC(18,2);
	v_notice_pay NUMERIC(18,2);
	v_hold_salary_non_taxable NUMERIC(18,2);
	v_children_education_allowance NUMERIC(18,2);
	v_gratuityinhand NUMERIC(18,2);
    v_rfcmastersalcomponents refcursor;
	v_rec record;
	v_reccomplianceflags record;
	v_pfapplicablecomponents  double precision DEFAULT 0.0;
	v_employerepfrate NUMERIC(18,2);
	v_openappointments openappointments%rowtype;
	v_charity_contribution_amount numeric(18,2):=0;
	v_monthlytaxable_bonus numeric(18,2):=0;
	v_monthlynontaxable_bonus numeric(18,2):=0;
	v_vpf numeric(18,2):=0;
	v_mealvoucher numeric(18,5):=0.0;
	v_grossearningcomponents numeric;
	v_salary_head_text text;

   v_mastercomponent refcursor;
   v_gratuityapplicablecomponents numeric(18,2):=0;
   v_gr1 numeric(18,2):=0;
   v_recmastercomponent record;
   v_salarymasterjson text;
BEGIN
	/**************Change 2.20 starts***********************/
	select sum(deduction_amount) 
			into v_mealvoucher
	   from public.trn_candidate_otherduction
	   inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
	   where trn_candidate_otherduction.candidate_id=p_appointment_id
	   	and trn_candidate_otherduction.active='Y'
	   	and deduction_amount>0
	  	and motd.id=134 --Meal Voucher ID
		and salaryid is null
	  group by trn_candidate_otherduction.candidate_id;
	  
	  v_mealvoucher:=coalesce(v_mealvoucher,0);
	/**************Change 2.20 ends*************************/
select * from openappointments where emp_id=p_appointment_id into v_openappointments;
	/**************Change 2.10 starts*************************/	
if v_openappointments.jobtype='Apprentices' or v_openappointments.jobtype='Trainee' then
if	p_pt_applicable	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'Proffessional tax not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_lwf_applicable	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'LWF not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_pf_opted	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'PF not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_esiopted	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'ESIC not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_gratuityopted	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'Gratuity not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_employergratuityopted	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'Employer Gratuity not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_isgroupinsurance	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'Group Insurance not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_ishourlysetup	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'Hourly Setup not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif p_charity_contribution	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'Charity Contribution not applicable for Apprentice. Please disable.' as msg;
		return sal;
elsif	p_ispiecerate	=	'Y'	then 	
OPEN sal FOR
		SELECT 
				'Piece Rate not applicable for Apprentice. Please disable.' as msg;
		return sal;
end if;
end if;
	/**************Change 2.10 ends*************************/	
/*************************change 1.7 starts*************************************/
select 
		coalesce(employerpfincludeinctc,'Y') employerpfincludeinctc,
		coalesce(edli_adminchargesincludeinctc,'Y') edli_adminchargesincludeinctc,
		coalesce(pfonbasiconly,'Y') pfonbasiconly,
		coalesce(pfcapapplied,'Y') pfcapapplied
from mst_employer_compliance_settings
where customer_account_id=p_customeraccountid and is_active='1'
into v_reccomplianceflags;

if coalesce(v_reccomplianceflags.edli_adminchargesincludeinctc,'Y')='Y' then
	v_employerepfrate:=0.13;
else
	v_employerepfrate:=0.12;
end if;

	Raise Notice 'v_reccomplianceflags.edli_adminchargesincludeinctc=%',v_reccomplianceflags.edli_adminchargesincludeinctc;
/*************************change 1.7 ends*************************************/								
/***************************change 1.5 starts************************************/
/**********************PF Condition**********************************************/
if (exists(select * from tbl_monthlysalary where emp_code=v_openappointments.emp_code and epf>0 and is_rejected='0')
	)
		 and p_pf_opted='N' then
			OPEN sal FOR
		SELECT 
				'Salary already generated. PF cannot be disabled.' as msg;
		return sal;	 
end if;
if (exists(select emp_code from openappointments where emp_id=p_appointment_id and uannumber ~ '^[0-9\.]+$')
	)
		 and p_pf_opted='N' then
	
			OPEN sal FOR
		SELECT 
				'UAN number already generated. PF cannot be disabled.' as msg;
		return sal;	 
end if;	
/***************************change 1.5 ends******************************************************************************/
/**********change 1.4 starts****************/
	SELECT sum(deduction_amount) INTO v_variableamount FROM trn_candidate_otherduction 
	WHERE candidate_id=p_appointment_id AND active='Y' AND COALESCE(includedinctc,'N')='Y' 
	AND COALESCE(isvariable,'N')='Y' AND deduction_frequency IN ('Quarterly','Half Yearly','Annually') 
	 and salaryid is null and deduction_id<>134;

	SELECT sum(deduction_amount) INTO v_otherdeductions FROM trn_candidate_otherduction 
	WHERE candidate_id=p_appointment_id AND active='Y' AND COALESCE(includedinctc,'N')='Y'
	 AND COALESCE(isvariable,'N')='N' AND deduction_frequency IN ('Quarterly','Half Yearly','Annually') 
	  and salaryid is null and deduction_id<>134;
/**********change 1.4 ends****************/
/****************************************change 2.0 starts************************************/
select sum(deduction_amount) otherdeductionswithesi
from public.trn_candidate_otherduction inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
where public.trn_candidate_otherduction.active='Y' and motd.deduction_name not in ('Medical Expenses')
and deduction_amount>0 and (
	trn_candidate_otherduction.deduction_id in (5,6) or 
coalesce(trn_candidate_otherduction.is_taxable,'N')='Y'
)
and trn_candidate_otherduction.deduction_frequency in ('Monthly')
and candidate_id=p_appointment_id and salaryid is null
 and deduction_id<>134
into v_monthlytaxable_bonus;

select sum(deduction_amount) othervariables
from public.trn_candidate_otherduction
inner join mst_otherduction motd on motd.id=trn_candidate_otherduction.deduction_id
where public.trn_candidate_otherduction.active='Y'
and motd.deduction_name not in ('Conveyance')
and deduction_amount>0
and trn_candidate_otherduction.deduction_frequency in ('Monthly')
and trn_candidate_otherduction.deduction_id not in (5,6,7,10)
and coalesce(trn_candidate_otherduction.is_taxable,'N')='N'
and candidate_id=p_appointment_id and salaryid is null
 and deduction_id<>134
into v_monthlynontaxable_bonus;
/******************************change 2.0 ends************************************************/	
			v_monthlyofferedpackage:=p_monthlyofferedpackage;
	/****************************store salary components*****************/				
				create temporary table tmpsalarycomponent
				(
					salary_component_id		text,
					salary_component_name	varchar(100),
					percentage_ctc			numeric(18,2),
					percentage_fixed		varchar(30),
					is_taxable				varchar(1),
					ispfapplicable			varchar(1),
					salary_component_amount	numeric(18,2)
				)on commit drop;
		
				insert into tmpsalarycomponent		
				select *  from jsonb_populate_recordset(null::record,p_salarystructure::jsonb) 
                            as (
									salary_component_id	text,
									salary_component_name	varchar(100),
									percentage_ctc		numeric(18,2),
									percentage_fixed	varchar(30),
									is_taxable			varchar(1),
									ispfapplicable			varchar(1),			
									salary_component_amount	numeric(18,2)
							);

	/****************change 2.4 starts**************************/ 
	select public.getmastersalarystructure(
	p_action =>'GetMasterSalaryStructure',
	p_customeraccountid =>p_customeraccountid)
	into v_mastercomponent;
	

	LOOP
		FETCH v_mastercomponent INTO v_recmastercomponent;
		EXIT WHEN NOT FOUND;
		      IF v_recmastercomponent.gratuityapplicable='Y' or upper(v_recmastercomponent.componentname)='BASIC SALARY' then
				select coalesce(salary_component_amount,0) from tmpsalarycomponent
				where UPPER(salary_component_name) =upper(v_recmastercomponent.componentname)
				into v_gr1;
				v_gratuityapplicablecomponents:=v_gratuityapplicablecomponents+coalesce(v_gr1,0);
			  END IF;
	END LOOP;
	/****************change 2.4 ends**************************/

	v_isesiambit:='N';
	SELECT wagesctgname, minimumwagessalary FROM mst_minimumwagescategory 
	WHERE wcid=p_minwagescategoryid INTO v_minwagescategoryname, v_minimumwagessalary;
	
	SELECT statecode FROM mst_state WHERE lower(trim(statename_inenglish))=lower(trim(p_minwagesstatename)) INTO v_statecode;
	v_lwfstatecode:=CASE WHEN COALESCE(p_lwf_applicable, 'N')='Y' THEN v_statecode ELSE 0 END;
	v_ptid:=CASE WHEN COALESCE(p_pt_applicable, 'N')='Y' THEN v_statecode ELSE 0 END;

	SELECT medicalinsuranceopted, gratuityopted, performancebonus_opted, npsopted, govt_bonus_opted, ewfamount, customeraccountid, emp_code, TO_CHAR(dateofjoining, 'dd/mm/yyyy'), appointment_status_id, uannumber
	INTO v_medicalinsuranceopted, v_gratuityopted, v_performancebonus_opted, v_npsopted, v_govt_bonus_opted, v_ews, v_customeraccountid, v_emp_code, v_doj, v_appointment_status_id, v_uannumber
	FROM openappointments 
	WHERE emp_id=p_appointment_id;
	
	v_pfopted:=p_pf_opted;
	v_esiopted:=p_esiopted;

	v_effectivedate:=greatest(to_date(v_doj, 'dd/mm/yyyy'), date_trunc('month', to_date(p_effectivefrom,'dd/mm/yyyy'))::date);

	IF v_appointment_status_id = 1 THEN
		v_operation:='Generate';
	ELSIF (v_appointment_status_id = 11 OR v_appointment_status_id = 14) THEN
		v_operation:='Restructure';
	END IF;

	v_effective_from:=TO_CHAR(v_effectivedate, 'dd/mm/yyyy');
	SELECT uspcalesiexceptionalcase(p_appointment_id, nullif(v_effective_from, '')) INTO v_isesiambit;

 if p_appointment_id in (12640,30620,30618) then --RBTC ESIC Exception Case handle due to Onbarding in tankha pay with excption Mail dated 24 July 2025 Jitendra
    v_isesiambit:='Y';
    end if;
		select sum(salary_component_amount) from tmpsalarycomponent
		where upper(salary_component_name) in ('BASIC SALARY')
		into v_basic;
		
		v_basic:=coalesce(v_basic,0);
		/******************************************/
			
	select sum(salary_component_amount) from tmpsalarycomponent where ispfapplicable='Y' into v_pfapplicablecomponents;
	v_pfapplicablecomponents:=coalesce(v_pfapplicablecomponents,0);
	v_pfapplicablecomponents:=coalesce(nullif(v_pfapplicablecomponents,0),v_basic);

	v_pfapplicablecomponents:=case when p_ispiecerate='Y' then p_monthlyofferedpackage else v_pfapplicablecomponents end;
	
			v_gratuity=0;
			if p_gratuityopted='Y' then
				v_gratuity:=uspcalcgratuity(p_customeraccountid,coalesce(v_gratuityapplicablecomponents,v_basic)::numeric) ;--((((v_basic)*15/26)*5)/60)::numeric(18,5);
			end if;
			
			
			v_employergratuity=0;
			if p_employergratuityopted='Y' then
				v_employergratuity:=uspcalcgratuity(p_customeraccountid,coalesce(v_gratuityapplicablecomponents,v_basic)::numeric);--((((v_basic)*15/26)*5)/60)::numeric(18,5);
			end if;			
		/******************************************/
		select sum(salary_component_amount) from tmpsalarycomponent
		where upper(salary_component_name) in ('HRA')
		into v_hra;
		v_hra:=coalesce(v_hra,0);

		select sum(salary_component_amount) from tmpsalarycomponent
		where upper(salary_component_name) in ('SPECIAL ALLOWANCE')
		into v_allowances;
		
		v_allowances:=coalesce(v_allowances,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('CONVEYANCE')
		into v_conveyance_allowance;

		v_conveyance_allowance:=coalesce(v_conveyance_allowance,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where upper(salary_component_name) in ('MEDICAL EXPENSES')
		into v_medical_allowance;
		
		v_medical_allowance:=coalesce(v_medical_allowance,0);
		
		/***********************************************************/
		select sum(salary_component_amount) from tmpsalarycomponent
		where upper(salary_component_name) in ('SALARY BONUS')
		into v_salarybonus;
		v_salarybonus:=coalesce(v_salarybonus,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where upper(salary_component_name) in ('COMMISSION')
		into v_commission;
		v_commission:=coalesce(v_commission,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('TRANSPORT ALLOWANCE')
		into v_transport_allowance;
		v_transport_allowance:=coalesce(v_transport_allowance,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('TRAVELLING ALLOWANCE')
		into v_travelling_allowance;
		v_travelling_allowance:=coalesce(v_travelling_allowance,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('LEAVE ENCASHMENT')
		into v_leave_encashment;
		v_leave_encashment:=coalesce(v_leave_encashment,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('OVERTIME ALLOWANCE')
		into v_overtime_allowance;
		v_overtime_allowance:=coalesce(v_overtime_allowance,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('NOTICE PAY')
		into v_notice_pay;
		v_notice_pay:=coalesce(v_notice_pay,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('HOLD SALARY (NON TAXABLE)')
		into v_hold_salary_non_taxable;
		v_hold_salary_non_taxable:=coalesce(v_hold_salary_non_taxable,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('CHILDREN EDUCATION ALLOWANCE')
		into v_children_education_allowance;
		v_children_education_allowance:=coalesce(v_children_education_allowance,0);
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where UPPER(salary_component_name) in ('GRATUITY IN HAND')
		into v_gratuityinhand;
		v_gratuityinhand:=coalesce(v_gratuityinhand,0);
/******************************************************************************************************************/
	
	IF ((v_esiopted='Y' or p_pt_applicable='Y' or p_lwf_applicable='Y') AND COALESCE(v_pfopted, 'N')='N') THEN
		IF (p_monthlyofferedpackage::INT < 17440 and v_number_of_employees>20) THEN
				v_is_valid:=0;
			OPEN sal FOR
				SELECT v_is_valid status, 'CTC can not be less than ₹17440.' msg;
			RETURN sal;
		END IF;
		IF (v_basic::INT <= 15000 and v_number_of_employees>20) THEN
			OPEN sal FOR
				SELECT v_is_valid status, 'Basic salary must be greater than ₹15000.' msg;
			RETURN sal;
		END IF;
	END IF;
/************LWF Calculation**************************************/
	IF COALESCE(p_lwf_applicable,'N')='Y' THEN
		SELECT employeelwfrate/(case when frequency='Annually' then 12 when frequency='Half Yearly' then 6 when frequency='Quartrly' then 3  when frequency='Monthly' then 1 end),
		employerlwfrate/(case when frequency='Annually' then 12 when frequency='Half Yearly' then 6 when frequency='Quartrly' then 3  when frequency='Monthly' then 1 end),
		deductionmonths, frequency
		INTO v_employeelwf, v_employerlwf, v_lwfdeductionmonths, v_frequency
		FROM statewiselwfrate
		WHERE statecode=v_lwfstatecode /*and v_lwfstatecode<>7*/ AND isactive='1';
	END IF;
	v_employerlwf:=COALESCE(v_employerlwf,0);
	v_employeelwf:=COALESCE(v_employeelwf,0);

	IF v_frequency<>'Monthly' THEN
		--v_employerlwf:=0;
		v_employeelwf:=0;
	END IF;

		select sum(salary_component_amount) from tmpsalarycomponent
		where is_taxable='Y'
		into v_esiappliedvariables;
		
		select sum(salary_component_amount) from tmpsalarycomponent
		where is_taxable='N'
		into v_esinotappliedvariables;	

		v_esiappliedvariables:=coalesce(v_esiappliedvariables,0);
		v_esinotappliedvariables:=coalesce(v_esinotappliedvariables,0);

		v_esinotappliedvariables:=case when p_ispiecerate='Y' then p_monthlyofferedpackage else v_esinotappliedvariables end;

		select sum(salary_component_amount) from tmpsalarycomponent
		into v_gross;	
		v_grossearningcomponents:=v_gross;
  
																	  
/************ESI Calculation**************************************/	
/**********************ESI Condition*******************************/
if (exists(select * from tbl_monthlysalary where emp_code=v_openappointments.emp_code and employeeesirate>0 and is_rejected='0')
	) and v_esiappliedvariables<21000 and v_isesiambit='Y'
		 and p_esiopted='N' then
	
			OPEN sal FOR
		SELECT 
				'Salary already generated. ESI cannot be disabled.' as msg;
		return sal;	 
end if;
if (exists(select emp_code from openappointments where emp_id=p_appointment_id and esinumber ~ '^[0-9\.]+$')
	) and v_esiappliedvariables<21000 and v_isesiambit='Y'
		 and p_esiopted='N' then
	
			OPEN sal FOR
		SELECT 
				'ESI number already generated. ESI cannot be disabled.' as msg;
		return sal;	 
end if;	

		IF (v_esiopted='Y' or p_pt_applicable='Y' or p_lwf_applicable='Y' or COALESCE(v_pfopted, 'N')='Y') and ((v_esiappliedvariables<=21000 and v_esiopted='Y') or v_isesiambit='Y') THEN
				v_ESI_Employer:=v_esiappliedvariables*0.0325;
			/****change 1/9 condition ******/
			if v_esiappliedvariables/p_salarydays>176 then
				v_ESI_Employee:=v_esiappliedvariables*.0075;
			end if;	
		else
				v_ESI_Employer:=0.00;
				v_ESI_Employee:=0.00;
		end if;
v_ESI_Employee:=ceil(v_ESI_Employee);	
/************PF Calculation**************************************/
		v_EPF_Employee:=0;
		v_EPF_Employer:=0;
		
		IF v_pfopted='Y'  THEN
			if p_pfcapapplied='Y' then
					if coalesce(v_reccomplianceflags.edli_adminchargesincludeinctc,'Y')='Y' then
							v_EPF_Employer:=(least(v_pfapplicablecomponents*v_employerepfrate,1950)::numeric(18,5));
					else
							v_EPF_Employer:=(least(v_pfapplicablecomponents*v_employerepfrate,1800)::numeric(18,5));
					end if;		
                    v_EPF_Employee:=(least(v_pfapplicablecomponents*.12,1800)::numeric(18,5));
			else
                    v_EPF_Employer:=((v_pfapplicablecomponents*v_employerepfrate)::numeric(18,5));-- commented for change 1.3 --opened for change 1.6
                    v_EPF_Employee:=((v_pfapplicablecomponents*.12)::numeric(18,5));
			
			end if;
					v_salarycategoryname='PF';
					
		else
                    v_EPF_Employer:=0::numeric(18,5);
                    v_EPF_Employee:=0::numeric(18,5);
					v_salarycategoryname='PFN';
		END IF;
		
		v_ctc:=v_gross+v_ESI_Employer+v_EPF_Employer+v_employerlwf+v_employergratuity;
		v_salary_in_hand:=v_gross-v_ESI_Employee-v_EPF_Employee-v_employeelwf-coalesce(v_gratuity,0);
		
 		v_salary_in_hand:=v_salary_in_hand-COALESCE(v_otherdeductions,0)-coalesce(p_employeeinsuranceamount,0);
 		v_ctc:=v_ctc+COALESCE(v_variableamount,0)+coalesce(p_employerinsuranceamount,0)+coalesce(v_monthlytaxable_bonus,0)+coalesce(v_monthlynontaxable_bonus,0)+v_mealvoucher;
/***************change 2.1 starts***************************/
select sum(deduction_amount) into v_vpf from trn_candidate_otherduction  
where candidate_id=p_appointment_id AND active='Y' and deduction_id=10   and salaryid is null;
v_salary_in_hand:=v_salary_in_hand-coalesce(v_vpf,0);
/***************change 2.1 ends*****************************/	
/***************change 2.7 starts***************************/
		select salary_head_text into v_salary_head_text from mst_tp_business_setups 
		where tp_account_id=v_customeraccountid ::bigint and row_status='1';
	if v_salary_head_text is not null then
				if ( SELECT count(1)
					FROM jsonb_array_elements(v_salary_head_text::jsonb) AS elem
					WHERE elem ? 'earningtype' ) > 0	then
					with tmpmasterstruct as
					(
					select *  from jsonb_populate_recordset(null::record,v_salary_head_text::jsonb)
					as 
						( 
							id bigint ,
						   earningtype text ,
						   componentname text,
						   calculationtype text ,
						   calculationbasis text ,
						   epfapplicable text ,
						   esiapplicable text ,
						   calculationpercent numeric ,
						   isactive text ,
						   displayorder int ,
						  includedingross text
						)
					)

					select sum(salary_component_amount)
						from tmpmasterstruct	inner join tmpsalarycomponent
						on tmpmasterstruct.componentname=tmpsalarycomponent.salary_component_name
						and coalesce(tmpmasterstruct.includedingross,'Y')='Y'
						into v_gross;
						
					else
						select sum(salary_component_amount) from tmpsalarycomponent
						into v_gross;
						raise notice 'if else step -2 v_gross=>%',v_gross;
					end if;		
			
   
		else
											
			with tmpmasterstruct as
					(
					select *  from jsonb_populate_recordset(null::record,v_salary_head_text::jsonb)
					as 
						( 
							id bigint ,
						   earningtype text ,
						   componentname text,
						   calculationtype text ,
						   calculationbasis text ,
						   epfapplicable text ,
						   esiapplicable text ,
						   calculationpercent numeric ,
						   isactive text ,
						   displayorder int ,
						  includedingross text
						)
					)		
				select (
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='BASIC SALARY'),'Y')='N' then 0 else coalesce(v_basic,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='HRA'),'Y')='N' then 0 else coalesce(v_hra,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='SPECIAL ALLOWANCE'),'Y')='N' then 0 else coalesce(v_allowances,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='CONVEYANCE'),'Y')='N' then 0 else coalesce(v_conveyance_allowance,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='MEDICAL EXPENSES'),'Y')='N' then 0 else coalesce(v_medical_allowance,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='COMMISSION'),'Y')='N' then 0 else coalesce(v_commission,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='SALARY BONUS'),'Y')='N' then 0 else coalesce(v_salarybonus,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='TRANSPORT ALLOWANCE'),'Y')='N' then 0 else coalesce(v_transport_allowance,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='TRAVELLING ALLOWANCE'),'Y')='N' then 0 else coalesce(v_travelling_allowance,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='LEAVE ENCASHMENT'),'Y')='N' then 0 else coalesce(v_leave_encashment,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='OVERTIME ALLOWANCE'),'Y')='N' then 0 else coalesce(v_overtime_allowance,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='NOTICE PAY'),'Y')='N' then 0 else coalesce(v_notice_pay,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='HOLD SALARY (NON TAXABLE)'),'Y')='N' then 0 else coalesce(v_hold_salary_non_taxable,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='CHILDREN EDUCATION ALLOWANCE'),'Y')='N' then 0 else coalesce(v_children_education_allowance,0) end +
			case when coalesce((select upper(includedingross) from tmpmasterstruct where upper(componentname)='GRATUITY IN HAND'),'Y')='N' then 0 else coalesce(v_gratuityinhand,0) end
		) into v_gross;
	end if;
/***************change 2.7 ends*****************************/	

		if p_charity_contribution='Y' then
			v_charity_contribution_amount:=v_basic*.01;
		end if;
		v_salary_in_hand:=v_salary_in_hand-coalesce(v_charity_contribution_amount,0)+v_mealvoucher;
-- 		OPEN sal FOR
-- 		SELECT v_ESI_Employer,v_ESI_Employee,v_EPF_Employee,v_EPF_Employer,v_employeelwf,v_employerlwf;
-- 		return sal;	

	select json_agg(json_build_object(salary_component_name, salary_component_amount))
		into v_salarymasterjson
		FROM (
				select salary_component_name,salary_component_amount from tmpsalarycomponent
			)t;

			
			OPEN sal FOR
   
   
		SELECT 
				p_appointment_Id personalinfoid, v_salarycategoryname salarycategoryname, v_monthlyofferedpackage monthlyofferedpackage, 
				v_basic basic, v_hra as HRA, v_allowances as allowances, v_gross gross, v_EPF_Employer epf_employer, v_EPF_Employee epf_employee,
				v_ESI_Employer esi_employer, v_ESI_Employee esi_employee, v_salary_in_hand salary_in_hand, v_CTC ctc, v_isesiambit esiexceptionalcase,
				/*0 employersocialsecurity, 0 employeesocialsecurity, 'Basic' salarygenerationbase,*/
				/*p_optedinsurance optedinsurance, p_familymemberscovered familymemberscovered, v_insuranceamount insuranceamount, 
				v_familyinsuranceamount familyinsuranceamount, v_ews ews, v_gratuity gratuity, COALESCE(v_NPS_EMPLOYER, 0) NPS_EMPLOYER,
				v_NPS_EMPLOYEE NPS_EMPLOYEE,*/ p_salarydays salarydays, /*p_bonusamount bonus, v_govt_bonus_opted govt_bonus_opted,
				v_govt_bonus_amt govt_bonus_amt, COALESCE(v_otherdeductions, 0) otherdeductions, p_is_special_category is_special_category,
				p_ct2 ctc2, */p_pfcapapplied pfcapapplied, /*p_taxes taxes,*/ p_lwf_applicable islwfstate, v_lwfstatecode lwfstatecode, v_employeelwf employeelwf,
				v_employerlwf employerlwf, v_lwfdeductionmonths lwfdeductionmonths, v_ptid ptid, p_locationtype location_type, 
				/*p_financialyear financial_year,*/ p_basicoption basicoption, p_salarydaysopted salarydaysopted, v_operation operation, 
				p_minwagesstatename minwagestatename, p_minwagescategoryid minwagescategoryid, v_minwagescategoryname minwagescategoryname, 
				v_minimumwagessalary minimumwagessalary, /*v_uannumber uannumber, 'Pass' calcresult, 0 suggestivesalary, '' salmessage, 
				0 leavetemplateid, '' leavetemplatetext, 0 dailywagerate, 0 dailyesiccontribution, 0 dailyepfcontribution, 0 dailysalary_in_hand, 0 dailyctc,
				v_timecriteria timecriteria, v_salarysetupcriteria salarysetupcriteria, v_salaryhours salaryhours, */v_effective_from effectivedate,
				1 status, 'Salary calculated successfully.' msg/*,v_number_of_employees number_of_employees,v_compliancemodeltype compliancemodeltype*/
				,v_conveyance_allowance conveyance_allowance
				,v_medical_allowance medical_allowance
				,p_gratuityopted gratuityopted, v_gratuity gratuity,p_employergratuityopted employergratuityopted,v_employergratuity employergratuity
				,v_salarybonus	as	salarybonus
				,v_commission	as	commission
				,v_transport_allowance	as	transport_allowance
				,v_travelling_allowance	as	travelling_allowance
				,v_leave_encashment	as	leave_encashment
				,v_overtime_allowance	as	overtime_allowance
				,v_notice_pay	as	notice_pay
				,v_hold_salary_non_taxable	as	hold_salary_non_taxable
				,v_children_education_allowance	as	children_education_allowance
				,v_gratuityinhand	as	gratuityinhand,v_pfapplicablecomponents pfapplicablecomponents,
				coalesce(v_reccomplianceflags.edli_adminchargesincludeinctc,'Y') edli_adminchargesincludeinctc
				,v_esiappliedvariables esiappliedcomponents,p_isgroupinsurance isgrouinsurance,
				coalesce(p_employeeinsuranceamount,0) p_employeeinsuranceamount,
	 
				coalesce(p_employerinsuranceamount,0) employerinsuranceamount,
				p_ishourlysetup ishourlysetup,p_charity_contribution charity_contribution,v_charity_contribution_amount charity_contribution_amount
				,coalesce(v_monthlytaxable_bonus,0) monthlytaxable_bonus,coalesce(v_monthlynontaxable_bonus,0) monthlynontaxable_bonus
				,v_vpf vpf
				,v_mealvoucher mealvoucher,v_grossearningcomponents grossearningcomponents,v_salarysetupcriteria salarysetupcriteria,v_grossearningcomponents grossearningcomponents,
				v_salarymasterjson salarymasterjson;
	   
	
											
		return sal;				
-- 		OPEN sal FOR
-- 		SELECT * from tmpsalarycomponent;
-- 		return sal;	
		/*********************/				   
	/*****************************************************************************/

END;
$BODY$;

ALTER FUNCTION public.uspcreatecustomsalarystructure(integer, character varying, integer, character varying, double precision, integer, integer, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, character varying, double precision, double precision, character varying, character varying, character varying)
    OWNER TO payrollingdb;

