CREATE TABLE edition_practical_assistant_instructors_course (
	capacity												 INTEGER NOT NULL,
	ano												 INTEGER NOT NULL,
	practical_assistant_instructors_turma								 VARCHAR(512) NOT NULL,
	practical_assistant_instructors_min_presencas							 INTEGER NOT NULL,
	course_id												 SERIAL NOT NULL,
	course_description										 TEXT,
	course_ects											 INTEGER NOT NULL DEFAULT 3,
	theory_instructors_class_staff_person_id								 INTEGER NOT NULL,
	theory_instructors_class_staff_person_id1								 INTEGER NOT NULL,
	instructors_class_area										 VARCHAR(512) NOT NULL,
	instructors_class_class_id									 BIGSERIAL NOT NULL,
	instructors_class_class_capacity									 SMALLINT,
	instructors_class_epaaicsicsp INTEGER NOT NULL,
	instructors_class_staff_person_id									 INTEGER,
	PRIMARY KEY(instructors_class_staff_person_id)
);

CREATE TABLE students (
	average		 FLOAT(8),
	numero_estudante VARCHAR(512) NOT NULL,
	email_estudante	 VARCHAR(512) NOT NULL,
	person_id	 INTEGER,
	PRIMARY KEY(person_id)
);

CREATE TABLE person (
	id		 SERIAL,
	name		 TEXT NOT NULL,
	nif		 BIGINT NOT NULL,
	cc		 BIGINT NOT NULL,
	email_pessoal VARCHAR(128) NOT NULL,
	phone	 CHAR(255) NOT NULL,
	male		 BOOL NOT NULL,
	PRIMARY KEY(id)
);

CREATE TABLE invoices (
	id			 INTEGER,
	status		 BOOL NOT NULL,
	cost			 INTEGER,
	admin_staff_person_id INTEGER NOT NULL,
	students_person_id	 INTEGER NOT NULL,
	PRIMARY KEY(id)
);

CREATE TABLE activity (
	name	 VARCHAR(512),
	cost	 FLOAT(8) NOT NULL,
	description TEXT,
	invoices_id INTEGER NOT NULL,
	PRIMARY KEY(name)
);

CREATE TABLE degree (
	id										 INTEGER,
	name										 VARCHAR(512) NOT NULL,
	cost										 INTEGER NOT NULL DEFAULT 0,
	description_									 TEXT,
	admin_staff_person_id								 INTEGER NOT NULL,
	invoices_id									 INTEGER NOT NULL,
	epaaicsicsp INTEGER NOT NULL,
	PRIMARY KEY(id)
);

CREATE TABLE theory (
	instructors_class_area										 VARCHAR(512) NOT NULL,
	instructors_class_class_id									 BIGSERIAL NOT NULL,
	instructors_class_class_capacity									 SMALLINT,
	instructors_class_epaaicsicsp INTEGER NOT NULL,
	instructors_class_staff_person_id									 INTEGER,
	PRIMARY KEY(instructors_class_staff_person_id)
);

CREATE TABLE department_classroom (
	dep_id					 BIGINT,
	name					 VARCHAR(512) NOT NULL,
	classroom_capacity			 INTEGER NOT NULL,
	classroom_location			 TEXT NOT NULL,
	theory_instructors_class_staff_person_id INTEGER NOT NULL,
	PRIMARY KEY(dep_id)
);

CREATE TABLE attendance (
	students_person_id INTEGER NOT NULL
);

CREATE TABLE edition_stats (
	passed		 BOOL NOT NULL DEFAULT False,
	students_person_id INTEGER NOT NULL
);

CREATE TABLE grades (
	grade	 FLOAT(5) NOT NULL,
	weight FLOAT(4) NOT NULL
);

CREATE TABLE lesson (
	class_start				 TIMESTAMP NOT NULL,
	duracao					 SMALLINT NOT NULL DEFAULT 60,
	abstract				 TEXT,
	department_classroom_dep_id		 BIGINT NOT NULL,
	theory_instructors_class_staff_person_id INTEGER NOT NULL
);

CREATE TABLE staff (
	salario	 FLOAT(8) NOT NULL,
	anos_servico	 INTEGER NOT NULL,
	active	 BOOL NOT NULL,
	numero_docente VARCHAR(512) NOT NULL,
	email_docente	 VARCHAR(512) NOT NULL,
	person_id	 INTEGER,
	PRIMARY KEY(person_id)
);

CREATE TABLE admin (
	staff_person_id INTEGER,
	PRIMARY KEY(staff_person_id)
);

CREATE TABLE grades_edition_stats (

);

CREATE TABLE edition_practical_assistance_course (
	epaaicsicsp INTEGER NOT NULL
);

CREATE TABLE students_activity (
	students_person_id INTEGER,
	activity_name	 VARCHAR(512),
	PRIMARY KEY(students_person_id,activity_name)
);

CREATE TABLE edition_practical_assistant_inst_course_self (
	epaaicsicsp	 INTEGER NOT NULL,
	epaaicsicsp1 INTEGER NOT NULL,
	PRIMARY KEY(epaaicsicsp,epaaicsicsp1)
);
CREATE TABLE instructors (
    instructor_person_id INTEGER,
    area VARCHAR(64), 
    PRIMARY KEY(instructor_person_id)
);
CREATE TABLE students_degree (
	students_person_id INTEGER,
	degree_id		 INTEGER,
	PRIMARY KEY(students_person_id,degree_id)
);

ALTER TABLE edition_practical_assistant_instructors_course ADD UNIQUE (course_id, theory_instructors_class_staff_person_id, instructors_class_class_id);
ALTER TABLE edition_practical_assistant_instructors_course ADD CONSTRAINT edition_practical_assistant_instructors_course_fk1 FOREIGN KEY (theory_instructors_class_staff_person_id) REFERENCES theory(instructors_class_staff_person_id);
ALTER TABLE edition_practical_assistant_instructors_course ADD CONSTRAINT edition_practical_assistant_instructors_course_fk2 FOREIGN KEY (theory_instructors_class_staff_person_id1) REFERENCES theory(instructors_class_staff_person_id);
ALTER TABLE edition_practical_assistant_instructors_course ADD CONSTRAINT edition_practical_assistant_instructors_course_fk3 FOREIGN KEY (instructors_class_epaaicsicsp) REFERENCES edition_practical_assistant_instructors_course(instructors_class_staff_person_id);
ALTER TABLE edition_practical_assistant_instructors_course ADD CONSTRAINT edition_practical_assistant_instructors_course_fk4 FOREIGN KEY (instructors_class_staff_person_id) REFERENCES staff(person_id);
ALTER TABLE students ADD UNIQUE (numero_estudante, email_estudante);
ALTER TABLE students ADD CONSTRAINT students_fk1 FOREIGN KEY (person_id) REFERENCES person(id);
ALTER TABLE person ADD UNIQUE (nif, cc, email_pessoal, phone);
ALTER TABLE invoices ADD CONSTRAINT invoices_fk1 FOREIGN KEY (admin_staff_person_id) REFERENCES admin(staff_person_id);
ALTER TABLE invoices ADD CONSTRAINT invoices_fk2 FOREIGN KEY (students_person_id) REFERENCES students(person_id);
ALTER TABLE activity ADD CONSTRAINT activity_fk1 FOREIGN KEY (invoices_id) REFERENCES invoices(id);
ALTER TABLE degree ADD UNIQUE (invoices_id);
ALTER TABLE degree ADD CONSTRAINT degree_fk1 FOREIGN KEY (admin_staff_person_id) REFERENCES admin(staff_person_id);
ALTER TABLE degree ADD CONSTRAINT degree_fk2 FOREIGN KEY (invoices_id) REFERENCES invoices(id);
ALTER TABLE degree ADD CONSTRAINT degree_fk3 FOREIGN KEY (epaaicsicsp) REFERENCES edition_practical_assistant_instructors_course(instructors_class_staff_person_id);
ALTER TABLE theory ADD UNIQUE (instructors_class_class_id);
ALTER TABLE theory ADD CONSTRAINT theory_fk1 FOREIGN KEY (instructors_class_epaaicsicsp) REFERENCES edition_practical_assistant_instructors_course(instructors_class_staff_person_id);
ALTER TABLE theory ADD CONSTRAINT theory_fk2 FOREIGN KEY (instructors_class_staff_person_id) REFERENCES staff(person_id);
ALTER TABLE department_classroom ADD CONSTRAINT department_classroom_fk1 FOREIGN KEY (theory_instructors_class_staff_person_id) REFERENCES theory(instructors_class_staff_person_id);
ALTER TABLE attendance ADD CONSTRAINT attendance_fk1 FOREIGN KEY (students_person_id) REFERENCES students(person_id);
ALTER TABLE edition_stats ADD UNIQUE (students_person_id);
ALTER TABLE edition_stats ADD CONSTRAINT edition_stats_fk1 FOREIGN KEY (students_person_id) REFERENCES students(person_id);
ALTER TABLE lesson ADD CONSTRAINT lesson_fk1 FOREIGN KEY (department_classroom_dep_id) REFERENCES department_classroom(dep_id);
ALTER TABLE lesson ADD CONSTRAINT lesson_fk2 FOREIGN KEY (theory_instructors_class_staff_person_id) REFERENCES theory(instructors_class_staff_person_id);
ALTER TABLE staff ADD CONSTRAINT staff_fk1 FOREIGN KEY (person_id) REFERENCES person(id);
ALTER TABLE admin ADD CONSTRAINT admin_fk1 FOREIGN KEY (staff_person_id) REFERENCES staff(person_id);
ALTER TABLE edition_practical_assistance_course ADD UNIQUE (epaaicsicsp);
ALTER TABLE edition_practical_assistance_course ADD CONSTRAINT edition_stats_practical_icourse_fk1 FOREIGN KEY (epaaicsicsp) REFERENCES edition_practical_assistant_instructors_course(instructors_class_staff_person_id);
ALTER TABLE students_activity ADD CONSTRAINT students_activity_fk1 FOREIGN KEY (students_person_id) REFERENCES students(person_id);
ALTER TABLE students_activity ADD CONSTRAINT students_activity_fk2 FOREIGN KEY (activity_name) REFERENCES activity(name);
ALTER TABLE edition_practical_assistant_inst_course_self ADD CONSTRAINT edition_practical_icourse_edition_fk1 FOREIGN KEY (epaaicsicsp) REFERENCES edition_practical_assistant_instructors_course(instructors_class_staff_person_id);
ALTER TABLE edition_practical_assistant_inst_course_self ADD CONSTRAINT edition_practical_assistant_instructors_course_edition_practical_assistant_instructors_course_fk2 FOREIGN KEY (epaaicsicsp1) REFERENCES edition_practical_assistant_instructors_course(instructors_class_staff_person_id);
ALTER TABLE students_degree ADD CONSTRAINT students_degree_fk1 FOREIGN KEY (students_person_id) REFERENCES students(person_id);
ALTER TABLE students_degree ADD CONSTRAINT students_degree_fk2 FOREIGN KEY (degree_id) REFERENCES degree(id);
