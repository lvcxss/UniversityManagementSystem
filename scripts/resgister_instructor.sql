-- FUNCTION: public.fn_register_instructor(text, text, bigint, bigint, text, text, text, text, text, real, integer, boolean, text)

-- DROP FUNCTION IF EXISTS public.fn_register_instructor(text, text, bigint, bigint, text, text, text, text, text, real, integer, boolean, text);

CREATE OR REPLACE FUNCTION public.fn_register_instructor(
    p_name text,
    p_email_pessoal text,
    p_cc bigint,
    p_nif bigint,
    p_gender text,
    p_phone text,
    p_password text,
    p_email_inst text,
    p_numero_docente text,
    p_salario real,
    p_anos_servico integer,
    p_active boolean,
    p_area text)
    RETURNS integer
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
  o_person_id INTEGER;
BEGIN
  INSERT INTO person (
    name, email_pessoal, cc, nif,
    gender, phone, password, role,
    email_institucional
  ) VALUES (
    p_name, p_email_pessoal, p_cc, p_nif,
    p_gender, p_phone, p_password, 'instructor',
    p_email_inst
  )
  RETURNING id INTO o_person_id;

  INSERT INTO employee (
    numero_docente, salario, anos_servico,
    active, person_id
  ) VALUES (
    p_numero_docente, p_salario, p_anos_servico,
    p_active, o_person_id
  );

  INSERT INTO instructors (
    instructor_person_id, area
  ) VALUES (
    o_person_id, p_area
  );

  RETURN o_person_id;
END;
$BODY$;

ALTER FUNCTION public.fn_register_instructor(text, text, bigint, bigint, text, text, text, text, text, real, integer, boolean, text)
    OWNER TO postgres;
