"""Conservative external-power detection: unknown state never enables video."""
from pathlib import Path


def external_power(root=Path('/sys/class/power_supply')):
    try:
        supplies = list(root.iterdir())
    except OSError:
        return False
    for supply in supplies:
        try:
            kind = (supply/'type').read_text().strip()
            # USB-C/PD chargers use USB-prefixed types. Batteries and peripherals
            # with their own online status must not count as laptop adapters.
            if kind != 'Mains' and not kind.startswith('USB') and kind != 'Wireless':
                continue
            scope = supply/'scope'
            if scope.exists() and scope.read_text().strip() == 'Device':
                continue
            if (supply/'online').read_text().strip() == '1':
                return True
        except OSError:
            continue
    return False
