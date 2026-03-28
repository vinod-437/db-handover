-- Table: public.empdeclr_prevemployerinc_dtls

-- DROP TABLE IF EXISTS public.empdeclr_prevemployerinc_dtls;

CREATE TABLE IF NOT EXISTS public.empdeclr_prevemployerinc_dtls
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    emp_code bigint NOT NULL,
    financial_year character varying(9) COLLATE pg_catalog."default",
    total_income numeric(18,2),
    tds numeric(18,2),
    professional_tax numeric(18,2),
    provident_fund numeric(18,2),
    total numeric(18,2),
    created_by integer,
    created_on timestamp without time zone NOT NULL,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_by integer,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    active bit(1),
    approval_status character varying(1) COLLATE pg_catalog."default",
    CONSTRAINT empdeclr_prevemployerinc_dtls_pkey1 PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empdeclr_prevemployerinc_dtls
    OWNER to payrollingdb;