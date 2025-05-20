# Codigo baseado nas demos enviadas pelo professor
import flask
import datetime
import logging
import psycopg as psycopg3
import jwt
from flask_bcrypt import Bcrypt
import random
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


@app.route("/register-person", methods=["POST"])
def register_person():
    data = flask.request.get_json()
    name = data.get("name")
    email = data.get("email")
    phone = data.get("phone")
    cc = data.get("cc")
    nif = data.get("nif")
    password = data.get("password")
    gender = data.get("gender")
    hashed_password = bcrypt.generate_password_hash(password).decode("utf-8")

    if not name or not email or not phone or not cc or not nif or not gender:
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Name, email, and phone are required",
                "results": None,
            }
        )

    conn = db_connection()
    cur = conn.cursor()
    statement = """
        INSERT INTO person (name, email_pessoal, cc, nif, gender, phone, password) 
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    """
    values = (name, email, cc, nif, gender, phone, hashed_password)

    try:
        cur.execute(statement, values)
        conn.commit()

        access_token = jwt.encode(
            {
                "username": email,
                "exp": datetime.datetime.now() + datetime.timedelta(minutes=30),
            },
            Config.SECRET_KEY,
            algorithm="HS256",
        )

        response = {
            "status": StatusCodes["success"],
            "results": {"access_token": access_token},
        }
    except (Exception, psycopg3.DatabaseError) as error:
        logger.error(f"POST /register-person - error: {error}")
        response = {"status": StatusCodes["internal_error"], "errors": str(error)}
    finally:
        if conn is not None:
            conn.close()

    return flask.jsonify(response)


@app.route("/login-person", methods=["GET"])
def login_person():
    data = flask.request.get_json()
    email = data.get("email")
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
            "SELECT name, password FROM person WHERE email_pessoal = %s", (email,)
        )
        rows = cur.fetchall()
        if not rows:
            response = {
                "status": StatusCodes["api_error"],
                "errors": "User not found",
                "results": None,
            }
        else:
            name = rows[0][0]
            hashed_password = rows[0][1]
            if bcrypt.check_password_hash(hashed_password, password):
                access_token = jwt.encode(
                    {
                        "username": email,
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
    print(username)
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


@app.route("/dbproj/user", methods=["PUT"])
def login_user():
    data = flask.request.get_json()
    email = data.get("email")
    password = data.get("password")

    if not email or not password:
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Username and password are required",
                "results": None,
            }
        )

    resultAuthToken = "Sample token, should be random!"  # TODO: use JWT

    response = {
        "status": StatusCodes["success"],
        "errors": None,
        "results": resultAuthToken,
    }
    return flask.jsonify(response)


@app.route("/dbproj/register/student", methods=["POST"])
@token_required
def register_student():
    data = flask.request.get_json()
    username = data.get("username")
    email = data.get("email")
    password = data.get("password")

    if not username or not email or not password:
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Username, email, and password are required",
                "results": None,
            }
        )

    resultUserId = random.randint(1, 200)
    response = {
        "status": StatusCodes["success"],
        "errors": None,
        "results": resultUserId,
    }
    return flask.jsonify(response)


@app.route("/dbproj/register/staff", methods=["POST"])
@token_required
def register_staff():
    data = flask.request.get_json()
    username = data.get("username")
    email = data.get("email")
    password = data.get("password")

    if not username or not email or not password:
        return flask.jsonify(
            {
                "status": StatusCodes["api_error"],
                "errors": "Username, email, and password are required",
                "results": None,
            }
        )

    resultUserId = random.randint(1, 200)  # TODO

    response = {
        "status": StatusCodes["success"],
        "errors": None,
        "results": resultUserId,
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
