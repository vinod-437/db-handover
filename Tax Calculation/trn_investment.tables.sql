-- Table: public.trn_investment

-- DROP TABLE IF EXISTS public.trn_investment;

CREATE TABLE IF NOT EXISTS public.trn_investment
(
    id integer NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 2147483647 CACHE 1 ),
    headid integer,
    financial_year character varying(9) COLLATE pg_catalog."default",
    investment_id integer NOT NULL,
    emp_code bigint NOT NULL,
    emp_id bigint,
    investment_amount numeric(18,2),
    investment_comment character varying(400) COLLATE pg_catalog."default",
    createdby bigint,
    createdon timestamp without time zone,
    createdbyip character varying(200) COLLATE pg_catalog."default",
    modifiedby bigint,
    modifiedon timestamp without time zone,
    midifiedbyip character varying(200) COLLATE pg_catalog."default",
    isactive bit(1),
    approval_status character varying(1) COLLATE pg_catalog."default" DEFAULT 'P'::character varying,
    approvedon timestamp without time zone,
    approvedby bigint,
    approvedbyip character varying(200) COLLATE pg_catalog."default",
    invdec_remarks character varying(255) COLLATE pg_catalog."default",
    CONSTRAINT trn_investment_pkey1 PRIMARY KEY (id),
    CONSTRAINT trn_investment_headid_fkey1 FOREIGN KEY (headid)
        REFERENCES public.mst_investmenthead (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT trn_investment_investment_id_fkey1 FOREIGN KEY (investment_id)
        REFERENCES public.mst_investment_section (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.trn_investment
    OWNER to payrollingdb;
-- Index: idx_trn_investment_1

-- DROP INDEX IF EXISTS public.idx_trn_investment_1;

CREATE INDEX IF NOT EXISTS idx_trn_investment_1
    ON public.trn_investment USING btree
    (investment_id ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;
-- Index: idx_trn_investment_finyear

-- DROP INDEX IF EXISTS public.idx_trn_investment_finyear;

CREATE INDEX IF NOT EXISTS idx_trn_investment_finyear
    ON public.trn_investment USING brin
    (financial_year COLLATE pg_catalog."default")
    WITH (pages_per_range=128, autosummarize=False)
    TABLESPACE pg_default;

-- Trigger: trgtrn_investmenthistoty

-- DROP TRIGGER IF EXISTS trgtrn_investmenthistoty ON public.trn_investment;

CREATE OR REPLACE TRIGGER trgtrn_investmenthistoty
    BEFORE INSERT OR DELETE OR UPDATE 
    ON public.trn_investment
    FOR EACH ROW
    EXECUTE FUNCTION public.usptrn_investmenthistoty_2();