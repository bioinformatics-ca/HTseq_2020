#set up environment variables
export WORK_DIR=~/workspace/HTseq/Integrative_Assignment/
export REF=$WORK_DIR/reference/

rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR
ln -fs ~/CourseData/HT_data/Module3/* .

# Load the software modules
module load mugqic/java/openjdk-jdk1.8.0_72 mugqic/bvatools/1.6 mugqic/trimmomatic/0.36 mugqic/samtools/1.9 mugqic/bwa/0.7.17 mugqic/GenomeAnalysisTK/4.1.0.0 mugqic/R_Bioconductor/3.5.0_3.7
# Parent 1

# Quality
mkdir originalQC_NA12892/
java -Xmx1G -jar ${BVATOOLS_JAR} readsqc \
  --read1 raw_reads/NA12892/NA12892_CBW_chr1_R1.fastq.gz \
  --read2 raw_reads/NA12892/NA12892_CBW_chr1_R2.fastq.gz \
  --threads 2 --regionName ACTL8 --output originalQC_NA12892/

# Trim Reads

cat reference/adapters.fa

mkdir -p reads/NA12892/

java -Xmx2G -cp $TRIMMOMATIC_JAR org.usadellab.trimmomatic.TrimmomaticPE -threads 2 -phred33 \
  raw_reads/NA12892/NA12892_CBW_chr1_R1.fastq.gz \
  raw_reads/NA12892/NA12892_CBW_chr1_R2.fastq.gz \
  reads/NA12892/NA12892_CBW_chr1_R1.t20l32.fastq.gz \
  reads/NA12892/NA12892_CBW_chr1_S1.t20l32.fastq.gz \
  reads/NA12892/NA12892_CBW_chr1_R2.t20l32.fastq.gz \
  reads/NA12892/NA12892_CBW_chr1_S2.t20l32.fastq.gz \
  ILLUMINACLIP:reference/adapters.fa:2:30:15 TRAILING:20 MINLEN:32 \
  2> reads/NA12892/NA12892.trim.out

cat reads/NA12892/NA12892.trim.out

mkdir postTrimQC_NA12892/
java -Xmx1G -jar ${BVATOOLS_JAR} readsqc \
  --read1 reads/NA12892/NA12892_CBW_chr1_R1.t20l32.fastq.gz \
  --read2 reads/NA12892/NA12892_CBW_chr1_R2.t20l32.fastq.gz \
  --threads 2 --regionName ACTL8 --output postTrimQC_NA12892/


# Alignment
mkdir -p alignment/NA12892/

bwa mem -M -t 2 \
  -R '@RG\tID:NA12892\tSM:NA12892\tLB:NA12892\tPU:runNA12892_1\tCN:Broad Institute\tPL:ILLUMINA' \
  reference/hg19.fa \
  reads/NA12892/NA12892_CBW_chr1_R1.t20l32.fastq.gz \
  reads/NA12892/NA12892_CBW_chr1_R2.t20l32.fastq.gz \
  | java -Xmx2G -jar ${GATK_JAR} SortSam \
  -I /dev/stdin \
  -O alignment/NA12892/NA12892.sorted.bam \
  -SO coordinate \
  --CREATE_INDEX true \
  --MAX_RECORDS_IN_RAM=500000


# Explore the bam files
samtools view alignment/NA12892/NA12892.sorted.bam | head -n4

# Count the *un-aligned* reads
samtools view -c -f4 alignment/NA12892/NA12892.sorted.bam
# Count the *aligned* reads
samtools view -c -F4 alignment/NA12892/NA12892.sorted.bam

# Indel realignment
# 1- Find the targets 2- Realign them.

#switch to old GATK 3.8
module unload  mugqic/GenomeAnalysisTK/4.1.0.0
module load mugqic/GenomeAnalysisTK/3.8
java -Xmx2G  -jar ${GATK_JAR} \
  -T RealignerTargetCreator \
  -R reference/hg19.fa \
  -o alignment/NA12892/realign.intervals \
  -I alignment/NA12892/NA12892.sorted.bam \
  -L chr1

java -Xmx2G -jar ${GATK_JAR} \
  -T IndelRealigner \
  -R reference/hg19.fa \
  -targetIntervals alignment/NA12892/realign.intervals \
  -o alignment/NA12892/NA12892.realigned.sorted.bam \
  -I alignment/NA12892/NA12892.sorted.bam
module unload mugqic/GenomeAnalysisTK/3.8
module load  mugqic/GenomeAnalysisTK/4.1.0.0


# FixMates (optional, see Module 3 main page for explanation)
#java -Xmx2G -jar ${PICARD_JAR} FixMateInformation \
#  VALIDATION_STRINGENCY=SILENT CREATE_INDEX=true SORT_ORDER=coordinate MAX_RECORDS_IN_RAM=500000 \
#  INPUT=alignment/NA12892/NA12892.realigned.sorted.bam \
#  OUTPUT=alignment/NA12892/NA12892.matefixed.sorted.bam

# Mark duplicates
java -Xmx2G -jar ${GATK_JAR} MarkDuplicates \
  --REMOVE_DUPLICATES false --CREATE_INDEX true \
  -I alignment/NA12892/NA12892.realigned.sorted.bam \
  -O alignment/NA12892/NA12892.sorted.dup.bam \
  --METRICS_FILE=alignment/NA12892/NA12892.sorted.dup.metrics


# less alignment/NA12892/NA12892.sorted.dup.metrics


# Recalibration
java -Xmx2G -jar ${GATK_JAR} BaseRecalibrator \
  -R reference/hg19.fa \
  --known-sites ${REF}/dbSNP_135_chr1.vcf.gz \
  -L chr1:17704860-18004860 \
  -O alignment/NA12892/NA12892.sorted.dup.recalibration_report.grp \
  -I alignment/NA12892/NA12892.sorted.dup.bam

java -Xmx2G -jar ${GATK_JAR} ApplyBQSR \
  -R reference/hg19.fa \
  -bqsr alignment/NA12892/NA12892.sorted.dup.recalibration_report.grp \
  -O alignment/NA12892/NA12892.sorted.dup.recal.bam \
  -I alignment/NA12892/NA12892.sorted.dup.bam




##emit 1 warning for the dictionnary
#not working

#java -Xmx2G -jar ${GATK_JAR} \
#  -T PrintReads \
#  -nct 2 \
#  -R reference/hg19.fa \
#  -BQSR alignment/NA12892/NA12892.sorted.dup.recalibration_report.grp \
#  -o alignment/NA12892/NA12892.sorted.dup.recal.bam \
#  -I alignment/NA12892/NA12892.sorted.dup.bam


# Extract Metrics
module unload  mugqic/GenomeAnalysisTK/4.1.0.0
module load mugqic/GenomeAnalysisTK/3.8

java  -Xmx2G -jar ${GATK_JAR} \
  -T DepthOfCoverage \
  --omitDepthOutputAtEachBase \
  --summaryCoverageThreshold 10 \
  --summaryCoverageThreshold 25 \
  --summaryCoverageThreshold 50 \
  --summaryCoverageThreshold 100 \
  --start 1 --stop 500 --nBins 499 -dt NONE \
  -R reference/hg19.fa \
  -o alignment/NA12892/NA12892.sorted.dup.recal.coverage \
  -I alignment/NA12892/NA12892.sorted.dup.recal.bam \
  -L chr1:17700000-18100000

module unload mugqic/GenomeAnalysisTK/3.8
module load  mugqic/GenomeAnalysisTK/4.1.0.0

## less -S alignment/NA12892/NA12892.sorted.dup.recal.coverage.sample_interval_summary


java -Xmx2G -jar ${GATK_JAR} CollectInsertSizeMetrics \
  -R reference/hg19.fa \
  -I alignment/NA12892/NA12892.sorted.dup.recal.bam \
  -O alignment/NA12892/NA12892.sorted.dup.recal.metric.insertSize.tsv \
  -H alignment/NA12892/NA12892.sorted.dup.recal.metric.insertSize.histo.pdf \
  --METRIC_ACCUMULATION_LEVEL LIBRARY


## less -S alignment/NA12892/NA12892.sorted.dup.recal.metric.insertSize.tsv
# head -9  alignment/NA12892/NA12892.sorted.dup.recal.metric.insertSize.tsv | tail -3 | cut -f5,6

java -Xmx2G -jar ${GATK_JAR} CollectAlignmentSummaryMetrics \
  -R reference/hg19.fa \
  -I alignment/NA12892/NA12892.sorted.dup.recal.bam \
  -O alignment/NA12892/NA12892.sorted.dup.recal.metric.alignment.tsv \
  --METRIC_ACCUMULATION_LEVEL LIBRARY


## less -S alignment/NA12892/NA12892.sorted.dup.recal.metric.alignment.tsv
# head -10  alignment/NA12892/NA12892.sorted.dup.recal.metric.alignment.tsv | tail -4 | cut -f7


### Parent 2


# Quality
mkdir originalQC_NA12891/
java -Xmx1G -jar ${BVATOOLS_JAR} readsqc \
  --read1 raw_reads/NA12891/NA12891_CBW_chr1_R1.fastq.gz \
  --read2 raw_reads/NA12891/NA12891_CBW_chr1_R2.fastq.gz \
  --threads 2 --regionName ACTL8 --output originalQC_NA12891/


# Trim

cat reference/adapters.fa

mkdir -p reads/NA12891/

java -Xmx2G -cp $TRIMMOMATIC_JAR org.usadellab.trimmomatic.TrimmomaticPE -threads 2 -phred33 \
  raw_reads/NA12891/NA12891_CBW_chr1_R1.fastq.gz \
  raw_reads/NA12891/NA12891_CBW_chr1_R2.fastq.gz \
  reads/NA12891/NA12891_CBW_chr1_R1.t20l32.fastq.gz \
  reads/NA12891/NA12891_CBW_chr1_S1.t20l32.fastq.gz \
  reads/NA12891/NA12891_CBW_chr1_R2.t20l32.fastq.gz \
  reads/NA12891/NA12891_CBW_chr1_S2.t20l32.fastq.gz \
  ILLUMINACLIP:reference/adapters.fa:2:30:15 TRAILING:20 MINLEN:32 \
  2> reads/NA12891/NA12891.trim.out

cat reads/NA12891/NA12891.trim.out

mkdir postTrimQC_NA12891/
java -Xmx1G -jar ${BVATOOLS_JAR} readsqc \
  --read1 reads/NA12891/NA12891_CBW_chr1_R1.t20l32.fastq.gz \
  --read2 reads/NA12891/NA12891_CBW_chr1_R2.t20l32.fastq.gz \
  --threads 2 --regionName ACTL8 --output postTrimQC_NA12891/


# Alignment
mkdir -p alignment/NA12891/

bwa mem -M -t 2 \
  -R '@RG\tID:NA12891\tSM:NA12891\tLB:NA12891\tPU:runNA12891_1\tCN:Broad Institute\tPL:ILLUMINA' \
  reference/hg19.fa \
  reads/NA12891/NA12891_CBW_chr1_R1.t20l32.fastq.gz \
  reads/NA12891/NA12891_CBW_chr1_R2.t20l32.fastq.gz \
  | java -Xmx2G -jar ${GATK_JAR} SortSam \
  -I /dev/stdin \
  -O alignment/NA12891/NA12891.sorted.bam \
  -SO coordinate \
  --CREATE_INDEX true \
  --MAX_RECORDS_IN_RAM=500000



# Explore the bam files
samtools view alignment/NA12891/NA12891.sorted.bam | head -n4

# Count the *un-aligned* reads
samtools view -c -f4 alignment/NA12891/NA12891.sorted.bam
# Count the *aligned* reads
samtools view -c -F4 alignment/NA12891/NA12891.sorted.bam

# Indel realignment
# 1- Find the targets 2- Realign them.
module unload  mugqic/GenomeAnalysisTK/4.1.0.0
module load mugqic/GenomeAnalysisTK/3.8

java -Xmx2G  -jar ${GATK_JAR} \
  -T RealignerTargetCreator \
  -R reference/hg19.fa \
  -o alignment/NA12891/realign.intervals \
  -I alignment/NA12891/NA12891.sorted.bam \
  -L chr1

java -Xmx2G -jar ${GATK_JAR} \
  -T IndelRealigner \
  -R reference/hg19.fa \
  -targetIntervals alignment/NA12891/realign.intervals \
  -o alignment/NA12891/NA12891.realigned.sorted.bam \
  -I alignment/NA12891/NA12891.sorted.bam

module load mugqic/GenomeAnalysisTK/3.8
module unload  mugqic/GenomeAnalysisTK/4.1.0.0

# FixMates (optional, see Module 3 main page for explanation)
#java -Xmx2G -jar ${PICARD_JAR} FixMateInformation \
#  VALIDATION_STRINGENCY=SILENT CREATE_INDEX=true SORT_ORDER=coordinate MAX_RECORDS_IN_RAM=500000 \
#  INPUT=alignment/NA12891/NA12891.realigned.sorted.bam \
#  OUTPUT=alignment/NA12891/NA12891.matefixed.sorted.bam

# Mark duplicates
java -Xmx2G -jar ${GATK_JAR} MarkDuplicates \
  --REMOVE_DUPLICATES false --CREATE_INDEX true \
  -I alignment/NA12891/NA12891.realigned.sorted.bam \
  -O alignment/NA12891/NA12891.sorted.dup.bam \
  --METRICS_FILE=alignment/NA12891/NA12891.sorted.dup.metrics

# less alignment/NA12891/NA12891.sorted.dup.metrics


# Recalibration
java -Xmx2G -jar ${GATK_JAR} BaseRecalibrator \
  -R reference/hg19.fa \
  --known-sites ${REF}/dbSNP_135_chr1.vcf.gz \
  -L chr1:17704860-18004860 \
  -O alignment/NA12891/NA12891.sorted.dup.recalibration_report.grp \
  -I alignment/NA12891/NA12891.sorted.dup.bam

java -Xmx2G -jar ${GATK_JAR} ApplyBQSR \
  -R reference/hg19.fa \
  -bqsr alignment/NA12891/NA12891.sorted.dup.recalibration_report.grp \
  -O alignment/NA12891/NA12891.sorted.dup.recal.bam \
  -I alignment/NA12891/NA12891.sorted.dup.bam




##emit 1 warning for the dictionnary
#not working

#java -Xmx2G -jar ${GATK_JAR} \
#  -T PrintReads \
#  -nct 2 \
#  -R ${REF}/hg19.fa \
#  -BQSR alignment/NA12891/NA12891.sorted.dup.recalibration_report.grp \
#  -o alignment/NA12891/NA12891.sorted.dup.recal.bam \
#  -I alignment/NA12891/NA12891.sorted.dup.bam


# Extract Metrics
module unload  mugqic/GenomeAnalysisTK/4.1.0.0
module load mugqic/GenomeAnalysisTK/3.8

java  -Xmx2G -jar ${GATK_JAR} \
  -T DepthOfCoverage \
  --omitDepthOutputAtEachBase \
  --summaryCoverageThreshold 10 \
  --summaryCoverageThreshold 25 \
  --summaryCoverageThreshold 50 \
  --summaryCoverageThreshold 100 \
  --start 1 --stop 500 --nBins 499 -dt NONE \
  -R reference/hg19.fa \
  -o alignment/NA12891/NA12891.sorted.dup.recal.coverage \
  -I alignment/NA12891/NA12891.sorted.dup.recal.bam \
  -L chr1:17700000-18100000

 module load mugqic/GenomeAnalysisTK/3.8
 module unload  mugqic/GenomeAnalysisTK/4.1.0.0


## less -S alignment/NA12891/NA12891.sorted.dup.recal.coverage.sample_interval_summary


java -Xmx2G -jar ${GATK_JAR} CollectInsertSizeMetrics \
  -R reference/hg19.fa \
  -I alignment/NA12891/NA12891.sorted.dup.recal.bam \
  -O alignment/NA12891/NA12891.sorted.dup.recal.metric.insertSize.tsv \
  -H alignment/NA12891/NA12891.sorted.dup.recal.metric.insertSize.histo.pdf \
  --METRIC_ACCUMULATION_LEVEL LIBRARY




## less -S alignment/NA12891/NA12891.sorted.dup.recal.metric.insertSize.tsv
# head -9  alignment/NA12891/NA12891.sorted.dup.recal.metric.insertSize.tsv | tail -3 | cut -f5,6

java -Xmx2G -jar ${GATK_JAR} CollectAlignmentSummaryMetrics \
  -R reference/hg19.fa \
  -I alignment/NA12891/NA12891.sorted.dup.recal.bam \
  -O alignment/NA12891/NA12891.sorted.dup.recal.metric.alignment.tsv \
  --METRIC_ACCUMULATION_LEVEL LIBRARY


## less -S alignment/NA12891/NA12891.sorted.dup.recal.metric.alignment.tsv
# head -10  alignment/NA12891/NA12891.sorted.dup.recal.metric.alignment.tsv | tail -4 | cut -f7
