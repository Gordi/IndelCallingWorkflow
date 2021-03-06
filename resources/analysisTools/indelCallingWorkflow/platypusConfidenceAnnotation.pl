#!/usr/bin/perl
#
# Copyright (c) 2018 German Cancer Research Center (DKFZ).
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/IndelCallingWorkflow).
#
# Confidence calculation for cancer sample
#
# perl /home/buchhalt/scripts/PlatypusPipeline/parsePlatypusResults.pl --fileName=indelMB99_CNAG.vcf --pid=MB99_CNAG --outFile=indelMB99_CNAG.filtered.vcf --controlColName=sample_control_MB99_CNAG --tumorColName=sample_tumor_MB99_CNAG --debug=1
# awk '{FS="\t"}{if($1!~/^#/ && $39>7 && $1!~/37/)print $0}' indelMB99_CNAG.filtered.vcf > indelMB99_CNAG.conf_8_to_10.vcf

use strict;
use warnings;
use Getopt::Long;
use POSIX qw(strftime);
use List::Util qw(min max);

my $makehead = 1;
my $print_annotation = 0;
my $refgenome = "hs37d5,ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/phase2_reference_assembly_sequence/hs37d5.fa.gz";
my $center = "DKFZ";
my @additionalHeader = "";
my $pid = "NA";
my $anno = 0;
my $fileName;
my $controlColName = "undef";
my $tumorColName = "undef";
my $onlyindel = 1;
my $debug = 0;
my $hetcontr = -4.60517;	# Score that a 0/0 call in the control is actually 0/1 or 1/0 (the more negative, the less likely)
my $homcontr = -4.60517;	# Score that a 0/0 call in the control is actually 1/1 (the more negative, the less likely)
my $homreftum = -4.60517;	# Score that a 0/1 or 1/0 or 1/1 in tumor is actually 0/0 (the more negative, the less likely)
my $tumaltgen = 0;			# Score that a 0/1 or 1/0 call in tumor is actually 1/1 or that a 1/1 call in tumor is actually 1/0 or 0/1 (the more negative, the less likely)

GetOptions (    "makehead|m=i"        	=> \$makehead,          # Set to 1 if you want to create the PanCan header (default = 1)
                "fileName|i=s" 			=> \$fileName,          # Input file name, set to - if you pipe into script
                "controlColName|c=s"	=> \$controlColName,    # Column number of Control
                "tumorColName|t=s"		=> \$tumorColName,      # Column number of Tumor
                "debug|d=i"				=> \$debug,             # Print justification for confidence score (default = 0)
                "anno|a=i"              => \$anno,              # Set to 1 if you want to print the original annotation (default = 0)
                "onlyindel|o=i"         => \$onlyindel,         # Set to 1 if you want to annotate only real indels (default = 1)
                "additionalHead|H=s"    => \@additionalHeader,
				"hetcontr=f"			=> \$hetcontr,
				"homcontr=f"			=> \$homcontr,
				"homreftum=f"			=> \$homreftum,
				"tumaltgen=f"			=> \$tumaltgen
) or die "Could not get the options!\n";

### Print the used filter options for the genotype filters
print STDERR "Genotype filter options:\n";
print STDERR "hetcontr = $hetcontr\tScore that a 0/0 call in the control is actually 0/1 or 1/0 (the more negative, the less likely)\n";
print STDERR "homcontr = $homcontr\tScore that a 0/0 call in the control is actually 1/1 (the more negative, the less likely)\n";
print STDERR "homreftum = $homreftum\tScore that a 0/1 or 1/0 or 1/1 in tumor is actually 0/0 (the more negative, the less likely)\n";
print STDERR "tumaltgen = $tumaltgen\t\tScore that a 0/1 or 1/0 call in tumor is actually 1/1 or that a 1/1 call in tumor is actually 1/0 or 0/1 (the more negative, the less likely)\n\n";

### Reading the input VCF file
if($fileName =~ /\.gz$/){open(DATA, "zcat $fileName |") || die $!;}
else{open(DATA, "<$fileName") || die $!;}



my $additionalHeader;
if(defined $additionalHeader[0]){
	$additionalHeader = join("\n", @additionalHeader);
	$additionalHeader .= "\n";
}else{
	$additionalHeader = "";
}

my $date = strftime "%Y%m%d", localtime;
my @refgenome = split(",", $refgenome);

my $pancanhead = "##fileformat=VCFv4.1
##fileDate=$date
##pancancerversion=1.0
##reference=<ID=$refgenome[0],Source=$refgenome[1]>;
##center=\"$center\"
##workflowName=DKFZ_SNV_workflow
##workflowVersion=1.0.0";
$pancanhead .= $additionalHeader;
$pancanhead .= "##INFO=<ID=SOMATIC,Number=0,Type=Flag,Description=\"Indicates if record is a somatic mutation\">
##INFO=<ID=GERMLINE,Number=0,Type=Flag,Description=\"Indicates if record is a germline mutation\">
##INFO=<ID=FR,Number=.,Type=Float,Description=\"Estimated population frequency of variant\">
##INFO=<ID=MMLQ,Number=1,Type=Float,Description=\"Median minimum base quality for bases around variant\">
##INFO=<ID=TCR,Number=1,Type=Integer,Description=\"Total reverse strand coverage at this locus\">
##INFO=<ID=HP,Number=1,Type=Integer,Description=\"Homopolymer run length around variant locus\">
##INFO=<ID=WE,Number=1,Type=Integer,Description=\"End position of calling window\">
##INFO=<ID=Source,Number=.,Type=String,Description=\"Was this variant suggested by Playtypus, Assembler, or from a VCF?\">
##INFO=<ID=FS,Number=.,Type=Float,Description=\"Fisher's exact test for strand bias (Phred scale)\">
##INFO=<ID=WS,Number=1,Type=Integer,Description=\"Starting position of calling window\">
##INFO=<ID=PP,Number=.,Type=Float,Description=\"Posterior probability (phred scaled) that this variant segregates\">
##INFO=<ID=TR,Number=.,Type=Integer,Description=\"Total number of reads containing this variant\">
##INFO=<ID=NF,Number=.,Type=Integer,Description=\"Total number of forward reads containing this variant\">
##INFO=<ID=TCF,Number=1,Type=Integer,Description=\"Total forward strand coverage at this locus\">
##INFO=<ID=NR,Number=.,Type=Integer,Description=\"Total number of reverse reads containing this variant\">
##INFO=<ID=TC,Number=1,Type=Integer,Description=\"Total coverage at this locus\">
##INFO=<ID=END,Number=.,Type=Integer,Description=\"End position of reference call block\">
##INFO=<ID=MGOF,Number=.,Type=Integer,Description=\"Worst goodness-of-fit value reported across all samples\">
##INFO=<ID=SbPval,Number=.,Type=Float,Description=\"Binomial P-value for strand bias test\">
##INFO=<ID=START,Number=.,Type=Integer,Description=\"Start position of reference call block\">
##INFO=<ID=ReadPosRankSum,Number=.,Type=Float,Description=\"Mann-Whitney Rank sum test for difference between in positions of variants in reads from ref and alt\">
##INFO=<ID=MQ,Number=.,Type=Float,Description=\"Root mean square of mapping qualities of reads at the variant position\">
##INFO=<ID=QD,Number=1,Type=Float,Description=\"Variant-quality/read-depth for this variant\">
##INFO=<ID=SC,Number=1,Type=String,Description=\"Genomic sequence 10 bases either side of variant position\">
##INFO=<ID=BRF,Number=1,Type=Float,Description=\"Fraction of reads around this variant that failed filters\">
##INFO=<ID=HapScore,Number=.,Type=Integer,Description=\"Haplotype score measuring the number of haplotypes the variant is segregating into in a window\">
##INFO=<ID=Size,Number=.,Type=Integer,Description=\"Size of reference call block\">
##INFO=<ID=DB,Number=0,Type=Flag,Description=\"dbSNP membership\">
##INFO=<ID=1000G,Number=0,Type=Flag,Description=\"Indicates membership in 1000Genomes\">
##FILTER=<ID=GOF,Description=\"Variant fails goodness-of-fit test.\">
##FILTER=<ID=badReads,Description=\"Variant supported only by reads with low quality bases close to variant position, and not present on both strands.\">
##FILTER=<ID=alleleBias,Description=\"Variant frequency is lower than expected for het\">
##FILTER=<ID=Q20,Description=\"Variant quality is below 20.\">
##FILTER=<ID=HapScore,Description=\"Too many haplotypes are supported by the data in this region.\">
##FILTER=<ID=MQ,Description=\"Root-mean-square mapping quality across calling region is low.\">
##FILTER=<ID=strandBias,Description=\"Variant fails strand-bias filter\">
##FILTER=<ID=SC,Description=\"Variants fail sequence-context filter. Surrounding sequence is low-complexity\">
##FILTER=<ID=QD,Description=\"Variants fail quality/depth filter.\">
##FILTER=<ID=ALTC,Description=\"Alternative reads in control and other filter not PASS\">
##FILTER=<ID=VAF,Description=\"Variant allele frequency in tumor < 10% and other filter not PASS\">
##FILTER=<ID=VAFC,Description=\"Variant allele frequency in tumor < 5% or variant allele frequency in control > 5%\">
##FILTER=<ID=QUAL,Description=\"Quality of entry too low and/or low coverage in region\">
##FILTER=<ID=ALTT,Description=\"Less than three variant reads in tumor\">
##FILTER=<ID=GTQ,Description=\"Quality for genotypes below thresholds\">
##FILTER=<ID=GTQFRT,Description=\"Quality for genotypes below thresholds and variant allele frequency in tumor < 10%\">
##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Unphased genotypes\">
##FORMAT=<ID=GQ,Number=.,Type=Integer,Description=\"Genotype quality as phred score\">
##FORMAT=<ID=GOF,Number=.,Type=Float,Description=\"Goodness of fit value\">
##FORMAT=<ID=NR,Number=.,Type=Integer,Description=\"Number of reads covering variant location in this sample\">
##FORMAT=<ID=GL,Number=.,Type=Float,Description=\"Genotype log10-likelihoods for AA,AB and BB genotypes, where A = ref and B = variant. Only applicable for bi-allelic sites\">
##FORMAT=<ID=NV,Number=.,Type=Integer,Description=\"Number of reads containing variant in this sample\">
##SAMPLE=<ID=CONTROL,SampleName=control_$pid,Individual=$pid,Description=\"Control\">
##SAMPLE=<ID=TUMOR,SampleName=tumor_$pid,Individual=$pid,Description=\"Tumor\">
#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tCONTROL\tTUMOR\t";


if ($makehead == 1)
{
    print $pancanhead;
}


### Parse the head and get the last header line
my @head;
while(<DATA>)
{
	chomp;
	if($_=~/^##/ && $_ !~ /^#CHROM/)
	{
		if($makehead ne "1"){print "$_\n";}
		next;
	}
	if($_=~/^#CHR/)
	{
		@head = split(/\t/, $_);
		last;
	}
}

### Extract the column numbers:
my $QUAL;
my $FILTER;
my $INFO;
my $CONTROL = 9;
my $TUMOR = 10;
my $CLASS;
my $CONF;	# confidence for somatic
my $PENAL;
my $DBSNP;
my $KGENOME;
my $MAPAB = 0;
my $SEGDP = 0;
my $HSDEP = 0;
my $BLACK = 0;
my $EXCLU = 0;
my $STREP = 0;
my $REPET = 0;
my $CHAIN = 0;
my $CONF2;	# confidence in general (overlap with strange regions)
my $REASONS;
for(my $i=0;$i<@head;$i++)
{
	if($head[$i] eq "QUAL")
	{
		$QUAL = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "FILTER")
	{
		$FILTER = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "INFO")
	{
		$INFO = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "$controlColName")
	{
		$CONTROL = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "$tumorColName")
	{
		$TUMOR = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "CLASSIFICATION")
	{
		$CLASS = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "CONFIDENCE")
	{
		$CONF = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "PENALTIES")
	{
		$PENAL = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "DBSNP")
	{
		$DBSNP = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if($head[$i] eq "1K_GENOMES")
	{
		$KGENOME = $i;
		print STDERR "$head[$i] in column $i\n";
	}
	if ($head[$i] =~ /MAP+ABILITY/)
	{
		$MAPAB = $i;
		print STDERR "MAPABILITY in column $i\n";
	}
	if ($head[$i] =~ /HISEQDEPTH/)
	{
		$HSDEP = $i;
		print STDERR "HISEQDEPTH in column $i\n";
	}
	if ($head[$i] =~ /SIMPLE_TANDEMREPEATS/)	# simple tandem repeats from Tandem Repeats Finder
	{
		$STREP = $i;
		print STDERR "SIMPLE_TANDEMREPEATS in column $i\n";
	}
	if ($head[$i] =~ /REPEAT_MASKER/)	# RepeatMasker annotation
	{
		$REPET = $i;
		print STDERR "REPEAT_MASKER in column $i\n";
	}
	if ($head[$i] =~ /DUKE_EXCLUDED/)
	{
		$EXCLU = $i;
		print STDERR "DUKE_EXCLUDED in column $i\n";
	}
	if ($head[$i] =~ /DAC_BLACKLIST/)
	{
		$BLACK = $i;
		print STDERR "DAC_BLACKLIST in column $i\n";
	}
	if ($head[$i] =~ /SELFCHAIN/)
	{
		$CHAIN = $i;
		print STDERR "SELFCHAIN in column $i\n";
	}
	if ($head[$i] eq "SEGDUP")
	{
		$SEGDP = $i;
		print STDERR "SEGDUP_COL in column $i\n";
	}
	if ($head[$i] eq "REGION_CONFIDENCE")
	{
		$CONF2 = $i;
		print STDERR "REGION_CONFIDENCE in column $i\n";
	}
	if ($head[$i] eq "REASONS")
	{
		$REASONS = $i;
		print STDERR "REASONS in column $i\n";
	}
}
### Add missing comlumns if not yet defined
if(!defined $CLASS)
{
	$CLASS = @head;
	push(@head, "CLASSIFICATION");
	print STDERR "$head[$CLASS] in column $CLASS\n";
}
if(!defined $CONF)
{
	$CONF = @head;
	push(@head, "CONFIDENCE");
	print STDERR "$head[$CONF] in column $CONF\n";
}
if(!defined $PENAL && $debug == 1)
{
	$PENAL = @head;
	push(@head, "PENALTIES");
	print STDERR "$head[$PENAL] in column $PENAL\n";
}
if(!defined $CONF2)
{
	$CONF2 = @head;
	push(@head, "REGION_CONFIDENCE");
	print STDERR "$head[$CONF2] in column $CONF2\n";
}
if(!defined $REASONS && $debug == 1)
{
	$REASONS = @head;
	push(@head, "REASONS");
	print STDERR "$head[$REASONS] in column $REASONS\n";
}
if($controlColName eq "undef")
{
	print STDERR "$head[$CONTROL] in column $CONTROL as of standard value\n";
}
if($tumorColName eq "undef")
{
	print STDERR "$head[$TUMOR] in column $TUMOR as of standard value\n";
}

### Print header:
### ### Change the columns to make sure control is always in column 9 and tumor in column 10 (0 based)
my $control_temp_head = $head[$CONTROL];
my $tumor_temp_head = $head[$TUMOR];
$head[9] = $control_temp_head;
$head[10] = $tumor_temp_head;
if($makehead ne "1")
{
	print join("\t", @head), "\n";
}
else
{
	print join("\t", @head[11 .. $#head]), "\n";
}

### Go over the data:
while(<DATA>)
{
	chomp;
	my $penalties;
	my $line=$_;
	my @splitIn = split(/\t/, $line);
	next if($splitIn[0] !~ /^(chr)*[\dXY]+$/);	# Ignore calls in contigs
    if($onlyindel == 1)                         # Ignore calls different from indels, should be changed later so that we also annotate replacements and maybe multiple alternatives
    {
        next if($splitIn[3] =~ /,/ || $splitIn[4] =~ /,/);          # Ignore multiple alternatives (containing a ",")
        next if($splitIn[3] =~ /\w\w+/ && $splitIn[4] =~ /\w\w+/);  # Ignore replacements (more than one bases for both, reference and alternative)
        next if($splitIn[3] =~ /^\w$/ && $splitIn[4] =~ /^\w$/);    # Ignore SNVs
    }

	my $class="";
	my $confidence=10;
	my $VAFControl=0;
	my $VAFTumor=0;
	my %filter;
	my $dbSnpPos;
	my $dbSnpId;
	my $region_conf = 10;
	my $reasons = "";


	if(defined $DBSNP && $splitIn[$DBSNP] =~ /MATCH\=exact/)
	{
		$splitIn[$INFO] .= ";DB";
		$dbSnpPos = $splitIn[1];
		($dbSnpId) = $splitIn[$DBSNP] =~ /ID\=(rs\d+)/;
	}
	if(defined $KGENOME && $splitIn[$KGENOME] =~ /MATCH\=exact/)
	{
		$splitIn[$INFO] .= ";1000G";
	}
	
	my ($qual) = $splitIn[$QUAL];
### variants with more than one alternative are still skipped e.g. chr12	19317131	.	GTT	GT,G	...
	if($splitIn[$CONTROL]=~/^(0\/0)/ && $splitIn[$TUMOR]=~/1\/0|0\/1|1\/1/)
	{
		my ($controlGT, $controlGP, $C_GOF, $controlGQ, $controlDP, $controlDP_V)=$splitIn[$CONTROL]=~/^([\d\.]\/[\d\.]):(.*,.*,.*):(\d+):(\d+):(\d+):(\d+)$/;

		if (! defined $controlDP || ! defined $controlGT)
		{
			print STDERR "really strange entry where controlDP and/or controlGT could not be parsed: $line\n";
		}

		my ($tumorGT, $tumorGP, $T_GOF, $tumorGQ, $tumorDP, $tumorDP_V)=$splitIn[$TUMOR]=~/^([\d\.]\/[\d\.]):(.*,.*,.*):(\d+):(\d+):(\d+):(\d+)$/;
		if($controlDP > 0 && $tumorDP > 0)
		{
			$VAFControl= ($controlDP_V/$controlDP)*100;
			$VAFTumor  = ($tumorDP_V/$tumorDP)*100;
		}

		### confidence measure
		if($controlGT=~/0\/0/ && $tumorGT=~/1\/0|0\/1|1\/1/)
		{
			$class="somatic";	# All calls with this genotype are called somatic
			$splitIn[$INFO] = "SOMATIC;".$splitIn[$INFO];
			if($splitIn[$FILTER]=~/PASS/)	# All intrinsic platypus filters are PASS
			{
				# Do nothing
			}
			else	# not PASS but not too bad
			{
				if($splitIn[$FILTER]=~/alleleBias/)	# alleleBias in platypus Filter seems ok if there is no other problem (-2)
				{
					$confidence-=2;
					$penalties .= "alleleBias_-2_";
					$filter{"alleleBias"} = 1;
					$region_conf-=2;
					$reasons.="alleleBias(-2)";
				}
				if($splitIn[$FILTER]=~/badReads/)	# badReads always seem to be bad (-3)
				{
					$confidence-=3;
					$penalties .= "badReads_-3_";
					$filter{"badReads"} = 1;
					$region_conf-=3;
					$reasons.="badReads(-3)";
				}
				if($splitIn[$FILTER]=~/MQ/)	# MQ (mapping quality) seems to have not a big influence on the quality (-1)
				{
					$confidence-=1;
					$penalties .= "MQ_-1_";
					$filter{"MQ"} = 1;
					$region_conf-=1;
					$reasons.="MQ(-1)";
				}
				if($splitIn[$FILTER]=~/SC/)	# SC sequence of low genomic complexity around call seems to be not too bad (-1)
				{
					$confidence-=1;
					$penalties .= "SC_-1_";
					$filter{"SC"} = 1;
					$region_conf-=1;
					$reasons.= "SC(-1)";
				}
				if($splitIn[$FILTER]=~/GOF/)	# GOF (goodness of fit) filter seems to be not too bad (-1)
				{
					$confidence-=1;
					$penalties .= "GOF_-1_";
					$filter{"GOF"} = 1;
					$region_conf-=1;
					$reasons.= "GOF(-1)";
				}
				if($splitIn[$FILTER]=~/QD/)	# QD (quality/depth filter) seems to be not too bad (-1)
				{
					$confidence-=1;
					$penalties .= "QD_-1_";
					$filter{"QD"} = 1;
					$region_conf-=1;
					$reasons.= "QD(-1)";
				}
				if($splitIn[$FILTER]=~/strandBias/)	# strandBias seems to be ok if there is no other problem (-2)
				{
					$confidence-=2;
					$penalties .= "strandBias_-2_";
					$filter{"strandBias"} = 1;
					$region_conf-=2;
					$reasons.= "strandBias(-2)";
				}
				if($controlDP_V > 0)	# Variant reads found in control (in addition to one of the above filters) (-1)
				{
					$confidence-=1;
					$penalties .= "alt_reads_in_control_-1_";
					$filter{"ALTC"} = 1;
				}
				if($VAFTumor < 10)	# Tumor variant allele frequency lower than 10% (in addition fo one of the above filters) (-1)
				{
					$confidence-=1;
					$penalties .= "VAF<10_-1_";
					$filter{"VAF"} = 1;
				}
			}

			# Minimum base quality, read depth and genotype quality
			if($qual > 40 && $controlDP >=10 && $tumorDP >=10 && $controlGQ >= 20 && $tumorGQ>=20)	# All quality filters are OK
			{
				# Do nothing
			} 
			elsif($qual > 20 && $controlDP >=5 && $tumorDP >=5 && $controlGQ >= 20 && $tumorGQ>=20)	# Medium quality values (not needed, is equal to bad values)(-2)
			{
				$confidence-=2;
				$penalties .= "medium_quality_values_-2_";
				$filter{"QUAL"} = 1;
			}
			else	# Bad quality values (is equal to medium bad values)(-2)
			{
				$confidence-=2;
				$penalties .= "bad_quality_values_-2_";
				$filter{"QUAL"} = 1;
			}

			if($tumorDP_V < 3)	# Less than three variant reads in tumor (-2)
			{
				$confidence-=2;
				$penalties .= "<3_reads_in_tumor_-2_";
				$filter{"ALTT"} = 1;
			}

			if($controlDP_V == 0)	# No variant reads in control (Perfect!)
			{
				# Do nothing
			}
			else	# Variant reads found in control
			{
				if($VAFControl < 5 && $VAFTumor > 5)	# VAF in control below 0.05 and bigger 0.05 in tumor (-1)
				{
					$confidence-=1;
					$penalties .= "alt_reads_in_control(VAF<0.05)_-1_";
					$filter{"ALTC"} = 1;
				}
				else	# Almost always bad (-3)
				{
					$confidence-=3;
					$penalties .= "alt_reads_in_control(VAF>=0.05_or_tumor_VAF<=0.05)_-3_";
					$filter{"VAFC"} = 1;
				}
			}

			my @ssControlGP=split(/,/, $controlGP);
			my @sstumorGP=split(/,/, $tumorGP);

			# Genotype probability
			if($tumorGT=~/1\/0|0\/1/)
			{
				if(($ssControlGP[1] < $hetcontr && $ssControlGP[2] < $homcontr) && ($sstumorGP[0] < $homreftum && $sstumorGP[2] < $tumaltgen))	# All genotype qualitys are OK
				{
					# Do nothing
				}
				else	# At least one genotype quality is bad (-2)
				{
					$confidence-=2;
					$penalties .= "bad_genotype_quality_-2_";
					$filter{"GTQ"} = 1;
					if($controlDP_V > 0)	# Bad genotype and alternative reads in control (-1)
					{
						$confidence-=1;
						$penalties .= "alt_reads_in_control_-1_";
						$filter{"ALTC"} = 1;
					}
					if($VAFTumor < 10)	# Bad genotype and VAF below 0.1 (-1)
					{
						$confidence-=1;
						$penalties .= "VAF<10_-1_";
						$filter{"GTQFRT"} = 1;
					}
				}
			}
			elsif($tumorGT=~/1\/1/)
			{
				if(($ssControlGP[1] < $hetcontr && $ssControlGP[2] < $homcontr) && ($sstumorGP[0] < $homreftum && $sstumorGP[1] < $tumaltgen))	# All genotype qualitys are OK
				{
					# Do nothing
				}
				else	# At least one genotype quality is bad (-2)
				{
					$confidence-=2;
					$penalties .= "bad_genotype_quality_-2_";
					$filter{"GTQ"} = 1;
					if($controlDP_V > 0)	# Bad genotype and alternative reads in control (-1)
					{
						$confidence-=1;
						$penalties .= "alt_reads_in_control_-1_";
						$filter{"ALTC"} = 1;
					}
					if($VAFTumor < 10)	# Bad genotype and VAF below 0.1 (-1)
					{
						$confidence-=1;
						$penalties .= "VAF<10_-1_";
						$filter{"GTQFRT"} = 1;
					}
				}
			}
		}
		else
		{
			$class="unclear";
			$splitIn[$INFO] = "UNCLEAR;".$splitIn[$INFO];
			$confidence=1;
		}
	}
	else	# Everything else is treated as germline (might be done differently so that we also get a confidence score for germline)
	# if the control genotype is something strange as 2/3, this is for sure not germline
	{
		if ($splitIn[$CONTROL]=~/1\/0|0\/1|1\/1/)
		{
			$class="germline";
			$splitIn[$INFO] = "GERMLINE;".$splitIn[$INFO];
		}
		else
		{
			$class="unclear";
			$splitIn[$INFO] = "UNCLEAR;".$splitIn[$INFO];
		}
		$confidence=1;
	}
	if($confidence < 1)	# Set confidence to 1 if it is below one
	{
		$confidence = 1;
	}
	if($confidence > 10)	# Set confidence to 10 if above (will not happen at the moment as we never give a bonus)
	{
		$confidence = 10;
	}

###### Stuff from Barbara
	# more filters to assess how good the region is, i.e. if indel overlaps with strange regions
	# the blacklists have few entries; the HiSeqDepth has more "reads attracting" regions,
	# often coincide with tandem repeats and CEN/TEL, not always with low mapability
	if ($splitIn[$EXCLU] ne "." || $splitIn[$BLACK] ne "." || $splitIn[$HSDEP] ne ".")
	{
		$region_conf-=3;	# really bad region, usually centromeric repeats
		$reasons.="Blacklist(-3)";
	}
	# Self Chain may not be very useful for SNVs, but for indels better than repeats.
	# Segmental duplications are not that bad for indels as for snvs
	if ($splitIn[$CHAIN] ne "." || $splitIn[$SEGDP] ne ".")
	{
		$region_conf--;
		$reasons.="SelfchainAndOrSegdup(-1)";
	}
	# simple (tandem) repeats and low complexity regions are prone to misalignment
	if ($splitIn[$REPET] =~ /Simple_repeat/ || $splitIn[$REPET] =~ /Low_/ || $splitIn[$REPET] =~ /Satellite/ || $splitIn[$STREP] ne ".")
	{
		$region_conf-=2;
		$reasons.="Repeat(-2)";
	}
	# other repeat elements (Alu, ..., LINE) are not that bad but may correlate with low mappability
	elsif ($splitIn[$REPET] ne ".")
	{
		$region_conf-=1;
		$reasons.="Other_repeat(-1)";
	}
	
	# Mapability is 1 for unique regions, 0.5 for regions appearing twice, 0.33... 3times, ...
	# Everything with really high number of occurences is artefacts
	# does not always correlate with the above regions
	# is overestimating badness bc. of _single_ end read simulations
	my $mapp = $splitIn[$MAPAB];
	if ($mapp eq ".")	# in very rare cases (CEN), there is no mapability => ".", which is not numeric but interpreted as 0
	{
		$region_conf-=5;
		$reasons.="Not_mappable(-5)";
	}
	else
	{
		if ($mapp =~ /&/)	# can have several entries for indels, e.g. 0.5&0.25 - take worst (lowest) or best (highest)?!
		{
			my @mappab = split ("&", $mapp);
			$mapp = min @mappab;	# just chose one - here: min
		}
		# else simple case: only one value
		my $reduce = 0;
		if ($mapp < 0.5)	# 0.5 does not seem to be that bad: region appears another time in the genome and we have paired end data!
		{
			$region_conf--;
			$reduce++;
			$reasons.="Low_mappability($mapp=>";
			if ($mapp < 0.25)	#  >4 times appearing region is worse but still not too bad
			{
				$region_conf--;
				$reduce++;
				if ($mapp < 0.1)	# > 5 times is bad
				{
					$region_conf-=2;
					$reduce+=2;
				}
				if ($mapp < 0.05)	# these regions are clearly very bad (Lego stacks)
				{
					$region_conf-=3;
					$reduce+=3;
				}
			}
		$reasons.="-$reduce)";
		}
	}

	if ($class ne "somatic" && $splitIn[$FILTER] !~ /PASS/)
	# such an indel is probably also "unclear" and not "germline"
	# all filters were already punished before but for germline we really want to be strict
	{
		$region_conf-=3;
		$reasons.="notPASS(-3)";
	}
	if($region_conf < 1)	# Set confidence to 1 if it is below one
	{
		$region_conf = 1;
	}

	### Insert the new columns:
	$splitIn[$CLASS] = $class;
	$splitIn[$CONF] = $confidence;
	$splitIn[$CLASS] = $class;
	$splitIn[$CONF] = $confidence;
	$splitIn[$CONF2] = $region_conf;
	if($class eq "somatic" && $confidence >= 8)
	{
		$splitIn[$FILTER] = "PASS";
	}
	if($class eq "somatic" && $confidence < 8)
	{
		$splitIn[$FILTER] = "";
		foreach(my @filteroptions = ("GOF","badReads","alleleBias","MQ","strandBias","SC","QD","ALTC","VAF","VAFC","QUAL","ALTT","GTQ","GTQFRT"))
		{
			if(exists $filter{$_} && $filter{$_} == 1){$splitIn[$FILTER] .= "$_;";}
		}
		$splitIn[$FILTER] =~ s/;$//;
	}
	### Change the columns to make sure control is always in column 9 and tumor in column 10 (0 based)
	my $control_temp = $splitIn[$CONTROL];
	my $tumor_temp = $splitIn[$TUMOR];
	$splitIn[9] = $control_temp;
	$splitIn[10] = $tumor_temp;
	$splitIn[$QUAL] = ".";
	if(defined $dbSnpId && defined $dbSnpPos)
	{
		$splitIn[2] = $dbSnpId."_".$dbSnpPos;
	}
	if($debug == 0)
	{
		print join("\t", @splitIn), "\n";
	}
	else
	{
		if(!defined $reasons)
		{
			$reasons = ".";
		}
		if(!defined $penalties)
		{
			$penalties = ".";
		}
		$penalties =~ s/_$//; 
		$splitIn[$PENAL] = $penalties;
		$splitIn[$REASONS] = $reasons;
		print join("\t", @splitIn) ,"\n";
	}
}
close DATA;
