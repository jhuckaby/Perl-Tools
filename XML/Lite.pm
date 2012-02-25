package XML::Lite;

# Copyright (c) 2005 - 2011 Joseph Huckaby
# Source Code released under the MIT License: 
# http://www.opensource.org/licenses/mit-license.php

##
# Lite.pm
#
# Description:
#	Lightweight XML parser and composer module written in pure Perl.
#
# Usage Examples:
#	my $xml = new XML::Lite "my_file.xml";
#	my $tree = $xml->getTree();
#	$tree->{Somthing}->{Other} = "Hello!";
#	$xml->compose( 'my_file.xml' );
##

use strict;
use FileHandle;
use File::Basename;
use UNIVERSAL qw/isa/;
use vars qw/$VERSION/;

my $defaults = {
	compress => 0,
	printErrors => 0,
	indentString => "\t",
	preserveAttributes => 1,
	entities => {
		'amp' => '&',
		'lt' => '<',
		'gt' => '>',
		'apos' => "'",
		'quot' => '"'
	}
};

sub new {
	my $class = shift @_;
	
	##
	# Get named parameters, or filename from argument list.
	##
	my $self;
	if (scalar(@_) > 1) { $self = { %$defaults, @_ }; }
	else { $self = { %$defaults, thingy => shift @_ }; }

	$self->{dtdNodeList} = [];
	$self->{piNodeList} = [];
	$self->{errors} = [];
	$self->{tree} = {};
	
	bless $self, $class;
		
	##
	# Determine what thingy is, and populate correct argument.
	##
	if ($self->{thingy}) {
		$self->importThingy( $self->{thingy} );
		delete $self->{thingy};
	}
	
	##
	# See what args we have, and get to the point of XML text.
	##
	$self->prepareParse();
				
	##
	# Parse XML
	##
	if ($self->{text}) { $self->parse(); }
	
	return $self;
}

sub importThingy {
	##
	# Import text, FileHandle or filename into root hash
	##
	my $self = shift;
	my $thingy = shift;
	
	undef $self->{text};
	undef $self->{fh};
	undef $self->{file};
	
	if (ref($thingy)) {
		if (isa($thingy, 'FileHandle')) {
			$self->{fh} = $thingy;
		}
		else {
			$self->{tree} = $thingy;
		}
	}
	elsif ($thingy =~ m@<.+?>@) {
		$self->{text} = $thingy;
	}
	elsif (-e $thingy) {
		$self->{file} = $thingy;
	}
	else {
		$self->throwError(
			type => 'parse',
			key => 'Thingy not found: ' . $thingy
		);
		return undef;
	}
}

sub prepareParse {
	##
	# Get to the point of XML text to prepare for parsing
	##
	my $self = shift;
	
	if (!$self->{text}) {
		if ($self->{file} && !$self->{fh}) {
			$self->{fh} = new FileHandle $self->{file};
			if (!$self->{fh}) {
				$self->throwError(
					type => 'parse',
					key => 'File not found: ' . $self->{file}
				);
				return undef;
			}
		}
		if ($self->{fh}) {
			my $len = read( $self->{fh}, $self->{text}, 
				(stat($self->{fh}))[7] );
			undef $self->{fh};
			if (!$len) {
				$self->throwError(
					type => 'parse',
					key => 'Zero bytes read'
				);
				return undef;
			} # zero bytes
		}
	}
}

sub reload {
	##
	# Reload file
	##
	my $self = shift;
	
	undef $self->{text};
	$self->{errors} = [];
	$self->{tree} = {};
	
	$self->prepareParse();
	if ($self->{text}) { $self->parse(); }
}

sub parse {
	##
	# Parse one level of nodes and recurse into nested nodes
	##
	my $self = shift;
	my $branch = shift || $self->{tree};
	my $name = shift || undef;
	my $foundClosing = 0;
		
	##
	# Process a single node, and any preceding text
	##
	while ($self->{text} =~ m@([^<]*?)<([^>]+)>@sog) {
		my ($before, $tag) = ($1, $2);
		
		##
		# If there was text preceding the opening tag, insert it now
		##
		if ($before =~ /\S/) {
			$before =~ s@^(\s*)(.+?)(\s*)$@$3@s;
			if ($branch->{content}) { $branch->{content} .= ' '; }
			$branch->{content} .= $self->decodeEntities($2);
		}
		
		##
		# Check if tag is a PI, DTD, CDATA, or Comment tag
		##
		if ($tag =~ /^\s*([\!\?])/o) {
			if    ($tag =~ /^\s*\?/) { 
				$tag = $self->parsePINode( $tag ); }
			elsif ($tag =~ /^\s*\!--/) {
				$tag = $self->parseCommentNode( $tag ); }
			elsif ($tag =~ /^\s*\!DOCTYPE/) { 
				$tag = $self->parseDTDNode( $tag ); }
			elsif ($tag =~ /^\s*\!\s*\[\s*CDATA/) {
				$tag = $self->parseCDATANode( $tag );
				if ($tag) {
					if ($branch->{content}) { $branch->{content} .= ' '; }
					$branch->{content} .= $self->decodeEntities($tag);
					next;
				}
			}
			else {
				$self->throwParseError( "Malformed special tag", $tag );
				last;
			}
			if (!defined($tag)) { last; }
			next;
		}
		else {
			##
			# Tag is standard, so parse name and attributes (if any)
			##
			if ($tag !~ m@^\s*(/?)([\w\-\:\.]+)\s*(.*)$@os) {
				$self->throwParseError( "Malformed tag", $tag );
				last;
			}
			my ($closing, $nodeName, $attribsRaw) = ($1, $2, $3);
			
			##
			# If this is a closing tag, make sure it matches its opening tag
			##
			if ($closing) {
				if ($nodeName eq ($name || '')) {
					$foundClosing = 1;
					last;
				}
				else {
					$self->throwParseError( 
						"Mismatched closing tag (expected </" . 
						$name . ">)", $tag );
					last;
				}
			}
			else {
				##
				# Not a closing tag, so parse attributes into hash.  If tag
				# is self-closing, no recursive parsing is needed.
				##
				my $selfClosing = $attribsRaw =~ s/\/\s*$//;
				my $leaf = {};
				
				if ($attribsRaw) {
					if ($self->{preserveAttributes}) {
						my $attribs = {};
						$attribsRaw =~ s@([\w\-\:\.]+)\s*=\s*([\"\'])([^\2]*?)\2@ $attribs->{$1} = $self->decodeEntities($3); ''; @esg;
						$leaf->{_Attribs} = $attribs;
					}
					else {
						$attribsRaw =~ s@([\w\-\:\.]+)\s*=\s*([\"\'])([^\2]*?)\2@ $leaf->{$1} = $self->decodeEntities($3); ''; @esg;
					}
					
					if ($attribsRaw =~ /\S/) {
						$self->throwParseError( 
							"Malformed attribute list", $tag );
					}
				}

				if (!$selfClosing) {
					##
					# Recurse for nested nodes
					##
					$self->parse( $leaf, $nodeName );
					if ($self->error()) { last; }
				}
				
				##
				# Compress into simple node if text only
				##
				my $num_keys = scalar keys %$leaf;
				if (defined($leaf->{content}) && ($num_keys == 1)) {
					$leaf = $leaf->{content};
				}
				elsif (!$num_keys) {
					$leaf = '';
				}
				
				##
				# Add leaf to parent branch
				##
				if (defined($branch->{$nodeName})) {
					if (isa($branch->{$nodeName}, 'ARRAY')) {
						push @{$branch->{$nodeName}}, $leaf;
					}
					else {
						my $temp = $branch->{$nodeName};
						$branch->{$nodeName} = [ $temp, $leaf ];
					}
				}
				else {
					$branch->{$nodeName} = $leaf;
				}
				
				if ($self->error() || ($branch eq $self->{tree})) { last; }
			} # not closing tag
		} # not comment/DTD/XML tag
	} # while loop

	##
	# Make sure we found the closing tag
	##
	if ($name && !$foundClosing) {
		$self->throwParseError( 
			"Missing closing tag (expected </" . 
			$name . ">)", $name );
	}
	
	##
	# If we are the master node, finish parsing and setup our doc node
	##
	if ($branch eq $self->{tree}) { $self->finishParse(); }
	if (!$self->error()) { $self->{parsed} = 1; }
}

sub finishParse {
	##
	# Grab any loose text/comments after final closing node, and setup docNodeName
	##
	my $self = shift;

	if ($self->{tree}->{content}) { delete $self->{tree}->{content}; }
	
	if (scalar keys %{$self->{tree}} > 1) {
		$self->throwError(
			type => 'parse',
			key => 'Only one top-level node is allowed in document'
		);
		return;
	}
	
	$self->{documentNodeName} = (keys %{$self->{tree}})[0];
	if ($self->{documentNodeName}) {
		$self->{tree} = $self->{tree}->{ $self->{documentNodeName} };
	}
}

sub getTree {
	##
	# Get hash tree representation of parsed XML document
	##
	my $self = shift;

	return $self->{tree};
}

sub parsePINode {
	##
	# Parse Processor Instruction Node, e.g. <?xml version="1.0"?>
	##
	my ($self, $tag) = @_;
	
	if ($tag !~ m@^\s*\?\s*([\w\-\:]+)\s*(.*)$@os) {
		$self->throwParseError( "Malformed PI tag", $tag );
		return undef;
	}
	
	push @{$self->{piNodeList}}, $tag;
	return $tag;
}

sub parseCommentNode {
	##
	# Parse Comment Node, e.g. <!-- hello -->
	##
	my ($self, $tag) = @_;
	
	##
	# Check for nested nodes, and find actual closing tag.
	##
	while ($tag !~ /--$/) {
		if ($self->{text} =~ m@([^>]*?)>@sog) {
			$tag .= '>' . $1;
		} else {
			$self->throwParseError( "Unclosed comment tag", $tag, 
				length($self->{text}) - length($tag) );
			return undef;
		}
	}
	
	return $tag;
}

sub parseDTDNode {
	##
	# Parse Document Type Descriptor Node, e.g. <!DOCTYPE ... >
	##
	my ($self, $tag) = @_;
	
	##
	# Check for external reference tag first
	##
	if ($tag =~ m@^\s*\!DOCTYPE\s+([\w\-\:]+)\s+SYSTEM\s+\"([^\"]+)\"@) {
		push @{$self->{dtdNodeList}}, $tag;
	}
	elsif ($tag =~ m@^\s*\!DOCTYPE\s+([\w\-\:]+)\s+\[@) {
		##
		# Tag is inline, so check for nested nodes.
		##
		while ($tag !~ /\]$/) {
			if ($self->{text} =~ m@([^>]*?)>@sog) {
				$tag .= '>' . $1;
			} else {
				$self->throwParseError( "Unclosed DTD tag", $tag, 
					length($self->{text}) - length($tag) );
				return undef;
			}
		}
		
		##
		# Make sure complete tag is well-formed, and push onto DTD stack.
		##
		if ($tag =~ m@^\s*\!DOCTYPE\s+([\w\-\:]+)\s+\[(.*)\]@s) {
			push @{$self->{dtdNodeList}}, $tag;
		} else {
			$self->throwParseError( "Malformed DTD tag", $tag );
			return undef;
		}
	}
	else {
		$self->throwParseError( "Malformed DTD tag", $tag );
		return undef;
	}
	
	return $tag;
}

sub parseCDATANode {
	##
	# Parse CDATA Node, e.g. <![CDATA[Brooks & Shields]]>
	##
	my ($self, $tag) = @_;
	
	##
	# Check for nested nodes, and find actual closing tag.
	##
	while ($tag !~ /\]\]$/) {
		if ($self->{text} =~ m@([^>]*?)>@sog) {
			$tag .= '>' . $1;
		} else {
			$self->throwParseError( "Unclosed CDATA tag", $tag, 
				length($self->{text}) - length($tag) );
			return undef;
		}
	}
	
	if ($tag =~ m@^\s*\!\s*\[\s*CDATA\s*\[(.*)\]\]@s) {
		return $1;
	} else {
		$self->throwParseError( "Malformed CDATA tag", $tag );
		return undef;
	}
}

sub composeNode {
	##
	# Compose a single node into proper XML, and recurse into
	# child nodes.
	##
	my ($self, $name, $branch, $fh, $indent) = @_;
	my $eol = $self->{compress} ? "" : "\n";
	my $istr = $self->{compress} ? "" : ($self->{indentString} x $indent);
	
	##
	# If branch is a hash reference, create node and walk keys
	##
	if (isa($branch, 'HASH')) {
		##
		# Compose indentation and opening tag
		##
		$fh->print( $istr . "<$name");
		
		my $numKeys = scalar keys %{$branch};
		my $hasAttribs = 0;
		
		##
		# Compose attributes, if any
		##
		if (defined($branch->{_Attribs})) {
			$hasAttribs = 1;
			foreach my $key (sort keys %{$branch->{_Attribs}}) {
				$fh->print( " $key=\"" . $self->encodeAttribEntities($branch->{_Attribs}->{$key}) . "\"" );
			}
		}
		
		##
		# Walk keys if any exist
		##
		if ($numKeys > $hasAttribs) {
			$fh->print( '>' );
			
			if (defined($branch->{content})) {
				##
				# Simple text node
				##
				$fh->print( $self->encodeEntities($branch->{content}) . "</$name>$eol" );
			}
			else {
				$fh->print( "$eol" );
				
				##
				# Step through each key, recursively calling composeNode()
				##
				foreach my $key (sort keys %{$branch}) {
					if ($key ne '_Attribs') {
						$self->composeNode( $key, $branch->{$key}, $fh, $indent + 1 );
					}
				}
				
				##
				# Compose closing tag with indentation
				##
				$fh->print( $istr . "</$name>$eol");
			}
		}
		else {
			##
			# No sub elements or text content, so make this a self-closing tag.
			##
			$fh->print( "/>$eol" );
		}
	}
	elsif (ref($branch) eq "ARRAY") {
		##
		# If branch is an array, recursively call composeNode() for each element,
		# but pass the same indent value as we were given.
		##
		foreach my $node (@{$branch}) {
			$self->composeNode( $name, $node, $fh, $indent );
		}
	}
	else {
		##
		# Branch is neither a hash or array, so it must be a plain text node
		# with no attributes.
		##
		$fh->print( $istr . "<$name>" . $self->encodeEntities($branch) . "</$name>$eol" );
	}
}

sub compose {
	##
	# Recursively compose XML from hash tree.
	##
	my $self = shift;
	my $fh = shift || XML::Lite::ScalarHandle->new();
	my $eol = $self->{compress} ? "" : "\n";

	##
	# If argument was a scalar, treat as path and open FileHandle for writing
	##
	if (!ref($fh)) {
		$fh = new FileHandle ">$fh";
		if (!$fh) { return undef; }
	}
	
	##
	# First print XML PI Node and any DTD nodes from the original xml text
	##
	if (scalar @{$self->{piNodeList}} > 0) {
		foreach my $piNode (@{$self->{piNodeList}}) {
			$fh->print( "<$piNode>$eol" );
		}
	}
	else {
		$fh->print( qq{<?xml version="1.0"?>$eol} );
	}
	
	if (scalar @{$self->{dtdNodeList}} > 0) {
		foreach my $dtdNode (@{$self->{dtdNodeList}}) {
			$fh->print( "<$dtdNode>$eol" );
		}
	}
	
	##
	# Recursively compose all nodes
	##
	$self->composeNode( $self->{documentNodeName}, $self->{tree}, $fh, 0 );

	##
	# Return composed XML if running in scalar mode, or 1 for success
	##
	if (isa($fh, 'XML::Lite::ScalarHandle')) { return $fh->fetch(); }

	return 1;
}

sub save {
	##
	# Write XML back out to original file
	##
	my $self = shift;
	my $atomic = shift || 0;
	
	if ($atomic) {
		my $temp_file = $self->{file} . ".$$." . rand() . ".tmp";
		if (!$self->compose( $temp_file )) {
			return undef;
		}
		if (!rename( $temp_file, $self->{file} )) {
			unlink $temp_file;
			return undef;
		}
	}
	else {
		return $self->compose( $self->{file} );
	}
	
	return 1;
}

sub setDocumentNodeName {
	##
	# Set the root document node name for composing
	##
	my $self = shift;

	$self->{documentNodeName} = shift;
}

sub addDTDNode {
	##
	# Push a new DTD node onto end of stack.  This is only for composing.
	##
	my $self = shift;
	my $node = shift;

	$node =~ s/^<(.+)>/$1/; # strip opening and closing angle brackets
	push @{$self->{dtdNodeList}}, $node;
}

sub error {
	##
	# Returns number of errors that occured, 0 if none
	##
	my $self = shift;

	return scalar @{$self->{errors}};
}

sub getError {
	##
	# Get specified error formatted in plain text
	##
	my $self = shift;
	my $error = shift;
	my $text = '';

	if (!$error) { return ''; }

	$text = ucfirst( $error->{type} || 'general' ) . ' Error';
	if ($error->{code}) { $text .= ' ' . $error->{code}; }
	$text .= ': ' . $error->{key};
	
	if ($error->{line}) { $text .= ' on line ' . $error->{line}; }
	if ($error->{text}) { $text .= ': ' . $error->{text}; }

	return $text;
}

sub getLastError {
	##
	# Get most recently thrown error in plain text format
	##
	my $self = shift;

	if (!$self->error()) { return undef; }
	return $self->getError( $self->{errors}->[-1] );
}

sub printError {
	##
	# Format error in plain text and send to STDERR
	##
	my $self = shift;
	my $error = shift;
	my $text = $self->getError( $error );
	
	warn "$text\n";
}

sub throwError {
	##
	# Push new error onto stack
	##
	my $self = shift;
	my $args = {@_};
	
	$args->{text} ||= '';
	$args->{text} =~ s@^\s+@@s;
	if ($args->{text} =~ /\n/) {
		$args->{text} =~ s@^(.+?)\n.+$@$1...@s;
	}
	
	push @{$self->{errors}}, $args;
	if ($self->{printErrors}) { $self->printError( $args ); }
}

sub throwParseError {
	##
	# Throw new parse error, and track location in original text.
	##
	my $self = shift;
	my $key = shift;
	my $tag = shift;
	
	my $line_num = (substr($self->{text}, 0, shift || 
		pos($self->{text})) =~ tr/\n//) + 1;
	$line_num -= $tag =~ tr/\n//;
	
	$self->throwError(
		type => 'parse',
		key => $key, 
		text => '<' . $tag . '>', 
		line => $line_num
	);
}

sub decodeEntities {
	##
	# Convert encoded entities like &amp; to their literal equivalents
	##
	my $self = shift;
	my $text = shift;

	if ($text =~ /\&/) {
		$text =~ s/(\&\#(\d+)\;)/ chr($2); /esg;
		$text =~ s/(\&\#x([0-9A-Fa-f]+)\;)/ chr(hex($2)); /esg;
		$text =~ s/(\&(\w+)\;)/ $self->{entities}->{$2} || $1; /esg;
	}

	return $text;
}

sub encodeEntities {
	##
	# Encode <, >, & and high-ascii into XML entities
	# Does not include &apos; and &quot;
	##
	my $self = shift;
	my $text = shift;

	$text =~ s/\&/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
	# $text =~ s/([\x80-\xFF])/ '&#'.ord($1).';'; /eg;

	return $text;
}

sub encodeAttribEntities {
	##
	# Encode ALL entities (used for attributes),
	# including the optional &apos;, &quot; and high/low-ascii
	##
	my $self = shift;
	my $text = shift;

	$text =~ s/\&/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
	$text =~ s/\'/&apos;/g;
	$text =~ s/\"/&quot;/g;
	# $text =~ s/([\x80-\xFF\x00-\x1F])/ '&#'.ord($1).';'; /eg;

	return $text;
}

sub lookup {
	##
	# Run simple XPath query, supporting things like:
	#		/Simple/Path/Here
	#		/ServiceList/Service[2]/@Type
	#		/Parameter[@Name='UsePU2']/@Value
	# Return ref to hash/array, or scalar string
	##
	my ($self, $xpath, $tree) = @_;
	if (!$tree) { $tree = $self->{tree}; }
	
	my $ref = $self->lookup_ref( $xpath, $tree );
	if (defined($ref) && isa($ref, 'SCALAR')) { $ref = $$ref; } # dereference scalars
	return $ref;
}

sub set {
	##
	# Evaluate xpath and set target to supplied value
	# DOES NOT CREATE PARENT NODES
	# Target type (hash, array, scalar) must match supplied type
	##
	my ($self, $xpath, $value, $tree) = @_;
	if (!$tree) { $tree = $self->{tree}; }
	
	my $value_ref = $value;
	if (!ref($value_ref)) { $value_ref = \$value; }
	
	my $ref = $self->lookup_ref( $xpath, $tree );
	if (!defined($ref)) { return undef; } # lookup failed
	if (ref($ref) ne ref($value_ref)) { return undef; } # type mismatch
	
	if (isa($ref, 'HASH')) { %$ref = %$value_ref; }
	elsif (isa($ref, 'ARRAY')) { @$ref = @$value_ref; }
	elsif (isa($ref, 'SCALAR')) { $$ref = $$value_ref; }
	else { return undef; } # unsupported type
	
	return 1;
}

sub lookup_ref {
	##
	# Evaluate xpath query and return reference to node (even if scalar ref)
	##
	my ($self, $xpath, $tree) = @_;
	if (!$tree) { $tree = $self->{tree}; }
		
	while ($xpath =~ /^\/?([^\/]+)/) {
		my $matches = [undef, $1];
		if ($matches->[1] =~ /^([\w\-\:\.]+)\[([^\]]+)\]$/) {
			my $arr_matches = [undef, $1, $2];
			# array index lookup, possibly complex attribute match
			if (defined($tree->{$arr_matches->[1]})) {
				$tree = $tree->{$arr_matches->[1]};
				my $elements = $tree; if (!isa($tree, 'ARRAY')) { $elements = [$tree]; }
				
				if ($arr_matches->[2] =~ /^\d+$/) {
					# simple array index lookup, i.e. /Parameter[2]
					if (defined($elements->[$arr_matches->[2]])) {
						$tree = ref($elements->[$arr_matches->[2]]) ? $elements->[$arr_matches->[2]] : \$elements->[$arr_matches->[2]];
						$xpath =~ s/^\/?([^\/]+)//;
					}
					else {
						return undef;
					}
				}
				elsif ($arr_matches->[2] =~ /^\@([\w\-\:\.]+)\=\'([^\']*)\'$/) {
					my $sub_matches = [undef, $1, $2];
					# complex attrib search query, i.e. /Parameter[@Name='UsePU2']
					my $count = scalar @$elements;
					my $found = 0;

					for (my $k = 0; $k < $count; $k++) {
						my $elem = $elements->[$k];
						if (defined($elem->{$sub_matches->[1]}) && ($elem->{$sub_matches->[1]} eq $sub_matches->[2])) {
							$found = 1;
							$tree = ref($elem) ? $elem : \$elem;
							$k = $count;
						}
						elsif (defined($elem->{'_Attribs'}) && 
								defined($elem->{'_Attribs'}->{$sub_matches->[1]}) && 
								($elem->{'_Attribs'}->{$sub_matches->[1]} eq $sub_matches->[2])) {
							$found = 1;
							$tree = ref($elem) ? $elem : \$elem;
							$k = $count;
						}
					} # foreach element
					
					if ($found) { $xpath =~ s/^\/?([^\/]+)//; }
					else {
						return undef;
					}
				} # attrib search
			} # found basic element name
			else {
				return undef;
			}
		} # array index lookup
		elsif ($matches->[1] =~ /^\@([\w\-\:\.]+)$/) {
			my $sub_matches = [undef, $1];
			# attrib lookup
			if (defined($tree->{'_Attribs'})) { $tree = $tree->{'_Attribs'}; }
			if (defined($tree->{$sub_matches->[1]})) {
				$tree = ref($tree->{$sub_matches->[1]}) ? $tree->{$sub_matches->[1]} : \$tree->{$sub_matches->[1]};
				$xpath =~ s/^\/?([^\/]+)//;
			}
			else {
				return undef;
			}
		} # attrib lookup
		elsif (defined($tree->{$matches->[1]})) {
			$tree = ref($tree->{$matches->[1]}) ? $tree->{$matches->[1]} : \$tree->{$matches->[1]};
			$xpath =~ s/^\/?([^\/]+)//;
		} # simple element lookup
		else {
			return undef;
		} # bad xpath
	} # foreach xpath node

	return $tree;
}

package XML::Lite::ScalarHandle;

##
# Simple scalar accumulation class supporting print() and fetch() methods.
##

sub new {
	my $class = shift;
	return bless { text => shift || '' }, $class;
}

sub print {
	my $self = shift;
	$self->{text} .= shift || '';
}

sub fetch {
	my $self = shift;
	return $self->{text};
}

1;
