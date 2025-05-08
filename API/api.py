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
            INSERT INTO staff (numero_docente, email_docente,  salario, anos_servico, active, person_id)
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
