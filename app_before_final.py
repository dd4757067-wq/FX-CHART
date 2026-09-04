from flask import Flask, render_template, request, redirect, url_for, session, flash
import sqlite3
import os
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask("DURJOY_FX")
app.secret_key = "DURJOY-FX-SECRET-2026"

DB_PATH = "database/durjoy_fx.db"


def get_db():
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    return db


def init_db():
    os.makedirs("database", exist_ok=True)

    db = get_db()

    db.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            bio TEXT DEFAULT '',
            experience TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    db.execute("""
        CREATE TABLE IF NOT EXISTS trades (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            pair TEXT NOT NULL,
            direction TEXT NOT NULL,
            timeframe TEXT DEFAULT '',
            entry REAL,
            stop_loss REAL,
            take_profit REAL,
            lot_size REAL,
            risk_percent REAL,
            risk_amount REAL,
            result TEXT DEFAULT '',
            profit_loss REAL DEFAULT 0,
            strategy TEXT DEFAULT '',
            session_name TEXT DEFAULT '',
            emotion TEXT DEFAULT '',
            mistake TEXT DEFAULT '',
            notes TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    db.commit()
    db.close()


def logged_in():
    return "user_id" in session


@app.route("/")
def home():
    if logged_in():
        return redirect(url_for("dashboard"))
    return render_template("index.html")


@app.route("/register", methods=["GET", "POST"])
def register():

    if request.method == "POST":

        username = request.form.get("username", "").strip()
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")

        if not username or not email or not password:
            flash("সবগুলো ঘর পূরণ করুন।", "error")
            return redirect(url_for("register"))

        if len(password) < 6:
            flash("Password কমপক্ষে ৬ অক্ষরের হতে হবে।", "error")
            return redirect(url_for("register"))

        db = get_db()

        try:
            db.execute(
                "INSERT INTO users (username,email,password) VALUES (?,?,?)",
                (
                    username,
                    email,
                    generate_password_hash(password)
                )
            )

            db.commit()

        except sqlite3.IntegrityError:
            db.close()
            flash("এই Username অথবা Email ইতিমধ্যে ব্যবহার করা হয়েছে।", "error")
            return redirect(url_for("register"))

        user = db.execute(
            "SELECT id FROM users WHERE email=?",
            (email,)
        ).fetchone()

        db.close()

        session["user_id"] = user["id"]
        session["username"] = username

        return redirect(url_for("dashboard"))

    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():

    if request.method == "POST":

        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")

        db = get_db()

        user = db.execute(
            "SELECT * FROM users WHERE email=?",
            (email,)
        ).fetchone()

        db.close()

        if user and check_password_hash(user["password"], password):

            session["user_id"] = user["id"]
            session["username"] = user["username"]

            return redirect(url_for("dashboard"))

        flash("Email অথবা Password সঠিক নয়।", "error")

    return render_template("login.html")


@app.route("/logout")
def logout():

    session.clear()

    return redirect(url_for("home"))


@app.route("/dashboard")
def dashboard():

    if not logged_in():
        return redirect(url_for("login"))

    db = get_db()

    trades = db.execute(
        """
        SELECT *
        FROM trades
        WHERE user_id=?
        ORDER BY id DESC
        """,
        (session["user_id"],)
    ).fetchall()

    total = len(trades)

    wins = sum(
        1 for t in trades
        if t["result"] == "Win"
    )

    losses = sum(
        1 for t in trades
        if t["result"] == "Loss"
    )

    pnl = sum(
        float(t["profit_loss"] or 0)
        for t in trades
    )

    win_rate = round(
        (wins / total) * 100,
        1
    ) if total else 0

    winning_values = [
        float(t["profit_loss"] or 0)
        for t in trades
        if float(t["profit_loss"] or 0) > 0
    ]

    losing_values = [
        float(t["profit_loss"] or 0)
        for t in trades
        if float(t["profit_loss"] or 0) < 0
    ]

    average_win = (
        sum(winning_values) / len(winning_values)
        if winning_values else 0
    )

    average_loss = (
        sum(losing_values) / len(losing_values)
        if losing_values else 0
    )

    gross_profit = sum(winning_values)
    gross_loss = abs(sum(losing_values))

    profit_factor = (
        gross_profit / gross_loss
        if gross_loss else 0
    )

    db.close()

    return render_template(
        "dashboard.html",
        trades=trades,
        total=total,
        wins=wins,
        losses=losses,
        pnl=round(pnl, 2),
        win_rate=win_rate,
        average_win=round(average_win, 2),
        average_loss=round(average_loss, 2),
        profit_factor=round(profit_factor, 2)
    )


@app.route("/journal", methods=["GET", "POST"])
def journal():

    if not logged_in():
        return redirect(url_for("login"))

    if request.method == "POST":

        pair = request.form.get("pair", "").strip()
        direction = request.form.get("direction", "Buy")
        timeframe = request.form.get("timeframe", "")

        entry = request.form.get("entry") or None
        stop_loss = request.form.get("stop_loss") or None
        take_profit = request.form.get("take_profit") or None
        lot_size = request.form.get("lot_size") or None
        risk_percent = request.form.get("risk_percent") or None
        risk_amount = request.form.get("risk_amount") or None

        result = request.form.get("result", "")
        profit_loss = request.form.get("profit_loss") or 0

        strategy = request.form.get("strategy", "")
        session_name = request.form.get("session_name", "")
        emotion = request.form.get("emotion", "")
        mistake = request.form.get("mistake", "")
        notes = request.form.get("notes", "")

        if not pair:
            flash("Currency Pair দিন।", "error")
            return redirect(url_for("journal"))

        db = get_db()

        db.execute("""
            INSERT INTO trades (
                user_id,
                pair,
                direction,
                timeframe,
                entry,
                stop_loss,
                take_profit,
                lot_size,
                risk_percent,
                risk_amount,
                result,
                profit_loss,
                strategy,
                session_name,
                emotion,
                mistake,
                notes
            )
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            session["user_id"],
            pair,
            direction,
            timeframe,
            entry,
            stop_loss,
            take_profit,
            lot_size,
            risk_percent,
            risk_amount,
            result,
            profit_loss,
            strategy,
            session_name,
            emotion,
            mistake,
            notes
        ))

        db.commit()
        db.close()

        flash("Trade successfully saved.", "success")

        return redirect(url_for("dashboard"))

    return render_template("journal.html")


@app.route("/calculator")
def calculator():

    if not logged_in():
        return redirect(url_for("login"))

    return render_template("calculator.html")


@app.route("/analysis")
def analysis():

    if not logged_in():
        return redirect(url_for("login"))

    return render_template("analysis.html")


@app.route("/analytics")
def analytics():

    if not logged_in():
        return redirect(url_for("login"))

    db = get_db()

    trades = db.execute(
        """
        SELECT *
        FROM trades
        WHERE user_id=?
        ORDER BY id DESC
        """,
        (session["user_id"],)
    ).fetchall()

    pair_stats = {}

    for trade in trades:

        pair = trade["pair"]

        if pair not in pair_stats:
            pair_stats[pair] = {
                "trades": 0,
                "wins": 0,
                "pnl": 0
            }

        pair_stats[pair]["trades"] += 1

        if trade["result"] == "Win":
            pair_stats[pair]["wins"] += 1

        pair_stats[pair]["pnl"] += float(
            trade["profit_loss"] or 0
        )

    db.close()

    return render_template(
        "analytics.html",
        pair_stats=pair_stats
    )


@app.route("/calendar")
def calendar():

    if not logged_in():
        return redirect(url_for("login"))

    return render_template("calendar.html")


@app.route("/profile", methods=["GET", "POST"])
def profile():

    if not logged_in():
        return redirect(url_for("login"))

    db = get_db()

    if request.method == "POST":

        bio = request.form.get("bio", "")
        experience = request.form.get("experience", "")

        db.execute(
            """
            UPDATE users
            SET bio=?, experience=?
            WHERE id=?
            """,
            (
                bio,
                experience,
                session["user_id"]
            )
        )

        db.commit()

        flash("Profile updated successfully.", "success")

    user = db.execute(
        """
        SELECT *
        FROM users
        WHERE id=?
        """,
        (session["user_id"],)
    ).fetchone()

    db.close()

    return render_template(
        "profile.html",
        user=user
    )


@app.errorhandler(404)
def not_found(error):

    return render_template("404.html"), 404


init_db()

app.run(
    host="0.0.0.0",
    port=5000,
    debug=True
)
