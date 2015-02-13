#!bin/env perl

use strict;
use warnings;

use Data::Dumper;

use DBI;
use File::Fetch;
use Getopt::Long;
use LWP;
use XML::RSS::Parser::Lite;


use lib 'lib';

my $driver      = "mysql";
my $database    = "rss";
my $dsn         = "DBI:$driver:dbname=$database";
my $username    = "root";
my $password    = "5n00Py1337";



{

	my $urls 	= get_rss_urls();
	my $watchFor	= get_watch_for();

	foreach my $key ( keys ( %{$urls} ) ) {
		printf STDOUT ( "Fetching Feed URL %s...\n", $key );

		#my $xml = get ( $urls->{$key}->{'url'} );

		my $browser = LWP::UserAgent->new;
		my $response = $browser->get ( $urls->{$key}->{'url'} );
   	 	
		die "Can't get $urls->{$key}->{'url'} -- ", $response->status_line
			unless $response->is_success;

		my $rp 	= new XML::RSS::Parser::Lite;
		$rp->parse($response->content);

		print Dumper $response->content;
    		
		for (my $i = 0; $i < $rp->count(); $i++) {
		        my $it = $rp->get($i);

			my $failKeyword = 0;
        
		        foreach my $watchItem ( keys ( %{$watchFor} ) ) {
		            if ( $it->get('title') =~ m/$watchItem/ ) {
		                printf ( " - Found series match %s...\n", $watchItem );
		                if ( defined( $watchFor->{$watchItem}->{'has'} ) ) {
				   printf ( "\t* Title: %s\n", $it->get('title') );
                    
                    
                		    #
		                    ##  Check our 'has' rules...
		                    ###

				    my @hasKeywords = $watchFor->{$watchItem}->{'has'};	

					printf "\t* Checking 'has' keyword rules...\n";
                    
                		    foreach my $has ( @hasKeywords ) {
					 printf ( "\t -> '%s' ... ", $has ); 

		                        if ($it->get('title') =~ m/$has/ ) {
                		            printf "Found\n";
		                        }
                		        else {
		                            printf ( "Not Found\n", $has );
						$failKeyword = 1;
                		        }
		                    }
                    
		                    #
		                    ##  Smart EP Filtering
		                    ###
                    			if (( int ( $watchFor->{$watchItem}->{'smart_ep_filter'} ) == 1 ) && ( $failKeyword == 0 ) ) {
	                		    	if ( $it->get('title') =~ m/S([0-9]{1,})E([0-9]{1,})/ ) {
		                        		printf "\t* Querying Smart Episode Filter\n";
							my $season 	= $1;
							my $episode	= $2;
							
							my $exists = smart_ep_filter ( $watchFor->{$watchItem}->{'id'}, $season, $episode );

							if ( $exists ) {
								printf "\t -> Allready registered!\n";
							}
							else {

								# 2.Broke.Girls.S03E24.720p.HDTV.X264-DIMENSION.torrent
								my $filename;

								print Dumper $it;

								if ( $it->get('url') =~ m/([\.0-9\-A-Za-z]{1,}[\.]{1}[a-z]{1,})[\?]{1}/ ) {

									print Dumper $it->get('url');

									$filename = $1;

									#getstore ( $it->get('url'), sprintf ( "%s/%s", '/mnt/data/rss/received', $filename ) )
									#	or die $!;a
									$response = $browser->get($it->get('url'),':content_file' => sprintf ( "%s/%s", '/mnt/data/rss/received', $filename ));

									print Dumper $response;
									
									if ( $response->is_success ) {
										update_smart_ep_filter ( $watchFor->{$watchItem}->{'id'}, $season, $episode );
									}
									else {
										die "Can't get $it->get('url') -- ", $response->status_line;
									}

								}

								
							}
	
						}
						else {
							printf "Couldn't reliably determine Season and/or Episode, sorry!\n";
						}
	
		         	        }
        		            
                    
               			 }
		            }
		        }
		}
	}
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

sub get_rss_urls {
	my $dbh = __connect ();

	my $sql = sprintf "SELECT * FROM rss_feed_urls";

	my $sth = $dbh->prepare ( $sql )
		or die $!;

	$sth->execute()
		or die $!;

	my $urls = ();

	while ( my $row = $sth->fetchrow_hashref()) {
		print Dumper $row;

		if ( int ( $row->{'enabled'} ) == 1 ) {
			unless ( defined ( $urls->{$row->{'name'}} ) ) {
				$urls->{$row->{'name'}} = {
						'url'	=> $row->{'url'}
					};
			}
		}
	}

	$sth->finish();

	__disconnect ( $dbh );

	return $urls;
	
}

sub get_watch_for {
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
				'id'	=> $row->{'id'},
                        	'has'   => @has,
				'not'	=> undef,
				'smart_ep_filter'	=> $row->{'smart_ep_filter'}

                        };

			undef @has;
			undef @not;
                }
        }

        $sth->finish();

        __disconnect ( $dbh );

        return $rules;
}

sub smart_ep_filter {
	my ( $id, $season, $episode_number ) = @_;

        my $dbh = __connect ();

        my $sql = sprintf ( "SELECT * FROM smart_ep_filter WHERE watch_id = '%s' AND season = '%s' and episode = '%s'", $id, $season, $episode_number ) ;

        my $sth = $dbh->prepare ( $sql )
                or die $!;

        $sth->execute()
                or die $!;

        my $episode = ();

        while ( my $row = $sth->fetchrow_hashref()) {
               $episode->{$row->{'id'}} = {
                                'season'   => $row->{'season'},
                                'episode'   => $row->{'episode'},
                                'watch_id'       => $row->{'watch_id'}

               };


        }

        $sth->finish();

        __disconnect ( $dbh );

        return $episode;
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

	update_last_seen ( $id );
}

sub update_last_seen {
	my ( $id ) = shift;

	my $dbh = __connect ();

	my $sql = sprintf "UPDATE rss_watch SET last_seen = NOW() WHERE id = ?";

	 my $sth = $dbh->prepare ( $sql )
                or die $!;

        $sth->execute( $id )
                or die $!;

        $sth->finish();

        __disconnect ( $dbh );

}
