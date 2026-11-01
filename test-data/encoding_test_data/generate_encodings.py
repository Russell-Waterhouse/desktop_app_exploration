#!/usr/bin/env python3
"""Generate the five encoding fixtures from one canonical recipe.

Run from anywhere:

    python3 generate_encodings.py

The script writes next to itself, overwriting:

    recipe-utf8.json          UTF-8, no BOM
    recipe-utf8-bom.json      UTF-8 with BOM
    recipe-utf16le-bom.json   UTF-16LE with BOM
    recipe-windows-1252.json  Windows-1252 (CP1252)
    recipe-latin-1.json       ISO-8859-1 (Latin-1)
"""

import json
from pathlib import Path

OUT = Path(__file__).resolve().parent

# Canonical text uses Windows-1252-only typography:
#   em dash U+2014 (cp1252 0x97), right single quote U+2019 (cp1252 0x92),
#   euro sign U+20AC (cp1252 0x80).
recipe = {
    "title": "Mushroom Risotto",
    "description": (
        "Creamy arborio rice with mushrooms, white wine, and parmesan — "
        "a classic Milanese-style dish."
    ),
    "servings": 4,
    "image_path": None,
    "notes": (
        "Stir often and add the stock a ladle at a time — the rice should "
        "stay loose, not stiff. Finish with a knob of butter and a spoonful "
        "of crème fraîche."
    ),
    "ingredients": [
        {"amount": "1", "unit": "lb", "name": "mushrooms, sliced"},
        {"amount": "1 1/2", "unit": "cups", "name": "arborio rice"},
        {"amount": "1", "unit": "", "name": "onion, finely chopped"},
        {"amount": "1/2", "unit": "cup", "name": "white wine"},
        {"amount": "6", "unit": "cups", "name": "vegetable stock, warm"},
        {"amount": "1/2", "unit": "cup", "name": "parmesan, grated (about €3 worth)"},
    ],
    "steps": [
        "Sauté the mushrooms in butter until browned; don’t crowd the pan, "
        "then set them aside.",
        "Cook the onion in butter until soft, then stir in the rice until "
        "it looks translucent at the edges.",
        "Pour in the wine and stir until it has mostly evaporated — about "
        "2 minutes.",
        "Add the warm stock a ladle at a time, stirring often and letting "
        "each addition absorb before adding the next, for about 20 minutes.",
        "Stir in the mushrooms and parmesan, season, and serve at once.",
    ],
}

# ISO-8859-1 cannot represent the cp1252-only characters, so the Latin-1
# fixture uses readable ASCII fallbacks in exactly those places. Everything
# else (including é, è, î) stays identical.
latin1_recipe = json.loads(json.dumps(recipe, ensure_ascii=False))
latin1_recipe["description"] = latin1_recipe["description"].replace(" — ", " - ")
latin1_recipe["notes"] = latin1_recipe["notes"].replace(" — ", " - ")
latin1_recipe["ingredients"][-1]["name"] = latin1_recipe["ingredients"][-1]["name"].replace(
    "€3", "EUR 3"
)
latin1_recipe["steps"][0] = latin1_recipe["steps"][0].replace("’", "'")
latin1_recipe["steps"][2] = latin1_recipe["steps"][2].replace(" — ", " - ")


def to_json(obj):
    # Same style as recipe-single.json: 2-space indent, literal non-ASCII,
    # single trailing newline.
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


canonical = to_json(recipe)
latin1 = to_json(latin1_recipe)

files = {
    "recipe-utf8.json": canonical.encode("utf-8"),
    "recipe-utf8-bom.json": b"\xef\xbb\xbf" + canonical.encode("utf-8"),
    "recipe-utf16le-bom.json": b"\xff\xfe" + canonical.encode("utf-16-le"),
    "recipe-windows-1252.json": canonical.encode("cp1252"),
    "recipe-latin-1.json": latin1.encode("latin-1"),
}

for name, data in files.items():
    (OUT / name).write_bytes(data)
    print(f"wrote {name} ({len(data)} bytes)")
