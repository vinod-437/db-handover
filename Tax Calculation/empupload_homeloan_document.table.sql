-- Table: public.empupload_homeloan_document

-- DROP TABLE IF EXISTS public.empupload_homeloan_document;

CREATE TABLE IF NOT EXISTS public.empupload_homeloan_document
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    emp_code bigint NOT NULL,
    emp_id bigint,
    financial_year character varying(9) COLLATE pg_catalog."default",
    lender_pannumber1 character varying(10) COLLATE pg_catalog."default",
    lender_pannumber2 character varying(10) COLLATE pg_catalog."default",
    lender_pannumber3 character varying(10) COLLATE pg_catalog."default",
    lender_pannumber4 character varying(10) COLLATE pg_catalog."default",
    loan_sanction_date date,
    principal_amount numeric(18,2),
    intrest_amount numeric(18,2),
    name_of_owner character varying(100) COLLATE pg_catalog."default",
    lender_name character varying(100) COLLATE pg_catalog."default",
    is_firsttymebuyer character varying(1) COLLATE pg_catalog."default",
    created_by integer,
    created_on timestamp without time zone NOT NULL,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_by integer,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    active bit(1),
    isbefore01apr1999 character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    loan_no character varying(50) COLLATE pg_catalog."default",
    loan_type character varying(10) COLLATE pg_catalog."default",
    loan_holder_type character varying(10) COLLATE pg_catalog."default",
    loan_holder_name character varying(100) COLLATE pg_catalog."default",
    documentpath character varying(200) COLLATE pg_catalog."default" NOT NULL,
    documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    original_documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    approval_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'P'::character varying,
    approvedby bigint,
    approvedon timestamp without time zone,
    approvedbyip character varying(200) COLLATE pg_catalog."default",
    remarks character varying(300) COLLATE pg_catalog."default",
    loan_amount numeric(18,2),
    property_value numeric(18,2),
    notification_sent_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    notification_process_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    homeloanproof_remarks character varying(255) COLLATE pg_catalog."default",
    uploaded_by_user_type character varying(20) COLLATE pg_catalog."default" DEFAULT 'Employee'::character varying,
    homeaddress character varying(500) COLLATE pg_catalog."default",
    modified_by_username character varying(150) COLLATE pg_catalog."default",
    modified_by_usertype character varying(150) COLLATE pg_catalog."default",
    CONSTRAINT empupload_homeloan_document_pk PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empupload_homeloan_document
    OWNER to payrollingdb;

COMMENT ON COLUMN public.empupload_homeloan_document.approval_status
    IS ' P for Pending,A for Approval and R for Rejection';
-- Index: idx_empupload_homeloan_document_empcode

-- DROP INDEX IF EXISTS public.idx_empupload_homeloan_document_empcode;

CREATE INDEX IF NOT EXISTS idx_empupload_homeloan_document_empcode
    ON public.empupload_homeloan_document USING btree
    (emp_code ASC NULLS LAST, financial_year COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

-- Trigger: trg_empupload_homeloan_document_history

-- DROP TRIGGER IF EXISTS trg_empupload_homeloan_document_history ON public.empupload_homeloan_document;

CREATE OR REPLACE TRIGGER trg_empupload_homeloan_document_history
    BEFORE DELETE OR UPDATE 
    ON public.empupload_homeloan_document
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_empupload_homeloan_document_history();