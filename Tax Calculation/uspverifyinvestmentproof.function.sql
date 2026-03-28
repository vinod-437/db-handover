-- FUNCTION: public.uspverifyinvestmentproof(bigint, text, integer, integer, text, double precision, text, bigint, character varying, character varying, character varying, text)

-- DROP FUNCTION IF EXISTS public.uspverifyinvestmentproof(bigint, text, integer, integer, text, double precision, text, bigint, character varying, character varying, character varying, text);

CREATE OR REPLACE FUNCTION public.uspverifyinvestmentproof(
	p_empcode bigint,
	p_financialyear text,
	p_headid integer,
	p_investmentid integer,
	p_approvalstatus text,
	p_receipt_amount double precision,
	p_action text,
	p_updatedby bigint,
	p_updatedbyip character varying,
	p_receiptno character varying,
	p_remarks character varying DEFAULT NULL::character varying,
	p_customeraccountid text DEFAULT '-9999'::text)
    RETURNS integer
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
/***********************************************************************
Version		Date	 		Change By			Comemnt	
1.0			30-Nov-2021		Shiv Kumar			Initial Version
1.1			21-Jan-2022		Shiv Kumar			Change for Multiple Document Accept for CH6 and 80C
*************************************************************************/
DECLARE
	v_monthlytenure int;
	v_rentstartyear int;
	v_rentendyear int;
	v_rentmonth int;
	v_rec record;
	v_rentstartmonth int;
	v_rentendmonth int;
	v_totalmonths int;
	v_totalamount numeric(18,2);
	v_comments varchar(500);
	v_joiningdate date;

BEGIN
if not exists (select * from openappointments where emp_code=p_empcode and customeraccountid=p_customeraccountid::bigint) then
	return 0;
end if;	
if p_action='VerifyDocument' then
	/*******For Chapter VI and 80C***************************/
   if p_headid=1 or p_headid=2  or p_headid=10 then 
   /*******Update Document Approval Status***************************/
			   update public.trn_investment_proof
			   set  approval_status=p_approvalstatus,
					   approvedby=p_updatedby,
					   approvedon=current_timestamp,
					   approvedbyip=p_updatedbyip,
					   remarks=p_remarks
					   where emp_code=p_empcode
					   and headid=p_headid
					   and investment_id=p_investmentid
					   and financial_year=p_financialyear
					   and receipt_number=p_receiptno  --Change 1.1
					   and coalesce(approval_status,'P')='P'
					   and isactive='1';
			------------Update Declaration Approval Status and Amount only on Approval--------------			   
	if p_approvalstatus='A' then
				select * 
				into v_rec
				 from trn_investment_proof  
				where 
					trn_investment_proof.approval_status='A'
					and trn_investment_proof.isactive='1'
					and trn_investment_proof.emp_code=p_empcode
					and trn_investment_proof.headid=p_headid
					and trn_investment_proof.investment_id=p_investmentid
					and trn_investment_proof.financial_year=p_financialyear;
					
					select sum(receipt_amount) 
						into v_totalamount
				 		from trn_investment_proof  
				where 
					trn_investment_proof.approval_status='A'
					and trn_investment_proof.isactive='1'
					and trn_investment_proof.emp_code=p_empcode
					and trn_investment_proof.headid=p_headid
					and trn_investment_proof.investment_id=p_investmentid
					and trn_investment_proof.financial_year=p_financialyear;
					
	if exists(select 'x' from trn_investment 
			  					where trn_investment.emp_code=p_empcode
								and trn_investment.headid=p_headid
								and trn_investment.investment_id=p_investmentid
								and trn_investment.financial_year=p_financialyear
								and coalesce(trn_investment.approval_status,'P')<>'R'
			 					and isactive='1')	then  --commented for Change 1.1
						 update public.trn_investment
						 set  approval_status=p_approvalstatus,
								   approvedby=p_updatedby,
								   approvedon=current_timestamp,
								   approvedbyip=p_updatedbyip,
							       investment_amount=v_totalamount
						where 
								trn_investment.emp_code=p_empcode
								and trn_investment.headid=p_headid
								and trn_investment.investment_id=p_investmentid
								and trn_investment.financial_year=p_financialyear
								and coalesce(trn_investment.approval_status,'P')<>'R'
								and isactive='1';		--commented for Change 1.1		
			else
				INSERT INTO public.trn_investment(
	 	   			 headid, financial_year, investment_id, emp_code, emp_id, investment_amount, investment_comment, createdby, createdon, 			createdbyip, 	isactive, approval_status, approvedon, approvedby, approvedbyip)
				SELECT  v_rec.headid, v_rec.financial_year, v_rec.investment_id, v_rec.emp_code, v_rec.emp_id, v_rec.receipt_amount	  ,	v_rec.investment_comment, p_updatedby, current_timestamp, p_updatedbyip,  v_rec.isactive, 'A', 		current_timestamp,p_updatedby, p_updatedbyip;
			end if;						
end if;
	/*************************************Housing Loan********************************/	
			elsif 	p_headid=4 then 
				update public.empupload_homeloan_document
						set  approval_status=p_approvalstatus,
							   approvedby=p_updatedby,
							   approvedon=current_timestamp,
							   approvedbyip=p_updatedbyip,
							   remarks=p_remarks
							   where emp_code=p_empcode
							   and financial_year=p_financialyear
							   and coalesce(approval_status,'P')='P'
							   and active='1'; 
			--------------------Update Declaration Approval Status and Amount only on Approval--------------		   
			if p_approvalstatus='A' then	
				select *
					into v_rec 
					from empupload_homeloan_document	   
				where 
					 empupload_homeloan_document.approval_status='A'
					and empupload_homeloan_document.active='1'
					and empupload_homeloan_document.emp_code=p_empcode
					and empupload_homeloan_document.financial_year=p_financialyear; 
		
if exists(select 'x' from empdeclr_homeloan
							where 
								 empdeclr_homeloan.emp_code=p_empcode
								and empdeclr_homeloan.financial_year=p_financialyear
								and coalesce(empdeclr_homeloan.approval_status,'P')='P'
								and empdeclr_homeloan.active='1') then
								
					update public.empdeclr_homeloan
						set  approval_status=p_approvalstatus,
							   approvedby=p_updatedby,
							   approvedbyip=p_updatedbyip,
							   approvedon=current_timestamp,
							   lender_pannumber1=v_rec.lender_pannumber1,
							   lender_pannumber2=v_rec.lender_pannumber2,
							   lender_pannumber3=v_rec.lender_pannumber3,
							   lender_pannumber4=v_rec.lender_pannumber4,
							   loan_sanction_date=v_rec.loan_sanction_date,
							   loan_amount=v_rec.loan_amount,
							   property_value=v_rec.property_value,
							   lender_name=v_rec.lender_name,
							   is_firsttymebuyer=v_rec.is_firsttymebuyer,
							   principal_on_borrowed_capital=v_rec.principal_amount,
							   interest_on_borrowed_capital=v_rec.intrest_amount,
							   isbefore01apr1999=v_rec.isbefore01apr1999,
							   homeaddress=v_rec.homeaddress
						where 
								 empdeclr_homeloan.emp_code=p_empcode
								and empdeclr_homeloan.financial_year=p_financialyear
								and coalesce(empdeclr_homeloan.approval_status,'P')='P'
								and empdeclr_homeloan.active='1'; 
		else
				INSERT INTO public.empdeclr_homeloan(
					 emp_code, financial_year, lender_pannumber1, lender_pannumber2, lender_pannumber3, lender_pannumber4, 											loan_sanction_date, loan_amount, property_value, 					lender_name, is_firsttymebuyer, principal_on_borrowed_capital, interest_on_borrowed_capital, created_by, created_on, created_by_ip, active, isbefore01apr1999, approval_status, approvedon, approvedbyip, approvedby,homeaddress)
			  SELECT v_rec.emp_code, v_rec.financial_year, v_rec.lender_pannumber1, v_rec.lender_pannumber2, v_rec.lender_pannumber3, v_rec.lender_pannumber4, v_rec.loan_sanction_date, v_rec.loan_amount,	v_rec.property_value,	v_rec.lender_name, v_rec.is_firsttymebuyer,	 v_rec.principal_amount, 				v_rec.intrest_amount, v_rec.approvedby,current_timestamp,v_rec.approvedbyip,'1', v_rec.isbefore01apr1999, v_rec.approval_status,  v_rec.approvedon, v_rec.approvedbyip,v_rec.approvedby,v_rec.homeaddress;
				end if;
	end if;		   
					   
	/******************************Rent Paid****************************************/	
		elsif 	p_headid=5 then 
    /******************Update Document Approval Status******************************/
	select dateofjoining into v_joiningdate from openappointments where emp_code=p_empcode;
			   update public.empdeclaration_rentdetails_documents
			   set  approval_status=p_approvalstatus,
					   approvedby=p_updatedby,
					   approvedon=current_timestamp,
					   approvedbyip=p_updatedbyip,
					   remarks=p_remarks
					   where emp_code=p_empcode
					   and financialyear=p_financialyear
					   and receiptno=p_receiptno
					   and coalesce(approval_status,'P')='P'
					   and active='1';
					   
	---------------------Update Declaration Approval Status and Amount only on Approval------------------------			   
			if p_approvalstatus='A' then
					select * into v_rec
						from empdeclaration_rentdetails_documents
						   where emp_code=p_empcode
						   and financialyear=p_financialyear
						   and receiptno=p_receiptno
						   and approval_status='A'
						   and active='1';
						   
					v_rentstartyear:=extract ('year' from v_rec.fromdate);
					v_rentendyear:=extract ('year' from v_rec.todate);
					v_rentstartmonth:= extract ('month' from v_rec.fromdate);  
					v_rentendmonth:= extract ('month' from v_rec.todate); 
					
					if v_rentstartyear=v_rentendyear then
				    	v_totalmonths:=(v_rentendmonth-v_rentstartmonth)+1;
					else
					  v_totalmonths:=(12-v_rentstartmonth)+1+(v_rentendmonth);
					end if;
-------------------------------------------------------------------------------
if v_rentstartyear=v_rentendyear then
		for counter in v_rentstartmonth..v_rentendmonth loop
				if not exists(select 'x' from empdeclaration_rentdetails
						  where empdeclaration_rentdetails.emp_code=p_empcode
									and empdeclaration_rentdetails.financial_year=financial_year
									--and coalesce(empdeclaration_rentdetails.approval_status,'P')='P'
									and empdeclaration_rentdetails.rent_year =v_rentstartyear
									and empdeclaration_rentdetails.rent_month = counter
									and empdeclaration_rentdetails.isactive='1') then
		if to_date('01'||lpad(counter::text,2,'0')||v_rentstartyear::text,'ddmmyyyy')>= DATE_TRUNC('MONTH',v_joiningdate)::date then
			INSERT INTO public.empdeclaration_rentdetails(
					emp_code, financial_year, rent_year, rent_month, is_metro, rentpaid,				 no_of_child_under_cea, no_of_child_under_cha, landlordname, landlordpancard, address, createdby, createdon, createdbyip, isactive, approval_status, approvedon, approvedby, approvedbyip)
			SELECT  v_rec.emp_code, v_rec.financialyear, v_rentstartyear, counter,    v_rec.is_metro, v_rec.rent_amount/v_totalmonths,v_rec.no_of_child_under_cea, v_rec.no_of_child_under_cha, v_rec.landlord_name, v_rec.landlord_pan, v_rec.landlord_address,   v_rec.approvedby,current_timestamp, v_rec.approvedbyip,'1', 'A', current_timestamp,v_rec.approvedby, v_rec.approvedbyip;
		end if;
		else
	update public.empdeclaration_rentdetails
			   		set  approval_status=p_approvalstatus,
					   approvedby=p_updatedby,
					   approvedon=current_timestamp,
					   approvedbyip=p_updatedbyip,
						landlordname=v_rec.landlord_name,
						address=v_rec.landlord_address,
						landlordpancard=v_rec.landlord_pan,
					    rentpaid=v_rec.rent_amount/v_totalmonths
					where empdeclaration_rentdetails.emp_code=p_empcode
							and empdeclaration_rentdetails.financial_year=financial_year
							and coalesce(empdeclaration_rentdetails.approval_status,'P')='P'
							and empdeclaration_rentdetails.rent_year =v_rentstartyear
							and empdeclaration_rentdetails.rent_month = counter
							and empdeclaration_rentdetails.isactive='1';

			end if;
			end loop;
else
-------For First Year-------------------------------------------------------	
		for counter in v_rentstartmonth..12 loop
				if not exists(select 'x' from empdeclaration_rentdetails
						  where empdeclaration_rentdetails.emp_code=p_empcode
									and empdeclaration_rentdetails.financial_year=financial_year
									--and coalesce(empdeclaration_rentdetails.approval_status,'P')='P'
									and empdeclaration_rentdetails.rent_year =v_rentstartyear
									and empdeclaration_rentdetails.rent_month = counter
									and empdeclaration_rentdetails.isactive='1') then
	if to_date('01'||lpad(counter::text,2,'0')||v_rentstartyear::text,'ddmmyyyy')>= DATE_TRUNC('MONTH',v_joiningdate)::date then
			INSERT INTO public.empdeclaration_rentdetails(
					emp_code, financial_year, rent_year, rent_month, is_metro, rentpaid,				 no_of_child_under_cea, no_of_child_under_cha, landlordname, landlordpancard, address, createdby, createdon, createdbyip, isactive, approval_status, approvedon, approvedby, approvedbyip)
			SELECT  v_rec.emp_code, v_rec.financialyear, v_rentstartyear, counter,    v_rec.is_metro, v_rec.rent_amount/v_totalmonths,v_rec.no_of_child_under_cea, v_rec.no_of_child_under_cha, v_rec.landlord_name, v_rec.landlord_pan, v_rec.landlord_address,   v_rec.approvedby,current_timestamp, v_rec.approvedbyip,'1', 'A', current_timestamp,v_rec.approvedby, v_rec.approvedbyip;
	end if;
else
	update public.empdeclaration_rentdetails
			   		set  approval_status=p_approvalstatus,
					   approvedby=p_updatedby,
					   approvedon=current_timestamp,
					   approvedbyip=p_updatedbyip,
						landlordname=v_rec.landlord_name,
						address=v_rec.landlord_address,
						landlordpancard=v_rec.landlord_pan,
					    rentpaid=v_rec.rent_amount/v_totalmonths
					where empdeclaration_rentdetails.emp_code=p_empcode
									and empdeclaration_rentdetails.financial_year=financial_year
									and coalesce(empdeclaration_rentdetails.approval_status,'P')='P'
									and empdeclaration_rentdetails.rent_year =v_rentstartyear
									and empdeclaration_rentdetails.rent_month = counter
									and empdeclaration_rentdetails.isactive='1';
			end if;
			end loop;

-------For Second Year-------------------------------------------------------	
		for counter in 1..v_rentendmonth loop
				if not exists(select 'x' from empdeclaration_rentdetails
						  where empdeclaration_rentdetails.emp_code=p_empcode
									and empdeclaration_rentdetails.financial_year=financial_year
									--and coalesce(empdeclaration_rentdetails.approval_status,'P')='P'
									and empdeclaration_rentdetails.rent_year =v_rentendyear
									and empdeclaration_rentdetails.rent_month = counter
									and empdeclaration_rentdetails.isactive='1') then
if to_date('01'||lpad(counter::text,2,'0')||v_rentstartyear::text,'ddmmyyyy')>= DATE_TRUNC('MONTH',v_joiningdate)::date then
			INSERT INTO public.empdeclaration_rentdetails(
					emp_code, financial_year, rent_year, rent_month, is_metro, rentpaid,				 no_of_child_under_cea, no_of_child_under_cha, landlordname, landlordpancard, address, createdby, createdon, createdbyip, isactive, approval_status, approvedon, approvedby, approvedbyip)
			SELECT  v_rec.emp_code, v_rec.financialyear, v_rentendyear, counter,    v_rec.is_metro, v_rec.rent_amount/v_totalmonths,v_rec.no_of_child_under_cea, v_rec.no_of_child_under_cha, v_rec.landlord_name, v_rec.landlord_pan, v_rec.landlord_address,   v_rec.approvedby,current_timestamp, v_rec.approvedbyip,'1', 'A', current_timestamp,v_rec.approvedby, v_rec.approvedbyip;
end if;
else
	update public.empdeclaration_rentdetails
			   		set  approval_status=p_approvalstatus,
					   approvedby=p_updatedby,
					   approvedon=current_timestamp,
					   approvedbyip=p_updatedbyip,
						landlordname=v_rec.landlord_name,
						address=v_rec.landlord_address,
						landlordpancard=v_rec.landlord_pan,
					    rentpaid=v_rec.rent_amount/v_totalmonths
					where empdeclaration_rentdetails.emp_code=p_empcode
									and empdeclaration_rentdetails.financial_year=financial_year
									and coalesce(empdeclaration_rentdetails.approval_status,'P')='P'
									and empdeclaration_rentdetails.rent_year =v_rentendyear
									and empdeclaration_rentdetails.rent_month = counter
									and empdeclaration_rentdetails.isactive='1';
			end if;
			end loop;
-----------------------------------------------------------------------------------------				
end if;
--------------------------------------------------------------------------------			
/*******************************************************************************/		  
				end if;
			   
   end if;
return 1;
end if;
end;
$BODY$;

ALTER FUNCTION public.uspverifyinvestmentproof(bigint, text, integer, integer, text, double precision, text, bigint, character varying, character varying, character varying, text)
    OWNER TO payrollingdb;

