-- FUNCTION: public.getmastersalarystructure(text, bigint)

-- DROP FUNCTION IF EXISTS public.getmastersalarystructure(text, bigint);

CREATE OR REPLACE FUNCTION public.getmastersalarystructure(
	p_action text,
	p_customeraccountid bigint)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_rfc refcursor;
	v_mastersalarysetup text;
	v_mastersalaryjson json;
BEGIN
    IF p_action = 'GetMasterSalaryStructure' THEN
	
	
	 select salary_head_text from mst_tp_business_setups where tp_account_id= p_customeraccountid::bigint 
     and row_status='1' into v_mastersalarysetup;
	if v_mastersalarysetup is null then
        OPEN v_rfc FOR
            SELECT
                id,
                componentname,
                earningtype,
                calculationtype,
                calculationpercent,
                calculationbasis,
                epfapplicable,
                esiapplicable,
                isactive,
                displayorder,
				includedingross,
				gratuityapplicable
            FROM
                mastersalarystructure
			where isactive='Y'	
			order by displayorder;

        RETURN v_rfc;
	else
	 if not EXISTS (SELECT * FROM pg_catalog.pg_class c   JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    		WHERE  c.relname = 'tmp_mastersalarystructure' AND c.relkind = 'r' and n.oid=pg_my_temp_schema()
					  ) then
				
		CREATE temporary TABLE tmp_mastersalarystructure
			(
				componentname character varying(100),
				earningtype character varying(100),
				calculationtype character varying(100),
				calculationpercent numeric,
				calculationbasis character varying(40),
				epfapplicable character varying(1),
				esiapplicable character varying(1),
				isactive character varying(1),
				displayorder integer,
				includedingross varchar(1),
				gratuityapplicable varchar(1),
				formula_sign varchar(1),
				formula_value text,
				custom_formula_basis text
			)on COMMIT DROP;	  
		else
			delete from tmp_mastersalarystructure;
		end if;
			v_mastersalaryjson:=(v_mastersalarysetup::json)->1;
			if exists (select * from (select * from json_each_text(v_mastersalaryjson)) tmp1 where key='salary_component') then
	
				insert into tmp_mastersalarystructure(
											componentname,
											earningtype,
											calculationtype,
											calculationpercent,
											calculationbasis,
											epfapplicable,
											esiapplicable,
											isactive,
											/*displayorder*/
											includedingross,
											gratuityapplicable,
											formula_sign ,
											formula_value,
											custom_formula_basis
					)
				select salary_component as componentname,
					salary_component as earningtype,
					percentage_fixed as calculationtype,
					percentage_ctc as calculationpercent,
					case when upper(salary_component)='BASIC SALARY' THEN 'CTC' when upper(salary_component)='HRA' 
					and p_customeraccountid::bigint in(5567,3088)  then 'CTC' when upper(salary_component)='HRA' then 'Basic' else null end as calculationbasis,
					case when upper(salary_component)='BASIC SALARY' THEN 'Y' else coalesce(epfapplicable,'N') end as  epfapplicable,
					is_taxable as  esiapplicable,
					'Y' as isactive,
					includedingross,
					case when upper(salary_component)='BASIC SALARY' THEN 'Y'  else coalesce(gratuityapplicable,'N') end as gratuityapplicable,
					formula_sign ,
					formula_value,
					custom_formula_basis
					
				from jsonb_populate_recordset(null::record,v_mastersalarysetup::jsonb)
				as(
					salary_component	varchar(100),
					percentage_ctc		numeric(18,2),
					percentage_fixed	varchar(30),
					is_taxable			varchar(1),
					epfapplicable		varchar(1),
					includedingross 	varchar(1),
					gratuityapplicable	varchar(1),
					formula_sign varchar(1),
					formula_value text,
					custom_formula_basis text
					);		
				--update tmp_mastersalarystructure set displayorder=row_number()over();
			else
				insert into tmp_mastersalarystructure(
											componentname,
											earningtype,
											calculationtype,
											calculationpercent,
											calculationbasis,
											epfapplicable,
											esiapplicable,
											isactive,
											/*displayorder*/
											includedingross,
											gratuityapplicable,
											formula_sign,
											formula_value,
											custom_formula_basis
					)
				
					select componentname,
											earningtype,
											calculationtype,
											calculationpercent,
											nullif(calculationbasis,''),
											epfapplicable,
											esiapplicable,
											isactive,
											/*displayorder*/
											includedingross,
											case when upper(componentname)='BASIC SALARY' THEN 'Y'  else coalesce(gratuityapplicable,'N') end as gratuityapplicable,
											formula_sign,
											formula_value,
											custom_formula_basis
					from jsonb_populate_recordset(null::record,v_mastersalarysetup::jsonb)
				as(
						componentname character varying(100),
						earningtype character varying(100),
						calculationtype character varying(100),
						calculationpercent numeric,
						calculationbasis character varying(40),
						epfapplicable character varying(1),
						esiapplicable character varying(1),
						isactive character varying(1),
						displayorder integer,
						includedingross varchar(1),
						gratuityapplicable	varchar(1),
						formula_sign varchar(1),
						formula_value text,
						custom_formula_basis text
			   );
			   
			end if;
		OPEN v_rfc FOR
		select mastersalarystructure.id,
		        coalesce(tmp_mastersalarystructure.componentname,mastersalarystructure.componentname) componentname,
                coalesce(tmp_mastersalarystructure.earningtype,mastersalarystructure.earningtype) earningtype,
                coalesce(tmp_mastersalarystructure.calculationtype,mastersalarystructure.calculationtype) calculationtype,
                coalesce(tmp_mastersalarystructure.calculationpercent,mastersalarystructure.calculationpercent) calculationpercent,
                coalesce(tmp_mastersalarystructure.calculationbasis,mastersalarystructure.calculationbasis) calculationbasis,
                coalesce(tmp_mastersalarystructure.epfapplicable,mastersalarystructure.epfapplicable) epfapplicable,
                coalesce(tmp_mastersalarystructure.esiapplicable,mastersalarystructure.esiapplicable) esiapplicable,
                coalesce(tmp_mastersalarystructure.isactive,mastersalarystructure.isactive) isactive,
                coalesce(tmp_mastersalarystructure.displayorder,mastersalarystructure.displayorder) displayorder,
				coalesce(nullif(tmp_mastersalarystructure.includedingross,''),'Y') as includedingross,
				coalesce(tmp_mastersalarystructure.gratuityapplicable,mastersalarystructure.gratuityapplicable) as gratuityapplicable,
				tmp_mastersalarystructure.formula_sign,
				tmp_mastersalarystructure.formula_value,
				tmp_mastersalarystructure.custom_formula_basis

		FROM	(select * from mastersalarystructure where coalesce(mastersalarystructure.isactive,'N')='Y') mastersalarystructure
						full join tmp_mastersalarystructure
		on upper(mastersalarystructure.componentname)=upper(tmp_mastersalarystructure.componentname)
		--where coalesce(mastersalarystructure.isactive,'N')='Y'
		order by coalesce(tmp_mastersalarystructure.displayorder,mastersalarystructure.displayorder);

			RETURN v_rfc;
		end if;
    ELSE
        RAISE EXCEPTION 'Invalid action: %', p_action;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$BODY$;

ALTER FUNCTION public.getmastersalarystructure(text, bigint)
    OWNER TO payrollingdb;

