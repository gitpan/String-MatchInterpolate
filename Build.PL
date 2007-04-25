use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new
  (
   module_name => 'String::MatchInterpolate',
   dist_version_from => 'lib/String/MatchInterpolate.pm',
   requires => {
                 'Text::Balanced' => 0,
               },
   build_requires => {
                 'Test::More' => 0,
                 'Test::Exception' => 0,
               },
   license => 'perl',
   create_makefile_pl => 'traditional',
  );
  
$build->create_build_script;
