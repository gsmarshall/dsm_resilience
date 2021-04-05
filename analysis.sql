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
/* our buildings layer has a huge number of features, so it could be useful to test our overlay on a subset of the features before we send it on
all million+ features */
CREATE TABLE buildings_sample AS
SELECT * FROM osm_buildings LIMIT 1000

CREATE TABLE impervious_sample
AS
SELECT st_multi(st_union(roads_clipped.geom01, buildings_sample.utmway))::geometry(multipolygon, 32737) as geom02
FROM roads_clipped, buildings_sample;

-- union impervious surfaces together
CREATE TABLE impervious_surfaces
AS
SELECT st_multi(st_union(roads_clipped.geom01, osm_buildings.utmway))::geometry(multipolygon, 32737) as geom02
FROM roads_clipped, osm_buildings

-- delete duplicate GEOMETRIES
CREATE TABLE lab_impervious_noDups
AS
SELECT (st_dump(geom)).geom::geometry(polygon, 4326)
FROM lab_impervious_surfaces;
