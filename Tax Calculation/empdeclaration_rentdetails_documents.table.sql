-- Table: public.empdeclaration_rentdetails_documents

-- DROP TABLE IF EXISTS public.empdeclaration_rentdetails_documents;

CREATE TABLE IF NOT EXISTS public.empdeclaration_rentdetails_documents
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    emp_code bigint NOT NULL,
    headid integer NOT NULL,
    financialyear character varying(9) COLLATE pg_catalog."default" NOT NULL,
    monthly_tenure integer NOT NULL,
    fromdate date NOT NULL,
    todate date NOT NULL,
    receiptno character varying(100) COLLATE pg_catalog."default" NOT NULL,
    receiptdate date NOT NULL,
    rent_amount numeric(18,2) NOT NULL,
    landlord_name character varying(200) COLLATE pg_catalog."default",
    landlord_address character varying(500) COLLATE pg_catalog."default",
    landlord_city character varying(200) COLLATE pg_catalog."default",
    landlord_state integer,
    landlord_pan character varying(10) COLLATE pg_catalog."default",
    documentpath character varying(200) COLLATE pg_catalog."default" NOT NULL,
    documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    original_documentname character varying(120) COLLATE pg_catalog."default" NOT NULL,
    is_metro character varying(1) COLLATE pg_catalog."default",
    no_of_child_under_cea integer NOT NULL,
    no_of_child_under_cha integer NOT NULL,
    created_by integer,
    created_on timestamp without time zone,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_by integer,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    active bit(1) DEFAULT '1'::"bit",
    approval_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'P'::character varying,
    approvedby bigint,
    approvedon timestamp without time zone,
    approvedbyip character varying(200) COLLATE pg_catalog."default",
    remarks character varying(300) COLLATE pg_catalog."default",
    notification_sent_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    notification_process_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    rentdtldoc_remarks character varying(255) COLLATE pg_catalog."default",
    uploaded_by_user_type character varying(20) COLLATE pg_catalog."default" DEFAULT 'Employee'::character varying,
    modified_by_username character varying(150) COLLATE pg_catalog."default",
    modified_by_usertype character varying(150) COLLATE pg_catalog."default",
    CONSTRAINT empdeclaration_rentdetails_documents_monthly_tenure_check CHECK (monthly_tenure = ANY (ARRAY[1, 2, 3, 4]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empdeclaration_rentdetails_documents
    OWNER to payrollingdb;

COMMENT ON COLUMN public.empdeclaration_rentdetails_documents.monthly_tenure
    IS ' 1=>"Monthly,2=>Quarterly,3=>Half-Yearly,4=>Yearly';

COMMENT ON COLUMN public.empdeclaration_rentdetails_documents.approval_status
    IS ' P for Pending,A for Approval and R for Rejection';
-- Index: idx_empdeclaration_rentdetails_documents_empcode

-- DROP INDEX IF EXISTS public.idx_empdeclaration_rentdetails_documents_empcode;

CREATE INDEX IF NOT EXISTS idx_empdeclaration_rentdetails_documents_empcode
    ON public.empdeclaration_rentdetails_documents USING btree
    (emp_code ASC NULLS LAST, financialyear COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

-- Trigger: trg_empdeclr_rentdetails_documents_history

-- DROP TRIGGER IF EXISTS trg_empdeclr_rentdetails_documents_history ON public.empdeclaration_rentdetails_documents;

CREATE OR REPLACE TRIGGER trg_empdeclr_rentdetails_documents_history
    BEFORE DELETE OR UPDATE 
    ON public.empdeclaration_rentdetails_documents
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_empdec_rent_documents_history();