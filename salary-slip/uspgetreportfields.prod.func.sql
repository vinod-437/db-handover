-- FUNCTION: public.uspgetreportfields(character varying, bigint, character varying)

-- DROP FUNCTION IF EXISTS public.uspgetreportfields(character varying, bigint, character varying);

CREATE OR REPLACE FUNCTION public.uspgetreportfields(
	p_reportname character varying,
	p_customeraccountid bigint,
	p_fieldtype character varying DEFAULT 'All'::character varying)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
v_rfcresult refcursor;
v_rfcsetupfields refcursor;
v_rec record;
begin
select * from getmastersalarystructure('GetMasterSalaryStructure',p_customeraccountid) into v_rfcsetupfields;

	 if not EXISTS (SELECT * FROM pg_catalog.pg_class c   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    		WHERE  c.relname = 'tmp_reportfields' AND c.relkind = 'r' and n.oid=pg_my_temp_schema()
					  ) then
								create temporary table  tmp_reportfields on commit drop
								as
								select * from reportfields where reportname=p_reportname and isactive='1'
								and fieldtype=coalesce(nullif(p_fieldtype,'All'),fieldtype);	  
		else
			delete from tmp_reportfields;
			insert into tmp_reportfields
			select * from reportfields where reportname=p_reportname and isactive='1'
			and fieldtype=coalesce(nullif(p_fieldtype,'All'),fieldtype);
		end if;

loop
fetch v_rfcsetupfields into v_rec;
exit when v_rec.componentname is null;
update tmp_reportfields set reportcomponentname=v_rec.earningtype
where reportcomponentname=v_rec.componentname;

update tmp_reportfields set reportcomponentname='Rate '||v_rec.earningtype
where reportcomponentname='Rate '||v_rec.componentname;

update tmp_reportfields set reportcomponentname='Arrear '||v_rec.earningtype
where reportcomponentname='Arrear '||v_rec.componentname;

update tmp_reportfields set reportcomponentname='Arrear Rate '||v_rec.earningtype
where reportcomponentname='Arrear Rate '||v_rec.componentname;
end loop;

if p_reportname='Salary Slip' then
	delete from  tmp_reportfields where reportcomponentname ilike '%Rate%';
	--7653    "HSQUARE SPORTS PRIVATE LIMITED As per ticket Updated salary slip template
	update tmp_reportfields set reportcomponentname=replace(reportcomponentname,'ESIC','ESI Employee Contribution @.75%') where p_customeraccountid in(7653);
	update tmp_reportfields set reportcomponentname=replace(reportcomponentname,'Provident Fund','EPF Employee Contribution @12%') where p_customeraccountid in (7653);

end if;
open v_rfcresult for
select reportcolumnname,reportcomponentname,displayorder-1 as displayorder
from tmp_reportfields
order by displayorder;
return v_rfcresult;

end;
$BODY$;

ALTER FUNCTION public.uspgetreportfields(character varying, bigint, character varying)
    OWNER TO payrollingdb;

