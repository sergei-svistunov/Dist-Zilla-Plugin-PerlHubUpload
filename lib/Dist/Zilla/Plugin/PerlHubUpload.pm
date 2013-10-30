package Dist::Zilla::Plugin::PerlHubUpload;

use Moose;

with 'Dist::Zilla::Role::Releaser';

use Path::Class qw(dir);
use File::pushd qw(pushd);
use File::Temp;
use Archive::Tar;
use Dpkg::Changelog::Parse;

has debuild_args => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => '-S -sa',
);

has dput_args => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => '',
);

sub release {
    my ($self, $archive) = @_;
    $archive = $archive->absolute;

    my $build_root = $self->zilla->root->subdir('.build');
    $build_root->mkpath unless -d $build_root;

    my $tmpdir = dir(File::Temp::tempdir(DIR => $build_root));

    $self->log("Extracting $archive to $tmpdir");

    my @files = do {
        my $pushd = pushd($tmpdir);
        Archive::Tar->extract_archive("$archive");
    };

    $self->log_fatal(["Failed to extract archive: %s", Archive::Tar->error])
      unless @files;

    my $pushd = pushd("$tmpdir/$files[0]");

    $self->_run_cmd(
        'debuild ' . $self->debuild_args . ' 2>&1',
        'Building source package',
        'Failed to build source package'
    );

    my $changelog = changelog_parse(file => 'debian/changelog');

    my $changes_fn = '../' . join('_', $changelog->{'Source'}, $changelog->{'Version'}, 'source.changes');

    my $tmp_file = File::Temp->new();
    print $tmp_file q{[perlhub]
fqdn = perlhub.ru
incoming = /dput_upload/
allow_dcut = 1
method = http
run_dinstall = 0};

    $self->_run_cmd(
        "dput --config $tmp_file " . $self->dput_args . " perlhub $changes_fn 2>&1",
        'Uploading source package',
        'Failed to upload source package'
    );

    undef($pushd);
    $tmpdir->rmtree;
}

sub _run_cmd {
    my ($self, $cmd, $desc, $error) = @_;

    $self->log("$desc:");
    print STDERR "$cmd\n";
    open(my $fh, "$cmd |") || $self->log_fatal('Cannot run `$cmd`: $!');
    while (<$fh>) {
        chomp;
        $self->log("  $_");
        print STDERR "  $_\n";
    }
    close($fh);

    $self->log_fatal($error) if $?;
}

1;

__END__

=pod

=head1 NAME

Dist::Zilla::Plugin::PerlHubUpload - build and upload source package to perlhub.ru

=head1 DESCRIPTION

It does not generate debian/* files, you must create them by yourself in advance.

=head1 ATTRIBUTES

=head2 debuild_args

`debuild` command arguments, default: '-S -sa'.

=head2 dput_args

`dput` command arguments, default: ''.

=head1 AUTHOR

Sergei Svistunov <svistunov@cpan.org>

=cut
