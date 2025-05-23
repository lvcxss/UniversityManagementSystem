-- FUNCTION: public.prevent_prereq_func()

-- DROP FUNCTION IF EXISTS public.prevent_prereq_func();

CREATE OR REPLACE FUNCTION public.prevent_prereq_func()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    has_cycle BOOLEAN;
BEGIN
    --problema: uma cadeira A pode precisar de uma cadeira B, essa cadeira B
    --pode precisar de uma cadeira C, a cadeira C nao pode depender nem de A nem de B
    --solucao: chamar recursivamente todas as dependencias da nova cadeira e verificar se 
    --nao existe nenhuma dependencia que cause incongruencia na db
    WITH RECURSIVE chain(course_id, prereq_id) AS (
        SELECT NEW.course, NEW.req_course
      UNION
        SELECT pc.course, pc.req_course
        FROM prereq_courses pc
        JOIN chain c ON pc.course = c.prereq_id
    )
    SELECT EXISTS (
        SELECT 1
        FROM chain
        WHERE prereq_id = NEW.course
    ) INTO has_cycle;

    IF has_cycle THEN
        RAISE EXCEPTION
          'Inserção inválida: criar % → % introduz um ciclo de pré-requisitos',
          NEW.course, NEW.req_course;
    END IF;

    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION public.prevent_prereq_func()
    OWNER TO postgres;
