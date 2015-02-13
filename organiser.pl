#!/bin/env perl

use strict;
use warnings;

use DBI;
use File::Path qw(make_path);
use Getopt::Long;

use Data::Dumper;

my $source;
my $destination;

my $driver      = "mysql";
my $database    = "";
my $dsn         = "DBI:$driver:dbname=$database";
my $username    = "";
my $password    = "";

GetOptions( "source=s"	=> \$source, "destination=s"	=> \$destination )
	or die ( "Error in command line arguments!\n" );

die "Missing argument --source <path>..." unless ( defined ( $source ) );
die "Missing argument --destination <path>..." unless ( defined ( $destination ) );

{
	chdir ( $source )
		or die $!;

	my @items = <*>;

	if ( scalar ( @items ) > 0 ) {

		my $rules = getRules();

		foreach my $item ( @items ) {
			my $testString = $item;

			$testString =~ s/[\s-]{2,}/\./g;
			$testString =~ s/\./ /g;
			$testString =~ s/\(//g;
			$testString =~ s/\)//g;	
	
			#printf ( "ITEM: '%s'\n", $item );
			#printf ( "Test String: %s\n", $testString );
		
			foreach my $rule ( keys %{$rules} ) {
				print Dumper $rule;

				if ( $testString =~ m/^$rule[\s-]{1,}S[0-9]{1,}E[0-9]{1,}/ ) {
					my $show = $rule;
					printf ( " RULE: '^%s\\s{1,}S[0-9]{1,}E[0-9]{1,}'\n", $rule );
					printf ( " Match -> %s\n", $show );

					if ( $item =~ m/S([0-9]{1,})E([0-9]{1,})/ ) {
						my $season      = $1;
                                                my $episode     = $2;

						my $libraryLocation = sprintf ( "%s/%s/season/%s", $destination, lc($show), $season );

						my $showDirectory = $libraryLocation;

						$showDirectory =~ s/ /\\ /g;

						#printf ( "Show Directory: %s\n", $showDirectory );

						unless ( -e $libraryLocation ) {
							printf ( " -> Created Directory '%s'\n", $libraryLocation );
							make_path ( $libraryLocation );
						}

						printf ( "Item: %s\n", $item );

						if ( -d $item ) {

							printf ( "Changing Directory to %s...\n", $item );
						
							chdir ( $item )
								or die $!;

							if ( -e ".organiser" ) {
								#printf "Organiser Control File Found...\n";
								next;
							}
							else {
								printf "%s...\n", $item;
							}

							my @types = qw/rar avi/;

							foreach my $type ( @types ) {
								my @files = <*.$type>;

								next if scalar ( @files ) == 0;

								my $command;

								if ( $type eq 'rar' ) {
									my $archive = $files[0];
									chomp ( $archive );

									$command = sprintf ( "7z e \"%s\" -o%s", $archive, $showDirectory );
								}
								elsif ( $type eq 'avi' ) {
									$command = sprintf ( "cp \"%s\" %s", $files[0], $showDirectory );
								}
							
								printf ( " -> Command - %s\n", $command );

                                                                system ( $command );

							}

							$showDirectory =~ s/\\\\//g;

							system ( "chown nobody:nogroup -R \"$showDirectory\"" );
	
							update_smart_ep_filter ( $rules->{$rule}->{'id'}, $season, $episode );

							

							open ( my $fhOut, ">", ".organiser" )
								or die $!;

							close ( $fhOut );

							chdir ( $source )
								or die $!;

						}
						else {
							if ( ( substr ( $item, length ( $item ) - 3, 3 ) eq 'mkv' ) or
								( substr ( $item, length ( $item ) - 3, 3 ) eq 'avi' ) ) {
								if ( -e ".$item.organiser" ) {
                                                                	#printf "Organiser Control File Found...\n";
                                                                	next;
                                                        	}
                                                        	else {
                                                                	printf "%s...\n", $item;
                                                        	}

								 my $command = sprintf ( "cp \"%s\" %s", $item, $showDirectory );

                                                        printf ( " -> Command - %s\n", $command );

                                                        system ( $command );

                                                        system ( "chown nobody:nogroup $showDirectory/$item" );

                                                        update_smart_ep_filter ( $rules->{$rule}->{'id'}, $season, $episode );



                                                        open ( my $fhOut, ">", ".$item.organiser" )
                                                                or die $!;

                                                        close ( $fhOut );

                                                        chdir ( $source )
                                                                or die $!;

							}

						}
					}
					else {
						printf "Couldn't work out TV Season/Episode...\n";
					}
				}
			}

			chdir ( $source );
		}

		undef ( @items );

	}
}



sub getRules {

	my $dbh = __connect ();

        my $sql = sprintf "SELECT * FROM rss_watch";

        my $sth = $dbh->prepare ( $sql )
                or die $!;

        $sth->execute()
                or die $!;

        my $rules = ();

        while ( my $row = $sth->fetchrow_hashref()) {
                unless ( defined ( $rules->{$row->{'name'}} ) ) {

                        my @has;
                        my @not;

                        if ( index ( $row->{'has'}, "," ) > 0 ) {
                                @has = split ( /,/, $row->{'has'} );
                        }
                        else {
                                push ( @has, $row->{'has'} );
                        }

                        $rules->{$row->{'name'}} = {
                                'id'    => $row->{'id'},
                                'has'   => @has,
                                'not'   => undef,
                                'smart_ep_filter'       => $row->{'smart_ep_filter'}

                        };

                        undef @has;
                        undef @not;
                }
        }

        $sth->finish();

        __disconnect ( $dbh );

        return $rules;

}

#
##  Database Functions
###

sub __connect {
    my $dbh = DBI->connect($dsn,$username,$password, { RaiseError => 1 })
        or die $DBI::errstr;

    return $dbh;
}

sub __disconnect {
    my $dbh = shift;

    $dbh->disconnect();
}

sub update_smart_ep_filter {
        my ( $id, $season, $episode ) = @_;

        my $dbh = __connect ();

        my $sql = sprintf "INSERT INTO smart_ep_filter (season, episode, watch_id, added ) VALUES ( ?, ?, ?, NOW() )";

        my $sth = $dbh->prepare ( $sql )
                or die $!;

        $sth->execute( $season, $episode, $id )
                or die $!;

        $sth->finish();

        __disconnect ( $dbh );
}

