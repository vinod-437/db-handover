-- FUNCTION: public.uspgetreceivables(character varying, text, text, character varying, bigint, character varying, character varying, character varying, character varying, character varying)

-- DROP FUNCTION IF EXISTS public.uspgetreceivables(character varying, text, text, character varying, bigint, character varying, character varying, character varying, character varying, character varying);

CREATE OR REPLACE FUNCTION public.uspgetreceivables(
	p_action character varying,
	p_fromdate text DEFAULT NULL::text,
	p_todate text DEFAULT NULL::text,
	p_search character varying DEFAULT ''::character varying,
	p_customeraccountid bigint DEFAULT '-9999'::integer,
	p_status character varying DEFAULT 'Pending'::character varying,
	p_invoiceno character varying DEFAULT ''::character varying,
	p_createdby character varying DEFAULT '-9999'::character varying,
	p_createdbyip character varying DEFAULT ''::character varying,
	p_rejectreason character varying DEFAULT ''::character varying)
    RETURNS refcursor
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
	declare v_rfc refcursor;
	v_employer employer%rowtype;
	v_cnt int:=0;
	begin
		/*************************************************************************************************
		Version Date			Change											Done_by
		1.0		28-Nov-2022		Initial Version									Shiv Kumar
		1.1		17-July-2023	Add GetAllReceivableDetailByCustomerID action	Parveen Kumar
		1.2		22-Sep-2023		round up received amount and trunc gst			Parveen Kumar
								 as requested by Deo Kumar
		1.3		18-Oct-2023		Add Billable Amount								Shiv Kumar
		**************************************************************************************************/

		select *
		into v_employer
		from public.employer where employerid=1 and active='1';

		if p_action='GetReceiptForTally' then
			open v_rfc for
			select   tallyinvoicenumber  DocumentNo,
					 to_char(dateofreceiving,'dd-mm-yyyy')DocumentDt,
					 'Service Receipt' DocumentType,
					mst_payment_ledger.tallyledgername as BankName, --json_response::jsonb->>'BANKNAME' BankName,
					netamountreceived BankAmount,
					json_response::jsonb->>'BANKTXNID' UTRNo,
					to_char( (case when paymentmethod = 'HDFC BANK' then to_date((json_response::jsonb->>'TXNDATE'),'yyyy-mm-dd hh:mi:ss') else (json_response::jsonb->>'TXNDATE')::date end),'dd-mm-yyyy') UTRDate,
					'TDS' TDSLedName,
					0 TDSLedAmount,
					service_name DocumentNarration,
					jsonb_build_object('PartyName',customeraccountname ,
				   'PartyAmt',netamountreceived ,'PartyCode',tbl_receivables.customeraccountid,
					'BillNo',invoiceno) as Partydetailslist
			from tbl_receivables inner join tbl_account 
			on tbl_receivables.customeraccountid=tbl_account.id
			inner join mst_payment_ledger on tbl_receivables.paymentmethod=mst_payment_ledger.paymentmethodname and mst_payment_ledger.isactive='1'
				where tbl_receivables.isactive='1'
				and tbl_receivables.status='Paid'
				and netamount>0
				and coalesce(tbl_receivables.receiptpushedtotally,'0')='0'
				and tallyinvoicenumber is not null and dateofreceiving is not null;
			return v_rfc;	
	end if;	
		/******************General Search************************************/
		if p_action='GetDataForTally' then
			open v_rfc for
			select      
				tallyinvoicenumber invoiceno,
				to_char(dateofreceiving,'dd-mm-yyyy') invoiceDt,	 -- to_char(invoiceDt,'dd-mm-yyyy') invoiceDt,			
				invoicetype, 
				customeraccountname customername, 
				customeraccountid customerCode,
				tbl_account.address AddressLine1,
				tbl_account.adress_ii AddressLine2,
				'' AddressLine3,
				'' AddressLine4,
				tbl_account.state StateName,
				tbl_account.pincode PinCode,
				'' ContactPerson, -- To be Added from contacts from CRM
				tbl_account.mobile MobileNo,
				tbl_account.email EmailID,
				tbl_account.ac_pan_no PANNo,
				tbl_account.ac_gstin_no GSTNo,
				tbl_receivables.id	orderno, 
				to_char(tbl_receivables.orderdate,'dd-mm-yyyy')  orderdate, 
				tbl_receivables.referenceno, 
				netamountreceived total_Invoice_Amount, 
				cgstamount CGST_Amt, 
				sgstamount SGST_Amt, 
				igstamount IGST_Amt,
				service_name service_Name, 
				netamount service_Amt,
				packagename ServiceDescLine1,
				'' ServiceDescLine2,
				'' ServiceDescLine3,
				'' ServiceDescLine4,
				'' ServiceDescLine5,
				'' ServiceDescLine6,
				'' ServiceDescLine7,
				'' ServiceDescLine8,
				'' ServiceDescLine9,
				'' ServiceDescLine10,
				servicechargeamount
			from tbl_receivables inner join tbl_account 
			on tbl_receivables.customeraccountid=tbl_account.id
				where tbl_receivables.isactive='1'
				and tbl_receivables.status='Paid'
				and tbl_receivables.recordpushedtotally='0'
				and entrytype='Invoice'
				and netamountreceived>0
				and tallyinvoicenumber is not null and dateofreceiving is not null
			order by tallyinvoiceid;

			return v_rfc;	
	end if;	
		if p_action='GetReceivableSummary' then
			open v_rfc for
			select case when tmp.istotalrow=0 then hsn_sac_number_tmp else '' end as hsn_sac_number,
			case when tmp.istotalrow=0 then tbl_account.accountname else 'Total' end as customeraccountname,
			case when tmp.istotalrow=0 then tbl_account.mobile else '' end as customermobilenumber,
			tmp.* from (
			SELECT coalesce(customeraccountid,-9999) customeraccountid,
			string_agg(distinct hsn_sac_number,',') hsn_sac_number_tmp,
					sum(numberofemployees) numberofemployees,
					sum(netamountreceived) netamountreceived,
					sum(servicechargeamount) servicechargeamount,
					sum(cgstamount) cgstamount,
					sum(sgstamount) sgstamount,
					sum(igstamount) igstamount,
					sum(netamount)  netamount,
				  grouping(customeraccountid) istotalrow
			FROM public.tbl_receivables
			where (
				customeraccountname ilike '%'||coalesce(p_search,'')||'%'
				or  customermobilenumber=coalesce(nullif(p_search,''),customermobilenumber) 
				)
			and dateofinitiation between to_date(p_fromdate,'dd/mm/yyyy') and to_date(p_todate,'dd/mm/yyyy')
			and status=p_status
				and tbl_receivables.isactive='1'
			group by rollup(customeraccountid)
				)tmp left join tbl_account
				on tmp.customeraccountid=tbl_account.id;

			return v_rfc;
		end if;	
		/******************General Search ends here************************************/	

		/******************Search By Customer************************************/	
		if p_action='GetReceivableSummaryByCustomerID' then
			open v_rfc for
			SELECT customeraccountid,string_agg(distinct customermobilenumber,',') customermobilenumber,
				string_agg(distinct customeraccountname,',') customeraccountname,
					string_agg(distinct hsn_sac_number,',') hsn_sac_number,
					sum(numberofemployees) numberofemployees,
					sum(netamountreceived) netamountreceived,
					sum(servicechargeamount) servicechargeamount,
					sum(cgstamount) cgstamount,
					sum(sgstamount) sgstamount,
					sum(igstamount) igstamount,
					sum(netamount) netamount
			FROM public.tbl_receivables
			where customeraccountid=p_customeraccountid
			and dateofinitiation between to_date(p_fromdate,'dd/mm/yyyy') and to_date(p_todate,'dd/mm/yyyy')
			and status=p_status
				and tbl_receivables.isactive='1'
			group by customeraccountid;

			return v_rfc;
		end if;	

		-- START [1.1] - Show All receivables.
		if p_action='GetAllReceivableDetailByCustomerID' then
			open v_rfc for
			SELECT 
				customeraccountid,customermobilenumber,customeraccountname,hsn_sac_number,numberofemployees, netamountreceived,servicechargepercent,servicechargeamount
				,gstmode,sgstpercent,sgstamount,cgstpercent,cgstamount,igstpercent,igstamount,netamount
				,to_char(dateofinitiation,'dd-Mon-yyyy') dateofinitiation
				,to_char(dateofreceiving,'dd-Mon-yyyy') dateofreceiving, source,
				case when is_verified::varchar='1' then 'Yes' else 'No' end is_verified,
				verifiedon::date verifiedon,
				transactionid,tbl_receivables.status,
				coalesce(nullif(tallyinvoicenumber,''),invoiceno) invoiceno
				,to_char(invoicedt,'dd-Mon-yyyy') invoicedt
				,invoicetype,orderno,to_char(orderdate,'dd-Mon-yyyy') orderdate
				,referenceno,service_name/*,recordpushedtotally,recordpushedtotallyon*/
				,(coalesce(sgstpercent,0)+coalesce(cgstpercent,0)+coalesce(igstpercent,0)) totalgstpercent
				,tbl_account.address as billingaddress, tbl_account.ac_gstin_no,left(tbl_account.ac_gstin_no,2) statecode
				,(netamount+coalesce(servicechargeamount,0)) gstbaseamount
				,packagename
				,to_char(case when tbl_receivables.status='Paid' then coalesce(mdified_on,createdon) else createdon end  at time zone 'UTC' at time zone 'Asia/Kolkata','dd Mon yyyy, hh:mi AM') trantime
				,to_char(case when tbl_receivables.status='Paid' then coalesce(mdified_on,createdon) else createdon end  ,'Mon-yyyy') tranmonth
				,json_response
				,paymentmethod
				,coalesce(tallyinvoicenumber,'') tallyinvoicenumber
				,case when coalesce(recordpushedtotally,'0')='1'::bit then 'Y' else 'N' end as Invoicesenttotally
				,to_char(recordpushedtotallyon,'dd-Mon-yyyy hh24:mi') as Invoicesenttotallyon
				,case when coalesce(receiptpushedtotally,'0')='1'::bit then 'Y' else 'N' end as receiptsenttotally
				,to_char(receiptpushedtotallyon,'dd-Mon-yyyy hh24:mi') as receiptsenttotallyon
				,tbl_receivables.product_type,tbl_receivables.entrytype
			FROM public.tbl_receivables 
			inner join tbl_account on tbl_receivables.customeraccountid=tbl_account.id 
			where 
				customeraccountid = coalesce(nullif(p_customeraccountid, -9999), customeraccountid)
				and case when tbl_receivables.status='Paid' then dateofreceiving else dateofinitiation end  between case when p_fromdate is null then case when tbl_receivables.status='Paid' then dateofreceiving else dateofinitiation end  else to_date(p_fromdate,'dd/mm/yyyy') end and case when p_todate is null then case when tbl_receivables.status='Paid' then dateofreceiving else dateofinitiation end  else to_date(p_todate,'dd/mm/yyyy') end
				and tbl_receivables.status = coalesce(nullif(p_status,'All'),tbl_receivables.status)
				AND (tbl_receivables.invoiceno = p_invoiceno OR tbl_receivables.tallyinvoicenumber = p_search OR tbl_receivables.customeraccountname ilike '%'||coalesce(p_search, '')||'%')
			order by coalesce(mdified_on,createdon) desc;

			return v_rfc;
		end if;
		-- END [1.1] - Show All receivables.

		if p_action='GetReceivableDetailByCustomerID' then
			open v_rfc for
			SELECT 
				customeraccountid,customermobilenumber,customeraccountname||' ['||tbl_account.state||']' customeraccountname,hsn_sac_number,numberofemployees, round(netamountreceived::numeric) netamountreceived,servicechargepercent,trunc(servicechargeamount::numeric,2) servicechargeamount
				,gstmode,sgstpercent,trunc(sgstamount::numeric,2) sgstamount,cgstpercent,trunc(cgstamount::numeric,2) cgstamount,igstpercent,trunc(igstamount::numeric,2) igstamount,netamount
				,to_char(dateofinitiation,'dd-Mon-yyyy') dateofinitiation
				,to_char(dateofreceiving,'dd-Mon-yyyy') dateofreceiving, source,
				case when is_verified::varchar='1' then 'Yes' else 'No' end is_verified,
				verifiedon::date verifiedon,
				transactionid,tbl_receivables.status,
				coalesce(nullif(tallyinvoicenumber,''),invoiceno) invoiceno
				,to_char(invoicedt,'dd-Mon-yyyy') invoicedt
				,invoicetype,orderno,to_char(orderdate,'dd-Mon-yyyy') orderdate
				,referenceno,service_name/*,recordpushedtotally,recordpushedtotallyon*/
				,(coalesce(sgstpercent,0)+coalesce(cgstpercent,0)+coalesce(igstpercent,0)) totalgstpercent
				,tbl_account.address as billingaddress, tbl_account.ac_gstin_no,left(tbl_account.ac_gstin_no,2) statecode
				,(netamount+coalesce(servicechargeamount,0)) gstbaseamount
				,packagename
				,to_char(case when tbl_receivables.status='Paid' then coalesce(mdified_on,createdon) else createdon end   at time zone 'UTC' at time zone 'Asia/Kolkata','dd Mon yyyy, hh:mi AM') trantime
				,to_char(case when tbl_receivables.status='Paid' then coalesce(mdified_on,createdon) else createdon end   ,'Mon-yyyy') tranmonth
				,json_response
				,case when packagename='Starting Payment' then coalesce(paymentmethod,'HDFC Manual') else paymentmethod end
				,coalesce(tallyinvoicenumber,'') tallyinvoicenumber
				,case when coalesce(recordpushedtotally,'0')='1'::bit then 'Y' else 'N' end as Invoicesenttotally
				,to_char(recordpushedtotallyon,'dd-Mon-yyyy hh24:mi') as Invoicesenttotallyon
				,case when coalesce(receiptpushedtotally,'0')='1'::bit then 'Y' else 'N' end as receiptsenttotally
				,to_char(receiptpushedtotallyon,'dd-Mon-yyyy hh24:mi') as receiptsenttotallyon
				,'Generated' invgenerationstatus
				, tbl_receivables.id receivables_id
				,coalesce(mdified_on,createdon) sortcolumn
				,trunc(round(netamountreceived::numeric)-netamountreceived::numeric,2) as shortandaccess
				,tbl_receivables.product_type,tbl_receivables.entrytype
			FROM public.tbl_receivables 
			inner join tbl_account on tbl_receivables.customeraccountid=tbl_account.id 
			where 
				customeraccountid = coalesce(nullif(p_customeraccountid, -9999), customeraccountid)
				and case when tbl_receivables.status='Paid' then dateofreceiving else dateofinitiation end  between case when p_fromdate is null then case when tbl_receivables.status='Paid' then dateofreceiving else dateofinitiation end  else to_date(p_fromdate,'dd/mm/yyyy') end and case when p_todate is null then case when tbl_receivables.status='Paid' then dateofreceiving else dateofinitiation end  else to_date(p_todate,'dd/mm/yyyy') end
				and tbl_receivables.status = coalesce(nullif(p_status,'All'),tbl_receivables.status) 
				AND ((tbl_receivables.paymentmethod IS NOT NULL OR tbl_receivables.paymentmethod <> '') OR p_status = 'Outstanding' or packagename='Starting Payment')
				AND (tbl_receivables.invoiceno = p_invoiceno OR tbl_receivables.tallyinvoicenumber = p_search OR tbl_receivables.customeraccountname ilike '%'||coalesce(p_search, '')||'%')
				AND tbl_receivables.isactive = '1'
			
			UNION ALL
				select coalesce(tblrec.customeraccountid,tblpay.customeraccountid) customeraccountid,
					ta.mobile customermobilenumber,
					ta.accountname||' ['||ta.state||']' customeraccountname,
					'998514' hsn_sac_number,
					0 numberofemployees, 
					round((((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)*(1+coalesce(tr1.ratevalue,tr2.ratevalue)/100.00)*(1+case when upper(trim(v_employer.state))=upper(trim(ta.state)) then coalesce(tr3.ratevalue,0)+coalesce(tr4.ratevalue,0) else coalesce(tr5.ratevalue,0) end/100))::numeric)
					netamountreceived,
					coalesce(tr1.ratevalue,tr2.ratevalue) servicechargepercent,
					trunc((((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)*coalesce(tr1.ratevalue,tr2.ratevalue)/100.00)::numeric,2) servicechargeamount,
					case when upper(trim(v_employer.state))=upper(trim(ta.state)) then 'Local' else 'Interstate' end gstmode,
					case when upper(trim(v_employer.state))=upper(trim(ta.state)) then tr3.ratevalue else 0 end as sgstpercent,
					trunc(((case when upper(trim(v_employer.state))=upper(trim(ta.state)) then tr3.ratevalue/100.00 else 0 end)*((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)*(1+coalesce(tr1.ratevalue,tr2.ratevalue)/100.00))::numeric,2) sgstamount,
					case when upper(trim(v_employer.state))=upper(trim(ta.state)) then tr4.ratevalue else 0 end as  cgstpercent,
					trunc(((case when upper(trim(v_employer.state))=upper(trim(ta.state)) then tr4.ratevalue/100.00 else 0 end)*((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)*(1+coalesce(tr1.ratevalue,tr2.ratevalue)/100.00))::numeric,2) cgstamount,
					case when upper(trim(v_employer.state))=upper(trim(ta.state)) then 0 else tr5.ratevalue end as igstpercent,
					trunc(((case when upper(trim(v_employer.state))=upper(trim(ta.state)) then  0 else tr5.ratevalue/100.00 end)*((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)*(1+coalesce(tr1.ratevalue,tr2.ratevalue)/100.00))::numeric,2) igstamount,
					((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)::numeric(18,2)netamount
					,'' dateofinitiation
					,'' dateofreceiving, 'Web' source,
					'No'  is_verified,
					null::date verifiedon,
					'-9999' transactionid,
					'' status,
					'' invoiceno
					,to_char(current_date,'dd-Mon-yyyy') invoicedt
					,'Service Invoice' invoicetype
					,'' orderno
					,'' orderdate
					,'' referenceno,
					'Manpower Service' service_name
					,case when upper(trim(v_employer.state))=upper(trim(ta.state)) then  (coalesce(tr4.ratevalue,0)+coalesce(tr3.ratevalue,0)) else coalesce(tr5.ratevalue,0) end totalgstpercent
					,ta.address as billingaddress, ta.ac_gstin_no,left(ta.ac_gstin_no,2) statecode
					,0 gstbaseamount
					,'' packagename
					,'' trantime
					,'' tranmonth
					,'' json_response
					,null paymentmethod
					,null tallyinvoicenumber
					,'N' as Invoicesenttotally
					,null::text as Invoicesenttotallyon
					,'N' as receiptsenttotally
					,null as receiptsenttotallyon
					,'NotGenerated' invgenerationstatus
					, 0 receivables_id
					,coalesce(tblrec.mdified_on,tblrec.createdon) sortcolumn
					,trunc(round((((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)*(1+coalesce(tr1.ratevalue,tr2.ratevalue)/100.00)*(1+case when upper(trim(v_employer.state))=upper(trim(ta.state)) then coalesce(tr3.ratevalue,0)+coalesce(tr4.ratevalue,0) else coalesce(tr5.ratevalue,0) end/100))::numeric)-((((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*-1)*(1+coalesce(tr1.ratevalue,tr2.ratevalue)/100.00)*(1+case when upper(trim(v_employer.state))=upper(trim(ta.state)) then coalesce(tr3.ratevalue,0)+coalesce(tr4.ratevalue,0) else coalesce(tr5.ratevalue,0) end/100))::numeric),2) shortandaccess
					,tblrec.product_type product_type,tblrec.entrytype entrytype
				from tbl_account ta 
				inner join 
				(
					select customeraccountid, sum(netamount) netamountreceived
					,null::timestamp without time zone mdified_on,null::timestamp without time zone createdon
					,tr.entrytype,tr.product_type
					from tbl_account ta 
					inner join tbl_receivables tr on ta.id=tr.customeraccountid and ta.status='1' and ta.pause_inactive_status='Active' and tr.isactive='1' and tr.status='Paid' and ta.id=coalesce(nullif(-9999,-9999),ta.id)
					and tallyinvoicenumber is not null and dateofreceiving is not null
					and tr.entrytype=case when tr.product_type='2' then 'Receipt' else tr.entrytype end
					group by customeraccountid,tr.entrytype,tr.product_type
				 ) tblrec on ta.id=tblrec.customeraccountid
				 left join 
				 (
					select op.customeraccountid, sum(ts.grossearning+coalesce(ts.employeresirate)+coalesce(ts.ac_1,0)+coalesce(ts.ac_10,0)+coalesce(ts.ac_2,0)+coalesce(ts.ac21,0)+coalesce(lwf_employer,0)+coalesce(case when ts.loan<>0 then ts.loan*-1 when ts.advance<>0 then ts.advance*-1 else 0 end,0)-coalesce(ts.otherledgerdeductions,0)) netamountpaid
					from openappointments op 
					inner join tbl_monthlysalary ts on op.emp_code=ts.emp_code and ts.issalaryorliability='S' and ts.is_rejected='0' and op.recordsource='HUBTPCRM' and op.customeraccountid=coalesce(nullif(-9999,-9999),op.customeraccountid) and op.customeraccountid is not null
					inner join banktransfers bt on ts.emp_code=bt.emp_code and ts.mprmonth=bt.salmonth and ts.mpryear=bt.salyear and ts.batch_no=bt.batchcode and coalesce(bt.isrejected,'0')<>'1'
					group by op.customeraccountid
				 ) tblpay
				 on tblrec.customeraccountid=tblpay.customeraccountid::bigint
				 left join tbl_ratemaster tr1 on ta.id=tr1.customeraccountid and tr1.ratemastername='Service Charge' and tr1.isactive='1'
				 left join tbl_ratemaster tr2 on tr2.customeraccountid is null and tr2.ratemastername='Service Charge' and tr2.isactive='1'
				 left join tbl_ratemaster tr3 on tr3.ratemastername='SGST' and tr3.isactive='1'
				 left join tbl_ratemaster tr4 on tr4.ratemastername='CGST' and tr4.isactive='1'
				 left join tbl_ratemaster tr5 on tr5.ratemastername='IGST' and tr5.isactive='1'
				 where (coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))<0
				 and p_status='Outstanding'
				 order by sortcolumn desc;
			return v_rfc;
		end if;
		if p_action='GetReceivableDetailByInvoiceNumber' then
			open v_rfc for
			SELECT customeraccountid,customermobilenumber,customeraccountname,hsn_sac_number,numberofemployees, netamountreceived,servicechargepercent,servicechargeamount
			,gstmode,sgstpercent,sgstamount,cgstpercent,cgstamount,igstpercent,igstamount,netamount
			,to_char(dateofinitiation,'dd-Mon-yyyy') dateofinitiation
			,to_char(dateofreceiving,'dd-Mon-yyyy') dateofreceiving, source,
			case when is_verified::varchar='1' then 'Yes' else 'No' end is_verified,
			verifiedon::date verifiedon,
			transactionid,tbl_receivables.status,coalesce(nullif(tallyinvoicenumber,''),invoiceno) invoiceno
					,to_char(invoicedt,'dd-Mon-yyyy') invoicedt
					,invoicetype,orderno,to_char(orderdate,'dd-Mon-yyyy') orderdate
					,referenceno,service_name/*,recordpushedtotally,recordpushedtotallyon*/
					,(coalesce(sgstpercent,0)+coalesce(cgstpercent,0)+coalesce(igstpercent,0)) totalgstpercent
					,tbl_account.address as billingaddress, tbl_account.ac_gstin_no,left(tbl_account.ac_gstin_no,2) statecode
					,(netamount+coalesce(servicechargeamount,0)) gstbaseamount
					,packagename
					,to_char(createdon at time zone 'UTC' at time zone 'Asia/Kolkata','dd Mon yyyy, hh:mi AM') trantime
					,to_char(createdon,'Mon-yyyy') tranmonth
					,json_response
					,paymentmethod
			FROM public.tbl_receivables inner join tbl_account on tbl_receivables.customeraccountid=tbl_account.id 
			where customeraccountid=coalesce(nullif(p_customeraccountid,-9999),customeraccountid)
			and invoiceno=p_invoiceno
			and tbl_receivables.isactive='1'
			order by tbl_receivables.id desc;

			return v_rfc;
		end if;		
		/******************Search By Customer ends here************************************/
		if p_action='GetOneMonthSubscription' then
			open v_rfc for
			select customeraccountid::text customeraccountid,employees::text employees,numberofemployees::text numberofemployees--,totalamount 
			,(
				select array_to_json(array_agg(row_to_json(X) )) FROM   
				(
					select '1' planid,'1 Month Payroll Amount' plandesc,totalamount::text amount,numberofemployees::text workers
					union all
					 	select '2' planid,'3 Month''s Payroll Amount' plandesc,(totalamount*3)::text amount,numberofemployees::text workers
					union all
					 	select '3' planid,'6 Month''s Payroll Amount' plandesc,(totalamount*6)::text amount,numberofemployees::text workers
-- 					union all
-- 					 	select '4' planid,'9 Month''s Payroll Amount' plandesc,(totalamount*9)::text amount,numberofemployees::text workers
					union all
					 	select '5' planid,'12 Month''s Payroll Amount' plandesc,(totalamount*12)::text amount,numberofemployees::text workers
-- 					union all
-- 					 	select '6' planid,'Custom Plan' plandesc,1000::text amount,numberofemployees::text workers
				) as X
			)::jsonb as plandesc
			,'100' as customplanamount
			--,'[{planid:1,plandesc:1 Month Payroll Amount,amount:'||totalamount||',workers:1},{planid:2,plandesc:3 Month Payroll Amount,amount:'||totalamount*3||',workers:1},{planid:3,plandesc:6 Month Payroll Amount,amount:'||totalamount*6||',workers:1},{planid:4,plandesc:9 Month Payroll Amount,amount:'||totalamount*9||',workers:1},{planid:5,plandesc:12 Month Payroll Amount,amount:'||totalamount*12||',workers:1}]'::text as plandesc			
			from (
			select o.customeraccountid,
					string_agg(o.emp_code::text,',') as employees,
					count(*) numberofemployees,
					sum(ctc) totalamount
					
-- 					sum(ctc) onemonthsubscription,
-- 					sum(ctc)*3 threemonthsubscription,
-- 					sum(ctc)*6 sixmonthsubscription,
-- 					sum(ctc)*9 ninemonthsubscription,
-- 					sum(ctc)*12 twelvemonthsubscription,
			from (select o.customeraccountid,o.emp_code,e.ctc,row_number() over (partition by o.emp_code order by e.id desc) rn
			from openappointments o inner join empsalaryregister e
			on o.emp_id=e.appointment_id
			and o.converted='Y' and o.appointment_status_id=11
			--and (coalesce(o.left_flag,'N')<>'Y') and e.isactive='1'
			and (o.dateofrelieveing is null or o.dateofrelieveing>=(date_trunc('month',current_date))::date)
			and o.customeraccountid=p_customeraccountid
			)o where rn=1
			group by o.customeraccountid
				)tmp;
			return v_rfc;
		end if;
		/****************************|| START - Billing and Receivables Dashboard ||****************************/
		if p_action = 'BillingDashboard' OR p_action = 'ReceivablesDashboard' then
            open v_rfc for
				SELECT 
					count(distinct customeraccountid) total_employers_count_billing
					, SUM(netamountreceived) total_employers_amount_billing
					, SUM(servicechargeamount) total_service_charge_billing
					, SUM(netamount) total_employers_billing
					, SUM(igstamount+sgstamount+cgstamount) total_gst_billing
					, count(distinct CASE WHEN recordpushedtotally = '1' THEN customeraccountid ELSE null END) total_employers_count_receivables
					, SUM(CASE WHEN recordpushedtotally='1' THEN netamountreceived ELSE 0 END) total_employers_amount_receivables
					, SUM(CASE WHEN recordpushedtotally='1' THEN servicechargeamount ELSE 0 END) total_service_charge_receivables
					, SUM(CASE WHEN recordpushedtotally='1' THEN netamount ELSE 0 END) total_employers_billing_receivables
					, SUM(CASE WHEN recordpushedtotally='1' THEN igstamount+sgstamount+cgstamount ELSE 0 END) total_gst_receivables
				FROM public.tbl_receivables
				WHERE 
					isactive = '1' AND
					status = COALESCE(NULLIF(p_status, 'All'),status) AND 
					dateofinitiation BETWEEN to_date(p_fromdate,'dd/mm/yyyy') AND to_date(p_todate,'dd/mm/yyyy');
            return v_rfc;
        end if; 
		/****************************|| END - Billing and Receivables Dashboard ||****************************/

		IF p_action='GetCreditAvailable' THEN
			IF EXISTS(SELECT * FROM mst_employer_credit WHERE customer_account_id=p_customeraccountid and is_active = '1') THEN
				OPEN v_rfc FOR
				SELECT 'Y' AS creditstatus, monthly_credit_amount_limit creditavailable, monthly_credit_percent_limit creditpercent 
				FROM mst_employer_credit 
				WHERE customer_account_id = p_customeraccountid and is_active = '1';
			ELSE
				OPEN v_rfc FOR
				SELECT 'N' AS creditstatus, 0 creditavailable;
			END IF;

			RETURN v_rfc;
		END IF;	
		if p_action='RejectInvoice' then
			if (select status from tbl_receivables where customeraccountid=p_customeraccountid and invoiceno=p_invoiceno)='Paid' then
				
				open v_rfc for
				select 'Invoice cannot be rejected. It is already Paid' as msg;
				return v_rfc;
			end if;
			update tbl_receivables
			set mdified_by=nullif(p_createdby,'-9999')::int,
				mdified_on=current_timestamp,
				mdified_byip=p_createdbyip,
				isactive='0',
				remarks=p_rejectreason
			where customeraccountid=p_customeraccountid
				and invoiceno=p_invoiceno
				and status<>'Paid';
			get diagnostics v_cnt=row_count;
			open v_rfc for
			select v_cnt::text|| ' Invoice Rejected.' as msg;
			return v_rfc;
		end if;
		if p_action='GetOutstandingInfo' then
		open v_rfc for
			select 	tblrec.customeraccountid,(coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))::numeric(18,2) balance,
					tbl_account.accountname, tbl_account.mobile, tbl_account.state, tbl_account.city,tbl_account.account_contact_name,tbl_account.ac_gstin_no,tbl_account.ac_pan_no, tbl_account.vpa_number, tbl_account.margin_type,
					(((coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))*(1+coalesce(trm1.ratevalue,trm2.ratevalue)/100.0))*(1+case when upper(trim(v_employer.state))=upper(trim(tbl_account.state)) then coalesce(trm3.ratevalue,0)+coalesce(trm4.ratevalue,0) else coalesce(trm5.ratevalue,0) end/100.0))::numeric(18,2) billableamount
				from (
				select customeraccountid,
			  		sum(netamount) netamountreceived
			 	from tbl_account ta inner join tbl_receivables tr
			  		on ta.id=tr.customeraccountid
 			  		and ta.status='1' and ta.pause_inactive_status='Active'
 			  		and tr.isactive='1' 
 			  		and tr.status='Paid'
					and ta.id=coalesce(nullif(p_customeraccountid,-9999),ta.id)
			 		group by customeraccountid
			 ) tblrec
			 left join 
			 (
				 	select op.customeraccountid,
						sum(ts.grossearning+coalesce(ts.employeresirate)+coalesce(ts.ac_1,0)+coalesce(ts.ac_10,0)+coalesce(ts.ac_2,0)+coalesce(ts.ac21,0)+coalesce(lwf_employer,0)+coalesce(case when ts.loan<>0 then ts.loan*-1 when ts.advance<>0 then ts.advance*-1 else 0 end,0)) netamountpaid
			 		from openappointments op inner join tbl_monthlysalary ts
				 		on op.emp_code=ts.emp_code
				 		and ts.issalaryorliability='S'
						and ts.is_rejected='0'
				 		and op.recordsource='HUBTPCRM'
					and op.customeraccountid=coalesce(nullif(p_customeraccountid,-9999),op.customeraccountid)
				 and op.customeraccountid is not null
-- 				 inner join banktransfers bt
-- 				 on ts.emp_code=bt.emp_code
-- 				 and ts.mprmonth=bt.salmonth
-- 				 and ts.mpryear=bt.salyear
-- 				 and ts.batch_no=bt.batchcode
-- 				 and coalesce(bt.isrejected,'0')<>'1'
			 		group by op.customeraccountid
			 ) tblpay
			 on tblrec.customeraccountid=tblpay.customeraccountid::bigint
			 left join  public.tbl_account on tblrec.customeraccountid=tbl_account.id
			 /**********************change 1.3 starts***************************************************/
			 left join tbl_ratemaster trm1 on trm1.customeraccountid=tblrec.customeraccountid and trm1.ratemastername='Service Charge' and trm1.isactive='1'
			 left join tbl_ratemaster trm2 on trm2.customeraccountid is null and trm2.ratemastername='Service Charge' and trm2.isactive='1'
			 left join tbl_ratemaster trm3 on trm3.ratemastername='CGST' and trm3.isactive='1'
			 left join tbl_ratemaster trm4 on trm4.ratemastername='SGST' and trm4.isactive='1'
			 left join tbl_ratemaster trm5 on trm5.ratemastername='IGST' and trm5.isactive='1'
			 /**********************change 1.3 ends***************************************************/
			 where (coalesce(tblrec.netamountreceived,0)-(coalesce(tblpay.netamountpaid,0)))::numeric(18,2)<0;
			 return v_rfc;
		end if;
		if p_action='GetDataForPayrollingSynch' then
		open v_rfc for
		select id::text,
				customeraccountid::text,
				customermobilenumber::character varying(15),
				customeraccountname::character varying(200),
				hsn_sac_number::character varying(30),
				coalesce(numberofemployees,0)::text numberofemployees,
				netamountreceived::text,
				servicechargepercent::text,
				servicechargeamount::text,
				gstmode::character varying(40),
				sgstpercent::text,
				sgstamount::text,
				cgstpercent::text,
				cgstamount::text,
				igstpercent::text,
				igstamount::text,
				netamount::text,
				to_char(coalesce(dateofinitiation,'1900-01-01'),'yyyy-mm-dd')::text dateofinitiation,
				to_char(coalesce(dateofreceiving,'1900-01-01'),'yyyy-mm-dd')::text dateofreceiving,
				source::character varying(50),
				coalesce(is_verified,'0')::varchar(1) is_verified,
				coalesce(verifiedbyempcode,-9999)::text verifiedbyempcode,
				to_char(coalesce(verifiedon,'1900-01-01 00:00:00'),'yyyy-mm-dd hh:mi:ss')::text verifiedon,
				verifiedbyip::character varying(150),
				transactionid::character varying(100),
				status::character varying(20),
				invoiceno::character varying(100),
				to_char(coalesce(invoicedt,'1900-01-01'),'yyyy-mm-dd')::text invoicedt,
				invoicetype::character varying(100),
				orderno::character varying(100),
				to_char(coalesce(orderdate,'1900-01-01'),'yyyy-mm-dd')::text orderdate,
				referenceno::character varying(100),
				contractids::character varying(400),
				contractname::character varying(200),
				service_name::character varying(100),
				paymentmethod::character varying(100),
				coalesce(created_by,-9999)::text created_by,
				to_char(coalesce(createdon,'1900-01-01 00:00:00'),'yyyy-mm-dd hh:mi:ss')::text createdon,
				createdbyip::character varying(30),
				coalesce(mdified_by,-9999)::text mdified_by,
				to_char(coalesce(mdified_on,'1900-01-01 00:00:00'),'yyyy-mm-dd hh:mi:ss')::text mdified_on,
				mdified_byip::character varying(30),
				coalesce(isactive,'0')::varchar(1) isactive,
				coalesce(recordpushedtotally,'0')::varchar(1) recordpushedtotally,
				to_char(coalesce(recordpushedtotallyon,'1900-01-01 00:00:00'),'yyyy-mm-dd hh:mi:ss')::text recordpushedtotallyon,
				packagename::character varying(100),
				json_response::text,
				coalesce(tallyinvoiceid,-9999)::text tallyinvoiceid,
				tallymasterid::character varying(30),
				coalesce(receiptpushedtotally,'0')::varchar(1) receiptpushedtotally,
				to_char(coalesce(receiptpushedtotallyon,'1900-01-01 00:00:00'),'yyyy-mm-dd hh:mi:ss')::text receiptpushedtotallyon,
				appsource::character varying(30),
				senttogateway::character varying(1),
				opscrmticketgenerated::character varying(1),
				tallyinvoicenumber::character varying(100),
				financial_year::character varying(9),
				coalesce(tranexpiryminutes,0)::text tranexpiryminutes,
				to_char(coalesce(paymentmethodupdatetime,'1900-01-01 00:00:00'),'yyyy-mm-dd hh:mi:ss')::text paymentmethodupdatetime,
				credit_applicable::character varying(1),
				coalesce(credit_percent,0.00)::text credit_percent,
				credit_used::character varying(1),
				to_char(coalesce(credit_used_date,'1900-01-01 00:00:00'),'yyyy-mm-dd hh:mi:ss')::text credit_used_date,
				--coalesce(credit_amount_used,0.00)::text credit_amount_used,
				coalesce(creditmonth,0)::text creditmonth,
				coalesce(credityear,0)::text credityear,
				remarks::character varying(100),
				product_type::character varying(200),
				entrytype::character varying(10)	
			from tbl_receivables
		where customeraccountid=p_customeraccountid 
			and product_type='2';
		return v_rfc;
		end if;
		
	end;
$BODY$;

ALTER FUNCTION public.uspgetreceivables(character varying, text, text, character varying, bigint, character varying, character varying, character varying, character varying, character varying)
    OWNER TO payrollingdb;

