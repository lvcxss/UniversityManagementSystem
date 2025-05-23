BEGIN;

CREATE TABLE IF NOT EXISTS public.activity
(
    description text COLLATE pg_catalog."default",
    id integer NOT NULL,
    name character varying(64) COLLATE pg_catalog."default" NOT NULL,
    cost money NOT NULL,
    CONSTRAINT activity_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.attendance
(
    students_person_id integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.class
(
    class_id integer NOT NULL DEFAULT nextval('class_seq'::regclass),
    name character varying(16) COLLATE pg_catalog."default" NOT NULL,
    edition_id integer NOT NULL,
    CONSTRAINT class_pkey PRIMARY KEY (class_id)
);

CREATE TABLE IF NOT EXISTS public.class_schedule
(
    class_id integer NOT NULL,
    department character varying(32) COLLATE pg_catalog."default" NOT NULL,
    classroom character varying(32) COLLATE pg_catalog."default" NOT NULL,
    start time without time zone NOT NULL,
    "end" time without time zone NOT NULL,
    weekday character varying(16) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT class_schedule_pkey PRIMARY KEY (weekday, start, class_id)
);

CREATE TABLE IF NOT EXISTS public.course
(
    id integer NOT NULL DEFAULT nextval('course_seq'::regclass),
    name character varying(64) COLLATE pg_catalog."default" NOT NULL,
    description text COLLATE pg_catalog."default",
    ects integer NOT NULL DEFAULT 3,
    CONSTRAINT course_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.course_edition
(
    edition_id integer NOT NULL,
    course_id integer NOT NULL,
    CONSTRAINT course_edition_pkey PRIMARY KEY (edition_id, course_id)
);

CREATE TABLE IF NOT EXISTS public.courses_degree
(
    course_id integer NOT NULL,
    degree_id integer NOT NULL,
    CONSTRAINT courses_degree_pkey PRIMARY KEY (degree_id, course_id)
);

CREATE TABLE IF NOT EXISTS public.degree
(
    id integer NOT NULL,
    name character varying(512) COLLATE pg_catalog."default" NOT NULL,
    cost money NOT NULL DEFAULT 0,
    description text COLLATE pg_catalog."default",
    staff_id integer NOT NULL,
    CONSTRAINT degree_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.department_classroom
(
    dep_id bigint NOT NULL,
    name character varying(512) COLLATE pg_catalog."default" NOT NULL,
    classroom_capacity integer NOT NULL,
    classroom_location text COLLATE pg_catalog."default" NOT NULL,
    theory_instructors_class_staff_person_id integer NOT NULL,
    CONSTRAINT department_classroom_pkey PRIMARY KEY (dep_id)
);

CREATE TABLE IF NOT EXISTS public.edition
(
    id integer NOT NULL DEFAULT nextval('edition_seq'::regclass),
    ano integer NOT NULL,
    course_id integer NOT NULL,
    coordinator integer NOT NULL,
    CONSTRAINT edition_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.edition_instructors
(
    ediiton_id integer NOT NULL,
    instructor_id integer NOT NULL,
    CONSTRAINT edition_instructors_pkey PRIMARY KEY (ediiton_id, instructor_id)
);

CREATE TABLE IF NOT EXISTS public.edition_stats
(
    passed boolean NOT NULL DEFAULT false,
    students_person_id integer NOT NULL,
    edition_id integer NOT NULL,
    CONSTRAINT edition_stats_pkey PRIMARY KEY (students_person_id, edition_id)
);

CREATE TABLE IF NOT EXISTS public.employee
(
    salario real NOT NULL,
    anos_servico integer NOT NULL,
    active boolean NOT NULL,
    numero_docente character varying(32) COLLATE pg_catalog."default" NOT NULL,
    person_id integer NOT NULL,
    CONSTRAINT staff_pkey PRIMARY KEY (person_id)
);

CREATE TABLE IF NOT EXISTS public.grades
(
    grade real NOT NULL,
    weight real NOT NULL
);

CREATE TABLE IF NOT EXISTS public.grades_edition_stats
(
)
;

CREATE TABLE IF NOT EXISTS public.instructors
(
    area character varying(32) COLLATE pg_catalog."default" NOT NULL,
    instructor_person_id integer NOT NULL,
    CONSTRAINT instructor_pkey PRIMARY KEY (instructor_person_id)
);

CREATE TABLE IF NOT EXISTS public.invoices
(
    id serial NOT NULL,
    status boolean NOT NULL DEFAULT false,
    cost money,
    staff_id integer,
    students_id integer NOT NULL,
    CONSTRAINT invoices_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.lesson
(
    class_start timestamp without time zone NOT NULL,
    duracao smallint NOT NULL DEFAULT 60,
    abstract text COLLATE pg_catalog."default",
    department_classroom_dep_id bigint NOT NULL,
    theory_instructors_class_staff_person_id integer NOT NULL
);

CREATE TABLE IF NOT EXISTS public.person
(
    id serial NOT NULL,
    name character varying(128) COLLATE pg_catalog."default" NOT NULL,
    nif bigint NOT NULL,
    cc bigint NOT NULL,
    email_pessoal character varying(128) COLLATE pg_catalog."default" NOT NULL,
    phone character(16) COLLATE pg_catalog."default" NOT NULL,
    gender character(16) COLLATE pg_catalog."default" NOT NULL,
    password character varying COLLATE pg_catalog."default" NOT NULL,
    email_institucional character varying(128) COLLATE pg_catalog."default" NOT NULL,
    role character varying(16) COLLATE pg_catalog."default",
    CONSTRAINT person_pkey PRIMARY KEY (id),
    CONSTRAINT person_nif_cc_email_pessoal_phone_key UNIQUE (nif, cc, email_pessoal, phone)
);

CREATE TABLE IF NOT EXISTS public.practical
(
    class_id integer NOT NULL,
    instructor_id integer NOT NULL,
    capacity integer NOT NULL,
    min_attendance integer NOT NULL,
    CONSTRAINT practical_pkey PRIMARY KEY (class_id)
);

CREATE TABLE IF NOT EXISTS public.prereq_courses
(
    course integer NOT NULL,
    req_course integer NOT NULL,
    CONSTRAINT prereq_courses_pkey PRIMARY KEY (course, req_course)
);

CREATE TABLE IF NOT EXISTS public.staff
(
    staff_person_id integer NOT NULL,
    CONSTRAINT admin_pkey PRIMARY KEY (staff_person_id)
);

CREATE TABLE IF NOT EXISTS public.students
(
    average real,
    numero_estudante character varying(512) COLLATE pg_catalog."default" NOT NULL,
    person_id integer NOT NULL,
    CONSTRAINT students_pkey PRIMARY KEY (person_id)
);

CREATE TABLE IF NOT EXISTS public.students_activity
(
    students_id integer NOT NULL,
    activity_id integer NOT NULL,
    CONSTRAINT students_activity_pkey PRIMARY KEY (activity_id, students_id)
);

CREATE TABLE IF NOT EXISTS public.students_classes
(
    student_id integer NOT NULL,
    class_id integer NOT NULL,
    CONSTRAINT students_classes_pkey PRIMARY KEY (student_id, class_id)
);

CREATE TABLE IF NOT EXISTS public.students_degree
(
    students_id integer NOT NULL,
    degree_id integer NOT NULL,
    staff_id integer NOT NULL,
    CONSTRAINT students_degree_pkey PRIMARY KEY (students_id, degree_id)
);

CREATE TABLE IF NOT EXISTS public.theory
(
    class_id integer NOT NULL,
    CONSTRAINT theory_pkey PRIMARY KEY (class_id)
);

ALTER TABLE IF EXISTS public.attendance
    ADD CONSTRAINT attendance_fk FOREIGN KEY (students_person_id)
    REFERENCES public.students (person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE
    NOT VALID;


ALTER TABLE IF EXISTS public.class
    ADD CONSTRAINT edition_fk FOREIGN KEY (edition_id)
    REFERENCES public.edition (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.course_edition
    ADD CONSTRAINT ce_fk FOREIGN KEY (edition_id)
    REFERENCES public.edition (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;


ALTER TABLE IF EXISTS public.course_edition
    ADD CONSTRAINT ce_fk1 FOREIGN KEY (course_id)
    REFERENCES public.course (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;


ALTER TABLE IF EXISTS public.courses_degree
    ADD CONSTRAINT course_id FOREIGN KEY (course_id)
    REFERENCES public.course (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.courses_degree
    ADD CONSTRAINT degree_fk FOREIGN KEY (degree_id)
    REFERENCES public.degree (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;


ALTER TABLE IF EXISTS public.degree
    ADD CONSTRAINT degree_fk1 FOREIGN KEY (staff_id)
    REFERENCES public.staff (staff_person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;


ALTER TABLE IF EXISTS public.edition
    ADD CONSTRAINT coordinator_id_fk FOREIGN KEY (coordinator)
    REFERENCES public.instructors (instructor_person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.edition
    ADD CONSTRAINT course_id_fk FOREIGN KEY (course_id)
    REFERENCES public.course (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.edition_instructors
    ADD CONSTRAINT instructor_id_fk FOREIGN KEY (ediiton_id)
    REFERENCES public.edition (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.edition_stats
    ADD CONSTRAINT ed_stats_fk FOREIGN KEY (edition_id)
    REFERENCES public.edition (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.edition_stats
    ADD CONSTRAINT edition_stats_fk FOREIGN KEY (students_person_id)
    REFERENCES public.students (person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE
    NOT VALID;


ALTER TABLE IF EXISTS public.employee
    ADD CONSTRAINT staff_fk1 FOREIGN KEY (person_id)
    REFERENCES public.person (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;
CREATE INDEX IF NOT EXISTS staff_pkey
    ON public.employee(person_id);


ALTER TABLE IF EXISTS public.instructors
    ADD CONSTRAINT instructor_id_fk FOREIGN KEY (instructor_person_id)
    REFERENCES public.person (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;
CREATE INDEX IF NOT EXISTS instructor_pkey
    ON public.instructors(instructor_person_id);


ALTER TABLE IF EXISTS public.invoices
    ADD CONSTRAINT invoices_fk1 FOREIGN KEY (staff_id)
    REFERENCES public.staff (staff_person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;


ALTER TABLE IF EXISTS public.invoices
    ADD CONSTRAINT invoices_fk2 FOREIGN KEY (students_id)
    REFERENCES public.students (person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE
    NOT VALID;


ALTER TABLE IF EXISTS public.lesson
    ADD CONSTRAINT lesson_fk1 FOREIGN KEY (department_classroom_dep_id)
    REFERENCES public.department_classroom (dep_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;


ALTER TABLE IF EXISTS public.prereq_courses
    ADD CONSTRAINT cour_fk FOREIGN KEY (course)
    REFERENCES public.course (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.prereq_courses
    ADD CONSTRAINT req_fk FOREIGN KEY (req_course)
    REFERENCES public.course (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.staff
    ADD CONSTRAINT admin_fk1 FOREIGN KEY (staff_person_id)
    REFERENCES public.employee (person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;
CREATE INDEX IF NOT EXISTS admin_pkey
    ON public.staff(staff_person_id);


ALTER TABLE IF EXISTS public.students
    ADD CONSTRAINT students_fk FOREIGN KEY (person_id)
    REFERENCES public.person (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE
    NOT VALID;
CREATE INDEX IF NOT EXISTS students_pkey
    ON public.students(person_id);


ALTER TABLE IF EXISTS public.students_activity
    ADD CONSTRAINT activity_id_fk FOREIGN KEY (activity_id)
    REFERENCES public.activity (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.students_activity
    ADD CONSTRAINT students_activity_fk FOREIGN KEY (students_id)
    REFERENCES public.students (person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE
    NOT VALID;


ALTER TABLE IF EXISTS public.students_classes
    ADD CONSTRAINT students_ed_fk FOREIGN KEY (student_id)
    REFERENCES public.students (person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE
    NOT VALID;


ALTER TABLE IF EXISTS public.students_classes
    ADD CONSTRAINT students_ed_fk1 FOREIGN KEY (class_id)
    REFERENCES public.class (class_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.students_degree
    ADD CONSTRAINT staff_id_fk FOREIGN KEY (staff_id)
    REFERENCES public.staff (staff_person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.students_degree
    ADD CONSTRAINT students_degree_fk1 FOREIGN KEY (students_id)
    REFERENCES public.students (person_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE CASCADE
    NOT VALID;


ALTER TABLE IF EXISTS public.students_degree
    ADD CONSTRAINT students_degree_fk2 FOREIGN KEY (degree_id)
    REFERENCES public.degree (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;


ALTER TABLE IF EXISTS public.theory
    ADD CONSTRAINT class_id_fk FOREIGN KEY (class_id)
    REFERENCES public.class (class_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;
CREATE INDEX IF NOT EXISTS theory_pkey
    ON public.theory(class_id);

END;
