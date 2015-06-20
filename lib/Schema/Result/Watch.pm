package Schema::Result::Watch;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);
__PACKAGE__->table('rss_watch');
__PACKAGE__->add_columns(qw/id name has not smart_ep_filter last_seen/);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->has_many(smart_ep_filter => 'Schema::Result::SmartEpFilter', 'watch_id');

1;