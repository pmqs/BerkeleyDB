#! perl -w

# SCCS: 1.3, 10/23/97     

BEGIN { die "BerkDB needs Perl 5.004_02 or greater" if $] < 5.004_02 ; }

use strict ;
use ExtUtils::MakeMaker ;

my $LIB_DIR ;
my $INC_DIR ;

ParseCONFIG() ;

# OS2 is a special case, so check for it now.
my $OS2 = "" ;
$OS2 = "-DOS2" if $^O eq 'os2' ;

# Win32 is another special case.
my $libs = "-ldb" ;
$libs = "-llibdb" if $^O eq 'MSWin32' ;

# Solaris is too.
$libs .= " -lthread" if $^O eq 'solaris' ;

WriteMakefile(
	NAME 		=> 'BerkDB',
	LIBS 		=> ["-L${LIB_DIR} $libs"],
        MAN3PODS        => ' ',         # Pods will be built by installman.
	INC		=> "-I$INC_DIR",
	VERSION_FROM	=> 'BerkDB.pm',
	XSPROTOARG	=> '-noprototypes',
	DEFINE		=> "$OS2",
	'macro'		=> { INSTALLDIRS => 'perl' },
        'dist'          => {COMPRESS=>'gzip', SUFFIX=>'gz'},    
	);


sub MY::postamble {
	'
$(NAME).xs:	typemap
	@$(TOUCH) $(NAME).xs

Makefile:	config.in 

	' ;
}

sub ParseCONFIG
{
    my ($k, $v) ;
    my @badkey = () ;
    my %Info = () ;
    my @Options = qw( INCLUDE LIB ) ;
    my %ValidOption = map {$_, 1} @Options ;
    my %Parsed = %ValidOption ;
    my $CONFIG = 'config.in' ;

    print "Parsing $CONFIG...\n" ;

    open(F, "$CONFIG") or die "Cannot open file $CONFIG: $!\n" ;
    while (<F>) {
	s/^\s*|\s*$//g ;
	next if /^\s*$/ or /^\s*#/ ;
	s/\s*#\s*$// ;

	($k, $v) = split(/\s+=\s+/, $_, 2) ;
	$k = uc $k ;
	if ($ValidOption{$k}) {
	    delete $Parsed{$k} ;
	    $Info{$k} = $v ;
	}
	else {
	    push(@badkey, $k) ;
	}
    }
    close F ;

    print "Unknown keys in $CONFIG ignored [@badkey]\n"
	if @badkey ;

    # check parsed values
    my @missing = () ;
    die "The following keys are missing from $CONFIG file: [@missing]\n" 
        if @missing = keys %Parsed ;

    $INC_DIR = $Info{'INCLUDE'} ;
    $LIB_DIR = $Info{'LIB'} ;
    print "Looks Good.\n" ;

}

# end of file Makefile.PL
