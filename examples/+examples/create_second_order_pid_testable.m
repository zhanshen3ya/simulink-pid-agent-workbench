function create_second_order_pid_testable()
%CREATE_SECOND_ORDER_PID_TESTABLE Build a testable Simulink PID demo model.
%   Uses Inport/Outport instead of Step/To Workspace so that model_test
%   can drive inputs and capture outputs for Gherkin acceptance tests.

model = "pid_ai_second_order_test";

if bdIsLoaded(model)
    close_system(model, 0);
end

if exist(model + ".slx", "file")
    delete(model + ".slx");
end

new_system(model);

add_block("simulink/Sources/In1", model + "/r", ...
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

add_block("simulink/Sinks/Out1", model + "/y", ...
    "Position", [560 70 590 100]);

add_block("simulink/Sinks/Out1", model + "/u", ...
    "Position", [350 145 380 175]);

add_line(model, "r/1", "sum/1");
add_line(model, "sum/1", "PID Controller/1");
add_line(model, "PID Controller/1", "Plant/1");
add_line(model, "Plant/1", "y/1");
add_line(model, "Plant/1", "sum/2", "autorouting", "on");
add_line(model, "PID Controller/1", "u/1", "autorouting", "on");

set_param(model, "StopTime", "10");
set_param(model, "Solver", "ode45");
set_param(model, "FixedStep", "0");
set_param(model, "EnableRefsToGlobalWS", "on");

save_system(model);
fprintf("Created testable model: %s.slx\n", model);
end