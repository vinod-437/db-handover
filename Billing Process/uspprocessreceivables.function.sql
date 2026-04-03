-- FUNCTION: public.uspprocessreceivables(character varying, numeric, bigint, bigint, character varying, character varying, character varying, integer, numeric, text, character varying, bigint, character varying, character varying, character varying, character varying, character varying, numeric, numeric, character varying, numeric, numeric, numeric, numeric, numeric, numeric, numeric, character varying, character varying, character varying, text, bigint, character varying, bigint, character varying, numeric, character varying, integer, integer, text, text, text, text, text, text, text, numeric, character varying, numeric, numeric, numeric, numeric, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, integer, numeric, numeric, character varying)

-- DROP FUNCTION IF EXISTS public.uspprocessreceivables(character varying, numeric, bigint, bigint, character varying, character varying, character varying, integer, numeric, text, character varying, bigint, character varying, character varying, character varying, character varying, character varying, numeric, numeric, character varying, numeric, numeric, numeric, numeric, numeric, numeric, numeric, character varying, character varying, character varying, text, bigint, character varying, bigint, character varying, numeric, character varying, integer, integer, text, text, text, text, text, text, text, numeric, character varying, numeric, numeric, numeric, numeric, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, integer, numeric, numeric, character varying);

CREATE OR REPLACE FUNCTION public.uspprocessreceivables(
	p_action character varying,
	p_baseamount numeric DEFAULT NULL::numeric,
	p_receibableid bigint DEFAULT '-9999'::integer,
	p_customeraccountid bigint DEFAULT NULL::bigint,
	p_customermobilenumber character varying DEFAULT NULL::character varying,
	p_customeraccountname character varying DEFAULT NULL::character varying,
	p_hsn_sac_number character varying DEFAULT '998514'::character varying,
	p_numberofemployees integer DEFAULT NULL::integer,
	p_netamountreceived numeric DEFAULT NULL::numeric,
	p_dateofreceiving text DEFAULT NULL::text,
	p_source character varying DEFAULT 'Mobile'::character varying,
	p_created_by bigint DEFAULT NULL::bigint,
	p_createdbyip character varying DEFAULT NULL::character varying,
	p_transactionid character varying DEFAULT NULL::character varying,
	p_paymentmethod character varying DEFAULT 'HDFC Manual'::character varying,
	p_invoiceno character varying DEFAULT NULL::character varying,
	p_finyear character varying DEFAULT NULL::character varying,
	p_servicechargerate numeric DEFAULT NULL::numeric,
	p_servicechargeamount numeric DEFAULT NULL::numeric,
	p_gstmode character varying DEFAULT NULL::numeric,
	p_sgstrate numeric DEFAULT NULL::numeric,
	p_sgstamount numeric DEFAULT NULL::numeric,
	p_cgstrate numeric DEFAULT NULL::numeric,
	p_cgstamount numeric DEFAULT NULL::numeric,
	p_igstrate numeric DEFAULT NULL::numeric,
	p_igstamount numeric DEFAULT NULL::numeric,
	p_netvalue numeric DEFAULT NULL::numeric,
	p_invoicetype character varying DEFAULT 'Service Invoice'::character varying,
	p_service_name character varying DEFAULT 'Manpower Service'::character varying,
	p_packagename character varying DEFAULT ''::character varying,
	p_json_response text DEFAULT NULL::text,
	p_tallymasterid bigint DEFAULT '-9999'::integer,
	p_transactionstatus character varying DEFAULT ''::character varying,
	p_verifiedbyempcode bigint DEFAULT '-9999'::integer,
	p_is_credit_used character varying DEFAULT 'N'::character varying,
	p_creditamount numeric DEFAULT NULL::numeric,
	p_paysource character varying DEFAULT 'Both'::character varying,
	p_month integer DEFAULT '-9999'::integer,
	p_year integer DEFAULT '-9999'::integer,
	p_producttypeid text DEFAULT '1'::text,
	p_entrytype text DEFAULT 'Invoice'::text,
	p_ordernumber text DEFAULT ''::text,
	p_dfm_invoicenumber_y_n text DEFAULT 'N'::text,
	p_dfm_receiptnumber text DEFAULT ''::text,
	p_dfm_invoicenumber text DEFAULT ''::text,
	p_invoice_adjustment_tallyinvoicenumber text DEFAULT ''::text,
	p_tdsamount numeric DEFAULT 0,
	p_istaxincludedflag character varying DEFAULT 'Y'::character varying,
	p_adjustment_amount numeric DEFAULT 0,
	p_receipt_amount numeric DEFAULT 0,
	p_excess_amount numeric DEFAULT 0,
	p_balance numeric DEFAULT 0,
	p_narration character varying DEFAULT ''::character varying,
	p_servicedescline2 character varying DEFAULT ''::character varying,
	p_servicedescline3 character varying DEFAULT ''::character varying,
	p_servicedescline4 character varying DEFAULT ''::character varying,
	p_servicedescline5 character varying DEFAULT ''::character varying,
	p_servicedescline6 character varying DEFAULT ''::character varying,
	p_servicedescline7 character varying DEFAULT ''::character varying,
	p_servicedescline8 character varying DEFAULT ''::character varying,
	p_servicedescline9 character varying DEFAULT ''::character varying,
	p_servicedescline10 character varying DEFAULT ''::character varying,
	p_billtype character varying DEFAULT ''::character varying,
	p_invoicemonth integer DEFAULT 0,
	p_invoiceyear integer DEFAULT 0,
	p_other_deductions numeric DEFAULT 0,
	p_pfadmincharges numeric DEFAULT 0,
	p_remarks character varying DEFAULT ''::character varying)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
v_rfc refcursor;

v_rfcreceiptinvoice refcursor;
v_rfccredit refcursor;
v_servicechargerate numeric(18,6);
v_servicechargeamount numeric(18,2);
v_cgstrate numeric(18,2):=0;
v_cgstamount numeric(18,2):=0;
v_sgstrate numeric(18,2):=0;
v_sgstamount numeric(18,2):=0;
v_igstrate numeric(18,2):=0;
v_igstamount numeric(18,2):=0;
v_netvalue numeric(18,2);
v_mygstno varchar(100);
v_customergstno varchar(100);
v_gstmode varchar(15);
v_customermobilenumber character varying DEFAULT NULL::character varying;
v_customeraccountname character varying DEFAULT NULL::character varying;
v_contactname  character varying;
v_address  character varying;
v_netamountreceived  numeric(18,2);
v_invoiceno varchar(16);
v_invoiceid bigint;
v_id bigint;
v_finyearsuffix varchar(4);
v_todaydate date;
v_rfccalculatedinvoice refcursor;
v_rec record;
v_recreceiptinvoice record;
v_statecode varchar(2);
v_transactionstatus varchar(50);

v_employername varchar(500);
v_employeraddress varchar(500);
v_employercinno varchar(500);
v_employergstno varchar(50);
v_employerpanno  varchar(20);
v_employerstatename varchar(200);
v_amountinwords varchar(1000);
v_jurisdiction varchar(100):='SUBJECT TO DELHI JURISDICTION';
v_accountstatename varchar(100);
v_service_name character varying;
v_financialyear varchar(9);
v_customeraccountid bigint;
v_tranexpiryminutes int;
v_baseamount numeric(18,2);
v_message text:='Payout Amount Saved Successfully.';

v_is_credit_used character varying;
v_creditamount numeric(18,2);
v_paysource character varying;
v_credit_applicable character varying:='N';
v_orderno character varying;
v_receiptinvoiceamount  numeric(18,2):=0.0;
v_invoicealreadyexists char(1):='N';
v_tbl_receivables tbl_receivables%rowtype;

v_paymentcount int:=0;
v_startingpaymentamt  numeric(18,2);
v_margin_type varchar(10);

v_originalservicechargerate numeric(18,6);
v_payout_mode_type text; 
v_balance   numeric(18,2);
v_receivableamount   numeric(18,2);
v_adjustmentamount   numeric(18,2);
v_adjustment_tallyinvoicenumber varchar(100);
v_tbl_account tbl_account%rowtype;
v_tallyinvoiceid bigint;
v_tallyinvoicenumber varchar(100);
v_entrytype text;
v_tbl_receivables_receipt tbl_receivables%rowtype;
v_tbl_receivables_invoice tbl_receivables%rowtype;
v_pfadmincharges   numeric(18,2);
v_hsn_sac_number character varying (10);
v_tbl_receivables_chk tbl_receivables%rowtype;
begin
	/*************************************************************************************************
	Version Date			Change										Done_by
	1.0		28-Nov-2022		Initial Version								Shiv Kumar
	1.1		15-Mar-2023		Add Tally Invoice Number					Shiv Kumar
	1.2		18-Apr-2023		Save Payment History						Shiv Kumar
	1.3		11-Jul-2023		credit PI CREATION							Shiv Kumar
	1.4		21-Sep-2023		Receipt for Payrolling						Shiv Kumar
	1.5		04-Oct-2023		Round Service charge as 					Shiv Kumar
							Saurav Jha's Mail dated 04-Oct-2023
	1.6		30-Oct-2023		Deduct Starting payment from receipt amt	Shiv Kumar
							and save Payrolling invoice amt into processing charges
	1.7		19-Dec-2023		Hybrid Receivable Calculation				Shiv Kumar
	1.8		09-Jan-2024		Attendance Receivable Calculation			Shiv Kumar
	1.9 	05-Feb-2024		Update tds amount and Istaxincluded in      Siddharth Bansal
							SetRecievablePaid	 Action				
		
	2.0   08-Feb-2024       Update adjustment amount and 
							adjustment invoice number in      			Siddharth Bansal
							SetRecievablePaid Action		
							
	2.1 	21-Feb-2024		Update excess amount and 
							receipt amount in      						Siddharth Bansal
							SetRecievablePaid Action
	2.2		17-Mar-2024		Adjust Payrolling Receipt and Invoice		Shiv Kumar
    2.3		21-Mar-2024		WFM ADD Action='SetRecievablePaid'		    CHANDRA MOHAN
    2.4		30-Mar-2024		Change upistatus Y to N in response		    Parveen Kumar
    2.5		01-Apr-2024		Adjust attendancemode PI				    Shiv Kumar
    2.6		03-Apr-2024		Change Invoice Number format 			    Shiv Kumar
							as per mail dated 03-Mar-2024
	2.7		04-Jun-2024		Adjust Invoice and receipt					Shiv Kumar
	2.8		25-Jun-2024		Add Billing Address							Shiv Kumar
	2.9		15-Jul-2024		Create only Receipt							Shiv Kumar
	2.10	14-Aug-2024		Duplicate transaction ID Exception			Shiv Kumar
	2.11	26-Aug-2024		Change p_hsn_sac_number and service name	Shiv Kumar
							As per mail Use of name Software 
							Subscription with SAC (SAC Code 998313)
							dated 26-Aug-2024
	2.12	26-Sep-2024		Add Bill Date								Shiv Kumar
	2.13	10-Oct-2024		Stop payment of Paid Invoice having receipt	Shiv Kumar
	2.14	27-Nov-2024		Not to adjust positive amount below 5		Shiv Kumar
	2.15	03-Apr-2025		change SaaS Invoice and Offroll 			Shiv Kumar
							Payrolling code
	2.16	01-Jul-2025		To disable Auto Adjustments feature			Shiv Kumar
							(as per mail dated 01-Jul-2025)
	**************************************************************************************************/
/****Step 1*****Calculate And display Total Amount to Employer*************************/
if p_action='CalcReciebaleFromBaseAmount' then 
		if p_customeraccountid is null then
			open v_rfc for
			select 4 as response;
			return v_rfc;
		end if;
/********change 2.11 starts******************************************/
	v_hsn_sac_number:=p_hsn_sac_number;
	if p_producttypeid='2' then
		v_hsn_sac_number:='998313';
	end if;
/********change 2.11 starts******************************************/		
		/********change 2.8 starts******************************************/
		select * from tbl_account where id=p_customeraccountid into v_tbl_account;
		/********change 2.8 ends********************************************/		
		
	    update tbl_receivables set isactive='0' where customeraccountid=p_customeraccountid and orderno<>p_ordernumber and status='Pending' and paymentmethod='HDFC Manual' and isactive='1'  /*and billtype=p_billtype and invoicemonth=p_invoicemonth and invoiceyear=p_invoiceyear*/;
		select gstno,employername,address,employer.state, cinno,panno,gstno 
		into v_mygstno,v_employername,v_employeraddress,v_employerstatename,v_employercinno,v_employerpanno,v_employergstno 
		from public.employer where employerid=1 and active='1';
		--and source<>'Tpayops';
		
		select ac_gstin_no,(string_to_array(accountname::varchar,'#'))[1]::varchar ,mobile,account_contact_name,coalesce(address,'')||case when nullif(ac_gstin_no,'') is null then ' '||tbl_account.city||', '||tbl_account.state||'-'||tbl_account.pincode else '' end address,left(ac_gstin_no,2),state,trim(payout_mode_type) 
		into v_customergstno,v_customeraccountname,v_customermobilenumber,v_contactname,v_address,v_statecode,v_accountstatename,v_payout_mode_type 
		from public.tbl_account where id=p_customeraccountid;
/*******************************start 1.6	***********************************************
select count(*) from tbl_receivables 
where customeraccountid =p_customeraccountid::bigint
	and packagename<>'Starting Payment' 
	and isactive='1' and status='Paid'
into v_paymentcount;

v_paymentcount:=coalesce(v_paymentcount,0);

select sum(netamount) from tbl_receivables 
where customeraccountid =p_customeraccountid::bigint
	and packagename='Starting Payment' 
	and isactive='1' 
	and status='Paid'
into v_startingpaymentamt;

v_startingpaymentamt:=coalesce(v_startingpaymentamt,0);

--v_adjustedamount
*******************************end 1.6	***********************************************/
/*******************************change 1.7 starts	***********************************************/
if p_packagename<>'Starting Payment' and p_producttypeid='2' and p_entrytype='Receipt' then

				v_balance:=case when v_tbl_account.product_type='2' then coalesce(p_balance,0) else 0 end;
				if v_balance<=0 then
					v_receivableamount=p_baseamount-v_balance;
					v_adjustmentamount:=v_balance;
					v_balance:=0;
				else
	/***change 2.4 starts*******/				
					--if v_balance<=2 then
							v_balance:=0;
					--end if;	
	/***change 2.4 ends*******/				
					v_receivableamount=greatest(p_baseamount-v_balance,0);
					v_adjustmentamount:=coalesce(least(p_baseamount,v_balance),0);
					v_balance=v_balance-v_adjustmentamount;
			
			select tallyinvoicenumber from tbl_receivables 
			where customeraccountid =p_customeraccountid::bigint
				--and packagename='Starting Payment' 
				and isactive='1' 
				and status='Paid' 
				and entrytype='Receipt'
				and v_adjustmentamount>0
				order by id desc limit 1
			into v_adjustment_tallyinvoicenumber;
				end if;
else
				v_receivableamount=p_baseamount;
				v_adjustmentamount:=0;
				v_adjustment_tallyinvoicenumber:=null;
				v_balance:=0;

end if;
/********************************change 1.7 ends*************************************************************/
/*********************************************************************************************/
	if p_packagename<>'Starting Payment' and p_producttypeid='2' and p_entrytype='Receipt' then
		select * from tbl_receivables 
			where customeraccountid =p_customeraccountid::bigint 
			and product_type='2' 
			and packagename<>'Starting Payment' 
			and isactive='1' and status not in('Paid','Failed')
			and netamount=v_receivableamount
			and billtype=p_billtype
			and invoicemonth=p_invoicemonth 
			and invoiceyear=p_invoiceyear
			and entrytype='Receipt'
			and paymentmethod='HDFC Manual'
		into v_tbl_receivables;
	if v_tbl_receivables.invoiceno is not null then
		open v_rfc for
		select p_customeraccountid customeraccountid,v_customermobilenumber customermobilenumber,v_customeraccountname customeraccountname, p_numberofemployees numberofemployees,sum(coalesce(netamount,0)+coalesce(adjustment_amount,0)) payoutamount, sum(netamountreceived)-sum(case when entrytype='Invoice' then coalesce(adjustment_amount,0) else 0 end) amount_to_pay,
				sum(case when entrytype='Receipt' then netamount else 0 end) baseamount,
				sum(servicechargepercent) servicechargerate,
				sum(servicechargeamount) servicechargeamount,
				v_tbl_receivables.gstmode gstmode,
				sum(sgstpercent) sgstrate,
				sum(sgstamount) sgstamount, 
				sum(cgstpercent) cgstrate, 
				sum(cgstamount) cgstamount, 
				sum(igstpercent) igstrate, 
				sum(igstamount) igstamount,
				sum(case when entrytype='Invoice' then coalesce(nullif(servicechargeamount,0),netamount) else 0 end) payrollingcharges,
				v_contactname customercontactname,
				v_address customeraddress,
				v_customergstno ac_gstnumber,
				v_statecode statecode,
				v_employername employername,
				v_employeraddress employeraddress,
				v_employerstatename employerstatename,
				v_employercinno employercinno,
				v_employerpanno employerpanno,
				v_employergstno employergstno,
				fnnumbertowords(sum(netamountreceived)-sum(case when entrytype='Invoice' then coalesce(adjustment_amount,0) else 0 end)) amountinwords,
				v_jurisdiction jurisdiction,
				v_accountstatename accountstatename,
				max(case when entrytype='Receipt' then invoiceno else null end) as pinumber,
				to_char(current_date,'dd-mon-yy') as pidate,
				'Processing Charge' as processingcharge_title,
				'998514' hsnsacnumber,
				v_tbl_receivables.service_name service_name,
				v_message paymessage,
				sum(netamountreceived)-sum(case when entrytype='Invoice' then coalesce(adjustment_amount,0) else 0 end) netamountreceived
			from tbl_receivables
			where tbl_receivables.orderno=v_tbl_receivables.invoiceno
			and customeraccountid=p_customeraccountid::bigint;
	
		return v_rfc;
		end if;
	end if;
	if p_packagename='Starting Payment' and p_producttypeid='2' and p_entrytype='Receipt' then
		select * from tbl_receivables 
			where customeraccountid =p_customeraccountid::bigint 
			and product_type='2' 
			and packagename='Starting Payment' 
			and isactive='1' and status not in('Paid','Failed')
			and netamount=p_baseamount
			and entrytype='Receipt'
		into v_tbl_receivables;
	if v_tbl_receivables.invoiceno is not null then
		open v_rfc for
		select p_customeraccountid customeraccountid,v_customermobilenumber customermobilenumber,v_customeraccountname customeraccountname, p_numberofemployees numberofemployees,sum(case when entrytype='Receipt' then netamount else 0 end) payoutamount, sum(netamountreceived) amount_to_pay,
		sum(case when entrytype='Receipt' then netamount else 0 end) baseamount,
				sum(servicechargepercent) servicechargerate,
				sum(servicechargeamount) servicechargeamount,
				v_tbl_receivables.gstmode gstmode,
				sum(sgstpercent) sgstrate,
				sum(sgstamount) sgstamount, 
				sum(cgstpercent) cgstrate, 
				sum(cgstamount) cgstamount, 
				sum(igstpercent) igstrate, 
				sum(igstamount) igstamount,
				sum(case when entrytype='Invoice' then netamount else 0 end) payrollingcharges,
				v_contactname customercontactname,
				v_address customeraddress,
				v_customergstno ac_gstnumber,
				v_statecode statecode,
				v_employername employername,
				v_employeraddress employeraddress,
				v_employerstatename employerstatename,
				v_employercinno employercinno,
				v_employerpanno employerpanno,
				v_employergstno employergstno,
				fnnumbertowords(sum(netamountreceived)) amountinwords,
				v_jurisdiction jurisdiction,
				v_accountstatename accountstatename,
				max(case when entrytype='Receipt' then invoiceno else null end) as pinumber,
				to_char(current_date,'dd-mon-yy') as pidate,
				'Processing Charge' as processingcharge_title,
				'998514' hsnsacnumber,
				v_tbl_receivables.service_name service_name,
				v_message paymessage,
				sum(netamountreceived) netamountreceived
			from tbl_receivables
			where tbl_receivables.orderno=v_tbl_receivables.invoiceno
			and customeraccountid=p_customeraccountid::bigint;
	
		return v_rfc;
		end if;
	end if;	
	/****************Change 1.3 starts********************************/		
		v_is_credit_used:=p_is_credit_used;
		v_creditamount:=p_creditamount;
		v_paysource:=p_paysource;
		if v_is_credit_used='Y' and v_creditamount>0 and v_paysource='Both' then
				update tbl_receivables 
					set isactive='0',createdon=current_timestamp,
					created_by=p_created_by,createdbyip=p_createdbyip
				where  customeraccountid=p_customeraccountid
					and coalesce(credit_applicable,'N')='Y'
					and coalesce(credit_used,'N')='N'
					and isactive='1'
					and creditmonth=p_month
					and credityear=p_year;

					v_paysource:='Credit';
					select public.uspprocessreceivables(
									p_action =>p_action,
									p_baseamount =>0::numeric,
									p_receibableid => '-9999'::integer,
									p_customeraccountid =>p_customeraccountid::bigint,
									p_source =>p_source::character varying,
									p_created_by =>p_created_by::bigint,
									p_createdbyip =>p_createdbyip::character varying,
									p_packagename =>p_packagename::character varying,
									p_is_credit_used => 'Y'::character varying,
									p_creditamount =>p_creditamount::numeric,
									p_paysource=>v_paysource,
									p_month=>p_month,
									p_year=>p_year,
									p_paymentmethod=>'HDFC Manual',
									p_producttypeid=>p_producttypeid)
						into v_rfccredit;
					if p_baseamount=0 then
						return v_rfccredit;
					end if;
				v_is_credit_used:='N';
				v_creditamount:=0;
		end if;
		if v_is_credit_used='Y' and v_creditamount>0 then
			v_credit_applicable:='Y';
			v_message:='Credit Amount Saved Successfully.';
		end if;
	/*****************Change 1.3 ends*******************************/	
		    select ratevalue,margin_type into v_servicechargerate,v_margin_type from tbl_ratemaster where ratemastername='Service Charge' and isactive='1' and customeraccountid=p_customeraccountid;
		if v_servicechargerate is null then
			select ratevalue,margin_type into v_servicechargerate,v_margin_type from tbl_ratemaster where ratemastername='Service Charge' and customeraccountid is null and isactive='1';
		end if;
		v_originalservicechargerate:=v_servicechargerate;
	/*****************Change 1.4 starts*******************************/	
		if p_entrytype='Receipt' and p_packagename<>'Starting Payment' then
			if lower(coalesce(v_margin_type,''))='flat' then
				v_receiptinvoiceamount:=coalesce(nullif(coalesce(p_numberofemployees,0),0),1)*v_servicechargerate;
			else
				v_receiptinvoiceamount:=p_baseamount*v_servicechargerate/100;
			end if;
		else
			v_receiptinvoiceamount:=0.0;
		end if;	
		if (p_entrytype='Invoice' and (p_producttypeid='2' or (p_producttypeid='1' and p_baseamount=0  and p_creditamount=0.0))) or p_entrytype='Receipt' then 
			v_servicechargerate:=0.00;
		end if;
	/*****************Change 1.4 ends*******************************/

		select ratevalue into v_cgstrate from tbl_ratemaster where ratemastername='CGST' and isactive='1';
		select ratevalue into v_sgstrate from tbl_ratemaster where ratemastername='SGST' and isactive='1';
		select ratevalue into v_igstrate from tbl_ratemaster where ratemastername='IGST' and isactive='1';
		
		if p_entrytype='Receipt' or (p_baseamount=0 and p_creditamount=0.0) then
			v_cgstrate:=0.0;
			v_sgstrate:=0.0;
			v_igstrate:=0.0; 
		end if;
		
		if v_is_credit_used='Y'  and v_creditamount>0 then
			v_baseamount=p_creditamount;
		else
			v_baseamount=p_baseamount;
		end if;
		if lower(coalesce(v_margin_type,''))='flat' then
				v_servicechargeamount:=coalesce(nullif(coalesce(p_numberofemployees,0),0),0)*v_servicechargerate;
		else		
				v_servicechargeamount:=(v_baseamount*v_servicechargerate/100); 
		end if;
		if upper(trim(v_employerstatename))=upper(trim(v_accountstatename)) then
			v_gstmode:='Local';
			v_sgstamount:=(v_baseamount+coalesce(v_servicechargeamount,0))*v_sgstrate/100;
			v_cgstamount:=(v_baseamount+coalesce(v_servicechargeamount,0))*v_cgstrate/100;	
			v_igstrate:=0;
			v_netamountreceived:=coalesce(v_baseamount,0)+coalesce(v_servicechargeamount,0)+coalesce(v_sgstamount,0)+coalesce(v_cgstamount,0);
			v_service_name:='Manpower Service';
		else
			v_gstmode:='Interstate';
			v_igstamount:=(v_baseamount+coalesce(v_servicechargeamount,0))*v_igstrate/100;
			v_cgstrate:=0;
			v_sgstrate:=0;
			v_netamountreceived:=coalesce(v_baseamount,0)+coalesce(v_servicechargeamount,0)+coalesce(v_igstamount,0);
			v_service_name:='Manpower Service';
		end if;
		if p_producttypeid='2' and p_entrytype='Invoice' then
					v_service_name:='Software Subscription';
		end if;
		if p_producttypeid='2' and p_entrytype='Receipt' then
					v_service_name:='Receipt Amount';
		end if;
/*********************************************************************************************/		
insert into public.tbl_subscriptioncalclog
(customeraccountid,numberofemployees,baseamount,netamountreceived,createdon
)values(p_customeraccountid,p_numberofemployees,v_baseamount,v_netamountreceived,current_timestamp);

/*********************************************************************************************/
SELECT public.fnnumbertowords(v_netamountreceived) into v_amountinwords;

/*********************************************************************************************/
update tbl_receivables set status='Expired' 
where customeraccountid=p_customeraccountid
and status='Pending'
and isactive='1'
and paymentmethod='HDFC UPI'
and paymentmethodupdatetime is not null
and paymentmethodupdatetime<current_timestamp-interval '2 minutes';

select invoiceno from public.tbl_receivables where customeraccountid=p_customeraccountid and
status =case when coalesce(v_credit_applicable,'N')='N' then 'Pending' else 'Outstanding' end 
and (coalesce(senttogateway,'N')='N'  or coalesce(paymentmethod,'')='HDFC Manual')
and netamountreceived=v_netamountreceived 
and isactive='1' 
and coalesce(credit_applicable,'N')=v_credit_applicable
and entrytype=p_entrytype and not(p_producttypeid='2' and p_entrytype='Invoice')
and product_type=p_producttypeid
and packagename=case when p_producttypeid ='2' then p_packagename else packagename end
and coalesce(creditmonth,-9999)=case when coalesce(v_credit_applicable,'N')='N' then -9999 else p_month end
and coalesce(credityear,-9999)=case when coalesce(v_credit_applicable,'N')='N' then -9999 else p_year end
 order by id desc limit 1
into v_invoiceno;

if v_invoiceno is null then
v_todaydate:=current_date;
	if (extract ('Month' from v_todaydate) in (4,5,6,7,8,9,10,11,12)) then
		v_finyearsuffix:=right(extract ('Year' from v_todaydate)::text,2)||right((extract ('Year' from v_todaydate)+1)::text,2);
	else
		v_finyearsuffix:=right((extract ('Year' from v_todaydate)-1)::text,2)||right(extract ('Year' from v_todaydate)::text,2);
	end if;
	select nextval('seq_invoceno') into v_invoiceid;
	v_invoiceno:='TP/PI/'||v_finyearsuffix||'/'||v_invoiceid::text;
	
select ac_gstin_no,accountname,mobile into v_customergstno,v_customeraccountname,v_customermobilenumber 
from public.tbl_account where id=p_customeraccountid;
		if p_balance>0 and p_entrytype='Invoice' and p_producttypeid='2' then
			v_adjustmentamount:=least(p_balance,v_netamountreceived);
			v_adjustment_tallyinvoicenumber:=null;
				select tallyinvoicenumber from tbl_receivables 
				where customeraccountid =p_customeraccountid::bigint
					and isactive='1' 
					and entrytype='Receipt'
					and status='Paid'
					order by id desc limit 1
				into v_adjustment_tallyinvoicenumber;
		end if;
	v_orderno:=v_invoiceno;
	v_pfadmincharges:=p_pfadmincharges;
	if v_payout_mode_type='self' then
		v_pfadmincharges:=0;
	end if;
	INSERT INTO public.tbl_receivables(
		customeraccountid,customermobilenumber,customeraccountname, numberofemployees,dateofinitiation, netamountreceived,servicechargepercent,servicechargeamount,gstmode, sgstpercent, sgstamount, cgstpercent, cgstamount, igstpercent, igstamount,netamount,  source,    created_by, createdon, createdbyip, isactive,	status,invoiceno,invoicedt,invoicetype,service_name,packagename,hsn_sac_number
		,credit_applicable,credit_used,creditmonth,credityear,paymentmethod
		,entrytype,product_type
		,recordpushedtotally
		,orderno
 		,receipt_amount
		,adjustment_amount
		,adjustment_tallyinvoicenumber
		,payout_mode_type
		,billtype
		,invoicemonth
		,invoiceyear
		,pfadmincharges
		,billing_address
		,billing_state
		,receiptpushedtotally
	)
--VALUES (p_customeraccountid,v_customermobilenumber,v_customeraccountname, p_numberofemployees,current_date, case when p_producttypeid='2' and p_entrytype='Receipt' and p_packagename<>'Starting Payment'  then v_receivableamount else v_netamountreceived end,case when (p_entrytype='Invoice' and p_producttypeid='2') then v_originalservicechargerate else  v_servicechargerate end,case when p_producttypeid='2' and p_entrytype='Invoice' then v_baseamount else v_servicechargeamount end,v_gstmode, v_sgstrate, v_sgstamount, v_cgstrate, v_cgstamount, v_igstrate, v_igstamount,case when p_producttypeid='2' and p_entrytype='Invoice' then  0 when p_producttypeid='2' and p_entrytype='Receipt' and p_packagename<>'Starting Payment'  then v_receivableamount else v_baseamount end,  p_source, p_created_by, current_timestamp, p_createdbyip,'1'::bit,case when p_baseamount='0' and coalesce(v_credit_applicable,'N')='Y' then 'Paid' when v_tbl_account.payment_plan='Manual' then 'Paid' when v_credit_applicable='Y' then 'Outstanding'	else 'Pending' end,v_invoiceno,current_date,p_invoicetype,v_service_name,p_packagename,v_hsn_sac_number
VALUES (p_customeraccountid,v_customermobilenumber,v_customeraccountname, p_numberofemployees,current_date, case when p_producttypeid='2' and p_entrytype='Receipt' and p_packagename<>'Starting Payment'  then v_receivableamount else v_netamountreceived end,case when (p_entrytype='Invoice' and p_producttypeid='2'and v_payout_mode_type not in ('EOR','DFM')) then v_originalservicechargerate else  v_servicechargerate end,case when p_producttypeid='2' and p_entrytype='Invoice' and v_payout_mode_type not in ('EOR','DFM') then v_baseamount else v_servicechargeamount end,v_gstmode, v_sgstrate, v_sgstamount, v_cgstrate, v_cgstamount, v_igstrate, v_igstamount,case when p_producttypeid='2' and p_entrytype='Invoice' and v_payout_mode_type not in ('EOR','DFM') then  0 when p_producttypeid='2' and p_entrytype='Receipt' and p_packagename<>'Starting Payment'  then v_receivableamount else v_baseamount end,  p_source, p_created_by, current_timestamp, p_createdbyip,'1'::bit,case when p_baseamount='0' and coalesce(v_credit_applicable,'N')='Y' then 'Paid' when v_tbl_account.payment_plan='Manual' then 'Paid' when v_credit_applicable='Y' then 'Outstanding'	else 'Pending' end,v_invoiceno,current_date,p_invoicetype,v_service_name,p_packagename,v_hsn_sac_number
	   ,v_credit_applicable,'N',case when coalesce(v_credit_applicable,'N')='N' then null else nullif(p_month,-9999) end,case when coalesce(v_credit_applicable,'N')='N' then null else nullif(p_year,-9999) end,case when p_baseamount=0 then 'HDFC Manual' else p_paymentmethod end
	   ,p_entrytype,p_producttypeid
	   ,(case when p_entrytype='Receipt' or v_tbl_account.payment_plan='Manual' then '1' else '0' end)::bit 
	   ,coalesce(nullif(p_ordernumber,''),v_invoiceno)
 	   ,case when p_entrytype='Receipt' then v_baseamount else null end
		,v_adjustmentamount
		,v_adjustment_tallyinvoicenumber
		,v_payout_mode_type
		,p_billtype
		,p_invoicemonth
		,p_invoiceyear
		,v_pfadmincharges
		,v_tbl_account.address
		,v_tbl_account.state
	   ,(case when v_tbl_account.payment_plan='Manual' then '1' else '0' end)::bit 
	   )
		returning id into v_id;
		v_pfadmincharges:=0;
else
	v_invoicealreadyexists='Y';
end if;
/*********************************************************************************************/
	if p_entrytype='Receipt' and v_invoicealreadyexists='N' and coalesce(p_numberofemployees,0)>0 then
			if p_packagename<>'Starting Payment' then
			
	if not exists(select * from tbl_receivables where customeraccountid =p_customeraccountid::bigint and isactive='1' and entrytype='Invoice' and status='Paid' and netamountreceived>0 and invoicemonth=p_invoicemonth  and invoiceyear=p_invoiceyear)	then	
			 select * from public.uspprocessreceivables(
											p_action =>p_action,
											p_baseamount =>v_receiptinvoiceamount::numeric,
											p_receibableid => '-9999'::integer,
											p_customeraccountid =>p_customeraccountid::bigint,
											p_source =>p_source::character varying,
											p_created_by =>p_created_by::bigint,
											p_createdbyip =>p_createdbyip::character varying,
											p_packagename =>p_packagename::character varying,
											p_is_credit_used => 'N'::character varying,
											p_creditamount =>0::numeric,
											p_paysource=>'Both',
											p_month=>0,
											p_year=>0,
											p_producttypeid=>p_producttypeid,
											p_entrytype=>'Invoice',
											p_ordernumber=>v_invoiceno,
			 								p_numberofemployees=>p_numberofemployees,
			 								p_balance=>v_balance,
											p_billtype=>p_billtype,
											p_invoicemonth=>p_invoicemonth,
											p_invoiceyear=>p_invoiceyear)
											into v_rfcreceiptinvoice;
											fetch v_rfcreceiptinvoice into v_recreceiptinvoice;
						v_balance:=least(v_balance,v_receiptinvoiceamount);											
				else
						open v_rfc for
						select p_customeraccountid customeraccountid,v_customermobilenumber customermobilenumber,v_customeraccountname customeraccountname, p_numberofemployees numberofemployees,v_baseamount baseamount, v_netamountreceived netamountreceived,v_servicechargerate servicechargerate,v_servicechargeamount servicechargeamount,v_gstmode gstmode, v_sgstrate sgstrate, v_sgstamount sgstamount, v_cgstrate cgstrate, v_cgstamount cgstamount, v_igstrate igstrate, v_igstamount igstamount
							,(v_baseamount+coalesce(v_servicechargeamount,0)) gstbaseamount,v_contactname customercontactname,v_address customeraddress,v_customergstno ac_gstnumber,v_statecode statecode
							,v_employername employername,v_employeraddress employeraddress,v_employerstatename employerstatename,v_employercinno employercinno,v_employerpanno employerpanno,v_employergstno employergstno,
							v_amountinwords amountinwords,v_jurisdiction jurisdiction,v_accountstatename accountstatename,
							v_invoiceno pinumber,to_char(current_date,'dd-mon-yy') as pidate,'Processing Charge' as processingcharge_title,'998514' hsnsacnumber,v_service_name service_name,v_message paymessage
							,v_netamountreceived amount_to_pay,v_baseamount payoutamount,v_adjustmentamount adjustmentamount;
						
						return v_rfc;

				end if;
				open v_rfc for
				select p_customeraccountid customeraccountid,v_customermobilenumber customermobilenumber,v_customeraccountname customeraccountname, p_numberofemployees numberofemployees,v_baseamount payoutamount,v_baseamount baseamount, case when p_producttypeid='2' and p_entrytype='Receipt' and p_packagename<>'Starting Payment'  then v_receivableamount else v_netamountreceived end+coalesce(v_recreceiptinvoice.netamountreceived,0)-coalesce(v_recreceiptinvoice.adjustmentamount,0) amount_to_pay,v_servicechargerate servicechargerate,v_servicechargeamount+coalesce(v_recreceiptinvoice.servicechargeamount,0) servicechargeamount,v_gstmode gstmode, v_sgstrate+coalesce(v_recreceiptinvoice.sgstrate,0) sgstrate, v_sgstamount+coalesce(v_recreceiptinvoice.sgstamount,0) sgstamount, v_cgstrate+coalesce(v_recreceiptinvoice.cgstrate,0) cgstrate, v_cgstamount+coalesce(v_recreceiptinvoice.cgstamount,0) cgstamount, v_igstrate+coalesce(v_recreceiptinvoice.igstrate,0) igstrate, v_igstamount+coalesce(v_recreceiptinvoice.igstamount,0) igstamount
					,(coalesce(v_receiptinvoiceamount,0)) payrollingcharges,v_contactname customercontactname,v_address customeraddress,v_customergstno ac_gstnumber,v_statecode statecode
					,v_employername employername,v_employeraddress employeraddress,v_employerstatename employerstatename,v_employercinno employercinno,v_employerpanno employerpanno,v_employergstno employergstno,
					fnnumbertowords(case when p_producttypeid='2' and p_entrytype='Receipt' and p_packagename<>'Starting Payment'  then v_receivableamount else v_netamountreceived end+coalesce(v_recreceiptinvoice.netamountreceived,0)-coalesce(v_recreceiptinvoice.adjustmentamount,0)) amountinwords,v_jurisdiction jurisdiction,v_accountstatename accountstatename,
					v_invoiceno pinumber,to_char(current_date,'dd-mon-yy') as pidate,'Processing Charge' as processingcharge_title,'998514' hsnsacnumber,v_service_name service_name,v_message paymessage
					,case when p_producttypeid='2' and p_entrytype='Receipt' and p_packagename<>'Starting Payment'  then v_receivableamount else v_netamountreceived end+coalesce(v_recreceiptinvoice.netamountreceived,0) netamountreceived;
			else
				open v_rfc for
				select p_customeraccountid customeraccountid,v_customermobilenumber customermobilenumber,v_customeraccountname customeraccountname, p_numberofemployees numberofemployees,v_baseamount payoutamount,v_baseamount baseamount, v_netamountreceived amount_to_pay,v_servicechargerate servicechargerate,v_servicechargeamount servicechargeamount,v_gstmode gstmode, v_sgstrate sgstrate, v_sgstamount sgstamount, v_cgstrate cgstrate, v_cgstamount cgstamount, v_igstrate igstrate, v_igstamount igstamount
					,(coalesce(v_receiptinvoiceamount,0)) payrollingcharges,v_contactname customercontactname,v_address customeraddress,v_customergstno ac_gstnumber,v_statecode statecode
					,v_employername employername,v_employeraddress employeraddress,v_employerstatename employerstatename,v_employercinno employercinno,v_employerpanno employerpanno,v_employergstno employergstno,
					fnnumbertowords(v_netamountreceived) amountinwords,v_jurisdiction jurisdiction,v_accountstatename accountstatename,
					v_invoiceno pinumber,to_char(current_date,'dd-mon-yy') as pidate,'Processing Charge' as processingcharge_title,'998514' hsnsacnumber,v_service_name service_name,v_message paymessage
					,v_netamountreceived netamountreceived;
			end if;
	else
		open v_rfc for
		select p_customeraccountid customeraccountid,v_customermobilenumber customermobilenumber,v_customeraccountname customeraccountname, p_numberofemployees numberofemployees,v_baseamount baseamount, v_netamountreceived netamountreceived,v_servicechargerate servicechargerate,v_servicechargeamount servicechargeamount,v_gstmode gstmode, v_sgstrate sgstrate, v_sgstamount sgstamount, v_cgstrate cgstrate, v_cgstamount cgstamount, v_igstrate igstrate, v_igstamount igstamount
			,(v_baseamount+coalesce(v_servicechargeamount,0)) gstbaseamount,v_contactname customercontactname,v_address customeraddress,v_customergstno ac_gstnumber,v_statecode statecode
			,v_employername employername,v_employeraddress employeraddress,v_employerstatename employerstatename,v_employercinno employercinno,v_employerpanno employerpanno,v_employergstno employergstno,
			v_amountinwords amountinwords,v_jurisdiction jurisdiction,v_accountstatename accountstatename,
			v_invoiceno pinumber,to_char(current_date,'dd-mon-yy') as pidate,'Processing Charge' as processingcharge_title,'998514' hsnsacnumber,v_service_name service_name,v_message paymessage
			,v_netamountreceived amount_to_pay,v_baseamount payoutamount,v_adjustmentamount adjustmentamount;

	end if;
return v_rfc;
end if;
/*********Calculate And display Total Amount to Employer ends*************************/
/****Step 2*****Save Data Before Sending to Payment Gateway*************************/
if p_action='SaveReciebale' then 
	if p_customeraccountid is null then
	   open v_rfc for
		select 4 as response;
		return v_rfc;
	end if;	
---------------------------------------------------------------------------------------
if p_producttypeid='1' then
select * from public.uspprocessreceivables(p_action =>'CalcReciebaleFromBaseAmount',p_baseamount=>p_netvalue,p_customeraccountid=>p_customeraccountid,p_producttypeid=>p_producttypeid,p_packagename=>p_packagename,p_entrytype=>p_entrytype)
	into v_rfccalculatedinvoice;
	fetch v_rfccalculatedinvoice into v_rec;
	if v_rec.servicechargeamount::numeric(18,2)<>p_servicechargeamount::numeric(18,2) or v_rec.netamountreceived::numeric(18,2)<>p_netamountreceived::numeric(18,2)
		or v_rec.servicechargerate::numeric(18,2)<>p_servicechargerate::numeric(18,2) or v_rec.gstmode<>p_gstmode 
		or v_rec.sgstrate::numeric(18,2)<>p_sgstrate::numeric(18,2) or v_rec.sgstamount::numeric(18,2) <>p_sgstamount::numeric(18,2) 
		or v_rec.cgstrate::numeric(18,2)<>p_cgstrate::numeric(18,2) or v_rec.cgstamount::numeric(18,2) <>p_cgstamount::numeric(18,2) 
		or v_rec.igstrate::numeric(18,2)<>p_igstrate::numeric(18,2) or v_rec.igstamount::numeric(18,2) <>p_igstamount::numeric(18,2) 
	then
		open v_rfc for
			select 5 as response;
		return v_rfc;
	end if;	
--else
--to check
end if;	
---------------------------------------------------------------------------------------
v_todaydate:=current_date;
if (extract ('Month' from v_todaydate) in (4,5,6,7,8,9,10,11,12)) then
	v_finyearsuffix:=right(extract ('Year' from v_todaydate)::text,2)||right((extract ('Year' from v_todaydate)+1)::text,2);
else
	v_finyearsuffix:=right((extract ('Year' from v_todaydate)-1)::text,2)||right(extract ('Year' from v_todaydate)::text,2);
end if;

if p_producttypeid='1' then
	select invoiceno from public.tbl_receivables 
		where customeraccountid=p_customeraccountid
		and status in ('Outstanding','Pending') and (coalesce(senttogateway,'N')='N' or  coalesce(paymentmethod,'')='HDFC Manual')
		and netamountreceived=p_netamountreceived and isactive='1' 
		and packagename=p_packagename
	into v_invoiceno;
else
	select invoiceno from public.tbl_receivables 
		where customeraccountid=p_customeraccountid
		and status in ('Outstanding','Pending') --and coalesce(senttogateway,'N')='N' 
		and coalesce(nullif(receipt_amount,0),netamount)=p_netvalue 
		and isactive='1'
		and packagename=p_packagename
		and entrytype='Receipt'
	into v_invoiceno;
end if;
select ac_gstin_no,accountname,mobile into v_customergstno,v_customeraccountname,v_customermobilenumber from public.tbl_account where id=p_customeraccountid;
	if p_packagename='Starting Payment' and p_entrytype='Receipt' and p_producttypeid='2' then
	update tbl_receivables 
		set packagename=p_packagename,senttogateway='Y' ,created_by=p_created_by,createdbyip=p_createdbyip,Status='Paid',dateofreceiving=current_date
		where customeraccountid=p_customeraccountid
		and status in ('Pending','Outstanding')
		and packagename='Starting Payment'
		and netamountreceived=0 
		and isactive='1';
	end if;

		if p_producttypeid='1' or (p_producttypeid='2' and p_packagename='Starting Payment') then
				update tbl_receivables set packagename=p_packagename,senttogateway='Y' ,created_by=p_created_by,createdbyip=p_createdbyip
					where customeraccountid=p_customeraccountid
					and status in ('Pending','Outstanding') 
					--and coalesce(senttogateway,'N')='N'
					--and netamount=p_netvalue 
					and isactive='1' 
					and packagename=p_packagename
					and invoiceno=v_invoiceno
				returning id into v_id;

					   open v_rfc for
					select id,
							customeraccountid,
							customermobilenumber,
							customeraccountname,
							netamountreceived,
							invoiceno	invoiceno,
							-- 'Y' upistatus,
							'N' upistatus,
							'N' paytmstatus,
							'Y' banktransferstatus 
					from public.tbl_receivables where id=v_id;
						return v_rfc;
		else	
				update tbl_receivables set packagename=p_packagename,senttogateway='Y' ,created_by=p_created_by,createdbyip=p_createdbyip
					where customeraccountid=p_customeraccountid
					and status in ('Pending','Outstanding') 
					--and coalesce(senttogateway,'N')='N'
					--and netamount=p_netvalue 
					and packagename=p_packagename
					and isactive='1' 
					and (invoiceno=v_invoiceno or orderno=v_invoiceno)
					and entrytype='Invoice';

				update tbl_receivables set packagename=p_packagename,senttogateway='Y' ,created_by=p_created_by,createdbyip=p_createdbyip
					where customeraccountid=p_customeraccountid
					and status in ('Pending','Outstanding') 
					--and coalesce(senttogateway,'N')='N'
					--and netamount=p_netvalue
					--and packagename=p_packagename  
					and isactive='1' 
					and invoiceno=v_invoiceno
					and entrytype='Receipt'
				returning id into v_id;
					
					open v_rfc for
					  select max(case when entrytype='Receipt' then id else null end) id,
							customeraccountid,
							customermobilenumber,
							customeraccountname,
							sum(netamountreceived) netamountreceived,
							orderno	invoiceno,
							-- 'Y' upistatus,
							'N' upistatus,
							'N' paytmstatus,
							'Y' banktransferstatus 
					from public.tbl_receivables 
						where (invoiceno=v_invoiceno or orderno=v_invoiceno)
					group by customeraccountid,customermobilenumber,customeraccountname,orderno;
						return v_rfc;
		end if;				
end if;
/*********Save Data Before Sending to Payment Gateway ends*************************/
if p_action='UpdatePaymentMethod' then
v_tranexpiryminutes:=2;
begin
				update tbl_receivables
				set paymentmethod=p_paymentmethod,
				mdified_on=current_timestamp,
				paymentmethodupdatetime=current_timestamp,
				mdified_byip=p_createdbyip,
				tranexpiryminutes=v_tranexpiryminutes
			where (invoiceno=p_invoiceno or orderno=p_invoiceno)and isactive='1';
open v_rfc for
		select 1 as response,v_tranexpiryminutes as tranexpiryminutes; 
		return v_rfc;
exception when others then
		open v_rfc for
		select 2 as response,0 as tranexpiryminutes; 
		return v_rfc;
end;		
end if;
/***Step 3******Update transactionid when Amount paid from Payment Gateway*************************/
if p_action='SetRecievablePaid' then
/****1*****change 2.14 starts*************************/
select * from tbl_receivables where invoiceno=p_invoiceno into v_tbl_receivables_chk;
if v_tbl_receivables_chk.entrytype='Invoice' 
	and exists(select * from tbl_receivables where tbl_receivables.orderno=v_tbl_receivables_chk.orderno and tbl_receivables.entrytype='Receipt' and tbl_receivables.isactive='1') 
	then
		open v_rfc for
		select 10 as response;
		return v_rfc;	
end if;
/*********change 2.14 ends*************************/
if (select status from tbl_receivables where invoiceno=p_invoiceno)='Paid' then
	open v_rfc for
		select 9 as response;
		return v_rfc;	
end if;
		if v_transactionstatus='TXN_SUCCESS' or v_transactionstatus='TXN_OUTSTANDING' and
			 exists(select * from tbl_receivables where coalesce(nullif(transactionid,''),'-9999')=p_transactionid and isactive='1'::bit and invoiceno<>p_invoiceno) then
				open v_rfc for
				select 2 as response; -- transactionid Already exists
				return v_rfc;
		end if;
LOCK TABLE tbl_receivables IN ACCESS EXCLUSIVE MODE;
select customeraccountid,entrytype  from tbl_receivables where invoiceno=p_invoiceno and isactive='1'into v_customeraccountid,v_entrytype;
select * from tbl_account where id=v_customeraccountid into v_tbl_account;
/*****************Change 1.2 starts***************/
	if p_paymentmethod='HDFC UPI' then 
		v_transactionstatus:=p_transactionstatus;
	elsif p_paymentmethod = 'Paytm' then
		select p_json_response::json->>'STATUS' into v_transactionstatus;
    elsif p_paymentmethod = 'WFM' then
		select p_json_response::json->>'STATUS' into v_transactionstatus;
		update tbl_receivables set receiptpushedtotally='1',
			narration=nullif(p_narration,''),
			servicedescline2=nullif(p_servicedescline2,''),
			servicedescline3=nullif(p_servicedescline3,''),
			servicedescline4=nullif(p_servicedescline4,''),
			servicedescline5=nullif(p_servicedescline5,''),
			servicedescline6=nullif(p_servicedescline6,''),
			servicedescline7=nullif(p_servicedescline7,''),
			servicedescline8=nullif(p_servicedescline8,''),
			servicedescline9=nullif(p_servicedescline9,''),
			servicedescline10=nullif(p_servicedescline10,'')
		where invoiceno=p_invoiceno and isactive='1';
	elsif p_paymentmethod = 'HDFC Manual' then
		-- v_transactionstatus:='Pending';
		v_transactionstatus:= CASE WHEN p_json_response::json->>'STATUS'='Approval Required' THEN 'Approval Required' ELSE 'Pending' END;
	elsif p_paymentmethod = 'Verify Manual Bank Transfer' then
	if	coalesce(v_tbl_account.ac_manager_verified,'N')='N' or coalesce(v_tbl_account.tally_push_enable,'N')='N' then
	open v_rfc for
		select 7 as response;
		return v_rfc;
	end if;
	
	
	select * from tbl_receivables where invoiceno=p_invoiceno into v_tbl_receivables;
	if  upper(v_tbl_receivables.billing_state)<>upper(v_tbl_account.state) then
	open v_rfc for
		select 8 as response;
		return v_rfc;	
	end if;
	
	v_tbl_receivables:=null;
	
		select p_json_response::json->>'STATUS' into v_transactionstatus;

			update tbl_receivables
				set transactionid=p_transactionid,
				status=case when v_transactionstatus='TXN_SUCCESS' or v_transactionstatus='TXN_OUTSTANDING' then 'Paid' when v_transactionstatus in ('TXN_FAILURE','TXN_FAILED') then 'Failed' else status end,
				dateofreceiving=case when v_transactionstatus ='TXN_PENDING' then null else p_dateofreceiving::date end,--to_date(p_dateofreceiving,'dd/mm/yyyy'),
				mdified_by=p_created_by,
				mdified_on=current_timestamp,
				mdified_byip=p_createdbyip,
				json_response=p_json_response,
				paymentmethod=case when packagename='Starting Payment' then coalesce(nullif(paymentmethod,''),'HDFC Manual') else paymentmethod end, 
				is_verified='1',
				verifiedbyempcode=p_verifiedbyempcode,
				verifiedon=current_timestamp,
				verifiedbyip=p_createdbyip,
				packagename=coalesce(nullif(p_packagename,''),packagename),
				final_customeramountpaid=p_receipt_amount::numeric,
				remarks=nullif(p_remarks,''),
				is_bill_outstanding=case when v_transactionstatus='TXN_OUTSTANDING' then 'Y' else is_bill_outstanding end
			where (invoiceno=p_invoiceno or orderno=p_invoiceno) and isactive='1'
			and tallyinvoicenumber is null and coalesce(status,'Pending')<>'Paid';
														
			update tbl_receivables
			set	tds_amount = p_tdsamount,
				istaxincluded = p_istaxincludedflag,
				adjustment_amount = p_adjustment_amount,
				adjustment_tallyinvoicenumber =nullif(p_invoice_adjustment_tallyinvoicenumber,''),
				excess_amount = p_excess_amount,
				other_deductions=p_other_deductions
			where invoiceno=p_invoiceno and isactive='1'
				and tallyinvoicenumber is null;
			
/********************change 2.7 starts here****************************************/
		select * from tbl_receivables where invoiceno=p_invoiceno and isactive='1' into v_tbl_receivables_receipt;
		if v_tbl_receivables_receipt.entrytype='Receipt' then
		select * from tbl_receivables where orderno=p_invoiceno and entrytype='Invoice'  and isactive='1' and tallyinvoicenumber is null into v_tbl_receivables_invoice;
			update tbl_receivables
			set	adjustment_amount = 0,
				netamountreceived=receipt_amount,
				netamount=receipt_amount
			where id=v_tbl_receivables_receipt.id;	
		
		update tbl_receivables
			set	adjustment_amount = 0
			where id=v_tbl_receivables_invoice.id and tallyinvoicenumber is null;
		
			
		update tbl_receivables
		set	adjustment_amount = least(coalesce(p_adjustment_amount,0),coalesce(v_tbl_receivables_invoice.netamountreceived,0))
		where id=v_tbl_receivables_invoice.id and tallyinvoicenumber is null;
		
		
	  	update tbl_receivables
			set	adjustment_amount = greatest(coalesce(p_adjustment_amount,0)-coalesce(v_tbl_receivables_invoice.netamountreceived,0),0),
				netamountreceived=netamountreceived-greatest(coalesce(p_adjustment_amount,0)-coalesce(v_tbl_receivables_invoice.netamountreceived,0),0),
				netamount=netamount-greatest(coalesce(p_adjustment_amount,0)-coalesce(v_tbl_receivables_invoice.netamountreceived,0),0)
			where id=v_tbl_receivables_receipt.id;		
	
	end if;		
/*********************change 2.7 ends here***************************************/				
/**********change 2.12 starts here****************************************/
update tbl_receivables
set billdate=case when v_transactionstatus='TXN_SUCCESS' or v_transactionstatus='TXN_OUTSTANDING' then current_date else null end
where (invoiceno=p_invoiceno or orderno=p_invoiceno) and isactive='1' and entrytype='Invoice' and tallyinvoicenumber is null;				
/**********change 2.12 ends here****************************************/
			
			if p_entrytype='Receipt' and p_packagename='Starting Payment' then
			
			update tbl_receivables
				set transactionid=p_transactionid,
				status=case when v_transactionstatus='TXN_SUCCESS' or v_transactionstatus='TXN_OUTSTANDING' then 'Paid' when v_transactionstatus in ('TXN_FAILURE','TXN_FAILED') then 'Failed' else status end,
				dateofreceiving=p_dateofreceiving::date,--to_date(p_dateofreceiving,'dd/mm/yyyy'),
				mdified_by=p_created_by,
				mdified_on=current_timestamp,
				mdified_byip=p_createdbyip,
				json_response=p_json_response,
				is_verified='1',
				verifiedbyempcode=p_verifiedbyempcode,
				verifiedon=current_timestamp,
				verifiedbyip=p_createdbyip
			where customeraccountid=v_customeraccountid and packagename='Starting Payment' and isactive='1' and product_type='1';
			end if;
	end if;
begin	
INSERT INTO public.invoice_paymentdetails(
	 		customeraccountid, invoicenumber, transactionid, paymentmethod, json_response, status, createdon, createdbyip, isactive)
	VALUES (v_customeraccountid, p_invoiceno, p_transactionid, p_paymentmethod, p_json_response, v_transactionstatus, current_timestamp, p_createdbyip, '1'::bit);
exception when others then
null;
end;
/*****************Change 1.2 ends***************/
if v_tbl_account.payout_mode_type in ('standard','hybrid') or (v_tbl_account.payout_mode_type in ('self','attendance') and v_entrytype='Receipt') then
	if exists(select * from tbl_receivables where coalesce(nullif(transactionid,''),'-9999')=p_transactionid and isactive='1' and orderno<>p_invoiceno) then
		open v_rfc for
		select 2 as response; -- transactionid Already exists
		return v_rfc;
	end if;
end if;
if v_tbl_account.payout_mode_type in ('self','attendance') and v_entrytype='Invoice' then
	if exists(select * from tbl_receivables where coalesce(nullif(transactionid,''),'-9999')=p_transactionid and isactive='1' and invoiceno<>p_invoiceno) then
		open v_rfc for
		select 2 as response; -- transactionid Already exists
		return v_rfc;
	end if;
end if;	
if p_paymentmethod <> 'Verify Manual Bank Transfer' then
	update tbl_receivables
		set transactionid=p_transactionid,
			paymentmethod=p_paymentmethod,
			status=case when v_transactionstatus='TXN_SUCCESS' or v_transactionstatus='TXN_OUTSTANDING' then 'Paid' when v_transactionstatus='TXN_REJECTED' then 'REJECTED' when v_transactionstatus in ('TXN_FAILURE','TXN_FAILED') then 'Failed' when v_transactionstatus='Approval Required' then 'Approval Required' when v_transactionstatus='Pending' then 'Pending' else status end,
			dateofreceiving=p_dateofreceiving::date,--to_date(p_dateofreceiving,'dd/mm/yyyy'),
			mdified_by=p_created_by,
			mdified_on=current_timestamp,
			mdified_byip=p_createdbyip,
			json_response=p_json_response
			--netamount=CASE WHEN v_transactionstatus='Approval Required' THEN (p_json_response::json->>'TXNAMOUNT')::numeric(18, 2) ELSE netamount END,
			--netamountreceived=CASE WHEN v_transactionstatus='Approval Required' THEN (p_json_response::json->>'TXNAMOUNT')::numeric(18, 2) ELSE netamountreceived END
		where (invoiceno=p_invoiceno or orderno=p_invoiceno) and isactive='1' and tallyinvoicenumber is null;
	end if;

		/************Change 1.2*********************************/
		if v_transactionstatus='TXN_SUCCESS' or v_transactionstatus='TXN_OUTSTANDING' then
		
			v_todaydate:=current_date;
			if (extract ('Month' from v_todaydate) in (4,5,6,7,8,9,10,11,12)) then
				v_finyearsuffix:=right(extract ('Year' from v_todaydate)::text,2)||right((extract ('Year' from v_todaydate)+1)::text,2);
				v_financialyear:=extract ('Year' from v_todaydate)::text||'-'||(extract ('Year' from v_todaydate)+1)::text;
			else
				v_finyearsuffix:=right((extract ('Year' from v_todaydate)-1)::text,2)||right(extract ('Year' from v_todaydate)::text,2);
				v_financialyear:=(extract ('Year' from v_todaydate)-1)::text||'-'||extract ('Year' from v_todaydate)::text;
			end if;
			
		select * from tbl_receivables where invoiceno=p_invoiceno into v_tbl_receivables;
		
		if v_tbl_receivables.entrytype='Receipt' then
			if upper(p_dfm_invoicenumber_y_n)='Y' then
						update tbl_receivables
						set dfm_invoicenumber_y_n=p_dfm_invoicenumber_y_n,
							dfm_invoicenumber=p_dfm_receiptnumber,
							recordpushedtotally='1',
							receiptpushedtotally='1',
							financial_year=v_financialyear
						where invoiceno=p_invoiceno and isactive='1' and entrytype='Receipt'
						and tallyinvoicenumber is null																   
						returning * into v_tbl_receivables;

			else
				if v_tbl_receivables.netamount>0 then
					update tbl_receivables
					set tallyinvoiceid=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and entrytype='Receipt'),0) +1
						,financial_year=v_financialyear
					where invoiceno=p_invoiceno and isactive='1' and entrytype='Receipt' and netamount>0
					and tallyinvoicenumber is null;

					update tbl_receivables
					set tallyinvoicenumber='RTP/'||v_finyearsuffix||'/'||tallyinvoiceid::text
					where invoiceno=p_invoiceno and isactive='1' and entrytype='Receipt'  and netamount>0
					and tallyinvoicenumber is null
					returning * into v_tbl_receivables;
				end if;	
			end if;	
		else
		
			/****************change 2.6 starts*************************/
		if right(v_financialyear,4)::int<=2025 then
			if v_tbl_account.product_type='2' then
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,6)='HO/TP/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='HO/TP/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
			else
				if exists (select * from public.mst_employer_credit where customer_account_id=v_tbl_account.id and is_active='1' and monthly_credit_amount_limit>0 and monthly_credit_percent_limit>0)then
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,7)='HO/WFM/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='HO/WFM/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
				else
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,7)='HO/SSE/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='HO/SSE/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
				end if;
			end if;	
		else
			if v_tbl_account.product_type='2' then
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,3)='TP/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='TP/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
			else
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,3)='ORP/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='ORP/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
			end if;
		end if;	
		
			update tbl_receivables
			set tallyinvoiceid=v_tallyinvoiceid,
				tallyinvoicenumber=v_tallyinvoicenumber,
				financial_year=v_financialyear
			where invoiceno=p_invoiceno and isactive='1' and entrytype='Invoice'  and (netamount>0 or servicechargeamount>0)
				  and tallyinvoicenumber is null
			/**************change 2.6 ends***************************/
			returning * into v_tbl_receivables;
		
		end if;
		if v_tbl_receivables.entrytype='Receipt' and v_tbl_receivables.packagename='Starting Payment' then
			update tbl_receivables
					set status=case when v_transactionstatus='TXN_SUCCESS' or v_transactionstatus='TXN_OUTSTANDING' then 'Paid' when v_transactionstatus='TXN_REJECTED' then 'REJECTED' when v_transactionstatus in ('TXN_FAILURE','TXN_FAILED') then 'Failed' else status end,
						dateofreceiving=p_dateofreceiving::date,--to_date(p_dateofreceiving,'dd/mm/yyyy'),
						mdified_by=p_created_by,
						mdified_on=current_timestamp,
						mdified_byip=p_createdbyip,
						json_response=p_json_response
					where customeraccountid=v_customeraccountid and packagename='Starting Payment' and product_type='1' and netamountreceived=0 and isactive='1'
						and tallyinvoicenumber is null;
		end if;
		if v_tbl_receivables.entrytype='Receipt' and v_tbl_receivables.packagename<>'Starting Payment' then	
		
				if upper(p_dfm_invoicenumber_y_n)='Y' then
							update tbl_receivables
							set dfm_invoicenumber_y_n=p_dfm_invoicenumber_y_n,
								dfm_invoicenumber=p_dfm_invoicenumber,
								recordpushedtotally='1',
								receiptpushedtotally='1',
								financial_year=v_financialyear
							where orderno=p_invoiceno and isactive='1' and entrytype='Invoice'
								and tallyinvoicenumber is null;
				else
				
			/****************change 2.6 starts*************************/
			
		if right(v_financialyear,4)::int<=2025 then
			if v_tbl_account.product_type='2' then
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,6)='HO/TP/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='HO/TP/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
			else
				if exists (select * from public.mst_employer_credit where customer_account_id=v_tbl_account.id and is_active='1' and monthly_credit_amount_limit>0 and monthly_credit_percent_limit>0)then
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,7)='HO/WFM/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='HO/WFM/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
				else
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,7)='HO/SSE/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='HO/SSE/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
				end if;
			end if;
		else
			if v_tbl_account.product_type='2' then
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,3)='TP/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='TP/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
			else
					v_tallyinvoiceid:=coalesce((select max(tallyinvoiceid)from tbl_receivables where isactive='1' and financial_year=v_financialyear and left(tallyinvoicenumber,4)='ORP/'  and entrytype='Invoice'),0) +1;
					v_tallyinvoicenumber:='ORP/'||v_finyearsuffix||'/'||v_tallyinvoiceid;
			end if;
		end if;
			update tbl_receivables
			set tallyinvoiceid=v_tallyinvoiceid,
				tallyinvoicenumber=v_tallyinvoicenumber,
				financial_year=v_financialyear
			where orderno=p_invoiceno and isactive='1' and entrytype='Invoice' and tallyinvoicenumber is null;
			/**************change 2.6 ends***************************/
				end if;
		end if;	
		end if;	
		/************Change 1.2 ends here*********************************/	
	open v_rfc for
		select 5 as response;
		return v_rfc;
end if;
/****Update transactionid when Amount paid from Payment Gateway ends***************/
/*********Update status on Tally Integration*****************************/
if p_action='UpdateTallyIntegration' then
	update tbl_receivables
	set recordpushedtotally='1',
	recordpushedtotallyon=current_timestamp,
	tallymasterid=p_tallymasterid
	where invoiceno=p_invoiceno and isactive='1' 
		  and entrytype='Invoice';
	
	open v_rfc for
		select 6 as response;
		return v_rfc;
end if;
/*********Update status on Tally Integration ends*****************************/
	open v_rfc for
		select 9999 as response;
		return v_rfc;
-- exception when others then
-- 		open v_rfc for
-- 		select 0 as response;
-- 		return v_rfc;
end;
$BODY$;

ALTER FUNCTION public.uspprocessreceivables(character varying, numeric, bigint, bigint, character varying, character varying, character varying, integer, numeric, text, character varying, bigint, character varying, character varying, character varying, character varying, character varying, numeric, numeric, character varying, numeric, numeric, numeric, numeric, numeric, numeric, numeric, character varying, character varying, character varying, text, bigint, character varying, bigint, character varying, numeric, character varying, integer, integer, text, text, text, text, text, text, text, numeric, character varying, numeric, numeric, numeric, numeric, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying, integer, integer, numeric, numeric, character varying)
    OWNER TO stagingpayrolling_app;

