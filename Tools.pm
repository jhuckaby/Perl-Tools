package Tools;

# Copyright (c) 2005 - 2011 Joseph Huckaby
# Source Code released under the MIT License: 
# http://www.opensource.org/licenses/mit-license.php

##
# Misc. utility functions.
##

use strict;
use Config;
use Digest::MD5 qw(md5_hex);
use FileHandle;
use File::Basename;
use Cwd qw/cwd abs_path/;
use DirHandle;
use Time::HiRes qw/time/;
use Time::Local;
use LWP::UserAgent;
use HTTP::Request;
use UNIVERSAL qw(isa);
use URI::Escape;
use Data::Dumper;
use XML::Lite;

BEGIN
{
    use Exporter   ();
    use vars qw(@ISA @EXPORT @EXPORT_OK);

    @ISA		= qw(Exporter);
    @EXPORT		= qw(load_file save_file get_hostname get_bytes_from_text get_text_from_bytes merge_hashes
                     short_float file_copy generate_unique_id memory_substitute memory_lookup escape_js
                     get_network_interfaces wget xml_to_javascript file_move xpath_lookup xpath_set_simple
 					 find_files normalize_midnight follow_symlinks get_remote_ip get_user_agent strip_high
					 XMLsearch XMLindexby XMLalwaysarray make_dirs_for get_args parse_xml compose_xml
					 get_client_info import_param parse_query compose_query parse_cookies touch 
					 get_seconds_from_text get_text_from_seconds probably rand_array find_elem_idx 
					 remove_from_array remove_all_from_array dumper deep_copy yyyy serialize_object
					 copy_hash_remove_keys trim yyyy_mm_dd get_nice_date nslookup commify pct find_object
					 parse_xml_collapse xpath_summary strip_html get_request_url);
	@EXPORT_OK	= qw();
}

my $months = [
	'January', 'February', 'March', 'April', 'May', 'June', 
	'July', 'August', 'September', 'October', 'November', 'December'
];

sub load_file {
	##
	# Load file contents
	##
	my $file = shift;
	my $contents = undef;

	my $fh = new FileHandle "<$file";
	if (defined($fh)) {
		$fh->read( $contents, (stat($fh))[7] );
		$fh->close();
	}
	
	##
	# Return contents of file as scalar.
	##
	return $contents;
}

sub save_file {
	##
	# Save file contents
	##
	my ($file, $contents) = @_;

	my $fh = new FileHandle ">$file";
	if (defined($fh)) {
		$fh->print( $contents );
		$fh->close();
		return 1;
	}
	
	return 0;
}

sub get_hostname {
	##
	# Get machine's hostname
	##
	my $hostname;
	
	if ($ENV{'HOST'} || $ENV{'HOSTNAME'}) {
		$hostname = $ENV{'HOST'} || $ENV{'HOSTNAME'};
	} elsif (defined($ENV{'SERVER_ADDR'})) {
		($hostname, undef, undef, undef, undef) = (gethostbyaddr(pack("C4", split(/\./, $ENV{'SERVER_ADDR'} || '127.0.0.1')), 2));
	} else {
		$hostname = `/bin/hostname`;
		chomp $hostname;
	}
	
	return $hostname || 'localhost';
}

sub get_bytes_from_text {
	##
	# Given text string such as '5.6 MB' or '79K', return actual byte value.
	##
	my $text = shift;
	my $bytes = $text;
	
	if ($text =~ /(\d+(\.\d+)?)\s*([A-Za-z]+)/) {
		$bytes = $1;
		my $code = $3;
		if ($code =~ /^b/i) { $bytes *= 1; }
		elsif ($code =~ /^k/i) { $bytes *= 1024; }
		elsif ($code =~ /^m/i) { $bytes *= 1024 * 1024; }
		elsif ($code =~ /^g/i) { $bytes *= 1024 * 1024 * 1024; }
		elsif ($code =~ /^t/i) { $bytes *= 1024 * 1024 * 1024 * 1024; }
	}
	
	return $bytes;
}

sub get_text_from_bytes {
	##
	# Given raw byte value, return text string such as '5.6 MB' or '79 K'
	##
	my $bytes = shift;
	
	if ($bytes < 1024) { return $bytes . ' bytes'; }
	else {
		$bytes /= 1024;
		if ($bytes < 1024) { return short_float($bytes) . ' K'; }
		else {
			$bytes /= 1024;
			if ($bytes < 1024) { return short_float($bytes) . ' MB'; }
			else {
				$bytes /= 1024;
				if ($bytes < 1024) { return short_float($bytes) . ' GB'; }
				else {
					$bytes /= 1024;
					return short_float($bytes) . ' TB';
				}
			}
		}
	}
}

sub short_float {
	##
	# Shorten floating-point decimal to 2 places, unless they are zeros.
	##
	my $f = shift;
	
	$f =~ s/^(\-?\d+\.[0]*\d{2}).*$/$1/;
	return $f;
}

sub commify {
	my $num = short_float(shift || 0); 
	while ($num =~ s/^(-?\d+)(\d{3})/$1,$2/) {} 
	return $num; 
}

sub pct {
	my ($count, $max) = @_; 
	my $pct = ($count * 100) / ($max || 1);
	if ($pct !~ /^\d+(\.\d+)?$/) { $pct = 0; }
	return short_float( $pct ) . '%';
}

sub file_copy {
	##
	# Simple file copy routine using FileHandles.
	##
	my ($source, $dest) = @_;
	my ($source_fh, $dest_fh);
	
	##
	# Accept open FileHandles or filenames as parameters
	##
	if (ref($source)) { $source_fh = $source; }
	else { $source_fh = new FileHandle "<$source"; }

	if (ref($dest)) { $dest_fh = $dest; }
	else { $dest_fh = new FileHandle ">$dest"; }
	
	if (!defined($source_fh)) { return 0; }
	if (!defined($dest_fh)) { return 0; }
	
	my ($size, $buffer, $total_size) = (0, undef, 0);
	while ($size = read($source_fh, $buffer, 32768)) {
		$dest_fh->print($buffer);
		$total_size += $size;
	}
	
	##
	# Only close FileHandles if we opened them.
	##
	if (!ref($source)) { $source_fh->close(); }
	if (!ref($dest)) { $dest_fh->close(); }
	
	return $total_size;
}

sub file_move {
	##
	# Tries rename() first, then falls back to file_copy()/unlink()
	##
	my ($source_file, $dest_file) = @_;

	if (rename($source_file, $dest_file)) { return 1; }
	else {
		if (file_copy($source_file, $dest_file)) {
			if (unlink($source_file)) { return 1; }
		}
	}
	return 0;
}

sub generate_unique_id {
	##
	# Generate MD5 hash using HiRes time, PID and random number
	##
	my $len = shift || 32;
	
	return substr(md5_hex(time() . $$ . rand(1)), 0, $len);
}

sub memory_substitute {
	##
	# Substitute inline [] tags with values from memory location,
	# looked up with virtual directory syntax
	##
	my ($content, $args) = @_;
	
	while ($content =~ m/\[([\w\/]+)\s*\]/) {
		my $param_name = $1;
		$content =~ s/\[([\w\/]+)\s*\]/ memory_lookup($param_name, $args) /e;
	} # foreach simple tag
	
	return $content;
}

sub memory_lookup {
	##
	# Walk memory tree using virtual directory syntax and return value found
	##
	my ($param_name, $param) = @_;
	
	while (($param_name =~ s/^\/?(\w+)//) && ref($param)) {
		if (isa($param, 'HASH')) { $param = $param->{$1}; }
		elsif (isa($param, 'ARRAY')) { $param = ${$param}[$1]; }
	}
	
	return $param;
}

sub xpath_lookup {
	# run simple XPath query, supporting things like:
	#		/Simple/Path/Here
	#		/ServiceList/Service[2]/@Type
	#		/Parameter[@Name='UsePU2']/@Value
	my ($xpath, $tree, $new_value) = @_;
	if (!ref($tree)) { return undef; }

	while ($xpath =~ /^\/?([^\/]+)/) {
		my $node = $1;
		if ($node =~ /^([\w\-\:]+)\[([^\]]+)\]$/) {
			# array index lookup, possibly complex attribute match
			my ($node_name, $arr_idx) = ($1, $2);
			
			if (defined($tree->[$node_name])) {
				$tree = $tree->[$node_name];
				my $elements = isa($tree, 'ARRAY') ? $tree : [ $tree ];

				if ($arr_idx =~ /^\d+$/) {
					# simple array index lookup, i.e. /Parameter[2]
					if (defined($elements->[$arr_idx])) {
						$xpath =~ s/^\/?([^\/]+)//;
						if (!$xpath && defined($new_value)) { $elements->[$arr_idx] = $new_value; }
						$tree = $elements->[$arr_idx];
					}
					else { return undef; }
				}
				elsif ($arr_idx =~ /^\@([\w\-\:]+)\=\'([^\']*)\'$/) {
					# complex attrib search query, i.e. /Parameter[@Name='UsePU2']
					my ($attrib_name, $attrib_value) = ($1, $2);
					my $count = scalar @$elements;
					my $found = 0;

					for (my $k = 0; $k < $count; $k++) {
						my $elem = $elements->[$k];
						if (defined($elem->{$attrib_name}) && ($elem->{$attrib_name} eq $attrib_value)) {
							$found = 1;
							$xpath =~ s/^\/?([^\/]+)//;
							if (!$xpath && defined($new_value)) { $elements->[$k] = $new_value; }
							$k = $count;
							$tree = $elem;
						}
						elsif (defined($elem->{'_Attribs'}) && 
								defined($elem->{'_Attribs'}->{$attrib_name}) && 
								($elem->{'_Attribs'}->{$attrib_name} eq $attrib_value)) {
							$found = 1;
							$xpath =~ s/^\/?([^\/]+)//;
							if (!$xpath && defined($new_value)) { $elements->[$k] = $new_value; }
							$k = $count;
							$tree = $elem;
						}
					} # foreach element

					if (!$found) { return undef; }
				} # attrib search
			} # found basic element name
			else {
				return undef;
			}
		} # array index lookup
		elsif ($node =~ /^\@([\w\-\:]+)$/) {
			# attrib lookup
			my $attrib_name = $1;
			if (defined($tree->{'_Attribs'})) { $tree = $tree->{'_Attribs'}; }
			if (defined($tree->{$attrib_name}) || defined($new_value)) {
				$xpath =~ s/^\/?([^\/]+)//;
				if (!$xpath && defined($new_value)) { $tree->{$attrib_name} = $new_value; }
				$tree = $tree->{$attrib_name};
			}
			else { return undef; }
		} # attrib lookup
		elsif (defined($tree->{$node}) || defined($new_value)) {
			$xpath =~ s/^\/?([^\/]+)//;
			if (!$xpath && defined($new_value)) { $tree->{$node} = $new_value; }
			elsif (defined($new_value)) { $tree->{$node} ||= {}; }
			$tree = $tree->{$node};
		} # simple element lookup
		else {
			return undef;
		} # bad xpath
	} # foreach xpath node

	return $tree;
}

sub xpath_set_simple {
	##
	# Set target node to value, simple xpath only, creates nodes as needed
	##
	my ($xpath, $xml, $value) = @_;
	
	# strip final node
	if ($xpath !~ /^\//) { $xpath = '/' . $xpath; } # force leading slash
	$xpath =~ s@/$@@; # strip trailing slash
	
	$xpath =~ s@/([^/]+)$@@; # strip final node
	my $final_node_name = $1;
	
	while ($xpath =~ s@^/([^/]+)@@) {
		my $node_name = $1;
		if (!$xml->{$node_name}) { $xml->{$node_name} = {}; }
		$xml = $xml->{$node_name};
	}
	
	$xml->{$final_node_name} = $value;
}

sub find_files {
	##
	# Recursively scan filesystem for wildcard match
	##
	my $dir = shift;
	my $spec = shift || '*';

	$dir =~ s@/$@@;

	##
	# First, convert filespec into regular expression.
	##
	my $reg_exp = $spec;
	$reg_exp =~ s/\./\\\./g; # escape real dots
	$reg_exp =~ s/\*/\.\+/g; # wildcards into .+
	$reg_exp =~ s/\?/\./g; # ? into .
	$reg_exp = '^'.$reg_exp.'$'; # match entire filename
	
	##
	# Now read through directory, checking files against
	# regular expression.  Push matched files onto array.
	##
	my @files = ();
	my $dirh = new DirHandle $dir;
	unless (defined($dirh)) { return @files; }
	
	my $filename;
	while (defined($filename = $dirh->read())) {
		if (($filename ne '.') && ($filename ne '..')) {
			if (-d $dir.'/'.$filename) { push @files, find_files( $dir.'/'.$filename, $spec ); }
			if ($filename =~ m@$reg_exp@) { push @files, $dir.'/'.$filename; }
		} # don't process . and ..
	}
	undef $dirh;
	
	##
	# Return final array.
	##
	return @files;
}

sub get_network_interfaces {
	##
	# Get hashref of network interfaces using ifconfig
	# Only currently guarenteed to work on Linux
	##
	my $ifs = {};

	if ($Config{'osname'} ne 'linux') { return {'Local Loopback' => '127.0.0.1'}; }
	my $raw = `/sbin/ifconfig 2>&1`;

	while ($raw =~ s/Link\sencap:(.+?)inet\saddr:(\d+\.\d+\.\d+\.\d+)//is) {
		my ($name, $ip) = ($1, $2);
		$name =~ s/HWaddr.+$//is;
		$name =~ s/\s+$//is;
		$ifs->{$name} = $ip;
	}

	return $ifs;
}

sub wget {
	##
	# Fetch URL and return HTTP::Response object
	##
	my $url = shift;
	my $headers = {@_};

	my $ua = LWP::UserAgent->new();
	$ua->timeout( 30 );
	my $req = HTTP::Request->new( 'GET', $url );
	
	foreach my $key (keys %$headers) {
		$req->header( $key => $headers->{$key} );
	}

	return $ua->request( $req );
}

sub xml_to_javascript {
	##
	# Convert XML hash tree to JavaScript objects/arrays
	# Do this non-destructively
	##
	my $xml = shift;
	my $indent = shift || 1;
	my $args = {@_};
	my $tabs = "\t" x $indent;
	my $parent_tabs = '';
	my $js = '';
	my $eol = "\n";
	
	if (!defined($args->{lowercase})) { $args->{lowercase} = 0; }
	if (!defined($args->{collapse_attribs})) { $args->{collapse_attribs} = 1; }
	if (!defined($args->{compress})) { $args->{compress} = 0; }
	if (!defined($args->{force_strings})) { $args->{force_strings} = 0; }

	if ($indent > 1) { $parent_tabs = "\t" x ($indent-1); }
	if ($args->{compress}) { $parent_tabs = ''; $tabs = ''; $eol = ''; }
	
	if (isa($xml, 'HASH')) {
		$js .= "{$eol";
		my @keys = keys %$xml;
		foreach my $key (@keys) {
			if (ref($xml->{$key})) {
				if (($key eq "_Attribs") && $args->{collapse_attribs}) {
					# foreach my $attrib_name (keys %{$xml->{'_Attribs'}}) { $xml->{$attrib_name} = $xml->{'_Attribs'}->{$attrib_name}; }
					# push @keys, keys %{$xml->{'_Attribs'}};
					foreach my $akey (keys %{$xml->{_Attribs}}) {
						$js .= $tabs . '"' . ($args->{lowercase} ? lc($akey) : $akey) . '": ' . escape_js($xml->{_Attribs}->{$akey}, $args->{force_strings}) . ",$eol";
					}
					next;
				}
				$js .= $tabs . '"' . ($args->{lowercase} ? lc($key) : $key) . '": ' . xml_to_javascript($xml->{$key}, $indent + 1, %$args);
			}
			else {
				$js .= $tabs . '"' . ($args->{lowercase} ? lc($key) : $key) . '": ' . escape_js($xml->{$key}, $args->{force_strings}) . ",$eol";
			}
		}
		$js =~ s/\,$eol$/$eol/;
		$js .= $parent_tabs . "},$eol";
	}
	elsif (isa($xml, 'ARRAY')) {
		$js .= "[$eol";
		foreach my $elem (@$xml) {
			if (ref($elem)) {
				$js .= $tabs . xml_to_javascript($elem, $indent + 1, %$args);
			}
			else {
				$js .= $tabs . escape_js($elem, $args->{force_strings}) . ",$eol";
			}
		}
		$js =~ s/\,$eol$/$eol/;
		$js .= $parent_tabs . "],$eol";
	}

	if ($indent == 1) {
		$js =~ s/\,$eol$//;
	}

	return $js;
}

sub escape_js {
	##
	# Escape value for JavaScript eval
	##
	my $value = shift;
	my $force_string = shift || 0;
	
	if ($force_string || ($value !~ /^\-?\d{1,15}(\.\d{1,15})?$/) || ($value =~ /^0[^\.]/)) {
		$value =~ s/\r\n/\n/sg; # dos2unix
		$value =~ s/\r/\n/sg; # mac2unix
		$value =~ s/\\/\\\\/g; # escape backslashes
		$value =~ s/\"/\\\"/g; # escape quotes
		$value =~ s/\n/\\n/g; # escape EOLs
		$value =~ s/<\/(scr)(ipt)>/<\/$1\" + \"$2>/ig; # escape closing script tags
		$value = '"' . $value . '"';
	}
	
	return $value;
}

sub normalize_midnight {
	##
	# Return epoch of nearest midnight before now
	##
	my $now = shift || time();
	
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime( $now );
	return timelocal( 0, 0, 0, $mday, $mon, $year );
}

sub follow_symlinks {
	##
	# Recursively resolve all symlinks in file path
	##
	my $file = shift;
	my $old_dir = cwd();

	chdir dirname $file;
	while (my $temp = readlink(basename $file)) {
		$file = $temp; 
		chdir dirname $file;
	}
	chdir $old_dir;

	return abs_path(dirname($file)) . '/' . basename($file);
}

sub get_remote_ip {
	##
	# Return the "true" remote IP address, even if request went through a cache
	##
	my $ip = $ENV{'REMOTE_ADDR'};
	
	if ($ENV{'HTTP_X_FORWARDED_FOR'}) {
		$ip .= ', ' . $ENV{'HTTP_X_FORWARDED_FOR'};
	}
	
	return $ip;
}

sub get_user_agent {
	##
	# Get the user agent string, and tack on the cache Via header if found.
	# Also check the X-Flash-Version header
	##
	my $useragent = shift || $ENV{'HTTP_USER_AGENT'} || '';
	
	if ($ENV{'HTTP_VIA'}) { $useragent .= "; " . $ENV{'HTTP_VIA'}; }
	if ($ENV{'HTTP_FORWARDED'}) { $useragent .= "; " . $ENV{'HTTP_FORWARDED'}; }
	if ($ENV{'HTTP_X_FLASH_VERSION'}) { $useragent .= "; Flash Player " . $ENV{'HTTP_X_FLASH_VERSION'}; }
	
	$useragent =~ s/(\[|\])//g;
	
	return $useragent;
}

sub get_client_info {
	##
	# IP and User Agent together
	##
	return get_remote_ip() . ', ' . get_user_agent(@_);
}

sub strip_high {
	##
	# Strip all high-ascii, and non-printable low-ascii chars from string
	# Returned stripped string.
	##
	my $text = shift;
	if (!defined($text)) { $text = ""; }
	
	$text =~ s/([\x80-\xFF\x00-\x08\x0B-\x0C\x0E-\x1F])//g;
	return $text;
}

sub merge_hashes {
	##
	# Simple recursive hash merge
	# Arrays are simply copied over
	##
	my ($base_hash, $new_hash, $replace_ok) = @_;
	
	foreach my $key (keys %$new_hash) {
		if (ref($new_hash->{$key})) {
			if (isa($new_hash->{$key}, 'HASH')) {
				if (!defined($base_hash->{$key}) || !isa($base_hash->{$key}, 'HASH')) {
					$base_hash->{$key} = {};
				}
				merge_hashes( $base_hash->{$key}, $new_hash->{$key} );
			}
			elsif ($replace_ok || !defined($base_hash->{$key})) {
				$base_hash->{$key} = $new_hash->{$key};
			}
		}
		elsif ($replace_ok || !defined($base_hash->{$key})) {
			$base_hash->{$key} = $new_hash->{$key};
		}
	}
}

sub XMLfind {
	my($xml,$args)=@_;
	
	if (ref($xml) =~ /HASH/) {
		foreach my $key (keys (%{$args})) {
			if (defined($xml->{$key}) && (($xml->{$key} eq $args->{$key}) || ($args->{$key} eq '*'))) {return $xml;}
		}
		foreach my $key (keys (%{$xml})) {
			if (my $result=XMLfind($xml->{$key},$args)) {return $result;}
		}
	} elsif (ref($xml) =~ /ARRAY/) {
		foreach my $element (@{$xml}) {
			if (my $result=XMLfind($element,$args)) {return $result;}
		}
	}
	return 0;
}

sub XMLsearch {
	my $args={@_};

	if (!defined($args->{xml})) {return 0;}
	my $xml=$args->{xml};
	delete $args->{xml};

	return XMLfind($xml,$args);
}

sub XMLindexby {

# XMLindexby(
#	xml			=> $reference_to_parent_node,	# hash reference to xml tree
#	element		=> 'name_of_array',				# string name of array
#	key			=> 'name_of_param_to_index_by',	# name of param whose values become elements themselves
#	recursive	=> 0-1,							# recursively search thru tree
#	compress	=> 0-1							# if only 1 param remains in element after indexing,
# );											# and param is scalar ref (not ref to more branches)
#												# "step-down" param's value into element itself

	my $args={@_}; # get hash ref to incoming args
	if (!defined($args->{xml}) || !defined($args->{key}) || !defined($args->{element})) {return 0;} # required params
	if (!defined($args->{recursive})) {$args->{recursive}=0;} # define to avoid use of uninitialized value
	if (!defined($args->{compress})) {$args->{compress}=0;} # define to avoid use of uninitialized value
	
	if ((ref($args->{xml}) =~ /HASH/)
		&& defined($args->{xml}->{$args->{element}})
		&& (ref($args->{xml}->{$args->{element}}) =~ /HASH/)
		&& defined($args->{xml}->{$args->{element}}->{$args->{key}})) {
			XMLalwaysarray(xml=>$args->{xml}, element=>$args->{element});
	}
	
	if ((ref($args->{xml}) =~ /HASH/) && (defined($args->{xml}->{$args->{element}})) && (ref($args->{xml}->{$args->{element}}) =~ /ARRAY/)) {
		my $reindex=0; # if at least one element in array has key param, assume entire array does (TBD: partial reindexing)
		for (my $i=scalar (@{$args->{xml}->{$args->{element}}})-1; $i>=0; $i--) { # step backward through array
			my $element=$args->{xml}->{$args->{element}}[$i]; # get ref to current element in array
			if (defined($element->{$args->{key}}) && $element->{$args->{key}}) { # if element contains key param
				$reindex=1; # tag array for deletion
				my $new_name=$element->{$args->{key}}; # get elements 'new name', i.e. value of key param
				
				delete $element->{$args->{key}}; # delete original key param
				if ($args->{compress} && (scalar keys (%{$element}) == 1) && !ref($element->{(keys (%{$element}))[0]})) { # if desired, compress remaining single param into element itself
					$element = $element->{(keys (%{$element}))[0]};
					# $sample->{variable}->{value} > becomes > $sample->{variable}
				} # compress
				
				if (exists($args->{xml}->{$new_name})) {
					if (!ref($args->{xml}->{$new_name}) || isa($args->{xml}->{$new_name}, 'HASH')) {
						$args->{xml}->{$new_name} = [ $args->{xml}->{$new_name} ];
					}
					if (isa($args->{xml}->{$new_name}, 'ARRAY')) {
						unshift @{$args->{xml}->{$new_name}}, $element;
						# $element = $args->{xml}->{$new_name}->[0];
					}
				}
				else {
					$args->{xml}->{$new_name}=$element; # insert new branch at parent's level
					# $element=$args->{xml}->{$new_name}; # reset $element to point to new branch
				}
				
			} # element contains key param
		} # for loop -- steps thru array
		if ($reindex) { # if we reindexed the array, delete it
			delete $args->{xml}->{$args->{element}}; # delete entire array after reindexing is complete
		} # reindexed array
	} # element found in top-level keys
	
	if ($args->{recursive}) {
		if (ref($args->{xml}) =~ /HASH/) {
			foreach my $element (keys (%{$args->{xml}})) { # step thru hash keys
				XMLindexby( # recurse into self
					xml=>$args->{xml}->{$element},
					element=>$args->{element},
					key=>$args->{key},
					recursive=>$args->{recursive},
					compress=>$args->{compress}
				);
			} # step thru hash keys
		} elsif (ref($args->{xml}) =~ /ARRAY/) {
			foreach my $element (@{$args->{xml}}) { # step through array
				XMLindexby( # recurse into self
					xml=>$element,
					element=>$args->{element},
					key=>$args->{key},
					recursive=>$args->{recursive},
					compress=>$args->{compress}
				);
			} # foreach loop -- steps thry array
		} # xml is array ref
	} # resursive mode
}

sub XMLalwaysarray {
	my $args={@_};

	if (!defined($args->{xml}) || !defined($args->{element})) {return 0;}

	if (defined($args->{xml}->{$args->{element}}) && ref($args->{xml}->{$args->{element}}) !~ /ARRAY/) {
		my $temp=$args->{xml}->{$args->{element}};
		undef $args->{xml}->{$args->{element}};
		(@{$args->{xml}->{$args->{element}}})=($temp);
		return 1;
	}
	return 0;
}

sub find_object {
	##
	# Find object in array based on criteria (sub hash compare)
	##
	my $list = isa($_[0], 'HASH') ? [shift] : shift;
	my $criteria = (scalar @_ == 1) ? shift : {@_};
	
	foreach my $elem (@$list) {
		my $matches = 0;
		foreach my $key (keys %$criteria) {
			my $value = $criteria->{$key};
			if (defined($elem->{$key}) && ($elem->{$key} eq $value)) { $matches++; }
			elsif (defined($elem->{_Attribs}) && defined($elem->{_Attribs}->{$key}) && ($elem->{_Attribs}->{$key} eq $value)) { $matches++; }
		}
		if ($matches >= scalar keys %$criteria) { return $elem; }
	}
	
	return 0;
}

sub make_dirs_for {
	##
	# Recursively create directories, given complete path.
	# If incoming path ends in slash, assumes user wants
	# directory there, otherwise assumes path ends in filename,
	# and strips it off.
	##
	my $file = shift;
	my $permissions = shift || 0775;
	
	##
	# if file has ending slash, assume user wants directory there
	##
	if ($file =~ m@/$@) {chop $file;}
	else {
		##
		# otherwise, assume file ends in actual filename, and strip it off
		##
		$file =~ s@^(.+)/[^/]+$@$1@;
	}
	
	##
	# if directories already exist, return immediately
	##
	if (-e $file) {return 1;}
	
	##
	# Assume we're starting from current directory, unless
	# incoming path begins with /
	##
	my $path='.';
	
	##
	# if file starts with slash, remove '.' from path
	# and remove slash from file for proper split operation
	##
	if ($file =~ m@^/@) {
		$path='';
		$file =~ s@^/@@;
	}
	
	##
	# Step through directories, creating as we go.
	##
	foreach my $dir (split(/\//,$file)) {
		##
		# Add current dir onto path
		##
		$path .= '/' . $dir;
		
		##
		# Only create dir if nonexistent.
		# Return 0 if failed to create.
		##
		if (!(-e $path)) {
			if (!mkdir($path,$permissions)) {return 0;}
		}
	}
	
	##
	# Return 1 for success.
	##
	return 1;
}

sub get_args {
	##
	# Convert long-style command-line args to hash ref
	##
	my $args = {};
	my @input = @_;
	if (!@input) { @input = @ARGV; }
	
	my $mode = undef;
	my $key = undef;
	
	while (defined($key = shift @input)) {
		if ($key =~ /^\-*(\w+)=(.+)$/) { $args->{$1} = $2; next; }
		
		my $dash = 0;
		if ($key =~ s/^\-+//) { $dash = 1; }

		if (!defined($mode)) {
			$mode = $key;
		}
		else {
			if ($dash) {
				if (!defined($args->{$mode})) { $args->{$mode} = 1; }
				$mode = $key;
			} 
			else {
				if (!defined($args->{$mode})) { $args->{$mode} = $key; }
				else { $args->{$mode} .= ' ' . $key; }
			} # no dash
		} # mode is 1
	} # while loop

	if (defined($mode) && !defined($args->{$mode})) { $args->{$mode} = 1; }

	return $args;
}

sub parse_xml {
	##
	# Simple static wrapper around XML::Lite for parsing
	##
	my $thingy = shift;
	my $parser = new XML::Lite( $thingy );
	if ($parser->getLastError()) { return $parser->getLastError(); }
	return $parser->getTree();
}

sub parse_xml_collapse {
	##
	# Simple static wrapper around XML::Lite for parsing
	# This one collapses attrib branches
	##
	my $thingy = shift;
	my $parser = new XML::Lite(
		preserveAttributes => 0,
		thingy => $thingy
	);
	if ($parser->getLastError()) { return $parser->getLastError(); }
	return $parser->getTree();
}

sub compose_xml {
	##
	# Simple static wrapper around XML::Lite for composing
	##
	my ($thingy, $doc_node_name) = @_;
	my $parser = new XML::Lite( $thingy );
	$parser->setDocumentNodeName( $doc_node_name );
	return $parser->compose();
}

sub import_param {
	##
	# Import Parameter into hash ref.  Dynamically create arrays for keys
	# with multiple values.
	##
	my ($operator, $key, $value) = @_;

	$value = uri_unescape( $value );
	
	if ($operator->{$key}) {
		if (isa($operator->{$key}, 'ARRAY')) {
			push @{$operator->{$key}}, $value;
		}
		else {
			$operator->{$key} = [ $operator->{$key}, $value ];
		}
	}
	else {
		$operator->{$key} = $value;
	}
}

sub parse_query {
	##
	# Parse query string into hash ref
	##
	my $uri = shift;
	my $query = {};
	
	$uri =~ s@^.*\?@@; # strip off everything before ?
	$uri =~ s/([\w\-\.\/]+)\=([^\&]*)\&?/ import_param($query, $1, $2); ''; /eg;
	
	return $query;
}

sub compose_query {
	##
	# Convert hash into escaped query string params
	##
	my $query = shift;
	my $qs = '';
	
	foreach my $key (sort keys %$query) {
		if (isa($query->{$key}, 'ARRAY')) {
			foreach my $elem (@{$query->{$key}}) {
				$qs .= ($qs ? '&' : '?') . $key . '=' . uri_escape($elem);
			}
		}
		else {
			$qs .= ($qs ? '&' : '?') . $key . '=' . uri_escape($query->{$key});
		}
	}
	
	return $qs;
}

sub parse_cookies {
	##
	# Parse HTTP cookies into hash table
	##
	my $cookie = {};
	my $cookies = $ENV{'HTTP_COOKIE'};
	if ($cookies) {
		foreach my $cookie_raw (split(/\;\s*/, $cookies)) {
			merge_hashes($cookie, parse_query($cookie_raw), 1);
		}
	}
	return $cookie;
}

sub touch {
	##
	# Update file mod date, and create file if nonexistent
	##
	my $file = shift;
	
	unless (-e $file) {
		my $fh = new FileHandle ">>$file";
	}
	
	my $now = int(time());
	utime $now, $now, $file;
}

sub get_seconds_from_text {
	##
	# Given text string, calculates total number of seconds.
	# Accepts many formats:
	#
	# Examples:
	#	'18.5 Sec'       -> 18.5
	#	'-45 minutes'    -> -2700
	#	'+2d'            -> 172800
	#	'3 DAYS 2 HOURS' -> 266400
	#	'Today +75d'     -> 1000673791 # today == current epoch
	#	'1 Year, 1 Week' -> 32240800
	#	'+3w -2h +10min' -> 1807800
	##
	my $text = shift;
	
	##
	# Regexp prefix for second, minute, hour, day, week, month, year rules.
	# Allows negative or positive integers or floats, allows space padding.
	##
	my $prefix = '([\-\+])?\s*(\d+(\.\d+)?)\s*';
	
	##
	# See if user passed in simple numerical value.
	# If so, return it immediately -- no processing needed.
	##
	if ($text =~ /^\s*$prefix$/) {return $text;}
	
	##
	# Start with 0 seconds, then add or subtract as we go.
	##
	my $seconds = 0;
	
	##
	# Define rules that translate text into raw seconds.
	##
	my $rules = {
		'today' => 'time()', # turns 'today' into epoch seconds
		$prefix.'s' => '$2', # plain seconds
		$prefix.'mi' => '($2 * 60)', # minutes
		$prefix.'h' => '($2 * 3600)', # hours
		$prefix.'d' => '($2 * 86400)', # days
		$prefix.'w' => '($2 * 604800)', # weeks
		$prefix.'mo' => '($2 * 2592000)', # months (30 days)
		$prefix.'y' => '($2 * 31536000)' # years (365 days)
	};
	
	##
	# Step through each rule, matching it to the text string.
	# Increments or decrements $seconds accordingly.
	##
	foreach my $rule (keys %{$rules}) {
		$text =~ s/$rule/eval('$seconds'.($1 || '+').'='.$rules->{$rule}.';');'';/ieg;
	}
	
	##
	# Return final value in seconds.
	##
	return $seconds;
}

sub get_text_from_seconds {
	##
	# Given raw seconds, returns text representation of relative time.
	# 
	# Examples:
	#	1     -> 1 second
	#	63    -> 1 minute, 3 seconds
	#	90000 -> 1 day, 1 hour
	##
	my $sec = shift;
	
	##
	# If value is negative, temporarily make positive -- 
	# Will negate again later.
	##
	my $neg = '';
	if ($sec < 0) {$sec = -$sec; $neg = '-';}
	
	##
	# Pretty-print the decimal portion -- only allow 2 digits after
	# the decimal point, unless they are zeros.
	##
	$sec =~ s/^(\d+\.[0]*\d{2}).*$/$1/;
	
	##
	# Strip off decimal portion -- will append later
	##
	my $sec_dec = '';
	if ($sec =~ s/^(\d+)(\.\d+)$/$1/) {$sec_dec = $2;}
	
	##
	# Setup text variables
	##
	my $p_text = 'second';
	my $p_amt = $sec.$sec_dec;
	my $s_text = '';
	my $s_amt = 0;
	
	##
	# If seconds exceed 59, convert to minutes (and remaining seconds)
	##
	if ($sec > 59) {
		my $min = int($sec / 60);
		$sec = $sec % 60;
		$sec .= $sec_dec;
		$s_text = 'second';
		$s_amt = $sec;
		$p_text = 'minute';
		$p_amt = $min;
		
		##
		# If minutes exceed 95, convert to hours (and remaining minutes)
		##
		if ($min > 59) {
			my $hour = int($min / 60);
			$min = $min % 60;
			$s_text = 'minute';
			$s_amt = $min;
			$p_text = 'hour';
			$p_amt = $hour;
			
			##
			# If hours exceed 23, convert to days (and remaining hours)
			##
			if ($hour > 23) {
				my $day = int($hour / 24);
				my $total_days = $day;
				$hour = $hour % 24;
				$s_text = 'hour';
				$s_amt = $hour;
				$p_text = 'day';
				$p_amt = $day;
				
				##
				# If days exceed 6, convert to weeks (and remaining days)
				##
				if ($day > 6) {
					my $week = int($day / 7);
					$day = $day % 7;
					$s_text = 'day';
					$s_amt = $day;
					$p_text = 'week';
					$p_amt = $week;
					
					##
					# If days exceed 30, convert to months (and remaining days)
					##
					if ($total_days > 30) {
						my $month = int($total_days / 31);
						$day = $total_days % 31;
						$s_text = 'day';
						$s_amt = $day;
						$p_text = 'month';
						$p_amt = $month;
						
						##
						# If days exceed 364, convert to years (and remaining months)
						##
						if ($total_days > 364) {
							my $year = int($total_days / 365);
							$month = $month % 12;
							$s_text = 'month';
							$s_amt = $month;
							$p_text = 'year';
							$p_amt = $year;
						} # day>30
					} # day>30
				} # day>6
			} # hour>23
		} # min>59
	} # sec>59
	
	##
	# Fill text with primary and secondary units, and apply pluralization.
	##
	my $text = $p_amt.' '.$p_text;
	if ($p_amt != 1) {$text .= 's';}
	if ($s_amt) {
		$text .= ', '.$s_amt.' '.$s_text;
		if ($s_amt != 1) {$text .= 's';}
	}
	
	##
	# Return final text, negated if original raw seconds were.
	##
	return $neg.$text;
}

sub probably {
	##
	# Calculate probability and return true or false
	# 1.0 will always return true
	# 0.5 will return true half the time
	# 0.0 will never return true
	##
	if (!defined($_[0])) { return 1; }
	return ( rand(1) < $_[0] ) ? 1 : 0;
}

sub rand_array {
	##
	# Pick random element from array ref
	##
	my $array = shift;
	return $array->[ int(rand(scalar @$array)) ];
}

sub find_elem_idx {
	##
	# Locate element inside of arrayref by value
	##
	my ($arr, $elem) = @_;
	
	my $idx = 0;
	foreach my $temp (@$arr) {
		if ($temp eq $elem) { return $idx; }
		$idx++;
	}
	
	return -1; # not found
}

sub remove_from_array {
	##
	# Locate first element inside of arrayref by value, then remove it
	##
	my ($arr, $elem) = @_;
	
	my $idx = find_elem_idx($arr, $elem);
	if ($idx > -1) {
		splice @$arr, $idx, 1;
		return 1;
	}
	return 0;
}

sub remove_all_from_array {
	##
	# Locate ALL elements matching value, and remove ALL from array
	##
	my ($arr, $elem) = @_;
	
	my $done = 0;
	my $found = 0;
	
	while (!$done) {
		my $idx = find_elem_idx($arr, $elem);
		if ($idx > -1) { splice @$arr, $idx, 1; $found++; }
		else { $done = 1; }
	}
	
	return $found;
}

sub dumper {
	##
	# Wrapper for Data::Dumper::Dumper
	##
	my $obj = shift;
	
	return Dumper($obj);
}

sub serialize_object {
	##
	# Utility method, uses Data::Dumper to serialize object tree to string
	##
	my $obj = shift;
	local $Data::Dumper::Indent = 0;
	local $Data::Dumper::Terse = 1;
	local $Data::Dumper::Quotekeys = 0;
	return Dumper($obj);
}

sub deep_copy {
	##
	# Deep copy a hash/array tree
	##
	my $in = shift;
	my $VAR1 = undef;
	local $Data::Dumper::Deepcopy = 1;
	return eval( Dumper($in) );
}

sub yyyy {
	##
	# Return current year as YYYY
	##
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime( time() );
	return sprintf("%0004d", $year + 1900);
}

sub yyyy_mm_dd {
	##
	# Return date in YYYY-MM-DD format given epoch
	##
	my $epoch = shift || time();
	
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime( $epoch );
	return sprintf( "%0004d-%02d-%02d", $year + 1900, $mon + 1, $mday );
}

sub get_nice_date {
	##
	# Given epoch, return pretty-printed date and possibly time too
	##
	my $epoch = shift;
	my $yes_time = shift || 0;
	my $nice = '';

	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime( $epoch );
	my $month_name = $months->[$mon];
	my $yyyy = sprintf( "%0004d", $year + 1900 );
	
	$nice .= "$month_name $mday, $yyyy";

	if ($yes_time) {
		$nice .= ' ';
		my $ampm = 'AM';
		if ($hour >= 12) { $hour -= 12; $ampm = 'PM'; }
		if (!$hour) { $hour += 12; }
		$min = sprintf( "%02d", $min );
		$sec = sprintf( "%02d", $sec );
		$nice .= "$hour:$min:$sec $ampm";
	}

	return $nice;
}

sub copy_hash_remove_keys {
	##
	# Make shallow copy of hash and remove selected keys
	##
	my $hash = shift;
	my $copy = { %$hash };
	
	while (my $key = shift @_) {
		delete $copy->{$key};
	}
	
	return $copy;
}

sub trim {
	##
	# Trim whitespace from beginning and end of string
	##
	my $text = shift;
	
	$text =~ s@^\s+@@; # beginning of string
	$text =~ s@\s+$@@; # end of string
	
	return $text;
}

sub nslookup {
	my $ips = shift;
	my $result = '';
	
	foreach my $ip (split(/\,\s*/, $ips)) {
		my $hostname;

		($hostname, undef, undef, undef, undef) = (gethostbyaddr(pack("C4", split(/\./, $ip)), 2));
		# if (defined($hostname)) {$hostname =~ s/^(\w+).*$/$1/;} # strip off junk after name
		
		if ($result) { $result .= ', '; }
		$result .= ($hostname || '(unknown host)');
	}
	
	return $result;
}

sub xpath_summary {
	# summarize all xpaths that point to scalar text values, recursively
	# return single level hash with xpaths as keys and the actual scalar values
	my ($xml, $base_path, $inc_refs) = @_;
	if (!$base_path) { $base_path = '/'; }
	my $paths = {};
	
	if (isa($xml, 'HASH')) {
		foreach my $key (keys %$xml) {
			if (ref($xml->{$key})) {
				if ($inc_refs) { $paths->{ $base_path . $key } = $xml->{$key}; }
				$paths = { %$paths, %{xpath_summary($xml->{$key}, $base_path . $key . '/', $inc_refs)} };
			}
			else {
				$paths->{ $base_path . $key } = $xml->{$key};
			}
		}
	}
	elsif (isa($xml, 'ARRAY')) {
		my $idx = 0;
		foreach my $elem (@$xml) {
			my $base_path_strip = $base_path; $base_path_strip =~ s/\/$//;
			if (ref($elem)) {
				if ($inc_refs) { $paths->{ $base_path_strip . '[' . $idx . ']' } = $elem; }
				$paths = { %$paths, %{xpath_summary($elem, $base_path_strip . '[' . $idx . ']/', $inc_refs)} };
			}
			else {
				$paths->{ $base_path_strip . '[' . $idx . ']' } = $elem;
			}
			$idx++;
		}
	}
	
	return $paths;
}

sub strip_html {
	# strip all html tags
	my $html = shift;
	$html =~ s/<.+?>//sg;
	return $html;
}

sub get_request_url {
	# reconstruct fully qualified request URL from headers
	my $url = '';
	if ($ENV{'REQUEST_URI'}) {
		$url = $ENV{'HTTPS'} ? 'https://' : 'http://';
		$url .= $ENV{'HTTP_HOST'} . $ENV{'REQUEST_URI'};
	}
	return $url;
}

1;