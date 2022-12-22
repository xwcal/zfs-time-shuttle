// CDDL HEADER START
//
// This file and its contents are supplied under the terms of the
// Common Development and Distribution License ("CDDL"), version 1.0.
// You may only use this file in accordance with the terms of version
// 1.0 of the CDDL.
//
// A full copy of the text of the CDDL should have accompanied this
// source.  A copy of the CDDL is also available via the Internet at
// https://www.opensource.org/licenses/CDDL-1.0
//
// CDDL HEADER END
//
// Copyright (C) 2019 Xiao Wan


// lang_packs is defined in lang_packs.js, loaded by index.html before this js file
var lang = lang_packs['zh'];

// elements:
var session_disp;
var lbutton;
var rbutton;
var returncode_disp;
var stdout_disp;
var stderr_disp;
var display_div;
var message_div;
var branch_pane;
var snap_pane;
var detail_pane;
var svg_box;
var note_box;
var sn_switch;

// session:
var seq = 0;
var token = '';
var expiry;
var renew_timer;

// cache:
var branches;
var snaps;
var sd; // should have called sdx (x for extra), well ...
var sd_names = ['csbm','csts','rbp','rsp','cbp','csp','ncbp','ncsp','tsmin'];
// An issue here is concurrent editing:
// Sessioning only protects against concurrent editing from the browser.
// There is nothing that prevents modifying the pool from console.
// The best guard is to check uber block timestamp at init_session and
// then right before commit, using (-e -p means search for device under the path):
// zdb -u -e -p /dev/shm/ rpool
// However, without a lock, changes can still happen after the check and before
// the commit.
// So, let's assume the user only uses the browser to modify the pool.

var selections = {};

var current_step; // used by event handlers and async continuations

var last_mount; // used by get_note_step1/2 to determine if remounting is needed

// debug:
var returnedObj;

var timemap_mgr;

var request_mgr = (function(){
  let queue = [];
  let pending;
  let ajax = new XMLHttpRequest();
  ajax.onreadystatechange = function(){
    // console.log(ajax.readyState);
    if (ajax.readyState < 4) {
      // console.log('In progress ...');
      return;
    }
    // console.log(ajax.statusText);
    if (ajax.status == 200)
      pending.res(ajax.response);
    else
      pending.rej(ajax.status);
    if (queue.length>0)
      dequeue();
  };
  function dequeue() {
    pending = queue.shift();
    ajax.open('POST','http://127.0.0.1:8000', true);
    ajax.send(pending.req);
  }
  function enqueue(req) {
    let p = new Promise((res,rej)=>queue.push({req:req, res:res, rej:rej}));
    if (ajax.readyState == 4 || ajax.readyState == 0) {
      dequeue();
    }
    return p;
  }
  function json_encode(op, args) {
    return JSON.stringify({seq:seq,
			   token:token,
			   ts:Date.now()/1000,
			   dur:10,
			   op:op,
			   args:args
			  });
  }
  
  return {send_request:(op,args)=>enqueue(json_encode(op, args))};
}());

var note_mgr = (function(){
  let pending;
  let selected = {};
  let cache = {step1:{}, step2:{}};

  get_note = {
    step1: async function(branch, snap) {
      let obranch = branch==last_mount? '': branch;
      let osnap = snap;
      let note = '';
      let stdout;
      let bo = lang.orig;
      while (branch == snap) {
	note += branch+'@'+snap+bo;
	[branch, snap] = get_origin(branch);
	note += branch+'@'+snap+'\n';
      }
      if (snap == 'baseline') {
	note += branch+'@'+snap+lang.no_note;
	return note;
      } else if (snap == '') {
	return null;
      }
      try {
	stdout = await exec(['sh/get_note_step1.sh', osnap, branch, snap, obranch]);
      } catch(e) {
	on_error(e);
	last_mount = undefined;
	return null;
      }
      if (stdout !== null) {
	last_mount = obranch;
	return note+stdout;
      } else {
	last_mount = undefined;
	return null;
      }
    },
    step2: async function(branch, snap) {
      let stdout;
      try {
	stdout = await exec(['sh/get_note_step2.sh', branch, snap, branch+'/home']);
      } catch(e) {
	on_error(e);
	last_mount = undefined;
	return null;
      }
      if (stdout !== null) {
	last_mount = branch+'/home';
	return stdout;
      } else {
	last_mount = undefined;
	return null;
      }
    }
  };

  function get_origin(branch) {
    let i = branches.findIndex(r=>r[0]==branch);
    if (i == -1) return [branch, ''];
    return branches[i][1].split('@');
  }

  async function display(step_name, branch, snap) {
    let key = branch+'@'+snap;
    let note = cache[step_name][key];
    if (note === null) {
      pending = key;
      note_box.innerHTML = lang.wait;
      return;
    } else if (note !== undefined) {
      show(key, note);
    } else {
      cache[step_name][key] = null;
      pending = key;
      note_box.innerHTML = lang.wait;
      note = await get_note[step_name](branch, snap);
      if (note !== null) {
	cache[step_name][key] = note;
      } else {
	delete cache[step_name][key];
	note = 'Unable to read note.';	
      }
      if (step_name != current_step) return;
      if (key == pending || (pending === undefined && key == selected[step_name])) {
	show(key, note);
	pending = undefined;
      }
    }
  }

  function show(key, note) {
    note_box.textContent = key+'\n------------------\n'+note;
  }

  function cancel() {
    pending = undefined;
    let key = selected[current_step];
    let note = cache[current_step][key];
    if (note !== null && note !== undefined)
      show(key, note);
    else
      note_box.innerHTML = '';
  }

  function set_selected(step_name, branch, snap) {
    let key = branch+'@'+snap;
    selected[step_name] = key;
  }

  function unset_selected(step_name) {
    delete selected[step_name];
  }

  return {
    display: display,
    cancel: cancel,
    set_selected: set_selected,
    unset_selected: unset_selected
  }
}());

// simple replacement formatting:
// replacing {n} with the nth argument
String.prototype.sformat = function() {
  let arr = [];
  let b = 0;
  let re = /{(\d+)}/g;
  let r;
  while ((r=re.exec(this))!==null) {
    arr.push(this.substring(b,r.index));
    if (arguments[r[1]] !== undefined)
      arr.push(arguments[r[1]]);
    b = re.lastIndex;
  }
  arr.push(this.substring(b));
  return arr.join('');
}

// dictionary replacement:
// replacing {key} with d.key
String.prototype.dformat = function(d) {
  let arr = [];
  let b = 0;
  let re = /{(\w+)}/g;
  let r;
  while ((r=re.exec(this))!==null) {
    arr.push(this.substring(b,r.index));
    if (d[r[1]] !== undefined)
      arr.push(d[r[1]]);
    b = re.lastIndex;
  }
  arr.push(this.substring(b));
  return arr.join('');
}


function SvgTimeMap() {
  
  let svg; 
  let defs;
  let xmlns = 'http://www.w3.org/2000/svg';

  let tm_branches = {};

  let branches_drawn = false;
  let snaps_drawn = new Set([]);

  let spu; // vertically, spu seconds per svg unit
  let spu_max = 86400; // correponds to 24h/unit
  let bw = 50; // branch width (in svg unit -- same below)
  let mlr = 0.05; // left and right margin as percentage of drawing width
  let mtb = 0.05; // top and bottom margin as percentage of drawing height
  // ddy: default y increment
  // -- "bottom y of vertical segment of child branch" minus "origin snap y"
  let ddy = 50;
  // nh: null height -- when snaps aren't all known, the height of the segment beyond
  // the last branching snap (high snap)
  let nh;
  let ts0;

  let bhh; // branch hover highlighter
  let bsh; // branch select highlighter
  let shh; // snap hover highlighter
  let ssh; // snap select highlighter

  let bhhg; // branch hover highlighter gradient

  let min = Math.min;
  let max = Math.max;
  let round = Math.round;
  
  function init() {
    // https://stackoverflow.com/questions/23588384/dynamically-created-svg-element-not-displaying
    svg = document.createElementNS(xmlns, 'svg');
    // https://stackoverflow.com/questions/19484707/how-can-i-make-an-svg-scale-with-its-parent-container
    svg.style.width = '100%';
    svg.style.height = '100%';
    
    defs = document.createElementNS(xmlns, 'defs');
    svg.appendChild(defs);

    // put bsh over bhh by adding it later:
    bhh = make_highlighter('bhh');
    bhhg = make_gradient('bhhg',0,0,0,0);
    defs.appendChild(bhhg);
    bsh = make_highlighter('bsh');

    // put ssh over shh:
    shh = make_highlighter('shh');
    ssh = make_highlighter('ssh');
  }

  function show(container) {
    container.appendChild(svg);
  }

  function resize(nbr, tsmin, tsmax) {
    spu = round((tsmax-tsmin)/screen.height);
    spu = max(1, min(spu, spu_max));
    let dw = nbr*bw; // drawing width
    let dh = round((tsmax-tsmin)/spu); // drawing height
    let tw = dw+2*mlr*dw;
    let th = dh+2*mtb*dh;

    nh = round(dh/10);
    ts0 = tsmin;
    
    // viewBox specifies where the viewBox lies in the svg coordinate system
    // and its size.
    //
    // with default preserveAspectRatio (xMidYMid meet):
    // the aspect radio of the viewBox is preserved, and the viewBox is
    // scaled so that it lies entirely within the svg element
    // and the horizonal and vertical mid points are aligned.
    // 
    // So, if the svg is 500px by 300px, and the drawing area is "0 0 300 300", then
    // it's mapped onto the svg box with topleft (x,y)=(100px,0px) and
    // bottomright (x,y)<(400px,300px) -- "<" means noninclusive, since we are 0based.
    // If the svg is now scaled down to 250px by 150px, the same drawing area then
    // is mapped onto the svg box with topleft (x,y)=(50px,0px) and
    // bottomright (x,y)<(200px,150px).

    // We want the tree to grow upward, so the regular cartesian system with
    // upward y axis is more natural. However, for convinience, we want a simple
    // mapping taking the cartesian y to the svg y.
    // There is built-in tranform for that, but the text (we may need to use labels)
    // gets flipped as well:
    // https://stackoverflow.com/questions/3846015/flip-svg-coordinate-system
    // Instead, we draw on the area with negative svg y, so that mapping from
    // cartesian y to svg y is just taking negation.
    
    // without margins, can set x:0,y:-th
    // with margins -- simply adjust by margins
    svg.setAttribute('viewBox','{x} {y} {w} {h}'.dformat({
      x: -mlr,
      y: -th+mtb,
      w: tw,
      h: th}));
  }

  function make_gradient(id, x1,y1, x2,y2) {
    let g = document.createElementNS(xmlns, 'linearGradient');
    g.setAttribute('id',id);
    g.setAttribute('x1',x1);
    g.setAttribute('y1',y1);
    g.setAttribute('x2',x2);
    g.setAttribute('y2',y2);
    g.setAttribute('gradientUnits','userSpaceOnUse');
    
    let s;
    
    s = document.createElementNS(xmlns, 'stop');
    s.setAttribute('style', 'stop-opacity:1;');
    s.setAttribute('offset', 0);
    g.appendChild(s);

    s = document.createElementNS(xmlns, 'stop');
    s.setAttribute('style', 'stop-opacity:0;');
    s.setAttribute('offset', 1);
    g.appendChild(s);
    
    return g;
  }

  // order by df traversal of tree with branches as nodes and "has origin branch"
  // as the "is parent" relation; children of a branch are inversely ordered
  // by snapshot name
  function sort(branches, tsmin) {
    let br2cs = {};
    let stack = []; // don't do recursion!
    let sorted = [];
    let br, orig;
    let ob,os;

    function visit(c, ip) {
      c[2] = ip; // parent's index
      c[3] = c[0]; // the last branching snap (high snap) on c[0] -- to be updated
      let cs = br2cs[c[0]];
      if (cs !== undefined) {
	stack.push([cs, sorted.length]);
	c[3] = cs[cs.length-1][1]; // update if has children
      }
      sorted.push(c);
    }
    
    for ([br,orig] of branches) {
      [ob,os] = orig.split('@');
      if (ob in br2cs)
	br2cs[ob].push([br,os,NaN,NaN]);
      else
	br2cs[ob] = [[br,os,NaN,NaN]];
    }

    // To make things easier for draw_branches(),
    // cheat a little bit by modifying the entry for root@baseline:
    // br2cs['root'] == [['0000000000', 'baseline', NaN]]
    br2cs['root'][0] = ['0000000000', tsmin, NaN];
    // Now pass in 0 as ip, so that make_bezier makes a path going straight up:
    visit(br2cs['root'][0],0);
    for (br in br2cs) {
      br2cs[br].sort((c1,c2)=>{
	let d=c1[1]-c2[1];
	if (d != 0) return d;
	else return c1[0]-c2[0];
      });
    }
    let c, ip;
    while (stack.length) {
      c = stack[stack.length-1][0].pop();
      ip = stack[stack.length-1][1];
      if (c)
	visit(c, ip);
      else
	stack.pop(); // pop the empty cs
    }
    return sorted;
  }

  // Concerning line-width:
  // https://www.w3.org/TR/SVG11/coords.html#Units
  // "One px unit is defined to be equal to one user unit.
  // Thus, a length of "5px" is the same as a length of "5". ...
  // However, if there are any coordinate system transformation due to the use of
  // ‘transform’ or ‘viewBox’ attributes, because "5px" maps to 5 user units and
  // because the coordinate system transformations have resulted in a revised
  // user coordinate system, "5px" likely will not map to 5 device pixels. "

  function make_bezier(i, x0, y0, dx, dy, x1, y1) {
    let bez = document.createElementNS(xmlns, 'path');
    let grad = make_gradient('grad'+i, x1, vt(y1), x1, vt(y1+nh));
    bez.setAttribute('style',
		     'fill:none;stroke:url(#grad{0});'.sformat(i));
    // https://www.w3.org/TR/SVG/paths.html
    bez.setAttribute('d', 'M{x0},{y0}c0,{dy} {dx},0 {dx},{dy}L{x1},{y1}'.dformat({
      x0: x0,
      y0: vt(y0),
      dx: dx,
      dy: vt(dy),
      x1: x1,
      y1: vt(y1+nh)
    }));
    return [bez, grad, x0, y0, dx, dy, x1];
  }

  function ts2y(ts) {
    // ts could be 0000000000 -- in that case, treat it as ts0
    return max(0, round((ts-ts0)/spu));
  }

  // vertical transform -- apply to y coords just before feeding to svg:
  function vt(cart_y) {
    return -cart_y;
  }

  function opacify(grad) {
    grad.lastElementChild.style.stopOpacity=1;
  }

  function draw_mark(x, y) {
    let mk = document.createElementNS(xmlns, 'path');
    mk.setAttribute('style','fill:none;');
    mk.setAttribute('d', 'M{0},{1}L{2},{3}'.sformat(x-5,vt(y),x+5,vt(y)));
    mk.setAttribute('class', 'mark');
    svg.appendChild(mk);
  }

  function draw_branches(branches, tsmin, tsmax) {
    if (branches_drawn) return;
    branches_drawn = true;
    resize(branches.length, tsmin, tsmax);
    let sorted = sort(branches, tsmin);
    let br, os, ip, hs, bcomp;
    let x0, y0, dx, dy, x1, y1, c;

    // see svg_timemap_trials for other ideas
    // 
    // Because of the way the branches are sorted and the choice of control points,
    // can prove that the curves never cross each other:
    //
    // Since we use the same dy for all curves, at any t,
    // the vertical components of two velocities (derivative) are the same
    // and always positve: 3(1-t)^2-6(1-t)t+3t^2 > 0 for all t
    // while for bigger dx, the horizontal component of the velocity is bigger
    // so the curves seperate as they extend upward
    //
    // see the derivative part in:
    // https://en.wikipedia.org/wiki/B%C3%A9zier_curve#Cubic_B%C3%A9zier_curves
    dy = ddy;
    for (let i=0; i<sorted.length; i++) {
      [br,os,ip,] = sorted[i];
      if (i == ip) continue; // root branch
      // br is the same as the first snap
      dy = min(dy, ts2y(br)-ts2y(os));
    }
    
    for (let i=0; i<sorted.length; i++) {
      [br, os, ip, hs] = sorted[i];
      x0 = ip*bw;
      y0 = ts2y(os);
      dx = (i-ip)*bw;
      // dy = ts2y(br)-y0; // actually looking pretty cool, but may cross
      x1 = x0+dx;
      y1 = ts2y(hs);
      bcomp = make_bezier(i, x0, y0, dx, dy, x1, y1);
      tm_branches[br] = bcomp;
      svg.appendChild(bcomp[0]);
      defs.appendChild(bcomp[1]);
    }
  }

  function draw_snaps(branch, snaps) {
    if (snaps_drawn.has(branch)) return;
    snaps_drawn.add(branch);
    let ts = snaps[0][0];
    let [bez, grad, x0, y0, dx, dy, x1] = tm_branches[branch];
    let y1 = ts2y(snaps[0][0]);
    adjust_bezier(bez, x0, y0, dx, dy, x1, y1);
    opacify(grad);
    for ([ts,] of snaps)
      draw_mark(x1, ts2y(ts));
  }

  function adjust_bezier(bez, x0, y0, dx, dy, x1, y1) {
    bez.setAttribute('d', 'M{x0},{y0}c0,{dy} {dx},0 {dx},{dy}L{x1},{y1}'.dformat({
      x0: x0,
      y0: vt(y0),
      dx: dx,
      dy: vt(dy),
      x1: x1,
      y1: vt(y1)
    }));
  }

  function make_highlighter(cls) {
    let h = document.createElementNS(xmlns, 'path');
    h.setAttribute('class', cls);
    h.setAttribute('style', 'fill:none;');
    svg.appendChild(h);
    return h;
  }

  function highlight_branch_hover(branch) {
    let g = tm_branches[branch][1];
    bhhg.setAttribute('x1',g.getAttribute('x1'));
    bhhg.setAttribute('y1',g.getAttribute('y1'));
    bhhg.setAttribute('x2',g.getAttribute('x2'));
    bhhg.setAttribute('y2',g.getAttribute('y2'));
    bhhg.lastElementChild.style.stopOpacity = g.lastElementChild.style.stopOpacity;
    highlight_branch(branch, bhh);
    bhh.style.display='';
  }

  function unhighlight_branch_hover() {
    bhh.style.display='none';
  }

  function highlight_branch_select(branch) {
    highlight_branch(branch, bsh);
  }

  function highlight_branch(branch, h) {
    let bez = tm_branches[branch][0];
    h.setAttribute('d', bez.getAttribute('d'));
  }

  function highlight_snap_hover(branch, snap) {
    highlight_snap(branch, snap, shh);
    shh.style.display='';
  }

  function unhighlight_snap_hover() {
    shh.style.display='none';
  }

  function highlight_snap_select(branch, snap) {
    highlight_snap(branch, snap, ssh);
    ssh.style.display='';
  }

  function unhighlight_snap_select() {
    ssh.style.display='none';
  }

  function highlight_snap(branch, snap, h) {
    let x = tm_branches[branch][6];
    let y = ts2y(snap);
    h.setAttribute('d', 'M{0},{1}L{2},{3}'.sformat(x-20,vt(y),x+20,vt(y)));
  }

  init();
  
  return {
    show: show,
    draw_branches: draw_branches,
    draw_snaps: draw_snaps,
    highlight_branch_hover: highlight_branch_hover,
    unhighlight_branch_hover: unhighlight_branch_hover,
    highlight_branch_select: highlight_branch_select,
    highlight_snap_hover: highlight_snap_hover,
    unhighlight_snap_hover: unhighlight_snap_hover,
    highlight_snap_select: highlight_snap_select,
    unhighlight_snap_select: unhighlight_snap_select
  }
  
};

function TimeMapMgr() {
  let maps = {};
  maps.step1 = SvgTimeMap();
  maps.step2 = SvgTimeMap();
  return {
    show: function(step_name) {
      if (step_name in maps) {
	if (svg_box.firstElementChild)
	  svg_box.removeChild(svg_box.firstElementChild);
	maps[step_name].show(svg_box);
      }
    },
    
    draw_branches: function(step_name, branches, tsmin, tsmax) {
      if (step_name in maps)
	maps[step_name].draw_branches(branches, tsmin, tsmax);
    },

    draw_snaps: function (step_name, branch, snaps) {
      if (step_name in maps)
	maps[step_name].draw_snaps(branch, snaps);
    },
    
    highlight_branch_hover: function (step_name, branch) {
      maps[step_name].highlight_branch_hover(branch);
    },
    
    unhighlight_branch_hover: function (step_name) {
      maps[step_name].unhighlight_branch_hover();
    },
    
    highlight_branch_select: function (step_name, branch) {
      maps[step_name].highlight_branch_select(branch);
    },
    
    highlight_snap_hover: function (step_name, branch, snap) {
      maps[step_name].highlight_snap_hover(branch, snap);
    },
    
    unhighlight_snap_hover: function (step_name) {
      maps[step_name].unhighlight_snap_hover();
    },
    
    highlight_snap_select: function(step_name, branch, snap) {
      maps[step_name].highlight_snap_select(branch, snap);
    },

    unhighlight_snap_select: function(step_name) {
      maps[step_name].unhighlight_snap_select();
    }
  } 
};


function init_elements() {
  session_disp = document.getElementById('session');
  lbutton = document.getElementById('lbutton');
  rbutton = document.getElementById('rbutton');
  display_div = document.getElementById('display');
  branch_pane = document.getElementById('branches');
  snap_pane = document.getElementById('snaps');
  detail_pane = document.getElementById('details');
  svg_box = document.getElementById('svg_box');
  note_box = document.getElementById('note_box');
  sn_switch = document.getElementById('sn_switch');
  message_div = document.getElementById('message');
  returncode_disp = document.getElementById('returncode');
  stdout_disp = document.getElementById('stdout');
  stderr_disp = document.getElementById('stderr');

  let tbrh = document.getElementById('tbr_header');
  let tsnph = document.getElementById('tsnp_header');
  tbrh.innerHTML = '<tr><td>'+lang.brname+'</td><td>'+lang.orig+'</td></tr>';
  tsnph.innerHTML = '<tr><td>'+lang.snpname+'</td><td>'+lang.creation+'</td></tr>';

  sn_switch.firstElementChild.textContent = lang.svg;
  sn_switch.lastElementChild.textContent = lang.note;

  branch_pane.onmouseover = function(e) {
    if (e.target.tagName != 'TD') return;
    timemap_mgr.highlight_branch_hover(current_step, e.target.parentElement.firstElementChild.textContent);
  };

  branch_pane.onmouseout = function(e) {
    if (e.target.tagName != 'TD') return;
    timemap_mgr.unhighlight_branch_hover(current_step);
  };

  snap_pane.onmouseover = async function(e) {
    if (e.target.tagName != 'TD') return;
    let branch = selections[current_step][0];
    let snap = e.target.parentElement.firstElementChild.textContent;
    timemap_mgr.highlight_snap_hover(current_step, branch, snap);
    note_mgr.display(current_step, branch, snap);
  }

  snap_pane.onmouseout = function(e) {
    if (e.target.tagName != 'TD') return;
    timemap_mgr.unhighlight_snap_hover(current_step);
    note_mgr.cancel();
  }

  let boxes = [svg_box, note_box];  
  let prev_target = sn_switch.firstElementChild;
  prev_target.classList.add('chosen');
  note_box.style.display = 'none';
  sn_switch.onclick = function(e) {
    if (e.target.tagName != 'SPAN') return;
    prev_target.classList.remove('chosen');
    boxes[prev_target.dataset.idx].style.display = 'none';
    prev_target = e.target;
    e.target.classList.add('chosen');
    boxes[e.target.dataset.idx].style.display = '';
  }
}

// idempotent
function style_disabled(b) {
  b.classList.remove('enabled');
  b.classList.add('disabled');
}

// idempotent
function style_enabled(b) {
  b.classList.remove('disabled');
  b.classList.add('enabled');
}

async function init_session() {
  let resp;
  try {
    resp = await request_mgr.send_request(''); 
  } catch(e) {
    on_error(e);
    return false;
  }
  let pack = parse(resp);
  if (!session_ok(pack)) return false;
  update_expiry(pack);
  return true;
}

function parse(s) {  
  try {
    return JSON.parse(s);
  } catch (e) {
    console.log('Parsing error on:');
    console.log(s);
    return {};
  }
}

function session_ok(pack) {
  if (pack.session==1) {
    if (pack.seq && seq!=pack.seq) {
      seq = pack.seq;
      token = pack.token;
      document.title = lang.title.sformat(seq);
    }
    return true;
  } else {
    console.log('Failed session:')
    console.log(pack);
    alert(lang.in_use.sformat(lang.title.sformat(pack.who)));
    return false;
  }
}

function update_expiry(pack) {
  expiry = pack.expiry;
  session_disp.textContent = expiry;
  clearTimeout(renew_timer);
  renew_timer = setTimeout(renew, 10000);
}

function renew() {
  let p = request_mgr.send_request('');
  p.then(x=>{
    let pack = parse(x);
    if (!session_ok(pack)) return;
    update_expiry(pack);
  }).catch(on_error);
}

function on_error(e) {
  console.log('Connection error with status code: '+e);
  alert(lang.connection_error);
}

async function step1() {
  prep_step({lbutton_text: lang.go_back,
	     rbutton_text: lang.go_forward,
	     message_multiline: false,
	     message_content: format_instr(lang.step1_instr),
	     display_hidden: false,
	     lbutton_hidden: true,
	     rbutton_enabled: false});
  
  if (!await init_state('step1')) return null;

  let source, arg;
  while (true) {
    [source, arg] = await Promise.race([branch_pane_click(),
					snap_pane_click(),
					rbutton_click()]);
    // console.log(source,arg);
    switch (source) {
    case 'sp':
      handle_snap_selection('step1', arg);
      break;
    case 'bp':
      await handle_branch_selection('step1', arg);
      break;
    case 'rb':
      if (selections.step1 && selections.step1[1] && check_step('step1'))
	return step2;
    }
  }
}

function prep_step({lbutton_text,
		    rbutton_text,
		    message_multiline,
		    message_content, 
		    display_hidden,
		    lbutton_hidden,
		    rbutton_enabled}) {
  style_enabled(lbutton);
  style_disabled(rbutton);
  lbutton.textContent = lbutton_text;
  rbutton.textContent = rbutton_text;
  if (message_multiline)
    message_div.classList.add('multiline');
  else
    message_div.classList.remove('multiline');
  message_div.innerHTML = message_content;
  display_div.hidden = display_hidden;
  lbutton.hidden = lbutton_hidden;
  if (rbutton_enabled)
    style_enabled(rbutton);
  else
    style_disabled(rbutton);
}

function format_instr(arr) {
  return arr[0].sformat('<span class="rbp">'+arr[1]+'</span>',
			'<span class="rsp">'+arr[2]+'</span>',
			'<span class="selected">'+arr[3]+'</span>',
			'<span class="selected">'+arr[4]+'</span>');
}

async function init_state(step_name, branch, snap) {
  let r;
  if (!sd) {    
    // avoid confusing the user while query is pending:
    branch_pane.innerHTML = lang.wait;
    snap_pane.innerHTML = lang.wait;
    try {
      r = await query_sd();
    } catch(e) {
      on_error(e);
      return false;
    }
    if (!r) return false;
  }
  // default to rbp and rsp:
  if (!branch) {
    branch = sd.rbp;
    snap = sd.rsp;
  }
  if (!branches) {
    try {
      r = await query_branches();
    } catch(e) {
      on_error(e);
      return false;
    }
    if (!r) return false;
    populate_pane(branch_pane, branches, b=>b==sd.rbp?'rbp':'');
  }
  current_step = step_name;
  if (!timemap_mgr) timemap_mgr = TimeMapMgr();
  timemap_mgr.draw_branches(step_name, branches, sd.tsmin, sd.csts);
  timemap_mgr.show(step_name);
  note_mgr.cancel(); // like a clear
  // overwrite parameters if selection is already made:
  if (selections[step_name]) [branch, snap] = selections[step_name];
  if (!branch) return true;
  style_selected_branch(branches, branch, branch_pane);
  if (!snaps[step_name][branch] || !snaps[step_name][branch].length)
    try {
      await query_snaps(step_name, branch);      
    } catch(e) {
      on_error(e);
      return false;
    }
  populate_pane(snap_pane, snaps[step_name][branch],
		branch==sd.rbp && step_name=='step1'?
		(s=>s==sd.rsp?'rsp':'') :
		(s=>''));
  timemap_mgr.draw_snaps(step_name, branch, snaps[step_name][branch]);
  timemap_mgr.highlight_branch_select(step_name, branch);
  if (!snap) return true;
  style_selected_snap(snaps[step_name][branch], snap, snap_pane);
  timemap_mgr.highlight_snap_select(step_name, branch, snap);
  note_mgr.set_selected(step_name, branch, snap);
  note_mgr.display(step_name, branch, snap);
  style_enabled(rbutton);
  // in case selection is not made (otherwise harmless):
  selections[step_name] = [branch, snap];

  return true;
}

async function query_sd() {
  let stdout = await exec(['sh/get_sd.sh']);
  if (stdout === null) return false;
  cache_sd(stdout);
  return true;
}

function cache_sd(stdout) {
  let sd_vals = stdout.trim().split(':');
  sd = {};
  for (let i=0; i<9; i++) {
    sd[sd_names[i]] = sd_vals[i];
  }
}

async function query_branches() {
  let stdout = await exec(['sh/list_branches.sh']);
  if (stdout === null) return false;
  cache_branches(stdout);
  return true;
}

function cache_branches(stdout) {
  snaps = {step1:{},step2:{}};
  branches = stdout.trim().split('\n').map(x=>x.split('\t'));
}


async function query_snaps(step_name, branch) {
  let suffix = step_name=='step1' ? '' : '/home';
  let stdout = await exec(['sh/list_snaps.sh', branch+suffix]);
  cache_snaps(step_name, branch, stdout);
  if (stdout !== null) last_mount = branch+suffix;
  else last_mount = undefined;
}

function cache_snaps(step_name, branch, stdout) {
  if (!stdout) {
    snaps[step_name][branch] = [];
    return;
  }
  let d = new Date();
  function conv(s, t) {
    d.setTime(t*1000);
    return [s, d.toLocaleString()];
  }
  try {
    snaps[step_name][branch] = stdout.trim().split('\n').map(row=>conv(...row.split('\t')));
  } catch(e) {
    console.log('cache_snaps() processing error: '+e);
    snaps[step_name][branch] = [];
  }
}

async function exec(args) {
  let resp = await request_mgr.send_request('exec', args);
  let pack = parse(resp);
  if (!session_ok(pack)) return null;
  update_expiry(pack);
  display_result(pack);
  if (pack.returncode != 0) {
    console.log('exec() error!\nargs: ['+args+']'
		+'\nreturncode:'+pack.returncode
		+'\nstderr:'+pack.stderr);
    return null;
  }
  return pack.stdout;
}

function populate_pane(pane, list, mark) {
  let content = '';
  for (let item of list) {
    content += elem_innerHTML(item, mark)
  }
  pane.innerHTML = content;
}


// See my comment in main.css over the input selector --
// better use a pure javascipt solution instead of relying on css
// for the radio input mess:
/*
function elem_innerHTML(pane_name, item) {
  return '<tr><td><label><input value="'+item[0]
    + '" name="'+pane_name
    + '" type="radio">'+item[0]+'</label></td><td>'+item[1]+'</td></tr>';
}
*/

function elem_innerHTML(item, mark) {
  return '<tr class="'+mark(item[0])+'" data-name="'+item[0]+'"><td>'+item[0]+'</td><td>'+item[1]+'</td></tr>';
}

function branch_pane_click() {
  return new Promise(res=>{
    branch_pane.onclick = function(e) {
      if (e.target.tagName == 'TD')
	res(['bp', e.target.parentElement.dataset.name]);
    };
  });
}

function snap_pane_click() {
  return new Promise(res=>{
    snap_pane.onclick = function(e) {
      if (e.target.tagName == 'TD')
	res(['sp', e.target.parentElement.dataset.name]);
    };
  });
}

function lbutton_click() {
  return new Promise(res=>{
    lbutton.onclick = function() {
      res(['lb', null]);
    };
  });
}

function rbutton_click() {
  return new Promise(res=>{
    rbutton.onclick = function() {
      res(['rb', null]);
    };
  });
}

async function handle_branch_selection(step_name, branch) {
  if (!selections[step_name] || branch != selections[step_name][0]) {
    selections[step_name] = [branch];
    style_disabled(rbutton);
    // avoid confusing the user while query is pending:
    snap_pane.innerHTML = lang.wait;
    timemap_mgr.unhighlight_snap_select(step_name);
    note_mgr.unset_selected(step_name);
    note_mgr.cancel();
  }
  style_selected_branch(branches, branch, branch_pane);
  if (!snaps[step_name][branch] || !snaps[step_name][branch].length)
    try {
      await query_snaps(step_name, branch);
    } catch(e) {
      on_error(e);
      return;
    }
  populate_pane(snap_pane, snaps[step_name][branch],
		branch==sd.rbp && step_name=='step1'?
		(s=>s==sd.rsp?'rsp':'') :
		(s=>''));
  timemap_mgr.draw_snaps(step_name, branch, snaps[step_name][branch]);
  timemap_mgr.highlight_branch_select(step_name, branch);
  timemap_mgr.highlight_branch_hover(step_name, branch); // draw again with updated y1
  if (selections[step_name][1]) {
    style_selected_snap(snaps[step_name][selections[step_name][0]],
			selections[step_name][1], snap_pane);
    timemap_mgr.highlight_snap_select(step_name, branch, selections[step_name][1]);
  }
}

function handle_snap_selection(step_name, snap) {
  selections[step_name][1] = snap;
  let branch = selections[step_name][0];
  style_selected_snap(snaps[step_name][branch], snap, snap_pane);
  timemap_mgr.highlight_snap_select(step_name, branch, snap);
  note_mgr.set_selected(step_name, branch, snap);
  style_enabled(rbutton);
}

// avoids new globals:
function make_styler(cls) {
  var last_tr;
  return function(list, item, pane){
    let i = list.findIndex(r=>r[0]==item);
    if (i == -1) return;
    let tr = pane.children[i];
    if (last_tr)
      last_tr.classList.remove(cls);
    last_tr = tr;
    tr.classList.add(cls);
  }
}

var style_selected_branch = make_styler('selected');
var style_selected_snap = make_styler('selected');

function check_step(step_name) {
  if (selections[step_name][0]==sd.csts) {
    alert(sd.csts+lang.illegal_branch);
    return false;
  } else {
    return true;
  }
}

async function step2() {
  prep_step({lbutton_text: lang.go_back,
	     rbutton_text: lang.go_forward,
	     message_multiline: false,
	     message_content: format_instr(lang.step2_instr),
	     display_hidden: false,
	     lbutton_hidden: false,
	     rbutton_enabled: false});

  if (!await init_state('step2', ...selections.step1)) return null;

  let source, arg;
  while (true) {
    [source, arg] = await Promise.race([branch_pane_click(),
					snap_pane_click(),
					lbutton_click(),
					rbutton_click()]);
    switch (source) {
    case 'sp':
      handle_snap_selection('step2', arg);
      break;
    case 'bp':
      await handle_branch_selection('step2', arg);
      break;
    case 'lb':
      return step1;
      break;
    case 'rb':
      if (selections.step2 && selections.step2[1] && check_step('step2'))
	return confirm_revert;
    }
  }
}

async function confirm_revert() {
  prep_step({lbutton_text: lang.go_back,
	     rbutton_text: lang.revert,
	     message_multiline: true,
	     message_content: format_confirm(lang.confirm),
	     display_hidden: true,
	     lbutton_hidden: false,
	     rbutton_enabled: true});

  let source, arg;
  while (true) {
    [source, arg] = await Promise.race([lbutton_click(),
					rbutton_click()]);
    switch (source) {
    case 'lb':
      return step2;
      break;
    case 'rb':
      return revert;
    }
  }
}

function format_confirm (msg) {
  let fmtstr = '<span class="selected">{0}</span>@<span class="selected">{1}</span>';
  let tspan = '<span>{0}</span>';
  return msg.dformat({
    step1snp: fmtstr.sformat(...selections.step1),
    step1time: tspan.sformat(get_creation('step1', ...selections.step1)),
    step2snp: fmtstr.sformat(...selections.step2),
    step2time: tspan.sformat(get_creation('step2', ...selections.step2))
  })
}

function get_creation(step_name, branch, snap) {
  let i = snaps[step_name][branch].findIndex(r=>r[0]==snap);
  return snaps[step_name][branch][i][1];
}

async function revert() {
  prep_step({lbutton_text: lang.restart,
	     rbutton_text: lang.reboot,
	     message_multiline: false,
	     message_content: lang.wait,
	     display_hidden: true,
	     lbutton_hidden: false,
	     rbutton_enabled: true});

  let r;
  try {
    r = await exec(['sh/revert.sh',
		    ...selections.step1,
		    ...selections.step2]);
  } catch(e) {
    on_error(e);
    return null;
  }
  if (r === null)
    message_div.innerHTML = '<p>{0}</p>'.sformat(lang.fail);
  else
    message_div.innerHTML = '<p>{0}</p>'.sformat(lang.success);
  
  // reset the cache in case step1 again:
  branches = undefined;
  snaps = undefined;
  sd = undefined;
  // also reset the timemaps
  timemap_mgr = undefined;

  let source, arg;
  while (true) {
    [source, arg] = await Promise.race([lbutton_click(),
					rbutton_click()]);
    switch (source) {
    case 'lb':
      return step1;
      break;
    case 'rb':
      return reboot;
    }
  }
}

async function reboot() {
  let r = await exec(['sh/reboot.sh']);
  if (r === null)
    alert(lang.not_rebooting);
  else
    alert(lang.rebooting);
  return null;
}

function display_result(pack) {
  returncode_disp.textContent = pack.returncode;
  stdout_disp.value = pack.stdout;
  stderr_disp.value = pack.stderr;
}


window.addEventListener('load',async function(){
  init_elements();
  if (!await init_session()) return;

  // No goto recursion free trick:
  // each step function returns the next step function to be called
  let next_step = await step1();
  while (next_step) {
    next_step = await next_step();
  }
});

/*
// doesn't work -- page navigation doesn't wait for async
window.addEventListener('beforeunload', async function(){
  await request_mgr.send_request('fini');
});
*/

// See:
// https://developer.mozilla.org/en-US/docs/Web/API/Navigator/sendBeacon
window.addEventListener('unload', function() {
  navigator.sendBeacon('http://127.0.0.1:8000', JSON.stringify({seq:seq,
								token:token,
								ts:0,
								dur:0,
								op:'fini',
								args:undefined
							       }));
});
