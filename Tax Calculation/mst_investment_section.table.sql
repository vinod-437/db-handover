-- Table: public.mst_investment_section

-- DROP TABLE IF EXISTS public.mst_investment_section;

CREATE TABLE IF NOT EXISTS public.mst_investment_section
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 51 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    financial_year character varying(9) COLLATE pg_catalog."default",
    headid integer NOT NULL,
    sectionname character varying(100) COLLATE pg_catalog."default",
    investmentname character varying(1000) COLLATE pg_catalog."default",
    investmentdescription character varying(1000) COLLATE pg_catalog."default",
    max_limit numeric(18,2),
    createdby integer,
    createdon timestamp without time zone,
    createdbyip character varying(200) COLLATE pg_catalog."default",
    modifiedby integer,
    modifiedon timestamp without time zone,
    midifiedbyip character varying(200) COLLATE pg_catalog."default",
    isactive bit(1),
    isacustomerspecific character varying(1) COLLATE pg_catalog."default" DEFAULT 'N'::character varying,
    customeraccountids bigint[],
    CONSTRAINT mst_investment_section_pkey PRIMARY KEY (id),
    CONSTRAINT mst_investment_section_headid_fkey FOREIGN KEY (headid)
        REFERENCES public.mst_investmenthead (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.mst_investment_section
    OWNER to payrollingdb;

-- Trigger: trgmst_investment_sectionhistoty

-- DROP TRIGGER IF EXISTS trgmst_investment_sectionhistoty ON public.mst_investment_section;

CREATE OR REPLACE TRIGGER trgmst_investment_sectionhistoty
    BEFORE DELETE OR UPDATE 
    ON public.mst_investment_section
    FOR EACH ROW
    EXECUTE FUNCTION public.uspmst_investment_sectionhistoty();