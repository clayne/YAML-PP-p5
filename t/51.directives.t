#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Deep;
use FindBin '$Bin';
use YAML::PP;

my $yp = YAML::PP->new(
    emit_version_directive => 1,
    header => 0, # this should be overruled by emit_version_directive
);
my $yp_footer = YAML::PP->new(
    emit_version_directive => 1,
    footer => 1,
);

my @docs = (
    { a => 1 },
    [ b => 2 ],
    'c3',
);

my $yaml = $yp->dump_string(@docs);
my $yaml_footer = $yp_footer->dump_string(@docs);

my $exp = <<'EOM';
%YAML 1.2
---
a: 1
...
%YAML 1.2
---
- b
- 2
...
%YAML 1.2
--- c3
EOM
my $exp_footer = <<'EOM';
%YAML 1.2
---
a: 1
...
%YAML 1.2
---
- b
- 2
...
%YAML 1.2
--- c3
...
EOM

is($yaml, $exp, 'Emit version directive');
is($yaml_footer, $exp_footer, 'Emit version directive (footer=1)');

done_testing;
