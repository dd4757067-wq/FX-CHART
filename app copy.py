import os
import sqlite3
import secrets
from pathlib import Path
from functools import wraps
from datetime import datetime
from flask import Flask, request, redirect, session, jsonify, render_template_string, flash
from werkzeug.security import generate_password_hash, check_password_hash

BASE = Path.cwd()
DB_DIR = BASE / "database"
DB_DIR.mkdir(exist_ok=True)
DB = DB_DIR / "durjoy_fx.db"

app = Flask("DURJOY_FX")

# --- FIX: persistent secret key ---
# আগের কোডে প্রতিবার সার্ভার রিস্টার্ট/রিডিপ্লয় হলে নতুন random secret key তৈরি হতো,
# ফলে সব ইউজার লগআউট হয়ে যেত। এখন key একবার তৈরি হয়ে ফাইলে সংরক্ষিত থাকে,
# অথবা DURJOY_SECRET_KEY environment variable থেকে নেওয়া যায় (Render এ সেট করা ভালো)।
SECRET_FILE = DB_DIR / "secret.key"
if os.environ.get("DURJOY_SECRET_KEY"):
    app.secret_key = os.environ["DURJOY_SECRET_KEY"]
elif SECRET_FILE.exists():
    app.secret_key = SECRET_FILE.read_text().strip()
else:
    key = secrets.token_hex(32)
    SECRET_FILE.write_text(key)
    app.secret_key = key

# ============================================================
# DATABASE
# ============================================================

def db():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    return con

def add_column(con, table, column, definition):
    cols = [r["name"] for r in con.execute(f"PRAGMA table_info({table})")]
    if column not in cols:
        con.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")

def init_db():
    con = db()

    con.execute("""
    CREATE TABLE IF NOT EXISTS users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        role TEXT DEFAULT 'member',
        bio TEXT DEFAULT '',
        experience TEXT DEFAULT '',
        avatar TEXT DEFAULT '',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS trades(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        pair TEXT,
        direction TEXT,
        timeframe TEXT,
        entry REAL,
        sl REAL,
        tp REAL,
        lot REAL,
        risk_percent REAL,
        risk_amount REAL,
        result TEXT,
        pnl REAL DEFAULT 0,
        strategy TEXT,
        session TEXT,
        emotion TEXT,
        mistake TEXT,
        lesson TEXT DEFAULT '',
        notes TEXT,
        screenshot TEXT DEFAULT '',
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id)
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS posts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        title TEXT,
        content TEXT,
        symbol TEXT,
        analysis TEXT,
        image TEXT DEFAULT '',
        likes INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id)
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS comments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER,
        user_id INTEGER,
        comment TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS likes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER,
        user_id INTEGER,
        UNIQUE(post_id,user_id)
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS follows(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        follower_id INTEGER,
        following_id INTEGER,
        UNIQUE(follower_id,following_id)
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS watchlist(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        symbol TEXT,
        UNIQUE(user_id,symbol)
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS alerts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        symbol TEXT,
        target REAL,
        direction TEXT,
        active INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS saved_analysis(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        symbol TEXT,
        timeframe TEXT,
        data TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS lessons(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id)
    )
    """)

    con.execute("""
    CREATE TABLE IF NOT EXISTS broker_connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        broker TEXT,
        label TEXT,
        account TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """)

    # Migration for older DURJOY FX databases
    for c, d in [
        ("bio", "TEXT DEFAULT ''"),
        ("experience", "TEXT DEFAULT ''"),
        ("avatar", "TEXT DEFAULT ''"),
        ("role", "TEXT DEFAULT 'member'")
    ]:
        add_column(con, "users", c, d)

    trade_cols = [
        ("timeframe", "TEXT"),
        ("risk_percent", "REAL"),
        ("risk_amount", "REAL"),
        ("strategy", "TEXT"),
        ("session", "TEXT"),
        ("emotion", "TEXT"),
        ("mistake", "TEXT"),
        ("lesson", "TEXT DEFAULT ''"),
        ("screenshot", "TEXT DEFAULT ''")
    ]

    for c, d in trade_cols:
        add_column(con, "trades", c, d)

    con.commit()
    con.close()

init_db()

# ============================================================
# AUTH
# ============================================================

def current_user():
    if "user_id" not in session:
        return None
    con = db()
    user = con.execute(
        "SELECT * FROM users WHERE id=?",
        (session["user_id"],)
    ).fetchone()
    con.close()
    return user

def login_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not current_user():
            return redirect("/login")
        return fn(*args, **kwargs)
    return wrapper

# ============================================================
# MAIN UI
# ============================================================

PAGE = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{ title }} | DURJOY FX</title>

<script src="https://unpkg.com/lightweight-charts/dist/lightweight-charts.standalone.production.standalone.js"></script>

<style>
:root{
 --bg:#101722;
 --panel:#172231;
 --panel2:#1d2a3b;
 --border:#2b3b50;
 --text:#edf4ff;
 --muted:#91a0b5;
 --green:#31d07c;
 --red:#ff647c;
 --blue:#5da9ff;
 --yellow:#f5c451;
}
*{box-sizing:border-box}
body{
 margin:0;
 background:linear-gradient(135deg,#0e1621,#131f2d);
 color:var(--text);
 font-family:Inter,Arial,sans-serif;
}
a{text-decoration:none;color:inherit}
nav{
 position:sticky;top:0;z-index:20;
 background:rgba(14,22,33,.95);
 border-bottom:1px solid var(--border);
 padding:14px 4%;
 display:flex;align-items:center;gap:20px;
 backdrop-filter:blur(12px);
}
.logo{font-size:21px;font-weight:900;color:var(--green)}
.navlinks{display:flex;gap:8px;flex-wrap:wrap}
.navlinks a{
 padding:8px 11px;border-radius:8px;color:#c7d2e3;font-size:14px
}
.navlinks a:hover{background:var(--panel2);color:white}
.container{width:min(1400px,94%);margin:25px auto}
.hero{
 padding:35px;border:1px solid var(--border);border-radius:20px;
 background:linear-gradient(135deg,#182637,#12202e);
}
h1,h2,h3{margin-top:0}
.muted{color:var(--muted)}
.grid{
 display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:16px
}
.card{
 background:rgba(23,34,49,.92);
 border:1px solid var(--border);
 border-radius:16px;padding:20px;
 box-shadow:0 10px 30px rgba(0,0,0,.16);
}
.stat{font-size:28px;font-weight:800;margin-top:8px}
.green{color:var(--green)}
.red{color:var(--red)}
.blue{color:var(--blue)}
.yellow{color:var(--yellow)}
button,.btn{
 border:0;border-radius:9px;padding:11px 15px;
 background:var(--green);color:#06120b;font-weight:800;cursor:pointer;
 display:inline-block;
}
button:hover,.btn:hover{filter:brightness(1.08)}
.btn2{background:var(--panel2);color:white;border:1px solid var(--border)}
input,select,textarea{
 width:100%;background:#101a27;color:white;
 border:1px solid var(--border);border-radius:9px;
 padding:11px;margin:6px 0 13px;
}
textarea{min-height:110px;resize:vertical}
label{font-size:13px;color:#aebbd0}
form{max-width:650px}
table{width:100%;border-collapse:collapse}
th,td{padding:11px;border-bottom:1px solid var(--border);text-align:left}
.small{font-size:13px}
.tag{
 display:inline-block;padding:5px 8px;border-radius:20px;
 background:#233247;color:#b9c8dd;font-size:12px;margin:3px
}
#chart{
 width:100%;height:600px;border:1px solid var(--border);
 border-radius:14px;overflow:hidden;background:#101722
}
.toolbar{
 display:flex;gap:8px;flex-wrap:wrap;margin-bottom:12px
}
.toolbar button{background:var(--panel2);color:white;border:1px solid var(--border)}
.chat{
 position:fixed;right:18px;bottom:18px;z-index:100
}
.chatbtn{
 width:58px;height:58px;border-radius:50%;
 font-size:24px;box-shadow:0 10px 30px #0008
}
.chatbox{
 display:none;width:min(370px,calc(100vw - 30px));
 height:500px;background:#142131;border:1px solid var(--border);
 border-radius:16px;overflow:hidden;box-shadow:0 20px 60px #000b
}
.chathead{padding:15px;background:#1d2d40;font-weight:800}
.messages{height:385px;padding:12px;overflow:auto}
.msg{padding:9px 11px;margin:7px 0;border-radius:10px;max-width:88%;font-size:13px}
.bot{background:#223348}
.me{background:#225e43;margin-left:auto}
.chatinput{display:flex;padding:10px;gap:7px}
.chatinput input{margin:0}
.post{margin-bottom:16px}
.posthead{display:flex;justify-content:space-between;gap:10px}
.chart-mini{height:180px}
footer{text-align:center;padding:35px;color:#718096}
@media(max-width:700px){
 nav{align-items:flex-start;flex-direction:column}
 .navlinks{width:100%}
 #chart{height:470px}
 .container{width:96%}
}
</style>
</head>

<body>

<nav>
<a class="logo" href="/">DURJOY FX</a>
<div class="navlinks">
<a href="/">Home</a>
{% if user %}
<a href="/dashboard">Dashboard</a>
<a href="/chart">Live Chart</a>
<a href="/journal">Journal</a>
<a href="/calculator">Calculator</a>
<a href="/risk-management">Risk</a>
<a href="/analytics">Analytics</a>
<a href="/learning">Learning</a>
<a href="/community">Community</a>
<a href="/calendar">Calendar</a>
<a href="/news">News</a>
<a href="/brokers">Brokers</a>
<a href="/profile">Profile</a>
<a href="/logout">Logout</a>
{% else %}
<a href="/login">Login</a>
<a href="/register">Register</a>
{% endif %}
</div>
</nav>

<div class="container">

{% with messages=get_flashed_messages() %}
{% for m in messages %}
<div class="card" style="margin-bottom:15px">{{m}}</div>
{% endfor %}
{% endwith %}

{{ body|safe }}

</div>

<div class="chat">
<div id="chatbox" class="chatbox">
<div class="chathead">🤖 DURJOY FX Help Assistant</div>
<div id="messages" class="messages">
<div class="msg bot">👋 Hello! Website ব্যবহার করতে কোনো সমস্যা হলে আমাকে জিজ্ঞেস করুন।</div>
</div>
<div class="chatinput">
<input id="chatinput" placeholder="আপনার প্রশ্ন লিখুন...">
<button onclick="sendChat()">Send</button>
</div>
</div>
<button class="chatbtn" onclick="toggleChat()">💬</button>
</div>

<footer>
DURJOY FX • Trading Journal • Charts • SMC • Analytics • Community
</footer>

<script>
function toggleChat(){
 let x=document.getElementById("chatbox");
 x.style.display=x.style.display==="block"?"none":"block";
}

async function sendChat(){
 let input=document.getElementById("chatinput");
 let text=input.value.trim();
 if(!text)return;

 let box=document.getElementById("messages");
 box.innerHTML += '<div class="msg me">'+escapeHtml(text)+'</div>';
 input.value="";

 let r=await fetch("/api/help",{
   method:"POST",
   headers:{"Content-Type":"application/json"},
   body:JSON.stringify({question:text})
 });
 let d=await r.json();

 box.innerHTML += '<div class="msg bot">'+escapeHtml(d.answer)+'</div>';
 box.scrollTop=box.scrollHeight;
}

function escapeHtml(s){
 return s.replace(/[&<>"']/g,m=>({
 "&":"&amp;","<":"&lt;",">":"&gt;",
 '"':"&quot;","'":"&#039;"
 })[m]);
}

document.getElementById("chatinput")?.addEventListener("keydown",e=>{
 if(e.key==="Enter")sendChat();
});
</script>

</body>
</html>
"""

def page(title, body):
    return render_template_string(
        PAGE,
        title=title,
        body=body,
        user=current_user()
    )

# ============================================================
# HOME
# ============================================================

@app.route("/")
def home():
    body = """
    <div class="hero">
      <span class="tag">WORLDWIDE TRADING PLATFORM</span>
      <h1>DURJOY FX</h1>
      <p class="muted">
      Trading chart, indicators, SMC analysis, journal, analytics,
      community, news, broker connections and trading tools — এক জায়গায়।
      </p>
      <div style="display:flex;gap:10px;flex-wrap:wrap">
        <a class="btn" href="/chart">Open Live Chart</a>
        <a class="btn btn2" href="/community">Explore Community</a>
        <a class="btn btn2" href="/calculator">Trading Calculators</a>
      </div>
    </div>

    <br>

    <div class="grid">
      <div class="card"><h3>📊 Live Market</h3><p class="muted">Interactive chart and market workspace.</p></div>
      <div class="card"><h3>🧠 SMC</h3><p class="muted">Liquidity, FVG, OB, BOS, CHOCH, MSS and analysis tools.</p></div>
      <div class="card"><h3>📒 Journal</h3><p class="muted">Track every trade and improve your performance.</p></div>
      <div class="card"><h3>👥 Community</h3><p class="muted">Share analysis, like, comment and follow traders.</p></div>
      <div class="card"><h3>📰 News</h3><p class="muted">Market-news architecture ready for external providers.</p></div>
      <div class="card"><h3>🤖 Help Bot</h3><p class="muted">Website-use problems can be asked in the support chat.</p></div>
    </div>
    """
    return page("Home", body)

# ============================================================
# AUTH
# ============================================================

@app.route("/register", methods=["GET","POST"])
def register():
    if request.method=="POST":
        username=request.form.get("username","").strip()
        email=request.form.get("email","").strip().lower()
        password=request.form.get("password","")

        if not username or not email or not password:
            flash("সব তথ্য পূরণ করুন।")
            return redirect("/register")

        con=db()
        # প্রথম ইউজার স্বয়ংক্রিয়ভাবে "owner" হবে (Publish/Learning পেজে full access)
        existing_count = con.execute("SELECT COUNT(*) c FROM users").fetchone()["c"]
        role = "owner" if existing_count == 0 else "member"
        try:
            con.execute(
                "INSERT INTO users(username,email,password,role) VALUES(?,?,?,?)",
                (username,email,generate_password_hash(password),role)
            )
            con.commit()
        except sqlite3.IntegrityError:
            con.close()
            flash("Username অথবা email আগে থেকেই আছে।")
            return redirect("/register")

        user=con.execute(
            "SELECT id FROM users WHERE username=?",(username,)
        ).fetchone()
        con.close()

        session["user_id"]=user["id"]
        return redirect("/dashboard")

    body="""
    <div class="card">
    <h2>Create your DURJOY FX account</h2>
    <form method="post">
      <label>Username</label><input name="username" required>
      <label>Email</label><input type="email" name="email" required>
      <label>Password</label><input type="password" name="password" required>
      <button>Create Account</button>
    </form>
    </div>
    """
    return page("Register",body)

@app.route("/login", methods=["GET","POST"])
def login():
    if request.method=="POST":
        email=request.form.get("email","").strip().lower()
        password=request.form.get("password","")

        con=db()
        user=con.execute(
            "SELECT * FROM users WHERE email=?",
            (email,)
        ).fetchone()

        ok = False
        if user:
            stored = user["password"]
            if stored.startswith(("pbkdf2:", "scrypt:")):
                ok = check_password_hash(stored, password)
            else:
                # পুরনো plain-text পাসওয়ার্ড (migration আগে তৈরি অ্যাকাউন্ট) —
                # মিলে গেলে এখনই hash করে আপডেট করে দাও, যাতে পরের বার থেকে নিরাপদ থাকে
                ok = (stored == password)
                if ok:
                    con.execute(
                        "UPDATE users SET password=? WHERE id=?",
                        (generate_password_hash(password), user["id"])
                    )
                    con.commit()
        con.close()

        if ok:
            session["user_id"]=user["id"]
            return redirect("/dashboard")

        flash("Email অথবা password ভুল।")

    body="""
    <div class="card">
    <h2>Login</h2>
    <form method="post">
      <label>Email</label><input type="email" name="email" required>
      <label>Password</label><input type="password" name="password" required>
      <button>Login</button>
    </form>
    </div>
    """
    return page("Login",body)

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/")

# ============================================================
# DASHBOARD
# ============================================================

@app.route("/dashboard")
@login_required
def dashboard():
    user=current_user()
    con=db()

    rows=con.execute(
        "SELECT * FROM trades WHERE user_id=? ORDER BY id DESC",
        (user["id"],)
    ).fetchall()

    total=len(rows)
    wins=sum(1 for x in rows if x["result"]=="WIN")
    losses=sum(1 for x in rows if x["result"]=="LOSS")
    pnl=sum((x["pnl"] or 0) for x in rows)
    winrate=(wins/total*100) if total else 0

    con.close()

    body=f"""
    <div class="hero">
      <span class="tag">TRADER DASHBOARD</span>
      <h1>Welcome, {user["username"]}</h1>
      <p class="muted">Your trading performance at a glance.</p>
    </div>
    <br>

    <div class="grid">
      <div class="card"><div class="muted">Total Trades</div><div class="stat">{total}</div></div>
      <div class="card"><div class="muted">Wins</div><div class="stat green">{wins}</div></div>
      <div class="card"><div class="muted">Losses</div><div class="stat red">{losses}</div></div>
      <div class="card"><div class="muted">Win Rate</div><div class="stat">{winrate:.1f}%</div></div>
      <div class="card"><div class="muted">Total P/L</div><div class="stat {'green' if pnl>=0 else 'red'}">{pnl:.2f}</div></div>
    </div>

    <br>
    <div class="grid">
      <a class="card" href="/chart"><h3>📊 Advanced Chart</h3><p class="muted">Chart + indicators + SMC workspace.</p></a>
      <a class="card" href="/journal"><h3>📒 Trading Journal</h3><p class="muted">Record and review trades.</p></a>
      <a class="card" href="/analytics"><h3>📈 Analytics</h3><p class="muted">Performance statistics.</p></a>
      <a class="card" href="/community"><h3>👥 Community</h3><p class="muted">Share your analysis.</p></a>
    </div>
    """
    return page("Dashboard",body)

# ============================================================
# ADVANCED CHART
# ============================================================

@app.route("/chart")
@login_required
def chart():
    body="""
    <div class="card">
      <h2>📊 DURJOY FX Advanced Chart</h2>

      <div class="toolbar">
        <select id="symbol" style="width:170px;margin:0">
          <option>BTCUSDT</option>
          <option>ETHUSDT</option>
          <option>BNBUSDT</option>
          <option>XRPUSDT</option>
          <option>EURUSD</option>
          <option>GBPUSD</option>
          <option>USDJPY</option>
          <option>XAUUSD</option>
          <option>NAS100</option>
          <option>US30</option>
        </select>

        <select id="tf" style="width:120px;margin:0">
          <option value="1m">1m</option>
          <option value="5m">5m</option>
          <option value="15m">15m</option>
          <option value="1h" selected>1h</option>
          <option value="4h">4h</option>
          <option value="1d">1D</option>
        </select>

        <button onclick="loadChart()">Load</button>
        <button onclick="addEMA()">EMA</button>
        <button onclick="addSMA()">SMA</button>
        <button onclick="addRSI()">RSI</button>
        <button onclick="drawLine()">Horizontal Line</button>
        <button onclick="markFVG()">FVG Zone</button>
        <button onclick="markOB()">Order Block</button>
        <button onclick="saveAnalysis()">💾 Save Analysis</button>
      </div>

      <div id="status" class="muted small" style="margin-bottom:8px">
      Loading market data...
      </div>

      <div id="chart"></div>

      <br>

      <div class="grid">
        <div class="card">
          <h3>💧 Liquidity</h3>
          <button onclick="tool('Liquidity Sweep')">Mark Sweep</button>
          <button onclick="tool('Buy Side Liquidity')">Buy-side</button>
          <button onclick="tool('Sell Side Liquidity')">Sell-side</button>
        </div>

        <div class="card">
          <h3>🧠 Market Structure</h3>
          <button onclick="tool('BOS')">BOS</button>
          <button onclick="tool('CHOCH')">CHOCH</button>
          <button onclick="tool('MSS')">MSS</button>
        </div>

        <div class="card">
          <h3>📐 Drawing Tools</h3>
          <button onclick="tool('Fibonacci')">Fibonacci</button>
          <button onclick="tool('Support')">Support</button>
          <button onclick="tool('Resistance')">Resistance</button>
        </div>

        <div class="card">
          <h3>🎯 Trade Planning</h3>
          <button onclick="tool('Entry')">Entry</button>
          <button onclick="tool('Stop Loss')">SL</button>
          <button onclick="tool('Take Profit')">TP</button>
        </div>
      </div>
    </div>

<script>
let chart;
let candleSeries;
let candles=[];
let currentSymbol="BTCUSDT";

function createChart(){
 const el=document.getElementById("chart");
 el.innerHTML="";

 chart=LightweightCharts.createChart(el,{
   width:el.clientWidth,
   height:600,
   layout:{
     background:{color:"#101722"},
     textColor:"#aebbd0"
   },
   grid:{
     vertLines:{color:"#1d2a3a"},
     horzLines:{color:"#1d2a3a"}
   },
   crosshair:{mode:LightweightCharts.CrosshairMode.Normal},
   timeScale:{timeVisible:true,secondsVisible:false}
 });

 candleSeries=chart.addSeries(
   LightweightCharts.CandlestickSeries,
   {
     upColor:"#31d07c",
     downColor:"#ff647c",
     borderVisible:false,
     wickUpColor:"#31d07c",
     wickDownColor:"#ff647c"
   }
 );

 window.addEventListener("resize",()=>{
   chart.applyOptions({width:el.clientWidth});
 });
}

async function loadChart(){
 currentSymbol=document.getElementById("symbol").value;
 let tf=document.getElementById("tf").value;

 document.getElementById("status").innerText=
   "Loading "+currentSymbol+" "+tf+" ...";

 createChart();

 // Binance public market data for crypto symbols.
 if(currentSymbol.endsWith("USDT")){
   try{
     let interval=tf==="1D"?"1d":tf;
     let url="https://api.binance.com/api/v3/klines?symbol="+
       currentSymbol+"&interval="+interval+"&limit=500";

     let r=await fetch(url);
     if(!r.ok)throw new Error("Market API unavailable");

     let data=await r.json();

     candles=data.map(x=>({
       time:Math.floor(x[0]/1000),
       open:parseFloat(x[1]),
       high:parseFloat(x[2]),
       low:parseFloat(x[3]),
       close:parseFloat(x[4])
     }));

     candleSeries.setData(candles);

     document.getElementById("status").innerText=
       "LIVE DATA • "+currentSymbol+" • Binance public market feed";

     // Live websocket
     let stream=currentSymbol.toLowerCase()+"@kline_"+interval;
     let ws=new WebSocket("wss://stream.binance.com:9443/ws/"+stream);

     ws.onmessage=e=>{
       let d=JSON.parse(e.data);
       let k=d.k;

       candleSeries.update({
         time:Math.floor(k.t/1000),
         open:parseFloat(k.o),
         high:parseFloat(k.h),
         low:parseFloat(k.l),
         close:parseFloat(k.c)
       });
     };

   }catch(err){
     document.getElementById("status").innerText=
       "Live data could not be loaded: "+err.message;
   }
 }else{
   // Forex/CFD symbols need a licensed external market-data provider.
   let fake=[];
   let base=100;
   let now=Math.floor(Date.now()/1000)-500*3600;

   for(let i=0;i<500;i++){
     let o=base;
     let c=o+(Math.random()-.48);
     let h=Math.max(o,c)+Math.random();
     let l=Math.min(o,c)-Math.random();
     fake.push({time:now+i*3600,open:o,high:h,low:l,close:c});
     base=c;
   }

   candleSeries.setData(fake);

   document.getElementById("status").innerText=
     currentSymbol+
     " requires an external licensed FX/CFD data provider. Configure provider API on the server.";
 }
}

function addEMA(){
 if(!candles.length)return;
 let period=20;
 let vals=[];
 let sum=0;
 let k=2/(period+1);

 candles.forEach((c,i)=>{
   sum+=c.close;
   if(i===period-1){
     let ema=sum/period;
     vals.push({time:c.time,value:ema});
   }else if(i>=period){
     let prev=vals[vals.length-1].value;
     let ema=(c.close-prev)*k+prev;
     vals.push({time:c.time,value:ema});
   }
 });

 let s=chart.addSeries(LightweightCharts.LineSeries,{
   lineWidth:2
 });
 s.setData(vals);
}

function addSMA(){
 if(!candles.length)return;
 let period=50;
 let vals=[];

 for(let i=period-1;i<candles.length;i++){
   let sum=0;
   for(let j=i-period+1;j<=i;j++)sum+=candles[j].close;
   vals.push({
     time:candles[i].time,
     value:sum/period
   });
 }

 let s=chart.addSeries(LightweightCharts.LineSeries,{lineWidth:2});
 s.setData(vals);
}

function addRSI(){
 alert("RSI workspace ready. RSI can be expanded into a separate indicator pane in the next provider/chart-engine layer.");
}

function drawLine(){
 let price=candles.length?candles[candles.length-1].close:100;
 let line=candleSeries.createPriceLine({
   price:price,
   color:"#f5c451",
   lineWidth:2,
   lineStyle:LightweightCharts.LineStyle.Dashed,
   axisLabelVisible:true,
   title:"Level"
 });
}

function markFVG(){
 alert("FVG tool selected — mark the imbalance area on your analysis.");
}

function markOB(){
 alert("Order Block tool selected — mark the institutional zone on your analysis.");
}

function tool(name){
 document.getElementById("status").innerText=
   "Analysis tool active: "+name;
}

async function saveAnalysis(){
 let payload={
   symbol:currentSymbol,
   timeframe:document.getElementById("tf").value,
   data:JSON.stringify(candles.slice(-100))
 };

 let r=await fetch("/api/save-analysis",{
   method:"POST",
   headers:{"Content-Type":"application/json"},
   body:JSON.stringify(payload)
 });

 let d=await r.json();
 alert(d.message);
}

loadChart();
</script>
    """
    return page("Advanced Chart",body)

# ============================================================
# JOURNAL
# ============================================================

@app.route("/journal",methods=["GET","POST"])
@login_required
def journal():
    user=current_user()

    if request.method=="POST":
        f=request.form
        con=db()
        con.execute("""
        INSERT INTO trades(
          user_id,pair,direction,timeframe,entry,sl,tp,lot,
          risk_percent,risk_amount,result,pnl,strategy,session,
          emotion,mistake,lesson,notes
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """,(
          user["id"],f.get("pair"),f.get("direction"),
          f.get("timeframe"),float(f.get("entry") or 0),
          float(f.get("sl") or 0),float(f.get("tp") or 0),
          float(f.get("lot") or 0),float(f.get("risk_percent") or 0),
          float(f.get("risk_amount") or 0),f.get("result"),
          float(f.get("pnl") or 0),f.get("strategy"),
          f.get("session"),f.get("emotion"),f.get("mistake"),
          f.get("lesson"),f.get("notes")
        ))
        con.commit()
        con.close()
        return redirect("/journal")

    con=db()
    trades=con.execute(
      "SELECT * FROM trades WHERE user_id=? ORDER BY id DESC",
      (user["id"],)
    ).fetchall()
    con.close()

    rows="".join(
      f"""
      <tr>
       <td>{x["pair"]}</td>
       <td>{x["direction"]}</td>
       <td>{x["result"] or "-"}</td>
       <td class="{'green' if (x['pnl'] or 0)>=0 else 'red'}">{x["pnl"] or 0:.2f}</td>
       <td>{x["strategy"] or "-"}</td>
       <td>{x["created_at"]}</td>
      </tr>
      """ for x in trades
    )

    body=f"""
    <div class="card">
    <h2>📒 Advanced Trading Journal</h2>
    <form method="post">
      <div class="grid">
       <div><label>Pair</label><input name="pair" placeholder="EURUSD / XAUUSD"></div>
       <div><label>Direction</label>
       <select name="direction"><option>BUY</option><option>SELL</option></select></div>
       <div><label>Timeframe</label><input name="timeframe" placeholder="15M"></div>
       <div><label>Entry</label><input type="number" step="any" name="entry"></div>
       <div><label>Stop Loss</label><input type="number" step="any" name="sl"></div>
       <div><label>Take Profit</label><input type="number" step="any" name="tp"></div>
       <div><label>Lot Size</label><input type="number" step="any" name="lot"></div>
       <div><label>Risk %</label><input type="number" step="any" name="risk_percent"></div>
       <div><label>Risk Amount</label><input type="number" step="any" name="risk_amount"></div>
       <div><label>Result</label>
       <select name="result"><option>WIN</option><option>LOSS</option><option>BREAKEVEN</option></select></div>
       <div><label>P/L</label><input type="number" step="any" name="pnl"></div>
       <div><label>Strategy</label><input name="strategy" placeholder="SMC / Breakout"></div>
       <div><label>Session</label><input name="session" placeholder="London / NY"></div>
       <div><label>Emotion</label><input name="emotion"></div>
       <div><label>Mistake</label><input name="mistake"></div>
      </div>
      <label>Lesson</label><textarea name="lesson"></textarea>
      <label>Notes</label><textarea name="notes"></textarea>
      <button>Save Trade</button>
    </form>
    </div>

    <br>
    <div class="card">
    <h3>Recent Trades</h3>
    <div style="overflow:auto">
    <table>
    <tr><th>Pair</th><th>Side</th><th>Result</th><th>P/L</th><th>Strategy</th><th>Date</th></tr>
    {rows}
    </table>
    </div>
    </div>
    """
    return page("Journal",body)

# ============================================================
# CALCULATOR
# ============================================================

@app.route("/calculator")
@login_required
def calculator():
    body="""
    <div class="card">
    <h2>🧮 Professional Trading Calculator</h2>

    <div class="grid">
      <div class="card">
       <h3>Risk Calculator</h3>
       <label>Account Balance</label><input id="bal" type="number" value="1000">
       <label>Risk %</label><input id="risk" type="number" value="1">
       <button onclick="riskCalc()">Calculate</button>
       <h3 id="riskout"></h3>
      </div>

      <div class="card">
       <h3>R:R Calculator</h3>
       <label>Entry</label><input id="entry" type="number" step="any">
       <label>Stop Loss</label><input id="sl" type="number" step="any">
       <label>Take Profit</label><input id="tp" type="number" step="any">
       <button onclick="rrCalc()">Calculate</button>
       <h3 id="rrout"></h3>
      </div>

      <div class="card">
       <h3>Position Size</h3>
       <label>Account</label><input id="pb" type="number" value="1000">
       <label>Risk %</label><input id="pr" type="number" value="1">
       <label>Stop Distance (pips)</label><input id="pd" type="number" value="20">
       <label>Pip Value per 1 lot</label><input id="pv" type="number" value="10">
       <button onclick="posCalc()">Calculate</button>
       <h3 id="pout"></h3>
      </div>

      <div class="card">
       <h3>Compounding</h3>
       <label>Starting Balance</label><input id="cb" type="number" value="100">
       <label>Profit per period %</label><input id="cp" type="number" value="5">
       <label>Periods</label><input id="cn" type="number" value="12">
       <button onclick="compound()">Calculate</button>
       <h3 id="cout"></h3>
      </div>
    </div>
    </div>

<script>
function riskCalc(){
 let a=+bal.value,r=+risk.value;
 riskout.innerText="Risk Amount = "+(a*r/100).toFixed(2);
}
function rrCalc(){
 let e=+entry.value,s=+sl.value,t=+tp.value;
 let risk=Math.abs(e-s);
 let reward=Math.abs(t-e);
 rrout.innerText="Risk : Reward = 1 : "+(reward/risk).toFixed(2);
}
function posCalc(){
 let a=+pb.value,r=+pr.value,d=+pd.value,v=+pv.value;
 let riskAmount=a*r/100;
 let lot=riskAmount/(d*v);
 pout.innerText="Estimated Lot Size = "+lot.toFixed(4);
}
function compound(){
 let b=+cb.value,p=+cp.value/100,n=+cn.value;
 let x=b*Math.pow(1+p,n);
 cout.innerText="Projected Balance = "+x.toFixed(2);
}
</script>
    """
    return page("Calculator",body)

# ============================================================
# ANALYTICS
# ============================================================

@app.route("/analytics")
@login_required
def analytics():
    user=current_user()
    con=db()

    rows=con.execute("""
      SELECT pair,
      COUNT(*) total,
      SUM(CASE WHEN result='WIN' THEN 1 ELSE 0 END) wins,
      SUM(CASE WHEN result='LOSS' THEN 1 ELSE 0 END) losses,
      SUM(COALESCE(pnl,0)) pnl
      FROM trades
      WHERE user_id=?
      GROUP BY pair
      ORDER BY pnl DESC
    """,(user["id"],)).fetchall()

    con.close()

    table="".join(
      f"""
      <tr>
       <td>{r["pair"]}</td>
       <td>{r["total"]}</td>
       <td>{r["wins"]}</td>
       <td>{r["losses"]}</td>
       <td>{r["pnl"]:.2f}</td>
       <td>{(r["wins"]/r["total"]*100):.1f}%</td>
      </tr>
      """ for r in rows
    )

    body=f"""
    <div class="card">
    <h2>📈 Performance Analytics</h2>
    <p class="muted">Pair-by-pair trading performance.</p>
    <div style="overflow:auto">
    <table>
      <tr><th>Pair</th><th>Trades</th><th>Wins</th><th>Losses</th><th>P/L</th><th>Win Rate</th></tr>
      {table}
    </table>
    </div>
    </div>
    """
    return page("Analytics",body)

# ============================================================
# COMMUNITY
# ============================================================

@app.route("/community",methods=["GET","POST"])
@login_required
def community():
    user=current_user()

    if request.method=="POST":
        title=request.form.get("title","")
        content=request.form.get("content","")
        symbol=request.form.get("symbol","")

        con=db()
        con.execute(
          "INSERT INTO posts(user_id,title,content,symbol) VALUES(?,?,?,?)",
          (user["id"],title,content,symbol)
        )
        con.commit()
        con.close()
        return redirect("/community")

    con=db()

    posts=con.execute("""
      SELECT posts.*,users.username
      FROM posts JOIN users ON posts.user_id=users.id
      ORDER BY posts.id DESC
    """).fetchall()

    html=""
    for p in posts:
        comments=con.execute("""
          SELECT comments.*,users.username
          FROM comments JOIN users ON comments.user_id=users.id
          WHERE post_id=? ORDER BY comments.id
        """,(p["id"],)).fetchall()

        chtml="".join(
          f'<div class="small"><b>{c["username"]}</b>: {c["comment"]}</div>'
          for c in comments
        )

        html+=f"""
        <div class="card post">
          <div class="posthead">
            <div>
              <h3>{p["title"] or "Trading Analysis"}</h3>
              <span class="tag">@{p["username"]}</span>
              <span class="tag">{p["symbol"] or "Market"}</span>
            </div>
            <span class="muted small">{p["created_at"]}</span>
          </div>

          <p>{p["content"]}</p>

          <form method="post" action="/like/{p["id"]}" style="display:inline">
            <button class="btn2">❤️ {p["likes"]}</button>
          </form>

          <form method="post" action="/comment/{p["id"]}" style="margin-top:10px;display:flex;gap:7px">
            <input name="comment" placeholder="Write a comment..." style="margin:0">
            <button>Comment</button>
          </form>

          <div style="margin-top:12px">
            {chtml}
          </div>
        </div>
        """

    con.close()

    body=f"""
    <div class="card">
      <h2>👥 DURJOY FX Community</h2>
      <form method="post">
        <label>Post Title</label><input name="title" placeholder="My EURUSD analysis">
        <label>Symbol</label><input name="symbol" placeholder="EURUSD">
        <label>Analysis</label><textarea name="content" placeholder="Share your trading analysis..."></textarea>
        <button>Publish Analysis</button>
      </form>
    </div>

    <br>
    {html or '<div class="card">No analysis posted yet.</div>'}
    """

    return page("Community",body)

@app.route("/like/<int:post_id>",methods=["POST"])
@login_required
def like(post_id):
    user=current_user()
    con=db()

    exists=con.execute(
      "SELECT id FROM likes WHERE post_id=? AND user_id=?",
      (post_id,user["id"])
    ).fetchone()

    if exists:
        con.execute("DELETE FROM likes WHERE id=?",(exists["id"],))
        con.execute(
          "UPDATE posts SET likes=MAX(likes-1,0) WHERE id=?",(post_id,)
        )
    else:
        con.execute(
          "INSERT INTO likes(post_id,user_id) VALUES(?,?)",
          (post_id,user["id"])
        )
        con.execute(
          "UPDATE posts SET likes=likes+1 WHERE id=?",(post_id,)
        )

    con.commit()
    con.close()
    return redirect("/community")

@app.route("/comment/<int:post_id>",methods=["POST"])
@login_required
def comment(post_id):
    user=current_user()
    text=request.form.get("comment","").strip()

    if text:
        con=db()
        con.execute(
          "INSERT INTO comments(post_id,user_id,comment) VALUES(?,?,?)",
          (post_id,user["id"],text)
        )
        con.commit()
        con.close()

    return redirect("/community")

# ============================================================
# PROFILE
# ============================================================

@app.route("/profile",methods=["GET","POST"])
@login_required
def profile():
    user=current_user()

    if request.method=="POST":
        con=db()
        con.execute("""
          UPDATE users SET bio=?,experience=? WHERE id=?
        """,(
          request.form.get("bio",""),
          request.form.get("experience",""),
          user["id"]
        ))
        con.commit()
        con.close()
        return redirect("/profile")

    body=f"""
    <div class="card">
      <h2>👤 @{user["username"]}</h2>
      <p class="muted">{user["email"]}</p>

      <form method="post">
        <label>Bio</label>
        <textarea name="bio">{user["bio"] or ""}</textarea>

        <label>Trading Experience</label>
        <input name="experience" value="{user["experience"] or ""}">

        <button>Save Profile</button>
      </form>
    </div>
    """
    return page("Profile",body)

# ============================================================
# BROKERS
# ============================================================

@app.route("/brokers",methods=["GET","POST"])
@login_required
def brokers():
    user=current_user()

    if request.method=="POST":
        con=db()
        con.execute("""
          INSERT INTO broker_connections(user_id,broker,label,account)
          VALUES(?,?,?,?)
        """,(
          user["id"],
          request.form.get("broker"),
          request.form.get("label"),
          request.form.get("account")
        ))
        con.commit()
        con.close()
        return redirect("/brokers")

    con=db()
    rows=con.execute(
      "SELECT * FROM broker_connections WHERE user_id=? ORDER BY id DESC",
      (user["id"],)
    ).fetchall()
    con.close()

    html="".join(
      f'<div class="card"><b>{r["broker"]}</b><p class="muted">{r["label"] or ""} • {r["account"] or ""}</p></div>'
      for r in rows
    )

    body=f"""
    <div class="card">
      <h2>🏦 Broker & Exchange Connections</h2>
      <p class="muted">
      Binance, MT5, Exness, XM এবং অন্যান্য provider-এর connector
      এখানে management-এর জন্য রাখা হয়েছে।
      </p>

      <form method="post">
        <label>Broker / Exchange</label>
        <select name="broker">
          <option>Binance</option>
          <option>MetaTrader 5</option>
          <option>Exness</option>
          <option>XM</option>
          <option>Other</option>
        </select>

        <label>Connection Label</label>
        <input name="label" placeholder="My main account">

        <label>Account ID / Reference</label>
        <input name="account">

        <button>Add Connection</button>
      </form>
    </div>

    <br>
    <h3>Your Connections</h3>
    {html or '<div class="card">No broker connections yet.</div>'}
    """
    return page("Brokers",body)

# ============================================================
# NEWS
# ============================================================

@app.route("/news")
def news():
    body="""
    <div class="hero">
      <span class="tag">MARKET INFORMATION</span>
      <h1>📰 Trading News & Economic Calendar</h1>
      <p class="muted">
      Forex, crypto, indices এবং macro-economic news-এর জন্য
      provider connector architecture প্রস্তুত।
      </p>
    </div>

    <br>

    <div class="grid">
      <div class="card">
        <h3>🔥 High Impact</h3>
        <p class="muted">NFP • CPI • FOMC • Interest Rate • GDP • Employment</p>
      </div>
      <div class="card">
        <h3>💱 Forex</h3>
        <p class="muted">Currency-market news provider integration.</p>
      </div>
      <div class="card">
        <h3>₿ Crypto</h3>
        <p class="muted">Crypto market news and exchange data.</p>
      </div>
      <div class="card">
        <h3>📅 Economic Calendar</h3>
        <p class="muted">Calendar API connector can be configured server-side.</p>
      </div>
    </div>
    """
    return page("News",body)

# ============================================================
# CALENDAR  (আগে nav-এ লিংক ছিল কিন্তু route ছিল না — এখন যোগ করা হলো)
# ============================================================

@app.route("/calendar")
def calendar():
    body = """
    <div class="hero">
      <span class="tag">ECONOMIC CALENDAR</span>
      <h1>Events that can move markets.</h1>
      <p class="muted">Filter scheduled events by importance and affected economies.</p>
    </div>
    <br>
    <div class="card">
      <div class="tradingview-widget-container">
        <div class="tradingview-widget-container__widget"></div>
        <script type="text/javascript"
          src="https://s3.tradingview.com/external-embedding/embed-widget-events.js" async>
        {
          "colorTheme": "dark",
          "isTransparent": false,
          "locale": "en",
          "countryFilter": "au,ca,cn,fr,de,in,it,jp,kr,gb,us,eu",
          "importanceFilter": "-1,0,1",
          "width": "100%",
          "height": 620
        }
        </script>
      </div>
    </div>
    """
    return page("Economic Calendar", body)

# ============================================================
# RISK MANAGEMENT  (আগে nav-এ লিংক ছিল কিন্তু route ছিল না — এখন যোগ করা হলো)
# ============================================================

@app.route("/risk-management")
def risk_management():
    body = """
    <div class="hero">
      <span class="tag">RISK MANAGEMENT SYSTEM</span>
      <h1>Protect capital before chasing profit.</h1>
      <p class="muted">Position sizing, stop loss, drawdown এবং trading discipline-এর practical checklist।</p>
    </div>
    <br>
    <div class="grid">
      <div class="card"><b>01</b><h3>Define risk first</h3>
        <p class="muted">Position size হিসাব করার আগে প্রতি ট্রেডে সর্বোচ্চ risk ঠিক করুন। আগের লস পুষিয়ে নিতে risk বাড়াবেন না।</p></div>
      <div class="card"><b>02</b><h3>Set invalidation</h3>
        <p class="muted">Stop সেট করুন যেখানে trade idea invalid হয়ে যায় — শুধু "comfortable" মনে হওয়া জায়গায় না।</p></div>
      <div class="card"><b>03</b><h3>Respect drawdown</h3>
        <p class="muted">Daily/weekly loss limit ব্যবহার করুন। limit ছুঁলে থামুন এবং review করুন।</p></div>
      <div class="card"><b>04</b><h3>Control leverage</h3>
        <p class="muted">Leverage exposure বাড়ায়, edge তৈরি করে না। Risk আর stop distance থেকে position size ঠিক করুন।</p></div>
    </div>
    <br>
    <div class="card">
      <h3>Quick Risk Calculator</h3>
      <label>Account Balance</label>
      <input id="rmBalance" type="number" value="1000">
      <label>Risk % per trade</label>
      <input id="rmRisk" type="number" value="1" step="0.1">
      <button onclick="calcRM()">Calculate</button>
      <p id="rmResult" class="stat green" style="margin-top:12px">—</p>
    </div>

    <script>
    function calcRM(){
      let bal = parseFloat(document.getElementById("rmBalance").value) || 0;
      let pct = parseFloat(document.getElementById("rmRisk").value) || 0;
      let amount = (bal * pct / 100).toFixed(2);
      document.getElementById("rmResult").innerText = "ঝুঁকির পরিমাণ: " + amount;
    }
    </script>
    """
    return page("Risk Management", body)

# ============================================================
# LEARNING CENTER  (nav/README-এ ছিল কিন্তু route ছিল না — এখন যোগ করা হলো)
# ============================================================

@app.route("/learning")
def learning():
    con = db()
    lessons = con.execute(
        "SELECT lessons.*, users.username FROM lessons "
        "JOIN users ON users.id = lessons.user_id "
        "ORDER BY lessons.id DESC LIMIT 20"
    ).fetchall()
    con.close()

    lesson_html = "".join(f"""
      <div class="card post">
        <div class="posthead"><b>{l['title']}</b><span class="small muted">by {l['username']}</span></div>
        <p>{l['body']}</p>
      </div>
    """ for l in lessons) or '<p class="muted">এখনো কোনো lesson publish হয়নি।</p>'

    body = f"""
    <div class="hero">
      <span class="tag">LEARNING CENTER</span>
      <h1>Beginner থেকে Advanced — সব curriculum এক জায়গায়।</h1>
    </div>
    <br>
    <div class="grid">
      <div class="card"><h3>🕯️ Candlestick Curriculum</h3><p class="muted">Basic থেকে advanced candlestick pattern।</p></div>
      <div class="card"><h3>📊 Technical Analysis</h3><p class="muted">Indicator, trend, support/resistance।</p></div>
      <div class="card"><h3>🧠 SMC / Price Action</h3><p class="muted">Smart Money Concept, order block, liquidity।</p></div>
      <div class="card"><h3>⏱️ Multi-timeframe</h3><p class="muted">HTF bias আর LTF entry combine করা।</p></div>
    </div>
    <br>
    <h2>Published Lessons</h2>
    {lesson_html}
    """
    return page("Learning Center", body)

# ============================================================
# PUBLISH  (শুধু owner/subscriber রোলের ইউজার lesson publish করতে পারবে)
# ============================================================

@app.route("/publish", methods=["GET","POST"])
@login_required
def publish():
    user = current_user()
    if user["role"] not in ("owner","subscriber"):
        flash("শুধুমাত্র subscriber/instructor এবং owner লেসন publish করতে পারবেন।")
        return redirect("/learning")

    if request.method == "POST":
        title = request.form.get("title","").strip()
        body_text = request.form.get("body","").strip()
        if title and body_text:
            con = db()
            con.execute(
                "INSERT INTO lessons(user_id,title,body) VALUES(?,?,?)",
                (user["id"], title, body_text)
            )
            con.commit()
            con.close()
            flash("Lesson publish হয়েছে।")
            return redirect("/learning")
        flash("Title এবং content দুটোই দিতে হবে।")

    body = """
    <div class="card">
      <h1>Publish Learning Post</h1>
      <p class="muted">শুধু subscriber/instructor এবং owner এখানে content publish করতে পারবেন।</p>
      <form method="post">
        <label>Title</label><input name="title" required>
        <label>Lesson / Post</label><textarea name="body" rows="10" required></textarea>
        <button>Publish</button>
      </form>
    </div>
    """
    return page("Publish", body)

# ============================================================
# SUPPORT BOT
# ============================================================

@app.route("/api/help",methods=["POST"])
def help_api():
    data=request.get_json(silent=True) or {}
    q=data.get("question","").lower().strip()

    answers=[
      (["register","account","অ্যাকাউন্ট","খুল","create"],
       "Account খুলতে Register-এ যান, username/email/password দিয়ে Create Account চাপুন।"),
      (["login","লগইন","password","পাসওয়ার্ড"],
       "Login পেজে আপনার registered email ও password দিয়ে Login করুন।"),
      (["journal","trade add","ট্রেড","জার্নাল"],
       "Trading Journal-এ গিয়ে Pair, Direction, Entry, SL, TP, Risk, Result এবং P/L দিয়ে trade save করতে পারবেন।"),
      (["chart","চার্ট","candle","candlestick"],
       "Advanced Chart পেজে গিয়ে symbol ও timeframe নির্বাচন করে Load চাপুন। Crypto USDT pairs-এর জন্য public Binance market feed ব্যবহার করা হচ্ছে।"),
      (["indicator","ema","sma","rsi","ইন্ডিকেটর"],
       "Chart-এর toolbar থেকে EMA/SMA এবং অন্যান্য analysis tools ব্যবহার করতে পারবেন।"),
      (["fvg","fair value"],
       "FVG হলো price imbalance/inefficiency zone। Chart-এর FVG analysis tool দিয়ে এটি mark করার workflow রাখা হয়েছে।"),
      (["order block","ob"],
       "Order Block analysis করতে Advanced Chart-এর Order Block tool ব্যবহার করুন।"),
      (["bos","choch","mss"],
       "BOS, CHOCH ও MSS হলো market-structure analysis concepts। Chart-এর Market Structure tools থেকে এগুলো mark করতে পারবেন।"),
      (["calculator","lot","risk","position","rr","r:r"],
       "Calculator পেজে Risk, R:R, Position Size এবং Compounding calculator আছে।"),
      (["analytics","performance","win rate"],
       "Analytics পেজে pair-wise trades, wins, losses, P/L এবং win rate দেখতে পারবেন।"),
      (["community","post","like","comment"],
       "Community-তে analysis publish করে অন্য traders-এর post like ও comment করতে পারবেন।"),
      (["broker","binance","mt5","exness","xm"],
       "Brokers পেজে broker/exchange connection reference যোগ করতে পারবেন। Secret API keys browser-side-এ রাখা উচিত নয়।"),
      (["news","নিউজ","calendar","economic"],
       "News পেজে market-news ও economic-calendar provider integration-এর জায়গা রাখা হয়েছে।"),
      (["problem","error","সমস্যা","কাজ","হচ্ছে না"],
       "সমস্যাটি কী হচ্ছে সেটি লিখুন—কোন page, কোন button এবং কী error দেখাচ্ছে জানালে troubleshooting করা যাবে।")
    ]

    for keys,ans in answers:
        if any(k in q for k in keys):
            return jsonify(answer=ans)

    return jsonify(answer=
      "আমি DURJOY FX website ব্যবহার করতে সাহায্য করতে পারি। "
      "আপনি কোন page বা feature নিয়ে সমস্যায় পড়েছেন সেটি লিখুন—যেমন Chart, Journal, Calculator, Profile, Community, Broker বা Login।"
    )

# ============================================================
# SAVE ANALYSIS
# ============================================================

@app.route("/api/save-analysis",methods=["POST"])
@login_required
def save_analysis():
    data=request.get_json(silent=True) or {}
    user=current_user()

    con=db()
    con.execute("""
      INSERT INTO saved_analysis(user_id,symbol,timeframe,data)
      VALUES(?,?,?,?)
    """,(
      user["id"],
      data.get("symbol"),
      data.get("timeframe"),
      data.get("data","")
    ))
    con.commit()
    con.close()

    return jsonify(message="Analysis saved successfully.")

# ============================================================
# HEALTH
# ============================================================

@app.route("/health")
def health():
    return jsonify(
      status="ok",
      project="DURJOY FX",
      version="FINAL",
      database=str(DB)
    )

# ============================================================
# ERROR
# ============================================================

@app.errorhandler(404)
def not_found(e):
    # FIX: আগে status code দেওয়া হতো না, তাই 404 পেজেও ব্রাউজার 200 OK দেখাতো
    return page("404","""
    <div class="card">
      <h1>404</h1>
      <p class="muted">এই page পাওয়া যায়নি।</p>
      <a class="btn" href="/">Back Home</a>
    </div>
    """), 404

# ============================================================
# START
# ============================================================

if __name__ == "__main__":
    print("")
    print("======================================")
    print("       DURJOY FX FINAL PLATFORM")
    print("======================================")
    print("Database:", DB)
    print("URL: http://127.0.0.1:5000")
    print("")
    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 5000)),
        debug=os.environ.get("FLASK_DEBUG") == "1"
    )
