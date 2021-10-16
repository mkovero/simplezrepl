#!/bin/bash -x
# Too simple zfs snapshot backup script
# Stores snapshot data in sqlite db
# init-funtion needs to be run only once to setup the database.
# by Markus Kovero <mui@mui.fi>

DATE=`date +%d%m%Y-%H%M%S`
CONN="sqlite3 backup.db"
DATASETS=`$CONN "select dataset from dataset where enabled='1' and remote='1';"`

function init() {
	$CONN "drop table host;drop table dataset; drop table snapshot;"
	$CONN "create table host (id INTEGER PRIMARY KEY,user TEXT,address TEXT,port TEXT);"
	$CONN "create table dataset (id INTEGER PRIMARY KEY, pool TEXT, dataset TEXT, remote BOOL, host TEXT,enabled BOOL);"
	$CONN "create table snapshot (id INTEGER PRIMARY KEY,dataset TEXT,name TEXT,date TIMESTAMP DEFAULT CURRENT_TIMESTAMP, full BOOL, remoteok BOOL);"
	add_host admin nurr.hurr.org 6062
	add_dataset rpool atk.mui.fi nurr.hurr.org
        add_dataset rpool www.mui.fi nurr.hurr.org
}

function add_host() {
	slog "Adding host $2 with user $1 and port $3"
        $CONN "insert into host (user,address,port) values (\"$1\",\"$2\",\"$3\");"
}

function add_dataset() { 
       	slog "Adding dataset $2 in pool $1 with target remote host $3" 
	$CONN "insert into dataset (pool,dataset,host,remote,enabled) values (\"$1\",\"$2\",\"$3\",1,1);"
}

function slog() {
	echo $@
}

function remote() {
        user=`$CONN "select user from host where address = \"$1\""`
        port=`$CONN "select port from host where address = \"$1\""`
        ssh -l $user -p $port $@
}

function test_full() {
	remote $1 "ls /share/CE_CACHEDEV1_DATA/keskustietokone/$1.img.full.gz"
}

function create_snapshot() {
	slog "Creating snapshot $1@$DATE"
	( zfs snapshot rpool/$1@$DATE ) && ( $CONN "insert into snapshot (dataset,name,full,remoteok) values (\"$1\",\"$1@$DATE\",0,0);" )
}

# TODO: make remote to fetch destination host from db
function send_full() {
	slog "Sending full rpool/$LATEST_LOCAL"
	LATEST_LOCAL=`latest_local_snapshot $1`; (( zfs send -cv rpool/$LATEST_LOCAL | remote nurr.hurr.org "cat - > /share/CE_CACHEDEV1_DATA/keskustietokone/$1-$DATE.img.incr.gz" ) && \
		                ( $CONN "update snapshot set full=1, remoteok=1 where name = \"$LATEST_LOCAL\";" ))
}

function latest_local_snapshot() {
        $CONN "select name from snapshot where dataset = \"$1\" and remoteok = 0 ORDER BY date DESC LIMIT 1";
}

function latest_remote_snapshot() {
	$CONN "select name from snapshot where dataset = \"$1\" and remoteok = 1 ORDER BY date DESC LIMIT 1";
}

# TODO: make remote to fetch destination host from db
function send_incremental() {
        slogo "Sending incremental rpool/$LATEST_LOCAL"
        LATEST_REMOTE=`latest_remote_snapshot $1`; LATEST_LOCAL=`latest_local_snapshot $1`; if [[ ! -z $LATEST_REMOTE ]]; then (( zfs send -cvi rpool/$LATEST_REMOTE rpool/$LATEST_LOCAL | remote nurr.hurr.org "cat - > /share/CE_CACHEDEV1_DATA/keskustietokone/$1-$DATE.img.incr.gz" ) && \
		( $CONN "update snapshot set remoteok=1 where name = \"$LATEST_LOCAL\";" )) else slog "No full!"; send_full $1; fi;
}

for i in $DATASETS; do
	create_snapshot "$i"
	send_incremental "$i"
done
