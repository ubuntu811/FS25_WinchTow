#!/usr/bin/env python3
"""The collision of a steel cable (FS25_WinchTow, scripts/WinchCable.lua): one 4 m long box, 5 cm square, twice in one i3d: cableRoot (a kinematic compound root) and cableChild (a compound child).
The script clones one root and as many children as the cable has metres, places them along the cable and adds the lot to physics as ONE body. Collision group STATIC_OBJECT (0x2), mask PLAYER only (0x100000):
it carries a person, it never touches the vehicles it is tied to.
  python3 tools/make_cable_segment.py      -> assets/cableSegment.i3d and .i3d.shapes   (the shapes writer is FS25_HorseDynamics/tools)"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(here, "..", "..", "FS25_HorseDynamics", "tools"))
import make_hitching_post as H
import make_horse_jumps as J
import shapes_io as S

HX, HY, HZ = 0.025, 0.025, 2.0
m = H.Mesh(); H.box(m, 0, 0, 0, HX, HY, HZ)
cp, cn, cu, ct, csub = H.merge([(m, 1)])
ent = H.shape_entity("cableBox", 1, cp, cn, cu, ct, csub, ["iron"], attachments=[(2, J.hull_block((0, 0, 0), (HX, HY, HZ)))])
hdr = type("Hd", (), {"version": 10, "seed": 91})()
sf = type("SF", (), {"header": hdr, "entities": [H.Raw(1, ent)]})()
out = os.path.join(here, "..", "assets")
os.makedirs(out, exist_ok=True)
S.write(os.path.join(out, "cableSegment.i3d.shapes"), sf)
attrs = 'collisionFilterGroup="0x2" collisionFilterMask="0x100000" castsShadows="false" receiveShadows="false" nonRenderable="true" materialIds="1" clipDistance="300"'
open(os.path.join(out, "cableSegment.i3d"), "w", encoding="iso-8859-1").write(f'''<?xml version="1.0" encoding="iso-8859-1"?>

<i3D name="cableSegment" version="1.6" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://i3d.giants.ch/schema/i3d-1.6.xsd">
  <Asset>
    <Export program="make_cable_segment.py" version="1"/>
  </Asset>
  <Files/>
  <Materials>
    <Material name="iron" materialId="1" diffuseColor="0.30 0.31 0.33 1" specularColor="0.45 0.45 0.45"/>
  </Materials>
  <Shapes externalShapesFile="cableSegment.i3d.shapes">
  </Shapes>
  <Scene>
    <TransformGroup name="cable" nodeId="1">
      <Shape name="cableRoot" shapeId="1" kinematic="true" compound="true" {attrs} nodeId="2"/>
      <Shape name="cableChild" shapeId="1" compoundChild="true" {attrs} nodeId="3"/>
    </TransformGroup>
  </Scene>

</i3D>
''')
print("wrote", out)
