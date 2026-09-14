/* Gitlines site — shared widget mock. Same snapshot, six faces. */
window.Gitlines = (function () {
  var ADD = 1247, DEL = 389, BARS = [18,34,26,58,92,71,44,22,30,66,88,40], GLYPH = "▂▃▃▅█▆▄▂▃▆█▄";
  var REPOS = [["gitlines",842,201],["thesis-icu",301,144],["widtget-app",104,44]];
  var THEMES = [
    { key:"default",    name:"Default",    period:"Daily", commits:"23 commits", bar:"Activity",   foot:"Updated just now",          blurb:"A restrained dark dashboard. Bright additions, coral deletions, compact charts." },
    { key:"glasshouse", name:"Glasshouse", period:"Daily", commits:"23 commits", bar:"Activity",   foot:"Updated just now",          blurb:"Translucent surfaces, hairline separators, mint and rose, almost no chrome." },
    { key:"phosphor",   name:"Phosphor",   period:"daily", commits:"23 commits", bar:"activity",   foot:"$ git log --since=1.day",   blurb:"A terminal. Monospaced output, block-glyph charts, git log style repo rows." },
    { key:"broadsheet", name:"Broadsheet", period:"Daily", commits:"23 commits", bar:"Day Book",   foot:"The Day's Ledger",          blurb:"Warm newsprint, serif type, press-red deletions, dotted day-book rows." },
    { key:"arcade",     name:"Arcade",     period:"DAILY", commits:"SCORE 23",   bar:"HIGH SCORE", foot:"PRESS ↻ TO REFRESH",        blurb:"Four-colour handheld. Commits are your score, peak activity is the high score." },
    { key:"blockwork",  name:"Blockwork",  period:"Daily", commits:"23 commits", bar:"Activity",   foot:"Updated just now",          blurb:"A modular studio. Drag panes into slots, hide what you don't need, pick a colourway." }
  ];
  function g(n){ return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
  function bars(t){
    if (t.key === "phosphor") return '<div class="bars-glyph">' + GLYPH + '</div>';
    return '<div class="bars">' + BARS.map(function(h,i){ return '<span class="bar' + ([3,7,9].indexOf(i)>-1?' neg':'') + '" style="height:' + h + '%"></span>'; }).join('') + '</div>';
  }
  function repos(t){
    return '<div class="repos">' + REPOS.map(function(r){
      return '<div class="repo"><span class="repo-name">' + r[0] + (t.key==="phosphor"?'/':'') + '</span><span class="repo-nums"><span class="repo-add">+' + g(r[1]) + '</span><span class="repo-del">−' + g(r[2]) + '</span></span></div>';
    }).join('') + '</div>';
  }
  function markup(t){
    return '<div class="w"><div class="w-head"><span class="w-user"><span class="w-dot"></span>@yjay18</span><span class="w-period">' + t.period + '</span></div>' +
      '<div class="w-body"><div class="w-metrics"><div class="m-add">+' + g(ADD) + '</div><div class="m-del">−' + g(DEL) + '</div><div class="m-commits">' + t.commits + '</div></div>' +
      '<div class="w-right"><div class="w-barlabel">' + t.bar + '</div>' + bars(t) + repos(t) + '</div></div><div class="w-foot">' + t.foot + '</div></div>';
  }
  function theme(key){ for (var i=0;i<THEMES.length;i++) if (THEMES[i].key===key) return THEMES[i]; return THEMES[0]; }
  function mount(el, key){ var t = theme(key); el.className = 'gl-widget t-' + t.key; el.innerHTML = markup(t); return t; }
  return { THEMES: THEMES, mount: mount, markup: markup, theme: theme, ADD: ADD, DEL: DEL };
})();
