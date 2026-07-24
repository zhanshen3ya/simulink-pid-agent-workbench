function create_multi_system_pid_demo()
%CREATE_MULTI_SYSTEM_PID_DEMO Build a five-PID, three-system selection demo.
rootDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
model = "pid_ai_multi_system_demo";
outputPath = fullfile(rootDir, model + ".slx");
if bdIsLoaded(model)
    try
        set_param(model, "FastRestart", "off");
    catch
    end
    close_system(model, 0);
end
if isfile(outputPath)
    delete(outputPath);
end
new_system(model);
localAddCascade(model, "Buck_Voltage_Current", [30, 30, 440, 235], ...
    "A", [2, 0.5, 0.02], [4, 1.2, 0.01], [0.15, 1]);
localAddSingle(model, "Thermal_Control", [480, 30, 835, 235], ...
    "B", [3, 0.8, 0.01], [1, 1.5, 1]);
localAddCascade(model, "Motor_Speed_Current", [870, 30, 1280, 235], ...
    "C", [1.5, 0.4, 0.01], [5, 1.5, 0.02], [0.08, 1]);
set_param(model, "StopTime", "8", "Solver", "ode23t", ...
    "Creator", "Simulink PID Agent Workbench", ...
    "ModifiedByFormat", "Simulink PID Agent Workbench");
save_system(model, outputPath);
close_system(model, 0);
fprintf("Created multi-system PID demo: %s\n", outputPath);
end

function localAddCascade(model, name, position, prefix, outerPid, innerPid, plantDen)
path = model + "/" + name;
add_block("simulink/Ports & Subsystems/Subsystem", path, "Position", position);
delete_line(path, "In1/1", "Out1/1");
delete_block(path + "/In1");
delete_block(path + "/Out1");
add_block("simulink/Sources/Step", path + "/Reference", ...
    "Time", "0", "Before", "0", "After", "1", "Position", [25, 55, 55, 85]);
add_block("simulink/Math Operations/Sum", path + "/Outer Sum", ...
    "Inputs", "+-", "Position", [85, 51, 110, 89]);
add_block("simulink/Continuous/PID Controller", path + "/Outer PID", ...
    "P", num2str(outerPid(1)), "I", num2str(outerPid(2)), ...
    "D", num2str(outerPid(3)), "N", "100", "Position", [140, 45, 225, 95]);
add_block("simulink/Math Operations/Sum", path + "/Inner Sum", ...
    "Inputs", "+-", "Position", [255, 51, 280, 89]);
add_block("simulink/Continuous/PID Controller", path + "/Inner PID", ...
    "P", num2str(innerPid(1)), "I", num2str(innerPid(2)), ...
    "D", num2str(innerPid(3)), "N", "100", "Position", [310, 45, 395, 95]);
add_block("simulink/Continuous/Transfer Fcn", path + "/Electrical Plant", ...
    "Numerator", "[1]", "Denominator", mat2str(plantDen), ...
    "Position", [430, 50, 520, 90]);
add_block("simulink/Continuous/Integrator", path + "/Stored Energy", ...
    "Position", [555, 50, 585, 90]);
localAddLogs(path, prefix, [640, 20]);
add_line(path, "Reference/1", "Outer Sum/1");
add_line(path, "Outer Sum/1", "Outer PID/1");
add_line(path, "Outer PID/1", "Inner Sum/1");
add_line(path, "Inner Sum/1", "Inner PID/1");
add_line(path, "Inner PID/1", "Electrical Plant/1");
add_line(path, "Electrical Plant/1", "Stored Energy/1");
add_line(path, "Stored Energy/1", "Outer Sum/2", "autorouting", "on");
add_line(path, "Electrical Plant/1", "Inner Sum/2", "autorouting", "on");
add_line(path, "Reference/1", "Log Reference/1", "autorouting", "on");
add_line(path, "Stored Energy/1", "Log Output/1", "autorouting", "on");
add_line(path, "Inner PID/1", "Log Control/1", "autorouting", "on");
end

function localAddSingle(model, name, position, prefix, pid, plantDen)
path = model + "/" + name;
add_block("simulink/Ports & Subsystems/Subsystem", path, "Position", position);
delete_line(path, "In1/1", "Out1/1");
delete_block(path + "/In1");
delete_block(path + "/Out1");
add_block("simulink/Sources/Step", path + "/Reference", ...
    "Time", "0", "Before", "0", "After", "1", "Position", [25, 55, 55, 85]);
add_block("simulink/Math Operations/Sum", path + "/Control Sum", ...
    "Inputs", "+-", "Position", [95, 51, 120, 89]);
add_block("simulink/Continuous/PID Controller", path + "/Thermal PID", ...
    "P", num2str(pid(1)), "I", num2str(pid(2)), "D", num2str(pid(3)), ...
    "N", "100", "Position", [155, 45, 245, 95]);
add_block("simulink/Continuous/Transfer Fcn", path + "/Thermal Plant", ...
    "Numerator", "[1]", "Denominator", mat2str(plantDen), ...
    "Position", [295, 50, 390, 90]);
localAddLogs(path, prefix, [450, 20]);
add_line(path, "Reference/1", "Control Sum/1");
add_line(path, "Control Sum/1", "Thermal PID/1");
add_line(path, "Thermal PID/1", "Thermal Plant/1");
add_line(path, "Thermal Plant/1", "Control Sum/2", "autorouting", "on");
add_line(path, "Reference/1", "Log Reference/1", "autorouting", "on");
add_line(path, "Thermal Plant/1", "Log Output/1", "autorouting", "on");
add_line(path, "Thermal PID/1", "Log Control/1", "autorouting", "on");
end

function localAddLogs(path, prefix, origin)
variables = [prefix + "_r", prefix + "_y", prefix + "_u"];
names = ["Log Reference", "Log Output", "Log Control"];
for index = 1:3
    y = origin(2) + (index - 1) * 45;
    add_block("simulink/Sinks/To Workspace", path + "/" + names(index), ...
        "VariableName", variables(index), "SaveFormat", "Timeseries", ...
        "Position", [origin(1), y, origin(1) + 90, y + 30]);
end
end