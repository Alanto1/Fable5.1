# Auto-generated gauntlet opponent. Do not edit; regenerate with sim.gauntlet.
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location('gauntlet_champion', '/home/user/Fable5.1/kaggriculture/sim/opponents/champ_v6f.py')
_m = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_m)
_m.P.update({})


def agent(obs, config=None):
    return _m.agent(obs, config)
