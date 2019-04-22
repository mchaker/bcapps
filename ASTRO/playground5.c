#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "SpiceUsr.h"
#include "SpiceZfc.h"
#include "/home/user/BCGIT/ASTRO/bclib.h"

int main( int argc, char **argv ) {

  SPICEDOUBLE_CELL(result, 20000);
  SPICEDOUBLE_CELL(cnfine, 2);
  SpiceInt i, count, fid;
  SpiceChar name[255];
  SpiceBoolean found;
  SpiceDouble beg, end;

  furnsh_c("/home/user/BCGIT/ASTRO/standard.tm");

  cidfrm_c(542, 255, &fid, name, &found);

  printf("507 to %d %s\n",fid,name);

  exit(-1);

  // these ET limits for jupxxx.bsp should be consistent
  spkcov_c ("/home/user/SPICE/KERNELS/jup310.bsp", 502, &cnfine);

  // refine slightly to avoid corner case errors
  SPICE_CELL_SET_D(SPICE_CELL_ELEM_D(&cnfine,0)+86400, 0, &cnfine);
  SPICE_CELL_SET_D(SPICE_CELL_ELEM_D(&cnfine,1)-86400, 1, &cnfine);

  // testing only
  SPICE_CELL_SET_D(year2et(2010), 0, &cnfine);
  SPICE_CELL_SET_D(year2et(2020), 1, &cnfine);
  

  printf("%f\n", SPICE_CELL_ELEM_D(&cnfine,0));
  printf("%f\n", SPICE_CELL_ELEM_D(&cnfine,1));

  gfoclt_c("FULL", "EUROPA", "ELLIPSOID", "IAU_EUROPA", "SUN", "ELLIPSOID", 
	   "IAU_SUN", "CN", "IO", 360, &cnfine, &result);

  count = wncard_c(&result); 

  for (i=0; i<count; i++) {
    wnfetd_c(&result,i,&beg,&end);
    printf("min %f %f\n",et2jd(beg),et2jd(end));
  }

  return 0;
}
