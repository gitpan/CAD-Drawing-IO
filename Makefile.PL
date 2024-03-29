use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'CAD::Drawing::IO',
    'VERSION_FROM'	=> 'IO.pm', # finds $VERSION
    'PREREQ_PM'		=> {
        },
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'IO.pm', # retrieve abstract from module
       AUTHOR     => 'Eric L. Wilhelm <ewilhelm at sbcglobal dot net>') : ()),
);
