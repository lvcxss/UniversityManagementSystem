-- FUNCTION: public.fn_register_student(text, text, bigint, bigint, text, text, text, text, text, real)

-- DROP FUNCTION IF EXISTS public.fn_register_student(text, text, bigint, bigint, text, text, text, text, text, real);

CREATE OR REPLACE FUNCTION public.fn_register_student(
    p_name text,
    p_email text,
    p_cc bigint,
    p_nif bigint,
    p_gender text,
    p_phone text,
    p_password text,
    p_email_inst text,
    p_numero_estudante text,
    p_average real)
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
  )
  VALUES (
    p_name, p_email, p_cc, p_nif,
    p_gender, p_phone, p_password, 'student',
    p_email_inst
  )
  RETURNING id INTO o_person_id;

  INSERT INTO students (
    numero_estudante, average, person_id
  )
  VALUES (
    p_numero_estudante, p_average, o_person_id
  );

  RETURN o_person_id;
END;
$BODY$;

ALTER FUNCTION public.fn_register_student(text, text, bigint, bigint, text, text, text, text, text, real)
    OWNER TO postgres;
