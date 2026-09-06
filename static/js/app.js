document.addEventListener('DOMContentLoaded', () => {
  const transition = document.getElementById('pageTransition');
  document.querySelectorAll('a[href]').forEach(a => {
    const href = a.getAttribute('href');
    if (!href || href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('javascript:') || a.target === '_blank') return;
    a.addEventListener('click', e => {
      const u = new URL(a.href, location.href);
      if (u.origin !== location.origin) return;
      if (transition) { e.preventDefault(); transition.classList.add('show'); setTimeout(()=>location.href=a.href, 180); }
    });
  });

  const back = document.getElementById('backBtn');
  if (back) back.addEventListener('click', () => history.back());

  const help = document.getElementById('helpBtn'), panel = document.getElementById('helpPanel'), close = document.getElementById('helpClose');
  if (help && panel) help.addEventListener('click',()=>panel.classList.toggle('open'));
  if (close && panel) close.addEventListener('click',()=>panel.classList.remove('open'));

  const pass = document.getElementById('loginPassword'), toggle = document.getElementById('togglePassword');
  if (pass && toggle) toggle.addEventListener('click',()=>{ pass.type=pass.type==='password'?'text':'password'; toggle.textContent=pass.type==='password'?'Show':'Hide'; });

  document.querySelectorAll('.social-btn').forEach(btn => btn.addEventListener('click', () => {
    const provider = btn.dataset.provider;
    alert(provider === 'google' ? 'Google/Gmail OAuth needs your Google Client ID and Client Secret.' :
      provider === 'facebook' ? 'Facebook OAuth needs your Facebook App ID and App Secret.' :
      'X/Twitter OAuth needs your X developer credentials.');
  }));

  const tabs = document.querySelectorAll('.learn-tab'), panels = document.querySelectorAll('.learn-panel');
  tabs.forEach(t => t.addEventListener('click',()=>{
    tabs.forEach(x=>x.classList.remove('active')); panels.forEach(x=>x.classList.remove('active'));
    t.classList.add('active'); const p=document.getElementById(t.dataset.tab); if(p) p.classList.add('active');
  }));

  const candleData = {
    'Bullish Engulfing':['Bullish Engulfing','A two-candle bullish reversal pattern where the second body engulfs the previous bearish body.','Shows strong buying pressure after bearish price action.','Bearish candle-এর পরে শক্তিশালী buying pressure বোঝায়।','c1'],
    'Bearish Engulfing':['Bearish Engulfing','A two-candle bearish reversal pattern where the second body engulfs the previous bullish body.','Shows strong selling pressure after bullish price action.','Bullish candle-এর পরে শক্তিশালী selling pressure বোঝায়।','c2'],
    'Doji':['Doji','Open and close are very close, producing a small real body.','Signals balance or hesitation; context is essential.','Open ও Close কাছাকাছি হলে indecision বা balance বোঝায়।','c3'],
    'Hammer':['Hammer','A small body with a long lower wick after a decline.','Can signal rejection of lower prices when context confirms.','নিচের price reject করে buyers ফিরে আসার সম্ভাবনা দেখায়।','c4'],
    'Shooting Star':['Shooting Star','A small body with a long upper wick after an advance.','Can signal rejection of higher prices when context confirms.','উপরের price reject হওয়ার সম্ভাবনা দেখায়।','c5'],
    'Morning Star':['Morning Star','A three-candle bullish reversal sequence after a decline.','Shows weakening sellers and a potential shift to buyers.','তিন-candle sequence-এ seller দুর্বল হয়ে buyer control আসতে পারে।','c6'],
    'Evening Star':['Evening Star','A three-candle bearish reversal sequence after an advance.','Shows weakening buyers and potential seller control.','তিন-candle sequence-এ buyer দুর্বল হয়ে seller control আসতে পারে।','c7'],
    'Pin Bar':['Pin Bar','A candle with a pronounced wick and relatively small body.','Highlights rejection; location and market structure matter.','লম্বা wick rejection এবং ছোট body দেখায়; location গুরুত্বপূর্ণ।','c8']
  };
  document.querySelectorAll('.candle-item').forEach(btn=>btn.addEventListener('click',()=>{
    document.querySelectorAll('.candle-item').forEach(x=>x.classList.remove('selected'));
    btn.classList.add('selected');
    const d=candleData[btn.dataset.name]; if(!d) return;
    const visual=document.getElementById('candleVisual');
    document.getElementById('candleName').textContent=d[0];
    document.getElementById('candleDesc').textContent=d[1];
    document.getElementById('candleEn').textContent=d[2];
    document.getElementById('candleBn').textContent=d[3];
    visual.className='stage-visual candle-visual '+d[4]+' animate-in';
    setTimeout(()=>visual.classList.remove('animate-in'),650);
  }));

  const patterns={
    'Ascending Triangle':['Ascending Triangle','Converging structure with rising lows pressing into relatively flat resistance.','Higher lows show buyers becoming more aggressive; breakout needs context and risk control.','Higher low তৈরি হয়ে resistance-এর দিকে pressure বাড়ে।','asc'],
    'Descending Triangle':['Descending Triangle','Converging structure with falling highs pressing into relatively flat support.','Lower highs show sellers becoming more aggressive; confirmation matters.','Lower high তৈরি হয়ে support-এর দিকে selling pressure বাড়ে।','desc'],
    'Falling Wedge':['Falling Wedge','Two downward-sloping converging boundaries compress price.','Momentum can contract before a breakout; wait for confirmation and context.','দুইটি নিচের দিকে ঢালু line কাছে আসতে থাকে; breakout confirmation দরকার।','wedge'],
    'Double Top':['Double Top','Price forms two prominent highs near a similar level with a valley between them.','A break of the intervening neckline gives stronger confirmation of reversal.','দুটি কাছাকাছি high এবং মাঝের neckline break reversal confirmation দিতে পারে।','double']
  };
  document.querySelectorAll('.pattern-item').forEach(btn=>btn.addEventListener('click',()=>{
    document.querySelectorAll('.pattern-item').forEach(x=>x.classList.remove('selected')); btn.classList.add('selected');
    const d=patterns[btn.dataset.name]; document.getElementById('patternName').textContent=d[0]; document.getElementById('patternDesc').textContent=d[1]; document.getElementById('patternUse').textContent=d[2]; document.getElementById('patternBn').textContent=d[3];
    const v=document.getElementById('patternVisual'); v.className='pattern-visual '+d[4]+' animate-in'; setTimeout(()=>v.classList.remove('animate-in'),850);
  }));

  const smc={
    'Market Structure':['Market Structure','Maps highs and lows to identify directional context.','বাংলা: High/Low sequence দেখে direction ও structure বোঝা হয়।'],
    'Liquidity':['Liquidity','Areas where resting orders are likely concentrated, often around obvious highs/lows.','বাংলা: সাধারণত obvious high/low-এর আশেপাশে resting orders-এর concentration থাকতে পারে।'],
    'Order Block':['Order Block','A price area associated with the final opposing candle before a strong displacement.','বাংলা: Strong displacement-এর আগে থাকা গুরুত্বপূর্ণ opposing candle-এর area হিসেবে দেখা হয়।'],
    'Fair Value Gap':['Fair Value Gap','A three-candle imbalance area where price moves rapidly and leaves inefficient trading.','বাংলা: দ্রুত price move-এর কারণে তৈরি হওয়া imbalance area।'],
    'Displacement':['Displacement','A decisive expansion in price showing strong directional intent.','বাংলা: বড় ও decisive price expansion directional intent দেখায়।'],
    'Breaker':['Breaker','A failed order-block area that can become relevant from the opposite side after structure changes.','বাংলা: Structure change-এর পরে failed zone বিপরীত দিকের reaction area হতে পারে।'],
    'Premium & Discount':['Premium & Discount','A framework for judging relative price location within a chosen range.','বাংলা: নির্দিষ্ট range-এর মধ্যে price তুলনামূলকভাবে expensive না cheap তা বোঝার framework।'],
    'Entry Model':['Entry Model','A repeatable sequence combining context, confirmation, invalidation and risk.','বাংলা: Context + confirmation + invalidation + risk মিলিয়ে repeatable entry process।']
  };
  document.querySelectorAll('.smc-card').forEach(b=>b.addEventListener('click',()=>{
    document.querySelectorAll('.smc-card').forEach(x=>x.classList.remove('selected')); b.classList.add('selected');
    const d=smc[b.dataset.name]; document.getElementById('smcName').textContent=d[0]; document.getElementById('smcDesc').textContent=d[1]; document.getElementById('smcBn').textContent=d[2];
  }));

  const road={
    'r1':['Foundation','Do: learn terminology, sessions, order types and basic chart reading.','Expect: slower progress at first. Avoid: trading before you understand the language.'],
    'r2':['Technical Structure','Do: practice candles, patterns, HH/HL/LH/LL and confirmation.','Expect: repeated chart examples. Avoid: memorizing patterns without context.'],
    'r3':['SMC + MTF','Do: build HTF→MTF→LTF analysis and define invalidation.','Expect: fewer but more structured setups. Avoid: forcing a setup because a zone exists.'],
    'r4':['Risk + Journal','Do: define risk before entry and review every trade.','Expect: consistency to improve through feedback. Avoid: increasing risk after losses.']
  };
  document.querySelectorAll('.road-card').forEach(b=>b.addEventListener('click',()=>{
    document.querySelectorAll('.road-card').forEach(x=>x.classList.remove('selected')); b.classList.add('selected');
    const d=road[b.classList[1]]; document.getElementById('roadDetail').innerHTML=`<div class="eyebrow">ROADMAP STAGE</div><h2>${d[0]}</h2><p>${d[1]}</p><p>${d[2]}</p>`;
  }));

  document.querySelectorAll('.like-btn').forEach(b=>b.addEventListener('click',()=>{
    fetch('/community/like/'+b.dataset.id,{method:'POST'}).then(()=>{b.textContent='♥ Liked';}).catch(()=>{});
  }));
});
