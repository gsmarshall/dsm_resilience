/*
Hannah Rigdon and Sam Marshall
Open Source GIScience Lab 4 - Urban Resilience in Dar es Salaam

Task: calculate the percent area covered by impervious surfaces within flood prone and non flood prone areas of each ward
notes: impervious surfaces are considered to be all roads and buildings.
An area is considered flood-prone if it is covered by any part of the flood scenarios layer - i.e. has any probable flood depth

Make sure you create a spatial index for each new layer you create before running any new queries on it
*/

/* 4/5 notes:
LIST OF RELEVANT LAYERS:
raw: wards, flood, planet_osm_roads
derived: dsm_wards, dsm_wards_flood, osm_roads, roads_buffered, roads_clipped

*/
/* ------------ Cleaning/preparing data --------------------- */

-- dissolve flood geometries to make them simpler - we only care if an area has ANY flood Risk
CREATE TABLE floodsimple
AS
SELECT st_union(geom)::geometry(multipolygon,32737) as geom
FROM flood;

-- start out with a fresh copy of the wards layer to mess with
CREATE TABLE dsm_wards as select * from wards

-- reproject wards
SELECT addgeometrycolumn('sam','dsm_wards','utmgeom',32737,'MULTIPOLYGON',2);

UPDATE dsm_wards
SET utmgeom = ST_Transform(geom, 32737);

ALTER TABLE dsm_wards
DROP COLUMN geom;

-- calculate total area for each ward
ALTER TABLE dsm_wards
ADD COLUMN area_sqkm real;

UPDATE dsm_wards
SET area_sqkm = st_area(utmgeom) / (1000 * 1000);

-- intersect wards and flood areas
CREATE TABLE dsm_wards_flood as
SELECT dsm_wards.id, dsm_wards.ward_name, dsm_wards.district_n, dsm_wards.district_c, dsm_wards.area_sqkm, st_multi(st_intersection(dsm_wards.utmgeom, floodsimple.geom))::geometry(multipolygon,32737) as geom
FROM dsm_wards INNER JOIN floodsimple
ON st_intersects(dsm_wards.utmgeom, floodsimple.geom);


-- ==================== ROADS LAYER ======================
-- would be cool to do some of the following in one query - ask joe about this in class?
-- copy roads into your schema so you can change it
CREATE TABLE osm_roads AS
SELECT osm_id, way FROM
planet_osm_roads;

-- reproject roads
SELECT addgeometrycolumn('sam','osm_roads','utmway',32737,'LineString',2);

UPDATE osm_roads
SET utmway = ST_Transform(way, 32737);

ALTER TABLE osm_roads
DROP COLUMN way;

-- buffer the roads
CREATE TABLE roads_buffered AS
SELECT osm_id, st_buffer(utmway, 5)::geometry(polygon,32737) as geom
FROM osm_roads

ALTER TABLE lab_roads_buffered
DROP COLUMN geom;


-- clip the roads to the wards
CREATE TABLE roads_clipped
AS
SELECT roads_buffered.*, st_multi(st_intersection(roads_buffered.geom, dsm_wards.utmgeom))::geometry(multipolygon, 32737) as geom01
FROM roads_buffered INNER JOIN dsm_wards
ON st_intersects(roads_buffered.geom, dsm_wards.utmgeom);

--drop the old geometries
ALTER TABLE roads_clipped
DROP COLUMN geom;
-- weird thing: adding the whole roads_clipped layer to the map works fine, but selecting 1000 features and trying ot add those doesnt, it shows up without any geometry


-- ===================== BUILDINGS LAYER ============================
-- create buildings layer
CREATE TABLE osm_buildings AS
SELECT osm_id, way
FROM planet_osm_polygon
WHERE  building is not null;

-- reproject buildings
SELECT addgeometrycolumn('sam','osm_buildings','utmway',32737,'polygon',2);

UPDATE osm_buildings
SET utmway = ST_Transform(way, 32737);

ALTER TABLE osm_buildings
DROP COLUMN way;


-- ======================= COMBINING LAYERS ========================
/*
-- our buildings layer has a huge number of features, so it could be useful to test our overlay on a subset of the features before we send it on
-- all million+ features
CREATE TABLE buildings_sample AS
SELECT * FROM osm_buildings LIMIT 1000

-- the old union query - this runs prohibitively slowly because union is more or less a very complicated cross join
CREATE TABLE impervious_sample
AS
SELECT st_multi(st_union(roads_clipped.geom01, buildings_sample.utmway))::geometry(multipolygon, 32737) as geom02
FROM roads_clipped, buildings_sample;

-- Suggestion for a GIS UNION operation on two layers
-- from  https://gis.stackexchange.com/questions/302086/postgis-union-of-two-polygons-layers
-- very small example:
create table impervious_sample as
select distinct a.geom1 from
(select distinct(st_dump(st_collect(roads_sample.geom01,build_small_sample.utmway))).geom as geom1
 from roads_sample inner join build_small_sample on not st_intersects(roads_sample.geom01,build_small_sample.utmway)) a inner join
(select distinct (st_dump(st_collect(st_symdifference(roads_sample.geom01,build_small_sample.utmway), st_intersection(roads_sample.geom01,build_small_sample.utmway)))).geom
from roads_sample, build_small_sample where st_intersects(roads_sample.geom01, build_small_sample.utmway)) b
on not st_intersects(a.geom1,b.geom)
union
select (st_dump(st_collect(st_symdifference(roads_sample.geom01,build_small_sample.utmway), st_intersection(roads_sample.geom01,build_small_sample.utmway)))).geom
from roads_sample inner join build_small_sample on st_intersects(roads_sample.geom01, build_small_sample.utmway)

-- slightly bigger example
create table impervious_sample as
select distinct a.geom1 from
(select distinct(st_dump(st_collect(roads_clipped.geom01,buildings_sample.utmway))).geom as geom1
 from roads_clipped inner join buildings_sample on not st_intersects(roads_clipped.geom01,buildings_sample.utmway)) a inner join
(select distinct (st_dump(st_collect(st_symdifference(roads_clipped.geom01,buildings_sample.utmway), st_intersection(roads_clipped.geom01,buildings_sample.utmway)))).geom
from roads_clipped, buildings_sample where st_intersects(roads_clipped.geom01, buildings_sample.utmway)) b
on not st_intersects(a.geom1,b.geom)
union
select (st_dump(st_collect(st_symdifference(roads_clipped.geom01,buildings_sample.utmway), st_intersection(roads_clipped.geom01,buildings_sample.utmway)))).geom
from roads_clipped inner join buildings_sample on st_intersects(roads_clipped.geom01, buildings_sample.utmway)

-- as far as I can tell, this query produces exactly the same result as the above - meaning the middle bit (the 'b' section) is redundant, and might be slowing down the bigger union?
create table impervious_experiment as
select distinct a.geom1 from
(select distinct(st_dump(st_collect(roads_clipped.geom01,buildings_sample.utmway))).geom as geom1
 from roads_clipped inner join buildings_sample on not st_intersects(roads_clipped.geom01,buildings_sample.utmway)) a
union
select (st_dump(st_collect(st_symdifference(roads_clipped.geom01,buildings_sample.utmway), st_intersection(roads_clipped.geom01,buildings_sample.utmway)))).geom
from roads_clipped inner join buildings_sample on st_intersects(roads_clipped.geom01, buildings_sample.utmway)


-- the qgis union algorithm appears to just do an intersection, a - b, b - a, and then combine those - let's try making a query to do exactly that
create table qgis_union as
select distinct a.geom from
(select distinct st_intersection(roads_clipped.geom01, buildings_sample.utmway) as geom
from roads_clipped inner join buildings_sample on st_intersects(roads_clipped.geom01, buildings_sample.utmway)) a
union
select distinct b.geom1 from
(select st_difference(roads_clipped.geom01, buildings_sample.utmway) as geom1
from roads_clipped full join buildings_sample on ) b
union
select distinct c.geom2 from
(select st_difference(buildings_sample.utmway, roads_clipped.geom01) as geom2
from roads_clipped full join buildings_sample) c


-- union impervious surfaces together
-- on the full layers, this failed after a bit with the error message "no space left on device"
create table impervious_surfaces as
select distinct a.geom1 from
(select distinct(st_dump(st_collect(roads_clipped.geom01, osm_buildings.utmway))).geom as geom1
 from roads_clipped inner join osm_buildings on not st_intersects(roads_clipped.geom01, osm_buildings.utmway)) a inner join
(select distinct (st_dump(st_collect(st_symdifference(roads_clipped.geom01, osm_buildings.utmway), st_intersection(roads_clipped.geom01, osm_buildings.utmway)))).geom
from roads_clipped, osm_buildings where st_intersects(roads_clipped.geom01, osm_buildings.utmway)) b
on not st_intersects(a.geom1, b.geom)
union
select (st_dump(st_collect(st_symdifference(roads_clipped.geom01, osm_buildings.utmway), st_intersection(roads_clipped.geom01, osm_buildings.utmway)))).geom
from roads_clipped inner join osm_buildings on st_intersects(roads_clipped.geom01, osm_buildings.utmway)


-- this maybe worked, but the info tab says it doesn't have geometries?
create table union_experiment as
(select geom01 from roads_sample
union
select utmway from build_small_sample)

-- this worked, and got rid of extraneous lines within the roads without making everything one feature
create table union_experiment_dump as
select (st_dump(st_union(a.geom01))).geom::geometry(polygon,32737) as geom
from
(select geom01 from roads_sample
union
select utmway from build_small_sample) as a

-- the medium one - same as above, but with more features. ran in ~7.75 seconds
create table union_med as
select (st_dump(st_union(a.geom01))).geom::geometry(polygon,32737) as geom
from
(select geom01 from roads_clipped
union
select utmway from buildings_sample) as a

-- ok, this is the big one, hopefully it doesn't break
-- took too long, cancelled it
create table impervious_surfaces as
select (st_dump(st_union(a.geom01))).geom::geometry(polygon,32737) as geom
from
(select geom01 from roads_clipped
union
select utmway from osm_buildings) as a


-- delete duplicate geometries
CREATE TABLE lab_impervious_noDups
AS
SELECT (st_dump(geom)).geom::geometry(polygon, 4326)
FROM lab_impervious_surfaces;

*/

-- =================== CALCULATE IMPERVIOUS AREA ==================

-- calculate area for roads and buildings separately, then add
-- this will over count in areas where our road buffer overlaps with our buildings, but this is not likely to be significant, and we have undercounted
-- other impervious surfaces

-- calculate area
ALTER TABLE osm_buildings
ADD COLUMN area_sqkm real;

UPDATE osm_buildings
SET area_sqkm = st_area(utmway) / (1000 * 1000);

ALTER TABLE roads_clipped
ADD COLUMN area_sqkm real;

UPDATE roads_clipped
SET area_sqkm = st_area(geom01) / (1000 * 1000);


-- intersect with flooded areas of each ward
create table flood_buildings as
select dsm_wards_flood.id, osm_buildings.area_sqkm, st_intersection(osm_buildings.utmway, dsm_wards_flood.geom) as geom
from osm_buildings inner join dsm_wards_flood on st_intersects(osm_buildings.utmway, dsm_wards_flood.geom)

create table flood_roads as
  select dsm_wards_flood.id, st_intersection(dsm_wards_flood.geom, roads_clipped.geom01) as geom from
  dsm_wards_flood inner join roads_clipped on st_intersects(dsm_wards_flood.geom, roads_clipped.geom01)

-- fix geometries, because for some reason that intersection produced a mix of all sorts of geometries - polygons, but also multipolys, linestrings, multilinestrings, and even geometry collections
create table flood_rds as
select flood_roads.id, (st_dump(flood_roads.geom)).geom
from flood_roads
where geometrytype(geom) = 'MULTIPOLYGON' or geometrytype(geom) = 'POLYGON'

alter table flood_rds
add column area_sqkm real;

update flood_roads
set area_sqkm = st_area(geom) / (1000000)


-- join floodplain buildings to floodplains layer
create table flood_impervious as
select dsm_wards_flood.id, dsm_wards_flood.ward_name, dsm_wards_flood.area_sqkm as fp_area, flood_buildings.area_sqkm from
dsm_wards_flood left join flood_buildings on dsm_wards_flood.id = flood_buildings.id

-- group by ward to sum areas
create table flood_build_grp as
  select id, ward_name, fp_area, sum(area_sqkm) from
  flood_impervious group by id, ward_name, fp_area

-- now do the last two steps again for the roads
create table flood_imperv_rds as
select flood_build_grp.id, flood_build_grp.ward_name, flood_build_grp.fp_area, flood_build_grp.sum, flood_rds.area_sqkm from
flood_build_grp left join flood_rds on flood_build_grp.id = flood_rds.id

create table flood_imperv_grp as
select id, ward_name, fp_area, sum as build_area, sum(area_sqkm) as rds_area from
flood_imperv_rds group by id, ward_name, fp_area, sum


-- add impervious areas and Summarize
alter table flood_imperv_grp
add column imperv_area real,
add column pct_imperv real;

update flood_imperv_grp
set imperv_area = build_area + rds_area;

update flood_imperv_grp
set pct_imperv = (imperv_area / fp_area) * 100;

-- finally, join the results back to the floodplain layer so we can visualize them
create table flood_plains_impervious as
select dsm_wards_flood.ward_name, dsm_wards_flood.geom, flood_imperv_grp.fp_area, flood_imperv_grp.imperv_area, flood_imperv_grp.pct_imperv from
dsm_wards_flood left join flood_imperv_grp on dsm_wards_flood.id = flood_imperv_grp.id


-- compound:
create table wards_impervious as
  select dsm_wards.*, sum(a.area_sqkm) as build_area, sum(b.area_sqkm) as road_area, build_area + road_area as imperv_area from
  dsm_wards left join
  (select dsm_wards.id, osm_buildings.area_sqkm, st_intersection(osm_buildings.utmway, dsm_wards.utmgeom) as geom
  from osm_buildings left join dsm_wards on st_intersects(osm_buildings.utmway, dsm_wards.utmgeom)) as a on dsm_wards.id = a.id
  group by id
  left join
  (select dsm_wards.id, osm_buildings.area_sqkm, st_intersection(roads_clipped.geom01, dsm_wards.utmgeom) as geom
  from roads_clipped left join dsm_wards on st_intersects(roads_clipped.geom01, dsm_wards.utmgeom)) as b on dsm_wards.id = b.id
  group by id
