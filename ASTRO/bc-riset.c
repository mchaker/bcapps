/* determines moon/sun rise/set/twilight times */

// the angular separation from zenith of a given body at a given time
// in a given place; because I plan to feed this routine to gfq, most
// "parameters" are global

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "SpiceUsr.h"
#include "SpiceZfc.h"
// this the wrong way to do things
#include "/home/user/BCGIT/ASTRO/bclib.h"

// Earth's equatorial and polar radii
#define EER 6378.137
#define EPR 6356.7523
#define MAXWIN 10000

// globals
SpiceDouble lat, lon, elev, utime, desired, pos[3], delta;
int target;

void show_results (char *prefix, SpiceCell result, 
                   void(* udfuns)(SpiceDouble et,SpiceDouble * value)) {

  SpiceInt nres = wncard_c(&result);
  SpiceDouble beg, end, vbeg, vend;

  for (int i=0; i<nres; i++) {
    wnfetd_c(&result,i,&beg,&end);
    udfuns(beg,&vbeg);
    udfuns(end,&vend);
    printf("%s %f %f %f %f\n",prefix,et2unix(beg),et2unix(end),vbeg,vend);
  }
}

void gfq (SpiceDouble et, SpiceDouble *value) {

  SpiceDouble v[3], lt;

  // target position (converting utc to et)
  spkezp_c(target,et,"ITRF93","CN+S",399,v,&lt);

  // target position compared to pos
  for (int i=0; i<=2; i++) {v[i] -= pos[i];}

  //  printf("@%f: %f %f %f\n",et2unix(et),v[0],v[1],v[2]);

  // and the angle (radians) (pi/2 minus because vsep is distance from zenith)
  *value = halfpi_c()-vsep_c(v,pos);
  printf("elev(%f) :%f\n",et2unix(et),*value*dpr_c());
}

void gfdecrx (void(* udfuns)(SpiceDouble et,SpiceDouble * value),
              SpiceDouble et, SpiceBoolean * isdecr ) {

  SpiceDouble v1=0, v2=0;
  udfuns(et-0.5,&v1);
  udfuns(et+0.5,&v2);
  // TODO: if v1 and v2 are identical, choose larger interval?
  if (v2<v1) {*isdecr=1;} else {*isdecr=0;}
}

int main(int argc, char **argv) {

  SPICEDOUBLE_CELL(cnfine,2);
  SPICEDOUBLE_CELL(result,2*MAXWIN);

  furnsh_c("/home/user/BCGIT/ASTRO/standard.tm");

  if (argc != 7) {
    // Units: degrees degrees meters seconds id-from-planet-ids.txt degrees
    printf("Usage: latitude longitude elevation unixtime target desired\n");
    exit(-1);
  }

  // assign from argv and convert degrees -> radians, meters -> km
  lat = atof(argv[1])*rpd_c();
  lon = atof(argv[2])*rpd_c();
  elev = atof(argv[3])/1000.;
  utime = atof(argv[4]);
  target = atoi(argv[5]);
  desired = atof(argv[6])*rpd_c();

  // compute position of lat,lon in IAU_EARTH frame (a rotating frame)
  georec_c (lon, lat, elev, EER, (EER-EPR)/EER, pos);
  //georec_c (lon, lat, elev, EER, 0, pos);

  printf("POS: %f %f %f\n",pos[0],pos[1],pos[2]);

  // create a window one day on either side of given time
  wninsd_c(unix2et(utime-86400),unix2et(utime+86400),&cnfine);

  // search for when object at desired altitude (astronomical)
  gfuds_c(gfq,gfdecrx,"=",desired,0,3600,MAXWIN,&cnfine,&result);

  printf("INPUT: %f %f %f %f %d\n",lat,lon,elev,utime,target);
  show_results("test",result,gfq);

  //  gfq(unix2et(utime),&ang);
  //printf("%f\n",r2d(ang));

  return 0;

}
