-- STUDENT
CREATE ROLE app_student NOLOGIN;
GRANT SELECT
  ON public.course,
     public.degree,
     public.activity,
     public.edition,
     public.course_edition,
     public.evaluation_period,
     public.students_classes,
     public.edition_stats,
     public.person
TO app_student;
GRANT EXECUTE ON FUNCTION enroll_course_edition(integer, integer, integer[]),
	get_student_courses(integer)
TO app_student;
GRANT INSERT
  ON public.students_activity, 
   public.students_classes, 
   public.students_edition,
   public.edition_stats
TO app_student;

-- INSTRUCTOR
CREATE ROLE app_instructor NOLOGIN;
GRANT
  SELECT ON public.course,
            public.degree,
            public.activity,
            public.edition,
            public.course_edition,
            public.evaluation_period,
            public.edition_stats
TO app_instructor;
GRANT INSERT, UPDATE
  ON public.grades_edition_stats
TO app_instructor;

-- STAFF
CREATE ROLE app_staff NOLOGIN;
--read em todas as tables do aluno 
GRANT SELECT
  ON public.course,
     public.degree,
     public.activity,
     public.edition,
     public.course_edition,
     public.evaluation_period,
     public.students_classes,
     public.edition_stats,
     public.person
TO app_staff;
--todos os registers
GRANT EXECUTE
  ON FUNCTION fn_register_staff(text, text, text, text, text, text, text, text, text, real, integer, boolean),
      fn_register_student(text, text,  text, text, text, text, text, text, text,real),
      fn_register_instructor(text, text, text, text, text, text, text, text, text, real, integer, boolean, text)
TO app_staff;
-- gerir inscrições e invoices
GRANT INSERT
  ON public.staff,
     public.students,
     public.instructors,
     public.degree,
     public.students_degree,
     public.students_activity
TO app_staff;
GRANT UPDATE
  ON public.invoices
TO app_staff;
GRANT SELECT ON passed_students_by_edition, top_students_by_district TO app_staff;
GRANT EXECUTE
  ON FUNCTION get_student_courses(integer),
      get_course_editions_by_degree(integer)
TO app_staff;
-- apagar utilizador aluno
GRANT DELETE
  ON public.person
TO app_staff;

-- super user
CREATE ROLE app_admin NOLOGIN;
GRANT app_student, app_instructor, app_staff TO app_admin;
GRANT USAGE, CREATE ON SCHEMA public TO app_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app_admin;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_admin;
