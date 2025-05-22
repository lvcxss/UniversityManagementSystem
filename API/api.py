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


# decorators
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
            flask.g.user = data["username"]
            if data["role"] != "staff":
                return jsonify({"message": "Permission denied"}), 403
        except Exception as e:
            return jsonify({"message": "Token is invalid", "error": str(e)}), 401

        return f(*args, **kwargs)

    return decorated


def student_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        if "Authorization" in request.headers:
            token = request.headers["Authorization"].split(" ")[-1]

        if not token:
            return jsonify({"message": "Token is missing!"}), 401

        try:
            data = jwt.decode(token, Config.SECRET_KEY, algorithms=["HS256"])
            flask.g.user = data["username"]

            if data["role"] != "student":
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
@app.route("/dbproj/register/staff", methods=["POST"])
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
    email_institucional = data.get("email_institucional")

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
            email_institucional,
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
            INSERT INTO person (name, email_pessoal, cc, nif, gender, phone, password, role, email_institucional)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """,
            (
                name,
                email,
                cc,
                nif,
                gender,
                phone,
                hashed_password,
                "staff",
                email_institucional,
            ),
        )
        person_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO employee (numero_docente ,  salario, anos_servico, active, person_id)
            VALUES (%s, %s, %s, %s, %s)
        """,
            (numero_docente, salario, anos_servico, active, person_id),
        )
        cur.execute(
            """
            INSERT INTO staff (staff_person_id)
            VALUES (%s)
            """,
            (person_id,),
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


@app.route("/dbproj/register/student", methods=["POST"])
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

    email_institucional = data.get("email_institucional")
    numero_estudante = data.get("numero_estudante")
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
            email_institucional,
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
            INSERT INTO person (name, email_pessoal, cc, nif, gender, phone, password, role, email_institucional)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """,
            (
                name,
                email,
                cc,
                nif,
                gender,
                phone,
                hashed_password,
                "student",
                email_institucional,
            ),
        )
        person_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO students (numero_estudante, average, person_id)
            VALUES (%s, %s, %s)
        """,
            (numero_estudante, average, person_id),
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
        logger.error(f"POST /register/student - error: {error}")
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


@app.route("/dbproj/register/degree", methods=["POST"])
@staff_required
def register_degree():
    username = flask.g.user
    data = flask.request.get_json()
    name = data.get("name")
    cost = data.get("cost")
    description = data.get("description")

    if not all(
        [
            name,
            cost,
            description,
        ]
    ):
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Missing required fields",
                "results": None,
            }
        )

    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT id FROM person WHERE email_institucional = %s", (username,))
        rows = cur.fetchall()
        person_id = rows[0][0]
        cur.execute(
            """
            INSERT INTO degree (name, cost, description, admin_staff_person_id)
            VALUES (%s, %s, %s, %s)
        """,
            (
                name,
                cost,
                description,
                person_id,
            ),
        )

        conn.commit()
        return flask.jsonify(
            {
                "status": StatusCodes["success"],
                "results": "we done did it",
            }
        )

    except Exception as error:
        if conn:
            conn.rollback()
        logger.error(f"POST /register/degree - error: {error}")
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


@app.route("/dbproj/register/instructor", methods=["POST"])
@staff_required
def register_instructor():
    data = flask.request.get_json()
    name = data.get("name")
    email = data.get("email")
    phone = data.get("phone")
    cc = data.get("cc")
    nif = data.get("nif")
    password = data.get("password")
    gender = data.get("gender")
    email_institucional = data.get("email_institucional")
    numero_docente = data.get("numero_docente")
    salario = data.get("salario")
    anos_servico = data.get("anos_servico")
    active = data.get("active")
    area = data.get("area")

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
            email_institucional,
            salario,
            anos_servico,
            active,
            area,
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
            INSERT INTO person (name, email_pessoal, cc, nif, gender, phone, password, role, email_institucional)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
            """,
            (
                name,
                email,
                cc,
                nif,
                gender,
                phone,
                hashed_password,
                "instructor",
                email_institucional,
            ),
        )
        person_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO employee (numero_docente,  salario, anos_servico, active, person_id)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (numero_docente, salario, anos_servico, active, person_id),
        )
        cur.execute(
            """
            INSERT INTO instructors (instructor_person_id, area)
            VALUES( %s, %s)
            """,
            (person_id, area),
        )

        conn.commit()

        access_token = jwt.encode(
            {
                "username": email_institucional,
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


# LOGINS
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
            """
            SELECT password, role
            FROM person
            WHERE email_institucional = %s
        """,
            (email,),
        )
        row = cur.fetchone()

        if not row:
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Credenciais inválidas",
                    "results": None,
                }
            ), 401

        hashed_pw, role = row
        if not bcrypt.check_password_hash(hashed_pw, password):
            return jsonify(
                {
                    "status": StatusCodes["unauthorized"],
                    "errors": "Credenciais inválidas",
                    "results": None,
                }
            ), 401

        access_token = jwt.encode(
            {
                "username": email,
                "role": role,
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )

        return jsonify(
            {
                "status": StatusCodes["success"],
                "errors": None,
                "results": {"auth_token": access_token},
            }
        ), 200

    except Exception as e:
        conn.rollback()
        logger.error(f"PUT /dbproj/user - error: {e}")
        return jsonify(
            {"status": StatusCodes["internal_error"], "errors": str(e), "results": None}
        ), 500

    finally:
        conn.close()


@app.route("/dbproj/person-info", methods=["GET"])
@token_required
def view_person_info():
    username = flask.g.user
    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT name, phone, gender FROM person WHERE email_institucional = %s",
        (username,),
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


# ENROLLS
@app.route("/dbproj/enroll_degree/<int:degree_id>", methods=["POST"])
@staff_required
def enroll_degree(degree_id):
    username = flask.g.user
    data = request.get_json()
    student_id = data.get("student_id")
    if not student_id or not degree_id:
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
            """
            SELECT id from person WHERE email_institucional = %s
            """,
            (username,),
        )
        staff_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO students_degree (students_id, degree_id, staff_id)
            VALUES (%s, %s, %s)
        """,
            (student_id, degree_id, staff_id),
        )
        logger.info(
            f"Degree enrollment: student={student_id}, degree={degree_id}, staff_id={staff_id}"
        )

        conn.commit()
        return jsonify({"status": StatusCodes["success"], "errors": None}), 200

    except Exception as e:
        conn.rollback()
        logger.error(f"POST /enroll_degree error: {e}")
        return jsonify({"status": StatusCodes["internal_error"], "errors": str(e)}), 500
    finally:
        conn.close()


@app.route("/dbproj/enroll_activity/<int:activity_id>", methods=["POST"])
@student_required
def enroll_activity(activity_id):
    username = flask.g.user
    if not activity_id:
        return jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Insira o id da atividade no link",
            }
        ), 400

    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT id from person WHERE email_institucional = %s
            """,
            (username,),
        )
        student_id = cur.fetchone()[0]
        cur.execute(
            """
            INSERT INTO students_activity (students_id, activity_id)
            VALUES (%s, %s)
        """,
            (student_id, activity_id),
        )
        logger.info(f"Degree enrollment: student={student_id}, activity={activity_id}")

        conn.commit()
        return jsonify({"status": StatusCodes["success"], "errors": None}), 200

    except Exception as e:
        conn.rollback()
        logger.error(f"POST /enroll_activity error: {e}")
        return jsonify({"status": StatusCodes["internal_error"], "errors": str(e)}), 500
    finally:
        conn.close()


@app.route("/enroll_course_edition/<int:course_edition_id>", methods=["POST"])
@student_required
def enroll_course_edition(course_edition_id):
    data = request.get_json()
    class_ids = data.get("classes", [])
    student_id = flask.g.user

    conn = db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
                SELECT * FROM enroll_course_edition(%s, %s, %s);
                """,
            (student_id, course_edition_id, class_ids),
        )
        conn.commit()
        return jsonify({"status": StatusCodes["success"], "errors": None}), 200

    except Exception as e:
        conn.rollback()
        logger.error(f"POST /enroll_activity error: {e}")
        return jsonify({"status": StatusCodes["internal_error"], "errors": str(e)}), 500
    finally:
        conn.close()


@app.route("/dbproj/delete_details/<int:student_id>", methods=["DELETE"])
@staff_required
def delete_details(student_id):
    conn = db_connection()
    cur = conn.cursor()
    cur.execute(
        """
        DELETE FROM public.person
         WHERE id = %s
           AND role = 'student'
        RETURNING id;
    """,
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
    return jsonify(
        {
            "status": StatusCodes["success"],
            "errors": None,
        }
    ), 204


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
