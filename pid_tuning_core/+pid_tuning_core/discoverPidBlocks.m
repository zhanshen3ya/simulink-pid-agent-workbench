function pidBlocks = discoverPidBlocks(modelName)
%DISCOVERPIDBLOCKS Find PID Controller blocks in a Simulink model.

load_system(modelName);

pidBlocks = find_system(modelName, ...
    "LookUnderMasks", "all", ...
    "FollowLinks", "on", ...
    "BlockType", "PIDController");

pidBlocks = cellstr(pidBlocks);
end

