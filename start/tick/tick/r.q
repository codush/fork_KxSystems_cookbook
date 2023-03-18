/q tick/r.q [host]:port[:usr:pwd] [host]:port[:usr:pwd]
/2008.09.09 .k ->.q
/ 
/ refer to https://code.kx.com/q/wp/rt-tick/
\


/ The code simply checks the operating system, and if it is not Windows, the appropriate OS command is invoked to sleep for one second. This is required as the RDB will soon try to establish a connection to the TP and a non-Windows OS may need some time to register the RDB before such an interprocess communication (TCP/IP) connection can be established.
if[not "w"=first string .z.o;system "sleep 1"];

upd:insert;

/ get the ticker plant and history ports, defaults are 5010,5012
/ for .z.x:
/       > q trade.q foo bar -p 4000
/           .z.x 0 is "foo"
/           .z.x 1 is "bar"
.u.x:.z.x,(count .z.x)_(":5010";":5012");

/ end of day: save, clear, hdb reload
/ 代码解析
/   t:tables`.;                       Return a list of the names of all tables defined in the default namespace and assign to the local variable t. t will contain `trade and `quote in this case.
/   t@:where `g=attr each t@\:`sym;   This line obtains the subset of tables in t that have the grouped attribute on their sym column. This is done because later these tables will be emptied out and their attribute information will be lost. Therefore we store this attribute information now so the attributes can be re-applied after the clear out. As an aside, the g attribute of the sym column makes queries that filter on the sym column run faster.
/   .Q.hdpf[`$":",.u.x 1;`:.;x;`sym]  .Q.hdpf is a high-level function which saves all in-memory tables to disk in partitioned format, empties them out and then instructs the HDB to reload. Its arguments at runtime here will be:
/       - para 1	`:localhost:5002	location of HDB
/       - para 2	`:.	current working directory – root of on-disk partitioned database
/       - para 3	2014.08.23	input to .u.end as supplied by TP: the partition to write to
/       - para 4    `sym	column on which to sort/part the tables prior to persisting
/   @[;`sym;`g#] each t; This line applies the g attribute to the sym column of each table as previously discussed.
.u.end:{
    t:tables`.;
    t@:where `g=attr each t@\:`sym;
    .Q.hdpf[`$":",.u.x 1;`:.;x;`sym];
    @[;`sym;`g#] each t;
 };

/ init schema and sync up from log file;cd to hdb(so client save can run)4
/ This section defines an important function called .u.rep. This function is invoked at startup once the RDB has connected/subscribed to the TP.
/ 代码解析                                       https://code.kx.com/q/wp/rt-tick/#uend
/   (.[;();:;].)each x;                         This line just loops over the table name/empty table pairs and initializes these tables accordingly within the current working namespace (default namespace). Upon first iteration of the projection, the argument is the pair:
/   if[null first y;:()];                       The next line checks if no messages have been written to the TP logfile.If that is the case, the RDB is ready to go and the function returns (arbitrarily with an empty list). Otherwise, proceed to the next line
/   -11!y;                                      This line simply replays an appropriate number of messages from the start of the TP logfile. At which point, based upon the definition of upd as insert, the RDB’s trade and quote tables are now populated.
/   system "cd ",1_-10_string first reverse y   This changes the current working directory of the RDB to the root of the on-disk partitioned database. Therefore, when .Q.hdpf is invoked at EOD, the day’s records will be written to the correct place.
.u.rep:{
    (.[;();:;].)each x;
    if[null first y;:()];
    -11!y;
    system "cd ",1_-10_string first reverse y
 };
/ HARDCODE \cd if other than logdir/db

/ connect to ticker plant for (schema;(logcount;log))
/ The following section of code appears at the end of r.q and kicks the RDB into life:
/ 代码解析
/   hopen `$":",.u.x 0                  Reading this from the right, we obtain the location of the tickerplant process which is then passed into the hopen function, which returns a handle (connection) to the tickerplant. Through this handle, we then send a synchronous message to the tickerplant, telling it to do two things:
/   .u.sub[`;`]                         Subscribe to all tables and to all symbols. .u.sub is a binary function defined on the tickerplant. If passed null symbols (as is the case here), it will return a list of pairs (table name/empty table), consistent with the first argument to .u.rep as discussed previously. At this point the RDB is subscribed to all tables and to all symbols on the tickerplant and will therefore receive all intraday updates from the TP. The exact inner workings of .u.sub as defined on the TP are beyond the scope of this white paper.
/   .u `i`L                             Obtain name/location of TP logfile and number of messages written by TP to said logfile. The output of this is the list passed as second argument to .u.rep as previously discussed.
.u.rep .(hopen `$":",.u.x 0)"(.u.sub[`;`];`.u `i`L)";

