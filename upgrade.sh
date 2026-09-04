#!/bin/bash

set -e

echo "======================================"
echo "       DURJOY FX V2 UPGRADE"
echo "======================================"

mkdir -p templates static/css static/js database routes services

cat > requirements.txt <<'REQ'
Flask
Werkzeug
gunicorn
REQ

cat > app.py <<'PY'
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
PY

cat > templates/base.html <<'HTML'
<!DOCTYPE html>
<html lang="bn">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{% block title %}DURJOY FX{% endblock %}</title>
<link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>

<body>

<header class="navbar">

<div class="brand">
<div class="brand-mark">D</div>
<div>
<strong>DURJOY FX</strong>
<span>TRADING PLATFORM</span>
</div>
</div>

<nav>

{% if session.get("user_id") %}

<a href="{{ url_for('dashboard') }}">Dashboard</a>
<a href="{{ url_for('journal') }}">Journal</a>
<a href="{{ url_for('analysis') }}">Chart</a>
<a href="{{ url_for('calculator') }}">Calculators</a>
<a href="{{ url_for('analytics') }}">Analytics</a>
<a href="{{ url_for('calendar') }}">Calendar</a>
<a href="{{ url_for('profile') }}">Profile</a>
<a class="logout" href="{{ url_for('logout') }}">Logout</a>

{% else %}

<a href="{{ url_for('login') }}">Login</a>
<a class="primary-btn" href="{{ url_for('register') }}">Get Started</a>

{% endif %}

</nav>

</header>

<main class="container">

{% with messages = get_flashed_messages(with_categories=true) %}

{% for category,message in messages %}

<div class="alert {{ category }}">
{{ message }}
</div>

{% endfor %}

{% endwith %}

{% block content %}{% endblock %}

</main>

<footer>

<div>
<strong>DURJOY FX</strong>
<p>Professional Trading Journal & Analytics Platform</p>
</div>

<div>
<p>Trade • Analyze • Improve</p>
</div>

</footer>

<script src="{{ url_for('static', filename='js/app.js') }}"></script>

</body>
</html>
HTML

cat > templates/index.html <<'HTML'
{% extends "base.html" %}

{% block title %}DURJOY FX — Professional Trading Platform{% endblock %}

{% block content %}

<section class="hero">

<div class="hero-content">

<div class="badge">NEXT GENERATION TRADING PLATFORM</div>

<h1>
Trade Smarter.<br>
<span>Analyze Better.</span>
</h1>

<p>
একটি professional workspace যেখানে তুমি Trading Journal,
Risk Management, Analytics, Chart Analysis এবং Trading Psychology
এক জায়গায় manage করতে পারবে।
</p>

<div class="hero-actions">
<a class="primary-btn" href="{{ url_for('register') }}">
Create Free Account
</a>

<a class="secondary-btn" href="{{ url_for('login') }}">
Login
</a>
</div>

</div>

<div class="hero-card">

<div class="mini-label">TRADING PERFORMANCE</div>

<div class="mock-number">+24.68%</div>

<div class="mock-chart">
<div></div><div></div><div></div><div></div>
<div></div><div></div><div></div><div></div>
</div>

<div class="mock-stats">

<div>
<span>Win Rate</span>
<strong>72.4%</strong>
</div>

<div>
<span>Profit Factor</span>
<strong>2.18</strong>
</div>

</div>

</div>

</section>


<section class="section">

<div class="section-heading">

<div>
<span class="eyebrow">POWERFUL TOOLS</span>
<h2>Everything a trader needs</h2>
</div>

<p>
Build discipline, track performance and understand your trading data.
</p>

</div>


<div class="feature-grid">

<div class="feature-card">
<div class="feature-icon">📒</div>
<h3>Trading Journal</h3>
<p>প্রতিটি trade বিস্তারিতভাবে record ও analyze করো।</p>
</div>

<div class="feature-card">
<div class="feature-icon">📊</div>
<h3>Performance Analytics</h3>
<p>Win rate, P/L, profit factor এবং trading statistics দেখো।</p>
</div>

<div class="feature-card">
<div class="feature-icon">🧮</div>
<h3>Risk Calculator</h3>
<p>Risk, position size এবং R:R দ্রুত calculate করো।</p>
</div>

<div class="feature-card">
<div class="feature-icon">📈</div>
<h3>Chart Workspace</h3>
<p>Technical এবং SMC analysis-এর জন্য dedicated workspace।</p>
</div>

<div class="feature-card">
<div class="feature-icon">🧠</div>
<h3>Trading Psychology</h3>
<p>Emotion, mistake এবং discipline track করো।</p>
</div>

<div class="feature-card">
<div class="feature-icon">📅</div>
<h3>Trading Calendar</h3>
<p>দিন, সপ্তাহ এবং মাস অনুযায়ী performance দেখো।</p>
</div>

</div>

</section>


<section class="quote">

<h2>
Your edge is not one trade.<br>
Your edge is your process.
</h2>

<p>DURJOY FX</p>

</section>

{% endblock %}
HTML

cat > templates/register.html <<'HTML'
{% extends "base.html" %}

{% block title %}Create Account — DURJOY FX{% endblock %}

{% block content %}

<div class="auth-page">

<div class="auth-card">

<span class="eyebrow">DURJOY FX</span>

<h1>Create your account</h1>

<p>Build your professional trading workspace.</p>

<form method="POST">

<label>Username</label>
<input name="username" placeholder="Your username" required>

<label>Email</label>
<input type="email" name="email" placeholder="you@example.com" required>

<label>Password</label>
<input type="password" name="password" placeholder="Minimum 6 characters" required>

<button class="primary-btn full">Create Account</button>

</form>

<p class="auth-link">
Already have an account?
<a href="{{ url_for('login') }}">Login</a>
</p>

</div>

</div>

{% endblock %}
HTML

cat > templates/login.html <<'HTML'
{% extends "base.html" %}

{% block title %}Login — DURJOY FX{% endblock %}

{% block content %}

<div class="auth-page">

<div class="auth-card">

<span class="eyebrow">WELCOME BACK</span>

<h1>Login to DURJOY FX</h1>

<p>Continue your trading journey.</p>

<form method="POST">

<label>Email</label>
<input type="email" name="email" required>

<label>Password</label>
<input type="password" name="password" required>

<button class="primary-btn full">Login</button>

</form>

<p class="auth-link">
Don't have an account?
<a href="{{ url_for('register') }}">Create Account</a>
</p>

</div>

</div>

{% endblock %}
HTML

cat > templates/dashboard.html <<'HTML'
{% extends "base.html" %}

{% block title %}Dashboard — DURJOY FX{% endblock %}

{% block content %}

<div class="page-head">

<div>
<span class="eyebrow">TRADING DASHBOARD</span>
<h1>Welcome, {{ session.get("username") }}</h1>
<p>Your complete trading performance overview.</p>
</div>

<a class="primary-btn" href="{{ url_for('journal') }}">
+ Add Trade
</a>

</div>


<div class="stats-grid">

<div class="stat-card">
<span>Total Trades</span>
<strong>{{ total }}</strong>
</div>

<div class="stat-card">
<span>Win Rate</span>
<strong>{{ win_rate }}%</strong>
</div>

<div class="stat-card">
<span>Net P/L</span>
<strong class="{% if pnl >= 0 %}positive{% else %}negative{% endif %}">
{{ pnl }}
</strong>
</div>

<div class="stat-card">
<span>Profit Factor</span>
<strong>{{ profit_factor }}</strong>
</div>

<div class="stat-card">
<span>Wins</span>
<strong>{{ wins }}</strong>
</div>

<div class="stat-card">
<span>Losses</span>
<strong>{{ losses }}</strong>
</div>

</div>


<div class="dashboard-grid">

<div class="panel">

<div class="panel-head">
<h2>Performance</h2>
<span>Overview</span>
</div>

<div class="performance-box">

<div>
<span>Average Win</span>
<strong>{{ average_win }}</strong>
</div>

<div>
<span>Average Loss</span>
<strong>{{ average_loss }}</strong>
</div>

<div>
<span>Winning Trades</span>
<strong>{{ wins }}</strong>
</div>

<div>
<span>Losing Trades</span>
<strong>{{ losses }}</strong>
</div>

</div>

<div class="empty-chart">

<div class="chart-line"></div>

<p>Equity curve will appear here as your journal grows.</p>

</div>

</div>


<div class="panel">

<div class="panel-head">
<h2>Quick Tools</h2>
</div>

<a class="tool-link" href="{{ url_for('journal') }}">
📒 Trading Journal
</a>

<a class="tool-link" href="{{ url_for('calculator') }}">
🧮 Risk Calculator
</a>

<a class="tool-link" href="{{ url_for('analysis') }}">
📈 Chart Analysis
</a>

<a class="tool-link" href="{{ url_for('analytics') }}">
📊 Advanced Analytics
</a>

</div>

</div>


<div class="panel">

<div class="panel-head">
<h2>Recent Trades</h2>

<a href="{{ url_for('journal') }}">View Journal →</a>

</div>

{% if trades %}

<div class="table-wrap">

<table>

<thead>
<tr>
<th>Pair</th>
<th>Direction</th>
<th>Result</th>
<th>P/L</th>
<th>Strategy</th>
<th>Date</th>
</tr>
</thead>

<tbody>

{% for trade in trades[:10] %}

<tr>

<td><strong>{{ trade["pair"] }}</strong></td>

<td>
<span class="direction">
{{ trade["direction"] }}
</span>
</td>

<td>

{% if trade["result"] == "Win" %}
<span class="status win">WIN</span>
{% elif trade["result"] == "Loss" %}
<span class="status loss">LOSS</span>
{% else %}
<span class="status">OPEN</span>
{% endif %}

</td>

<td class="{% if (trade['profit_loss'] or 0) >= 0 %}positive{% else %}negative{% endif %}">
{{ trade["profit_loss"] or 0 }}
</td>

<td>{{ trade["strategy"] }}</td>

<td>{{ trade["created_at"] }}</td>

</tr>

{% endfor %}

</tbody>

</table>

</div>

{% else %}

<div class="empty">
<p>No trades yet.</p>
<a class="primary-btn" href="{{ url_for('journal') }}">Add Your First Trade</a>
</div>

{% endif %}

</div>

{% endblock %}
HTML

cat > templates/journal.html <<'HTML'
{% extends "base.html" %}

{% block title %}Trading Journal — DURJOY FX{% endblock %}

{% block content %}

<div class="page-head">

<div>
<span class="eyebrow">TRADE JOURNAL</span>
<h1>Record Your Trade</h1>
<p>Track every decision and build your trading history.</p>
</div>

</div>


<div class="form-panel">

<form method="POST">

<div class="form-grid">

<div>
<label>Currency Pair</label>
<input name="pair" placeholder="EURUSD / XAUUSD / BTCUSD" required>
</div>

<div>
<label>Direction</label>
<select name="direction">
<option>Buy</option>
<option>Sell</option>
</select>
</div>

<div>
<label>Timeframe</label>
<select name="timeframe">
<option>1M</option>
<option>5M</option>
<option>15M</option>
<option>30M</option>
<option>1H</option>
<option>4H</option>
<option>1D</option>
<option>1W</option>
</select>
</div>

<div>
<label>Entry</label>
<input type="number" step="any" name="entry">
</div>

<div>
<label>Stop Loss</label>
<input type="number" step="any" name="stop_loss">
</div>

<div>
<label>Take Profit</label>
<input type="number" step="any" name="take_profit">
</div>

<div>
<label>Lot Size</label>
<input type="number" step="any" name="lot_size">
</div>

<div>
<label>Risk %</label>
<input type="number" step="any" name="risk_percent">
</div>

<div>
<label>Risk Amount</label>
<input type="number" step="any" name="risk_amount">
</div>

<div>
<label>Result</label>
<select name="result">
<option value="">Select</option>
<option>Win</option>
<option>Loss</option>
<option>Breakeven</option>
</select>
</div>

<div>
<label>Profit / Loss</label>
<input type="number" step="any" name="profit_loss" placeholder="0">
</div>

<div>
<label>Trading Session</label>
<select name="session_name">
<option value="">Select Session</option>
<option>Asian</option>
<option>London</option>
<option>New York</option>
<option>London + New York</option>
</select>
</div>

<div>
<label>Strategy</label>
<input name="strategy" placeholder="SMC / Breakout / FVG">
</div>

<div>
<label>Emotion</label>
<select name="emotion">
<option>Calm</option>
<option>Confident</option>
<option>Fear</option>
<option>Greed</option>
<option>FOMO</option>
<option>Revenge</option>
</select>
</div>

<div>
<label>Mistake</label>
<input name="mistake" placeholder="Optional">
</div>

</div>

<label>Trade Notes</label>
<textarea name="notes" rows="6" placeholder="Why did you take this trade? What did you learn?"></textarea>

<button class="primary-btn" type="submit">
Save Trade
</button>

</form>

</div>

{% endblock %}
HTML

cat > templates/calculator.html <<'HTML'
{% extends "base.html" %}

{% block title %}Trading Calculators — DURJOY FX{% endblock %}

{% block content %}

<div class="page-head">

<div>
<span class="eyebrow">TRADING TOOLS</span>
<h1>Trading Calculator Center</h1>
<p>Calculate risk and reward before entering a trade.</p>
</div>

</div>


<div class="calculator-grid">

<div class="calculator-card">

<h2>Risk Calculator</h2>

<label>Account Balance</label>
<input id="balance" type="number" step="any" placeholder="1000">

<label>Risk %</label>
<input id="risk" type="number" step="any" placeholder="1">

<label>Stop Loss (Pips)</label>
<input id="slpips" type="number" step="any" placeholder="20">

<button class="primary-btn full" onclick="calculateRisk()">
Calculate Risk
</button>

<div class="calc-result">

<div>
<span>Risk Amount</span>
<strong id="riskAmount">0</strong>
</div>

<div>
<span>Risk per Pip</span>
<strong id="riskPerPip">0</strong>
</div>

</div>

</div>


<div class="calculator-card">

<h2>R:R Calculator</h2>

<label>Risk (Pips)</label>
<input id="riskPips" type="number" step="any" placeholder="20">

<label>Reward (Pips)</label>
<input id="rewardPips" type="number" step="any" placeholder="40">

<button class="primary-btn full" onclick="calculateRR()">
Calculate R:R
</button>

<div class="calc-result">

<span>Risk : Reward</span>
<strong id="rrResult">1 : 0</strong>

</div>

</div>


<div class="calculator-card">

<h2>Position Calculator</h2>

<label>Risk Amount</label>
<input id="positionRisk" type="number" step="any" placeholder="10">

<label>Stop Loss (Pips)</label>
<input id="positionSL" type="number" step="any" placeholder="20">

<label>Pip Value / Lot</label>
<input id="pipValue" type="number" step="any" placeholder="10">

<button class="primary-btn full" onclick="calculatePosition()">
Calculate Lot Size
</button>

<div class="calc-result">

<span>Estimated Lot Size</span>
<strong id="lotResult">0.00</strong>

</div>

</div>


<div class="calculator-card">

<h2>Compounding</h2>

<label>Starting Balance</label>
<input id="compoundStart" type="number" step="any" placeholder="100">

<label>Monthly Return %</label>
<input id="compoundRate" type="number" step="any" placeholder="5">

<label>Months</label>
<input id="compoundMonths" type="number" step="1" placeholder="12">

<button class="primary-btn full" onclick="calculateCompound()">
Calculate
</button>

<div class="calc-result">

<span>Projected Balance</span>
<strong id="compoundResult">0</strong>

</div>

</div>

</div>

{% endblock %}
HTML

cat > templates/analysis.html <<'HTML'
{% extends "base.html" %}

{% block title %}Chart Analysis — DURJOY FX{% endblock %}

{% block content %}

<div class="page-head">

<div>
<span class="eyebrow">MARKET ANALYSIS</span>
<h1>Chart Analysis Workspace</h1>
<p>SMC এবং technical analysis-এর জন্য তোমার workspace.</p>
</div>

</div>


<div class="chart-panel">

<div class="chart-toolbar">

<button onclick="addLine()">Horizontal Line</button>
<button onclick="addNote()">Add Note</button>
<button onclick="clearChart()">Clear</button>

<select>
<option>EURUSD</option>
<option>GBPUSD</option>
<option>XAUUSD</option>
<option>USDJPY</option>
<option>BTCUSD</option>
</select>

<select>
<option>1M</option>
<option>5M</option>
<option>15M</option>
<option>1H</option>
<option>4H</option>
<option>1D</option>
</select>

</div>


<div id="analysisCanvas" class="analysis-canvas">

<div class="candles">

<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>
<span></span>

</div>

<div class="analysis-message">
CHART WORKSPACE
</div>

</div>

</div>


<div class="smc-grid">

<div class="smc-card">
<strong>Liquidity</strong>
<span>Mark liquidity zones</span>
</div>

<div class="smc-card">
<strong>Order Block</strong>
<span>Identify institutional zones</span>
</div>

<div class="smc-card">
<strong>Fair Value Gap</strong>
<span>Mark FVG areas</span>
</div>

<div class="smc-card">
<strong>Market Structure</strong>
<span>BOS / CHOCH / MSS</span>
</div>

<div class="smc-card">
<strong>Premium / Discount</strong>
<span>Analyze dealing range</span>
</div>

<div class="smc-card">
<strong>Entry Model</strong>
<span>Entry / SL / TP planning</span>
</div>

</div>

{% endblock %}
HTML

cat > templates/analytics.html <<'HTML'
{% extends "base.html" %}

{% block title %}Analytics — DURJOY FX{% endblock %}

{% block content %}

<div class="page-head">

<div>
<span class="eyebrow">PERFORMANCE ANALYTICS</span>
<h1>Trading Analytics</h1>
<p>Understand where your edge is coming from.</p>
</div>

</div>


<div class="panel">

<div class="panel-head">
<h2>Pair Performance</h2>
</div>

{% if pair_stats %}

<div class="table-wrap">

<table>

<thead>
<tr>
<th>Pair</th>
<th>Total Trades</th>
<th>Wins</th>
<th>Win Rate</th>
<th>Net P/L</th>
</tr>
</thead>

<tbody>

{% for pair,data in pair_stats.items() %}

<tr>

<td><strong>{{ pair }}</strong></td>

<td>{{ data.trades }}</td>

<td>{{ data.wins }}</td>

<td>
{% if data.trades %}
{{ ((data.wins / data.trades) * 100)|round(1) }}%
{% else %}
0%
{% endif %}
</td>

<td class="{% if data.pnl >= 0 %}positive{% else %}negative{% endif %}">
{{ data.pnl|round(2) }}
</td>

</tr>

{% endfor %}

</tbody>

</table>

</div>

{% else %}

<div class="empty">
<p>Analytics will appear after you add trades.</p>
</div>

{% endif %}

</div>

{% endblock %}
HTML

cat > templates/calendar.html <<'HTML'
{% extends "base.html" %}

{% block title %}Trading Calendar — DURJOY FX{% endblock %}

{% block content %}

<div class="page-head">

<div>
<span class="eyebrow">TRADING CALENDAR</span>
<h1>Trading Calendar</h1>
<p>Track your daily trading activity.</p>
</div>

</div>

<div class="calendar-placeholder">

<div class="calendar-top">
<span>Trading Performance Calendar</span>
<span>Coming Next</span>
</div>

<div class="calendar-grid">

{% for day in range(1,32) %}

<div class="calendar-day">
<span>{{ day }}</span>
<small>—</small>
</div>

{% endfor %}

</div>

</div>

{% endblock %}
HTML

cat > templates/profile.html <<'HTML'
{% extends "base.html" %}

{% block title %}Profile — DURJOY FX{% endblock %}

{% block content %}

<div class="profile-layout">

<div class="profile-card">

<div class="avatar">
{{ user["username"][0]|upper }}
</div>

<h1>{{ user["username"] }}</h1>

<p>{{ user["email"] }}</p>

<div class="profile-meta">
Member since {{ user["created_at"] }}
</div>

</div>


<div class="form-panel">

<span class="eyebrow">PROFILE SETTINGS</span>

<h2>Trading Profile</h2>

<form method="POST">

<label>Bio</label>

<textarea name="bio" rows="5">{{ user["bio"] }}</textarea>

<label>Trading Experience</label>

<select name="experience">

<option value="">Select</option>

<option {% if user["experience"]=="Beginner" %}selected{% endif %}>
Beginner
</option>

<option {% if user["experience"]=="Intermediate" %}selected{% endif %}>
Intermediate
</option>

<option {% if user["experience"]=="Advanced" %}selected{% endif %}>
Advanced
</option>

<option {% if user["experience"]=="Professional" %}selected{% endif %}>
Professional
</option>

</select>

<button class="primary-btn" type="submit">
Save Profile
</button>

</form>

</div>

</div>

{% endblock %}
HTML

cat > templates/404.html <<'HTML'
{% extends "base.html" %}

{% block title %}404 — DURJOY FX{% endblock %}

{% block content %}

<div class="empty-page">

<h1>404</h1>

<h2>Page not found</h2>

<p>The page you're looking for doesn't exist.</p>

<a class="primary-btn" href="{{ url_for('home') }}">
Back Home
</a>

</div>

{% endblock %}
HTML

cat > static/css/style.css <<'CSS'
:root{
--bg:#10151c;
--surface:#171e27;
--surface2:#1c2530;
--border:#2b3542;
--text:#edf2f7;
--muted:#8f9baa;
--accent:#58d68d;
--accent2:#38b878;
--danger:#ff6b6b;
--shadow:0 20px 60px rgba(0,0,0,.25);
}

*{
box-sizing:border-box;
margin:0;
padding:0;
}

body{
font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif;
background:
radial-gradient(circle at 80% 0%,rgba(57,214,141,.08),transparent 30%),
var(--bg);
color:var(--text);
line-height:1.6;
}

a{
color:inherit;
text-decoration:none;
}

.navbar{
height:76px;
border-bottom:1px solid var(--border);
display:flex;
align-items:center;
justify-content:space-between;
padding:0 5%;
background:rgba(16,21,28,.92);
backdrop-filter:blur(15px);
position:sticky;
top:0;
z-index:10;
}

.brand{
display:flex;
align-items:center;
gap:12px;
}

.brand-mark{
width:40px;
height:40px;
border-radius:12px;
display:grid;
place-items:center;
background:var(--accent);
color:#08120d;
font-weight:900;
font-size:20px;
}

.brand strong{
display:block;
letter-spacing:1px;
}

.brand span{
display:block;
font-size:9px;
color:var(--muted);
letter-spacing:2px;
}

nav{
display:flex;
align-items:center;
gap:8px;
}

nav a{
padding:9px 12px;
border-radius:8px;
font-size:13px;
color:var(--muted);
}

nav a:hover{
background:var(--surface);
color:var(--text);
}

.container{
width:min(1200px,90%);
margin:auto;
min-height:calc(100vh - 150px);
}

.primary-btn,
.secondary-btn{
display:inline-flex;
align-items:center;
justify-content:center;
padding:12px 20px;
border-radius:9px;
font-weight:700;
border:1px solid transparent;
cursor:pointer;
transition:.2s;
}

.primary-btn{
background:var(--accent);
color:#07130d;
}

.primary-btn:hover{
background:var(--accent2);
transform:translateY(-1px);
}

.secondary-btn{
border-color:var(--border);
background:var(--surface);
color:var(--text);
}

.full{
width:100%;
}

.hero{
min-height:680px;
display:grid;
grid-template-columns:1.1fr .9fr;
gap:70px;
align-items:center;
}

.badge,
.eyebrow{
font-size:11px;
letter-spacing:2px;
font-weight:800;
color:var(--accent);
}

.hero h1{
font-size:clamp(48px,7vw,82px);
line-height:1.02;
margin:18px 0;
letter-spacing:-3px;
}

.hero h1 span{
color:var(--accent);
}

.hero p{
max-width:650px;
font-size:18px;
color:var(--muted);
}

.hero-actions{
display:flex;
gap:12px;
margin-top:30px;
}

.hero-card{
background:linear-gradient(145deg,var(--surface2),var(--surface));
border:1px solid var(--border);
border-radius:24px;
padding:30px;
box-shadow:var(--shadow);
}

.mini-label{
color:var(--muted);
font-size:11px;
letter-spacing:2px;
}

.mock-number{
font-size:48px;
font-weight:800;
margin:20px 0;
}

.mock-chart{
height:180px;
display:flex;
align-items:end;
gap:10px;
border-bottom:1px solid var(--border);
}

.mock-chart div{
flex:1;
background:var(--accent);
opacity:.7;
border-radius:5px 5px 0 0;
}

.mock-chart div:nth-child(1){height:25%}
.mock-chart div:nth-child(2){height:35%}
.mock-chart div:nth-child(3){height:30%}
.mock-chart div:nth-child(4){height:50%}
.mock-chart div:nth-child(5){height:42%}
.mock-chart div:nth-child(6){height:65%}
.mock-chart div:nth-child(7){height:55%}
.mock-chart div:nth-child(8){height:85%}

.mock-stats{
display:grid;
grid-template-columns:1fr 1fr;
gap:15px;
margin-top:22px;
}

.mock-stats div{
padding:15px;
background:var(--bg);
border-radius:10px;
}

.mock-stats span,
.stat-card span,
.performance-box span,
.calc-result span{
display:block;
font-size:12px;
color:var(--muted);
}

.mock-stats strong{
font-size:22px;
}

.section{
padding:70px 0;
}

.section-heading{
display:flex;
justify-content:space-between;
align-items:end;
gap:30px;
margin-bottom:35px;
}

.section-heading h2{
font-size:38px;
margin-top:8px;
}

.section-heading p{
color:var(--muted);
max-width:420px;
}

.feature-grid{
display:grid;
grid-template-columns:repeat(3,1fr);
gap:16px;
}

.feature-card,
.stat-card,
.panel,
.form-panel,
.calculator-card,
.profile-card,
.calendar-placeholder{
background:rgba(23,30,39,.9);
border:1px solid var(--border);
border-radius:16px;
}

.feature-card{
padding:25px;
}

.feature-icon{
font-size:30px;
margin-bottom:20px;
}

.feature-card h3{
margin-bottom:8px;
}

.feature-card p{
color:var(--muted);
font-size:14px;
}

.quote{
margin:80px 0;
padding:80px 30px;
text-align:center;
background:var(--surface);
border:1px solid var(--border);
border-radius:20px;
}

.quote h2{
font-size:40px;
line-height:1.2;
}

.quote p{
color:var(--accent);
margin-top:20px;
letter-spacing:3px;
}

.page-head{
display:flex;
justify-content:space-between;
align-items:end;
gap:20px;
padding:55px 0 30px;
}

.page-head h1{
font-size:38px;
margin:8px 0;
}

.page-head p{
color:var(--muted);
}

.stats-grid{
display:grid;
grid-template-columns:repeat(6,1fr);
gap:12px;
margin-bottom:18px;
}

.stat-card{
padding:20px;
}

.stat-card strong{
display:block;
font-size:25px;
margin-top:6px;
}

.positive{
color:var(--accent)!important;
}

.negative{
color:var(--danger)!important;
}

.dashboard-grid{
display:grid;
grid-template-columns:2fr 1fr;
gap:18px;
margin-bottom:18px;
}

.panel{
padding:25px;
margin-bottom:18px;
}

.panel-head{
display:flex;
justify-content:space-between;
align-items:center;
margin-bottom:20px;
}

.panel-head h2{
font-size:19px;
}

.panel-head span,
.panel-head a{
font-size:12px;
color:var(--muted);
}

.performance-box{
display:grid;
grid-template-columns:repeat(4,1fr);
gap:12px;
}

.performance-box div{
padding:15px;
background:var(--bg);
border-radius:10px;
}

.performance-box strong{
font-size:18px;
}

.empty-chart{
height:250px;
margin-top:18px;
border:1px dashed var(--border);
border-radius:12px;
display:flex;
align-items:center;
justify-content:center;
position:relative;
overflow:hidden;
}

.chart-line{
position:absolute;
width:80%;
height:2px;
background:var(--accent);
transform:rotate(-8deg);
opacity:.6;
}

.empty-chart p{
color:var(--muted);
font-size:12px;
z-index:1;
background:var(--surface);
padding:5px 10px;
}

.tool-link{
display:block;
padding:15px;
background:var(--bg);
border:1px solid var(--border);
border-radius:10px;
margin-bottom:10px;
color:var(--muted);
}

.tool-link:hover{
color:var(--text);
border-color:var(--accent);
}

.table-wrap{
overflow-x:auto;
}

table{
width:100%;
border-collapse:collapse;
font-size:13px;
}

th,
td{
padding:15px 10px;
text-align:left;
border-bottom:1px solid var(--border);
white-space:nowrap;
}

th{
font-size:11px;
color:var(--muted);
text-transform:uppercase;
}

.status{
font-size:10px;
padding:4px 8px;
border-radius:20px;
background:var(--surface2);
color:var(--muted);
}

.status.win{
color:var(--accent);
background:rgba(88,214,141,.1);
}

.status.loss{
color:var(--danger);
background:rgba(255,107,107,.1);
}

.empty{
padding:50px;
text-align:center;
color:var(--muted);
}

.empty .primary-btn{
margin-top:20px;
}

.auth-page{
min-height:650px;
display:grid;
place-items:center;
}

.auth-card{
width:min(440px,100%);
background:var(--surface);
border:1px solid var(--border);
border-radius:20px;
padding:35px;
box-shadow:var(--shadow);
}

.auth-card h1{
margin:10px 0;
font-size:32px;
}

.auth-card p{
color:var(--muted);
margin-bottom:25px;
}

.auth-link{
margin-top:20px!important;
font-size:13px;
text-align:center;
}

.auth-link a{
color:var(--accent);
}

label{
display:block;
font-size:12px;
font-weight:700;
color:var(--muted);
margin:16px 0 7px;
}

input,
select,
textarea{
width:100%;
padding:13px 14px;
background:var(--bg);
color:var(--text);
border:1px solid var(--border);
border-radius:9px;
outline:none;
font:inherit;
}

input:focus,
select:focus,
textarea:focus{
border-color:var(--accent);
}

textarea{
resize:vertical;
}

.form-panel{
padding:30px;
}

.form-grid{
display:grid;
grid-template-columns:repeat(3,1fr);
gap:5px 15px;
margin-bottom:15px;
}

.calculator-grid{
display:grid;
grid-template-columns:repeat(2,1fr);
gap:18px;
padding-bottom:50px;
}

.calculator-card{
padding:25px;
}

.calculator-card h2{
margin-bottom:10px;
}

.calc-result{
margin-top:20px;
padding:18px;
background:var(--bg);
border-radius:10px;
}

.calc-result strong{
display:block;
font-size:28px;
margin-top:5px;
}

.chart-panel{
background:var(--surface);
border:1px solid var(--border);
border-radius:16px;
padding:15px;
}

.chart-toolbar{
display:flex;
gap:8px;
flex-wrap:wrap;
margin-bottom:12px;
}

.chart-toolbar button,
.chart-toolbar select{
width:auto;
padding:9px 12px;
}

.analysis-canvas{
height:520px;
background:
linear-gradient(var(--border) 1px,transparent 1px),
linear-gradient(90deg,var(--border) 1px,transparent 1px),
#0c1117;
background-size:50px 50px;
border-radius:10px;
position:relative;
overflow:hidden;
}

.candles{
position:absolute;
inset:50px;
display:flex;
align-items:center;
justify-content:space-around;
}

.candles span{
width:7px;
height:var(--h,80px);
background:var(--accent);
position:relative;
}

.candles span:nth-child(2n){
height:120px;
}

.candles span:nth-child(3n){
height:55px;
}

.candles span::before{
content:"";
position:absolute;
width:1px;
height:180px;
background:var(--accent);
left:3px;
top:-30px;
opacity:.8;
}

.analysis-message{
position:absolute;
bottom:15px;
left:15px;
color:var(--muted);
font-size:11px;
letter-spacing:2px;
}

.smc-grid{
display:grid;
grid-template-columns:repeat(3,1fr);
gap:12px;
margin:18px 0 50px;
}

.smc-card{
padding:20px;
background:var(--surface);
border:1px solid var(--border);
border-radius:12px;
}

.smc-card strong,
.smc-card span{
display:block;
}

.smc-card span{
color:var(--muted);
font-size:12px;
margin-top:5px;
}

.profile-layout{
display:grid;
grid-template-columns:320px 1fr;
gap:18px;
padding:60px 0;
}

.profile-card{
padding:30px;
text-align:center;
height:max-content;
}

.avatar{
width:90px;
height:90px;
margin:0 auto 20px;
display:grid;
place-items:center;
border-radius:50%;
background:var(--accent);
color:#07130d;
font-size:36px;
font-weight:900;
}

.profile-card p{
color:var(--muted);
}

.profile-meta{
margin-top:20px;
padding-top:20px;
border-top:1px solid var(--border);
font-size:12px;
color:var(--muted);
}

.calendar-placeholder{
padding:25px;
margin-bottom:50px;
}

.calendar-top{
display:flex;
justify-content:space-between;
margin-bottom:20px;
color:var(--muted);
}

.calendar-grid{
display:grid;
grid-template-columns:repeat(7,1fr);
gap:8px;
}

.calendar-day{
height:90px;
padding:10px;
background:var(--bg);
border-radius:8px;
border:1px solid var(--border);
}

.calendar-day span{
display:block;
font-weight:700;
}

.calendar-day small{
color:var(--muted);
}

.empty-page{
text-align:center;
padding:150px 20px;
}

.empty-page h1{
font-size:100px;
color:var(--accent);
line-height:1;
}

.empty-page h2{
font-size:30px;
margin:15px;
}

.alert{
margin-top:20px;
padding:12px 15px;
border-radius:8px;
font-size:13px;
}

.alert.success{
background:rgba(88,214,141,.1);
color:var(--accent);
border:1px solid rgba(88,214,141,.2);
}

.alert.error{
background:rgba(255,107,107,.1);
color:var(--danger);
border:1px solid rgba(255,107,107,.2);
}

footer{
margin-top:80px;
padding:35px 5%;
border-top:1px solid var(--border);
display:flex;
justify-content:space-between;
color:var(--muted);
font-size:12px;
}

footer strong{
color:var(--text);
letter-spacing:1px;
}

@media(max-width:900px){

.hero{
grid-template-columns:1fr;
padding:70px 0;
}

.feature-grid{
grid-template-columns:repeat(2,1fr);
}

.stats-grid{
grid-template-columns:repeat(3,1fr);
}

.form-grid{
grid-template-columns:repeat(2,1fr);
}

.dashboard-grid{
grid-template-columns:1fr;
}

.smc-grid{
grid-template-columns:repeat(2,1fr);
}

.profile-layout{
grid-template-columns:1fr;
}

}

@media(max-width:600px){

.navbar{
height:auto;
padding:15px;
align-items:flex-start;
gap:12px;
}

nav{
display:none;
}

.container{
width:92%;
}

.hero{
min-height:auto;
padding:70px 0;
}

.hero h1{
font-size:48px;
}

.hero-card{
padding:20px;
}

.section-heading{
display:block;
}

.section-heading h2{
font-size:30px;
}

.feature-grid,
.calculator-grid,
.form-grid,
.smc-grid{
grid-template-columns:1fr;
}

.stats-grid{
grid-template-columns:repeat(2,1fr);
}

.performance-box{
grid-template-columns:repeat(2,1fr);
}

.page-head{
display:block;
}

.page-head .primary-btn{
margin-top:20px;
}

footer{
display:block;
}

footer div+div{
margin-top:15px;
}

}
CSS

cat > static/js/app.js <<'JS'
function calculateRisk(){

const balance =
parseFloat(document.getElementById("balance").value) || 0;

const risk =
parseFloat(document.getElementById("risk").value) || 0;

const sl =
parseFloat(document.getElementById("slpips").value) || 0;

const amount =
balance * risk / 100;

const perPip =
sl > 0 ? amount / sl : 0;

document.getElementById("riskAmount").textContent =
amount.toFixed(2);

document.getElementById("riskPerPip").textContent =
perPip.toFixed(4);
}


function calculateRR(){

const risk =
parseFloat(document.getElementById("riskPips").value) || 0;

const reward =
parseFloat(document.getElementById("rewardPips").value) || 0;

const rr =
risk > 0 ? reward / risk : 0;

document.getElementById("rrResult").textContent =
"1 : " + rr.toFixed(2);
}


function calculatePosition(){

const risk =
parseFloat(document.getElementById("positionRisk").value) || 0;

const sl =
parseFloat(document.getElementById("positionSL").value) || 0;

const pipValue =
parseFloat(document.getElementById("pipValue").value) || 0;

const lot =
sl > 0 && pipValue > 0
? risk / (sl * pipValue)
: 0;

document.getElementById("lotResult").textContent =
lot.toFixed(2);
}


function calculateCompound(){

const start =
parseFloat(document.getElementById("compoundStart").value) || 0;

const rate =
parseFloat(document.getElementById("compoundRate").value) || 0;

const months =
parseInt(document.getElementById("compoundMonths").value) || 0;

const result =
start * Math.pow(1 + rate / 100, months);

document.getElementById("compoundResult").textContent =
result.toFixed(2);
}


function addLine(){

const canvas =
document.getElementById("analysisCanvas");

const line =
document.createElement("div");

line.style.position = "absolute";
line.style.left = "5%";
line.style.right = "5%";
line.style.top = "50%";
line.style.height = "1px";
line.style.background = "rgba(88,214,141,.8)";

canvas.appendChild(line);
}


function addNote(){

const canvas =
document.getElementById("analysisCanvas");

const note =
document.createElement("div");

note.textContent = "Analysis Note";

note.style.position = "absolute";
note.style.top = "25%";
note.style.left = "30%";
note.style.padding = "8px 12px";
note.style.background = "#171e27";
note.style.border = "1px solid #2b3542";
note.style.borderRadius = "6px";
note.style.color = "#edf2f7";
note.style.fontSize = "12px";

canvas.appendChild(note);
}


function clearChart(){

const canvas =
document.getElementById("analysisCanvas");

const candles =
canvas.querySelector(".candles");

const message =
canvas.querySelector(".analysis-message");

canvas.innerHTML = "";

canvas.appendChild(candles);
canvas.appendChild(message);
}
JS

echo ""
echo "======================================"
echo "     DURJOY FX V2 READY"
echo "======================================"
echo ""
echo "Installing required packages..."
python3 -m pip install -r requirements.txt

echo ""
echo "Database initializing..."
python3 -c "from app import init_db; init_db(); print('DATABASE OK')"

echo ""
echo "======================================"
echo "        UPGRADE COMPLETE"
echo "======================================"
echo ""
echo "Run:"
echo "python3 app.py"
echo ""
