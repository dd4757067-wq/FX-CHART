#!/bin/bash

mkdir -p templates static/css static/js database

cat > app.py <<'PY'
from flask import Flask, render_template, request, redirect, url_for, session, flash
import sqlite3
import os
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask("DURJOY_FX")
app.secret_key = "DURJOY-FX-CHANGE-THIS-SECRET-KEY"

BASE_DIR = os.path.dirname(os.path.abspath(_file_))
DB_PATH = os.path.join(BASE_DIR, "database", "durjoy_fx.db")


def get_db():
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    return db


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    db = get_db()

    db.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    db.execute("""
        CREATE TABLE IF NOT EXISTS trades (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            pair TEXT NOT NULL,
            direction TEXT NOT NULL,
            entry REAL,
            stop_loss REAL,
            take_profit REAL,
            lot_size REAL,
            risk_percent REAL,
            result TEXT,
            profit_loss REAL,
            strategy TEXT,
            session_name TEXT,
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(user_id) REFERENCES users(id)
        )
    """)

    db.commit()
    db.close()


@app.route("/")
def home():
    if "user_id" in session:
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
                "INSERT INTO users (username, email, password) VALUES (?, ?, ?)",
                (username, email, generate_password_hash(password))
            )
            db.commit()
        except sqlite3.IntegrityError:
            db.close()
            flash("Username অথবা Email ইতিমধ্যে ব্যবহার করা হয়েছে।", "error")
            return redirect(url_for("register"))

        user = db.execute(
            "SELECT id FROM users WHERE email = ?", (email,)
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
            "SELECT * FROM users WHERE email = ?", (email,)
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
    if "user_id" not in session:
        return redirect(url_for("login"))

    db = get_db()

    trades = db.execute(
        "SELECT * FROM trades WHERE user_id = ? ORDER BY id DESC",
        (session["user_id"],)
    ).fetchall()

    total = len(trades)
    wins = sum(1 for t in trades if t["result"] == "Win")
    losses = sum(1 for t in trades if t["result"] == "Loss")
    pnl = sum((t["profit_loss"] or 0) for t in trades)

    win_rate = round((wins / total) * 100, 1) if total else 0

    db.close()

    return render_template(
        "dashboard.html",
        trades=trades,
        total=total,
        wins=wins,
        losses=losses,
        pnl=round(pnl, 2),
        win_rate=win_rate
    )


@app.route("/journal", methods=["GET", "POST"])
def journal():
    if "user_id" not in session:
        return redirect(url_for("login"))

    if request.method == "POST":
        pair = request.form.get("pair", "").strip()
        direction = request.form.get("direction", "")
        entry = request.form.get("entry") or None
        stop_loss = request.form.get("stop_loss") or None
        take_profit = request.form.get("take_profit") or None
        lot_size = request.form.get("lot_size") or None
        risk_percent = request.form.get("risk_percent") or None
        result = request.form.get("result", "")
        profit_loss = request.form.get("profit_loss") or 0
        strategy = request.form.get("strategy", "")
        session_name = request.form.get("session_name", "")
        notes = request.form.get("notes", "")

        if not pair:
            flash("Currency Pair দিন।", "error")
            return redirect(url_for("journal"))

        db = get_db()

        db.execute("""
            INSERT INTO trades
            (user_id, pair, direction, entry, stop_loss, take_profit,
             lot_size, risk_percent, result, profit_loss, strategy,
             session_name, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            session["user_id"], pair, direction, entry, stop_loss,
            take_profit, lot_size, risk_percent, result, profit_loss,
            strategy, session_name, notes
        ))

        db.commit()
        db.close()

        flash("Trade successfully saved.", "success")
        return redirect(url_for("dashboard"))

    return render_template("journal.html")


@app.route("/calculator")
def calculator():
    if "user_id" not in session:
        return redirect(url_for("login"))

    return render_template("calculator.html")


@app.route("/analysis")
def analysis():
    if "user_id" not in session:
        return redirect(url_for("login"))

    return render_template("analysis.html")


@app.route("/profile")
def profile():
    if "user_id" not in session:
        return redirect(url_for("login"))

    db = get_db()

    user = db.execute(
        "SELECT username, email, created_at FROM users WHERE id = ?",
        (session["user_id"],)
    ).fetchone()

    db.close()

    return render_template("profile.html", user=user)


@app.errorhandler(404)
def not_found(error):
    return render_template("404.html"), 404


init_db()

app.run(host="0.0.0.0", port=5000, debug=True)
PY


cat > templates/base.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="DURJOY FX - Professional Trading Journal and Analysis Platform">
    <title>{% block title %}DURJOY FX{% endblock %}</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>

<body>

<header class="navbar">
    <a href="/" class="logo">
        <span class="logo-mark">D</span>
        <span>DURJOY <b>FX</b></span>
    </a>

    <nav>
        {% if session.get("user_id") %}
            <a href="/dashboard">Dashboard</a>
            <a href="/journal">Journal</a>
            <a href="/analysis">Analysis</a>
            <a href="/calculator">Calculator</a>
            <a href="/profile">Profile</a>
            <a href="/logout" class="nav-button">Logout</a>
        {% else %}
            <a href="/login">Login</a>
            <a href="/register" class="nav-button">Get Started</a>
        {% endif %}
    </nav>
</header>

<main>
    {% with messages = get_flashed_messages(with_categories=true) %}
        {% for category, message in messages %}
            <div class="flash {{ category }}">{{ message }}</div>
        {% endfor %}
    {% endwith %}

    {% block content %}{% endblock %}
</main>

<footer>
    <div>
        <strong>DURJOY FX</strong>
        <p>Trade smarter. Journal better. Improve consistently.</p>
    </div>
    <span>© 2026 DURJOY FX</span>
</footer>

<script src="{{ url_for('static', filename='js/app.js') }}"></script>
</body>
</html>
HTML


cat > templates/index.html <<'HTML'
{% extends "base.html" %}

{% block title %}DURJOY FX — Trading Journal Platform{% endblock %}

{% block content %}

<section class="hero">
    <div class="hero-content">
        <div class="eyebrow">TRADING JOURNAL • ANALYSIS • PERFORMANCE</div>

        <h1>
            Master Your Trading.<br>
            <span>One Trade At A Time.</span>
        </h1>

        <p>
            একটি professional workspace যেখানে তুমি তোমার trades journal,
            performance analysis এবং trading decisions এক জায়গায় manage করতে পারবে।
        </p>

        <div class="hero-buttons">
            <a href="/register" class="primary-button">Create Free Account →</a>
            <a href="/login" class="secondary-button">Sign In</a>
        </div>
    </div>

    <div class="hero-panel">
        <div class="mini-top">
            <span>TRADING PERFORMANCE</span>
            <span class="live-dot">● LIVE</span>
        </div>

        <div class="big-number">+24.68%</div>

        <div class="chart-lines">
            <div></div><div></div><div></div><div></div>
            <svg viewBox="0 0 500 160" preserveAspectRatio="none">
                <polyline
                    points="0,135 60,125 100,140 150,105 200,115 245,75 290,92 340,55 390,65 430,30 500,18"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="4"/>
            </svg>
        </div>

        <div class="mini-stats">
            <div><small>WIN RATE</small><b>68.4%</b></div>
            <div><small>TRADES</small><b>127</b></div>
            <div><small>R:R</small><b>1 : 2.4</b></div>
        </div>
    </div>
</section>

<section class="features section">
    <div class="section-heading">
        <div class="eyebrow">BUILT FOR TRADERS</div>
        <h2>Everything you need to improve.</h2>
        <p>একটি trading workspace-এর মধ্যে প্রয়োজনীয় গুরুত্বপূর্ণ tools.</p>
    </div>

    <div class="feature-grid">
        <div class="feature-card">
            <div class="icon">📒</div>
            <h3>Trading Journal</h3>
            <p>প্রতিটি trade-এর entry, risk, result, strategy এবং notes সংরক্ষণ করো।</p>
        </div>

        <div class="feature-card">
            <div class="icon">📊</div>
            <h3>Performance Analytics</h3>
            <p>Win rate, P/L, trading statistics এবং performance বুঝতে সাহায্য করবে।</p>
        </div>

        <div class="feature-card">
            <div class="icon">⌁</div>
            <h3>Chart Analysis</h3>
            <p>নিজের market analysis workspace তৈরি করার foundation।</p>
        </div>

        <div class="feature-card">
            <div class="icon">🧮</div>
            <h3>Trading Calculator</h3>
            <p>Risk, position size এবং risk/reward হিসাব করার জন্য dedicated tools.</p>
        </div>
    </div>
</section>

<section class="quote-section">
    <div>
        <div class="eyebrow">THE DURJOY FX METHOD</div>
        <h2>Don't just trade.<br><span>Study your trades.</span></h2>
    </div>
    <p>
        একজন disciplined trader শুধু market দেখে না—
        নিজের performance-ও analyze করে।
    </p>
</section>

{% endblock %}
HTML


cat > templates/register.html <<'HTML'
{% extends "base.html" %}
{% block title %}Create Account — DURJOY FX{% endblock %}

{% block content %}
<section class="auth-page">
    <div class="auth-card">
        <div class="eyebrow">START YOUR JOURNEY</div>
        <h1>Create your account</h1>
        <p>নিজের trading workspace তৈরি করো।</p>

        <form method="POST">
            <label>Username</label>
            <input name="username" required placeholder="Your username">

            <label>Email</label>
            <input type="email" name="email" required placeholder="you@example.com">

            <label>Password</label>
            <input type="password" name="password" required placeholder="Minimum 6 characters">

            <button class="primary-button full" type="submit">Create Account</button>
        </form>

        <p class="auth-bottom">Already have an account? <a href="/login">Login</a></p>
    </div>
</section>
{% endblock %}
HTML


cat > templates/login.html <<'HTML'
{% extends "base.html" %}
{% block title %}Login — DURJOY FX{% endblock %}

{% block content %}
<section class="auth-page">
    <div class="auth-card">
        <div class="eyebrow">WELCOME BACK</div>
        <h1>Sign in</h1>
        <p>Your trading workspace is waiting.</p>

        <form method="POST">
            <label>Email</label>
            <input type="email" name="email" required placeholder="you@example.com">

            <label>Password</label>
            <input type="password" name="password" required placeholder="Your password">

            <button class="primary-button full" type="submit">Login</button>
        </form>

        <p class="auth-bottom">Don't have an account? <a href="/register">Create one</a></p>
    </div>
</section>
{% endblock %}
HTML


cat > templates/dashboard.html <<'HTML'
{% extends "base.html" %}
{% block title %}Dashboard — DURJOY FX{% endblock %}

{% block content %}

<section class="dashboard">
    <div class="dashboard-head">
        <div>
            <div class="eyebrow">YOUR WORKSPACE</div>
            <h1>Welcome back, {{ session["username"] }}</h1>
            <p>Track, review and improve your trading performance.</p>
        </div>

        <a href="/journal" class="primary-button">+ Add Trade</a>
    </div>

    <div class="stat-grid">
        <div class="stat-card">
            <span>Total Trades</span>
            <strong>{{ total }}</strong>
        </div>

        <div class="stat-card">
            <span>Win Rate</span>
            <strong>{{ win_rate }}%</strong>
        </div>

        <div class="stat-card">
            <span>Winning Trades</span>
            <strong>{{ wins }}</strong>
        </div>

        <div class="stat-card">
            <span>Net P/L</span>
            <strong class="{{ 'profit' if pnl >= 0 else 'loss' }}">
                {{ "%.2f"|format(pnl) }}
            </strong>
        </div>
    </div>

    <div class="dashboard-grid">

        <div class="panel large-panel">
            <div class="panel-head">
                <div>
                    <h2>Recent Trades</h2>
                    <p>Your latest journal entries.</p>
                </div>
                <a href="/journal">View journal →</a>
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
                        </tr>
                    </thead>

                    <tbody>
                    {% for trade in trades[:10] %}
                        <tr>
                            <td><b>{{ trade["pair"] }}</b></td>
                            <td>{{ trade["direction"] }}</td>
                            <td>
                                <span class="result {{ trade['result']|lower }}">
                                    {{ trade["result"] or "—" }}
                                </span>
                            </td>
                            <td>{{ "%.2f"|format(trade["profit_loss"] or 0) }}</td>
                            <td>{{ trade["strategy"] or "—" }}</td>
                        </tr>
                    {% endfor %}
                    </tbody>
                </table>
            </div>
            {% else %}
                <div class="empty">
                    <div>📒</div>
                    <h3>No trades yet</h3>
                    <p>Your first journal entry will appear here.</p>
                    <a href="/journal" class="primary-button">Add your first trade</a>
                </div>
            {% endif %}
        </div>

        <div class="panel">
            <h2>Quick Tools</h2>
            <div class="quick-links">
                <a href="/journal">📒 <span>Trading Journal</span> <b>→</b></a>
                <a href="/analysis">📈 <span>Chart Analysis</span> <b>→</b></a>
                <a href="/calculator">🧮 <span>Risk Calculator</span> <b>→</b></a>
                <a href="/profile">👤 <span>My Profile</span> <b>→</b></a>
            </div>
        </div>

    </div>
</section>

{% endblock %}
HTML


cat > templates/journal.html <<'HTML'
{% extends "base.html" %}
{% block title %}Trading Journal — DURJOY FX{% endblock %}

{% block content %}
<section class="form-page">
    <div class="page-heading">
        <div class="eyebrow">TRADE JOURNAL</div>
        <h1>Record your trade.</h1>
        <p>প্রতিটি trade লিখে রাখো, পরে performance analyze করো।</p>
    </div>

    <form method="POST" class="trade-form">

        <div class="form-section">
            <h2>Trade Information</h2>

            <div class="form-grid">
                <div>
                    <label>Currency Pair *</label>
                    <input name="pair" required placeholder="EURUSD">
                </div>

                <div>
                    <label>Direction</label>
                    <select name="direction">
                        <option value="Buy">Buy</option>
                        <option value="Sell">Sell</option>
                    </select>
                </div>

                <div>
                    <label>Entry</label>
                    <input type="number" step="any" name="entry" placeholder="1.08500">
                </div>

                <div>
                    <label>Stop Loss</label>
                    <input type="number" step="any" name="stop_loss" placeholder="1.08200">
                </div>

                <div>
                    <label>Take Profit</label>
                    <input type="number" step="any" name="take_profit" placeholder="1.09100">
                </div>

                <div>
                    <label>Lot Size</label>
                    <input type="number" step="any" name="lot_size" placeholder="0.01">
                </div>

                <div>
                    <label>Risk %</label>
                    <input type="number" step="any" name="risk_percent" placeholder="1">
                </div>

                <div>
                    <label>Result</label>
                    <select name="result">
                        <option value="">Select result</option>
                        <option value="Win">Win</option>
                        <option value="Loss">Loss</option>
                        <option value="BE">Break Even</option>
                    </select>
                </div>

                <div>
                    <label>Profit / Loss</label>
                    <input type="number" step="any" name="profit_loss" placeholder="50">
                </div>

                <div>
                    <label>Market Session</label>
                    <select name="session_name">
                        <option value="">Select session</option>
                        <option>Asian</option>
                        <option>London</option>
                        <option>New York</option>
                        <option>London / New York</option>
                    </select>
                </div>
            </div>
        </div>

        <div class="form-section">
            <h2>Trade Review</h2>

            <div>
                <label>Strategy</label>
                <input name="strategy" placeholder="SMC / FVG / Breakout / Support & Resistance">
            </div>

            <div>
                <label>Notes & Psychology</label>
                <textarea name="notes" rows="7" placeholder="Why did you take this trade? What did you learn? How did you feel?"></textarea>
            </div>
        </div>

        <button class="primary-button" type="submit">Save Trade →</button>
    </form>
</section>
{% endblock %}
HTML


cat > templates/calculator.html <<'HTML'
{% extends "base.html" %}
{% block title %}Trading Calculator — DURJOY FX{% endblock %}

{% block content %}
<section class="calculator-page">
    <div class="page-heading">
        <div class="eyebrow">TRADING TOOLS</div>
        <h1>Risk & R:R Calculator</h1>
        <p>Trade নেওয়ার আগে নিজের risk বুঝে নাও।</p>
    </div>

    <div class="calculator-card">
        <div class="form-grid">
            <div>
                <label>Account Balance</label>
                <input id="balance" type="number" step="any" placeholder="1000">
            </div>

            <div>
                <label>Risk %</label>
                <input id="risk" type="number" step="any" placeholder="1">
            </div>

            <div>
                <label>Stop Loss (pips)</label>
                <input id="slPips" type="number" step="any" placeholder="20">
            </div>

            <div>
                <label>Reward (pips)</label>
                <input id="tpPips" type="number" step="any" placeholder="40">
            </div>
        </div>

        <button class="primary-button" onclick="calculateRisk()">Calculate</button>

        <div class="calculator-results">
            <div>
                <small>RISK AMOUNT</small>
                <strong id="riskAmount">$0.00</strong>
            </div>

            <div>
                <small>RISK : REWARD</small>
                <strong id="rrResult">1 : 0</strong>
            </div>
        </div>
    </div>
</section>
{% endblock %}
HTML


cat > templates/analysis.html <<'HTML'
{% extends "base.html" %}
{% block title %}Chart Analysis — DURJOY FX{% endblock %}

{% block content %}
<section class="analysis-page">

    <div class="page-heading">
        <div class="eyebrow">MARKET WORKSPACE</div>
        <h1>Chart Analysis</h1>
        <p>নিজের technical analysis করার জন্য dedicated workspace.</p>
    </div>

    <div class="chart-workspace">
        <div class="chart-toolbar">
            <button onclick="addLine()">＋ Line</button>
            <button onclick="addNote()">＋ Note</button>
            <button onclick="clearAnalysis()">Clear</button>
        </div>

        <div id="chartArea" class="fake-chart">
            <div class="grid-lines"></div>

            <svg viewBox="0 0 1000 450" preserveAspectRatio="none">
                <polyline
                    points="0,340 80,320 140,350 210,275 270,300 340,220 400,245 470,175 530,210 600,135 665,165 730,95 800,130 870,70 940,100 1000,45"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="5"/>
            </svg>

            <div id="analysisNotes"></div>
        </div>
    </div>

    <div class="disclaimer">
        <strong>Educational workspace:</strong>
        This platform is designed for journaling and analysis. It does not guarantee trading profits.
    </div>

</section>
{% endblock %}
HTML


cat > templates/profile.html <<'HTML'
{% extends "base.html" %}
{% block title %}Profile — DURJOY FX{% endblock %}

{% block content %}
<section class="profile-page">

    <div class="profile-cover"></div>

    <div class="profile-card">
        <div class="avatar">{{ user["username"][0]|upper }}</div>

        <div>
            <div class="eyebrow">TRADER PROFILE</div>
            <h1>{{ user["username"] }}</h1>
            <p>{{ user["email"] }}</p>
            <small>Member since {{ user["created_at"] }}</small>
        </div>
    </div>

</section>
{% endblock %}
HTML


cat > templates/404.html <<'HTML'
{% extends "base.html" %}
{% block title %}Page Not Found — DURJOY FX{% endblock %}

{% block content %}
<section class="auth-page">
    <div class="auth-card center">
        <div class="eyebrow">404</div>
        <h1>Page not found.</h1>
        <p>The page you're looking for doesn't exist.</p>
        <a href="/" class="primary-button">Back to Home</a>
    </div>
</section>
{% endblock %}
HTML


cat > static/css/style.css <<'CSS'
:root {
    --bg: #0b0f14;
    --bg2: #10161d;
    --panel: #131a22;
    --panel2: #171f28;
    --border: rgba(255,255,255,.08);
    --text: #e8edf2;
    --muted: #8c98a5;
    --accent: #72e0a5;
    --accent2: #45c985;
    --danger: #f47d8c;
    --shadow: 0 20px 60px rgba(0,0,0,.28);
}

* {
    box-sizing: border-box;
}

html {
    scroll-behavior: smooth;
}

body {
    margin: 0;
    background:
        radial-gradient(circle at 80% 0%, rgba(114,224,165,.07), transparent 30%),
        linear-gradient(135deg, #0b0f14, #0e1319 50%, #0a0e13);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
    min-height: 100vh;
}

a {
    color: inherit;
    text-decoration: none;
}

button,
input,
select,
textarea {
    font: inherit;
}

.navbar {
    height: 76px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 6%;
    border-bottom: 1px solid var(--border);
    background: rgba(11,15,20,.86);
    backdrop-filter: blur(18px);
    position: sticky;
    top: 0;
    z-index: 50;
}

.logo {
    display: flex;
    align-items: center;
    gap: 10px;
    font-weight: 800;
    letter-spacing: .5px;
}

.logo b {
    color: var(--accent);
}

.logo-mark {
    width: 34px;
    height: 34px;
    border: 1px solid rgba(114,224,165,.5);
    display: grid;
    place-items: center;
    border-radius: 9px;
    color: var(--accent);
    background: rgba(114,224,165,.07);
}

nav {
    display: flex;
    gap: 24px;
    align-items: center;
}

nav a {
    color: #aeb8c2;
    font-size: 14px;
    transition: .2s;
}

nav a:hover {
    color: var(--text);
}

.nav-button,
.primary-button {
    display: inline-flex;
    justify-content: center;
    align-items: center;
    border: 0;
    background: var(--accent);
    color: #08110c;
    padding: 12px 19px;
    border-radius: 9px;
    font-weight: 750;
    cursor: pointer;
    transition: .2s;
}

.nav-button:hover,
.primary-button:hover {
    background: #8cebb8;
    transform: translateY(-1px);
}

.secondary-button {
    display: inline-flex;
    justify-content: center;
    align-items: center;
    padding: 12px 19px;
    border: 1px solid var(--border);
    border-radius: 9px;
    color: var(--text);
    background: rgba(255,255,255,.025);
}

.hero {
    max-width: 1240px;
    margin: auto;
    min-height: 680px;
    padding: 100px 5%;
    display: grid;
    grid-template-columns: 1.1fr .9fr;
    gap: 70px;
    align-items: center;
}

.eyebrow {
    color: var(--accent);
    font-size: 11px;
    font-weight: 800;
    letter-spacing: 2px;
    margin-bottom: 18px;
}

.hero h1 {
    font-size: clamp(45px, 6vw, 78px);
    line-height: .98;
    letter-spacing: -3px;
    margin: 0;
}

.hero h1 span,
.quote-section span {
    color: var(--accent);
}

.hero p {
    max-width: 610px;
    color: var(--muted);
    font-size: 17px;
    line-height: 1.8;
    margin: 28px 0;
}

.hero-buttons {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
}

.hero-panel {
    padding: 28px;
    border: 1px solid var(--border);
    background: linear-gradient(145deg, rgba(255,255,255,.055), rgba(255,255,255,.018));
    border-radius: 20px;
    box-shadow: var(--shadow);
}

.mini-top,
.mini-stats {
    display: flex;
    justify-content: space-between;
    gap: 20px;
}

.mini-top {
    color: var(--muted);
    font-size: 11px;
    letter-spacing: 1.5px;
}

.live-dot {
    color: var(--accent);
}

.big-number {
    font-size: 50px;
    font-weight: 800;
    margin: 35px 0 15px;
}

.chart-lines {
    height: 180px;
    position: relative;
    overflow: hidden;
    color: var(--accent);
}

.chart-lines div {
    border-top: 1px solid var(--border);
    margin-top: 45px;
}

.chart-lines svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
}

.mini-stats {
    margin-top: 20px;
    border-top: 1px solid var(--border);
    padding-top: 20px;
}

.mini-stats small,
.calculator-results small {
    color: var(--muted);
    font-size: 10px;
    display: block;
    letter-spacing: 1px;
}

.mini-stats b {
    display: block;
    margin-top: 7px;
}

.section {
    max-width: 1240px;
    margin: auto;
    padding: 100px 5%;
}

.section-heading {
    max-width: 700px;
    margin-bottom: 45px;
}

.section-heading h2,
.quote-section h2 {
    font-size: clamp(32px, 4vw, 50px);
    letter-spacing: -1.5px;
    margin: 0 0 15px;
}

.section-heading p {
    color: var(--muted);
}

.feature-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
}

.feature-card,
.panel,
.stat-card,
.calculator-card,
.auth-card,
.form-section,
.profile-card {
    border: 1px solid var(--border);
    background: rgba(255,255,255,.025);
    border-radius: 16px;
}

.feature-card {
    padding: 28px;
    min-height: 210px;
}

.icon {
    font-size: 27px;
    margin-bottom: 25px;
}

.feature-card h3 {
    margin: 0 0 10px;
}

.feature-card p {
    color: var(--muted);
    line-height: 1.6;
    font-size: 14px;
}

.quote-section {
    max-width: 1100px;
    margin: 50px auto 120px;
    padding: 65px;
    border-top: 1px solid var(--border);
    border-bottom: 1px solid var(--border);
    display: flex;
    justify-content: space-between;
    gap: 60px;
}

.quote-section p {
    max-width: 400px;
    color: var(--muted);
    line-height: 1.8;
    align-self: center;
}

.auth-page,
.form-page,
.calculator-page,
.analysis-page,
.profile-page,
.dashboard {
    max-width: 1200px;
    margin: auto;
    padding: 70px 5%;
}

.auth-page {
    min-height: calc(100vh - 150px);
    display: grid;
    place-items: center;
}

.auth-card {
    width: min(470px, 100%);
    padding: 42px;
    box-shadow: var(--shadow);
}

.auth-card h1,
.page-heading h1,
.dashboard-head h1 {
    margin: 0 0 10px;
    font-size: 42px;
    letter-spacing: -1.5px;
}

.auth-card p,
.page-heading p,
.dashboard-head p {
    color: var(--muted);
}

form {
    margin-top: 30px;
}

label {
    display: block;
    color: #bac3cc;
    font-size: 13px;
    margin: 18px 0 8px;
}

input,
select,
textarea {
    width: 100%;
    border: 1px solid var(--border);
    background: #0d1319;
    color: var(--text);
    border-radius: 9px;
    padding: 13px 14px;
    outline: none;
}

input:focus,
select:focus,
textarea:focus {
    border-color: rgba(114,224,165,.5);
}

textarea {
    resize: vertical;
}

.full {
    width: 100%;
    margin-top: 22px;
}

.auth-bottom {
    text-align: center;
    margin-top: 25px;
}

.auth-bottom a,
.panel-head a {
    color: var(--accent);
}

.flash {
    max-width: 900px;
    margin: 20px auto 0;
    padding: 13px 18px;
    border-radius: 9px;
    background: rgba(114,224,165,.08);
    border: 1px solid rgba(114,224,165,.18);
    color: var(--accent);
}

.flash.error {
    color: var(--danger);
    background: rgba(244,125,140,.07);
    border-color: rgba(244,125,140,.18);
}

.dashboard-head {
    display: flex;
    justify-content: space-between;
    align-items: end;
    gap: 30px;
    margin-bottom: 40px;
}

.stat-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 14px;
}

.stat-card {
    padding: 25px;
}

.stat-card span {
    color: var(--muted);
    font-size: 12px;
}

.stat-card strong {
    display: block;
    margin-top: 12px;
    font-size: 30px;
}

.profit {
    color: var(--accent);
}

.loss {
    color: var(--danger);
}

.dashboard-grid {
    display: grid;
    grid-template-columns: 1.7fr .8fr;
    gap: 16px;
    margin-top: 16px;
}

.panel {
    padding: 26px;
}

.large-panel {
    min-width: 0;
}

.panel-head {
    display: flex;
    justify-content: space-between;
    gap: 20px;
    align-items: start;
}

.panel h2 {
    margin: 0 0 7px;
}

.panel-head p {
    color: var(--muted);
    margin: 0 0 25px;
    font-size: 13px;
}

.table-wrap {
    overflow-x: auto;
}

table {
    width: 100%;
    border-collapse: collapse;
    min-width: 650px;
}

th {
    color: var(--muted);
    text-align: left;
    font-size: 11px;
    font-weight: 600;
    padding: 12px;
    border-bottom: 1px solid var(--border);
}

td {
    padding: 15px 12px;
    border-bottom: 1px solid var(--border);
    font-size: 13px;
}

.result {
    padding: 5px 9px;
    border-radius: 20px;
    font-size: 11px;
    background: rgba(255,255,255,.05);
}

.result.win {
    color: var(--accent);
}

.result.loss {
    color: var(--danger);
}

.quick-links {
    display: grid;
    gap: 10px;
    margin-top: 22px;
}

.quick-links a {
    display: grid;
    grid-template-columns: 25px 1fr 20px;
    gap: 10px;
    padding: 15px;
    background: rgba(255,255,255,.025);
    border: 1px solid var(--border);
    border-radius: 9px;
}

.quick-links b {
    color: var(--muted);
}

.empty {
    text-align: center;
    padding: 60px 20px;
    color: var(--muted);
}

.empty div {
    font-size: 35px;
}

.empty h3 {
    color: var(--text);
}

.trade-form {
    max-width: 1000px;
}

.form-section {
    padding: 28px;
    margin-bottom: 18px;
}

.form-section h2 {
    margin-top: 0;
}

.form-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 0 18px;
}

.calculator-card {
    max-width: 850px;
    padding: 35px;
    margin-top: 40px;
}

.calculator-results {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 15px;
    margin-top: 25px;
}

.calculator-results > div {
    padding: 22px;
    background: rgba(114,224,165,.04);
    border: 1px solid var(--border);
    border-radius: 10px;
}

.calculator-results strong {
    display: block;
    font-size: 27px;
    margin-top: 8px;
}

.chart-workspace {
    margin-top: 40px;
    border: 1px solid var(--border);
    border-radius: 15px;
    overflow: hidden;
    background: #0b1015;
}

.chart-toolbar {
    display: flex;
    gap: 8px;
    padding: 12px;
    border-bottom: 1px solid var(--border);
}

.chart-toolbar button {
    background: rgba(255,255,255,.05);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 7px;
    padding: 8px 13px;
    cursor: pointer;
}

.fake-chart {
    height: 520px;
    position: relative;
    overflow: hidden;
    color: var(--accent);
}

.grid-lines {
    position: absolute;
    inset: 0;
    opacity: .6;
    background-image:
        linear-gradient(rgba(255,255,255,.035) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,.035) 1px, transparent 1px);
    background-size: 70px 70px;
}

.fake-chart svg {
    position: absolute;
    width: 100%;
    height: 100%;
}

.analysis-note {
    position: absolute;
    background: rgba(114,224,165,.1);
    border: 1px solid rgba(114,224,165,.3);
    color: var(--accent);
    padding: 8px 12px;
    border-radius: 7px;
    font-size: 12px;
}

.disclaimer {
    margin-top: 20px;
    padding: 18px;
    border: 1px solid var(--border);
    border-radius: 10px;
    color: var(--muted);
    font-size: 12px;
}

.profile-cover {
    height: 190px;
    border-radius: 18px 18px 0 0;
    background:
        radial-gradient(circle at 20% 50%, rgba(114,224,165,.15), transparent 30%),
        linear-gradient(110deg, #111a21, #0c1218);
    border: 1px solid var(--border);
}

.profile-card {
    margin-top: -1px;
    padding: 30px;
    display: flex;
    align-items: center;
    gap: 25px;
    border-radius: 0 0 18px 18px;
}

.avatar {
    width: 90px;
    height: 90px;
    border-radius: 50%;
    display: grid;
    place-items: center;
    background: rgba(114,224,165,.1);
    border: 1px solid rgba(114,224,165,.35);
    color: var(--accent);
    font-size: 35px;
    font-weight: 800;
}

.profile-card h1 {
    margin: 0 0 5px;
}

.profile-card p,
.profile-card small {
    color: var(--muted);
}

footer {
    max-width: 1240px;
    margin: 40px auto 0;
    padding: 35px 5%;
    border-top: 1px solid var(--border);
    display: flex;
    justify-content: space-between;
    gap: 30px;
    color: var(--muted);
    font-size: 13px;
}

footer strong {
    color: var(--text);
}

.center {
    text-align: center;
}

@media (max-width: 900px) {
    nav {
        gap: 10px;
    }

    nav a:not(.nav-button) {
        display: none;
    }

    .hero {
        grid-template-columns: 1fr;
        padding-top: 70px;
    }

    .feature-grid {
        grid-template-columns: repeat(2, 1fr);
    }

    .stat-grid {
        grid-template-columns: repeat(2, 1fr);
    }

    .dashboard-grid {
        grid-template-columns: 1fr;
    }
}

@media (max-width: 600px) {
    .navbar {
        padding: 0 5%;
    }

    .hero {
        min-height: auto;
        padding: 65px 5%;
    }

    .hero h1 {
        font-size: 45px;
    }

    .hero-panel {
        padding: 20px;
    }

    .big-number {
        font-size: 38px;
    }

    .feature-grid,
    .stat-grid,
    .form-grid,
    .calculator-results {
        grid-template-columns: 1fr;
    }

    .quote-section {
        margin: 20px 5% 80px;
        padding: 35px 0;
        display: block;
    }

    .dashboard-head {
        align-items: start;
        flex-direction: column;
    }

    .auth-card {
        padding: 28px 22px;
    }

    .page-heading h1,
    .dashboard-head h1 {
        font-size: 34px;
    }

    .profile-card {
        align-items: flex-start;
        flex-direction: column;
    }

    footer {
        flex-direction: column;
    }
}
CSS


cat > static/js/app.js <<'JS'
function calculateRisk() {
    const balance = parseFloat(document.getElementById("balance").value) || 0;
    const risk = parseFloat(document.getElementById("risk").value) || 0;
    const sl = parseFloat(document.getElementById("slPips").value) || 0;
    const tp = parseFloat(document.getElementById("tpPips").value) || 0;

    const riskAmount = balance * (risk / 100);
    const rr = sl > 0 ? tp / sl : 0;

    document.getElementById("riskAmount").textContent =
        "$" + riskAmount.toFixed(2);

    document.getElementById("rrResult").textContent =
        "1 : " + rr.toFixed(2);
}


function addLine() {
    const chart = document.getElementById("chartArea");
    if (!chart) return;

    const line = document.createElement("div");
    line.style.position = "absolute";
    line.style.left = "0";
    line.style.right = "0";
    line.style.top = Math.floor(Math.random() * 70 + 15) + "%";
    line.style.borderTop = "1px dashed rgba(114,224,165,.55)";
    chart.appendChild(line);
}


function addNote() {
    const area = document.getElementById("analysisNotes");
    if (!area) return;

    const note = document.createElement("div");
    note.className = "analysis-note";
    note.textContent = "Analysis Note";
    note.style.left = Math.floor(Math.random() * 60 + 10) + "%";
    note.style.top = Math.floor(Math.random() * 60 + 15) + "%";

    area.appendChild(note);
}


function clearAnalysis() {
    const chart = document.getElementById("chartArea");
    const notes = document.getElementById("analysisNotes");

    if (!chart || !notes) return;

    notes.innerHTML = "";

    const extras = chart.querySelectorAll(":scope > div:not(.grid-lines):not(#analysisNotes)");
    extras.forEach(item => item.remove());
}
JS

echo ""
echo "=========================================="
echo "       DURJOY FX SETUP COMPLETE"
echo "=========================================="
echo ""
echo "Run the website with:"
echo ""
echo "python3 app.py"
echo ""
