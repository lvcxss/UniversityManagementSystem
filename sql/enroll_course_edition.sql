-- FUNCTION: public.enroll_course_edition(integer, integer, integer[])

-- DROP FUNCTION IF EXISTS public.enroll_course_edition(integer, integer, integer[]);

CREATE OR REPLACE FUNCTION public.enroll_course_edition(
	p_student_person_id integer,
	p_edition_id integer,
	p_class_ids integer[])
    RETURNS TABLE(status text, message text) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
  v_course_id       INTEGER;
  v_prereq_course   INTEGER;
  v_conflicts       INTEGER;
  v_class_id        INTEGER;
  v_capacity        INTEGER;
  v_enrolled_count  INTEGER;
BEGIN
  -- obter course edition 
  SELECT ce.course_id
    INTO v_course_id
  FROM course_edition ce
  WHERE ce.edition_id = p_edition_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'error', 'Edition '||p_edition_id||' not found';
    RETURN;
  END IF;

  -- verificar se o student tem um degree "compativel" 
  IF NOT EXISTS (
    SELECT 1
      FROM students_degree sd
      JOIN courses_degree cd ON sd.degree_id = cd.degree_id
     WHERE sd.students_id = p_student_person_id
       AND cd.course_id   = v_course_id
  ) THEN
    RETURN QUERY SELECT 'error', 'Student not enrolled in a compatible degree';
    RETURN;
  END IF;

  -- verificar se tem os prerequerements
  FOR v_prereq_course IN
    SELECT req_course
      FROM prereq_courses
     WHERE course = v_course_id
  LOOP
    IF NOT EXISTS (
      SELECT 1
        FROM edition_stats es
        JOIN edition e ON e.id = es.edition_id
       WHERE es.students_person_id = p_student_person_id
         AND es.passed              = TRUE
         AND e.course_id           = v_prereq_course
    ) THEN
      RETURN QUERY
      SELECT 'error',
             'Missing prerequisite course (ID '||v_prereq_course||')';
      RETURN;
    END IF;
  END LOOP;

	IF EXISTS (
  SELECT 1
    FROM class c
   WHERE c.class_id = ANY(p_class_ids)
     AND c.edition_id <> p_edition_id
) THEN
  RETURN QUERY SELECT 'error', 'One or more classes do not belong to the specified edition';
  RETURN;
	END IF;

  -- 4) capacidade da turma
  FOREACH v_class_id IN ARRAY p_class_ids LOOP
    SELECT p.capacity
      INTO v_capacity
      FROM practical p
     WHERE p.class_id = v_class_id;
    IF NOT FOUND THEN
      v_capacity := NULL;  -- sem limite
    END IF;

    SELECT COUNT(*) 
      INTO v_enrolled_count
      FROM students_classes sc
     WHERE sc.class_id = v_class_id;

    IF v_capacity IS NOT NULL
       AND v_enrolled_count >= v_capacity
    THEN
      RETURN QUERY
      SELECT 'error', 'Class ID '||v_class_id||' is full';
      RETURN;
    END IF;
  END LOOP;

  -- 5) overlays de horarios
  DROP TABLE IF EXISTS tmp_req;
  DROP TABLE IF EXISTS tmp_exist;

  CREATE TEMP TABLE tmp_req ON COMMIT DROP AS
    SELECT cs.class_id, cs.weekday, cs.start, cs."end"
      FROM class_schedule cs
     WHERE cs.class_id = ANY(p_class_ids);

  CREATE TEMP TABLE tmp_exist ON COMMIT DROP AS
    SELECT cs.class_id, cs.weekday, cs.start, cs."end"
      FROM students_classes sc
      JOIN class_schedule cs ON cs.class_id = sc.class_id
     WHERE sc.student_id = p_student_person_id;

  -- conflito novas vs existentes
  SELECT COUNT(*) INTO v_conflicts
    FROM tmp_req n
    JOIN tmp_exist e
      ON n.weekday = e.weekday
     AND n.start   < e."end"
     AND n."end"   > e.start;
  IF v_conflicts > 0 THEN
    RETURN QUERY SELECT 'error', 'Schedule conflict with existing classes';
    RETURN;
  END IF;

  -- conflito entre as novas
  SELECT COUNT(*) INTO v_conflicts
    FROM tmp_req a
    JOIN tmp_req b
      ON a.class_id < b.class_id
     AND a.weekday  = b.weekday
     AND a.start    < b."end"
     AND a."end"    > b.start;
  IF v_conflicts > 0 THEN
    RETURN QUERY SELECT 'error', 'Schedule conflict among requested classes';
    RETURN;
  END IF;

  -- 6) inscrever na stats
  INSERT INTO edition_stats(students_person_id, edition_id, passed)
  VALUES (p_student_person_id, p_edition_id, FALSE)
  ON CONFLICT (students_person_id, edition_id) DO NOTHING;

  -- 7) inscrever nas classes
  FOREACH v_class_id IN ARRAY p_class_ids LOOP
    INSERT INTO students_classes(student_id, class_id)
    VALUES (p_student_person_id, v_class_id)
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN QUERY SELECT 'success', 'Student enrolled successfully';
END;
$BODY$;

ALTER FUNCTION public.enroll_course_edition(integer, integer, integer[])
    OWNER TO postgres;
