use strict;
use warnings;
package YAML::PP::Lexer;

our $VERSION = '0.000'; # VERSION

use constant TRACE => $ENV{YAML_PP_TRACE};
use constant DEBUG => $ENV{YAML_PP_DEBUG} || $ENV{YAML_PP_TRACE};

use YAML::PP::Grammar qw/ $GRAMMAR /;

use constant NODE_TYPE => 0;
use constant NODE_OFFSET => 1;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    $self->init;
    return $self;
}

sub init {
    $_[0]->{next_tokens} = [];
    $_[0]->{line} = 1;
}

sub next_tokens { return $_[0]->{next_tokens} }
sub line { return $_[0]->{line} }
sub set_line { $_[0]->{line} = $_[1] }
sub inc_line { return $_[0]->{line}++ }

my $RE_WS = '[\t ]';
my $RE_LB = '[\r\n]';
my $RE_DOC_END = qr/\A(\.\.\.)(?=$RE_WS|$)/m;
my $RE_DOC_START = qr/\A(---)(?=$RE_WS|$)/m;
my $RE_EOL = qr/\A($RE_WS+#.*|$RE_WS+)?(?:$RE_LB|\z)/;
my $RE_COMMENT_EOL = qr/\A(#.*)?(?:$RE_LB|\z)/;

#ns-word-char    ::= ns-dec-digit | ns-ascii-letter | “-”
my $RE_NS_WORD_CHAR = '[0-9A-Za-z-]';
my $RE_URI_CHAR = '(?:' . '%[0-9a-fA-F]{2}' .'|'.  q{[0-9A-Za-z#;/?:@&=+$,_.!*'\(\)\[\]-]} . ')';
my $RE_NS_TAG_CHAR = '(?:' . '%[0-9a-fA-F]{2}' .'|'.  q{[0-9A-Za-z#;/?:@&=+$_.*'\(\)-]} . ')';

#  [#x21-#x7E]          /* 8 bit */
# | #x85 | [#xA0-#xD7FF] | [#xE000-#xFFFD] /* 16 bit */
# | [#x10000-#x10FFFF]                     /* 32 bit */

#nb-char ::= c-printable - b-char - c-byte-order-mark
#my $RE_NB_CHAR = '[\x21-\x7E]';
my $RE_ANCHOR_CAR = '[\x21-\x2B\x2D-\x5A\x5C\x5E-\x7A\x7C\x7E]';

#my $RE_PLAIN_START = '[\x21\x22\x24-\x7E]';
my $RE_PLAIN_START = '[\x21\x22\x24-\x39\x3B-\x7E]';
my $RE_PLAIN = '[\x21-\x7E]';
my $RE_PLAIN_END = '[\x21-\x39\x3B-\x7E]';
#my $RE_PLAIN_FIRST = '[\x24\x28-\x29\x2B\x2E-\x3D\x41-\x5A\x5C\x5E-\x5F\x61-\x7A\x7E]';
my $RE_PLAIN_FIRST = '[\x24\x28-\x29\x2B\x2E-\x39\x3B-\x3D\x41-\x5A\x5C\x5E-\x5F\x61-\x7A\x7E]';
# c-indicators
#! 21
#" 22
## 23
#% 25
#& 26
#' 27
#* 2A
#, 2C FLOW
#- 2D XX
#: 3A XX
#> 3E
#? 3F XX
#@ 40
#[ 5B FLOW
#] 5D FLOW
#` 60
#{ 7B FLOW
#| 7C
#} 7D FLOW


our $RE_INT = '[+-]?[1-9]\d*';
our $RE_OCT = '0o[1-7][0-7]*';
our $RE_HEX = '0x[1-9a-fA-F][0-9a-fA-F]*';
our $RE_FLOAT = '[+-]?(?:\.\d+|\d+\.\d*)(?:[eE][+-]?\d+)?';
our $RE_NUMBER ="'(?:$RE_INT|$RE_OCT|$RE_HEX|$RE_FLOAT)";

#my $RE_PLAIN_WORD = "$RE_PLAIN_START(?:$RE_PLAIN_END|$RE_PLAIN*$RE_PLAIN_END)?";
my $RE_PLAIN_WORD = "(?::$RE_PLAIN_START|$RE_PLAIN_START)(?::$RE_PLAIN_END|$RE_PLAIN_END)*";
my $RE_PLAIN_FIRST_WORD1 = "(?:[:]$RE_PLAIN_END|$RE_PLAIN_FIRST)(?::$RE_PLAIN_END|$RE_PLAIN_END)*";
my $RE_PLAIN_FIRST_WORD2 = "(?:[?-]$RE_PLAIN_END|$RE_PLAIN_FIRST)(?::$RE_PLAIN_END|$RE_PLAIN_END)*";
#my $RE_PLAIN_FIRST_WORD2 = "(?:$RE_PLAIN_FIRST$RE_PLAIN*$RE_PLAIN_END)";
#my $RE_PLAIN_FIRST_WORD3 = "(?:$RE_PLAIN_FIRST$RE_PLAIN_END?)";
#my $RE_PLAIN_FIRST_WORD = "(?:$RE_PLAIN_FIRST_WORD1|$RE_PLAIN_FIRST_WORD2|$RE_PLAIN_FIRST_WORD3)";
my $RE_PLAIN_FIRST_WORD = "(?:$RE_PLAIN_FIRST_WORD1|$RE_PLAIN_FIRST_WORD2)";
my $RE_PLAIN_KEY = "(?:$RE_PLAIN_FIRST_WORD(?:$RE_WS+$RE_PLAIN_WORD)*|)";
#my $key_content_re_dq = '[^"\r\n\\\\]';
#my $key_content_re_sq = q{[^'\r\n]};
#my $key_re_double_quotes = qr{"(?:\\\\|\\[^\r\n]|$key_content_re_dq)*"};
#my $key_re_single_quotes = qr{'(?:\\\\|''|$key_content_re_sq)*'};
#my $key_full_re = qr{(?:$key_re_double_quotes|$key_re_single_quotes|$RE_PLAIN_KEY)};
my $key_full_re = qr{$RE_PLAIN_KEY};

my $plain_start_word_re = '[^*!&\s#][^\r\n\s]*';
my $plain_word_re = '[^#\r\n\s][^\r\n\s]*';


#c-secondary-tag-handle  ::= “!” “!”
#c-named-tag-handle  ::= “!” ns-word-char+ “!”
#ns-tag-char ::= ns-uri-char - “!” - c-flow-indicator
#ns-global-tag-prefix    ::= ns-tag-char ns-uri-char*
#c-ns-local-tag-prefix   ::= “!” ns-uri-char*
my $RE_TAG = "!(?:$RE_NS_WORD_CHAR*!$RE_NS_TAG_CHAR+|$RE_NS_TAG_CHAR+|<$RE_URI_CHAR+>|)";

#c-ns-anchor-property    ::= “&” ns-anchor-name
#ns-char ::= nb-char - s-white
#ns-anchor-char  ::= ns-char - c-flow-indicator
#ns-anchor-name  ::= ns-anchor-char+
my $RE_ANCHOR = "$RE_ANCHOR_CAR+";

my $RE_SEQSTART = qr/\A(-)(?=$RE_WS|$)/m;
my $RE_COMPLEX = qr/(\?)(?=$RE_WS|$)/m;
my $RE_COMPLEXCOLON = qr/\A(:)(?=$RE_WS|$)/m;
my $RE_ALIAS = qr/(\*$RE_ANCHOR)/m;


my %REGEXES = (
    ANCHOR => qr{(&$RE_ANCHOR)},
    TAG => qr{($RE_TAG)},
    EOL => qr{($RE_EOL)},
    EMPTY => qr{($RE_COMMENT_EOL)},
    LB => qr{($RE_LB)},
    WS => qr{($RE_WS*)},
    'WS' => qr{($RE_WS+)},
    SCALAR => qr{($RE_PLAIN_KEY)},
    ALIAS => qr{$RE_ALIAS},
    QUESTION => qr{$RE_COMPLEX},
    COLON => qr{(?m:(:)(?=$RE_WS|$))},
    DASH => qr{(?m:(-)(?=$RE_WS|$))},
    DOUBLEQUOTE => qr{(")},
    DOUBLEQUOTED => qr{((?:\\(?:.|$)|[^"\r\n\\])*)}m,
    SINGLEQUOTE => qr{(')},
    SINGLEQUOTED => qr{((?:''|[^'\r\n])*)},
    LITERAL => qr{(\|)},
    FOLDED => qr{(>)},
    FLOW_MAP_START => qr{(\{)},
    FLOW_SEQ_START => qr{(\[)},
);

sub parse_tokens {
    my ($self, $parser, %args) = @_;
    my $rules = $parser->rules;
    my $callback = $args{callback};
    my $tokens = $parser->tokens;
    my $new_type;
    my $ok = 0;

    TRACE and $parser->debug_rules($rules);
    TRACE and $parser->debug_yaml;
    DEBUG and $parser->debug_next_line;

    my $next_tokens = $self->next_tokens;
    RULE: while (my $next_rule = shift @$rules) {
        TRACE and warn __PACKAGE__.':'.__LINE__.": !!!!! $next_rule\n";
        if (ref $next_rule eq 'HASH') {
            my $success;
            my $next = $next_tokens->[0];
            TRACE and warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$next], ['next']);
            my $def = $next_rule->{ $next->[0] };
            if ($def) {
                shift @$next_tokens;
                push @$tokens, $next;
            }
            if (not $def and $next->[0] eq 'WS') {
                $def = $next_rule->{ 'WS?' };
                shift @$next_tokens;
                push @$tokens, $next;
            }
            if (not $def) {
                $def = $next_rule->{ 'WS?' };
            }
            if (not $def) {
                $def = $next_rule->{DEFAULT};
                TRACE and warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$def], ['def']);
            }
            if ($def) {
                DEBUG and $parser->got("---got $next->[0]");
                my ($sub, $next_rule) = @$def;
                $ok = 1;
                $success = 1;
                if ($sub) {
                    $callback->($parser, $sub);
                }
                if (ref $next_rule eq 'HASH') {
                    @$rules = $next_rule;
                }
                else {
                    @$rules = @$next_rule;
                }
            }
            else {
                DEBUG and $parser->not("---not $next->[0]");
                unless (@$rules) {
                    return (0);
                }
            }
            next RULE;
        }
        elsif (ref $next_rule eq 'SCALAR') {
            TRACE and warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([$next_rule], ['next_rule']);
            DEBUG and $parser->got("NEW: $$next_rule");
            if (exists $GRAMMAR->{ $$next_rule }) {
                my $new = $GRAMMAR->{ $$next_rule };
                if (ref $new eq 'HASH') {
                    unshift @$rules, $new;
                }
                else {
                    unshift @$rules, @$new;
                }
                next RULE;
            }
            else {
                $new_type = $$next_rule;
                last RULE;
            }
        }
        else {
            die "Unexpected";
        }

    }
    TRACE and $parser->highlight_yaml;
    TRACE and $parser->debug_tokens;

    return ($ok, $new_type);
}

sub fetch_next_tokens {
    my ($self, $offset, $yaml) = @_;
    my $next = $self->next_tokens;
    unless (@$next) {
        $self->_fetch_next_tokens($offset, $yaml);
    }
    return $next;
}

sub _fetch_next_tokens {
    my ($self, $offset, $yaml) = @_;
    my $next = $self->next_tokens;
    TRACE and warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$offset], ['offset']);
    TRACE and warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$yaml], ['yaml']);
    if (not length $$yaml) {
        return;
    }
    my $first = substr($$yaml, 0, 1);
    TRACE and warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$first], ['first']);
    if ($offset == 0) {
        if ($first eq "%") {
            if ($$yaml =~ s/\A(\s*%YAML ?1\.2$RE_WS*)//) {
                $self->push_token( YAML_DIRECTIVE => $1 );
            }
            elsif ($$yaml =~ s/\A(\s*%TAG +(!$RE_NS_WORD_CHAR*!|!) +(tag:\S+|!$RE_URI_CHAR+)$RE_WS*)//) {
                $self->push_token( TAG_DIRECTIVE => $1 );
                my $tag_alias = $2;
                my $tag_url = $3;
            }
            elsif ($$yaml =~ s/\A(\s*\A%(?:\w+).*)//) {
                $self->push_token( RESERVED_DIRECTIVE => $1 );
                warn "Found reserved directive '$1'";
            }
            else {
                die "Invalid directive";
            }
            if ($$yaml =~ s/\A([\r\n]|\z)//) {
                $self->push_token( EMPTY => $1 );
            }
            else {
                die "Invalid directive";
            }
            return;
        }
        elsif ($first eq "#") {
            if ($$yaml =~ s/\A(#.*(?:[\r\n]|\z))//) {
                $self->push_token( EMPTY => $1 );
                return;
            }
        }
        elsif ($first eq ' ') {
            my $ws = '';
            if ($$yaml =~ s/\A( +)//) {
                $ws = $1;
            }
            if ($$yaml =~ s/\A(#.*(?:[\r\n]|\z))//) {
                $self->push_token( EMPTY => $ws . $1 );
                return;
            }
            elsif ($$yaml =~ s/\A([\r\n]|\z)//) {
                $self->push_token( EMPTY => $ws . $1 );
                return;
            }
            else {
                $self->push_token( INDENT => $ws );
            }
        }
        elsif ($first eq '-') {
            if ($$yaml =~ s/$RE_DOC_START//) {
                $self->push_token( DOC_START => $1 );
                my $eol = $$yaml =~ s/\A($RE_EOL|\z)//;
                if ($eol) {
                    $self->push_token( EOL => $1 );
                    return;
                }
                else {
                    if ($$yaml =~ s/\A($RE_WS+)//) {
                        $self->push_token( WS => $1 );
                    }
                    else {
                        warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$yaml], ['yaml']);
                        die "Unexpected content after ---";
                    }
                }
            }
        }
        elsif ($first eq '.') {
            if ($$yaml =~ s/$RE_DOC_END//) {
                $self->push_token( DOC_END => $1 );
                $$yaml =~ s/($RE_EOL|\z)// or die "Unexpected";
                $self->push_token( EOL => $1 );
                return;
            }
        }
    }

    $first = substr($$yaml, 0, 1);
    while (length $$yaml) {
        my $rule;
#        warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$first], ['first']);

    if ($first eq '"' or $first eq "'") {
        my $token_name = $first eq '"' ? 'DOUBLEQUOTE' : 'SINGLEQUOTE';
        my $token_name2 = $token_name . 'D';
        my $regex = $REGEXES{ $token_name2 };
        if ($$yaml =~ s/\A($first)$regex($first|[\r\n]|\z)//) {
            my $quote = $1;
            $self->push_token( $token_name => $1 );
            if ($3 eq $first) {
                $self->push_token( $token_name . 'D_SINGLE' => $2 );
                $self->push_token( $token_name => $3 );
            }
            else {
                $self->push_token( $token_name . 'D_LINE' => $2 );
                $self->push_token( LB => $3 );
                while (1) {
                    if ($$yaml =~ s/\A$regex($first|[\r\n])//) {
                        if ($2 eq $first) {
                            $self->push_token( $token_name . 'D_END' => $1 );
                            $self->push_token( $token_name => $2 );
                            last;
                        }
                        else {
                            $self->push_token( $token_name . 'D_LINE' => $1 );
                            $self->push_token( LB => $2 );
                        }
                    }
                    else {
                        die "Invalid quoted string";
                    }
                }
            }
        }
        else {
            die "Invalid quoted string";
        }
    }
    elsif ($first eq '-' or $first eq ':' or $first eq '?') {
        my $token_name = { '-' => 'DASH', ':' => 'COLON', '?' => 'QUESTION' }->{ $first };
        if ($$yaml =~ s/\A(\Q$first\E)(?:($RE_WS+)|([\r\n]|\z))//) {
            $self->push_token( $token_name => $1 );
            if (defined $2) {
                my $ws = $2;
                if ($$yaml =~ s/\A(#.*|)([\r\n]|\z)//) {
                    $self->push_token( EOL => $ws . ($1 // '') . $2 );
                    return;
                }
                else {
                    $self->push_token( WS => $ws );
                }
            }
            else {
                $self->push_token( EOL => $3 );
                return;
            }
        }
        else {
            $rule = 'SCALAR';
        }
    }
    elsif ($first eq '#') {
        if ($$yaml =~ s/\A(#.*(?:[\r\n]|\z))//) {
            $self->push_token( EMPTY => $1 );
            return;
        }
    }
    elsif ($first eq '|' or $first eq '>') {
        my $token_name = { '|' => 'LITERAL', '>' => 'FOLDED' }->{ $first };
        if ($$yaml =~ s/\A(\Q$first\E)//) {
            $self->push_token( $token_name => $1 );
            if ($$yaml =~ s/\A([1-9]\d*)([+-]?)//) {
                $self->push_token( BLOCK_SCALAR_INDENT => $1 );
                $self->push_token( BLOCK_SCALAR_CHOMP => $2 ) if $2;
            }
            elsif ($$yaml =~ s/\A([+-])([1-9]\d*)?//) {
                $self->push_token( BLOCK_SCALAR_CHOMP => $1 );
                $self->push_token( BLOCK_SCALAR_INDENT => $2 ) if $2;
            }
            if ($$yaml =~ s/\A($RE_WS+#.*|$RE_WS*)([\r\n]|\z)//) {
                $self->push_token( EOL => $1 . $2 );
                return;
            }
        }
    }
    elsif ($first eq '!') {
        if ($$yaml =~ s/\A($RE_TAG)//) {
            $self->push_token( TAG => $1 );
        }
    }
    elsif ($first eq '&') {
        if ($$yaml =~ s/\A(\&$RE_ANCHOR)//) {
            $self->push_token( ANCHOR => $1 );
        }
    }
    elsif ($first eq '*') {
        if ($$yaml =~ s/\A(\*$RE_ANCHOR)//) {
            $self->push_token( ALIAS => $1 );
        }
    }
    elsif ($first eq ' ') {
        if ($$yaml =~ s/\A($RE_WS+)//) {
            my $ws = $1;
            if ($$yaml =~ s/\A(#.*)?([\r\n]|\z)//) {
                $self->push_token( EOL => $ws . ($1 // '') . $2 );
                return;
            }
            else {
                $self->push_token( WS => $ws );
            }
        }
    }
    elsif ($first eq "\n") {
        if ($$yaml =~ s/\A(\n)//) {
            $self->push_token( EOL => $1 );
            return;
        }
    }
    elsif ($first eq '{' or $first eq '[') {
        die "Not Implemented: Flow Style";
    }
    else {
        $rule = 'SCALAR';
    }
    if (not $rule) {
    }
    else {
        if ($$yaml =~ s/\A($RE_PLAIN_KEY)// and (length $1) > 0) {
            $self->push_token( SCALAR => $1 );
            if ($$yaml =~ s/\A(?:($RE_WS+#.*)|($RE_WS*))([\r\n]|\z)//) {
                if (defined $1) {
                    $self->push_token( COMMENT_EOL => $1 . $3 );
                    return;
                }
                else {
                    $self->push_token( EOL => $2 . $3 );
                    return;
                }
            }
        }
        else {
            warn __PACKAGE__.':'.__LINE__.$".Data::Dumper->Dump([\$yaml], ['yaml']);
            die "Invalid plain scalar";
        }
    }

        $first = substr($$yaml, 0, 1);
    }
    push @$next, $self->new_token( EOL => '' );

    return;
}

my %is_new_line = (
    EOL => 1,
    COMMENT_EOL => 1,
    LB => 1,
    EMPTY => 1,
);

sub push_token {
    my ($self, $type, $value) = @_;
    my $next = $self->next_tokens;
    push @$next, [ $type => $value ];
    if ($is_new_line{ $type }) {
        $self->inc_line;
    }
}

sub new_token {
    my ($self, $type, $value) = @_;
    return [ $type => $value ];
}

1;
