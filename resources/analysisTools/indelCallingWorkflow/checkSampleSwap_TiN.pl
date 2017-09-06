#!/usr/bin/perl 
############ 
## Author: Nagarajan Paramasivam
## Program to 
###  1. Check for Tumor-Control sample swap from same individual
###  2. Check for Tumor in Control from sample individual (TiN)
### 
############
use strict;
use File::Basename;
use Getopt::Long;
use JSON::Create 'create_json';

### Input Files and parameters and paths ############################################
my ($pid, $rawFile, $ANNOTATE_VCF, $DBSNP, $biasScript, $tumorBAM, $controlBAM, $ref, $gnomAD, $TiN_R, $localControl, $chrLengthFile, $normal_header_pattern, $tumor_header_pattern, $localControl_2, $canopy_Function, $seqType);

GetOptions ("pid=s"                      => \$pid,
            "raw_file=s"                 => \$rawFile,
            "annotate_vcf=s"             => \$ANNOTATE_VCF, 
            "gnomAD_commonSNV=s"         => \$gnomAD,
            "localControl_commonSNV=s"   => \$localControl,
            "localControl_commonSNV_2=s" => \$localControl_2,
            "bias_script=s"              => \$biasScript,
            "tumor_bam=s"                => \$tumorBAM,
            "control_bam=s"              => \$controlBAM,
            "reference=s"                => \$ref,
            "TiN_R_script=s"             => \$TiN_R,
            "canopyFunction=s"           => \$canopy_Function,
            "chrLengthFile=s"            => \$chrLengthFile,
            "normal_header_col=s"        => \$normal_header_pattern,
            "tumor_header_col=s"         => \$tumor_header_pattern,
            "sequenceType=s"             => \$seqType)
or die("Error in SwapChecker input parameters");

die("ERROR: PID is not provided\n") unless defined $pid;
die("ERROR: Raw vcf file is not provided\n") unless defined $rawFile;
die("ERROR: annotate_vcf.pl script path is missing\n") unless defined $ANNOTATE_VCF;
die("ERROR: gnomAD common SNVs is not provided\n") unless defined $gnomAD;
die("ERROR: strand bias script path is missing\n") unless defined $ANNOTATE_VCF;
die("ERROR: Tumor bam is missing\n") unless defined $tumorBAM;
die("ERROR: Control bam is missing\n") unless defined $controlBAM;
die("ERROR: Genome reference file is missing\n") unless defined $ref;

# With fill path, filename in annotation
my $analysisBasePath           = dirname $rawFile;
my $snvsGT_RawFile             = $analysisBasePath."/snvs_${pid}.GTfiltered_raw.vcf"; 
my $snvsGT_gnomADFile          = $analysisBasePath."/snvs_${pid}.GTfiltered_gnomAD.vcf";
my $snvsGT_somatic             = $analysisBasePath."/snvs_${pid}.GTfiltered_gnomAD.SomaticIn.vcf";
my $snvsGT_germlineRare        = $analysisBasePath."/snvs_${pid}.GTfiltered_gnomAD.Germline.Rare.vcf";
my $snvsGT_germlineRare_txt    = $analysisBasePath."/snvs_${pid}.GTfiltered_gnomAD.Germline.Rare.txt";
my $snvsGT_germlineRare_png    = $analysisBasePath."/snvs_${pid}.GTfiltered_gnomAD.Germline.Rare.Rescue.png";
my $snvsGT_germlineRare_oFile  = $analysisBasePath."/snvs_${pid}.GTfiltered_gnomAD.Germline.Rare.Rescue.txt";
my $snvsGT_somaticRareBiasFile = $analysisBasePath."/snvs_${pid}.GTfiltered_gnomAD.SomaticIn.Rare.BiasFiltered.vcf";
my $jsonFile                    = $analysisBasePath."/checkSampleSwap.json"; # checkSwap.json

###########################################################################################
### For JSON file

my %json = (  
  pid => $pid,
  SomaticSNVsInTumor => 0,
  SomaticSNVsInControl => 0,
  GermlineSNVs_HeterozygousInBoth => 0,  
  GermlineSNVs_HeterozygousInBoth_Rare => 0,
  RestOfVariant => 0,
  SomaticSNVsInTumor_CommonIn_gnomAD => 0,
  SomaticSNVsInTumor_CommonIn_gnomAD_Per => 0,
  SomaticSNVsInControl_CommonIn_gnomAD => 0,
  SomaticSNVsInControl_CommonIn_gnomAD_Per => 0,
  SomaticSNVSInTumor_inBias => 0,
  SomaticSNVSInTumor_inBias_Per => 0,
  SomaticSNVsInControl_inBias => 0,
  SomaticSNVsInControl_inBias_Per => 0,
  SomaticSNVsInTumor_PASS => 0,
  SomaticSNVsInTumor_PASS_Per => 0,
  SomaticSNVsInControl_PASS => 0,
  SomaticSNVsInControl_PASS_Per => 0,
  TumorInNormal_Germline_afterResuce => 0,
  TumorInNormal_Somatic_afterResuce => 0
);

###########
## 
open(my $IN, 'zcat '. $rawFile.'| ') || die "Cant read in the $rawFile.temp2\n";
open(JSON, ">$jsonFile") || die "Can't craete the $jsonFile\n";

## Filtering for Somatic variants and germline based on platypus genotype
my ($controlCol, $tumorCol, $formatCol);

my $columnCounter;

## Creating tumor and control raw somatic snvs files 
open(GTraw, ">$snvsGT_RawFile") || die "Can't create the $snvsGT_RawFile\n";

while(<$IN>) {
  chomp;
  my $line = $_;  
   
  if($line =~ /^#/)  {
    # Headers
    if($line =~ /^#CHROM/) {
      my @header = split(/\t/, $line);

      $columnCounter = $#header;

      for(my $i=0; $i<=$#header; $i++) {        
        $controlCol = $i, if($header[$i] =~ /$normal_header_pattern/i);
        $tumorCol = $i, if($header[$i] =~ /$tumor_header_pattern/i);
        $formatCol = $i, if($header[$i] =~ /FORMAT/);
      }

      if($controlCol =~ /^$/ || $tumorCol =~ /^$/) {
        # stop if header doesn't control or tumor in the column header
        $json{"Comment_SwapChecker"} = "VCF doesn't have control-tumor pair info in the column header";
        print JSON create_json (\%json);
        print "Normal header patter provided : $normal_header_pattern\n";
        print "Tumor header patter provided : $tumor_header_pattern\n";
        die("$pid doesn't have control-tumor pair info in the column header\n");
      }
      else {
        print GTraw "$line\tControl_AF\tTumor_AF\tTumor_dpALT\tTumor_dp\tControl_dpALT\tControl_dp\tGT_Classification\n";
      }
    } 
    else {
      ## Rest of the header rows
      print GTraw "$line\n";
    }
  }
  else {
    # Variants
    my @variantInfos = split(/\t/, $line);
    my $filter = $variantInfos[6];
    my $chr    = $variantInfos[0];
    my $ref    = $variantInfos[3];
    my @alt    = split(/,/, $variantInfos[4]);
    my @control = split(/:/, $variantInfos[$controlCol]);
    my @tumor   = split(/:/, $variantInfos[$tumorCol]);
    my @format  = split(/:/, $variantInfos[$formatCol]);

    my ($iGT, $iGQ, $iPL, $iNV, $iDP);
    for(my $i=0; $i<=$#format; $i++) {
      if($format[$i] eq "GT"){$iGT=$i}
      if($format[$i] eq "GQ"){$iGQ=$i}
      if($format[$i] eq "PL" || $format[$i] eq "GL"){$iPL=$i}
      if($format[$i] eq "NV"){$iNV=$i}
      if($format[$i] eq "NR"){$iDP=$i}
    }

    # Removing extra chr contigs, Indels and bad quality snvs
    # Including both indels and snvs - removed as we will have issue with bias Filter
    if($chr=~/^(X|Y|[1-9]|1[0-9]|2[0-2])$/ && $filter =~/^(PASS|alleleBias)$/ && $variantInfos[4] != /,/) {


      my @tumor_dp = split(/,/, $tumor[$iDP]);
      my @control_dp = split(/,/, $control[$iDP]);
      my @tumor_nv = split(/,/, $tumor[$iNV]);
      my @control_nv = split(/,/, $control[$iNV]);

      for(my $i=0;$i<=$#alt; $i++) {

        if($tumor_dp[$i] >= 5 && $control_dp[$i] >= 5) {

          $variantInfos[4] = $alt[$i] ;
          my $newLine = join("\t", @variantInfos) ;

          my $tumor_AF = $tumor_nv[$i]/$tumor_dp[$i] ;
          my $control_AF = $control_nv[$i]/$control_dp[$i] ;

          if($tumor_AF > 0 && $control_AF == 0 ) {
            print GTraw "$newLine\t$control_AF\t$tumor_AF\t$tumor_nv[$i]\t$tumor_dp[$i]\t$control_nv[$i]\t$control_dp[$i]\tTumor_Somatic\n";
          }
          elsif($tumor_AF == 0 && $control_AF > 0) {
            print GTraw "$newLine\t$control_AF\t$tumor_AF\t$tumor_nv[$i]\t$tumor_dp[$i]\t$control_nv[$i]\t$control_dp[$i]\tControl_Somatic\n";
          }
          else {
            print GTraw "$newLine\t$control_AF\t$tumor_AF\t$tumor_nv[$i]\t$tumor_dp[$i]\t$control_nv[$i]\t$control_dp[$i]\tGermlineInBoth\n";
          }
        }
      }
    } 
  }
}

close GTraw;

## Annotating with dbSNP

my $runAnnotation = system("cat $snvsGT_RawFile | perl $ANNOTATE_VCF -a - -b '$gnomAD' --columnName='gnomAD_COMMON_SNV' --reportMatchType  --bAdditionalColumn=2 | perl $ANNOTATE_VCF -a - -b '$localControl' --columnName='LocalControl_COMMON_SNV' --reportMatchType --bAdditionalColumn=2 | perl $ANNOTATE_VCF -a - -b '$localControl_2' --columnName='LocalControl2_COMMON_SNV' --reportMatchType --bAdditionalColumn=2 > $snvsGT_gnomADFile");


if($runAnnotation != 0 ) {
  `rm $jsonFile`;
  die("ERROR: In the allele frequency annotation step\n") ;
}

####### Germline file and rare variant filtering

open(ANN, "<$snvsGT_gnomADFile") || die "cant open the $snvsGT_gnomADFile\n";

open(GermlineRareFile, ">$snvsGT_germlineRare") || die "cant create the $snvsGT_germlineRare\n";
open(GermlineRareFileText, ">$snvsGT_germlineRare_txt") || die "cant create the $snvsGT_germlineRare_txt\n";

print GermlineRareFileText "CHR\tPOS\tREF\tALT\tControl_AF\tTumor_AF\tTumor_dpALT\tTumor_dp\tControl_dpALT\tControl_dp\tRareness\n";

open(SomaticFile, ">$snvsGT_somatic") || die "cant create the $snvsGT_somatic\n";

while(<ANN>) {
  chomp;
  my $annLine = $_;
  if($annLine =~ /^#/) {
    print GermlineRareFile "$annLine\n";
    print SomaticFile "$annLine\n";    
  }
  else {

    my @annLineSplit = split(/\t/, $annLine);
    my $start_col = $columnCounter+1;
    my $end_col = $columnCounter+6;
    my $gnomAD_col = $columnCounter+8; 

    my $germlineTextInfo = join("\t", @annLineSplit[0..1], @annLineSplit[3..4], @annLineSplit[$start_col..$end_col]);
    if($annLineSplit[$gnomAD_col] =~/;FILTER=PASS|^\.$/) {
      if($annLine=~/_Somatic/) {
	if($annLine=~/MATCH/) {
	  $annLine =~ s/_Somatic/_Somatic_Common/;
	  print SomaticFile "$annLine\n"; 
	}
	else {
	  $annLine =~ s/_Somatic/_Somatic_Rare/;
	  print SomaticFile "$annLine\n";
        }
      }
      else {
	if($annLine =~ /GermlineInBoth/ && $annLine !~ /MATCH/ && $seqType eq 'WGS') {
	  $json{'GermlineSNVs_HeterozygousInBoth_Rare'}++;
	  print GermlineRareFile "$annLine\n";
	  print GermlineRareFileText "$germlineTextInfo\tRare\n";
	}
        elsif($annLine =~ /GermlineInBoth/ && $seqType eq 'WES') {
          my $rareness;
          if($annLine !~ /MATCH/) {
            $json{'GermlineSNVs_HeterozygousInBoth_Rare'}++;
            $rareness = "Rare";
          }
          else {
            $rareness = "Common";
          }
          print GermlineRareFile "$annLine\n";
          print GermlineRareFileText "$germlineTextInfo\t$rareness\n";
        }
      }  
    }
  }
}

close GermlineRareFile;
close SomaticFile;
close Ann;

#######################################
### Finding and plotting TiN

print "Rscript-3.3.1 $TiN_R -f $snvsGT_germlineRare_txt --oPlot $snvsGT_germlineRare_png --oFile $snvsGT_germlineRare_oFile -p $pid --chrLength $chrLengthFile --cFunction $canopy_Function\n" ;

my $runRscript = system("Rscript-3.3.1 $TiN_R -f $snvsGT_germlineRare_txt --oPlot $snvsGT_germlineRare_png --oFile $snvsGT_germlineRare_oFile -p $pid --chrLength $chrLengthFile --cFunction $canopy_Function" ) ;

if($runRscript != 0) { 
  `rm $jsonFile`;
  die "Error while running $TiN_R in swapChecker\n";
}
 
chomp($json{'TumorInNormal_Germline_afterResuce'} = `cat $snvsGT_germlineRare_oFile | grep 'Germline' | wc -l`);
chomp($json{'TumorInNormal_Somatic_afterResuce'}  = `cat $snvsGT_germlineRare_oFile | grep 'Somatic_Rescue' | wc -l`);

if($json{'TumorInNormal_Somatic_afterResuce'} > 0) {

  my $rescuedTumorAF = `cat $snvsGT_germlineRare_oFile | grep 'Somatic_Rescue' | cut -f5 | perl -lne '\$x += \$_; END { print \$x; }'`;
  $json{'averageRescuedTumorAF'} = $rescuedTumorAF/$json{'TumorInNormal_Somatic_afterResuce'};
  $json{'estimatedContamination'} = $json{'averageRescuedTumorAF'}*2;
}
else
{
  $json{'averageRescuedTumorAF'} = 0;
  $json{'estimatedContamination'} = 0;
}

#######################################
## Running Bias Filters

my $runBiasScript = system("python $biasScript $snvsGT_somatic $tumorBAM $ref $snvsGT_somaticRareBiasFile --tempFolder $analysisBasePath --maxOpRatioPcr=0.34 --maxOpRatioSeq=0.34 --maxOpReadsPcrWeak=2 --maxOpReadsPcrStrong=2");

if($runBiasScript !=0) {
  die "Error while running $biasScript in swapChecker\n";
}


### Counting The Numbers 
open(SOM_RareBias, "<$snvsGT_somaticRareBiasFile") || die "Can't open the file $snvsGT_somaticRareBiasFile\n";

while(<SOM_RareBias>) {
  chomp;
  if($_!~/^#/) {
    if($_=~/Tumor_Somatic_Common/ && $_!~/bPcr|bSeq/) {
      $json{'SomaticSNVsInTumor_CommonIn_gnomAD'}++;
    }
    elsif($_=~/Tumor_Somatic/ && $_=~/bPcr|bSeq/) {
      $json{'SomaticSNVSInTumor_inBias'}++;
    }
    elsif($_=~/Tumor_Somatic_Rare/) {
      $json{'SomaticSNVsInTumor_PASS'}++;
    }

    if($_=~/Control_Somatic_Common/ && $_!~/bPcr|bSeq/) {
      $json{'SomaticSNVsInControl_CommonIn_gnomAD'}++;    
    }
    elsif($_=~/Control_Somatic/ && $_=~/bPcr|bSeq/) {
      $json{'SomaticSNVsInControl_inBias'}++;
    }
    elsif($_=~/Control_Somatic_Rare/) {
      $json{'SomaticSNVsInControl_PASS'}++;
    }   
  }
}

##################
## Creating json file 

if($json{'SomaticSNVsInTumor_PASS'} < $json{'SomaticSNVsInControl'}) {
  # Potential sample swap

  if($json{'SomaticSNVsInTumor_PASS'} > ($json{'SomaticSNVsInControl'} - $json{'SomaticSNVsInControl_CommonIn_gnomAD'})) {
      # Control somatic with lots of dbSNP variants
    $json{"Comment_SwapChecker"} = "Common-gnomAD-variants contamination in control-somatic variants.";
  }
  elsif($json{'SomaticSNVsInTumor_PASS'} > ($json{'SomaticSNVsInControl'} - $json{'SomaticSNVsInControl_inBias'})) {
    # Control somatic with lots of bias variants
     $json{"Comment_SwapChecker"} = "Bias-variants contamination among control-somatic variants.";
  }
  elsif($json{'SomaticSNVsInTumor_PASS'} > ($json{'SomaticSNVsInControl'} - ($json{'SomaticSNVsInControl_inBias'} + $json{'SomaticSNVsInControl_CommonIn_gnomAD'}))) {
    # Control somatic with lots of bias and dbSNP variants 
    $json{"Comment_SwapChecker"} = "Common-gnomAD-variants and bias-variants among control-somatic variants.";
  }
  else
  {
    ## this is $tumorGood < $controlGood
    $json{"Comment_SwapChecker"} = "Potential tumor-control swap or Common-gnomAD/bias variants are not completely removed.";
  }
}
else {
  # No swap
  $json{"Comment_SwapChecker"} = "No tumor-control swap detected.";
}

## Percentage calculations
if($json{'SomaticSNVsInTumor'} > 0) {
  $json{'SomaticSNVsInTumor_CommonIn_gnomAD_Per'} = $json{'SomaticSNVsInTumor_CommonIn_gnomAD'}/$json{'SomaticSNVsInTumor'};
  $json{'SomaticSNVSInTumor_inBias_Per'} = $json{'SomaticSNVSInTumor_inBias'}/$json{'SomaticSNVsInTumor'};
  $json{'SomaticSNVsInTumor_PASS_Per'} = $json{'SomaticSNVsInTumor_PASS'}/$json{'SomaticSNVsInTumor'};
}
else {
  $json{'SomaticSNVsInTumor_CommonIn_gnomAD_Per'} = 0;
  $json{'SomaticSNVSInTumor_inBias_Per'} = 0;
  $json{'SomaticSNVsInTumor_PASS_Per'} = 0;
}

if($json{'SomaticSNVsInControl'} > 0) {
  $json{'SomaticSNVsInControl_CommonIn_gnomAD_Per'} = $json{'SomaticSNVsInControl_CommonIn_gnomAD'}/$json{'SomaticSNVsInControl'};
  $json{'SomaticSNVsInControl_inBias_Per'} = $json{'SomaticSNVsInControl_inBias'}/$json{'SomaticSNVsInControl'};
  $json{'SomaticSNVsInControl_PASS_Per'} = $json{'SomaticSNVsInControl_PASS'}/$json{'SomaticSNVsInControl'};
}
else {
  $json{'SomaticSNVsInControl_CommonIn_gnomAD_Per'} = 0;
  $json{'SomaticSNVsInControl_inBias_Per'} = 0;
  $json{'SomaticSNVsInControl_PASS_Per'} = 0;

}

print JSON create_json (\%json);
close JSON;

######################################
#### Cleaning up files 
`rm $snvsGT_RawFile $snvsGT_gnomADFile`;
