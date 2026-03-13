package Mail::SpamAssassin::Plugin::ZZ_BayesSQL;

use strict;
use warnings;
use Mail::SpamAssassin::Plugin;
use File::Basename;

our @ISA = qw(Mail::SpamAssassin::Plugin);

sub new {
    my ($class, $sa) = @_;
    my $self = $class->SUPER::new($sa);

    $self->{disabled}      = 0;
    $self->{auto_spam_min} = 12.0;
    $self->{auto_ham_max}  = 0.1;

    my $env_path = dirname(__FILE__) . '/zz_bayessql.env';
    my $env_map  = $self->_read_env_file($env_path, $sa);

    foreach my $key (qw(EC_BAYES_SQL_DSN EC_BAYES_SQL_USER EC_BAYES_SQL_PASS EC_HIGHSPAM_THRESHOLD)) {
        unless (exists $env_map->{$key} && length $env_map->{$key}) {
            $sa->log_err("ZZ_BayesSQL: Pflicht-Key '$key' fehlt oder leer in '$env_path'. Plugin deaktiviert!");
            $self->{disabled} = 1;
            return $self;
        }
    }

    unless ($env_map->{EC_HIGHSPAM_THRESHOLD} =~ /^\d+(?:\.\d+)?$/) {
        $sa->log_err("ZZ_BayesSQL: Ungueltiger EC_HIGHSPAM_THRESHOLD. Plugin deaktiviert!");
        $self->{disabled} = 1;
        return $self;
    }

    $self->{dsn}                = $env_map->{EC_BAYES_SQL_DSN};
    $self->{db_user}            = $env_map->{EC_BAYES_SQL_USER};
    $self->{db_pass}            = $env_map->{EC_BAYES_SQL_PASS};
    $self->{highspam_threshold} = $env_map->{EC_HIGHSPAM_THRESHOLD} + 0;

    if (exists $env_map->{EC_AUTOLEARN_SPAM_MIN} && $env_map->{EC_AUTOLEARN_SPAM_MIN} =~ /^\d+(?:\.\d+)?$/) {
        $self->{auto_spam_min} = $env_map->{EC_AUTOLEARN_SPAM_MIN} + 0;
    }
    if (exists $env_map->{EC_AUTOLEARN_HAM_MAX} && $env_map->{EC_AUTOLEARN_HAM_MAX} =~ /^\d+(?:\.\d+)?$/) {
        $self->{auto_ham_max} = $env_map->{EC_AUTOLEARN_HAM_MAX} + 0;
    }

    
    my $conf = $sa->{conf};
    $conf->{bayes_store_module}          = 'Mail::SpamAssassin::BayesStore::SQL';
    $conf->{bayes_sql_dsn}               = $self->{dsn};
    $conf->{bayes_sql_username}          = $self->{db_user};
    $conf->{bayes_sql_password}          = $self->{db_pass};
    $conf->{bayes_sql_override_username} = 'global_bayes_user';
    $conf->{use_bayes}                   = 1;
    $conf->{bayes_auto_learn}            = 1;




    $sa->info("ZZ_BayesSQL: Plugin geladen. DSN=" . $self->_log_mask_dsn($self->{dsn})
        . " user=" . $self->{db_user}
        . sprintf(" HighSpam>=%.2f AutoSpam>=%.2f AutoHam<=%.2f",
            $self->{highspam_threshold},
            $self->{auto_spam_min},
            $self->{auto_ham_max})
    );

    return $self;
}


sub check_end {
    my ($self, $params) = @_;
    return if $self->{disabled};

    my $pms = $params->{permsgstatus};
    return unless $pms;

    my $score = $pms->{score} // 0;

    if ($score >= $self->{highspam_threshold}) {
        $pms->set_tag('ECHIGHSPAM', sprintf("YES; score=%.2f", $score));
        $self->{main}->info("ZZ_BayesSQL: HighSpam-Tag gesetzt score=$score");
    } else {
        $pms->set_tag('ECHIGHSPAM', '');
    }

    return;
}

# --- Hilfsfunktionen ---

sub _read_env_file {
    my ($self, $path, $sa) = @_;
    my %map;

    unless (-r $path) {
        $sa->log_err("ZZ_BayesSQL: env-file '$path' nicht gefunden oder nicht lesbar!");
        return \%map;
    }

    if (open my $fh, "<", $path) {
        my $lineno = 0;
        while (<$fh>) {
            $lineno++;
            chomp;
            s/^\s*#.*$//;
            s/^\s+|\s+$//g;
            next if $_ eq '';

            if (/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/) {
                my ($k, $v) = ($1, $2);
                $v =~ s/^"(.*)"$/$1/;
                $v =~ s/^'(.*)'$/$1/;
                $map{$k} = $v;
            } else {
                $sa->log_warn("ZZ_BayesSQL: ungueltige Zeile $lineno in '$path': $_");
            }
        }
        close $fh;
    } else {
        $sa->log_err("ZZ_BayesSQL: konnte env-file '$path' nicht oeffnen: $!");
    }

    return \%map;
}

sub _log_mask_dsn {
    my ($self, $dsn) = @_;
    return '' unless defined $dsn && length $dsn;
    $dsn =~ s/(passwd|password)=([^;]+)/$1=***MASKED***/ig;
    return $dsn;
}

1;