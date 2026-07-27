import unittest

from autopid.config.schema import AutoPidConfig
from autopid.discovery.model_scanner import analyze_scan
from autopid.runners.mock_runner import MockRunner


def discover(name):
    config = AutoPidConfig()
    config.model.file = "mock:" + name
    return analyze_scan(MockRunner().scan(config))


class DiscoveryTests(unittest.TestCase):
    def test_buck_roles_follow_negative_feedback_topology(self):
        result = discover("buck")
        self.assertEqual(len(result.controllers), 1)
        loop = result.loops[0]
        self.assertEqual(loop.signals.reference_signal, "sig_r")
        self.assertEqual(loop.signals.measurement_signal, "sig_y")
        self.assertEqual(loop.signals.error_signal, "sig_e")
        self.assertEqual(loop.signals.raw_control_signal, "sig_u_raw")
        self.assertEqual(loop.signals.actuator_signal, "sig_u")
        self.assertEqual(loop.confidence.decision, "suggested_confirmation")

    def test_same_name_decoy_is_not_selected(self):
        result = discover("wrong_signal")
        self.assertEqual(result.loops[0].signals.measurement_signal, "sig_y")
        self.assertNotEqual(result.loops[0].signals.measurement_signal, "sig_fake")

    def test_matlab_scalar_string_ports_are_normalized(self):
        config = AutoPidConfig()
        export = MockRunner().scan(config)
        export["controllers"][0]["input_ports"] = "pid:in:1"
        export["controllers"][0]["output_ports"] = "pid:out:1"
        for signal in export["signals"]:
            if len(signal["dst_ports"]) == 1:
                signal["dst_ports"] = signal["dst_ports"][0]
        loop = analyze_scan(export).loops[0]
        self.assertEqual(loop.signals.error_signal, "sig_e")
        self.assertEqual(loop.signals.actuator_signal, "sig_u")

    def test_complete_unnamed_topology_requires_confirmation_not_rejection(self):
        config = AutoPidConfig()
        export = MockRunner().scan(config)
        for signal in export["signals"]:
            signal["name"] = ""
            signal["unit"] = ""
            signal["sample_time"] = ""
        loop = analyze_scan(export).loops[0]
        self.assertEqual(loop.confidence.decision, "suggested_confirmation")
        self.assertFalse(loop.confidence.dynamic_probe_performed)

    def test_cascade_recommends_inner_before_outer(self):
        result = discover("cascade")
        loops = {item.loop_level: item for item in result.loops}
        self.assertEqual(loops["inner"].recommended_tuning_order, 1)
        self.assertEqual(loops["outer"].recommended_tuning_order, 2)
        self.assertEqual(loops["outer"].child_loop, loops["inner"].controller.path)


if __name__ == "__main__":
    unittest.main()
