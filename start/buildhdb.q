/ buildhdb.q
/ builds a historical trade/quote database
//
/ tables:
/ daily: date sym open high low close price size
/ depth: date time sym price size side ex
/ mas: sym name
/ nbbo: date time sym bid ask bsize asize
/ quote: date time sym bid ask bsize asize mode ex
/ trade: date time sym price size stop cond ex
//
/ trade, quote, nbbo are partitioned by date
/ round robin partition is optional
//
/ requires write permission in target directories

/ config
dst:`:start/db      / database root
dsp:""              / optional database segment root
dsx:5               / number of segments

bgn:2013.05.01      / begin, end
end:2013.05.31      / (only mon-fri used)
bgntm: 09:30:00.0   / exchange open time
endtm: 16:00:00.0   / exchange close time

/ approximate values:
nt:1000             / trades per stock per day
qpt:5               / quotes per trade
npt:3               / nbbo per trade
nl2:1000            / level II entries in day

\S 104831           / random seed
/ util

pi:acos -1
accum:{prds 1.0,-1 _ x}
int01:{(til x)%x-1}
limit:{(neg x)|x & y}
minmax:{(min x;max x)}
normalrand:{(cos 2 * pi * x ? 1f) * sqrt neg 2 * log x ? 1f}
rnd:{0.01*floor 0.5+x*100}
xrnd:{exp x * limit[2] normalrand y}
randomize:{value "\\S ",string "i"$0.8*.z.p%1000000000}
shiv:{(last x)&(first x)|asc x+-2+(count x)?5}
vol:{10+`int$x?90}
vol2:{x?100*1 1 1 1 2 2 3 4 5 8 10 15 20}

/ =========================================================
choleski:{
 n:count A:x+0.0;
 if[1>=n;:sqrt A];
 p:ceiling n%2;
 X:p#'p#A;
 Y:p _'p#A;
 Z:p _'p _A;
 T:(flip Y) mmu inv X;
 L0:n #' (choleski X) ,\: (n-1)#0.0;
 L1:choleski Z-T mmu Y;
 L0,(T mmu p#'L0),'L1}

/ =========================================================
/ paired correlation, matrix of variates, min 0.1 coeff
choleskicor:{
 x:"f"$x;y:"f"$y;
 n:count y;
 c:0.1|(n,n)#1.0,x,((n-2)#0.0),x;
 (choleski c) mmu y}

/ =========================================================
/ volume profile - random times, weighted toward ends
/ x=count
volprof:{
 p:1.75;
 c:floor x%3;
 b:(c?1.0) xexp p;
 e:2-(c?1.0) xexp p;
 m:(x-2*c)?1.0;
 {(neg count x)?x} m,0.5*b,e}


/ write[sa,"/trade/";t];
/ =========================================================
write:{
 t:.Q.en[dst] update sym:`p#sym from `sym xasc y;
 $[count dsp;
  (` sv dsp,(`$"d",string dspx),`$x) set t;             / ` sv https://code.kx.com/q/ref/sv/#filepath-components
  (` sv dst,`$x) set t];}               
/ symbol data for tick demo


/
3 cut：每3个元素为一组
sn的输出为一个nested list：
`AMZN;"Amazon.com, Inc."; 92;
`AMD;"ADVANCED MICRO DEVICES"; 33;
...
\
sn:3 cut (                          
 `AMZN;"Amazon.com, Inc."; 92;
 `AMD;"ADVANCED MICRO DEVICES"; 33;
 `AIG;"AMERICAN INTL GROUP INC"; 27;
 `AAPL;"APPLE INC COM STK"; 84;
 `BAC;"Bank of America Corporation";36;
 `CCL;"Carnival Corporation & plc";8;
 `DELL;"DELL INC";12;
 `DOW;"DOW CHEMICAL CO";20;
 `GOOG;"GOOGLE INC CLASS A";72;
 `HPQ;"HEWLETT-PACKARD CO";36;
 `INTC;"INTEL CORP";51;
 `IBM;"INTL BUSINESS MACHINES CORP";42;
 `META;"Meta Platforms, Inc.";90;
 `MSFT;"MICROSOFT CORP";9;
 `NIO;"NIO Inc.";29;
 `NVDA;"NVIDIA Corporation";132;
 `ORCL;"ORACLE CORPORATION";35;
 `PEP;"PEPSICO INC";22;
 `PRU;"PRUDENTIAL FINANCIAL INC.";59;
 `SNAP;"Snap Inc.";9;
 `SBUX;"STARBUCKS CORPORATION";5;
 `SOFI;"SoFi Technologies, Inc.";214;
 `T;"AT&T Inc.";18;
 `TSLA;"Tesla, Inc.";63;
 `TWTR;"Twitter, Inc.";53;
 `TXN;"TEXAS INSTRUMENTS";18;
 `XPEV;"XPeng Inc."; 6)

s:first each sn         / =`AMZN`AMD`AIG`AAPL`BAC...       相当于@[;0] each sn
n:@[;1] each sn         / ="Amazon..."  "ADVANCED..."  "AMERICAN..." ...
p:last each sn          / =92  33  27...                   相当于@[;2] each sn
m:" ABHILNORYZ"         / mode  
c:" 89ABCEGJKLNOPRTWZ"  / cond
e:"NONNONONNNNOONO"     / ex
/ gen

vex:1.0005         / average volume growth per day
ccf:0.5            / correlation coefficient

/ =========================================================
/ qx index, qb/qbb/qa/qba margins, qp price, qn position
batch:{[x;len]
  p0:prices[;x];
  p1:prices[;x+1];
  d:xrnd[0.0003] len;
  qx::len?cnt;
  qb::rnd len?1.0;
  qa::rnd len?1.0;
  qbb::qb & -0.02 + rnd len?1.0;
  qba::qa & -0.02 + rnd len?1.0;
  n:where each qx=/:til cnt;
  s:p0*accum each d n;
  s:s + (p1-last each s)*{int01 count x} each s;
  qp::len#0.0;
  (qp n):rnd s;
  qn::0}

/ =========================================================
/ constrained random walk
/ x max movement per step
/ y max movement at any time (above/below)
/ z number of steps
cgen:{
  m:reciprocal y;                                     / https://code.kx.com/q/ref/reciprocal/
  while[any (m>p) or y<p:prds 1.0+x*normalrand z];
  p}

/ =========================================================
getdates:{
 b:x 0;
 e:x 1;
 d:b + til 1 + e-b;                         / 2013.05.01 2013.05.02 2013.05.03 2013.05.04 2013.05.05 2013.05.06 2013.05.07 ..
 d:d where 5> d-`week$d;                    / `week$d是转化为周。 5>d-`week$d是寻找工作日周一-周五
 hols:101 404 612 701 1001 1013 1225 1226;  / holidays
 d where not ((`dd$d)+100*`mm$d) in hols}   / dd$: 转化为日期的日https://code.kx.com/q/ref/cast/#temporal

/ =========================================================
makeprices:{
 r:cgen[0.0375;3] each cnt#nd;
 r:choleskicor[ccf;1,'r];
 (p % first each r) * r *\: 1.1 xexp int01 nd+1}

/ =========================================================
/ day volumes
makevolumes:{                                     /????
 v:cgen[0.03;3;x];
 a:vex xexp neg x;
 0.05|2&v*a+((reciprocal last v)-a)*int01 x}
/ main

cnt:count s                       / = 27
dates:getdates bgn,end            / = 2013.05.01 2013.05.02 2013.05.03 2013.05.06 2013.05.07 .. 
nd:count dates                    / = 20
td:([]date:();sym:();open:();high:();low:();close:();price:();size:())

prices:makeprices nd + 1
volumes:floor (cnt*nt*qpt+npt) * makevolumes  /???? floor (27*1000*5*3) * 

dspx:0
patt:{update sym:`p#sym from `sym`time xasc x}

day:{
  len:volumes x;
  batch[x;len];
  sa:string dx:dates x;
  r:asc bgntm+floor (endtm-bgntm)*volprof count qx;
  cx:len?qpt+npt;
  cn:count n:where cx=0;
  sp:1=cn?20;
  t:([]sym:s qx n;time:shiv r n;price:qp n;size:vol cn;stop:sp;cond:cn?c;ex:e qx n);
  tx:select open:first price,high:max price,low:min price,close:last price,price:sum price*size,sum size by sym from t;
  td,:([]date:(count s)#dx)+0!tx;
  cn:count n:where cx<qpt;
  q:([]sym:s qx n;time:r n;bid:(qp-qb)n;ask:(qp+qa)n;bsize:vol cn;asize:vol cn;mode:cn?m;ex:e qx n);
  cn:count n:where cx>=qpt;
  b:([]sym:s qx n;time:r n;bid:(qp-qbb)n;ask:(qp+qba)n;bsize:vol cn;asize:vol cn);
  write[sa,"/trade/";t];
  write[sa,"/quote/";q];
  write[sa,"/nbbo/";b];
  dspx::(dspx+1) mod dsx;}

day each til nd;

{
  batch[nd-1;nl2];
  r:asc bgntm+(count qx)?endtm-bgntm;
  m:nl2?2;
  t:([]date:last dates;time:r;sym:s qx;price:qp+qa*-1 1 m;size:vol2 nl2;side:"BS" m;ex:e qx);
  (` sv dst,`depth) set .Q.en[dst] t;}[];

(` sv dst,`daily) set .Q.en[dst] td;                       / ` sv https://code.kx.com/q/ref/sv/#filepath-components
(` sv dst,`mas) set .Q.en[dst] ([]sym:s;name:n);
if[count dsp;(` sv dst,`par.txt) 0: ((1_string dsp),"/d") ,/: string til dsx];
