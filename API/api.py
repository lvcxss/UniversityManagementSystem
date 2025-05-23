import flask
import datetime
import logging
import psycopg as psycopg3
import jwt
from flask_bcrypt import Bcrypt
from flask import request, jsonify
from functools import wraps
from config import Config

app = flask.Flask(__name__)
app.config.from_object(Config)
bcrypt = Bcrypt(app)

StatusCodes = {
    "success": 200,
    "api_error": 400,
    "internal_error": 500,
    "unauthorized": 401,
}

##########################################################
## DATABASE ACCESS
##########################################################


def db_connection():
    return psycopg3.connect(
        user=Config.DB_USER,
        password=Config.DB_PASSWORD,
        host=Config.DB_HOST,
        port=Config.DB_PORT,
        dbname=Config.DB_NAME,
    )


##########################################################
## AUTHENTICATION HELPERS
##########################################################


def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        if not auth_header:
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Token is missing!",
                    "results": None,
                }
            ), 401
        try:
            token = auth_header.split()[1]
            payload = jwt.decode(token, Config.SECRET_KEY, algorithms=["HS256"])
            flask.g.person_id = payload["person_id"]
            flask.g.role = payload["role"]
        except jwt.ExpiredSignatureError:
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Token has expired!",
                    "results": None,
                }
            ), 401
        except jwt.InvalidTokenError as e:
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Invalid token!",
                    "results": None,
                }
            ), 401
        return f(*args, **kwargs)

    return decorated


def staff_required(f):
    @wraps(f)
    @token_required
    def decorated(*args, **kwargs):
        if flask.g.role != "staff":
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Permission denied: staff only",
                    "results": None,
                }
            ), 403
        return f(*args, **kwargs)

    return decorated


def student_required(f):
    @wraps(f)
    @token_required
    def decorated(*args, **kwargs):
        if flask.g.role != "student":
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Permission denied: student only",
                    "results": None,
                }
            ), 403
        return f(*args, **kwargs)

    return decorated


##########################################################
## ENDPOINTS
##########################################################


@app.route("/people/", methods=["GET"])
def people():
    logging.info("GET /people")
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT name, phone FROM person")
        rows = cur.fetchall()
        results = [
            {
                "name": row[0].strip(),
                "phone": row[1].strip(),
            }
            for row in rows
        ]
        return jsonify({"status": StatusCodes["success"], "results": results}), 200
    except Exception as e:
        logging.error(f"GET /people - error: {e}")
        return jsonify({"status": StatusCodes["internal_error"], "errors": str(e)}), 500
    finally:
        conn.close()


@app.route("/dbproj/register/staff", methods=["POST"])
def register_staff():
    data = request.get_json()
    required = [
        "name",
        "email",
        "phone",
        "cc",
        "nif",
        "gender",
        "password",
        "numero_docente",
        "salario",
        "anos_servico",
        "active",
        "email_institucional",
    ]
    if not all(data.get(k) is not None for k in required):
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        ), 400
    hashed_pw = bcrypt.generate_password_hash(data["password"]).decode()
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT fn_register_staff(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);",
            (
                data["name"],
                data["email"],
                data["cc"],
                data["nif"],
                data["gender"],
                data["phone"],
                hashed_pw,
                data["email_institucional"],
                data["numero_docente"],
                data["salario"],
                data["anos_servico"],
                data["active"],
            ),
        )
        person_id = cur.fetchone()[0]
        conn.commit()
        token = jwt.encode(
            {
                "role": "staff",
                "person_id": person_id,
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )
        return jsonify(
            {
                "status": StatusCodes["success"],
                "results": {
                    "access_token": token,
                    "person_id": person_id,
                    "numero_docente": data["numero_docente"],
                },
            }
        ), 200
    except Exception as e:
        conn.rollback()
        logging.error(f"POST /register/staff - error: {e}")
        return jsonify(
            {"status": StatusCodes["internal_error"], "errors": str(e), "results": None}
        ), 500
    finally:
        conn.close()


@app.route("/dbproj/register/student", methods=["POST"])
@staff_required
def register_student():
    data = request.get_json()
    required = [
        "name",
        "email",
        "phone",
        "cc",
        "nif",
        "gender",
        "password",
        "numero_estudante",
        "email_institucional",
        "average",
    ]
    if not all(data.get(k) is not None for k in required):
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        ), 400
    hashed_pw = bcrypt.generate_password_hash(data["password"]).decode()
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT fn_register_student(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);",
            (
                data["name"],
                data["email"],
                data["cc"],
                data["nif"],
                data["gender"],
                data["phone"],
                hashed_pw,
                data["email_institucional"],
                data["numero_estudante"],
                data["average"],
            ),
        )
        person_id = cur.fetchone()[0]
        conn.commit()
        token = jwt.encode(
            {
                "role": "student",
                "person_id": person_id,
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )
        return jsonify(
            {
                "status": StatusCodes["success"],
                "results": {
                    "access_token": token,
                    "person_id": person_id,
                    "numero_estudante": data["numero_estudante"],
                },
            }
        ), 200
    except Exception as e:
        conn.rollback()
        logging.error(f"POST /register/student - error: {e}")
        return jsonify(
            {"status": StatusCodes["internal_error"], "errors": str(e), "results": None}
        ), 500
    finally:
        conn.close()


@app.route("/dbproj/register/degree", methods=["POST"])
@staff_required
def register_degree():
    data = request.get_json()
    required = ["name", "cost", "description"]
    if not all(data.get(k) is not None for k in required):
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        ), 400
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO degree(name,cost,description,admin_staff_person_id) VALUES(%s,%s,%s,%s);",
            (data["name"], data["cost"], data["description"], flask.g.person_id),
        )
        conn.commit()
        return jsonify(
            {
                "status": StatusCodes["success"],
                "results": "Degree registered successfully",
            }
        ), 200
    except Exception as e:
        conn.rollback()
        logging.error(f"POST /register/degree - error: {e}")
        return jsonify(
            {"status": StatusCodes["internal_error"], "errors": str(e), "results": None}
        ), 500
    finally:
        conn.close()


@app.route("/dbproj/register/instructor", methods=["POST"])
@staff_required
def register_instructor():
    data = request.get_json()
    required = [
        "name",
        "email",
        "phone",
        "cc",
        "nif",
        "gender",
        "password",
        "numero_docente",
        "email_institucional",
        "salario",
        "anos_servico",
        "active",
        "area",
    ]
    if not all(data.get(k) is not None for k in required):
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        ), 400
    hashed_pw = bcrypt.generate_password_hash(data["password"]).decode()
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT fn_register_instructor(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);",
            (
                data["name"],
                data["email"],
                data["cc"],
                data["nif"],
                data["gender"],
                data["phone"],
                hashed_pw,
                data["email_institucional"],
                data["numero_docente"],
                data["salario"],
                data["anos_servico"],
                data["active"],
                data["area"],
            ),
        )
        person_id = cur.fetchone()[0]
        conn.commit()
        token = jwt.encode(
            {
                "role": "instructor",
                "person_id": person_id,
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )
        return jsonify(
            {
                "status": StatusCodes["success"],
                "results": {
                    "access_token": token,
                    "person_id": person_id,
                    "numero_docente": data["numero_docente"],
                },
            }
        ), 200
    except Exception as e:
        conn.rollback()
        logging.error(f"POST /register-instructor - error: {e}")
        return jsonify(
            {"status": StatusCodes["internal_error"], "errors": str(e), "results": None}
        ), 500
    finally:
        conn.close()


@app.route("/dbproj/user", methods=["PUT"])
def login_user():
    data = request.get_json() or {}
    email = data.get("username")
    password = data.get("password")
    if not email or not password:
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Campos 'email' e 'password' são obrigatórios",
                "results": None,
            }
        ), 400
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT password, role, id FROM person WHERE email_institucional=%s",
            (email,),
        )
        row = cur.fetchone()
        if not row or not bcrypt.check_password_hash(row[0], password):
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Credenciais inválidas",
                    "results": None,
                }
            ), 401
        _, role, person_id = row
        token = jwt.encode(
            {
                "role": role,
                "person_id": person_id,
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )
        return jsonify(
            {
                "status": StatusCodes["success"],
                "errors": None,
                "results": {"auth_token": token},
            }
        ), 200
    except Exception as e:
        conn.rollback()
        logging.error(f"PUT /dbproj/user - error: {e}")
        return jsonify(
            {"status": StatusCodes["internal_error"], "errors": str(e), "results": None}
        ), 500
    finally:
        conn.close()

    return flask.jsonify(response)

@app.route("/dbproj/person-info", methods=["GET"])
@token_required
def view_person_info():
    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT name, phone, gender FROM person WHERE id=%s", (flask.g.person_id,)
    )
    name, phone, gender = cur.fetchone()
    return jsonify(
        {
            "status": StatusCodes["success"],
            "errors": None,
            "results": {
                "person_id": flask.g.person_id,
                "name": name,
                "phone": phone,
                "gender": gender,
            },
        }
    ), 200

@app.route("/top-students", methods=["GET"])
def show_top_students():
    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        " SELECT students.person_id, person.name, students.average FROM students LEFT JOIN person ON students.person_id = person.id ORDER BY average DESC LIMIT 3"  
    )
    rows = cur.fetchall()
    if not rows:
        response = {
            "status": StatusCodes["api_error"],
            "errors": "Student not found",
            "results": None,
        }
    else:
        person_id = [rows[0][0], rows[1][0], rows[2][0]]
        person_name =[rows[0][1], rows[1][1], rows[2][1]]
        person_average=[rows[0][2], rows[1][2], rows[2][2]]
        
        response = {
            "Top 3": [
                {"Name": person_name[0], "Average": person_average[0]},
                {"Name": person_name[1], "Average": person_average[1]},
                {"Name": person_name[2], "Average": person_average[2]}
                ]
            }
    return flask.jsonify(response)
@app.route("/degree-course-info/<degree_id>", methods =["GET"])
#@staff_required()
def view_degree_info(degree_id):
    conn = db_connection()
    cur = conn.cursor()
    response = None  
    
    try:
        
        cur.execute(
            """
            SELECT epaaicsicsp FROM degree WHERE id = %s""", 
            (degree_id,),
        )
        rows = cur.fetchall()
        
        if not rows:
            response = {
                "status": StatusCodes["api_error"],
                "errors": "Degree not found",  
                "results": None,
            }
        else:
            epaaicsicsp = rows[0][0]
            
            cur.execute(
                """
                SELECT course_id, ano, instructors_class_class_capacity, 
                       instructors_class_employee_person_id, 
                       theory_instructors_class_employee_person_id, 
                       theory_instructors_class_employee_person_id1 
                FROM edition_practical_assistant_instructors_course 
                WHERE course_id = %s
                """, 
                (epaaicsicsp,)
            )
            rows = cur.fetchall()
            
            if not rows:
                response = {
                    "status": StatusCodes["api_error"],
                    "errors": "Course edition not found",  
                    "results": None,
                }
            else:
                # Create success response
                response = {
                    "status": StatusCodes["success"],
                    "results": {
                        "edition": rows[0][1],
                        "degree_id": degree_id, 
                        "class_capacity": rows[0][2],  
                        "coordenador": rows[0][3],
                        "assistente_1": rows[0][4], 
                        "assistente_2": rows[0][5]
                    }
                }
                
    except (Exception, psycopg2.DatabaseError) as error:  # Changed psycopg3 to psycopg2 (assuming)
        response = {
            "status": StatusCodes["internal_error"],
            "errors": str(error),
        } 
    finally:
        if conn is not None:
            conn.close()

    return flask.jsonify(response)

@app.route("/login-instructor", methods=["GET"])
def login_instructor():
    data = flask.request.get_json()
    email = data.get("email_docente")
    password = data.get("password")

    if not email or not password:
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Email and password are required",
                "results": None,
            }
        )

    conn = db_connection()
    cur = conn.cursor()
    response = {}
    try:
        cur.execute(
            " SELECT staff.person_id, person.name, person.password, person.email_pessoal FROM staff LEFT JOIN person ON staff.person_id = person.id WHERE staff.email_docente = %s",
            (email,),
        )
        rows = cur.fetchall()
        if not rows:
            response = {
                "status": StatusCodes["api_error"],
                "errors": "Staff not found",
                "results": None,
            }
        else:
            name = rows[0][1]
            hashed_password = rows[0][2]
            email_pessoal = rows[0][3]
            if bcrypt.check_password_hash(hashed_password, password):
                access_token = jwt.encode(
                    {
                        "username": email_pessoal,
                        "role": "instructor",
                        "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
                    },
                    Config.SECRET_KEY,
                    algorithm="HS256",
                )
                response = {
                    "status": StatusCodes["success"],
                    "results": {"access_token": access_token},
                    "message": f"Welcome {name}",
                }
            else:
                response = {
                    "status": StatusCodes["api_error"],
                    "errors": "Password incorrect",
                    "results": None,
                }
    except (Exception, psycopg3.DatabaseError) as error:
        response = {
            "status": StatusCodes["internal_error"],
            "errors": str(error),
        }
    finally:
        if conn is not None:
            conn.close()


@app.route("/dbproj/enroll_degree/<int:degree_id>", methods=["POST"])
@staff_required
def enroll_degree(degree_id):
    data = request.get_json()
    student_id = data.get("student_id")
    if not student_id:
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "campo 'student_id' é obrigatórios",
            }
        ), 400
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO students_degree(students_id,degree_id,staff_id) VALUES(%s,%s,%s)",
            (student_id, degree_id, flask.g.person_id),
        )
        conn.commit()
        return jsonify({"status": StatusCodes["success"], "errors": None}), 200
    except Exception as e:
        conn.rollback()
        logging.error(f"POST /enroll_degree error: {e}")
        return jsonify({"status": StatusCodes["internal_error"], "errors": str(e)}), 500
    finally:
        conn.close()


@app.route("/dbproj/enroll_activity/<int:activity_id>", methods=["POST"])
@student_required
def enroll_activity(activity_id):
    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "INSERT INTO students_activity(students_id,activity_id) VALUES(%s,%s)",
            (flask.g.person_id, activity_id),
        )
        conn.commit()
        return jsonify({"status": StatusCodes["success"], "errors": None}), 200
    except Exception as e:
        conn.rollback()
        logging.error(f"POST /enroll_activity error: {e}")
        return jsonify({"status": StatusCodes["internal_error"], "errors": str(e)}), 500
    finally:
        conn.close()


@app.route("/enroll_course_edition/<int:course_edition_id>", methods=["POST"])
@student_required
def enroll_course_edition(course_edition_id):
    data = request.get_json() or {}
    class_ids = data.get("classes", [])
    app.logger.debug(f"enroll_course_edition payload: {data}")
    if not isinstance(class_ids, list):
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "‘classes’ deve ser uma lista de IDs",
            }
        ), 400

    app.logger.debug(f"flask.g.person_id = {flask.g.person_id}")
    app.logger.debug(f"course_edition_id = {course_edition_id}")
    app.logger.debug(f"class_ids (raw) = {class_ids} / type = {type(class_ids)}")

    sql_array = "{" + ",".join(str(i) for i in class_ids) + "}"

    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT * FROM enroll_course_edition(%s, %s, %s::int[]);",
            (flask.g.person_id, course_edition_id, sql_array),
        )
        row = cur.fetchone()
        app.logger.debug(f"enroll_course_edition db returned: {row}")
        conn.commit()
        if not row:
            return jsonify(
                {
                    "status": StatusCodes["internal_error"],
                    "errors": "Sem resposta do banco",
                }
            ), 500
        if row[0] == "error":
            return jsonify({"status": StatusCodes["api_error"], "errors": row[1]}), 400

        return jsonify({"status": StatusCodes["success"], "message": row[1]}), 200

    except Exception as e:
        conn.rollback()
        app.logger.error(f"POST /enroll_course_edition error: {e}")
        return jsonify({"status": StatusCodes["internal_error"], "errors": str(e)}), 500
    finally:
        conn.close()


@app.route("/dbproj/delete_details/<int:student_id>", methods=["DELETE"])
@staff_required
def delete_details(student_id):
    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        "DELETE FROM public.person WHERE id=%s AND role='student' RETURNING id;",
        (student_id,),
    )
    deleted = cur.fetchone()
    if not deleted:
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "o id deverá ser ed um student",
            }
        ), 400
    conn.commit()
    return jsonify({"status": StatusCodes["success"], "errors": None}), 204

@app.route("/top_by_district", methods=["GET"])
def generate_top_by_district():  # Renamed from register_instructor for clarity
    conn = db_connection()
    cur = conn.cursor()

    try:
        # Execute the best student query
        cur.execute("""
            WITH ranked_students AS (
                SELECT 
                    p.district,
                    s.person_id,
                    s.average,
                    ROW_NUMBER() OVER (
                        PARTITION BY p.district 
                        ORDER BY s.average DESC
                    ) AS rank
                FROM students s
                JOIN person p 
                    ON s.person_id = p.id
            )
            SELECT 
                district,
                person_id,
                average
            FROM ranked_students
            WHERE rank = 1;
        """)

        # Format results
        results = []
        for row in cur.fetchall():
            results.append({
                "district": row[0],
                "best_student_id": row[1],
                "highest_average": float(row[2])  # Convert decimal to float for JSON
            })

        return flask.jsonify({
            "status": StatusCodes["success"],
            "results": results
        })

    except Exception as error:
        if conn:
            conn.rollback()
        logger.error(f"GET /top_by_district - error: {error}")
        return flask.jsonify({
            "status": StatusCodes["internal_error"],
            "errors": str(error),
            "results": None
        })
    finally:
        if conn:
            conn.close()


@app.route("/report", methods=["GET"])
def generate_report():  # Renamed from register_instructor for clarity
    conn = db_connection()
    cur = conn.cursor()

    try:
        cur.execute("""
        SELECT ep.ano AS ano, COUNT(*) AS passed_students_count FROM edition_stats es
        JOIN students_degree sd ON es.students_person_id = sd.students_person_id 
        JOIN degree dg ON dg.id = sd.degree_id 
        JOIN edition_practical_assistant_instructors_course ep ON ep.instructors_class_epaaicsicsp = dg.epaaicsicsp 
        WHERE es.passed = TRUE
        GROUP BY ep.ano;
        """)

        # Format results
        results = []
        for row in cur.fetchall():
            results.append({
                "edição": row[0],
                "numero": row[1]
            })

        return flask.jsonify({
            "status": StatusCodes["success"],
            "results": results
        })

    except Exception as error:
        if conn:
            conn.rollback()
        logger.error(f"GET /report - error: {error}")
        return flask.jsonify({
            "status": StatusCodes["internal_error"],
            "errors": str(error),
            "results": None
        })
    finally:
        if conn:
            conn.close()


if __name__ == "__main__":
    logging.basicConfig(filename="log_file.log")
    logger = logging.getLogger("logger")
    logger.setLevel(logging.DEBUG)
    ch = logging.StreamHandler()
    ch.setLevel(logging.DEBUG)
    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s]:  %(message)s", "%H:%M:%S"
    )
    ch.setFormatter(formatter)
    logger.addHandler(ch)
    app.run(host="127.0.0.1", port=8080, debug=True, threaded=True)
