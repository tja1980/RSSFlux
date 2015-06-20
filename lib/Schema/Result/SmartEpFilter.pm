package Schema::Result::SmartEpFilter;
use base qw/DBIx::Class::Core/;

__PACKAGE__->load_components(qw/InflateColumn::DateTime/);
__PACKAGE__->table('smart_ep_filter');
__PACKAGE__->add_columns(qw/id season episode watchid added/);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->belongs_to(rss_watch => 'Schema::Result::Watch', 'id');

1;