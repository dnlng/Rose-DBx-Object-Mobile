package Rose::DBx::Object::Mobile;
use strict;
use warnings;
no warnings 'uninitialized';
use Exporter 'import';

use base qw(Rose::Object);
our @EXPORT_OK = qw(config load mobile_form mobile_listview);
our %EXPORT_TAGS = (object => [qw(mobile_form)], manager => [qw(mobile_listview mobile_pager)]);

use JQuery::Mobile;
use Rose::DB::Object::Helpers ();
use File::Copy::Recursive ();
use Lingua::EN::Inflect ();
use Scalar::Util ();
use File::Path;
use Clone qw(clone);
use HTML::FillInForm;

our $VERSION = 0.01;
# 27.3

sub load {
	my ($self, $args) = @_;

	no strict 'refs';
	foreach my $class (@{$args}) {
		my $class_type;
	
		if (($class)->isa('Rose::DB::Object')) {
			$class_type = 'object';
		}
		else {
			$class_type = 'manager';
		}
		
		foreach my $sub (@{$EXPORT_TAGS{$class_type}}) {
			unless ($class->can($sub)) {
				my $package_sub = $class . '::' . $sub;
				*$package_sub = \&$sub;
			}
		}
	}
	
	return 1;
}

sub mobile_pager {
	my ($self, %args) = @_;
	_before($self, \%args) if exists $args{before};

	return unless $args{get} && defined $args{get}->{per_page};
	
	$args{get}->{page} ||= 1;

	my ($previous_page, $next_page, $last_page, $total) = _pagination($self, $args{get});

	my $controlgroup = $args{controlgroup};

	$controlgroup->{type} = 'horizontal' unless exists $controlgroup->{type};

	my $jquery_mobile = ref $args{jquery_mobile} eq 'OBJECT'? $args{jquery_mobile} : JQuery::Mobile->new(%{$args{jquery_mobile}});
	
	unless (defined $controlgroup->{content}) {

		my $path = $args{path} || '/';
		my $query_string = $args{query_string} || '';

		$query_string = '?' . $query_string if $query_string && ! $query_string =~ /^?/;

		my $prev = $args{prev};
		$prev->{href} ||= $path . $previous_page . $query_string;
		$prev->{value} ||= 'Prev';

		if ($previous_page == $args{get}->{page}) {
			$prev->{class} .= ' ui-disabled';
		}
		my $prev_button = $jquery_mobile->button(%{$prev});

		my $next = $args{next};
		$next->{href} ||= $path . $next_page . $query_string;
		$next->{value} ||= 'Next';
		if ($next_page == $args{get}->{page}) {
			$next->{class} .= ' ui-disabled';
		}
		my $next_button = $jquery_mobile->button(%{$next});

		my $page_buttons = '';
		if ($args{display}) {
			my ($min, $max) = _pager_bound($args{get}->{page}, $last_page, $args{display});
			my $count = $min;
			while ($count <= $max) {
				my $page = clone ($args{page});
				$page->{href} = $path . $count . $query_string;
				$page->{value} = $count;
				$page->{class} = ' ui-btn-active' if $count == $args{get}->{page};
				$page_buttons .= $jquery_mobile->button(%{$page});

				$count++;
			}
		}

		$controlgroup->{content} = $prev_button . $page_buttons .  $next_button;
	}
		
	my $output = $jquery_mobile->controlgroup(%{$controlgroup});
	return $output;
}

sub mobile_listview {
	my ($self, %args) = @_;
	_before($self, \%args) if exists $args{before};

	my $class = $self->object_class();
	$args{like_operator} ||= ($class->meta->db->driver eq 'pg'?'ilike':'like');

	my $title_column = $args{title};
	my $count_column = $args{count};
	my $image_column = $args{image};
	my $value_column = $args{value};
	my $aside_column = $args{aside};
	my $href_column = $args{href};
	my $divider_column = $args{divider};

	my $split_column = $args{split};
	my $split_value_or_column = $args{split_value};


	$title_column ||= 'stringify_me' if $class->can('stringify_me');
	$count_column ||= 'count' if $class->can('count');
	$image_column ||= 'image' if $class->can('image');
	$value_column ||= 'description' if $class->can('description');

	my $active = $args{active};

	my $listview = $args{listview};
	my $item_data = $args{item_data};

	if ($args{pager} && $args{query} && $args{get}->{per_page}) {
		$args{get}->{page} ||= $args{query}->param('page') || 1;
	}

	my $objects = $self->get_objects(%{$args{get}});
	return unless $objects && @{$objects};

	my $divider = '';
	
	foreach my $object (@{$objects}) {
		if ($divider_column) {
			my $current_divider = $object->$divider_column;
			if ($divider ne $current_divider) {
				$divider = $current_divider;
				push @{$listview->{items}}, {value => $divider, divider => 1};
			}
		}

		my $item = {};
		$item = clone($item_data) if $item_data && ref $item_data eq 'HASH';

		if ($active) {
			my $active_column = $active->{column};
			$item->{active} = 1 if $object->$active_column eq $active->{value};
		}

		$item->{title} = $object->$title_column if $title_column;
		$item->{count} = $object->$count_column if $count_column;
		$item->{image} = $object->$image_column if $image_column;
		$item->{value} = $object->$value_column if $value_column;
		$item->{aside} = $object->$aside_column if $aside_column;
		$item->{href} = $object->$href_column if $href_column;

		if ($split_column) {
			$item->{split} = $object->$split_column;
			if ($split_value_or_column) {
				if ($object->can($split_value_or_column)) {
					$item->{split_value} = $object->$split_value_or_column;
				}
				else {
					$item->{split_value} = $split_value_or_column;
				}
			}
		}

		push @{$listview->{items}}, $item;
	}

	my $jquery_mobile = ref $args{jquery_mobile} eq 'OBJECT'? $args{jquery_mobile} : JQuery::Mobile->new(%{$args{jquery_mobile}});
	my $output = $jquery_mobile->listview(%{$listview});

	if ($args{pager} && exists $args{get} && defined $args{get}->{per_page}) {
		my $pager_config = ref $args{pager} eq 'HASH'? $args{pager} : {};
		$pager_config->{get} ||= $args{get};

		my $pager = $self->mobile_pager(%{$pager_config});
		$output .= $pager;
	}

	return $output;
}

sub mobile_form {
	my ($self, %args) = @_;
	_before($self, \%args) if exists $args{before};

	# DB table info
	my $table = $self->meta->table;
	my $class = ref $self || $self;
	my $foreign_keys = _get_foreign_keys($class);
	my $relationships = _get_relationships($class);
	my $column_order = $args{order} || _get_column_order($class, $relationships);

	# init form
	my $form = _init_form($self, \%args, $table, $class);
	my $regex_var = _regex_var();
	my ($relationship_object, $field_order, $has_files, $error);

	my $submit = $args{query}->param('_submit');
	if ($submit) {
		$form->{validate} = 1 unless defined $form->{validate} && ! $form->{validate};
	}

	foreach my $query_key (keys %{$args{queries}}) {
		push @{$form->{fields}}, {name => $query_key, value => $args{queries}->{$query_key}, type => 'hidden'};
	}

	foreach my $column (@{$column_order}) {
		my $field_def = _process_columns($self, \%args, $form, $column, $class, $regex_var, $foreign_keys, $relationships, $relationship_object, $field_order);
		$has_files++ if ($field_def->{type} eq 'file');

		if ($form->{validate}) {

			if ($field_def->{multiple}) {

				my @values = $args{query}->param($column);

				if ($field_def->{required}) {
					if (! scalar @values) {
						$field_def->{invalid} = 1;
						$error++;
					}
					else {
						if ($field_def->{validate} && ref $field_def->{validate} eq 'CODE') {
							unless ($field_def->{validate}->(\@values, $form)) {
								$field_def->{invalid} = 1;
								$error++;
							}
						}
						elsif ($field_def->{pattern}) {
							foreach my $value (@values) {
								unless ($value =~ /$field_def->{pattern}/) {
									$field_def->{invalid} = 1;
									$error++;
									last;
								}
							}
						}
					}
				}
				elsif (scalar @values && $field_def->{pattern}) {
					foreach my $value (@values) {
						unless ($value =~ /$field_def->{pattern}/) {
							$field_def->{invalid} = 1;
							$error++;
							last;
						}
					}
				}
			}
			else {
				my $value = $args{query}->param($column);


				if ($field_def->{required}) {
					if (! length($value)) {
						$field_def->{invalid} = 1;
						$error++;
					}
					elsif ($field_def->{validate} && ref $field_def->{validate} eq 'CODE') {
						unless ($field_def->{validate}->($value, $form)) {
							$field_def->{invalid} = 1;
							$error++;
						}
					}
					elsif ($field_def->{pattern}) {
						unless ($value =~ /$field_def->{pattern}/) {
							$field_def->{invalid} = 1;
							$error++;	
						}
						
					}
				}
				elsif (length($value) && $field_def->{pattern}) {
					unless ($value =~ /$field_def->{pattern}/) {
						$field_def->{invalid} = 1;
						$error++;	
					}
					
				}
			}
		}

		push @{$form->{fields}}, $field_def;
	}

	if ($has_files) {
		$form->{enctype} ||= 'multipart/form-data';
		$form->{ajax} = 'false' if $form->{enctype} eq 'multipart/form-data';
	}

	$form->{buttons} ||= $args{buttons};

	unless ($form->{buttons}) {
		push @{$form->{buttons}}, {id => '_submit', name=> '_submit', type=> 'submit', value => ucfirst($form->{button_action})};
	}

	if ($submit  && ! $error) {
		no strict 'refs';
		my $form_action_callback = '_' . $form->{button_action} . '_object';
		
		if (exists $args{controllers}->{$submit}) {

			# method buttons
			if (ref $args{controllers}->{$submit} eq 'HASH') {
				if ($args{controllers}->{$submit}->{$form->{button_action}}) {
					unless (ref $args{controllers}->{$submit}->{$form->{button_action}} eq 'CODE' && ! $args{controllers}->{$submit}->{$form->{button_action}}->($self)) {
						$self = $form_action_callback->($self, $class, $table, $column_order, $form, $relationships, $relationship_object, \%args);
					}
				}
				$args{controllers}->{$submit}->{callback}->($self) if ref $args{controllers}->{$submit}->{callback} eq 'CODE';

			}
			else {
				$args{controllers}->{$submit}->($self) if ref $args{controllers}->{$submit} eq 'CODE';
			}
		}
		elsif($submit eq ucfirst ($form->{button_action})) {
			$self = $form_action_callback->($self, $class, $table, $column_order, $form, $relationships, $relationship_object, \%args);
		}
	}

	my $jquery_mobile = ref $args{jquery_mobile} eq 'OBJECT'? $args{jquery_mobile} : JQuery::Mobile->new(%{$args{jquery_mobile}});
	my $output = $jquery_mobile->form(%{$form});
	$output = HTML::FillInForm->fill(\$output, $args{query}, %{$args{fill_form}});
	return $output;
}

sub _regex_var {
	return {
		INT => '^-?\s*[0-9]+$',
		NUM => '^-?\s*[0-9]+\.?[0-9]*$|^-?\s*\.[0-9]+$',
		FNAME => '^[a-zA-Z]+[- ]?[a-zA-Z]*$',
		LNAME => '^[a-zA-Z]+[- ]?[a-zA-Z]+\s*,?([a-zA-Z]+|[a-zA-Z]+\.)?$',
		EMAIL => '^[\w\-\+\._]+\@[a-zA-Z0-9][-a-zA-Z0-9\.]*\.[a-zA-Z]+$',
		FLOAT => '^-?\s*[0-9]+\.[0-9]+$',
	};
}

sub _init_form {
	my ($self, $args, $table, $class) = @_;

	my $form = $args->{form};
	$form->{description} ||= $args->{description};
	$form->{delimiter} ||= ',';
	$form->{method} ||= 'post';
	$form->{title} = $args->{title};

	if (ref $self) {
		my $primary_key = $class->meta->primary_key_column_names->[0];
		if ($args->{copy}) {
			$form->{button_action} = 'copy';
		}
		else {
			$form->{button_action} = 'update';
		}

		$args->{queries}->{object} ||= $self->$primary_key;
		$form->{title} ||= $self->can('stringify_me') ? _label($form->{button_action} . ' ' . $self->stringify_me()) : _label($form->{button_action} . ' ' . _singularise_table(_title($table, $args->{table_prefix}), $args->{tables_are_singular}));
		$form->{object} = $self->$primary_key;

	}
	else {
		$form->{button_action} = 'create';
		$form->{title} ||= _label($form->{button_action} . ' ' . _singularise_table(_title($table, $args->{table_prefix}), $args->{tables_are_singular}));
	}

	return $form;
}

sub _process_columns {
	my ($self, $args, $form, $column, $class, $regex_var, $foreign_keys, $relationships, $relationship_object, $field_order) = @_;

	my $field_def;
	$field_def = $args->{fields}->{$column} if exists $args->{fields} && exists $args->{fields}->{$column};

	my $column_definition_method = $column . '_definition';

	if ($class->can($column_definition_method)) {
		my $column_definition = $class->$column_definition_method;

		foreach my $property (keys %{$column_definition}) {
			if ($property eq 'required') {
				if (exists $field_def->{'required'}) {
					delete $field_def->{'required'} if ! $field_def->{'required'};
				}
				else {
					$field_def->{'required'} = 'required' if ($column_definition->{$property});	
				}
			}
			elsif ($property eq 'validate') {

				next if exists $field_def->{'pattern'};
				my $validate = $field_def->{$property} || $column_definition->{$property};

				if (! ref $validate) {
					if (exists $regex_var->{$validate}) {
						$field_def->{'pattern'} = $regex_var->{$validate};
					}
					else {
						($field_def->{'pattern'}) = ($validate =~ /^\/(.*)\/$/);
					}
				}
				else {
					if (ref $validate eq 'CODE') {
						$field_def->{'validate'} = $validate;
					}
					elsif (ref $validate eq 'HASH') {
						if (exists $validate->{javascript} && $validate->{javascript} =~ /^\/.*\/$/) {
							# looks like a regex
							($field_def->{'pattern'}) = ($validate->{javascript} =~ /^\/(.*)\/$/);
						}

						if (exists $validate->{perl} && ref $validate->{perl} eq 'CODE') {
							$field_def->{'validate'} = $validate->{perl};
						}
					}
					elsif (ref $validate eq 'ARRAY') {
						$field_def->{'pattern'} = '^(' . join ('|', @{$validate}) . ')$';
					}
				}
			}
			else {
				$field_def->{$property} = $column_definition->{$property} unless defined $field_def->{$property} || $property =~ /^(format|stringify|unsortable|sortopts|cleanopts|jsmessage|comment)$/;
			}
		}
	}
	
	if (exists $relationships->{$column}) {
		# one to many or many to many relationships
		$field_def->{multiple} ||= 1;

		my $foreign_class_primary_key = $relationships->{$column}->{class}->meta->primary_key_column_names->[0];

		if (ref $self && ! exists $field_def->{value}) {
			my $foreign_object_value;

		 	foreach my $foreign_object ($self->$column) {

				$foreign_object_value->{$foreign_object->$foreign_class_primary_key} = $foreign_object->can('stringify_me') ? $foreign_object->stringify_me() : $foreign_object->$foreign_class_primary_key;

				$relationship_object->{$column}->{$foreign_object->$foreign_class_primary_key} = undef; # keep it for update
			}
			$field_def->{value} = $foreign_object_value;
		}

		my $objects = Rose::DB::Object::Manager->get_objects(object_class => $relationships->{$column}->{class});
		if (@{$objects}) {
			foreach my $object (@{$objects}) {
				$field_def->{options}->{$object->$foreign_class_primary_key} = $object->can('stringify_me') ? $object->stringify_me() : $object->$foreign_class_primary_key;
			}
		}
		else {
			$field_def->{type} ||= 'select';
			$field_def->{disabled} ||= 1;
		}

	}
	elsif (exists $class->meta->{columns}->{$column}) {

		# normal column
		$field_def->{required} = 'required' if ! defined $field_def->{required} && $class->meta->{columns}->{$column}->{not_null};
		
		unless (exists $field_def->{options} || (defined $field_def->{type} && $field_def->{type} eq 'hidden')) {
			if (exists $foreign_keys->{$column}) {
				# create or edit
				my $foreign_class = $foreign_keys->{$column}->{class};
				my $foreign_class_primary_key = $foreign_class->meta->primary_key_column_names->[0];

				my $objects = Rose::DB::Object::Manager->get_objects(object_class => $foreign_keys->{$column}->{class});
				if (@{$objects}) {
					foreach my $object (@{$objects}) {
						$field_def->{options}->{$object->$foreign_class_primary_key} = $object->can('stringify_me') ? $object->stringify_me() : $object->$foreign_class_primary_key;
					}
				}
				else {
					$field_def->{type} ||= 'select';
					$field_def->{disabled} ||= 1;
				}

			}
			elsif (exists $class->meta->{columns}->{$column}->{check_in}) {
				$field_def->{options} = $class->meta->{columns}->{$column}->{check_in};
				if (! exists $field_def->{multiple} && ref $class->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set') {
					$field_def->{multiple} = 1;	
					$field_def->{type} ||= 'select';
				}
				
			}
			elsif (! exists $field_def->{type} && ref $class->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Text') {
				$field_def->{type} = 'textarea';
				$field_def->{cols} ||= '55';
				$field_def->{rows} ||= '10';
			}
		}

		if (ref $self) {
			# edit
			unless (exists $field_def->{value}) {

				my $current_value;
				if ($class->can($column . '_for_edit')) {
					my $edit_method = $column . '_for_edit';
					$current_value = $self->$edit_method;
					if (ref $current_value eq 'ARRAY' || ref $current_value eq 'HASH') {
						$field_def->{value} = $current_value;
					}
					else {
						$field_def->{value} = "$current_value"; # make object stringifies
					}
				}
				else {
					if (ref $self->meta->{columns}->{$column} eq 'Rose::DB::Object::Metadata::Column::Set') {
						$field_def->{value} = $self->$column;
					}
					elsif (exists $field_def->{multiple} && $field_def->{multiple} && $field_def->{options}) {
						my $delimiter = '\\' . $form->{delimiter};
						$field_def->{value} = [split /$delimiter/, $self->$column];
					}
					else {
						$current_value = $self->$column;
						$field_def->{value} = "$current_value"; # double quote to make it literal to stringify object refs such as DateTime
					}
				}
			}

			if ($field_def->{type} eq 'file') {
				delete $field_def->{value};
			}
		}
		else {
			unless (exists $field_def->{value}) {
				if ($class->can($column . '_for_create')) {
					my $create_method = $column.'_for_create';
					my $create_result = $self->$create_method($self->meta->{columns}->{$column}->{default});
					$field_def->{value} = $create_result if defined $create_result;
				}
				else {
					$field_def->{value} = $self->meta->{columns}->{$column}->{default} if defined $self->meta->{columns}->{$column}->{default};
				}
			}
		}
	}

	if (! $field_def->{type} && $field_def->{options}) {

		my $field_option_size = 0;
		if (ref $field_def->{options} eq 'HASH') {
			$field_option_size = scalar keys %{$field_def->{options}};
		}
		elsif (ref $field_def->{options} eq 'ARRAY') {
			$field_option_size = scalar @{$field_def->{options}};
		}

		if ($field_option_size > 5) {
			$field_def->{type} = 'select';
		}
		elsif (exists $field_def->{multiple} && $field_def->{multiple}) {
			$field_def->{type} = 'checkbox';	
		}
		else {
			$field_def->{type} = 'radio';
		}
	}

	# delete $field_def->{multiple} if $field_def->{multiple} && $field_def->{type} ne 'select';

	$field_def->{label} ||= _label(_title($column, $args->{table_prefix}));

	unless (exists $field_def->{name}) {
		push @{$field_order}, $column;
		$field_def->{name} = $column;
	}

	return $field_def;
}

sub _create_object {
	my ($self, $class, $table, $field_order, $form, $relationships, $relationship_object, $args) = @_;
	my $custom_field_value;
	$self = $self->new();

	foreach my $column (@{$field_order}) {
		if(defined $args->{query}->param($column) && length($args->{query}->param($column))) {
			my @values = $args->{query}->param($column);
			 # one to many or many to many
			if (exists $relationships->{$column}) {
				my $new_foreign_object_id_hash;
				my $foreign_class_primary_key = $relationships->{$column}->{class}->meta->primary_key_column_names->[0];

				foreach my $id (@values) {
					push @{$new_foreign_object_id_hash}, {$foreign_class_primary_key => $id};
				}

				$self->$column(@{$new_foreign_object_id_hash});
			}
			else {
				my $field_value;
				my $values_size = scalar @values;
				if($values_size > 1) {
					$field_value = join $form->{delimiter}, @values;
				}
				else {
					$field_value = $args->{query}->param($column); # if this line is removed, function will still think it should return an array, which will fail for file upload
				}

				if ($class->can($column . '_for_update')) {
					$custom_field_value->{$column . '_for_update'} = $field_value; # save it for later
					$self->$column('0') if $self->meta->{columns}->{$column}->{not_null}; # zero fill not null columns
				}
				elsif ($class->can($column)) {
					$self->$column($field_value);
				}
			}
		}
	}

	$self->save;

	# after save, run formatting methods, which may require an id, such as file upload
	if ($custom_field_value) {
		foreach my $update_method (keys %{$custom_field_value}) {
			$self->$update_method($custom_field_value->{$update_method});
		}
		$self->save;
	}

	return $self;
}

sub _update_object {
	my ($self, $class, $table, $field_order, $form, $relationships, $relationship_object, $args) = @_;
	my $primary_key = $self->meta->primary_key_column_names->[0];

	foreach my $column (@{$field_order}) {
		my @values = $args->{query}->param($column);
		my $values_size = scalar @values;
		my $field_value;
		if($values_size > 1) {
			$field_value = join $form->{delimiter}, @values;
		}
		else {
			$field_value = $args->{query}->param($column); # if this line is removed, CGI will still think it should return an array, which will fail for file upload
		}

		if (exists $relationships->{$column}) {
			my $foreign_class = $relationships->{$column}->{class};
			my $foreign_class_foreign_keys = _get_foreign_keys($foreign_class);
			my $foreign_key;

			foreach my $fk (keys %{$foreign_class_foreign_keys}) {
				if ($foreign_class_foreign_keys->{$fk}->{class} eq $class) {
					$foreign_key = $fk;
					last;
				}
			}

			my $default = undef;
			$default = $relationships->{$column}->{class}->meta->{columns}->{$table.'_id'}->{default} if defined $relationships->{$column}->{class}->meta->{columns}->{$table.'_id'}->{default};

			if(length($args->{query}->param($column))) {
				my ($new_foreign_object_id, $old_foreign_object_id, $value_hash, $new_foreign_object_id_hash);
				my $foreign_class_primary_key = $relationships->{$column}->{class}->meta->primary_key_column_names->[0];

				foreach my $id (@values) {
					push @{$new_foreign_object_id}, $foreign_class_primary_key => $id;
					$value_hash->{$id} = undef;
					push @{$new_foreign_object_id_hash}, {$foreign_class_primary_key => $id};
				}

				foreach my $id (keys %{$relationship_object->{$column}}) {
					push @{$old_foreign_object_id}, $foreign_class_primary_key => $id unless exists $value_hash->{$id};
				}

				if ($relationships->{$column}->{type} eq 'one to many') {
					Rose::DB::Object::Manager->update_objects(object_class => $foreign_class, set => {$foreign_key => $default}, where => [or => $old_foreign_object_id]) if $old_foreign_object_id;
					Rose::DB::Object::Manager->update_objects(object_class => $foreign_class, set => {$foreign_key => $self->$primary_key}, where => [or => $new_foreign_object_id]) if $new_foreign_object_id;
				}
				else {
					 # many to many
					$self->$column(@{$new_foreign_object_id_hash});
				}
			}
			else {
				if ($relationships->{$column}->{type} eq 'one to many') {
					Rose::DB::Object::Manager->update_objects(object_class => $foreign_class, set => {$foreign_key => $default}, where => [$foreign_key => $self->$primary_key]);
				}
				else {
					# many to many
					$self->$column([]); # cascade deletes foreign objects
				}
			}
		}
		else {
			my $update_method;
			if ($class->can($column . '_for_update')) {
				$update_method = $column . '_for_update';
			}
			elsif ($class->can($column)) {
				$update_method = $column;
			}

			if ($update_method) {
				if (length($args->{query}->param($column))) {
					$self->$update_method($field_value);
				}
				else {
					$self->$update_method(undef);
				}
			}
		}
	}
	
	$self->save;
	return $self;
}


sub _copy_object {
	my ($self, $class, $table, $field_order, $form, $relationships, $relationship_object, $args) = @_;
	my $clone = Rose::DB::Object::Helpers::clone_and_reset($self);
	# fix here: insert placeholder for not null columns, below need test
	foreach my $column (@{$field_order}) {
		next if exists $relationships->{$column};
		if ($class->can($column . '_for_update')) {
			$self->$column('0') if $self->meta->{columns}->{$column}->{not_null}; # zero fill not null columns
		}
	}

	$clone->save(); # need the auto generated primary key for files;

	if ($self->can('renderer_config')) {
		my $renderer_config = $self->renderer_config();
		my $primary_key = $self->meta->primary_key_column_names->[0];
		my $self_upload_path = File::Spec->catdir($renderer_config->{upload}->{path}, $self->stringify_class, $self->$primary_key);
		File::Copy::Recursive::dircopy($self_upload_path, File::Spec->catdir($renderer_config->{upload}->{path}, $self->stringify_class, $clone->$primary_key)) if -d $self_upload_path;
	}

	return _update_object($clone, $class, $table, $field_order, $form, $relationships, $relationship_object, $args);
}

# util

sub _before {
	my ($self, $weak_args) = @_;
	my $before = delete $weak_args->{before};
	Scalar::Util::weaken($weak_args);
	return $before->($self, $weak_args);
}

sub _singularise_table {
	my ($table, $tables_are_singular) = @_;
	return $table if $tables_are_singular;
	return _singularise($table);
}

sub _pluralise_table {
	my ($table, $tables_are_singular) = @_;
	return Lingua::EN::Inflect::PL($table) if $tables_are_singular;
	return $table;
}

sub _singularise {
	my $word = shift;
	$word =~ s/ies$/y/ix;
	return $word if ($word =~ s/ses$/s/x);
	return $word if($word =~ /[aeiouy]ss$/ix);
	$word =~ s/s$//ix;
	return $word;
}

sub _title {
	my ($table_name, $prefix) = @_;
	return $table_name unless $prefix;
	$table_name =~ s/^$prefix//x;
	return $table_name;
}

sub _label {
	my $string = shift;
	$string =~ s/_/ /g;
	$string =~ s/\b(\w)/\u$1/gx;
	return $string;
}

sub _get_column_order {
	my ($class, $relationships) = @_;
	my $order;
	foreach my $column (sort {$a->ordinal_position <=> $b->ordinal_position} @{$class->meta->columns}) {
		push @{$order}, "$column" unless exists $column->{is_primary_key_member};
	}

	foreach my $relationship (keys %{$relationships}) {
		push @{$order}, $relationship;
	}
	return $order;
}

sub _get_foreign_keys {
	my $class = shift;
	my $foreign_keys;
	foreach my $foreign_key (@{$class->meta->foreign_keys}) {
		(my $key, my $value) = $foreign_key->_key_columns;
		$foreign_keys->{$key} = {name => $foreign_key->name, table => $foreign_key->class->meta->table, column => $value, is_required => $foreign_key->is_required, class => $foreign_key->class};
	}
	return $foreign_keys;
}

sub _get_unique_keys {
	my $class = shift;
	my $unique_keys;
	foreach my $unique_key (@{$class->meta->{unique_keys}}) {
		$unique_keys->{$unique_key->columns->[0]} = undef;
	}
	return $unique_keys;
}

sub _get_relationships {
	my $class = shift;
	my $relationships;

	foreach my $relationship (@{$class->meta->relationships}) {
		if ($relationship->type eq 'one to many') {
			$relationships->{$relationship->name}->{type} = $relationship->type;
			$relationships->{$relationship->name}->{class} = $relationship->class;
		}
		elsif($relationship->type eq 'many to many') {
			$relationships->{$relationship->name}->{type} = $relationship->type;
			$relationships->{$relationship->name}->{class} = $relationship->foreign_class;
		}
	}
	return $relationships;
}

sub _pager_bound {
	my ($page, $last_page, $display) = @_;

	if ($display >= $last_page) {
		$display = $last_page;
	}
	
	my $side = int (($display - 1) / 2); # even each side

	my $min = $page - $side;
	my $max = $page + $side;

	if ($min < 1) {
		$max = $display;
		$min = 1;
	}
	elsif ($max > $last_page) {
		$max = $last_page;
		$min = $last_page - $display + 1;	
	}

	return ($min, $max);
}

sub _pagination {
	my ($self, $get) = @_;
	my $total = $self->get_objects_count(%{$get});
	return (1, 1, 1, $total) unless $get->{per_page} && $get->{page};
	my ($last_page, $next_page, $previous_page);
	if ($total < $get->{per_page}) {
		$last_page = 1;
	}
	else {
		my $pages = $total / $get->{per_page};
		if ($pages == int $pages) {
			$last_page = $pages;
		}
		else {
			$last_page = 1 + int($pages);
		}
	}

	if ($get->{page} == $last_page) {
		$next_page = $last_page;
	}
	else {
		$next_page = $get->{page} + 1;
	}

	if ($get->{page} == 1) {
		$previous_page = 1;
	}
	else {
		$previous_page = $get->{page} - 1;
	}

	return ($previous_page, $next_page, $last_page, $total);
}

1;

__END__

=head1 NAME

Rose::DBx::Object::Mobile - jQuery Mobile UI Generation for Rose::DB::Object

=head1 SYNOPSIS
  
  # in Rose::DB::Object object class
  package Company::Employee
  use Rose::DBx::Object::Mobile qw(:object);
  ...
   
  # in Rose::DB::Object manager class
  package Company::Employee::Manager
  use Rose::DBx::Object::Mobile qw(:manager);
  ...

  
  # in application
  # render a listview
  print Company::Employee::Manager->mobile_listview(
    title => 'first_name', # use the 'first_name' column of the Company::Employee class as the item 'title'
    value => 'summary', # use the 'summary' column of the Company::Employee class as the item 'value'
  );

  # create a new Employee record
  print Company::Employee->mobile_form(
    query => $self->query, # a query object that has param() method
    form => {action => '/self-url'},
    order => [qw(title first_name last_name email password summary)], # column order
    buttons => [
      {name=> '_submit', type=>'submit', theme => 'e', icon => 'arrow-r', iconpos => 'right', value => 'Save'}, # submit button
    ],
    controllers => {
      'Save' => {
        create => 1, # save the record
        callback => sub {
          my $object = shift;
          return $self->redirect('/self-url?created=1'); # 
        }
      }
    }
  );

=head1 DESCRIPTION

Rose::DBx::Object::Mobile renders jQuery Mobile listviews and forms for L<Rose::DB::Object>. It relies on L<JQuery::Mobile> for the actual UI generation.

=head1 METHODS

=head2 C<new>

C<new()> instantiates a new C<Rose::DBx::Object::Mobile> object.
C<new()> is for importing mobile_form() and mobile_listview() into existing Rose::DB::Object classes dynamically:

  my $mobile = Rose::DBx::Object::Mobile->new(load => ['Company::Employee', 'Company::Employee::Manager']);

=head2 C<load>

Since C<Rose::DBx::Object::Mobile> inherits from L<Rose::Object>, the above line is equivalent to:

  my $mobile = Rose::DBx::Object::Mobile->new();
  $mobile->load(['Company::Employee', 'Company::Employee::Manager']);


=cut