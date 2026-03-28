-- FUNCTION: public.uspupdatetaxonpaiddays(bigint, bigint, character varying, integer, integer, numeric, numeric, character varying)

-- DROP FUNCTION IF EXISTS public.uspupdatetaxonpaiddays(bigint, bigint, character varying, integer, integer, numeric, numeric, character varying);

CREATE OR REPLACE FUNCTION public.uspupdatetaxonpaiddays(
	p_emp_code bigint,
	p_createdby bigint,
	p_createdbyip character varying,
	p_month integer,
	p_year integer,
	p_paiddays numeric DEFAULT 0.0,
	p_leavetaken numeric DEFAULT 0.0,
	p_advance_or_current character varying DEFAULT 'Advance'::character varying)
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
	v_rfcadvice refcursor;
	v_empsalaryregister empsalaryregister%rowtype;
	v_recadvice record;
	v_rfcadvice_2 refcursor;
	v_openappointments openappointments%rowtype;
	v_regime varchar(30);
	v_financial_year varchar(30);
	projectioncursors refcursor;
	v_working_minutes numeric:=0;
	v_shift_minutes numeric:=0;
	v_cmsdownloadedwages cmsdownloadedwages%rowtype;
	v_rec record;
	
	v_currentpf numeric(18,2);
	v_currentvpf numeric(18,2);
	v_currentinsurance numeric(18,2);
	v_currentprofessionaltax numeric(18,2);
	v_grossearning numeric(18,2);
	v_vpf numeric(18,2);
	v_ledgeramount numeric(18,2);
	v_currentmealvoucher numeric(18,2); 
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
		
	--Raise Notice 'Step 1';	
if p_month in (1,2,3) then
	v_financial_year:=(p_year-1)::text||'-'||p_year::text;
else
	v_financial_year:=(p_year)::text||'-'||(p_year+1)::text;
end if;
	select * from openappointments where emp_code=p_emp_code into v_openappointments;
	select regime_tye into v_regime from employee_regime where emp_code=p_emp_code and financial_year=v_financial_year and isactive='1';
	v_regime:=coalesce(v_regime,'New');
/**********************change 1.35 starts***************************************************/
	if not exists(select * from paymentadvice where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and advicelockstatus='Locked'  and attendancemode<>'Ledger' and paiddaysstatus='Valid')
	then	
		--Raise Notice 'Step 2';	

				select e.* into v_empsalaryregister from empsalaryregister e inner join openappointments op
						on e.appointment_id=op.emp_id and op.emp_code=p_emp_code and e.isactive='1'
				where op.converted='Y' and op.appointment_status_id=11		
					and (op.dateofrelieveing is null or dateofrelieveing>=v_currentmonthstartdate::date)
					and  v_currentmonthenddate::date between effectivefrom and coalesce(effectiveto,v_currentmonthenddate::date)
					order by e.id desc limit 1;	
			/*		
			if 	(coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' and v_empsalaryregister.salarydays>coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))
			    or (coalesce(v_empsalaryregister.salaryindaysopted,'N')='N' and v_monthdays>=coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))
			     or exists(select * from paymentadvice where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and attendancemode='MPR' and paiddaysstatus='Valid')
			then
*/
	--Raise Notice 'Step 3';	

		select sum(epf) epf,sum(vpf) vpf,sum(insurance) insurance,sum(professionaltax) professionaltax
		from (
				select  epf,vpf,insurance,professionaltax  from tbl_monthlysalary where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and is_rejected='0'
					union all
				select sum(epf) epf,sum(vpf) vpf,sum(insurance) insurance,sum(professionaltax) professionaltax from paymentadvice where emp_code=p_emp_code and mprmonth=p_month and mpryear=p_year and paiddaysstatus='Valid'
			) tmp
		into v_rec;

		v_currentpf:=case when coalesce(v_empsalaryregister.pfcapapplied,'Y')='N' then coalesce(v_empsalaryregister.pfapplicablecomponents,0)*(coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))/(case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' then v_empsalaryregister.salarydays else v_monthdays end)
					else

						case when coalesce(v_empsalaryregister.pfapplicablecomponents,0)*(coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))/(case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' then v_empsalaryregister.salarydays else v_monthdays end) +coalesce(v_rec.epf,0)<1800
							then coalesce(v_empsalaryregister.pfapplicablecomponents,0)*(coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))/(case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' then v_empsalaryregister.salarydays else v_monthdays end)
						else
						greatest((1800-coalesce(v_rec.epf,0)),0)
						end
					end;
					
		v_currentinsurance:=case when v_openappointments.customeraccountid=v_openappointments.customeraccountid then (coalesce(v_empsalaryregister.insuranceamount,0)+coalesce(v_empsalaryregister.familyinsuranceamount,0))-coalesce(v_rec.insurance,0) 
							else
								(coalesce(v_empsalaryregister.insuranceamount,0)+coalesce(v_empsalaryregister.familyinsuranceamount,0))*(coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))/(case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' then v_empsalaryregister.salarydays else v_monthdays end)
							end;

		v_grossearning:=v_empsalaryregister.gross*(coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))/(case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' then v_empsalaryregister.salarydays else v_monthdays end);
		
		
			/**************Change Meal Voucher starts***********************/
	select sum(deduction_amount) 
			into v_currentmealvoucher
	   from public.trn_candidate_otherduction
	   inner join empsalaryregister e on e.id=trn_candidate_otherduction.salaryid
	   where trn_candidate_otherduction.candidate_id=v_openappointments.emp_id
	   	and trn_candidate_otherduction.active='Y'
	   	and deduction_amount>0
	  	and trn_candidate_otherduction.deduction_id=134 --Meal Voucher ID, Must Change for Production
		and e.isactive='1';
	  
	  v_currentmealvoucher:=coalesce(v_currentmealvoucher,0);
	/**************Change Meal Voucher ends*************************/
		/***************************************************************/
		
		select sum(amount) into v_ledgeramount 
		from tbl_employeeledger
		where emp_code=p_emp_code and processmonth=p_month
		and processyear=p_year and isactive='1' and is_taxable='Y'
		and coalesce(isledgerdisbursed,'0'::bit)<>'1'::bit;
		
		v_grossearning:=v_grossearning+coalesce(v_ledgeramount,0);
		/***************************************************************/
	
		with tmpexgrossearning as
			(
			select emp_code,sum(grossearning) grossearning,sum(professionaltax) pt from tbl_monthlysalary
				where emp_code =p_emp_code and
				  (
					  (mprmonth=p_month and mpryear=p_year and p_advance_or_current ='Advance')
					  or
						(to_date(left(hrgeneratedon,11),'dd Mon yyyy')
							between (date_trunc('month', current_date)-interval '1 month')::date
						 		and (date_trunc('month', current_date)-interval '1 day')::date
 							and p_advance_or_current ='Current'
						)
					)
				and is_rejected='0'
				and istaxapplicable='1'
				group by emp_code
			)
			select tbl1.professionaltax into v_currentprofessionaltax
			from (select op.emp_code,e.id,mst_statewiseprofftax.ptamount professionaltax,te.grossearning,mst_statewiseprofftax.lowerlimit,mst_statewiseprofftax.upperlimit,te.pt
				  from  openappointments op 
			inner join empsalaryregister e on e.appointment_id=op.emp_id
				  and op.emp_code=p_emp_code and e.appointment_id=v_openappointments.emp_id
				  inner join vw_mst_statewiseprofftax mst_statewiseprofftax on mst_statewiseprofftax.ptid=e.ptid 
				  and extract ('month' from (current_date-interval '1 month'))=mst_statewiseprofftax.ptmonth 
				  and trim(lower(case when op.gender='M' then 'Male' when op.gender='F' then 'Female' else op.gender end))=trim(lower(mst_statewiseprofftax.ptgender))
				  and mst_statewiseprofftax.isactive='1'
				 left join tmpexgrossearning te on te.emp_code=op.emp_code) tbl1
			where tbl1.professionaltax>0
			and (coalesce(tbl1.grossearning,0)+coalesce(v_grossearning,0)) between tbl1.lowerlimit and tbl1.upperlimit
			and coalesce(tbl1.pt,0)<=0;
	
	
	v_vpf:=coalesce(v_empsalaryregister.vpfemployee,0)+coalesce((select deduction_amount from public.trn_candidate_otherduction
																where trn_candidate_otherduction.candidate_id=v_openappointments.emp_id
																and trn_candidate_otherduction.deduction_id=10
																and trn_candidate_otherduction.salaryid=v_empsalaryregister.id),0);
	--Raise Notice 'Step 4';	
	
		select public.uspupdatetaxforsalary(
						p_empcode =>p_emp_code,
						p_createdby =>p_createdby,
						p_createdbyip =>p_createdbyip,
						p_month =>p_month,
						p_year =>p_year,
						p_currentgrossearning =>v_grossearning,
						p_currentotherdeductions => 0, --v_recadvice.otherdeductions,
						p_currentbasic=>v_empsalaryregister.basic*(coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))/(case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' then v_empsalaryregister.salarydays else v_monthdays end),
						p_currenthra =>v_empsalaryregister.hra*(coalesce(p_paiddays,0)+coalesce(p_leavetaken,0))/(case when coalesce(v_empsalaryregister.salaryindaysopted,'N')='Y' then v_empsalaryregister.salarydays else v_monthdays end),
						p_batchid =>v_cmsdownloadedwages.batch_no,
						p_currentpf =>v_currentpf,
						p_currentvpf =>v_vpf,
						p_currentinsurance =>v_currentinsurance,
						p_currentprofessionaltax =>v_currentprofessionaltax/*,
						p_taxmonth=>p_month, --p_taxmonth,
						p_advance_or_current=>p_advance_or_current*/
						,p_currentmealvoucher=>v_currentmealvoucher
					)into v_rfcadvice_2;  
			--end if;
 	return 1;
end if;
end if;
		return 0;
	end;

$BODY$;

ALTER FUNCTION public.uspupdatetaxonpaiddays(bigint, bigint, character varying, integer, integer, numeric, numeric, character varying)
    OWNER TO payrollingdb;

