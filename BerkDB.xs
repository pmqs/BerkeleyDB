/*
 
 BerkDB.xs -- Perl 5 interface to Berkeley DB version 2
 
 written by Paul Marquess (pmarquess@bfsec.bt.co.uk)

 SCCS: 1.6, 10/23/97  

 All comments/suggestions/problems are welcome
 
     Copyright (c) 1997 Paul Marquess. All rights reserved.
     This program is free software; you can redistribute it and/or
     modify it under the same terms as Perl itself.
 
 Changes:
        0.01 -  First Alpha Release
 
*/



#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <db.h>
#ifdef __cplusplus
}
#endif

/* #define TRACE */


typedef struct {
        DBTYPE  	type ;
	SV *		ref2env ;
        DB *    	dbp ;
	SV *		ref2db ;
        SV *    	compare ;
        SV *    	prefix ;
        SV *   	 	hash ;
	int		Status ;
        DB_INFO *	info ;
        DBC *   	cursor ;
	DB_TXN *	txn ;
	u_int32_t	partial ;
	u_int32_t	dlen ;
	u_int32_t	doff ;
        } BerkDB_type;

typedef struct {
	int		Status ;
	/* char		ErrBuff[1000] ; */
	SV *		ErrPrefix ;
	DB_ENV		Env ;
	} BerkDB_ENV_type ;

typedef BerkDB_ENV_type *	BerkDB__Env ;
typedef BerkDB_type * 		BerkDB ;
typedef BerkDB_type * 		BerkDB__Common ;
typedef BerkDB_type * 		BerkDB__Hash ;
typedef BerkDB_type * 		BerkDB__Btree ;
typedef BerkDB_type * 		BerkDB__Recno ;
typedef BerkDB_type   		BerkDB__Cursor_type ;
typedef BerkDB_type * 		BerkDB__Cursor ;
typedef DB_TXNMGR *   		BerkDB__TxnMgr ;
typedef DB_TXN *      		BerkDB__Txn ;
typedef DB_LOG *      		BerkDB__Log ;
typedef DB_LOCKTAB *  		BerkDB__Lock ;
typedef DBT 			DBTKEY ;
typedef DBT 			DBTKEY_B ;
typedef DBT 			DBTVALUE ;
typedef void *	      		PV_or_NULL ;
typedef PerlIO *      		IO_or_NULL ;

#ifdef TRACE
#define Trace(x)	printf x 
#else
#define Trace(x)	
#endif

#define ERR_BUFF "BerkDB::Error" 

#define ZMALLOC(to, typ) ((to = (typ *)safemalloc(sizeof(typ))), \
				Zero(to,1,typ))

#define SetValue_iv(i, k) if ((sv = readHash(hash, k)) && sv != &sv_undef) \
				i = SvIV(sv)
#define SetValue_io(i, k) if ((sv = readHash(hash, k)) && sv != &sv_undef) \
				i = IoOFP(sv_2io(sv))
#define SetValue_sv(i, k) if ((sv = readHash(hash, k)) && sv != &sv_undef) \
				i = sv
#define SetValue_pv(i, k,t) if ((sv = readHash(hash, k)) && sv != &sv_undef) \
				i = (t)SvPV(sv,na)
#define SetValue_pvx(i, k, t) if ((sv = readHash(hash, k)) && sv != &sv_undef) \
				i = (t)SvPVX(sv)
#define SetValue_ov(i,k,t) if ((sv = readHash(hash, k)) && sv != &sv_undef) {\
				IV tmp = SvIV((SV*)SvRV(sv));	\
				i = (t) tmp ;			\
			  }

#define OutputValue(arg, name)                                  \
        { if (RETVAL == 0) {                                    \
              sv_setpvn(arg, name.data, name.size) ;            \
          }                                                     \
        }

#define OutputKey(arg, name)                                    \
        { if (RETVAL == 0) 					\
          {                                                     \
                if (db->type != DB_RECNO) {                     \
                    sv_setpvn(arg, name.data, name.size);       \
                }                                               \
                else                                            \
                    sv_setiv(arg, (I32)*(I32*)name.data - 1);   \
          }                                                     \
        }

#define OutputKey_B(arg, name)                                  \
        { if (RETVAL == 0) 					\
          {                                                     \
                if (db->type == DB_RECNO || 			\
		(db->type == DB_BTREE && flags & DB_GET_RECNO)){\
                    sv_setiv(arg, (I32)*(I32*)name.data - 1);   \
                }                                               \
                else {                                          \
                    sv_setpvn(arg, name.data, name.size);       \
                }                                               \
          }                                                     \
        }

#define SetPartial(data) 		\
	data.flags = db->partial ;	\
	data.dlen  = db->dlen ;		\
	data.doff  = db->doff ;	

/* Internal Global Data */
static db_recno_t Value ;
static db_recno_t zero = 0 ;
static BerkDB	CurrentDB ;
static DBTKEY	empty ;
static char	ErrBuff[1000] ;


static I32
GetArrayLength(db)
BerkDB db ;
{
    DBT		key ;
    DBT		value ;
    int		RETVAL ;

    key.flags = 0 ;
    value.flags = 0 ;
    RETVAL = (db->cursor->c_get)(db->cursor, &key, &value, DB_LAST) ;
    if (RETVAL == 0)
        RETVAL = *(I32 *)key.data ;
    else /* No key means empty file */
        RETVAL = 0 ;

    Trace(("GetArrayLength got %d\n", RETVAL)) ;
    return ((I32)RETVAL) ;
}

static db_recno_t
GetRecnoKey(db, value)
BerkDB  db ;
I32      value ;
{
    Trace(("GetRecnoKey start value = %d\n", value)) ;
    if (db->type == DB_RECNO && value < 0) {
	/* Get the length of the array */
	I32 length = GetArrayLength(db) ;

	/* check for attempt to write before start of array */
	if (length + value + 1 <= 0)
	    croak("Modification of non-creatable array value attempted, subscript %ld", (long)value) ;

	value = length + value + 1 ;
    }
    else
        ++ value ;

    Trace(("GetRecnoKey end value = %d\n", value)) ;

    return value ;
}


static int
btree_compare(key1, key2)
const DBT * key1 ;
const DBT * key2 ;
{
    dSP ;
    void * data1, * data2 ;
    int retval ;
    int count ;
    
    data1 = key1->data ;
    data2 = key2->data ;

    /* As newSVpv will assume that the data pointer is a null terminated C 
       string if the size parameter is 0, make sure that data points to an 
       empty string if the length is 0
    */
    if (key1->size == 0)
        data1 = "" ; 
    if (key2->size == 0)
        data2 = "" ;

    ENTER ;
    SAVETMPS;

    PUSHMARK(sp) ;
    EXTEND(sp,2) ;
    PUSHs(sv_2mortal(newSVpv(data1,key1->size)));
    PUSHs(sv_2mortal(newSVpv(data2,key2->size)));
    PUTBACK ;

    count = perl_call_sv(CurrentDB->compare, G_SCALAR); 

    SPAGAIN ;

    if (count != 1)
        croak ("BerkDB btree_compare: expected 1 return value from compare sub, got %d\n", count) ;

    retval = POPi ;

    PUTBACK ;
    FREETMPS ;
    LEAVE ;
    return (retval) ;

}

static size_t
btree_prefix(key1, key2)
const DBT * key1 ;
const DBT * key2 ;
{
    dSP ;
    void * data1, * data2 ;
    int retval ;
    int count ;
    
    data1 = key1->data ;
    data2 = key2->data ;

    /* As newSVpv will assume that the data pointer is a null terminated C 
       string if the size parameter is 0, make sure that data points to an 
       empty string if the length is 0
    */
    if (key1->size == 0)
        data1 = "" ;
    if (key2->size == 0)
        data2 = "" ;

    ENTER ;
    SAVETMPS;

    PUSHMARK(sp) ;
    EXTEND(sp,2) ;
    PUSHs(sv_2mortal(newSVpv(data1,key1->size)));
    PUSHs(sv_2mortal(newSVpv(data2,key2->size)));
    PUTBACK ;

    count = perl_call_sv(CurrentDB->prefix, G_SCALAR); 

    SPAGAIN ;

    if (count != 1)
        croak ("BerkDB btree_prefix: expected 1 return value from prefix sub, got %d\n", count) ;
 
    retval = POPi ;
 
    PUTBACK ;
    FREETMPS ;
    LEAVE ;

    return (retval) ;
}

static u_int32_t
hash_cb(data, size)
const void * data ;
size_t size ;
{
    dSP ;
    int retval ;
    int count ;

    if (size == 0)
        data = "" ;

    ENTER ;
    SAVETMPS;

    PUSHMARK(sp) ;

    XPUSHs(sv_2mortal(newSVpv((char*)data,size)));
    PUTBACK ;

    count = perl_call_sv(CurrentDB->hash, G_SCALAR); 

    SPAGAIN ;

    if (count != 1)
        croak ("BerkDB hash_cb: expected 1 return value from hash sub, got %d\n", count) ;

    retval = POPi ;

    PUTBACK ;
    FREETMPS ;
    LEAVE ;

    return (retval) ;
}

static void
db_errcall_cb(db_errpfx, buffer)
const char *db_errpfx; 
char *buffer ;
{
#if 0

    if (db_errpfx == NULL) 
	db_errpfx = "" ;
    if (buffer == NULL ) 
	buffer = "" ;
    ErrBuff[0] = '\0'; 
    if (strlen(db_errpfx) + strlen(buffer) + 3 <= 1000) {
	if (*db_errpfx != '\0') {
	    strcat(ErrBuff, db_errpfx) ;
	    strcat(ErrBuff, ": ") ;
	}
	strcat(ErrBuff, buffer) ;
    }

#endif

    SV * sv = perl_get_sv(ERR_BUFF, FALSE) ;
    if (db_errpfx)
	sv_setpvf(sv, "%s: %s", db_errpfx, buffer) ;
    else
        sv_setpv(sv, buffer) ;
}

static SV *
readHash(hash, key)
HV * hash ;
char * key ;
{
    SV **       svp;
    svp = hv_fetch(hash, key, strlen(key), FALSE);
    if (svp && SvOK(*svp))
        return *svp ;
    return NULL ;
}

static void
hv_store_iv(hash, key, value)
HV * hash;
char * key;
int value ;
{
    hv_store(hash, key, strlen(key), newSViv(value), 0);
}

static BerkDB
my_db_open(db, ref, dbenv, file, type, flags, mode, info)
BerkDB		db ;
SV *		ref ;
BerkDB__Env	dbenv ;
const char *	file;
DBTYPE		type;
int		flags;
int		mode;
DB_INFO * 	info ;
{
    DB_ENV *	env    = NULL ;
    BerkDB     	RETVAL = NULL ;
    DB *	dbp ;
    int		Status ;

    Trace(("_db_open(dbenv[%lu] file[%s] type[%d] flags[%d] mode[%d]\n", 
		dbenv, file, type, flags, mode)) ;

    if (dbenv) 
	env = &dbenv->Env ;

    if ((Status = db_open(file, type, flags, mode, env, info, &dbp)) == 0) {
	if (dbenv) 
	    dbenv->Status = Status ;
	RETVAL = db ;
	RETVAL->dbp  = dbp ;
    	RETVAL->type = type ;
	if (ref) 
	    RETVAL->ref2env = newRV(ref) ;

    }
    else { 
	Trace(("status = %d\n", Status)) ; 
    }

    return RETVAL ;
}


static int
not_here(s)
char *s;
{
    croak("%s not implemented on this architecture", s);
    return -1;
}




static double
constant(name, arg)
char *name;
int arg;
{
    errno = 0;
    switch (*name) {
    case 'A':
	break;
    case 'B':
	break;
    case 'C':
	break;
    case 'D':
	if (strEQ(name, "DBM_INSERT"))
#ifdef DBM_INSERT
	    return DBM_INSERT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DBM_REPLACE"))
#ifdef DBM_REPLACE
	    return DBM_REPLACE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DBM_SUFFIX"))
#ifdef DBM_SUFFIX
	    return DBM_SUFFIX;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AFTER"))
#ifdef DB_AFTER
	    return DB_AFTER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_DUP"))
#ifdef DB_AM_DUP
	    return DB_AM_DUP;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_INMEM"))
#ifdef DB_AM_INMEM
	    return DB_AM_INMEM;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_LOCKING"))
#ifdef DB_AM_LOCKING
	    return DB_AM_LOCKING;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_LOGGING"))
#ifdef DB_AM_LOGGING
	    return DB_AM_LOGGING;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_MLOCAL"))
#ifdef DB_AM_MLOCAL
	    return DB_AM_MLOCAL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_PGDEF"))
#ifdef DB_AM_PGDEF
	    return DB_AM_PGDEF;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_RDONLY"))
#ifdef DB_AM_RDONLY
	    return DB_AM_RDONLY;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_RECOVER"))
#ifdef DB_AM_RECOVER
	    return DB_AM_RECOVER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_SWAP"))
#ifdef DB_AM_SWAP
	    return DB_AM_SWAP;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_AM_THREAD"))
#ifdef DB_AM_THREAD
	    return DB_AM_THREAD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_APPEND"))
#ifdef DB_APPEND
	    return DB_APPEND;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_ARCH_ABS"))
#ifdef DB_ARCH_ABS
	    return DB_ARCH_ABS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_ARCH_DATA"))
#ifdef DB_ARCH_DATA
	    return DB_ARCH_DATA;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_ARCH_LOG"))
#ifdef DB_ARCH_LOG
	    return DB_ARCH_LOG;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_BEFORE"))
#ifdef DB_BEFORE
	    return DB_BEFORE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_BTREEMAGIC"))
#ifdef DB_BTREEMAGIC
	    return DB_BTREEMAGIC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_BTREEOLDVER"))
#ifdef DB_BTREEOLDVER
	    return DB_BTREEOLDVER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_BTREEVERSION"))
#ifdef DB_BTREEVERSION
	    return DB_BTREEVERSION;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_BT_RECNUM"))
#ifdef DB_BT_RECNUM
	    return DB_BT_RECNUM;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_CHECKPOINT"))
#ifdef DB_CHECKPOINT
	    return DB_CHECKPOINT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_CREATE"))
#ifdef DB_CREATE
	    return DB_CREATE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_CURRENT"))
#ifdef DB_CURRENT
	    return DB_CURRENT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_DBT_INTERNAL"))
#ifdef DB_DBT_INTERNAL
	    return DB_DBT_INTERNAL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_DBT_MALLOC"))
#ifdef DB_DBT_MALLOC
	    return DB_DBT_MALLOC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_DBT_PARTIAL"))
#ifdef DB_DBT_PARTIAL
	    return DB_DBT_PARTIAL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_DBT_USERMEM"))
#ifdef DB_DBT_USERMEM
	    return DB_DBT_USERMEM;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_DELETED"))
#ifdef DB_DELETED
	    return DB_DELETED;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_DELIMITER"))
#ifdef DB_DELIMITER
	    return DB_DELIMITER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_DUP"))
#ifdef DB_DUP
	    return DB_DUP;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_ENV_APPINIT"))
#ifdef DB_ENV_APPINIT
	    return DB_ENV_APPINIT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_ENV_STANDALONE"))
#ifdef DB_ENV_STANDALONE
	    return DB_ENV_STANDALONE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_ENV_THREAD"))
#ifdef DB_ENV_THREAD
	    return DB_ENV_THREAD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_EXCL"))
#ifdef DB_EXCL
	    return DB_EXCL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_FILE_ID_LEN"))
#ifdef DB_FILE_ID_LEN
	    return DB_FILE_ID_LEN;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_FIRST"))
#ifdef DB_FIRST
	    return DB_FIRST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_FIXEDLEN"))
#ifdef DB_FIXEDLEN
	    return DB_FIXEDLEN;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_FLUSH"))
#ifdef DB_FLUSH
	    return DB_FLUSH;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_GET_RECNO"))
#ifdef DB_GET_RECNO
	    return DB_GET_RECNO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_HASHMAGIC"))
#ifdef DB_HASHMAGIC
	    return DB_HASHMAGIC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_HASHOLDVER"))
#ifdef DB_HASHOLDVER
	    return DB_HASHOLDVER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_HASHVERSION"))
#ifdef DB_HASHVERSION
	    return DB_HASHVERSION;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_HS_DIRTYMETA"))
#ifdef DB_HS_DIRTYMETA
	    return DB_HS_DIRTYMETA;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_INCOMPLETE"))
#ifdef DB_INCOMPLETE
	    return DB_INCOMPLETE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_INIT_LOCK"))
#ifdef DB_INIT_LOCK
	    return DB_INIT_LOCK;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_INIT_LOG"))
#ifdef DB_INIT_LOG
	    return DB_INIT_LOG;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_INIT_MPOOL"))
#ifdef DB_INIT_MPOOL
	    return DB_INIT_MPOOL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_INIT_TXN"))
#ifdef DB_INIT_TXN
	    return DB_INIT_TXN;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_KEYEMPTY"))
#ifdef DB_KEYEMPTY
	    return DB_KEYEMPTY;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_KEYEXIST"))
#ifdef DB_KEYEXIST
	    return DB_KEYEXIST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_KEYFIRST"))
#ifdef DB_KEYFIRST
	    return DB_KEYFIRST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_KEYLAST"))
#ifdef DB_KEYLAST
	    return DB_KEYLAST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LAST"))
#ifdef DB_LAST
	    return DB_LAST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCKMAGIC"))
#ifdef DB_LOCKMAGIC
	    return DB_LOCKMAGIC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCKVERSION"))
#ifdef DB_LOCKVERSION
	    return DB_LOCKVERSION;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_CONFLICT"))
#ifdef DB_LOCK_CONFLICT
	    return DB_LOCK_CONFLICT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_DEADLOCK"))
#ifdef DB_LOCK_DEADLOCK
	    return DB_LOCK_DEADLOCK;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_DEFAULT"))
#ifdef DB_LOCK_DEFAULT
	    return DB_LOCK_DEFAULT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_NORUN"))
#ifdef DB_LOCK_NORUN
	    return DB_LOCK_NORUN;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_NOTGRANTED"))
#ifdef DB_LOCK_NOTGRANTED
	    return DB_LOCK_NOTGRANTED;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_NOTHELD"))
#ifdef DB_LOCK_NOTHELD
	    return DB_LOCK_NOTHELD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_NOWAIT"))
#ifdef DB_LOCK_NOWAIT
	    return DB_LOCK_NOWAIT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_OLDEST"))
#ifdef DB_LOCK_OLDEST
	    return DB_LOCK_OLDEST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_RANDOM"))
#ifdef DB_LOCK_RANDOM
	    return DB_LOCK_RANDOM;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_RIW_N"))
#ifdef DB_LOCK_RIW_N
	    return DB_LOCK_RIW_N;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_RW_N"))
#ifdef DB_LOCK_RW_N
	    return DB_LOCK_RW_N;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOCK_YOUNGEST"))
#ifdef DB_LOCK_YOUNGEST
	    return DB_LOCK_YOUNGEST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOGMAGIC"))
#ifdef DB_LOGMAGIC
	    return DB_LOGMAGIC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOGOLDVER"))
#ifdef DB_LOGOLDVER
	    return DB_LOGOLDVER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_LOGVERSION"))
#ifdef DB_LOGVERSION
	    return DB_LOGVERSION;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MAX_PAGES"))
#ifdef DB_MAX_PAGES
	    return (unsigned)DB_MAX_PAGES;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MAX_RECORDS"))
#ifdef DB_MAX_RECORDS
	    return (unsigned)DB_MAX_RECORDS;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MPOOL_CLEAN"))
#ifdef DB_MPOOL_CLEAN
	    return DB_MPOOL_CLEAN;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MPOOL_CREATE"))
#ifdef DB_MPOOL_CREATE
	    return DB_MPOOL_CREATE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MPOOL_DIRTY"))
#ifdef DB_MPOOL_DIRTY
	    return DB_MPOOL_DIRTY;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MPOOL_DISCARD"))
#ifdef DB_MPOOL_DISCARD
	    return DB_MPOOL_DISCARD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MPOOL_LAST"))
#ifdef DB_MPOOL_LAST
	    return DB_MPOOL_LAST;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MPOOL_NEW"))
#ifdef DB_MPOOL_NEW
	    return DB_MPOOL_NEW;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MPOOL_PRIVATE"))
#ifdef DB_MPOOL_PRIVATE
	    return DB_MPOOL_PRIVATE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_MUTEXDEBUG"))
#ifdef DB_MUTEXDEBUG
	    return DB_MUTEXDEBUG;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_NEEDSPLIT"))
#ifdef DB_NEEDSPLIT
	    return DB_NEEDSPLIT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_NEXT"))
#ifdef DB_NEXT
	    return DB_NEXT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_NOMMAP"))
#ifdef DB_NOMMAP
	    return DB_NOMMAP;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_NOOVERWRITE"))
#ifdef DB_NOOVERWRITE
	    return DB_NOOVERWRITE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_NOSYNC"))
#ifdef DB_NOSYNC
	    return DB_NOSYNC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_NOTFOUND"))
#ifdef DB_NOTFOUND
	    return DB_NOTFOUND;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_PAD"))
#ifdef DB_PAD
	    return DB_PAD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_PREV"))
#ifdef DB_PREV
	    return DB_PREV;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RDONLY"))
#ifdef DB_RDONLY
	    return DB_RDONLY;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RECNUM"))
#ifdef DB_RECNUM
	    return DB_RECNUM;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RECORDCOUNT"))
#ifdef DB_RECORDCOUNT
	    return DB_RECORDCOUNT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RECOVER"))
#ifdef DB_RECOVER
	    return DB_RECOVER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RECOVER_FATAL"))
#ifdef DB_RECOVER_FATAL
	    return DB_RECOVER_FATAL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_REGISTERED"))
#ifdef DB_REGISTERED
	    return DB_REGISTERED;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RENUMBER"))
#ifdef DB_RENUMBER
	    return DB_RENUMBER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RE_DELIMITER"))
#ifdef DB_RE_DELIMITER
	    return DB_RE_DELIMITER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RE_FIXEDLEN"))
#ifdef DB_RE_FIXEDLEN
	    return DB_RE_FIXEDLEN;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RE_PAD"))
#ifdef DB_RE_PAD
	    return DB_RE_PAD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RE_RENUMBER"))
#ifdef DB_RE_RENUMBER
	    return DB_RE_RENUMBER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RE_SNAPSHOT"))
#ifdef DB_RE_SNAPSHOT
	    return DB_RE_SNAPSHOT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_SEQUENTIAL"))
#ifdef DB_SEQUENTIAL
	    return DB_SEQUENTIAL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_SET"))
#ifdef DB_SET
	    return DB_SET;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_SET_RANGE"))
#ifdef DB_SET_RANGE
	    return DB_SET_RANGE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_SET_RECNO"))
#ifdef DB_SET_RECNO
	    return DB_SET_RECNO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_SNAPSHOT"))
#ifdef DB_SNAPSHOT
	    return DB_SNAPSHOT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_SWAPBYTES"))
#ifdef DB_SWAPBYTES
	    return DB_SWAPBYTES;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TEMPORARY"))
#ifdef DB_TEMPORARY
	    return DB_TEMPORARY;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_THREAD"))
#ifdef DB_THREAD
	    return DB_THREAD;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TRUNCATE"))
#ifdef DB_TRUNCATE
	    return DB_TRUNCATE;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXNMAGIC"))
#ifdef DB_TXNMAGIC
	    return DB_TXNMAGIC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXNVERSION"))
#ifdef DB_TXNVERSION
	    return DB_TXNVERSION;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_BACKWARD_ROLL"))
#ifdef DB_TXN_BACKWARD_ROLL
	    return DB_TXN_BACKWARD_ROLL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_CKP"))
#ifdef DB_TXN_CKP
	    return DB_TXN_CKP;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_FORWARD_ROLL"))
#ifdef DB_TXN_FORWARD_ROLL
	    return DB_TXN_FORWARD_ROLL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_LOCK_2PL"))
#ifdef DB_TXN_LOCK_2PL
	    return DB_TXN_LOCK_2PL;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_LOCK_MASK"))
#ifdef DB_TXN_LOCK_MASK
	    return DB_TXN_LOCK_MASK;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_LOCK_OPTIMISTIC"))
#ifdef DB_TXN_LOCK_OPTIMISTIC
	    return DB_TXN_LOCK_OPTIMISTIC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_LOG_MASK"))
#ifdef DB_TXN_LOG_MASK
	    return DB_TXN_LOG_MASK;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_LOG_REDO"))
#ifdef DB_TXN_LOG_REDO
	    return DB_TXN_LOG_REDO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_LOG_UNDO"))
#ifdef DB_TXN_LOG_UNDO
	    return DB_TXN_LOG_UNDO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_LOG_UNDOREDO"))
#ifdef DB_TXN_LOG_UNDOREDO
	    return DB_TXN_LOG_UNDOREDO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_NOSYNC"))
#ifdef DB_TXN_NOSYNC
	    return DB_TXN_NOSYNC;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_OPENFILES"))
#ifdef DB_TXN_OPENFILES
	    return DB_TXN_OPENFILES;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_REDO"))
#ifdef DB_TXN_REDO
	    return DB_TXN_REDO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_TXN_UNDO"))
#ifdef DB_TXN_UNDO
	    return DB_TXN_UNDO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_USE_ENVIRON"))
#ifdef DB_USE_ENVIRON
	    return DB_USE_ENVIRON;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_USE_ENVIRON_ROOT"))
#ifdef DB_USE_ENVIRON_ROOT
	    return DB_USE_ENVIRON_ROOT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_VERSION_MAJOR"))
#ifdef DB_VERSION_MAJOR
	    return DB_VERSION_MAJOR;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_VERSION_MINOR"))
#ifdef DB_VERSION_MINOR
	    return DB_VERSION_MINOR;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_VERSION_PATCH"))
#ifdef DB_VERSION_PATCH
	    return DB_VERSION_PATCH;
#else
	    goto not_there;
#endif
	break;
    case 'E':
	break;
    case 'F':
	break;
    case 'G':
	break;
    case 'H':
	break;
    case 'I':
	break;
    case 'J':
	break;
    case 'K':
	break;
    case 'L':
	break;
    case 'M':
	break;
    case 'N':
	break;
    case 'O':
	break;
    case 'P':
	break;
    case 'Q':
	break;
    case 'R':
	break;
    case 'S':
	break;
    case 'T':
	break;
    case 'U':
	break;
    case 'V':
	break;
    case 'W':
	break;
    case 'X':
	break;
    case 'Y':
	break;
    case 'Z':
	break;
    case 'a':
	break;
    case 'b':
	break;
    case 'c':
	break;
    case 'd':
	break;
    case 'e':
	break;
    case 'f':
	break;
    case 'g':
	break;
    case 'h':
	break;
    case 'i':
	break;
    case 'j':
	break;
    case 'k':
	break;
    case 'l':
	break;
    case 'm':
	break;
    case 'n':
	break;
    case 'o':
	break;
    case 'p':
	break;
    case 'q':
	break;
    case 'r':
	break;
    case 's':
	break;
    case 't':
	break;
    case 'u':
	break;
    case 'v':
	break;
    case 'w':
	break;
    case 'x':
	break;
    case 'y':
	break;
    case 'z':
	break;
    }
    errno = EINVAL;
    return 0;

not_there:
    errno = ENOENT;
    return 0;
}


MODULE = BerkDB		PACKAGE = BerkDB	PREFIX = env_

char *
DB_VERSION_STRING()
	CODE:
	  RETVAL = DB_VERSION_STRING ;
	OUTPUT:
	  RETVAL


double
constant(name,arg)
	char *		name
	int		arg

#define env_db_version(maj, min, patch) 	db_version(&maj, &min, &patch)
char *
env_db_version(maj, min, patch)
	int  maj
	int  min
	int  patch
	OUTPUT:
	  RETVAL
	  maj
	  min
	  patch


MODULE = BerkDB::Env		PACKAGE = BerkDB::Env PREFIX = env_


BerkDB::Env
_db_appinit(ref)
	SV * 		ref
        BerkDB__Env 	RETVAL = NULL ;
	CODE:
	{
	    HV *	hash ;
	    SV *	sv ;
	    char *	home = NULL ;
	    char **	config = NULL ;
	    int		flags = 0 ;
	    SV *	errprefix = NULL;
	    FILE *	handle = NULL ;
	    int status ;

	    Trace(("in _db_appinit\n")) ;
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(home, "Home", char *) ;
	    SetValue_pv(config, "Config", char **) ;
	    SetValue_sv(errprefix, "ErrPrefix") ;
	    SetValue_iv(flags, "Flags") ;
	    SetValue_io(handle, "ErrFile") ;
	    Trace(("_db_appinit(config=[%d], home=[%s],handle[%d],errprefix=[%s],flags=[%d]\n", 
			config, home, handle, errprefix, flags)) ;
#ifdef TRACE 
	    if (config) {
	       int i ;
	      for (i = 0 ; i < 10 ; ++ i) {
		if (config[i] == NULL) {
		    printf("    End\n") ;
		    break ;
		}
	        printf("    config = [%s]\n", config[i]) ;
	      }
	    }
#endif
	    ZMALLOC(RETVAL, BerkDB_ENV_type) ;
	    Trace(("Handle = %X\n", handle)) ;

	    /* Take a copy of the error prefix */
	    if (errprefix) {
	        Trace(("copying errprefix\n" )) ;
		RETVAL->ErrPrefix = newSVsv(errprefix) ;
		SvPOK_only(RETVAL->ErrPrefix) ;
	    }
	    if (RETVAL->ErrPrefix)
	        RETVAL->Env.db_errpfx = SvPVX(RETVAL->ErrPrefix) ;

	    SetValue_io(RETVAL->Env.db_errfile, "Handle") ;
	    SetValue_iv(RETVAL->Env.lk_max, "LockMax") ;
	    SetValue_iv(RETVAL->Env.lg_max, "LogMax") ;
	    SetValue_iv(RETVAL->Env.tx_max, "TxnMax") ;
	    SetValue_iv(RETVAL->Env.db_verbose, "Verbose") ;
	    /* RETVAL->Env.db_errbuf = RETVAL->ErrBuff ; */
	    RETVAL->Env.db_errcall = db_errcall_cb ;
	    status = db_appinit(home, config, &RETVAL->Env, flags) ;
	    Trace(("  status = %d env %d Env %d\n", status, RETVAL, &RETVAL->Env)) ;
	    if (status != 0)
		RETVAL = NULL ;
	}
	OUTPUT:
	    RETVAL


#define EnDis(x)	((x) ? "Enabled" : "Disabled")
void
printEnv(env)
        BerkDB::Env  env
	CODE:
	  printf("env             [0x%X]\n", env) ;
	  /* printf("  ErrBuff       [%s]\n", env->ErrBuff) ; */
	  printf("  ErrPrefix     [%s]\n", env->ErrPrefix 
				           ? SvPVX(env->ErrPrefix) : 0) ;
	  printf("  DB_ENV\n") ;
	  printf("    db_lorder   [%d]\n", env->Env.db_lorder) ;
	  printf("    db_home     [%s]\n", env->Env.db_home) ;
	  printf("    db_data_dir [%s]\n", env->Env.db_data_dir) ;
	  printf("    db_log_dir  [%s]\n", env->Env.db_log_dir) ;
	  printf("    db_tmp_dir  [%s]\n", env->Env.db_tmp_dir) ;
	  printf("    lk_info     [%s]\n", EnDis(env->Env.lk_info)) ;
	  printf("    lk_max      [%d]\n", env->Env.lk_max) ;
	  printf("    lg_info     [%s]\n", EnDis(env->Env.lg_info)) ;
	  printf("    lg_max      [%d]\n", env->Env.lg_max) ;
	  printf("    mp_info     [%s]\n", EnDis(env->Env.mp_info)) ;
	  printf("    mp_size     [%d]\n", env->Env.mp_size) ;
	  printf("    tx_info     [%s]\n", EnDis(env->Env.tx_info)) ;
	  printf("    tx_max      [%d]\n", env->Env.tx_max) ;
	  printf("    flags       [%d]\n", env->Env.flags) ;
	  printf("\n") ;

char *
errPrefix(env, prefix)
        BerkDB::Env  env
	SV * 		prefix
	CODE:
	  if (env->ErrPrefix) {
	      RETVAL = SvPVX(env->ErrPrefix) ;
	      sv_setsv(env->ErrPrefix, prefix) ;
	  }
	  else {
	      RETVAL = NULL ;
	      env->ErrPrefix = newSVsv(prefix) ;
	  }
	  SvPOK_only(env->ErrPrefix) ;
	  env->Env.db_errpfx = SvPVX(env->ErrPrefix) ;
	OUTPUT:
	  RETVAL

#define env_DESTROY(env)	db_appexit(&env->Env)
int
env_DESTROY(env)
        BerkDB::Env  env
	INIT:
	  Trace(("In BerkDB::Env::DESTROY env %ld Env %ld \n", 
			env, &env->Env)) ;
        CLEANUP:
	  Trace(("start cleanup BerkDB::Env::DESTROY\n")) ;
	  if (env->ErrPrefix)
	      SvREFCNT_dec(env->ErrPrefix) ;
          Safefree(env) ;
	  Trace(("real end of BerkDB::Env::DESTROY\n")) ;


BerkDB::Txn
txn_begin(env, pid=NULL)
	BerkDB::Env	env
	BerkDB::Txn	pid
	CODE:
	{
	    int status ;
	    if (env->Env.tx_info == NULL)
		croak("Transaction Manager not enabled") ;
	    env->Status = txn_begin(env->Env.tx_info, pid, &RETVAL) ;
	    if (env->Status != 0) {
		printf("XXXX\n") ;
		RETVAL = NULL ;
	    }
	}
	OUTPUT:
	    RETVAL

MODULE = BerkDB::Hash	PACKAGE = BerkDB::Hash	PREFIX = hash_

BerkDB::Hash
_db_open_hash(ref)
	SV * 		ref
	CODE:
	{
	    HV *		hash ;
	    SV * 		sv ;
	    DB_INFO 		info ;
	    BerkDB__Env	dbenv = NULL;
	    SV *		ref_dbenv = NULL;
	    const char *	file = NULL ;
	    int			flags = 0 ;
	    int			mode = 0 ;
    	    BerkDB     		db ;
	
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(file, "Filename", char *) ;
	    SetValue_ov(dbenv, "Env", BerkDB__Env) ;
	    ref_dbenv = sv ;
	    SetValue_iv(flags, "Flags") ;
	    SetValue_iv(mode, "Mode") ;

       	    Zero(&info, 1, DB_INFO) ;
	    SetValue_iv(info.db_cachesize, "Cachesize") ;
	    SetValue_iv(info.db_lorder, "Lorder") ;
	    SetValue_iv(info.db_pagesize, "Pagesize") ;
	    SetValue_iv(info.h_ffactor, "Ffactor") ;
	    SetValue_iv(info.h_nelem, "Nelem") ;
	    SetValue_iv(info.flags, "Property") ;
	    ZMALLOC(db, BerkDB_type) ; 
	    SetValue_ov(db->txn, "Txn", BerkDB__Txn) ;
	    if ((sv = readHash(hash, "Hash")) && sv != &sv_undef) {
		info.h_hash = hash_cb ;
		db->hash = newSVsv(sv) ;
	    }
	    
	    RETVAL = my_db_open(db, ref_dbenv, dbenv, file, DB_HASH, flags, mode, &info) ;
	}
	OUTPUT:
	    RETVAL


HV *
stat(db, flags=0)
	BerkDB::Common	db
	int		flags
	HV *		RETVAL = NULL ;
        NOT_IMPLEMENTED_YET


MODULE = BerkDB::Btree	PACKAGE = BerkDB::Btree	PREFIX = btree_

BerkDB::Btree
_db_open_btree(ref)
	SV * 		ref
	CODE:
	{
	    HV *		hash ;
	    SV * 		sv ;
	    DB_INFO 		info ;
	    BerkDB__Env	dbenv = NULL;
	    SV *		ref_dbenv = NULL;
	    const char *	file = NULL ;
	    int			flags = 0 ;
	    int			mode = 0 ;
    	    BerkDB     		db ;
	
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(file, "Filename", char*) ;
	    SetValue_ov(dbenv, "Env", BerkDB__Env) ;
	    ref_dbenv = sv ;
	    SetValue_iv(flags, "Flags") ;
	    SetValue_iv(mode, "Mode") ;

       	    Zero(&info, 1, DB_INFO) ;
	    SetValue_iv(info.db_cachesize, "Cachesize") ;
	    SetValue_iv(info.db_lorder, "Lorder") ;
	    SetValue_iv(info.db_pagesize, "Pagesize") ;
	    SetValue_iv(info.bt_minkey, "Minkey") ;
	    SetValue_iv(info.flags, "Property") ;
	    ZMALLOC(db, BerkDB_type) ; 
	    SetValue_ov(db->txn, "Txn", BerkDB__Txn) ;
	    if ((sv = readHash(hash, "Compare")) && sv != &sv_undef) {
		info.bt_compare = btree_compare ;
		db->compare = newSVsv(sv) ;
	    }
	    if ((sv = readHash(hash, "Prefix")) && sv != &sv_undef) {
		info.bt_prefix = btree_prefix ;
		db->prefix = newSVsv(sv) ;
	    }
	    
	    RETVAL = my_db_open(db, ref_dbenv, dbenv, file, DB_BTREE, flags, mode, &info) ;
	}
	OUTPUT:
	    RETVAL


HV *
stat(db, flags=0)
	BerkDB::Common	db
	int		flags
	HV *		RETVAL = NULL ;
	CODE:
	{
	    DB_BTREE_STAT *	stat ;
	    db->Status = ((db->dbp)->stat)(db->dbp, &stat, safemalloc, flags) ;
	    if (db->Status == 0) {
	    	RETVAL = (HV*)sv_2mortal((SV*)newHV()) ;
		hv_store_iv(RETVAL, "bt_flags", stat->bt_flags) ;
		hv_store_iv(RETVAL, "bt_maxkey", stat->bt_maxkey) ;
		hv_store_iv(RETVAL, "bt_minkey", stat->bt_minkey);
		hv_store_iv(RETVAL, "bt_re_len", stat->bt_re_len);
		hv_store_iv(RETVAL, "bt_re_pad", stat->bt_re_pad);
		hv_store_iv(RETVAL, "bt_pagesize", stat->bt_pagesize);
		hv_store_iv(RETVAL, "bt_levels", stat->bt_levels);
		hv_store_iv(RETVAL, "bt_nrecs", stat->bt_nrecs);
		hv_store_iv(RETVAL, "bt_int_pg", stat->bt_int_pg);
		hv_store_iv(RETVAL, "bt_leaf_pg", stat->bt_leaf_pg);
		hv_store_iv(RETVAL, "bt_dup_pg", stat->bt_dup_pg);
		hv_store_iv(RETVAL, "bt_over_pg", stat->bt_over_pg);
		hv_store_iv(RETVAL, "bt_free", stat->bt_free);
		hv_store_iv(RETVAL, "bt_freed", stat->bt_freed);
		hv_store_iv(RETVAL, "bt_int_pgfree", stat->bt_int_pgfree);
		hv_store_iv(RETVAL, "bt_leaf_pgfree", stat->bt_leaf_pgfree);
		hv_store_iv(RETVAL, "bt_dup_pgfree", stat->bt_dup_pgfree);
		hv_store_iv(RETVAL, "bt_over_pgfree", stat->bt_over_pgfree);
		hv_store_iv(RETVAL, "bt_pfxsaved", stat->bt_pfxsaved);
		hv_store_iv(RETVAL, "bt_split", stat->bt_split);
		hv_store_iv(RETVAL, "bt_rootsplit", stat->bt_rootsplit);
		hv_store_iv(RETVAL, "bt_fastsplit", stat->bt_fastsplit);
		hv_store_iv(RETVAL, "bt_added", stat->bt_added);
		hv_store_iv(RETVAL, "bt_deleted", stat->bt_deleted);
		hv_store_iv(RETVAL, "bt_get", stat->bt_get);
		hv_store_iv(RETVAL, "bt_cache_hit", stat->bt_cache_hit);
		hv_store_iv(RETVAL, "bt_cache_miss", stat->bt_cache_miss);
		safefree(stat) ;
	    }
	}
	OUTPUT:
	    RETVAL


MODULE = BerkDB::Common  PACKAGE = BerkDB::Common	PREFIX = dab_


#define dab_DESTROY(db)	((db->dbp)->close)(db->dbp, 0)
int
dab_DESTROY(db)
	BerkDB::Common	db
	INIT:
	  CurrentDB = db ;
	  Trace(("In BerkDB::Common::DESTROY\n")) ;
	  if (db->cursor)
	      ((db->cursor)->c_close)(db->cursor) ;
	CLEANUP:
	  if (db->hash)
            SvREFCNT_dec(db->hash) ;
          if (db->compare)
            SvREFCNT_dec(db->compare) ;
          if (db->prefix)
            SvREFCNT_dec(db->prefix) ;
          if (db->ref2env)
	      SvREFCNT_dec(db->ref2env) ;
          Safefree(db) ;
	  Trace(("End of BerkDB::Common::DESTROY\n")) ;

#define db_cursor(db, txn, cur)  ((db->dbp)->cursor)(db->dbp, txn, cur)
BerkDB::Cursor
db_cursor(db)
        BerkDB::Common 	db
        BerkDB::Cursor 	RETVAL = NULL ;
	CODE:
	{
	  DBC *		cursor ;
	  CurrentDB = db ;
	  if ((db->Status = db_cursor(db, db->txn, &cursor)) == 0){
	      ZMALLOC(RETVAL, BerkDB__Cursor_type) ;
	      RETVAL->cursor  = cursor ;
	      RETVAL->dbp     = db->dbp ;
	      RETVAL->ref2db  = newRV(SvRV(ST(0))) ;
              RETVAL->type    = db->type ;
              RETVAL->compare = db->compare ;
              RETVAL->prefix  = db->prefix ;
              RETVAL->hash    = db->hash ;
	      RETVAL->partial = db->partial ;
	      RETVAL->doff    = db->doff ;
	      RETVAL->dlen    = db->dlen ;
              /* RETVAL->info ; */
	  }
	}

	OUTPUT:
	  RETVAL


void
partial_set(db, offset, length)
        BerkDB::Common 	db
	u_int32_t	offset
	u_int32_t	length
	PPCODE:
	    if (GIMME == G_ARRAY) {
		XPUSHs(sv_2mortal(newSViv(db->partial == DB_DBT_PARTIAL))) ;
		XPUSHs(sv_2mortal(newSViv(db->doff))) ;
		XPUSHs(sv_2mortal(newSViv(db->dlen))) ;
	    }
	    db->partial = DB_DBT_PARTIAL ;
	    db->doff    = offset ;
	    db->dlen    = length ;
	

void
partial_clear(db)
        BerkDB::Common 	db
	PPCODE:
	    if (GIMME == G_ARRAY) {
		XPUSHs(sv_2mortal(newSViv(db->partial == DB_DBT_PARTIAL))) ;
		XPUSHs(sv_2mortal(newSViv(db->doff))) ;
		XPUSHs(sv_2mortal(newSViv(db->dlen))) ;
	    }
	    db->partial = 
	    db->doff    = 
	    db->dlen    = 0 ;


#define db_del(db, key, flags)  \
	(db->Status = ((db->dbp)->del)(db->dbp, db->txn, &key, flags))
int
db_del(db, key, flags=0)
	BerkDB::Common	db
	DBTKEY		key
	u_int		flags
	INIT:
	  CurrentDB = db ;


#define db_get(db, key, data, flags)   \
	(db->Status = ((db->dbp)->get)(db->dbp, db->txn, &key, &data, flags))
int
db_get(db, key, data, flags=0)
	BerkDB::Common	db
	u_int		flags
	DBTKEY_B	key
	DBT		data = NO_INIT
	INIT:
	  CurrentDB = db ;
	  SetPartial(data) ;
	OUTPUT:
	  data

#define db_put(db,key,data,flag)	\
		(db->Status = (db->dbp->put)(db->dbp,db->txn,&key,&data,flag))
int
db_put(db, key, data, flags=0)
	BerkDB::Common	db
	DBTKEY		key
	DBT		data
	u_int		flags
	INIT:
	  CurrentDB = db ;
	  /* SetPartial(data) ; */

#define db_fd(d, x)	(db->Status = (db->dbp->fd)(db->dbp, &x))
int
db_fd(db)
	BerkDB::Common	db
	CODE:
	  CurrentDB = db ;
	  db_fd(db, RETVAL) ;
	OUTPUT:
	  RETVAL


#define db_sync(db, fl)	(db->Status = (db->dbp->sync)(db->dbp, fl))
int
db_sync(db, flags=0)
	BerkDB::Common	db
	u_int		flags
	INIT:
	  CurrentDB = db ;





MODULE = BerkDB::Cursor              PACKAGE = BerkDB::Cursor	PREFIX = cu_


#define cu_DESTROY(c)	((c->cursor)->c_close)(c->cursor)
int
cu_DESTROY(db)
    BerkDB::Cursor	db
	INIT:
	  Trace(("in cursor DESTROY\n")) ;
	  CurrentDB = db ;
	CLEANUP:
	  Trace(("cursor DESTROY cleanup\n")) ;
          if (db->ref2db)
	      SvREFCNT_dec(db->ref2db) ;
          Safefree(db) ;
	  Trace(("end of cursor DESTROY\n")) ;


#define cu_c_del(c,f)	(c->Status = ((c->cursor)->c_del)(c->cursor,f))
int
cu_c_del(db, flags=0)
    BerkDB::Cursor	db
    int			flags
	INIT:
	  CurrentDB = db ;


#define cu_c_get(c,k,d,f) (c->Status = (c->cursor->c_get)(c->cursor,&k,&d,f))
int
cu_c_get(db, key, data, flags=0)
    BerkDB::Cursor	db
    int			flags
    DBTKEY_B		key
    DBT			data = NO_INIT
	INIT:
	  CurrentDB = db ;
	  SetPartial(data) ;
	OUTPUT:
	  key
	  data


#define cu_c_put(c,k,d,f)  (c->Status = (c->cursor->c_put)(c->cursor,&k,&d,f))
int
cu_c_put(db, key, data, flags=0)
    BerkDB::Cursor	db
    DBTKEY		key
    DBT			data
    int			flags
	INIT:
	  CurrentDB = db ;
	  /* SetPartial(data) ; */





MODULE = BerkDB::Txn              PACKAGE = BerkDB::Txn		PREFIX = xx_

BerkDB::TxnMgr
txn_open(dir, flags, mode, dbenv)
    const char *	dir
    int 		flags
    int 		mode
    BerkDB::Env 	dbenv
        NOT_IMPLEMENTED_YET

BerkDB::Txn
txn_begin(txnp, tid)
	BerkDB::TxnMgr	txnp
	BerkDB::Txn	tid
        NOT_IMPLEMENTED_YET


int
txn_close(txnp)
	BerkDB::TxnMgr	txnp
        NOT_IMPLEMENTED_YET

#define xx_txn_unlink(d,f,e)	txn_unlink(d,f,&(e->Env))
int
xx_txn_unlink(dir, force, dbenv)
    const char *	dir
    int 		force
    BerkDB::Env 	dbenv

int
txn_prepare(tid)
	BerkDB::Txn	tid

int
txn_commit(tid)
	BerkDB::Txn	tid

int
txn_abort(tid)
	BerkDB::Txn	tid

u_int32_t
txn_id(tid)
	BerkDB::Txn	tid

int
txn_checkpoint(txnp, kbyte, min)
	BerkDB::TxnMgr	txnp
	long		kbyte
	long		min

HV *
txn_stat(txnp)
	BerkDB::TxnMgr	txnp
	HV *		RETVAL = NULL ;
	CODE:
	{
	    DB_TXN_STAT *	stat ;
	    if(txn_stat(txnp, &stat, safemalloc) == 0) {
	    	RETVAL = (HV*)sv_2mortal((SV*)newHV()) ;
		hv_store_iv(RETVAL, "st_time_ckp", stat->st_time_ckp) ;
		hv_store_iv(RETVAL, "st_last_txnid", stat->st_last_txnid) ;
		hv_store_iv(RETVAL, "st_maxtxns", stat->st_maxtxns) ;
		hv_store_iv(RETVAL, "st_naborts", stat->st_naborts) ;
		hv_store_iv(RETVAL, "st_nbegins", stat->st_nbegins) ;
		hv_store_iv(RETVAL, "st_ncommits", stat->st_ncommits) ;
		hv_store_iv(RETVAL, "st_nactive", stat->st_nactive) ;
		safefree(stat) ;
	    }
	}
	OUTPUT:
	    RETVAL

MODULE = BerkDB::_tiedHash        PACKAGE = BerkDB::_tiedHash

int
FIRSTKEY(db)
        BerkDB::Common         db
        CODE:
        {
            DBTKEY      key ;
            DBT         value ;
	    DBC *	cursor ;
 
	    /* 
		TODO!
		set partial value to 0 - to eliminate the retrieval of
		the value need to store any existing partial settings &
		restore at the end.

	     */
            CurrentDB = db ;
	    key.flags = value.flags = 0 ;
	    /* If necessary create a cursor for FIRSTKEY/NEXTKEY use */
	    if (!db->cursor &&
		(db->Status = db_cursor(db, db->txn, &cursor)) == 0 )
	            db->cursor  = cursor ;
	    
	    if (db->cursor)
	        RETVAL = ((db->cursor)->c_get)(db->cursor, &key, &value, DB_FIRST);
	    else
		RETVAL = db->Status ;
	    /* check for end of cursor */
	    if (RETVAL == DB_NOTFOUND) {
	      ((db->cursor)->c_close)(db->cursor) ;
	      db->cursor = NULL ;
	    }
            ST(0) = sv_newmortal();
	    OutputKey(ST(0), key) 
        }
 


int
NEXTKEY(db, key)
        BerkDB::Common  db
        DBTKEY          key
        CODE:
        {
            DBT         value ;
 
            CurrentDB = db ;
	    key.flags = value.flags = 0 ;
	    RETVAL = ((db->cursor)->c_get)(db->cursor, &key, &value, DB_NEXT);

	    /* check for end of cursor */
	    if (RETVAL == DB_NOTFOUND) {
	      ((db->cursor)->c_close)(db->cursor) ;
	      db->cursor = NULL ;
	    }
            ST(0) = sv_newmortal();
	    OutputKey(ST(0), key) 
        }
 

MODULE = BerkDB        PACKAGE = BerkDB

BOOT:
  {
    SV * ver_sv = perl_get_sv("BerkDB::db_version", TRUE) ;
    int Major, Minor, Patch ;
    (void)db_version(&Major, &Minor, &Patch) ;
    sv_setpvf(ver_sv, "%d.%d", Major, Minor) ;

    empty.data  = &zero ;
    empty.size  =  sizeof(db_recno_t) ;
    empty.flags = 0 ;

    /* Create the $BerkDB::Error scalar */
    sv_setpv(perl_get_sv(ERR_BUFF, TRUE), "") ;

  }

