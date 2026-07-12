function create_cascade_two_pid_demo()
%CREATE_CASCADE_TWO_PID_DEMO Build a simple inner/outer loop PID demo model.

model = "pid_ai_cascade_two_pid_demo";

if bdIsLoaded(model)
    close_system(model, 0);
end

new_system(model);

add_block("simulink/Sources/Step", model + "/r", ...
    "Time", "0", "Before", "0", "After", "1", ...
    "Position", [40 70 70 100]);

add_block("simulink/Math Operations/Sum", model + "/outer_sum", ...
    "Inputs", "+-", ...
    "Position", [120 66 145 104]);

add_block("simulink/Continuous/PID Controller", model + "/Outer PID", ...
    "P", "2", "I", "0.4", "D", "0.02", "N", "100", ...
    "Position", [185 60 285 110]);

add_block("simulink/Math Operations/Sum", model + "/inner_sum", ...
    "Inputs", "+-", ...
    "Position", [330 66 355 104]);

add_block("simulink/Continuous/PID Controller", model + "/Inner PID", ...
    "P", "3", "I", "0.6", "D", "0.01", "N", "100", ...
    "Position", [395 60 495 110]);

add_block("simulink/Continuous/Transfer Fcn", model + "/Velocity Plant", ...
    "Numerator", "[1]", "Denominator", "[0.2 1]", ...
    "Position", [545 65 650 105]);

add_block("simulink/Continuous/Integrator", model + "/Position Integrator", ...
    "InitialCondition", "0", ...
    "Position", [700 65 730 105]);

add_block("simulink/Sinks/To Workspace", model + "/to_r", ...
    "VariableName", "r", "SaveFormat", "Timeseries", ...
    "Position", [785 10 845 40]);

add_block("simulink/Sinks/To Workspace", model + "/to_y", ...
    "VariableName", "y", "SaveFormat", "Timeseries", ...
    "Position", [785 65 845 95]);

add_block("simulink/Sinks/To Workspace", model + "/to_u", ...
    "VariableName", "u", "SaveFormat", "Timeseries", ...
    "Position", [545 135 605 165]);

add_line(model, "r/1", "outer_sum/1");
add_line(model, "outer_sum/1", "Outer PID/1");
add_line(model, "Outer PID/1", "inner_sum/1");
add_line(model, "inner_sum/1", "Inner PID/1");
add_line(model, "Inner PID/1", "Velocity Plant/1");
add_line(model, "Velocity Plant/1", "Position Integrator/1");
add_line(model, "Position Integrator/1", "to_y/1");
add_line(model, "Position Integrator/1", "outer_sum/2", "autorouting", "on");
add_line(model, "Velocity Plant/1", "inner_sum/2", "autorouting", "on");
add_line(model, "r/1", "to_r/1", "autorouting", "on");
add_line(model, "Inner PID/1", "to_u/1", "autorouting", "on");

set_param(model, "StopTime", "8");
save_system(model);
fprintf("Created cascade two-PID demo model: %s.slx\n", model);
end

