# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Validation module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#

package Fink::Validation;

use Fink::Services qw(&read_properties &read_properties_var &expand_percent &get_arch);
use Fink::Config qw($config);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&validate_info_file &validate_dpkg_file);
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

# Currently, the Set* and NoSet* fields only support a limited list of variables.
our @set_vars =
	qw(
		cc cflags cpp cppflags cxx cxxflags dyld_library_path
		ld_prebind ld_prebind_allow_overlap ld_force_no_prebind
		ld_seg_addr_table ld ldflags library_path libs
		macosx_deployment_target make mflags makeflags
	);

# Required fields.
our @required_fields =
	qw(Package Version Revision Maintainer);

# All fields that expect a boolean value
our %boolean_fields = map {$_, 1}
	(
		qw(builddependsonly essential nosourcedirectory updateconfigguess updatelibtool updatepod noperltests),
		map {"noset".$_} @set_vars
	);

# Obsolete fields, generate a warning
our %obsolete_fields = map {$_, 1}
	qw(comment commentport commenstow usegettext);

# Fields to check for hardcoded /sw
our %check_hardcode_fields = map {$_, 1}
	( 
		qw(
		 patchscript
		 configureparams
		 compilescript
		 installscript
		 shlibs
		 preinstscript
		 postinstscript
		 prermscript
		 postrmscript
		 conffiles
		 daemonicfile
		),
		(map {"set".$_} @set_vars)
	);

# Fields in which %n/%v can and should be used
our %name_version_fields = map {$_, 1}
	qw(
		 source sourcedirectory sourcerename
		 source0 source0extractdir source0rename
		 patch
		);

# Free-form text fields which display in 'fink describe'
our %text_describe_fields = map {$_, 1}
	qw(
		 descdetail descusage
		);

# Allowed values for the license field
our %allowed_license_values = map {$_, 1}
	(
	 "GPL", "LGPL", "GPL/LGPL", "BSD", "Artistic", "Artistic/GPL", "GFDL", 
	 "GPL/GFDL", "LGPL/GFDL", "GPL/LGPL/GFDL", "LDP", "GPL/LGPL/LDP", 
	 "OSI-Approved", "Public Domain", "Restrictive/Distributable", 
	 "Restrictive", "Commercial"
	);

# List of all valid fields, 
# sorted in the same order as in the packaging manual.
# (A few are handled elsewhere in this module, but are also included here,
#  commented out, for easier reference when comparing with the manual.)

our %valid_fields = map {$_, 1}
	(
		(
#  initial data:
		 'package',
		 'version',
		 'revision',
		 'epoch',
		 'description',
		 'type',
		 'license',
		 'maintainer',
		 'infon',  # set by handle_infon_block if InfoN: used
#  dependencies:
		 'depends',
		 'builddepends',
		  #  need documentation for buildconflicts
		 'buildconflicts',
		 'provides',
		 'conflicts',
		 'replaces',
		 'recommends',
		 'suggests',
		 'enhances',
		 'pre-depends',
		 'essential',
		 'builddependsonly',
#  unpack phase:
		 'custommirror',
		 'source',
		 #sourceN
		 'sourcedirectory',
		 'nosourcedirectory',
		 #sourceNextractdir
		 'sourcerename',
		 #sourceNRename
		 'source-md5',
		 #sourceN-md5
		 'tarfilesrename',
		 #tarNfilesrename
#  patch phase:
		 'updateconfigguess',
		 'updateconfigguessindirs',
		 'updatelibtool',
		 'updatelibtoolindirs',
		 'updatepomakefile',
		 'patch',
		 'patchscript'
#  compile phase:
		),
		(map {"set".$_} @set_vars),
		(map {"noset".$_} @set_vars),
		(
		 'configureparams',
		 'gcc',
		 'compilescript',
		 'noperltests',
#  install phase:
		 'updatepod',
		 'installscript',
		 'appbundles',
		 'jarfiles',
		 'docfiles',
		 'shlibs',
		 'runtimevars',
		 'splitoff',
		 #splitoffN
		 #files
#  build phase:
		 'preinstscript',
		 'postinstscript',
		 'prermscript',
		 'postrmscript',
		 'conffiles',
		 'infodocs',
		 'daemonicfile',
		 'daemonicname',
#  additional data:
		 'homepage',
		 'descdetail',
		 'descusage',
		 'descpackaging',
		 'descport'
		)
	);

# List of all fields which are legal in a splitoff
our %splitoff_valid_fields = map {$_, 1}
	(
		(
#  initial data:
		 'package',
		 'type',
		 'license',
#  dependencies:
		 'depends',
		 'provides',
		 'conflicts',
		 'replaces',
		 'recommends',
		 'suggests',
		 'enhances',
		 'pre-depends',
		 'essential',
		 'builddependsonly',
#  install phase:
		 'updatepod',
		 'installscript',
		 'jarfiles',
		 'docfiles',
		 'shlibs',
		 'runtimevars',
		 'files',
#  build phase:
		 'preinstscript',
		 'postinstscript',
		 'prermscript',
		 'postrmscript',
		 'conffiles',
		 'infodocs',
		 'daemonicfile',
		 'daemonicname',
#  additional data:
		 'homepage',
		 'description',
		 'descdetail',
		 'descusage',
		 'descpackaging',
		 'descport',
		)
	);



END { }				# module clean-up code here (global destructor)



# Should check/verifies the following in .info files:
#	+ the filename matches %f.info
#	+ patch file (from Patch and PatchScript) is present
#	+ all required fields are present
#	+ warn if obsolete fields are encountered
#	+ warn about missing Description/Maintainer/License fields
#	+ warn about overlong Description fields
#	+ warn about Description starting with "A" or "An" or containing the package name
#	+ warn if boolean fields contain bogus values
#	+ warn if fields seem to contain the package name/version, and suggest %n/%v should be used
#		(excluded from this are fields like Description, Homepage etc.)
#	+ warn if unknown fields are encountered
#	+ warn if /sw is hardcoded in the script or set fields or patch file
#		(from Patch and PatchScript)
#	+ correspondence between source* and source*-md5 fields
#	+ if type is bundle/nosource - warn about usage of "Source" etc.
#	+ if 'fink describe' output will display poorly on vt100
#	+ Check Package/Version/Revision for disallowed characters
#	+ Check if have sufficient InfoN if using their features
#   + Warn if shbang in dpkg install-time scripts
#   + Error if %i used in dpkg install-time scripts
#   + Warn if non-ASCII chars in any field
#
# TODO: Optionally, should sort the fields to the recommended field order
#	- better validation of splitoffs
#	- validate dependencies, e.g. "foo (> 1.0-1)" should generate an error since
#	  it uses ">" instead of ">>".
#	- correct format of Shlibs: (including misuse of %v-%r)
#	- use of %n in SplitOff:Package: (should be %N)
#	- use of SplitOff:Depends: %n (should be %N (tracker Bugs #622810)
#	- actually instantiate the Package or PkgVersion object
#	  (easier to try it than to check for some broken-ness here)
#	- run a mock build phase (catch typos in dependencies,
#	  BuildDependsOnly violations, etc.)
#	- make sure for each %type_*[foo] there is a Type: foo
#	- ... other things, make suggestions ;)
#
sub validate_info_file {
	my $filename = shift;
	my $val_prefix = shift;
	my ($properties, @parts);
	my ($pkgname, $pkginvarname, $pkgversion, $pkgrevision, $pkgfullname, $pkgdestdir, $pkgpatchpath, @patchfiles);
	my ($field, $value);
	my ($basepath, $buildpath);
	my ($type, $type_hash);
	my $expand = {};
	my $looks_good = 1;
	my $error_found = 0;
	my $arch = get_arch();

	if (Fink::Config::verbosity_level() >= 3) {
		print "Validating package file $filename...\n";
	}
	
	#
	# Check for line endings before reading properties
	#
	open(INPUT, "<$filename") or die "Couldn't read $filename: $!\n";
	my $info_file_content = <INPUT>;
	close INPUT or die "Couldn't read $filename: $!\n";
	if ($info_file_content =~ m/\r\n/s) {
		print "Error: Info file has DOS line endings. ($filename)\n";
		$looks_good = 0;
	}
	return unless ($looks_good);
	if ($info_file_content =~ m/\r/s) {
		print "Error: Info file has Mac line endings. ($filename)\n";
		$looks_good = 0;
	}
	return unless ($looks_good);

	# read the file properties
	$properties = &read_properties($filename);
	$properties = Fink::Package->handle_infon_block($properties, $filename);
	return unless keys %$properties;
	
	# determine the base path
	if (defined $val_prefix) {
		$basepath = $val_prefix;
		$buildpath = "$basepath/src";
	} else {
		$basepath = $config->param_default("basepath", "/sw");
		$buildpath = $config->param_default("buildpath", "$basepath/src");
	}

	# make sure have InfoN (N>=2) if use Info2 features
	if (($properties->{infon} || 1) < 2) {
		# fink-0.16.1 can't even index if unknown %-exp in *any* field!
		foreach (sort keys %$properties) {
			next if /^splitoff\d*$/;  # SplitOffs checked later
			if ($properties->{$_} =~ /\%type_(raw|pkg)\[.*?\]/) {
				print "Error: Use of %type_ expansions (field \"$_\") requires InfoN level 2 or higher. ($filename)\n";
				$looks_good = 0;
				return;
			}
		}
	}

	( $pkginvarname = $pkgname = $properties->{package} ) =~ s/\%type_(raw|pkg)\[.*?\]//g;
	# right now we don't know how to deal with variants too well
	if (defined ($type = $properties->{type}) ) {
		$type =~ s/(\S+?)\s*\(:?.*?\)/$1 ./g;  # use . for all subtype lists
		$type_hash = Fink::PkgVersion->type_hash_from_string($type,$filename);
		foreach (keys %$type_hash) {
			( $expand->{"type_pkg[$_]"} = $expand->{"type_raw[$_]"} = $type_hash->{$_} ) =~ s/\.//g;
		}
		$pkgname = &expand_percent($pkgname, $expand, $filename.' Package');
	}

	$pkgversion = $properties->{version};
	$pkgversion = '' unless defined $pkgversion;
	$pkgrevision = $properties->{revision};
	$pkgrevision = '' unless defined $pkgrevision;
	$pkgfullname = "$pkgname-$pkgversion-$pkgrevision";
	$pkgdestdir = "$buildpath/root-".$pkgfullname;
	
	@parts = split(/\//, $filename);
	$filename = pop @parts;		# remove filename
	$pkgpatchpath = join("/", @parts);

	#
	# First check for critical errors
	#

	if ($pkgname =~ /[^+\-.a-z0-9]/) {
		print "Error: Package name may only contain lowercase letters, numbers,";
		print "'.', '+' and '-' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgversion =~ /[^+\-.a-z0-9]/) {
		print "Error: Package version may only contain lowercase letters, numbers,";
		print "'.', '+' and '-' ($filename)\n";
		$looks_good = 0;
	}
	if ($pkgrevision =~ /[^+.a-z0-9]/) {
		print "Error: Package revision may only contain lowercase letters, numbers,";
		print "'.' and '+' ($filename)\n";
		$looks_good = 0;
	}
	
	# TODO: figure out how to validate multivariant Type:
	#  - make sure syntax is okay
	#  - make sure each type appears as a type_*[] in Package

	return unless ($looks_good);

	#
	# Now check for other mistakes
	#

	# variants with Package: foo-%type[bar] leave escess hyphens
	my @ok_filenames = $pkgname;
	$ok_filenames[0] =~ s/-+/-/g;
	$ok_filenames[0] =~ s/-*$//g;
	$ok_filenames[1] = "$ok_filenames[0]-$pkgversion-$pkgrevision";
	map $_ .= ".info", @ok_filenames;

	unless (1 == grep $filename eq $_, @ok_filenames) {
		print "Warning: File name should be ", join( " or ", @ok_filenames ),"\n";
		$looks_good = 0;
	}
	
	# Make sure Maintainer is in the correct format: Joe Bob <jbob@foo.com>
	$value = $properties->{maintainer};
	if ($value !~ /^[^<>@]+\s+<\S+\@\S+>$/) {
		print "Warning: Malformed value for \"maintainer\". ($filename)\n";
		$looks_good = 0;
	}

	# License should always be specified, and must be one of the allowed set
	$value = $properties->{license};
	if ($value) {
		if (not $allowed_license_values{$value}) {
			print "Warning: Unknown license \"$value\". ($filename)\n";
			$looks_good = 0;
		}
	} elsif (not (defined($properties->{type}) and $properties->{type} =~ /\bbundle\b/i)) {
		print "Warning: No license specified. ($filename)\n";
		$looks_good = 0;
	}

	# check SourceN and corresponding fields

	# find them all
	my %source_fields = map { lc $_, 1 } grep { /^Source(|[2-9]|[1-9]\d+)$/i } keys %$properties;

	# have Source or SourceN when we shouldn't
	if (exists $properties->{type} and $properties->{type} =~ /\b(nosource|bundle)\b/i) {
		if (keys %source_fields) {
			print "Warning: Source and/or SourceN field(s) found for \"Type: $1\". ($filename)\n";
			$looks_good = 0;
		}
	} else {
		if (!exists $source_fields{source}) {
			print "Warning: the implicit \"Source\" feature is deprecated and will be removed soon.\nAdd \"Source: %n-%v.tar.gz\" to assure future compatibility. ($filename)\n";
			$looks_good = 0;
		}
		$source_fields{source} = 1;  # always have Source (could be implicit)
	}
	if (exists $properties->{source} and $properties->{source} =~ /^none$/i and keys %source_fields > 1) {
		print "Error: \"Source: none\" but found SourceN field(s). ($filename)\n";
		$looks_good = 0;
	}

	# check for bogus "none" sources and sources without MD5
	# remove "none" from %source_fields (will use in main field loop)
	foreach (keys %source_fields) {
		if (exists $properties->{$_} and $properties->{$_} =~ /^none$/i) {
			delete $source_fields{$_};  # keep just real ones
			if (/\d+/) {
				print "Warning: \"$_: none\" is a no-op. ($filename)\n";
				$looks_good = 0;
			}
		} else {
			my $md5_field = $_ . "-md5";
			if (!exists $properties->{$md5_field} and !defined $properties->{$md5_field}) {
				print "Error: \"$_\" does not have a corresponding \"$md5_field\" field. ($filename)\n";
				$ looks_good = 0;
			}
		}
		
	}

	if (&validate_info_component($properties, "", $filename) == 0) {
		$looks_good = 0;
	}

	# Loop over all fields and verify them
	foreach $field (keys %$properties) {
		$value = $properties->{$field};

		# Warn if field is obsolete
		if ($obsolete_fields{$field}) {
			print "Warning: Field \"$field\" is obsolete. ($filename)\n";
			$looks_good = 0;
			next;
		}

		# Boolean field?
		if ($boolean_fields{$field} and not ((lc $value) =~ /^\s*(true|yes|on|1|false|no|off|0)\s*$/)) {
			print "Warning: Boolean field \"$field\" contains suspicious value \"$value\". ($filename)\n";
			$looks_good = 0;
			next;
		}

		# If this field permits percent expansion, check if %f/%n/%v should be used
		if ($name_version_fields{$field} and $value) {
			 if ($value =~ /\b\Q$pkgfullname\E\b/) {
				 print "Warning: Field \"$field\" contains full package name. Use %f instead. ($filename)\n";
				 $looks_good = 0;
			 } elsif ($value =~ /\b\Q$pkgversion\E\b/) {
				 print "Warning: Field \"$field\" contains package version. Use %v instead. ($filename)\n";
				 $looks_good = 0;
			 }
		}

		# these fields are printed verbatim, so check to make sure
		# they won't look weird on an 80-column plain-text terminal
		if (Fink::Config::verbosity_level() > 3 and $text_describe_fields{$field} and $value) {
			# no intelligent word-wrap so warn for long lines
			my $maxlinelen = 79;
			foreach my $line (split /\n/, $value) {
				if (length $line > $maxlinelen) {
					print "Warning: \"$field\" contains line(s) exceeding $maxlinelen characters. ($filename)\nThis field may be displayed with line-breaks in the middle of words.\n";
					$looks_good = 0;
					next;
				}
			}
		}

		# Check for any source-related field without associated Source(N) field
		if ($field =~ /^Source(\d*)-MD5|Source(\d*)Rename|Tar(\d*)FilesRename|Source(\d+)ExtractDir$/i) {
			my $sourcefield = defined $+  # corresponding Source(N) field
				? "source$+"
				: "source";  
			if (!exists $source_fields{$sourcefield}) {
				my $msg = $field =~ /-MD5$/i
					? "Warning" # no big deal
					: "Error";  # probably means typo, giving broken behavior
					print "$msg: \"$field\" specified for non-existent \"$sourcefield\". ($filename)\n";
					$looks_good = 0;
				}
			next;
		}

		# Validate splitoffs
		if ($field =~ m/^splitoff([2-9]|[1-9]\d+)?$/) {
			# Parse the splitoff properties
			my $splitoff_properties = $properties->{$field};
			my $splitoff_field = $field;
			$splitoff_properties =~ s/^\s+//gm;
			$splitoff_properties = &read_properties_var("$field of \"$filename\"", $splitoff_properties);

			# make sure have InfoN (N>=2) if use Info2 features
			if (($properties->{infon} || 1) < 2) {
				# fink-0.16.1 can't even index if unknown %-exp in *any* field!
				foreach (sort keys %$splitoff_properties) {
					if ($splitoff_properties->{$_} =~ /\%type_(raw|pkg)\[.*?\]/) {
						print "Error: Use of %type_ expansions (field \"$_\" of \"$field\") requires InfoN level 2 or higher. ($filename)\n";
						$looks_good = 0;
						return;
					}
				}
			}

			if (&validate_info_component($splitoff_properties, $splitoff_field, $filename) == 0) {
				$looks_good = 0;
			}

			if (exists $splitoff_properties->{shlibs}) {
				my @shlibs = split /\n/, $splitoff_properties->{shlibs};
				chomp @shlibs;
				my %shlibs;
				foreach (@shlibs) {
					my @shlibs_parts;
					if (scalar(@shlibs_parts = split ' ', $_, 3) != 3) {
						print "Warning: Malformed line in field \"shlibs\" of \"$field\". ($filename)\n  $_\n";
						$looks_good = 0;
						next;
					}
					if (not /^(\%p)?\//) {
						print "Warning: Pathname \"$shlibs_parts[0]\" is not absolute and is not in \%p in field \"shlibs\" of \"$field\". ($filename)\n";
						$looks_good = 0;
					}
					if ($shlibs{$shlibs_parts[0]}++) {
						print "Warning: File \"$shlibs_parts[0]\" is listed more than once in field \"shlibs\" of \"$field\". ($filename)\n";
						$looks_good = 0;
					}
					if (not $shlibs_parts[1] =~ /^\d+\.\d+\.\d+$/) {
						print "Warning: Malformed compatibility_version for \"$shlibs_parts[0]\" in field \"shlibs\" of \"$field\". ($filename)\n";
						$looks_good = 0;
					}
					my @shlib_deps = split /\s*\|\s*/, $shlibs_parts[2], -1;
					foreach (@shlib_deps) {
						if (not /^[a-z%]\S*\s+\(>=\s*(\S+-\S+)\)$/) {
							print "Warning: Malformed dependency \"$_\" for \"$shlibs_parts[0]\" in field \"shlibs\" of \"$field\". ($filename)\n";
							$looks_good = 0;
							next;
						}
						my $shlib_dep_vers = $1;
						if ($shlib_dep_vers =~ /\%/) {
							print "Warning: Non-hardcoded version in dependency \"$_\" for \"$shlibs_parts[0]\" in field \"shlibs\" of \"$field\". ($filename)\n";
							$looks_good = 0;
							next;
						}
					}
				}
			}

			if (defined ($value = $splitoff_properties->{files})) {
				if ($value =~ /\/[\s\r\n]/ or $value =~ /\/$/) {
					print "Warning: Field \"files\" of \"$splitoff_field\" contains entries that end in \"/\" ($filename)\n";
					$looks_good = 0;
				}
			}
		} # end of SplitOff field validation
	}

	# Warn for missing / overlong package descriptions
	$value = $properties->{description};
	if (not (defined $value and length $value)) {
		print "Error: No package description supplied. ($filename)\n";
		$looks_good = 0;
	} elsif (length($value) > 60) {
		print "Error: Length of package description exceeds 60 characters. ($filename)\n";
		$looks_good = 0;
	} elsif (Fink::Config::verbosity_level() > 3) {
		# Some pedantic checks
		if (length($value) > 45) {
			print "Warning: Length of package description exceeds 45 characters. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/^[Aa]n? /) {
			print "Warning: Description starts with \"A\" or \"An\". ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/^[a-z]/) {
			print "Warning: Description starts with lower case. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ /\b\Q$pkgname\E\b/i) {
			print "Warning: Description contains package name. ($filename)\n";
			$looks_good = 0;
		}
		if ($value =~ m/\.$/) {
			print "Warning: Description ends with \".\". ($filename)\n";
			$looks_good = 0;
		}
	}
	
	$expand = { 'n' => $pkgname,
				'v' => $pkgversion,
				'r' => $pkgrevision,
				'f' => $pkgfullname,
				'p' => $basepath, 'P' => $basepath,
				'd' => $pkgdestdir,
				'i' => $pkgdestdir.$basepath,
				'a' => $pkgpatchpath,
				'b' => '.',
				'm' => $arch,
				%{$expand},
				'ni' => $pkginvarname,
				'Ni' => $pkginvarname
	};

	# Verify the patch file(s) exist and check some things
	@patchfiles = ();
	# anything in PatchScript that looks like a patch file name
	# (i.e., strings matching the glob %a/*.patch)
	$value = $properties->{patchscript};
	if ($value) {
		@patchfiles = ($value =~ /\%a\/.*?\.patch/g);
		# strip directory if info is simple filename (in $PWD)
		map {s/\%a\///} @patchfiles unless $pkgpatchpath;
	}

	# the contents if Patch (if any)
	$value = $properties->{patch};
	if ($value) {
		# add directory if info is not simple filename (not in $PWD)
		$value = "\%a/" .$value if $pkgpatchpath;
		unshift @patchfiles, $value;
	}

	# now check each one in turn
	foreach $value (@patchfiles) {
		$value = &expand_percent($value, $expand, $filename.' Patch');
		unless (-f $value) {
			print "Error: can't find patchfile \"$value\"\n";
			$looks_good = 0;
		}
		else {
			# Check patch file
			open(INPUT, "<$value") or die "Couldn't read $value: $!\n";
			my $patch_file_content = <INPUT>;
			close INPUT or die "Couldn't read $value: $!\n";
			# Check for empty patch file
			if (!$patch_file_content) {
				print "Warning: Patch file is empty. ($value)\n";
				$looks_good = 0;
			}
			# Check for line endings of patch file
			elsif ($patch_file_content =~ m/\r\n/s) {
				print "Error: Patch file has DOS line endings. ($value)\n";
				$looks_good = 0;
			}
			elsif ($patch_file_content =~ m/\r/s) {
				print "Error: Patch file has Mac line endings. ($value)\n";
				$looks_good = 0;
			}
			# Check for hardcoded /sw.
			open(INPUT, "<$value") or die "Couldn't read $value: $!\n";
			while (defined($patch_file_content=<INPUT>)) {
				# only check lines being added (and skip diff header line)
				next unless $patch_file_content =~ /^\+(?!\+\+ )/;
				if ($patch_file_content =~ /\/sw([\s\/]|\Z)/) {
					print "Warning: Patch file appears to contain a hardcoded /sw. ($value)\n";
					$looks_good = 0;
					last;
				}
			}
			close INPUT or die "Couldn't read $value: $!\n";
		}
	}
	
	if ($looks_good and Fink::Config::verbosity_level() >= 3) {
		print "Package looks good!\n";
	}
}

# checks that are common to a parent and a splitoff package of a .info file
# returns boolean of whether everything is okay
sub validate_info_component {
	my $properties = shift;      # hashref (will not be altered)
	my $splitoff_field = shift;  # "splitoffN", or null or undef in parent
	my $filename = shift;

	my (@pkg_required_fields, %pkg_valid_fields);

	my $is_splitoff = 0;
	$splitoff_field = "" unless defined $splitoff_field;
	if (defined $splitoff_field && length $splitoff_field) {
		$is_splitoff = 1;
		$splitoff_field = sprintf ' of "%s"', $splitoff_field;
		@pkg_required_fields = qw(package);
		%pkg_valid_fields = %splitoff_valid_fields;
	} else {
		@pkg_required_fields = @required_fields;
		%pkg_valid_fields = %valid_fields;
	}		

	my ($field, $value);
	my $looks_good = 1;

	### field-specific checks

	# Verify that all required fields are present
	foreach $field (@pkg_required_fields) {
		unless (exists $properties->{lc $field}) {
			print "Error: Required field \"$field\"$splitoff_field missing. ($filename)\n";
			$looks_good = 0;
		}
	}

	# dpkg install-time script stuff
	foreach $field (qw/preinstscript postinstscript preinstrm postinstrm/) {
		next unless defined ($value = $properties->{$field});

		# A #! line is worthless
		if ($value =~ /^\s*\#!/) {
			print "Warning: Useless use of explicit interpretter in \"$field\"$splitoff_field. ($filename)\n";
			$looks_good = 0;
		}

		# must operate on %p not %i
		if ($value =~ /\%i\//) {
			print "Error: Use of \%i in field \"$field\"$splitoff_field. ($filename)\n";
			$looks_good = 0;
		}
	}

	### checks that apply to all fields

	foreach $field (keys %$properties) {
		next if $field =~ /^splitoff/;   # we don't do recursive stuff here
		$value = $properties->{$field};

		# Check for hardcoded /sw
		if ($check_hardcode_fields{$field} and $value =~ /\/sw([\s\/]|\Z)/) {
			print "Warning: Field \"$field\"$splitoff_field appears to contain a hardcoded /sw. ($filename)\n";
			$looks_good = 0;
		}

		# Check for %p/src
		if ($value =~ /\%p\\?\/src\\?\//) {
			print "Warning: Field \"$field\"$splitoff_field appears to contain \%p/src. ($filename)\n";
			$looks_good = 0;
		}

		# warn for non-plain-text chars
		if ($value =~ /[^[:ascii:]]/) {
			print "Warning: \"$field\"$splitoff_field contains non-standard characters. ($filename)\n";
			$looks_good = 0;
		}

		# Warn if field is unknown
		unless ($pkg_valid_fields{$field}) {
			unless (!$is_splitoff and
					( $field =~ m/^source([2-9]|[1-9]\d+)(|extractdir|rename|-md5)$/
					  or $field =~ m/^tar([2-9]|[1-9]\d+)filesrename$/
					  ) ) {
				print "Warning: Field \"$field\"$splitoff_field is unknown. ($filename)\n";
				$looks_good = 0;
			}
		}
	}

	return $looks_good;
}

#
# Check a given .deb file for standard compliance
#
# - usage of non-recommended directories (/sw/src, /sw/man, /sw/info, /sw/doc, /sw/libexec, /sw/lib/locale)
# - usage of other non-standard subdirs 
# - storage of a .bundle inside /sw/lib/perl5/darwin or /sw/lib/perl5/auto
# - Emacs packages
#     - installation of .elc files
#     - (it's now OK to install files directly into
#        /sw/share/emacs/site-lisp, so we no longer check for this)
# - BuildDependsOnly: if package stores files in /sw/include, it should
#     declare BuildDependsOnly true
# - Check presence and execute-flag on executable specified in daemonicfile
# - If a package contains a daemonicfile, it should Depends:daemonic
# - Check for symptoms of running update-scrollkeeper during package building
# - If a package has .omf sources, it should call update-scrollkeeper during Post(Inst,Rm}Script
# - If a package Post{Inst,Rm}Script calls update-scrollkeeper, it should Depends:scrollkeeper

# - ideas?
#
sub validate_dpkg_file {
	my $dpkg_filename = shift;
	my $val_prefix = shift;

	my ($basepath, $buildpath);
	# determine the base path
	if (defined $val_prefix) {
		$basepath = $val_prefix;
		$buildpath = "$basepath/src";
	} else {
		$basepath = $config->param_default("basepath", "/sw");
		$buildpath = $config->param_default("buildpath", "$basepath/src");
	}

	# these are used in a regex and are automatically prepended with ^
	# make sure to protect regex metachars!
	my @bad_dirs = ("$basepath/src/", "$basepath/man/", "$basepath/info/", "$basepath/doc/", "$basepath/libexec/", "$basepath/lib/locale/", ".*/CVS/", ".*/RCS/");
	my @good_dirs = ( map "$basepath/$_", qw/ bin sbin include lib share var etc src Applications / );

	my ($pid, @found_bad_dir);
	my $filename;
	my $looks_good = 1;
	my $installed_headers = 0;
	my $installed_dylibs = 0;
	my $scrollkeeper_misuse_warned = 0;
	my $deb_control;

	print "Validating .deb file $dpkg_filename...\n";

	# Quick & Dirty solution!!!
	# This is a potential security risk, we should maybe filter $dpkg_filename...

	# read some fields from the control file
	{
	my @deb_control_fields = qw/ builddependsonly package depends version source/;
	$deb_control = { map {$_, 1} (@deb_control_fields) };
	foreach (`dpkg --field $dpkg_filename @deb_control_fields`) {
		/^([^:]*): (.*)/;
		$deb_control->{lc $1} = $2;
	}
	}
	my $pkgbuilddir = sprintf '%s/%s-%s/', map { qr{\Q$_\E} } $buildpath, $deb_control->{source}, $deb_control->{version};
	my $pkginstdirs = sprintf '%s/root-(?:%s|%s)-%s/', map { qr{\Q$_\E} } $buildpath, $deb_control->{source}, $deb_control->{package}, $deb_control->{version};

	# read some control script files
	foreach (qw/ preinst postinst prerm postrm /) {
		$deb_control->{$_} = [ `dpkg -I $dpkg_filename $_ 2>/dev/null` ];
#		print "control file $_:\n", @{$deb_control->{$_}};
#		print "control file $_:\n", map { /^\s*scrollkeeper-update/ ? "+$_" : "-$_" } @{$deb_control->{$_}};
	}

	# create hash where keys are names of packages listed in Depends
	$deb_control->{depends_pkgs} = {
		map { /\s*([^ \(]*)/, undef } split /[|,]/, $deb_control->{depends}
	};

	$pid = open(DPKG_CONTENTS, "dpkg --contents $dpkg_filename |") or die "Couldn't run dpkg: $!\n";
	my @dpkg_contents = <DPKG_CONTENTS>;
	close(DPKG_CONTENTS) or die "Error on close: ", $?>>8, " $!\n";

	foreach (@dpkg_contents) {
		# process
		if (/([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*([^\s]*)\s*\.([^\s]*)/) {
			$filename = $6;
			#print "$filename\n";
			next if "$basepath/" =~ /^\Q$filename\E/;  # skip parent components of basepath hierarchy
			if (not $filename =~ /^$basepath/) {
				if (($filename =~ /^\/etc/) || ($filename =~ /^\/tmp/) || ($filename =~ /^\/var/)) {
					print "Error: File \"$filename\" is overwriting essential system symlink pointing to /private/...\n";
					$looks_good = 0;
				} elsif ($filename =~ /^\/mach/) {
					print "Error: File \"$filename\" is overwriting essential system symlink pointing to /mach.sym\n";
					$looks_good = 0;
				} elsif (not (($dpkg_filename =~ /xfree86[_\-]/) || ($dpkg_filename =~ /xorg[_\-]/))) {
					print "Warning: File \"$filename\" installed outside of $basepath\n";
					$looks_good = 0;
				} else {
					if (not (($filename =~ /^\/Applications\/XDarwin.app/) || ($filename =~ /^\/usr\/X11R6/) || ($filename =~ /^\/private\/etc\/fonts/) )) {
						next if (($filename eq "/Applications/") || ($filename eq "/private/") || ($filename eq "/private/etc/") || ($filename eq "/usr/"));
						print "Warning: File \"$filename\" installed outside of $basepath, /Applications/XDarwin.app, /private/etc/fonts, and /usr/X11R6\n";
						$looks_good = 0;
					}
				}
			} elsif ($filename ne "$basepath/src/" and @found_bad_dir = grep { $filename =~ /^$_/ } @bad_dirs) {
				# Directory from this list are not allowed to exist in the .deb.
				# The only exception is $basepath/src which may exist but must be empty
				print "Warning: File installed into deprecated directory $found_bad_dir[0]\n";
				print "					Offender is $filename\n";
				$looks_good = 0;
			} elsif (not grep { $filename =~ /^$_/ } @good_dirs) {
				# Directory from this list are the top-level dirs that may exist in the .deb.
				print "Warning: File \"$filename\" installed outside of allowable subdirectories of $basepath\n";
				$looks_good = 0;
			} elsif ($filename =~/^($basepath\/lib\/perl5\/auto\/.*\.bundle)/ ) {
				print "Warning: Apparent perl XS module installed directly into $basepath/lib/perl5 instead of a versioned subdirectory.\n  Offending file: $1\n";
				$looks_good = 0;
			} elsif ( $filename =~/^($basepath\/lib\/perl5\/darwin\/.*\.bundle)/ ) {
				print "Warning: Apparent perl XS module installed directly into $basepath/lib/perl5 instead of a versioned subdirectory.\n  Offending file: $1\n";
				$looks_good = 0;
			} elsif ( ($filename =~/^($basepath\/.*\.elc)$/) &&
				  (not (($dpkg_filename =~ /emacs[0-9][0-9][_\-]/) ||
					($dpkg_filename =~ /xemacs[_\-]/)))) {
				$looks_good = 0;
				print "Warning: Compiled .elc file installed. Package should install .el files, and provide a /sw/lib/emacsen-common/packages/install/<package> script that byte compiles them for each installed Emacs flavour.\n  Offending file: $1\n";
			} elsif ( $filename =~/^$basepath\/include\S*[^\/]$/ ) {
				$installed_headers = 1;
 			} elsif ( $filename =~/\.dylib$/ ) {
 				$installed_dylibs = 1;
			} elsif ( $filename =~/^$basepath\/share\/omf\/.*\.omf/ ) {
				foreach (qw/ postinst postrm /) {
					next if $_ eq "postrm" && $deb_control->{package} eq "scrollkeeper"; # circular dep
					if (not grep { /^\s*scrollkeeper-update/ } @{$deb_control->{$_}}) {
						print "Warning: scrollkeeper source file found, but scrollkeeper-update not called\nin $_. See scrollkeeper package docs for information. Offending file:\n  $filename\n";
						$looks_good = 0;
					}
				}
			} elsif ( $filename =~ /^$basepath\/etc\/daemons\/\S+$/ ) {
				if (not exists $deb_control->{depends_pkgs}->{daemonic}) {
					print "Warning: Package appears to contain a daemonicfile but does not depend on the package \"daemonic\"\n  Offending file: $filename\n";
					$looks_good = 0;
				}
				my $daemonicfile = ".$filename";
				open(DAEMONIC_FILE, "dpkg --fsys-tarfile $dpkg_filename | tar -xf - -O $daemonicfile |") or die "Couldn't run dpkg: $!\n";
				while (<DAEMONIC_FILE>) {
					if (/^\s*<executable.*?>(\S+)<\/executable>\s*$/) {
						my $executable = $1;
						my $perms;
						map { /^(\S+)/; $perms .= $1 } grep /\s+\.$executable$/, @dpkg_contents;
						if (defined $perms) {
							if ($perms =~ /^-..([xs-])......$/) {
								if ($1 eq '-') {
									print "Error: daemonicfile executable \"$executable\" in this .deb does not have execute permissions. ($dpkg_filename)\n";
									$looks_good = 0;
								}
							} else {
								print "Warning: got confused by permissions \"$perms\" for daemonicfile executable in .deb. ($dpkg_filename)\n";
								$looks_good = 0;
							}
						} else {
							if (not -e $executable) {
								print "Warning: daemonicfile executable \"$executable\" does not exist. ($dpkg_filename)\n";
								$looks_good = 0;
							} elsif (not -x $executable) {
								print "Warning: daemonicfile executable \"$executable\" does not have execute permissions. ($dpkg_filename)\n";
								$looks_good = 0;
							}
						}
					}
				}
				close(DAEMONIC_FILE) or die "Error on close: ", $?>>8, " $!\n";
			} elsif ( $filename =~ /^$basepath\/var\/scrollkeeper/ ) {
				if (not $scrollkeeper_misuse_warned++) {
					print "Warning: Found $basepath/var/scrollkeeper, which usually results from calling\nscrollkeeper-update during CompileScript or InstallScript. See the\nscrollkeeper package docs for information on the correct use of that utility.\n";
					$looks_good = 0;
				}
			}
			if ( $filename =~/\.la$/ ) {
				open(LA_FILE, "dpkg --fsys-tarfile $dpkg_filename | tar -xf - -O .$filename |") or die "Couldn't run dpkg: $!\n";
				while (<LA_FILE>) {
					if (/$pkgbuilddir/) {
						print "Warning: libtool file $filename points to fink build dir. ($dpkg_filename)\n";
						$looks_good = 0;
					} elsif (/$pkginstdirs/) {
						print "Warning: libtool file $filename points to fink install dir. ($dpkg_filename)\n";
						$looks_good = 0;
					}
				}
				close(LA_FILE) or die "Error on close: ", $?>>8, " $!\n";
			}
		}
	}

# Note that if the .deb was compiled with an old version of fink which
# does not record the BuildDependsOnly field, or with an old version
# which did not use the "Undefined" value for the BuildDependsOnly field,
# the warning is not issued

	if ($installed_headers and $installed_dylibs) {
		if ($deb_control->{builddependsonly} =~ /Undefined/) {
			print "Warning: Headers installed in $basepath/include, as well as a dylib, but package does not declare BuildDependsOnly to be true (or false)\n";
			$looks_good = 0;
		}
	}

	# verify Depends:scrollkeeper
	foreach (qw/ preinst postinst prerm postrm /) {
		next if $deb_control->{package} eq "scrollkeeper"; # circular dep
		if ( grep { /^\s*scrollkeeper-update/ } @{$deb_control->{$_}} and not exists $deb_control->{depends_pkgs}->{scrollkeeper}) {
			print "Warning: Calling scrollkeeper-update in $_ requires \"Depends:scrollkeeper\"\n";
			$looks_good = 0;
		}
	}

	# scrollkeeper-update should be called from PostInstScript and PostRmScript
	foreach (qw/ preinst prerm /) {
		if (grep { /^\s*scrollkeeper-update/ } @{$deb_control->{$_}}) {
			print "Warning: scrollkeeper-update in $_ is a no-op\nSee scrollkeeper package docs for information.\n";
			$looks_good = 0;
		}
	}

	if ($looks_good and Fink::Config::verbosity_level() >= 3) {
		print "Package looks good!\n";
	}
}


### EOF
1;
