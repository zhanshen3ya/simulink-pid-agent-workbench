function create_pid_agent_library()
%CREATE_PID_AGENT_LIBRARY Build the Simulink Library Browser launcher.
rootDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
model = "pid_agent_lib";
outputPath = fullfile(rootDir, model + ".slx");
if bdIsLoaded(model)
    close_system(model, 0);
end
if isfile(outputPath)
    delete(outputPath);
end
new_system(model, "Library");
add_block("simulink/Ports & Subsystems/Subsystem", model + "/PID Agent Manager", ...
    "Position", [80, 70, 260, 150], ...
    "OpenFcn", "pid_project_manager.launchFromLibrary();", ...
    "AttributesFormatString", "Double-click to select and schedule PID controllers");
delete_line(model + "/PID Agent Manager", "In1/1", "Out1/1");
delete_block(model + "/PID Agent Manager/In1");
delete_block(model + "/PID Agent Manager/Out1");
mask = Simulink.Mask.create(model + "/PID Agent Manager");
mask.Type = "PID Agent Manager";
mask.Description = "Open the project-level PID selection and tuning plan manager.";
mask.Display = "disp('PID Agent Manager')";
set_param(model, "Creator", "Simulink PID Agent Workbench", ...
    "ModifiedByFormat", "Simulink PID Agent Workbench", "Lock", "on");
save_system(model, outputPath);
close_system(model, 0);
fprintf("Created PID Agent library: %s\n", outputPath);
end