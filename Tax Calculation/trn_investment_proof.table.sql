-- Table: public.trn_investment_proof

-- DROP TABLE IF EXISTS public.trn_investment_proof;

CREATE TABLE IF NOT EXISTS public.trn_investment_proof
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    headid integer,
    financial_year character varying(9) COLLATE pg_catalog."default",
    investment_id integer NOT NULL,
    emp_code bigint NOT NULL,
    emp_id bigint,
    investment_comment character varying(400) COLLATE pg_catalog."default",
    createdby bigint,
    createdon timestamp without time zone,
    createdbyip character varying(200) COLLATE pg_catalog."default",
    modifiedby bigint,
    modifiedon timestamp without time zone,
    midifiedbyip character varying(200) COLLATE pg_catalog."default",
    isactive bit(1),
    documentpath character varying(200) COLLATE pg_catalog."default" NOT NULL,
    documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    original_documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    approval_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'P'::character varying,
    approvedby bigint,
    approvedon timestamp without time zone,
    approvedbyip character varying(200) COLLATE pg_catalog."default",
    receipt_number character varying(50) COLLATE pg_catalog."default",
    receipt_date date,
    receipt_amount numeric(18,2),
    remarks character varying(300) COLLATE pg_catalog."default",
    notification_sent_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    notification_process_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    invdecproof_remarks character varying(255) COLLATE pg_catalog."default",
    uploaded_by_user_type character varying(20) COLLATE pg_catalog."default" DEFAULT 'Employee'::character varying,
    modified_by_username character varying(150) COLLATE pg_catalog."default",
    modified_by_usertype character varying(150) COLLATE pg_catalog."default",
    CONSTRAINT trn_investment_proof_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.trn_investment_proof
    OWNER to payrollingdb;

COMMENT ON COLUMN public.trn_investment_proof.approval_status
    IS ' P for Pending,A for Approval and R for Rejection';
-- Index: idx_trn_investment_proof_empcode

-- DROP INDEX IF EXISTS public.idx_trn_investment_proof_empcode;

CREATE INDEX IF NOT EXISTS idx_trn_investment_proof_empcode
    ON public.trn_investment_proof USING btree
    (emp_code ASC NULLS LAST, financial_year COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

-- Trigger: trg_trn_investment_proof_history

-- DROP TRIGGER IF EXISTS trg_trn_investment_proof_history ON public.trn_investment_proof;

CREATE OR REPLACE TRIGGER trg_trn_investment_proof_history
    BEFORE DELETE OR UPDATE 
    ON public.trn_investment_proof
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_trn_investment_proof_history();