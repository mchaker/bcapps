-- goal for madis.db which may replace metarnew.db

-- most observations DO include relative humidity, but that's
-- redundant (can be calculated from temperature and dewpoint), so I
-- don't include it below

CREATE TABLE madis (
 type, -- type, as defined by MADIS
 id, -- id, as defined by MADIS
 name, -- descriptive name of station
 latitude DOUBLE, -- in decimal degrees -90..+90
 longitude DOUBLE, -- in decimal degrees -180..+180
 elevation DOUBLE, -- in feet above sealevel
 temperature DOUBLE, -- in degrees F
 dewpoint DOUBLE, -- in degrees F
 pressure DOUBLE, -- in inches of Hg (~30.00 is "normal")
 time, -- time of observation as "YYYY-MM-DD HH:MM:SS" UTC
 winddir DOUBLE, -- wind direction, in degrees, 0..360
 windspeed DOUBLE, -- in miles per hour
 gust DOUBLE, -- gust speed in miles per hour
 cloudcover TEXT,
 events TEXT,
 observation TEXT, -- the full text of the observation
 source TEXT, -- the data source
 timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 comments TEXT
);

CREATE VIEW madis_now AS
SELECT m.* FROM madis m JOIN (SELECT id, type, MAX(time) AS time FROM
madis WHERE type NOT IN ('MOS') GROUP BY id, type ORDER BY RANDOM())
AS t ON (m.id = t.id AND m.type = t.type AND m.time = t.time) WHERE
MIN(m.time,m.timestamp) > DATETIME(CURRENT_TIMESTAMP, '-3 hour');

-- for madis, only one report from a given station at a given time
CREATE UNIQUE INDEX i1 ON madis(type, id, time);

-- below is in stations.db, but also in madis for joins
CREATE TABLE stations ( 
 metar TEXT,
 wmobs INT, 
 city TEXT, 
 state TEXT, 
 country TEXT, 
 latitude DOUBLE, 
 longitude DOUBLE, 
 elevation DOUBLE,
 source TEXT 
);

CREATE INDEX i_metar ON stations(metar);

