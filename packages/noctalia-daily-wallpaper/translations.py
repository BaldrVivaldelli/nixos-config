"""Extend the pinned plugin's English strings and provide a Spanish fallback."""
import json
from pathlib import Path

path = Path("translations/en.json")
english = json.loads(path.read_text())
english["panel"].update({
    "editorial_hint": "Official daily images. Your wallpaper changes only when you apply one.",
    "apply": "Apply wallpaper",
    "source": "View source",
})
path.write_text(json.dumps(english, ensure_ascii=False, indent=2) + "\n")
spanish = json.loads(json.dumps(english))
spanish["panel"].update({
    "title": "Fondos del día",
    "loading": "Cargando la imagen del día…",
    "error": "No se pudo cargar la imagen.",
    "editorial_hint": "Imágenes oficiales del día. Tu fondo cambia sólo cuando elegís aplicarlo.",
    "apply": "Aplicar fondo",
    "source": "Ver fuente",
})
spanish["notify"].update({"applied": "Fondo aplicado", "failed": "No se pudo cargar el fondo"})
Path("translations/es.json").write_text(json.dumps(spanish, ensure_ascii=False, indent=2) + "\n")
