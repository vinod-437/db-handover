-- Table: public.empdeclaration_rentdetails

-- DROP TABLE IF EXISTS public.empdeclaration_rentdetails;

CREATE TABLE IF NOT EXISTS public.empdeclaration_rentdetails
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    emp_code bigint NOT NULL,
    financial_year character varying(9) COLLATE pg_catalog."default",
    rent_year integer,
    rent_month integer,
    is_metro character varying(1) COLLATE pg_catalog."default",
    rentpaid numeric(18,2),
    no_of_child_under_cea integer,
    no_of_child_under_cha integer,
    landlordname character varying(200) COLLATE pg_catalog."default",
    landlordpancard character varying(10) COLLATE pg_catalog."default",
    address character varying(500) COLLATE pg_catalog."default",
    createdby bigint,
    createdon timestamp without time zone,
    createdbyip character varying(200) COLLATE pg_catalog."default",
    isactive bit(1),
    approval_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'P'::character varying,
    approvedon timestamp without time zone,
    approvedby bigint,
    approvedbyip character varying(200) COLLATE pg_catalog."default",
    rentdtl_remarks character varying(255) COLLATE pg_catalog."default",
    CONSTRAINT empdeclaration_rentdetails_pkey1 PRIMARY KEY (id),
    CONSTRAINT rentdetails_uq1 UNIQUE (emp_code, rent_year, rent_month, isactive)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empdeclaration_rentdetails
    OWNER to payrollingdb;
-- Index: idx_empdeclaration_rentdetails

-- DROP INDEX IF EXISTS public.idx_empdeclaration_rentdetails;

CREATE INDEX IF NOT EXISTS idx_empdeclaration_rentdetails
    ON public.empdeclaration_rentdetails USING brin
    (financial_year COLLATE pg_catalog."default")
    WITH (pages_per_range=128, autosummarize=False)
    TABLESPACE pg_default;
-- Index: idx_empdeclaration_rentdetails_1

-- DROP INDEX IF EXISTS public.idx_empdeclaration_rentdetails_1;

CREATE INDEX IF NOT EXISTS idx_empdeclaration_rentdetails_1
    ON public.empdeclaration_rentdetails USING btree
    (financial_year COLLATE pg_catalog."default" ASC NULLS LAST, emp_code ASC NULLS LAST, approval_status COLLATE pg_catalog."default" ASC NULLS LAST, isactive ASC NULLS LAST)
    INCLUDE(rentpaid, landlordname, landlordpancard)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;