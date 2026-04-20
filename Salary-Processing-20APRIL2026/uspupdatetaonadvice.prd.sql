-- FUNCTION: public.uspupdatetaonadvice(bigint, integer, integer, integer, bigint, bigint, character varying, character varying, numeric, integer, text)

-- DROP FUNCTION IF EXISTS public.uspupdatetaonadvice(bigint, integer, integer, integer, bigint, bigint, character varying, character varying, numeric, integer, text);

CREATE OR REPLACE FUNCTION public.uspupdatetaonadvice(
	p_customeraccountid bigint,
	p_month integer,
	p_year integer,
	p_geofenceid integer DEFAULT 0,
	p_emp_code bigint DEFAULT '-9999'::integer,
	p_createdby bigint DEFAULT '-9999'::integer,
	p_createdbyip character varying DEFAULT ''::character varying,
	p_salmode character varying DEFAULT 'Actual'::character varying,
	p_paiddays numeric DEFAULT 0.0,
	p_taxmonth integer DEFAULT 0,
	p_advance_or_current text DEFAULT 'Current'::text)
    RETURNS integer
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
v_rfc refcursor;
v_rfcadvice refcursor;
v_recadvice record;
v_rfcadvice_2 refcursor;
v_cnt int;
begin
/*************************************************************************
Version Date			Change								Done_by
1.0		10-May-2024     Initial Version						Shiv Kumar
1.1		04-Jun-2024     TDS Condition					Shiv Kumar
*************************************************************************/
if coalesce((select tds_enablestatus from tbl_account where id=p_customeraccountid),'Y')='Y' then /*****change 1.1*****/
	/*************Change 1.2 starts*********************/
		select 	uspwagesfromattendance_pregenerate(
					p_action =>'GenerateWages_pregenerate',
					p_emp_code =>p_emp_code,
					p_createdby =>p_customeraccountid,
					p_createdbyip =>'::1',
					p_month =>p_month,
					p_year =>p_year,
					p_salmode=>p_salmode,
					p_paiddays=>p_paiddays)
		into v_rfcadvice;
	if not v_rfcadvice is null then
	fetch v_rfcadvice into v_recadvice;
	--		raise notice 'v_recadvice.grossearning=% v_recadvice.paiddays=%',v_recadvice.grossearning,v_recadvice.paiddays;	

	--if v_recadvice.paiddays>0 then
--Raise Notice 'p_currentgrossearning =>%',v_recadvice.grossearning;		
	select public.uspupdatetaxforsalary(
		p_empcode =>p_emp_code,
		p_createdby =>p_createdby,
		p_createdbyip =>p_createdbyip,
		p_month =>p_month,
		p_year =>p_year,
		p_currentgrossearning =>v_recadvice.grossearning,
		p_currentotherdeductions =>v_recadvice.otherdeductions,
		p_currentbasic=>v_recadvice.basic,
		p_currenthra =>v_recadvice.hra,
		p_batchid =>v_recadvice.batch_no,
		p_currentpf =>v_recadvice.epf,
		p_currentvpf =>v_recadvice.vpf,
		p_currentinsurance =>v_recadvice.insurance,
		p_currentprofessionaltax =>v_recadvice.professionaltax
		,p_currentmealvoucher=>coalesce(v_recadvice.mealvoucher,0)
	)into v_rfcadvice_2;
	--end if;
	end if;
else
	update empsalaryregister set taxes=case when empsalaryregister.tdsmode='Manual' then taxes else 0 end ,taxupdatedon=current_timestamp where appointment_id=(select emp_id from openappointments where emp_code=p_emp_code);
end if;	
return 1;
--exception when others then
--return -1;
end;
$BODY$;

ALTER FUNCTION public.uspupdatetaonadvice(bigint, integer, integer, integer, bigint, bigint, character varying, character varying, numeric, integer, text)
    OWNER TO payrollingdb;

