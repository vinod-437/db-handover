-- FOREIGN TABLE: public.mst_taxslabs

-- DROP FOREIGN TABLE IF EXISTS public.mst_taxslabs;

CREATE FOREIGN TABLE IF NOT EXISTS public.mst_taxslabs(
    id bigint,
    financial_year character varying(9) COLLATE pg_catalog."default",
    regimetype character varying(10) COLLATE pg_catalog."default",
    maxage integer,
    taxableincomefrom numeric(18,2),
    taxableincometo numeric(18,2),
    taxrate numeric(18,2),
    taxslab character varying(20) COLLATE pg_catalog."default",
    isactive bit(1),
    configname character varying(100) COLLATE pg_catalog."default",
    marginal_relief_applicable bit(1)
)
    SERVER hubapp_db_fw
    OPTIONS (schema_name 'public', table_name 'vw_mst_taxslabs');

ALTER FOREIGN TABLE public.mst_taxslabs
    OWNER TO payrollingdb;