package Schema::Result::Torrents;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);
__PACKAGE__->table('rss_torrents');
__PACKAGE__->add_columns(qw/id title url category added rid/);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->belongs_to(rss_feed_urls => 'Schema::Result::Feeds', 'id');

1;