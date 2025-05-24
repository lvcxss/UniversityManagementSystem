CREATE OR REPLACE FUNCTION get_student_courses(
    student_id_param INTEGER
)
RETURNS TABLE (
    course_id INTEGER,
    course_name VARCHAR(64),  -- Matches CHARACTER VARYING(64)
    edition_year INTEGER,
    grade NUMERIC(5,2)       -- Matches NUMERIC(5,2)
) AS $$
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
$$ LANGUAGE plpgsql;
