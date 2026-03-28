-- Table: public.tbl_candidates_policies

-- DROP TABLE IF EXISTS public.tbl_candidates_policies;

CREATE TABLE IF NOT EXISTS public.tbl_candidates_policies
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    policy_id bigint,
    policy_name character varying(100) COLLATE pg_catalog."default",
    policy_status character varying(100) COLLATE pg_catalog."default",
    emp_code bigint,
    customeraccountid bigint,
    remarks character varying(100) COLLATE pg_catalog."default" DEFAULT NULL::character varying,
    record_type character varying(100) COLLATE pg_catalog."default" DEFAULT NULL::character varying,
    is_active boolean DEFAULT true,
    created_user character varying(200) COLLATE pg_catalog."default",
    created_on timestamp without time zone,
    created_by_ip character varying(200) COLLATE pg_catalog."default",
    modified_user character varying(200) COLLATE pg_catalog."default" DEFAULT NULL::character varying,
    modified_on timestamp without time zone,
    modified_by_ip character varying(200) COLLATE pg_catalog."default" DEFAULT NULL::character varying,
    CONSTRAINT tbl_candidates_policies_pkey PRIMARY KEY (id),
    CONSTRAINT tbl_candidates_policies_policy_id_fkey FOREIGN KEY (policy_id)
        REFERENCES public.mst_candidates_policies (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.tbl_candidates_policies
    OWNER to payrollingdb;