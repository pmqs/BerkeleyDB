
package BerkDB;


#     Copyright (c) 1997 Paul Marquess. All rights reserved.
#     This program is free software; you can redistribute it and/or
#     modify it under the same terms as Perl itself.
#
# SCCS: 1.6, 10/23/97  

# The documentation for this module is at the bottom of this file,
# after the line __END__.

BEGIN { require 5.004_02 }

use strict;
use Carp;
use vars qw($VERSION @ISA @EXPORT $AUTOLOAD);

$VERSION = '0.01';

require Exporter;
require DynaLoader;
require AutoLoader;
use FileHandle ;

@ISA = qw(Exporter DynaLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	DBM_INSERT
	DBM_REPLACE
	DBM_SUFFIX
	DB_AFTER
	DB_AM_DUP
	DB_AM_INMEM
	DB_AM_LOCKING
	DB_AM_LOGGING
	DB_AM_MLOCAL
	DB_AM_PGDEF
	DB_AM_RDONLY
	DB_AM_RECOVER
	DB_AM_SWAP
	DB_AM_THREAD
	DB_APPEND
	DB_ARCH_ABS
	DB_ARCH_DATA
	DB_ARCH_LOG
	DB_BEFORE
	DB_BTREEMAGIC
	DB_BTREEOLDVER
	DB_BTREEVERSION
	DB_BT_RECNUM
	DB_CHECKPOINT
	DB_CREATE
	DB_CURRENT
	DB_DBT_INTERNAL
	DB_DBT_MALLOC
	DB_DBT_PARTIAL
	DB_DBT_USERMEM
	DB_DELETED
	DB_DELIMITER
	DB_DUP
	DB_ENV_APPINIT
	DB_ENV_STANDALONE
	DB_ENV_THREAD
	DB_EXCL
	DB_FILE_ID_LEN
	DB_FIRST
	DB_FIXEDLEN
	DB_FLUSH
	DB_GET_RECNO
	DB_HASHMAGIC
	DB_HASHOLDVER
	DB_HASHVERSION
	DB_HS_DIRTYMETA
	DB_INCOMPLETE
	DB_INIT_LOCK
	DB_INIT_LOG
	DB_INIT_MPOOL
	DB_INIT_TXN
	DB_KEYEMPTY
	DB_KEYEXIST
	DB_KEYFIRST
	DB_KEYLAST
	DB_LAST
	DB_LOCKMAGIC
	DB_LOCKVERSION
	DB_LOCK_CONFLICT
	DB_LOCK_DEADLOCK
	DB_LOCK_DEFAULT
	DB_LOCK_NORUN
	DB_LOCK_NOTGRANTED
	DB_LOCK_NOTHELD
	DB_LOCK_NOWAIT
	DB_LOCK_OLDEST
	DB_LOCK_RANDOM
	DB_LOCK_RIW_N
	DB_LOCK_RW_N
	DB_LOCK_YOUNGEST
	DB_LOGMAGIC
	DB_LOGOLDVER
	DB_LOGVERSION
	DB_MAX_PAGES
	DB_MAX_RECORDS
	DB_MPOOL_CLEAN
	DB_MPOOL_CREATE
	DB_MPOOL_DIRTY
	DB_MPOOL_DISCARD
	DB_MPOOL_LAST
	DB_MPOOL_NEW
	DB_MPOOL_PRIVATE
	DB_MUTEXDEBUG
	DB_NEEDSPLIT
	DB_NEXT
	DB_NOMMAP
	DB_NOOVERWRITE
	DB_NOSYNC
	DB_NOTFOUND
	DB_PAD
	DB_PREV
	DB_RDONLY
	DB_RECNUM
	DB_RECORDCOUNT
	DB_RECOVER
	DB_RECOVER_FATAL
	DB_REGISTERED
	DB_RENUMBER
	DB_RE_DELIMITER
	DB_RE_FIXEDLEN
	DB_RE_PAD
	DB_RE_RENUMBER
	DB_RE_SNAPSHOT
	DB_SEQUENTIAL
	DB_SET
	DB_SET_RANGE
	DB_SET_RECNO
	DB_SNAPSHOT
	DB_SWAPBYTES
	DB_TEMPORARY
	DB_THREAD
	DB_TRUNCATE
	DB_TXNMAGIC
	DB_TXNVERSION
	DB_TXN_BACKWARD_ROLL
	DB_TXN_CKP
	DB_TXN_FORWARD_ROLL
	DB_TXN_LOCK_2PL
	DB_TXN_LOCK_MASK
	DB_TXN_LOCK_OPTIMISTIC
	DB_TXN_LOG_MASK
	DB_TXN_LOG_REDO
	DB_TXN_LOG_UNDO
	DB_TXN_LOG_UNDOREDO
	DB_TXN_NOSYNC
	DB_TXN_OPENFILES
	DB_TXN_REDO
	DB_TXN_UNDO
	DB_USE_ENVIRON
	DB_USE_ENVIRON_ROOT
	DB_VERSION_MAJOR
	DB_VERSION_MINOR
	DB_VERSION_PATCH
);

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

    my $constname;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    my $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
	if ($! =~ /Invalid/) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	}
	else {
		croak "Your vendor has not defined BerkDB macro $constname";
	}
    }
    eval "sub $AUTOLOAD { $val }";
    goto &$AUTOLOAD;
}

bootstrap BerkDB $VERSION;

# Preloaded methods go here.


sub ParseParameters($@)
{
    my ($default, @rest) = @_ ;
    my (%got) = %$default ;
    my (@Bad) ;
    my ($key, $value) ;
    my $sub = (caller(1))[3] ;
    my %options = () ;
    local ($Carp::CarpLevel) = 1 ;

    # allow the options to be passed as a hash reference or
    # as the complete hash.
    if (@rest == 1) {

        croak "$sub: parameter is not a reference to a hash"
            if ref $rest[0] ne "HASH" ;

        %options = %{ $rest[0] } ;
    }
    elsif (@rest >= 2) {
        %options = @rest ;
    }

    while (($key, $value) = each %options)
    {
	$key =~ s/^-// ;

        if (exists $default->{$key})
          { $got{$key} = $value }
        else
	  { push (@Bad, $key) }
    }
    
    if (@Bad) {
        my ($bad) = join(", ", @Bad) ;
        croak "unknown key value(s) @Bad" ;
    }

    return \%got ;
}


package BerkDB::Env ;

use UNIVERSAL qw( isa ) ;
use Carp ;

sub isaFilehandle
{
    my $fh = shift ;

    return ((isa($fh,'GLOB') or isa(\$fh,'GLOB')) and defined fileno($fh) )

}

sub new
{
    # Usage:
    #
    #	$env = new BerkDB::Env
    #			[ -Home		=> $path, ]
    #			[ -Config	=> { name => value, name => value }
    #			[ -ErrFile   	=> filename or filehandle, ]
    #			[ -ErrPrefix 	=> "string", ]
    #			[ -Flags	=> DB_INIT_LOCK| ]
    #			[ -Verbose	=> boolean ]
    #			[ -LockMax	=> number ]
    #			[ -LogMax	=> number ]
    #			[ -TxnMax	=> number ]
    #			;

    my $pkg = shift ;
    my $got = BerkDB::ParseParameters({
					Home		=> undef,
					ErrFile  	=> undef,
					ErrPrefix 	=> undef,
					Flags     	=> 0,
					Verbose		=> 0,
					Config		=> undef,
					LockMax		=> 0,
					LogMax		=> 0,
					TxnMax		=> 0,
					}, @_) ;

    if (defined $got->{ErrFile}) {
	if (!isaFilehandle($got->{ErrFile})) {
	    my $handle = new FileHandle ">$got->{ErrFile}"
		or croak "Cannot open file $got->{ErrFile}: $!\n" ;
	    $got->{ErrFile} = $handle ;
	}
    }

    
    if (defined $got->{Config}) {
    	croak("Config parameter must be a hash reference")
            if ! ref $got->{Config} eq 'HASH' ;

        @BerkDB::a = () ;
	my $k = "" ; my $v = "" ;
	while (($k, $v) = each %{$got->{Config}}) {
	    push @BerkDB::a, "$k\t$v" ;
	}

        $got->{"Config"} = pack("p*", @BerkDB::a, undef) 
	    if @BerkDB::a ;
    }

    my $obj =  _db_appinit($got) ;
    bless $obj, $pkg if $obj ;

    return $obj ;

}

#*Hash = \&BerkDB::Hash::new ;

package BerkDB::Hash ;

use vars qw(@ISA) ;
@ISA = qw( BerkDB::Common BerkDB::_tiedHash ) ;
use UNIVERSAL qw( isa ) ;
use Carp ;

sub new
{
    my $self = shift ;
    my $got = BerkDB::ParseParameters(
		      {
			# Generic Stuff
			Filename 	=> undef,
			#Flags		=> BerkDB::DB_CREATE(),
			Flags		=> 0,
			Property	=> 0,
			Mode		=> 0666,
			Cachesize 	=> 0,
			Lorder 		=> 0,
			Pagesize 	=> 0,
			Env		=> undef,
			#Tie 		=> undef,
			Txn		=> undef,

			# Hash specific
			Ffactor		=> 0,
			Nelem 		=> 0,
			Hash 		=> undef,
		      }, @_) ;

    croak("Env not of type BerkDB::Env")
	if defined $got->{Env} and ! isa($got->{Env},'BerkDB::Env');

    croak("Txn not of type BerkDB::Txn")
	if defined $got->{Txn} and ! isa($got->{Txn},'BerkDB::Txn');

    croak("-Tie needs a reference to a hash")
	if defined $got->{Tie} and $got->{Tie} !~ /HASH/ ;

    my $obj = _db_open_hash($got);
    if ($obj) {
        bless $obj, $self ;

        tie %{ $got->{Tie} }, $self, $obj 
            if $got->{Tie};

    }

    return $obj ;
}

*TIEHASH = \&new ;
#sub TIEHASH  
#{ 
#    my $self = shift ;
#
#    return $self->new(@_) ;
#}

package BerkDB::Common ;

sub Tie
{
    # Usage:
    #
    #   $db->Tie \%hash ;
    #

    my $self = shift ;

print "Tie method REF=[$self] [" . (ref $self) . "]\n" ;

    croak("usage \$x->Tie \\%hash\n") unless @_ ;
    my $ref  = shift ; 

    croak("Tie needs a reference to a hash")
	if defined $ref and $ref !~ /HASH/ ;

    #tie %{ $ref }, ref($self), $self ; 
    tie %{ $ref }, "BerkDB::_tiedHash", $self ; 
    return undef ;
}

package BerkDB::_tiedHash ;

sub TIEHASH  
{ 
    my $self = shift ;
    my $db_object = shift ;

print "Tiehash REF=[$self] [" . (ref $self) . "]\n" ;

    return bless { Obj => $db_object}, $self ; 
}

sub STORE
{
    my $self = shift ;
    my $key  = shift ;
    my $value = shift ;

    $self->db_put($key, $value) ;
}

sub FETCH
{
    my $self = shift ;
    my $key  = shift ;
    my $value = undef ;
    $self->db_get($key, $value) ;

    return $value ;
}

sub EXISTS
{
    my $self = shift ;
    my $key  = shift ;
    my $value = undef ;
    $self->db_get($key, $value) == 0 ;
}

sub DELETE
{
    my $self = shift ;
    my $key  = shift ;
    $self->db_del($key) ;
}

sub CLEAR
{
    my $self = shift ;
    my ($key, $value) = (0, 0) ;
    my $cursor = $self->db_cursor() ;
    while ($cursor->c_get($key, $value, BerkDB::DB_NEXT()) == 0) 
	{ $cursor->c_del() }
    #1 while $cursor->c_del() == 0 ;
    # cursor will self-destruct
}

sub DESTROY
{
    my $self = shift ;
    print "BerkDB::_tieHash::DESTROY\n" ;
    $self->{Cursor}->c_close() if $self->{Cursor} ;
}

package BerkDB::Btree ;

use vars qw(@ISA) ;
@ISA = qw( BerkDB::Common BerkDB::_tiedHash ) ;
use UNIVERSAL qw( isa ) ;
use Carp ;

sub new
{
    my $self = shift ;
    my $got = BerkDB::ParseParameters(
		      {
			# Generic Stuff
			Filename 	=> undef,
			#Flags		=> BerkDB::DB_CREATE(),
			Flags		=> 0,
			Property	=> 0,
			Mode		=> 0666,
			Cachesize 	=> 0,
			Lorder 		=> 0,
			Pagesize 	=> 0,
			Env		=> undef,
			#Tie 		=> undef,
			Txn		=> undef,

			# Btree specific
			Minkey		=> 0,
			Compare		=> undef,
			Prefix 		=> undef,
		      }, @_) ;

    croak("Env not of type BerkDB::Env")
	if defined $got->{Env} and ! isa($got->{Env},'BerkDB::Env');

    croak("Txn not of type BerkDB::Txn")
	if defined $got->{Txn} and ! isa($got->{Txn},'BerkDB::Txn');

    croak("-Tie needs a reference to a hash")
	if defined $got->{Tie} and $got->{Tie} !~ /HASH/ ;

    my $obj = _db_open_btree($got);
    if ($obj) {
        bless $obj, $self ;

        tie %{ $got->{Tie} }, $self, $obj 
            if $got->{Tie};

    }

    return $obj ;
}

*BerkDB::Btree::TIEHASH = \&BerkDB::Btree::new ;


package BerkDB::Recno ;

sub db_open
{
    my $pkg = shift ;
    my $got = BerkDB::ParseParameters({Filename => undef,
					Flags	=> BerkDB::DB_CREATE(),
					Mode	=> 0666,
					Env	=> undef,
					Info	=> undef}, @_) ;

    print "filename is undef\n" if $got->{Filename} eq undef ;
    my $filename = $got->{Filename} ;
    #BerkDB::_db_open(($got->{Filename} eq undef) ? undef : $got->{Filename}, BerkDB::DB_HASH(), $got->{Flags},
    BerkDB::_db_open($got->{Filename}, BerkDB::DB_RECNO(), $got->{Flags},
		$got->{Mode}, ) ; #$got->{Env}, $got->{Info}) ;
}

package BerkDB ;



# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__


