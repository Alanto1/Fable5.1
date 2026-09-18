# Auto-generated variant of kaggriculture/main.py with parameter overrides.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("kagg_variant_mod", "/home/user/Fable5.1/kaggriculture/main.py")
_m = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_m)
_m.P.update({'endgame_crop': 'VALUE'})


def agent(obs, config=None):
    return _m.agent(obs, config)
