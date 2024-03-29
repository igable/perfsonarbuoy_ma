#!/usr/bin/perl -w -I ./lib ../lib

#use strict;
use warnings;
use Config::General qw(ParseConfig SaveConfig);
use Sys::Hostname;
use English qw( -no_match_vars );
use Module::Load;
use File::Temp qw(tempfile);
use Term::ReadKey;
use Cwd;

=head1 NAME

psConfigureDaemon - Ask a series of questions to generate a configuration file.

=head1 DESCRIPTION

Ask questions based on a service to generate a configuration file.

=cut

my $dirname = getcwd . "/";
unless ( $dirname =~ m/scripts\/$/ ) {
    $dirname .= "scripts/";
}

my $was_installed = 0;
my $DEFAULT_FILE;
my $confdir;

if ($was_installed) {
    $confdir = "XXX_CONFDIR_XXX";
}
else {
    $confdir = getcwd;
}

$DEFAULT_FILE = $confdir . "/daemon.conf";

print " -- perfSONAR-PS Daemon Configuration --\n";
print " - [press enter for the default choice] -\n\n";

my $file = shift;

unless ($file) {
    $file = &ask( "What file should I write the configuration to? ", $DEFAULT_FILE, undef, '.+' );
}

my $tmp;
our $default_hostname = hostname();
our $hostname         = 'localhost';
our $db_name          = q{};
our $db_port          = q{};
our $db_username      = 'dbuser';
our $db_password      = 'dbpass';

my %config = ();
if ( -f $file ) {
    %config = ParseConfig($file);
}

# make sure all the endpoints start with a "/".
if ( defined $config{"port"} ) {
    foreach my $port ( keys %{ $config{"port"} } ) {
        if ( exists $config{"port"}->{$port}->{"endpoint"} ) {
            foreach my $endpoint ( keys %{ $config{"port"}->{$port}->{"endpoint"} } ) {
                my $new_endpoint = $endpoint;

                if ( $endpoint =~ /^[^\/]/mx ) {
                    $new_endpoint = "/" . $endpoint;
                }

                if ( $endpoint ne $new_endpoint ) {
                    $config{"port"}->{$port}->{"endpoint"}->{$new_endpoint} = $config{"port"}->{$port}->{"endpoint"}->{$endpoint};
                    delete( $config{"port"}->{$port}->{"endpoint"}->{$endpoint} );
                }
            }
        }
    }
}

while (1) {
    my $input;
    print "1) Set global values\n";
    print "2) Add/Edit endpoint\n";
    print "3) Enable/Disable port/endpoint\n";
    print "4) Save configuration\n";
    print "5) Exit\n";
    $input = &ask( "? ", q{}, undef, '[12345]' );

    if ( $input == 5 ) {
        exit(0);
    }
    elsif ( $input == 4 ) {
        if ( -f $file ) {
            system("mv $file $file~");
        }

        SaveConfig_mine( $file, \%config );
        print "\n";
        print "Saved config to $file\n";
        print "\n";
    }
    elsif ( $input == 1 ) {
        $config{"max_worker_processes"}     = &ask( "Enter the maximum number of children processes (0 means infinite) ",                   "30",                                                         $config{"max_worker_processes"},     '^\d+$' );
        $config{"max_worker_lifetime"}      = &ask( "Enter number of seconds a child can process before it is stopped (0 means infinite) ", "300",                                                        $config{"max_worker_lifetime"},      '^\d+$' );
        $config{"disable_echo"}             = &ask( "Disable echo by default (0 for no, 1 for yes) ",                                       0,                                                            $config{"disable_echo"},             '^[01]$' );
        $config{"ls_instance"}              = &ask( "The LS for MAs to register with ",                                                     "http://packrat.internet2.edu:8005/perfSONAR_PS/services/LS", $config{"ls_instance"},              '(^http|^$)' );
        $config{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ",                           60,                                                           $config{"ls_registration_interval"}, '^\d+$' );
        $config{"root_hints_url"}           = &ask( "URL of the root.hints file ",                                                          "http://www.perfsonar.net/gls.root.hints",                    $config{"root_hints_url"},           '(^http|^$)' );
        $config{"root_hints_file"}          = &ask( "Where shold the root.hints file be stored ",                                           $confdir . "/gls.root.hints",                                 $config{"root_hints_file"},          '^\/' );
        $config{"reaper_interval"}          = &ask( "Interval between when children are repeaed [in seconds] ",                             20,                                                           $config{"reaper_interval"},          '^\d+$' );
        $config{"pid_dir"}                  = &ask( "Enter pid dir location ",                                                              "/var/run",                                                   $config{"pid_dir"},                  q{} );
        $config{"pid_file"}                 = &ask( "Enter pid filename ",                                                                  "ps.pid",                                                     $config{"pid_file"},                 q{} );
    }
    elsif ( $input == 3 ) {
        my @elements = ();
        my %status   = ();

        foreach my $port ( sort keys %{ $config{"port"} } ) {
            next unless ( exists $config{"port"}->{$port}->{"endpoint"} );
            push @elements, $port;

            if ( exists $config{"port"}->{$port}->{"disabled"} and $config{"port"}->{$port}->{"disabled"} == 1 ) {
                $status{$port} = 1;
            }
        }

        foreach my $port ( sort keys %{ $config{"port"} } ) {
            next unless ( exists $config{"port"}->{$port}->{"endpoint"} );
            foreach my $endpoint ( sort keys %{ $config{"port"}->{$port}->{"endpoint"} } ) {
                push @elements, "$port$endpoint";
                if ( exists $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"disabled"}
                    and $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"disabled"} == 1 )
                {
                    $status{"$port$endpoint"} = 1;
                }
            }
        }

        if ( $#elements > -1 ) {
            print "\n";
            print "Select element to enable/disable: \n";
            my $len = $#elements;
            for my $i ( 0 .. $len ) {
                print " $i) $elements[$i] ";
                print " *" if exists $status{ $elements[$i] };
                print "\n";
            }
            print "\n";
            print " * element is disabled\n";
            print "\n";

            do {
                $input = &ask( "Select a number from the above ", q{}, undef, '^\d+$' );
            } while ( $input > $#elements );

            my $new_status;

            if ( exists $status{ $elements[$input] } ) {
                $new_status = 0;
            }
            else {
                $new_status = 1;
            }

            print "\n";
            if ($new_status) {
                print "Disabling";
            }
            else {
                print "Enabling";
            }

            if ( $elements[$input] =~ /^(\d+)(\/.*)$/mx ) {
                print " endpoint " . $elements[$input] . "\n";
                $config{"port"}->{$1}->{"endpoint"}->{$2}->{"disabled"} = $new_status;
            }
            elsif ( $elements[$input] =~ /^(\d+)$/mx ) {
                print " port " . $elements[$input] . "\n";
                $config{"port"}->{$1}->{"disabled"} = $new_status;
            }
            print "\n";
        }
    }
    elsif ( $input == 2 ) {
        my @endpoints = ();
        foreach my $port ( sort keys %{ $config{"port"} } ) {
            next unless ( exists $config{"port"}->{$port}->{"endpoint"} );
            foreach my $endpoint ( sort keys %{ $config{"port"}->{$port}->{"endpoint"} } ) {
                push @endpoints, "$port$endpoint";
            }
        }

        if ( $#endpoints > -1 ) {
            print "\n";
            print "Existing Endpoints: \n";
            my $len = $#endpoints;
            for my $i ( 0 .. $len ) {
                print " $i) $endpoints[$i]\n";
            }
            print "\n";
        }

        do {
            $input = &ask( "Enter endpoint in form 'port/endpoint_path' (e.g. 8080/perfSONAR_PS/services/SERVICE_NAME) or select from a number from the above ", q{}, undef, '^(\d+[\/].*|\d+)$' );
            if ( $input =~ /^\d+$/mx ) {
                $input = $endpoints[$input];
            }
        } while ( not( $input =~ /\d+[\/].*/mx ) );

        my ( $port, $endpoint );
        if ( $input =~ /(\d+)([\/].*)/mx ) {
            $port     = $1;
            $endpoint = $2;
        }

        unless ( exists $config{"port"} ) {
            my %hash = ();
            $config{"port"} = \%hash;
        }

        unless ( exists $config{"port"}->{$port} ) {
            my %hash = ();
            $config{"port"}->{$port} = \%hash;
            $config{"port"}->{$port}->{"endpoint"} = ();
        }

        unless ( exists $config{"port"}->{$port}->{"endpoint"}->{$endpoint} ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint} = ();
        }

        my $valid_module = 0;
        my $module       = $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"};
        if ( defined $module ) {
            if ( $module eq "perfSONAR_PS::Services::MA::SNMP" ) {
                $module = "snmp";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::Status" ) {
                $module = "status";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::CircuitStatus" ) {
                $module = "circuitstatus";
            }
            elsif ( $module eq "perfSONAR_PS::Services::TS::TS" ) {
                $module = "topology";
            }
            elsif ( $module eq "perfSONAR_PS::Services::LS::LS" ) {
                $module = "ls";
            }
            elsif ( $module eq "perfSONAR_PS::Services::LS::gLS" ) {
                $module = "gls";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::perfSONARBUOY" ) {
                $module = "perfsonarbuoy";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MA::PingER" ) {
                $module = "pingerma";
            }
            elsif ( $module eq "perfSONAR_PS::Services::MP::PingER" ) {
                $module = "pingermp";
            }
        }

        my %opts;
        do {
            $module = &ask( "Enter endpoint module [snmp,ls,gls,perfsonarbuoy,pingerma,pingermp,status,circuitstatus,topology] ", q{}, $module, q{} );
            $module = lc($module);

            if (   $module eq "snmp"
                or $module eq "status"
                or $module eq "ls"
                or $module eq "gls"
                or $module eq "circuitstatus"
                or $module eq "topology"
                or $module eq "perfsonarbuoy"
                or $module eq "pingerma"
                or $module eq "pingermp" )
            {
                $valid_module = 1;
            }
        } while ( $valid_module == 0 );

        unless ($hostname) {
            $hostname = &ask( "Enter the external host or IP for this machine ", $hostname, $default_hostname, '.+' );
        }

        my $accesspoint = &ask( "Enter the accesspoint for this service ", "http://$hostname:$port$endpoint", undef, '^http' );

        if ( $module eq "snmp" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::SNMP";
            config_snmp_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "status" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::Status";
            config_status_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "circuitstatus" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::CircuitStatus";
            config_circuitstatus_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "topology" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::TS::TS";
            config_topology_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "ls" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::LS::LS";
            config_ls( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "gls" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::LS::gLS";
            config_gls( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "perfsonarbuoy" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"} = "perfSONAR_PS::Services::MA::perfSONARBUOY";
            config_perfsonarbuoy_ma( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config );
        }
        elsif ( $module eq "pingerma" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"}       = "perfSONAR_PS::Services::MA::PingER";
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"service_type"} = "MA";
            config_pinger( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config, "pingerma" );
        }
        elsif ( $module eq "pingermp" ) {
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"module"}       = "perfSONAR_PS::Services::MP::PingER";
            $config{"port"}->{$port}->{"endpoint"}->{$endpoint}->{"service_type"} = "MP";
            config_pinger( $config{"port"}->{$port}->{"endpoint"}->{$endpoint}, $accesspoint, \%config, "pingermp" );
        }
    }
}

sub config_gls {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"gls"} = () unless exists $config->{"gls"};

    $config->{"gls"}->{"root"}                     = "0";
    $config->{"gls"}->{"enable_registration"}      = 1;
    $config->{"gls"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", $config{"ls_registration_interval"}, $config->{"gls"}->{"ls_registration_interval"}, '^\d+$' );
    $config->{"gls"}->{"ls_ttl"}                   = &ask( "Enter default TTL for registered data [in minutes] ", "60", $config->{"gls"}->{"ls_ttl"}, '\d+' );
    $config->{"gls"}->{"metadata_db_name"}         = &ask( "Enter the directory of the XML database ", $confdir . "/ls-xmldb", $config->{"gls"}->{"metadata_db_name"}, '^\/' );
    $config->{"gls"}->{"metadata_db_name"} .= "/" unless $config->{"gls"}->{"metadata_db_name"} =~ m/\/$/;
    unless ( -d $config->{"gls"}->{"metadata_db_name"} ) {
        system( "mkdir " . $config->{"gls"}->{"metadata_db_name"} );
    }

    if ( not -e $config->{"gls"}->{"metadata_db_name"} . "DB_CONFIG" ) {
        my $RUN = q{};
        open( $RUN, "perl " . $dirname . "makeDBConfig.pl |" );
        my @result = <$RUN>;
        close($RUN);
        if ( $result[0] ) {
            system( "mv " . $result[0] . " " . $config->{"gls"}->{"metadata_db_name"} . "DB_CONFIG" );
        }
        else {
            return -1;
        }
    }

    $config->{"gls"}->{"metadata_db_file"}         = "glsstore.dbxml";
    $config->{"gls"}->{"metadata_summary_db_file"} = "glsstore-summary.dbxml";

    $config->{"gls"}->{"maintenance_interval"} = &ask( "Enter the time between LS maintenance (summarization, cleaning) [in minutes] ", "30", $config->{"gls"}->{"maintenance_interval"}, '^\d+$' );

    $config->{"gls"}->{"service_name"}        = &ask( "Enter a name for this service ", "Lookup Service", $config->{"gls"}->{"service_name"},        '.+' );
    $config->{"gls"}->{"service_type"}        = &ask( "Enter the service type ",        "LS",             $config->{"gls"}->{"service_type"},        '.+' );
    $config->{"gls"}->{"service_description"} = &ask( "Enter a service description ",   "Lookup Service", $config->{"gls"}->{"service_description"}, '.+' );
    $config->{"gls"}->{"service_accesspoint"} = &ask( "Enter the service's URI ",       $accesspoint,     $config->{"gls"}->{"service_accesspoint"}, '^http:\/\/' );
    return;
}

sub config_ls {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"ls"} = () unless exists $config->{"ls"};

    $config->{"ls"}->{"enable_registration"} = 1;
    $config->{"ls"}->{"ls_ttl"}              = &ask( "Enter default TTL for registered data [in minutes] ", "60", $config->{"ls"}->{"ls_ttl"}, '\d+' );
    $config->{"ls"}->{"metadata_db_name"}    = &ask( "Enter the directory of the XML database ", $confdir . "/ls-xmldb", $config->{"ls"}->{"metadata_db_name"}, '^\/' );
    $config->{"ls"}->{"metadata_db_name"} .= "/" unless $config->{"ls"}->{"metadata_db_name"} =~ m/\/$/;
    unless ( -d $config->{"ls"}->{"metadata_db_name"} ) {
        system( "mkdir " . $config->{"ls"}->{"metadata_db_name"} );
    }

    unless ( -e $config->{"ls"}->{"metadata_db_name"} . "DB_CONFIG" ) {
        my $RUN = q{};
        open( $RUN, "perl " . $dirname . "makeDBConfig.pl |" );
        my @result = <$RUN>;
        close($RUN);
        if ( $result[0] ) {
            system( "mv " . $result[0] . " " . $config->{"ls"}->{"metadata_db_name"} . "DB_CONFIG" );
        }
        else {
            return -1;
        }
    }

    $config->{"ls"}->{"metadata_db_file"} = "lsstore.dbxml";

    $config->{"ls"}->{"maintenance_interval"} = &ask( "Enter the time between LS maintenance (cleaning) [in minutes] ", "30", $config->{"ls"}->{"maintenance_interval"}, '^\d+$' );

    $config->{"ls"}->{"service_name"}        = &ask( "Enter a name for this service ", "Lookup Service", $config->{"ls"}->{"service_name"},        '.+' );
    $config->{"ls"}->{"service_type"}        = &ask( "Enter the service type ",        "LS",             $config->{"ls"}->{"service_type"},        '.+' );
    $config->{"ls"}->{"service_description"} = &ask( "Enter a service description ",   "Lookup Service", $config->{"ls"}->{"service_description"}, '.+' );
    $config->{"ls"}->{"service_accesspoint"} = &ask( "Enter the service's URI ",       $accesspoint,     $config->{"ls"}->{"service_accesspoint"}, '^http:\/\/' );

    return;
}

sub config_perfsonarbuoy_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    my $amiconfdir = $confdir;
    $config->{"perfsonarbuoy"} = () unless exists $config->{"perfsonarbuoy"};

    $config->{"perfsonarbuoy"}->{"owmesh"} = &ask( "Enter the directory *LOCATION* of the 'owmesh.conf' file: ", $amiconfdir, $config->{"perfsonarbuoy"}->{"owmesh"}, '.+' );
    $amiconfdir                            = $config->{"perfsonarbuoy"}->{"owmesh"};
    $config->{"perfsonarbuoy"}->{"legacy"} = "0";

    $config->{"perfsonarbuoy"}->{"metadata_db_type"} = &ask( "Enter the database type to read from (file or xmldb) ", "file", $config->{"perfsonarbuoy"}->{"metadata_db_type"}, '(file|xmldb)' );

    if ( $config->{"perfsonarbuoy"}->{"metadata_db_type"} eq "file" ) {
        delete $config->{"perfsonarbuoy"}->{"metadata_db_file"} if $config->{"perfsonarbuoy"}->{"metadata_db_file"} and $config->{"perfsonarbuoy"}->{"metadata_db_file"} =~ m/dbxml$/mx;
        $config->{"perfsonarbuoy"}->{"metadata_db_file"} = &ask( "Enter the filename of the XML file ", $amiconfdir . "/psb-store.xml", $config->{"perfsonarbuoy"}->{"metadata_db_file"}, '\.xml$' );
    }
    elsif ( $config->{"perfsonarbuoy"}->{"metadata_db_type"} eq "xmldb" ) {
        $config->{"perfsonarbuoy"}->{"metadata_db_name"} = &ask( "Enter the directory of the XML database ", $amiconfdir . "/psb-xmldb", $config->{"perfsonarbuoy"}->{"metadata_db_name"}, '.+' );
        $config->{"perfsonarbuoy"}->{"metadata_db_name"} .= "/" unless $config->{"perfsonarbuoy"}->{"metadata_db_name"} =~ m/\/$/;
        unless ( -d $config->{"perfsonarbuoy"}->{"metadata_db_name"} ) {
            system( "mkdir " . $config->{"perfsonarbuoy"}->{"metadata_db_name"} );
        }

        unless ( -e $config->{"perfsonarbuoy"}->{"metadata_db_name"} . "DB_CONFIG" ) {
            my $RUN = q{};
            open( $RUN, "perl " . $dirname . "makeDBConfig.pl |" );
            my @result = <$RUN>;
            close($RUN);
            if ( $result[0] ) {
                system( "mv " . $result[0] . " " . $config->{"perfsonarbuoy"}->{"metadata_db_name"} . "DB_CONFIG" );
            }
            else {
                return -1;
            }
        }

        delete $config->{"perfsonarbuoy"}->{"metadata_db_file"} if $config->{"perfsonarbuoy"}->{"metadata_db_file"} and $config->{"perfsonarbuoy"}->{"metadata_db_file"} =~ m/\.xml$/mx;
        $config->{"perfsonarbuoy"}->{"metadata_db_file"} = "psbstore.dbxml";
    }

    $config->{"perfsonarbuoy"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes)", "0", $config->{"perfsonarbuoy"}->{"enable_registration"}, '^[01]$' );
    my $registration_interval = $def_config->{"ls_registration_interval"};
    $registration_interval = $config->{"perfsonarbuoy"}->{"ls_registration_interval"} if exists $config->{"perfsonarbuoy"}->{"ls_registration_interval"};
    my $ls_instance = $def_config->{"ls_instance"};
    $ls_instance = $config->{"perfsonarbuoy"}->{"ls_instance"} if exists $config->{"perfsonarbuoy"}->{"ls_instance"};
    if ( $config->{"perfsonarbuoy"}->{"enable_registration"} eq "1" ) {
        $config->{"perfsonarbuoy"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );
        $config->{"perfsonarbuoy"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );
    }
    else {
        $config->{"perfsonarbuoy"}->{"ls_instance"}              = $ls_instance           if $ls_instance;
        $config->{"perfsonarbuoy"}->{"ls_registration_interval"} = $registration_interval if $registration_interval;
    }

    $config->{"perfsonarbuoy"}->{"service_name"} = &ask( "Enter a name for this service ", "perfSONARBUOY MA", $config->{"perfsonarbuoy"}->{"service_name"}, '.+' );

    $config->{"perfsonarbuoy"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"perfsonarbuoy"}->{"service_type"}, '.+' );

    $config->{"perfsonarbuoy"}->{"service_description"} = &ask( "Enter a service description ", "perfSONARBUOY MA", $config->{"perfsonarbuoy"}->{"service_description"}, '.+' );

    $config->{"perfsonarbuoy"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"perfsonarbuoy"}->{"service_accesspoint"}, '^http:\/\/' );

    return;
}

sub config_snmp_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"snmp"} = () unless exists $config->{"snmp"};

    my $rrdtool = q{};
    my $RRDTOOL = q{};
    if ( open( $RRDTOOL, "which rrdtool |" ) ) {
        $rrdtool = <$RRDTOOL>;
        $rrdtool =~ s/rrdtool:\s+//mx if $rrdtool;
        $rrdtool =~ s/\n//gmx         if $rrdtool;
        close($RRDTOOL);
    }

    if ( open( $RRDTOOL, "whereis rrdtool |" ) ) {
        $rrdtool = <$RRDTOOL>;
        $rrdtool =~ s/rrdtool:\s+//mx if $rrdtool;
        $rrdtool =~ s/\n//gmx         if $rrdtool;
        close($RRDTOOL);
    }

    unless ($rrdtool) {
        print "RRDTool binary not found, please install RRDTool.\n";
        return -1;
    }

    my @rrd = split( / /, $rrdtool );
    $config->{"snmp"}->{"rrdtool"} = &ask( "Enter the location of the RRD binary ", $rrd[0], $config->{"snmp"}->{"rrdtool"}, '.+' );

    $config->{"snmp"}->{"default_resolution"} = &ask( "Enter the default resolution of RRD queries ", "300", $config->{"snmp"}->{"default_resolution"}, '^\d+$' );

    my $makeStore = 0;
    my @result    = ();
    my $external  = &ask( "Use external monitoring source [e.g. cacti, cricket, mrtg, etc.] for metadata creation? (0 for no, 1 for yes) ", "0", "0", '^[01]$' );
    if ($external) {
        $config->{"snmp"}->{"metadata_db_external"} = &ask( "Enter external monitoring source (none | cacti | cricket | mrtg ) ", "none", $config->{"snmp"}->{"metadata_db_external"}, '^(none|cacti|mrtg|cricket)$' );
        if ( exists $config->{"snmp"}->{"metadata_db_external"} and $config->{"snmp"}->{"metadata_db_external"} eq "cacti" ) {
            $config->{"snmp"}->{"metadata_db_external_source"} = &ask( "Enter cacti configuration file location (/path/to/file) ", "/etc/cacti/cactid.conf", $config->{"snmp"}->{"metadata_db_external_source"}, '\.conf$' );
        }
        elsif ( exists $config->{"snmp"}->{"metadata_db_external"} and $config->{"snmp"}->{"metadata_db_external"} eq "cricket" ) {

            my $suggest = $ENV{CRICKET_HOME};
            $suggest = "/home/cricket" unless $suggest;
            $config->{"snmp"}->{"metadata_db_external_cricket_home"} = &ask( "Enter cricket home directory (/path/to/cricket) ", $suggest, $config->{"snmp"}->{"metadata_db_external_cricket_home"}, '.+' );
            
            $config->{"snmp"}->{"metadata_db_external_cricket_cricket"} = &ask( "Enter cricket install directory (/path/to/cricket/cricket) ", $config->{"snmp"}->{"metadata_db_external_cricket_home"}."/cricket", $config->{"snmp"}->{"metadata_db_external_cricket_cricket"}, '.+' );

            $config->{"snmp"}->{"metadata_db_external_cricket_data"} = &ask( "Enter cricket data directory (/path/to/cricket/data) ", $config->{"snmp"}->{"metadata_db_external_cricket_home"}."/cricket-data", $config->{"snmp"}->{"metadata_db_external_cricket_data"}, '.+' );

            $config->{"snmp"}->{"metadata_db_external_cricket_config"} = &ask( "Enter cricket config directory (/path/to/cricket/config) ", $config->{"snmp"}->{"metadata_db_external_cricket_home"}."/cricket-config", $config->{"snmp"}->{"metadata_db_external_cricket_config"}, '.+' );
        }   
    }
    else {
        $config->{"snmp"}->{"metadata_db_external"}        = "none";
        $config->{"snmp"}->{"metadata_db_external_source"} = "";
        my $makeStore = &ask( "Automatically generate a 'test' metadata database (0 for no, 1 for yes) ", "0", "0", '^[01]$' );
        if ($makeStore) {
            my $RUN = q{};
            open( $RUN, "perl " . $dirname . "makeStore.pl " . $confdir . " |" );
            @result = <$RUN>;
            close($RUN);
            unless ( $result[0] ) {
                return -1;
            }
        }
    }

    $config->{"snmp"}->{"metadata_db_type"} = &ask( "Enter the internal database type to read from (file or xmldb) ", "file", $config->{"snmp"}->{"metadata_db_type"}, '(file|xmldb)' );

    if ( $config->{"snmp"}->{"metadata_db_type"} eq "file" ) {
        delete $config->{"snmp"}->{"metadata_db_file"} if $config->{"snmp"}->{"metadata_db_file"} and $config->{"snmp"}->{"metadata_db_file"} =~ m/dbxml$/mx;
        $config->{"snmp"}->{"metadata_db_file"} = &ask( "Enter the filename of the XML file ", $confdir . "/snmp-store.xml", $config->{"snmp"}->{"metadata_db_file"}, '\.xml$' );
        if ( $result[0] ) {
            if ( -f $config->{"snmp"}->{"metadata_db_file"} ) {
                system( "mv " . $config->{"snmp"}->{"metadata_db_file"} . " " . $config->{"snmp"}->{"metadata_db_file"} . "~" );
            }
            system( "mv " . $result[0] . " " . $config->{"snmp"}->{"metadata_db_file"} );
        }
        delete $config->{"snmp"}->{"db_autoload"}               if $config->{"snmp"}->{"db_autoload"};
        delete $config->{"snmp"}->{"autoload_metadata_db_file"} if $config->{"snmp"}->{"autoload_metadata_db_file"};
        delete $config->{"snmp"}->{"metadata_db_name"}          if $config->{"snmp"}->{"metadata_db_name"};
    }
    elsif ( $config->{"snmp"}->{"metadata_db_type"} eq "xmldb" ) {
        $config->{"snmp"}->{"metadata_db_name"} = &ask( "Enter the directory of the XML database ", $confdir . "/snmp-xmldb", $config->{"snmp"}->{"metadata_db_name"}, '.+' );
        $config->{"snmp"}->{"metadata_db_name"} .= "/" unless $config->{"snmp"}->{"metadata_db_name"} =~ m/\/$/;
        unless ( -d $config->{"snmp"}->{"metadata_db_name"} ) {
            system( "mkdir " . $config->{"snmp"}->{"metadata_db_name"} );
        }

        unless ( -e $config->{"snmp"}->{"metadata_db_name"} . "DB_CONFIG" ) {
            my $RUN = q{};
            open( $RUN, "perl " . $dirname . "makeDBConfig.pl |" );
            my @result = <$RUN>;
            close($RUN);
            if ( $result[0] ) {
                system( "mv " . $result[0] . " " . $config->{"snmp"}->{"metadata_db_name"} . "DB_CONFIG" );
            }
            else {
                return -1;
            }
        }

        delete $config->{"snmp"}->{"metadata_db_file"} if $config->{"snmp"}->{"metadata_db_file"} and $config->{"snmp"}->{"metadata_db_file"} =~ m/\.xml$/mx;
        $config->{"snmp"}->{"metadata_db_file"} = "snmpstore.dbxml";
        if ( $result[0] ) {
            $config->{"snmp"}->{"db_autoload"} = 1;
            $config->{"snmp"}->{"autoload_metadata_db_file"} = &ask( "Enter the filename of the base XML file to load ", $confdir . "/snmp-store.xml", $config->{"snmp"}->{"autoload_metadata_db_file"}, '\.xml$' );
            if ( -f $config->{"snmp"}->{"autoload_metadata_db_file"} ) {
                system( "mv " . $config->{"snmp"}->{"autoload_metadata_db_file"} . " " . $config->{"snmp"}->{"autoload_metadata_db_file"} . "~" );
            }
            system( "mv " . $result[0] . " " . $config->{"snmp"}->{"autoload_metadata_db_file"} );
        }
        else {
            $config->{"snmp"}->{"db_autoload"} = &ask( "Would you like to auto-load the database [non-destructive] ? (0 for no, 1 for yes) ", "1", $config->{"snmp"}->{"db_autoload"}, '^[01]$' );
            if ( $config->{"snmp"}->{"db_autoload"} eq "1" ) {
                $config->{"snmp"}->{"autoload_metadata_db_file"} = &ask( "Enter the filename of the base XML file to load ", $confdir . "/store.xml", $config->{"snmp"}->{"autoload_metadata_db_file"}, '\.xml$' );
            }
        }
    }

    $config->{"snmp"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes)", "0", $config->{"snmp"}->{"enable_registration"}, '^[01]$' );
    my $registration_interval = $def_config->{"ls_registration_interval"};
    $registration_interval = $config->{"snmp"}->{"ls_registration_interval"} if exists $config->{"snmp"}->{"ls_registration_interval"};
    my $ls_instance = $def_config->{"ls_instance"};
    $ls_instance = $config->{"snmp"}->{"ls_instance"} if exists $config->{"snmp"}->{"ls_instance"};
    if ( $config->{"snmp"}->{"enable_registration"} eq "1" ) {
        $config->{"snmp"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );
        $config->{"snmp"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );
    }
    else {
        $config->{"snmp"}->{"ls_instance"}              = $ls_instance           if $ls_instance;
        $config->{"snmp"}->{"ls_registration_interval"} = $registration_interval if $registration_interval;
    }

    $config->{"snmp"}->{"service_name"} = &ask( "Enter a name for this service ", "SNMP MA", $config->{"snmp"}->{"service_name"}, '.+' );

    $config->{"snmp"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"snmp"}->{"service_type"}, '.+' );

    $config->{"snmp"}->{"service_description"} = &ask( "Enter a service description ", "SNMP MA", $config->{"snmp"}->{"service_description"}, '.+' );

    $config->{"snmp"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"snmp"}->{"service_accesspoint"}, '^http:\/\/' );

    return;
}

sub config_pinger {
    my ( $config, $accesspoint, $def_config, $modulename ) = @_;
    my $moduletype = ( $modulename =~ /ma$/ ? "MA" : "MP" );
    $config->{$modulename} = () unless exists $config->{$modulename};
    
    $config->{$modulename}->{"db_type"} = &ask( "Enter the database type to read from (sqlite,mysql) ", "mysql", $config->{$modulename}->{"db_type"}, '^(sqlite|mysql)$' );
    
    my $dirname = getcwd;
     
    if ( $config->{$modulename}->{"db_type"} eq "sqlite" ) {
        $config->{$modulename}->{"db_file"} = &ask( "Enter the filename of the SQLite database ", "pinger.db", $config->{$modulename}->{"db_file"}, '.+' );
	eval {
	    require DBD::SQLite;
	    require DBI;

	    system("sqlite3 $config->{$modulename}->{db_file} < $dirname/../scripts/create_pingerMA_SQLite.sql");
	 
	    my $dbh = DBI->connect("dbi:SQLite:dbname=$config->{$modulename}->{db_file}", "","", 
	                            { AutoCommit => 1,
                                      RaiseError => 1 });
	    $dbh->do("INSERT into host (ip_name, ip_number, comments) values ('test_name', '1.0.0.1', 'test')");
	    
	    if($dbh->err()) { die "$DBI::errstr\n"; }
	};
	if($EVAL_ERROR) {
	    die " $EVAL_ERROR :: You have to install perl DBD::SQLite driver, run: sudo cpan -i 'DBD::SQLite' ";
	}	
    }
    elsif ( $config->{$modulename}->{"db_type"} eq "mysql" ) {
        $config->{$modulename}->{db_name} = &ask( "Enter the name of the MySQL database ",                                $db_name,          $config->{$modulename}->{"db_name"}, '.+' );
        $config->{$modulename}->{db_host} = &ask( "Enter the host for the MySQL database ",                               $default_hostname, $config->{$modulename}->{"db_host"}, '.+' );
        $tmp                                = &ask( "Enter the port for the MySQL database (leave blank for the default) ", $db_port,          $config->{$modulename}->{"db_port"}, '^\d*$' );
        $config->{$modulename}->{db_port} = $tmp if ( $tmp ne "" );
        $tmp = &ask( "Enter the username for the MySQL database (leave blank for default) ", $db_username, $config->{$modulename}->{"db_username"}, '' );
        $config->{$modulename}->{db_username} = $tmp if ( $tmp ne "" );
        $tmp = &ask( "Enter the password for the MySQL database (leave blank for default) ", $db_password, $config->{$modulename}->{"db_password"}, '' );
        $config->{$modulename}->{db_password} = $tmp if ( $tmp ne "" );
	ReadMode 'noecho';
	my $root_pass = &ask( "Enter the 'root' password for the MySQL database  ",  '',undef, '' );
	ReadMode 'normal';
        $config->{$modulename}->{db_password} = $tmp if ( $tmp ne "" );
	eval {
	    require DBD::mysql;
	    require DBI;

	    system("mysql -u root -p'$root_pass' -e 'create  database if not exists  $config->{$modulename}->{db_name}'");
	    system("mysql -u root ->{db_username} -p'$root_pass' -e 'grant all privileges  $config->{$modulename}->{db_name}.* to 
	            '$config->{$modulename}->{db_username}'@'localhost' identified by '$config->{$modulename}->{db_password}'");
	    system("mysql -u root ->{db_username} -p'$root_pass' -e 'flush privileges'");
	    system("mysql -u $config->{$modulename}->{db_username} -p'$config->{$modulename}->{db_password}' $config->{$modulename}->{db_name} < $dirname/../scripts/create_pingerMA_MySQL.sql");
	 
	    my $dbh = DBI->connect("dbi:mysql:database=$config->{$modulename}->{db_name}",  $config->{$modulename}->{db_username}, $config->{$modulename}->{db_password}, 
	                            { AutoCommit => 1,
                                      RaiseError => 1 });
	    $dbh->do("INSERT into host (ip_name, ip_number, comments) values ('test_name', '1.0.0.1', 'test')");
	    
	    if($dbh->err()) { die "$DBI::errstr\n"; }
	};
	if($EVAL_ERROR) {
	    die " $EVAL_ERROR :: You have to install perl DBD::mysql driver, run: sudo cpan -i 'DBD::mysql' ";
	}
    }

    if ( $modulename eq "pingermp" ) {
        $config->{$modulename}->{"configuration_file"} = &ask( "Name of XML configuration file for landmarks and schedules ", "pinger-landmarks.xml", $config->{$modulename}->{"configuration_file"}, '.+' );
    }

    if ( $modulename eq "pingerma" ) {
        $config->{$modulename}->{"query_size_limit"} = &ask( "Enter the limit on query size ", "100000", $config->{$modulename}->{"query_size_limit"}, '^\d*$' );
    }

    $config->{$modulename}->{"enable_registration"} = &ask( "Will this service register with an LS (0,1) ", "0", $config->{$modulename}->{"enable_registration"}, '^[01]$' );

    if ( $config->{$modulename}->{"enable_registration"} eq "1" ) {
        my $registration_interval = $def_config->{"ls_registration_interval"};
        $registration_interval = $config->{$modulename}->{"ls_registration_interval"} if ( defined $config->{$modulename}->{"ls_registration_interval"} );
        $config->{$modulename}->{"ls_registration_interval"} = &ask( "Enter the number of minutes between LS registrations ", "30", $registration_interval, '^\d+$' );
    }
    $config->{$modulename}->{"service_name"} = &ask( "Enter a name for this service ", "PingER $moduletype", $config->{$modulename}->{"service_name"}, '.+' );

    $config->{$modulename}->{"service_type"} = &ask( "Enter the service type ", $moduletype, $config->{$modulename}->{"service_type"}, '.+' );

    $config->{$modulename}->{"service_description"} = &ask( "Enter a service description ", "PingER $moduletype on $default_hostname", $config->{$modulename}->{"service_description"}, '.+' );

    $config->{$modulename}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{$modulename}->{"service_accesspoint"}, '^http:\/\/' );

}

sub config_status_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"status"} = () unless exists $config->{"status"};
    $config->{"status"}->{"read_only"} = &ask( "Is this service read-only  (0 for no, 1 for yes) ", "0", $config->{"status"}->{"read_only"}, '^[01]$' );

    $config->{"status"}->{"db_type"} = &ask( "Enter the database type to read from ", "sqlite|mysql", $config->{"status"}->{"db_type"}, '(sqlite|mysql)' );

    if ( $config->{"status"}->{"db_type"} eq "sqlite" ) {
        $config->{"status"}->{"db_file"} = &ask( "Enter the filename of the SQLite database ", "status.db", $config->{"status"}->{"db_file"}, '.+' );
        $tmp = &ask( "Enter the table in the database to use ", "link_status", $config->{"status"}->{"db_table"}, '.+' );
        $config->{"status"}->{"db_table"} = $tmp if ($tmp);
    }
    elsif ( $config->{"status"}->{"db_type"} eq "mysql" ) {
        $config->{"status"}->{"db_name"} = &ask( "Enter the name of the MySQL database ",                               q{},         $config->{"status"}->{"db_name"}, '.+' );
        $config->{"status"}->{"db_host"} = &ask( "Enter the host for the MySQL database ",                              "localhost", $config->{"status"}->{"db_host"}, '.+' );
        $tmp                             = &ask( "Enter the port for the MySQL database (leave blank for the default)", q{},         $config->{"status"}->{"db_port"}, '^\d*$' );
        $config->{"status"}->{"db_port"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the username for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"db_username"}, q{} );
        $config->{"status"}->{"db_username"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the password for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"db_password"}, q{} );
        $config->{"status"}->{"db_password"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the table in the database to use (leave blank for the default) ", "link_status", $config->{"status"}->{"db_table"}, q{} );
        $config->{"status"}->{"db_table"} = $tmp if ($tmp);
    }

    $config->{"status"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes) ", "0", $config->{"status"}->{"enable_registration"}, '^[01]$' );

    if ( $config->{"status"}->{"enable_registration"} eq "1" ) {
        my $registration_interval = $def_config->{"ls_registration_interval"};
        $registration_interval = $config->{"status"}->{"ls_registration_interval"} if ( defined $config->{"status"}->{"ls_registration_interval"} );
        $config->{"status"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );

        my $ls_instance = $def_config->{"ls_instance"};
        $ls_instance = $config->{"status"}->{"ls_instance"} if ( defined $config->{"status"}->{"ls_instance"} );
        $config->{"status"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );

        $config->{"status"}->{"service_name"} = &ask( "Enter a name for this service ", "Link Status MA", $config->{"status"}->{"service_name"}, '.+' );

        $config->{"status"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"status"}->{"service_type"}, '.+' );

        $config->{"status"}->{"service_description"} = &ask( "Enter a service description ", "Link Status MA", $config->{"status"}->{"service_description"}, '.+' );

        $config->{"status"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"status"}->{"service_accesspoint"}, '^http:\/\/' );
    }
    return;
}

sub config_circuitstatus_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"circuitstatus"} = () unless exists $config->{"circuitstatus"};
    $config->{"circuitstatus"}->{"circuits_file_type"} = "file";

    $config->{"circuitstatus"}->{"circuits_file"} = &ask( "Enter the file to get link information from ", q{}, $config->{"circuitstatus"}->{"circuits_file"}, '.+' );

    $config->{"circuitstatus"}->{"status_ma_type"} = &ask( "Enter the MA to get status information from ", "sqlite|mysql", $config->{"circuitstatus"}->{"status_ma_type"}, '(sqlite|mysql|ma|ls)' );

    if ( $config->{"circuitstatus"}->{"status_ma_type"} eq "ma" ) {
        $config->{"circuitstatus"}->{"status_ma_uri"} = &ask( "Enter the URI of the Status MA ", q{}, $config->{"circuitstatus"}->{"status_ma_uri"}, '^http' );
    }
    elsif ( $config->{"circuitstatus"}->{"status_ma_type"} eq "ls" ) {
        my $ls = $def_config->{"ls_instance"};
        $ls = $config->{"circuitstatus"}->{"ls_instance"} if ( defined $config->{"circuitstatus"}->{"ls_instance"} );
        $config->{"circuitstatus"}->{"ls_instance"} = &ask( "Enter the URI of the LS to get MA information from ", q{}, $ls, '^http' );
    }
    elsif ( $config->{"circuitstatus"}->{"status_ma_type"} eq "sqlite" ) {
        $config->{"circuitstatus"}->{"status_ma_name"}  = &ask( "Enter the filename of the SQLite database ", q{},           $config->{"status"}->{"status_ma_name"},  '.+' );
        $config->{"circuitstatus"}->{"status_ma_table"} = &ask( "Enter the table in the database to use ",    "link_status", $config->{"status"}->{"status_ma_table"}, '.+' );
    }
    elsif ( $config->{"circuitstatus"}->{"status_ma_type"} eq "mysql" ) {
        $config->{"status"}->{"status_ma_name"} = &ask( "Enter the name of the MySQL database ",                               q{},         $config->{"status"}->{"status_ma_name"}, '.+' );
        $config->{"status"}->{"status_ma_host"} = &ask( "Enter the host for the MySQL database ",                              "localhost", $config->{"status"}->{"status_ma_host"}, '.+' );
        $tmp                                    = &ask( "Enter the port for the MySQL database (leave blank for the default)", q{},         $config->{"status"}->{"status_ma_port"}, '^\d*$' );
        $config->{"status"}->{"status_ma_port"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the username for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"status_ma_username"}, q{} );
        $config->{"status"}->{"status_ma_username"} = $tmp if ($tmp);
        $tmp = &ask( "Enter the password for the MySQL database (leave blank for none) ", q{}, $config->{"status"}->{"status_ma_password"}, q{} );
        $config->{"status"}->{"status_ma_password"} = $tmp if ($tmp);
        $config->{"circuitstatus"}->{"status_ma_table"} = &ask( "Enter the table in the database to use ", "link_status", $config->{"status"}->{"status_ma_table"}, '.+' );
    }

    $config->{"circuitstatus"}->{"topology_ma_type"} = &ask( "Enter the MA to get Topology information from ", "sqlite|mysql", $config->{"circuitstatus"}->{"topology_ma_type"}, '(xml|ma|none)' );

    $config->{"circuitstatus"}->{"topology_ma_type"} = lc( $config->{"circuitstatus"}->{"topology_ma_type"} );

    if ( $config->{"circuitstatus"}->{"topology_ma_type"} eq "xml" ) {
        $config->{"topology"}->{"topology_ma_name"} = &ask( "Enter the directory of the XML database ", q{}, $config->{"topology"}->{"topology_ma_name"}, '.+' );
        $config->{"topology"}->{"topology_ma_file"} = &ask( "Enter the filename of the XML database ",  q{}, $config->{"topology"}->{"topology_ma_file"}, '.+' );
    }
    elsif ( $config->{"circuitstatus"}->{"topology_ma_type"} eq "ma" ) {
        $config->{"circuitstatus"}->{"topology_ma_uri"} = &ask( "Enter the URI of the Status MA ", q{}, $config->{"circuitstatus"}->{"topology_ma_uri"}, '^http' );
    }

    $config->{"circuitstatus"}->{"cache_length"} = &ask( "Enter length of time to cache 'current' results ", q{}, $config->{"circuitstatus"}->{"cache_length"}, '^\d+$' );
    if ( $config->{"circuitstatus"}->{"cache_length"} > 0 ) {
        $config->{"circuitstatus"}->{"cache_file"} = &ask( "Enter file to cache 'current' results in ", q{}, $config->{"circuitstatus"}->{"cache_file"}, '.+' );
    }

    $config->{"circuitstatus"}->{"max_recent_age"} = &ask( "Enter age in seconds at which a result is considered stale ", q{}, $config->{"circuitstatus"}->{"max_recent_age"}, '^\d+$' );
    return;
}

sub config_topology_ma {
    my ( $config, $accesspoint, $def_config ) = @_;

    $config->{"topology"} = () unless exists $config->{"topology"};
    $config->{"topology"}->{"db_type"} = "xml";

    $config->{"topology"}->{"read_only"} = &ask( "Is this service read-only (0 for no, 1 for yes) ", "1", $config->{"topology"}->{"read_only"}, '^[01]$' );

    $config->{"topology"}->{"db_environment"} = &ask( "Enter the directory of the XML database ", q{}, $config->{"topology"}->{"db_environment"}, '.+' );

    $config->{"topology"}->{"db_file"} = &ask( "Enter the filename of the XML database ", q{}, $config->{"topology"}->{"db_file"}, '.+' );

    $config->{"topology"}->{"enable_registration"} = &ask( "Will this service register with an LS (0 for no, 1 for yes) ", "0", $config->{"topology"}->{"enable_registration"}, '^[01]$' );

    if ( $config->{"topology"}->{"enable_registration"} eq "1" ) {
        my $registration_interval = $def_config->{"ls_registration_interval"};
        $registration_interval = $config->{"topology"}->{"ls_registration_interval"} if ( defined $config->{"topology"}->{"ls_registration_interval"} );
        $config->{"topology"}->{"ls_registration_interval"} = &ask( "Interval between when LS registrations occur [in minutes] ", "30", $registration_interval, '^\d+$' );

        my $ls_instance = $def_config->{"ls_instance"};
        $ls_instance = $config->{"topology"}->{"ls_instance"} if ( defined $config->{"topology"}->{"ls_instance"} );
        $config->{"topology"}->{"ls_instance"} = &ask( "URL of an LS to register with ", q{}, $ls_instance, '^http:\/\/' );

        $config->{"topology"}->{"service_name"} = &ask( "Enter a name for this service ", "Topology MA", $config->{"topology"}->{"service_name"}, '.+' );

        $config->{"topology"}->{"service_type"} = &ask( "Enter the service type ", "MA", $config->{"topology"}->{"service_type"}, '.+' );

        $config->{"topology"}->{"service_description"} = &ask( "Enter a service description ", "Topology MA", $config->{"topology"}->{"service_description"}, '.+' );

        $config->{"topology"}->{"service_accesspoint"} = &ask( "Enter the service's URI ", $accesspoint, $config->{"topology"}->{"service_accesspoint"}, '^http:\/\/' );
    }
    return;
}

sub ask {
    my ( $prompt, $value, $prev_value, $regex ) = @_;

    my $result;
    do {
        print $prompt;
        if ( defined $prev_value ) {
            print "[", $prev_value, "]";
        }
        elsif ( defined $value ) {
            print "[", $value, "]";
        }
        print ": ";
        local $| = 1;
	
        local $_ = <STDIN>;
        chomp;
        if ( defined $_ and $_ ne q{} ) {
            $result = $_;
        }
        elsif ( defined $prev_value ) {
            $result = $prev_value;
        }
        elsif ( defined $value ) {
            $result = $value;
        }
        else {
            $result = q{};
        }
    } while ( $regex and ( not $result =~ /$regex/mx ) );

    return $result;
}

sub SaveConfig_mine {
    my ( $file, $hash ) = @_;

    my $fh;

    if ( open( $fh, ">", $file ) ) {
        printValue( $fh, q{}, $hash, -4 );
        if ( close($fh) ) {
            return 0;
        }
    }
    return -1;
}

sub printSpaces {
    my ( $fh, $count ) = @_;
    while ( $count > 0 ) {
        print $fh " ";
        $count--;
    }
    return;
}

sub printScalar {
    my ( $fileHandle, $name, $value, $depth ) = @_;

    printSpaces( $fileHandle, $depth );
    if ( $value =~ /\n/mx ) {
        my @lines = split( $value, '\n' );
        print $fileHandle "$name     <<EOF\n";
        foreach my $line (@lines) {
            printSpaces( $fileHandle, $depth );
            print $fileHandle $line . "\n";
        }
        printSpaces( $fileHandle, $depth );
        print $fileHandle "EOF\n";
    }
    else {
        print $fileHandle "$name     " . $value . "\n";
    }
    return;
}

sub printValue {
    my ( $fileHandle, $name, $value, $depth ) = @_;

    if ( ref $value eq "" ) {
        printScalar( $fileHandle, $name, $value, $depth );

        return;
    }
    elsif ( ref $value eq "ARRAY" ) {
        foreach my $elm ( @{$value} ) {
            printValue( $fileHandle, $name, $elm, $depth );
        }

        return;
    }
    elsif ( ref $value eq "HASH" ) {
        if ( $name eq "endpoint" or $name eq "port" ) {
            foreach my $elm ( sort keys %{$value} ) {
                printSpaces( $fileHandle, $depth );
                print $fileHandle "<$name $elm>\n";
                printValue( $fileHandle, q{}, $value->{$elm}, $depth + 4 );
                printSpaces( $fileHandle, $depth );
                print $fileHandle "</$name>\n";
            }
        }
        else {
            if ($name) {
                printSpaces( $fileHandle, $depth );
                print $fileHandle "<$name>\n";
            }
            foreach my $elm ( sort keys %{$value} ) {
                printValue( $fileHandle, $elm, $value->{$elm}, $depth + 4 );
            }
            if ($name) {
                printSpaces( $fileHandle, $depth );
                print $fileHandle "</$name>\n";
            }
        }

        return;
    }
}

__END__
	
=head1 SEE ALSO

L<Config::General>, L<Sys::Hostname>, L<Data::Dumper>

To join the 'perfSONAR Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu
Aaron Brown, aaron@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2004-2010, Internet2 and the University of Delaware

All rights reserved.

=cut
