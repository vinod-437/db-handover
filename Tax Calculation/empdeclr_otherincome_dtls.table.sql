-- Table: public.empdeclr_otherincome_dtls

-- DROP TABLE IF EXISTS public.empdeclr_otherincome_dtls;

CREATE TABLE IF NOT EXISTS public.empdeclr_otherincome_dtls
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
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
    CONSTRAINT empdeclr_otherincome_dtls_pkey1 PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.empdeclr_otherincome_dtls
    OWNER to payrollingdb;