function result = demo_buck_dual_loop_tuning()
%DEMO_BUCK_DUAL_LOOP_TUNING Jointly tune voltage and current PI controllers.

cfg = examples.buck_dual_loop_config();
result = main_pid_search(cfg);
end
