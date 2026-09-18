# Auto-generated gauntlet opponent. Do not edit; regenerate with sim.gauntlet.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location('gauntlet_ladder_animal', '/home/user/Fable5.1/kaggriculture/sim/opponents/champ_v6f.py')
_m = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_m)
_m.P.update({'cow_k': 1.8, 'sheep_k': 3.0, 'max_cows': 16, 'max_sheep': 20, 'straw_mult': 1.0, 'melon_repeat': 0})


def agent(obs, config=None):
    return _m.agent(obs, config)
