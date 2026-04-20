-- FUNCTION: public.uspupdatetaxforsalary(bigint, bigint, character varying, integer, integer, double precision, double precision, double precision, double precision, text, double precision, double precision, double precision, double precision, double precision)

-- DROP FUNCTION IF EXISTS public.uspupdatetaxforsalary(bigint, bigint, character varying, integer, integer, double precision, double precision, double precision, double precision, text, double precision, double precision, double precision, double precision, double precision);

CREATE OR REPLACE FUNCTION public.uspupdatetaxforsalary(
	p_empcode bigint,
	p_createdby bigint,
	p_createdbyip character varying,
	p_month integer,
	p_year integer,
	p_currentgrossearning double precision,
	p_currentotherdeductions double precision,
	p_currentbasic double precision,
	p_currenthra double precision,
	p_batchid text,
	p_currentpf double precision DEFAULT 0.0,
	p_currentvpf double precision DEFAULT 0.0,
	p_currentinsurance double precision DEFAULT 0.0,
	p_currentprofessionaltax double precision DEFAULT 0.0,
	p_currentmealvoucher double precision DEFAULT 0.0)
    RETURNS integer
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare 
v_rfctax refcursor;
v_financialyear varchar(9);
v_regime varchar(10);
v_remainingmonths int;
----------------------------------------
v_totalincome numeric(18,2);
v_totalsavings numeric(18,2);
v_taxableincome numeric(18,2);
v_netpayabletax numeric(18,2);
v_taxdeducted numeric(18,2);
v_balancetax numeric(18,2);
v_taxslab varchar(30);
v_currentmonthtaxdeducted numeric(18,2):=0;
  -----------------------------------------
v_leftflag varchar(1):='N';
v_pfpreviousemployer  numeric(18,2):=0;
v_openappointments openappointments%rowtype;
begin
/*************************************************************************
Version Date			Change								Done_by
1.1		25-Feb-2022		Added for Left Candidates			Shiv Kumar
1.2		25-Apr-2025     Manual TDS Condition				Shiv Kumar
**************************************************************************/
select * into v_openappointments from openappointments where emp_code=p_empcode;

-- STEP 1: Verify early exit condition - If the employee is explicitly exempted from TDS, zero out any existing tax and return
if exists(select * from empsalaryregister where appointment_id=v_openappointments.emp_id and isactive='1' and is_exemptedfromtds='Y')
then
	update empsalaryregister set taxes= 0 where appointment_id=v_openappointments.emp_id and isactive='1' and is_exemptedfromtds='Y';
	return 1;
end if;
--Raise notice 'Enable Status=%',(select tds_enablestatus from tbl_account where id=v_openappointments.customeraccountid);	

v_leftflag:=coalesce(v_openappointments.left_flag,'N');
-- STEP 2: Proceed only if the employer/customer account has TDS processing enabled
if coalesce((select tds_enablestatus from tbl_account where id=v_openappointments.customeraccountid),'Y')='Y' then /*****change 1.1*****/
	------------Calc Financial Year----------------------------- 
	-- STEP 3: Identify the applicable Financial Year bounds based on the processing month
	 if p_month between 4 and 12 then
		v_financialyear:=p_year||'-'||(p_year+1);
	 else
		v_financialyear:=(p_year-1)||'-'||p_year;
	 end if;
	------------Find Regime----------------------------------------
-- STEP 4: Fetch previously deposited PF/taxes from previous employers to ensure accurate tax bracket calculation
select 
coalesce(nullif(pf_apr2024,'')::numeric(18),0)+
coalesce(nullif(pf_may2024,'')::numeric(18),0)+
coalesce(nullif(pf_jun2024,'')::numeric(18),0)+
coalesce(nullif(pf_jul2024,'')::numeric(18),0)+
coalesce(nullif(pf_aug2024,'')::numeric(18),0)
from regenesyspreviousincome rp inner join openappointments op
on rp.employee_code=op.orgempcode
and op.emp_code=p_empcode
and op.customeraccountid=5484
and v_financialyear='2024-2025'
into v_pfpreviousemployer;
		
		-- STEP 5: Identify the employee's opted Tax Regime (Old vs New)
		select regime_tye into v_regime
		from employee_regime
		where emp_code=p_empcode
		and financial_year=v_financialyear
		and isactive='1';	
		if right(v_financialyear,4)::int<=2023 then
			v_regime:=coalesce(v_regime,'Old');		
		else
			v_regime:=coalesce(v_regime,'New');		
		end if;
-------------------Find Tax Amount-------------------------------------------
raise notice 'v_regime=>%', v_regime;
raise notice 'p_currentgrossearning=>%', p_currentgrossearning;
raise notice 'p_currentotherdeductions=>%', p_currentotherdeductions;
raise notice 'p_currentbasic=>%', p_currentbasic;
raise notice 'p_currenthra=>%', p_currenthra;
raise notice 'p_month=>%', p_month;
raise notice 'p_year=>%', p_year;
raise notice 'p_batchid=>%', p_batchid;
raise notice 'coalesce(p_currentpf,0)=>%',  coalesce(p_currentpf,0);
raise notice 'p_currentinsurance=>%', p_currentinsurance;
raise notice 'p_currentvpf=>%',  p_currentvpf;
raise notice 'p_currentprofessionaltax=>%',  p_currentprofessionaltax;
raise notice 'p_currentmealvoucher=>%',  p_currentmealvoucher;

-- STEP 6: Execute core tax calculation engine to resolve full-year tax liability and required deductions
select * from public.Uspcalculatetaxonsalary(p_empcode,v_financialyear,v_regime,
											 p_currentgrossearning,
											 p_currentotherdeductions,
											 p_currentbasic,
											 p_currenthra,
											 p_month,
											 p_year,
											 p_batchid,
											 coalesce(p_currentpf,0)/*+coalesce(v_pfpreviousemployer,0)*/,
											 p_currentvpf,
											 p_currentinsurance,
											 p_currentprofessionaltax,
											 p_currentmealvoucher)
  into v_rfctax;
fetch  v_rfctax 
into  v_totalincome,v_totalsavings,v_taxableincome,v_netpayabletax,v_taxdeducted,v_balancetax,v_taxslab,v_currentmonthtaxdeducted;
Raise Notice 'v_totalincome=%,v_totalsavings=%,v_taxableincome=%,v_netpayabletax=%,v_taxdeducted=%,v_balancetax=%,v_taxslab=%,v_currentmonthtaxdeducted=%',v_totalincome,v_totalsavings,v_taxableincome,v_netpayabletax,v_taxdeducted,v_balancetax,v_taxslab,v_currentmonthtaxdeducted;
------------Find Remaining Months--------------------------------------------------
 -- STEP 7: Determine remaining months in FY to properly amortize the balance tax burden
 if p_month between 4 and 12 then
 	v_remainingmonths:=(12-p_month)+4;
 else
 	v_remainingmonths:=4-p_month;
 end if;
 --Change 1.1 
if v_leftflag='Y' then 
	v_remainingmonths:=1;
end if;
--Change 1.1 ends
----------Update Tax------------------------------------------------------ 
 -- STEP 8: Update amortized monthly tax requirement onto the salary register
 update empsalaryregister
 set taxes=case when coalesce(v_netpayabletax,0)<=0 then 0
							when coalesce(v_netpayabletax,0)>0 and coalesce(v_netpayabletax,0)-coalesce(v_taxdeducted,0)>0 then ( coalesce(v_netpayabletax,0)-(coalesce(v_taxdeducted,0)-coalesce(v_currentmonthtaxdeducted,0)))/v_remainingmonths
							when coalesce(v_netpayabletax,0)>0 and coalesce(v_netpayabletax,0)-coalesce(v_taxdeducted,0)<=0 then greatest( ( coalesce(v_netpayabletax,0)-(coalesce(v_taxdeducted,0)-coalesce(v_currentmonthtaxdeducted,0))),0)/v_remainingmonths
 else greatest(v_balancetax,0)/v_remainingmonths end,taxupdatedby=p_createdby,taxupdatedon=current_timestamp,taxupdatedbyip=p_createdbyip
 where appointment_id=(select emp_id from openappointments
					  where emp_code=p_empcode
					  and appointment_status_id<>13
					  and converted='Y')
	and isactive='1';

else
	-- STEP 9: Fallback - if TDS disabled on the account, zero out auto-calculated taxes on the salary register
	update empsalaryregister set taxupdatedon=current_timestamp,taxes=case when empsalaryregister.tdsmode='Manual' then taxes else 0 end where appointment_id=v_openappointments.emp_id;
end if;		
return 1;
 --exception when others then
 --return -1;
end;
$BODY$;

ALTER FUNCTION public.uspupdatetaxforsalary(bigint, bigint, character varying, integer, integer, double precision, double precision, double precision, double precision, text, double precision, double precision, double precision, double precision, double precision)
    OWNER TO payrollingdb;

