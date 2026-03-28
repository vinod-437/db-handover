-- FUNCTION: public.uspcalesiexceptionalcase(integer, character varying)

-- DROP FUNCTION IF EXISTS public.uspcalesiexceptionalcase(integer, character varying);

CREATE OR REPLACE FUNCTION public.uspcalesiexceptionalcase(
	p_appointment_id integer,
	p_effectivefrom character varying DEFAULT NULL::character varying)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
	v_emp_code bigint;
	v_oldgross numeric(18,2); 
	v_oldesi numeric(18,2);
	v_oldeffectivefrom date;
	v_esiapplicabletilldate date;
	v_neweffectivefrom date;
	v_appointment_status_id int;
	v_isesiexceptionalcase varchar(1);
	v_oldeffectiveyear int;
	v_oldeffectivemonth int;
	
	v_neweffectiveyear int;
	v_neweffectivemonth int;
	v_oldisesiexceptionalcase varchar(1);
begin
/****************************************************************************************
Version 	dated 			changed_by 		Description
1.0 				 		Shiv Kumar 		Initial Version
1.1 		08-Nov-2023		Shiv Kumar 		Change ESI Ambit Logic after 15th of APril or Oct month(Mail Salary Complaint from NCRPB 08-Oct-2023))
******************************************************************************************/					   
v_isesiexceptionalcase:='N';
if p_effectivefrom is null then
return 'N';
end if;

select appointment_status_id,emp_code
	into v_appointment_status_id,v_emp_code
from openappointments
	where emp_id=p_appointment_id
	and isactive='1';
if v_emp_code is null then
	return 'N';
end if;

update tbl_esiexceptionalcases set  active='0',modified_on=current_timestamp where emp_code=v_emp_code and active='1';
/**********************Change 1.1 starts********************************************************/
if 	 (to_date(p_effectivefrom,'dd/mm/yyyy') between to_date('01/04/'||extract('year' from current_date),'dd/mm/yyyy') and to_date('30/04/'||extract('year' from current_date),'dd/mm/yyyy')
     and current_date between to_date('01/04/'||extract('year' from current_date),'dd/mm/yyyy') and (to_date('01/04/'||extract('year' from current_date),'dd/mm/yyyy')+interval '1 month 14 days')::date
	  )
 or  (to_date(p_effectivefrom,'dd/mm/yyyy') between to_date('01/10/'||extract('year' from current_date),'dd/mm/yyyy') and to_date('31/10/'||extract('year' from current_date),'dd/mm/yyyy') 
	  and current_date between to_date('01/10/'||extract('year' from current_date),'dd/mm/yyyy') and (to_date('01/10/'||extract('year' from current_date),'dd/mm/yyyy')+interval '1 month 14 days')::date
	  ) 
or (not exists(select * from tbl_monthlysalary where emp_code=v_emp_code and is_rejected='0' and employeeesirate>0)	  
   and
	not exists(select * from tbl_monthly_liability_salary where emp_code=v_emp_code and is_rejected='0' and employeeesirate>0)	
   )	  
	  then
	return 'N';
end if;
/**********************Change 1.1 ends********************************************************/
	
select gross,employeeesirate,effectivefrom,isesiexceptionalcase
	into v_oldgross,v_oldesi,v_oldeffectivefrom,v_oldisesiexceptionalcase
from empsalaryregister
	where appointment_id=p_appointment_id 
    --and isactive='1'
	and id in (select salaryid from tbl_monthlysalary where emp_code=(select emp_code from openappointments where emp_id=p_appointment_Id) and is_rejected='0')
	order by id desc limit 1;
/************Below Line added 11-Jan-2022****************/	
v_oldeffectivefrom:=greatest(DATE_TRUNC('MONTH', current_date - INTERVAL '2 MONTH' - INTERVAL '1 DAY')::date,v_oldeffectivefrom);
/************Line added 11-Jan-2022 ends****************/
raise notice 'oldeffectivefrom: % ', v_oldeffectivefrom;	
/*****No ESI Exceptional case if Not Restructure case or old ESI is 0*****/
if v_appointment_status_id <>14 or (coalesce(v_oldesi,0.0)<=0.0 and coalesce(v_oldisesiexceptionalcase,'N')='N') then
	v_isesiexceptionalcase:='N';
	return v_isesiexceptionalcase;
end if;

/******Restrucre Employee block starts here******************/
v_neweffectivefrom:=to_date(p_effectivefrom,'dd/mm/yyyy');

select extract('month' from v_oldeffectivefrom),extract('year' from v_oldeffectivefrom)
into v_oldeffectivemonth,v_oldeffectiveyear;

select extract('month' from v_neweffectivefrom),extract('year' from v_neweffectivefrom)
into v_neweffectivemonth,v_neweffectiveyear;
/*************If Old effective date is bwtween October and March***********************/
if v_oldeffectivemonth in (10,11,12,1,2,3) then
      if v_oldeffectivemonth in (10,11,12) then
			if v_neweffectivefrom<to_date('01/04/'||(v_oldeffectiveyear+1)::text,'dd/mm/yyyy') 
			and (
				exists(select * from tbl_monthlysalary where emp_code=v_emp_code and is_rejected='0'
			 		and (((mprmonth in (10,11,12) and mpryear = v_oldeffectiveyear) or ((mprmonth in (1,2,3) and mpryear = v_oldeffectiveyear+1))))
						 and employeeesirate>0)
			or exists(select * from tbl_monthly_liability_salary where emp_code=v_emp_code and is_rejected='0'
			 and ((mprmonth in (10,11,12) and mpryear = v_oldeffectiveyear) or ((mprmonth in (1,2,3) and mpryear = v_oldeffectiveyear+1)))
					  and employeeesirate>0)
			 )then 
				v_isesiexceptionalcase:='Y';
				v_esiapplicabletilldate:=to_date('31/03/'||(v_oldeffectiveyear+1)::text,'dd/mm/yyyy');
			end if;
	  end if;
	   if v_oldeffectivemonth in (1,2,3) then
			if v_neweffectivefrom<to_date('01/04/'||(v_oldeffectiveyear)::text,'dd/mm/yyyy') 
			and (
				exists(select * from tbl_monthlysalary where emp_code=v_emp_code and is_rejected='0'
			 and ((mprmonth in (10,11,12) and mpryear = v_oldeffectiveyear-1) or ((mprmonth in (1,2,3) and mpryear = v_oldeffectiveyear)))
					and employeeesirate>0)
				or  exists(select * from tbl_monthly_liability_salary where emp_code=v_emp_code and is_rejected='0'
			 and ((mprmonth in (10,11,12) and mpryear = v_oldeffectiveyear-1) or ((mprmonth in (1,2,3) and mpryear = v_oldeffectiveyear)))
			  and employeeesirate>0)
				 )then
				v_isesiexceptionalcase:='Y';
				v_esiapplicabletilldate:=to_date('31/03/'||(v_oldeffectiveyear)::text,'dd/mm/yyyy');
			end if;
	  end if;
end if;
/*************If Old effective date is bwtween April and September***********************/
if v_oldeffectivemonth in (4,5,6,7,8,9) then
		if v_neweffectivefrom<to_date('01/10/'||(v_oldeffectiveyear)::text,'dd/mm/yyyy') 
		and (exists(select * from tbl_monthlysalary where emp_code=v_emp_code and is_rejected='0'
			 and (mprmonth in (4,5,6,7,8,9) and mpryear = v_oldeffectiveyear)
			  and employeeesirate>0)
		or exists(select * from tbl_monthly_liability_salary where emp_code=v_emp_code and is_rejected='0'
			 and (mprmonth in (4,5,6,7,8,9) and mpryear = v_oldeffectiveyear)
			 and employeeesirate>0)
			 )then
			v_isesiexceptionalcase:='Y';
			v_esiapplicabletilldate:=to_date('30/09/'||(v_oldeffectiveyear)::text,'dd/mm/yyyy');
		end if;
end if;

 if v_isesiexceptionalcase='Y' then
INSERT INTO public.tbl_esiexceptionalcases(
	 emp_code, emp_id, oldesi, oldeffectivefrom, neweffectivefrom, esiapplicabletilldate, created_on, active)
	VALUES (v_emp_code, p_appointment_id, v_oldesi, v_oldeffectivefrom, v_neweffectivefrom, v_esiapplicabletilldate,current_timestamp, '1');
end if;
return v_isesiexceptionalcase;

end;
$BODY$;

ALTER FUNCTION public.uspcalesiexceptionalcase(integer, character varying)
    OWNER TO payrollingdb;

