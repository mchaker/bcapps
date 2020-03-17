#!/bin/perl

# yet another attempt (still feel I'm not doing it "quite right")

# TODO: after fix numbered characters, see if there's only #1 of
# something and never #2

require "/usr/local/lib/bclib.pl";

chdir("/home/barrycarter/BCGIT/METAWIKI/");
my($pagedir) = "/usr/local/etc/metawiki/pbs3/";

# TODO: watch out for "double aliasing" (misc2.sql does NOT currently catch it)
# aliases

# not always necessary to run each of these every time
pbs_run_querys();
pbs_create_anno();
pbs_create_pages();

# runs the queries created by various other subroutines
sub pbs_run_querys {
  # remove the existing db
  system("rm /var/tmp/pbs3.db");
  open(A, "|sqlite3 /var/tmp/pbs3.db");
  for $i ("BEGIN",pbs_schema(),pbs_create_db(),pbs_largeimagelinks(),"COMMIT") {
    print A "$i;\n";
  }
  close(A);

  # Note: pbs_fix_numbered_queries() uses queries above, so must start new proc
  # and now done in a for loop (separately, since db closed after above)
  open(A, "|sqlite3 /var/tmp/pbs3.db");
  for $i ("BEGIN",pbs_fix_numbered_characters(),"COMMIT") {print A "$i;\n";}
  close(A);

  # cleanup
  system("sqlite3 /var/tmp/pbs3.db < misc2.sql");
}

# create pages
sub pbs_create_pages {

 # rsync from git
  system("rsync -Pavz /home/barrycarter/BCGIT/METAWIKI/*.mw $pagedir");

  # clean out NEW dir
  system("$pagedir/NEW/*.mw");

# now the query to create the pages (splitting on triple pipe avoids
# problems with {{wp|foo}})

my($query) = << "MARK";
SELECT source, GROUP_CONCAT(data,"|||") AS data FROM (
SELECT source, relation||'='||GROUP_CONCAT(target,", ") AS data FROM (
SELECT DISTINCT t1.source, t2.relation, t2.target
 FROM triples t1 JOIN triples t2 ON (t1.source=t2.source)
ORDER BY t1.source, t2.relation, t2.target
) GROUP BY source, relation ORDER BY source, relation
) GROUP BY source ORDER BY source
MARK
;

  for $i (sqlite3hashlist($query, "/var/tmp/pbs3.db")) {

    # fix commas
    $i->{source}=~s/&\#44\;/,/g;
    $i->{data}=~s/&\#44\;/,/g;

    # remove braces (cant have these in a title)
    $i->{source}=~s/\{\{.*?\|(.*?)\}\}/$1/g;
    $i->{source}=~s/[\[\[]//g;

    # this works because Perl can cast lists to hashes
    my(%hash) = split(/\|\|\||\=/, $i->{data});

    # multiple classes?
    if ($hash{class}=~/,/) {
      warn "$i->{source}: $hash{class} (multiple classes)";
      # storyline trumps others (but warn anyway, because of TODO)
      # TODO: need to do a lot more here, at least redirects
      if ($hash{class}=~/storyline/) {
	$hash{class} = "storyline";
      } else {
	warn "NORESOLVE: $i->{source}: $hash{class} (multiple classes)";
	next;
      }
    }

    debug("WRITING (page): $i->{source}");
    open(A, ">$pagedir/NEW/$i->{source}.mw");
    print A "{{$hash{class}\n|title=$i->{source}\n";
    # this seems ugly, since I have it in almost the form I need it
    for $j (sort keys %hash) {print A "|$j=$hash{$j}\n";}
    print A "}}\n";
    close(A);
  }
}

# create anno files for feh
sub pbs_create_anno {
  my($query) = << "MARK";
SELECT datasource, 
GROUP_CONCAT(source||"::"||relation||"::"||target,"\\n") AS data 
FROM triples WHERE relation NOT IN ('book', 'isbn')
AND datasource GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
GROUP BY datasource ORDER BY datasource;
MARK
;

  for $i (sqlite3hashlist($query, "/var/tmp/pbs3.db")) {
    debug("WRITING (anno): $i->{datasource}");
    # convert \n to actual new lines
    $i->{data}=~s/\\n/\n/g;
    write_file($i->{data}, "/mnt/extdrive/GOCOMICS/pearlsbeforeswine/ANNO/page-$i->{datasource}.gif.txt");
  }
}

# queries to provide largeimagelinks for each strip
sub pbs_largeimagelinks {
  my(@res);
  for $i (split(/\n/, read_file("largeimagelinks.txt"))) {
    $i=~s/^(.*?)\s+.*?\/([0-9a-f]+)\?.*$//;
    push(@res, "INSERT INTO triples (source, relation, target, datasource)
VALUES ('$1', 'hash', '$2', 'largeimagelinks.txt')");
  }
  return @res;
}

# fix numbered characters
sub pbs_fix_numbered_characters {
  my(@res);

  my($query) = << "MARK";
SELECT char, MIN(mindate) AS min FROM (
SELECT source AS char, REPLACE(MIN(datasource),'-','') AS mindate 
FROM triples WHERE source GLOB '* [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*'
GROUP BY source UNION
SELECT target AS char, REPLACE(MIN(datasource),'-','') AS mindate
FROM triples WHERE target GLOB '* [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*'
AND relation NOT IN ('notes', 'description', 'event') GROUP BY target
) GROUP BY char ORDER BY char;
MARK
;

  for $i (sqlite3hashlist($query, "/var/tmp/pbs3.db")) {
    $i->{char}=~/^(.*?)\s+(\d{8})\s*\((.*?)\)$/||warn("BAD CHAR: $i->{char}");
    my($base, $date, $species) = ($1, $2, $3);
    unless ($date == $i->{min}) {warn("$i->{char} NOMATCH: $date/$i->{min}");}
    my($newname) = "$base ($species) &#65283;".sprintf("%0.2d",++$times{$base}{$species});
#    debug("GAMMA: $i->{char} -> $newname");
    push(@res,"INSERT INTO triples (source, relation, target, datasource) VALUES ('$newname', 'reference_name', '$i->{char}', 'pbs_fix_numbered_characters')");
    for $j ("source", "target") {
      # below covers cases where char appears in notes/descriptions/etc
      push(@res,"UPDATE triples SET $j=REPLACE($j,'$i->{char}','$newname') WHERE $j LIKE '%$i->{char}%' AND relation NOT IN ('reference_name')");
    }
  }

  # check for useless renumberings
  for $i (keys %times) {
    if ($times{$base}==1) {
      warn("$base appears only once, no renumbering required");
    }
  }
  return @res;
}

# Querys to populate the database (but not create it)

sub pbs_create_db {
  my(@triples,@res,$multiref);

  my($all) = read_file("pbs.txt");
  $all=~m%<data>(.*?)</data>%s;
  for $i (split(/\n/, $1.read_file("pbs-cl.txt"))) {
    $i=~s/^(\S+)\s+//;
    my($dates) = $1;

    # distinguish multirefs and turn [[foo]] into [[dates::foo]]
    if ($dates eq "MULTIREF") {
      # TODO: these are both serious hacks
      $dates="MULTIREF".++$multiref;
      # bizarre format keeps dates hyperlinked
      $i=~s/\[\[(\d{4}\-\d{2}\-\d{2})\]\]/[[[[dates::$1]]]]/g;
#      debug("I: $i");
    }

    $i=~s/\'/&\#39\;/g;
    $i=~s/,/&\#44\;/g;
#    debug("ALPHA: $i");
    while ($i=~s/\[\[([^\[\]]*?)\]\]/\001/) {
#      debug("BETA: $i");
      my(@anno) = ($dates, split(/::/, $1));
#      debug("ANNO". join(", ",@anno));

      # this preserves [[double brackets]] in things like notes
      if (scalar @anno > 2) {
	push(@triples, [@anno]);
	$i=~s/\001/$anno[-1]/;
      } else {
	$i=~s/\001/\002$anno[-1]\003/;
      }
    }
  }

  for $i (@triples) {
    # cleanup the [[problem]]
#    debug("I23: $i->[2], $i->[3]");
    $i->[2]=~s/\002(.*?)\003/[[$1]]/g;
    if (scalar @$i == 4) {$i->[3]=~s/\002(.*?)\003/[[$1]]/g;}

    # len 3 -> date, rel, val, ignore; len 4 -> source, entity, rel, val
    for $j (parse_date_list($i->[0])) {
      for $k (split(/\+/, $i->[1])) {
	for $l (split(/\+/, $i->[2])) {
	  if (scalar(@$i) == 3) {
	    push(@res,"INSERT INTO triples VALUES ('$j', '$k', '$l', '$j')");
	  } elsif (scalar(@$i) == 4) {
	    for $m (split/\+/, $i->[3]) {
	      push(@res,"INSERT INTO triples VALUES ('$k', '$l', '$m', '$j')");
	    }
	  }
	}
      }
    }
  }
  return @res;
}

# literally just returns the schema
sub pbs_schema {
  return ("DROP TABLE IF EXISTS triples",
	  "CREATE TABLE triples (source, relation, target, datasource)",
	  "CREATE INDEX i1 ON triples(source)",
	  "CREATE INDEX i2 ON triples(relation)",
	  "CREATE INDEX i3 ON triples(target)",
	  "CREATE INDEX i4 ON triples(datasource)"
	  );
}
