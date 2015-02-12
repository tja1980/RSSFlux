package Schema::Result::Feeds;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('rss_feed_urls');
__PACKAGE__->add_columns(qw/id name url description enabled/);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->has_many(cds => 'Schema::Result::Torrents', 'rid');

1;