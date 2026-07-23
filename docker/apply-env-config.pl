#!/usr/bin/perl
# Runtime: override ANY kivitendo.conf setting from the environment.
# Intended for 12-factor / Kubernetes deployments (ConfigMap + Secret).
#
# Convention:  KIVI_<SECTION>__<KEY> = value
#   <SECTION> : the .conf section, uppercased, with '/' and '-' written as '_'
#               e.g. [authentication/database] -> AUTHENTICATION_DATABASE
#                    [mail_delivery]           -> MAIL_DELIVERY
#   <KEY>     : the key, uppercased (its own underscores kept)
#   separator : a DOUBLE underscore '__' between section and key
#
# Examples:
#   KIVI_AUTHENTICATION__ADMIN_PASSWORD=s3cret
#   KIVI_AUTHENTICATION_DATABASE__HOST=db.internal
#   KIVI_MAIL_DELIVERY__HOST=smtp.example.com
#   KIVI_SYSTEM__DEFAULT_LANGUAGE=de
#
# Only the keys named in the environment are changed; every other setting and
# all of the documentation comments in kivitendo.conf are left untouched. A
# commented-out key is uncommented and set; a missing key is appended to its
# section; a missing section is created.
use strict;
use warnings;

my $conf = $ENV{KIVITENDO_CONF} || '/opt/kivitendo-erp/config/kivitendo.conf';

# Collect overrides from the environment.
my @overrides;
for my $name (sort keys %ENV) {
    next unless $name =~ /^KIVI_(.+?)__(.+)$/;
    push @overrides, { sec_norm => uc($1), key => lc($2), val => $ENV{$name}, name => $name };
}
exit 0 unless @overrides;

open my $in, '<', $conf or die "open $conf: $!";
my @lines = <$in>;
close $in;

# Map normalized section name -> the canonical name as written in the file.
my %canonical;
for (@lines) {
    next unless /^\s*\[([^\]]+)\]\s*$/;
    my $section = $1;                       # capture before the s/// below,
    (my $norm = uc $section) =~ s{[/\-]}{_}g;  # which would reset $1
    $canonical{$norm} = $section;
}

for my $o (@overrides) {
    my $section = $canonical{ $o->{sec_norm} };
    if (!defined $section) {
        $section = lc $o->{sec_norm};             # unknown -> create it
        push @lines, "\n[$section]\n";
        $canonical{ $o->{sec_norm} } = $section;
    }
    apply_override(\@lines, $section, $o->{key}, $o->{val});
    print "config override: [$section] $o->{key} (from \$$o->{name})\n";
}

open my $out, '>', $conf or die "write $conf: $!";
print $out @lines;
close $out;
exit 0;

sub apply_override {
    my ($lines, $section, $key, $val) = @_;
    my ($in_section, $done) = (0, 0);

    for (my $i = 0; $i <= $#$lines; $i++) {
        my $line = $lines->[$i];

        if ($line =~ /^\s*\[([^\]]+)\]\s*$/) {
            # Leaving the target section without having found the key: insert it.
            if ($in_section && !$done) {
                splice @$lines, $i, 0, "$key = $val\n";
                $done = 1;
            }
            $in_section = ($1 eq $section) ? 1 : 0;
            next;
        }

        next unless $in_section && !$done;

        # Match "key = ..." or a commented "# key = ..."; replace in place.
        if ($line =~ /^\s*#?\s*\Q$key\E\s*=/) {
            $lines->[$i] = "$key = $val\n";
            $done = 1;
        }
    }

    # Target section ran to end of file without the key present: append it.
    push @$lines, "$key = $val\n" if $in_section && !$done;
}
