# Auto-generated gauntlet opponent. Do not edit; regenerate with sim.gauntlet.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location('gauntlet_ladder_melon', '/home/user/Fable5.1/kaggriculture/sim/opponents/champ_v6f.py')
_m = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_m)
_m.P.update({'melon_tiles': 16, 'melon_repeat': 14, 'melon_last_day': 16, 'melon_guard': 45, 'straw_mult': 1.2})


def agent(obs, config=None):
    return _m.agent(obs, config)
