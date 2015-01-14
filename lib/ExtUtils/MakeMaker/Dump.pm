package ExtUtils::MakeMaker::Dump;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(dump_makefile_pl_script);

our %SPEC;

$SPEC{dump_makefile_pl_script} = {
    v => 1.1,
    summary => 'Run a Makefile.PL script but only to '.
        'dump the %WriteMakefileArgs',
    description => <<'_',

This function runs `Makefile.PL` script that uses `ExtUtils::MakeMaker` but
monkey-patches beforehand so that `WriteMakefile()` will dump the argument and
then exit. The goal is to get the argument without actually running the script
to produce a Makefile.

This is used for example in `App::lcpan` project. When a release file does not
contain any `META.json` or `META.yml` file, the next best thing to try is to
extract this information from `Makefile.PL`. Since this is an executable script,
we'll need to run it, but we don't want to actually produce a Makefile, hence
the patch. (Another alternative would be to do a static analysis of the script.)

Note: `Makefile.PL` using `Module::Install` works too, because under the hood
it's still `ExtUtils::MakeMaker`.

_
    args => {
        filename => {
            summary => 'Path to the script',
            req => 1,
            schema => 'str*',
        },
        libs => {
            summary => 'Libraries to unshift to @INC when running script',
            schema  => ['array*' => of => 'str*'],
        },
    },
};
sub dump_makefile_pl_script {
    require Capture::Tiny;
    require UUID::Random;

    my %args = @_;

    my $filename = $args{filename} or return [400, "Please specify filename"];
    (-f $filename) or return [404, "No such file: $filename"];

    my $libs = $args{libs} // [];

    my $tag = UUID::Random::generate();
    my @cmd = (
        $^X, (map {"-I$_"} @$libs),
        "-MTimeout::Self=3", # to defeat scripts that prompts for stuffs
        "-MExtUtils::MakeMaker::Patch::DumpAndExit=-tag,$tag",
        $filename,
        "--version",
    );
    my ($stdout, $stderr, $exit) = Capture::Tiny::capture(
        sub { system @cmd },
    );

    my $wmf_args;
    if ($stdout =~ /^# BEGIN DUMP $tag\s+(.*)^# END DUMP $tag/ms) {
        $wmf_args = eval $1;
        if ($@) {
            return [500, "Error in eval-ing captured ".
                        "\\\%WriteMakefileArgs: $@, raw capture: <<<$1>>>"];
        }
        if (ref($wmf_args) ne 'HASH') {
            return [500, "Didn't get a hash \%WriteMakefileArgs, ".
                        "raw capture: stdout=<<$stdout>>"];
        }
    } else {
        return [500, "Can't capture \%WriteMakefileArgs, raw capture: ".
                    "stdout=<<$stdout>>, stderr=<<$stderr>>"];
    }

    [200, "OK", $wmf_args];
}

1;
# ABSTRACT:

=head1 SEE ALSO

L<Module::Build::Dump>
