-- Table: public.tbl_monthlysalary

-- DROP TABLE IF EXISTS public.tbl_monthlysalary;

CREATE TABLE IF NOT EXISTS public.tbl_monthlysalary
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    mprmonth integer,
    mpryear integer,
    batchid character varying(150) COLLATE pg_catalog."default",
    createdby integer,
    createdon timestamp without time zone,
    createdbyip character varying(200) COLLATE pg_catalog."default",
    emp_code bigint,
    subunit integer,
    dateofleaving timestamp without time zone,
    totalleavetaken double precision,
    emp_name character varying(100) COLLATE pg_catalog."default",
    post_offered character varying(200) COLLATE pg_catalog."default",
    emp_address character varying(500) COLLATE pg_catalog."default",
    email character varying(100) COLLATE pg_catalog."default",
    mobilenum character varying(15) COLLATE pg_catalog."default",
    pancard character varying(10) COLLATE pg_catalog."default",
    gender character(10) COLLATE pg_catalog."default",
    dateofbirth date,
    fathername character varying(100) COLLATE pg_catalog."default",
    residential_address character varying(500) COLLATE pg_catalog."default",
    pfnumber character varying(30) COLLATE pg_catalog."default",
    uannumber character varying(30) COLLATE pg_catalog."default",
    lossofpay double precision,
    paiddays double precision,
    monthdays integer,
    ratebasic numeric(18,2),
    ratehra numeric(18,2),
    rateconv double precision,
    ratemedical double precision,
    ratespecialallowance numeric(18,2),
    fixedallowancestotalrate numeric(18,2),
    basic double precision,
    hra double precision,
    conv double precision,
    medical double precision,
    specialallowance double precision,
    fixedallowancestotal double precision,
    ratebasic_arr double precision,
    ratehra_arr double precision,
    rateconv_arr double precision,
    ratemedical_arr double precision,
    ratespecialallowance_arr double precision,
    fixedallowancestotalrate_arr double precision,
    incentive double precision,
    refund double precision,
    grossearning double precision,
    epf double precision,
    vpf double precision,
    employeeesirate double precision,
    tds double precision,
    loan double precision,
    lwf double precision,
    insurance numeric,
    mobile double precision,
    advance double precision,
    other double precision,
    grossdeduction double precision,
    netpay double precision,
    ac_1 double precision,
    ac_10 double precision,
    ac_2 double precision,
    ac21 double precision,
    employeresirate double precision,
    lwfcontr integer,
    ews numeric(10,2),
    gratuity numeric(10,2),
    recordtype text COLLATE pg_catalog."default",
    govt_bonus_opted character varying(1) COLLATE pg_catalog."default",
    govt_bonus_amt double precision,
    modifiedby integer,
    modifiedon timestamp without time zone,
    modifiedbyip character varying(200) COLLATE pg_catalog."default",
    is_special_category character varying(1) COLLATE pg_catalog."default",
    ctc2 double precision,
    batch_no character varying(150) COLLATE pg_catalog."default",
    actual_paid_ctc2 double precision,
    ctc double precision,
    ctc_paid_days double precision,
    ctc_actual_paid double precision,
    mobile_deduction double precision,
    salaryid bigint,
    bankaccountno character varying(30) COLLATE pg_catalog."default",
    ifsccode character varying(30) COLLATE pg_catalog."default",
    bankname character varying(250) COLLATE pg_catalog."default",
    bankbranch character varying(250) COLLATE pg_catalog."default",
    employeenps double precision,
    employernps double precision,
    insuranceamount double precision,
    familyinsurance double precision,
    issalarydownloaded character varying(1) COLLATE pg_catalog."default",
    remarks character varying(255) COLLATE pg_catalog."default",
    isarear character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    isarearprocessed character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    arearprocessmonth integer,
    arearprocessyear integer,
    arearprocessedby bigint,
    arearprocessedon timestamp without time zone,
    arearprocessedbyip character varying(200) COLLATE pg_catalog."default",
    employee_esi_incentive numeric(18,2),
    employer_esi_incentive numeric(18,2),
    total_esi_incentive numeric(18,2),
    account1_7q_dues numeric(18,2),
    account1_14b_dues numeric(18,2),
    account10_7q_dues numeric(18,2),
    account10_14b_dues numeric(18,2),
    account2_7q_dues numeric(18,2),
    account2_14b_dues numeric(18,2),
    account21_7q_dues numeric(18,2),
    account21_14b_dues numeric(18,2),
    pf_due_date date,
    pf_paid_date date,
    totalarear numeric(18,2),
    arearaddedmonths character varying(100) COLLATE pg_catalog."default",
    employee_esi_incentive_deduction numeric(18,2),
    employer_esi_incentive_deduction numeric(18,2),
    total_esi_incentive_deduction numeric(18,2),
    salaryindaysopted character varying(1) COLLATE pg_catalog."default",
    mastersalarydays integer,
    otherledgerarears numeric(18,2),
    otherledgerdeductions numeric(18,2),
    is_rejected bit(1) DEFAULT '0'::"bit",
    reject_reason character varying(500) COLLATE pg_catalog."default",
    rejected_on timestamp without time zone,
    rejected_by bigint,
    recordscreen character varying(30) COLLATE pg_catalog."default" DEFAULT 'Current Wages'::character varying,
    esi_incentive_processed bit(1),
    esi_incentive_processedon timestamp without time zone,
    esi_incentive_processedby bigint,
    esi_incentive_processedbyip character varying(200) COLLATE pg_catalog."default",
    esi_incentive_processmonth character varying(30) COLLATE pg_catalog."default",
    esi_incentive_processyear character varying(30) COLLATE pg_catalog."default",
    attendancemode character varying(30) COLLATE pg_catalog."default" DEFAULT 'MPR'::character varying,
    incrementarear double precision,
    incrementarear_basic double precision,
    incrementarear_hra double precision,
    incrementarear_allowance double precision,
    incrementarear_gross double precision,
    incrementarear_employeeesi double precision,
    incrementarear_employeresi double precision,
    lwf_employee numeric(18,2),
    lwf_employer numeric(18,2),
    othervariables numeric(18,2),
    otherdeductions numeric(18,2),
    bonus numeric(18,2) DEFAULT 0,
    otherledgerarearwithoutesi numeric(18,2) DEFAULT 0,
    otherbonuswithesi numeric(18,2) DEFAULT 0,
    salarydownloadedby bigint,
    salarydownloadedon timestamp without time zone,
    salarydownloadedbyip character varying(200) COLLATE pg_catalog."default",
    lwfstatecode integer,
    tdsadjustment double precision,
    is_disbersible bit(1),
    atds double precision,
    manual_tds_adjustment character varying(100) COLLATE pg_catalog."default",
    manual_remarks character varying(300) COLLATE pg_catalog."default",
    voucher_amount double precision DEFAULT 0.0,
    voucher_remarks character varying(300) COLLATE pg_catalog."default",
    salary_remarks character varying(300) COLLATE pg_catalog."default",
    voucher_date date,
    arearids character varying(200) COLLATE pg_catalog."default",
    hrgeneratedon character varying(100) COLLATE pg_catalog."default",
    transactionid bigint,
    disbursedledgerids character varying(500) COLLATE pg_catalog."default",
    security_amt numeric(18,2) DEFAULT 0,
    issalaryorliability character varying(1) COLLATE pg_catalog."default" DEFAULT 'S'::character varying,
    modification_comment character varying(100) COLLATE pg_catalog."default",
    disbursementmode character varying(30) COLLATE pg_catalog."default" DEFAULT 'Salary'::character varying,
    istaxapplicable bit(1) DEFAULT '1'::bit(1),
    tptype character varying(10) COLLATE pg_catalog."default" DEFAULT 'NonTP'::character varying,
    professionaltax numeric(18,2) DEFAULT 0,
    is_billable character varying(1) COLLATE pg_catalog."default" DEFAULT 'Y'::character varying,
    pfchallannumber character varying(30) COLLATE pg_catalog."default",
    esichallannumber character varying(30) COLLATE pg_catalog."default",
    lwfchallannumber character varying(30) COLLATE pg_catalog."default",
    ptchallannumber character varying(30) COLLATE pg_catalog."default",
    customtaxablecomponents json,
    customnontaxablecomponents json,
    payment_record_id bigint,
    ratecommission numeric(18,2),
    ratetransport_allowance numeric(18,2),
    ratetravelling_allowance numeric(18,2),
    rateleave_encashment numeric(18,2),
    rateovertime_allowance numeric(18,2),
    ratenotice_pay numeric(18,2),
    ratehold_salary_non_taxable numeric(18,2),
    ratechildren_education_allowance numeric(18,2),
    rategratuityinhand numeric(18,2),
    commission numeric(18,2),
    transport_allowance numeric(18,2),
    travelling_allowance numeric(18,2),
    leave_encashment numeric(18,2),
    overtime_allowance numeric(18,2),
    notice_pay numeric(18,2),
    hold_salary_non_taxable numeric(18,2),
    children_education_allowance numeric(18,2),
    gratuityinhand numeric(18,2),
    ratesalarybonus numeric(18,2),
    salarybonus numeric(18,2),
    attendanceid bigint,
    tea_allowance numeric(10,2) DEFAULT 0.0,
    unitname character varying(200) COLLATE pg_catalog."default",
    departmentname character varying(200) COLLATE pg_catalog."default",
    designationname character varying(200) COLLATE pg_catalog."default",
    pfapplicablecomponents numeric(18,2),
    esiapplicablecomponents numeric(18,2),
    isgroupinsurance character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    employerinsuranceamount numeric,
    perkamount numeric(18,2),
    charity_contribution_amount numeric(18,2) DEFAULT 0.0,
    rejected_by_username character varying(255) COLLATE pg_catalog."default",
    is_advice character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    mealvoucher numeric(10,2),
    multipayoutrequestid bigint DEFAULT 0,
    overtime numeric(18,2) DEFAULT 0,
    workflowappid bigint DEFAULT '-9999'::integer,
    is_workflow_approved character varying(1) COLLATE pg_catalog."default" DEFAULT 'Y'::character varying,
    tdsdeductionmonth character varying(10) COLLATE pg_catalog."default" DEFAULT 'current'::character varying,
    paymenttypeid integer,
    salaryjson text COLLATE pg_catalog."default",
    otherearningcomponents numeric(18,2) DEFAULT 0.0,
    CONSTRAINT tbl_monthlysalary_pk PRIMARY KEY (id),
    CONSTRAINT monthsal_uq UNIQUE (mprmonth, mpryear, batchid, emp_code, is_rejected, isarear, recordscreen, salaryid),
    CONSTRAINT tbl_monthlysalary_salaryid_fkey FOREIGN KEY (salaryid)
        REFERENCES public.empsalaryregister (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT tbl_monthlysalary_attendancemode_check CHECK (attendancemode::text = ANY (ARRAY['Ledger'::character varying::text, 'Manual'::character varying::text, 'MPR'::character varying::text])),
    CONSTRAINT tbl_monthlysalary_disbursementmode_check CHECK (disbursementmode::text = ANY (ARRAY['Salary'::character varying::text, 'Voucher'::character varying::text])),
    CONSTRAINT tbl_monthlysalary_isarear_check CHECK (isarear::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])),
    CONSTRAINT tbl_monthlysalary_isarearprocessed_check CHECK (isarearprocessed::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])),
    CONSTRAINT tbl_monthlysalary_issalaryorliability_check CHECK (issalaryorliability::text = ANY (ARRAY['S'::character varying::text, 'L'::character varying::text])),
    CONSTRAINT tbl_monthlysalary_is_workflow_approved_check CHECK (is_workflow_approved::text = ANY (ARRAY['Y'::character varying, 'N'::character varying]::text[])),
    CONSTRAINT tbl_monthlysalary_tdsdeductionmonth_check CHECK (tdsdeductionmonth::text = ANY (ARRAY['current'::character varying, 'next'::character varying]::text[]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.tbl_monthlysalary
    OWNER to payrollingdb;
-- Index: idx_hrgen_tbl_monthlysalary

-- DROP INDEX IF EXISTS public.idx_hrgen_tbl_monthlysalary;

CREATE INDEX IF NOT EXISTS idx_hrgen_tbl_monthlysalary
    ON public.tbl_monthlysalary USING brin
    (hrgeneratedon_todate("left"(hrgeneratedon::text, 11)))
    WITH (pages_per_range=128, autosummarize=False)
    TABLESPACE pg_default;
-- Index: idx_monyear_wages3

-- DROP INDEX IF EXISTS public.idx_monyear_wages3;

CREATE INDEX IF NOT EXISTS idx_monyear_wages3
    ON public.tbl_monthlysalary USING btree
    (emp_code ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: idx_tbl_monthlysalary_createdon_brin

-- DROP INDEX IF EXISTS public.idx_tbl_monthlysalary_createdon_brin;

CREATE INDEX IF NOT EXISTS idx_tbl_monthlysalary_createdon_brin
    ON public.tbl_monthlysalary USING brin
    (COALESCE(modifiedon, createdon))
    WITH (pages_per_range=128, autosummarize=False)
    TABLESPACE pg_default;
-- Index: idx_tblmonsal_arearids

-- DROP INDEX IF EXISTS public.idx_tblmonsal_arearids;

CREATE INDEX IF NOT EXISTS idx_tblmonsal_arearids
    ON public.tbl_monthlysalary USING btree
    (emp_code ASC NULLS LAST, arearids COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: idx_tblmonsal_codeyearmonbatch

-- DROP INDEX IF EXISTS public.idx_tblmonsal_codeyearmonbatch;

CREATE INDEX IF NOT EXISTS idx_tblmonsal_codeyearmonbatch
    ON public.tbl_monthlysalary USING btree
    (mpryear ASC NULLS LAST, mprmonth ASC NULLS LAST, emp_code ASC NULLS LAST, batchid COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: idx_tblmonsal_yearmon

-- DROP INDEX IF EXISTS public.idx_tblmonsal_yearmon;

CREATE INDEX IF NOT EXISTS idx_tblmonsal_yearmon
    ON public.tbl_monthlysalary USING btree
    (mpryear ASC NULLS LAST, mprmonth ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: tbl_monthlysalary_attid

-- DROP INDEX IF EXISTS public.tbl_monthlysalary_attid;

CREATE UNIQUE INDEX IF NOT EXISTS tbl_monthlysalary_attid
    ON public.tbl_monthlysalary USING btree
    (emp_code ASC NULLS LAST, attendanceid ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default
    WHERE is_rejected = '0'::"bit";
-- Index: uq_tblmonthly_salary

-- DROP INDEX IF EXISTS public.uq_tblmonthly_salary;

CREATE UNIQUE INDEX IF NOT EXISTS uq_tblmonthly_salary
    ON public.tbl_monthlysalary USING btree
    (mprmonth ASC NULLS LAST, mpryear ASC NULLS LAST, batchid COLLATE pg_catalog."default" ASC NULLS LAST, emp_code ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default
    WHERE is_rejected = '0'::"bit";

-- Trigger: trg_updatesalaryhistory

-- DROP TRIGGER IF EXISTS trg_updatesalaryhistory ON public.tbl_monthlysalary;

CREATE OR REPLACE TRIGGER trg_updatesalaryhistory
    BEFORE DELETE OR UPDATE 
    ON public.tbl_monthlysalary
    FOR EACH ROW
    EXECUTE FUNCTION public.update_salaryhistory();