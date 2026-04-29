from __future__ import annotations

from conftest import REPO_ROOT
from spruce_harness import HarnessRunner, load_profile, profile_names


def test_all_profiles_are_detected_by_helper_functions():
    for profile_name in profile_names():
        profile = load_profile(profile_name)
        runner = HarnessRunner(REPO_ROOT, profile)
        try:
            result = runner.source_helper_and_run(
                'printf "%s|%s|%s|%s|%s\\n" "$PLATFORM" "$DISPLAY_WIDTH" "$DISPLAY_HEIGHT" "$DISPLAY_ASPECT_RATIO" "$PLATFORM_ARCHITECTURE"'
            )
            assert result.returncode == 0, result.stderr
            detected = result.stdout.strip().split("|")
            assert detected == [
                profile.expected_platform,
                profile.expected_display["DISPLAY_WIDTH"],
                profile.expected_display["DISPLAY_HEIGHT"],
                profile.expected_display["DISPLAY_ASPECT_RATIO"],
                profile.expected_display["PLATFORM_ARCHITECTURE"],
            ]
        finally:
            runner.cleanup()
