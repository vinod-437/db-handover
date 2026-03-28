-- Table: public.mst_candidates_policies

-- DROP TABLE IF EXISTS public.mst_candidates_policies;

CREATE TABLE IF NOT EXISTS public.mst_candidates_policies
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    policy_name character varying(100) COLLATE pg_catalog."default",
    policy_desc character varying(500) COLLATE pg_catalog."default",
    is_active bit(1),
    created_user character varying(200) COLLATE pg_catalog."default",
    created_on timestamp without time zone,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_user character varying(200) COLLATE pg_catalog."default",
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default",
    CONSTRAINT mst_candidates_policies_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.mst_candidates_policies
    OWNER to payrollingdb;