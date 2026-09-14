/* Gitlines — the four real widget families, rebuilt from widtget/Views/DefaultWidgetView.swift.
   Every size below is the point value in the Swift source; 1em == 1 point inside a widget. */
(function () {
  var USER = '@yjay18', PERIOD = 'DAILY';
  /* one snapshot: additions 1,247 · deletions 389 · 23 commits · 3 repositories */
  var CELLS = [[40,8],[96,22],[62,14],[128,55],[141,38],[92,30],[124,44],[200,61],[178,62],[84,25],[68,18],[34,12]];
  var LABELS = ['00','02','04','06','08','10','12','14','16','18','20','22'];
  var REPOS = [['gitlines',14,842,201],['thesis-icu',6,301,144],['widtget-app',3,104,44]];
  var ADD = 1247, DEL = 389, COMMITS = 23, NET = ADD - DEL, PEAK = '14', AVG = 71;
  var MAXCELL = CELLS.reduce(function (m, c) { return Math.max(m, c[0] + c[1]); }, 1);
  var FAMILY = { small: [155,155], medium: [329,155], large: [329,345], xl: [681,345] };

  /* SF Symbols the header uses: point.3.connected.trianglepath.dotted, and arrow.clockwise */
  var MARK = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round" width="100%" height="100%">' +
    '<path d="M4.4 5.2 L11.6 5.2 M4.4 5.2 L8 11.2 M11.6 5.2 L8 11.2" stroke-dasharray="1.6 1.7"/>' +
    '<circle cx="4.4" cy="5.2" r="1.7" fill="currentColor" stroke="none"/><circle cx="11.6" cy="5.2" r="1.7" fill="currentColor" stroke="none"/>' +
    '<circle cx="8" cy="11.2" r="1.7" fill="currentColor" stroke="none"/></svg>';
  var REFRESH = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" width="100%" height="100%">' +
    '<path d="M13.2 8a5.2 5.2 0 1 1-1.6-3.75"/><path d="M13.4 2.6 L13.4 5.6 L10.4 5.6"/></svg>';

  function n(v) { return String(v).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function e(px) { return px + 'em'; }
  /* points, safe on elements that set their own font-size */
  function pt(v) { return 'calc(var(--pt) * ' + v + ')'; }

  function header(compact) {
    var gap = compact ? 4 : 7, fs = compact ? 10 : 11;
    return '<div class="hd" style="gap:' + e(gap) + ';height:' + e(16) + '">' +
      (compact ? '' : '<span class="mark" style="width:' + e(11) + ';height:' + e(11) + '">' + MARK + '</span>') +
      '<span class="user" style="font-size:' + e(fs) + '">' + USER + '</span>' +
      '<span class="sp"></span>' +
      '<span class="rf" style="width:' + e(10) + ';height:' + e(10) + '">' + REFRESH + '</span>' +
      '<span class="pill" style="font-size:' + e(9) + ';padding:' + pt(4) + ' ' + pt(compact ? 5 : 7) + ';letter-spacing:' + pt(.8) + '">' + PERIOD + '</span></div>';
  }
  function metric(value, sign, cls, size) {
    return '<div class="big ' + cls + '" style="font-size:' + e(size) + '">' + sign + n(value) + '</div>';
  }
  function secondary(compact) {
    var h = compact ? 23 : 27, pad = compact ? 8 : 10, vf = compact ? 10 : 11, lf = compact ? 8 : 9, gap = compact ? 7 : 12;
    return '<div class="sec" style="height:' + e(h) + ';padding:0 ' + e(pad) + ';gap:' + e(gap) + '">' +
      '<span class="m"><span class="v" style="font-size:' + e(vf) + '">' + COMMITS + '</span><span class="l" style="font-size:' + e(lf) + '">commits</span></span>' +
      '<span class="div" style="height:' + e(11) + '"></span>' +
      '<span class="m"><span class="v" style="font-size:' + e(vf) + '">' + REPOS.length + '</span><span class="l" style="font-size:' + e(lf) + '">repositories</span></span></div>';
  }
  function strip(h) {
    var out = '<div class="strip" style="height:' + e(h) + '">';
    for (var i = 0; i < CELLS.length; i++) {
      var a = CELLS[i][0], d = CELLS[i][1], total = a + d;
      if (!total) { out += '<span class="bar"><i class="z"></i></span>'; continue; }
      var th = Math.max(3, h * (total / MAXCELL)) - 1;          /* 1pt gap between the two segments */
      out += '<span class="bar"><i class="a" style="height:' + e(th * (a / total)) + '"></i>' +
             '<i class="d" style="height:' + e(th * (d / total)) + '"></i></span>';
    }
    return out + '</div>';
  }
  function axis(size) {
    return '<div class="axis" style="font-size:' + e(size) + '">' + LABELS.map(function (l) { return '<span>' + l + '</span>'; }).join('') + '</div>';
  }
  function insights(compact) {
    var tf = compact ? 6.5 : 7.5, vf = compact ? 12 : 15, df = compact ? 5.5 : 6.5, gap = compact ? 6 : 10, sh = compact ? 35 : 42, sp = compact ? 2 : 3;
    function one(t, v, d, cls) {
      return '<span class="i" style="gap:' + e(sp) + '"><span class="t" style="font-size:' + e(tf) + '">' + t + '</span>' +
        '<span class="v ' + cls + '" style="font-size:' + e(vf) + '">' + v + '</span>' +
        '<span class="d" style="font-size:' + e(df) + '">' + d + '</span></span>';
    }
    return '<div class="ins" style="gap:' + e(gap) + '">' + one('NET', '+' + n(NET), 'LINES', 'add') +
      '<span class="sep" style="height:' + e(sh) + '"></span>' + one('PEAK', PEAK, 'INTERVAL', '') +
      '<span class="sep" style="height:' + e(sh) + '"></span>' + one('AVG', n(AVG), 'LINES / COMMIT', '') + '</div>';
  }
  function repos(limit, compact) {
    var nf = compact ? 9 : 10, cf = compact ? 8 : 9, gap = compact ? 7 : 9, sp = compact ? 3 : 5, bar = compact ? 3 : 4;
    var max = REPOS.reduce(function (m, r) { return Math.max(m, r[2] + r[3]); }, 1);
    var out = '<div class="col" style="gap:' + e(gap) + '">';
    REPOS.slice(0, limit).forEach(function (r) {
      var total = r[2] + r[3], w = (total / max) * 100;
      out += '<div class="repo" style="gap:' + e(sp) + '">' +
        '<span class="top"><span class="nm" style="font-size:' + e(nf) + '">' + r[0] + '</span>' +
        '<span class="c" style="font-size:' + e(cf) + '">' + r[1] + 'c</span><span class="sp"></span>' +
        '<span class="n add" style="font-size:' + e(cf) + '">+' + n(r[2]) + '</span>' +
        '<span class="n del" style="font-size:' + e(cf) + '">−' + n(r[3]) + '</span></span>' +
        '<span class="track" style="height:' + e(bar) + '"><i class="a" style="width:' + (w * r[2] / total) + '%"></i>' +
        '<i class="d" style="width:' + (w * r[3] / total) + '%"></i></span></div>';
    });
    if (REPOS.length > limit) out += '<span class="lab" style="font-size:' + e(9) + '">+' + (REPOS.length - limit) + ' more</span>';
    return out + '</div>';
  }
  function label(text, size) { return '<span class="lab" style="font-size:' + e(size) + ';letter-spacing:' + pt(size > 8 ? 1 : .9) + '">' + text + '</span>'; }
  function status() { return '<span class="st" style="font-size:' + e(8) + '">Updated just now</span>'; }
  function grid() {
    var out = '<div class="grid" style="height:' + e(32) + '">';
    for (var i = 0; i < 14; i++) {
      var c = CELLS[i % CELLS.length], t = c[0] + c[1], k = t / MAXCELL;
      var fill = (18 + 82 * k);                                  /* intensity drives how much of the cell fills */
      out += '<i><b class="a" style="height:' + (fill * c[0] / t) + '%"></b><b class="d" style="height:' + (fill * c[1] / t) + '%"></b></i>';
    }
    return out + '</div>';
  }
  function snek() {
    /* one block per commit, serpentine — the same shape the widget draws */
    var cols = 12, out = '<div class="snek" style="grid-template-columns:repeat(' + cols + ',1fr)">', order = [];
    for (var i = 0; i < 24; i++) { var r = Math.floor(i / cols), c = i % cols; order[r * cols + (r % 2 ? cols - 1 - c : c)] = i; }
    for (var j = 0; j < 24; j++) { var idx = order[j];
      out += '<i class="' + (idx < COMMITS ? (idx === COMMITS - 1 ? 'on head' : 'on') : '') + '"></i>'; }
    return out + '</div><div class="st" style="font-size:' + e(8) + ';text-align:center">snek happy · ' + COMMITS + ' commits</div>';
  }
  function surf(inner, pad, radius, extra) {
    return '<div class="surf col" style="padding:' + e(pad) + ';border-radius:' + e(radius) + ';' + (extra || '') + '">' + inner + '</div>';
  }

  var BUILD = {
    small: function () {
      return '<div class="wk-in" style="padding:' + e(12) + ';gap:' + e(5) + '">' + header(true) +
        metric(ADD, '+', 'add', 27) + metric(DEL, '−', 'del', 25) +
        '<span class="grow"></span>' + secondary(true) +
        '<div class="row" style="gap:' + e(7) + ';height:' + e(12) + ';align-items:flex-end">' +
        '<span class="grow">' + strip(9) + '</span>' + status() + '</div></div>';
    },
    medium: function () {
      return '<div class="wk-in" style="padding:' + e(14) + ';gap:' + e(9) + '">' + header(false) +
        '<div class="row grow" style="gap:' + e(12) + '">' +
        '<div class="col grow" style="gap:' + e(5) + '">' + metric(ADD, '+', 'add', 31) + metric(DEL, '−', 'del', 29) +
        '<span class="grow"></span>' + secondary(true) + '</div><span class="rule-v"></span>' +
        '<div class="col grow" style="gap:' + e(8) + '">' + repos(2, true) + '<span class="grow"></span>' + strip(16) + status() + '</div></div></div>';
    },
    large: function () {
      var card = function (v, s, c) { return '<div class="surf grow" style="padding:' + e(9) + ' ' + e(12) + ';border-radius:' + e(12) + '">' + metric(v, s, c, 35) + '</div>'; };
      return '<div class="wk-in" style="padding:' + e(16) + ';gap:' + e(11) + '">' + header(false) +
        '<div class="row" style="gap:' + e(10) + ';height:' + e(70) + '">' + card(ADD, '+', 'add') + card(DEL, '−', 'del') + '</div>' +
        secondary(false) +
        '<div class="row grow" style="gap:' + e(12) + '">' +
        surf(label('ACTIVITY', 8) + strip(40) + axis(6.5) + '<span class="rule-h" style="margin:' + e(4) + ' 0"></span>' + insights(true) + '<span class="grow"></span>' + status(), 10, 10, 'gap:' + e(5) + ';flex:1 1 0;min-width:0') +
        /* compact rows here: the web fallback face is wider than SF Rounded, so the
           source's 10pt rows clip the repository name in the large family's half-width card */
        surf(label('REPOSITORIES', 8) + repos(3, true), 10, 10, 'gap:' + e(8) + ';flex:1 1 0;min-width:0') +
        '</div></div>';
    },
    xl: function () {
      var card = function (v, s, c) { return '<div class="surf" style="padding:' + e(11) + ' ' + e(14) + ';border-radius:' + e(13) + '">' + metric(v, s, c, 50) + '</div>'; };
      return '<div class="wk-in" style="padding:' + e(17) + ';gap:' + e(13) + '">' + header(false) +
        '<div class="row grow" style="gap:' + e(14) + '">' +
        '<div class="col" style="gap:' + e(10) + ';flex:1 1 0;min-width:0">' + card(ADD, '+', 'add') + card(DEL, '−', 'del') + secondary(false) +
        surf(insights(false), 11, 12, 'padding:' + e(11) + ' ' + e(13)) + '</div>' +
        '<div class="col" style="gap:' + e(10) + ';flex:1 1 0;min-width:0">' +
        surf(label('ACTIVITY', 9) + strip(50) + axis(7) + grid() + status(), 13, 13, 'gap:' + e(7)) +
        surf(snek(), 13, 13, 'gap:' + e(5) + ';flex:1 1 auto;justify-content:center') + '</div>' +
        surf(label('REPOSITORIES', 9) + repos(3, false), 13, 13, 'gap:' + e(11) + ';flex:1 1 0;min-width:0') +
        '</div></div>';
    }
  };

  window.GitlinesSizes = {
    families: Object.keys(FAMILY),
    /* renders one family into el at its true macOS point size */
    render: function (el, family) {
      el.className = 'wk wk-' + family;
      el.innerHTML = BUILD[family]();
      return el;
    }
  };
})();
