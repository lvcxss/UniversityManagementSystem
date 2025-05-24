CREATE TABLE IF NOT EXISTS public.evaluation_period
(
    period_id   SERIAL      PRIMARY KEY,
    name        VARCHAR(64) NOT NULL,       
    weight_pct  NUMERIC(5,2) NOT NULL       -- deixei pct de porcentagem (defesa helper, ik)
);


DROP TABLE IF EXISTS public.grades_edition_stats;

CREATE TABLE IF NOT EXISTS public.grades_edition_stats
(
    students_person_id  INTEGER     NOT NULL,
    edition_id          INTEGER     NOT NULL,
    period_id           INTEGER     NOT NULL,
    grade               NUMERIC(5,2) NOT NULL,
    CONSTRAINT ges_pkey PRIMARY KEY (students_person_id, edition_id, period_id),
    CONSTRAINT ges_students_fk FOREIGN KEY (students_person_id)
      REFERENCES public.students(person_id) ON DELETE CASCADE,
    CONSTRAINT ges_edition_fk FOREIGN KEY (edition_id)
      REFERENCES public.edition(id) ON DELETE CASCADE,
    CONSTRAINT ges_period_fk FOREIGN KEY (period_id)
      REFERENCES public.evaluation_period(period_id) ON DELETE RESTRICT
);
