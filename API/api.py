# Codigo baseado nas demos enviadas pelo professor
import flask
import datetime
import logging
import psycopg as psycopg3
import jwt
from flask_bcrypt import Bcrypt
import random
from flask import request, jsonify
from functools import wraps
from config import Config

app = flask.Flask(__name__)
app.config.from_object(Config)
app.config["JWT_SECRET_KEY"] = Config.SECRET_KEY
bcrypt = Bcrypt(app)

StatusCodes = {
    "success": 200,
    "api_error": 400,
    "internal_error": 500,
    "unauthorized": 401,
}


##########################################################
## endpoints
##########################################################


@app.route("/people/", methods=["GET"])
def people():
    logger.info("GET /people")

    conn = db_connection()
    cur = conn.cursor()

    try:
        cur.execute("SELECT name, email_pessoal, phone FROM person")
        rows = cur.fetchall()

        logger.debug("GET /people- parse")
        Results = []
        for row in rows:
            logger.debug(row)
            content = {
                "name": row[0].strip(),
                "email_pessoal": row[1].strip(),
                "phone": row[2].strip(),
            }
            Results.append(content)  # appending to the payload to be returned

        response = {"status": StatusCodes["success"], "results": Results}

    except (Exception, psycopg3.DatabaseError) as error:
        logger.error(f"GET /people - error: {error}")
        response = {"status": StatusCodes["internal_error"], "errors": str(error)}

    finally:
        if conn is not None:
            conn.close()

    return flask.jsonify(response)


##########################################################
## endpoints end
##########################################################


##########################################################
## DATABASE ACCESS
##########################################################


def db_connection():
    db = psycopg3.connect(
        user=Config.DB_USER,
        password=Config.DB_PASSWORD,
        host=Config.DB_HOST,
        port=Config.DB_PORT,
        dbname=Config.DB_NAME,
    )

    return db


##########################################################
## AUTHENTICATION HELPERS
##########################################################


def staff_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        if "Authorization" in request.headers:
            token = request.headers["Authorization"].split(" ")[-1]

        if not token:
            return jsonify({"message": "Token is missing!"}), 401

        try:
            data = jwt.decode(token, Config.SECRET_KEY, algorithms=["HS256"])
            if data["role"] != "staff":
                return jsonify({"message": "Permission denied"}), 403
        except Exception as e:
            return jsonify({"message": "Token is invalid", "error": str(e)}), 401

        return f(*args, **kwargs)

    return decorated


def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = flask.request.headers.get("Authorization")
        logger.info(f"token: {token}")

        if not token:
            return flask.jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Token is missing!",
                    "results": None,
                }
            ), 401

        try:
            token = token.split(" ")[1]
            payload = jwt.decode(token, Config.SECRET_KEY, algorithms=["HS256"])
            flask.g.user = payload["username"]
        except jwt.ExpiredSignatureError:
            return flask.jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Token has expired!",
                    "results": None,
                }
            ), 401
        except jwt.InvalidTokenError:
            return flask.jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Invalid token!",
                    "results": None,
                }
            ), 401

        return f(*args, **kwargs)

    return decorated


# REGISTERS
@app.route("/register-staff", methods=["POST"])
def register_staff():
    data = flask.request.get_json()
    name = data.get("name")
    email = data.get("email")
    phone = data.get("phone")
    cc = data.get("cc")
    nif = data.get("nif")
    gender = data.get("gender")
    password = data.get("password")
    numero_docente = data.get("numero_docente")
    salario = data.get("salario")
    anos_servico = data.get("anos_servico")
    active = data.get("active")
    email_docente = data.get("email_docente")

    if not all(
        [
            name,
            email,
            phone,
            cc,
            nif,
            gender,
            password,
            numero_docente,
            salario,
            anos_servico,
            email_docente,
            active is not None,
        ]
    ):
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        )

    hashed_password = bcrypt.generate_password_hash(password).decode("utf-8")

    conn = db_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            """
            INSERT INTO person (name, email_pessoal, cc, nif, gender, phone, password, role)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """,
            (name, email, cc, nif, gender, phone, hashed_password, "staff"),
        )
        person_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO employee (numero_docente, email_docente,  salario, anos_servico, active, person_id)
            VALUES (%s, %s, %s, %s, %s, %s)
        """,
            (numero_docente, email_docente, salario, anos_servico, active, person_id),
        )

        conn.commit()

        access_token = jwt.encode(
            {
                "username": email,
                "role": "staff",
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )

        return flask.jsonify(
            {
                "status": StatusCodes["success"],
                "results": {
                    "access_token": access_token,
                    "person_id": person_id,
                    "numero_docente": numero_docente,
                },
            }
        )

    except Exception as error:
        if conn:
            conn.rollback()
        logger.error(f"POST /register-staff - error: {error}")
        return flask.jsonify(
            {
                "status": StatusCodes["internal_error"],
                "errors": str(error),
                "results": None,
            }
        )
    finally:
        if conn:
            conn.close()


@app.route("/register-student", methods=["POST"])
@staff_required
def register_student():
    data = flask.request.get_json()
    name = data.get("name")
    email = data.get("email")
    phone = data.get("phone")
    cc = data.get("cc")
    nif = data.get("nif")
    gender = data.get("gender")
    password = data.get("password")
    numero_estudante = data.get("numero_estudante")
    email_estudante = data.get("email_estudante")
    average = data.get("average")

    if not all(
        [
            name,
            email,
            phone,
            cc,
            nif,
            gender,
            password,
            numero_estudante,
            email_estudante,
            average,
        ]
    ):
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        )

    hashed_password = bcrypt.generate_password_hash(password).decode("utf-8")

    conn = db_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            """
            INSERT INTO person (name, email_pessoal, cc, nif, gender, phone, password, role)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """,
            (name, email, cc, nif, gender, phone, hashed_password, "student"),
        )
        person_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO students (numero_estudante,email_estudante, average, person_id)
            VALUES (%s, %s, %s, %s)
        """,
            (numero_estudante, email_estudante, average, person_id),
        )

        conn.commit()

        access_token = jwt.encode(
            {
                "username": email,
                "role": "student",
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )

        return flask.jsonify(
            {
                "status": StatusCodes["success"],
                "results": {
                    "access_token": access_token,
                    "person_id": person_id,
                    "numero_estudante": numero_estudante,
                },
            }
        )

    except Exception as error:
        if conn:
            conn.rollback()
        logger.error(f"POST /register-student - error: {error}")
        return flask.jsonify(
            {
                "status": StatusCodes["internal_error"],
                "errors": str(error),
                "results": None,
            }
        )
    finally:
        if conn:
            conn.close()


# LOGINS


@app.route("/login-staff", methods=["GET"])
def login_staff():
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
            " SELECT employee.person_id, person.name, person.password, person.email_pessoal FROM employee LEFT JOIN person ON employee.person_id = person.id WHERE employee.email_docente = %s",
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
                        "role": "staff",
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

    return flask.jsonify(response)


@app.route("/login-student", methods=["GET"])
def login_student():
    data = flask.request.get_json()
    email = data.get("email_estudante")
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
            " SELECT students.person_id, person.name, person.password, person.email_pessoal FROM students LEFT JOIN person ON students.person_id = person.id WHERE students.email_estudante = %s",
            (email,),
        )
        rows = cur.fetchall()
        if not rows:
            response = {
                "status": StatusCodes["api_error"],
                "errors": "Student not found",
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
                        "role": "student",
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

    return flask.jsonify(response)


@app.route("/person-info", methods=["GET"])
@token_required
def view_person_info():
    username = flask.g.user
    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT name, phone, gender FROM person WHERE email_pessoal = %s", (username,)
    )
    rows = cur.fetchall()
    name = rows[0][0]
    phone = rows[0][1]
    gender = rows[0][2]
    response = {
        "status": StatusCodes["success"],
        "errors": None,
        "results": {"user": username, "name": name, "phone": phone, "gender": gender},
    }
    return flask.jsonify(response)
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
@app.route("/register-instructor", methods=["POST"])
@staff_required
def register_instructor():
    data    = flask.request.get_json()
    name    = data.get("name")
    email   = data.get("email")
    phone   = data.get("phone")
    cc      = data.get("cc")
    nif     = data.get("nif")
    gender  = data.get("gender")
    password        = data.get("password")
    numero_docente  = data.get("numero_docente")
    email_docente   = data.get("email_docente")
    salario         = data.get("salario")
    anos_servico    = data.get("anos_servico")
    active          = data.get("active")
    person_id       = data.get("person_id")

    if not all(
        [
            name,
            email,
            phone,
            cc,
            nif,
            gender,
            password,
            numero_docente,
            email_docente,
            salario,
            anos_servico,
            active,
            person_id,
        ]
    ):
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        )

    hashed_password = bcrypt.generate_password_hash(password).decode("utf-8")

    conn = db_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            """
            INSERT INTO person (name, email_pessoal, cc, nif, gender, phone, password, role)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
            """,
            (name, email, cc, nif, gender, phone, hashed_password, "instructor"),
        )
        person_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO staff (numero_docente, email_docente,  salario, anos_servico, active, person_id)
            VALUES (%s, %s, %s, %s, %s, %s)
            """, 
            (numero_docente, email_docente, salario, anos_servico, active, person_id),
        )
        # cur.execute(
        #     """
        #     INSERT INTO instructor (numero_docente, email_docente,  salario, anos_servico, active, person_id)
        #     VALUES (%s, %s, %s, %s)
        #     """, 
        #     (numero_docente, email_docente, salario, anos_servico, active, person_id),
        # )

        conn.commit()

        access_token = jwt.encode(
            {
                "username": email,
                "role": "instructor",
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )

        return flask.jsonify(
            {
                "status": StatusCodes["success"],
                "results": {
                    "access_token": access_token,
                    "person_id": person_id,
                    "numero_docente": numero_docente,
                },
            }
        )

    except Exception as error:
        if conn:
            conn.rollback()
        logger.error(f"POST /register-instructor - error: {error}")
        return flask.jsonify(
            {
                "status": StatusCodes["internal_error"],
                "errors": str(error),
                "results": None,
            }
        )
    finally:
        if conn:
            conn.close()

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
    # set up logging
    logging.basicConfig(filename="log_file.log")
    logger = logging.getLogger("logger")
    logger.setLevel(logging.DEBUG)
    ch = logging.StreamHandler()
    ch.setLevel(logging.DEBUG)

    # create formatter
    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s]:  %(message)s", "%H:%M:%S"
    )
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    host = "127.0.0.1"
    port = 8080
    app.run(host=host, debug=True, threaded=True, port=port)
    logger.info(f"API stubs online: http://{host}:{port}")
