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


our $VERSION = '1.1';

my $config = Config::Tiny->read( 'default.conf' );

my $log    = Log::Tiny->new( $config->{log}->{filename} )
                or _error ( "Could not open log file " . $config->{log}->{filename} .
                    " for write. (Cause: " . Log::Tiny->errstr . ")" );

{
    $log->INFO ( sprintf ( "Fetcher, Version %s", $VERSION ) );
    
    my $schema  = Schema->connect (
        $config->{database}->{dsn}, $config->{database}->{username}, $config->{database}->{password}
    );
    
    my $urls        = get_rss_urls( $schema );
    my $watchFor    = get_watch_for( $schema );
    
    foreach my $key ( keys ( %{$urls} ) ) {
        my $browser     = LWP::UserAgent->new;
        my $response    = $browser->get ( $urls->{$key}->{'url'} );
        
        unless ( $response->is_success ) {
            _warn ( "Can't get " . $urls->{$key}->{'url'} . ". (Cause: " . $response->status_line . ")" );
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
                
                if ( uc( $item ) =~ m/^([A-Z\.\-0-9\s]{1,})([S]{1}[0-9]{1,2}[E]{1}[0-9]{1,2}).{1,}$/ ) {
                    my $showName        = $1;
                    my $seasonEpisode   = $2;
                    
                    $showName =~ s/\s$//g;
                    
                    if ( $showName eq uc( $watchItem ) ) {
                        
                        $log->INFO ( "Found TV Show " . $showName );
                        
                        next if _notKeywords ( $item, $watchFor->{$watchItem}->{'not'} ) == 1;
                        next if _hasKeywords ( $item, $watchFor->{$watchItem}->{'has'} ) == 0;
                            
                        if ( $it->get('title') =~ m/S([0-9]{1,})E([0-9]{1,})/ ) {
                            my $season 	= $1;
                            my $episode	= $2;
                            
                            if ( $it->get('url') =~ m/([\.0-9\-A-Za-z]{1,}[\.]{1}[a-z]{1,})[\?]{1}/ ) {
                                my $torrentSaveTo = sprintf ( "%s/%s", $config->{'paths'}->{'torrents'}, $1 );
                                
                                $response = $browser->get($it->get('url'),':content_file' => $torrentSaveTo );
    
                                if ( $response->is_success ) {
                                    $log->INFO("Saved .torrent as " . $torrentSaveTo );
                                }
                                else {
                                    _warn("Can't retrieve torrent url " . $it->get('url') . ", returned " . $response->status_line );
                                    next;
                                }
                            }
                            else {
                                _warn("Couldn't determine a filename to save the .torrent from url " . $it->get('url') . ".");
                                next;
                            }
                            
                            if ( $watchFor->{$watchItem}->{'smartepfilter'} eq 'Y' ) {
                                if ( smart_ep_filter ( $schema, $watchFor->{$watchItem}->{'id'}, $season, $episode ) >= 1 ) {
                                    $log->INFO("Episode has allready been registered, won't do anything with this." );
                                    next;
                                }
                                else {
                                    update_smart_ep_filter ( $schema, $watchFor->{$watchItem}->{'id'}, $season, $episode );
                                }
                            }
                        }
                        else {
                            printf "Couldn't reliably determine Season and/or Episode, sorry!\n";
                            next
                        }
    
                        update_last_seen ( $schema, $watchFor->{$watchItem}->{'id'} );
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
            $log->INFO( "Matched 'not' keyword " . $not . "." );
            
            $fail = 1;
            last;
        }
    }
    
    undef ( @notKeywords );
    
    return $fail;
}

sub _hasKeywords {
    my ( $item, $keywords ) = @_;
    my $fail = 1;
    
    my @hasKeywords = split ( /,/, $keywords );
                        
    foreach my $has ( @hasKeywords ) {
        unless ( $item =~ m/$has/ ) {
            $log->INFO( "Matched 'has' keyword " . $has . "." );
            
            $fail = 0;
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

    my $exists = $schema->resultset('SmartEpFilter')->search({
            'watchid'  => $id,
            'season'    => $season,
            'episode'   => $episode_number
        } )->count;
    
    return $exists;    
}

sub update_smart_ep_filter {
    my ( $schema, $id, $season, $episode_number ) = @_;
    
    $schema->resultset("SmartEpFilter")->create( {
        'watchid'  => $id,
        'season'    => $season,
        'episode'   => $episode_number
    } );
    
    $log->INFO("Added Episode to Smart EP Filter.")
}

sub get_rss_urls {
    my $schema  = shift;
    my $urls    = ();
    
    $log->INFO( "Getting RSS Feed Urls..." );
    
    my @results = $schema->resultset('Feeds')->all;
    
    foreach my $result ( @results ) {
        next if $result->enabled != 1;
        
        $urls->{$result->name} = {
            'id'        => $result->id,
            'url'       => $result->url,
            'enabled'   => $result->enabled,
        };
        
        $log->INFO ( "Added Feed URL " . $result->name );
    }
    
    return $urls;
    
}

sub update_last_seen {
    my ( $schema, $id ) = @_;
    
    my $result = $schema->resultset("Watch")->search(
        { 'id' => $id }
    );
    
    $result->update({ lastseen => \'NOW()' });
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
            'smartepfilter'   => $result->smartepfilter
        };
        
        $log->INFO ( "Added Watch Rule for " . $result->name );
    }
    
    return $rules;
    
}

sub set_torrent_history {
    my ( $schema, $detail ) = @_;
    
    $schema->resultset("Torrents")->create( $detail );
}

sub get_torrent_history {
    my ( $schema, $title ) = @_;
    
    my $exists = $schema->resultset("Torrents")->search( {
        'title' => $title } )->count;
    
    return $exists;
}