-- Table: public.empsalaryregister

-- DROP TABLE IF EXISTS public.empsalaryregister;

CREATE TABLE IF NOT EXISTS public.empsalaryregister
(
    id integer NOT NULL DEFAULT nextval('empsalaryregister_seq'::regclass),
    finyear character varying(10) COLLATE pg_catalog."default",
    appointment_id integer NOT NULL,
    designation character varying(100) COLLATE pg_catalog."default",
    locationtype character varying(30) COLLATE pg_catalog."default",
    salminwagesctgid integer,
    salctgid integer,
    minimumwagesalary numeric(18,4),
    monthlyofferedpackage numeric(18,4),
    basic numeric(18,2),
    hra numeric(18,2),
    allowances numeric(18,2),
    gross numeric(18,2),
    employerepfrate numeric(18,4),
    employeresirate numeric(18,4),
    employernpsrate numeric(18,4),
    employeeepfrate numeric(18,4),
    employeeesirate numeric(18,4),
    employeenpsrate numeric(18,4),
    verificationstatus character varying(10) COLLATE pg_catalog."default",
    salaryinhand numeric(18,2),
    ctc numeric(18,2),
    verifiedby integer,
    verifiedon timestamp without time zone,
    isactive bit(1),
    createdby integer,
    createddate timestamp without time zone,
    createdbyip character varying(200) COLLATE pg_catalog."default",
    modifiedby integer,
    modifiedon timestamp without time zone,
    modifiedbyip character varying(200) COLLATE pg_catalog."default",
    optedinsurance character(1) COLLATE pg_catalog."default",
    insuranceamount numeric(10,2),
    familymemberscovered integer,
    familyinsuranceamount numeric(10,2),
    ews numeric(10,2),
    gratuity numeric(10,2),
    basicoption integer,
    salarydays integer,
    salaryindaysopted character varying(1) COLLATE pg_catalog."default",
    bonus double precision,
    conveyance_allowance double precision,
    medical_allowance double precision,
    vpfemployee double precision,
    taxes double precision,
    govt_bonus_opted character varying(1) COLLATE pg_catalog."default",
    govt_bonus_amt double precision,
    special_allowance double precision,
    is_special_category character varying(1) COLLATE pg_catalog."default",
    ct2 double precision,
    revised character varying(1) COLLATE pg_catalog."default",
    minwagesctgname character varying(1000) COLLATE pg_catalog."default",
    revisiondate date,
    remarks character varying(500) COLLATE pg_catalog."default",
    pfcapapplied character varying(1) COLLATE pg_catalog."default" DEFAULT 'Y'::character varying,
    effectivefrom date,
    effectiveto date,
    taxupdatedon timestamp without time zone,
    taxupdatedby bigint,
    taxupdatedbyip character varying(200) COLLATE pg_catalog."default",
    islwfstate character varying(1) COLLATE pg_catalog."default",
    lwfstatecode integer,
    employeelwf numeric(10,2),
    employerlwf numeric(10,2),
    lwfdeductionmonths character varying(50) COLLATE pg_catalog."default",
    isesiexceptionalcase character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    esiapplicabletilldate date,
    esicexceptionmessage character varying(150) COLLATE pg_catalog."default",
    isattendancerequired character varying(1) COLLATE pg_catalog."default" DEFAULT 'Y'::character varying,
    salarygenerationbase character varying(30) COLLATE pg_catalog."default",
    generatedbycustomeraccountid bigint,
    modifiedbycustomeraccountid bigint,
    leavetemplateid bigint,
    leavetemplatetext text COLLATE pg_catalog."default",
    employergratuity double precision,
    professionaltax numeric(18,2) DEFAULT 0,
    ptid integer,
    timecriteria character varying(30) COLLATE pg_catalog."default",
    salaryhours numeric(8,4),
    salarysetupcriteria character varying(10) COLLATE pg_catalog."default",
    dynamiccomponent text COLLATE pg_catalog."default",
    employergratuityopted character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    salarysetupmode character varying(30) COLLATE pg_catalog."default" DEFAULT 'Advance'::character varying,
    commission numeric(18,2),
    transport_allowance numeric(18,2),
    travelling_allowance numeric(18,2),
    leave_encashment numeric(18,2),
    overtime_allowance numeric(18,2),
    notice_pay numeric(18,2),
    hold_salary_non_taxable numeric(18,2),
    children_education_allowance numeric(18,2),
    gratuityinhand numeric(18,2),
    salarybonus numeric(18,2),
    dailyallowance_rate numeric(18,2) DEFAULT 0,
    consultanttdsid integer,
    e_customeraccountid bigint,
    e_unitid bigint,
    e_departmentid bigint,
    e_designationid bigint,
    perkilometerrate numeric(10,2) DEFAULT 0.0,
    tea_allowance_enabled character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    pfapplicablecomponents numeric(18,4),
    edli_adminchargesincludeinctc character varying(1) COLLATE pg_catalog."default" DEFAULT 'Y'::character varying,
    esiapplicablecomponents numeric(10,2),
    tdsmode character varying(20) COLLATE pg_catalog."default" DEFAULT 'Auto'::character varying,
    isgroupinsurance character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    employerinsuranceamount numeric,
    customtaxpercent numeric(10,2),
    ishourlysetup character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    charity_contribution character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    is_exemptedfromtds character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    tds_exempted_docpath text COLLATE pg_catalog."default",
    shift_hours character varying(5) COLLATE pg_catalog."default" DEFAULT '08:00'::character varying,
    grossearningcomponents numeric(18,2),
    fullmonthincentiveapplicable character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    flexiblemonthdays character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    salarymasterjson text COLLATE pg_catalog."default",
    CONSTRAINT empsalaryregister_pkey PRIMARY KEY (id),
    CONSTRAINT ck_empsalaryregister_salarydays_nonzero CHECK (salarydays > 0),
    CONSTRAINT empsalaryregister_isattendancerequired_check CHECK (isattendancerequired::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])),
    CONSTRAINT empsalaryregister_ishourlysetup_check CHECK (ishourlysetup::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text])),
    CONSTRAINT empsalaryregister_pfcapapplied_check CHECK (pfcapapplied::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text, NULL::character varying::text])),
    CONSTRAINT empsalaryregister_salarygenerationbase_check CHECK (salarygenerationbase::text = ANY (ARRAY[NULL::character varying::text, 'CTC'::character varying::text, 'SalaryInHand'::character varying::text])),
    CONSTRAINT empsalaryregister_salarysetupcriteria_check CHECK (salarysetupcriteria::text = ANY (ARRAY['PieceRate'::character varying::text, 'Monthly'::character varying::text, 'Daily'::character varying::text]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empsalaryregister
    OWNER to payrollingdb;
-- Index: empsalaryregister_uq_idx

-- DROP INDEX IF EXISTS public.empsalaryregister_uq_idx;

CREATE UNIQUE INDEX IF NOT EXISTS empsalaryregister_uq_idx
    ON public.empsalaryregister USING btree
    (appointment_id ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default
    WHERE isactive = '1'::"bit";
-- Index: idx_empsal1

-- DROP INDEX IF EXISTS public.idx_empsal1;

CREATE INDEX IF NOT EXISTS idx_empsal1
    ON public.empsalaryregister USING btree
    (appointment_id ASC NULLS LAST, id ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: idx_empsal2

-- DROP INDEX IF EXISTS public.idx_empsal2;

CREATE INDEX IF NOT EXISTS idx_empsal2
    ON public.empsalaryregister USING btree
    (appointment_id ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: idx_empsal3

-- DROP INDEX IF EXISTS public.idx_empsal3;

CREATE INDEX IF NOT EXISTS idx_empsal3
    ON public.empsalaryregister USING btree
    (isactive ASC NULLS LAST, effectivefrom ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

-- Trigger: trg_empsalaryregister_newhistory

-- DROP TRIGGER IF EXISTS trg_empsalaryregister_newhistory ON public.empsalaryregister;

CREATE OR REPLACE TRIGGER trg_empsalaryregister_newhistory
    BEFORE DELETE OR UPDATE 
    ON public.empsalaryregister
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_empsalaryregister_newhistory();