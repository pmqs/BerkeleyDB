/*
 
 BerkeleyDB.xs -- Perl 5 interface to Berkeley DB version 2
 
 written by Paul Marquess <Paul.Marquess@btinternet.com>

 SCCS: %I%, %G%  

 All comments/suggestions/problems are welcome
 
     Copyright (c) 1997/8 Paul Marquess. All rights reserved.
     This program is free software; you can redistribute it and/or
     modify it under the same terms as Perl itself.

     Please refer to the COPYRIGHT section in 
 
 Changes:
        0.01 -  First Alpha Release
        0.02 -  
 
*/



#ifdef __cplusplus
extern "C" {
#endif
#define PERL_POLLUTE
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* Being the Berkeley DB we prefer the <sys/cdefs.h> (which will be
 * shortly #included by the <db.h>) __attribute__ to the possibly
 * already defined __attribute__, for example by GNUC or by Perl. */

#undef __attribute__

#include <db.h>

/* need to define DEFSV & SAVE_DEFSV for older version of Perl */
#ifndef DEFSV
#define DEFSV GvSV(defgv)
#endif

#ifndef SAVE_DEFSV
#define SAVE_DEFSV SAVESPTR(GvSV(defgv))
#endif

#ifdef __cplusplus
}
#endif

/* #define TRACE */
/* #define ALLOW_RECNO_OFFSET */
#define ALLOW_KV_FILTER


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
	int		active ;
#ifdef ALLOW_RECNO_OFFSET
	int		array_base ;
#endif
#ifdef ALLOW_KV_FILTER
	int		filtering ;
        SV *    	readKey ;
        SV *    	writeKey ;
        SV *    	readValue ;
        SV *    	writeValue ;
#endif
        } BerkeleyDB_type;

typedef struct {
	int		Status ;
	/* char		ErrBuff[1000] ; */
	SV *		ErrPrefix ;
	SV *		ErrHandle ;
	DB_ENV		Env ;
	int		TxnMgrStatus ;
	int		active ;
	} BerkeleyDB_ENV_type ;

typedef struct {
	BerkeleyDB_ENV_type *	env ;
	SV *			ref2env ;
	} BerkeleyDB_TxnMgr_type ;

#if 1
typedef struct {
	int		Status ;
	DB_TXN *	txn ;
	int		active ;
	} BerkeleyDB_Txn_type ;
#else
typedef DB_TXN                BerkeleyDB_Txn_type ;
#endif

typedef BerkeleyDB_ENV_type *	BerkeleyDB__Env ;
typedef BerkeleyDB_ENV_type *	BerkeleyDB__Env__Inner ;
typedef BerkeleyDB_type * 	BerkeleyDB ;
typedef BerkeleyDB_type *	BerkeleyDB__Common ;
typedef BerkeleyDB_type *	BerkeleyDB__Common__Inner ;
typedef BerkeleyDB_type * 	BerkeleyDB__Hash ;
typedef BerkeleyDB_type * 	BerkeleyDB__Btree ;
typedef BerkeleyDB_type * 	BerkeleyDB__Recno ;
typedef BerkeleyDB_type   	BerkeleyDB__Cursor_type ;
typedef BerkeleyDB_type * 	BerkeleyDB__Cursor ;
typedef BerkeleyDB_TxnMgr_type * BerkeleyDB__TxnMgr ;
typedef BerkeleyDB_TxnMgr_type * BerkeleyDB__TxnMgr__Inner ;
typedef BerkeleyDB_Txn_type *	BerkeleyDB__Txn ;
typedef BerkeleyDB_Txn_type *	BerkeleyDB__Txn__Inner ;
typedef DB_LOG *      		BerkeleyDB__Log ;
typedef DB_LOCKTAB *  		BerkeleyDB__Lock ;
typedef DBT 			DBTKEY ;
typedef DBT 			DBT_B ;
typedef DBT 			DBTKEY_B ;
typedef DBT 			DBTVALUE ;
typedef void *	      		PV_or_NULL ;
typedef PerlIO *      		IO_or_NULL ;
typedef int			DualType ;

#ifdef TRACE
#define Trace(x)	printf x 
#else
#define Trace(x)	
#endif

#ifdef ALLOW_RECNO_OFFSET
#define RECNO_BASE	db->array_base
#else
#define RECNO_BASE	1
#endif

#if DB_VERSION_MAJOR == 2 && DB_VERSION_MINOR < 5
#define flagSet(bitmask)        (flags & (bitmask))  
#else   
#define flagSet(bitmask)	((flags & DB_OPFLAGS_MASK) == (bitmask))
#endif

#ifdef ALLOW_KV_FILTER
#define ckFilter(arg,type,name)                         \
        if (db->type) {                                 \
            /* printf("filtering %s\n", name) ; */      \
            if (db->filtering)                          \
                croak("recursion detected") ;           \
            db->filtering = TRUE ;                      \
            SAVE_DEFSV ;   /* save $_ */                \
            /* DEFSV = sv_2mortal(newSVsv(arg)) ; */            \
            DEFSV = arg ;                               \
                                                        \
            PUSHMARK(sp) ;                              \
                                                        \
            (void) perl_call_sv(db->type, G_DISCARD|G_NOARGS);  \
            SPAGAIN ;                                   \
            /* sv_setsv(arg, DEFSV) ; */                \
            arg =  DEFSV ;                              \
            PUTBACK ;                                   \
            db->filtering = FALSE ;                     \
        }
#else
#define ckFilter(type, sv, name)
#endif

#define ERR_BUFF "BerkeleyDB::Error" 

#define ZMALLOC(to, typ) ((to = (typ *)safemalloc(sizeof(typ))), \
				Zero(to,1,typ))

#define my_sv_setpvn(sv, d, s) (s ? sv_setpvn(sv, d, s) : sv_setpv(sv, "") )

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

#define SetValue_ovx(i,k,t) if ((sv = readHash(hash, k)) && sv != &sv_undef) {\
				HV * hv = (HV *)GetInternalObject(sv);		\
				SV ** svp = hv_fetch(hv, "db", 2, FALSE);\
				IV tmp = SvIV(*svp);			\
				i = (t) tmp ;				\
			  }

#define SetValue_ovX(i,k,t) if ((sv = readHash(hash, k)) && sv != &sv_undef) {\
				IV tmp = SvIV(GetInternalObject(sv));\
				i = (t) tmp ;				\
			  }

#define LastDBerror DB_NOTFOUND

#define setDUALerrno(var, err)					\
		sv_setnv(var, (double)err) ;			\
		sv_setpv(var, (err < LastDBerror		\
				? "Unknown"			\
				: err == 0 ? ""			\
				    : err < 0 			\
					? db_err_str[abs(err)] 	\
					: Strerror(err))) ;	\
		SvNOK_on(var); 					

#define OutputValue(arg, name)                                  \
        { if (RETVAL == 0) {                                    \
              my_sv_setpvn(arg, name.data, name.size) ;         \
              ckFilter(arg, readValue,"readValue") ;            \
          }                                                     \
        }

#define OutputValue_B(arg, name)                                  \
        { if (RETVAL == 0) {                                    \
		if (db->type == DB_BTREE && 			\
			flagSet(DB_GET_RECNO)){			\
                    sv_setiv(arg, (I32)(*(I32*)name.data) - RECNO_BASE); \
                }                                               \
                else {                                          \
                    my_sv_setpvn(arg, name.data, name.size) ;   \
                }                                               \
                ckFilter(arg, readValue, "readValue");          \
          }                                                     \
        }

#define OutputKey(arg, name)                                    \
        { if (RETVAL == 0) 					\
          {                                                     \
                if (db->type != DB_RECNO) {                     \
                    my_sv_setpvn(arg, name.data, name.size);    \
                }                                               \
                else                                            \
                    sv_setiv(arg, (I32)*(I32*)name.data - RECNO_BASE);   \
                ckFilter(arg, readKey, "readKey") ;            \
          }                                                     \
        }

#define OutputKey_B(arg, name)                                  \
        { if (RETVAL == 0) 					\
          {                                                     \
                if (db->type == DB_RECNO || 			\
			(db->type == DB_BTREE && 		\
			    flagSet(DB_GET_RECNO))){		\
                    sv_setiv(arg, (I32)(*(I32*)name.data) - RECNO_BASE); \
                }                                               \
                else {                                          \
                    my_sv_setpvn(arg, name.data, name.size);    \
                }                                               \
                ckFilter(arg, readKey, "readKey") ;            \
          }                                                     \
        }

#define SetPartial(data,db) 					\
	data.flags = db->partial ;				\
	data.dlen  = db->dlen ;					\
	data.doff  = db->doff ;	

#define ckActive(active, type) 					\
    {								\
	if (!active)  						\
	    croak("%s is already closed", type) ;		\
    }

#define ckActive_Environment(a)	ckActive(a, "Environment")
#define ckActive_TxnMgr(a)	ckActive(a, "Transaction Manager")
#define ckActive_Transaction(a) ckActive(a, "Transaction")
#define ckActive_Database(a) 	ckActive(a, "Database")
#define ckActive_Cursor(a) 	ckActive(a, "Cursor")

/* Internal Global Data */
static db_recno_t Value ;
static db_recno_t zero = 0 ;
static BerkeleyDB	CurrentDB ;
static DBTKEY	empty ;
static char	ErrBuff[1000] ;
static char *   db_err_str[] = {
	"",
	"Sync didn't finish",			/* DB_INCOMPLETE 	*/
	"The key/data pair was deleted or was never created by the user",
						/* DB_KEYEMPTY		*/
	"The key/data pair already exists",	/* DB_KEYEXIST 		*/
	"Locker killed to resolve deadlock",	/* DB_LOCK_DEADLOCK 	*/
	"Lock unavailable, no-wait set",	/* DB_LOCK_NOTGRANTED 	*/
	"Lock not held by locker",		/* DB_LOCK_NOTHELD	*/
	"Key/data pair not found (EOF)",	/* DB_NOTFOUND		*/
#if 0
	"Recovery file marked deleted",		/* DB_DELETED		*/
	"Page needs to be split",		/* DB_NEEDSPLIT		*/
	"Entry was previously registered",	/* DB_REGISTERED	*/
	"Database needs byte swapping",		/* DB_SWAPBYTES		*/
	"Encountered ckp record in log",	/* DB_TXN_CKP		*/
#endif
			
	} ;


static I32
GetArrayLength(db)
BerkeleyDB db ;
{
    DBT		key ;
    DBT		value ;
    int		RETVAL = 0 ;
    DBC *   	cursor ;

    key.flags = 0 ;
    value.flags = 0 ;
#if DB_VERSION_MAJOR == 2 && DB_VERSION_MINOR < 6
    if ( ((db->dbp)->cursor)(db->dbp, db->txn, &cursor) == 0 )
#else
    if ( ((db->dbp)->cursor)(db->dbp, db->txn, &cursor, 0) == 0 )
#endif
    {
        RETVAL = cursor->c_get(cursor, &key, &value, DB_LAST) ;
        if (RETVAL == 0)
            RETVAL = *(I32 *)key.data ;
        else /* No key means empty file */
            RETVAL = 0 ;
        cursor->c_close(cursor) ;
    }

    Trace(("GetArrayLength got %d\n", RETVAL)) ;
    return ((I32)RETVAL) ;
}

#if 0

#define GetRecnoKey(db, value)  _GetRecnoKey(db, value)

static db_recno_t
_GetRecnoKey(db, value)
BerkeleyDB  db ;
I32      value ;
{
    Trace(("GetRecnoKey start value = %d\n", value)) ;
    if (db->type == DB_RECNO && value < 0) {
	/* Get the length of the array */
	I32 length = GetArrayLength(db) ;

	/* check for attempt to write before start of array */
	if (length + value + RECNO_BASE <= 0)
	    croak("Modification of non-creatable array value attempted, subscript %ld", (long)value) ;

	value = length + value + RECNO_BASE ;
    }
    else
        ++ value ;

    Trace(("GetRecnoKey end value = %d\n", value)) ;

    return value ;
}

#else /* ! 0 */

#if 0
#ifdef ALLOW_RECNO_OFFSET
#define GetRecnoKey(db, value) _GetRecnoKey(db, value)
		
static db_recno_t
_GetRecnoKey(db, value)
BerkeleyDB  db ;
I32      value ;
{
    if (value + RECNO_BASE < 1)
	croak("key value %d < base (%d)", (value), RECNO_BASE?0:1) ;
    return value + RECNO_BASE ;
}

#else
#endif /* ALLOW_RECNO_OFFSET */
#endif /* 0 */

#define GetRecnoKey(db, value) ((value) + RECNO_BASE )

#endif /* 0 */

static SV *
GetInternalObject(sv)
SV * sv ;
{
    SV * info = (SV*) NULL ;
    SV * s ;
    MAGIC * mg ;

    Trace(("in GetInternalObject %d\n", sv)) ;
    if (sv == NULL || !SvROK(sv))
        return NULL ;

    s = SvRV(sv) ;
    if (SvMAGICAL(s))
    {
        if (SvTYPE(s) == SVt_PVHV || SvTYPE(s) == SVt_PVAV)
            mg = mg_find(s, 'P') ;
        else
            mg = mg_find(s, 'q') ;

	 /* all this testing is probably overkill, but till I know more
	    about global destruction it stays.
	 */
        /* if (mg && mg->mg_obj && SvRV(mg->mg_obj) && SvPVX(SvRV(mg->mg_obj))) */
        if (mg && mg->mg_obj && SvRV(mg->mg_obj) ) 
            info = SvRV(mg->mg_obj) ;
	else
	    info = s ;
    }

    Trace(("end of GetInternalObject %d\n", info)) ;
    return info ;
}

static void
destroy_env(env)
BerkeleyDB__Env env ;
{
      Trace(("start destroy_env %d\n", env)) ;
      db_appexit(&env->Env) ;
      if (env->ErrHandle)
          SvREFCNT_dec(env->ErrHandle) ;
      if (env->ErrPrefix)
          SvREFCNT_dec(env->ErrPrefix) ;
      Trace(("end destroy_env\n")) ;
}

#if 0
static void
destroy_txnmgr(txnmgr)
BerkeleyDB__TxnMgr txnmgr ;
{
      Trace(("start destroy_txnmgr %d\n", txnmgr)) ;
      if (txnmgr->ref2env)
          SvREFCNT_dec(txnmgr->ref2env) ;
      Trace(("end destroy_txnmgr\n")) ;
}
#endif

static void
destroy_db(db)
BerkeleyDB db ;
{
      Trace(("start destroy_db %d\n", db)) ;
      ((db->dbp)->close)(db->dbp, 0) ;
      if (db->hash)
        SvREFCNT_dec(db->hash) ;
      if (db->compare)
        SvREFCNT_dec(db->compare) ;
      if (db->prefix)
        SvREFCNT_dec(db->prefix) ;
      if (db->ref2env)
          SvREFCNT_dec(db->ref2env) ;
#ifdef ALLOW_KV_FILTER
      if (db->readKey)
          SvREFCNT_dec(db->readKey) ;
      if (db->writeKey)
          SvREFCNT_dec(db->writeKey) ;
      if (db->readValue)
          SvREFCNT_dec(db->readValue) ;
      if (db->writeValue)
          SvREFCNT_dec(db->writeValue) ;
#endif

      Trace(("end destroy_db\n")) ;
}

static void
destroy_cursor(c)
BerkeleyDB__Cursor c;
{
    Trace(("start destroy_cursor %d\n", c)) ;
    ((c->cursor)->c_close)(c->cursor) ;
    if (c->ref2db)
       SvREFCNT_dec(c->ref2db) ;
    Trace(("end destroy_cursor\n")) ;
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

    PUSHMARK(SP) ;
    EXTEND(SP,2) ;
    PUSHs(sv_2mortal(newSVpv(data1,key1->size)));
    PUSHs(sv_2mortal(newSVpv(data2,key2->size)));
    PUTBACK ;

    count = perl_call_sv(CurrentDB->compare, G_SCALAR); 

    SPAGAIN ;

    if (count != 1)
        croak ("BerkeleyDB btree_compare: expected 1 return value from compare sub, got %d\n", count) ;

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

    PUSHMARK(SP) ;
    EXTEND(SP,2) ;
    PUSHs(sv_2mortal(newSVpv(data1,key1->size)));
    PUSHs(sv_2mortal(newSVpv(data2,key2->size)));
    PUTBACK ;

    count = perl_call_sv(CurrentDB->prefix, G_SCALAR); 

    SPAGAIN ;

    if (count != 1)
        croak ("BerkeleyDB btree_prefix: expected 1 return value from prefix sub, got %d\n", count) ;
 
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

    PUSHMARK(SP) ;

    XPUSHs(sv_2mortal(newSVpv((char*)data,size)));
    PUTBACK ;

    count = perl_call_sv(CurrentDB->hash, G_SCALAR); 

    SPAGAIN ;

    if (count != 1)
        croak ("BerkeleyDB hash_cb: expected 1 return value from hash sub, got %d\n", count) ;

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
    if (sv) {
        if (db_errpfx)
	    sv_setpvf(sv, "%s: %s", db_errpfx, buffer) ;
        else
            sv_setpv(sv, buffer) ;
    }
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
hash_delete(hash, key)
char * hash;
IV key;
{
    HV * hv = perl_get_hv(hash, TRUE);
    (void) hv_delete(hv, (char*)&key, sizeof(key), G_DISCARD);
}

static void
hash_store_iv(hash, key, value)
char * hash;
IV key;
IV value ;
{
    HV * hv = perl_get_hv(hash, TRUE);
    SV ** ret = hv_store(hv, (char*)&key, sizeof(key), newSViv(value), 0);
    /* printf("hv_store returned %d\n", ret) ; */
}

static void
hv_store_iv(hash, key, value)
HV * hash;
char * key;
IV value ;
{
    hv_store(hash, key, strlen(key), newSViv(value), 0);
}

static BerkeleyDB
my_db_open(db, ref, ref_dbenv, dbenv, file, type, flags, mode, info)
BerkeleyDB	db ;
SV * 		ref;
SV *		ref_dbenv ;
BerkeleyDB__Env	dbenv ;
const char *	file;
DBTYPE		type;
int		flags;
int		mode;
DB_INFO * 	info ;
{
    DB_ENV *	env    = NULL ;
    BerkeleyDB 	RETVAL = NULL ;
    DB *	dbp ;
    int		Status ;

    Trace(("_db_open(dbenv[%lu] ref_dbenv [%lu] file[%s] type[%d] flags[%d] mode[%d]\n", 
		dbenv, ref_dbenv, file, type, flags, mode)) ;

    CurrentDB = db ;
    if (dbenv) 
	env = &dbenv->Env ;

    if ((Status = db_open(file, type, flags, mode, env, info, &dbp)) == 0) {
	Trace(("db_opened\n"));
	RETVAL = db ;
	RETVAL->dbp  = dbp ;
    	RETVAL->type = dbp->type ;
	RETVAL->Status = Status ;
	RETVAL->active = TRUE ;
	hash_store_iv("BerkeleyDB::Term::Db", (IV)dbp, 1) ;
	Trace(("  storing %d in BerkeleyDB::Term::Db\n", dbp)) ;
	if (dbenv) {
	    RETVAL->ref2env = newRV(ref_dbenv) ;
	    dbenv->Status = Status ;
	}
#ifdef ALLOW_KV_FILTER
        {
            SV * sv ;
	    HV * hash = (HV*) SvRV(ref) ;
            if ((sv = readHash(hash, "ReadKey")) && sv != &sv_undef)
                db->readKey = newSVsv(sv) ;
            if ((sv = readHash(hash, "WriteKey")) && sv != &sv_undef)
                db->writeKey = newSVsv(sv) ;
            if ((sv = readHash(hash, "ReadValue")) && sv != &sv_undef)
                db->readValue = newSVsv(sv) ;
            if ((sv = readHash(hash, "WriteValue")) && sv != &sv_undef)
                db->writeValue = newSVsv(sv) ;
        }	    
#endif	    
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
	if (strEQ(name, "DB_BTREE"))
	    return DB_BTREE;
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
	if (strEQ(name, "DB_GET_BOTH"))
#ifdef DB_GET_BOTH
	    return DB_GET_BOTH;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_GET_RECNO"))
#ifdef DB_GET_RECNO
	    return DB_GET_RECNO;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_HASH"))
	    return DB_HASH;
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
	if (strEQ(name, "DB_INIT_CDB"))
#ifdef DB_INIT_CDB
	    return DB_INIT_CDB;
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
	if (strEQ(name, "DB_NEXT_DUP"))
#ifdef DB_NEXT_DUP
	    return DB_NEXT_DUP;
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
	if (strEQ(name, "DB_RECNO"))
	    return DB_RECNO;
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
	if (strEQ(name, "DB_REGION_ANON"))
#ifdef DB_REGION_ANON
	    return DB_REGION_ANON;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_REGION_INIT"))
#ifdef DB_REGION_INIT
	    return DB_REGION_INIT;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_REGION_NAME"))
#ifdef DB_REGION_NAME
	    return DB_REGION_NAME;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_REGISTERED"))
#ifdef DB_REGISTERED
	    return DB_REGISTERED;
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
	if (strEQ(name, "DB_RENUMBER"))
#ifdef DB_RENUMBER
	    return DB_RENUMBER;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RUNRECOVERY"))
#ifdef DB_RUNRECOVERY
	    return DB_RUNRECOVERY;
#else
	    goto not_there;
#endif
	if (strEQ(name, "DB_RMW"))
#ifdef DB_RMW
	    return DB_RMW;
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
	if (strEQ(name, "DB_TSL_SPINS"))
#ifdef DB_TSL_SPINS
	    return DB_TSL_SPINS;
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


MODULE = BerkeleyDB		PACKAGE = BerkeleyDB	PREFIX = env_

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

int
db_value_set(value, which)
	int value
	int which

MODULE = BerkeleyDB::Env		PACKAGE = BerkeleyDB::Env PREFIX = env_


BerkeleyDB::Env 
_db_appinit(self, ref)
	char *		self
	SV * 		ref
	CODE:
	{
	    HV *	hash ;
	    SV *	sv ;
	    char *	home = NULL ;
	    char **	config = NULL ;
	    int		flags = 0 ;
	    SV *	errprefix = NULL;
	    int status ;

	    Trace(("in _db_appinit [%s] %d\n", self, ref)) ;
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(home,      "Home", char *) ;
	    SetValue_pv(config,    "Config", char **) ;
	    SetValue_sv(errprefix, "ErrPrefix") ;
	    SetValue_iv(flags,     "Flags") ;
	    Trace(("_db_appinit(config=[%d], home=[%s],errprefix=[%s],flags=[%d]\n", 
			config, home, errprefix, flags)) ;
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
	    ZMALLOC(RETVAL, BerkeleyDB_ENV_type) ;

	    /* Take a copy of the error prefix */
	    if (errprefix) {
	        Trace(("copying errprefix\n" )) ;
		RETVAL->ErrPrefix = newSVsv(errprefix) ;
		SvPOK_only(RETVAL->ErrPrefix) ;
	    }
	    if (RETVAL->ErrPrefix)
	        RETVAL->Env.db_errpfx = SvPVX(RETVAL->ErrPrefix) ;

	    if ((sv = readHash(hash, "ErrFile")) && sv != &sv_undef) {
		RETVAL->Env.db_errfile = IoOFP(sv_2io(sv)) ;
		RETVAL->ErrHandle = newRV(sv) ;
	    }
	    /* SetValue_io(RETVAL->Env.db_errfile, "ErrFile") ; */
	    SetValue_iv(RETVAL->Env.db_verbose, "Verbose") ;
	    /* RETVAL->Env.db_errbuf = RETVAL->ErrBuff ; */
	    RETVAL->Env.db_errcall = db_errcall_cb ;
	    RETVAL->active = TRUE ;
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
        BerkeleyDB::Env  env
	INIT:
	    ckActive_Environment(env->active) ;
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

SV *
errPrefix(env, prefix)
        BerkeleyDB::Env  env
	SV * 		 prefix
	INIT:
	    ckActive_Environment(env->active) ;
	CODE:
	  if (env->ErrPrefix) {
	      RETVAL = newSVsv(env->ErrPrefix) ;
              SvPOK_only(RETVAL) ;
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

DualType
status(env)
        BerkeleyDB::Env 	env
	CODE:
	    RETVAL =  env->Status ;
	OUTPUT: 
	    RETVAL

DualType
db_appexit(env)
        BerkeleyDB::Env 	env
	INIT:
	    ckActive_Environment(env->active) ;
	CODE:
	    RETVAL = db_appexit(&env->Env) ;
	    env->active = FALSE ;
	OUTPUT: 
	    RETVAL
	    

void
DESTROY(env)
        BerkeleyDB::Env  env
	int RETVAL = 0 ;
	CODE:
	  Trace(("In BerkeleyDB::Env::DESTROY\n"));
	  Trace(("    env %ld Env %ld dirty %d\n", env, &env->Env, dirty)) ;
	  if (env->active)
              db_appexit(&env->Env) ;
          if (env->ErrHandle)
              SvREFCNT_dec(env->ErrHandle) ;
          if (env->ErrPrefix)
              SvREFCNT_dec(env->ErrPrefix) ;
          Safefree(env) ;
	  Trace(("End of BerkeleyDB::Env::DESTROY %d\n", RETVAL)) ;

BerkeleyDB::TxnMgr
TxnMgr(env)
        BerkeleyDB::Env  env
	INIT:
	    ckActive_Environment(env->active) ;
	CODE:
	    ZMALLOC(RETVAL, BerkeleyDB_TxnMgr_type) ;
	    RETVAL->env  = env ;
	    /* hash_store_iv("BerkeleyDB::Term::TxnMgr", txn, 1) ; */
	    /* RETVAL->ref2env = newRV(SvRV(ST(0))) ; */
	OUTPUT:
	    RETVAL


MODULE = BerkeleyDB::Term		PACKAGE = BerkeleyDB::Term

void
env_close(env)
	BerkeleyDB_ENV_type * env
	CODE:
	Trace(("BerkeleyDB::Term::env_close %d\n", env)) ;
	destroy_env(env) ;

void
db_close(db)
	DB *		  db
	CODE:
	/* BerkeleyDB_type * db */
	Trace(("BerkeleyDB::Term::db_close %d\n", db)) ;
        /* destroy_db(db) ; */
	(db->close)(db, 0) ;
	/* ((db->dbp)->close)(db->dbp, 0) ; */

void
close_dbs()
	CODE:
	DB * db ;
	HE * he ;
	I32 len ;
	HV * hv = perl_get_hv("BerkeleyDB::Term::Db", TRUE);
	I32 ret = hv_iterinit(hv) ;
	while ( he = hv_iternext(hv) ) {
	    db = * (DB**) (IV) hv_iterkey(he, &len) ;
	    /* printf("close_dbs %d %d\n", db, len) ; */
	    (db->close)(db, 0) ;
	    /* printf("close_dbs closed\n"); */
	}
	
void
cur_close(db)
	BerkeleyDB__Cursor_type * db
	CODE:
	Trace(("BerkeleyDB::Term::cur_close %d\n", db)) ;
        destroy_cursor(db) ;
	


MODULE = BerkeleyDB::Hash	PACKAGE = BerkeleyDB::Hash	PREFIX = hash_

BerkeleyDB::Hash
_db_open_hash(self, ref)
	char *		self
	SV * 		ref
	CODE:
	{
	    HV *		hash ;
	    SV * 		sv ;
	    DB_INFO 		info ;
	    BerkeleyDB__Env	dbenv = NULL;
	    SV *		ref_dbenv = NULL;
	    const char *	file = NULL ;
	    int			flags = 0 ;
	    int			mode = 0 ;
    	    BerkeleyDB 		db ;
	
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(file, "Filename", char *) ;
	    SetValue_ov(dbenv, "Env", BerkeleyDB__Env) ;
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
	    ZMALLOC(db, BerkeleyDB_type) ; 
	    if ((sv = readHash(hash, "Txn")) && sv != &sv_undef) {
		BerkeleyDB__Txn tmp = (BerkeleyDB__Txn)SvIV((SV*)SvRV(sv));
		db->txn = tmp->txn ;
	    }
	    if ((sv = readHash(hash, "Hash")) && sv != &sv_undef) {
		info.h_hash = hash_cb ;
		db->hash = newSVsv(sv) ;
	    }
	    RETVAL = my_db_open(db, ref, ref_dbenv, dbenv, file, DB_HASH, flags, mode, &info) ;
	}
	OUTPUT:
	    RETVAL


HV *
db_stat(db, flags=0)
	BerkeleyDB::Common	db
	int			flags
	HV *			RETVAL = NULL ;
        NOT_IMPLEMENTED_YET


MODULE = BerkeleyDB::Unknown	PACKAGE = BerkeleyDB::Unknown	PREFIX = hash_

void
_db_open_unknown(ref)
	SV * 		ref
	PPCODE:
	{
	    HV *		hash ;
	    SV * 		sv ;
	    DB_INFO 		info ;
	    BerkeleyDB__Env	dbenv = NULL;
	    SV *		ref_dbenv = NULL;
	    const char *	file = NULL ;
	    int			flags = 0 ;
	    int			mode = 0 ;
    	    BerkeleyDB 		db ;
	    BerkeleyDB		RETVAL ;
	    static char * 		Names[] = {"", "Btree", "Hash", "Recno"} ;
	
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(file, "Filename", char *) ;
	    SetValue_ov(dbenv, "Env", BerkeleyDB__Env) ;
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
	    ZMALLOC(db, BerkeleyDB_type) ; 
	    if ((sv = readHash(hash, "Txn")) && sv != &sv_undef) {
		BerkeleyDB__Txn tmp = (BerkeleyDB__Txn)SvIV((SV*)SvRV(sv));
		db->txn = tmp->txn ;
	    }
	    
	    RETVAL = my_db_open(db, ref, ref_dbenv, dbenv, file, DB_UNKNOWN, flags, mode, &info) ;
	    XPUSHs(sv_2mortal(newSViv((IV)RETVAL)));
	    if (RETVAL)
	        XPUSHs(sv_2mortal(newSVpv(Names[RETVAL->type], 0))) ;
	    else
	        XPUSHs(sv_2mortal(newSViv((IV)NULL)));
	}



MODULE = BerkeleyDB::Btree	PACKAGE = BerkeleyDB::Btree	PREFIX = btree_

BerkeleyDB::Btree
_db_open_btree(self, ref)
	char *		self
	SV * 		ref
	CODE:
	{
	    HV *		hash ;
	    SV * 		sv ;
	    DB_INFO 		info ;
	    BerkeleyDB__Env	dbenv = NULL;
	    SV *		ref_dbenv = NULL;
	    const char *	file = NULL ;
	    int			flags = 0 ;
	    int			mode = 0 ;
    	    BerkeleyDB  	db ;
	
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(file, "Filename", char*) ;
	    SetValue_ov(dbenv, "Env", BerkeleyDB__Env) ;
	    ref_dbenv = sv ;
	    SetValue_iv(flags, "Flags") ;
	    SetValue_iv(mode, "Mode") ;

       	    Zero(&info, 1, DB_INFO) ;
	    SetValue_iv(info.db_cachesize, "Cachesize") ;
	    SetValue_iv(info.db_lorder, "Lorder") ;
	    SetValue_iv(info.db_pagesize, "Pagesize") ;
	    SetValue_iv(info.bt_minkey, "Minkey") ;
	    SetValue_iv(info.flags, "Property") ;
	    ZMALLOC(db, BerkeleyDB_type) ; 
	    if ((sv = readHash(hash, "Txn")) && sv != &sv_undef) {
		BerkeleyDB__Txn tmp = (BerkeleyDB__Txn)SvIV((SV*)SvRV(sv));
		db->txn = tmp->txn ;
	    }
	    if ((sv = readHash(hash, "Compare")) && sv != &sv_undef) {
		info.bt_compare = btree_compare ;
		db->compare = newSVsv(sv) ;
	    }
	    if ((sv = readHash(hash, "Prefix")) && sv != &sv_undef) {
		info.bt_prefix = btree_prefix ;
		db->prefix = newSVsv(sv) ;
	    }
	    
	    RETVAL = my_db_open(db, ref, ref_dbenv, dbenv, file, DB_BTREE, flags, mode, &info) ;
	}
	OUTPUT:
	    RETVAL


HV *
db_stat(db, flags=0)
	BerkeleyDB::Common	db
	int			flags
	HV *			RETVAL = NULL ;
	INIT:
	  ckActive_Database(db->active) ;
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
#if DB_VERSION_MAJOR == 2 && DB_VERSION_MINOR < 5
		hv_store_iv(RETVAL, "bt_freed", stat->bt_freed);
		hv_store_iv(RETVAL, "bt_pfxsaved", stat->bt_pfxsaved);
		hv_store_iv(RETVAL, "bt_split", stat->bt_split);
		hv_store_iv(RETVAL, "bt_rootsplit", stat->bt_rootsplit);
		hv_store_iv(RETVAL, "bt_fastsplit", stat->bt_fastsplit);
		hv_store_iv(RETVAL, "bt_added", stat->bt_added);
		hv_store_iv(RETVAL, "bt_deleted", stat->bt_deleted);
		hv_store_iv(RETVAL, "bt_get", stat->bt_get);
		hv_store_iv(RETVAL, "bt_cache_hit", stat->bt_cache_hit);
		hv_store_iv(RETVAL, "bt_cache_miss", stat->bt_cache_miss);
#endif
		hv_store_iv(RETVAL, "bt_int_pgfree", stat->bt_int_pgfree);
		hv_store_iv(RETVAL, "bt_leaf_pgfree", stat->bt_leaf_pgfree);
		hv_store_iv(RETVAL, "bt_dup_pgfree", stat->bt_dup_pgfree);
		hv_store_iv(RETVAL, "bt_over_pgfree", stat->bt_over_pgfree);
		hv_store_iv(RETVAL, "bt_magic", stat->bt_magic);
		hv_store_iv(RETVAL, "bt_version", stat->bt_version);
		safefree(stat) ;
	    }
	}
	OUTPUT:
	    RETVAL


MODULE = BerkeleyDB::Recno	PACKAGE = BerkeleyDB::Recno	PREFIX = recno_

BerkeleyDB::Recno
_db_open_recno(self, ref)
	char *		self
	SV * 		ref
	CODE:
	{
	    HV *		hash ;
	    SV * 		sv ;
	    DB_INFO 		info ;
	    BerkeleyDB__Env	dbenv = NULL;
	    SV *		ref_dbenv = NULL;
	    const char *	file = NULL ;
	    int			flags = 0 ;
	    int			mode = 0 ;
    	    BerkeleyDB 		db ;
	
	    hash = (HV*) SvRV(ref) ;
	    SetValue_pv(file, "Fname", char*) ;
	    SetValue_ov(dbenv, "Env", BerkeleyDB__Env) ;
	    ref_dbenv = sv ;
	    SetValue_iv(flags, "Flags") ;
	    SetValue_iv(mode, "Mode") ;

       	    Zero(&info, 1, DB_INFO) ;
	    SetValue_iv(info.db_cachesize, "Cachesize") ;
	    SetValue_iv(info.db_lorder, "Lorder") ;
	    SetValue_iv(info.db_pagesize, "Pagesize") ;
	    SetValue_iv(info.bt_minkey, "Minkey") ;

	    SetValue_iv(info.flags, "Property") ;
	    SetValue_pv(info.re_source, "Source", char*) ;
	    if ((sv = readHash(hash, "Len")) && sv != &sv_undef) {
		info.re_len = SvIV(sv) ; ;
		info.flags |= DB_FIXEDLEN ;
	    }
	    if ((sv = readHash(hash, "Delim")) && sv != &sv_undef) {
		info.re_delim = SvPOK(sv) ? *SvPV(sv,na) : SvIV(sv) ; ;
		info.flags |= DB_DELIMITER ;
	    }
	    if ((sv = readHash(hash, "Pad")) && sv != &sv_undef) {
		info.re_pad = (u_int32_t)SvPOK(sv) ? *SvPV(sv,na) : SvIV(sv) ; ;
		info.flags |= DB_PAD ;
	    }
	    ZMALLOC(db, BerkeleyDB_type) ; 
	    if ((sv = readHash(hash, "Txn")) && sv != &sv_undef) {
		BerkeleyDB__Txn tmp = (BerkeleyDB__Txn)SvIV((SV*)SvRV(sv));
		db->txn = tmp->txn ;
	    }
#ifdef ALLOW_RECNO_OFFSET
	    SetValue_iv(db->array_base, "ArrayBase") ;
	    db->array_base = (db->array_base == 0 ? 1 : 0) ;
#endif /* ALLOW_RECNO_OFFSET */
	    
	    RETVAL = my_db_open(db, ref, ref_dbenv, dbenv, file, DB_RECNO, flags, mode, &info) ;
	}
	OUTPUT:
	    RETVAL



MODULE = BerkeleyDB::Common  PACKAGE = BerkeleyDB::Common	PREFIX = dab_


DualType
db_close(db,flags=0)
        BerkeleyDB::Common 	db
	int 			flags
	INIT:
	    ckActive_Database(db->active) ;
	CODE:
	    CurrentDB = db ;
	    RETVAL =  db->Status = ((db->dbp)->close)(db->dbp, flags) ;
	    db->active = FALSE ;
	OUTPUT: 
	    RETVAL

void
dab_DESTROY(db)
	BerkeleyDB::Common	db
	CODE:
	  CurrentDB = db ;
	  Trace(("In BerkeleyDB::Common::DESTROY db %d dirty=%d\n", db, dirty)) ;
      	  if (! dirty && db->active) ((db->dbp)->close)(db->dbp, 0) ;
      	  if (db->hash)
        	  SvREFCNT_dec(db->hash) ;
      	  if (db->compare)
        	  SvREFCNT_dec(db->compare) ;
      	  if (db->prefix)
        	  SvREFCNT_dec(db->prefix) ;
      	  if (db->ref2env)
          	  SvREFCNT_dec(db->ref2env) ;
#ifdef ALLOW_KV_FILTER
          if (db->readKey)
              SvREFCNT_dec(db->readKey) ;
          if (db->writeKey)
              SvREFCNT_dec(db->writeKey) ;
          if (db->readValue)
              SvREFCNT_dec(db->readValue) ;
          if (db->writeValue)
              SvREFCNT_dec(db->writeValue) ;
#endif
	  hash_delete("BerkeleyDB::Term::Db", db->dbp) ;
          Safefree(db) ;
	  Trace(("End of BerkeleyDB::Common::DESTROY \n")) ;

#if DB_VERSION_MAJOR == 2 && DB_VERSION_MINOR < 6
#define db_cursor(db, txn, cur,flags)  ((db->dbp)->cursor)(db->dbp, txn, cur)
#else
#define db_cursor(db, txn, cur,flags)  ((db->dbp)->cursor)(db->dbp, txn, cur,flags)
#endif
BerkeleyDB::Cursor
db_cursor(db, flags=0)
        BerkeleyDB::Common 	db
	u_int32_t		flags 
        BerkeleyDB::Cursor 	RETVAL = NULL ;
	INIT:
	    ckActive_Database(db->active) ;
	CODE:
	{
	  DBC *		cursor ;
	  CurrentDB = db ;
	  if ((db->Status = db_cursor(db, db->txn, &cursor, flags)) == 0){
	      ZMALLOC(RETVAL, BerkeleyDB__Cursor_type) ;
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
	      RETVAL->active  = TRUE ;
#ifdef ALLOW_RECNO_OFFSET
	      RETVAL->array_base  = db->array_base ;
#endif /* ALLOW_RECNO_OFFSET */
#ifdef ALLOW_KV_FILTER
	      RETVAL->filtering   = FALSE ;
	      RETVAL->readKey     = db->readKey ;
	      RETVAL->writeKey    = db->writeKey ;
	      RETVAL->readValue   = db->readValue ;
	      RETVAL->writeValue  = db->writeValue ;
#endif
              /* RETVAL->info ; */
	      hash_store_iv("BerkeleyDB::Term::Cursor", cursor, 1) ;
	  }
	}
	OUTPUT:
	  RETVAL


int
ArrayOffset(db)
        BerkeleyDB::Common 	db
	INIT:
	    ckActive_Database(db->active) ;
	CODE:
#ifdef ALLOW_RECNO_OFFSET
	    RETVAL = db->array_base ? 0 : 1 ;
#else
	    RETVAL = 0 ;
#endif /* ALLOW_RECNO_OFFSET */
	OUTPUT: 
	    RETVAL

int
type(db)
        BerkeleyDB::Common 	db
	INIT:
	    ckActive_Database(db->active) ;
	CODE:
	    RETVAL = db->type ;
	OUTPUT: 
	    RETVAL

int
byteswapped(db)
        BerkeleyDB::Common 	db
	INIT:
	    ckActive_Database(db->active) ;
	CODE:
#if DB_VERSION_MAJOR == 2 && DB_VERSION_MINOR < 5
	    croak("byteswapped needs Berkeley DB 2.5 or later") ;
#else
	    RETVAL = db->dbp->byteswapped ;
#endif
	OUTPUT: 
	    RETVAL

DualType
status(db)
        BerkeleyDB::Common 	db
	CODE:
	    RETVAL =  db->Status ;
	OUTPUT: 
	    RETVAL

#ifdef ALLOW_KV_FILTER

#define setFilter(type)						\
	    if (db->type)					\
	        RETVAL = sv_2mortal(newSVsv(db->type)) ;	\
	    if (db->type && code == &sv_undef) {		\
                SvREFCNT_dec(db->type) ;			\
	        db->type = NULL ;				\
	    }							\
	    else if (code) {					\
	        if (db->type)					\
	            sv_setsv(db->type, code) ;			\
	        else						\
	            db->type = newSVsv(code) ;			\
	    }	    


SV *
ReadKey(db, code=NULL)
	BerkeleyDB::Common	db
	SV *			code
	SV *			RETVAL = NULL ;
	CODE:
	    setFilter(readKey) ;
	OUTPUT:
	    RETVAL

SV *
WriteKey(db, code=NULL)
	BerkeleyDB::Common	db
	SV *			code
	SV *			RETVAL = NULL ;
	CODE:
	    setFilter(writeKey) ;
	OUTPUT:
	    RETVAL

SV *
ReadValue(db, code=NULL)
	BerkeleyDB::Common	db
	SV *			code
	SV *			RETVAL = NULL ;
	CODE:
	    setFilter(readValue) ;
	OUTPUT:
	    RETVAL

SV *
WriteValue(db, code=NULL)
	BerkeleyDB::Common	db
	SV *			code
	SV *			RETVAL = NULL ;
	CODE:
	    setFilter(writeValue) ;
	OUTPUT:
	    RETVAL

#endif /* ALLOW_KV_FILTER */

void
partial_set(db, offset, length)
        BerkeleyDB::Common 	db
	u_int32_t		offset
	u_int32_t		length
	INIT:
	    ckActive_Database(db->active) ;
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
        BerkeleyDB::Common 	db
	INIT:
	    ckActive_Database(db->active) ;
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
DualType
db_del(db, key, flags=0)
	BerkeleyDB::Common	db
	DBTKEY		key
	u_int		flags
	INIT:
	    ckActive_Database(db->active) ;
	    CurrentDB = db ;


#define db_get(db, key, data, flags)   \
	(db->Status = ((db->dbp)->get)(db->dbp, db->txn, &key, &data, flags))
DualType
db_get(db, key, data, flags=0)
	BerkeleyDB::Common	db
	u_int		flags
	DBTKEY_B	key
	DBT		data = NO_INIT
	INIT:
	  ckActive_Database(db->active) ;
	  CurrentDB = db ;
	  SetPartial(data,db) ;
	OUTPUT:
	  key	if (flagSet(DB_SET_RECNO)) OutputValue(ST(1), key) ;
	  data  

#define db_put(db,key,data,flag)	\
		(db->Status = (db->dbp->put)(db->dbp,db->txn,&key,&data,flag))
DualType
db_put(db, key, data, flags=0)
	BerkeleyDB::Common	db
	DBTKEY			key
	DBT			data
	u_int			flags
	INIT:
	  ckActive_Database(db->active) ;
	  CurrentDB = db ;
	  /* SetPartial(data,db) ; */
	OUTPUT:
	  key	if (flagSet(DB_APPEND)) OutputKey(ST(1), key) ;

#define db_fd(d, x)	(db->Status = (db->dbp->fd)(db->dbp, &x))
DualType
db_fd(db)
	BerkeleyDB::Common	db
	INIT:
	  ckActive_Database(db->active) ;
	CODE:
	  CurrentDB = db ;
	  db_fd(db, RETVAL) ;
	OUTPUT:
	  RETVAL


#define db_sync(db, fl)	(db->Status = (db->dbp->sync)(db->dbp, fl))
DualType
db_sync(db, flags=0)
	BerkeleyDB::Common	db
	u_int			flags
	INIT:
	  ckActive_Database(db->active) ;
	  CurrentDB = db ;

void
Txn(db, txn)
        BerkeleyDB::Common      db
        BerkeleyDB::Txn         txn
	INIT:
	  ckActive_Database(db->active) ;
	  ckActive_Transaction(txn->active) ;
	CODE:
	   db->txn = txn->txn ;




MODULE = BerkeleyDB::Cursor              PACKAGE = BerkeleyDB::Cursor	PREFIX = cu_

DualType
c_close(db)
    BerkeleyDB::Cursor	db
	INIT:
	  CurrentDB = db ;
	  ckActive_Cursor(db->active) ;
	  db->active = FALSE ;
	CODE:
	    RETVAL =  db->Status =
    	      ((db->cursor)->c_close)(db->cursor) ;
	OUTPUT:
	  RETVAL

void
DESTROY(db)
    BerkeleyDB::Cursor	db
	CODE:
	  CurrentDB = db ;
	  Trace(("In BerkeleyDB::Cursor::DESTROY db %d dirty=%d\n", db, dirty));
	  hash_delete("BerkeleyDB::Term::Cursor", db->cursor) ;
	  if (db->active)
    	      ((db->cursor)->c_close)(db->cursor) ;
    	  if (db->ref2db)
       	 	   SvREFCNT_dec(db->ref2db) ;
          Safefree(db) ;
	  Trace(("End of BerkeleyDB::Cursor::DESTROY\n")) ;

DualType
status(db)
        BerkeleyDB::Cursor 	db
	CODE:
	    RETVAL =  db->Status ;
	OUTPUT: 
	    RETVAL


#define cu_c_del(c,f)	(c->Status = ((c->cursor)->c_del)(c->cursor,f))
DualType
cu_c_del(db, flags=0)
    BerkeleyDB::Cursor	db
    int			flags
	INIT:
	  CurrentDB = db ;
	  ckActive_Cursor(db->active) ;
	OUTPUT:
	  RETVAL


#define cu_c_get(c,k,d,f) (c->Status = (c->cursor->c_get)(c->cursor,&k,&d,f))
DualType
cu_c_get(db, key, data, flags=0)
    BerkeleyDB::Cursor	db
    int			flags
    DBTKEY_B		key
    DBT_B		data = NO_INIT
	INIT:
	  CurrentDB = db ;
	  ckActive_Cursor(db->active) ;
	  SetPartial(data,db) ;
	  /* key		if (! (flags & DB_GET_RECNO)) OutputKey_B(ST(1), key) ; */
	OUTPUT:
	  RETVAL
	  key		
	  data


#define cu_c_put(c,k,d,f)  (c->Status = (c->cursor->c_put)(c->cursor,&k,&d,f))
DualType
cu_c_put(db, key, data, flags=0)
    BerkeleyDB::Cursor	db
    DBTKEY		key
    DBT			data
    int			flags
	INIT:
	  CurrentDB = db ;
	  ckActive_Cursor(db->active) ;
	  /* SetPartial(data,db) ; */
	OUTPUT:
	  RETVAL





MODULE = BerkeleyDB::TxnMgr           PACKAGE = BerkeleyDB::TxnMgr	PREFIX = xx_

BerkeleyDB::Txn
txn_begin(txnmgr, pid=NULL)
	BerkeleyDB::TxnMgr	txnmgr
	BerkeleyDB::Txn		pid
	CODE:
	{
	    DB_TXN *txn ;
	    DB_TXN *p_id = NULL ;
	    if (txnmgr->env->Env.tx_info == NULL)
		croak("Transaction Manager not enabled") ;
	    if (pid)
		p_id = pid->txn ;
	    txnmgr->env->TxnMgrStatus = txn_begin(txnmgr->env->Env.tx_info, p_id, &txn) ;
	    if (txnmgr->env->TxnMgrStatus == 0) {
	      ZMALLOC(RETVAL, BerkeleyDB_Txn_type) ;
	      RETVAL->txn  = txn ;
	      RETVAL->active = TRUE ;
	      hash_store_iv("BerkeleyDB::Term::Txn", txn, 1) ;
		/* RETVAL = txn ; */
	    }
	    else
		RETVAL = NULL ;
	}
	OUTPUT:
	    RETVAL


DualType
status(mgr)
        BerkeleyDB::TxnMgr 	mgr
	CODE:
	    RETVAL =  mgr->env->TxnMgrStatus ;
	OUTPUT: 
	    RETVAL


void
DESTROY(mgr)
    BerkeleyDB::TxnMgr	mgr
	CODE:
	  Trace(("In BerkeleyDB::TxnMgr::DESTROY dirty=%d\n", dirty)) ;
          if (mgr->ref2env)
              SvREFCNT_dec(mgr->ref2env) ;
          Safefree(mgr) ;
	  Trace(("End of BerkeleyDB::TxnMgr::DESTROY\n")) ;

DualType
txn_close(txnp)
	BerkeleyDB::TxnMgr	txnp
        NOT_IMPLEMENTED_YET


#define xx_txn_checkpoint(t,k,m) txn_checkpoint(t->env->Env.tx_info, k, m)
DualType
xx_txn_checkpoint(txnp, kbyte, min)
	BerkeleyDB::TxnMgr	txnp
	long			kbyte
	long			min

HV *
txn_stat(txnp)
	BerkeleyDB::TxnMgr	txnp
	HV *			RETVAL = NULL ;
	CODE:
	{
	    DB_TXN_STAT *	stat ;
	    if(txn_stat(txnp->env->Env.tx_info, &stat, safemalloc) == 0) {
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


BerkeleyDB::TxnMgr
txn_open(dir, flags, mode, dbenv)
    const char *	dir
    int 		flags
    int 		mode
    BerkeleyDB::Env 	dbenv
        NOT_IMPLEMENTED_YET


MODULE = BerkeleyDB::Txn              PACKAGE = BerkeleyDB::Txn		PREFIX = xx_

DualType
status(tid)
        BerkeleyDB::Txn 	tid
	CODE:
	    RETVAL =  tid->Status ;
	OUTPUT: 
	    RETVAL

int
DESTROY(tid)
    BerkeleyDB::Txn	tid
	CODE:
	  Trace(("In BerkeleyDB::Txn::DESTROY dirty=%d\n", dirty)) ;
	  if (tid->active)
	    txn_abort(tid->txn) ;
          RETVAL = (int)tid ;
	  hash_delete("BerkeleyDB::Term::Txn", tid->txn) ;
          Safefree(tid) ;
	  Trace(("End of BerkeleyDB::Txn::DESTROY\n")) ;
	OUTPUT:
	  RETVAL

#define xx_txn_unlink(d,f,e)	txn_unlink(d,f,&(e->Env))
DualType
xx_txn_unlink(dir, force, dbenv)
    const char *	dir
    int 		force
    BerkeleyDB::Env 	dbenv
        NOT_IMPLEMENTED_YET

#define xx_txn_prepare(t) (t->Status = txn_prepare(t->txn))
DualType
xx_txn_prepare(tid)
	BerkeleyDB::Txn	tid
	INIT:
	    ckActive_Transaction(tid->active) ;

#define xx_txn_commit(t) (t->Status = txn_commit(t->txn))
DualType
xx_txn_commit(tid)
	BerkeleyDB::Txn	tid
	INIT:
	    ckActive_Transaction(tid->active) ;
	    tid->active = FALSE ;

#define xx_txn_abort(t) (t->Status = txn_abort(t->txn))
DualType
xx_txn_abort(tid)
	BerkeleyDB::Txn	tid
	INIT:
	    ckActive_Transaction(tid->active) ;
	    tid->active = FALSE ;

#define xx_txn_id(t) txn_id(t->txn)
u_int32_t
xx_txn_id(tid)
	BerkeleyDB::Txn	tid

MODULE = BerkeleyDB::_tiedHash        PACKAGE = BerkeleyDB::_tiedHash

int
FIRSTKEY(db)
        BerkeleyDB::Common         db
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
		(db->Status = db_cursor(db, db->txn, &cursor, 0)) == 0 )
	            db->cursor  = cursor ;
	    
	    if (db->cursor)
	        RETVAL = (db->Status) = 
		    ((db->cursor)->c_get)(db->cursor, &key, &value, DB_FIRST);
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
        BerkeleyDB::Common  db
        DBTKEY              key
        CODE:
        {
            DBT         value ;
 
            CurrentDB = db ;
	    key.flags = value.flags = 0 ;
	    RETVAL = (db->Status) =
		((db->cursor)->c_get)(db->cursor, &key, &value, DB_NEXT);

	    /* check for end of cursor */
	    if (RETVAL == DB_NOTFOUND) {
	      ((db->cursor)->c_close)(db->cursor) ;
	      db->cursor = NULL ;
	    }
            ST(0) = sv_newmortal();
	    OutputKey(ST(0), key) 
        }
 
MODULE = BerkeleyDB::_tiedArray        PACKAGE = BerkeleyDB::_tiedArray

I32       
FETCHSIZE(db)
        BerkeleyDB::Common         db
        CODE:
            CurrentDB = db ;
            RETVAL = GetArrayLength(db) ;
        OUTPUT:
            RETVAL


MODULE = BerkeleyDB        PACKAGE = BerkeleyDB

BOOT:
  {
    SV * ver_sv = perl_get_sv("BerkeleyDB::db_version", TRUE) ;
    int Major, Minor, Patch ;
    (void)db_version(&Major, &Minor, &Patch) ;
    sv_setpvf(ver_sv, "%d.%d", Major, Minor) ;

    empty.data  = &zero ;
    empty.size  =  sizeof(db_recno_t) ;
    empty.flags = 0 ;

  }

