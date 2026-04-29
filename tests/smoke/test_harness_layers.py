from __future__ import annotations

import pytest

from spruce_harness.device_surface import collect_surface_observations, surface_enabled


def test_device_surface_layer_is_explicitly_gated():
    if surface_enabled():
        observations = collect_surface_observations()
        assert "commands" in observations
        assert "files" in observations
    else:
        with pytest.raises(RuntimeError):
            collect_surface_observations()


@pytest.mark.device_surface
def test_device_surface_probe_collects_read_only_observations_when_enabled():
    if not surface_enabled():
        pytest.skip("set SPRUCE_HARNESS_ALLOW_DEVICE_SURFACE=1 to run actual device surface probes")
    observations = collect_surface_observations()
    assert "cpuinfo" in observations["commands"]
