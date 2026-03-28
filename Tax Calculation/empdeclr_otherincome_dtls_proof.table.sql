-- Table: public.empdeclr_otherincome_dtls_proof

-- DROP TABLE IF EXISTS public.empdeclr_otherincome_dtls_proof;

CREATE TABLE IF NOT EXISTS public.empdeclr_otherincome_dtls_proof
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    emp_code bigint NOT NULL,
    financial_year character varying(9) COLLATE pg_catalog."default",
    incomefromothersources numeric(18,2),
    businessincome numeric(18,2),
    incomefromcapitalgains numeric(18,2),
    anyotherincome numeric(18,2),
    interestonsavingbank numeric(18,2),
    tds_others numeric(18,2),
    total numeric(18,2),
    created_by integer,
    created_on timestamp without time zone NOT NULL,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_by integer,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    active bit(1),
    documentpath character varying(200) COLLATE pg_catalog."default" NOT NULL,
    documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    original_documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    proof_amount numeric(18,2),
    approval_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'P'::character varying,
    approvedby bigint,
    approvedon timestamp without time zone,
    approvedbyip bigint,
    remarks character varying(300) COLLATE pg_catalog."default",
    CONSTRAINT empdeclr_otherincome_dtls_proof_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empdeclr_otherincome_dtls_proof
    OWNER to payrollingdb;

COMMENT ON COLUMN public.empdeclr_otherincome_dtls_proof.approval_status
    IS ' P for Pending,A for Approval and R for Rejection';

-- Trigger: trgempdeclr_otherincome_dtls_proof_history

-- DROP TRIGGER IF EXISTS trgempdeclr_otherincome_dtls_proof_history ON public.empdeclr_otherincome_dtls_proof;

CREATE OR REPLACE TRIGGER trgempdeclr_otherincome_dtls_proof_history
    BEFORE DELETE OR UPDATE 
    ON public.empdeclr_otherincome_dtls_proof
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_empdeclr_otherincome_dtls_proof_history();