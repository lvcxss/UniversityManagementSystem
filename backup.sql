--
-- PostgreSQL database dump
--

-- Dumped from database version 16.8
-- Dumped by pg_dump version 16.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: create_invoice_activity(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_invoice_activity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_amount NUMERIC(10,2);
BEGIN
  SELECT d.cost
    INTO v_amount
  FROM activity d
  WHERE d.id = NEW.activity_id;

  INSERT INTO invoices(students_id, cost)
  VALUES (
    NEW.students_id,
    v_amount
  );

  RETURN NEW;
END;

$$;


ALTER FUNCTION public.create_invoice_activity() OWNER TO postgres;

--
-- Name: create_invoice_degree(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_invoice_degree() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_amount NUMERIC(10,2);
BEGIN
  SELECT d.cost
    INTO v_amount
  FROM degree d
  WHERE d.id = NEW.degree_id;

  INSERT INTO invoices(students_id, staff_id,cost)
  VALUES (
    NEW.students_id,
    NEW.staff_id,
    v_amount
  );

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_invoice_degree() OWNER TO postgres;

--
-- Name: enroll_course_edition(integer, integer, integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.enroll_course_edition(p_student_person_id integer, p_edition_id integer, p_class_ids integer[]) RETURNS TABLE(status text, message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_course_id       INTEGER;
  v_prereq_course   INTEGER;
  v_conflicts       INTEGER;
  v_class_id        INTEGER;
  v_capacity        INTEGER;
  v_enrolled_count  INTEGER;
BEGIN
  -- obter course edition 
    SELECT ce.course_id INTO v_course_id
    FROM course_edition ce
    WHERE ce.edition_id = p_edition_id
	FOR UPDATE;
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

  -- capacidade da turma
  FOREACH v_class_id IN ARRAY p_class_ids LOOP
    SELECT p.capacity INTO v_capacity
    FROM practical p
    WHERE p.class_id = v_class_id;

    IF v_capacity IS NOT NULL THEN
        PERFORM 1 
        FROM practical p 
        WHERE p.class_id = v_class_id 
        FOR UPDATE;
        SELECT COUNT(*) INTO v_enrolled_count
        FROM students_classes sc
        WHERE sc.class_id = v_class_id;
        IF v_enrolled_count >= v_capacity THEN
            RETURN QUERY SELECT 'error', 'Class ID '||v_class_id||' is full';
            RETURN;
        END IF;
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
$$;


ALTER FUNCTION public.enroll_course_edition(p_student_person_id integer, p_edition_id integer, p_class_ids integer[]) OWNER TO postgres;

--
-- Name: fn_register_instructor(text, text, text, text, text, text, text, text, text, real, integer, boolean, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_register_instructor(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean, p_area text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_register_instructor(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean, p_area text) OWNER TO postgres;

--
-- Name: fn_register_staff(text, text, text, text, text, text, text, text, text, real, integer, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_register_staff(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  o_person_id INTEGER;
BEGIN
  INSERT INTO person (
    name, email_pessoal, cc, nif,
    gender, phone, password, role,
    email_institucional
  ) VALUES (
    p_name, p_email_pessoal, p_cc, p_nif,
    p_gender, p_phone, p_password, 'staff',
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

  INSERT INTO staff (staff_person_id)
  VALUES (o_person_id);

  RETURN o_person_id;
END;
$$;


ALTER FUNCTION public.fn_register_staff(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean) OWNER TO postgres;

--
-- Name: fn_register_student(text, text, text, text, text, text, text, text, text, real); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_register_student(p_name text, p_email text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_estudante text, p_average real) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_register_student(p_name text, p_email text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_estudante text, p_average real) OWNER TO postgres;

--
-- Name: get_course_editions_by_degree(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_course_editions_by_degree(p_degree_id integer) RETURNS TABLE(course_id integer, course_name character varying, degree_id integer, edition_id integer, year integer, total_capacity bigint, degree_count bigint, passed_students_count bigint, coordinator integer, staff_person_id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id AS course_id,
        c.name AS course_name,
        d.id AS degree_id,
        e.id AS edition_id,
        e.ano AS year,
        SUM(p.capacity) AS total_capacity,
        COUNT(DISTINCT d.id) AS degree_count,
        SUM(es.passed::int) AS passed_students_count,
        e.coordinator,
        dc.theory_instructors_class_staff_person_id
    FROM 
        public.degree d
    JOIN 
        courses_degree cd ON d.id = cd.degree_id
    JOIN 
        course c ON c.id = cd.course_id
    JOIN 
        edition e ON e.course_id = c.id
    JOIN 
        class cl ON cl.edition_id = e.id
    JOIN 
        class_schedule cs ON cs.class_id = cl.class_id
    JOIN 
        department_classroom dc ON dc.name = cs.classroom
    JOIN 
        practical p ON cs.class_id = p.class_id
    JOIN 
        edition_stats es ON es.edition_id = e.id
    WHERE
        d.id = p_degree_id
    GROUP BY
        c.id,
        c.name,
        d.id,
        e.id,
        e.ano,
        e.coordinator,
        dc.theory_instructors_class_staff_person_id;
END;
$$;


ALTER FUNCTION public.get_course_editions_by_degree(p_degree_id integer) OWNER TO postgres;

--
-- Name: get_student_courses(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_student_courses(student_id_param integer) RETURNS TABLE(course_id integer, course_name character varying, edition_year integer, grade numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        ce.course_id::INTEGER,
        c.name::VARCHAR(64),  -- Explicit cast to match return type
        e.ano::INTEGER,
        ge.grade::NUMERIC(5,2)  -- Cast to NUMERIC(5,2)
    FROM
        students_degree sd
    JOIN courses_degree cd 
        ON sd.degree_id = cd.degree_id
    JOIN course c 
        ON cd.course_id = c.id
    JOIN course_edition ce 
        ON c.id = ce.course_id
    JOIN edition e
        ON ce.edition_id = e.id
    LEFT JOIN grades_edition_stats ge 
        ON ce.edition_id = ge.edition_id 
        AND sd.students_id = ge.students_person_id
    WHERE
        sd.students_id = student_id_param;
END;
$$;


ALTER FUNCTION public.get_student_courses(student_id_param integer) OWNER TO postgres;

--
-- Name: prevent_prereq_func(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.prevent_prereq_func() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
          'invalid insertion : creating % → % creates a cycle',
          NEW.course, NEW.req_course;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_prereq_func() OWNER TO postgres;

--
-- Name: update_passed_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_passed_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    recurso_grade NUMERIC;  
    total_weighted NUMERIC; 
BEGIN
    --verificar se ha nota de recurso (id 4)
    SELECT grade INTO recurso_grade
    FROM grades_edition_stats
    WHERE students_person_id = NEW.students_person_id
      AND edition_id = NEW.edition_id
      AND period_id = 4;

    
    IF FOUND THEN
        IF recurso_grade >= 50 THEN
            UPDATE edition_stats
               SET passed = TRUE
             WHERE students_person_id = NEW.students_person_id
               AND edition_id = NEW.edition_id;
        ELSE
            UPDATE edition_stats
               SET passed = FALSE
             WHERE students_person_id = NEW.students_person_id
               AND edition_id = NEW.edition_id;
        END IF;
    ELSE
        --media fora do recurso
        SELECT SUM(g.grade * p.weight_pct / 100)
          INTO total_weighted
          FROM grades_edition_stats g
          JOIN evaluation_period p 
            ON g.period_id = p.period_id
         WHERE g.students_person_id = NEW.students_person_id
           AND g.edition_id = NEW.edition_id
           AND g.period_id != 4;  
        IF total_weighted >= 50 THEN
            UPDATE edition_stats
               SET passed = TRUE
             WHERE students_person_id = NEW.students_person_id
               AND edition_id = NEW.edition_id;
        ELSE
            UPDATE edition_stats
               SET passed = FALSE
             WHERE students_person_id = NEW.students_person_id
               AND edition_id = NEW.edition_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_passed_status() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.activity (
    description text,
    id integer NOT NULL,
    name character varying(64) NOT NULL,
    cost money NOT NULL
);


ALTER TABLE public.activity OWNER TO postgres;

--
-- Name: attendance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance (
    students_person_id integer NOT NULL
);


ALTER TABLE public.attendance OWNER TO postgres;

--
-- Name: class_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.class_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.class_seq OWNER TO postgres;

--
-- Name: class; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.class (
    class_id integer DEFAULT nextval('public.class_seq'::regclass) NOT NULL,
    name character varying(16) NOT NULL,
    edition_id integer NOT NULL
);


ALTER TABLE public.class OWNER TO postgres;

--
-- Name: class_schedule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.class_schedule (
    class_id integer NOT NULL,
    department character varying(32) NOT NULL,
    classroom character varying(32) NOT NULL,
    start time without time zone NOT NULL,
    "end" time without time zone NOT NULL,
    weekday character varying(16) NOT NULL
);


ALTER TABLE public.class_schedule OWNER TO postgres;

--
-- Name: course_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.course_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.course_seq OWNER TO postgres;

--
-- Name: course; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.course (
    id integer DEFAULT nextval('public.course_seq'::regclass) NOT NULL,
    name character varying(64) NOT NULL,
    description text,
    ects integer DEFAULT 3 NOT NULL
);


ALTER TABLE public.course OWNER TO postgres;

--
-- Name: course_edition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.course_edition (
    edition_id integer NOT NULL,
    course_id integer NOT NULL
);


ALTER TABLE public.course_edition OWNER TO postgres;

--
-- Name: courses_degree; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.courses_degree (
    course_id integer NOT NULL,
    degree_id integer NOT NULL
);


ALTER TABLE public.courses_degree OWNER TO postgres;

--
-- Name: degree; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.degree (
    id integer NOT NULL,
    name character varying(512) NOT NULL,
    cost integer DEFAULT 0 NOT NULL,
    description text,
    staff_id integer NOT NULL
);


ALTER TABLE public.degree OWNER TO postgres;

--
-- Name: department_classroom; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.department_classroom (
    dep_id bigint NOT NULL,
    name character varying(512) NOT NULL,
    classroom_capacity integer NOT NULL,
    classroom_location text NOT NULL,
    theory_instructors_class_staff_person_id integer NOT NULL
);


ALTER TABLE public.department_classroom OWNER TO postgres;

--
-- Name: edition_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.edition_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.edition_seq OWNER TO postgres;

--
-- Name: edition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.edition (
    id integer DEFAULT nextval('public.edition_seq'::regclass) NOT NULL,
    ano integer NOT NULL,
    course_id integer NOT NULL,
    coordinator integer NOT NULL
);


ALTER TABLE public.edition OWNER TO postgres;

--
-- Name: edition_instructors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.edition_instructors (
    editon_id integer NOT NULL,
    instructor_id integer NOT NULL
);


ALTER TABLE public.edition_instructors OWNER TO postgres;

--
-- Name: edition_stats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.edition_stats (
    students_person_id integer NOT NULL,
    edition_id integer NOT NULL,
    passed boolean DEFAULT false NOT NULL,
    month integer DEFAULT 1
);


ALTER TABLE public.edition_stats OWNER TO postgres;

--
-- Name: employee; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employee (
    salario real NOT NULL,
    anos_servico integer NOT NULL,
    active boolean NOT NULL,
    numero_docente character varying(32) NOT NULL,
    person_id integer NOT NULL
);


ALTER TABLE public.employee OWNER TO postgres;

--
-- Name: evaluation_period; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.evaluation_period (
    period_id integer NOT NULL,
    name character varying(64) NOT NULL,
    weight_pct numeric(5,2) NOT NULL
);


ALTER TABLE public.evaluation_period OWNER TO postgres;

--
-- Name: evaluation_period_period_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.evaluation_period_period_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.evaluation_period_period_id_seq OWNER TO postgres;

--
-- Name: evaluation_period_period_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.evaluation_period_period_id_seq OWNED BY public.evaluation_period.period_id;


--
-- Name: grades; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.grades (
    grade real NOT NULL,
    weight real NOT NULL
);


ALTER TABLE public.grades OWNER TO postgres;

--
-- Name: grades_edition_stats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.grades_edition_stats (
    students_person_id integer NOT NULL,
    edition_id integer NOT NULL,
    period_id integer NOT NULL,
    grade numeric(5,2) NOT NULL
);


ALTER TABLE public.grades_edition_stats OWNER TO postgres;

--
-- Name: instructors; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.instructors (
    area character varying(32) NOT NULL,
    instructor_person_id integer NOT NULL
);


ALTER TABLE public.instructors OWNER TO postgres;

--
-- Name: invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.invoices (
    id integer NOT NULL,
    status boolean DEFAULT false NOT NULL,
    cost money,
    staff_id integer,
    students_id integer NOT NULL
);


ALTER TABLE public.invoices OWNER TO postgres;

--
-- Name: invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.invoices_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invoices_id_seq OWNER TO postgres;

--
-- Name: invoices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.invoices_id_seq OWNED BY public.invoices.id;


--
-- Name: lesson; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lesson (
    class_start timestamp without time zone NOT NULL,
    duracao smallint DEFAULT 60 NOT NULL,
    abstract text,
    department_classroom_dep_id bigint NOT NULL,
    theory_instructors_class_staff_person_id integer NOT NULL
);


ALTER TABLE public.lesson OWNER TO postgres;

--
-- Name: passed_students_by_edition; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.passed_students_by_edition AS
 SELECT e.ano,
    es.month,
    count(*) AS passed_students_count
   FROM (public.edition_stats es
     JOIN public.edition e ON ((e.id = es.edition_id)))
  WHERE (es.passed = true)
  GROUP BY e.ano, es.month;


ALTER VIEW public.passed_students_by_edition OWNER TO postgres;

--
-- Name: person; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.person (
    id integer NOT NULL,
    name text NOT NULL,
    nif text NOT NULL,
    cc text NOT NULL,
    email_pessoal character varying(128) NOT NULL,
    phone character(16) NOT NULL,
    gender character(1) NOT NULL,
    password character varying NOT NULL,
    role character varying NOT NULL,
    district character varying(512),
    email_institucional character varying(128) NOT NULL
);


ALTER TABLE public.person OWNER TO postgres;

--
-- Name: person_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.person_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.person_id_seq OWNER TO postgres;

--
-- Name: person_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.person_id_seq OWNED BY public.person.id;


--
-- Name: practical; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.practical (
    class_id integer NOT NULL,
    instructor_id integer NOT NULL,
    capacity integer NOT NULL,
    min_attendance integer NOT NULL
);


ALTER TABLE public.practical OWNER TO postgres;

--
-- Name: prereq_courses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.prereq_courses (
    course integer NOT NULL,
    req_course integer NOT NULL
);


ALTER TABLE public.prereq_courses OWNER TO postgres;

--
-- Name: staff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff (
    staff_person_id integer NOT NULL
);


ALTER TABLE public.staff OWNER TO postgres;

--
-- Name: students; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students (
    average real,
    numero_estudante character varying(512) NOT NULL,
    person_id integer NOT NULL
);


ALTER TABLE public.students OWNER TO postgres;

--
-- Name: students_activity; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students_activity (
    activity_id integer NOT NULL,
    students_id integer NOT NULL
);


ALTER TABLE public.students_activity OWNER TO postgres;

--
-- Name: students_classes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students_classes (
    student_id integer NOT NULL,
    class_id integer NOT NULL
);


ALTER TABLE public.students_classes OWNER TO postgres;

--
-- Name: students_degree; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students_degree (
    students_id integer NOT NULL,
    degree_id integer NOT NULL,
    staff_id integer
);


ALTER TABLE public.students_degree OWNER TO postgres;

--
-- Name: students_edition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students_edition (
    student_id integer NOT NULL,
    edition_id integer NOT NULL
);


ALTER TABLE public.students_edition OWNER TO postgres;

--
-- Name: theory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.theory (
    instructor_id integer NOT NULL
);


ALTER TABLE public.theory OWNER TO postgres;

--
-- Name: top_students_by_district; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.top_students_by_district AS
 WITH ranked_students AS (
         SELECT p.district,
            s.person_id,
            s.average,
            row_number() OVER (PARTITION BY p.district ORDER BY s.average DESC) AS rank
           FROM (public.students s
             JOIN public.person p ON ((s.person_id = p.id)))
        )
 SELECT district,
    person_id,
    average
   FROM ranked_students
  WHERE (rank = 1);


ALTER VIEW public.top_students_by_district OWNER TO postgres;

--
-- Name: evaluation_period period_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evaluation_period ALTER COLUMN period_id SET DEFAULT nextval('public.evaluation_period_period_id_seq'::regclass);


--
-- Name: invoices id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices ALTER COLUMN id SET DEFAULT nextval('public.invoices_id_seq'::regclass);


--
-- Name: person id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person ALTER COLUMN id SET DEFAULT nextval('public.person_id_seq'::regclass);


--
-- Data for Name: activity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.activity (description, id, name, cost) FROM stdin;
febrada by nei (bar aberto)	1	febrada	$5.99
\.


--
-- Data for Name: attendance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance (students_person_id) FROM stdin;
\.


--
-- Data for Name: class; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.class (class_id, name, edition_id) FROM stdin;
1	bd	1
2	so	1
\.


--
-- Data for Name: class_schedule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.class_schedule (class_id, department, classroom, start, "end", weekday) FROM stdin;
1	dei	1	23:00:00	21:00:00	1
\.


--
-- Data for Name: course; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.course (id, name, description, ects) FROM stdin;
1	ikea ipaaicspicsp	welocme	6
\.


--
-- Data for Name: course_edition; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.course_edition (edition_id, course_id) FROM stdin;
1	1
\.


--
-- Data for Name: courses_degree; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.courses_degree (course_id, degree_id) FROM stdin;
1	1
\.


--
-- Data for Name: degree; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.degree (id, name, cost, description, staff_id) FROM stdin;
1	Engenharia	2	5	21
\.


--
-- Data for Name: department_classroom; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.department_classroom (dep_id, name, classroom_capacity, classroom_location, theory_instructors_class_staff_person_id) FROM stdin;
1	c.5.2	50	texas	1
\.


--
-- Data for Name: edition; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.edition (id, ano, course_id, coordinator) FROM stdin;
1	1999	1	24
\.


--
-- Data for Name: edition_instructors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.edition_instructors (editon_id, instructor_id) FROM stdin;
1	24
1	1
\.


--
-- Data for Name: edition_stats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.edition_stats (students_person_id, edition_id, passed, month) FROM stdin;
11	1	t	1
13	1	f	1
37	1	t	1
\.


--
-- Data for Name: employee; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employee (salario, anos_servico, active, numero_docente, person_id) FROM stdin;
7128	4	t	uc200032	21
9994	4	t	uc1111	24
7128	4	t	uc222422	28
7128	4	t	uc222469	29
7128	4	t	uc222469	30
7128	4	t	uc222469	31
7128	4	t	uc222433369	38
9994	4	t	uc122111	39
\.


--
-- Data for Name: evaluation_period; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.evaluation_period (period_id, name, weight_pct) FROM stdin;
1	teste pratico	20.00
2	projeto	40.00
3	teste teorico	40.00
4	recurso	100.00
\.


--
-- Data for Name: grades; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.grades (grade, weight) FROM stdin;
\.


--
-- Data for Name: grades_edition_stats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.grades_edition_stats (students_person_id, edition_id, period_id, grade) FROM stdin;
37	1	1	10.00
37	1	2	10.00
37	1	3	10.00
37	1	4	50.00
\.


--
-- Data for Name: instructors; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.instructors (area, instructor_person_id) FROM stdin;
2x2	1
comp sci	24
comp sci	39
\.


--
-- Data for Name: invoices; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.invoices (id, status, cost, staff_id, students_id) FROM stdin;
1	f	$2.00	21	23
3	f	$2.00	21	37
4	f	$5.99	\N	37
\.


--
-- Data for Name: lesson; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lesson (class_start, duracao, abstract, department_classroom_dep_id, theory_instructors_class_staff_person_id) FROM stdin;
\.


--
-- Data for Name: person; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.person (id, name, nif, cc, email_pessoal, phone, gender, password, role, district, email_institucional) FROM stdin;
24	cleverson	522	9251	2@skbi.com	+351 111 223 123	M	$2b$12$tyRfQljuq/DztPk3J/6oiemu1PaeFcb3Iqj/K.piVIMZjm/fbAUlW	instructor	\N	cuh@uc.pt
1	joao instrutor	98724198422	3212	joao@dei.uc.pt	+351 222 222 222	m	$2b$12$bW1kBfzIpD05mCQzfhxN5OAlMIkxi/w4Qdy.RPDOb3GCfEcCgWbbO	instructor	Lisboa	a@a.c
27	João Silva	123456789	987654321	joao.silva@gmail.com	+351 912 345 678	M	senha_segura_123	student	Porto	joao.silva@universidade.pt
28	bett4a	9871312	1234336	bett44@gmail.com	+351 112 996 123	M	$2b$12$VHmFTy9bXC.I9A.UAmy.SOczWZfXlDIS347MI2WPju6U0Juwk/oRy	staff	\N	betat23@uc.pt
29	beta	$2b$12$DUfzY9TxKkfRcf6qDHM7heK7WRYI1PGzBoMxyG.qEpbfHHJL.9psW	$2b$12$.asIoXaPlyCslgWCfOHM8OENCsJ...gC0UhQUI7PdnB9p2TxZFmI2	beta@gmail.com	+351 112 116 123	M	$2b$12$Q6gy0X353XkvcCke6zxOOOMt.bQcPHL1rbEY7ETfoYLFLxqRXPsWa	staff	\N	beta69@uc.pt
32	slqa32	$2b$12$BQJ9cQmN4OtR7gJNtm12wOYQpThweP9007A/MIKRRtWLrukHCw5ki	$2b$12$bvweXQiM/TEymAbDQgyO3e6MMmkc8AccJ5JLhcRErvYufJtBRG7NO	sk@askau32.com	+999 143 155 763	M	$2b$12$P0g2wP2dCdFB7GDj74nVB.gPXEOsZfbyeU4mAO.tcShIVSyCYgCF6	student	\N	cmi211222@uc.pt
7	staff	987241984244	1234	staff@gmail.com	+351 123 123 123	m	$2b$12$bW1kBfzIpD05mCQzfhxN5OAlMIkxi/w4Qdy.RPDOb3GCfEcCgWbbO	staff	Abrantes	v@b.c
11	studenttest	123	3	student@gmail.com	+351 312 123 123	m	$2b$12$rsGcL1dsLtzhYGbrNea0euqlYPTGtFNXOKVPbHZ1jgWRHugVLxt36	student	Coimbra	alpa@gmail.com
13	studenttest2	9872211842132	2334	student2@gmail.com	+351 313 123 123	m	$2b$12$OVt6ZCo5qVDnmSqCGUAGGeAM53WzsRZKFHywyf6M9StjvU8VD8LQ.	student	Polo Norte	teste@gmail.com
21	behelitta	9872419842145	1234566	behelita@gmail.com	+351 123 666 123	M	$2b$12$pAmZjdF/T3pzQ1rjalaugexyClMLhNZ7c.HuhjrRW2fOyZUmlSIzO	staff	\N	behelita23@uc.pt
14	behelit	9872419842122	12345	behelit@gmail.com	+351 123 123 123	M	$2b$12$cuRkIloBd49B8QqqtJVxm./5bo70kKKNV9lfQ47bX5c7ZP2WaCbAa	staff	California	teste2@gmail.com
37	slq2232	$2b$12$pnyCIVVoPb07G3igN9/7bugHcGpKqxD.rJLA1KRL3VIPKoOzHm/GC	$2b$12$E6FA3OygkluwHmxRkjI4OeTuIGLQW5LnwvzkTnmX1hhFV6Lrq8RRm	sk@ask22u32.com	+999 123 155 763	M	$2b$12$cVEtv9rRggyDEBoM6A654ec4zIX.VuTKWvyECk.GRKNTAHm8kG426	student	\N	cmi2112222@uc.pt
38	bet2a	$2b$12$/W.gqRhLUXoj3KmiXWUg2OfiERytI2tKBve5QEVdTeUeQvArPI4LC	$2b$12$7jdTB7VaYoL//TPkQi.COOneKRtGuVoExHNZ/slKGuH36WOL9rl7m	beta421@gmail.com	+351 112 226 123	M	$2b$12$y9HwTf/3ZNZfr0LfDuD.f.znfCMlnjpnbuRg/QqTMmmcq.4n23F2C	staff	\N	beta369@uc.pt
39	cleversontemsp	$2b$12$rvPtKtJZrOG19FqNrfX3gOQFW6U8duMhLuU1HyJAjtuetHm6kraj2	$2b$12$jXcA6sQGT7q3fLKmyPk3VO1oLvGhVejzdWvpjdGYZvaBzLGDrhkRa	2@skbdi.com	+351 122 223 123	M	$2b$12$erZOorZ.Rh9qAPGQWvQBmOpjQZKElteACW4hTfhVlZ5nJKmTkY1fC	instructor	\N	cuh22@uc.pt
\.


--
-- Data for Name: practical; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.practical (class_id, instructor_id, capacity, min_attendance) FROM stdin;
\.


--
-- Data for Name: prereq_courses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.prereq_courses (course, req_course) FROM stdin;
\.


--
-- Data for Name: staff; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.staff (staff_person_id) FROM stdin;
21
28
29
30
31
38
\.


--
-- Data for Name: students; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students (average, numero_estudante, person_id) FROM stdin;
10	123412678	11
10	123412678	13
17	uc23231442342	32
17	uc232314432342	37
\.


--
-- Data for Name: students_activity; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students_activity (activity_id, students_id) FROM stdin;
1	37
\.


--
-- Data for Name: students_classes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students_classes (student_id, class_id) FROM stdin;
37	2
\.


--
-- Data for Name: students_degree; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students_degree (students_id, degree_id, staff_id) FROM stdin;
37	1	21
\.


--
-- Data for Name: students_edition; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students_edition (student_id, edition_id) FROM stdin;
\.


--
-- Data for Name: theory; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.theory (instructor_id) FROM stdin;
\.


--
-- Name: class_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.class_seq', 1, false);


--
-- Name: course_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.course_seq', 1, false);


--
-- Name: edition_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.edition_seq', 1, false);


--
-- Name: evaluation_period_period_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.evaluation_period_period_id_seq', 1, false);


--
-- Name: invoices_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.invoices_id_seq', 4, true);


--
-- Name: person_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.person_id_seq', 40, true);


--
-- Name: activity activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_pkey PRIMARY KEY (id);


--
-- Name: staff admin_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT admin_pkey PRIMARY KEY (staff_person_id);


--
-- Name: class class_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.class
    ADD CONSTRAINT class_pkey PRIMARY KEY (class_id);


--
-- Name: class_schedule class_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.class_schedule
    ADD CONSTRAINT class_schedule_pkey PRIMARY KEY (weekday, start, class_id);


--
-- Name: course_edition course_edition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_edition
    ADD CONSTRAINT course_edition_pkey PRIMARY KEY (edition_id, course_id);


--
-- Name: course course_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course
    ADD CONSTRAINT course_pkey PRIMARY KEY (id);


--
-- Name: courses_degree courses_degree_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.courses_degree
    ADD CONSTRAINT courses_degree_pkey PRIMARY KEY (degree_id, course_id);


--
-- Name: degree degree_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.degree
    ADD CONSTRAINT degree_pkey PRIMARY KEY (id);


--
-- Name: department_classroom department_classroom_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.department_classroom
    ADD CONSTRAINT department_classroom_pkey PRIMARY KEY (dep_id);


--
-- Name: edition_instructors edition_instructors_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition_instructors
    ADD CONSTRAINT edition_instructors_pkey PRIMARY KEY (editon_id, instructor_id);


--
-- Name: edition edition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition
    ADD CONSTRAINT edition_pkey PRIMARY KEY (id);


--
-- Name: edition_stats edition_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition_stats
    ADD CONSTRAINT edition_stats_pkey PRIMARY KEY (edition_id, students_person_id);


--
-- Name: edition_stats edition_stats_students_person_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition_stats
    ADD CONSTRAINT edition_stats_students_person_id_key UNIQUE (students_person_id);


--
-- Name: evaluation_period evaluation_period_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evaluation_period
    ADD CONSTRAINT evaluation_period_pkey PRIMARY KEY (period_id);


--
-- Name: grades_edition_stats ges_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_edition_stats
    ADD CONSTRAINT ges_pkey PRIMARY KEY (students_person_id, edition_id, period_id);


--
-- Name: instructors instructor_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.instructors
    ADD CONSTRAINT instructor_pkey PRIMARY KEY (instructor_person_id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: edition_stats monthcheck; Type: CHECK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE public.edition_stats
    ADD CONSTRAINT monthcheck CHECK (((month >= 1) AND (month <= 12))) NOT VALID;


--
-- Name: person person_nif_cc_email_pessoal_phone_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT person_nif_cc_email_pessoal_phone_key UNIQUE (nif, cc, email_pessoal, phone);


--
-- Name: person person_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT person_pkey PRIMARY KEY (id);


--
-- Name: practical practical_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.practical
    ADD CONSTRAINT practical_pkey PRIMARY KEY (class_id);


--
-- Name: prereq_courses prereq_courses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prereq_courses
    ADD CONSTRAINT prereq_courses_pkey PRIMARY KEY (course, req_course);


--
-- Name: students_activity students_activity_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_activity
    ADD CONSTRAINT students_activity_pkey PRIMARY KEY (activity_id);


--
-- Name: students_classes students_classes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_classes
    ADD CONSTRAINT students_classes_pkey PRIMARY KEY (student_id, class_id);


--
-- Name: students_degree students_degree_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_degree
    ADD CONSTRAINT students_degree_pkey PRIMARY KEY (students_id, degree_id);


--
-- Name: students_edition students_edition_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_edition
    ADD CONSTRAINT students_edition_pkey PRIMARY KEY (student_id, edition_id);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (person_id);


--
-- Name: theory theory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theory
    ADD CONSTRAINT theory_pkey PRIMARY KEY (instructor_id);


--
-- Name: person unique_cc; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT unique_cc UNIQUE (cc);


--
-- Name: person unique_email_institucional; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT unique_email_institucional UNIQUE (email_institucional);


--
-- Name: person unique_nif; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT unique_nif UNIQUE (nif);


--
-- Name: students_activity trg_create_invoice_activity; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_create_invoice_activity AFTER INSERT ON public.students_activity FOR EACH ROW EXECUTE FUNCTION public.create_invoice_activity();


--
-- Name: students_degree trg_create_invoice_degree; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_create_invoice_degree AFTER INSERT ON public.students_degree FOR EACH ROW EXECUTE FUNCTION public.create_invoice_degree();


--
-- Name: grades_edition_stats trg_update_passed_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_passed_status AFTER INSERT OR UPDATE ON public.grades_edition_stats FOR EACH ROW EXECUTE FUNCTION public.update_passed_status();


--
-- Name: course_edition ce_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_edition
    ADD CONSTRAINT ce_fk FOREIGN KEY (edition_id) REFERENCES public.edition(id);


--
-- Name: course_edition ce_fk1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_edition
    ADD CONSTRAINT ce_fk1 FOREIGN KEY (course_id) REFERENCES public.course(id);


--
-- Name: edition coordinator id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition
    ADD CONSTRAINT "coordinator id" FOREIGN KEY (coordinator) REFERENCES public.instructors(instructor_person_id) NOT VALID;


--
-- Name: prereq_courses cour_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prereq_courses
    ADD CONSTRAINT cour_fk FOREIGN KEY (course) REFERENCES public.course(id) NOT VALID;


--
-- Name: edition course id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition
    ADD CONSTRAINT "course id" FOREIGN KEY (course_id) REFERENCES public.course(id) NOT VALID;


--
-- Name: edition_stats edition id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition_stats
    ADD CONSTRAINT "edition id" FOREIGN KEY (edition_id) REFERENCES public.edition(id) NOT VALID;


--
-- Name: grades_edition_stats ges_edition_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_edition_stats
    ADD CONSTRAINT ges_edition_fk FOREIGN KEY (edition_id) REFERENCES public.edition(id) ON DELETE CASCADE;


--
-- Name: grades_edition_stats ges_period_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_edition_stats
    ADD CONSTRAINT ges_period_fk FOREIGN KEY (period_id) REFERENCES public.evaluation_period(period_id) ON DELETE RESTRICT;


--
-- Name: grades_edition_stats ges_students_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_edition_stats
    ADD CONSTRAINT ges_students_fk FOREIGN KEY (students_person_id) REFERENCES public.students(person_id) ON DELETE CASCADE;


--
-- Name: theory instructor id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.theory
    ADD CONSTRAINT "instructor id" FOREIGN KEY (instructor_id) REFERENCES public.instructors(instructor_person_id) NOT VALID;


--
-- Name: department_classroom instructor_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.department_classroom
    ADD CONSTRAINT instructor_id FOREIGN KEY (theory_instructors_class_staff_person_id) REFERENCES public.instructors(instructor_person_id) NOT VALID;


--
-- Name: instructors person id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.instructors
    ADD CONSTRAINT "person id" FOREIGN KEY (instructor_person_id) REFERENCES public.person(id) NOT VALID;


--
-- Name: prereq_courses req_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prereq_courses
    ADD CONSTRAINT req_fk FOREIGN KEY (req_course) REFERENCES public.course(id) NOT VALID;


--
-- Name: students_degree staff_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_degree
    ADD CONSTRAINT staff_id_fk FOREIGN KEY (staff_id) REFERENCES public.staff(staff_person_id) NOT VALID;


--
-- Name: students_degree student id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_degree
    ADD CONSTRAINT "student id" FOREIGN KEY (students_id) REFERENCES public.students(person_id) ON DELETE CASCADE NOT VALID;


--
-- Name: edition_stats student id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.edition_stats
    ADD CONSTRAINT "student id" FOREIGN KEY (students_person_id) REFERENCES public.students(person_id) ON DELETE CASCADE NOT VALID;


--
-- Name: students_activity student id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_activity
    ADD CONSTRAINT "student id" FOREIGN KEY (students_id) REFERENCES public.students(person_id) ON DELETE CASCADE NOT VALID;


--
-- Name: students_edition student_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_edition
    ADD CONSTRAINT student_id FOREIGN KEY (student_id) REFERENCES public.students(person_id) NOT VALID;


--
-- Name: students_classes student_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_classes
    ADD CONSTRAINT student_id FOREIGN KEY (student_id) REFERENCES public.students(person_id) ON DELETE CASCADE NOT VALID;


--
-- Name: students_degree students_degree_fk2; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_degree
    ADD CONSTRAINT students_degree_fk2 FOREIGN KEY (degree_id) REFERENCES public.degree(id);


--
-- Name: students_classes students_ed_fk1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_classes
    ADD CONSTRAINT students_ed_fk1 FOREIGN KEY (class_id) REFERENCES public.class(class_id) NOT VALID;


--
-- Name: students studentsfk1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT studentsfk1 FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE NOT VALID;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT ALL ON SCHEMA public TO app_admin;


--
-- Name: FUNCTION create_invoice_activity(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.create_invoice_activity() TO app_admin;


--
-- Name: FUNCTION create_invoice_degree(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.create_invoice_degree() TO app_admin;


--
-- Name: FUNCTION enroll_course_edition(p_student_person_id integer, p_edition_id integer, p_class_ids integer[]); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.enroll_course_edition(p_student_person_id integer, p_edition_id integer, p_class_ids integer[]) TO app_student;
GRANT ALL ON FUNCTION public.enroll_course_edition(p_student_person_id integer, p_edition_id integer, p_class_ids integer[]) TO app_admin;


--
-- Name: FUNCTION fn_register_instructor(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean, p_area text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_register_instructor(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean, p_area text) TO app_staff;
GRANT ALL ON FUNCTION public.fn_register_instructor(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean, p_area text) TO app_admin;


--
-- Name: FUNCTION fn_register_staff(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_register_staff(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean) TO app_staff;
GRANT ALL ON FUNCTION public.fn_register_staff(p_name text, p_email_pessoal text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_docente text, p_salario real, p_anos_servico integer, p_active boolean) TO app_admin;


--
-- Name: FUNCTION fn_register_student(p_name text, p_email text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_estudante text, p_average real); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_register_student(p_name text, p_email text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_estudante text, p_average real) TO app_staff;
GRANT ALL ON FUNCTION public.fn_register_student(p_name text, p_email text, p_cc text, p_nif text, p_gender text, p_phone text, p_password text, p_email_inst text, p_numero_estudante text, p_average real) TO app_admin;


--
-- Name: FUNCTION get_course_editions_by_degree(p_degree_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_course_editions_by_degree(p_degree_id integer) TO app_staff;
GRANT ALL ON FUNCTION public.get_course_editions_by_degree(p_degree_id integer) TO app_admin;


--
-- Name: FUNCTION get_student_courses(student_id_param integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_student_courses(student_id_param integer) TO app_student;
GRANT ALL ON FUNCTION public.get_student_courses(student_id_param integer) TO app_staff;
GRANT ALL ON FUNCTION public.get_student_courses(student_id_param integer) TO app_admin;


--
-- Name: FUNCTION prevent_prereq_func(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.prevent_prereq_func() TO app_admin;


--
-- Name: FUNCTION update_passed_status(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_passed_status() TO app_admin;


--
-- Name: TABLE activity; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.activity TO app_student;
GRANT SELECT ON TABLE public.activity TO app_instructor;
GRANT SELECT ON TABLE public.activity TO app_staff;
GRANT ALL ON TABLE public.activity TO app_admin;


--
-- Name: TABLE attendance; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.attendance TO app_admin;


--
-- Name: SEQUENCE class_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.class_seq TO app_admin;


--
-- Name: TABLE class; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.class TO app_admin;


--
-- Name: TABLE class_schedule; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.class_schedule TO app_admin;


--
-- Name: SEQUENCE course_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.course_seq TO app_admin;


--
-- Name: TABLE course; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.course TO app_student;
GRANT SELECT ON TABLE public.course TO app_instructor;
GRANT SELECT ON TABLE public.course TO app_staff;
GRANT ALL ON TABLE public.course TO app_admin;


--
-- Name: TABLE course_edition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.course_edition TO app_student;
GRANT SELECT ON TABLE public.course_edition TO app_instructor;
GRANT SELECT ON TABLE public.course_edition TO app_staff;
GRANT ALL ON TABLE public.course_edition TO app_admin;


--
-- Name: TABLE courses_degree; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.courses_degree TO app_admin;


--
-- Name: TABLE degree; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.degree TO app_student;
GRANT SELECT ON TABLE public.degree TO app_instructor;
GRANT SELECT,INSERT ON TABLE public.degree TO app_staff;
GRANT ALL ON TABLE public.degree TO app_admin;


--
-- Name: TABLE department_classroom; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.department_classroom TO app_admin;


--
-- Name: SEQUENCE edition_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.edition_seq TO app_admin;


--
-- Name: TABLE edition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.edition TO app_student;
GRANT SELECT ON TABLE public.edition TO app_instructor;
GRANT SELECT ON TABLE public.edition TO app_staff;
GRANT ALL ON TABLE public.edition TO app_admin;


--
-- Name: TABLE edition_instructors; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.edition_instructors TO app_admin;


--
-- Name: TABLE edition_stats; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.edition_stats TO app_student;
GRANT SELECT ON TABLE public.edition_stats TO app_instructor;
GRANT SELECT ON TABLE public.edition_stats TO app_staff;
GRANT ALL ON TABLE public.edition_stats TO app_admin;


--
-- Name: TABLE employee; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.employee TO app_admin;


--
-- Name: TABLE evaluation_period; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.evaluation_period TO app_student;
GRANT SELECT ON TABLE public.evaluation_period TO app_instructor;
GRANT SELECT ON TABLE public.evaluation_period TO app_staff;
GRANT ALL ON TABLE public.evaluation_period TO app_admin;


--
-- Name: SEQUENCE evaluation_period_period_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.evaluation_period_period_id_seq TO app_admin;


--
-- Name: TABLE grades; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.grades TO app_admin;


--
-- Name: TABLE grades_edition_stats; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT,UPDATE ON TABLE public.grades_edition_stats TO app_instructor;
GRANT ALL ON TABLE public.grades_edition_stats TO app_admin;


--
-- Name: TABLE instructors; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT ON TABLE public.instructors TO app_staff;
GRANT ALL ON TABLE public.instructors TO app_admin;


--
-- Name: TABLE invoices; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE ON TABLE public.invoices TO app_staff;
GRANT ALL ON TABLE public.invoices TO app_admin;


--
-- Name: SEQUENCE invoices_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.invoices_id_seq TO app_admin;


--
-- Name: TABLE lesson; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.lesson TO app_admin;


--
-- Name: TABLE passed_students_by_edition; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.passed_students_by_edition TO app_staff;
GRANT ALL ON TABLE public.passed_students_by_edition TO app_admin;


--
-- Name: TABLE person; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.person TO app_student;
GRANT SELECT,DELETE ON TABLE public.person TO app_staff;
GRANT ALL ON TABLE public.person TO app_admin;


--
-- Name: SEQUENCE person_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.person_id_seq TO app_admin;


--
-- Name: TABLE practical; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.practical TO app_admin;


--
-- Name: TABLE prereq_courses; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.prereq_courses TO app_admin;


--
-- Name: TABLE staff; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT ON TABLE public.staff TO app_staff;
GRANT ALL ON TABLE public.staff TO app_admin;


--
-- Name: TABLE students; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT ON TABLE public.students TO app_staff;
GRANT ALL ON TABLE public.students TO app_admin;


--
-- Name: TABLE students_activity; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT ON TABLE public.students_activity TO app_student;
GRANT INSERT ON TABLE public.students_activity TO app_staff;
GRANT ALL ON TABLE public.students_activity TO app_admin;


--
-- Name: TABLE students_classes; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.students_classes TO app_student;
GRANT SELECT ON TABLE public.students_classes TO app_staff;
GRANT ALL ON TABLE public.students_classes TO app_admin;


--
-- Name: TABLE students_degree; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT ON TABLE public.students_degree TO app_staff;
GRANT ALL ON TABLE public.students_degree TO app_admin;


--
-- Name: TABLE students_edition; Type: ACL; Schema: public; Owner: postgres
--

GRANT INSERT ON TABLE public.students_edition TO app_student;
GRANT ALL ON TABLE public.students_edition TO app_admin;


--
-- Name: TABLE theory; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.theory TO app_admin;


--
-- Name: TABLE top_students_by_district; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.top_students_by_district TO app_staff;
GRANT ALL ON TABLE public.top_students_by_district TO app_admin;


--
-- PostgreSQL database dump complete
--

