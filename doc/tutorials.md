# A sourmash tutorial

This tutorial should run without modification on Ubuntu 15.10 ("wily");
it was developed on AWS ami-05384865 (us-west region).

You'll need about 30 GB of free disk space to download the database,
and about 1-2 GB of RAM to search it.  The tutorial should take about
20 minutes total to run.

## Installing sourmash

To install sourmash, run:

```
sudo apt-get -y update && \
sudo apt-get install -y python3.5-dev python3.5-venv make \
    libc6-dev g++ zlib1g-dev
```

this installs Python 3.5.

Now, create a local software install and populate it with Jupyter and
other dependencies:

```

python3.5 -m venv ~/py3
. ~/py3/bin/activate
pip install -U pip
pip install -U Cython
pip install -U jupyter jupyter_client ipython pandas matplotlib scipy scikit-learn khmer

pip install https://github.com/dib-lab/sourmash/archive/master.zip

```

## Generate a signature for Illumina reads

Download some reads and a reference genome:

```
mkdir ~/data
cd ~/data
wget http://public.ged.msu.edu.s3.amazonaws.com/ecoli_ref-5m-trim.pe.fq.gz
wget https://s3.amazonaws.com/public.ged.msu.edu/ecoliMG1655.fa.gz
```

Compute a scaled MinHash signature from our reads:

```
mkdir ~/sourmash
cd ~/sourmash

sourmash compute --scaled 10000 ~/data/ecoli_ref*pe*.fq.gz -o ecoli-reads.sig -k 31
```

## Compare reads to assemblies

Use case: how much of the read content is contained in the reference genome?

Build a signature for an E. coli genome:

```
sourmash compute --scaled 10000 -k 31 ~/data/ecoliMG1655.fa.gz -o ecoli-genome.sig
```

and now evaluate *containment*, that is, what fraction of the read content is
contained in the genome:

```
sourmash search -k 31 ecoli-reads.sig ecoli-genome.sig --containment
```

and you should see:

```
# running sourmash subcommand: search
loaded query: /home/ubuntu/data/ecoli_ref-5m... (k=31, DNA)
loaded 1 signatures from ecoli-genome.sig
1 matches:
similarity   match
----------   -----
 46.6%       /home/ubuntu/data/ecoliMG1655.fa.gz
```


Try the reverse - why is it bigger?
         
```
sourmash search -k 31 ecoli-genome.sig ecoli-reads.sig --containment
```

## Make and search a database quickly.

Suppose that we have a collection of signatures (made with `sourmash
compute` as above) and we want to search it with our newly assembled
genome (or the reads, even!). How would we do that?

Let's grab a sample collection of 50 E. coli genomes and unpack it --

```
mkdir ecoli_many_sigs
cd ecoli_many_sigs

curl -O -L https://github.com/dib-lab/sourmash/raw/master/data/eschericia-sigs.tar.gz

tar xzf eschericia-sigs.tar.gz
rm eschericia-sigs.tar.gz

cd ../

```

This will produce 50 files named `ecoli-N.sig` in the `ecoli_many_sigs` --

```
ls ecoli_many_sigs
```

Let's turn this into an easily-searchable database with `sourmash sbt_index` --

```
sourmash index -k 31 ecolidb ecoli_many_sigs/*.sig
```

and now we can search!

```
sourmash search ecoli-genome.sig ecolidb.sbt.json -n 20
```

You should see output like this:

```
# running sourmash subcommand: search
loaded query: /home/ubuntu/data/ecoliMG1655.... (k=31, DNA)
loaded SBT ecolidb.sbt.json
Searching SBT ecolidb.sbt.json
49 matches; showing first 20:
similarity   match
----------   -----
 88.4%       NZ_GG774190.1 Escherichia coli MS 196-1 Scfld2538, whole gen
 87.8%       NZ_JMGW01000001.1 Escherichia coli 1-176-05_S4_C2 e117605S4C
 86.6%       NZ_JMGU01000001.1 Escherichia coli 2-011-08_S3_C2 e201108S3C
 86.6%       NZ_JH659569.1 Escherichia coli M919 supercont2.1, whole geno
 81.3%       NZ_JHRU01000001.1 Escherichia coli strain 100854 100854_1, w
 78.9%       NZ_JHDG01000001.1 Escherichia coli 1-176-05_S3_C1 e117605S3C
 78.3%       NZ_MOJK01000001.1 Escherichia coli strain 469 Cleandata-BN4_
 78.1%       NZ_JNLZ01000001.1 Escherichia coli 3-105-05_S1_C1 e310505S1C
 78.1%       NZ_MOGK01000001.1 Escherichia coli strain 676 BN4_676_1_(pai
 78.1%       NZ_MIWF01000001.1 Escherichia coli strain AF7759-1 contig_00
 70.6%       NZ_KE700241.1 Escherichia coli HVH 147 (4-5893887) acYxy-sup
 69.2%       NZ_CP011331.1 Escherichia coli O104:H4 str. C227-11, complet
 69.0%       NZ_JHGJ01000001.1 Escherichia coli O45:H2 str. 2009C-4780 co
 69.0%       NZ_MIWP01000001.1 Escherichia coli strain K6412 contig_0001,
 68.6%       NZ_JHHE01000001.1 Escherichia coli O103:H2 str. 2009C-3279 c
 68.0%       NZ_LVOV01000001.1 Escherichia coli strain swine72 swine72_co
 67.5%       NZ_LQWB01000001.1 Escherichia coli strain GN03624 GCID_ECOLI
 67.1%       NZ_JHGS01000001.1 Escherichia coli O111:NM str. 2009C-4052 c
 67.1%       NZ_JHMG01000001.1 Escherichia coli O121:H19 str. 2010EL1058
 66.7%       NZ_AIGC01000068.1 Escherichia coli DEC7C gecDEC7C.contig.67_
```

## Compare many signatures and build a tree.

Adjust plotting (this is a bug in sourmash :) --
```
echo 'backend : Agg' > matplotlibrc
```

Compare all the things:

```
sourmash compare ecoli_many_sigs/* -o ecoli_cmp
```

and then plot:

```
sourmash plot --pdf --labels ecoli_cmp
```

which will produce a file `ecoli_cmp.matrix.pdf` and `ecoli_cmp.dendro.pdf`
which you can then download via your file browser and view on your local
computer.

Here's a PNG version:

![E. coli comparison plot](_static/ecoli_cmp.matrix.png)

## What's in my metagenome?

Download and unpack a newer version of the k=31 RefSeq index described
in
[CTB's blog post](http://ivory.idyll.org/blog/2016-sourmash-sbt-more.html)
-- this one contains sketches of all 100k Genbank microbes. (See
[available databases](databases.html) for more information.)

```
curl -O https://s3-us-west-1.amazonaws.com/spacegraphcats.ucdavis.edu/microbe-genbank-sbt-k31-2017.05.09.tar.gz
tar xzf microbe-genbank-sbt-k31-2017.05.09.tar.gz
```

This produces a file `genbank-k31.sbt.json` and a whole bunch of hidden
files in the directory `.sbt.genbank-k31`.

Next, run the 'gather' command to see what's in your ecoli genome --
```
sourmash gather -k 31 ecoli-genome.sig genbank-k31.sbt.json
```

and you should get:

```
# running sourmash subcommand: sbt_gather
loaded query: /home/ubuntu/data/ecoliMG1655.... (k=31, DNA)

overlap     p_query p_match 
---------   ------- --------
4.9 Mbp     100.0%   99.8%      CP011320.1 Escherichia coli strain SQ37,

found 1 matches total;
the recovered matches hit 100.0% of the query
```

In this case, the output is kind of boring because this is a single
genome.  But! You can use this on metagenomes (assembled and
unassembled) as well; you've just got to make the signature files.

To see this in action, here is gather running on a signature generated
from some sequences that assemble (but don't align to known genomes)
from the
[Shakya et al. 2013 mock metagenome paper](https://www.ncbi.nlm.nih.gov/pubmed/23387867).

```
wget https://github.com/dib-lab/sourmash/raw/master/doc/_static/shakya-unaligned-contigs.sig
sourmash gather -k 31 shakya-unaligned-contigs.sig genbank-k31.sbt.json
```

This should yield:
```
# running sourmash subcommand: gather
loaded query: mqc500.QC.AMBIGUOUS.99.unalign... (k=31, DNA)
loaded SBT genbank-k31.sbt.json

overlap     p_query p_match
---------   ------- --------
1.4 Mbp      11.0%   58.0%      JANA01000001.1 Fusobacterium sp. OBRC1 c
1.0 Mbp       7.7%   25.9%      CP001957.1 Haloferax volcanii DS2 plasmi
0.9 Mbp       7.5%   11.8%      BA000019.2 Nostoc sp. PCC 7120 DNA, comp
0.7 Mbp       5.9%   23.0%      FOVK01000036.1 Proteiniclasticum ruminis
0.7 Mbp       5.3%   17.6%      AE017285.1 Desulfovibrio vulgaris subsp.
0.6 Mbp       4.9%   11.1%      CP001252.1 Shewanella baltica OS223, com
0.6 Mbp       4.8%   27.3%      AP008226.1 Thermus thermophilus HB8 geno
0.6 Mbp       4.4%   11.2%      CP000031.2 Ruegeria pomeroyi DSS-3, comp
480.0 kbp     3.8%    7.6%      CP000875.1 Herpetosiphon aurantiacus DSM
410.0 kbp     3.3%   10.5%      CH959317.1 Sulfitobacter sp. NAS-14.1 sc
1.4 Mbp      10.9%   11.8%      LN831027.1 Fusobacterium nucleatum subsp
0.5 Mbp       4.1%    5.3%      CP000753.1 Shewanella baltica OS185, com
420.0 kbp     3.3%    7.7%      FNDZ01000023.1 Proteiniclasticum ruminis
150.0 kbp     1.2%    4.5%      CP015081.1 Deinococcus radiodurans R1 ch
150.0 kbp     1.2%    8.2%      CP000969.1 Thermotoga sp. RQ2, complete
290.0 kbp     2.3%    4.1%      CH959311.1 Sulfitobacter sp. EE-36 scf_1
1.2 Mbp       9.4%    5.0%      CP013328.1 Fusobacterium nucleatum subsp
110.0 kbp     0.9%    3.5%      FREL01000833.1 Enterococcus faecalis iso
0.6 Mbp       5.0%    2.8%      CP000527.1 Desulfovibrio vulgaris DP4, c
340.0 kbp     2.7%    3.3%      KQ235732.1 Fusobacterium nucleatum subsp
70.0 kbp      0.6%    1.2%      CP000850.1 Salinispora arenicola CNS-205
60.0 kbp      0.5%    0.7%      CP000270.1 Burkholderia xenovorans LB400
50.0 kbp      0.4%    2.6%      CP001080.1 Sulfurihydrogenibium sp. YO3A
50.0 kbp      0.4%    3.2%      L77117.1 Methanocaldococcus jannaschii D
found less than 40.0 kbp in common. => exiting

found 24 matches total;
the recovered matches hit 73.4% of the query

```

It is straightforward to build your own databases for use with `search`
and `gather`; ping us if you want us to write that up.

[Return to index](index.html)
