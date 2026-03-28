-- Table: public.empdeclr_homeloan

-- DROP TABLE IF EXISTS public.empdeclr_homeloan;

CREATE TABLE IF NOT EXISTS public.empdeclr_homeloan
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    emp_code bigint,
    financial_year character varying(9) COLLATE pg_catalog."default",
    lender_pannumber1 character varying(100) COLLATE pg_catalog."default",
    lender_pannumber2 character varying(20) COLLATE pg_catalog."default",
    lender_pannumber3 character varying(20) COLLATE pg_catalog."default",
    lender_pannumber4 character varying(20) COLLATE pg_catalog."default",
    loan_sanction_date date,
    loan_amount numeric(18,2),
    property_value numeric(18,2),
    lender_name character varying(100) COLLATE pg_catalog."default",
    is_firsttymebuyer character varying(1) COLLATE pg_catalog."default",
    principal_on_borrowed_capital numeric(18,2),
    interest_on_borrowed_capital numeric(18,2),
    created_by integer,
    created_on timestamp without time zone NOT NULL,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_by integer,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    active bit(1),
    isbefore01apr1999 character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    approval_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'P'::character varying,
    approvedon timestamp without time zone,
    approvedby bigint,
    approvedbyip character varying(200) COLLATE pg_catalog."default",
    homeloandec_remarks character varying(255) COLLATE pg_catalog."default",
    homeaddress character varying(500) COLLATE pg_catalog."default",
    CONSTRAINT empdeclr_homeloan_pkey1 PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empdeclr_homeloan
    OWNER to payrollingdb;
-- Index: idx_empdeclr_homeloan

-- DROP INDEX IF EXISTS public.idx_empdeclr_homeloan;

CREATE INDEX IF NOT EXISTS idx_empdeclr_homeloan
    ON public.empdeclr_homeloan USING brin
    (financial_year COLLATE pg_catalog."default")
    WITH (pages_per_range=128, autosummarize=False)
    TABLESPACE pg_default;