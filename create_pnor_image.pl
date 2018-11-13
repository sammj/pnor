#!/usr/bin/perl

use strict;
use File::Basename;
use XML::Simple;
use Getopt::Long;
use Pod::Usage;

my $program_name = File::Basename::basename $0;

# Mandatory arguments
my $release;
my $outdir;
my $scratch_dir; # mayyyybe, probably not needed if we pull from hb_image_dir etc
my $pnor_data_dir;
my $pnor_filename;
my $hb_image_dir;
my $xml_layout_file;
my $payload;
my $bootkernel;
my $occ_binary_filename;
my $sbe_binary_filename;
my $targeting_binary_filename;
my $hcode_file;
my $hbbl_file;
my $openpower_version_filename;

# Platform dependent arguments
# P9
my $hdat_binary_filename;
my $wofdata_binary_filename;
my $memddata_binary_filename;
# P8
my $sbec_binary_filename = "";
my $wink_binary_filename = "";

# Optional arguments (ie. optional source files)
my $rootfs = "";
my $sbkt_file = "";
my $ringovd = "";
my $hb_volatile_file = "";

my $SEPARATOR = ",";

sub write_header_csv {
	my ($csv, $num, $base, $flags) = @_;
	my $S = $SEPARATOR;
	printf $csv "\@%d${S}0x%08x${S}%s\n", $num, $base, $flags;
}

sub write_partition_csv {
	my ($csv, $name, $base, $size, $flags, $tocs, $file) = @_;
	my $S = $SEPARATOR;
	printf $csv "%s${S}0x%08x${S}0x%08x${S}%s${S}%s${S}%s\n",
		$name, $base, $size, $flags, $tocs, $file;
}

GetOptions (
	# Mandatory arguments
	'release' => \$release,
	'outdir' => \$outdir,
	'scratch_dir' => \$scratch_dir,
	'pnor_data_dir' => \$pnor_data_dir,
	'pnor_filename' => \$pnor_filename,
	'hb_image_dir' => \$hb_image_dir,
	'xml_layout_file' => \$xml_layout_file,
	'payload' => \$payload,
	'bootkernel' => \$bootkernel,
	'occ_binary_filename' => \$occ_binary_filename,
	'sbe_binary_filename' => \$sbe_binary_filename,
	'targeting_binary_filename' => \$targeting_binary_filename,
	'hcode_file' => \$hcode_file,
	'hbbl_file' => \$hbbl_file,
	'openpower_version_filename' => \$openpower_version_filename,
	# P9 arguments
	'hdat_binary_filename' => \$hdat_binary_filename,
	'wofdata_binary_filename' => \$wofdata_binary_filename,
	'memddata_binary_filename' => \$memddata_binary_filename,
	# P8 arguments
	'sbec_binary_filename' => \$sbec_binary_filename,
	'wink_binary_filename' => \$wink_binary_filename,
	# Optional arguments
	'rootfs' => \$rootfs,
	'sbkt_file' => \$sbkt_file,
	'ringovd' => \$ringovd,
	'hb_volatile_file' => \$hb_volatile_file,
	);

if ($ARGV != 1) {
	die "Unrecognised arguments\n";
}

# Check for mandatory arguments

if ($outdir eq "") {
    die "-outdir <path_to_directory_for_output_files> is a required command line variable. Please run again with this parameter.\n";
}
if ($release eq "") {
    die "-release <p8 or p9> is a required command line variable. Please run again with this parameter.\n";
}

print "release = $release\n";
print "scratch_dir = $scratch_dir\n";
print "pnor_data_dir = $pnor_data_dir\n";

my %filenames = (
	# FIXME something seems off, have I overshot here? How much crap
	# ends up in the scratch dir?
	# right, HBD comes from op_target_dir/targeting_binary_source, so we're
	# blanking out too much
	'HBD' => "",#FIXME$scratch_dir/$targeting_binary_filename",
	'SBE' => "",#FIXME$scratch_dir/$sbe_binary_filename",
	'HBB' => "",#FIXME$scratch_dir/hostboot.header.bin.ecc",
	'HBI' => "",#FIXME$scratch_dir/hostboot_extended.header.bin.ecc",
	'HBRT' => "",#FIXME$scratch_dir/hostboot_runtime.header.bin.ecc",
	'HBEL' => "",#$scratch_dir/hbel.bin.ecc", # blank + ecc
	'GUARD' => "",#$scratch_dir/guard.bin.ecc", # blank + ecc
	'PAYLOAD' => "$payload",
	'BOOTKERNEL' => "$bootkernel",
	'ROOTFS' => "$rootfs", # TODO? if ($rootfs ne "",)
	'NVRAM' => "",#$scratch_dir/nvram.bin", # blank
	'MVPD' => "",#$scratch_dir/mvpd_fill.bin.ecc", # blank + ecc
	'DJVPD' => "",#$scratch_dir/djvpd_fill.bin.ecc", # blank + ecc
	'CVPD' => "",#FIXME$scratch_dir/cvpd.bin.ecc",
	'ATTR_TMP' => "",#$scratch_dir/attr_tmp.bin.ecc", #blank + ecc
	'ATTR_PERM' => "",#$scratch_dir/attr_perm.bin.ecc", #blank + ecc
	'OCC' => "$occ_binary_filename",
	'FIRDATA' => "",#$scratch_dir/firdata.bin.ecc", #blank + ecc
	'CAPP' => "",#FIXME$scratch_dir/cappucode.bin.ecc",
	'SECBOOT' => "",#$scratch_dir/secboot.bin.ecc", #blank + ecc
	'VERSION' => "$openpower_version_filename",
	'IMA_CATALOG' => "",#FIXME$scratch_dir/ima_catalog.bin.ecc",
	#P9 Only
	'WOFDATA' => "$wofdata_binary_filename",
	'MEMD' => "$memddata_binary_filename",
	'HDAT' => "$hdat_binary_filename",
	#P8 Only
	'SBEC' => "",#FIXME$scratch_dir/$sbec_binary_filename",
	'WINK' => "",#FIXME$scratch_dir/$wink_binary_filename",
	#Not P8
	'SBKT' => "",#FIXME$scratch_dir/SBKT.bin",
	'HCODE' => "",#FIXME$scratch_dir/$wink_binary_filename",
	'HBBL' => "",#FIXME$scratch_dir/hbbl.bin.ecc",
	'RINGOVD' => "",#$scratch_dir/ringOvd.bin", #blank + ecc
	'HB_VOLATILE' => "",#FIXME don't actually know $scratch_dir/guard.bin.ecc"
);

#Generate the CSV
my $ref = XMLin("$xml_layout_file", ForceArray => ['metadata', 'section'], SuppressEmpty => undef);
my $csv;
open($csv, ">", "$scratch_dir/pnor_layout.csv") or die "Can't open > $scratch_dir/pnor_layout.csv $!";

if (${$ref->{'metadata'}}[0]->{'arrangement'} ne "A-D-B") {
	printf STDERR "Found '%s' expecting 'A-D-B'\n",
		${$ref->{'metadata'}}[0]->{'arrangement'};
	die "Unexpected <arrangement> tag";
}

my $image_size = hex (${$ref->{'metadata'}}[0]->{'imageSize'});
my $block_size = hex (${$ref->{'metadata'}}[0]->{'blockSize'});
my $block_count = $image_size / $block_size;
my $toc_size = hex (${$ref->{'metadata'}}[0]->{'tocSize'});
my $side_string = "0";
my $side_count = keys(%{${$ref->{'metadata'}}[0]->{'side'}});

#Please don't ask me why
my $part_offset = 0;
if ($release eq "p9") {
	$part_offset = $block_size;
}

if (@{$ref->{'metadata'}} == 1) {
	if ($side_count == 1) {
		write_header_csv $csv, 0, 0, "";
		write_header_csv $csv, 1, $image_size - $toc_size - $part_offset, "";
		$side_string = "01";
	} elsif ($side_count == 2) {
		write_header_csv $csv, 0, 0, "";
		write_header_csv $csv, 1, ($image_size / 2) - $toc_size - $part_offset, "";
		write_header_csv $csv, 2, ($image_size / 2), "G";
		write_header_csv $csv, 3, $image_size - $toc_size - $part_offset, "G";
		$side_string = "0123";
	} else {
		printf STDERR "Sides not 1 or 2, total: %d\n", $side_count;
		die "Unexpected number of sides\n";
	}
} else {
	printf STDERR "Found %d <metadata> tags\n", @{$ref->{'metadata'}};
	die "There shouldn't be more than one <metadata>\n";
}

foreach my $section (@{$ref->{'section'}}) {
	my $name = $section->{'eyeCatch'};
	my $base = hex($section->{'physicalOffset'});
	my $size = hex($section->{'physicalRegionSize'});
	my $flags = "";
	$flags .= 'E' if (exists($section->{'ecc'}));
	$flags .= 'L' if (exists($section->{'sha512Version'}));
	$flags .= 'F' if (exists($section->{'reprovision'}));
	$flags .= 'I' if (exists($section->{'sha512perEC'}));
	$flags .= 'P' if (exists($section->{'preserved'}));
	$flags .= 'R' if (exists($section->{'readOnly'}));
	$flags .= 'C' if (exists($section->{'clearOnEccErr'}));
	$flags .= 'V' if (exists($section->{'volatile'}));
	my $side = "";
	if (exists($section->{'side'}) and $section->{'side'} ne "sideless") {
		$side = "01" if ($section->{'side'} eq "A");
		$side = "23" if ($section->{'side'} eq "B");
	} else {
		$side = $side_string; #Either "sideless" or no sides at all so all 0 is good
	}
	my $file = "/dev/zero";
	if (exists($filenames{$section->{'eyeCatch'}})) {
		$file = "$filenames{$section->{'eyeCatch'}}";
		# TODO have a way of marking partitions as optional
		if ($section->{'eyeCatch'} eq "MEMD") {
			unless(-e $file) {
				$file="";
			}
		}
	} else {
		print STDERR "# Don't know what file to use for partition: $section->{'eyeCatch'}\n";
	}
	write_partition_csv $csv, $name, $base, $size, $flags, $side, $file;
}

#BACKUP_PART should exist in the TOC before OTHER_SIDE. ffspart will
#respect the order of the CSV

#Add the other side and backup part partitions
if ($side_count == 2) {
	write_partition_csv $csv, "BACKUP_PART",
		($image_size / 2) - $toc_size - $part_offset, $toc_size, "B", 0, "/dev/zero";
	write_partition_csv $csv, "BACKUP_PART",
		$image_size - $toc_size - $part_offset, $toc_size, "B", 2, "/dev/zero";

	#BACKUP_PART for OTHER_SIDEs
	write_partition_csv $csv, "BACKUP_PART", 0, $toc_size, "B", 1, "/dev/zero";
	write_partition_csv $csv, "BACKUP_PART", $image_size / 2, $toc_size,
		"B", 3, "/dev/zero";

	write_partition_csv $csv, "OTHER_SIDE", $image_size / 2, $toc_size,
		"B", 0, "/dev/zero";
	write_partition_csv $csv, "OTHER_SIDE", 0, $toc_size, "B", 2, "/dev/zero";

	#OTHER_SIDEs for BACKUP_PARTs
	write_partition_csv $csv, "OTHER_SIDE", $image_size - $toc_size - $part_offset,
		$toc_size, "B", 1, "/dev/zero";
	write_partition_csv $csv, "OTHER_SIDE",
		($image_size / 2) - $toc_size - $part_offset,
		$toc_size, "B", 3, "/dev/zero";
} else {
	#Don't forget those pesky backup parts for the regular TOC
	write_partition_csv $csv, "BACKUP_PART",
		$image_size - $toc_size - $part_offset, $toc_size,
		"B", 0, "/dev/zero";
	write_partition_csv $csv, "BACKUP_PART", 0, $toc_size, "B", 1, "/dev/zero";
}


#ffspart should really learn to make its own output file
run_command("touch $pnor_filename");
run_command("ffspart -s $block_size -c $block_count -i $scratch_dir/pnor_layout.csv -p $pnor_filename --allow_empty");

#END MAIN
#-------------------------------------------------------------------------
sub parse_config_file {

}

#trim_string takes one string as input, trims leading and trailing whitespace
# before returning that string
sub trim_string {
    my $str = shift;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

sub run_command {
    my $command = shift;
    print "$command\n";
    my $rc = system($command);
    if ($rc !=0 ){
        die "Error running command: $command. Nonzero return code of ($rc) returned.\n";
    }
    return $rc;
}
