#!/usr/bin/env python3
"""Generate Android vectors/legacy PNGs from eclipse.svg (Linux librsvg + Cairo)."""
from pathlib import Path
import ctypes as c
import ctypes.util
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
SOURCE = ROOT / 'assets/branding/eclipse.svg'
A = 'http://schemas.android.com/apk/res/android'
AA = 'http://schemas.android.com/aapt'
S = 'http://www.w3.org/2000/svg'
ET.register_namespace('android', A)
ET.register_namespace('aapt', AA)

def attr(key):
    return f'{{{A}}}{key}'

def path_data(node):
    if node.tag == f'{{{S}}}path':
        return node.attrib['d']
    x, y, r = (float(node.attrib[k]) for k in ['cx', 'cy', 'r'])
    return f'M{x},{y-r} A{r},{r} 0,1 0,{x},{y+r} A{r},{r} 0,1 0,{x},{y-r} Z'

def vector():
    svg = ET.parse(SOURCE).getroot()
    gradients = {g.attrib['id']: g for g in svg.findall(f'{{{S}}}defs/*')}
    result = ET.Element('vector', {attr('width'): '108dp', attr('height'): '108dp', attr('viewportWidth'): '256', attr('viewportHeight'): '256'})
    # Equivalent to the previous 14dp inset in a 108dp adaptive foreground.
    group = ET.SubElement(result, 'group', {attr('pivotX'): '128', attr('pivotY'): '128', attr('scaleX'): '0.74074074', attr('scaleY'): '0.74074074'})
    for node in svg:
        if node.tag not in (f'{{{S}}}path', f'{{{S}}}circle'):
            continue
        path = ET.SubElement(group, 'path', {attr('pathData'): path_data(node)})
        for key, target in [('fill', 'fillColor'), ('stroke', 'strokeColor')]:
            value = node.attrib.get(key, 'none')
            if value == 'none':
                continue
            if not value.startswith('url('):
                path.set(attr(target), value)
                continue
            gradient = gradients[value[5:-1]]
            wrapper = ET.SubElement(path, f'{{{AA}}}attr', {'name': f'android:{target}'})
            native = ET.SubElement(wrapper, 'gradient', {attr('type'): 'linear', **{attr(b): gradient.attrib[a] for a,b in [('x1','startX'),('y1','startY'),('x2','endX'),('y2','endY')]}})
            for stop in gradient:
                ET.SubElement(native, 'item', {attr('offset'): stop.attrib['offset'], attr('color'): stop.attrib['stop-color']})
        for key, target in [('stroke-width', 'strokeWidth'), ('stroke-linecap', 'strokeLineCap')]:
            if key in node.attrib:
                path.set(attr(target), node.attrib[key])
    ET.indent(result)
    ET.ElementTree(result).write(RES / 'drawable/ic_launcher_foreground.xml', encoding='utf-8', xml_declaration=True)

def rasterize():
    rsvg = c.CDLL(ctypes.util.find_library('rsvg-2'))
    cairo = c.CDLL(ctypes.util.find_library('cairo'))
    objects = c.CDLL(ctypes.util.find_library('gobject-2.0'))
    rsvg.rsvg_handle_new_from_data.argtypes = [c.c_char_p,c.c_size_t,c.c_void_p]
    rsvg.rsvg_handle_new_from_data.restype = c.c_void_p
    rsvg.rsvg_handle_render_cairo.argtypes = [c.c_void_p,c.c_void_p]
    rsvg.rsvg_handle_render_cairo.restype = c.c_int
    cairo.cairo_image_surface_create.argtypes = [c.c_int,c.c_int,c.c_int]
    cairo.cairo_image_surface_create.restype = c.c_void_p
    cairo.cairo_create.argtypes = [c.c_void_p]
    cairo.cairo_create.restype = c.c_void_p
    cairo.cairo_scale.argtypes = [c.c_void_p,c.c_double,c.c_double]
    cairo.cairo_translate.argtypes = [c.c_void_p,c.c_double,c.c_double]
    cairo.cairo_set_source_rgb.argtypes = [c.c_void_p,c.c_double,c.c_double,c.c_double]
    cairo.cairo_paint.argtypes = [c.c_void_p]
    cairo.cairo_surface_write_to_png.argtypes = [c.c_void_p,c.c_char_p]
    cairo.cairo_surface_write_to_png.restype = c.c_int
    cairo.cairo_destroy.argtypes = [c.c_void_p]
    cairo.cairo_surface_destroy.argtypes = [c.c_void_p]
    objects.g_object_unref.argtypes = [c.c_void_p]
    data = SOURCE.read_bytes()
    handle = rsvg.rsvg_handle_new_from_data(data,len(data),None)
    if not handle:
        raise RuntimeError('Invalid source SVG')
    outputs = [(ROOT/'assets/branding/eclipse.png',512,False), (ROOT/'docs/ui-previews/launcher-safe-area.png',512,True)]
    outputs += [(RES/f'mipmap-{density}/ic_launcher.png',size,True) for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]]
    try:
        for path,size,inset in outputs:
            surface = cairo.cairo_image_surface_create(0,size,size)
            ctx = cairo.cairo_create(surface)
            try:
                cairo.cairo_set_source_rgb(ctx,146/255,149/255,155/255)
                cairo.cairo_paint(ctx)
                cairo.cairo_scale(ctx,size/512,size/512)
                if inset:
                    cairo.cairo_translate(ctx,512*14/108,512*14/108)
                    cairo.cairo_scale(ctx,80/108,80/108)
                if not rsvg.rsvg_handle_render_cairo(handle,ctx):
                    raise RuntimeError('SVG rendering failed')
                path.parent.mkdir(parents=True,exist_ok=True)
                if cairo.cairo_surface_write_to_png(surface,str(path).encode()) != 0:
                    raise RuntimeError(f'PNG write failed: {path}')
            finally:
                cairo.cairo_destroy(ctx)
                cairo.cairo_surface_destroy(surface)
    finally:
        objects.g_object_unref(handle)

if __name__ == '__main__':
    vector()
    rasterize()
    print('Generated native vector, preview, and five legacy launcher sizes.')
