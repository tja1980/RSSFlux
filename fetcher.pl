#!/usr/bin/env perl

use strict;
use warnings;


use LWP;
use TryCatch;
use XML::RSS::Parser::Lite;

use Data::Dumper;

use lib 'lib';
use Config::Tiny;
use Log::Tiny;
use Moose;
use Schema;


our $VERSION = '1.0';

my $config = Config::Tiny->read( 'default.conf' );

my $log    = Log::Tiny->new( $config->{log}->{filename} )
                or _error ( "Could not open log file " . $config->{log}->{filename} .
                    " for write. (Cause: " . Log::Tiny->errstr . ")" );

{
    # ^([A-Za-z\.\-0-9]{1,})([S]{1}[0-9]{1,2}[E]{1}[0-9]{1,2}).{1,}$
    
    $log->INFO ( sprintf ( "Fetcher, Version %s", $VERSION ) );
    
    $log->DEBUG ( Dumper ( $config ) );
    
    my $schema  = Schema->connect (
        $config->{database}->{dsn}, $config->{database}->{username}, $config->{database}->{password}
    );
    
    my $urls        = get_rss_urls( $schema );
    my $watchFor    = get_watch_for( $schema );
    
    foreach my $key ( keys ( %{$urls} ) ) {
        my $browser     = LWP::UserAgent->new;
        my $response    = $browser->get ( $urls->{$key}->{'url'} );
        
        unless ( $response->is_success ) {
            _warn ( "Can't get $urls->{$key}->{'url'}. (Cause: " . $response->status_line . ")" );
            next;
        }
        
        my $rp 	= new XML::RSS::Parser::Lite;
        
        $rp->parse($response->content);
        
        for (my $i = 0; $i < $rp->count(); $i++) {
            my $it = $rp->get($i);
            
            if ( get_torrent_history ( $schema, $it->get('title') ) == 0 ) {
                set_torrent_history ( $schema, {
                    'title' => $it->get('title'),
                    'url'   => $it->get('url'),
                    'rid'   => $urls->{$key}->{'id'}
                });
            }
            
            foreach my $watchItem ( keys ( %{$watchFor} ) ) {
                
                my $item = $it->get('title');
                
                $item =~ m/^([A-Za-z\.\-0-9]{1,})[\.]{1}([S]{1}[0-9]{1,2}[E]{1}[0-9]{1,2}).{1,}$/;
                
                my $showName        = uc( $1 );
                my $seasonEpisode   = uc( $2 );
                
                # TODO: Add double ep feature..
                
                my $matchString     = ( $watchItem ) =~ s/\s/\./g;
                
                if ( $showName eq $matchString ) {
                    if ( defined( $watchFor->{$watchItem}->{'has'} ) ) {
                        
                        next if _notKeywords ( $watchItem, $watchFor->{$watchItem}->{'not'} ) == 1;
                        next if _hasKeywords ( $watchItem, $watchFor->{$watchItem}->{'has'} ) == 1;
                        
                        # if ( $it->get('url') =~ m/([\.0-9\-A-Za-z]{1,}[\.]{1}[a-z]{1,})[\?]{1}/ ) {
                        
                        
                        if ( int ( $watchFor->{$watchItem}->{'smartepfilter'} ) == 1 ) {
                            if ( $it->get('title') =~ m/S([0-9]{1,})E([0-9]{1,})/ ) {
                                
                                my $season 	= $1;
                                my $episode	= $2;
                                
                                next if smart_ep_filter ( $schema, $watchFor->{$watchItem}->{'id'}, $season, $episode ) >= 1;

                                update_last_seen ( $schema, $watchFor->{$watchItem}->{'id'} );
                                
                                #my $filename;
                                #
                                #print Dumper $it;
                                #
                                #if ( $it->get('url') =~ m/([\.0-9\-A-Za-z]{1,}[\.]{1}[a-z]{1,})[\?]{1}/ ) {
                                #
                                #    print Dumper $it->get('url');
                                #
                                #    $filename = $1;
                                #
                                #    #getstore ( $it->get('url'), sprintf ( "%s/%s", '/mnt/data/rss/received', $filename ) )
                                #    #	or die $!;a
                                #    $response = $browser->get($it->get('url'),':content_file' => sprintf ( "%s/%s", '/mnt/data/rss/received', $filename ));
                                #
                                #    print Dumper $response;
                                #    
                                #    if ( $response->is_success ) {
                                #            update_smart_ep_filter ( $watchFor->{$watchItem}->{'id'}, $season, $episode );
                                #    }
                                #    else {
                                #            die "Can't get $it->get('url') -- ", $response->status_line;
                                #    }
                                #
                                #}

                                        
                                

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
##  Common
###
    
sub _error {
    my $message = shift;    
    $log->ERROR ( $message );    
    die $message;
}

sub _warn {
    my $message = shift;    
    $log->WARN ( $message );    
}

sub _notKeywords {
    my ( $item, $keywords ) = @_;
    my $fail = 0;
    
    my @notKeywords = split ( /,/, $keywords );
                        
    foreach my $not ( @notKeywords ) {
        if ( $item =~ m/$not/ ) {
            $fail = 1;
            last;
        }
    }
    
    undef ( @notKeywords );
    
    return $fail;
}

sub _hasKeywords {
    my ( $item, $keywords ) = @_;
    my $fail = 0;
    
    my @hasKeywords = split ( /,/, $keywords );
                        
    foreach my $has ( @hasKeywords ) {
        unless ( $item =~ m/$has/ ) {
            $fail = 1;
            last;
        }
    }
    
    undef ( @hasKeywords );
    
    return $fail;
}

#
##  Functions
###

sub smart_ep_filter {
    my ( $schema, $id, $season, $episode_number ) = @_;

    my $exists = $schema->resultset('SmartEpFilter')->search(
        {
            'watch_id'  => $id,
            'season'    => $season,
            'episode'   => $episode_number
        }
    )->count;
    
    return $exists;    
}

sub get_rss_urls {
    my $schema  = shift;
    my $urls    = ();
    
    $log->INFO( "Getting RSS Feed Urls..." );
    
    my @results = $schema->resultset('Feeds')->all;
    
    foreach my $result ( @results ) {
        next if $result->enabled != 1;
        
        $urls->{$result->name} = {
            url => $result->url 
        };
        
        $log->INFO ( "Added Feed URL " . $result->name );
    }
    
    return $urls;
    
}

sub update_last_seen {
    my ( $schema, $id ) = shift;

    $schema->resultset("Watch")->search(
        { 'id' => $id }
    );
    
    $schema->update({ lastseen => 'NOW()' });
}

sub get_watch_for {
    my $schema  = shift;
    my $rules   = ();
    
    $log->INFO ( "Getting Watch Rules..." );
    
    my @results = $schema->resultset('Watch')->all;
    
    foreach my $result ( @results ) {
        if ( defined ( $rules->{$result->name} ) ) {
            _warn ( "Show " . $result->name . ", with id " . $result->id . " allready exists in watch list." );
        }
        
        $rules->{$result->name} = {
            'id'	            => $result->id,
            'has'               => $result->has,
            'not'	            => $result->not,
            'smartepfilter'   => $result->smart_ep_filter
        };
        
        $log->INFO ( "Added Watch Rule for " . $result->name );
    }
    
    return $rules;
    
}

sub set_torrent_history {
    my ( $schema, $detail ) = @_;
    
    $log->DEBUG(sprintf("Set Torrent %s ", $detail->{'title'} ) );
    
    $schema->resultset("Torrents")->create( $detail );
}

sub get_torrent_history {
    my ( $schema, $title ) = @_;
    
    
    
    my $exists = $schema->resultset("Torrents")->search( {
        'title' => $title } )->count;
    
    $log->DEBUG(sprintf("Get Torrent count %s for %s ", $exists, $title ) );
    
    return $exists;
}