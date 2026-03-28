-- FUNCTION: public.uspccalcgrossfromctc_withoutconveyance(integer, integer, character varying, integer, character varying, double precision, double precision, character varying, character varying, integer, integer, character varying, integer, character varying, character varying, double precision, double precision, character varying, double precision, character varying, double precision, character varying, double precision, character varying, character varying, character varying, character varying, character varying, character varying, character varying, double precision, double precision, bigint, character varying, double precision)

-- DROP FUNCTION IF EXISTS public.uspccalcgrossfromctc_withoutconveyance(integer, integer, character varying, integer, character varying, double precision, double precision, character varying, character varying, integer, integer, character varying, integer, character varying, character varying, double precision, double precision, character varying, double precision, character varying, double precision, character varying, double precision, character varying, character varying, character varying, character varying, character varying, character varying, character varying, double precision, double precision, bigint, character varying, double precision);

CREATE OR REPLACE FUNCTION public.uspccalcgrossfromctc_withoutconveyance(
	p_appointment_id integer,
	p_salarycategoryid integer,
	p_minwagesstatename character varying,
	p_minwagescategoryid integer,
	p_locationtype character varying,
	p_basic double precision,
	p_monthlyofferedpackage double precision,
	p_financialyear character varying,
	p_optedinsurance character varying,
	p_familymemberscovered integer,
	p_basicoption integer DEFAULT 5,
	p_ewfopted character varying DEFAULT 'N'::character varying,
	p_salarydays integer DEFAULT 30,
	p_salarydaysopted character varying DEFAULT 'N'::character varying,
	p_bonusopted character varying DEFAULT 'N'::character varying,
	p_bonusamount double precision DEFAULT 0.0,
	p_insuranceamt double precision DEFAULT 0.0,
	p_familymemberopted character varying DEFAULT 'N'::character varying,
	p_perperson_family_amt double precision DEFAULT 0.0,
	p_is_special_category character varying DEFAULT 'N'::character varying,
	p_ct2 double precision DEFAULT 0.0,
	p_pfcapapplied character varying DEFAULT 'Y'::character varying,
	p_taxes double precision DEFAULT 0.0,
	p_effectivefrom character varying DEFAULT NULL::character varying,
	p_pt_applicable character varying DEFAULT 'N'::character varying,
	p_lwf_applicable character varying DEFAULT 'N'::character varying,
	p_pf_opted character varying DEFAULT 'N'::character varying,
	p_esiopted character varying DEFAULT 'N'::character varying,
	p_gratuityopted character varying DEFAULT 'N'::character varying,
	p_employergratuityopted character varying DEFAULT 'N'::character varying,
	p_conveyanceamount double precision DEFAULT 0.0,
	p_pfapplicablecomponents double precision DEFAULT 0.0,
	p_customeraccountid bigint DEFAULT '-9999'::integer,
	p_isgroupinsurance character varying DEFAULT 'N'::character varying,
	p_employerinsuranceamount double precision DEFAULT 0.0)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$

/*************************************************************************
Version 	Date			Change								Done_by
1.0							Initial Version				
1.1			04-Mar-2024		Change effectivedate				Shiv Kumar			
1.2			05-Mar-2024		Remove Allowance Loop to optimize	Shiv Kumar
2.0			09-Apr-2024		Add LWF and PT deduction
                            functionality on the user choice	Parveen Kumar		
2.1			29-Apr-2024		As per mail dated 29-Apr-2024		Shiv Kumar
							Custom Min wages Required for
							 some employer
2.2			03-May-2024		Add Professional tax				Shiv Kumar
2.3			20-Jun-2024		ESI disable Condition				Shiv Kumar
2.4			18-Sep-2024		Admin EDLI Charges Yes/No			Shiv Kumar
2.6			01-Jul-2025		Meal Voucher						Shiv Kumar
2.7			23-Jul-2025		Deduct Annually, Half yearly,		Shiv Kumar
							 quarterly LWF from gross
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
	v_salarysetupcriteria text:='Monthly';
	v_salaryhours double precision:=8.00;
	v_is_valid int:=0;
	v_compliancemodeltype varchar(10);
	v_tbl_account tbl_account%rowtype;
	v_professionaltax text;
	v_gender varchar(20);
	v_employergratuity numeric(18,5):=0.0;
	v_esimessage text:='';
	v_reccomplianceflags record;
	v_pfapplicablecomponents double precision DEFAULT 0.0;
	v_mealvoucher numeric(18,5):=0.0;
BEGIN
	/**************Change 2.6 starts***********************/
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
	/**************Change 2.6 ends*************************/
	v_pfapplicablecomponents:=coalesce(nullif(p_pfapplicablecomponents,0),p_basic);
	v_isesiambit:='N';
	v_gratuityopted:=p_gratuityopted;
	
			v_employergratuity=0;
			if p_employergratuityopted='Y' then
				v_employergratuity:=uspcalcgratuity(v_customeraccountid,p_basic::numeric) ;--(p_basic*4.81/100)::numeric(18,5);
			end if;
			
	SELECT wagesctgname, minimumwagessalary FROM mst_minimumwagescategory WHERE wcid=p_minwagescategoryid INTO v_minwagescategoryname, v_minimumwagessalary;
	SELECT statecode FROM mst_state WHERE lower(trim(statename_inenglish))=lower(trim(p_minwagesstatename)) INTO v_statecode;
	v_lwfstatecode:=CASE WHEN COALESCE(p_lwf_applicable, 'N')='Y' THEN v_statecode ELSE 0 END;
	v_ptid:=CASE WHEN COALESCE(p_pt_applicable, 'N')='Y' THEN v_statecode ELSE 0 END;

	SELECT medicalinsuranceopted,/* gratuityopted,*/ performancebonus_opted, npsopted, govt_bonus_opted, ewfamount, customeraccountid, emp_code, TO_CHAR(dateofjoining, 'dd/mm/yyyy'), appointment_status_id, uannumber,gender
	INTO v_medicalinsuranceopted,/* v_gratuityopted,*/ v_performancebonus_opted, v_npsopted, v_govt_bonus_opted, v_ews, v_customeraccountid, v_emp_code, v_doj, v_appointment_status_id, v_uannumber,v_gender
	FROM openappointments 
	WHERE emp_id=p_appointment_id;
	v_pfopted:=p_pf_opted;
	v_esiopted:=p_esiopted;
/*************************change 1.7 starts*************************************/
select 
		coalesce(employerpfincludeinctc,'Y') employerpfincludeinctc,
		coalesce(edli_adminchargesincludeinctc,'Y') edli_adminchargesincludeinctc,
		coalesce(pfonbasiconly,'Y') pfonbasiconly,
		coalesce(pfcapapplied,'Y') pfcapapplied
from mst_employer_compliance_settings
where customer_account_id=p_customeraccountid 
and is_active='1'
into v_reccomplianceflags;
/*************************change 1.7 end*************************************/
/*****************************Change 1.0 starts here****************************************/

if v_esiopted='Y' and p_esiopted='N' and COALESCE(v_isesiambit,'N')='N' then
v_esiopted='N';
v_esimessage:='Employee is in ESI Rancge';
end if;
/*****************************Change 1.1 ends here *********************************************/
v_effectivedate:=greatest(to_date(v_doj, 'dd/mm/yyyy'), date_trunc('month', to_date(p_effectivefrom,'dd/mm/yyyy'))::date); --Added Change 1.1

	IF v_appointment_status_id = 1 THEN
		v_operation:='Generate';
	ELSIF (v_appointment_status_id = 11 OR v_appointment_status_id = 14) THEN
		v_operation:='Restructure';
	END IF;

	v_effective_from:=TO_CHAR(v_effectivedate, 'dd/mm/yyyy');
	SELECT uspcalesiexceptionalcase(p_appointment_id, nullif(v_effective_from, '')) INTO v_isesiambit;

	select * FROM tbl_account WHERE id=v_customeraccountid INTO v_tbl_account;
	v_compliancemodeltype:=v_tbl_account.compliancemodeltype;
	--SELECT number_of_employees,compliancemodeltype FROM tbl_account WHERE id=v_customeraccountid INTO v_number_of_employees,v_compliancemodeltype;
	v_number_of_employees:=COALESCE(v_tbl_account.number_of_employees,0);
	
if v_tbl_account.minwagestatus='Y' then	 --change 2.1 starts
	IF (v_number_of_employees>20 and v_compliancemodeltype='PCM')AND COALESCE(v_pfopted, 'N')='N' THEN
		IF p_monthlyofferedpackage::INT < 17440 THEN
			OPEN sal FOR
				SELECT v_is_valid status, 'Monthly Offered Package (MOP) can not be less than ₹17440.' msg;
			RETURN sal;
		END IF;
		IF p_basic::INT <= 15000 THEN
			OPEN sal FOR
				SELECT v_is_valid status, 'Basic salary must be greater than ₹15000.' msg;
			RETURN sal;
		END IF;
	END IF;
end if;--change 2.1 ends
	IF COALESCE(p_lwf_applicable,'N')='Y' THEN
		SELECT employeelwfrate/(case when frequency='Annually' then 12 when frequency='Half Yearly' then 6 when frequency='Quartrly' then 3  when frequency='Monthly' then 1 end),
		employerlwfrate/(case when frequency='Annually' then 12 when frequency='Half Yearly' then 6 when frequency='Quartrly' then 3  when frequency='Monthly' then 1  end),
		deductionmonths, frequency
		INTO v_employeelwf, v_employerlwf, v_lwfdeductionmonths, v_frequency
		FROM statewiselwfrate
		WHERE statecode=v_lwfstatecode and v_lwfstatecode<>7 AND isactive='1';
	END IF;
	v_employerlwf:=COALESCE(v_employerlwf,0);
	v_employeelwf:=COALESCE(v_employeelwf,0);

	IF v_frequency<>'Monthly' THEN
		--v_employerlwf:=0;
		v_employeelwf:=0;
	END IF;

	IF p_ewfopted='Y' AND COALESCE(v_ews,0)=0 THEN
		SELECT head_value INTO v_ews FROM mst_salaryrate WHERE head_name='EWS' AND active='Y' AND Financial_Year=p_FinancialYear LIMIT 1;
	END IF;

	SELECT sum(deduction_amount) INTO v_variableamount FROM trn_candidate_otherduction WHERE candidate_id=p_appointment_id AND active='Y' AND COALESCE(includedinctc,'N')='Y' AND COALESCE(isvariable,'N')='Y' AND deduction_frequency IN ('Quarterly','Half Yearly','Annually') and salaryid is null and deduction_id<>134; --Meal Voucher ID
	SELECT sum(deduction_amount) INTO v_otherdeductions FROM trn_candidate_otherduction WHERE candidate_id=p_appointment_id AND active='Y' AND COALESCE(includedinctc,'N')='Y' AND COALESCE(isvariable,'N')='N' AND deduction_frequency IN ('Quarterly','Half Yearly','Annually') and salaryid is null and deduction_id<>134; --Meal Voucher ID
	SELECT sum(deduction_amount) INTO v_esiapplieddeductions FROM trn_candidate_otherduction WHERE candidate_id=p_appointment_id AND active='Y' AND trn_candidate_otherduction.deduction_id IN (5,6) and deduction_id<>134; --Meal Voucher ID
	SELECT sum(deduction_amount) INTO v_monthlyvaraible_excluded FROM trn_candidate_otherduction WHERE candidate_id=p_appointment_id AND active='Y' AND COALESCE(includedinctc,'N')='N' AND deduction_frequency IN ('Monthly') AND trn_candidate_otherduction.deduction_id not IN (5,6) and deduction_id<>134; --Meal Voucher ID
	SELECT SalCtgName INTO v_salarycategoryname FROM MstSalaryCategory WHERE scid=p_salarycategoryid;
--raise notice 'v_variableamount=%',v_variableamount;
	IF p_salarycategoryid=1 OR p_salarycategoryid=2 THEN
		v_minwagescategoryid:=p_minwagescategoryid;

		IF p_monthlyofferedpackage>=25000 THEN
			v_monthlyofferedpackage:=p_monthlyofferedpackage-coalesce(v_variableamount,0)-coalesce(p_employerinsuranceamount,0)-v_mealvoucher;
			v_basic:=round(p_basic::numeric(18,5));
			SELECT round((head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_basic END)::numeric(18,5)) INTO v_hra FROM mst_salaryrate WHERE head_name='HRA' AND salary_category_id=p_salarycategoryid AND active='Y' AND Financial_Year=p_FinancialYear AND LocationType=p_Locationtype LIMIT 1;
			IF COALESCE(v_hra,0)=0 THEN
				IF COALESCE(p_locationtype,'Metro')='Metro' THEN
					v_hra:=round((v_basic*.5)::numeric(18,5));
				ELSE
					v_hra:=round((v_basic*.4)::numeric(18,5));
				END IF;
			END IF;

			v_EPF_Employee:=0;
			v_EPF_Employer:=0;
			IF v_pfopted='Y' OR (v_basic<=15000 AND v_number_of_employees>20 and v_compliancemodeltype='PCM') THEN
				
				IF coalesce(v_reccomplianceflags.edli_adminchargesincludeinctc,'Y')='Y' then
					if p_pfcapapplied='Y' THEN
						if p_salarydays = '1' then
							v_EPF_Employer:=(least(v_pfapplicablecomponents*.13,1950)::numeric(18,5));					
						else
							v_EPF_Employer:=round(least(v_pfapplicablecomponents*.13,1950)::numeric(18,5));
						end if;	
					ELSE
						if p_salarydays = '1' then
                    	v_EPF_Employer:=((v_pfapplicablecomponents*.13)::numeric(18,5));
						else
                    	v_EPF_Employer:=round((v_pfapplicablecomponents*.13)::numeric(18,5));
						end if;
					END IF;
				ELSE
					if p_pfcapapplied='Y' THEN
						if p_salarydays = '1' then
                    		v_EPF_Employer:=(least(v_pfapplicablecomponents*.12,1800)::numeric(18,5));
						else
						v_EPF_Employer:=round(least(v_pfapplicablecomponents*.12,1800)::numeric(18,5));
						end if;
					ELSE
						if p_salarydays = '1' then
                    		v_EPF_Employer:=((v_pfapplicablecomponents*.12)::numeric(18,5));
						else
	                    	v_EPF_Employer:=round((v_pfapplicablecomponents*.12)::numeric(18,5));
						end if;					
					END IF;
				end if;

				IF p_pfcapapplied='Y' THEN
						v_EPF_Employee:=round(least(v_pfapplicablecomponents*.12,1800)::numeric(18,5));
				ELSE
						v_EPF_Employee:=round((v_pfapplicablecomponents*.12)::numeric(18,5));
				END IF;
            ELSE
                v_EPF_Employee:=0.0;
                v_EPF_Employer:=0.0;
			END IF;

			v_ESI_Employer:=0;
			v_ESI_Employee:=0;
			v_NPS_EMPLOYER:=0;
			v_NPS_EMPLOYEE:=0;
			IF v_npsopted='Y' AND v_basic>15000 THEN
				SELECT round((head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_basic END)::numeric(18,5)) INTO v_NPS_EMPLOYER FROM mst_salaryrate WHERE head_name='NPS_EMPLOYER' AND salary_category_id=p_salarycategoryid AND active='Y' AND Financial_Year=p_FinancialYear LIMIT 1;
				SELECT round((head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_basic END)::numeric(18,5)) INTO v_NPS_EMPLOYEE FROM mst_salaryrate WHERE head_name='NPS_EMPLOYEE' AND salary_category_id=p_salarycategoryid AND active='Y' AND Financial_Year=p_FinancialYear LIMIT 1;
			END IF;

			v_govt_bonus_amt:=0;
			IF COALESCE(v_govt_bonus_opted,'N')='Y' THEN
				SELECT head_value INTO v_govt_bonus_rate FROM mst_salaryrate WHERE head_name='Government_Bonus' AND active='Y' AND financial_year=p_FinancialYear;
				v_govt_bonus_amt:=v_basic*COALESCE(v_govt_bonus_rate,0.0833);
			END IF;

			IF COALESCE(v_isesiambit,'N')='Y' THEN
				v_gross2=(COALESCE(v_monthlyofferedpackage,0)-COALESCE(v_EPF_Employer,0)-coalesce(v_employerlwf,0)-COALESCE(v_govt_bonus_amt,0)-coalesce(v_employergratuity,0))/1.0325+coalesce(p_conveyanceamount,0)*.0325;
				IF v_gross2>v_monthlyofferedpackage THEN
					v_hra:=v_monthlyofferedpackage-(COALESCE(v_basic,0)+COALESCE(v_EPF_Employer,0)+coalesce(v_employerlwf,0)+COALESCE(v_govt_bonus_amt,0)+COALESCE((v_gross2-coalesce(p_conveyanceamount,0))*.0325,0)+coalesce(v_employergratuity,0));
					v_allowances:=0;
				ELSE
					IF v_gross2-(COALESCE(v_basic,0)+COALESCE(v_hra,0))<=100 THEN
						v_hra:=v_hra+v_gross2-(COALESCE(v_basic,0)+COALESCE(v_hra,0));
						v_allowances:=0;
					ELSE
						v_allowances:=v_gross2-(COALESCE(v_basic,0)+COALESCE(v_hra,0));
					END IF;
				END IF;
			ELSE
				v_gross2=COALESCE(v_basic,0)+COALESCE(v_hra,0)+COALESCE(v_EPF_Employer,0)+COALESCE(v_govt_bonus_amt,0)+coalesce(v_employerlwf,0)+coalesce(v_employergratuity,0);

				IF v_gross2>v_monthlyofferedpackage THEN
					v_hra:=v_monthlyofferedpackage-(COALESCE(v_basic,0)+COALESCE(v_EPF_Employer,0)+coalesce(v_employerlwf,0)+COALESCE(v_govt_bonus_amt,0)+coalesce(v_employergratuity,0));
					v_allowances:=0;
				ELSE
					IF v_monthlyofferedpackage-v_gross2<=100 THEN
						v_hra:=v_hra+(v_monthlyofferedpackage-v_gross2);
						v_allowances:=0;
					ELSE
						v_allowances:=v_monthlyofferedpackage-v_gross2;
					END IF;
				END IF;
			END IF;

			v_Difference:=0;
			IF p_basicoption=2 THEN
				v_basic:=round(p_basic);
				v_hra:=0;
				v_allowances:=0;
			END IF;
			v_gross:=v_basic+v_hra+v_allowances;
			v_ESI_Employer:=0.0;
			v_ESI_Employee:=0.0;
			IF COALESCE(v_isesiambit,'N')='Y' THEN
				SELECT head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE (v_gross+v_govt_bonus_amt) END INTO v_ESI_Employer FROM mst_salaryrate WHERE head_name='ESI_Employer' AND salary_category_id=p_salarycategoryid AND active='Y' AND Financial_Year=p_FinancialYear LIMIT 1;
				IF COALESCE(v_ESI_Employer,0)=0 THEN
					v_ESI_Employer:=(v_gross-coalesce(p_conveyanceamount,0))*0.0325;
				END IF;

				SELECT head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE (v_gross+v_govt_bonus_amt) END INTO v_ESI_Employee FROM mst_salaryrate WHERE head_name='ESI_Employee' AND salary_category_id=p_salarycategoryid AND active='Y' AND Financial_Year=p_FinancialYear LIMIT 1;
				IF COALESCE(v_ESI_Employee,0)=0 THEN
					v_ESI_Employee:=(v_gross-coalesce(p_conveyanceamount,0))*.0075;
				END IF;
			END IF;

			--IF p_optedinsurance='Y' OR upper(p_optedinsurance)='E' THEN
				v_insuranceamount:=COALESCE(p_insuranceamt,0);
			--ELSE
			--	v_insuranceamount:=0;
			--END IF;

			IF p_familymemberopted='Y' AND (p_optedinsurance='Y' OR p_optedinsurance='E') THEN
				v_familyinsuranceamount:=COALESCE(p_familymemberscovered,0)*COALESCE(p_perperson_family_amt,0.0);
				v_familymemberscovered:=p_familymemberscovered;
			ELSE
				v_familyinsuranceamount:=0;
				v_familymemberscovered:=0;
			END IF;

			IF COALESCE(p_ewfopted,'N')='N' THEN
				v_ews:=0;
			END IF;

			v_gratuity=0;
			IF v_gratuityopted='Y' THEN
				v_gratuity:=uspcalcgratuity(v_customeraccountid,v_basic::numeric) ; --(v_basic*4.81/100)::numeric(18,5);
			END IF;
			v_salary_in_hand:=v_gross-COALESCE(v_EPF_Employee,0)-COALESCE(v_NPS_EMPLOYEE,0)-COALESCE(v_ews,0)-COALESCE(v_gratuity,0)+COALESCE(v_govt_bonus_amt,0);
			v_ctc:=v_gross+COALESCE(v_EPF_Employer,0)+COALESCE(v_NPS_EMPLOYER,0)+COALESCE(v_govt_bonus_amt,0)+coalesce(v_employergratuity,0);
			--IF p_optedinsurance='Y' THEN
				v_salary_in_hand=v_salary_in_hand-COALESCE(v_insuranceamount,0)-COALESCE(v_familyinsuranceamount,0);
			--END IF;

			IF p_bonusopted='Y' THEN
				v_salary_in_hand:=v_salary_in_hand-COALESCE(p_bonusamount,0);
			END IF;

			v_salary_in_hand:=v_salary_in_hand-COALESCE(v_otherdeductions,0);
			v_salary_in_hand:=v_salary_in_hand+COALESCE(v_monthlyvaraible_excluded,0);
			v_CTC:=v_CTC+COALESCE(v_variableamount,0);
			v_salary_in_hand:=v_salary_in_hand-COALESCE(v_employeelwf,0); 
			v_CTC:=v_CTC+COALESCE(v_employerlwf,0);
			v_salary_in_hand:=v_salary_in_hand-COALESCE(v_ESI_Employee,0);
			v_ctc:=v_ctc+COALESCE(v_ESI_Employer,0)+coalesce(p_employerinsuranceamount,0);
			IF ROUND((COALESCE(v_CTC, 0) - COALESCE(v_govt_bonus_amt,0)-coalesce(v_employergratuity,0))::numeric,2) > ROUND(p_monthlyofferedpackage::numeric,2) THEN
				OPEN sal FOR
					SELECT 0 status, 'With Basic Salary ₹'||p_basic||', CTC (₹'||v_CTC||') must not be greater than Monthly Offered Package (₹. '||p_monthlyofferedpackage||').' msg;
				RETURN sal;
			END IF;
/************************Change 2.2 starts*************************************************/
if COALESCE(p_pt_applicable, 'N')='Y' then
	select array_to_json(array_agg(row_to_json(X))) FROM (
		  select lowerlimit,upperlimit,
		case when ptmonth=1 then 'Jan' when ptmonth=2 then 'Feb' when ptmonth=3 then 'Mar' when ptmonth=4 then 'Apr' when ptmonth=5 then 'May' when ptmonth=6 then 'Jun' when ptmonth=7 then 'Jul' when ptmonth=8 then 'Aug' when ptmonth=9 then 'Sep' when ptmonth=10 then 'Oct' when ptmonth=11 then 'Nov' when ptmonth=12 then 'Dec' end as DeductionMonth
		,ptamount
		  from  vw_mst_statewiseprofftax mst_statewiseprofftax 
		  where mst_statewiseprofftax.ptid=v_ptid
		  and lower(case when v_gender='M' then 'Male' when v_gender='F' then 'Female' else v_gender end)=lower(mst_statewiseprofftax.ptgender)
		  and mst_statewiseprofftax.isactive='1'
		and (coalesce(v_gross,0)+COALESCE(v_govt_bonus_amt,0)+COALESCE(v_esiapplieddeductions,0)) between mst_statewiseprofftax.lowerlimit and mst_statewiseprofftax.upperlimit
		) as X
		into v_professionaltax;	 
end if;			
		v_professionaltax:=coalesce(v_professionaltax,'');
/************************Change 2.2 ends*************************************************/
			OPEN sal FOR
				SELECT 
				p_appointment_Id personalinfoid, v_salarycategoryname salarycategoryname, v_monthlyofferedpackage monthlyofferedpackage, 
				v_basic basic, v_hra as HRA, v_allowances as allowances, v_gross gross, v_EPF_Employer epf_employer, v_EPF_Employee epf_employee,
				v_ESI_Employer esi_employer, v_ESI_Employee esi_employee, v_salary_in_hand salary_in_hand, v_CTC ctc, v_isesiambit esiexceptionalcase,
				0 employersocialsecurity, 0 employeesocialsecurity, 'Basic' salarygenerationbase,
				p_optedinsurance optedinsurance, p_familymemberscovered familymemberscovered, v_insuranceamount insuranceamount, 
				v_familyinsuranceamount familyinsuranceamount, v_ews ews, v_gratuity gratuity, COALESCE(v_NPS_EMPLOYER, 0) NPS_EMPLOYER,
				v_NPS_EMPLOYEE NPS_EMPLOYEE, p_salarydays salarydays, p_bonusamount bonus, v_govt_bonus_opted govt_bonus_opted,
				v_govt_bonus_amt govt_bonus_amt, COALESCE(v_otherdeductions, 0) otherdeductions, p_is_special_category is_special_category,
				p_ct2 ctc2, p_pfcapapplied pfcapapplied, p_taxes taxes, p_lwf_applicable islwfstate, v_lwfstatecode lwfstatecode, v_employeelwf employeelwf,
				v_employerlwf employerlwf, v_lwfdeductionmonths lwfdeductionmonths, v_ptid ptid, p_locationtype location_type, 
				p_financialyear financial_year, p_basicoption basicoption, p_salarydaysopted salarydaysopted, v_operation operation, 
				p_minwagesstatename minwagestatename, p_minwagescategoryid minwagescategoryid, v_minwagescategoryname minwagescategoryname, 
				v_minimumwagessalary minimumwagessalary, v_uannumber uannumber, 'Pass' calcresult, 0 suggestivesalary, '' salmessage, 
				0 leavetemplateid, '' leavetemplatetext, 0 dailywagerate, 0 dailyesiccontribution, 0 dailyepfcontribution, 0 dailysalary_in_hand, 0 dailyctc,
				v_timecriteria timecriteria, v_salarysetupcriteria salarysetupcriteria, v_salaryhours salaryhours, v_effective_from effectivedate,
				1 status, 'Salary calculated successfully.' msg,v_number_of_employees number_of_employees,v_compliancemodeltype compliancemodeltype
				,v_professionaltax professionaltax,v_esimessage esimessage
				,coalesce(p_isgroupinsurance,'N') isgroupinsurance,coalesce(p_employerinsuranceamount,0) employerinsuranceamount;
			RETURN sal;
		ELSE
		
			v_monthlyofferedpackage:=p_monthlyofferedpackage-coalesce(p_conveyanceamount,0)-coalesce(v_variableamount,0)-coalesce(p_employerinsuranceamount,0)-v_mealvoucher;
			v_basic:=p_basic;
			IF p_basicoption=1 OR p_basicoption=5 THEN
				v_govt_bonus_amt:=0;
				IF COALESCE(v_govt_bonus_opted,'N')='Y' THEN
					SELECT head_value INTO v_govt_bonus_rate FROM mst_salaryrate WHERE head_name='Government_Bonus' AND active='Y' AND financial_year=p_FinancialYear;
					v_govt_bonus_amt:=v_basic*COALESCE(v_govt_bonus_rate,0.0833);
				END IF;

				SELECT round((head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_basic END)::numeric(18,5)) INTO v_hra FROM mst_salaryrate WHERE head_name='HRA' AND salary_category_id=p_salarycategoryid AND active='Y' AND Financial_Year=p_FinancialYear AND LocationType=p_Locationtype LIMIT 1;

				IF COALESCE(v_hra,0)=0 THEN
					IF COALESCE(p_locationtype,'Metro')='Metro' THEN
						v_hra:=round((v_basic*.5)::numeric(18,5));
					ELSE
						v_hra:=round((v_basic*.4)::numeric(18,5));
					END IF;
				END IF;
				if v_basic+v_hra>v_monthlyofferedpackage then
                    v_hra:=v_monthlyofferedpackage-v_basic;
                end if;
				v_allowances:=0;
				v_gross:=v_basic+v_hra+v_allowances;
			END IF;
--raise notice 'v_gross=%',v_gross;
            IF v_pfopted='Y' OR (v_basic<=15000 AND v_number_of_employees>20 and v_compliancemodeltype='PCM') THEN
				IF coalesce(v_reccomplianceflags.edli_adminchargesincludeinctc,'Y')='Y' then
					if p_pfcapapplied='Y' THEN
						if p_salarydays = '1' then
							v_EPF_Employer:=(least(v_pfapplicablecomponents*.13,1950)::numeric(18,5));					
						else
							v_EPF_Employer:=round(least(v_pfapplicablecomponents*.13,1950)::numeric(18,5));
						end if;	
					ELSE
						if p_salarydays = '1' then
                    		v_EPF_Employer:=((v_pfapplicablecomponents*.13)::numeric(18,5));
						else
                    		v_EPF_Employer:=round((v_pfapplicablecomponents*.13)::numeric(18,5));
						end if;
					END IF;
				ELSE
					if p_pfcapapplied='Y' THEN
						if p_salarydays = '1' then
                    		v_EPF_Employer:=(least(v_pfapplicablecomponents*.12,1800)::numeric(18,5));
						else
                    		v_EPF_Employer:=round(least(v_pfapplicablecomponents*.12,1800)::numeric(18,5));
						end if;
					ELSE
						if p_salarydays = '1' then
                    		v_EPF_Employer:=((v_pfapplicablecomponents*.12)::numeric(18,5));
						else
	                    	v_EPF_Employer:=round((v_pfapplicablecomponents*.12)::numeric(18,5));
						end if;					
					END IF;
				end if;

				IF p_pfcapapplied='Y' THEN
						v_EPF_Employee:=round(least(v_pfapplicablecomponents*.12,1800)::numeric(18,5));
				ELSE
						v_EPF_Employee:=round((v_pfapplicablecomponents*.12)::numeric(18,5));
				END IF;
            ELSE
                v_EPF_Employee:=0.0;
                v_EPF_Employer:=0.0;
            END IF;

			v_EPF_Employee:=COALESCE(v_EPF_Employee,0);
			v_EPF_Employer:=COALESCE(v_EPF_Employer,0);
			v_ESI_Employer:=0;
			v_ESI_Employee:=0;
--IF ((v_esiopted='Y' or p_pt_applicable='Y' or p_lwf_applicable='Y') AND COALESCE(v_pfopted, 'N')='N') THEN
IF (((v_esiopted='Y' or p_pt_applicable='Y' or p_lwf_applicable='Y' or COALESCE(v_pfopted, 'N')='Y') AND v_gross<=21000) OR COALESCE(v_isesiambit,'N')='Y') and v_esiopted='Y' THEN
v_esiopted='Y';
end if;
if v_esiopted='Y' and p_esiopted='N' and COALESCE(v_isesiambit,'N')='N' then
v_esiopted='N';
v_esimessage:='Employee is in ESI Rancge';
end if;

/***************************Change 2.5 starts**********************************************/
				v_gross2=(COALESCE(v_monthlyofferedpackage,0)-COALESCE(v_EPF_Employer,0)-coalesce(v_employerlwf,0)-COALESCE(v_govt_bonus_amt,0)-coalesce(v_employergratuity,0))/1.0325;
				--Raise Notice 'v_gross2=%',v_gross2;
				IF v_gross2>v_monthlyofferedpackage THEN
					v_hra:=v_monthlyofferedpackage-(COALESCE(v_basic,0)+COALESCE(v_EPF_Employer,0)+coalesce(v_employerlwf,0)+COALESCE(v_govt_bonus_amt,0)+COALESCE((v_gross2-coalesce(p_conveyanceamount,0))*.0325,0)+coalesce(v_employergratuity,0));
					v_allowances:=0;
				ELSE
					IF v_gross2-(COALESCE(v_basic,0)+COALESCE(v_hra,0))<=100 THEN
						v_hra:=v_hra+v_gross2-(COALESCE(v_basic,0)+COALESCE(v_hra,0));
						v_allowances:=0;
					ELSE
						v_allowances:=v_gross2-(COALESCE(v_basic,0)+COALESCE(v_hra,0));
					END IF;
				END IF;
			v_gross:=(COALESCE(v_basic,0)+COALESCE(v_hra,0)+coalesce(v_allowances,0));

	/************************Change 2.5 ends*******************************************/			
			IF v_esiopted='Y' THEN
				SELECT head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_gross END INTO v_ESI_Employer FROM mst_salaryrate WHERE head_name='ESI_Employer' AND salary_category_id=p_salarycategoryid AND active='Y' /*AND Financial_Year=p_FinancialYear*/ LIMIT 1;
				SELECT head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_gross END INTO v_ESI_Employee FROM mst_salaryrate WHERE head_name='ESI_Employee' AND salary_category_id=p_salarycategoryid AND active='Y' /*AND Financial_Year=p_FinancialYear*/ LIMIT 1;
				--Raise notice 'v_ESI_Employer=%,v_ESI_Employee=%',v_ESI_Employer,v_ESI_Employee;
				IF v_govt_bonus_amt>0 THEN
					v_ESI_Employer:=v_ESI_Employer+v_govt_bonus_amt*0.0325;
					v_ESI_Employee:=v_ESI_Employee+v_govt_bonus_amt*.0075;
				END IF;

				v_ESI_Employer:=v_ESI_Employer+COALESCE(v_esiapplieddeductions,0)*0.0325;
				v_ESI_Employee:=v_ESI_Employee+COALESCE(v_esiapplieddeductions,0)*0.0075;

				IF COALESCE(v_ESI_Employer,0)=0 THEN
					v_ESI_Employer:=(v_gross)*0.0325;
					IF v_govt_bonus_amt>0 THEN
						v_ESI_Employer:=v_ESI_Employer+v_govt_bonus_amt*0.0325;
					END IF;
					v_ESI_Employer:=v_ESI_Employer+COALESCE(v_esiapplieddeductions,0)*0.0325;
				END IF;

				IF COALESCE(v_ESI_Employee,0)=0 THEN
					v_ESI_Employee:=(v_gross)*.0075;
					IF v_govt_bonus_amt>0 THEN
						v_ESI_Employee:=v_ESI_Employee+v_govt_bonus_amt*.0075;
					END IF;
					v_ESI_Employee:=v_ESI_Employee+COALESCE(v_esiapplieddeductions,0)*0.0075;
				END IF;
			END IF;
		--raise notice 'Step 1:ESI_Employer=%,v_gross=%',v_ESI_Employer,v_gross;	
-- 				              if (v_number_of_employees<=10 or v_compliancemodeltype='PM') and v_esiopted='N' then
-- 							  	v_ESI_Employer:=0;
-- 								v_ESI_Employee:=0;
-- 							  end if;
			v_NPS_EMPLOYER:=0;
			v_NPS_EMPLOYEE:=0;

			--IF p_optedinsurance='Y' OR upper(p_optedinsurance)='E' THEN
				v_insuranceamount:=COALESCE(p_insuranceamt,0);
			--ELSE
			--	v_insuranceamount:=0;
			--END IF;

			IF p_familymemberopted='Y' AND (p_optedinsurance='Y' OR p_optedinsurance='E') THEN
				v_familyinsuranceamount:=COALESCE(p_familymemberscovered,0)*COALESCE(p_perperson_family_amt,0.0);
				v_familymemberscovered:=p_familymemberscovered;
			ELSE
				v_familyinsuranceamount:=0;
				v_familymemberscovered:=0;
			END IF;

			IF COALESCE(p_ewfopted,'N')='N' THEN
				v_ews:=0;
			END IF;

			v_gratuity=0;
			IF v_gratuityopted='Y' THEN
				v_gratuity:=uspcalcgratuity(v_customeraccountid,v_basic::numeric) ; --(v_basic*4.81/100)::numeric(18,5);
			END IF;
			v_CTC:=COALESCE(v_gross,0)+COALESCE(v_EPF_Employer,0)+COALESCE(v_ESI_Employer,0)+COALESCE(v_NPS_EMPLOYER,0)+COALESCE(v_govt_bonus_amt,0)+coalesce(v_employerlwf,0);

			IF COALESCE(v_govt_bonus_opted,'N')='Y' AND p_minwagescategoryid IN (1,2,3,4) AND p_salarydaysopted='Y' THEN
				SELECT head_value INTO v_govt_bonus_rate FROM mst_salaryrate WHERE head_name='Government_Bonus' AND active='Y' AND financial_year=p_FinancialYear;
				v_govt_bonus_amt:=v_basic*COALESCE(v_govt_bonus_rate,0.0833);
				v_CTC:=v_CTC+v_govt_bonus_amt;
			END IF;

			IF (p_basicoption=1 OR p_basicoption=5) AND not(v_esiopted='Y' AND v_gross<=21000) AND COALESCE(v_isesiambit,'N')='N' AND v_CTC<v_monthlyofferedpackage THEN
				IF v_monthlyofferedpackage-v_CTC<=100 THEN
					v_hra:=v_hra+(v_monthlyofferedpackage-v_CTC);
					v_allowances:=0;
				ELSE
					v_allowances:=v_monthlyofferedpackage-v_CTC;
				END IF;

				v_gross:=v_basic+v_hra+v_allowances;
				v_CTC:=COALESCE(v_gross,0)+COALESCE(v_EPF_Employer,0)+COALESCE(v_ESI_Employer,0)+COALESCE(v_NPS_EMPLOYER,0)+COALESCE(v_govt_bonus_amt,0)+coalesce(v_employerlwf,0)+coalesce(v_employergratuity,0);
			END IF;
			
		--raise notice 'Step 2:ESI_Employer=%,v_gross=%',v_ESI_Employer,v_gross;	
			-- RAISE NOTICE 'INITIAL CTC:%, Basic:%, HRA: %, Allowances:%, GROSS:%, EPF Employer:%, ESI Employer: %, CTC: %', v_CTC,v_basic,v_hra,v_allowances,v_gross,v_EPF_Employer,v_ESI_Employer,v_CTC;
			/*********change 1.2 starts here*****/
			--Raise notice 'v_CTC=%,v_monthlyofferedpackage=%,v_allowances=%',v_CTC,v_monthlyofferedpackage,v_allowances;
			IF (v_CTC-coalesce(v_variableamount,0)) < (v_monthlyofferedpackage) THEN
				if COALESCE(v_ESI_Employer,0)>0 then
					v_allowances:=v_allowances+(((v_monthlyofferedpackage)-(v_CTC))/1.0325);
				else
					v_allowances:=v_allowances+(((v_monthlyofferedpackage)-(v_CTC)));
				end if;
			elsif (v_CTC-coalesce(v_variableamount,0)) > (p_monthlyofferedpackage) THEN
				if COALESCE(v_ESI_Employer,0)>0 then
					v_allowances:=v_allowances-((((v_CTC)-v_monthlyofferedpackage))/1.0325);
				else
					v_allowances:=v_allowances-((((v_CTC)-v_monthlyofferedpackage)));
				end if;
			end if;
if v_allowances<0 then
  if v_allowances*1<=v_hra then
  	v_hra=v_hra+v_allowances;
	v_allowances:=0;
  end if;

end if;
					v_gross:=v_basic+v_hra+v_allowances;
					v_ESI_Employer:=0;
					v_ESI_Employee:=0;

		--raise notice 'Step 3:ESI_Employer=%,v_gross=%',v_ESI_Employer,v_gross;	
					IF v_esiopted='Y' OR COALESCE(v_isesiambit,'N') = 'Y' THEN
						SELECT head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_gross END INTO v_ESI_Employer FROM mst_salaryrate WHERE head_name='ESI_Employer' AND salary_category_id=p_salarycategoryid AND active='Y' /*AND Financial_Year=p_FinancialYear*/ LIMIT 1;
						SELECT head_value*CASE WHEN head_calc_type ='Val' THEN 1 ELSE v_gross END INTO v_ESI_Employee FROM mst_salaryrate WHERE head_name='ESI_Employee' AND salary_category_id=p_salarycategoryid AND active='Y' /*AND Financial_Year=p_FinancialYear*/ LIMIT 1;

						IF v_govt_bonus_amt>0 THEN
							v_ESI_Employer:=v_ESI_Employer+v_govt_bonus_amt*0.0325;
							v_ESI_Employee:=v_ESI_Employee+v_govt_bonus_amt*.0075;
						END IF;

						v_ESI_Employer:=v_ESI_Employer+COALESCE(v_esiapplieddeductions,0)*0.0325;
						IF COALESCE(v_ESI_Employer,0)=0 THEN
							v_ESI_Employer:=v_gross*0.0325;
							IF v_govt_bonus_amt>0 THEN
								v_ESI_Employer:=v_ESI_Employer+v_govt_bonus_amt*0.0325;
							END IF;
							v_ESI_Employer:=v_ESI_Employer+COALESCE(v_esiapplieddeductions,0)*0.0325;
						END IF;

						v_ESI_Employee:=v_ESI_Employee+COALESCE(v_esiapplieddeductions,0)*0.0075;
						IF COALESCE(v_ESI_Employee,0)=0 THEN
							v_ESI_Employee:=v_gross*.0075;
							IF v_govt_bonus_amt>0 THEN
								v_ESI_Employee:=v_ESI_Employee+v_govt_bonus_amt*.0075;
							END IF;
							v_ESI_Employee:=v_ESI_Employee+COALESCE(v_esiapplieddeductions,0)*0.0075;
						END IF;
					END IF;

				              if (v_number_of_employees<=10 or v_compliancemodeltype='PM') and v_esiopted='N' then
							  	v_ESI_Employer:=0;
								v_ESI_Employee:=0;
							  end if;
					v_CTC:=COALESCE(v_gross,0)+COALESCE(v_EPF_Employer,0)+COALESCE(v_ESI_Employer,0)+COALESCE(v_NPS_EMPLOYER,0)+COALESCE(v_govt_bonus_amt,0);
/*********below part commented for change 1.2 starts here*****/
					-- RAISE NOTICE 'ADJUST CTC:%, Basic:%, HRA: %, Allowances:%, GROSS:%, EPF Employer:%, ESI Employer: %, CTC: %', v_CTC,v_basic,v_hra,v_allowances,v_gross,v_EPF_Employer,v_ESI_Employer,v_CTC;
-- 					IF ROUND(v_CTC) <= ROUND(p_monthlyofferedpackage) AND (p_basicoption=1 OR p_basicoption=3) THEN
-- 						EXIT;
-- 					END IF;
-- 					IF ROUND(v_CTC) >= ROUND(p_monthlyofferedpackage) AND p_basicoption=5 THEN
-- 						EXIT;
-- 					END IF;
-- 				END LOOP;
-- 			END IF;
/*********below part commented for change 1.2 ends here*****/
			v_CTC := v_CTC + COALESCE(v_esiapplieddeductions, 0) + COALESCE(v_variableamount, 0) + COALESCE(v_employerlwf, 0)+coalesce(v_employergratuity,0);
			/*********change 1.2 ends here*****/
			v_salary_in_hand:=v_gross-COALESCE(v_ESI_Employee,0)-COALESCE(v_EPF_Employee,0)-COALESCE(v_NPS_EMPLOYEE,0)-COALESCE(v_ews,0)-COALESCE(v_gratuity,0);
			--IF p_optedinsurance='Y' THEN
				v_salary_in_hand=v_salary_in_hand-COALESCE(v_insuranceamount,0)-COALESCE(v_familyinsuranceamount,0);
			--END IF;
			IF p_bonusopted='Y' THEN
				v_salary_in_hand:=v_salary_in_hand-COALESCE(p_bonusamount,0);
			END IF;
			v_salary_in_hand:=v_salary_in_hand-COALESCE(v_otherdeductions,0);
			v_salary_in_hand:=v_salary_in_hand+COALESCE(v_monthlyvaraible_excluded,0);
			IF v_govt_bonus_amt>0 THEN
				v_salary_in_hand:=v_salary_in_hand+COALESCE(v_govt_bonus_amt,0);
			END IF;

			v_salary_in_hand := v_salary_in_hand + COALESCE(v_esiapplieddeductions,0) - COALESCE(v_employeelwf, 0);

			-- IF ROUND((COALESCE(v_CTC, 0) - COALESCE(v_govt_bonus_amt,0)-coalesce(v_employergratuity,0))::numeric,2) > ROUND(p_monthlyofferedpackage::numeric,2) THEN
			-- 	OPEN sal FOR
			-- 		SELECT 0 status, 'With Basic Salary ₹'||p_basic||', CTC (₹'||v_CTC||') should not be greater than Monthly Offered Package (₹'||p_monthlyofferedpackage||').' msg;
			-- 	RETURN sal;
			-- END IF;
/************************Change 2.2 starts*************************************************/
if COALESCE(p_pt_applicable, 'N')='Y' then
	select array_to_json(array_agg(row_to_json(X))) FROM (
		  select lowerlimit,upperlimit,ptmonth ,ptamount
		  from  vw_mst_statewiseprofftax mst_statewiseprofftax 
		  where mst_statewiseprofftax.ptid=v_ptid
		  and lower(case when v_gender='M' then 'Male' when v_gender='F' then 'Female' else v_gender end)=lower(mst_statewiseprofftax.ptgender)
		  and mst_statewiseprofftax.isactive='1'
		and (coalesce(v_gross,0)+COALESCE(v_govt_bonus_amt,0)+COALESCE(v_esiapplieddeductions,0)) between mst_statewiseprofftax.lowerlimit and mst_statewiseprofftax.upperlimit
		) as X
		into v_professionaltax;	 
end if;			
		v_professionaltax:=coalesce(v_professionaltax,'');
/************************Change 2.2 ends*************************************************/
if v_gross>21000 then
v_gross=v_gross+COALESCE(v_ESI_Employer,0);
v_ESI_Employee:=0;
v_ESI_Employer:=0;
if v_allowances>0 then
	v_allowances:=v_allowances+COALESCE(v_ESI_Employer,0);
elsif v_hra>0 then
	v_hra:=v_hra+COALESCE(v_ESI_Employer,0); 	
end if;	
end if;
v_CTC := v_CTC +coalesce(p_conveyanceamount,0)+coalesce(p_employerinsuranceamount,0);
v_gross := v_gross +coalesce(p_conveyanceamount,0);
			OPEN sal FOR
				SELECT 
				p_appointment_Id personalinfoid, v_salarycategoryname salarycategoryname, p_monthlyofferedpackage monthlyofferedpackage,
				v_basic basic, v_hra as HRA, v_allowances as allowances, v_gross gross, v_EPF_Employer epf_employer, v_EPF_Employee epf_employee,
				v_ESI_Employer esi_employer, v_ESI_Employee esi_employee, v_salary_in_hand salary_in_hand, v_CTC ctc, v_isesiambit esiexceptionalcase,
				0 employersocialsecurity, 0 employeesocialsecurity, 'Basic' salarygenerationbase,
				p_optedinsurance optedinsurance, p_familymemberscovered familymemberscovered, v_insuranceamount insuranceamount, 
				v_familyinsuranceamount familyinsuranceamount, v_ews ews, v_gratuity gratuity, COALESCE(v_NPS_EMPLOYER, 0) NPS_EMPLOYER,
				v_NPS_EMPLOYEE NPS_EMPLOYEE, p_salarydays salarydays, p_bonusamount bonus, v_govt_bonus_opted govt_bonus_opted,
				v_govt_bonus_amt govt_bonus_amt, COALESCE(v_otherdeductions, 0) otherdeductions, p_is_special_category is_special_category,
				p_ct2 ctc2, p_pfcapapplied pfcapapplied, p_taxes taxes, p_lwf_applicable islwfstate, v_lwfstatecode lwfstatecode, v_employeelwf employeelwf,
				v_employerlwf employerlwf, v_lwfdeductionmonths lwfdeductionmonths, v_ptid ptid, p_locationtype location_type, 
				p_financialyear financial_year, p_basicoption basicoption, p_salarydaysopted salarydaysopted, v_operation operation, 
				p_minwagesstatename minwagestatename, p_minwagescategoryid minwagescategoryid, v_minwagescategoryname minwagescategoryname, 
				v_minimumwagessalary minimumwagessalary, v_uannumber uannumber, 'Pass' calcresult, 0 suggestivesalary, '' salmessage,
				0 leavetemplateid, '' leavetemplatetext, 0 dailywagerate, 0 dailyesiccontribution, 0 dailyepfcontribution, 0 dailysalary_in_hand, 0 dailyctc,
				v_timecriteria timecriteria, v_salarysetupcriteria salarysetupcriteria, v_salaryhours salaryhours, v_effective_from effectivedate,
				1 status, 'Salary calculated successfully.' msg,v_number_of_employees number_of_employees,v_compliancemodeltype compliancemodeltype
				,v_professionaltax professionaltax,v_esimessage esimessage
				,coalesce(p_isgroupinsurance,'N') isgroupinsurance,coalesce(p_employerinsuranceamount,0) employerinsuranceamount;
			RETURN sal;
		END IF;
	END IF;
END;
$BODY$;

ALTER FUNCTION public.uspccalcgrossfromctc_withoutconveyance(integer, integer, character varying, integer, character varying, double precision, double precision, character varying, character varying, integer, integer, character varying, integer, character varying, character varying, double precision, double precision, character varying, double precision, character varying, double precision, character varying, double precision, character varying, character varying, character varying, character varying, character varying, character varying, character varying, double precision, double precision, bigint, character varying, double precision)
    OWNER TO payrollingdb;

