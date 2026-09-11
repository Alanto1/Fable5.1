"""Create an opponent/variant file with parameter overrides:
   python -m kaggriculture.tools.make_variant name '{"opening":"GOOSE:9"}' [source_main.py]"""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
name, overrides = sys.argv[1], sys.argv[2]
main_path = os.path.abspath(sys.argv[3]) if len(sys.argv) > 3 else os.path.join(ROOT, "kaggriculture", "main.py")
json.loads(overrides)  # validate
tpl = open(os.path.join(ROOT, "kaggriculture", "sim", "variant_template.py")).read()
out = os.path.join(ROOT, "kaggriculture", "sim", "opponents", name + ".py")
open(out, "w").write(tpl.replace("__OVERRIDES__", overrides).replace("__MAIN_PATH__", main_path))
print(out)
