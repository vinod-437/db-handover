-- Table: public.empdeclr_letoutpropertyincome

-- DROP TABLE IF EXISTS public.empdeclr_letoutpropertyincome;

CREATE TABLE IF NOT EXISTS public.empdeclr_letoutpropertyincome
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    emp_code bigint,
    financial_year character varying(9) COLLATE pg_catalog."default",
    ishavingloan character varying(1) COLLATE pg_catalog."default",
    grossannualrental_income numeric(18,2),
    municipal_taxes numeric(18,2),
    netannualvalue numeric(18,2),
    standard_deduction numeric(18,2),
    interest_on_borrowed_capital numeric(18,2),
    netincomefromhouse numeric(18,2),
    created_by integer,
    created_on timestamp without time zone NOT NULL,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_by integer,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    active bit(1),
    CONSTRAINT empdeclr_letoutpropertyincome_pkey1 PRIMARY KEY (id),
    CONSTRAINT empdeclr_letoutpropertyincome_ishavingloan_check1 CHECK (ishavingloan::text = ANY (ARRAY['Y'::character varying::text, 'N'::character varying::text]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empdeclr_letoutpropertyincome
    OWNER to payrollingdb;