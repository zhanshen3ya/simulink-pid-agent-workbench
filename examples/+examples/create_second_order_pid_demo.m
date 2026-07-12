function create_second_order_pid_demo()
%CREATE_SECOND_ORDER_PID_DEMO Build a simple Simulink PID tuning demo model.

model = "pid_ai_second_order_demo";

if bdIsLoaded(model)
    close_system(model, 0);
end

new_system(model);

add_block("simulink/Sources/Step", model + "/r", ...
    "Time", "0", "Before", "0", "After", "1", ...
    "Position", [60 80 90 110]);

add_block("simulink/Math Operations/Sum", model + "/sum", ...
    "Inputs", "+-", ...
    "Position", [140 76 165 114]);

add_block("simulink/Continuous/PID Controller", model + "/PID Controller", ...
    "P", "1", "I", "0.2", "D", "0.01", "N", "100", ...
    "Position", [210 70 310 120]);

add_block("simulink/Continuous/Transfer Fcn", model + "/Plant", ...
    "Numerator", "[1]", "Denominator", "[1 1.2 1]", ...
    "Position", [370 75 470 115]);

add_block("simulink/Sinks/To Workspace", model + "/to_y", ...
    "VariableName", "y", "SaveFormat", "Timeseries", ...
    "Position", [560 70 620 100]);

add_block("simulink/Sinks/To Workspace", model + "/to_r", ...
    "VariableName", "r", "SaveFormat", "Timeseries", ...
    "Position", [560 15 620 45]);

add_block("simulink/Sinks/To Workspace", model + "/to_u", ...
    "VariableName", "u", "SaveFormat", "Timeseries", ...
    "Position", [350 145 410 175]);

add_line(model, "r/1", "sum/1");
add_line(model, "sum/1", "PID Controller/1");
add_line(model, "PID Controller/1", "Plant/1");
add_line(model, "Plant/1", "to_y/1");
add_line(model, "Plant/1", "sum/2", "autorouting", "on");
add_line(model, "r/1", "to_r/1", "autorouting", "on");
add_line(model, "PID Controller/1", "to_u/1", "autorouting", "on");

set_param(model, "StopTime", "10");
save_system(model);
fprintf("Created demo model: %s.slx\n", model);
end
